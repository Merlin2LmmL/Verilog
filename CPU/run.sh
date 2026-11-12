#!/usr/bin/env bash
# assemble a program and run it on the cpu
# ./run.sh [-t] [-w] program.asm [+keys=file] [+max_cycles=N] [+seed=N] [+plain]
#   -t  trace every instruction
#   -w  waveform -> build/<program>.vcd
# Without +keys=file, what you type goes to the program (tools/keyboard.sh).
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
plusargs=()
wave=0
while [[ ${1:-} == -* ]]; do
  case $1 in
    -t) plusargs+=(+trace) ;;
    -w) wave=1 ;;
    *)  echo "unknown option: $1"; exit 1 ;;
  esac
  shift
done
src=${1:?usage: run.sh [-t] [-w] program.asm [+plusargs]}
shift

name=$(basename "$src" .asm)
out="$here/build"
mkdir -p "$out"

python3 "$here/tools/asm.py" "$src" -o "$out/$name"
iverilog -g2012 -Wall -Wno-timescale -I "$here/cpu" -o "$out/soc.vvp" "$here/cpu/soc_sim.v"

plusargs+=("+text=$out/$name.text.hex" "+data=$out/$name.data.hex")
(( wave )) && plusargs+=("+vcd=$out/$name.vcd")
if [[ -t 0 && " $* " != *" +keys="* ]]; then
  exec "$here/tools/keyboard.sh" vvp -n "$out/soc.vvp" "${plusargs[@]}" "$@"
fi
exec vvp -n "$out/soc.vvp" "${plusargs[@]}" "$@"
