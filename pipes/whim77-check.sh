#!/bin/sh
# Whim phase 77, the check -- no buffer-name argument matching.
# See pipes/whim77-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim77-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim77-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim77-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim77-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

# The matching and everything that existed only to serve it are gone.
for g in buflist_findpat file_pat_to_reg_pat buflist_match; do
    n=$(grep -cE -- "\\b$g\\b" "$f" || true)
    [ "$n" = 0 ] || { echo "  nobufpat     $g still has $n mentions"; exit 1; }
done
# EX_BUFNAME itself stays: the rows still carry the flag, and the count check at the
# top of do_one_cmd still reads it.  Removing a flag from cmdnames[] rows would be a
# table edit, which is a different and riskier thing.
grep -qE '\bEX_BUFNAME\b' "$f" || { echo "  nobufpat     EX_BUFNAME went -- the rows and the count check still name it"; exit 1; }
# `ni` and the seven checks that consult it must be untouched.
grep -qE '^[ \t]*ni = \(! \(\(int\)\(ea\.cmdidx\) < 0\)' "$f" || { echo "  nobufpat     do_one_cmd no longer computes ni"; exit 1; }
n=$(grep -cE '!ni\b' "$f" || true)
[ "$n" -ge 7 ] || { echo "  nobufpat     only $n checks still consult ni, expected at least 7"; exit 1; }
# doend is a shared label: the goto inside the block went, the label must not have.
awk '/^do_one_cmd\(/,/^\}$/' "$f" | grep -qE '^doend:$' || { echo "  nobufpat     do_one_cmd lost its shared exit label"; exit 1; }
g=$(awk '/^do_one_cmd\(/,/^\}$/' "$f" | grep -cE 'goto doend;' || true)
[ "$g" -ge 5 ] || { echo "  nobufpat     only $g gotos target doend, expected many -- the label may have been orphaned"; exit 1; }
# and the Ex dispatcher itself must still work
for g in do_one_cmd find_ex_command ex_ni cmdnames; do
    grep -qE "\\b$g\\b" "$f" || { echo "  nobufpat     $g went -- the Ex dispatcher still needs it"; exit 1; }
done
echo "  nobufpat     no buffer-name matching; ni, EX_BUFNAME and the doend label intact"

tools/phasecheck.sh "$work" "$f" "$state/symbols"

tools/phasebuild.sh "$work" "$before_lines"

d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT
cp "$work/whim-vim" "$d/vim"

# `:buffer nosuchname` is NOT a discriminator and is not used as one: measured on q76
# it exits 1 with nothing on stderr and the file written either way, because ex_ni
# sets eap->errmsg rather than printing.  A probe on it would prove nothing.  These
# exercise what SURVIVES, and all three were calibrated against q76 first.
printf 'a\nb\nc\n' > "$d/t.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+$' '+s/^/LAST /' '+wq' t.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/t.txt")" = 'a|b|LAST c|' ] || { echo "  nobufpat     the file did not load: '$(tr '\n' '|' < "$d/t.txt")'"; exit 1; }

printf 'p1\np2\n' > "$d/w.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+1' '+normal! A-w' '+wq' w.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/w.txt")" = 'p1-w|p2|' ] || { echo "  nobufpat     writing broke: '$(tr '\n' '|' < "$d/w.txt")'"; exit 1; }

# :e still names a file -- the path that DOES take a file argument, next to the one removed
printf 'e1\n' > "$d/e1.txt"; printf 'e2\n' > "$d/e2.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+e e2.txt' '+normal! A-E' '+wq' e1.txt </dev/null >/dev/null 2>&1) || true
[ "$(cat "$d/e1.txt")" = 'e1' ] || { echo "  nobufpat     :e wrote over the first file: $(cat "$d/e1.txt")"; exit 1; }
[ "$(cat "$d/e2.txt")" = 'e2-E' ] || { echo "  nobufpat     :e did not load the second file: $(cat "$d/e2.txt")"; exit 1; }

# a command with a range and an argument, so the argument parsing around the removed
# block still works
printf 'k1\ndrop\nk2\n' > "$d/g.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+g/drop/d' '+wq' g.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/g.txt")" = 'k1|k2|' ] || { echo "  nobufpat     :g broke: '$(tr '\n' '|' < "$d/g.txt")'"; exit 1; }

# and a retired EX_BUFNAME command must still be refused rather than crash
printf 'z\n' > "$d/z.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+buffer nosuchname' '+normal! A-ok' '+wq' z.txt </dev/null >/dev/null 2>&1) || true
[ "$(cat "$d/z.txt")" = 'z-ok' ] || { echo "  nobufpat     :buffer with a name broke the session: $(cat "$d/z.txt")"; exit 1; }
echo "  nobufpat     loads, writes, :e names a file, :g takes a pattern, :buffer still refused"

# --- the delta, cumulative --------------------------------------------------
tools/whimdelta.sh "$work/whim-vim" "$f" --term-moved --cases bomb_on,filter,read_cmd,retab,sort_u,sort_n,ff_dos,binary_mode,format_gq,format_comment,open_comment \
    helpclose intro version cd chdir lcd lchdir tcd tchdir pwd '!' language \
    tags preserve swapname mkvimrc mkexrc checktime command comclear colorscheme \
    abbreviate noreabbrev abclear iabbrev inoreabbrev iabclear cabbrev cnoreabbrev cabclear \
    sleep smile vim9script autocmd augroup doautocmd doautoall noautocmd sandbox filetype \
    tab tabedit tabfirst tabmove tablast tabnext tabnew tabonly tabprevious tabNext tabrewind tabs redrawtabline \
    browse confirm mode open tmap tmapclear tnoremap \
    all args argadd argdelete argdedupe argglobal arglocal argument first last rewind \
    sargument sall sfirst slast srewind \
    aboveleft ball belowright botright horizontal leftabove new only resize rightbelow \
    sbuffer sbNext sball sbfirst sblast sbnext sbprevious sbrewind split sunhide sview \
    syncbind topleft unhide vertical vnew vsplit \
    buffer bNext bdelete bfirst blast brewind buffers bwipeout files ls \
    bnext bprevious keepalt \
    center left retab right sort uniq \
    qall quitall wall wqall xall \
    startinsert startreplace startgreplace stopinsert \
    noswapfile \
    setlocal setglobal \
    lmap lnoremap lmapclear \
    jumps clearjumps
