# ISA — 32-bit Harvard CPU (v0.2)

Working name: TBD. Implemented in `cpu/` (Verilog) and `tools/asm.py` (assembler);
see `README.md` for how to run programs.

## 1. Overview

| Property | Choice |
|---|---|
| Word size | 32 bits (registers, data, instructions) |
| Architecture | Harvard: separate instruction memory and data memory |
| Registers | 16 × 32 bit, `r0` hardwired to 0 |
| Instruction size | fixed 32 bits, 8-bit opcode, all fields hex-digit aligned |
| Addressing | byte-addressed, little-endian |
| Flags | none — branches compare two registers directly |
| Execution | single-cycle (first implementation) |
| I/O | memory-mapped (see §7) |

Reset state: `PC = 0`, all registers 0. A program must set `sp` itself (see §9).

## 2. Registers

| Register | Alias | Role | Preserved across calls? |
|---|---|---|---|
| `r0` | `zero` | always 0, writes ignored (hardware) | — |
| `r1`–`r4` | `a0`–`a3` | arguments; `r1` = return value | no (caller saves) |
| `r5`–`r9` | `t0`–`t4` | temporaries | no (caller saves) |
| `r10`–`r13` | `s0`–`s3` | saved registers | yes (callee saves) |
| `r14` | `sp` | stack pointer | yes |
| `r15` | `lr` | link register (return address) | no |

Only `r0` is special in hardware. `sp` and `lr` are conventions (§8); `jal`/`jalr` write
whatever register you name.

## 3. Instruction formats

Field names by bit position — the decoder always uses these:

```
          31      24 23  20 19  16 15  12 11                 0
R-type:  [  opcode  |  A   |  B   |  C   |      0 (unused)     ]
I-type:  [  opcode  |  A   |  B   |          imm16             ]
J-type:  [  opcode  |  A   |               imm20               ]
```

- **A** = bits 23:20, **B** = bits 19:16, **C** = bits 15:12 (each a register number 0–15)
- **imm16** = bits 15:0, **imm20** = bits 19:0
- In hex, an instruction reads as `OO A B CCCC`: e.g. `0x01312000` = op `01`, A=3, B=1, C=2.

How the fields are used:

| Kind | Writes | Reads (port 1) | Reads (port 2) |
|---|---|---|---|
| R-type ALU | A | B | C |
| I-type ALU / load / `jalr` | A | B | — |
| Store | — | B (base address) | A (data) |
| Branch | — | B | A |
| `jal` | A | — | — |

So register read port 1 is always **B**; read port 2 is **C** for R-type and **A** for stores and branches.

### Immediates

- `sext(imm16)`: sign-extended to 32 bits (−32768 … 32767). Used by `addi slti sltiu`, loads, stores, branches, `jalr`.
- `zext(imm16)`: zero-extended (0 … 65535). Used by `andi ori xori` — so `lui` + `ori` can build any 32-bit constant.
- Shift amounts use only the low 5 bits (`& 31`).

## 4. Opcode map

Opcodes are grouped by their high hex digit; register and immediate versions of an ALU op
share the low digit (`add` = `0x01`, `addi` = `0x11`).

| | x0 | x1 | x2 | x3 | x4 | x5 | x6 | x7 | x8 | x9 | xA | xF |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **0x** ALU reg | *illegal* | add | sub | and | or | xor | shl | shr | sra | slt | sltu | |
| **1x** ALU imm | | addi | | andi | ori | xori | shli | shri | srai | slti | sltiu | lui |
| **2x** mul/div | mul | *mulh* | *mulhu* | | div | divu | mod | modu | | | | |
| **3x** memory | ld | ldb | ldbu | *ldh* | *ldhu* | | | | st | stb | *sth* | |
| **4x** branch | beq | bne | blt | bge | bltu | bgeu | | | | | | |
| **5x** jump | jal | jalr | | | | | | | | | | |
| **Fx** system | *reserved (interrupts)* | | | | | | | | | | | halt (`0xFF`) |

*Italic* = reserved for later. Every opcode not listed is **illegal**.
Opcode `0x00` is deliberately illegal: running into zeroed memory stops the simulation
instead of silently executing garbage.

**Illegal instruction (simulation):** print PC and instruction, then `$finish`.

## 5. Instructions

Notation: `R[x]` = register x, `PC` = address of the current instruction,
`M32[a]` / `M8[a]` = data memory word / byte at byte address `a`.

### 5.1 ALU, register (R-type) — `op rd, rs, rt` → A=rd, B=rs, C=rt

| Op | Assembly | Operation |
|---|---|---|
| 0x01 | `add rd, rs, rt` | `R[rd] = R[rs] + R[rt]` |
| 0x02 | `sub rd, rs, rt` | `R[rd] = R[rs] - R[rt]` |
| 0x03 | `and rd, rs, rt` | `R[rd] = R[rs] & R[rt]` |
| 0x04 | `or  rd, rs, rt` | `R[rd] = R[rs] \| R[rt]` |
| 0x05 | `xor rd, rs, rt` | `R[rd] = R[rs] ^ R[rt]` |
| 0x06 | `shl rd, rs, rt` | `R[rd] = R[rs] << R[rt][4:0]` |
| 0x07 | `shr rd, rs, rt` | `R[rd] = R[rs] >> R[rt][4:0]` (logical, fills 0) |
| 0x08 | `sra rd, rs, rt` | `R[rd] = R[rs] >>> R[rt][4:0]` (arithmetic, fills sign bit) |
| 0x09 | `slt rd, rs, rt` | `R[rd] = (signed R[rs] < signed R[rt]) ? 1 : 0` |
| 0x0A | `sltu rd, rs, rt` | `R[rd] = (unsigned R[rs] < unsigned R[rt]) ? 1 : 0` |

### 5.2 ALU, immediate (I-type) — `op rd, rs, imm` → A=rd, B=rs

| Op | Assembly | Operation |
|---|---|---|
| 0x11 | `addi rd, rs, imm` | `R[rd] = R[rs] + sext(imm)` |
| 0x13 | `andi rd, rs, imm` | `R[rd] = R[rs] & zext(imm)` |
| 0x14 | `ori  rd, rs, imm` | `R[rd] = R[rs] \| zext(imm)` |
| 0x15 | `xori rd, rs, imm` | `R[rd] = R[rs] ^ zext(imm)` |
| 0x16 | `shli rd, rs, imm` | `R[rd] = R[rs] << imm[4:0]` |
| 0x17 | `shri rd, rs, imm` | `R[rd] = R[rs] >> imm[4:0]` |
| 0x18 | `srai rd, rs, imm` | `R[rd] = R[rs] >>> imm[4:0]` |
| 0x19 | `slti rd, rs, imm` | `R[rd] = (signed R[rs] < sext(imm)) ? 1 : 0` |
| 0x1A | `sltiu rd, rs, imm` | `R[rd] = (unsigned R[rs] < unsigned sext(imm)) ? 1 : 0` |
| 0x1F | `lui rd, imm` | `R[rd] = imm << 16` (B must be 0) |

There is no `subi`: use `addi` with a negative immediate.

### 5.3 Multiply / divide (R-type)

| Op | Assembly | Operation |
|---|---|---|
| 0x20 | `mul  rd, rs, rt` | `R[rd] = low 32 bits of R[rs] * R[rt]` (same for signed/unsigned) |
| 0x24 | `div  rd, rs, rt` | `R[rd] = signed R[rs] / signed R[rt]` (rounds toward 0, like C) |
| 0x25 | `divu rd, rs, rt` | `R[rd] = unsigned R[rs] / unsigned R[rt]` |
| 0x26 | `mod  rd, rs, rt` | `R[rd] = signed R[rs] % signed R[rt]` (sign follows `rs`, like C) |
| 0x27 | `modu rd, rs, rt` | `R[rd] = unsigned R[rs] % unsigned R[rt]` |

Special cases (no exceptions, always a defined result):

| Case | div / divu | mod / modu |
|---|---|---|
| divide by 0 | `0xFFFFFFFF` | `R[rs]` |
| `div`: `0x80000000 / -1` (overflow) | `0x80000000` | `0` |

Reserved: `mulh` (0x21) / `mulhu` (0x22) = high 32 bits of the 64-bit product.

### 5.4 Memory (I-type)

Loads: A=rd, B=base. Stores: A=data register, B=base. Address = `R[base] + sext(imm)`.

| Op | Assembly | Operation |
|---|---|---|
| 0x30 | `ld   rd, [rs+imm]` | `R[rd] = M32[addr]` |
| 0x31 | `ldb  rd, [rs+imm]` | `R[rd] = sext(M8[addr])` (signed `char`) |
| 0x32 | `ldbu rd, [rs+imm]` | `R[rd] = zext(M8[addr])` (unsigned `char`) |
| 0x38 | `st   rt, [rs+imm]` | `M32[addr] = R[rt]` |
| 0x39 | `stb  rt, [rs+imm]` | `M8[addr] = R[rt][7:0]` |

- `ld`/`st` must be 4-byte aligned. The hardware ignores the low 2 address bits (`addr & ~3`); the simulator also prints a warning.
- Little-endian: the word `0x11223344` stored at address 0 puts `0x44` at byte 0 and `0x11` at byte 3.
- Reserved: `ldh`/`ldhu`/`sth` (16-bit halfwords, for C `short`).

### 5.5 Branches (I-type) — `op ra, rb, label` → A=ra, B=rb

Target = `PC + sext(imm) * 4` (offset counted in instructions, relative to the branch itself;
range ±32768 instructions). The assembler computes `imm` from the label.

| Op | Assembly | Branches if |
|---|---|---|
| 0x40 | `beq  ra, rb, label` | `R[ra] == R[rb]` |
| 0x41 | `bne  ra, rb, label` | `R[ra] != R[rb]` |
| 0x42 | `blt  ra, rb, label` | `signed R[ra] < signed R[rb]` |
| 0x43 | `bge  ra, rb, label` | `signed R[ra] >= signed R[rb]` |
| 0x44 | `bltu ra, rb, label` | `unsigned R[ra] < unsigned R[rb]` |
| 0x45 | `bgeu ra, rb, label` | `unsigned R[ra] >= unsigned R[rb]` |

Otherwise `PC = PC + 4`.

### 5.6 Jumps

| Op | Format | Assembly | Operation |
|---|---|---|---|
| 0x50 | J | `jal rd, label` | `R[rd] = PC + 4; PC = PC + sext(imm20) * 4` (range ±512K instructions) |
| 0x51 | I | `jalr rd, rs, imm` | `R[rd] = PC + 4; PC = (R[rs] + sext(imm)) & ~3` |

`jalr` computes the target before writing `rd`, so `jalr lr, lr, 0` works.

### 5.7 System

| Op | Assembly | Operation |
|---|---|---|
| 0xFF | `halt` | stop the CPU (simulation: print cycle count, `$finish`) |
| 0xF0–0xFE | — | reserved (interrupt return, enable/disable, …) |

## 6. Assembler

### Syntax

```
label:                      ; labels end with ':'
        addi r1, r0, 10     ; comments start with ';'
        ld   r2, [sp+4]     ; memory operand: [reg+imm], [reg-imm] or [reg]
        li   r3, 0xFFFF0000 ; numbers: 42, -7, 0x2A, 0b101010, 'A'
```

Wherever a number is expected, an expression works too: `IO + 4`, `'A' - 'a'`,
`(1 << 20) | 3`, `COLS * 4` (operators `+ - * // % << >> & | ^ ~` and parentheses).

Register names: `r0`–`r15` or their aliases (`zero a0–a3 t0–t4 s0–s3 sp lr`).

### Pseudo-instructions

| Pseudo | Expands to |
|---|---|
| `nop` | `add r0, r0, r0` (`0x01000000`) |
| `mov rd, rs` | `add rd, rs, r0` |
| `li rd, value` | `addi rd, r0, value` if it fits in 16 bits signed, else `lui rd, hi` + `ori rd, rd, lo` |
| `la rd, label` | `lui` + `ori` with the label's address |
| `not rd, rs` | `sub rd, r0, rs` + `addi rd, rd, -1` (~x = −x − 1; works even when rd = rs) |
| `neg rd, rs` | `sub rd, r0, rs` |
| `j label` | `jal r0, label` |
| `call label` | `jal lr, label` |
| `ret` | `jalr r0, lr, 0` |
| `jr rs` | `jalr r0, rs, 0` |
| `bgt ra, rb, l` / `ble` / `bgtu` / `bleu` | `blt rb, ra, l` / `bge rb, ra, l` / … (operands swapped) |
| `beqz ra, l` / `bnez ra, l` | `beq ra, r0, l` / `bne ra, r0, l` |
| `push rs` | `addi sp, sp, -4` + `st rs, [sp]` |
| `pop rd` | `ld rd, [sp]` + `addi sp, sp, 4` |

### Directives

| Directive | Meaning |
|---|---|
| `.text` | following lines go to instruction memory (default) |
| `.data` | following lines go to data memory (initial RAM contents) |
| `.word v, …` | 32-bit values (aligned to 4 bytes automatically) |
| `.byte v, …` | 8-bit values |
| `.string "hi"` | bytes of the string plus a terminating 0 |
| `.space n` | n zero bytes |
| `.align n` | pad to a multiple of n bytes |
| `.equ NAME, value` | define a constant (it can only use symbols defined above it) |

Output: `prog.text.hex` (loaded into instruction memory), `prog.data.hex` (loaded into RAM)
and `prog.lst`, a listing with the address and machine code of every source line.

Because of the Harvard split, a program **cannot read its own instruction memory**: lookup
tables, strings and level data go in `.data`.

## 7. Memory map

### Instruction memory (separate address space)

| Address | Size | Contents |
|---|---|---|
| `0x0000_0000`–`0x0000_FFFF` | 64 KB (16K instructions) | program, starts at 0 |

### Data memory

| Address | Size | Contents |
|---|---|---|
| `0x0000_0000`–`0x0003_FFFF` | 256 KB | RAM: `.data` at 0, then heap ↑ … stack ↓ from `0x0004_0000` |
| `0xFFFE_0000`–`0xFFFE_0F9F` | 4000 B | text screen, 40 × 25 cells, one word per cell |
| `0xFFFF_0000`–`0xFFFF_00FF` | 256 B | I/O registers |

Anything else: reads return 0, writes are ignored, the simulator prints a warning.

### Text screen

Cell `(x, y)` is at `0xFFFE_0000 + (y * 40 + x) * 4`. Cell format:

```
 31        16 15  12 11   8 7          0
[   unused   |  bg  |  fg  | character  ]
```

Colors: the 16 terminal colors — 0 black, 1 red, 2 green, 3 yellow, 4 blue, 5 magenta,
6 cyan, 7 light gray, 8–15 the bright versions (8 dark gray … 15 white). A cell with both
colors 0 is shown in the terminal's default colors, so plain characters (`0x00000041` = `A`)
stay visible. The screen is only drawn when the program writes to `SCREEN_SHOW`, so a game
can draw a whole frame first, then show it.

### I/O registers (base `0xFFFF_0000`)

| Offset | Name | R/W | Function |
|---|---|---|---|
| `0x00` | `CONSOLE_OUT` | W | print the low byte as an ASCII character |
| `0x04` | `PRINT_INT` | W | print the value as a signed decimal number |
| `0x08` | `KEY_STATUS` | R | 1 if a key is waiting, else 0 |
| `0x0C` | `KEY_DATA` | R | ASCII code of the next key (reading removes it) |
| `0x10` | `TIMER` | R | clock cycles since reset |
| `0x14` | `RANDOM` | R | a new pseudo-random 32-bit number on every read |
| `0x18` | `SCREEN_SHOW` | W | any write: display the text screen |
| `0x1C` | `LEDS` | R/W | 32 output bits (visible in the waveform) |

Keyboard in simulation: keys come from a file (`+keys=file`, one byte per key), all waiting
from the start. Interactive input is still open.

## 8. Calling convention

- Arguments in `r1`–`r4`, more on the stack. Return value in `r1`.
- `call func` puts the return address in `lr`; `ret` returns.
- A function may freely change `r1`–`r9` and `lr`. It must restore `r10`–`r13` and `sp` before returning.
- A function that calls other functions must save `lr` first (it gets overwritten).
- The stack grows downward, `sp` points at the last used word, and stays 4-byte aligned.

Typical function:

```
draw_box:                   ; draw_box(x, y) — x in r1, y in r2
        addi sp, sp, -8     ; room for two words
        st   lr,  [sp+4]    ; save return address (we call another function)
        st   s0,  [sp+0]    ; save s0 (we use it below)
        ...
        call draw_char
        ...
        ld   s0,  [sp+0]
        ld   lr,  [sp+4]
        addi sp, sp, 8
        ret
```

## 9. Startup

Every program starts like this (later a C compiler adds it automatically):

```
        .text
start:  li   sp, 0x00040000 ; stack at the top of RAM
        call main
        halt
```

## 10. Example: Fibonacci

```
; print the first 20 Fibonacci numbers, one per line
        .text
        li   s0, 0xFFFF0000     ; I/O base address
        li   r1, 0              ; a = 0
        li   r2, 1              ; b = 1
        li   r3, 20             ; counter
loop:
        st   r1, [s0+0x04]      ; PRINT_INT  a
        li   r4, '\n'
        st   r4, [s0+0x00]      ; CONSOLE_OUT newline
        add  r4, r1, r2         ; t = a + b
        mov  r1, r2             ; a = b
        mov  r2, r4             ; b = t
        addi r3, r3, -1         ; counter--
        bnez r3, loop
        halt
```

Hand-encoded examples:

| Assembly | Fields | Hex |
|---|---|---|
| `addi r1, r0, 10` | op 11, A=1, B=0, imm=000A | `0x1110000A` |
| `add r3, r1, r2` | op 01, A=3, B=1, C=2 | `0x01312000` |
| `st r1, [r10+4]` | op 38, A=1 (data), B=A (base), imm=0004 | `0x381A0004` |
| `blt r1, r3, -2` | op 42, A=1, B=3, imm=FFFE | `0x4213FFFE` |
| `halt` | op FF | `0xFF000000` |

## 11. Reserved for later

- Interrupts and an interrupt return instruction (`0xF0`–`0xFE`)
- `mulh`/`mulhu`, halfword loads/stores
- Pixel framebuffer as an additional peripheral
- Pipelined implementation (the ISA has no flags and no delay slots, so it pipelines cleanly)
