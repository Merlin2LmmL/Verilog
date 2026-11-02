#!/usr/bin/env bash
# Usage: ./wave.sh <thing.v | thing_tb.v | thing.vcd>   Opens GTKWave on thing.vcd.
#        ./wave.sh <program.asm>                     Opens CPU/build/program.vcd (from CPU/run.sh -w).
# VS Code installed as a snap leaks snap library paths into its terminal, which
# crashes system programs like gtkwave ("undefined symbol: __libc_pthread_init").
# Strip every variable that points into /snap before launching.
target="${1:?usage: wave.sh <file.v|file.vcd|program.asm>}"
case $target in
  *.vcd) ;;
  *.asm) target="$(dirname "$(realpath "$0")")/CPU/build/$(basename "$target" .asm).vcd" ;;
  *)     b=${target%.v}; target="${b%_tb}.vcd" ;;
esac
[[ -f $target ]] || { echo "No such waveform: $target (run the simulation first)"; exit 1; }
for v in $(env | grep -E '/snap/|^SNAP' | cut -d= -f1); do
  [[ $v == PATH ]] && continue
  unset "$v"
done
export PATH=$(echo "$PATH" | tr ':' '\n' | grep -v '^/snap/' | paste -sd:)
nohup gtkwave "$target" >/dev/null 2>&1 &
