#!/bin/sh
# Pure phase 14 -- no tag stack.  See PURE-GOAL.md.
#
# Usage: tools/pure14.sh <work-dir>      (run from the repository root)
#
# A tag jump is the editor discovering, on its own, that a file it was never
# told about exists: get_tagfname() walks 'tags' upward from the current file,
# opens whatever it finds and binary-searches it.  That is filesystem-layout
# knowledge, and it is the largest single item left in the tree.
#
# Retiring the fifteen command rows is most of it.  FOUR ENTRY POINTS ARE NOT
# COMMANDS, and each keeps the whole subtree alive on its own -- which is why
# this needs a tool and not a list:
#
#   * nv_help(), the <Help> key, calls ex_help(), which calls do_tag().  :help
#     has been ex_ni since Phase 1, but the KEY was never cut, so the entire
#     help-tag search survived a phase that thought it had removed it.
#   * nv_tagpop(), CTRL-T, calls do_tag() straight out of nv_cmds[].
#   * ExpandFromContext() dispatches EXPAND_TAGS and EXPAND_HELP.
#   * get_next_completion_match() dispatches CTRL-X CTRL-].
#
# CTRL-] needs nothing: nv_ident() builds the string ":ta " and runs it as an Ex
# command, so retiring the row is enough and the key reports what :tag reports.
#
# NOT removed here: vim_findfile().  'tags' and 'path' searching share it, and
# find_file_in_path_option() still serves :find and gf.  That is a separate
# decision, because gf is a normal-mode command a user would miss.
#
# THE DELTA: fifteen command names report "not implemented"; CTRL-] and CTRL-T
# report the same; the eight tag options stop existing.
set -eu

work=${1:?usage: pure14.sh <work-dir>}
f="$work/pure-vim.c"

before_lines=$(grep -c '' "$f")
tools/symbols.sh "$f" .cache/symbols/before

# --- cut the entry points -------------------------------------------------
python3 tools/notags.py "$f"
python3 tools/retire.py "$f" tag tags tNext tfirst tjump tlast tnext tprevious \
    trewind tselect stag stjump stselect ltag pop
# Six of the eight.  'tags' and 'tagcase' are PV_BOTH -- buffer-local -- and
# their rows also initialise their globals, so removing them leaves p_tags and
# p_tc NULL and the editor segfaults before the first keystroke.  They stay,
# inert, until a phase removes the buffer-local fields properly.
python3 tools/dropoptions.py "$f" tagbsearch taglength tagrelative \
    tagstack tagsecure showfulltag

tools/sweep.sh "$f"

tools/canon.sh "$f"

# An error is not a warning: ask gcc whether it succeeded before asking what it
# complained about, or a failed compile ends the phase with nothing to say.

tools/phasecheck.sh "$work" "$f" .cache/symbols/before

make -C "$work" clean >/dev/null 2>&1 || true
if make -C "$work" >/dev/null 2>&1; then
    echo "  build        ok, $before_lines -> $(grep -c '' "$f") lines, $(stat -c%s "$work/pure-vim") bytes"
else
    echo "  build        FAILED -- rerun by hand: make -C $work"
    exit 1
fi

# --- the delta, cumulative --------------------------------------------------
# ONE row moves, not fifteen.  Retiring a command only shows up in the sweep if
# the command used to SUCCEED: :tag, :tjump and the rest already failed with no
# tags file to read, and ex_ni fails too, so their recorded exit is unchanged.
# :tags listed an empty tag stack and exited 0, and now reports instead.  The
# declared list is what moved, not what was cut.
tools/puredelta.sh "$work/pure-vim" "$f" --cases filter,read_cmd \
    helpclose intro version cd chdir lcd lchdir tcd tchdir pwd recover '!' language \
    tags
