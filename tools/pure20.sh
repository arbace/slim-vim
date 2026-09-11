#!/bin/sh
# Pure phase 20 -- six options that no longer decide anything.  See PURE-GOAL.md.
#
# Usage: tools/pure20.sh <work-dir>      (run from the repository root)
#
# 'path' and 'suffixesadd' have been inert since the file finder went, 'tags'
# and 'tagcase' since the tag stack, 'autoread' since the timestamp poll, and
# 'swapfile' since the swap file.  All six are still here, because a row is what
# initialises its global and tools/dropoptions.py refuses to leave one dangling
# -- Phase 14's trap, which this phase finally clears rather than works around.
#
# THE ORDER IS THE PHASE, and it is forced rather than chosen:
#
#   1. the three readers that are not plumbing (tools/noinertopts.py)
#   2. the rows, with --local (tools/dropoptions.py)
#   3. SWEEP -- which is what removes did_set_tagcase() and did_set_swapfile(),
#      the option callbacks, reachable only from the rows
#   4. the buffer fields and their plumbing (tools/droplocal.py)
#   5. sweep again
#
# Steps 3 and 4 cannot swap.  The callbacks read the buffer field, so removing
# the field first stops the file compiling; the sweep works by reading gcc's
# warnings, so a file that does not compile is a file the sweep cannot act on,
# and the callbacks would stay for ever.
#
# THE DELTA: none.  All six options report E518 instead of a value that decided
# nothing.
set -eu

work=${1:?usage: pure17.sh <work-dir>}
f="$work/pure-vim.c"

before_lines=$(grep -c '' "$f")
gcc -c -O0 -o "$work/sym.o" "$f" 2>/dev/null
before_syms=$(nm -u "$work/sym.o" | wc -l)

# --- cut the entry points -------------------------------------------------
python3 tools/noinertopts.py "$f"
python3 tools/dropoptions.py "$f" --local \
    path suffixesadd tags tagcase autoread swapfile

sweep() {
sweep=0
while :; do
    sweep=$((sweep + 1))
    was=$(sha256sum "$f" | cut -d' ' -f1)
    a=$(python3 tools/deadsweep.py "$f" | tail -1)
    c=$(python3 tools/deadprotos.py "$f" | tail -1)
    b=$(python3 tools/typereach.py "$f" --delete | tail -1)
    d=$(python3 tools/funcreach.py "$f" --delete | tail -1)
    echo "  sweep $sweep      $a; $c; $b; $d"
    [ "$(sha256sum "$f" | cut -d' ' -f1)" = "$was" ] && break
    [ "$sweep" -ge 15 ] && { echo "  sweep        not converging"; exit 1; }
done
}

sweep
python3 tools/droplocal.py "$f" b_p_path b_p_sua b_p_tags b_p_tc b_p_ar b_p_swf
sweep

# The post-condition, and the check that was missing when this phase first ran.
# dropoptions.py --strict asks "does anything still read this global?", but it
# has to ask BEFORE the sweep, when the option's own callback still does.  After
# the sweep the question is answerable and the answer must be nothing at all --
# an unread global is itself swept, so the right count is zero mentions, not one.
for g in p_path p_sua p_tags p_tc p_ar p_swf; do
    n=$(grep -c "\b$g\b" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  globals      $g still has $n mentions after the sweep"
        echo "               a dropped row leaves its global uninitialised, and a"
        echo "               reader of it is a segfault before the first keystroke"
        grep -n "\b$g\b" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
echo "  globals      none of the six is mentioned anywhere any more"

tools/canon.sh "$f"

if ! gcc -c -O0 -Wall -Wextra -Wno-unused-parameter -o /dev/null "$f" \
        2>"$work/gcc.txt"; then
    echo "  compile      FAILED -- the cut did not leave valid C"
    grep -m5 'error:' "$work/gcc.txt" | sed 's/^/               /'
    exit 1
fi
warn=$(grep 'warning:' "$work/gcc.txt" | grep -cv 'implicit-fallthrough' || true)
if [ "$warn" != 0 ]; then
    echo "  warnings     $warn besides the fall-throughs -- the sweep is not finished"
    grep 'warning:' "$work/gcc.txt" | grep -v 'implicit-fallthrough' | head -5 \
        | sed 's/^/               /'
    exit 1
fi
rm -f "$work/gcc.txt"

gcc -c -O0 -o "$work/nm.o" "$f" 2>/dev/null
ext=$(nm --extern-only --defined-only "$work/nm.o" | awk '{print $NF}' | grep -v '^main$' || true)
if [ -n "$ext" ]; then
    echo "  linkage      these became external: $ext"
    exit 1
fi
echo "  linkage      nm on the object still prints exactly main"

nm -u "$work/sym.o" | awk '{print $2}' | sort > "$work/sym.before"
nm -u "$work/nm.o"  | awk '{print $2}' | sort > "$work/sym.after"
gone=$(comm -23 "$work/sym.before" "$work/sym.after" | tr '\n' ' ')
after_syms=$(nm -u "$work/nm.o" | wc -l)
rm -f "$work/nm.o" "$work/sym.o" "$work/sym.before" "$work/sym.after"
# Reported, not checked: this phase removes a habit rather than a dependency,
# and stat() stays for everything the user does ask for.
echo "  symbols      $before_syms -> $after_syms${gone:+, gone: $gone}"

make -C "$work" clean >/dev/null 2>&1 || true
if make -C "$work" >/dev/null 2>&1; then
    echo "  build        ok, $before_lines -> $(grep -c '' "$f") lines, $(stat -c%s "$work/pure-vim") bytes"
else
    echo "  build        FAILED -- rerun by hand: make -C $work"
    exit 1
fi

# --- the delta, cumulative --------------------------------------------------
tools/puredelta.sh "$work/pure-vim" "$f" --cases bomb_on,filter,read_cmd \
    helpclose intro version cd chdir lcd lchdir tcd tchdir pwd '!' language \
    tags preserve swapname mkvimrc mkexrc checktime
