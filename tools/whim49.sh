#!/bin/sh
# Whim phase 49 -- one set of options.  See WHIM-GOAL.md.
#
# Usage: tools/whim49.sh <work-dir>      (run from the repository root)
#
# Every buffer and window option keeps its global and local copy inside the
# editor; what goes is every way to make the two differ, so :set is the only way
# an option is given a value.  :setlocal and :setglobal go, the :set opt< suffix
# goes, and modelines go with their four options: 'modeline', 'modelines',
# 'modelineexpr' and 'modelinestrict'.  See tools/oneoptset.py.
#
# THE DELTA: :setlocal and :setglobal, which succeeded run bare.
set -eu

work=${1:?usage: whim49.sh <work-dir>}
f="$work/whim-vim.c"

before_lines=$(grep -c '' "$f")
tools/symbols.sh "$f" .cache/symbols/before

python3 tools/retire.py "$f" setlocal setglobal
python3 tools/oneoptset.py "$f"
# The rows go before the sweep and without --strict: do_modelines() reads
# 'modeline' and 'modelines' until the sweep takes it.  The post-condition is the
# check.
python3 tools/dropoptions.py "$f" --local modeline
python3 tools/dropoptions.py "$f" modelines modelineexpr modelinestrict

tools/sweep.sh "$f"
python3 tools/droplocal.py "$f" b_p_ml
tools/sweep.sh "$f"

for g in do_modelines chk_modeline p_mls p_mle p_mlstr p_ml p_ml_nobin b_p_ml b_p_ml_nobin \
         modeline_whitelist is_modeline_whitelisted; do
    n=$(grep -cE -- "\\b$g\\b" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  optset       $g still has $n mentions after the sweep"
        grep -nE -- "\\b$g\\b" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
echo "  optset       no modeline, and nothing that set one copy of an option"

tools/phasecheck.sh "$work" "$f" .cache/symbols/before

tools/phasebuild.sh "$work" "$before_lines"

# :set opt< must be refused, and an ordinary :set still taken.
out=$(cd "$work" && ./whim-vim -e -s '+set ts=3' '+q!' </dev/null 2>&1) && rc=0 || rc=$?
[ "$rc" = 0 ] || { echo "  optset       the control failed: :set ts=3 exits $rc: $out"; exit 1; }
out=$(cd "$work" && ./whim-vim -e -s '+set ts<' '+q!' </dev/null 2>&1) && rc=0 || rc=$?
[ "$rc" = 1 ] || { echo "  optset       :set ts< exits $rc, expected 1: $out"; exit 1; }

# A modeline must no longer set anything.  'modelinestrict' let a modeline set
# only whitelisted options, and 'fileformat' was not one of them, so a first
# version of this check that used ff=dos passed against binaries that still read
# modelines.  'shiftwidth' is on the whitelist and shows in the bytes: >> on a
# file whose modeline says sw=2 indents by two if the modeline was read, and by
# the compiled-in four if not.
d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT
printf 'one\n# vim: set sw=2:\n' > "$d/m.txt"
(cd "$d" && HOME="$d" "$OLDPWD/$work/whim-vim" -e -s '+1normal! >>' '+w' '+q!' m.txt </dev/null >/dev/null 2>&1) || true
if [ "$(head -1 "$d/m.txt")" != "    one" ]; then
    echo "  optset       a modeline set 'shiftwidth': the first line is '$(head -1 "$d/m.txt")'"
    exit 1
fi
echo "  optset       :set ts< is refused, and a modeline sets nothing"

# --- the delta, cumulative --------------------------------------------------
tools/whimdelta.sh "$work/whim-vim" "$f" --term-moved --cases bomb_on,filter,read_cmd,retab,sort_u,sort_n \
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
    setlocal setglobal
