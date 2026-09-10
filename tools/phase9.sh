#!/bin/sh
# Phase 9 -- leave the preprocessor behind.  See GOAL.md.
#
# Usage: tools/phase9.sh <work-dir>       (run from the repository root)
#
# This replaces the patch that a tier-1 run synthesised.  What is algorithmic
# is done by rules here; whatever is left over is applied at the end from
# tools/patches/p9-residue.patch, which is regenerated whenever the agent runs
# and is the number `make residue` reports.  Driving it to zero is the work.
#
# The order is forced and one step of it is a trap:
#
#   DELETE BEFORE CONVERTING, IN EXACTLY ONE ROUND.  A quarter of the macros
#   are named nowhere but their own definition, and every one deleted is one
#   that never has to be converted or expanded.  Iterating to a fixpoint finds
#   48 more and produces a permanently different vim.c, because the number of
#   rounds decides how many constants reach toenum.py -- 1,444 enumerators
#   against 1,410.  See tools/dropmacros.py.
set -eu

work=${1:?usage: phase9.sh <work-dir>}
f="$work/vim.c"
export SOURCE_DATE_EPOCH=1700000000

before=$(grep -c '' "$f")
before_defines=$(grep -c '^[ 	]*#[ 	]*define' "$f" || true)

# --- delete, then convert -------------------------------------------------
python3 tools/dropmacros.py "$f"
python3 tools/toenum.py "$f"

# --- the X-macro, before anything expands it ------------------------------
# ex_cmds.h is inlined twice with EXCMD meaning two different things either
# side of an #undef.  An expander keyed by name takes the second body for both
# copies, which puts 600 struct initialisers inside enum CMD_index and leaves
# every CMD_xxx undeclared.  Split it first.
python3 tools/xmacro9.py "$f"

# --- the two that keep their names ---------------------------------------
python3 tools/gettext9.py "$f"

# --- expand what neither deletion nor an enumerator could take ------------
# The expander rescans its own output, because the preprocessor does: a macro
# whose body names another macro leaves that name behind, and missing it left
# 282 undeclared symbols once.
python3 tools/expand.py --keep=_,NGETTEXT "$f"

# --- what expansion leaves behind ----------------------------------------
# Every do { ... } while (0) wrapper, by brace matching rather than by regex:
# 18 lines carry two wrappers, one nested inside the other, and the spelling
# varies between `while (0);` and `while (0) ;`.
python3 tools/undowhile.py "$f"

# Expansion pastes in `for` headers of its own, so the Phase 7 invariants are
# broken again by the time we get here.  This is GOAL.md rule 9: an invariant
# nothing re-checks is not an invariant, and 1,558 unbraced bodies once sat in
# a file whose documentation said every body was braced.
tools/canon.sh "$f"

# The table's rows come out of expansion indented by one space, because the
# expander collapses whitespace inside a macro body.  Every other initialiser
# block in this file is indented by four, and 600 rows that are not is 1,200
# lines of residue for nothing.
sed -i -e 's|^ \[CMD_|    [CMD_|' -e '/^    \[CMD_/s|} ,$|},|' \
       -e 's|^ \(CMD_[A-Za-z0-9_]*\) ,$|    \1,|' "$f"

# --- whatever is not yet a rule ------------------------------------------
residue=tools/patches/p9-residue.patch
if [ -f "$residue" ]; then
    if patch -p1 -d "$work" --forward --silent < "$residue"; then
        echo "  residue      $(grep -c '^[+-][^+-]' "$residue") lines applied"
    else
        echo "  residue      no longer applies -- upstream moved under it, or an"
        echo "               algorithm above now does part of its job.  Falling"
        echo "               through to tier 1 regenerates it."
        exit 1
    fi
fi

after_defines=$(grep -c '^[ 	]*#[ 	]*define' "$f" || true)
echo "  macros       $before_defines -> $after_defines defines, $before -> $(grep -c '' "$f") lines"

make -C "$work" clean >/dev/null 2>&1 || true
if make -C "$work" >/dev/null 2>&1; then
    echo "  build        ok"
else
    echo "  build        FAILED -- rerun by hand: make -C $work"
    exit 1
fi
