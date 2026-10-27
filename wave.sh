#!/usr/bin/env bash
# Usage: ./wave.sh <thing.v | thing_tb.v | thing.vcd>   Opens GTKWave on thing.vcd.
# VS Code installed as a snap leaks snap library paths into its terminal, which
# crashes system programs like gtkwave ("undefined symbol: __libc_pthread_init").
# Strip every variable that points into /snap before launching.
target="${1:?usage: wave.sh <file.v|file.vcd>}"
[[ $target == *.vcd ]] || { b=${target%.v}; target="${b%_tb}.vcd"; }
[[ -f $target ]] || { echo "No such waveform: $target (run the simulation first)"; exit 1; }
for v in $(env | grep -E '/snap/|^SNAP' | cut -d= -f1); do
  [[ $v == PATH ]] && continue
  unset "$v"
done
export PATH=$(echo "$PATH" | tr ':' '\n' | grep -v '^/snap/' | paste -sd:)
nohup gtkwave "$target" >/dev/null 2>&1 &
