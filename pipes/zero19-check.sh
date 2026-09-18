#!/bin/sh
# Zero phase 19, the check -- the core can no longer stop the process.
# See pipes/zero19-edit.sh, and ZERO-GOAL.md.
#
# Usage: pipes/zero19-check.sh <work-dir> <state-dir>    (run from the repository root)
#
# Runs after pipes/zero19-edit.sh and the sweep tools/phaserun.sh runs between them,
# and reads nothing from the edit's shell -- only the work tree and the state
# directory.  What the edit left there is `old.c`, the source this phase was HANDED,
# and `old`, that source built with the boundary's own flags.
#
# WHAT IS CLAIMED is that `exit` leaves the core's undefined set and NOTHING arrives in
# its place, while every way the editor can end still ends it the same way.  Four
# things could make that false and each has a build of its own:
#
#   out      the output.  `nm -u` must lose exactly `exit` and gain nothing, and no
#            spelling of a jump -- setjmp, _setjmp, sigsetjmp, longjmp, siglongjmp --
#            may be there either.  This is the whole claim and it is one `comm`.
#   alt      THE ROAD NOT TAKEN, and the reason this phase does not look like the
#            review that proposed it.  The same output with the launcher rewritten to
#            `sigsetjmp`/`siglongjmp` out of <setjmp.h>: required to show `exit` gone
#            AND `sigsetjmp` and `siglongjmp` arrived, 33 where the output is 32 --
#            worse than not doing the phase at all.  Compiled to an object only; it is
#            a number, not a program.
#   off      the control for the status table: the output with `host_code = r;` changed
#            to `host_code = r + 1;`, ONE character, which must move ALL SIX statuses.
#            A table of six agreements proves nothing unless a wrong one is caught.
#   masks    the SIGNAL MASK at the moment the process ends, measured on the INPUT
#            immediately before `exit(r);` and on the OUTPUT immediately before
#            `return host_code;`.  The two must agree, on SIGTERM and on SIGHUP.
#
# THE MASK IS THE ONE THING `sigsetjmp` WOULD BUY AND THE MEASUREMENT IS WHY IT IS NOT
# BOUGHT.  `__builtin_longjmp` does not restore the process mask, so after a jump out
# of `deathtrap` on SIGTERM the landing site still has SIGTERM blocked.  That is
# exactly the state `exit()` was already called in -- `exit(r)` ran from inside the
# handler, with the handled signal blocked, and always did.  So the builtin PRESERVES
# what the process ends with and `siglongjmp` would CHANGE it, and the `masks` pair is
# what turns that from an argument into a number.  A host that keeps running is where
# the mask would matter, and there is none: main() lands and returns four lines later.
#
# THE COUNTING TRAP.  `exit` is FIVE words in the input and ONE is a call; FOUR in the
# output and NONE is.  `assert exit at 0 mentions` fails on a correct phase and
# `assert 'exit(' at 0` fails on mch_exit(, preserve_exit(, getout( and the new
# vim_host_exit( and host_exit(.  The assertion that works is `nm -u`, section 3.
set -eu

work=${1:?usage: zero19-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero19-check.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"
before_lines=$(cat "$state/input-lines")

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")

# --- 1. the four other sources, written first because their builds are the slow part --
mkdir -p "$tmp/i"
python3 - "$state/old.c" "$f" "$tmp/i" <<'PY'
import sys
TAG = 'hostexit'
old, new, out = sys.argv[1], sys.argv[2], sys.argv[3]


def die(msg):
    sys.exit('  %-12s %s' % (TAG, msg))


def edit(text, want, repl, what):
    if text.count(want) != 1:
        die('%s occurs %d times, expected 1 -- a probe must land where it is meant to, '
            'or what it measures is not what it is read as' % (what, text.count(want)))
    return text.replace(want, repl, 1)


# THE MASK PROBE.  Four writes of a fixed string from a place where the process is
# about to end; it asks the kernel what is blocked and says so on stderr.
def probe(indent):
    p = indent
    return (p + '{\n'
            + p + '    sigset_t hostmask;\n'
            + p + '    sigemptyset(&hostmask);\n'
            + p + '    sigprocmask(SIG_BLOCK, NULL, &hostmask);\n'
            + p + '    (void)write(2, sigismember(&hostmask, SIGTERM) ? "TERM-MASKED\\n" : "TERM-CLEAR\\n", sigismember(&hostmask, SIGTERM) ? 12 : 11);\n'
            + p + '    (void)write(2, sigismember(&hostmask, SIGHUP) ? "HUP-MASKED\\n" : "HUP-CLEAR\\n", sigismember(&hostmask, SIGHUP) ? 11 : 10);\n'
            + p + '}\n')


t_old = open(old, errors='surrogateescape').read()
t_new = open(new, errors='surrogateescape').read()

# in_mask: the INPUT, asked what is blocked immediately before the exit() that this
# phase removes.  This is the state the process has ALWAYS ended in.
in_mask = edit(t_old, '    exit(r);\n', probe('    ') + '    exit(r);\n',
               "mch_exit's `exit(r);` in the INPUT")
# out_mask: the OUTPUT, asked the same thing immediately before the launcher returns.
out_mask = edit(t_new, '        return host_code;\n',
                probe('        ') + '        return host_code;\n',
                "the launcher's `return host_code;` in the OUTPUT")

# alt: THE ROAD NOT TAKEN.  The same output with the one mechanism swapped for the
# library one.  It needs a thirteenth #include, which is half of what it costs.
BUILTIN = ('static void *host_jump[5];\n'
           'static int host_code;\n'
           '\n'
           '    static void\n'
           'host_exit(int r)\n'
           '{\n'
           '    host_code = r;\n'
           '    __builtin_longjmp(host_jump, 1);\n'
           '}\n')
SIGJMP = ('static sigjmp_buf host_jump;\n'
          'static int host_code;\n'
          '\n'
          '    static void\n'
          'host_exit(int r)\n'
          '{\n'
          '    host_code = r;\n'
          '    siglongjmp(host_jump, 1);\n'
          '}\n')
alt = edit(t_new, BUILTIN, SIGJMP, "the launcher's jump, in the OUTPUT")
alt = edit(alt, '    if (__builtin_setjmp(host_jump) != 0)\n',
           '    if (sigsetjmp(host_jump, 1) != 0)\n', "main()'s landing site")
alt = edit(alt, '#include <stdio.h>\n', '#include <stdio.h>\n#include <setjmp.h>\n',
           'the first #include')

# off: the control for the status table.  ONE character.
off = edit(t_new, '    host_code = r;\n', '    host_code = r + 1;\n',
           "host_exit's one assignment")

for name, text in (('in_mask', in_mask), ('out_mask', out_mask), ('alt', alt),
                   ('off', off)):
    open('%s/%s.c' % (out, name), 'w', errors='surrogateescape').write(text)
print('  %-12s four more sources: the input asked what signals are blocked immediately '
      'before `exit(r);`, the output asked the same immediately before `return '
      'host_code;`, the output with the launcher rewritten to sigsetjmp/siglongjmp out '
      'of <setjmp.h>, and the output with `host_code = r;` made `host_code = r + 1;`'
      % TAG)
PY

for n in in_mask out_mask off; do
    # shellcheck disable=SC2086
    ( gcc $cflags $ldflags -o "$tmp/i/$n" "$tmp/i/$n.c" ) &
done
# shellcheck disable=SC2086
( gcc $cflags -c -o "$tmp/i/alt.o" "$tmp/i/alt.c" ) &

# --- 2. the source, while those compile -----------------------------------------------
python3 - "$f" "$state/old.c" <<'PY'
import re, sys
TAG = 'hostexit'
new = open(sys.argv[1], errors='surrogateescape').read()
old = open(sys.argv[2], errors='surrogateescape').read()
fail = []


def mentions(text, name):
    return len(re.findall(r'\b%s\b' % name, text))


def runs(text):
    L = text.split('\n')
    return sum(1 for i in range(1, len(L)) if L[i] == '' and L[i - 1] == '')


# THE INPUT, so this is a check on the phase and not on whatever it was handed.
if old.count('    exit(r);\n') != 1 or len(re.findall(r'^\s*exit\(', old, re.M)) != 1:
    fail.append('the input did not hold exactly one `exit(` statement, so this is not '
                'the file the phase was written against -- phase 17 is what left one')
for name in ('vim_host_exit', 'host_exit', 'host_jump', 'host_code'):
    if mentions(old, name):
        fail.append('`%s` was already a word in the input' % name)

# THE OUTPUT.  The counting trap is why both sides are counted and the DIFFERENCE
# asserted.
if mentions(old, 'exit') != 5 or mentions(new, 'exit') != 4:
    fail.append('`exit` as a word is %d in the input and %d in the output, expected 5 '
                'and 4 -- two string literals, a `goto exit;` and its `exit:` label in '
                'vim_regsub_both() are the four that stay, and `exit(r);` is the one '
                'that goes' % (mentions(old, 'exit'), mentions(new, 'exit')))
if re.findall(r'^\s*exit\(', new, re.M):
    fail.append('a statement in the output still begins with `exit(`')
if mentions(new, '_exit'):
    fail.append('`_exit` is back, and phase 17 took it to zero')
for name in ('setjmp', 'longjmp', 'sigsetjmp', 'siglongjmp', 'sigjmp_buf', 'jmp_buf'):
    if mentions(new, name):
        fail.append('`%s` is named in the output.  The launcher jumps with gcc\'s '
                    'builtins, which emit no call and no relocation; the library '
                    'spellings cost two undefined symbols and a thirteenth #include, '
                    'which is worse than not doing this phase' % name)

# THE THREE EDITS AND THE LAUNCHER, one by one.
for text, what in (
        ('static void (*vim_host_exit)(int);\n\n    static void\nmch_exit(int r)\n{\n',
         'the pointer declared immediately above mch_exit(), its one reader'),
        ('    ml_close_all(TRUE);\n\n    vim_host_exit(r);\n}\n',
         "mch_exit()'s tail: everything it did before is unchanged and only the last "
         'statement moved'),
        ('    static int\nvim_main(int argc, char **argv, void (*exit_fn)(int))\n{\n\n'
         '    vim_host_exit = exit_fn;\n',
         'vim_main() taking the callback as a parameter and installing it')):
    if new.count(text) != 1:
        fail.append('%s: not found exactly once in the output' % what)
LAUNCH = ('\nstatic void *host_jump[5];\nstatic int host_code;\n'
          '\n    static void\nhost_exit(int r)\n{\n    host_code = r;\n'
          '    __builtin_longjmp(host_jump, 1);\n}\n'
          '\n    int\nmain(int argc, char **argv)\n{\n'
          '    if (__builtin_setjmp(host_jump) != 0)\n    {\n'
          '        return host_code;\n    }\n'
          '    return vim_main(argc, argv, host_exit);\n}\n')
if not new.endswith(LAUNCH):
    fail.append('zero-vim.c does not end with the twenty-line launcher.  CLAUDE.md '
                'states that main() is literally the last thing in this file and its '
                'closing brace the final line, and that stays true')

for name, want, why in (
        ('vim_host_exit', 3, 'its declaration, the one call in mch_exit and the one '
                             'assignment in vim_main'),
        ('host_exit', 2, "the launcher's definition and the argument main() passes.  "
                         '`vim_host_exit` is a different word'),
        ('host_jump', 3, 'its declaration, the longjmp and the setjmp'),
        ('host_code', 3, 'its declaration, the write and the return'),
        ('vim_main', 2, 'its definition and the one call from the launcher'),
        ('vim_main2', 2, "upstream's, untouched"),
        ('main', 1, "the launcher's head, still the only bare `main` in the file"),
        ('mch_exit', 8, 'this phase changes one statement inside it and no call to it'),
        ('getout', 7, 'untouched'),
        ('preserve_exit', 3, 'untouched'),
        ('deathtrap', 3, 'a prototype, a definition and the one installation')):
    if mentions(new, name) != want:
        fail.append('`%s` as a whole word has %d mentions, expected %d -- %s'
                    % (name, mentions(new, name), want, why))

# EIGHTEEN LINES AND NOT ONE MORE, which is also what says the sweep found nothing.
if len(new.split('\n')) != len(old.split('\n')) + 18:
    fail.append('the file gained %d lines, expected 18'
                % (len(new.split('\n')) - len(old.split('\n'))))
if runs(new) != runs(old):
    fail.append('runs of two blank lines: %d in the output against %d in the input'
                % (runs(new), runs(old)))

# The tables and the directive count this phase does not touch.  THE DIRECTIVE COUNT IS
# PART OF THE CLAIM here and not a formality: <setjmp.h> would be a thirteenth.
sys.path.insert(0, 'tools')
import create_cmdidxs
rows = re.findall(r'^    \[CMD_\w+\] = \{.*$', new, re.M)
if len(rows) != 98 or len(create_cmdidxs.names(sys.argv[1])) != 98:
    fail.append('cmdnames[] is not the 98 rows phase 10 left')
i = new.find('static struct vimoption options[]')
j = new.index('\n};', i)
if len(re.findall(r'^[ \t]*\{"([a-z]+)",', new[i:j], re.M)) != 108:
    fail.append('options[] is not the 108 rows phase 12 left')
d = [l for l in new.split('\n') if l.startswith('#')]
if len(d) != 12 or any(not l.startswith('#include <') for l in d):
    fail.append('the output does not have exactly the twelve `#include` directives '
                'phase 16 left -- a thirteenth would be <setjmp.h>, and avoiding it is '
                'half of why the launcher jumps with gcc builtins')

if fail:
    for line in fail:
        print('  %-12s %s' % (TAG, line))
    sys.exit(1)
print('  %-12s mch_exit() ends `vim_host_exit(r);`, the pointer is declared above it, '
      'vim_main() takes the callback as its third parameter and installs it, and the '
      'launcher is twenty lines that land on __builtin_setjmp and RETURN the status.  '
      '+18 lines, four hunks' % TAG)
print('  %-12s the counting trap: `exit` as a word is 5 -> 4 and the number of `exit(` '
      'STATEMENTS is 1 -> 0.  The four that stay are two string literals and a `goto '
      "exit;` with its `exit:` label in vim_regsub_both(), so `assert exit at 0` fails "
      'on a correct phase.  No spelling of setjmp or longjmp is in the file either'
      % '')
print('  %-12s and the twelve #includes are phase 16\'s, untouched: <setjmp.h> would be '
      'a thirteenth, which is half of what the library spelling costs' % '')
PY

# --- 3. the compile, the linkage and the libc surface ---------------------------------
# `exit` AND NOTHING ELSE, stated as the two comm sets rather than as a count.
cp "$state/symbols/undefined" "$tmp/before.u"
tools/phasecheck.sh "$work" "$f" "$state/symbols"
comm -23 "$tmp/before.u" .cache/symbols/last/undefined > "$tmp/gone.u"
comm -13 "$tmp/before.u" .cache/symbols/last/undefined > "$tmp/came.u"
printf 'exit\n' > "$tmp/want.u"
if ! cmp -s "$tmp/gone.u" "$tmp/want.u" || [ -s "$tmp/came.u" ]; then
    echo "  hostexit     the libc surface did not move by exactly exit:"
    echo "               gone: $(tr '\n' ' ' < "$tmp/gone.u")"
    echo "               came: $(tr '\n' ' ' < "$tmp/came.u")"
    echo "               NOTHING MAY ARRIVE.  An indirect call names no symbol, and a"
    echo "               jump that named one would trade two symbols for one."
    exit 1
fi
for absent in exit _exit setjmp _setjmp sigsetjmp __sigsetjmp longjmp siglongjmp \
              abort _Exit quick_exit atexit; do
    if grep -qx "$absent" .cache/symbols/last/undefined; then
        echo "  hostexit     $absent is undefined, and the core has no way to end the process any more"; exit 1
    fi
done
# ZERO-PLAN.md 4b's invariant, re-asserted for free.
for absent in open creat openat stat access fcntl getcwd strerror fopen fdopen \
              opendir fclose getc putc fsync; do
    if grep -qx "$absent" .cache/symbols/last/undefined; then
        echo "  hostexit     $absent is undefined, and the core has had no way to open a file since phase 13"; exit 1
    fi
done
echo "  hostexit     symbols $(cat .cache/symbols/last/before) -> $(cat .cache/symbols/last/after), the gone set is EXACTLY exit and NOTHING arrives -- the core cannot end the process, cannot abort, cannot _exit and names no jump"

# --- 4. the binary --------------------------------------------------------------------
make -C "$work" clean >/dev/null 2>&1 || true
[ -e "$work/zero-vim" ] && { echo "  build        the clean did not remove zero-vim"; exit 1; }
if ! make -C "$work" >/dev/null 2>&1; then
    echo "  build        FAILED -- rerun by hand: make -C $work"
    exit 1
fi
bin="$work/zero-vim"
echo "  build        ok, $before_lines -> $(grep -c '' "$f") lines, $(stat -c%s "$bin") bytes"

# --- 5. the road not taken, as a number ------------------------------------------------
wait || true
[ -f "$tmp/i/alt.o" ] || { echo "  hostexit     the sigsetjmp variant did not compile"; exit 1; }
nm -u "$tmp/i/alt.o" | awk '{print $NF}' | sort > "$tmp/alt.u"
for want in sigsetjmp siglongjmp; do
    grep -qx "$want" "$tmp/alt.u" \
        || { echo "  hostexit     the sigsetjmp variant does not need $want, so it is not the variant this phase is arguing against"; exit 1; }
done
grep -qx exit "$tmp/alt.u" \
    && { echo "  hostexit     the sigsetjmp variant still needs exit, so it is not comparable"; exit 1; }
n_out=$(grep -c '' .cache/symbols/last/undefined)
n_alt=$(grep -c '' "$tmp/alt.u")
[ "$n_alt" -gt "$n_out" ] \
    || { echo "  hostexit     the sigsetjmp variant needs $n_alt symbols against the output's $n_out, and the whole argument for the builtin is that it needs MORE"; exit 1; }
echo "  hostexit     THE ROAD NOT TAKEN, measured: the same output with the launcher rewritten to sigsetjmp/siglongjmp out of <setjmp.h> needs $n_alt undefined symbols against this one's $n_out -- exit goes either way, and the library spelling brings sigsetjmp and siglongjmp in its place.  Two symbols for one, plus a thirteenth #include: worse than not doing the phase"

# --- 6. every way the editor can end, and the mask the process ends with ---------------
for n in in_mask out_mask off; do
    [ -x "$tmp/i/$n" ] || { echo "  hostexit     the $n build is missing"; exit 1; }
done

python3 - "$state/old" "$bin" "$tmp/i/off" "$tmp/i/in_mask" "$tmp/i/out_mask" <<'PY'
import concurrent.futures
import os
import select
import shutil
import signal
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, 'tools')
import zstream

TAG = 'hostexit'
old_bin, new_bin, off_bin, in_mask, out_mask = sys.argv[1:6]
fail = []


def env_for(home):
    env = dict(os.environ)
    env.update(TERM='xterm', HOME=home, VIM=os.path.join(home, 'novim'),
               VIMRUNTIME=os.path.join(home, 'novim'),
               XDG_CONFIG_HOME=os.path.join(home, 'xdg'))
    for k in ('LINES', 'COLUMNS', 'VIMINIT', 'EXINIT', 'MYVIMRC'):
        env.pop(k, None)
    return env


def quiet(binary, args):
    """Run to completion with stdin AND stderr at /dev/null; give back (status, b'').

    BOTH OF THOSE ARE MEASUREMENTS AND NEITHER IS A PREFERENCE, and the second is a
    property of the editor that a reader will not guess.

    stdin is /dev/null and not a pipe the harness closes: with a pipe, the EOF row came
    back as a twenty-second timeout on four binaries out of five and as a clean 1 on the
    fifth -- a race in the HARNESS.  A file already at end of file has none.

    stderr is /dev/null and not a PIPE because `fill_input_buf()` reads it.  When a read
    of fd 0 returns nothing and fd 0 is not a terminal, it does `close(0);
    vim_ignored = dup(2);` and tries again -- so the EOF route's SECOND read is a read
    of whatever fd 2 is.  Measured on the binary this phase was handed: with stderr at
    /dev/null the second read is another end of file and `read_error_exit` runs and
    exits 1; with stderr a pipe the harness holds open, the editor waits there for keys
    that never come and the row times out.  The exit status of the EOF route is
    therefore a statement about the harness's fd 2 as much as about the editor, and
    tools/zstream.py's docstring has the same finding from the other end.
    """
    vim = zstream.stage(binary)     # argv[0], and the copy race: tools/zstream.py
    home = tempfile.mkdtemp(prefix='zero19-home-')
    try:
        with open(os.devnull, 'rb') as devnull:
            p = subprocess.run([vim] + list(args), stdin=devnull,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                               env=env_for(home), timeout=20, start_new_session=True)
        return p.returncode, b''
    except subprocess.TimeoutExpired:
        return 'TIMEOUT', b''
    finally:
        shutil.rmtree(home, ignore_errors=True)


def signalled(binary, sig):
    """Start the editor on pipes, let it draw, then signal it.  (status, stderr).

    It waits for the editor to have DRAWN the typed text and then gone quiet rather
    than for a clock: a fixed sleep signals the editor wherever its redraw had got to,
    which under load is a recording of the machine and not of the program.
    """
    vim = zstream.stage(binary)
    home = tempfile.mkdtemp(prefix='zero19-home-')
    p = subprocess.Popen([vim, '+set paste'], stdin=subprocess.PIPE,
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                         env=env_for(home), start_new_session=True)
    try:
        p.stdin.write(b'ihello')
        p.stdin.flush()
    except OSError:
        pass
    drawn = b''
    last, deadline = time.time(), time.time() + 20.0
    while True:
        if time.time() > deadline:
            drawn += b'<<NEVER DREW>>'
            break
        r, _, _ = select.select([p.stdout.fileno()], [], [], 0.05)
        if r:
            chunk = os.read(p.stdout.fileno(), 65536)
            if not chunk:
                break
            drawn += chunk
            last = time.time()
        elif b'hello' in drawn and time.time() - last > 0.3:
            break
    try:
        os.kill(p.pid, sig)
    except ProcessLookupError:
        pass
    try:
        _, err = p.communicate(timeout=20)
    except subprocess.TimeoutExpired:
        p.kill()
        _, err = p.communicate()
    shutil.rmtree(home, ignore_errors=True)
    if b'<<NEVER DREW>>' in drawn:
        return 'NEVER DREW', b''
    return p.returncode, err


# THE SIX WAYS THE EDITOR CAN END.  Each is a different one of ZERO-PLAN.md's
# termination routes, and every one of them now goes through the function pointer:
# getout() falls into mch_exit(), and mch_exit() is the only caller of vim_host_exit.
WAYS = [
    ('quit',    lambda b: quiet(b, ['+q!']),   0, ':q! -- ex_quit -> getout(0) -> mch_exit(0)'),
    ('cquit3',  lambda b: quiet(b, ['+cq 3']), 3, ':cq 3 -- ex_cquit -> getout(3)'),
    ('eof',     lambda b: quiet(b, []),        1, 'end of input -- read_error_exit -> preserve_exit -> getout(1)'),
    ('badopt',  lambda b: quiet(b, ['-Z']),    1, 'a bad option -- mainerr -> mch_exit(1), which never reaches the editor at all'),
    ('sigterm', lambda b: signalled(b, signal.SIGTERM), 1, 'SIGTERM -- deathtrap -> preserve_exit -> getout(1), from inside a signal handler'),
    ('sighup',  lambda b: signalled(b, signal.SIGHUP),  1, 'SIGHUP -- deathtrap -> preserve_exit -> getout(1), from inside a signal handler'),
]
JOBS = [(w, tag, b) for w in WAYS for tag, b in
        (('old', old_bin), ('new', new_bin), ('off', off_bin))]
# The mask pair: the input asked immediately before exit(r), the output asked
# immediately before the launcher returns.
MASKS = [('in_%s' % t, in_mask, s) for t, s in (('term', signal.SIGTERM), ('hup', signal.SIGHUP))] \
      + [('out_%s' % t, out_mask, s) for t, s in (('term', signal.SIGTERM), ('hup', signal.SIGHUP))]
ALL = [(j[0][1], j[2], ('way', j[0][0], j[1])) for j in JOBS] \
    + [((lambda b, s=s: signalled(b, s)), b, ('mask', n, None)) for n, b, s in MASKS]
with concurrent.futures.ThreadPoolExecutor(max_workers=len(ALL)) as ex:
    res = list(ex.map(lambda a: (a[2], a[0](a[1])), ALL))
got = {k[1:]: v for k, v in res if k[0] == 'way'}
masks = {k[1]: v for k, v in res if k[0] == 'mask'}

rows = []
for name, _fn, want, why in WAYS:
    o, n, c = got[(name, 'old')][0], got[(name, 'new')][0], got[(name, 'off')][0]
    rows.append('%s=%s' % (name, n))
    if o != want:
        fail.append('the binary this phase was HANDED exited %s on %s, expected %d -- '
                    'so the agreement below would be two wrong answers agreeing'
                    % (o, why, want))
    if n != o:
        fail.append('%s: the input exited %s and the output %s.  The status now travels '
                    'from mch_exit through a function pointer, into a jump buffer and '
                    'out of main() as a return value, and every step of that is what '
                    'this row is checking' % (why, o, n))
    if c == n:
        fail.append("the control -- the output with host_exit's `host_code = r;` made "
                    '`host_code = r + 1;`, ONE character -- also exited %s on %s, so '
                    'this row is not measuring the value travelling' % (c, why))

# THE MASK THE PROCESS ENDS WITH.  This is the only thing the library spelling would
# have changed, and the measurement is that it does not need changing.
def marks(rec):
    err = rec[1].decode('latin-1')
    return tuple(sorted(l for l in err.split('\n')
                        if l in ('TERM-MASKED', 'TERM-CLEAR', 'HUP-MASKED', 'HUP-CLEAR')))


mask_rows = []
for sig in ('term', 'hup'):
    a, b = marks(masks['in_%s' % sig]), marks(masks['out_%s' % sig])
    if not a:
        fail.append('the INPUT instrumented before `exit(r);` reported no mask at all '
                    'on SIG%s, so the comparison below would be two silences agreeing'
                    % sig.upper())
    if a != b:
        fail.append('SIG%s: the process used to end with %s and now ends with %s.  '
                    '__builtin_longjmp does not restore the signal mask, and the whole '
                    'argument for using it is that exit() was already called from '
                    'inside the handler with the handled signal blocked'
                    % (sig.upper(), a or 'nothing', b or 'nothing'))
    mask_rows.append('SIG%s %s' % (sig.upper(), ' '.join(a)))
if masks['in_term'][0] != 1 or masks['out_term'][0] != 1:
    fail.append('an instrumented signal run did not exit 1')

if fail:
    for line in fail:
        print('  %-12s %s' % (TAG, line))
    sys.exit(1)
print('  %-12s every way the editor can end, the same on both binaries: %s -- ex_quit, '
      'ex_cquit, read_error_exit, mainerr and deathtrap twice.  Every one of them now '
      'leaves mch_exit through a function pointer, lands in main() and comes back as a '
      'RETURN VALUE' % (TAG, '  '.join(rows)))
print('  %-12s and the table is PROVEN able to fail: the output built again with '
      "host_exit's `host_code = r;` made `host_code = r + 1;` -- one character -- moves "
      'ALL SIX (%s)'
      % ('', '  '.join('%s=%s' % (w[0], got[(w[0], 'off')][0]) for w in WAYS)))
print('  %-12s THE SIGNAL MASK THE PROCESS ENDS WITH IS UNCHANGED, which is the one '
      'thing sigsetjmp would have bought: %s, identical on the input asked immediately '
      'before `exit(r);` and on the output asked immediately before the launcher '
      'returns.  exit() was always called from inside the handler with the handled '
      'signal blocked -- SIGHUP is clear only because prepare_to_exit() ignores it on '
      'the way past -- so __builtin_longjmp PRESERVES that and siglongjmp would CHANGE '
      'it' % ('', ', '.join(mask_rows)))
PY

# tools/phaserun.sh runs tools/zerodelta.sh --phase 19 after this check, and this
# phase declares NOTHING: the corpus must not move at all.
