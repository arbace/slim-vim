#!/bin/sh
# Whim phase 76 -- one regexp engine, so no retry.  See WHIM-GOAL.md.
#
# Usage: pipes/whim76-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# PROVED BY A SINGLE ASSIGNMENT.  `prog->re_engine = BACKTRACKING_ENGINE` is the only
# place re_engine is ever written, so the field can hold no other value -- and both
#
#     if (rmp->regprog->re_engine == AUTOMATIC_ENGINE && result == -1)
#
# blocks, one in vim_regexec_string and one in vim_regexec_multi, are unreachable.
# They exist to recompile a pattern with the backtracking engine when the automatic
# choice failed; with one engine there is nothing to fall back to.  nfa_regengine and
# regexp_engine are already at zero mentions -- the NFA engine went in an earlier
# phase and these two blocks are what was left pointing at its corpse.
#
# WHAT GOES WITH THEM:
#   * p_re entirely.  It is an ORPHAN OPTION -- no row in the option table, so it can
#     never be set and reads as 0 -- and its only uses are the `< 0 || > 2`
#     validation, which can therefore never fire, and the save/restore inside the two
#     dead blocks.
#   * AUTOMATIC_ENGINE, which has no other reader.
#   * nfa_regprog_T and nfa_state_T, by cascade: their only non-type mentions are the
#     two `((nfa_regprog_T *)rmp->regprog)->pattern` casts INSIDE the dead blocks.
#     A husk kept alive purely by unreachable code.
#
# Audited before writing: both blocks are 25 lines, carry no break or continue that
# would rebind, contain no label, and are followed by no else -- so fold_never takes
# them without the hazards phases 71, 72 and 75 each ran into.
#
# THE DELTA: none expected.  The blocks never ran, so removing them cannot change a
# match.  Declared empty and left for whimdelta.sh to correct.
set -eu

work=${1:?usage: whim76-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

tools/st.sh edit whim76 "$f"

tools/st.sh cmdidxs "$f" --check >/dev/null

# tools/phaserun.sh sweeps next, then runs pipes/whim76-check.sh.
