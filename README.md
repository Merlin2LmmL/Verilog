# Verilog playground

Setup once: `sudo apt install iverilog gtkwave`

## Layout

```
HDLbits Problemsets/
  Basics/   and.v  and_tb.v  gates.v  gates_tb.v  ...
  Modules/  add32.v  add32_tb.v  ...
  Vectors/  vec.v  vec_tb.v  ...
sim.sh      run testbenches
wave.sh     open a waveform in GTKWave
.vscode/    Ctrl+Shift+B task, linter settings
```

Each solution `thing.v` has a self-checking testbench `thing_tb.v` next to it.
The testbench does `` `include "thing.v" `` so it is self-contained (this is why several
files can all define `top_module`). It prints `PASS: ...` or `FAIL ...` lines and writes
`thing.vcd`. Compiled output goes to a `build/` folder next to the files.

## Running

- **In VS Code:** open `thing.v` or `thing_tb.v` and press **Ctrl+Shift+B**.
- **Terminal:** `./sim.sh "HDLbits Problemsets/Vectors/vec.v"` runs one;
  `./sim.sh "HDLbits Problemsets/Vectors"` runs every testbench in the folder and prints a summary.
- **Waveform:** Ctrl+Shift+P -> Tasks: Run Task -> "Verilog: open waveform (gtkwave)",
  or `./wave.sh path/to/thing.v`. Use `wave.sh` rather than plain `gtkwave` in VS Code's
  terminal: the snap-installed VS Code breaks `gtkwave` there.

## Adding a new problem

1. Write `name.v` (keep the module name HDLBits asks for, e.g. `top_module`).
2. Copy any `*_tb.v` as `name_tb.v`, change the `` `include ``, the module name, the ports and the check.

Later: a `cpu/` folder with alu.v, pc.v, regfile.v, ... and a `cpu_tb.v`. Multi-file designs
can `` `include `` each of their parts from the testbench the same way.
