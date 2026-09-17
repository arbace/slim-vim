#!/bin/sh
# One zero recording: what a binary does, in the five ways zero can ask.
#
# Usage: tools/zrecord.sh <binary> <source> <outdir>   (run from the repository root)
#
# The instrument zero has is the screen, so every part of this drives the editor
# and keeps what it drew (ZERO-PLAN.md 2):
#
#   screen/          tools/zcases.py   102 keystroke cases, one record each
#   ref-excmds.txt   tools/zexcmds.py  every Ex command name typed at `:`
#   ref-argv.txt     tools/zargv.py    every command line the parser may see
#   ref-pty.txt      tools/zpty.py     the window size and raw mode, on a real pty
#   ref-term.txt     tools/termcheck.py  the terminal table, unchanged from whim
#
# The five are independent and run at once.  A recording is the unit both the
# baselines and a phase's comparison are made of, so it is made here once and
# never twice in two shapes.
set -eu

bin=${1:?usage: zrecord.sh <binary> <source> <outdir>}
src=${2:?usage: zrecord.sh <binary> <source> <outdir>}
out=${3:?usage: zrecord.sh <binary> <source> <outdir>}

rm -rf "$out"
mkdir -p "$out"

python3 tools/zcases.py "$bin" "$out/screen" >/dev/null &
p1=$!
python3 tools/zexcmds.py "$bin" "$src" "$out/ref-excmds.txt" >/dev/null &
p2=$!
python3 tools/zargv.py "$bin" "$out/ref-argv.txt" >/dev/null &
p3=$!
python3 tools/zpty.py "$bin" "$out/ref-pty.txt" >/dev/null &
p4=$!
python3 tools/termcheck.py "$bin" "$out/ref-term.txt" >/dev/null &
p5=$!
rc=0
wait $p1 || rc=1
wait $p2 || rc=1
wait $p3 || rc=1
wait $p4 || rc=1
wait $p5 || rc=1
if [ "$rc" != 0 ]; then
    echo "  record       a harness failed on $bin"
    exit 1
fi
for f in "$out/ref-excmds.txt" "$out/ref-argv.txt" "$out/ref-pty.txt" "$out/ref-term.txt"; do
    [ -s "$f" ] || { echo "  record       $f is empty"; exit 1; }
done
[ -n "$(ls -A "$out/screen" 2>/dev/null)" ] || { echo "  record       $out/screen is empty"; exit 1; }
