#!/bin/sh
# Whim phase 70 -- :e reloads in place, and there is no swap file.  See WHIM-GOAL.md.
#
# Usage: pipes/whim70-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# THIS INVARIANT IS IMPOSED, NOT PROVED, and that is the difference between it and
# phase 68.  One window fell out of the two places a window could be created.  A
# second BUFFER is genuinely reachable: curbuf_reusable() wants an unnamed, empty
# buffer, so once the first file is named, `:e other` allocates a new buf_T and
# switches to it.  Measured on q69: `:e h2.txt` then `+wq h1.txt` writes h2.
#
# So do_ecmd() is made to reuse the one buffer:
#
#   * the other_file branch renames curbuf with setfname() instead of calling
#     buflist_new(), sets oldbuf = FALSE, and falls through;
#   * the reload path below it -- u_sync(), u_savecommon(), buf_freeall(curbuf,
#     BFA_KEEP_UNDO), then open_buffer(... READ_KEEP_UNDO) -- ALREADY IS "wipe and
#     re-read in place".  Its gate widens from `!other_file && !oldbuf` to `!oldbuf`;
#   * the whole `if (buf != curbuf)` block goes: BufLeave, buf_copy_options, u_sync,
#     close_buffer(DOBUF_WIPE), the auto_buf dance, the curwin->w_buffer swap and
#     get_winopts.  It is removed by brace matching, not by matching its body.
#
# ORDER: fname2fnum() FIRST.  It calls buflist_new(name, p, 1, 0) to give a file
# mark's file a buffer, and once reuse is unconditional that call would wipe the
# buffer being edited.  Folded to nothing; getmark_buf_fnum() already treats a zero
# fnum as "not in a buffer".
#
# NO SWAP FILE, EVER -- not even one left from another age.  Swap files are already
# never WRITTEN here: findswapname, p_swf, swapfile_info, swapfile_unchanged,
# ml_recover and ml_sync_all are gone, mf_open() is the in-memory memfile, and
# ml_open_file() had been reduced to a single `b_may_swap = FALSE`.  What survived
# was the DETECTION prompt, and it was already unreachable: measured on q69, a .swp
# sitting beside the file produces no prompt at all, and the edit and the write go
# through in silence.  So swap_exists_action, the three SEA_* actions,
# handle_swap_exists(), check_swap_exists_action(), check_need_swap(), ml_open_file()
# and the b_may_swap field all go together -- vestigial scaffolding, the can_cindent
# shape again: a flag written in three places and never true.
#
# The one test that was not obviously dead is in changed(), not buf_write -- the
# first change to a buffer used to open its swap file there.  It is folded away.
#
# WHAT IS LOST: the state of the file you leave -- its undo history and its marks.
# `:e` and `:wq` keep working, on one buffer.  What stays: the load path, the
# argument-free reload (`:e` with no name), and :e! discarding changes.
#
# THE DELTA: none expected.  :e prints nothing to stderr, and an exsweep row is
# `exit= left= err=` -- the same reason :next did not move in phase 69.  Declared
# empty and left for whimdelta.sh to correct.
set -eu

work=${1:?usage: whim70-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

tools/st.sh edit whim70 "$f"

tools/st.sh cmdidxs "$f" --check >/dev/null

# tools/phaserun.sh sweeps next, then runs pipes/whim70-check.sh.
