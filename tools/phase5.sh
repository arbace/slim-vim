#!/bin/sh
# Phase 5 -- resolve every conditional directive by marker counting.  See GOAL.md.
#
# Usage: tools/phase5.sh <work-dir>       (run from the repository root)
#
# 8,251 conditional groups become 17, and a third of the tree goes with them.
# The rule the whole phase turns on: DO NOT EVALUATE THE CONDITIONS.  Plant a
# unique token in every branch of every group, preprocess once per translation
# unit, and keep the branches whose token comes out.  Only the preprocessor
# knows -- definedness is position-dependent, so an include guard looks constant
# to a -dM dump and resolving `#ifndef VIM_H` to false deletes the contents of
# every header; and a macro can reach one unit and not another, as TIOCGETP and
# CRMOD do.
#
# Two ways of marking that are wrong, and both compile and run:
#
#   * A group reached in one unit and not another looks resolvable.  plant.py
#     therefore plants a second marker immediately BEFORE each group, so a unit
#     can say "reached it and took no branch" as distinct from "never got
#     here".  Without it, #ifdef DO_INIT in globals.h resolves to main.c's
#     answer and hands the other 66 units initialisers that belong to main.c.
#   * Presence is not enough; the markers must be COUNTED.  ex_cmds.h is read
#     twice in what was ex_docmd.c with DO_DECLARE_EXCMD toggled, so a branch
#     taken on the first read and skipped on the second is present without
#     being uniformly live.  A branch is live only when its marker appears
#     exactly as often as the group was reached.
#
# SOURCE_DATE_EPOCH is exported for the `gcc -E` runs and not only for builds:
# version.c embeds __TIME__, so two preprocessings seconds apart differ at one
# token in 64,275 and the tier-2 report looks like a real failure.
set -eu

work=${1:?usage: phase5.sh <work-dir>}
jobs=$(nproc 2>/dev/null || echo 4)
export SOURCE_DATE_EPOCH=1700000000

root=$(pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

units=$(cd "$work" && ls *.c | grep -v '^regexp_bt\.c$\|^regexp_nfa\.c$')
n_units=$(echo "$units" | wc -w | tr -d ' ')

# --- tier 2's left-hand side ---------------------------------------------
# gcc -E is cheap -- all 67 units in parallel take a fifth of a second -- so
# there is no reason to economise on measurements here.
#
# -P matters: without it gcc emits line markers, `# 123 "vim.h"`, and those are
# tokens.  Resolution removes lines, so every marker after the first change
# carries a different number and all 67 units report a token difference that is
# not one.
mkdir -p "$tmp/before"
( cd "$work" && echo "$units" | tr ' ' '\n' \
    | xargs -P "$jobs" -I{} sh -c 'gcc -E -P -o '"$tmp"'/before/{}.i {}' )
echo "  preprocess   $n_units units, before"

# --- plant, in a copy, and tally what survives ----------------------------
cp -a "$work" "$tmp/planted"
python3 tools/plant.py "$tmp/planted"/*.c "$tmp/planted"/*.h "$tmp/planted"/proto/*.pro

mkdir -p "$tmp/live"
( cd "$tmp/planted" && echo "$units" | tr ' ' '\n' \
    | xargs -P "$jobs" -I{} sh -c \
        'gcc -E {} 2>/dev/null | grep -o "ZMK_[0-9]*_ZMK" | sort | uniq -c > '"$tmp"'/live/{}.txt' )
echo "  tally        $(cat "$tmp"/live/*.txt | wc -l | tr -d ' ') marker counts from $n_units units"

# --- resolve the pristine sources from those votes ------------------------
python3 tools/resolve.py "$tmp/live" "$work"/*.c "$work"/*.h "$work"/proto/*.pro

# --- #undef goes the same way ---------------------------------------------
# Most of these undefine a macro that was never defined; for the rest the macro
# simply stays defined.  The exception is a name defined twice in one file,
# where the #undef between the two is what makes that legal -- those are split
# into two names from tools/renames.txt.  #undef EXCMD stays until the X-macro
# it belongs to goes, in Phase 9.
python3 tools/undefs.py tools/renames.txt EXCMD \
    "$work"/*.c "$work"/*.h "$work"/proto/*.pro

# --- tier 2 ---------------------------------------------------------------
# Resolution is token-preserving by construction, and this is what proves it.
# It caught both of the marking faults above in a build that was otherwise
# perfectly happy.
mkdir -p "$tmp/after"
( cd "$work" && echo "$units" | tr ' ' '\n' \
    | xargs -P "$jobs" -I{} sh -c 'gcc -E -P -o '"$tmp"'/after/{}.i {}' )

bad=0
for u in $units; do
    python3 tools/tier2.py "$tmp/before/$u.i" "$tmp/after/$u.i" >/dev/null 2>&1 || {
        echo "  tier 2       $u DIFFERS"
        bad=$((bad + 1))
    }
done
if [ "$bad" != 0 ]; then
    echo "  tier 2       $bad of $n_units units changed token stream -- a"
    echo "               resolution took a branch that was not uniformly live."
    exit 1
fi
echo "  tier 2       $n_units units, token streams identical"

make -C "$work" clean >/dev/null 2>&1 || true
if make -C "$work" -j"$jobs" >/dev/null 2>&1; then
    left=$(cat "$work"/*.c "$work"/*.h "$work"/proto/*.pro | grep -c '^[ 	]*#[ 	]*\(if\|ifdef\|ifndef\)' || true)
    echo "  build        ok, $left conditional groups left"
else
    echo "  build        FAILED -- rerun by hand: make -C $work"
    exit 1
fi
