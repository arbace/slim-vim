#!/bin/sh
# Zero phase 3 -- the instrument becomes the screen.  See ZERO-GOAL.md, ZERO-PLAN.md.
#
# Usage: pipes/zero3.sh <work-dir>       (run from the repository root)
#
# NO SOURCE CHANGE AT ALL: r3's zero-vim.c is r2's, byte for byte, and this phase
# asserts it.  What changes is how every later phase is measured.
#
# Zero's editor is on its way to having no file to write, no file to read and no
# stream to print on, so `tools/behaviour.py` -- which ends every case with
# `+w! <file>` and reads the file back -- and `tools/exsweep.py` -- which runs a
# command on a file and records the exit status -- stop being instruments the
# moment the phases they are meant to measure land.  A whole-program phase is
# right here because there is no source edit for a sweep to follow.
#
# The instrument they are replaced with is `tools/zrecord.sh`: keystrokes in on
# stdin, escape sequences out on stdout, and a screen per redraw rebuilt from them
# (ZERO-PLAN.md 2).  Five parts -- 102 keystroke cases, every Ex command typed at
# `:`, every command line the parser may see, four pty scenarios for what only a
# terminal shows, and whim's own terminal table.
#
# WHAT THIS PHASE PROVES, in order, each depending on the one before:
#
#   1. the tree is untouched: zero-vim.c is what the phase was handed;
#   2. it builds with the boundary's flags, and is still absolutely static;
#   3. THE INSTRUMENT IS DETERMINISTIC: three recordings of that binary, byte for
#      byte identical, digests included;
#   4. THE INSTRUMENT CAN FAIL: a copy of the source with do_addsub() returning
#      FAIL -- CLAUDE.md's canonical break -- must move EXACTLY the eleven cases
#      that increment or decrement, and no others.  A corpus that cannot fail is
#      not evidence;
#   5. the declared delta holds: tools/zerodelta.sh --phase 3 against
#      .reference/zero-baselines, which zero phase 0 records from whim-vim.  Those
#      baselines are the INPUT's behaviour, so the delta is cumulative -- phase 2
#      removed the two "not to a terminal" warnings, and `stderr-moved` is that,
#      declared once and checked at every phase after it;
#   6. the old instrument still reaches whim's baselines: tools/whimdelta.sh on the
#      same binary against .reference/baselines, which is the only bridge between
#      the two pipelines' recordings and is kept for exactly that.
set -eu

work=${1:?usage: zero3.sh <work-dir>}
f="$work/zero-vim.c"
base=.reference/zero-baselines

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# --- 1. the tree is untouched ----------------------------------------------
before=$(sha256sum "$f" | cut -c1-64)

# --- 2. the build, with the boundary's flags -------------------------------
make -C "$work" clean >/dev/null 2>&1 || true
if ! make -C "$work" >/dev/null 2>&1; then
    echo "  build        FAILED -- rerun by hand: make -C $work"
    exit 1
fi
bin="$work/zero-vim"
type=$(readelf -h "$bin" | awk -F: '$1 ~ /^ *Type$/ { sub(/^ +/, "", $2); split($2, t, " "); print t[1] }')
interp=$(readelf -l "$bin" | grep -c 'INTERP' || true)
dynamic=$(readelf -d "$bin" | grep -c '^There is no dynamic section in this file\.$' || true)
relocs=$(readelf -r "$bin" | grep -c '^There are no relocations in this file\.$' || true)
if [ "$type" != EXEC ] || [ "$interp" != 0 ] || [ "$dynamic" != 1 ] || [ "$relocs" != 1 ]; then
    echo "  static       NOT absolutely static: type $type, INTERP $interp, no-dynamic $dynamic, no-relocations $relocs"
    exit 1
fi
echo "  build        ok, $(stat -c%s "$bin") bytes: EXEC, no INTERP, no dynamic section, 0 relocations"

# --- 3. the instrument is deterministic ------------------------------------
# Three recordings of one binary.  The stream digests are inside them, so this is
# stronger than "the screens agree": a redraw that draws the same result
# differently would move the sha and fail here.
for r in 1 2 3; do
    tools/zrecord.sh "$bin" "$f" "$tmp/run$r"
    if [ "$r" != 1 ] && ! diff -r "$tmp/run1" "$tmp/run$r" >/dev/null; then
        echo "  instrument   run $r differs from run 1 -- not deterministic, not an instrument:"
        diff -rq "$tmp/run1" "$tmp/run$r" | head -10 | sed 's/^/               /'
        exit 1
    fi
done
cases=$(ls "$tmp/run1/screen" | grep -c '')
cmds=$(grep -c '^=== ' "$tmp/run1/ref-excmds.txt")
argvs=$(grep -c '^=== ' "$tmp/run1/ref-argv.txt")
ptys=$(grep -c '^=== ' "$tmp/run1/ref-pty.txt")
echo "  instrument   $cases cases, $cmds commands, $argvs command lines, $ptys pty scenarios: 3 identical runs, digests included"

# --- 4. the instrument can fail --------------------------------------------
# CLAUDE.md's canonical break: do_addsub() returns FAIL, so CTRL-A and CTRL-X do
# nothing.  Exactly the cases that increment or decrement must move.  The patched
# copy lives in a scratch directory and the work tree never sees it.
expected="decr_dec decr_hex incr_alpha incr_bin incr_count incr_dec incr_hex incr_midword incr_oct incr_unsigned mb_incr"
mkdir -p "$tmp/broken"
python3 - "$f" "$tmp/broken/zero-vim.c" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
t = open(src, errors='surrogateescape').read()
head = '\ndo_addsub('
i = t.index(head)
j = t.index('{\n', i) + 2
open(dst, 'w', errors='surrogateescape').write(t[:j] + '    return FAIL;\n' + t[j:])
PY
cp "$work/Makefile" "$tmp/broken/Makefile"
if ! make -C "$tmp/broken" >/dev/null 2>&1; then
    echo "  ablefail     the patched copy did not build -- the break is wrong, not the corpus"
    exit 1
fi
tools/st.sh zcases "$tmp/broken/zero-vim" "$tmp/broken-screen" >/dev/null
moved=$(diff -rq "$tmp/run1/screen" "$tmp/broken-screen" 2>/dev/null \
        | grep -E '^(Files|Only in)' | sed 's/^Only in [^:]*: //; s/ and .*//; s/.*screen\///' \
        | sort -u | tr '\n' ' ')
if [ "$moved" != "$expected " ]; then
    echo "  ablefail     a broken do_addsub() moved a different set of cases:"
    echo "                 got      ${moved:-(none)}"
    echo "                 expected $expected"
    echo "               A corpus that cannot fail is not evidence, and one that"
    echo "               fails differently is not this corpus."
    exit 1
fi
echo "  ablefail     do_addsub() returning FAIL moves exactly 11 of $cases cases, and nothing else"

# --- 5. the declared delta, against the input's own behaviour ---------------
tools/zerodelta.sh "$bin" "$f" --phase 3

# --- 6. the bridge to whim's baselines -------------------------------------
# The file-based harnesses are kept, untouched, because they are whim's and slim's
# and because they are the only recording the two pipelines share.  Nothing zero
# does from here reads them -- but while the editor can still write a file, this
# says in one line that the frozen whim delta holds of the binary zero has now.
whim_last=$(. tools/pipeline.sh whim && echo "${PHASE_LIST##* }")
if [ -d .reference/baselines/behaviour ]; then
    if ! tools/whimdelta.sh "$bin" "$f" --phase "$whim_last" > "$tmp/whimdelta" 2>&1; then
        cat "$tmp/whimdelta"
        echo "  bridge       zero-vim does NOT show whim's declared delta to phase $whim_last"
        exit 1
    fi
    held=$(sed -n 's/^ *delta  *exactly as declared: //p' "$tmp/whimdelta")
    printf '  %-12s %s commands and %s cases against slim-vim'"'"'s baselines, exactly whim'"'"'s declared delta to phase %s\n' \
        "bridge" "$(printf '%s\n' "${held%%;*}" | wc -w)" "$(printf '%s\n' "${held#*cases:}" | wc -w)" "$whim_last"
else
    echo "  bridge       no slim baselines at .reference/baselines -- whim's delta not rechecked"
fi

# --- 1, concluded: nothing in the tree moved -------------------------------
after=$(sha256sum "$f" | cut -c1-64)
if [ "$before" != "$after" ]; then
    echo "  source       zero-vim.c was modified by a phase that must not modify it"
    exit 1
fi
echo "  source       zero-vim.c unchanged, $(grep -c '' "$f") lines: r3 is r2's tree, and only the instrument moved"
