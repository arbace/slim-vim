#!/bin/sh
# Whim phase 69, the check -- one file argument, and no argument list.
# See pipes/whim69-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim69-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim69-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim69-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim69-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

for g in ex_next ex_previous do_argfile do_arglist arglist_del_files alist_set alist_clear alist_add \
         alist_name alist_init editing_arg_idx check_arglist_locked arglist_locked arg_had_last \
         global_alist alist_T aentry_T w_alist w_arg_idx w_arg_idx_invalid AL_SET AL_ADD AL_DEL; do
    n=$(grep -cE -- "\\b$g\\b" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  onearg       $g still has $n mentions after the sweep"
        grep -nE -- "\\b$g\\b" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
# The naming path MUST survive -- it is what makes the file load at all.
for g in buflist_add buflist_new open_buffer b_ffname readfile command_line_scan; do
    grep -qE "\\b$g\\b" "$f" || { echo "  onearg       $g went too -- the one file would not load"; exit 1; }
done
grep -q 'buflist_add(p, BLN_CURBUF | BLN_LISTED);' "$f" || { echo "  onearg       the command line no longer names the buffer"; exit 1; }
echo "  onearg       one file argument, no argument list, and the name still reaches curbuf"

tools/phasecheck.sh "$work" "$f" "$state/symbols"

tools/phasebuild.sh "$work" "$before_lines"

d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT
cp "$work/whim-vim" "$d/vim"

# LOAD FIRST.  This is the probe the earlier attempt lacked: it proves the buffer
# holds the file's lines, not merely that the editor exits cleanly.
printf 'l1\nl2\nl3\n' > "$d/t.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+$' '+s/^/LAST /' '+wq' t.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/t.txt")" = 'l1|l2|LAST l3|' ] || { echo "  onearg       the file did not load: '$(tr '\n' '|' < "$d/t.txt")'"; exit 1; }
printf 'a\nb\nc\n' > "$d/e.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+2' '+normal! dd' '+wq' e.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/e.txt")" = 'a|c|' ] || { echo "  onearg       editing broke: '$(tr '\n' '|' < "$d/e.txt")'"; exit 1; }
# a second file argument is refused, and nothing is written
printf 'one\n' > "$d/g1.txt"; printf 'two\n' > "$d/g2.txt"
if (cd "$d" && HOME="$d" ./vim -e -s '+normal! iX' '+wq' g1.txt g2.txt </dev/null >/dev/null 2>&1); then
    echo "  onearg       two file arguments were accepted"; exit 1
fi
[ "$(cat "$d/g1.txt")" = 'one' ] && [ "$(cat "$d/g2.txt")" = 'two' ] || { echo "  onearg       a refused command line still wrote"; exit 1; }
# :next is refused, and :e still works
printf 'n1\n' > "$d/n.txt"
if (cd "$d" && HOME="$d" ./vim -e -s '+next' '+q!' n.txt </dev/null >/dev/null 2>&1); then
    echo "  onearg       :next was accepted"; exit 1
fi
printf 'h1\n' > "$d/h1.txt"; printf 'h2\n' > "$d/h2.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+e h2.txt' '+normal! iE' '+wq' h1.txt </dev/null >/dev/null 2>&1) || true
[ "$(cat "$d/h1.txt")" = 'h1' ] && [ "$(cat "$d/h2.txt")" = 'Eh2' ] || { echo "  onearg       :e broke: h1=$(cat "$d/h1.txt") h2=$(cat "$d/h2.txt")"; exit 1; }
echo "  onearg       the file loads and edits; a second argument and :next are refused; :e still opens"

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
