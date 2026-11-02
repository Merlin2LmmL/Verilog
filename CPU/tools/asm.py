#!/usr/bin/env python3
# Assembler for my CPU (instruction set: ../ISA.md)
#
#   python3 asm.py program.asm [-o build/program]
#
# writes <out>.text.hex (instruction ROM), <out>.data.hex (RAM) and <out>.lst (listing)

import argparse
import ast
import operator
import re
import sys

REGS = {f'r{i}': i for i in range(16)}
REGS.update(zero=0, a0=1, a1=2, a2=3, a3=4, t0=5, t1=6, t2=7, t3=8, t4=9,
            s0=10, s1=11, s2=12, s3=13, sp=14, lr=15)

R_OPS = {'add': 0x01, 'sub': 0x02, 'and': 0x03, 'or': 0x04, 'xor': 0x05,
         'shl': 0x06, 'shr': 0x07, 'sra': 0x08, 'slt': 0x09, 'sltu': 0x0A,
         'mul': 0x20, 'div': 0x24, 'divu': 0x25, 'mod': 0x26, 'modu': 0x27}
SIGNED_I_OPS = {'addi': 0x11, 'slti': 0x19, 'sltiu': 0x1A}
LOGIC_I_OPS = {'andi': 0x13, 'ori': 0x14, 'xori': 0x15}    # imm is zero-extended
SHIFT_I_OPS = {'shli': 0x16, 'shri': 0x17, 'srai': 0x18}
LOAD_OPS = {'ld': 0x30, 'ldb': 0x31, 'ldbu': 0x32}
STORE_OPS = {'st': 0x38, 'stb': 0x39}
BRANCH_OPS = {'beq': 0x40, 'bne': 0x41, 'blt': 0x42, 'bge': 0x43, 'bltu': 0x44, 'bgeu': 0x45}
SWAPPED_BRANCHES = {'bgt': 'blt', 'ble': 'bge', 'bgtu': 'bltu', 'bleu': 'bgeu'}
OP_ADD, OP_SUB, OP_ADDI, OP_ORI, OP_LUI = 0x01, 0x02, 0x11, 0x14, 0x1F
OP_LD, OP_ST, OP_BEQ, OP_BNE = 0x30, 0x38, 0x40, 0x41
OP_JAL, OP_JALR, OP_HALT = 0x50, 0x51, 0xFF
SP, LR = 14, 15

TEXT_SIZE = 64 * 1024
DATA_SIZE = 256 * 1024


class AsmError(Exception):
    pass


class Undefined(AsmError):
    pass


def enc_r(op, a, b, c):
    return op << 24 | a << 20 | b << 16 | c << 12


def enc_i(op, a, b, imm):
    return op << 24 | a << 20 | b << 16 | (imm & 0xFFFF)


def enc_j(op, a, imm):
    return op << 24 | a << 20 | (imm & 0xFFFFF)


def check_range(value, lo, hi, what):
    if not lo <= value <= hi:
        raise AsmError(f'{what} {value} out of range ({lo} .. {hi})')
    return value


ESCAPES = {'n': 10, 't': 9, 'r': 13, '0': 0, 'e': 27, '\\': 92, "'": 39, '"': 34}


def unescape(text):
    # inside of a string/char literal -> list of bytes
    out, i = [], 0
    while i < len(text):
        ch = text[i]
        if ch == '\\':
            i += 1
            if i >= len(text) or text[i] not in ESCAPES:
                raise AsmError(f'unknown escape sequence in "{text}"')
            out.append(ESCAPES[text[i]])
        else:
            if ord(ch) > 255:
                raise AsmError(f"character '{ch}' does not fit in a byte")
            out.append(ord(ch))
        i += 1
    return out


def strip_comment(line):
    # a ; inside quotes is not a comment
    quote, i = None, 0
    while i < len(line):
        ch = line[i]
        if quote:
            if ch == '\\':
                i += 1
            elif ch == quote:
                quote = None
        elif ch in '"\'':
            quote = ch
        elif ch == ';':
            return line[:i]
        i += 1
    return line


def split_operands(text):
    # split at commas, but not inside quotes or brackets
    parts, current, depth, quote, i = [], '', 0, None, 0
    while i < len(text):
        ch = text[i]
        if quote:
            if ch == '\\' and i + 1 < len(text):
                current += ch
                i += 1
                ch = text[i]
            elif ch == quote:
                quote = None
        elif ch in '"\'':
            quote = ch
        elif ch in '[(':
            depth += 1
        elif ch in '])':
            depth -= 1
        elif ch == ',' and depth == 0:
            parts.append(current.strip())
            current = ''
            i += 1
            continue
        current += ch
        i += 1
    if current.strip():
        parts.append(current.strip())
    return parts


CHAR_RE = re.compile(r"'(\\.|[^'\\])'")
BINOPS = {ast.Add: operator.add, ast.Sub: operator.sub, ast.Mult: operator.mul,
          ast.FloorDiv: operator.floordiv, ast.Mod: operator.mod,
          ast.LShift: operator.lshift, ast.RShift: operator.rshift,
          ast.BitAnd: operator.and_, ast.BitOr: operator.or_, ast.BitXor: operator.xor}
UNOPS = {ast.USub: operator.neg, ast.UAdd: operator.pos, ast.Invert: operator.invert}


def evaluate(expr, symbols):
    # numbers, 'c', labels/.equ names and + - * // % << >> & | ^ ~ ( )
    # python parses it, but only numbers, names and those operators are allowed
    text = CHAR_RE.sub(lambda m: str(unescape(m.group(1))[0]), expr.strip())
    try:
        tree = ast.parse(text, mode='eval')
    except SyntaxError:
        raise AsmError(f"cannot understand '{expr}'")

    def ev(node):
        if isinstance(node, ast.Expression):
            return ev(node.body)
        if isinstance(node, ast.Constant) and type(node.value) is int:
            return node.value
        if isinstance(node, ast.Name):
            if node.id in symbols:
                return symbols[node.id]
            if node.id.lower() in REGS:
                raise AsmError(f"register '{node.id}' is not allowed here")
            raise Undefined(f"undefined symbol '{node.id}'")
        if isinstance(node, ast.UnaryOp) and type(node.op) in UNOPS:
            return UNOPS[type(node.op)](ev(node.operand))
        if isinstance(node, ast.BinOp) and type(node.op) in BINOPS:
            return BINOPS[type(node.op)](ev(node.left), ev(node.right))
        raise AsmError(f"cannot understand '{expr}'")

    return ev(tree)


def register(token):
    number = REGS.get(token.strip().lower())
    if number is None:
        raise AsmError(f"expected a register, got '{token}'")
    return number


MEM_RE = re.compile(r'^\[\s*(.*?)\s*\]$')
BASE_RE = re.compile(r'^([A-Za-z_]\w*)\s*(?:([+-].*))?$')


def memory_operand(token, symbols):
    # [reg], [reg+off], [reg-off] or just [address] -> (base, offset)
    m = MEM_RE.match(token.strip())
    if not m:
        raise AsmError(f"expected a memory operand like [sp+4], got '{token}'")
    inner = m.group(1)
    m = BASE_RE.match(inner)
    if m and m.group(1).lower() in REGS:
        offset = evaluate(m.group(2), symbols) if m.group(2) else 0
        return REGS[m.group(1).lower()], offset
    return 0, evaluate(inner, symbols)


def li_parts(value):
    # addi if it fits in 16 bits, otherwise lui (+ ori)
    if not -(1 << 31) <= value < (1 << 32):
        raise AsmError(f'value {value} does not fit in 32 bits')
    u = value & 0xFFFFFFFF
    s = u - (1 << 32) if u >> 31 else u
    if -32768 <= s <= 32767:
        return [(OP_ADDI, s)]
    if u & 0xFFFF == 0:
        return [(OP_LUI, u >> 16)]
    return [(OP_LUI, u >> 16), (OP_ORI, u & 0xFFFF)]


def instruction_size(mnemonic, operands, symbols):
    # has to be known in pass 1, before all labels are
    if mnemonic == 'li' and len(operands) == 2:
        try:
            return len(li_parts(evaluate(operands[1], symbols)))
        except Undefined:
            return 2    # a label, so always lui + ori
    if mnemonic in ('la', 'not', 'push', 'pop'):
        return 2
    return 1


def encode(mnemonic, ops, pc, symbols, size):
    def need(count):
        if len(ops) != count:
            raise AsmError(f"'{mnemonic}' needs {count} operand(s), got {len(ops)}")

    def value(token):
        return evaluate(token, symbols)

    def sext16(token):
        return check_range(value(token), -32768, 32767, 'immediate')

    def offset(token, bits):
        target = value(token)
        if target % 4:
            raise AsmError(f'jump target {target:#x} is not a multiple of 4')
        limit = 1 << (bits - 1)
        return check_range((target - pc) // 4, -limit, limit - 1, 'jump distance (instructions)')

    m = mnemonic
    if m in R_OPS:
        need(3)
        return [enc_r(R_OPS[m], register(ops[0]), register(ops[1]), register(ops[2]))]
    if m in SIGNED_I_OPS:
        need(3)
        return [enc_i(SIGNED_I_OPS[m], register(ops[0]), register(ops[1]), sext16(ops[2]))]
    if m in LOGIC_I_OPS:
        need(3)
        imm = check_range(value(ops[2]), 0, 0xFFFF, 'immediate (zero-extended)')
        return [enc_i(LOGIC_I_OPS[m], register(ops[0]), register(ops[1]), imm)]
    if m in SHIFT_I_OPS:
        need(3)
        imm = check_range(value(ops[2]), 0, 31, 'shift amount')
        return [enc_i(SHIFT_I_OPS[m], register(ops[0]), register(ops[1]), imm)]
    if m == 'lui':
        need(2)
        return [enc_i(OP_LUI, register(ops[0]), 0, check_range(value(ops[1]), 0, 0xFFFF, 'immediate'))]
    if m in LOAD_OPS or m in STORE_OPS:
        need(2)
        base, off = memory_operand(ops[1], symbols)
        check_range(off, -32768, 32767, 'offset')
        return [enc_i(LOAD_OPS.get(m) or STORE_OPS[m], register(ops[0]), base, off)]
    if m in BRANCH_OPS:
        need(3)
        return [enc_i(BRANCH_OPS[m], register(ops[0]), register(ops[1]), offset(ops[2], 16))]
    if m in SWAPPED_BRANCHES:
        need(3)
        op = BRANCH_OPS[SWAPPED_BRANCHES[m]]
        return [enc_i(op, register(ops[1]), register(ops[0]), offset(ops[2], 16))]
    if m in ('beqz', 'bnez'):
        need(2)
        op = OP_BEQ if m == 'beqz' else OP_BNE
        return [enc_i(op, register(ops[0]), 0, offset(ops[1], 16))]
    if m == 'jal':
        need(2)
        return [enc_j(OP_JAL, register(ops[0]), offset(ops[1], 20))]
    if m == 'jalr':
        need(3)
        return [enc_i(OP_JALR, register(ops[0]), register(ops[1]), sext16(ops[2]))]
    if m == 'halt':
        need(0)
        return [OP_HALT << 24]

    # pseudo-instructions (ISA.md section 6)
    if m == 'nop':
        need(0)
        return [enc_r(OP_ADD, 0, 0, 0)]
    if m == 'mov':
        need(2)
        return [enc_r(OP_ADD, register(ops[0]), register(ops[1]), 0)]
    if m == 'li':
        need(2)
        rd, v = register(ops[0]), value(ops[1])
        parts = li_parts(v)
        if size == 2 and len(parts) == 1:    # pass 1 already planned 2 words for a label
            u = v & 0xFFFFFFFF
            parts = [(OP_LUI, u >> 16), (OP_ORI, u & 0xFFFF)]
        return [enc_i(op, rd, 0 if op != OP_ORI else rd, imm) for op, imm in parts]
    if m == 'la':
        need(2)
        rd, u = register(ops[0]), value(ops[1]) & 0xFFFFFFFF
        return [enc_i(OP_LUI, rd, 0, u >> 16), enc_i(OP_ORI, rd, rd, u & 0xFFFF)]
    if m == 'not':    # ~x = -x - 1, works even if rd == rs
        need(2)
        rd, rs = register(ops[0]), register(ops[1])
        return [enc_r(OP_SUB, rd, 0, rs), enc_i(OP_ADDI, rd, rd, -1)]
    if m == 'neg':
        need(2)
        return [enc_r(OP_SUB, register(ops[0]), 0, register(ops[1]))]
    if m == 'j':
        need(1)
        return [enc_j(OP_JAL, 0, offset(ops[0], 20))]
    if m == 'call':
        need(1)
        return [enc_j(OP_JAL, LR, offset(ops[0], 20))]
    if m == 'ret':
        need(0)
        return [enc_i(OP_JALR, 0, LR, 0)]
    if m == 'jr':
        need(1)
        return [enc_i(OP_JALR, 0, register(ops[0]), 0)]
    if m == 'push':
        need(1)
        return [enc_i(OP_ADDI, SP, SP, -4), enc_i(OP_ST, register(ops[0]), SP, 0)]
    if m == 'pop':
        need(1)
        return [enc_i(OP_LD, register(ops[0]), SP, 0), enc_i(OP_ADDI, SP, SP, 4)]
    raise AsmError(f"unknown instruction '{mnemonic}'")


LABEL_RE = re.compile(r'^([A-Za-z_]\w*)\s*:')


class Assembler:
    def __init__(self, path):
        self.path = path
        self.symbols = {}
        self.items = []
        self.errors = []
        self.pc = {'text': 0, 'data': 0}
        self.section = 'text'
        self.pending_labels = []    # get the address of the next thing that's placed

    def error(self, line_no, message):
        self.errors.append((line_no, f'{self.path}:{line_no}: error: {message}'))

    def define(self, name, value, line_no):
        if name in self.symbols:
            self.error(line_no, f"'{name}' is defined twice")
        elif name.lower() in REGS:
            self.error(line_no, f"'{name}' is a register name")
        else:
            self.symbols[name] = value

    def place(self, line_no, align=1):
        addr = self.pc[self.section]
        addr += -addr % align
        self.pc[self.section] = addr
        for name in self.pending_labels:
            self.define(name, addr, line_no)
        self.pending_labels = []
        return addr

    # pass 1: addresses and labels
    def pass1(self, lines):
        for line_no, raw in enumerate(lines, 1):
            line = strip_comment(raw).strip()
            while (m := LABEL_RE.match(line)):
                self.pending_labels.append(m.group(1))
                line = line[m.end():].strip()
            if not line:
                continue
            parts = line.split(None, 1)
            name = parts[0].lower()
            ops = split_operands(parts[1]) if len(parts) > 1 else []
            try:
                if name.startswith('.'):
                    self.directive(name, ops, parts[1] if len(parts) > 1 else '', line_no, raw)
                else:
                    if self.section != 'text':
                        raise AsmError('instructions belong in .text (Harvard: the CPU cannot run code from RAM)')
                    size = instruction_size(name, ops, self.symbols)
                    addr = self.place(line_no)
                    self.items.append(dict(kind='instr', addr=addr, size=size, name=name,
                                           ops=ops, line_no=line_no, src=raw))
                    self.pc['text'] += 4 * size
            except AsmError as e:
                self.error(line_no, e)
        self.place(len(lines))

    def directive(self, name, ops, rest, line_no, raw):
        data = self.section == 'data'
        if name in ('.text', '.data'):
            self.place(line_no)
            self.section = name[1:]
        elif name == '.equ':
            if len(ops) != 2:
                raise AsmError('usage: .equ NAME, value')
            try:
                self.define(ops[0], evaluate(ops[1], self.symbols), line_no)
            except Undefined as e:
                raise AsmError(f'{e} (.equ can only use symbols defined above it)')
        elif name == '.word':
            if not ops:
                raise AsmError('.word needs at least one value')
            addr = self.place(line_no, align=4)
            self.items.append(dict(kind='word', section=self.section, addr=addr, ops=ops,
                                   line_no=line_no, src=raw))
            self.pc[self.section] += 4 * len(ops)
        elif not data:
            raise AsmError(f'{name} only works in .data (Harvard: the program cannot read .text)')
        elif name == '.byte':
            if not ops:
                raise AsmError('.byte needs at least one value')
            addr = self.place(line_no)
            self.items.append(dict(kind='byte', section='data', addr=addr, ops=ops,
                                   line_no=line_no, src=raw))
            self.pc['data'] += len(ops)
        elif name == '.string':
            m = re.fullmatch(r'"((?:\\.|[^"\\])*)"', rest.strip())
            if not m:
                raise AsmError('usage: .string "text"')
            values = unescape(m.group(1)) + [0]
            addr = self.place(line_no)
            self.items.append(dict(kind='bytes', section='data', addr=addr, values=values,
                                   line_no=line_no, src=raw))
            self.pc['data'] += len(values)
        elif name == '.space':
            if len(ops) != 1:
                raise AsmError('usage: .space count')
            count = check_range(evaluate(ops[0], self.symbols), 0, DATA_SIZE, '.space')
            addr = self.place(line_no)
            self.items.append(dict(kind='bytes', section='data', addr=addr, values=[0] * count,
                                   line_no=line_no, src=raw))
            self.pc['data'] += count
        elif name == '.align':
            if len(ops) != 1:
                raise AsmError('usage: .align n')
            n = check_range(evaluate(ops[0], self.symbols), 1, 4096, '.align')
            self.pc['data'] += -self.pc['data'] % n
        else:
            raise AsmError(f"unknown directive '{name}'")

    # pass 2: machine code
    def pass2(self):
        text = [0] * (self.pc['text'] // 4)
        data = bytearray(self.pc['data'])
        listing = {'text': [], 'data': []}
        for item in self.items:
            try:
                if item['kind'] == 'instr':
                    words = encode(item['name'], item['ops'], item['addr'], self.symbols, item['size'])
                    assert len(words) == item['size'], 'size changed between passes'
                    for i, w in enumerate(words):
                        text[item['addr'] // 4 + i] = w
                    listing['text'].append((item['addr'], [f'{w:08x}' for w in words], item['src']))
                elif item['kind'] == 'word':
                    words = []
                    for op in item['ops']:
                        v = evaluate(op, self.symbols)
                        check_range(v, -(1 << 31), (1 << 32) - 1, '.word value')
                        words.append(v & 0xFFFFFFFF)
                    if item['section'] == 'text':
                        for i, w in enumerate(words):
                            text[item['addr'] // 4 + i] = w
                    else:
                        for i, w in enumerate(words):
                            data[item['addr'] + 4 * i:item['addr'] + 4 * i + 4] = w.to_bytes(4, 'little')
                    listing[item['section']].append((item['addr'], [f'{w:08x}' for w in words], item['src']))
                else:
                    if item['kind'] == 'byte':
                        values = [check_range(evaluate(op, self.symbols), -128, 255, '.byte value') & 0xFF
                                  for op in item['ops']]
                    else:
                        values = item['values']
                    data[item['addr']:item['addr'] + len(values)] = bytes(values)
                    shown = ' '.join(f'{v:02x}' for v in values[:8]) + (' ...' if len(values) > 8 else '')
                    listing['data'].append((item['addr'], [shown], item['src']))
            except AsmError as e:
                self.error(item['line_no'], e)
        if self.pc['text'] > TEXT_SIZE:
            self.error(0, f"program too big: {self.pc['text']} bytes (instruction memory is {TEXT_SIZE})")
        if len(data) > DATA_SIZE:
            self.error(0, f'data too big: {len(data)} bytes (RAM is {DATA_SIZE})')
        return text, data, listing


def write_outputs(out, text, data, listing, symbols):
    with open(f'{out}.text.hex', 'w') as f:
        f.writelines(f'{w:08x}\n' for w in text)
    data = bytes(data) + bytes(-len(data) % 4)
    with open(f'{out}.data.hex', 'w') as f:
        f.writelines(f"{int.from_bytes(data[i:i + 4], 'little'):08x}\n" for i in range(0, len(data), 4))
    with open(f'{out}.lst', 'w') as f:
        for section in ('text', 'data'):
            f.write(f'---- .{section} ----\n')
            for addr, codes, src in listing[section]:
                f.write(f'{addr:08x}: {codes[0]:<24} {src.rstrip()}\n')
                for code in codes[1:]:
                    f.write(f'{"":10}{code}\n')
        f.write('---- symbols ----\n')
        for name, value in sorted(symbols.items(), key=lambda kv: kv[1] & 0xFFFFFFFF):
            f.write(f'{value & 0xFFFFFFFF:08x}  {name}\n')


def main():
    parser = argparse.ArgumentParser(description='Assemble a program for my CPU (see ISA.md).')
    parser.add_argument('source')
    parser.add_argument('-o', '--out', help='output path without extension (default: next to the source)')
    args = parser.parse_args()
    out = args.out or re.sub(r'\.asm$', '', args.source)

    try:
        with open(args.source) as f:
            lines = f.read().splitlines()
    except OSError as e:
        sys.exit(f'error: {e}')

    asm = Assembler(args.source)
    asm.pass1(lines)
    text, data, listing = asm.pass2()
    if not text:
        asm.error(len(lines), 'no instructions')
    if asm.errors:
        print('\n'.join(message for _, message in sorted(asm.errors)), file=sys.stderr)
        sys.exit(1)

    write_outputs(out, text, data, listing, asm.symbols)
    print(f'assembled {args.source}: {len(text)} instructions, {len(data)} bytes of data')


if __name__ == '__main__':
    main()
