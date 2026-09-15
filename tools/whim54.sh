#!/bin/sh
# Whim phase 54 -- no option without a variable.  See WHIM-GOAL.md.
#
# Usage: tools/whim54.sh <work-dir>      (run from the repository root)
#
# A row whose variable is (char_u *)NULL is an option :set accepts, reports and
# ignores: its feature was never compiled in, or went in an earlier phase.  The
# set is COMPUTED from options[] rather than listed, so a row a later upstream
# adds without a variable goes too.
#
# THE DELTA: none the harnesses record -- no case sets an option without a
# variable.  The probes check four of them are now unknown.
set -eu

work=${1:?usage: whim54.sh <work-dir>}
f="$work/whim-vim.c"

before_lines=$(grep -c '' "$f")
tools/symbols.sh "$f" .cache/symbols/before

# The variable field, not the row: a string default is often (char_u *)NULL too.
# And the spacing varies -- 'termguicolors' is (char_u*)NULL.
names=$(python3 - "$f" <<'PY'
import re, sys
t = open(sys.argv[1], errors='surrogateescape').read()
rows = re.findall(r'^[ \t]*\{"(\w+)",\s*(?:"\w*"|NULL),\s*P_[\w|]+,\s*\(char_u ?\*\)NULL,\s*PV_NONE,', t, re.M)
print(' '.join(rows))
PY
)
n=$(echo $names | wc -w)
[ "$n" -gt 100 ] || { echo "  novar        found only $n rows without a variable -- the pattern stopped matching"; exit 1; }
echo "  novar        $n options have no variable"
# shellcheck disable=SC2086
python3 tools/dropoptions.py "$f" $names

tools/sweep.sh "$f"

# Across lines: a row's flags and its variable are on two, so grep would count 0
# whatever was left -- a check that cannot fail.
left=$(python3 - "$f" <<'PY'
import re, sys
t = open(sys.argv[1], errors='surrogateescape').read()
print(len(re.findall(r'^[ \t]*\{"\w+",\s*(?:"\w*"|NULL),\s*P_[\w|]+,\s*\(char_u ?\*\)NULL,', t, re.M)))
PY
)
[ "$left" = 0 ] || { echo "  novar        $left rows without a variable remain"; exit 1; }
echo "  novar        every option row has a variable"

tools/phasecheck.sh "$work" "$f" .cache/symbols/before

tools/phasebuild.sh "$work" "$before_lines"

d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT
cp "$work/whim-vim" "$d/vim"
(cd "$d" && HOME="$d" ./vim -e -s '+set sw=3' '+q!' </dev/null >/dev/null 2>&1) || { echo "  novar        the control :set sw=3 failed"; exit 1; }
for o in foldmethod cursorline undofile clipboard; do
    if (cd "$d" && HOME="$d" ./vim -e -s "+set $o?" '+q!' </dev/null >/dev/null 2>&1); then
        echo "  novar        :set $o? was accepted"; exit 1
    fi
done
echo "  novar        :set sw works; :set foldmethod, cursorline, undofile and clipboard are unknown"
python3 tools/arrowcheck.py "$work/whim-vim"

# --- the delta, cumulative --------------------------------------------------
tools/whimdelta.sh "$work/whim-vim" "$f" --term-moved --cases bomb_on,filter,read_cmd,retab,sort_u,sort_n,ff_dos,binary_mode \
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
