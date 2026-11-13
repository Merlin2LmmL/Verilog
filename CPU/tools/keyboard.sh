#!/usr/bin/env bash
# Live keyboard for the simulation: runs the command (the simulator) and sends every key
# you press to the CPU. The keys go into a temporary file that the simulator gets as
# +keys=<file> and keeps reading while the program runs (see cpu/io.v).
#   tools/keyboard.sh vvp -n build/soc.vvp +text=... +data=...
# Arrow keys become the codes 0x80 up, 0x81 down, 0x82 left, 0x83 right, Enter is 10
# and Backspace is 8 (ISA.md section 7). Ctrl+C stops the program.
set -u

keys=$(mktemp "${TMPDIR:-/tmp}/cpu-keys.XXXXXX")
saved=$(stty -g)
# keys arrive one by one without Enter and aren't printed; Ctrl+C still works
stty -icanon -echo min 1

"$@" "+keys=$keys" < /dev/null &
pid=$!


# Ctrl+C only sets a flag: the terminal must be restored after `read` has returned,
# because `read -s` puts back its own (raw) terminal settings when it gets interrupted
stop=0
trap 'stop=1' INT TERM

while (( !stop )) && kill -0 "$pid" 2> /dev/null; do
  IFS= read -rsn1 -d '' -t 0.05 c || continue
  case $c in
    $'\e')                                   # arrow keys are ESC [ A ... ESC [ D
      rest=''
      IFS= read -rsn2 -t 0.05 rest
      case $rest in
        '[A') c=$'\x80' ;;
        '[B') c=$'\x81' ;;
        '[D') c=$'\x82' ;;
        '[C') c=$'\x83' ;;
        *)    c+=$rest ;;
      esac ;;
    $'\x7f') c=$'\b' ;;                      # Backspace
  esac
  printf '%s' "$c" >> "$keys"
done

if (( stop )); then
  kill "$pid" 2> /dev/null
  echo
fi
wait "$pid"
status=$?
stty "$saved"
rm -f "$keys"
(( stop )) && exit 130
exit $status
