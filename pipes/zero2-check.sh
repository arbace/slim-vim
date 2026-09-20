#!/bin/sh
# Zero phase 2, the check -- the terminal warnings, the pause and --ttyfail.
# See pipes/zero2-edit.sh, and ZERO-GOAL.md.
#
# Usage: pipes/zero2-check.sh <work-dir> <state-dir>     (run from the repository root)
#
# Runs after pipes/zero2-edit.sh and the sweep tools/phaserun.sh runs between them,
# and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.  What the edit left there is `old`, the
# binary this phase was HANDED, built from the boundary's own makefile flags.
#
# THE PROBES ARE THIS PHASE'S EVIDENCE, and they are two-sided for the reason phase
# 1's symbol check is: the three harnesses tools/zerodelta.sh runs cannot see this
# cut at all -- behaviour.py and exsweep.py run the editor `-e -s`, where
# exmode_active takes check_tty()'s first branch, and termcheck.py drives a real pty
# where neither stream is a file.  So the declared delta is legitimately "none", and
# a delta of none from a blind harness proves nothing on its own.  Every probe below
# therefore requires the OLD binary to do the thing and the new one not to.
set -eu

work=${1:?usage: zero2-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero2-check.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"
before_lines=$(cat "$state/input-lines")

# --- 1. what the cut removed -------------------------------------------------------
for gone in tty_fail ttyfail 'Vim: Warning: Output is not to a terminal' \
            'Vim: Warning: Input is not from a terminal' 'ui_delay(2005L'; do
    n=$(grep -cF -- "$gone" "$f" || true)
    [ "$n" = 0 ] || { echo "  nottywarn    '$gone' still has $n mentions"; exit 1; }
done
# COUNTED IN OCCURRENCES, NOT LINES.  `grep -c` counts matching lines, and
# `!isatty(fd) && isatty(read_cmd_fd)` puts two calls on one -- which is how the
# five isatty calls below first read as four and failed a check that was right.
occurrences() {
    grep -oE -- "$1" "$2" | grep -c '' || true
}
n=$(occurrences '\bui_delay\(' "$f")
[ "$n" = 10 ] || { echo "  nottywarn    ui_delay is named $n times, expected 10 (8 calls, a prototype and the definition)"; exit 1; }

# --- 2. what it deliberately kept, and the reader that forces each -----------------
# Each of these is a thing the survey said must survive; a sweep that took one of
# them anyway would leave the editor silently different rather than fail to build.
grep -q '^check_tty(void)$' "$f" || { echo "  nottywarn    check_tty(void) is gone"; exit 1; }
grep -q '^    check_tty();$' "$f" || { echo "  nottywarn    nothing calls check_tty()"; exit 1; }
body=$(awk '/^check_tty\(void\)$/,/^\}$/' "$f")
printf '%s\n' "$body" | grep -q 'input_isatty = mch_input_isatty();' \
    || { echo "  nottywarn    check_tty no longer asks mch_input_isatty()"; exit 1; }
printf '%s\n' "$body" | grep -q 'if (exmode_active)' \
    || { echo "  nottywarn    the exmode_active branch went -- Ex mode is a later phase, not this one"; exit 1; }
printf '%s\n' "$body" | grep -q 'silent_mode = TRUE;' \
    || { echo "  nottywarn    Ex mode no longer goes silent when its input is not a terminal"; exit 1; }
grep -q 'int out_redir = !stdout_isatty;' "$f" \
    || { echo "  nottywarn    stdout_isatty lost the reader that keeps it, and mch_check_win, alive"; exit 1; }
grep -q 'stdout_isatty = (mch_check_win(' "$f" \
    || { echo "  nottywarn    nothing assigns stdout_isatty any more"; exit 1; }
n=$(occurrences '\bisatty\(' "$f")
[ "$n" = 5 ] || { echo "  nottywarn    isatty is called $n times, expected the same 5: this phase folds no isatty caller"; exit 1; }
grep -q 'if (params.want_full_screen && !silent_mode)' "$f" \
    || { echo "  nottywarn    want_full_screen lost its surviving reader"; exit 1; }
# The case the flag lived in still does both halves of its job.
n=$(awk '/^command_line_scan\(mparm_T/,/^\}$/' "$f" | grep -c 'had_minmin = TRUE;' || true)
[ "$n" = 1 ] || { echo "  nottywarn    '--' sets had_minmin $n times, expected once"; exit 1; }
echo "  nottywarn    kept: the exmode branch, mch_input_isatty, stdout_isatty's reader, mch_check_win, all 5 isatty calls"

# --- 3. the compile, the linkage and the libc surface ------------------------------
tools/phasecheck.sh "$work" "$f" "$state/symbols"

# --- 4. the binary -----------------------------------------------------------------
# NOT tools/phasebuild.sh, which links the object tools/sweep.sh compiled along the
# way -- and that object is `gcc -c -O0` with this machine's default flags, which
# since zero phase 1 are not zero's: it carries the stack canaries -fno-stack-protector
# takes out, and PIE code where the link is -no-pie.  Linking it would produce a
# binary that is not what the boundary's makefile builds, and every probe below
# would be run against the wrong file.  A full compile of 86,000 lines is 3.6
# seconds and is the honest one.
make -C "$work" clean >/dev/null 2>&1 || true
if ! make -C "$work" >/dev/null 2>&1; then
    echo "  build        FAILED -- rerun by hand: make -C $work"
    exit 1
fi
bin="$work/zero-vim"
echo "  build        ok, $before_lines -> $(grep -c '' "$f") lines, $(stat -c%s "$bin") bytes"

# --- 5. the probes -----------------------------------------------------------------
d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT
mkdir -p "$d/h" "$d/old" "$d/new"
# Staged as `vim` under both names: a vim binary reads its own argv[0], and a
# basename starting with r, e, g or the view/ex prefixes is a different editor.
cp "$state/old" "$d/old/vim"
cp "$bin" "$d/new/vim"
printf 'ihello world\033:q!\r' > "$d/keys"

# No -u NONE: an empty $HOME, $VIM, $VIMRUNTIME and $XDG_CONFIG_HOME are the
# isolation, as in every harness here, and whim-vim has had no -u since its phase 18.
run() {
    w="$d/$1"
    shift
    ( cd "$w" && env -u VIMINIT -u EXINIT -u MYVIMRC \
        HOME="$d/h" VIM="$d/h/novim" VIMRUNTIME="$d/h/novim" \
        XDG_CONFIG_HOME="$d/h/xdg" TERM=xterm "$@" )
}

# 5a.  stdin a file of keystrokes, stdout a file: the case the warnings were for.
for side in old new; do
    printf 'one\ntwo\nthree\n' > "$d/$side/f.txt"
    t0=$(date +%s%N)
    rc=0
    run "$side" ./vim f.txt <"$d/keys" >"$d/$side.out" 2>"$d/$side.err" || rc=$?
    t1=$(date +%s%N)
    echo $(( (t1 - t0) / 1000000 )) > "$d/$side.ms"
    echo "$rc" > "$d/$side.rc"
done
for side in old new; do
    [ "$(cat "$d/$side.rc")" = 0 ] \
        || { echo "  nottywarn    the $side binary exited $(cat "$d/$side.rc") on a redirected run, expected 0"; exit 1; }
done
# The old binary must warn, and must pause, or the two requirements below could not
# fail.  A compiler or an upstream that had already removed them would be reported
# here rather than silently passing.
for want in 'Output is not to a terminal' 'Input is not from a terminal'; do
    grep -qF "$want" "$d/old.err" \
        || { echo "  nottywarn    the input binary did not print '$want' -- the check below proves nothing"; exit 1; }
done
old_ms=$(cat "$d/old.ms")
new_ms=$(cat "$d/new.ms")
[ "$old_ms" -ge 1500 ] \
    || { echo "  nottywarn    the input binary took ${old_ms}ms, so it did not pause -- the timing check proves nothing"; exit 1; }
if [ -s "$d/new.err" ]; then
    echo "  nottywarn    stderr is not empty after the cut:"
    sed 's/^/               /' "$d/new.err"
    exit 1
fi
[ "$new_ms" -le 500 ] \
    || { echo "  nottywarn    the redirected run still takes ${new_ms}ms, expected under 500 with the pause gone"; exit 1; }
if ! cmp -s "$d/old.out" "$d/new.out"; then
    echo "  nottywarn    the escape stream MOVED: $(stat -c%s "$d/old.out") -> $(stat -c%s "$d/new.out") bytes"
    echo "               only the warnings and the pause were to go, not what is drawn"
    exit 1
fi
[ "$(tr '\n' '|' < "$d/new/f.txt")" = 'one|two|three|' ] \
    || { echo "  nottywarn    :q! wrote the file"; exit 1; }
echo "  nottywarn    redirected: stderr $(stat -c%s "$d/old.err") -> 0 bytes, ${old_ms}ms -> ${new_ms}ms, the $(stat -c%s "$d/new.out")-byte stream byte-identical"

# 5b.  --ttyfail is now an unknown option.  Both binaries exit 1 -- the old one
# because the flag asked it to, the new one because the flag does not exist -- so
# the status is not the check; what mainerr() prints is.
for side in old new; do
    printf 'one\ntwo\n' > "$d/$side/t.txt"
    rc=0
    run "$side" ./vim --ttyfail t.txt </dev/null >/dev/null 2>"$d/$side.tf" || rc=$?
    [ "$rc" = 1 ] || { echo "  nottywarn    the $side binary exited $rc on --ttyfail, expected 1"; exit 1; }
done
if grep -qF 'Unknown option argument: "--ttyfail"' "$d/old.tf"; then
    echo "  nottywarn    the input binary already rejected --ttyfail -- this check proves nothing"
    exit 1
fi
if ! grep -qF 'Unknown option argument: "--ttyfail"' "$d/new.tf"; then
    echo "  nottywarn    --ttyfail is not an unknown option:"
    sed 's/^/               /' "$d/new.tf"
    exit 1
fi

# 5c.  and the rest of that switch case, and the two argument forms next to it,
# still work -- the same result from both binaries.
printf 'z\n' > "$d/old/-x.txt"; printf 'z\n' > "$d/new/-x.txt"
for side in old new; do
    rc=0
    run "$side" ./vim -e -s '+1' '+normal! A-dd' '+wq' -- -x.txt </dev/null >/dev/null 2>&1 || rc=$?
    [ "$rc" = 0 ] || { echo "  nottywarn    '--' as end of options exited $rc on the $side binary"; exit 1; }
    [ "$(tr '\n' '|' < "$d/$side/-x.txt")" = 'z-dd|' ] \
        || { echo "  nottywarn    '--' stopped ending the options on the $side binary"; exit 1; }

    printf 'one\ntwo\n' > "$d/$side/c.txt"
    rc=0
    run "$side" ./vim '+normal! A-PLUS' '+wq' c.txt <"$d/keys" >/dev/null 2>/dev/null || rc=$?
    [ "$rc" = 0 ] || { echo "  nottywarn    +cmd exited $rc on the $side binary"; exit 1; }
    [ "$(tr '\n' '|' < "$d/$side/c.txt")" = 'one-PLUS|two|' ] \
        || { echo "  nottywarn    +cmd broke on the $side binary: '$(tr '\n' '|' < "$d/$side/c.txt")'"; exit 1; }

    printf 'one\ntwo\n' > "$d/$side/T.txt"
    rc=0
    run "$side" ./vim -T dumb '+normal! A-T' '+wq' T.txt <"$d/keys" >/dev/null 2>/dev/null || rc=$?
    [ "$rc" = 0 ] || { echo "  nottywarn    -T exited $rc on the $side binary"; exit 1; }
    [ "$(tr '\n' '|' < "$d/$side/T.txt")" = 'one-T|two|' ] \
        || { echo "  nottywarn    -T broke on the $side binary: '$(tr '\n' '|' < "$d/$side/T.txt")'"; exit 1; }
done
echo "  nottywarn    --ttyfail is mainerr'd, '--', +cmd and -T unchanged on both binaries"

# 5d.  a real terminal, where nothing here was ever reached: the same session under
# both binaries.  termcheck drives 19 of these in the declared delta; this
# one is the before-and-after the delta cannot give, because it has no old binary.
python3 - "$state/old" "$bin" <<'PY'
import os, re, sys, tempfile
sys.path.insert(0, 'tools')
# tools/ptyrun.py -- named as a PATH so tools/implhash.sh hashes it into this
# phase's key.  implhash greps for paths and an `import` names a module, so
# without this line an edit to it changes what this phase produces and moves
# no key at all.  See CLAUDE.md on cutil.py and macros.py.  Do not delete it.
import ptyrun
ESC = b'\x1b'
home = tempfile.mkdtemp(prefix='zero2-home-')
env = dict(os.environ, HOME=home, VIM=os.path.join(home, 'novim'),
           VIMRUNTIME=os.path.join(home, 'novim'),
           XDG_CONFIG_HOME=os.path.join(home, 'xdg'))
for k in ('VIMINIT', 'EXINIT', 'MYVIMRC'):
    env.pop(k, None)

def one(binary):
    d = tempfile.mkdtemp(prefix='zero2-pty-')
    open(os.path.join(d, 'f.txt'), 'w').write('alpha one\nbeta two\n')
    text, status = ptyrun.session(binary, ['f.txt'],
                                  [b'GA-typed', ESC, b':set term?\r', b':wq\r'],
                                  term='xterm', cwd=d, settle=0.6, env=env)
    s = text.decode('utf-8', 'replace')
    # The two answers land among the '~' filler and the cursor keeps moving through
    # them, so take the name and nothing after it, as termcheck does.
    got = sorted(set(re.findall(r'term=[\w.-]+', s)))
    return status, open(os.path.join(d, 'f.txt')).read(), got, '-typed' in s

old, new = one(sys.argv[1]), one(sys.argv[2])
for name, r in (('old', old), ('new', new)):
    if r[0] != 0 or r[1] != 'alpha one\nbeta two-typed\n' or not r[3] or not r[2]:
        sys.exit('  %-12s the pty session broke on the %s binary: status=%s file=%r term=%s typed=%s'
                 % ('nottywarn', name, r[0], r[1], r[2], r[3]))
if old != new:
    sys.exit('  %-12s the pty session moved: %r -> %r' % ('nottywarn', old, new))
# The `term=` answer is not printed: the ruler follows it on the same screen line,
# so what comes back is 'term=xterm-256color2,14All' and reads like a terminal name
# that does not exist.  termcheck's rows have the same artifact.  What it is
# here for is the comparison, which is exact.
print('  %-12s pty: status 0, the typed text on screen and in the file, the same '
      'term answer either side' % 'nottywarn')
PY
