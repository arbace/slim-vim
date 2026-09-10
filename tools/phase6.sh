#!/bin/sh
# Phase 6 -- merge 162 files into one translation unit.  See SLIM-GOAL.md.
#
# Usage: tools/phase6.sh <work-dir>       (run from the repository root)
#
# The collisions have to be found BEFORE the merge, because afterwards there
# are no per-file objects left to compare.  `nm --defined-only` over them names
# anything defined in more than one object; gcc's `.0`/`.1` suffixed names are
# function-local statics and are not collisions.  `nm` cannot see macros, so
# the fourth -- GAP, in what were option.c and term.c -- is found only by the
# compiler's redefinition warning, which is why it is in the table rather than
# discovered here.
#
# Which side gives way, and to what, is not deducible from anything: the
# previous pass renamed ex_cmds.c's sort_compare to string_sort_compare, which
# the name does not suggest.  tools/renames.txt is that decision, written down,
# and an unlisted collision is a hard failure rather than a judgement call.
set -eu

work=${1:?usage: phase6.sh <work-dir>}
jobs=$(nproc 2>/dev/null || echo 4)
export SOURCE_DATE_EPOCH=1700000000

root=$(pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# --- collisions, against the table ----------------------------------------
for o in "$work"/objects/*.o; do
    nm --defined-only "$o" 2>/dev/null | awk '{print $NF}'
done | grep -v '\.[0-9]*$' | sort | uniq -d > "$tmp/collisions"

missing=
while read -r name; do
    [ -n "$name" ] || continue
    grep -q ":$name:" tools/renames.txt || missing="$missing $name"
done < "$tmp/collisions"
if [ -n "$missing" ]; then
    echo "  collisions   NOT IN tools/renames.txt:$missing"
    echo "               Which side gives way is not deducible -- add it to the"
    echo "               table rather than letting a pass choose, or two passes"
    echo "               will produce different vim.c files for no reason."
    exit 1
fi
echo "  collisions   $(grep -c '' "$tmp/collisions") found, all in the table"

# --- apply the renames ----------------------------------------------------
n_ren=0
while IFS=: read -r scope old new; do
    case "$scope" in ''|\#*) continue;; esac
    case "$old" in *@*) continue;; esac          # occurrence-scoped: Phase 5's
    [ -f "$work/$scope" ] || continue
    before=$(grep -c "\\b$old\\b" "$work/$scope" || true)
    sed -i "s/\\b$old\\b/$new/g" "$work/$scope"
    n_ren=$((n_ren + before))
done < tools/renames.txt
echo "  renamed      $n_ren identifiers, per the table"

# --- pathdef.c still describes the old build ------------------------------
# :version prints these, and they named -I, -D, -g -O2 and -lintl -- none of
# which is on the command line that actually runs.
sed -i \
    -e 's|^char_u \*all_cflags = .*|char_u *all_cflags = (char_u *)"gcc -O0 -c vim.c";|' \
    -e 's|^char_u \*all_lflags = .*|char_u *all_lflags = (char_u *)"gcc -O0 -static -s -o vim vim.c";|' \
    "$work/pathdef.c"
echo "  pathdef      names the command that is actually run"

# --- main() last ----------------------------------------------------------
# main.c has functions after main(), and the finished file ends with main()'s
# closing brace.
python3 tools/mainlast.py "$work/main.c"

# --- the merge ------------------------------------------------------------
# regexp_bt.c and regexp_nfa.c are sources but not translation units: regexp.c
# #includes them, and merge.py inlines them there like any other local include.
# Listing them here as well merges them twice, and gcc reports it as sixteen
# redefinitions in the regexp code rather than as the duplication it is.
sources=$(cd "$work" && ls *.c \
    | grep -v '^main\.c$\|^regexp_bt\.c$\|^regexp_nfa\.c$' | sort | tr '\n' ' ')
( cd "$work" && python3 "$root/tools/merge.py" vim.c $sources main.c )

( cd "$work" && rm -f $sources main.c regexp_bt.c regexp_nfa.c *.h && rm -rf proto objects )
cp tools/templates/merged.mk "$work/Makefile"
echo "  merged       $(grep -c '' "$work/vim.c") lines, one file"

python3 tools/renameregion.py tools/renames.txt "$work/vim.c"

# --- re-resolve, now that there is one unit -------------------------------
# Every group Phase 5 had to leave alone existed because units disagreed, and
# there is one unit now.  The include-guard exception goes too: nothing can be
# included twice any more.
gcc -E -P -o "$tmp/before.i" "$work/vim.c"
cp -a "$work" "$tmp/planted"
python3 tools/plant.py "$tmp/planted/vim.c" >/dev/null
mkdir -p "$tmp/live"
( cd "$tmp/planted" && gcc -E vim.c 2>/dev/null \
    | grep -o 'ZMK_[0-9]*_ZMK' | sort | uniq -c > "$tmp/live/vim.txt" )
python3 tools/resolve.py --no-guards "$tmp/live" "$work/vim.c"

# --- the feature-test macros ----------------------------------------------
# glibc-era, and musl declares everything unconditionally.  The check is that
# the preprocessed output does not move.
python3 tools/dropftm.py "$work/vim.c"
gcc -E -P -o "$tmp/after.i" "$work/vim.c"
if python3 tools/tier2.py "$tmp/before.i" "$tmp/after.i" >/dev/null; then
    echo "  tier 2       token-identical through resolve and the feature macros"
else
    echo "  tier 2       DIFFERS -- resolution or a feature-test macro changed the program"
    exit 1
fi

# --- the canary -----------------------------------------------------------
# It is expected to break here: the merge disturbs the block's shape.  Check
# the numbers, then restore the canonical form.
if ! python3 tools/create_cmdidxs.py "$work/vim.c" --check >/dev/null 2>&1; then
    python3 tools/create_cmdidxs.py "$work/vim.c" --update
    echo "  cmdidxs      regenerated -- the merge disturbed the block, as expected"
else
    echo "  cmdidxs      already byte-identical"
fi

make -C "$work" clean >/dev/null 2>&1 || true
if make -C "$work" >/dev/null 2>&1; then
    echo "  build        ok, one gcc invocation"
else
    echo "  build        FAILED -- rerun by hand: make -C $work"
    exit 1
fi
