#!/bin/sh
# Whim phase 55 -- no option nothing reads.  See WHIM-GOAL.md.
#
# Usage: tools/whim55.sh <work-dir>      (run from the repository root)
#
# Phase 54 took the options with no variable.  These have one, and nothing but
# the option machinery reads it: the declaration, the row, get_varp() and the
# buffer copy for a local one, set_context_in_set_cmd()'s completion, and a
# did_set_* callback that only validates the value or fills a flag set nothing
# reads (cfc_flags, cia_flags, opfunc_cb).  Setting one of them changed nothing.
#
#   autocompletetimeout cdhome cdpath completetimeout imcmdline secure
#   shellcmdflag shelltemp shellxescape shellxquote shortname ttybuiltin warn
#   xtermcodes commentstring completefuzzycollect completeitemalign helpfile
#   lispoptions operatorfunc
#
# And sixteen terminal codes the editor stores and never sends:
#
#   t_8b t_8f t_EC t_EI t_GP t_RB t_RC t_RF t_RS t_SC t_SH t_SI t_SR t_WP t_XM t_u7
#
# Their KS_ enumerators stay: the built-in terminal tables still name them.
#
# FOUND, NOT LISTED FROM MEMORY: each was checked for a reader outside that
# machinery by its variable (p_xx, b_p_xx, wo_xx, KS_xx), for a by-name use of
# its long or short name, and for what its callback assigns.  The post-greps
# below are the same check, and a new reader of any of them fails the phase.
#
# THE DELTA: none the harnesses record -- no case sets one.  The probes check
# three of them are now unknown.
set -eu

work=${1:?usage: whim55.sh <work-dir>}
f="$work/whim-vim.c"

before_lines=$(grep -c '' "$f")
tools/symbols.sh "$f" .cache/symbols/before

python3 - "$f" <<'PY'
import sys
path = sys.argv[1]
t = open(path, errors='surrogateescape').read()
old = ' || p == (char_u *)&p_cdpath)'
if t.count(old) != 1:
    sys.exit('  unusedopts   the cdpath completion test occurs %d times, expected 1' % t.count(old))
t = t.replace(old, ')')
open(path, 'w', errors='surrogateescape').write(t)
print("  unusedopts   'cdpath' is no longer completed as a directory list")
PY

python3 tools/dropoptions.py "$f" autocompletetimeout cdhome cdpath completetimeout imcmdline secure \
    shellcmdflag shelltemp shellxescape shellxquote ttybuiltin warn xtermcodes \
    completefuzzycollect completeitemalign helpfile operatorfunc \
    t_8b t_8f t_EC t_EI t_GP t_RB t_RC t_RF t_RS t_SC t_SH t_SI t_SR t_WP t_XM t_u7
python3 tools/dropoptions.py "$f" --local shortname commentstring lispoptions

tools/sweep.sh "$f"
python3 tools/droplocal.py "$f" b_p_sn b_p_cms b_p_lop
tools/sweep.sh "$f"

for g in p_act p_cdh p_cdpath p_cto p_imcmdline p_secure p_shcf p_stmp p_sxe p_sxq p_sn b_p_sn \
         p_tbi p_warn p_xtermcodes p_cms b_p_cms p_cfc cfc_flags p_cia cia_flags p_hf p_lop b_p_lop \
         p_opfunc opfunc_cb did_set_commentstring did_set_completefuzzycollect did_set_completeitemalign \
         did_set_helpfile did_set_lispoptions did_set_operatorfunc; do
    n=$(grep -cE -- "\\b$g\\b" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  unusedopts   $g still has $n mentions after the sweep"
        grep -nE -- "\\b$g\\b" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
echo "  unusedopts   no variable, flag set or callback of the 36 is left"

tools/phasecheck.sh "$work" "$f" .cache/symbols/before

tools/phasebuild.sh "$work" "$before_lines"

d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT
cp "$work/whim-vim" "$d/vim"
(cd "$d" && HOME="$d" ./vim -e -s '+set sw=3' '+q!' </dev/null >/dev/null 2>&1) || { echo "  unusedopts   the control :set sw=3 failed"; exit 1; }
for o in shelltemp commentstring t_EI; do
    if (cd "$d" && HOME="$d" ./vim -e -s "+set $o?" '+q!' </dev/null >/dev/null 2>&1); then
        echo "  unusedopts   :set $o? was accepted"; exit 1
    fi
done
echo "  unusedopts   :set sw works; :set shelltemp, commentstring and t_EI are unknown"

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
