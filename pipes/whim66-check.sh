#!/bin/sh
# Whim phase 66, the check -- no sentences, paragraphs, sections, methods, #if blocks or comment blocks.
# See pipes/whim66-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim66-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim66-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim66-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim66-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

for g in findsent findpar startPS current_sent current_par nv_brace nv_findpar; do
    n=$(grep -cE -- "\\b$g\\b" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  nopara       $g still has $n mentions after the sweep"
        grep -nE -- "\\b$g\\b" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
for g in findmatchlimit nv_bracket_block current_block current_word current_quote nv_percent getnextmark nv_brackets; do
    grep -qE "\\b$g\\b" "$f" || { echo "  nopara       $g went too -- it was not the paragraph's"; exit 1; }
done
echo "  nopara       no sentence, paragraph or section is left; brackets and words are"

tools/phasecheck.sh "$work" "$f" "$state/symbols"

tools/phasebuild.sh "$work" "$before_lines"

d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT
cp "$work/whim-vim" "$d/vim"

# Each cut key beeps, and a beep abandons the rest of a :normal! sequence -- so the
# ix never runs and the file is untouched.  The control below proves ix would.
sample() { printf 'One two. Three four.\n\nvoid f(void)\n{\n    if (x)\n    {\n        y;\n    }\n}\n#if A\n#endif\n' > "$d/t.txt"; }
for k in ')ix' '(ix' '}ix' '{ix' ']]ix' '[[ix' '[mix' ']mix' '[#ix' '[/ix' 'dapix' 'disix'; do
    sample
    (cd "$d" && HOME="$d" ./vim -e -s '+5' "+normal! $k" '+wq' t.txt </dev/null >/dev/null 2>&1) || true
    if ! cmp -s "$d/t.txt" /dev/stdin <<EOF
One two. Three four.

void f(void)
{
    if (x)
    {
        y;
    }
}
#if A
#endif
EOF
    then
        echo "  nopara       $k changed the file:"; sed -n 1,3p "$d/t.txt" | sed 's/^/               /'; exit 1
    fi
done
sample
(cd "$d" && HOME="$d" ./vim -e -s '+5' '+normal! ix' '+wq' t.txt </dev/null >/dev/null 2>&1) || true
grep -q '^    xif (x)$' "$d/t.txt" || { echo "  nopara       the control insert failed"; exit 1; }

# and what stays: [{ still walks out to the enclosing {, % still matches, i{ still selects
sample
(cd "$d" && HOME="$d" ./vim -e -s '+7' '+normal! [{' '+s/^/X/' '+wq' t.txt </dev/null >/dev/null 2>&1) || true
grep -q '^X    {$' "$d/t.txt" || { echo "  nopara       [{ no longer walks out: $(grep -n X "$d/t.txt" | head -1)"; exit 1; }
sample
(cd "$d" && HOME="$d" ./vim -e -s '+4' '+normal! %' '+s/^/X/' '+wq' t.txt </dev/null >/dev/null 2>&1) || true
grep -q '^X}$' "$d/t.txt" || { echo "  nopara       % no longer matches: $(grep -n X "$d/t.txt" | head -1)"; exit 1; }
sample
(cd "$d" && HOME="$d" ./vim -e -s '+7' '+normal! di{' '+wq' t.txt </dev/null >/dev/null 2>&1) || true
# grep -qv is true when ANY line lacks the pattern, so it can pass vacuously: the
# check is that the block's contents are gone and its braces are not.
grep -q '^    {$' "$d/t.txt" || { echo "  nopara       i{ took the enclosing braces too"; exit 1; }
grep -q 'y;' "$d/t.txt" && { echo "  nopara       i{ no longer selects a block -- y; survived"; exit 1; }
# the Ex addresses are refused, so the paragraph is still there afterwards
sample
(cd "$d" && HOME="$d" ./vim -e -s "+'{,'}d" '+wq' t.txt </dev/null >/dev/null 2>&1) || true
grep -q '^One two\. Three four\.$' "$d/t.txt" || { echo "  nopara       '{,'} still addressed a paragraph"; exit 1; }
echo "  nopara       the cut keys do nothing; [{ and % still move; i{ still selects; '{ is refused"

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
