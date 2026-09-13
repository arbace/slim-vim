#!/bin/sh
# Pure phase 24 -- a write is a write, and nobody owns it.  See PURE-GOAL.md.
#
# Usage: tools/pure27.sh <work-dir>      (run from the repository root)
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

work=${1:?usage: pure27.sh <work-dir>}
f="$work/pure-vim.c"

before_lines=$(grep -c '' "$f")
tools/symbols.sh "$f" .cache/symbols/before

# --- cut the entry points -------------------------------------------------
python3 tools/nobackup.py "$f"
python3 tools/dropoptions.py "$f" --local --strict \
    backup backupcopy backupdir backupext backupskip patchmode writebackup
python3 tools/noowner.py "$f"


tools/sweep.sh "$f"
python3 tools/droplocal.py "$f" b_p_bkc
tools/sweep.sh "$f"

for g in 'p_bk\b' 'p_wb\b' 'p_bkc\b' 'p_bdir\b' 'p_bex\b' 'p_bsk\b' 'p_pm\b' \
         'b_p_bkc' 'vim_rename' 'vim_copyfile' 'set_file_time' 'mch_get_acl' \
         'vim_acl_T' 'backup_copy' 'dobackup'; do
    n=$(grep -c -- "$g" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  backup       $g still has $n mentions after the sweep"
        grep -n -- "$g" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
echo "  backup       nothing is copied aside, renamed, or timestamped"

for g in 'getuid' 'getgid' 'get_user_name' 'ROOT_UID' 'b0_uname'; do
    n=$(grep -c -- "$g" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  owner        $g still has $n mentions after the sweep"
        grep -n -- "$g" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
echo "  owner        nothing asks who you are"

# And the distinction this phase rests on: a file still has a mode.
for g in mch_setperm mch_fsetperm mch_getperm; do
    if [ "$(grep -c "\b$g(" "$f" || true)" = 0 ]; then
        echo "  permissions  $g went too -- permissions are not ownership"
        exit 1
    fi
done
echo "  permissions  chmod and fchmod stay: a file still has a mode"


tools/phasecheck.sh "$work" "$f" .cache/symbols/before
for g in utime readlink symlink rename; do
    if grep -qx -- "$g" .cache/symbols/last/undefined; then
        echo "  symbols      $g is still undefined in the object"
        exit 1
    fi
done
echo "  symbols      utime, readlink, symlink and rename are gone from nm -u"
for g in getuid getgid; do
    if grep -qx -- "$g" .cache/symbols/last/undefined; then
        echo "  symbols      $g is still undefined in the object"
        exit 1
    fi
done
echo "  symbols      getuid and getgid are gone from nm -u"

make -C "$work" clean >/dev/null 2>&1 || true
if make -C "$work" >/dev/null 2>&1; then
    echo "  build        ok, $before_lines -> $(grep -c '' "$f") lines, $(stat -c%s "$work/pure-vim") bytes"
else
    echo "  build        FAILED -- rerun by hand: make -C $work"
    exit 1
fi

# THE CHECK THIS PHASE EXISTS FOR, and no build can make it: overwriting a file
# must leave the file and nothing beside it.  `:set backup` is what would have
# produced `f.txt~`, and the option is gone -- so the test is that the directory
# holds exactly what it held before.
bk=$(cd "$work" && rm -rf .bktest && mkdir .bktest && cd .bktest \
     && printf 'one\n' > f.txt \
     && ../pure-vim -e -s -c '%s/one/two/' -c 'wq' f.txt </dev/null >/dev/null 2>&1
     printf '%s:%s' "$(ls -A | tr '\n' ' ')" "$(cat f.txt)")
rm -rf "$work/.bktest"
if [ "$bk" != "f.txt :two" ]; then
    echo "  overwrite    a write left '$bk', expected 'f.txt :two'"
    exit 1
fi
echo "  overwrite    overwriting a file leaves the file, and nothing beside it"

# The capability this phase must NOT have removed: `:w!` over a read-only file.
# No harness writes to one, which is why it is checked here.
ro=$(cd "$work" && rm -rf .rotest && mkdir .rotest && cd .rotest \
     && printf 'one\n' > f.txt && chmod 444 f.txt \
     && ../pure-vim -e -s -c '%s/one/two/' -c 'wq!' f.txt </dev/null >/dev/null 2>&1
     cat f.txt 2>/dev/null)
chmod -R u+w "$work/.rotest" 2>/dev/null || true
rm -rf "$work/.rotest"
if [ "$ro" != "two" ]; then
    echo "  readonly     :w! over a read-only file gave '$ro', expected 'two'"
    exit 1
fi
echo "  readonly     :w! over a read-only file still writes it"

# --- the delta, cumulative --------------------------------------------------
tools/puredelta.sh "$work/pure-vim" "$f" --term-moved --cases bomb_on,filter,read_cmd \
    helpclose intro version cd chdir lcd lchdir tcd tchdir pwd '!' language \
    tags preserve swapname mkvimrc mkexrc checktime
