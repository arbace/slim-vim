#!/bin/sh
# Zero phase 13, the check -- no `FILE *` that is never opened.
# See pipes/zero13-edit.sh, and ZERO-GOAL.md.
#
# Usage: pipes/zero13-check.sh <work-dir> <state-dir>    (run from the repository root)
#
# Runs after pipes/zero13-edit.sh and the sweep tools/phaserun.sh runs between them,
# and reads nothing from the edit's shell -- only the work tree and the state
# directory.  What the edit left there is `old`, the binary this phase was HANDED,
# and `old.c`, the source it was built from.
#
# NOTHING THIS PHASE REMOVES IS REACHABLE, so there is no behavioural must-differ
# probe and no dishonest one is offered instead.  It is phase 9's situation and phase
# 9's answer: the source the phase was handed, built TWICE.
#
#   probe  `(void)write(2, "FILESTAR-ENTERED\n", 17);` at FIVE places -- the top of
#          `closescript()`, inside `inchar()`'s `getc(scriptin[curscript])` loop,
#          inside `redir_write()`'s `redirecting()` block, inside `undo_cmdmod`'s,
#          and the top of `vim_fsync()`.  ZERO of the 106 records may carry it.
#   ctl    the IDENTICAL instrument at the top of `ui_write()`, which is reached by
#          every byte the editor draws.  It must mark almost all of them, and the
#          zero above is worth nothing without it.
#
# FIVE THINGS ARE PROVED.
#
# 1. THE COUNTS, WHICH ARE THE REST OF THE ARGUMENT.  `FILE` at **0 mentions** is the
#    cleanest single assertion this phase has: the type is not named in `zero-vim.c`
#    at all afterwards.  With it go `scriptin`, `curscript`, `NSCRIPT`,
#    `saved_typebuf`, `closescript`, `using_script`, `redir_fd`, `redir_off`,
#    `redir_write`, `redirecting`, `vim_fsync` and the two hand-folded locals
#    `script_char` and `retesc`.
#
#    THE TRAPS, ALL MEASURED:
#      * `may_sync_undo()` AND `is_safe_now()` MUST NOT BE DELETED.  Both survive one
#        conjunct shorter and still do their real work, and a check that expected
#        them at 0 would fail on a correct phase.
#      * `fputs` DOES NOT LEAVE, and ZERO-PLAN.md row 12 says it does.  After this
#        phase the source names it nowhere and `nm -u` still lists it: gcc lowers
#        `fprintf(stderr, "...")` to it, exactly as it lowers `printf` to `fputc`,
#        `fwrite` and `putchar`.  The freed set is asserted as exactly
#        `fclose fsync getc putc`.
#      * `fsync` IS THIS PHASE'S, not the buffer-name phase's: its only caller was
#        `vim_fsync()`, whose only caller was `ui_write()`'s `console` branch.
#      * `retesc` is a LOCAL THAT IS READ AND NEVER WRITTEN after the loop goes. No
#        warning covers it, `deadsweep.py` does not act on it, and leaving it would
#        mean `inchar()` returns an uninitialised value on a path the compiler thinks
#        exists.  `did_return` is the same shape.  Both were folded by hand.
#      * `NSCRIPT` is the one enumerator that leaves, and NOTHING RENUMBERS.
#
# 2. THE LIBC SURFACE, NAMED AS A SET AND NOT AS A COUNT -- `fclose getc putc fsync`
#    and nothing else -- and ZERO-PLAN.md 4b's invariant asserted in its strongest
#    form: `open creat openat stat access fcntl getcwd strerror fopen fdopen opendir`
#    absent from BOTH the source and the undefined set.  After this phase the core
#    has no `open`, no `stat`, no stdio stream and no fourth descriptor: it can only
#    read, write, close and dup fds 0, 1 and 2.
#
# 3. THE INSTRUMENTED PAIR, above.
#
# 4. EIGHTEEN ADVERSARIAL SESSIONS on both instrumented binaries, because "nothing
#    reaches it" is a claim about every input and not about the corpus: `:messages`,
#    `:verbose set ai?`, `:silent echo`, `:history`, `:registers`, `:display`, `ga`,
#    an unknown command, `:set all`, `:marks`, `:undolist`, `:changes`, `:map`,
#    `:highlight`, `:normal ihi`, `:g/a/p`, a recorded-and-replayed register and
#    `:set verbose=9` -- every one of them a way of making the editor PRINT, which is
#    where `redir_write()` sat.  Each must reach `ui_write()` and none may reach any
#    of the five.
#
# 5. AND THE ORDINARY SESSIONS, byte-identical either side, each required to be doing
#    something.  The corpus itself is `tools/zerodelta.sh --phase 13`, which
#    tools/phaserun.sh runs after this check.
set -eu

work=${1:?usage: zero13-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero13-check.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"
before_lines=$(cat "$state/input-lines")

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# The two instrumented builds are started first and waited for in section 3: they are
# seconds of wall time the source checks below can be spending instead.  The flags are
# the boundary's, as everywhere (ZERO-GOAL.md rule 8).
cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")
mkdir -p "$tmp/i"
python3 - "$state/old.c" "$tmp/i" <<'PY'
import sys
src, out = sys.argv[1], sys.argv[2]
TAG = 'nofile'
MARK = '    (void)write(2, "FILESTAR-ENTERED\\n", 17);\n'
t = open(src, errors='surrogateescape').read()

# FIVE PLACES, and each is a place the FILE* would have to be non-NULL to reach.
# They are exact text and counted: an instrument that silently lands nowhere would
# make the zero below a probe that cannot fail.
SITES = [
    ('closescript(void)\n{\n', 'the top of closescript()'),
    ('    while (scriptin[curscript] != NULL && script_char < 0)\n    {\n',
     "inchar()'s script loop, which is getc()'s only caller"),
    ('    if (redirecting())\n    {\n', "redir_write()'s redirecting() block"),
    ('        if (redirecting())\n        {\n', "undo_cmdmod's redirecting() block"),
    ('vim_fsync(int fd)\n{\n', 'the top of vim_fsync()'),
]
probe = t
for text, what in SITES:
    if probe.count(text) != 1:
        sys.exit('  %-12s %s occurs %d times in the input source, expected 1'
                 % (TAG, what, probe.count(text)))
    probe = probe.replace(text, text + MARK)
open('%s/probe.c' % out, 'w', errors='surrogateescape').write(probe)

# THE CONTROL, and it is the identical instrument: ui_write() is what every byte the
# editor draws goes through, so it must mark almost everything.
CTL = 'ui_write(char_u *s, int len, int console  __attribute__((unused)) )\n{\n'
if t.count(CTL) != 1:
    sys.exit('  %-12s ui_write does not open exactly once in the input source' % TAG)
open('%s/ctl.c' % out, 'w', errors='surrogateescape').write(t.replace(CTL, CTL + MARK))
PY
# shellcheck disable=SC2086
( cd "$tmp/i" && gcc $cflags $ldflags -o probe probe.c ) &
pid_probe=$!
# shellcheck disable=SC2086
( cd "$tmp/i" && gcc $cflags $ldflags -o ctl ctl.c ) &
pid_ctl=$!

# --- 1. what went, recorded -----------------------------------------------------------
for gone in scriptin curscript NSCRIPT saved_typebuf closescript using_script \
            redir_fd redir_off redir_write redirecting vim_fsync script_char \
            retesc did_return FILE; do
    n=$(grep -cw -- "$gone" "$f" || true)
    [ "$n" = 0 ] || { echo "  nofile       '$gone' still has $n mentions"; exit 1; }
done
echo "  nofile       FILE at 0 mentions -- the type is not named in zero-vim.c at all now -- with scriptin, curscript, NSCRIPT, saved_typebuf, closescript, using_script, redir_fd, redir_off, redir_write, redirecting, vim_fsync and the two hand-folded locals"

# --- 2. and everything that must NOT be at zero -------------------------------------
python3 - "$f" "$state/old.c" <<'PY'
import re, sys
sys.path.insert(0, 'tools')
import create_cmdidxs
import cutil
TAG = 'nofile'
new = open(sys.argv[1], errors='surrogateescape').read()
old = open(sys.argv[2], errors='surrogateescape').read()
fail = []


def count(text, name):
    return len(re.findall(r'\b%s\b' % name, text))


# BOTH OF THESE SURVIVE FOLDED, and a check that expected them at 0 fails on a
# correct phase.  may_sync_undo still runs u_sync() on the rest of its test, and
# is_safe_now is still `stuff_empty() && typebuf.tb_len == 0 && !global_busy`.
KEPT = {'may_sync_undo': 3, 'is_safe_now': 3,
        'free_typebuf': 4,        # 5 before: closescript's call went
        'ui_write': 3, 'mch_write': 2,
        'read_cmd_fd': 12,        # the terminal's, and untouched by this phase
        'p_paste': 12,            # exempt for ever (ZERO-PLAN.md 2d)
        'u_sync': 8}
for name, want in sorted(KEPT.items()):
    k = count(new, name)
    if k != want:
        fail.append('%s has %d mentions, expected %d -- %s'
                    % (name, k, want, 'this phase reached too far'
                       if k < want else 'something survived that should not have'))

# ui_write is two parameters and one statement now.
if not re.search(r'^ui_write\(char_u \*s, int len\)$', new, re.M):
    fail.append('ui_write does not have a two-parameter signature: dropping the '
                'parameter is what makes the cut honest, because sweep.sh compiles '
                'with -Wno-unused-parameter and would never see it')
if 'ui_write(out_buf, len);' not in new:
    fail.append("ui_write's one call site still passes a third argument")
span = cutil.find_definition(new, 'ui_write')
body = new[span[0]:span[1]] if span else ''
if body.count(';') != 1 or 'mch_write' not in body:
    fail.append('ui_write is not mch_write() and nothing else now: %r' % body)

# THE TWO SURVIVORS, read rather than counted: each must have lost exactly the one
# conjunct and kept the rest.
span = cutil.find_definition(new, 'may_sync_undo')
b = new[span[0]:span[1]] if span else ''
if 'scriptin' in b or 'u_sync' not in b or 'arrow_used' not in b:
    fail.append('may_sync_undo is not one conjunct shorter with u_sync() still in '
                'it: %r' % b)
span = cutil.find_definition(new, 'is_safe_now')
b = new[span[0]:span[1]] if span else ''
for keep in ('stuff_empty', 'typebuf.tb_len', 'global_busy'):
    if keep not in b:
        fail.append('is_safe_now lost %s, and it keeps everything but the scriptin '
                    'conjunct' % keep)

# `fputs` STAYS and the source names it NOWHERE.  That pair is the assertion
# ZERO-PLAN.md row 12 gets wrong, and it is checked from the source side here and
# from the `nm -u` side in section 4.
for gccs in ('fputs', 'fputc', 'fwrite', 'putchar'):
    if count(new, gccs):
        fail.append("%s is named in the source, and it should not be -- gcc lowers "
                    'printf and fprintf to it' % gccs)

# THE INVARIANT, FROM THE SOURCE SIDE.  Nothing that could open anything is named.
for absent in ('open', 'creat', 'openat', 'fopen', 'fdopen', 'opendir', 'stat',
               'access', 'fcntl', 'getcwd', 'strerror', 'fclose', 'getc', 'putc',
               'fsync', 'mkdir', 'rename', 'unlink', 'readlink'):
    if re.search(r'(?<![\w.>])%s\s*\(' % absent, new):
        fail.append('%s( is called in the source, and after this phase the core has '
                    'no way to name or open anything' % absent)

# THE TABLE AND THE OPTIONS, neither of which this phase touches.
rows = re.findall(r'^    \[CMD_\w+\] = \{.*$', new, re.M)
got = create_cmdidxs.names(sys.argv[1])
if len(rows) != 98 or len(got) != 98:
    fail.append('cmdnames[] has %d rows and names() reads %d; both must be 98'
                % (len(rows), len(got)))
i, j = new.find('static struct vimoption options[]'), None
j = new.index('\n};', i)
if len(re.findall(r'^[ \t]*\{"([a-z]+)",', new[i:j], re.M)) != 108:
    fail.append('options[] is not the 108 rows phase 12 left')

# What the six anchors cost the old file, as a difference rather than a number.
for name, want in (('scriptin', 8), ('redir_fd', 6), ('redirecting', 4),
                   ('redir_write', 7), ('vim_fsync', 3), ('FILE', 2),
                   ('free_typebuf', 5)):
    if count(old, name) != want:
        fail.append('the input is not the file this phase was written against: '
                    '%s %d, expected %d' % (name, count(old, name), want))
if 'FILESTAR' in old or 'FILESTAR' in new:
    fail.append('the instrument marker is in a source file, and it belongs only to '
                'the two builds this check makes in a temp directory')

if fail:
    for line in fail:
        print('  %-12s %s' % (TAG, line))
    print('  %-12s may_sync_undo and is_safe_now SURVIVE folded, and a check that' % '')
    print('  %-12s expected them at 0 fails on a correct phase; fputs STAYS and is' % '')
    print("  %-12s gcc's own, named nowhere in the source." % '')
    sys.exit(1)
print('  %-12s kept: may_sync_undo 3 and is_safe_now 3, both SURVIVING one conjunct '
      'shorter and still doing their work, free_typebuf 4 (closescript was its fifth '
      'mention), ui_write 3 with a TWO-parameter signature and mch_write() as its '
      'whole body' % TAG)
print('  %-12s fputs, fputc, fwrite and putchar are named nowhere in the source and '
      "are gcc's own -- ZERO-PLAN.md row 12 gives fputs to this phase and it does "
      'not go' % '')
print('  %-12s and nothing that could open or name anything is called: open, creat, '
      'openat, fopen, fdopen, opendir, stat, access, fcntl, getcwd, strerror, '
      'fclose, getc, putc and fsync are absent from the source' % '')
PY

# --- 3. the compile, the linkage and the libc surface -------------------------------
# FOUR SYMBOLS GO AND THE SET IS NAMED, not the count.  `fclose` and `getc` were
# `closescript()`'s and `inchar()`'s script loop's; `putc` was `redir_write()`'s;
# `fsync` was `vim_fsync()`'s, whose only caller was `ui_write()`'s console branch.
# `fputs` does NOT go: gcc lowers fprintf(stderr, ...) to it.
cp "$state/symbols/undefined" "$tmp/before.u"
tools/phasecheck.sh "$work" "$f" "$state/symbols"
comm -23 "$tmp/before.u" .cache/symbols/last/undefined > "$tmp/gone.u"
comm -13 "$tmp/before.u" .cache/symbols/last/undefined > "$tmp/came.u"
printf 'fclose\nfsync\ngetc\nputc\n' > "$tmp/want.u"
if ! cmp -s "$tmp/gone.u" "$tmp/want.u" || [ -s "$tmp/came.u" ]; then
    echo "  nofile       the libc surface did not move by exactly fclose, fsync, getc and putc:"
    echo "               gone: $(tr '\n' ' ' < "$tmp/gone.u")"
    echo "               came: $(tr '\n' ' ' < "$tmp/came.u")"
    exit 1
fi
# THE TERMINAL AND THE MESSAGE LAYER STAY, and are the whole host boundary that is
# left.  `fputs` is asserted STILL undefined beside them, which is the half of
# ZERO-PLAN.md row 12 that is wrong.
for keep in read write close dup ioctl select tcgetattr tcsetattr nanosleep isatty \
            printf fflush stderr fputs fputc fwrite putchar __errno_location; do
    grep -qx "$keep" .cache/symbols/last/undefined \
        || { echo "  nofile       $keep went, and it is not this phase's: read, write, close, dup, ioctl, select, tcgetattr, tcsetattr, nanosleep and isatty are the terminal's, printf, fflush and stderr are the message layer's, and fputs, fputc, fwrite, putchar and __errno_location are gcc's own"; exit 1; }
done
# ZERO-PLAN.md 4b's INVARIANT, in its strongest form: from here the core has no way
# to acquire a file descriptor and no stdio stream either.
for absent in open creat openat stat access fcntl getcwd strerror fopen fdopen \
              opendir chmod fchmod fstat lstat unlink ftruncate fclose getc putc fsync; do
    if grep -qx "$absent" .cache/symbols/last/undefined; then
        echo "  nofile       $absent is undefined, and after this phase the core can neither open a file nor hold a stdio stream"; exit 1
    fi
done
echo "  nofile       symbols $(cat .cache/symbols/last/before) -> $(cat .cache/symbols/last/after), and the set is exactly fclose fsync getc putc -- with open, creat, openat, stat, access, fcntl, getcwd, strerror, fopen, fdopen and opendir absent, the core has no open, no stat, no stdio stream and no fourth descriptor: it can read, write, close and dup fds 0, 1 and 2 and nothing else"

# --- 4. the enumerators, before and after -------------------------------------------
# ONE GOES AND NOTHING RENUMBERS: NSCRIPT was the length of scriptin[] and
# saved_typebuf[], and typereach.py takes it as a whole anonymous definition.
tools/enumvals.sh "$state/old.c" "$tmp/ev.old" &
pid_ev=$!
tools/enumvals.sh "$f" "$tmp/ev.new"
wait $pid_ev
python3 - "$tmp/ev.old" "$tmp/ev.new" <<'PY'
import sys
TAG = 'nofile'
o = dict(l.rsplit('=', 1) for l in open(sys.argv[1]).read().splitlines())
n = dict(l.rsplit('=', 1) for l in open(sys.argv[2]).read().splitlines())
gone, came = sorted(set(o) - set(n)), sorted(set(n) - set(o))
moved = sorted(k for k in set(o) & set(n) if o[k] != n[k])
if gone != ['NSCRIPT'] or came or moved:
    if gone != ['NSCRIPT']:
        print('  %-12s the enumerators that went are %s, expected exactly NSCRIPT'
              % (TAG, ' '.join(gone) or 'none'))
    if came:
        print('  %-12s enumerators arrived: %s' % (TAG, ' '.join(came)))
    if moved:
        print('  %-12s survivors renumbered: %s' % (TAG, ' '.join(moved)))
    sys.exit(1)
print('  %-12s enumerators %d -> %d: NSCRIPT alone, as a whole anonymous definition, '
      'and not one survivor renumbered' % (TAG, len(o), len(n)))
PY

# --- 5. the binary -------------------------------------------------------------------
make -C "$work" clean >/dev/null 2>&1 || true
if ! make -C "$work" >/dev/null 2>&1; then
    echo "  build        FAILED -- rerun by hand: make -C $work"
    exit 1
fi
bin="$work/zero-vim"
echo "  build        ok, $before_lines -> $(grep -c '' "$f") lines, $(stat -c%s "$bin") bytes"

# --- 6. the instrumented pair, which is the whole of this phase's evidence -----------
wait $pid_probe || { echo "  nofile       the five-site probe did not build"; exit 1; }
wait $pid_ctl   || { echo "  nofile       the ui_write() control did not build"; exit 1; }
tools/zrecord.sh "$tmp/i/probe" "$tmp/i/probe.c" "$tmp/REC.probe" >/dev/null &
pid_rp=$!
tools/zrecord.sh "$tmp/i/ctl" "$tmp/i/ctl.c" "$tmp/REC.ctl" >/dev/null &
pid_rc=$!
rc=0
wait $pid_rp || rc=1
wait $pid_rc || rc=1
[ "$rc" = 0 ] || { echo "  nofile       a harness failed on one of the two recordings"; exit 1; }

total=$(find "$tmp/REC.probe" -type f | wc -l)
marked=$(grep -rl 'FILESTAR-ENTERED' "$tmp/REC.probe" | wc -l)
cmarked=$(grep -rl 'FILESTAR-ENTERED' "$tmp/REC.ctl" | wc -l)
if [ "$total" != 106 ]; then
    echo "  nofile       a recording is $total files, not the 106 this phase counted"
    exit 1
fi
if [ "$marked" != 0 ]; then
    echo "  nofile       $marked of $total records ENTERED one of the five sites on the binary this phase was handed:"
    grep -rl 'FILESTAR-ENTERED' "$tmp/REC.probe" | sed "s|^|               |"
    echo "               so this phase removes code that CAN run, and the cut is wrong"
    exit 1
fi
if [ "$cmarked" -lt 100 ]; then
    echo "  nofile       the control marked only $cmarked of $total records through the"
    echo "               identical instrument on ui_write(), which every byte the"
    echo "               editor draws goes through.  Without it the zero above is a"
    echo "               probe that cannot fail."
    exit 1
fi
echo "  nofile       the instrumented pair: the five sites entered by 0 of $total records, ui_write() by $cmarked of $total through the identical instrument -- that, and nothing else, is what says this phase removed code that could not run"

# --- 7. eighteen adversarial sessions, on both instrumented binaries -------------------
python3 - "$tmp/i/probe" "$tmp/i/ctl" <<'PY'
import concurrent.futures
import sys
sys.path.insert(0, 'tools')
import zstream
TAG = 'nofile'
ESC, CR = b'\x1b', b'\r'
QUIT = ESC + b':q!' + CR
PASTE = ['+set paste']
SEED = [b'ialpha' + ESC, b':set nopaste' + CR]
# EVERY ONE OF THESE IS A WAY OF MAKING THE EDITOR PRINT, which is where
# redir_write() sat -- msg_puts_attr_len() called it for every message -- plus the
# two that could once have fed the typeahead from a script.
SESSIONS = [
    ('messages',   SEED + [b':messages' + CR, QUIT]),
    ('verbose',    SEED + [b':verbose set ai?' + CR, QUIT]),
    ('silent',     SEED + [b':silent echo' + CR, QUIT]),
    ('history',    SEED + [b':history' + CR, QUIT]),
    ('registers',  SEED + [b'yy', b':registers' + CR, QUIT]),
    ('display',    SEED + [b'yy', b':display' + CR, QUIT]),
    ('ga',         SEED + [b'ga', QUIT]),
    ('unknown',    SEED + [b':nosuchcommand' + CR, QUIT]),
    ('set_all',    SEED + [b':set all' + CR, QUIT]),
    ('marks',      SEED + [b':marks' + CR, QUIT]),
    ('undolist',   SEED + [b':undolist' + CR, QUIT]),
    ('changes',    SEED + [b':changes' + CR, QUIT]),
    ('map',        SEED + [b':map' + CR, QUIT]),
    ('highlight',  SEED + [b':highlight' + CR, QUIT]),
    ('normal',     SEED + [b':normal ihi' + CR, QUIT]),
    ('global_p',   SEED + [b':g/a/p' + CR, QUIT]),
    ('replay',     SEED + [b'qaxq', b'@a', QUIT]),
    ('verbose9',   SEED + [b':set verbose=9' + CR, b'yy', QUIT]),
]


def one(job):
    name, binary, keys = job
    try:
        scr, out, err, rc = zstream.session(binary, keys, args=PASTE)
    except zstream.Blocked:
        return name, binary, None, 0
    return name, binary, rc, err.count(b'FILESTAR-ENTERED')


probe, ctl = sys.argv[1], sys.argv[2]
jobs = [(n, b, k) for n, k in SESSIONS for b in (probe, ctl)]
with concurrent.futures.ThreadPoolExecutor(max_workers=len(jobs)) as ex:
    res = list(ex.map(one, jobs))
got, fail = {}, []
for name, binary, rc, marks in res:
    if rc is None:
        fail.append('%s blocked, so it says nothing either way' % name)
    got[(name, binary)] = marks
for name, _ in SESSIONS:
    p, c = got.get((name, probe)), got.get((name, ctl))
    if p:
        fail.append('%s entered one of the five sites %d times on the binary this '
                    'phase was handed' % (name, p))
    if not c:
        fail.append('%s never reached ui_write() either, so it proves nothing: a '
                    'session that draws nothing is not an adversary' % name)
if fail:
    for line in fail:
        print('  %-12s %s' % (TAG, line))
    sys.exit(1)
print('  %-12s eighteen adversarial sessions -- :messages, :verbose, :silent, '
      ':history, :registers, :display, ga, an unknown command, :set all, :marks, '
      ':undolist, :changes, :map, :highlight, :normal, :g/a/p, a replayed register '
      'and :set verbose=9 -- each reached ui_write() and not one reached any of the '
      'five' % TAG)
PY

# --- 8. and the ordinary sessions, byte-identical either side --------------------------
python3 - "$state/old" "$bin" <<'PY'
import concurrent.futures
import hashlib
import os
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, 'tools')
import zrec
import zscreen

TAG = 'nofile'
ESC, CR = b'\x1b', b'\r'
QUIT = ESC + b':q!' + CR
CTRL_G = b'\x07'
old_bin, new_bin = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])


def record(binary, args, keys, timeout=10):
    stage = tempfile.mkdtemp(prefix='zero13-bin-')
    vim = os.path.join(stage, 'vim')
    shutil.copy2(binary, vim)
    os.chmod(vim, 0o755)
    home = tempfile.mkdtemp(prefix='zero13-home-')
    env = dict(os.environ)
    env.update(TERM='xterm', HOME=home, VIM=os.path.join(home, 'novim'),
               VIMRUNTIME=os.path.join(home, 'novim'),
               XDG_CONFIG_HOME=os.path.join(home, 'xdg'))
    for k in ('LINES', 'COLUMNS', 'VIMINIT', 'EXINIT', 'MYVIMRC'):
        env.pop(k, None)
    d = tempfile.mkdtemp(prefix='zero13-run-')
    kf = os.path.join(d, 'keys')
    with open(kf, 'wb') as fh:
        fh.write(b''.join(keys))
    try:
        with open(kf, 'rb') as stdin:
            r = subprocess.run([vim] + list(args), stdin=stdin,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               env=env, cwd=d, timeout=timeout,
                               start_new_session=True)
        rc, out, err = r.returncode, r.stdout, r.stderr
    except subprocess.TimeoutExpired:
        rc, out, err = 'timeout', b'', b''
    shutil.rmtree(stage, ignore_errors=True)
    shutil.rmtree(home, ignore_errors=True)
    shutil.rmtree(d, ignore_errors=True)
    scr = zscreen.Screen(24, 80)
    scr.feed(out)
    text = zrec.section('exit %s' % rc)
    text += zrec.section('bells %d' % scr.bells)
    text += zrec.section('stream %d sha=%s' % (len(out), hashlib.sha256(out).hexdigest()[:16]))
    text += zrec.section('stderr', err.decode('utf-8', 'replace').rstrip('\n'))
    for i, (dump, y, x, bells) in enumerate(scr.snaps):
        text += zrec.section('snap %d cursor=%d,%d bells=%d' % (i, y, x, bells), dump)
    return zrec.scrub(text), out.decode('utf-8', 'replace')


def typed(seed, *keys):
    return (['+set paste'], [b'i' + seed + ESC, b':set nopaste' + CR] + list(keys) + [QUIT])


HELLO = b'hello'
# name, (args, keys), what the new binary must still be SHOWING
PROBES = [
    ('editing',   typed(b'alpha' + CR + b'beta', b'0dwA-tail' + ESC, b'u', b'yyp'), 'alpha'),
    ('ctrl_g',    typed(b'a' + CR + b'b', CTRL_G),                   '[Modified]'),
    ('registers', typed(HELLO, b'yy', b':registers' + CR),           'Type Name Content'),
    ('messages',  typed(HELLO, b':messages' + CR),                   'hello'),
    ('silent',    typed(HELLO, b':silent echo' + CR),                'hello'),
    ('verbose',   typed(HELLO, b':verbose set ai?' + CR),            'autoindent'),
    ('replay',    typed(b'alpha', b'qaxq', b'@a'),                   'pha'),
    ('quit',      (['+set paste'], [b'i' + HELLO + ESC, b':set nopaste' + CR, b':q' + CR]), None),
    ('quit_bang', (['+set paste'], [b'i' + HELLO + ESC, b':set nopaste' + CR, b':q!' + CR]), None),
]


def one(probe):
    name, (args, keys), want = probe
    return (name, record(old_bin, args, keys), record(new_bin, args, keys), want)


with concurrent.futures.ThreadPoolExecutor(max_workers=len(PROBES)) as ex:
    results = list(ex.map(one, PROBES))

fail = []
for name, o, n, want in results:
    if o[0] != n[0]:
        fail.append('%s moved, and NOTHING in this phase may move a record' % name)
    if want is not None and want not in n[0] and want not in n[1]:
        fail.append('%s: the new binary no longer shows %r, so "it did not move" is '
                    'two failures agreeing' % (name, want))
if fail:
    for line in fail:
        print('  %-12s %s' % (TAG, line))
    sys.exit(1)
print('  %-12s nine ordinary sessions byte-identical either side and each doing its '
      'work: an editing session, CTRL-G with [Modified], :registers with its table, '
      ':messages, :silent, :verbose, a recorded register replayed with @a, :q and '
      ':q!' % TAG)
PY
