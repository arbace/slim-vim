#!/bin/sh
# Whim phase 25, the check -- a write is a write, and nobody owns it.
# See pipes/whim25-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim25-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim25-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim25-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim25-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

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


tools/phasecheck.sh "$work" "$f" "$state/symbols"
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

tools/phasebuild.sh "$work" "$before_lines"

# THE CHECK THIS PHASE EXISTS FOR, and no build can make it: overwriting a file
# must leave the file and nothing beside it.  `:set backup` is what would have
# produced `f.txt~`, and the option is gone -- so the test is that the directory
# holds exactly what it held before.
bk=$(cd "$work" && rm -rf .bktest && mkdir .bktest && cd .bktest \
     && printf 'one\n' > f.txt \
     && ../whim-vim -e -s -c '%s/one/two/' -c 'wq' f.txt </dev/null >/dev/null 2>&1
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
     && ../whim-vim -e -s -c '%s/one/two/' -c 'wq!' f.txt </dev/null >/dev/null 2>&1
     cat f.txt 2>/dev/null)
chmod -R u+w "$work/.rotest" 2>/dev/null || true
rm -rf "$work/.rotest"
if [ "$ro" != "two" ]; then
    echo "  readonly     :w! over a read-only file gave '$ro', expected 'two'"
    exit 1
fi
echo "  readonly     :w! over a read-only file still writes it"
