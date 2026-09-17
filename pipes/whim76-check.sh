#!/bin/sh
# Whim phase 76, the check -- one regexp engine, so no retry.
# See pipes/whim76-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim76-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim76-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim76-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim76-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

# The retry, the option and the husk it kept alive are gone.
for g in AUTOMATIC_ENGINE p_re nfa_regprog_T nfa_state_T nfa_regengine regexp_engine; do
    n=$(grep -cE -- "\\b$g\\b" "$f" || true)
    [ "$n" = 0 ] || { echo "  oneengine    $g still has $n mentions"; exit 1; }
done
# The one engine and everything matching depends on must survive.
for g in BACKTRACKING_ENGINE re_engine bt_regengine bt_regprog_T regprog_T regengine_T \
         vim_regcomp vim_regfree vim_regexec_string vim_regexec_multi re_in_use re_flags; do
    grep -qE "\\b$g\\b" "$f" || { echo "  oneengine    $g went -- matching still needs it"; exit 1; }
done
grep -qE 'prog->re_engine = BACKTRACKING_ENGINE;' "$f" || { echo "  oneengine    the engine is no longer recorded on the program"; exit 1; }
echo "  oneengine    one engine, no retry; the matcher and its program types intact"

tools/phasecheck.sh "$work" "$f" "$state/symbols"

tools/phasebuild.sh "$work" "$before_lines"

d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT
cp "$work/whim-vim" "$d/vim"

# EVERY PROBE CALIBRATED AGAINST q75 FIRST.  This phase touches vim_regexec_string and
# vim_regexec_multi, so the probes exercise MATCHING rather than plain editing -- a
# load-and-edit probe would pass whatever happened to the regexp layer.
printf 'a\nb\nc\n' > "$d/t.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+$' '+s/^/LAST /' '+wq' t.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/t.txt")" = 'a|b|LAST c|' ] || { echo "  oneengine    the file did not load: '$(tr '\n' '|' < "$d/t.txt")'"; exit 1; }

# a quantified pattern, matched many times on one line -- vim_regexec_string
printf 'alpha\nbeta\ngamma\n' > "$d/s.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+%s/a\+/X/g' '+wq' s.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/s.txt")" = 'XlphX|betX|gXmmX|' ] || { echo "  oneengine    a quantified match broke: '$(tr '\n' '|' < "$d/s.txt")'"; exit 1; }

# :g drives vim_regexec_multi over every line
printf 'one1\ntwo2\nthree3\n' > "$d/d.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+g/[0-9]$/s/[0-9]$/N/' '+wq' d.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/d.txt")" = 'oneN|twoN|threeN|' ] || { echo "  oneengine    :g over a pattern broke: '$(tr '\n' '|' < "$d/d.txt")'"; exit 1; }

# capture groups and back-references, which the backtracking engine implements
printf 'foo\nbar\nfoobar\n' > "$d/r.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+%s/\(foo\)\(bar\)/\2\1/' '+wq' r.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/r.txt")" = 'foo|bar|barfoo|' ] || { echo "  oneengine    back-references broke: '$(tr '\n' '|' < "$d/r.txt")'"; exit 1; }

# a non-capturing group with a count -- the shape the NFA engine used to be chosen for
printf 'aaa\nbbb\n' > "$d/c.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+%s/\%(a\|b\)\{2}/Z/' '+wq' c.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/c.txt")" = 'Za|Zb|' ] || { echo "  oneengine    a counted group broke: '$(tr '\n' '|' < "$d/c.txt")'"; exit 1; }

# and a plain search, which reaches the matcher by a different path again
printf 'x\ny\n' > "$d/n.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+/y' '+normal! A-found' '+wq' n.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/n.txt")" = 'x|y-found|' ] || { echo "  oneengine    search broke: '$(tr '\n' '|' < "$d/n.txt")'"; exit 1; }
echo "  oneengine    quantifiers, :g, back-references, counted groups and search all match"

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
