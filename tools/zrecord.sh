#!/bin/sh
# One zero recording: what a binary does, in the five ways zero can ask.
#
# Usage: tools/zrecord.sh <binary> <source> <outdir>   (run from the repository root)
#
# The instrument zero has is the screen, so every part of this drives the editor
# and keeps what it drew (ZERO-PLAN.md 2):
#
#   screen/          zcases   102 keystroke cases, one record each
#   memline/         zmemline 16 big-buffer cases, one record each (below)
#   ref-excmds.txt   zexcmds  every Ex command name typed at `:`
#   ref-argv.txt     zargv    every command line the parser may see
#   ref-pty.txt      zpty     the window size and raw mode, on a real pty
#   ref-term.txt     ztermcheck the terminal table, whim's termcheck.py
#                                      asked with no file argument (see below)
#
# zmemline is the sixth part and zero phase 40 is why: every one of the
# 102 screen cases allocates exactly ONE data block, so nothing above ml_get() was
# ever asked a question the memline TREE answers -- measured, a binary with one
# line deleted from ml_find_line's pointer bookkeeping records all 102 of them byte
# for byte.  These cases build buffers of 200 to 25,000 lines instead.
#
# The six are independent and run at once.  A recording is the unit both the
# baselines and a phase's comparison are made of, so it is made here once and
# never twice in two shapes.
set -eu

bin=${1:?usage: zrecord.sh <binary> <source> <outdir>}
src=${2:?usage: zrecord.sh <binary> <source> <outdir>}
out=${3:?usage: zrecord.sh <binary> <source> <outdir>}

rm -rf "$out"
mkdir -p "$out"

tools/st.sh zcases "$bin" "$out/screen" >/dev/null &
p1=$!
tools/st.sh zmemline "$bin" "$out/memline" >/dev/null &
p6=$!
tools/st.sh zexcmds "$bin" "$src" "$out/ref-excmds.txt" >/dev/null &
p2=$!
tools/st.sh zargv "$bin" "$out/ref-argv.txt" >/dev/null &
p3=$!
tools/st.sh zpty "$bin" "$out/ref-pty.txt" >/dev/null &
p4=$!
# NOT termcheck, and the difference is one argument: it opens a file to
# put something on the screen, and from zero phase 5 a file argument is an unknown
# option, so every row would read `(none)`.  ztermcheck is that tool with
# its ask() replaced and nothing else, proven to record the same nineteen rows.
tools/st.sh ztermcheck "$bin" "$out/ref-term.txt" >/dev/null &
p5=$!
rc=0
wait $p1 || rc=1
wait $p2 || rc=1
wait $p3 || rc=1
wait $p4 || rc=1
wait $p5 || rc=1
wait $p6 || rc=1
if [ "$rc" != 0 ]; then
    echo "  record       a harness failed on $bin"
    exit 1
fi
for f in "$out/ref-excmds.txt" "$out/ref-argv.txt" "$out/ref-pty.txt" "$out/ref-term.txt"; do
    [ -s "$f" ] || { echo "  record       $f is empty"; exit 1; }
done
for d in "$out/screen" "$out/memline"; do
    [ -n "$(ls -A "$d" 2>/dev/null)" ] || { echo "  record       $d is empty"; exit 1; }
done
