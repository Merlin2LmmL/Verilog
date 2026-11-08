// JavaScript model of the CPU in ../cpu/ (decoder.v, alu.v, cpu.v, io.v), see ../ISA.md
// Works in the browser (global CPU32) and in node (module.exports), so it can be tested.
(function (root) {
  'use strict';

  const RAM_BYTES = 0x40000;
  const IMEM_WORDS = 16384;
  const IO_BASE = 0xFFFF0000;
  const SCREEN_BASE = 0xFFFE0000;
  const SCREEN_END = 0xFFFE0FA0;

  const ALU_NAMES = ['pass b', 'add', 'sub', 'and', 'or', 'xor', 'shl', 'shr', 'sra', 'slt', 'sltu',
                     'mul', 'div', 'divu', 'mod', 'modu'];
  const ALU_SYMBOLS = ['b', '+', '-', '&', '|', '^', '<<', '>>', '>>>', '<', '<u', '*', '/', '/u', '%', '%u'];

  // opcode -> [mnemonic, kind]
  // kinds: R (rd, rs, rt), I (rd, rs, imm), LUI, LOAD, STORE, BRANCH, JAL, JALR, HALT
  const OPS = {
    0x01: ['add', 'R'], 0x02: ['sub', 'R'], 0x03: ['and', 'R'], 0x04: ['or', 'R'], 0x05: ['xor', 'R'],
    0x06: ['shl', 'R'], 0x07: ['shr', 'R'], 0x08: ['sra', 'R'], 0x09: ['slt', 'R'], 0x0A: ['sltu', 'R'],
    0x11: ['addi', 'I'], 0x13: ['andi', 'I'], 0x14: ['ori', 'I'], 0x15: ['xori', 'I'],
    0x16: ['shli', 'I'], 0x17: ['shri', 'I'], 0x18: ['srai', 'I'], 0x19: ['slti', 'I'], 0x1A: ['sltiu', 'I'],
    0x1F: ['lui', 'LUI'],
    0x20: ['mul', 'R'], 0x24: ['div', 'R'], 0x25: ['divu', 'R'], 0x26: ['mod', 'R'], 0x27: ['modu', 'R'],
    0x30: ['ld', 'LOAD'], 0x31: ['ldb', 'LOAD'], 0x32: ['ldbu', 'LOAD'],
    0x38: ['st', 'STORE'], 0x39: ['stb', 'STORE'],
    0x40: ['beq', 'BRANCH'], 0x41: ['bne', 'BRANCH'], 0x42: ['blt', 'BRANCH'],
    0x43: ['bge', 'BRANCH'], 0x44: ['bltu', 'BRANCH'], 0x45: ['bgeu', 'BRANCH'],
    0x50: ['jal', 'JAL'], 0x51: ['jalr', 'JALR'],
    0xFF: ['halt', 'HALT'],
  };

  const ZERO_EXT_IMM = new Set([0x13, 0x14, 0x15]);   // andi ori xori

  const u32 = (x) => x >>> 0;
  const sext16 = (x) => (x << 16) >> 16;
  const hex8 = (x) => u32(x).toString(16).padStart(8, '0');

  function regName(n) {
    return n === 14 ? 'sp' : n === 15 ? 'lr' : 'r' + n;
  }

  // instruction word -> control signals (what decoder.v does)
  function decode(instr) {
    instr = u32(instr);
    const op = instr >>> 24;
    const a = (instr >>> 20) & 15, b = (instr >>> 16) & 15, c = (instr >>> 12) & 15;
    const imm16 = instr & 0xFFFF;
    const imm20 = instr & 0xFFFFF;
    const entry = OPS[op];
    const d = {
      instr, op, a, b, c, imm16, imm20,
      name: entry ? entry[0] : '???', kind: entry ? entry[1] : 'ILLEGAL',
      illegal: !entry, halt: false,
      rs1: b, rs2: null, rd: null,            // register numbers actually used
      aluOp: 1, aluBImm: false, usesAlu: false,
      imm: sext16(imm16),
      regWrite: false, wbSel: 'alu',          // alu | mem | pc4
      memRead: false, memWrite: false, memByte: false, memSigned: false,
      branch: false, jal: false, jalr: false,
    };
    switch (d.kind) {
      case 'R':
        d.rs2 = c; d.rd = a; d.regWrite = true; d.usesAlu = true;
        d.aluOp = op >= 0x20 ? [0xB, 0, 0, 0, 0xC, 0xD, 0xE, 0xF][op & 7] : (op & 15);
        break;
      case 'I':
        d.rd = a; d.regWrite = true; d.usesAlu = true; d.aluBImm = true; d.aluOp = op & 15;
        if (ZERO_EXT_IMM.has(op)) d.imm = imm16;
        break;
      case 'LUI':
        d.rs1 = null; d.rd = a; d.regWrite = true; d.usesAlu = true; d.aluBImm = true;
        d.aluOp = 0; d.imm = u32(imm16 << 16);
        break;
      case 'LOAD':
        d.rd = a; d.regWrite = true; d.usesAlu = true; d.aluBImm = true; d.memRead = true;
        d.memByte = op !== 0x30; d.memSigned = op === 0x31; d.wbSel = 'mem';
        break;
      case 'STORE':
        d.rs2 = a; d.usesAlu = true; d.aluBImm = true; d.memWrite = true; d.memByte = op === 0x39;
        break;
      case 'BRANCH':
        d.rs2 = a; d.branch = true; d.imm = sext16(imm16) * 4;
        break;
      case 'JAL':
        d.rs1 = null; d.rd = a; d.regWrite = true; d.jal = true; d.wbSel = 'pc4';
        d.imm = ((imm20 << 12) >> 12) * 4;
        break;
      case 'JALR':
        d.rd = a; d.regWrite = true; d.jalr = true; d.usesAlu = true; d.aluBImm = true; d.wbSel = 'pc4';
        break;
      case 'HALT':
        d.halt = true; d.rs1 = null;
        break;
      default:
        d.rs1 = null;
    }
    return d;
  }

  function alu(op, a, b) {
    a = u32(a); b = u32(b);
    const sa = a | 0, sb = b | 0;
    switch (op) {
      case 0: return b;
      case 1: return u32(a + b);
      case 2: return u32(a - b);
      case 3: return u32(a & b);
      case 4: return u32(a | b);
      case 5: return u32(a ^ b);
      case 6: return u32(a << (b & 31));
      case 7: return u32(a >>> (b & 31));
      case 8: return u32(sa >> (b & 31));
      case 9: return sa < sb ? 1 : 0;
      case 10: return a < b ? 1 : 0;
      case 11: return u32(Math.imul(a, b));
      case 12: return b === 0 ? 0xFFFFFFFF : (a === 0x80000000 && b === 0xFFFFFFFF) ? 0x80000000 : u32(Math.trunc(sa / sb));
      case 13: return b === 0 ? 0xFFFFFFFF : u32(Math.floor(a / b));
      case 14: return b === 0 ? a : (a === 0x80000000 && b === 0xFFFFFFFF) ? 0 : u32(sa % sb);
      case 15: return b === 0 ? a : u32(a % b);
    }
    return 0;
  }

  // "blt ra, rb" jumps if R[ra] < R[rb]; ra is port 2, rb is port 1
  function compare(op, p2, p1) {
    switch (op) {
      case 0x40: return p2 === p1;
      case 0x41: return p2 !== p1;
      case 0x42: return (p2 | 0) < (p1 | 0);
      case 0x43: return (p2 | 0) >= (p1 | 0);
      case 0x44: return p2 < p1;
      case 0x45: return p2 >= p1;
    }
    return false;
  }

  function disasm(instr, pc) {
    const d = decode(instr);
    const r = regName;
    const sh = (n) => (n < 0 ? '-' + (-n) : '' + n);
    const hx = (n) => '0x' + u32(n).toString(16).toUpperCase();
    switch (d.kind) {
      case 'R': return `${d.name} ${r(d.a)}, ${r(d.b)}, ${r(d.c)}`;
      case 'I': return `${d.name} ${r(d.a)}, ${r(d.b)}, ${ZERO_EXT_IMM.has(d.op) ? hx(d.imm16) : sh(d.imm)}`;
      case 'LUI': return `lui ${r(d.a)}, ${hx(d.imm16)}`;
      case 'LOAD': return `${d.name} ${r(d.a)}, [${r(d.b)}${d.imm < 0 ? '-' + (-d.imm) : '+' + d.imm}]`;
      case 'STORE': return `${d.name} ${r(d.a)}, [${r(d.b)}${d.imm < 0 ? '-' + (-d.imm) : '+' + d.imm}]`;
      case 'BRANCH': {
        const target = pc === undefined ? null : u32(pc + d.imm);
        return `${d.name} ${r(d.a)}, ${r(d.b)}, ${target === null ? sh(d.imm / 4) : hx(target)}`;
      }
      case 'JAL': {
        const target = pc === undefined ? null : u32(pc + d.imm);
        return `jal ${r(d.a)}, ${target === null ? sh(d.imm / 4) : hx(target)}`;
      }
      case 'JALR': return `jalr ${r(d.a)}, ${r(d.b)}, ${sh(d.imm)}`;
      case 'HALT': return 'halt';
    }
    return '(illegal)';
  }

  // parse the hex text box: words separated by spaces/newlines/commas, comments after ; # or //
  // returns { words: [{value, line}], errors: [{line, text, message}] }
  function parseHex(text) {
    const words = [], errors = [];
    text.split('\n').forEach((raw, i) => {
      const line = raw.replace(/(;|#|\/\/).*$/, '').trim();
      if (!line) return;
      for (const tok of line.split(/[\s,]+/)) {
        if (!tok) continue;
        const t = tok.replace(/^0x/i, '').replace(/_/g, '');
        if (!/^[0-9a-fA-F]{1,8}$/.test(t)) {
          errors.push({ line: i, text: tok, message: `"${tok}" is not a hex number of up to 8 digits` });
        } else {
          words.push({ value: parseInt(t, 16) >>> 0, line: i });
        }
      }
    });
    return { words, errors };
  }

  class Machine {
    constructor() {
      this.text = new Uint32Array(IMEM_WORDS);
      this.textLen = 0;
      this.data = new Uint8Array(RAM_BYTES);
      this.initialData = new Uint8Array(RAM_BYTES);
      this.onOutput = null;
      this.reset();
    }

    loadProgram(words, dataWords) {
      this.text.fill(0);
      this.textLen = Math.min(words.length, IMEM_WORDS);
      for (let i = 0; i < this.textLen; i++) this.text[i] = words[i];
      this.initialData.fill(0);
      (dataWords || []).slice(0, RAM_BYTES / 4).forEach((w, i) => {
        for (let k = 0; k < 4; k++) this.initialData[i * 4 + k] = (w >>> (8 * k)) & 255;
      });
      this.reset();
    }

    reset() {
      this.pc = 0;
      this.regs = new Uint32Array(16);
      this.data.set(this.initialData);
      this.cycles = 0;
      this.halted = false;
      this.trapped = false;
      this.timer = 0;
      this.rng = 0x2545F491;
      this.leds = 0;
      this.touched = new Set();           // word indexes of RAM that were written
      this.lastWrittenReg = null;
      this.lastStore = null;
      this.warnings = [];
    }

    fetch() {
      const idx = this.pc >>> 2;
      return idx < IMEM_WORDS ? this.text[idx] : 0;
    }

    readWord(addr) {
      addr = u32(addr) & ~3;
      if (addr < RAM_BYTES)
        return u32(this.data[addr] | this.data[addr + 1] << 8 | this.data[addr + 2] << 16 | this.data[addr + 3] << 24);
      if (addr >= SCREEN_BASE && addr < SCREEN_END) return 0;
      if (addr >= IO_BASE && addr < IO_BASE + 0x100) {
        switch (addr - IO_BASE) {
          case 0x08: return 0;                                    // no keyboard in the browser (yet)
          case 0x0C: return 0;
          case 0x10: return this.timer;
          case 0x14: return this.rng;
          case 0x1C: return this.leds;
        }
        return 0;
      }
      return 0;
    }

    // look at what the instruction at PC would do, without changing anything
    peek() {
      const instr = this.fetch();
      const d = decode(instr);
      const t = {
        d, pc: this.pc, instr,
        p1Reg: d.rs1, p2Reg: d.rs2,
        p1: d.rs1 === null ? 0 : this.regs[d.rs1],
        p2: d.rs2 === null ? 0 : this.regs[d.rs2],
        aluA: 0, aluB: 0, aluY: 0,
        taken: false, nextPc: u32(this.pc + 4), pc4: u32(this.pc + 4),
        memAddr: null, memLane: 0, memData: null, loadValue: null,
        wbValue: null, writeReg: null,
      };
      if (d.illegal) { t.nextPc = this.pc; return t; }
      if (d.halt) { t.nextPc = this.pc; return t; }

      if (d.usesAlu) {
        t.aluA = d.rs1 === null ? 0 : t.p1;
        t.aluB = d.aluBImm ? u32(d.imm) : t.p2;
        t.aluY = alu(d.aluOp, t.aluA, t.aluB);
      }
      if (d.branch) {
        t.taken = compare(d.op, t.p2, t.p1);
        if (t.taken) t.nextPc = u32(this.pc + d.imm);
      }
      if (d.jal) t.nextPc = u32(this.pc + d.imm);
      if (d.jalr) t.nextPc = u32(t.aluY & ~3);
      if (d.memRead || d.memWrite) {
        t.memAddr = u32(t.aluY & ~3);
        t.memLane = t.aluY & 3;
        if (d.memWrite) t.memData = d.memByte ? t.p2 & 255 : t.p2;
        if (d.memRead) {
          const w = this.readWord(t.memAddr);
          if (d.memByte) {
            const byte = (w >>> (8 * t.memLane)) & 255;
            t.loadValue = d.memSigned ? u32((byte << 24) >> 24) : byte;
          } else {
            t.loadValue = w;
          }
        }
      }
      if (d.regWrite) {
        t.wbValue = d.wbSel === 'mem' ? t.loadValue : d.wbSel === 'pc4' ? t.pc4 : t.aluY;
        t.writeReg = d.rd;
      }
      return t;
    }

    // run the instruction at PC. returns the trace of what it did
    step() {
      if (this.halted) return null;
      const t = this.peek();
      const d = t.d;
      this.lastWrittenReg = null;
      this.lastStore = null;
      this.cycles++;
      this.timer = u32(this.timer + 1);

      if (d.illegal) {
        this.halted = true; this.trapped = true;
        return t;
      }
      if (d.halt) {
        this.halted = true;
        return t;
      }
      if ((d.memRead || d.memWrite) && !d.memByte && t.memLane !== 0)
        this.warnings.push(`misaligned ${d.memWrite ? 'st' : 'ld'} at ${hex8(t.aluY)} (PC ${hex8(this.pc)})`);

      if (d.memWrite) this.store(t.memAddr, t.memLane, t.p2, d.memByte);
      if (d.memRead && t.memAddr >= IO_BASE && t.memAddr - IO_BASE === 0x14) this.rng = xorshift(this.rng);

      if (d.regWrite && d.rd !== 0) {
        this.regs[d.rd] = t.wbValue;
        this.lastWrittenReg = d.rd;
      }
      this.pc = t.nextPc;
      return t;
    }

    store(addr, lane, value, byte) {
      if (addr < RAM_BYTES) {
        if (byte) {
          this.data[addr + lane] = value & 255;
        } else {
          for (let k = 0; k < 4; k++) this.data[addr + k] = (value >>> (8 * k)) & 255;
        }
        this.touched.add(addr >>> 2);
        this.lastStore = addr >>> 2;
      } else if (addr >= IO_BASE && addr < IO_BASE + 0x100) {
        switch (addr - IO_BASE) {
          case 0x00: this.out(String.fromCharCode(value & 255)); break;
          case 0x04: this.out(String(value | 0)); break;
          case 0x1C: this.leds = u32(value); break;
        }
      } else if (!(addr >= SCREEN_BASE && addr < SCREEN_END)) {
        this.warnings.push(`store to unmapped address ${hex8(addr)}`);
      }
    }

    out(s) { if (this.onOutput) this.onOutput(s); }
  }

  function xorshift(s) {
    s = u32(s);
    s = u32(s ^ (s << 13));
    s = u32(s ^ (s >>> 17));
    return u32(s ^ (s << 5));
  }

  const api = { Machine, decode, disasm, parseHex, alu, hex8, regName, u32, OPS, ALU_NAMES, ALU_SYMBOLS, RAM_BYTES, IMEM_WORDS };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.CPU32 = api;
})(typeof self !== 'undefined' ? self : this);
