# CPU

My own 32-bit CPU: Harvard architecture, 16 registers, single-cycle, written in Verilog
and simulated with Icarus Verilog. The instruction set is specified in [ISA.md](ISA.md).

## Quick start

```
cd CPU
./run.sh programs/fib.asm          # assemble + run a program
./run.sh tests/isa_test.asm        # self-test of every instruction: prints PASS
```

Or open any `.asm` file in VS Code and press **Ctrl+Shift+B**.

## Layout

```
ISA.md              the instruction set: formats, opcodes, memory map, calling convention
run.sh              assemble a program and run it on the CPU
cpu/                the hardware (see cpu/README.md)
tools/asm.py        the assembler
programs/           example programs
  fib.asm           Fibonacci numbers
  hello.asm         a string from .data, printed by a function
  keys.asm          keyboard input (with programs/keys.txt)
  screen.asm        colored text screen with a bouncing ball
  pixels.asm        128x96 pixel screen: gradient, all 256 colors, a bouncing square
  draw.asm          draw on the pixel screen with the arrow keys (live keyboard)
  snake.asm         snake on the pixel screen, steered with the arrow keys
  video.asm         plays the compressed black-and-white video in video.bin
tools/keyboard.sh   sends what you type to the running program
tools/video.py      turns a video into video.bin (and the playground's ui/video-data.js)
tests/isa_test.asm  89 checks covering every instruction
build/              generated files (hex, listing, waveform)
```

## How a program runs

1. `tools/asm.py` assembles `prog.asm` into `build/prog.text.hex` (instruction ROM),
   `build/prog.data.hex` (initial RAM) and `build/prog.lst` (listing).
2. `cpu/soc_sim.v` loads both hex files, resets the CPU and clocks it until it executes
   `halt`, hits an illegal instruction, or runs out of time.

## Options

```
./run.sh [-t] [-w] program.asm [+keys=file] [+max_cycles=N] [+seed=N] [+plain] [+fb=file]
```

| Option | Effect |
|---|---|
| `-t` | trace: print every executed instruction and what it changed |
| `-w` | write a waveform to `build/<program>.vcd` (open: `../wave.sh build/<program>.vcd`) |
| `+keys=file` | keyboard input from a file: every byte is one key press. Without it, what you type in the terminal goes to the program (arrow keys too, Ctrl+C stops it) |
| `+max_cycles=N` | stop after N cycles (default 200 000 000) |
| `+seed=N` | different random numbers |
| `+plain` | print the text screen without colors, one frame after another (and don't draw the pixel screen) |
| `+fb=file` | save the pixel screen as a PPM image every time it is shown (the file keeps the last frame) |
| `+fast` | only in the Verilator build: don't wait for the real clock at screen refreshes |

In VS Code (Ctrl+Shift+P → Tasks: Run Task) there are also "CPU: run program with trace"
and "CPU: run program and open waveform".

## Debugging a program

- **Assembler errors** show up as `file:line: error: ...` (and in VS Code's Problems panel).
- **Trace** (`-t`): every line is `PC: instruction  change`, e.g.
  `00000010: 01312000   r3 = 00000014`. Look the PC up in `build/<program>.lst`
  to see which source line it was.
- **Waveform** (`-w`): useful signals are `soc_sim.dut.core.pc`, `.instr`, and the registers
  `soc_sim.dut.core.regs.r1` … `.sp`, `.lr`.
- An **illegal instruction** (e.g. running past the end of the program) stops the CPU and
  prints its PC. Unmapped or misaligned memory accesses print a warning.

## Writing programs

Start from `programs/hello.asm` (functions, `.data`), `programs/screen.asm` (text screen,
timer) or `programs/pixels.asm` (pixel screen). Every program that calls functions should first set up the stack: `li sp, 0x00040000`.
Syntax, pseudo-instructions and directives: ISA.md section 6.

## Simulation speed

Icarus Verilog simulates about 43 000 CPU cycles per second, which is fine for
programs and simple text screen games (redraw only the cells that change). The pixel
demo needs about 12 million cycles, so with Icarus it takes minutes; the Verilator
build from `release.sh` (about 2–3 million cycles per second) or the playground runs it
in a few seconds. `tools/bench.sh` measures all three.
