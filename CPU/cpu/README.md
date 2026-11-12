# The hardware

Single-cycle design: in every clock cycle one instruction goes all the way through
fetch → decode → register read → ALU → memory → register write. Everything between
two clock edges is combinational; only the PC, the registers and the memories change
on the rising edge.

```
          +------+  instr  +---------+  control (alu_op, reg_we, mem_we, branch, ...)
   +----->| imem |-------->| decoder |---------------------------------------+
   |      +------+         +---------+                                       |
   |                         | rs1 rs2 rd imm                                |
   |                         v                                               v
   |                    +---------+  rs1_val  +-----+  alu_y (result or address)
   |                    | regfile |---------->|     |----------+--------------------+
   |  pc                |         |  rs2_val  | ALU |          |                    |
   |                    |         |---+------>|     |          v                    |
   |                    +---------+   |  imm->+-----+   +-------------+             |
   |                         ^        +--store data---->| data bus    |             |
   |                         |                          | (soc.v)     |--> RAM      |
   |                         |      loaded value        |             |--> pixels   |
   |                         +------------<-------------|             |--> text     |
   |                         |                          |             |--> io       |
   |                         |                          +-------------+             |
   |                    wb_val = ALU result / loaded value / PC+4                   |
   |                                                                                |
   +---- next pc = pc+4, or pc+imm (taken branch, jal), or alu_y (jalr) <-----------+
```

## Modules

| File | What it does |
|---|---|
| `isa.vh` | constants: opcodes, internal ALU codes, memory map |
| `alu.v` | add, sub, logic, shifts, compares, mul/div/mod (+ `alu_tb.v`) |
| `regfile.v` | 16 × 32-bit registers, r0 = 0, 2 read ports, 1 write port (+ `regfile_tb.v`) |
| `decoder.v` | instruction → register numbers, immediate, control signals |
| `cpu.v` | the core: PC, branch decision, byte lanes for loads/stores, write back |
| `imem.v` | instruction ROM, 64 KB, filled from `+text=<file>` |
| `ram.v` | data RAM, 256 KB, byte-writable, filled from `+data=<file>` |
| `framebuffer.v` | 128 × 96 pixel screen, 1 byte per pixel, drawn in the terminal (only what changed) and optionally saved as a PPM image |
| `screen.v` | 40 × 25 text screen, printed to the terminal |
| `io.v` | I/O registers: console, number output, keyboard (read from the key file while the program runs), timer, random, LEDs, showing the screens |
| `soc.v` | wires everything together; the address decoder picks RAM, pixel screen, text screen or I/O |
| `soc_sim.v` | simulation top level that runs a program (started by `../run.sh`) |

The unit testbenches run like the HDLBits ones: open `alu_tb.v` and press Ctrl+Shift+B.

## Ideas for later

- **Pipelining:** split the cycle into stages (fetch / decode / execute / memory / write back)
  for a higher clock speed; needs forwarding and hazard handling.
- **Interrupts:** the timer or keyboard interrupting the program (opcodes `0xF0`–`0xFE` are reserved).
- **A real multiplier/divider** circuit instead of Verilog's `*` and `/`.
