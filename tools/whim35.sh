#!/bin/sh
# Whim phase 35 -- insert completion and the popup menu.  See WHIM-GOAL.md.
#
# Usage: tools/whim35.sh <work-dir>      (run from the repository root)
#
# CTRL-N and CTRL-P complete the word being typed, and CTRL-X opens a submenu of
# sources: the current file, 'dictionary', 'thesaurus', tags, file names,
# spelling, whole lines, the command line, a register, a user function.  Almost
# none of those still exists -- tags went in phase 12, spelling was never in a
# tiny build, 'completefunc' needs +eval, and file-name completion goes through
# the globbing phase 9 removed.
#
# THE CUT IS FIVE STUBS AND THE SWEEP, and it works because the subsystem is
# reached only through predicates: edit() has SIXTEEN `goto docomplete` sites and
# every one is guarded by ctrl_x_mode_*(), pum_visible(), ins_compl_active() or
# ins_compl_has_autocomplete().  Answer those honestly and every branch is dead;
# funcreach.py then takes the interior.
#
# THE DELTA: none the harness records.  No behaviour case types CTRL-N -- the
# phase checks that itself, in a pty, because a popup menu needs a screen.
set -eu

work=${1:?usage: whim35.sh <work-dir>}
f="$work/whim-vim.c"

before_lines=$(grep -c '' "$f")
tools/symbols.sh "$f" .cache/symbols/before

# --- cut the entry points -------------------------------------------------
python3 tools/nocompl.py "$f"
python3 tools/dropoptions.py "$f" --local \
    autocomplete complete completefunc completeopt dictionary infercase \
    pumborder pummaxwidth pumopt \
    pumheight pumwidth thesaurus


tools/sweep.sh "$f"
python3 tools/droplocal.py "$f" b_p_cpt b_p_cot b_p_dict b_p_tsr b_p_inf b_p_ac
tools/sweep.sh "$f"

# WORD-ANCHORED, because these names nest: `pum_redraw` is a prefix of
# `pum_redraw_in_same_position`, which this phase KEEPS as a stub, so a
# substring count says the cut failed when it did not.  Same shape as the
# droplocal bug phase 31 found.
for g in ins_compl_get_exp pum_redraw ins_compl_next b_p_cpt b_p_dict p_pumheight; do
    n=$(grep -cE -- "\\b$g\\b" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  compl        $g still has $n mentions after the sweep"
        grep -n -- "$g" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
echo "  compl        no sources, no match array, no popup menu"

tools/phasecheck.sh "$work" "$f" .cache/symbols/before

make -C "$work" clean >/dev/null 2>&1 || true
if make -C "$work" >/dev/null 2>&1; then
    echo "  build        ok, $before_lines -> $(grep -c '' "$f") lines, $(stat -c%s "$work/whim-vim") bytes"
else
    echo "  build        FAILED -- rerun by hand: make -C $work"
    exit 1
fi

# Insert mode must still work, and CTRL-N must now insert nothing rather than
# completing.  In a pty, because a popup menu needs a screen -- under `-e -s`
# neither half would mean anything.
if python3 tools/complcheck.py "$work/whim-vim"; then
    echo "  compl        insert mode still inserts; CTRL-N completes nothing"
else
    echo "  compl        insert mode or CTRL-N is not behaving as declared"
    exit 1
fi

# --- the delta, cumulative --------------------------------------------------
tools/whimdelta.sh "$work/whim-vim" "$f" --term-moved --cases bomb_on,filter,read_cmd \
    helpclose intro version cd chdir lcd lchdir tcd tchdir pwd '!' language \
    tags preserve swapname mkvimrc mkexrc checktime command comclear
