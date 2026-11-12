#!/usr/bin/env bash
# build the ready-to-run release for Linux: a Verilator-compiled simulator
# plus the assembled demo programs, packed into dist/cpu-<version>-linux-x86_64.zip
#   ./release.sh v0.2.0
# needs: verilator, a C++ compiler, python3, zip
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
version=${1:?usage: release.sh <version>   e.g. release.sh v0.2.0}
name="cpu-$version-linux-x86_64"
work="$here/build/verilator"
dist="$here/dist"
pkg="$dist/$name"

programs=(fib hello keys screen pixels)
tests=(isa_test)

rm -rf "$work" "$pkg"
mkdir -p "$work" "$pkg/programs"

# the simulator: soc_sim.v is the same top level that run.sh uses with Icarus.
# -static, so it doesn't depend on the libraries of the machine it runs on.
# user_finish.cpp replaces Verilator's "- soc_sim.v:64: Verilog $finish" message
# (which shows a path from the build machine) with a silent version
cat > "$work/user_finish.cpp" <<'EOF'
#include "verilated.h"
void vl_finish(const char*, int, const char*) VL_MT_UNSAFE {
    Verilated::threadContextp()->gotFinish(true);
}
EOF
verilator --binary --timing -O3 -Wno-fatal -Wno-lint -Wno-style \
  -CFLAGS "-O2 -DVL_USER_FINISH" -LDFLAGS -static \
  -I"$here/cpu" --top-module soc_sim "$here/cpu/soc_sim.v" "$work/user_finish.cpp" \
  --Mdir "$work" -o cpu-sim
cp "$work/cpu-sim" "$pkg/cpu-sim"
strip "$pkg/cpu-sim"

# the programs
for p in "${programs[@]}"; do
  python3 "$here/tools/asm.py" "$here/programs/$p.asm" -o "$pkg/programs/$p"
done
for p in "${tests[@]}"; do
  python3 "$here/tools/asm.py" "$here/tests/$p.asm" -o "$pkg/programs/$p"
done
cp "$here/programs/keys.txt" "$pkg/programs/"

# newer Verilator versions print a report at the end unless +verilator+quiet is
# given, older ones (like 5.020) reject that option, so only use it if it works
quiet=""
# (run in its own bash, so a rejected option doesn't print "Aborted (core dumped)")
if bash -c '"$@" >/dev/null 2>&1; exit $?' _ "$pkg/cpu-sim" +verilator+quiet \
    "+text=$pkg/programs/fib.text.hex" "+data=$pkg/programs/fib.data.hex" 2>/dev/null; then
  quiet="+verilator+quiet "
fi

cat > "$pkg/run" <<'EOF'
#!/usr/bin/env bash
# Runs one of the programs on the CPU.
#   ./run fib
#   ./run screen +plain
#   ./run keys +keys=mytext.txt
here=$(cd "$(dirname "$0")" && pwd)
prog=${1:-}

if [[ -z $prog || ! -f $here/programs/$prog.text.hex ]]; then
  echo "usage: ./run <program> [+plain] [+fb=file.ppm] [+trace] [+keys=file] [+max_cycles=N] [+seed=N]"
  echo "programs: $(cd "$here/programs" && ls *.text.hex | sed 's/\.text\.hex$//' | tr '\n' ' ')"
  exit 1
fi
shift

extra=()
if [[ $prog == keys && " $* " != *" +keys="* ]]; then
  extra+=("+keys=$here/programs/keys.txt")   # some sample key presses
fi

exec "$here/cpu-sim" @QUIET@\
  "+text=$here/programs/$prog.text.hex" "+data=$here/programs/$prog.data.hex" \
  "${extra[@]}" "$@"
EOF
sed -i "s/@QUIET@/$quiet/" "$pkg/run"
chmod +x "$pkg/run"

cat > "$pkg/README.txt" <<EOF
My 32-bit CPU, $version, ready to run on Linux (x86_64)
=================================================

Nothing to install or build. Unzip, then:

    cd $name
    ./run fib          first 20 Fibonacci numbers
    ./run hello        Hello, World!
    ./run keys         echoes key presses in uppercase (from programs/keys.txt)
    ./run screen       a ball bouncing on the 40x25 text screen
    ./run pixels       a square bouncing on the 128x96 pixel screen
    ./run isa_test     89 checks for every instruction, prints PASS

The pixel screen is drawn in the terminal with 24-bit colors, two pixels per
character, so the window needs to be at least 128 x 49 characters.

Options:

    +plain             screen without colors (for terminals that don't do them),
                       the pixel screen is then only saved with +fb
    +fb=frame.ppm      save the pixel screen as an image (the last frame stays)
    +trace             print every instruction the CPU executes
    +keys=file.txt     your own key presses for the keys program
    +max_cycles=N      stop after N cycles
    +seed=N            other random numbers

What's in here:

    run                the launcher
    cpu-sim            the CPU with its RAM, screens and I/O, compiled with
                       Verilator into one self-contained executable
    programs/          the assembled programs: .text.hex (instructions),
                       .data.hex (starting RAM), .lst (listing with the source)

Works on any x86_64 Linux, the executable is statically linked.
Source code, the instruction set and how to write your own programs:
https://github.com/Merlin2LmmL/Verilog

cpu-sim contains the Verilator runtime library (LGPL-3.0 / Artistic-2.0),
https://www.veripool.org/verilator/
EOF

(cd "$dist" && rm -f "$name.zip" && zip -q -r "$name.zip" "$name")
echo "built $dist/$name.zip"
