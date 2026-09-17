#!/bin/sh
# Whim phase 55, the check -- no option nothing reads.
# See pipes/whim55-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim55-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim55-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim55-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim55-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

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

tools/phasecheck.sh "$work" "$f" "$state/symbols"

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
