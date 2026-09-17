#!/bin/sh
# Whim phase 74, the check -- no file marks.
# See pipes/whim74-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim74-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim74-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim74-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim74-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

# The file marks are gone, and so is everything that only existed to serve them.
for g in namedfm xfmark_T EXTRA_MARKS fname2fnum fmarks_check_names fmarks_check_one \
         fm_getname buflist_getfile; do
    n=$(grep -cE -- "\\b$g\\b" "$f" || true)
    [ "$n" = 0 ] || { echo "  nofmark      $g still has $n mentions"; exit 1; }
done
# fmark_T STAYS: struct taggy embeds it, so the tag stack depends on it.
grep -qE '\bfmark_T\b' "$f" || { echo "  nofmark      fmark_T went -- the tag stack embeds it"; exit 1; }
grep -qE 'fmark_T[ \t]+fmark;' "$f" || { echo "  nofmark      struct taggy lost its fmark"; exit 1; }
# and the marks that are NOT file marks must all survive
for g in b_namedm b_last_cursor b_last_insert b_last_change b_op_start b_op_end \
         w_pcmark w_prev_pcmark setpcmark getmark setmark setmark_pos check_mark \
         clrallmarks mark_adjust_internal mark_col_adjust ex_marks ex_delmarks; do
    grep -qE "\\b$g\\b" "$f" || { echo "  nofmark      $g went -- that was never a file mark"; exit 1; }
done
# do_join's PARAMETER named setmark must be untouched -- an unscoped edit would have
# eaten it, which is the b_next mistake in another costume.
grep -qE 'do_join\(long[^)]*int[ \t]+setmark\)' "$f" || { echo "  nofmark      do_join lost its setmark parameter"; exit 1; }
echo "  nofmark      no file marks; lowercase, the special marks and the tag stack intact"

tools/phasecheck.sh "$work" "$f" "$state/symbols"

tools/phasebuild.sh "$work" "$before_lines"

d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT
cp "$work/whim-vim" "$d/vim"

# LOAD FIRST.
printf 'a\nb\nc\n' > "$d/t.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+$' '+s/^/LAST /' '+wq' t.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/t.txt")" = 'a|b|LAST c|' ] || { echo "  nofmark      the file did not load: '$(tr '\n' '|' < "$d/t.txt")'"; exit 1; }

printf 'one\ntwo\nthree\n' > "$d/e.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+2' '+normal! dd' '+wq' e.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/e.txt")" = 'one|three|' ] || { echo "  nofmark      editing broke: '$(tr '\n' '|' < "$d/e.txt")'"; exit 1; }

# THE DISCRIMINATOR, and the reason this phase failed the first time.  The mark name
# carries a quote, so the vim text is double-quoted at the shell and the quote never
# reaches a shell metacharacter position.  Both halves were calibrated on q73, where
# lowercase gives K1|K2-kept|K3| and uppercase gives U1-up|U2|U3| -- so the uppercase
# case CHANGES here, which is what makes it evidence rather than decoration.
printf 'K1\nK2\nK3\n' > "$d/lo.txt"
(cd "$d" && HOME="$d" ./vim -e -s "+normal! 2Gmb" "+normal! 3G" "+normal! 'bA-kept" "+wq" lo.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/lo.txt")" = 'K1|K2-kept|K3|' ] || { echo "  nofmark      a lowercase mark stopped working: '$(tr '\n' '|' < "$d/lo.txt")'"; exit 1; }

printf 'U1\nU2\nU3\n' > "$d/up.txt"
(cd "$d" && HOME="$d" ./vim -e -s "+normal! 1GmA" "+normal! 3G" "+normal! 'AA-up" "+wq" up.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/up.txt")" = 'U1|U2|U3|' ] || { echo "  nofmark      an uppercase mark still works: '$(tr '\n' '|' < "$d/up.txt")'"; exit 1; }

# a backtick mark too, the other key that reaches getmark
printf 'B1\nB2\nB3\n' > "$d/bt.txt"
(cd "$d" && HOME="$d" ./vim -e -s "+normal! 2Gmc" "+normal! 3G" '+normal! `cA-bt' "+wq" bt.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/bt.txt")" = 'B1|B2-bt|B3|' ] || { echo "  nofmark      a backtick mark stopped working: '$(tr '\n' '|' < "$d/bt.txt")'"; exit 1; }

# :marks and :delmarks must still run.  NOT discriminators -- both write the file
# either way and neither reaches stderr -- so they are no-crash checks only.
printf 'M1\n' > "$d/mk.txt"
(cd "$d" && HOME="$d" ./vim -e -s "+normal! 1Gma" '+marks' "+normal! A-mk" '+wq' mk.txt </dev/null >/dev/null 2>&1) || true
[ "$(cat "$d/mk.txt")" = 'M1-mk' ] || { echo "  nofmark      :marks broke the session: $(cat "$d/mk.txt")"; exit 1; }
printf 'D1\n' > "$d/dm.txt"
(cd "$d" && HOME="$d" ./vim -e -s "+normal! 1Gma" '+delmarks a' "+normal! A-dm" '+wq' dm.txt </dev/null >/dev/null 2>&1) || true
[ "$(cat "$d/dm.txt")" = 'D1-dm' ] || { echo "  nofmark      :delmarks broke the session: $(cat "$d/dm.txt")"; exit 1; }
echo "  nofmark      lowercase and backtick marks work; uppercase is unset; :marks and :delmarks run"
