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

## CPU Playground

The playground is a web page for exploring the CPU without installing anything. You
enter machine code as hex, and the page shows what each instruction does inside the
CPU. Programs can be run in one go or one instruction at a time.

**Opening it**

The playground is live at **https://merlin2lmml.github.io/Verilog/**.

To run it locally, open `CPU/ui/index.html` in any current browser. No build step and no server are
needed. If you prefer to serve it, run `python3 -m http.server` inside `CPU/ui` and
open `http://localhost:8000`.

**Entering a program**

- Type or paste the program into the *Program (hex)* field, one 32-bit instruction
  per line, for example `01312000` for `add r3, r1, r2`. A `0x` prefix is optional.
- Everything after `;`, `#` or `//` is a comment.
- The *Instructions* table below the editor shows the address, the hex word and the
  disassembled instruction. Invalid hex is reported under the editor.
- Initial contents of data memory can be entered in the optional *Data memory* field,
  as hex words starting at address 0.
- The *Example* menu loads ready-made programs: a short calculation, a loop, Fibonacci,
  Hello World and a program that uses every instruction type.

You can generate the hex for your own assembly programs with the assembler
(`CPU/tools/asm.py`); the `.text.hex` and `.data.hex` files it writes use the same
format as the two fields.

**Reading the display**

The display always shows the next instruction, the one at the current PC, before it
runs.

- The instruction is split into its fields (opcode, A, B, C or immediate), colored by
  their role.
- A sentence under it describes the operation with the actual values, for example
  `84 = 12 * 7`.
- The data path diagram shows the 16 registers, the ALU, the data memory, the
  write-back multiplexer and the program counter. The path of the current instruction
  is highlighted:

| Color | Meaning |
|---|---|
| Blue | register read port 1 (field B), for example the first ALU operand |
| Orange | register read port 2 (field C, or field A for stores and branches) |
| Purple | immediate value |
| Green | result, memory address and write-back to the destination register |

- Branches use the comparator and show whether they are taken. Loads and stores
  show the address, the byte lane and the data going in or out of memory.
- *Console output* shows what the program prints. *Data memory* lists every word the
  program has written, with the most recent write highlighted.

**Running it**

| Control | Key | Action |
|---|---|---|
| Step | `S` | execute one instruction |
| Run | `R` | run until `halt`; press again to pause |
| Reset | `Esc` | return to the start with the program still loaded |
| Speed menu | | 1, 4 or 20 instructions per second, or as fast as possible |

The page stops by itself at `halt` and at an illegal instruction, and in the
"as fast as possible" mode also after 20 million cycles. The program is kept in the browser's local storage, so it is still there after
a reload.

**Accuracy and limits**

The CPU model in `CPU/ui/emu.js` follows the Verilog in `CPU/cpu/`. It gives the same
results and cycle counts as the Icarus simulation for `isa_test.asm`, `fib.asm` and
`hello.asm`. The text screen and keyboard are not implemented in the playground yet;
writes to the screen are ignored and the keyboard reports no key.

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
  ui/                               CPU Playground: hex editor + data path diagram in the browser
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

The Basics, Vectors and Modules solutions have a testbench each, and 22 of the 24 pass.
The two that fail, `Vectors/reverse_vec.v` and `Modules/by_pos.v`, are known bugs in
the solutions. The Procedures and More Features solutions do not have testbenches yet.

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
Verilator compiles the CPU to C++ and is much faster, so `CPU/release.sh` uses it to
build the ready-to-run Linux package.

## Adding a new HDLBits problem

1. Save the solution as `name.v` and keep the module name HDLBits asks for
   (usually `top_module`).
2. Copy any `*_tb.v` to `name_tb.v`, then change the `` `include ``, the ports and
   the expected outputs.
3. Run it with `./sim.sh` or Ctrl+Shift+B.

## Questions or ideas?

If you find a bug or have an idea for the CPU, open an issue. I'm still learning,
so I'm happy about any feedback.
