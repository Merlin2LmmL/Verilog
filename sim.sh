#!/usr/bin/env bash
# Usage: ./sim.sh [file.v | folder]   (default: current folder)
#   thing_tb.v   -> run that testbench
#   thing.v      -> run thing_tb.v next to it
#   folder       -> run every *_tb.v in it and print a summary
# A testbench `include`s the design it tests, so only the testbench is compiled.
set -uo pipefail

command -v iverilog >/dev/null || { echo "iverilog missing: sudo apt install iverilog gtkwave"; exit 1; }

run_tb() {
  local tb dir name top out
  tb=$(realpath "$1"); dir=$(dirname "$tb"); name=$(basename "$tb" .v)
  top=$(grep -m1 -oP '^\s*module\s+\K\w+' "$tb")
  mkdir -p "$dir/build"
  echo "--- $name ---"
  iverilog -g2012 -Wall -Wno-timescale -I "$dir" -s "$top" -o "$dir/build/$name.vvp" "$tb" || return 1
  out=$(cd "$dir" && vvp "build/$name.vvp")
  echo "$out" | grep -v '^VCD info'
  grep -q '^PASS' <<<"$out"
}

target="${1:-.}"
if [[ -d $target ]]; then
  mapfile -t tbs < <(find "$target" -maxdepth 1 -name '*_tb.v' | sort)
  (( ${#tbs[@]} )) || { echo "No *_tb.v testbench in $target"; exit 1; }
  pass=0; failed=()
  for tb in "${tbs[@]}"; do
    if run_tb "$tb"; then pass=$((pass+1)); else failed+=("$(basename "$tb" _tb.v)"); fi
  done
  echo "=== $pass/${#tbs[@]} passed ${failed[*]:+- failed: ${failed[*]}} ==="
  (( ${#failed[@]} == 0 ))
else
  [[ $target == *_tb.v ]] || target="${target%.v}_tb.v"
  [[ -f $target ]] || { echo "No testbench: $target"; exit 1; }
  run_tb "$target"
fi
