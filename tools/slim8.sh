#!/bin/sh
# Phase 8 -- internal linkage, then dead code to a fixpoint.  See SLIM-GOAL.md.
#
# Usage: tools/slim8.sh <work-dir>       (run from the repository root)
#
# Before the macro work, not after: every macro deleted here is one that does
# not have to be converted in Phase 9.
#
# The order is forced.  Split declarations are joined first, because the dead
# sweep deletes by line and half a declaration left behind surfaces as an
# unrelated undeclared symbol.  Then everything but main() becomes static,
# which is what turns `-Wall -Wextra` into a real dead-code detector: with
# internal linkage the compiler can see that nothing uses a thing.  Only then
# does the sweep run, and it runs to a JOINT fixpoint with the type sweep,
# because deleting a function orphans its callees and deleting a type orphans
# the functions that took it.
set -eu

work=${1:?usage: phase8.sh <work-dir>}
f="$work/vim.c"
export SOURCE_DATE_EPOCH=1700000000

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

before_lines=$(grep -c '' "$f")

# --- join, then make it all internal --------------------------------------
python3 tools/joindecls.py "$f"

# EXTERN is what makes the globals external, and it becomes static TEXTUALLY.
# Expanding it as a macro instead pads all 1,055 sites with a space on each
# side and leaves ` static  int p_ai;`.
n_ext=$(grep -c '^EXTERN\b' "$f" || true)
sed -i 's/^EXTERN\b/static/' "$f"
echo "  EXTERN       $n_ext sites became static, textually"

# PLURAL_MSG is the same shape one level down: its body emits a bare
# `char var[]`, which leaves two error strings external however the call sites
# are written.  The macro body is what has to change.
sed -i 's/^\(# define PLURAL_MSG(.*)\)\( *\)char \(var1\[\] = msg1;\) *char \(var2\[\] = msg2;\)/\1\2static char \3     static char \4/' "$f"

# --- until nm says only main ----------------------------------------------
# nm the OBJECT, not a linked binary: a static musl binary defines 1,400-odd
# symbols of its own and buries the answer.
round=0
while :; do
    round=$((round + 1))
    gcc -c -O0 -o "$tmp/o.o" "$f" 2>/dev/null || {
        echo "  static       build failed in round $round"
        gcc -c -O0 -o /dev/null "$f" 2>&1 | grep -E 'error' | head -5 | sed 's/^/               /'
        exit 1
    }
    ext=$(nm --extern-only --defined-only "$tmp/o.o" | awk '{print $NF}' | grep -v '^main$' || true)
    [ -z "$ext" ] && break
    if [ "$round" -ge 20 ]; then
        echo "  static       not converging; still external:$(echo $ext | head -c 200)"
        exit 1
    fi
    # One pass, not one process per symbol.  This used to spawn a python for
    # each external name, each reading and rewriting a seven-megabyte file:
    # 2,045 of them, 148 seconds, forty per cent of the phase, to make edits
    # that touch one line each.  A file-scope declaration names exactly one
    # thing, so asking every line "what do you declare, and is it in the set?"
    # is O(lines) where the old shape was O(lines x symbols).
    echo "$ext" > "$tmp/ext.txt"
    python3 tools/makestatic.py "$f" --from "$tmp/ext.txt"
done
echo "  static       nm on the object prints exactly main, after $round round(s)"

# --- dead code, to a joint fixpoint ---------------------------------------
# Functions and variables from -Wall -Wextra; types by reachability, for which
# no warning exists.  Alternating, because each orphans the other.
# The fixpoint is the FILE, not any tool's report.  Keying on a count means
# parsing three tools' prose, and reading only the first number of
# "prototypes 0, functions 1, variables 2" stops the loop with work left to do
# -- which it did, leaving three unused functions and a failed warning gate.
sweep=0
while :; do
    sweep=$((sweep + 1))
    before=$(sha256sum "$f" | cut -d' ' -f1)

    a=$(python3 tools/deadsweep.py "$f" | tail -1)
    # Prototypes for functions that no longer exist say nothing to gcc, and
    # each one is a ROOT for the type sweep -- proftime_T and getoption_T
    # survived an entire type pass on the strength of one dead declaration
    # apiece.  So this belongs inside the loop, between the two.
    c=$(python3 tools/deadprotos.py "$f" | tail -1)
    b=$(python3 tools/typereach.py "$f" --delete | tail -1)
    echo "  sweep $sweep      $a; $c; $b"

    [ "$(sha256sum "$f" | cut -d' ' -f1)" = "$before" ] && break
    if [ "$sweep" -ge 15 ]; then
        echo "  sweep        not converging after $sweep rounds"
        exit 1
    fi
done

# --- the two warnings that are findings, not dead code --------------------
# SLIM-GOAL.md predicts both, and both were there.  They are the reason the sweep is
# not a delete-everything-it-names loop: a warning can be the compiler noticing
# a bug rather than noticing something unused.
#
#   :winpos parsed two numbers nothing reads any more.  getdigits() advances
#   the pointer, so the CALLS have to stay and only the variables go -- delete
#   the calls and the second number is parsed from the first one's text.
#
#   The swap-file age check compared st.st_mtime against time(NULL) minus
#   sinfo.uptime, and uptime is unsigned, which makes the whole subtraction
#   unsigned and liable to wrap.  A cast to time_t is the fix; deleting
#   anything here would have been wrong.
python3 tools/findings8.py "$f"

# --- and the only warnings left must be the fall-throughs -----------------
# 37 of them, deliberate, and Phase 9 is where they are marked as such with
# __attribute__((fallthrough)).  Anything else means the sweep is unfinished --
# and the requirement is nothing else AT ALL, never "the usual two", because a
# new warning cannot hide behind a remembered count.
gcc -c -O0 -Wall -Wextra -Wno-unused-parameter -o /dev/null "$f" 2>&1 \
    | grep 'warning:' > "$tmp/warn" || true
other=$(grep -cv 'implicit-fallthrough' "$tmp/warn" || true)
ft=$(grep -c 'implicit-fallthrough' "$tmp/warn" || true)
if [ "$other" != 0 ]; then
    echo "  warnings     $other besides the fall-throughs -- the sweep is not finished"
    grep -v 'implicit-fallthrough' "$tmp/warn" | head -5 | sed 's/^/               /'
    exit 1
fi
echo "  warnings     $ft fall-throughs and nothing else"

make -C "$work" clean >/dev/null 2>&1 || true
if make -C "$work" >/dev/null 2>&1; then
    echo "  build        ok, $before_lines -> $(grep -c '' "$f") lines"
else
    echo "  build        FAILED -- rerun by hand: make -C $work"
    exit 1
fi
