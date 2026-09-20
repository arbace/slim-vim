#!/bin/sh
# Zero phase 21, the check -- the messages are the editor's, the writing is the host's.
# See pipes/zero21-edit.sh, and ZERO-GOAL.md.
#
# Usage: pipes/zero21-check.sh <work-dir> <state-dir>    (run from the repository root)
#
# Runs after pipes/zero21-edit.sh and the sweep tools/phaserun.sh runs between them,
# and reads nothing from the edit's shell -- only the work tree and the state
# directory.  What the edit left there is `old.c`, the source this phase was HANDED,
# and `old`, that source built with the boundary's own flags.  EVERY PROBE BELOW IS A
# PAIR, because a number from one binary is not evidence.
#
# WHAT IS CLAIMED, in three parts:
#
#   SYMBOLS     `nm -u` loses EXACTLY `fflush fputc fputs fwrite printf putchar
#               stderr` and gains nothing -- one `comm`, never a count.  FOUR of the
#               seven are named nowhere in the source: gcc emits them from
#               `printf("%s", x)` and `fprintf(stderr, "%s", x)`.  They were predicted
#               to leave with the construct, and the empty `arrived` side is what
#               verifies the prediction.  `<stdio.h>` goes with them, 12 directives to
#               11.
#   STRUCTURE   the file has exactly TWO bare `write()` call sites -- `mch_write`'s and
#               `host_message`'s -- and one `vim_host_message` the launcher installs
#               through vim_main()'s parameter list, exactly as phase 19 installs
#               `vim_host_exit`.  `zhostonly` is run unchanged, and the phase
#               deliberately adds nothing to its VOCAB (pipes/zero21-edit.sh says why:
#               `write` would be false while mch_write holds one, and the stdio words
#               would fail phase 20's own output and so `make zero-verify` at r20).
#   BEHAVIOUR   NOTHING AT ALL.  The same bytes reach the same file descriptors at the
#               same moments; only the syscall underneath them changes.
#
# THE DECLARED DELTA IS NOTHING, AND THE FIRST CHECK OF THAT IS `diff -r` AND NOT
# tools/zerodelta.sh.  Measured on the control below: `diff -r` of the two recordings
# reports 217 lines across 24 moved records and zerodelta.sh names only FOURTEEN,
# because ten of the 24 argv rows (`-`, `--`, `-e`, `-E`, `-e -s`, `-v`, `f.txt`,
# `f.txt g.txt`, `+q! f.txt`, `-- +q!`) are already declared movers from phases 4 and 5
# and tools/zcompare.py therefore accepts any FURTHER movement in them silently.  So
# this check diffs the recording of the binary it was handed against the recording of
# the one it made, and uses zerodelta.sh as the second opinion -- on the CONTROL, where
# it must refuse.
#
# THE INSTRUMENTED PAIR IS THE EVIDENCE THAT THE DELTA IS EMPTY FOR THE RIGHT REASON.
# Phase 9's shape: the input source built with `write(2, "MESSAGE-OUT\n", 12)` at all
# NINETEEN output statements, and the output source built with the IDENTICAL instrument
# inside `host_message`.  Both must mark exactly the same records -- 24 of the 30 argv
# rows, by name, and 0 of the 102 screens, 0 of ref-excmds.txt, 0 of ref-pty.txt and 0
# of ref-term.txt.  Same places, same times, different primitive.  It also settles
# `msg_puts_printf` and `exit_scroll`'s printf arm without removing them: the 24 marked
# rows are 23 `mainerr` and one `report_term_error`, so the other four speakers fire in
# ZERO of 106 records.
#
# THE COUNTING TRAPS, AND WHY THE ASSERTIONS ARE SHAPED AS THEY ARE:
#
#   * `printf` IS NOT AT 0.  13 -> 10, and none of the ten is a call: nine
#     `format(printf, ...)` attributes and the string "E767: Too many arguments for
#     printf()".  `assert printf at 0` FAILS ON A CORRECT PHASE.  The assertions that
#     work are `fprintf` 16 -> 0, `stderr` 17 -> 0, `fflush` 1 -> 0, `printf` 13 -> 10
#     and `nm -u`.
#   * `errno` DOES NOT MOVE, 3 -> 3, and `__errno_location` is REQUIRED still undefined.
#     It is held by `host_tty_set`'s and `musl_wait_for_input`'s two `== EINTR` tests,
#     both of them inside phase 20's host block, and it leaves at the split.  Removing
#     stdio has nothing to do with it -- said out loud, because a reader who watches
#     seven symbols go will look for the eighth.
#   * `msg_use_printf` 6 AND `msg_puts_printf` 3, UNCHANGED.  They are not dead: the
#     first returns TRUE 23 times in 106 records.  Removing them is a later phase's
#     question and would free nothing, the symbols being gone here.
#   * `host_message` AND `vim_host_message` ARE DIFFERENT WORDS to \b, which is why
#     their counts are separate -- phase 19 learnt that with `host_exit`.
#
# THE ONE THING THAT REALLY CHANGES AND NO RECORDING CAN SEE IS THE BUFFER'S BOUND.
# `mainerr`'s `str` and `report_term_error`'s `term` are argv, and a 1024-byte assembly
# buffer caps a message that used to be unbounded.  Both halves are pinned below: an
# option name of 900 characters must be the same 995 bytes on both binaries, and one of
# 2,000 must be 2,095 bytes on the input and exactly 1,023 here, with `-T` 2,039 against
# exactly 1,023.  A cap that drifted either way would fail.  The counts are RAW: the
# version banner's `__DATE__`/`__TIME__` differ between two builds and their LENGTH does
# not, so only the equality at 900 is scrubbed.
set -eu

work=${1:?usage: zero21-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero21-check.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"
before_lines=$(cat "$state/input-lines")

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")

# --- 1. the three extra sources, written and started first because builds are slow ----
# ctl.c   THE CONTROL: `write(err ? 2 : 1, ...)` made `write(err ? 1 : 1, ...)`, one
#         character, which must move every message-bearing record.
# IN.c    the source this phase was HANDED, with a marker at all 19 output statements.
# OUT.c   this phase's OUTPUT, with the identical marker inside host_message().
python3 - "$f" "$state/old.c" "$tmp" <<'PY'
import re, sys
TAG = 'message'
new = open(sys.argv[1], errors='surrogateescape').read()
old = open(sys.argv[2], errors='surrogateescape').read()
tmp = sys.argv[3]

A = '        int w = (int)write(err ? 2 : 1, msg + off, (size_t)(n - off));\n'
if new.count(A) != 1:
    sys.exit('  %-12s host_message()\'s one write() is not in the output exactly once, '
             'so the control below would not be the control' % TAG)
open(tmp + '/ctl.c', 'w', errors='surrogateescape').write(
    new.replace(A, A.replace('err ? 2 : 1', 'err ? 1 : 1')))

MARK = '     write(2, "MESSAGE-OUT\\n", 12) ;'
lines = old.split('\n')
out = []
n = 0
for l in lines:
    if re.match(r'^\s*(printf|fprintf)\(', l):
        out.append(MARK)
        n += 1
    out.append(l)
if n != 19:
    sys.exit('  %-12s the instrument went on %d statements of the input, expected the '
             '19 that put bytes on a stream (16 fprintf + 3 printf; the fflush emits '
             'nothing of its own)' % (TAG, n))
open(tmp + '/IN.c', 'w', errors='surrogateescape').write('\n'.join(out))

B = '''host_message(const char *msg, int len, int err)
{
    int         n = len;
'''
C = '''host_message(const char *msg, int len, int err)
{
    int         n = len;

    write(2, "MESSAGE-OUT\\n", 12);
'''
if new.count(B) != 1:
    sys.exit('  %-12s host_message()\'s head is not in the output exactly once' % TAG)
open(tmp + '/OUT.c', 'w', errors='surrogateescape').write(new.replace(B, C))
print('  %-12s the control (`err ? 2 : 1` made `err ? 1 : 1`, one character) and the '
      'instrumented pair (the input marked at all %d output statements, the output '
      'marked once inside host_message) are written' % (TAG, n))
PY
pids=
for v in ctl IN OUT; do
    # shellcheck disable=SC2086
    ( gcc $cflags $ldflags -o "$tmp/$v" "$tmp/$v.c" ) &
    pids="$pids $!"
done

# --- 2. the source ----------------------------------------------------------------------
python3 - "$f" "$state/old.c" "$before_lines" <<'PY'
import re, sys
TAG = 'message'
new = open(sys.argv[1], errors='surrogateescape').read()
old = open(sys.argv[2], errors='surrogateescape').read()
before = int(sys.argv[3])
fail = []


def mentions(text, name):
    return len(re.findall(r'\b%s\b' % name, text))


# THE INPUT, so this is a check on the phase and not on whatever it was handed.
for name, want in (('fprintf', 16), ('stderr', 17), ('fflush', 1), ('printf', 13),
                   ('errno', 3), ('info_message', 9), ('vim_host_exit', 3)):
    if mentions(old, name) != want:
        fail.append('the input has %d mentions of `%s`, expected %d'
                    % (mentions(old, name), name, want))
if old.count('#include <stdio.h>\n') != 1:
    fail.append('the input did not include <stdio.h> exactly once')
for name in ('vim_host_message', 'host_message'):
    if mentions(old, name):
        fail.append('`%s` was already in the input, so its arrival proves nothing' % name)

# WHAT IS GONE.  Three words, and `printf` is deliberately NOT among them.
for name in ('fprintf', 'stderr', 'fflush', 'FILE', 'stdout'):
    if mentions(new, name):
        fail.append('`%s` has %d mentions and should have none'
                    % (name, mentions(new, name)))
if re.findall(r'(?m)^\s*(?:printf|fprintf|fflush)\(', new):
    fail.append('a statement still begins with printf(, fprintf( or fflush(')

# WHAT IS THERE.
for name, want, why in (
        ('printf', 10, 'THE COUNTING TRAP: nine `format(printf, ...)` attributes and '
                       'the string "E767: Too many arguments for printf()".  None is a '
                       'call, and `assert printf at 0` fails on a correct phase'),
        ('vim_host_message', 10, 'the declaration, vim_main()\'s installation and the '
                                 'EIGHT call sites -- 4 in msg_puts_printf, 2 in '
                                 'exit_scroll, 1 in report_term_error, 1 in mainerr'),
        ('host_message', 2, "the launcher's definition and the argument main() passes.  "
                            '`vim_host_message` is a DIFFERENT word to \\b'),
        ('vim_host_exit', 3, "phase 19's, untouched"),
        ('host_exit', 2, "phase 19's, untouched"),
        ('vim_main', 2, 'its definition and the one call from the launcher'),
        ('main', 1, 'still the only bare `main` in the file'),
        ('msg_use_printf', 6, 'a prototype, a definition and four call sites -- '
                              'UNTOUCHED.  It returns TRUE in 23 of 106 records, so it '
                              'is not dead and folding it is a later phase'),
        ('msg_puts_printf', 3, 'a prototype, a definition and one call -- all 75 lines '
                               'stay and only what they call changes'),
        ('info_message', 9, 'untouched: the four sites that read it kept their '
                            '`if (info_message)` shape, so this phase changes which '
                            'primitive writes and nothing about which stream'),
        ('errno', 3, 'UNCHANGED, and said out loud: the #include and two uses, both '
                     'inside phase 20\'s host block.  __errno_location is NOT this '
                     "phase's and is required below to be still undefined"),
        ('vim_snprintf', 73, 'four more than the input -- report_term_error and mainerr '
                             'each assemble in two arms, with the only formatter the '
                             'file has had since phase 14'),
        ('musl_strlen', 134, "one more than the input: host_message's, in the len < 0 "
                             'arm.  The launcher may call it -- it is the same '
                             'translation unit and it goes to the host file at the '
                             'split'),
):
    if mentions(new, name) != want:
        fail.append('`%s` has %d mentions, expected %d -- %s'
                    % (name, mentions(new, name), want, why))

# THE STRUCTURAL CLAIM THAT `zhostonly` CANNOT MAKE, and pipes/zero21-edit.sh
# says why it is not added to its VOCAB.  Two bare write() call sites and no more.
w = [(i + 1, l.strip()) for i, l in enumerate(new.split('\n'))
     if re.search(r'(?<![_A-Za-z])write\(', l)]
if len(w) != 2:
    fail.append('there are %d bare write() call sites, expected 2 -- mch_write\'s '
                'write(1, ...) and host_message\'s write(err ? 2 : 1, ...): %s'
                % (len(w), '; '.join('%d: %s' % x for x in w[:6])))
elif 'write(1, (char *)s, len)' not in w[0][1] or 'err ? 2 : 1' not in w[1][1]:
    fail.append('the two write() call sites are not mch_write\'s and host_message\'s: %s'
                % '; '.join('%d: %s' % x for x in w))
if mentions(old, 'write') - mentions(new, 'write') != -1:
    fail.append('`write` moved by %d mentions, expected exactly +1 -- host_message\'s'
                % (mentions(new, 'write') - mentions(old, 'write')))

# THE SHAPE OF THE FILE.
sys.path.insert(0, 'tools')
# tools/create_cmdidxs.py -- named as a PATH so tools/implhash.sh hashes it into this
# phase's key.  implhash greps for paths and an `import` names a module, so
# without this line an edit to it changes what this phase produces and moves
# no key at all.  See CLAUDE.md on cutil.py and macros.py.  Do not delete it.
import create_cmdidxs
rows = re.findall(r'^    \[CMD_\w+\] = \{.*$', new, re.M)
if len(rows) != 98 or len(create_cmdidxs.names(sys.argv[1])) != 98:
    fail.append('cmdnames[] is not the 98 rows phase 10 left -- this phase touches no '
                'Ex command')
i = new.find('static struct vimoption options[]')
j = new.index('\n};', i)
n_opt = len(re.findall(r'^[ \t]*\{"([a-z]+)",', new[i:j], re.M))
if n_opt != 107:
    fail.append('options[] has %d rows, expected the 107 phase 20 left -- this phase '
                'touches no option' % n_opt)
d = [l for l in new.split('\n') if l.startswith('#')]
o = [l for l in old.split('\n') if l.startswith('#')]
if len(o) != 12 or len(d) != 11 or any(not l.startswith('#include <') for l in d):
    fail.append('the directive count is %d -> %d, expected 12 -> 11 with every survivor '
                'an #include of a system header.  ZERO-GOAL.md permits a phase to '
                'REMOVE one and forbids adding one; this is the second removal in the '
                'pipeline, and <stdio.h> is the header these seven symbols came from'
                % (len(o), len(d)))
if '<stdio.h>' in new:
    fail.append('<stdio.h> is still named somewhere in the output')
L = new.split('\n')
if sum(1 for k in range(1, len(L)) if L[k] == '' and L[k - 1] == ''):
    fail.append('there is a run of two blank lines, which canon.sh should have taken')
if len(L) - 1 != before + 25:
    fail.append('the file is %d lines and the input was %d -- expected exactly 25 more: '
                '2 for the pointer and its blank line, 1 for vim_main\'s installation, '
                '1 net in report_term_error, 23 for host_message and the blank line '
                'above it, less 1 for the fflush and less 1 for <stdio.h>.  The six '
                'one-for-one sites and mainerr are line-neutral'
                % (len(L) - 1, before))

if fail:
    for line in fail:
        print('  %-12s %s' % (TAG, line))
    sys.exit(1)
print('  %-12s fprintf 16 -> 0, stderr 17 -> 0, fflush 1 -> 0, and printf 13 -> 10 -- '
      'NOT 0, because nine of the ten survivors are `format(printf, ...)` attributes '
      'and the tenth is the E767 string, and none of the three that were calls is left'
      % TAG)
print('  %-12s exactly TWO bare write() call sites: mch_write\'s write(1, ...) and '
      'host_message\'s write(err ? 2 : 1, ...).  msg_use_printf 6, msg_puts_printf 3 '
      'and info_message 9 are UNTOUCHED, and errno does not move at all (3 -> 3)' % '')
print('  %-12s directives 12 -> 11, <stdio.h> gone and named nowhere; cmdnames[] 98 and '
      'options[] 107 unchanged; no run of two blank lines' % '')
PY

# --- 3. phase 20's structural check, unchanged and re-run here -------------------------
tools/st.sh zhostonly "$f"

# --- 4. the compile, the linkage and the libc surface ----------------------------------
# ONE comm.  Four of the seven -- fputc fputs fwrite putchar -- are named NOWHERE in
# the source: gcc emits them from printf("%s", x) and fprintf(stderr, "%s", x).  The
# empty `arrived` side is what turns "they should go too" into a measurement.
cp "$state/symbols/undefined" "$tmp/before.u"
tools/phasecheck.sh "$work" "$f" "$state/symbols"
comm -23 "$tmp/before.u" .cache/symbols/last/undefined > "$tmp/gone.u"
comm -13 "$tmp/before.u" .cache/symbols/last/undefined > "$tmp/came.u"
printf 'fflush\nfputc\nfputs\nfwrite\nprintf\nputchar\nstderr\n' > "$tmp/want.u"
if ! cmp -s "$tmp/gone.u" "$tmp/want.u" || [ -s "$tmp/came.u" ]; then
    echo "  message      the libc surface did not move by exactly those seven:"
    echo "               gone: $(tr '\n' ' ' < "$tmp/gone.u")"
    echo "               came: $(tr '\n' ' ' < "$tmp/came.u")"
    echo "               NOTHING MAY ARRIVE, and nothing else may leave.  fputc, fputs,"
    echo "               fwrite and putchar are gcc's, named nowhere in the source, and"
    echo "               were PREDICTED to leave with the construct."
    exit 1
fi
# WHAT MUST STILL BE THERE.  `write` is now host_message's as well as mch_write's, and
# __errno_location is phase 20's two EINTR tests and not this phase's business.
for want in write read __errno_location ioctl select tcgetattr tcsetattr nanosleep \
            sigaction sigemptyset kill getpid malloc free realloc time gettimeofday; do
    if ! grep -qx "$want" .cache/symbols/last/undefined; then
        echo "  message      $want is NOT undefined any more, and this phase does not"
        echo "               claim to free it.  __errno_location in particular is held"
        echo "               by phase 20's two `== EINTR` tests and leaves at the split."
        exit 1
    fi
done
# ZERO-PLAN.md 4b, still absolute, and now visible in the directive list too.
for absent in open creat openat stat access fcntl getcwd strerror fopen fdopen \
              opendir fclose getc putc fsync exit _exit close dup isatty; do
    if grep -qx "$absent" .cache/symbols/last/undefined; then
        echo "  message      $absent is undefined, and no phase since 13 has put it back"; exit 1
    fi
done
echo "  message      symbols $(cat .cache/symbols/last/before) -> $(cat .cache/symbols/last/after), the gone set is EXACTLY fflush fputc fputs fwrite printf putchar stderr and NOTHING arrives -- four of the seven (fputc fputs fwrite putchar) are gcc's own, named nowhere in the source, predicted to leave with the construct and verified by building"
echo "  message      write and read are REQUIRED still present -- the core still writes fd 1 through mch_write and the host writes fd 2 through host_message, which is what is left of ZERO-PLAN.md 4c; __errno_location is required present too, and it is phase 20's"

# --- 5. the binary -----------------------------------------------------------------------
make -C "$work" clean >/dev/null 2>&1 || true
[ -e "$work/zero-vim" ] && { echo "  build        the clean did not remove zero-vim"; exit 1; }
if ! make -C "$work" >/dev/null 2>&1; then
    echo "  build        FAILED -- rerun by hand: make -C $work"
    exit 1
fi
bin="$work/zero-vim"
echo "  build        ok, $before_lines -> $(grep -c '' "$f") lines, $(stat -c%s "$bin") bytes"

for p in $pids; do
    wait "$p" || { echo "  message      one of the control or instrumented builds failed"; exit 1; }
done

# --- 6. five recordings, all at once -----------------------------------------------------
rpids=
for v in "old $state/old $state/old.c" "new $bin $f" "ctl $tmp/ctl $tmp/ctl.c" \
         "IN $tmp/IN $tmp/IN.c" "OUT $tmp/OUT $tmp/OUT.c"; do
    # shellcheck disable=SC2086
    set -- $v
    tools/zrecord.sh "$2" "$3" "$tmp/REC-$1" >/dev/null 2>&1 &
    rpids="$rpids $!"
done
for p in $rpids; do
    wait "$p" || { echo "  message      a recording failed"; exit 1; }
done

# --- 7. the probes -----------------------------------------------------------------------
python3 - "$state/old" "$bin" "$tmp" <<'PY'
import concurrent.futures
import os
import re
import socket
import subprocess
import sys

sys.path.insert(0, 'tools')
# tools/zstream.py -- named as a PATH so tools/implhash.sh hashes it into this
# phase's key.  implhash greps for paths and an `import` names a module, so
# without this line an edit to it changes what this phase produces and moves
# no key at all.  See CLAUDE.md on cutil.py and macros.py.  Do not delete it.
import zstream

TAG = 'message'
OLD, NEW, TMP = sys.argv[1], sys.argv[2], sys.argv[3]
fail = []


def env_for():
    env = dict(os.environ)
    env.update(TERM='xterm', HOME=TMP + '/h', VIM=TMP + '/h/nv',
               VIMRUNTIME=TMP + '/h/nv', XDG_CONFIG_HOME=TMP + '/h/xdg')
    for k in ('LINES', 'COLUMNS', 'VIMINIT', 'EXINIT', 'MYVIMRC'):
        env.pop(k, None)
    return env


def seqwrites(binary, args):
    """Write BOUNDARIES on fd 2: SOCK_SEQPACKET preserves one message per write()."""
    vim = zstream.stage(binary)
    a, b = socket.socketpair(socket.AF_UNIX, socket.SOCK_SEQPACKET)
    devnull = os.open(os.devnull, os.O_RDWR)
    pid = os.fork()
    if pid == 0:
        a.close()
        os.dup2(devnull, 0)
        os.dup2(devnull, 1)
        os.dup2(b.fileno(), 2)
        os.execve(vim, [vim] + list(args), env_for())
        os._exit(127)
    b.close()
    os.close(devnull)
    os.waitpid(pid, 0)
    a.setblocking(False)
    msgs = []
    while True:
        try:
            m = a.recv(65536)
        except BlockingIOError:
            break
        if not m:
            break
        msgs.append(m)
    a.close()
    return len(msgs), b''.join(msgs)


def stderr_of(binary, args):
    vim = zstream.stage(binary)
    p = subprocess.run([vim] + list(args), stdin=subprocess.DEVNULL,
                       capture_output=True, env=env_for())
    return p.stderr


def scrub(b):
    """The version banner carries __DATE__/__TIME__, which differ between two builds of
    the same source.  Its LENGTH does not -- __DATE__ is 11 characters and __TIME__ 8 --
    so the byte counts below are raw and only the equality is scrubbed."""
    return re.sub(rb'compiled [^)]*', b'<compiled>', b)


def marked(d):
    """Which records of a recording carry the instrument's marker."""
    M = b'MESSAGE-OUT'
    out = {}
    sd = os.path.join(d, 'screen')
    names = sorted(os.listdir(sd))
    out['screen'] = ([n for n in names
                      if M in open(os.path.join(sd, n), 'rb').read()], len(names))
    for name in ('ref-argv.txt', 'ref-excmds.txt', 'ref-pty.txt', 'ref-term.txt'):
        txt = open(os.path.join(d, name), 'rb').read()
        blocks = [b for b in re.split(br'(?m)^(?==== )', txt) if b.strip()]
        out[name] = ([b.split(b'\n')[0].decode('latin-1') for b in blocks if M in b],
                     len(blocks))
    return out


def diffcount(a, b):
    p = subprocess.run(['diff', '-r', a, b], capture_output=True)
    return len(p.stdout.decode('latin-1', 'replace').splitlines())


# seqwrites() forks, so it is run HERE and not inside the pool below: fork() in a
# multi-threaded process is a DeprecationWarning in 3.12 and a real hazard in general,
# and these four execs cost a tenth of a second between them.
g = {'seq_Q_old': seqwrites(OLD, ['-Q']), 'seq_Q_new': seqwrites(NEW, ['-Q']),
     'seq_T_old': seqwrites(OLD, ['-T', 'no-such-term-9x']),
     'seq_T_new': seqwrites(NEW, ['-T', 'no-such-term-9x'])}

JOBS = {
    'long900_old': lambda: stderr_of(OLD, ['-' + 'x' * 900]),
    'long900_new': lambda: stderr_of(NEW, ['-' + 'x' * 900]),
    'long2k_old': lambda: stderr_of(OLD, ['-' + 'x' * 2000]),
    'long2k_new': lambda: stderr_of(NEW, ['-' + 'x' * 2000]),
    'termlong_old': lambda: stderr_of(OLD, ['-T', 'z' * 2000]),
    'termlong_new': lambda: stderr_of(NEW, ['-T', 'z' * 2000]),
    'diff_new': lambda: diffcount(TMP + '/REC-old', TMP + '/REC-new'),
    'diff_ctl': lambda: diffcount(TMP + '/REC-old', TMP + '/REC-ctl'),
    'mark_IN': lambda: marked(TMP + '/REC-IN'),
    'mark_OUT': lambda: marked(TMP + '/REC-OUT'),
}
with concurrent.futures.ThreadPoolExecutor(max_workers=len(JOBS)) as ex:
    keys = list(JOBS)
    g.update(zip(keys, ex.map(lambda k: JOBS[k](), keys)))

# ---- MUST NOT DIFFER: the whole recording ------------------------------------------------
if g['diff_new'] != 0:
    fail.append('THE RECORDING MOVED: `diff -r` of the binary this phase was handed and '
                'the one it made reports %d lines, and this phase declares NOTHING.  '
                'The same bytes must reach the same file descriptors at the same '
                'moments; only the syscall underneath them changes' % g['diff_new'])

# ---- MUST DIFFER: the control ------------------------------------------------------------
if g['diff_ctl'] == 0:
    fail.append('THE CONTROL DID NOT MOVE.  `write(err ? 2 : 1, ...)` made '
                '`write(err ? 1 : 1, ...)` sends every message to stdout instead of '
                'stderr, which must move all 24 message-bearing records.  A check that '
                'cannot fail is not evidence')

# ---- MUST DIFFER: the write boundaries ---------------------------------------------------
for tag, args, nold, nnew, nbytes in (('Q', '-Q', 6, 1, 96),
                                      ('T', '-T no-such-term-9x', 5, 1, 54)):
    co, bo = g['seq_%s_old' % tag]
    cn, bn = g['seq_%s_new' % tag]
    if (co, cn) != (nold, nnew):
        fail.append('seq_%s (`%s`): %d write()s on the input and %d here, expected %d '
                    'and %d' % (tag, args, co, cn, nold, nnew))
    if len(bo) != nbytes or len(bn) != nbytes:
        fail.append('seq_%s: %d bytes on the input and %d here, expected %d on both -- '
                    'the SYSCALLS collapse and the BYTES do not'
                    % (tag, len(bo), len(bn), nbytes))
    if scrub(bo) != scrub(bn):
        fail.append('seq_%s: the byte stream on fd 2 differs.  old=%r new=%r'
                    % (tag, bo, bn))

# ---- MUST NOT DIFFER, then MUST: the buffer's bound --------------------------------------
if scrub(g['long900_old']) != scrub(g['long900_new']) or len(g['long900_old']) != 995:
    fail.append('an unknown option of 900 characters is not the same 995 bytes on both '
                'binaries (%d and %d) -- the 1024-byte assembly buffer is biting earlier '
                'than measured, or the message moved'
                % (len(g['long900_old']), len(g['long900_new'])))
if len(g['long2k_old']) != 2095 or len(g['long2k_new']) != 1023:
    fail.append('an unknown option of 2,000 characters gives %d bytes on the input and '
                '%d here, expected 2,095 and exactly 1,023 -- the cap this phase '
                'introduces is stated, not discovered, and a cap that drifted either '
                'way is a different phase'
                % (len(g['long2k_old']), len(g['long2k_new'])))
if len(g['termlong_old']) != 2039 or len(g['termlong_new']) != 1023:
    fail.append('a -T of 2,000 characters gives %d bytes on the input and %d here, '
                'expected 2,039 and exactly 1,023 -- the same cap reached by the other '
                'speaker, which has no version banner in front of it'
                % (len(g['termlong_old']), len(g['termlong_new'])))

# ---- MUST NOT DIFFER: the instrumented pair ----------------------------------------------
a, b = g['mark_IN'], g['mark_OUT']
for k in a:
    if a[k][0] != b[k][0]:
        fail.append('the instrumented pair disagrees on %s: the input marks %d record(s) '
                    'and the output %d.  Same places, same times, different primitive -- '
                    'and that is the whole evidence that an empty declaration is empty '
                    'for the right reason' % (k, len(a[k][0]), len(b[k][0])))
for k in ('screen', 'ref-excmds.txt', 'ref-pty.txt', 'ref-term.txt'):
    if a[k][0]:
        fail.append('%s carries the marker in %d record(s) and should carry it in none: '
                    'nothing in the corpus but a command line ever makes this editor '
                    'write to a stream' % (k, len(a[k][0])))
if len(a['ref-argv.txt'][0]) != 24 or a['ref-argv.txt'][1] != 30:
    fail.append('the instrument marks %d of the %d argv rows, expected 24 of 30 -- 23 '
                'mainerr and one report_term_error, which is also what says the other '
                'four speakers (msg_puts_printf x4, exit_scroll x2) fire in ZERO of 106 '
                'records' % (len(a['ref-argv.txt'][0]), a['ref-argv.txt'][1]))

if fail:
    for line in fail:
        print('  %-12s %s' % (TAG, line))
    sys.exit(1)

print('  %-12s MUST NOT DIFFER: the whole recording, `diff -r`, %d lines -- 102 screen '
      'cases, ref-excmds.txt, ref-argv.txt, ref-pty.txt and ref-term.txt.  THAT is the '
      'check and not tools/zerodelta.sh, which accepts further movement in the ten argv '
      'rows phases 4 and 5 already declared' % (TAG, g['diff_new']))
print('  %-12s MUST DIFFER, the control: this phase\'s own output with `err ? 2 : 1` '
      'made `err ? 1 : 1`, one character, moves %d lines of `diff -r`.  The table can '
      'fail' % ('', g['diff_ctl']))
print('  %-12s MUST DIFFER, the write boundaries, with a SOCK_SEQPACKET fd 2: `-Q` is '
      '%d writes of %d bytes on the input and %d of %d here; `-T no-such-term-9x` is %d '
      'of %d and %d of %d.  The same bytes, one syscall -- and the latent hazard goes '
      'with them, stdout\'s buffered printf arm arriving after everything the editor '
      'drew'
      % ('', g['seq_Q_old'][0], len(g['seq_Q_old'][1]), g['seq_Q_new'][0],
         len(g['seq_Q_new'][1]), g['seq_T_old'][0], len(g['seq_T_old'][1]),
         g['seq_T_new'][0], len(g['seq_T_new'][1])))
print('  %-12s THE INSTRUMENTED PAIR, phase 9\'s shape: the input built with '
      'write(2, "MESSAGE-OUT\\n", 12) at all 19 output statements and the output with '
      'the IDENTICAL instrument inside host_message() mark exactly the same %d of the '
      '30 argv rows, by name, and 0 of 102 screens, 0 excmds, 0 pty, 0 term.  The 24 '
      'are 23 mainerr and one report_term_error, so msg_puts_printf and exit_scroll\'s '
      'printf arm fire in ZERO of 106 records and are nonetheless kept'
      % ('', len(a['ref-argv.txt'][0])))
print('  %-12s THE BOUND, stated rather than discovered: an unknown option of 900 '
      'characters is the same %d bytes on both binaries and one of 2,000 is %d bytes on '
      'the input and exactly %d here; a -T of 2,000 is %d against %d -- the same cap, '
      'reached by the other speaker.  1024 is IOSIZE and is what every other message in '
      'this editor is built in'
      % ('', len(g['long900_old']), len(g['long2k_old']), len(g['long2k_new']),
         len(g['termlong_old']), len(g['termlong_new'])))
PY

# --- 8. the second opinion, on the control ------------------------------------------------
# tools/zerodelta.sh is run by tools/phaserun.sh on the real binary after this check.
# Here it is run on the CONTROL, where it MUST refuse -- and the number it names is the
# reason `diff -r` above is the first check and this is the second: it sees fourteen of
# the twenty-four moved records, the other ten being argv rows phases 4 and 5 already
# declared and tools/zcompare.py therefore no longer compares.
if tools/zerodelta.sh "$tmp/ctl" "$tmp/ctl.c" --phase 21 >"$tmp/zd.txt" 2>&1; then
    echo "  message      tools/zerodelta.sh ACCEPTED the control, which sends every"
    echo "               message to stdout instead of stderr.  It must refuse."
    tail -5 "$tmp/zd.txt"
    exit 1
fi
named=$(sed -n 's/.*ref-argv.txt moved and was not declared: //p' "$tmp/zd.txt" | tr ' ' '\n' | grep -c 'argv:' || true)
if [ "$named" -lt 1 ]; then
    echo "  message      tools/zerodelta.sh refused the control for some other reason:"
    tail -5 "$tmp/zd.txt"
    exit 1
fi
echo "  message      the second opinion: tools/zerodelta.sh REFUSES the control and names $named argv rows, against the 24 records diff -r sees.  That gap is exactly why diff -r is the first check and this is the second: ten of the 24 are rows phases 4 and 5 already declared, and tools/zcompare.py no longer compares them"

# tools/phaserun.sh runs tools/zerodelta.sh --phase 21 after this check, and this
# phase declares NOTHING: the corpus must not move at all.
