#!/bin/sh
# Pure phase 30 -- a write is a write.  See PURE-GOAL.md.
#
# Usage: tools/pure30.sh <work-dir>      (run from the repository root)
#
# Writing a file in vim is not one operation.  Before the new contents go
# anywhere, the old file may be renamed or copied aside, its permissions, owner,
# group, ACL and timestamps carried over, the write attempted, and the whole
# thing rolled back if it fails -- and afterwards the copy is kept, or deleted,
# or renamed again for 'patchmode'.  That is 437 lines of buf_write(), and what
# the seven backup options are between them.
#
# dobackup IS THE HINGE.  It is (p_wb || p_bk || *p_pm != NUL), so with the
# options gone it is FALSE, `backup` stays NULL and `backup_copy` stays FALSE --
# and the tests spread through the rest of buf_write() each collapse to the
# branch they already took under `:set nobackup nowritebackup`, a configuration
# vim has always supported.
#
# THREE THINGS FALL OUT: vim_rename() has five callers and all five are in here,
# so vim_copyfile() goes with it -- readlink, symlink and rename.
# set_file_time() carried the old timestamps onto the backup -- utime, one
# caller.  And mch_get_acl()/mch_set_acl()/mch_free_acl() are already stubs,
# because this build has no ACL support; they went unnoticed because a stub
# compiles.
#
# 'backupcopy' IS PV_BOTH, so the rows go with --local and the buffer field with
# droplocal.py afterwards -- the pairing phase 14 records, and the ordering is
# forced: the option callbacks read the field, so the sweep that removes them
# has to run between the rows and the field.
#
# THE DELTA: none the harness records.  :w writes; it just stops leaving a ~
# file beside what it wrote, which no harness asked for.
set -eu

work=${1:?usage: pure30.sh <work-dir>}
f="$work/pure-vim.c"

before_lines=$(grep -c '' "$f")
tools/symbols.sh "$f" .cache/symbols/before

# --- cut the entry points -------------------------------------------------
python3 tools/nobackup.py "$f"
python3 tools/dropoptions.py "$f" --local --strict \
    backup backupcopy backupdir backupext backupskip patchmode writebackup


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

tools/canon.sh "$f"



tools/phasecheck.sh "$work" "$f" .cache/symbols/before

for g in utime readlink symlink rename; do
    if grep -qx -- "$g" .cache/symbols/last/undefined; then
        echo "  symbols      $g is still undefined in the object"
        exit 1
    fi
done
echo "  symbols      utime, readlink, symlink and rename are gone from nm -u"

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

# --- the delta, cumulative --------------------------------------------------
tools/puredelta.sh "$work/pure-vim" "$f" --term-moved --cases bomb_on,filter,read_cmd \
    helpclose intro version cd chdir lcd lchdir tcd tchdir pwd '!' language \
    tags preserve swapname mkvimrc mkexrc checktime
