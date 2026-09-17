#!/bin/sh
# Whim phase 64, the check -- no formatting, comment or nroff-macro options.
# See pipes/whim64-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim64-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim64-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim64-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim64-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

for g in p_fo p_flp p_com p_para p_sections b_p_fo b_p_flp b_p_com has_format_option get_leader_len get_last_leader_offset \
         auto_format check_auto_format did_add_space paragraph_start same_leader skip_comment get_number_indent ends_in_white \
         inmacro buf_has_cstyle_comments end_comment_pending Insstart_textlen Insstart_blank_vcol did_set_formatoptions \
         did_set_comments OPENLINE_DO_COM OPENLINE_COM_LIST OPENLINE_FORMAT OPENLINE_KEEPTRAIL INSCHAR_DO_COM INSCHAR_COM_LIST \
         COM_MAX_LEN FO_WRAP FO_AUTO \
         op_format format_lines fmt_check_par nv_gd find_decl OP_FORMAT OP_FORMAT2 INSCHAR_FORMAT INSCHAR_NO_FEX cursor_start \
         op_reindent bangredo OP_INDENT OP_FILTER CPO_FILTER \
         cindent_on can_cindent set_can_cindent; do
    n=$(grep -cE -- "\\b$g\\b" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  noformatopts $g still has $n mentions after the sweep"
        grep -nE -- "\\b$g\\b" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
for g in internal_format comp_textwidth startPS findpar check_linecomment op_shift op_colon do_bang do_filter \
         may_do_si did_si can_si can_si_back; do
    grep -qE "\\b$g\\b" "$f" || { echo "  noformatopts $g went too -- it was not the formatter's"; exit 1; }
done
echo "  noformatopts no leader, format flag, nroff macro, formatter or declaration search is left; the wrap is"

tools/phasecheck.sh "$work" "$f" "$state/symbols"

tools/phasebuild.sh "$work" "$before_lines"

d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT
cp "$work/whim-vim" "$d/vim"
(cd "$d" && HOME="$d" ./vim -e -s '+set sw=3' '+q!' </dev/null >/dev/null 2>&1) || { echo "  noformatopts the control :set sw=3 failed"; exit 1; }
for o in formatoptions formatlistpat comments paragraphs sections; do
    if (cd "$d" && HOME="$d" ./vim -e -s "+set $o?" '+q!' </dev/null >/dev/null 2>&1); then
        echo "  noformatopts :set $o? was accepted"; exit 1
    fi
done
: > "$d/w.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+set tw=10' '+normal! Aaaa bbb ccc ddd' '+wq' w.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/w.txt")" = 'aaa bbb|ccc ddd|' ] || { echo "  noformatopts typing did not wrap at 'textwidth': '$(tr '\n' '|' < "$d/w.txt")'"; exit 1; }
printf 'one two three four five six seven eight nine ten\nshort\n' > "$d/g.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+1' '+set tw=10' '+normal! gqq' '+wq' g.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/g.txt")" = 'one two three four five six seven eight nine ten|short|' ] || { echo "  noformatopts gqq still formatted: '$(tr '\n' '|' < "$d/g.txt")'"; exit 1; }
(cd "$d" && HOME="$d" ./vim -e -s '+1' '+set tw=10' '+normal! gqj' '+wq' g.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/g.txt")" = 'one two three four five six seven eight nine ten|short|' ] || { echo "  noformatopts gq with a motion still formatted: '$(tr '\n' '|' < "$d/g.txt")'"; exit 1; }
printf 'int x;\n\nvoid f(void)\n{\n    int x;\n    x = x + 1;\n}\n' > "$d/gd.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+6' '+normal! 0fxgd' '+s/^/HERE /' '+wq' gd.txt </dev/null >/dev/null 2>&1) || true
grep -q '^HERE     x = x + 1;$' "$d/gd.txt" || { echo "  noformatopts gd moved the cursor: $(grep -n HERE "$d/gd.txt")"; exit 1; }
# A retired operator abandons the rest of the sequence rather than letting the
# motion through: MEASURED on the boundary before this phase, where `!jix` (already
# nv_error) left the file alone while `=jix` re-indented and inserted, giving
# xa|b|c|.  So both keys leaving it alone is the check, and ! is the invariant
# that says what the cut should look like.
for k in '=' '!'; do
    printf 'a\nb\nc\n' > "$d/op.txt"
    (cd "$d" && HOME="$d" ./vim -e -s '+1' "+normal! ${k}jix" '+wq' op.txt </dev/null >/dev/null 2>&1) || true
    [ "$(tr '\n' '|' < "$d/op.txt")" = 'a|b|c|' ] || { echo "  noformatopts $k still ran as an operator: '$(tr '\n' '|' < "$d/op.txt")'"; exit 1; }
done
# and the control: ix on its own still inserts, so the check above cannot pass
# by the binary simply doing nothing.
printf 'a\nb\nc\n' > "$d/op.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+1' '+normal! ix' '+wq' op.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/op.txt")" = 'xa|b|c|' ] || { echo "  noformatopts the control insert failed: '$(tr '\n' '|' < "$d/op.txt")'"; exit 1; }
# 'smartindent' is kept on purpose, so it is checked rather than assumed: after a
# line ending in { the next line is indented one 'shiftwidth', and a } comes back.
printf 'if (x) {\n' > "$d/si.txt"
cr=$(printf '\r')
(cd "$d" && HOME="$d" ./vim -e -s '+set si sw=4' "+normal! GA${cr}y;" '+normal! o}' '+wq' si.txt </dev/null >/dev/null 2>&1) || true
[ "$(cat -A "$d/si.txt" | tr '\n' '|')" = 'if (x) {$|    y;$|}$|' ] || { echo "  noformatopts smartindent stopped indenting: '$(tr '\n' '|' < "$d/si.txt")'"; exit 1; }
printf 'a\n.PP\nb\n' > "$d/p.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+1' '+normal! }' '+s/^/X/' '+wq' p.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/p.txt")" = 'a|.PP|Xb|' ] || { echo "  noformatopts } stopped somewhere other than the last line: '$(tr '\n' '|' < "$d/p.txt")'"; exit 1; }
echo "  noformatopts the five are unknown; typing wraps at 'textwidth'; gqq, gqj, gd, = and ! do nothing; } passes .PP"

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
