# Verilog: learning HDL and building my own CPU

This repo is where I learn Verilog. It started with the exercises on
[HDLBits](https://hdlbits.01xz.net) and is slowly turning into my own 32-bit CPU,
with its own instruction set, an assembler and a few programs that run on it in
simulation. If you want to see how far I've gotten, or run the CPU yourself,
this README should get you there.

Some background: my first CPU was a 16-bit design I clicked together in a GUI
logic simulator, with 8 registers and a handful of flags. It worked, but writing
programs for it was painful. This one is meant to be big enough for real programs
and, eventually, small games.

## Where things stand

**HDLBits**

- [x] Basics
- [x] Vectors
- [x] Modules
- [x] Procedures
- [x] More Verilog Features
- [ ] Combinational Logic
- [ ] Sequential Logic

Basics, Vectors and Modules have a testbench for every solution, and 22 of the 24
pass. The other two (`Vectors/reverse_vec.v` and `Modules/by_pos.v`) are real bugs
in my solutions that I still need to fix.

**The CPU**

- [x] Instruction set written down in [CPU/ISA.md](CPU/ISA.md)
- [x] Single-cycle CPU in Verilog
- [x] Assembler
- [x] Test program for every instruction (89 checks, all passing)
- [x] Example programs: Fibonacci, Hello World, keyboard input and a bouncing ball
- [ ] A snake game on the text screen
- [ ] A faster simulator (Verilator), because games will need it
- [ ] Some day: a small C compiler for it

## What you need

I work on Ubuntu, but any Linux with these should do:

- **Icarus Verilog** (`iverilog` and `vvp`) to compile and simulate the Verilog
- **Python 3** for the assembler
- **GTKWave** if you want to look at waveforms

```bash
sudo apt install iverilog gtkwave python3
git clone https://github.com/Merlin2LmmL/Verilog.git
cd Verilog
```

VS Code is optional. The repo has build tasks and linter settings for the
Verilog-HDL extension (`mshr-h.veriloghdl`), and VS Code suggests it when you open
the folder.

## What's in here

```
HDLbits Problemsets/
  Basics/  Vectors/  Modules/       solutions, each with a testbench
  Procedures/  More Features/       solutions (no testbenches yet)
CPU/
  ISA.md                            the instruction set
  run.sh                            assemble a program and run it on the CPU
  cpu/                              the CPU and its peripherals in Verilog
  tools/asm.py                      the assembler
  programs/                         example programs
  tests/isa_test.asm                checks every instruction
sim.sh                              run testbenches (or a CPU program)
wave.sh                             open a waveform in GTKWave
```

## Running the HDLBits testbenches

Every solution `thing.v` sits next to a testbench `thing_tb.v`. The testbench
includes the solution, feeds it inputs, compares the outputs with what they should
be and prints `PASS` or `FAIL`. It also writes a waveform, `thing.vcd`.

Run one problem, or a whole folder at once:

```bash
./sim.sh "HDLbits Problemsets/Vectors/vec.v"
./sim.sh "HDLbits Problemsets/Vectors"
```

The folder version ends with a summary like `=== 8/9 passed - failed: reverse_vec ===`.

To look at the signals in GTKWave:

```bash
./wave.sh "HDLbits Problemsets/Vectors/vec.v"
```

If your VS Code is installed as a snap, use `wave.sh` instead of calling `gtkwave`
directly in its terminal. The snap leaks some library paths that make GTKWave
crash, and `wave.sh` removes them first.

## Running programs on the CPU

Everything goes through `CPU/run.sh`. It assembles the program, compiles the CPU
with Icarus and runs it until the program halts:

```bash
cd CPU
./run.sh programs/fib.asm                          # the first 20 Fibonacci numbers
./run.sh programs/hello.asm                        # Hello, World!
./run.sh programs/keys.asm +keys=programs/keys.txt # echoes the key file in uppercase
./run.sh programs/screen.asm                       # a ball bouncing on the text screen
./run.sh tests/isa_test.asm                        # tests every instruction
```

There is no real keyboard yet. `keys.asm` reads its key presses from a text file,
so put whatever you like in `programs/keys.txt`.

Some options that help when something doesn't work:

| Option | What it does |
|---|---|
| `-t` | prints every instruction the CPU executes and what it changed |
| `-w` | saves a waveform to `CPU/build/<program>.vcd` |
| `+keys=file` | key presses for the program, one per byte of the file |
| `+max_cycles=N` | stops after N cycles, in case your program never halts |
| `+seed=N` | other random numbers |
| `+plain` | draws the text screen without colors |

With `-t`, every line shows the address, the instruction in hex and what changed:

```
00000000: 1fa0ffff   r10 = ffff0000
00000004: 11100000   r1 = 00000000
00000008: 11200001   r2 = 00000001
```

The assembler also writes `CPU/build/<program>.lst`, which shows which source line
ended up at which address. That makes the trace a lot easier to follow.

## Running things from VS Code

- Open a `.v`, `_tb.v` or `.asm` file and press **Ctrl+Shift+B**. That runs the
  testbench or assembles and runs the program.
- **Ctrl+Shift+P → Tasks: Run Task** has a few more:
  - *Verilog: open waveform (gtkwave)*
  - *CPU: run program with trace*
  - *CPU: run program and open waveform*

## Writing your own program

Here's a small program that prints the squares from 1 to 10:

```asm
        .equ IO,        0xFFFF0000
        .equ PRINT_INT, 0x04

        .text
        li   s0, IO
        li   r1, 1                  ; n = 1
        li   r2, 10                 ; stop after 10
loop:   mul  r3, r1, r1             ; r3 = n * n
        st   r3, [s0+PRINT_INT]     ; print it
        li   r4, ' '
        st   r4, [s0]               ; and a space
        addi r1, r1, 1              ; n++
        ble  r1, r2, loop           ; again while n <= 10
        halt
```

Save it as `CPU/squares.asm` and run `./run.sh squares.asm`:

```
1 4 9 16 25 36 49 64 81 100
--- halted after 64 cycles ---
```

`programs/hello.asm` is a good next example: it uses data memory and a function call.
If your program calls functions, set up the stack first with `li sp, 0x00040000`.
All instructions, pseudo-instructions and directives are in
[CPU/ISA.md](CPU/ISA.md).

## The CPU in short

- **32 bit** with a **Harvard architecture**: the program and the data live in
  separate memories.
- **16 registers.** `r0` is always 0, `r14` is the stack pointer (`sp`) and `r15`
  holds the return address (`lr`).
- **Every instruction is 32 bits with an 8-bit opcode.** The fields line up with hex
  digits, so `0x01312000` reads as `add r3, r1, r2`, even in a waveform.
- **No flags.** Branches compare two registers directly: `blt r1, r2, loop`.
- **MUL, DIV and MOD in hardware.** Dividing by zero gives a fixed result instead of
  crashing.
- **Single-cycle**: every instruction finishes in one clock cycle.
- **Peripherals are memory addresses.** Writing a character to the screen is a
  normal store.

| Address | What's there |
|---|---|
| `0x00000000`–`0x0003FFFF` | RAM (256 KB) |
| `0xFFFE0000` | text screen, 40×25 cells with 16 colors |
| `0xFFFF0000` | console output |
| `0xFFFF0004` | print a number |
| `0xFFFF0008` / `0xFFFF000C` | keyboard status / key |
| `0xFFFF0010` | timer |
| `0xFFFF0014` | random number |
| `0xFFFF0018` | show the screen |
| `0xFFFF001C` | LEDs |

More about the hardware is in [CPU/README.md](CPU/README.md) and
[CPU/cpu/README.md](CPU/cpu/README.md).

## How fast is it?

Icarus simulates about 60,000 CPU cycles per second. That's plenty for Fibonacci
(165 cycles), but a game that redraws the whole screen every frame will feel slow.
That's why Verilator is on the list.

## Adding a new HDLBits problem

1. Save the solution as `name.v` and keep the module name HDLBits asks for
   (usually `top_module`).
2. Copy any `*_tb.v` to `name_tb.v`, then change the `` `include ``, the ports and
   the expected outputs.
3. Run it with `./sim.sh` or Ctrl+Shift+B.

## Questions or ideas?

If you find a bug or have an idea for the CPU, open an issue. I'm still learning,
so I'm happy about any feedback.
