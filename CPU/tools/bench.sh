#!/usr/bin/env bash
# How many CPU cycles per second does each simulator manage?
#   tools/bench.sh                 # uses whatever is installed
#   ICARUS_CYCLES=100000 FAST_CYCLES=5000000 tools/bench.sh
#
# Runs tests/bench.asm (an endless loop, 11 cycles per pass) for a fixed number of
# cycles on:
#   - Icarus Verilog      (needs iverilog and vvp)
#   - Verilator           (needs build/verilator/cpu-sim, see release.sh)
#   - the JavaScript model from ui/emu.js (needs node)
# The start-up time of every simulator is measured with a 1-cycle run and subtracted.
set -euo pipefail

here=$(cd "$(dirname "$0")/.." && pwd)
out="$here/build"
mkdir -p "$out"
icarus_cycles=${ICARUS_CYCLES:-200000}
fast_cycles=${FAST_CYCLES:-20000000}

python3 "$here/tools/asm.py" "$here/tests/bench.asm" -o "$out/bench" > /dev/null
args=("+text=$out/bench.text.hex" "+data=$out/bench.data.hex")

# seconds the command takes
now() { date +%s.%N; }
timeit() { local t0 t1; t0=$(now); "$@" > /dev/null 2>&1 || true; t1=$(now); awk -v a="$t0" -v b="$t1" 'BEGIN { print b - a }'; }

report() {   # name cycles seconds startup
  awk -v n="$1" -v c="$2" -v s="$3" -v st="$4" 'BEGIN {
    net = s - st; if (net < 0.001) net = 0.001
    printf "%-22s %12d cycles  %7.2f s  (start-up %.2f s)  ->  %12.0f cycles/s\n", n, c, net, st, c / net }'
}

echo "benchmark: tests/bench.asm (mul, div, load, store, branch), $(nproc) CPU threads"
echo

if command -v iverilog > /dev/null && command -v vvp > /dev/null; then
  iverilog -g2012 -Wno-timescale -I "$here/cpu" -o "$out/soc.vvp" "$here/cpu/soc_sim.v"
  startup=$(timeit vvp -n "$out/soc.vvp" "${args[@]}" +max_cycles=1)
  secs=$(timeit vvp -n "$out/soc.vvp" "${args[@]}" +max_cycles="$icarus_cycles")
  report "Icarus Verilog" "$icarus_cycles" "$secs" "$startup"
else
  echo "Icarus Verilog         not installed, skipped"
fi

sim=${CPU_SIM:-$out/verilator/cpu-sim}
if [[ -x $sim ]]; then
  # newer Verilator versions print a report unless +verilator+quiet is given, older
  # ones (like 5.020) abort on that option, so only use it if it works
  quiet=()
  if bash -c '"$@" > /dev/null 2>&1' _ "$sim" +verilator+quiet "${args[@]}" +max_cycles=1 2>/dev/null; then
    quiet=(+verilator+quiet)
  fi
  startup=$(timeit "$sim" "${quiet[@]}" "${args[@]}" +max_cycles=1)
  secs=$(timeit "$sim" "${quiet[@]}" "${args[@]}" +max_cycles="$fast_cycles")
  report "Verilator" "$fast_cycles" "$secs" "$startup"
else
  echo "Verilator              $sim not found, skipped (build it with release.sh)"
fi

if command -v node > /dev/null; then
  js="
    const E = require('$here/ui/emu.js'), fs = require('fs');
    const rd = (f) => E.parseHex(fs.readFileSync(f, 'utf8')).words.map((w) => w.value);
    const m = new E.Machine();
    m.loadProgram(rd('$out/bench.text.hex'), rd('$out/bench.data.hex'));
    const n = Number(process.argv[1]);
    for (let i = 0; i < n && !m.halted; i++) m.step();
  "
  startup=$(timeit node -e "$js" 1)
  secs=$(timeit node -e "$js" "$fast_cycles")
  report "JavaScript (ui/emu.js)" "$fast_cycles" "$secs" "$startup"
else
  echo "JavaScript             node not installed, skipped"
fi
