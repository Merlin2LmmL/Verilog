#!/usr/bin/env python3
"""Translate RV32E assembly (clang -S output) into assembly for this CPU.

    python3 tools/rv2cpu.py [-o out.asm] [--stack ADDR] file.s [file.s ...]

All files are translated together into one program: the code goes to .text, and every
constant, variable and zero-filled array (.rodata, .data, .bss) goes to .data, in that
order, starting at RAM address 0.

Register mapping (every register is used the same way everywhere, so the calling
convention of the compiler keeps working):

    zero r0 | a0-a3 r1-r4 | a4 a5 r5 r6 | t0 t1 t2 r7-r9 | s0 s1 r10 r11 | sp r14 | ra r15
    r12 and r13 (gp, tp) are free in RV32E code, so they are the translator's scratch registers.

What is not a one-to-one rename:
    * %hi/%lo address pairs: `lui` becomes `la` (the whole address), the %lo part becomes 0
    * big immediates for and/or/xor (this CPU zero-extends them): loaded into a scratch register
    * lui with a number: `li` with the shifted value
    * .half/.short data, strings and zero fills become .byte / .space
    * labels are renamed so that they are valid names here
"""
import argparse
import re
import sys

REG = {'zero': 0, 'a0': 1, 'a1': 2, 'a2': 3, 'a3': 4, 'a4': 5, 'a5': 6, 't0': 7, 't1': 8,
       't2': 9, 's0': 10, 'fp': 10, 's1': 11, 'gp': 12, 'tp': 13, 'sp': 14, 'ra': 15}
for _n, _abi in enumerate(['zero', 'ra', 'sp', 'gp', 'tp', 't0', 't1', 't2', 's0', 's1',
                           'a0', 'a1', 'a2', 'a3', 'a4', 'a5']):
    REG['x%d' % _n] = REG[_abi]
SCRATCH = 'r13'

THREE = {'add': 'add', 'sub': 'sub', 'and': 'and', 'or': 'or', 'xor': 'xor', 'sll': 'shl',
         'srl': 'shr', 'sra': 'sra', 'slt': 'slt', 'sltu': 'sltu', 'mul': 'mul', 'mulh': 'mulh',
         'mulhu': 'mulhu', 'div': 'div', 'divu': 'divu', 'rem': 'mod', 'remu': 'modu'}
IMM = {'addi': 'addi', 'slti': 'slti', 'sltiu': 'sltiu', 'slli': 'shli', 'srli': 'shri',
       'srai': 'srai'}
LOGIC_IMM = {'andi': ('and', 'andi'), 'ori': ('or', 'ori'), 'xori': ('xor', 'xori')}
LOAD = {'lw': 'ld', 'lb': 'ldb', 'lbu': 'ldbu', 'lh': 'ldh', 'lhu': 'ldhu'}
STORE = {'sw': 'st', 'sb': 'stb', 'sh': 'sth'}
BRANCH = {'beq': 'beq', 'bne': 'bne', 'blt': 'blt', 'bge': 'bge', 'bltu': 'bltu',
          'bgeu': 'bgeu', 'bgt': 'bgt', 'ble': 'ble', 'bgtu': 'bgtu', 'bleu': 'bleu'}
BRANCH_ZERO = {'beqz': 'beq', 'bnez': 'bne', 'blez': 'ble', 'bgtz': 'bgt', 'bltz': 'blt',
               'bgez': 'bge'}
IGNORED = ('.file', '.attribute', '.ident', '.addrsig', '.addrsig_sym', '.size', '.type',
           '.globl', '.global', '.local', '.weak', '.option', '.cfi_', '.p2align_text')


class Error(Exception):
    pass


def reg(name):
    key = name.strip()
    if key not in REG:
        raise Error("unknown register '%s'" % name)
    return 'r%d' % REG[key]


FILE_NO = [0]      # local labels (.L...) only exist inside one file, so they get its number


def rename(label):
    label = label.strip()
    if label.startswith('.'):
        label = 'L%d_' % FILE_NO[0] + label[1:]
    else:
        label = '_' + label
    return re.sub(r'[.$]', '_', label)


def rename_expr(expr):
    """Rename every symbol in an expression like .LJTI0_0+4, keep the numbers."""
    return re.sub(r'(?<![\w.$])[.A-Za-z_][\w.$]*', lambda m: rename(m.group(0)), expr)


def split_operands(text):
    parts, depth, cur, quoted, skip = [], 0, '', False, False
    for ch in text:
        if quoted:
            cur += ch
            if skip:
                skip = False
            elif ch == '\\':
                skip = True
            elif ch == '"':
                quoted = False
            continue
        if ch == '"':
            quoted = True
            cur += ch
            continue
        if ch == '(':
            depth += 1
        elif ch == ')':
            depth -= 1
        if ch == ',' and depth == 0:
            parts.append(cur.strip())
            cur = ''
        else:
            cur += ch
    if cur.strip():
        parts.append(cur.strip())
    return parts


def number(text):
    try:
        return int(text.strip(), 0)
    except ValueError:
        return None


def split_sym(expr):
    """'sym+4' -> ('sym', 4); 'sym' -> ('sym', 0)."""
    m = re.match(r'^([.A-Za-z_][\w.$]*)\s*(?:([+-])\s*(\w+))?$', expr.strip())
    if not m:
        raise Error("cannot understand the address '%s'" % expr)
    add = int(m.group(3), 0) if m.group(3) else 0
    return m.group(1), -add if m.group(2) == '-' else add


def parse_string(text):
    text = text.strip()
    if not (text.startswith('"') and text.endswith('"')):
        raise Error('bad string %s' % text)
    body, out, i = text[1:-1], [], 0
    esc = {'n': 10, 't': 9, 'r': 13, '0': 0, '\\': 92, '"': 34, "'": 39, 'a': 7, 'b': 8,
           'f': 12, 'v': 11}
    while i < len(body):
        ch = body[i]
        if ch != '\\':
            out.append(ord(ch))
            i += 1
            continue
        i += 1
        if body[i] in '01234567':
            j = i
            while j < len(body) and j < i + 3 and body[j] in '01234567':
                j += 1
            out.append(int(body[i:j], 8) & 255)
            i = j
        elif body[i] == 'x':
            j = i + 1
            while j < len(body) and body[j] in '0123456789abcdefABCDEF':
                j += 1
            out.append(int(body[i + 1:j], 16) & 255)
            i = j
        else:
            out.append(esc[body[i]])
            i += 1
    return out


class Translator:
    def __init__(self):
        self.text = []
        self.data = {'rodata': [], 'data': [], 'bss': []}
        self.section = 'text'
        self.hi = {}            # register name -> (symbol, addend) of its last %hi
        self.file = ''
        self.line = 0
        self.counts = {'text': 0}
        self.aliases = []       # `name = expr` lines (merged globals), put after the data

    def emit(self, line):
        if self.section == 'text':
            self.text.append(line)
        else:
            self.data[self.section].append(line)

    def ins(self, line):
        self.text.append('        ' + line)
        self.counts['text'] += 1

    def where(self):
        return '%s:%d' % (self.file, self.line)

    # ---- sections and data -------------------------------------------------
    def set_section(self, name):
        name = name.strip().strip('"')
        if name.startswith('.text'):
            self.section = 'text'
        elif name.startswith(('.rodata', '.srodata', '.data.rel.ro')):
            self.section = 'rodata'
        elif name.startswith(('.data', '.sdata')):
            self.section = 'data'
        elif name.startswith(('.bss', '.sbss', '.tbss')):
            self.section = 'bss'
        elif name.startswith(('.note', '.comment', '.riscv', '.llvm_addrsig')):
            self.section = 'ignore'
            self.data.setdefault('ignore', [])
        else:
            raise Error("unknown section '%s'" % name)

    def directive(self, name, rest):
        ops = split_operands(rest)
        if name == '.text':
            self.section = 'text'
        elif name == '.data':
            self.section = 'data'
        elif name == '.bss':
            self.section = 'bss'
        elif name == '.section':
            self.set_section(ops[0])
        elif self.section == 'ignore':
            return
        elif name in ('.p2align', '.balign', '.align'):
            if self.section != 'text':
                n = int(ops[0], 0)
                size = 1 << n if name != '.balign' else n
                if size > 1:
                    self.emit('        .align %d' % size)
        elif name in ('.word', '.4byte', '.long'):
            self.emit('        .word ' + ', '.join(rename_expr(o) for o in ops))
        elif name in ('.half', '.short', '.2byte', '.hword'):
            values = []
            for o in ops:
                v = number(o)
                if v is None:
                    raise Error('%s: .half needs numbers' % self.where())
                values += [v & 255, (v >> 8) & 255]
            self.emit('        .byte ' + ', '.join(map(str, values)))
        elif name == '.byte':
            self.emit('        .byte ' + ', '.join(ops))
        elif name in ('.quad', '.8byte', '.dword'):
            values = []
            for o in ops:
                v = number(o)
                if v is None:
                    raise Error('%s: .quad needs numbers' % self.where())
                values += [v & 0xFFFFFFFF, (v >> 32) & 0xFFFFFFFF]
            self.emit('        .word ' + ', '.join(map(str, values)))
        elif name in ('.zero', '.skip', '.space'):
            count = int(ops[0], 0)
            fill = int(ops[1], 0) & 255 if len(ops) > 1 else 0
            if fill:                    # .zero 64,119: the value is repeated
                for i in range(0, count, 16):
                    self.emit('        .byte ' + ', '.join([str(fill)] * min(16, count - i)))
            elif count:
                self.emit('        .space %d' % count)
        elif name in ('.asciz', '.string', '.ascii'):
            values = []
            for o in ops:
                values += parse_string(o) + ([0] if name != '.ascii' else [])
            for i in range(0, len(values), 16):
                self.emit('        .byte ' + ', '.join(map(str, values[i:i + 16])))
        elif name in ('.comm', '.lcomm'):
            size = int(ops[1], 0)
            align = int(ops[2], 0) if len(ops) > 2 else 4
            self.data['bss'].append('        .align %d' % max(align, 1))
            self.data['bss'].append('%s:' % rename(ops[0]))
            self.data['bss'].append('        .space %d' % size)
        elif name.startswith(IGNORED):
            pass
        else:
            raise Error("%s: unknown directive %s" % (self.where(), name))

    # ---- instructions --------------------------------------------------------
    def mem(self, text):
        """'12(a0)' or '%lo(sym)(a0)' -> (base register name, offset text)."""
        m = re.match(r'^(.*)\(([\w]+)\)$', text.strip())
        if not m:
            raise Error('%s: bad memory operand %s' % (self.where(), text))
        off, base = m.group(1).strip() or '0', m.group(2)
        lo = re.match(r'^%lo\((.*)\)$', off)
        if lo:
            off = str(self.lo_offset(base, lo.group(1)))
        return base, off

    def lo_offset(self, base, expr):
        """The %lo part: the base register already holds the whole address from `la`."""
        sym, add = split_sym(expr)
        if base not in self.hi:
            raise Error('%s: %%lo(%s) without a %%hi in %s' % (self.where(), expr, base))
        hsym, hadd = self.hi[base]
        if hsym != sym:
            raise Error('%s: %%lo(%s) after %%hi(%s)' % (self.where(), expr, hsym))
        return add - hadd

    def address(self, off, base):
        off = rename_expr(off) if not number(off) and number(off) != 0 else off
        n = number(off)
        if n is not None:
            return '[%s%+d]' % (reg(base), n) if n else '[%s]' % reg(base)
        return '[%s+%s]' % (reg(base), off)

    def instruction(self, op, rest):
        ops = split_operands(rest)
        n = len(ops)
        if op in THREE:
            self.ins('%s %s, %s, %s' % (THREE[op], reg(ops[0]), reg(ops[1]), reg(ops[2])))
        elif op in IMM:
            if op == 'addi' and ops[2].startswith('%lo('):
                off = self.lo_offset(ops[1], ops[2][4:-1])
                if off or reg(ops[0]) != reg(ops[1]):
                    self.ins('addi %s, %s, %d' % (reg(ops[0]), reg(ops[1]), off))
                return
            self.ins('%s %s, %s, %s' % (IMM[op], reg(ops[0]), reg(ops[1]), ops[2]))
        elif op in LOGIC_IMM:
            v = number(ops[2])
            if v is None:
                raise Error('%s: %s needs a number' % (self.where(), op))
            if op == 'xori' and v == -1:
                self.ins('not %s, %s' % (reg(ops[0]), reg(ops[1])))
            elif 0 <= v <= 0xFFFF:
                self.ins('%s %s, %s, %d' % (LOGIC_IMM[op][1], reg(ops[0]), reg(ops[1]), v))
            else:
                self.ins('li %s, %d' % (SCRATCH, v))
                self.ins('%s %s, %s, %s' % (LOGIC_IMM[op][0], reg(ops[0]), reg(ops[1]), SCRATCH))
        elif op in LOAD:
            base, off = self.mem(ops[1])
            self.ins('%s %s, %s' % (LOAD[op], reg(ops[0]), self.address(off, base)))
        elif op in STORE:
            base, off = self.mem(ops[1])
            self.ins('%s %s, %s' % (STORE[op], reg(ops[0]), self.address(off, base)))
        elif op in BRANCH:
            self.ins('%s %s, %s, %s' % (BRANCH[op], reg(ops[0]), reg(ops[1]), rename(ops[2])))
        elif op in BRANCH_ZERO:
            self.ins('%s %s, r0, %s' % (BRANCH_ZERO[op], reg(ops[0]), rename(ops[1])))
        elif op == 'lui':
            m = re.match(r'^%hi\((.*)\)$', ops[1])
            if m:
                sym, add = split_sym(m.group(1))
                self.hi[ops[0].strip()] = (sym, add)
                self.ins('la %s, %s' % (reg(ops[0]), rename_expr(m.group(1))))
            else:
                self.ins('li %s, %d' % (reg(ops[0]), (int(ops[1], 0) << 12) & 0xFFFFFFFF))
        elif op == 'li':
            self.ins('li %s, %s' % (reg(ops[0]), ops[1]))
        elif op == 'la' or op == 'lla':
            self.ins('la %s, %s' % (reg(ops[0]), rename_expr(ops[1])))
        elif op == 'mv':
            self.ins('mov %s, %s' % (reg(ops[0]), reg(ops[1])))
        elif op == 'not':
            self.ins('not %s, %s' % (reg(ops[0]), reg(ops[1])))
        elif op == 'neg':
            self.ins('neg %s, %s' % (reg(ops[0]), reg(ops[1])))
        elif op == 'seqz':
            self.ins('sltiu %s, %s, 1' % (reg(ops[0]), reg(ops[1])))
        elif op == 'snez':
            self.ins('sltu %s, r0, %s' % (reg(ops[0]), reg(ops[1])))
        elif op == 'sltz':
            self.ins('slt %s, %s, r0' % (reg(ops[0]), reg(ops[1])))
        elif op == 'sgtz':
            self.ins('slt %s, r0, %s' % (reg(ops[0]), reg(ops[1])))
        elif op in ('zext.b', 'zext.h'):
            self.ins('andi %s, %s, %d' % (reg(ops[0]), reg(ops[1]), 255 if op == 'zext.b' else 65535))
        elif op in ('sext.b', 'sext.h'):
            sh = 24 if op == 'sext.b' else 16
            self.ins('shli %s, %s, %d' % (reg(ops[0]), reg(ops[1]), sh))
            self.ins('srai %s, %s, %d' % (reg(ops[0]), reg(ops[0]), sh))
        elif op == 'nop':
            self.ins('nop')
        elif op == 'ret':
            self.ins('ret')
        elif op == 'j':
            self.ins('j %s' % rename(ops[0]))
        elif op == 'tail':
            self.ins('j %s' % rename(ops[0]))
        elif op == 'call':
            self.ins('call %s' % rename(ops[0]))
        elif op == 'jal':
            if n == 1:
                self.ins('call %s' % rename(ops[0]))
            else:
                self.ins('jal %s, %s' % (reg(ops[0]), rename(ops[1])))
        elif op == 'jr':
            self.ins('jr %s' % reg(ops[0]))
        elif op == 'jalr':
            if n == 1:
                self.ins('jalr r15, %s, 0' % reg(ops[0]))
            elif n == 2:
                base, off = self.mem(ops[1]) if '(' in ops[1] else (ops[1], '0')
                self.ins('jalr %s, %s, %s' % (reg(ops[0]), reg(base), off))
            else:
                self.ins('jalr %s, %s, %s' % (reg(ops[0]), reg(ops[1]), ops[2]))
        else:
            raise Error("%s: cannot translate '%s %s'" % (self.where(), op, rest))

    # ---- the whole file ------------------------------------------------------
    def translate(self, path):
        self.file = path
        FILE_NO[0] += 1
        self.section = 'text'
        self.hi = {}
        with open(path) as f:
            lines = f.read().split('\n')
        for self.line, raw in enumerate(lines, 1):
            line = re.sub(r'(^|\s)#.*$', '', raw).strip()
            while True:
                m = re.match(r'^([.A-Za-z_$][\w.$]*)\s*:', line)
                if not m:
                    break
                if self.section != 'ignore':
                    self.emit('%s:' % rename(m.group(1)))
                line = line[m.end():].strip()
            if not line:
                continue
            alias = re.match(r'^([.A-Za-z_$][\w.$]*)\s*=\s*(.+)$', line)
            if alias:
                self.aliases.append('        .equ %s, %s' % (rename(alias.group(1)),
                                                         rename_expr(alias.group(2))))
                continue
            parts = line.split(None, 1)
            word, rest = parts[0], parts[1] if len(parts) > 1 else ''
            try:
                if word.startswith('.'):
                    self.directive(word, rest)
                elif self.section == 'text':
                    self.instruction(word.lower(), rest)
                elif self.section != 'ignore':
                    raise Error('%s: instruction %s outside the code' % (self.where(), word))
            except (Error, IndexError, KeyError, ValueError) as e:
                raise Error(str(e) if isinstance(e, Error) else '%s: %s: %r' % (self.where(), line, e))

    def output(self, stack):
        out = ['; Translated from RV32E assembly by tools/rv2cpu.py (see platformer/DESIGN.md).',
               '; Code first, then the data: constants, variables and the zero-filled arrays,',
               '; starting at RAM address 0.', '', '        .text', '_start:',
               '        li   sp, %d' % stack, '        call _main', '        halt', '']
        out += self.text
        out += ['', '        .data']
        for name in ('rodata', 'data', 'bss'):
            out += self.data[name]
        out += self.aliases
        return '\n'.join(out) + '\n'


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('files', nargs='+')
    ap.add_argument('-o', '--output', default='-')
    ap.add_argument('--stack', type=lambda s: int(s, 0), default=0x3FFF0,
                    help='initial stack pointer (default 0x3FFF0)')
    args = ap.parse_args()
    t = Translator()
    try:
        for path in args.files:
            t.translate(path)
    except Error as e:
        sys.exit('rv2cpu: %s' % e)
    text = t.output(args.stack)
    if args.output == '-':
        sys.stdout.write(text)
    else:
        with open(args.output, 'w') as f:
            f.write(text)
        print('%s: %d instructions' % (args.output, t.counts['text'] + 3), file=sys.stderr)


if __name__ == '__main__':
    main()
