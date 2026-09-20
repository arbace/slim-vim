#!/bin/sh
# Zero phase 20, the check -- the signals and the terminal are the host's.
# See pipes/zero20-edit.sh, and ZERO-GOAL.md.
#
# Usage: pipes/zero20-check.sh <work-dir> <state-dir>    (run from the repository root)
#
# Runs after pipes/zero20-edit.sh and the sweep tools/phaserun.sh runs between them,
# and reads nothing from the edit's shell -- only the work tree and the state
# directory.  What the edit left there is `old.c`, the source this phase was HANDED,
# and `old`, that source built with the boundary's own flags.  EVERY PROBE BELOW IS A
# PAIR, because a number from one binary is not evidence.
#
# WHAT IS CLAIMED, in three parts, and each has its own kind of check:
#
#   STRUCTURE   the core names none of the host's vocabulary.  This is the phase's
#               real content and ``zhostonly`` is the assertion: 43 words,
#               every mention inside the host block, seven named exceptions in the
#               core that are the deadly-signal message and the clock.  A count of
#               `sigaction` would say nothing about WHERE.
#   SYMBOLS     `nm -u` loses exactly `close dup isatty raise sigaddset sigismember
#               sigprocmask` and gains nothing -- ONE comm, not two, because the two
#               halves of this phase are one phase.  It does NOT lose `sigaction
#               sigemptyset kill ioctl tcgetattr tcsetattr nanosleep select`, and the
#               check requires those PRESENT: moving code from the core to the host
#               inside one translation unit frees nothing, and a check that asserted
#               them gone would be asserting the file split had happened.
#   BEHAVIOUR   the declared delta is NOTHING, so tools/zerodelta.sh proves the
#               recording did not move -- and the recording cannot see any of this
#               (no case sends a signal, resizes a window, types `gs` or reaches EOF
#               with a terminal on fd 2), so the phase owes probes.  Fifteen of them,
#               below, seven that MUST differ and eight that MUST NOT.
#
# THE PROBES THAT MATTER MOST ARE THE ONES THAT MUST NOT DIFFER, and two of them are
# the whole reason the signal phase and the terminal phase were merged:
# `sigterm_restores` and `sighup_restores` require the editor killed mid-session to
# restore the terminal to ICANON=1 ECHO=1 ISIG=1 ONLCR=1 ICRNL=1, print `Vim: Caught
# deadly signal TERM` and `Vim: Finished.`, and exit 1 -- on BOTH binaries.  A
# host-side deadly handler that simply died would leave the tty raw, and the phase
# would have shipped a regression with a promise to fix it later.
#
# `gs_interrupt` IS THE PROBE WITH ITS OWN CONTROL.  `10gs` then CTRL-C recovers in
# about 1.8 s on both binaries; the check also builds THIS PHASE'S OWN OUTPUT with the
# two `host_tty_set` calls inside `musl_delay` deleted and requires that one NOT to
# recover at all.  Without that control, "both took 1.8 s" is two numbers agreeing and
# proves nothing about the sleep mode being real.
#
# `sigint_external` IS HERE BECAUSE IT CAUGHT A REAL BUG.  With no SIGINT handler at
# all -- which is what deleting `catch_sigint` leaves -- SIG_DFL kills the editor, and
# the `gs` probe found it: the sleep mode leaves ISIG on, so CTRL-C during a `gs`
# raises SIGINT.  The host catches it and hands the core a `0x03` byte, which is what
# `fill_input_buf` already turns into `got_int`.
#
# THE COUNTING TRAPS, AND WHY THE ASSERTIONS ARE SHAPED AS THEY ARE:
#
#   * `resize_func` IS NOT AT 0.  It is `inchar_loop`'s parameter, which stays -- the
#     core passes NULL and inchar_loop tests for it.  `assert resize_func at 0` fails
#     on a correct phase.
#   * `deathtrap` GOES UP, 3 -> 4, because the host installs it twice.  A phase about
#     removing signal handling that leaves one MORE mention of a handler is exactly
#     what this phase is, and the number says so.
#   * `errno` DOES NOT MOVE, 3 -> 3.  Both its uses are host-side now and the third is
#     `#include <errno.h>`, so `<errno.h>` leaves the CORE and `__errno_location`
#     stays in `nm -u` until the split.  Said out loud rather than implied.
#   * A PTY BYTE COUNT IS NOT AN ASSERTION.  The pty probes drive a real terminal with
#     real waits, so what they assert is structural -- exit status, terminal mode,
#     what text was drawn -- and the byte counts are REPORTED.  The two places a count
#     IS the evidence are `tstp_external`, where it must differ, and `stopcont`, where
#     both must draw a whole screen.  The deterministic pipe probes
#     (tools/zstream.py) do assert exactly.
set -eu

work=${1:?usage: zero20-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero20-check.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"
before_lines=$(cat "$state/input-lines")

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")

# --- 1. the control, written and started first because its build is the slow part -----
python3 - "$f" "$tmp/nosleep.c" <<'PY'
import sys
TAG = 'host'
t = open(sys.argv[1], errors='surrogateescape').read()
A = '''    if (relax)
    {
        host_tty_set(FALSE, TRUE);
    }
'''
B = '''    if (relax)
    {
        host_tty_set(TRUE, FALSE);
    }
'''
for text in (A, B):
    if t.count(text) != 1:
        sys.exit('  %-12s the musl_delay sleep-mode pair is not in the output exactly '
                 'once, so the control below would not be the control' % TAG)
open(sys.argv[2], 'w', errors='surrogateescape').write(t.replace(A, '').replace(B, ''))
print('  %-12s the control: this phase\'s own output with musl_delay()\'s two '
      'host_tty_set() calls deleted and nothing else -- the sleep mode gone and the '
      'nanosleep left' % TAG)
PY
# shellcheck disable=SC2086
( gcc $cflags $ldflags -o "$tmp/nosleep" "$tmp/nosleep.c" ) &
pid_nosleep=$!

# --- 2. the source ---------------------------------------------------------------------
python3 - "$f" "$state/old.c" <<'PY'
import re, sys
TAG = 'host'
new = open(sys.argv[1], errors='surrogateescape').read()
old = open(sys.argv[2], errors='surrogateescape').read()
fail = []


def mentions(text, name):
    return len(re.findall(r'\b%s\b' % name, text))


# THE INPUT, so this is a check on the phase and not on whatever it was handed.
for name, want in (('mch_signal', 18), ('signal_info', 9), ('settmode', 13),
                   ('isatty', 4), ('deathtrap', 3), ('win_resize_enabled', 6)):
    if mentions(old, name) != want:
        fail.append('the input has %d mentions of `%s`, expected %d'
                    % (mentions(old, name), name, want))

# WHAT IS GONE.  Thirty-four names, and every one of them was either a signal handler,
# the machinery that installed one, a terminal mode, or a question about whether this
# is a terminal at all.
GONE = ('mch_signal set_signals reset_signals catch_signals catch_int_signal '
        'catch_sigint sig_tstp sigcont_handler sigcont_received after_sigcont '
        'in_mch_suspend ignore_sigtstp got_tstp sig_winch set_sigwinch_handler '
        'handle_resize do_resize mch_get_shellsize win_resize_setting '
        'win_resize_enabled term_set_win_resize did_set_termresize p_trz '
        'settmode mch_settmode mch_tcgetattr get_tty_fd mch_cur_tmode cur_tmode '
        'mch_check_win stdout_isatty did_read_something isatty out_redir '
        'tmode_T TMODE_COOK TMODE_RAW TMODE_SLEEP sighandler_T '
        'MCH_DELAY_SETTMODE').split()
left = [n for n in GONE if mentions(new, n)]
if left:
    fail.append('these names should be at 0 mentions and are not: %s' % ' '.join(left))
for n in GONE:
    if not mentions(old, n):
        fail.append('`%s` was already at 0 in the input, so its absence proves nothing'
                    % n)

# WHAT IS THERE, and the three that a reader will expect to be smaller.
for name, want, why in (
        ('resize_func', 6, "inchar_loop's PARAMETER, which STAYS: the prototype, the "
                           'definition and three uses inside it.  The core passes '
                           'NULL and inchar_loop tests for it, so `assert resize_func '
                           'at 0` fails on a correct phase'),
        ('deathtrap', 4, 'a prototype, the definition and the TWO installations in '
                         'musl_host_init().  It GOES UP: the host installs the core\'s '
                         'deadly handler rather than replacing it, which is what keeps '
                         'the terminal restored and the message printed'),
        ('vim_handle_signal', 5, 'untouched -- a prototype, the definition, '
                                 "deathtrap's call and the two in ui_inchar"),
        ('signal_info', 4, 'the struct tag, the array and deathtrap\'s two reads.  Its '
                           'five rows are two and its `deadly` field is gone, because '
                           'catch_signals() was its only reader'),
        ('term_enter', 6, 'a prototype, the definition and four call sites'),
        ('term_leave', 5, 'a prototype, the definition and three call sites'),
        ('term_entered', 6, 'the flag that replaced the three-valued cur_tmode'),
        ('musl_host_init', 3, 'prototype, definition, and the one call from mch_init()'),
        ('musl_get_winsize', 4, 'prototype, definition, ui_get_shellsize()\'s call and '
                                'musl_read_input()\'s'),
        ('musl_term_start', 3, 'prototype, definition, term_enter()\'s call'),
        ('musl_term_stop', 3, 'prototype, definition, term_leave()\'s call'),
        ('musl_tty_keys', 3, 'prototype, definition, get_tty_info()\'s call'),
        ('musl_delay', 3, 'prototype, definition, mch_delay()\'s call'),
        ('musl_wait_for_input', 3, 'prototype, definition, RealWaitForChar()\'s call -- '
                                   'ONE call site, because the pending check that was '
                                   'going to be a second function lives inside it'),
        ('musl_read_input', 3, 'prototype, definition, fill_input_buf()\'s call'),
        ('musl_suspend', 3, 'prototype, definition, mch_suspend()\'s call'),
        ('host_catch', 11, 'its definition, eight installations in musl_host_init() '
                           'and two in musl_suspend()'),
        ('errno', 3, 'UNCHANGED, and said out loud: the #include and two uses, both of '
                     'them host-side now.  So <errno.h> leaves the CORE and '
                     '__errno_location stays in nm -u until the file splits'),
        ('sigaction', 2, 'both in host_catch(), 0 in the core'),
        ('sigemptyset', 1, 'host_catch(), 0 in the core'),
        ('kill', 2, "musl_suspend()'s kill(0, SIGTSTP) and vim_handle_signal()'s "
                    're-raise, which is the one core mention and a named exception in '
                    'zhostonly'),
        ('ioctl', 2, "the #include and the host's one TIOCGWINSZ"),
        ('tcgetattr', 2, 'host_tty_set() and musl_tty_keys()'),
        ('tcsetattr', 1, 'host_tty_set()'),
        ('nanosleep', 1, 'musl_delay()'),
        ('select', 1, 'musl_wait_for_input().  There is no #include for it: it arrives '
                      'transitively through <sys/param.h> (ZERO-PLAN.md 4c)'),
        ('getpid', 2, "mch_get_pid()'s and vim_handle_signal()'s -- neither is this "
                      "phase's, and getpid stays"),
):
    if mentions(new, name) != want:
        fail.append('`%s` has %d mentions, expected %d -- %s'
                    % (name, mentions(new, name), want, why))

# THE SHAPE OF THE FILE.
sys.path.insert(0, 'tools')
import create_cmdidxs
rows = re.findall(r'^    \[CMD_\w+\] = \{.*$', new, re.M)
if len(rows) != 98 or len(create_cmdidxs.names(sys.argv[1])) != 98:
    fail.append('cmdnames[] is not the 98 rows phase 10 left -- this phase touches no '
                'Ex command')
i = new.find('static struct vimoption options[]')
j = new.index('\n};', i)
n_opt = len(re.findall(r'^[ \t]*\{"([a-z]+)",', new[i:j], re.M))
if n_opt != 107:
    fail.append("options[] has %d rows, expected 107 -- 'termresize' is the one row "
                'this phase removes, from the 108 phase 12 left' % n_opt)
d = [l for l in new.split('\n') if l.startswith('#')]
if len(d) != 12 or any(not l.startswith('#include <') for l in d):
    fail.append('the output does not have exactly the twelve `#include` directives '
                'phase 16 left.  This phase adds none and removes none: <errno.h> and '
                '<termios.h> are still needed, by the HOST')
L = new.split('\n')
if sum(1 for k in range(1, len(L)) if L[k] == '' and L[k - 1] == ''):
    fail.append('there is a run of two blank lines, which canon.sh should have taken')

if fail:
    for line in fail:
        print('  %-12s %s' % (TAG, line))
    sys.exit(1)
print('  %-12s 40 names at 0: every signal handler, the installer, the three-valued '
      'terminal mode and every question about whether this is a terminal.  '
      '`resize_func` is NOT among them (it is inchar_loop\'s parameter) and '
      '`deathtrap` goes UP, 3 -> 4, because the host installs the core\'s deadly '
      'handler rather than replacing it' % TAG)
print('  %-12s the host is 11 host_catch() installations, 2 sigaction, 1 sigemptyset, '
      '1 kill, 1 ioctl, 2 tcgetattr, 1 tcsetattr, 1 nanosleep and 1 select; `errno` '
      'does not move at all (3 -> 3), both its uses being host-side, so <errno.h> '
      'leaves the CORE and __errno_location stays until the split' % '')
print('  %-12s cmdnames[] 98 unchanged, options[] 108 -> 107 (`termresize`), twelve '
      '#includes unchanged, no run of two blank lines' % '')
PY

# --- 3. the structural claim, which is the phase ---------------------------------------
tools/st.sh zhostonly "$f"

# --- 4. the compile, the linkage and the libc surface ----------------------------------
# ONE comm for the whole phase, because the signals half and the terminal half are one
# phase.  Four of the seven are what mch_signal()'s fifty lines of sigset() emulation
# and sig_tstp()'s re-raise named; three are the descriptor sites and the terminal
# questions the phase deletes outright.
cp "$state/symbols/undefined" "$tmp/before.u"
tools/phasecheck.sh "$work" "$f" "$state/symbols"
comm -23 "$tmp/before.u" .cache/symbols/last/undefined > "$tmp/gone.u"
comm -13 "$tmp/before.u" .cache/symbols/last/undefined > "$tmp/came.u"
printf 'close\ndup\nisatty\nraise\nsigaddset\nsigismember\nsigprocmask\n' > "$tmp/want.u"
if ! cmp -s "$tmp/gone.u" "$tmp/want.u" || [ -s "$tmp/came.u" ]; then
    echo "  host         the libc surface did not move by exactly those seven:"
    echo "               gone: $(tr '\n' ' ' < "$tmp/gone.u")"
    echo "               came: $(tr '\n' ' ' < "$tmp/came.u")"
    echo "               NOTHING MAY ARRIVE, and nothing else may leave."
    exit 1
fi
# WHAT MUST STILL BE THERE.  Moving a call from the core to the host inside one
# translation unit frees nothing: a symbol leaves when its last CALLER leaves the file.
for want in sigaction sigemptyset kill ioctl tcgetattr tcsetattr nanosleep select \
            read write __errno_location; do
    if ! grep -qx "$want" .cache/symbols/last/undefined; then
        echo "  host         $want is NOT undefined any more, and this phase does not"
        echo "               claim to free it -- the host block calls it from the same"
        echo "               translation unit.  If this is really gone, the claim in"
        echo "               pipes/zero20-edit.sh's header is wrong and needs rewriting"
        exit 1
    fi
done
# ZERO-PLAN.md 4b, now absolute: the core cannot acquire a descriptor at all.
for absent in open creat openat stat access fcntl getcwd strerror fopen fdopen \
              opendir fclose getc putc fsync exit _exit; do
    if grep -qx "$absent" .cache/symbols/last/undefined; then
        echo "  host         $absent is undefined, and no phase since 13 has put it back"; exit 1
    fi
done
echo "  host         symbols $(cat .cache/symbols/last/before) -> $(cat .cache/symbols/last/after), the gone set is EXACTLY close dup isatty raise sigaddset sigismember sigprocmask and NOTHING arrives -- and sigaction sigemptyset kill ioctl tcgetattr tcsetattr nanosleep select are REQUIRED still present, because moving a call inside one translation unit frees nothing"
echo "  host         ZERO-PLAN.md 4b in its strongest form: with close and dup gone the core cannot open, close or duplicate ANY descriptor -- it is handed fds 0, 1 and 2 and that is the whole of it"

# --- 5. the binary ----------------------------------------------------------------------
make -C "$work" clean >/dev/null 2>&1 || true
[ -e "$work/zero-vim" ] && { echo "  build        the clean did not remove zero-vim"; exit 1; }
if ! make -C "$work" >/dev/null 2>&1; then
    echo "  build        FAILED -- rerun by hand: make -C $work"
    exit 1
fi
bin="$work/zero-vim"
echo "  build        ok, $before_lines -> $(grep -c '' "$f") lines, $(stat -c%s "$bin") bytes"

wait $pid_nosleep || { echo "  host         the control did not build"; exit 1; }

# --- 6. the probes, because no recording can see any of this ---------------------------
python3 - "$state/old" "$bin" "$tmp/nosleep" <<'PY'
import concurrent.futures
import fcntl
import os
import pty
import re
import select
import shutil
import signal
import struct
import sys
import tempfile
import termios
import time

sys.path.insert(0, 'tools')
import zstream

TAG = 'host'
OLD, NEW, NOSLEEP = sys.argv[1], sys.argv[2], sys.argv[3]
ESC = b'\x1b'
fail = []


def env_for(home):
    env = dict(os.environ)
    env.update(TERM='xterm', HOME=home, VIM=os.path.join(home, 'nv'),
               VIMRUNTIME=os.path.join(home, 'nv'),
               XDG_CONFIG_HOME=os.path.join(home, 'xdg'))
    for k in ('LINES', 'COLUMNS', 'VIMINIT', 'EXINIT', 'MYVIMRC'):
        env.pop(k, None)
    return env


def setsize(fd, r, c):
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack('HHHH', r, c, 0, 0))


def pipe(binary, keys, rows=40, cols=200, snap=-2):
    """A deterministic session on pipes.  tools/zstream.py stages argv[0] as `vim`."""
    scr, out, err, rc = zstream.session(binary, keys, rows=rows, cols=cols)
    if not scr.snaps:
        return '<no snapshot>', len(out), rc
    k = snap if len(scr.snaps) >= abs(snap) else -1
    body = [l.rstrip() for l in scr.snaps[k][0].split('\n')
            if l.strip() and l.strip() != '~']
    return ' || '.join(body)[:110], len(out), rc


class Term:
    """A real pty.  THE CHILD SETS ITS OWN WINDOW SIZE BEFORE exec (tools/zpty.py)."""

    def __init__(self, binary, args=('+set paste',), rows=24, cols=80,
                 stdin_devnull=False, stdout_pipe=False):
        vim = zstream.stage(binary)
        self.home = tempfile.mkdtemp(prefix='zero20-')
        rp = wp = None
        if stdout_pipe:
            rp, wp = os.pipe()
        pid, fd = pty.fork()
        if pid == 0:
            setsize(0, rows, cols)
            if stdin_devnull:
                os.dup2(os.open(os.devnull, os.O_RDONLY), 0)
            if stdout_pipe:
                os.close(rp)
                os.dup2(wp, 1)
                os.dup2(wp, 2)
            os.execve(vim, [vim] + list(args), env_for(self.home))
            os._exit(1)
        if stdout_pipe:
            os.close(wp)
        self.pid, self.fd, self.out, self.pipe = pid, fd, bytearray(), rp

    def pump(self, secs):
        src = [self.fd] + ([self.pipe] if self.pipe is not None else [])
        end = time.time() + secs
        while time.time() < end and src:
            for g in select.select(src, [], [], 0.05)[0]:
                try:
                    b = os.read(g, 65536)
                except OSError:
                    src.remove(g)
                    continue
                if b:
                    self.out.extend(b)
                else:
                    # END OF FILE, AND IT HAS TO BE TAKEN OUT OF THE SET.  A closed
                    # descriptor is readable for ever, so a select that keeps asking
                    # about it spins at full speed for the rest of the wait -- with
                    # thirty-three probes running at once that is the machine, not the
                    # editor, and every byte count below is a reading of the machine.
                    src.remove(g)

    def keys(self, k):
        try:
            os.write(self.fd, k)
        except OSError:
            pass

    def mode(self):
        a = termios.tcgetattr(self.fd)
        return 'ICANON=%d ECHO=%d ISIG=%d ONLCR=%d ICRNL=%d' % (
            bool(a[3] & termios.ICANON), bool(a[3] & termios.ECHO),
            bool(a[3] & termios.ISIG), bool(a[1] & termios.ONLCR),
            bool(a[0] & termios.ICRNL))

    def reap(self, secs=3.0):
        end = time.time() + secs
        while time.time() < end:
            p, s = os.waitpid(self.pid, os.WNOHANG)
            if p:
                if os.WIFSIGNALED(s):
                    return 'killed by SIG%d' % os.WTERMSIG(s)
                return 'exit %d' % os.WEXITSTATUS(s)
            self.pump(0.05)
        try:
            os.kill(self.pid, signal.SIGKILL)
            os.waitpid(self.pid, 0)
        except Exception:
            pass
        return 'STILL RUNNING'

    def text(self):
        return re.sub(rb'\x1b\[[0-9;?]*[A-Za-z]', b'', bytes(self.out))

    def close(self):
        for g in (self.fd, self.pipe):
            try:
                if g is not None:
                    os.close(g)
            except Exception:
                pass
        shutil.rmtree(self.home, ignore_errors=True)


# ---- the probes, each a function of one binary ----------------------------------------
def p_resize_inband(b):
    return pipe(b, [ESC + b'[48;30;100t', b':set columns?\r', ESC + b':q!\r'])


def p_trz_query(b):
    return pipe(b, [b':set trz?\r', ESC + b':q!\r'])


def p_trz_set(b):
    return pipe(b, [b':set trz=sigwinch\r', ESC + b':q!\r'])


def p_inband_stop(b):
    return pipe(b, [ESC + b'[?1z', b':q!\r'], rows=24, cols=80, snap=-1)


def deadly(b, sig):
    t = Term(b)
    t.pump(1.0)
    t.keys(b'ihello\x1b')
    t.pump(0.6)
    during = t.mode()
    os.kill(t.pid, sig)
    t.pump(1.2)
    st = t.reap()
    after = t.mode()
    txt = t.text()
    n = len(t.out)
    t.close()
    return (st, during, after, b'Caught deadly signal' in txt, b'Finished' in txt, n)


def survives(b, how):
    """Edit, do `how`, continue it if it stopped, edit again, quit."""
    t = Term(b)
    t.pump(1.0)
    t.keys(b'iAAA\x1b')
    t.pump(0.6)
    how(t)
    t.pump(1.2)
    try:
        if open('/proc/%d/stat' % t.pid).read().split(') ', 1)[1].split()[0] == 'T':
            os.kill(t.pid, signal.SIGCONT)
            t.pump(0.6)
    except Exception:
        pass
    t.keys(b'iBBB\x1b:q!\r')
    t.pump(1.0)
    st = t.reap()
    txt = t.text()
    n = len(t.out)
    t.close()
    return st, n, b'AAA' in txt, b'BBB' in txt


def p_stopcont(b):
    t = Term(b)
    t.pump(1.0)
    t.keys(b'iAAA\x1b')
    t.pump(0.6)
    n0 = len(t.out)
    os.kill(t.pid, signal.SIGSTOP)
    t.pump(0.4)
    os.kill(t.pid, signal.SIGCONT)
    t.pump(1.2)
    drawn = len(t.out) - n0
    t.keys(b'iBBB\x1b:q!\r')
    t.pump(1.0)
    st = t.reap()
    ok = b'BBB' in t.text()
    t.close()
    return st, drawn, ok


def p_pty_resize(b):
    t = Term(b)
    t.pump(1.0)
    t.keys(b':set lines? columns?\r')
    t.pump(0.8)
    setsize(t.fd, 30, 100)
    t.pump(1.2)
    t.keys(b':set lines? columns?\r')
    t.pump(0.8)
    t.keys(b':q!\r')
    t.pump(0.6)
    t.reap()
    got = [m.decode('latin-1').split() for m in
           re.findall(rb'lines=\d+\s+columns=\d+', t.text())]
    t.close()
    return [' '.join(g) for g in got]


def p_eof_on_tty2(b):
    t = Term(b, stdin_devnull=True)
    t.pump(2.5)
    st = t.reap(2.0)
    r = (st, len(t.out), b'Finished' in t.text())
    t.close()
    return r


def p_ctrl_c_redir(b):
    t = Term(b, stdout_pipe=True)
    t.pump(1.0)
    t.keys(b'\x03')
    t.pump(1.0)
    t.keys(b':q!\r')
    t.pump(0.8)
    st = t.reap()
    txt = t.text()
    r = (st, b'E492' in txt, b'press <Enter> to exit Vim' in txt)
    t.close()
    return r


def p_raw_mode(b):
    t = Term(b)
    t.pump(1.0)
    t.keys(b'ihello\x1b')
    t.pump(0.6)
    m = t.mode()
    t.keys(b':q!\r')
    t.pump(0.6)
    t.reap()
    t.close()
    return m


def p_gs_interrupt(b):
    """10gs, then CTRL-C.  The sleep mode leaves ISIG on, so the wait is cut short."""
    t = Term(b)
    t.pump(1.0)
    t.keys(b'ihello\x1b')
    t.pump(0.6)
    t.keys(b'10gs')
    t0 = time.time()
    t.pump(1.5)
    t.keys(b'\x03')
    t.pump(0.3)
    t.keys(b':q!\r')
    end = time.time() + 22
    got = None
    while time.time() < end:
        p, s = os.waitpid(t.pid, os.WNOHANG)
        if p:
            got = time.time() - t0
            break
        t.pump(0.1)
    if got is None:
        try:
            os.kill(t.pid, signal.SIGKILL)
            os.waitpid(t.pid, 0)
        except Exception:
            pass
        got = 99.0
    t.close()
    return got


JOBS = []
for tag, fn in (('resize_inband', p_resize_inband), ('trz_query', p_trz_query),
                ('trz_set', p_trz_set), ('inband_stop', p_inband_stop),
                ('sigterm', lambda b: deadly(b, signal.SIGTERM)),
                ('sighup', lambda b: deadly(b, signal.SIGHUP)),
                ('sigint_external',
                 lambda b: survives(b, lambda t: os.kill(t.pid, signal.SIGINT))),
                ('tstp_external',
                 lambda b: survives(b, lambda t: os.kill(t.pid, signal.SIGTSTP))),
                ('ctrl_z_key', lambda b: survives(b, lambda t: t.keys(b'\x1a'))),
                ('stop_cmd', lambda b: survives(b, lambda t: t.keys(b':stop\r'))),
                ('stopcont', p_stopcont), ('pty_resize', p_pty_resize),
                ('eof_on_tty2', p_eof_on_tty2), ('ctrl_c_redir', p_ctrl_c_redir),
                ('raw_mode_live', p_raw_mode), ('gs_interrupt', p_gs_interrupt)):
    JOBS.append((tag, 'old', OLD, fn))
    JOBS.append((tag, 'new', NEW, fn))
JOBS.append(('gs_interrupt', 'nosleep', NOSLEEP, p_gs_interrupt))

with concurrent.futures.ThreadPoolExecutor(max_workers=len(JOBS)) as ex:
    res = dict(zip([(j[0], j[1]) for j in JOBS],
                   ex.map(lambda j: j[3](j[2]), JOBS)))


def g(tag, side):
    return res[(tag, side)]


# ---- MUST DIFFER -----------------------------------------------------------------------
if 'columns=100' in g('resize_inband', 'old')[0] or \
        'columns=100' not in g('resize_inband', 'new')[0]:
    fail.append('resize_inband: typing `ESC [ 48;30;100 t` must leave the escape as '
                'buffer text on the input and resize the editor to 100 columns on the '
                'output.  old=%r new=%r'
                % (g('resize_inband', 'old')[0], g('resize_inband', 'new')[0]))
for tag, word in (('trz_query', 'trz?'), ('trz_set', 'trz=sigwinch')):
    o, n = g(tag, 'old')[0], g(tag, 'new')[0]
    if 'E518' in o or 'E518: Unknown option: %s' % word not in n:
        fail.append("%s: `:set %s` must be accepted on the input and E518 on the "
                    "output -- 'termresize' is the one option this phase removes.  "
                    'old=%r new=%r' % (tag, word, o, n))
if g('inband_stop', 'old')[2] == 0 or g('inband_stop', 'new')[2] != 0:
    fail.append('inband_stop: `ESC [ ? 1 z` is the private sequence the host sends for '
                'an external kill -TSTP.  On the input it is not a command and the '
                'session ends at end of input (rc 1); on the output it runs `:stop`, '
                'comes back and the following `:q!` quits cleanly (rc 0).  old rc=%s '
                'new rc=%s' % (g('inband_stop', 'old')[2], g('inband_stop', 'new')[2]))
o, n = g('eof_on_tty2', 'old'), g('eof_on_tty2', 'new')
if o[0] != 'STILL RUNNING' or o[2] or n[0] != 'exit 1' or not n[2]:
    fail.append('eof_on_tty2: with stdin at EOF and a TERMINAL on fd 2, the input '
                'reopens fd 0 from fd 2 and carries on editing, and the output prints '
                '`Vim: Finished.` and exits 1.  This is the ONE behaviour this phase '
                'changes.  old=%s new=%s' % (o, n))
o, n = g('ctrl_c_redir', 'old'), g('ctrl_c_redir', 'new')
if not o[1] or o[2] or n[1] or not n[2]:
    fail.append('ctrl_c_redir: CTRL-C in Normal mode with stdout a pipe ran '
                '`do_cmdline_cmd("qa")` on the input (E492, whim having removed :qa) '
                'and draws the message on the output, because stdout_isatty is folded '
                'to TRUE.  old=%s new=%s' % (o, n))
o, n = g('tstp_external', 'old'), g('tstp_external', 'new')
for tag, r in (('old', o), ('new', n)):
    if r[0] != 'exit 0' or not r[2] or not r[3]:
        fail.append('tstp_external (%s): the editor must survive kill -TSTP and still '
                    'be editing afterwards -- %s' % (tag, r))
if o[1] == n[1]:
    fail.append('tstp_external: the two streams are the same length (%d).  The input '
                "goes through the core's own got_tstp flag and the output through the "
                'in-band `ESC [ ? 1 z`, and the byte count is what says it took the '
                'new path' % o[1])

# ---- MUST NOT DIFFER --------------------------------------------------------------------
for tag, sig in (('sigterm', 'TERM'), ('sighup', 'HUP')):
    o, n = g(tag, 'old'), g(tag, 'new')
    for side, r in (('old', o), ('new', n)):
        if r[0] != 'exit 1':
            fail.append('%s (%s): expected `exit 1`, got %s' % (tag, side, r[0]))
        if r[1] != 'ICANON=0 ECHO=0 ISIG=0 ONLCR=0 ICRNL=0':
            fail.append('%s (%s): the editor was not in raw mode before the signal: %s'
                        % (tag, side, r[1]))
        if r[2] != 'ICANON=1 ECHO=1 ISIG=1 ONLCR=1 ICRNL=1':
            fail.append('%s (%s): THE TERMINAL WAS NOT RESTORED: %s.  This is the '
                        'reason the signal phase and the terminal phase were merged: '
                        'the host installs the core\'s `deathtrap` rather than '
                        'replacing it, so deathtrap -> preserve_exit -> '
                        'prepare_to_exit -> term_leave() still runs'
                        % (tag, side, r[2]))
        if not r[3] or not r[4]:
            fail.append('%s (%s): `Vim: Caught deadly signal %s` and `Vim: Finished.` '
                        'must both be drawn -- got %s, %s'
                        % (tag, side, sig, r[3], r[4]))
    if o[5] != n[5]:
        fail.append('%s: the stream is %d bytes on the input and %d on the output, and '
                    'the deadly path is required to be identical' % (tag, o[5], n[5]))
for tag in ('sigint_external', 'ctrl_z_key', 'stop_cmd'):
    o, n = g(tag, 'old'), g(tag, 'new')
    for side, r in (('old', o), ('new', n)):
        if r[0] != 'exit 0' or not r[2] or not r[3]:
            fail.append('%s (%s): the editor must survive and still be editing '
                        'afterwards -- %s' % (tag, side, r))
if g('raw_mode_live', 'old') != g('raw_mode_live', 'new') or \
        g('raw_mode_live', 'new') != 'ICANON=0 ECHO=0 ISIG=0 ONLCR=0 ICRNL=0':
    fail.append('raw_mode_live: the terminal while the editor is editing must be raw '
                'on both -- old=%r new=%r'
                % (g('raw_mode_live', 'old'), g('raw_mode_live', 'new')))
for side in ('old', 'new'):
    got = g('pty_resize', side)
    if got != ['lines=24 columns=80', 'lines=30 columns=100']:
        fail.append('pty_resize (%s): a 24x80 pty resized to 30x100 must be seen -- '
                    'got %s.  On the output this is the WHOLE in-band path: the host '
                    'catches SIGWINCH, its ioctl reads the new size, musl_read_input '
                    'hands the core `CSI 48;30;100;0;0t`, and handle_csi resizes'
                    % (side, got))
for side in ('old', 'new'):
    st, drawn, ok = g('stopcont', side)
    if st != 'exit 0' or not ok or drawn < 1000:
        fail.append('stopcont (%s): after kill -STOP; kill -CONT the editor must redraw '
                    'its screen and still be editing -- got %s, %d bytes drawn, '
                    'BBB=%s.  On the output that redraw is the host catching SIGCONT '
                    'with the same handler as SIGWINCH, which is why the CSI 48 arm '
                    'lost its `height != Rows` guard' % (side, st, drawn, ok))
for side in ('old', 'new'):
    if g('gs_interrupt', side) > 6.0:
        fail.append('gs_interrupt (%s): `10gs` then CTRL-C after 1.5 s must come back '
                    'in about 1.8 s and took %.2f s' % (side, g('gs_interrupt', side)))
if g('gs_interrupt', 'nosleep') < 15.0:
    fail.append('THE CONTROL RECOVERED.  This phase\'s own output with musl_delay()\'s '
                'two host_tty_set() calls deleted took %.2f s, and the whole point of '
                'the sleep mode is that WITHOUT it the interrupt character is a plain '
                'byte in the input queue and the nanosleep runs to its full ten '
                'seconds.  Two numbers agreeing prove nothing if a wrong one is not '
                'caught' % g('gs_interrupt', 'nosleep'))

if fail:
    for line in fail:
        print('  %-12s %s' % (TAG, line))
    sys.exit(1)

print('  %-12s MUST DIFFER (7): resize_inband -- `ESC[48;30;100t` is buffer text on the '
      'input and `columns=100` here; trz_query and trz_set -- `:set trz?` and `:set '
      "trz=sigwinch` are accepted on the input and E518 here; inband_stop -- `ESC[?1z` "
      'is nothing on the input and runs `:stop` here (rc %s -> %s); eof_on_tty2 -- with '
      'a terminal on fd 2 the input reopens fd 0 and keeps editing (%d B) where this '
      'prints `Vim: Finished.` and exits 1 (%d B); ctrl_c_redir -- CTRL-C with stdout a '
      'pipe was E492 and is the message; tstp_external -- %d B against %d B, the '
      'in-band path'
      % (TAG, g('inband_stop', 'old')[2], g('inband_stop', 'new')[2],
         g('eof_on_tty2', 'old')[1], g('eof_on_tty2', 'new')[1],
         g('tstp_external', 'old')[1], g('tstp_external', 'new')[1]))
print('  %-12s MUST NOT DIFFER, and these are the ones the merge was for: kill -TERM '
      'and kill -HUP both exit 1, both restore the terminal to %s, both draw `Vim: '
      'Caught deadly signal` and `Vim: Finished.`, and both streams are the same '
      'length (%d and %d bytes)'
      % ('', g('sigterm', 'new')[2], g('sigterm', 'new')[5], g('sighup', 'new')[5]))
print('  %-12s and: kill -INT survives on both (the host hands the core a 0x03 byte, '
      'where SIG_DFL would KILL it); keyboard CTRL-Z and `:stop` both come back '
      'editing; the terminal is raw while editing on both (%s); a 24x80 pty resized to '
      '30x100 is seen by both; kill -STOP/-CONT redraws %d bytes on the input and %d '
      'here'
      % ('', g('raw_mode_live', 'new'), g('stopcont', 'old')[1], g('stopcont', 'new')[1]))
print('  %-12s gs_interrupt, WITH ITS CONTROL: `10gs` then CTRL-C comes back at %.2f s '
      'on the input and %.2f s here -- and at %.2f s on this phase\'s own output with '
      "musl_delay()'s two host_tty_set() calls deleted.  That is what says the sleep "
      'mode is real: TMODE_SLEEP is not "discard input", it is the saved termios with '
      'ICANON and ECHO cleared and ISIG LEFT ON, so the interrupt character is a '
      'signal for the duration of the sleep'
      % ('', g('gs_interrupt', 'old'), g('gs_interrupt', 'new'),
         g('gs_interrupt', 'nosleep')))
PY

# tools/phaserun.sh runs tools/zerodelta.sh --phase 20 after this check, and this
# phase declares NOTHING: the corpus must not move at all.
