#!/bin/sh
# Whim phase 25 -- a write is a write, and nobody owns it.  See WHIM-GOAL.md.
#
# Usage: pipes/whim25-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# TWO CUTS IN ONE PHASE, and they are one story: everything writing a file did
# beyond writing it.
#
# THE BACKUP.  Before the new contents go anywhere the old file may be renamed
# or copied aside, its permissions, owner, group, ACL and timestamps carried
# over, the write attempted, and the whole thing rolled back if it fails -- and
# afterwards the copy is kept, or deleted, or renamed again for 'patchmode'.
# That is 437 lines of buf_write() and seven options.  `dobackup` is the hinge:
# (p_wb || p_bk || *p_pm != NUL), so with the options gone it is FALSE and the
# tests through the rest of the function collapse to the branch they already
# took under `:set nobackup nowritebackup`.
#
# vim_rename() has five callers and all five are in there, so vim_copyfile()
# goes with it -- readlink, symlink, rename.  set_file_time() carried the old
# timestamps onto the backup -- utime.  mch_get_acl()/mch_set_acl()/
# mch_free_acl() were already stubs, this build having no ACL support.  fchown
# and umask went too: every call to both was inside the backup block.
#
# THE OWNER.  An embedded editor runs where there are no users to tell apart,
# so `st_old.st_uid == getuid()` is a question with no answer.  `:w!` clears the
# read-only bit without asking whose file it is; the mode is masked to 0777
# always rather than only for a stranger, which is the safe direction;
# 'modeline' stops asking whether this is root; and get_user_name(), a stub
# since phase 20, stops being called at all.
#
# WHAT STAYS: chmod and fchmod.  PERMISSIONS ARE NOT OWNERSHIP -- a file still
# has a mode, `:w!` still has to clear the read-only bit, and the mode of the
# file that was there is still put back on the one that replaces it.
#
# THE TWO CUTS ARE ONE PHASE because the second's sites are inside the code the
# first reshapes, and because neither moves anything the harness records.  The
# phase still checks both separately: nothing is left beside a written file, and
# `:w!` over a read-only file still writes it.
#
# THE DELTA: none the harness records.
set -eu

work=${1:?usage: whim25-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

# --- cut the entry points -------------------------------------------------
tools/st.sh nobackup "$f"
tools/st.sh dropoptions "$f" --local --strict \
    backup backupcopy backupdir backupext backupskip patchmode writebackup
tools/st.sh noowner "$f"

# No sweep here.  One stood here, and the lines after it were written for swept text,
# but this phase and every stage it has run in reproduce their boundaries without
# it (WHIM-PLAN.md 2c; pipes/whim.stages) -- the stage's one sweep does its work.
tools/st.sh droplocal "$f" b_p_bkc

# tools/phaserun.sh sweeps next, then runs pipes/whim25-check.sh.
