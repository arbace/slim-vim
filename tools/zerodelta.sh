#!/bin/sh
# What zero-vim does differently from whim-vim, as a check rather than a report.
#
# Usage: tools/zerodelta.sh <binary> <source> --phase N
#        tools/zerodelta.sh --declared N
#
# tools/whimdelta.sh's rule against a different instrument.  --phase N records the
# binary with tools/zrecord.sh and hands the recording, the baselines and
# pipes/zero.delta to zcompare, which requires **exactly** the declared
# difference: every record that moved is declared, every declaration moved
# something, and nothing else differs at all.  --declared N prints what phase N
# itself declares, for a phase program that wants to assert its own list.
#
# THE BASELINES ARE WHIM-VIM'S: .reference/zero-baselines, recorded by zero phase 0
# from the committed whim-vim.c built with whim's own compile line.  So the delta is
# the difference from whim, not from slim; it is CUMULATIVE, as whim's is against
# slim -- the lines up to phase N are the whole difference from the input at N --
# and it starts empty.  Recording the baselines from the pipeline's INPUT is not
# the mistake CLAUDE.md warns about, which is a pipeline re-recording from its own
# current binary and then agreeing with itself by construction.  whim-vim.c is
# immutable to this pipeline; zero-vim is what gets compared.
#
# THE INSTRUMENT IS THE SCREEN (zero phase 3, ZERO-PLAN.md 2): keystrokes in on
# stdin, escape sequences out on stdout, and a screen per redraw rebuilt from them.
# The old file-based harnesses -- behaviour.py, exsweep.py -- are whim's and slim's
# and are untouched; they cannot be zero's, because the editor they measure is on
# its way to having no file to write and no stream to print on.
#
# A separate tool and not a mode of whimdelta.sh, because whimdelta.sh is hashed into
# every whim stage's key: a zero line there would re-run all of whim.  This file is
# named by nothing whim runs.
#
# "Six commands differ" is a check.  "Some commands differ" is not.
set -eu

if [ "${1:-}" = "--declared" ]; then
    tools/st.sh zcompare --declared pipes/zero.delta \
        "${2:?usage: zerodelta.sh --declared N}"
    exit 0
fi

bin=${1:?usage: zerodelta.sh <binary> <source> --phase N}
src=${2:?usage: zerodelta.sh <binary> <source> --phase N}
[ "${3:-}" = "--phase" ] || { echo "usage: zerodelta.sh <binary> <source> --phase N" >&2; exit 2; }
n=${4:?usage: zerodelta.sh <binary> <source> --phase N}

base=.reference/zero-baselines
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0

# The same source check whimdelta.sh runs beside its harnesses: no option global
# left without the row that initialises it (orphanopts).
tools/st.sh orphanopts "$src" > "$tmp/orphanopts" 2>&1 &
pid_o=$!

orphans() {
    if wait $pid_o; then cat "$tmp/orphanopts"; else cat "$tmp/orphanopts"; fail=1; fi
}

# Unlike whimdelta.sh, an absent baseline is a failure and not a note: zero phase 0
# records them before anything is compared, so a missing set means the pipeline is
# being run out of order.
if [ ! -d "$base/screen" ] || [ ! -f "$base/ref-excmds.txt" ] \
        || [ ! -f "$base/ref-argv.txt" ] || [ ! -f "$base/ref-term.txt" ] \
        || [ ! -f "$base/ref-pty.txt" ]; then
    orphans
    echo "  delta        no zero baselines at $base -- zero phase 0 records them"
    echo "               (a recording is screen/, ref-excmds.txt, ref-argv.txt,"
    echo "                ref-pty.txt and ref-term.txt: tools/zrecord.sh)"
    exit 1
fi

tools/zrecord.sh "$bin" "$src" "$tmp/now"
orphans

tools/st.sh zcompare "$base" "$tmp/now" pipes/zero.delta "$n" || fail=1
exit $fail
