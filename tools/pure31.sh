#!/bin/sh
# Pure phase 31 -- nobody owns a file.  See PURE-GOAL.md.
#
# Usage: tools/pure31.sh <work-dir>      (run from the repository root)
#
# An embedded editor runs where there are no users to tell apart, so asking who
# you are is asking a question with no answer.  Four places were still asking.
#
#   * `:w!` on a read-only file makes it writable first, but only IF YOU OWN IT.
#     The ownership test goes and the chmod stays: where the test used to say
#     no, the chmod now says no instead, and the same error comes back.
#   * when a write fails and `!` retries, the mode is masked to 0777 -- dropping
#     setuid, setgid and sticky -- but only if you are not the owner.  The test
#     goes and THE MASKING STAYS, which is the safe direction.
#   * 'modeline' is forced off when getuid() == ROOT_UID.  There is no root here
#     and no +eval for a modeline to reach.
#   * get_user_name() was stubbed to `return FAIL;` in phase 23, when the
#     password database went, and its two callers were left writing the answer
#     into the swap file's block zero.  The second one's `else` has been dead
#     since then, because the condition it guarded was already always true.
#
# WHAT STAYS: chmod and fchmod, through mch_setperm() and mch_fsetperm().
# PERMISSIONS ARE NOT OWNERSHIP.  A file still has a mode, `:w!` still has to
# clear the read-only bit, and the mode of the file that was there is still put
# back on the one that replaces it.  Removing those would take `:w!` on a
# read-only file with them, which is a capability and not a concept.
#
# THE DELTA: none the harness records.
set -eu

work=${1:?usage: pure31.sh <work-dir>}
f="$work/pure-vim.c"

before_lines=$(grep -c '' "$f")
tools/symbols.sh "$f" .cache/symbols/before

# --- cut the entry points -------------------------------------------------
python3 tools/noowner.py "$f"


tools/sweep.sh "$f"

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
