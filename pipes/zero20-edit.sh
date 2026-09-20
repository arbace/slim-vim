#!/bin/sh
# Zero phase 20 -- the signals and the terminal are the host's.  See ZERO-GOAL.md.
#
# Usage: pipes/zero20-edit.sh <work-dir> <state-dir>     (run from the repository root)
#
# ZERO-PLAN.md 4c's third step, and the largest of the three: `mch_get_shellsize`,
# `mch_settmode` and the signal handlers move across, "which takes ioctl, tcgetattr,
# tcsetattr, select, nanosleep and the nine signal symbols with them".  It takes none
# of them, and the phase says so rather than implying a reduction it does not make.
#
# WITHIN ONE TRANSLATION UNIT, MOVING CODE FROM THE CORE TO THE HOST FREES NOTHING.
# A symbol leaves `nm -u` when its last CALLER leaves the file, and that is the split.
# So `sigaction`, `sigemptyset`, `kill`, `ioctl`, `tcgetattr`, `tcsetattr`,
# `nanosleep` and `select` all survive this phase -- every one of them now called
# from the 240-line host block at the bottom of the file and from nowhere else.
# WHAT LEAVES IS WHAT THE PHASE DELETES: `raise sigaddset sigismember sigprocmask`,
# which were `mch_signal()`'s fifty lines of sigset() emulation and `sig_tstp`'s
# re-raise, and `close dup isatty`, which were the two dead descriptor sites and the
# three questions about terminals that nothing asks any more.  31 -> 24.
#
# THE PHASE'S VALUE IS STRUCTURAL, AND ``zhostonly`` IS THAT CLAIM AS AN
# ASSERTION: every mention of the host's vocabulary -- 43 words, from `sigaction` to
# `VMIN` -- is inside the host block, with eight named exceptions in the core that are
# the deadly-signal message and the clock.  Without that tool the strongest available
# form of "the core names none of this" is `sigaction` at 2 mentions, which says
# nothing about where.
#
# ------------------------------------------------------------------------------------
# WHAT THE HOST TELLS THE EDITOR, AND WHY IT IS IN BAND
#
# The editor had five signal handlers.  Four of them existed to tell it something:
# SIGWINCH "you were resized", SIGTSTP "you were asked to stop", SIGCONT "you were
# continued", SIGINT "the user interrupted you".  A host cannot deliver a signal to a
# core it is linked into -- there is no such thing -- so the four become BYTES the
# core reads from its input, which is the one channel that already exists.  The fifth,
# the deadly pair SIGHUP/SIGTERM, is not a message: it is the process ending, and it
# stays (below).
#
# THE WIRE FORMAT FOR THE RESIZE IS NOT OURS, AND IT WAS ALREADY IN THE FILE.
# `handle_csi()` has always parsed DEC private mode 2048's notification
# (`CSI 48 ; rows ; cols ; hpx ; wpx t`, Tim Culverhouse, 2024) -- and the arm could
# never run, because `\033[?2048$p`, the DECRQM query a terminal answers to set
# `win_resize_setting`, appears NOWHERE in slim-vim.c, whim-vim.c or zero-vim.c.  So
# the whole negotiation was dead code guarding a working parser.  This phase deletes
# the negotiation, the 'termresize' option that drove it and the two state variables,
# and makes the notification unconditional -- and the HOST writes it, from its own
# SIGWINCH handler and its own ioctl.
#
# WHY THE HOST KEEPS THE ioctl RATHER THAN RELYING ON THE TERMINAL.  Mode 2048 is
# implemented by ghostty, kitty, foot, iTerm2, contour and Bobcat, and NOT by xterm,
# tmux, GNU screen, WezTerm, Alacritty, VTE, Konsole, st, Windows Terminal, urxvt or
# Zellij -- and tmux and screen TERMINATE it, answering DECRQM with the correct "not
# recognised" and forwarding nothing.  A core that relied on the terminal would be an
# editor that never learns it was resized under tmux.  Deleting the host's
# `TIOCGWINSZ` instead would free `ioctl` and an eleventh #include and cost that,
# which is a number bought with the terminal.
#
# `\033[?1z` IS OURS AND IS IN NO SPEC, and that is said here rather than discovered.
# `first == '?' && argc == 1 && arg[0] == 1 && trail == 'z'` reaches no existing arm
# (the `?`-prefixed arms end in `c`, `y` and `u`), and `z` is a letter so the trail
# scan stops on it.  Doing real work from inside the termcode parser has precedent in
# the file: the resize arm calls `set_shellsize()`, which redraws the whole screen.
#
# THE INTERRUPT TRAVELS AS THE BYTE IT ALREADY IS.  `catch_sigint` set `got_int`
# directly; the host instead hands the core a `0x03`, which `fill_input_buf`'s own
# CTRL-C scan turns into `got_int` -- the only way `got_int` is ever set in raw mode,
# because raw mode clears ISIG.  IT IS NOT OPTIONAL: with no handler at all, SIG_DFL
# KILLS the editor, and the `10gs` probe found it -- CTRL-C during a `gs` sleep raises
# SIGINT, because the sleep mode deliberately leaves ISIG on (below).  Measured on the
# binary this phase was handed and on a build with no SIGINT handler: `kill -INT`
# mid-session leaves the first editing and kills the second with SIG2.
#
# CTRL-Z IS THE ONE THING THAT CANNOT GO IN BAND, and `musl_suspend()` is why there is
# one call out and not zero.  In raw mode ISIG is clear, so the keyboard CTRL-Z
# arrives as the byte 0x1a, reaches `nv_cmds[]`'s real `{Ctrl_Z, nv_suspend, 0, 0}`
# row, and THE CORE DECIDES to suspend.  A one-way host->core channel has no way to
# carry that decision back.  The external `kill -TSTP` is the other direction and fits
# the in-band path exactly.
#
# ------------------------------------------------------------------------------------
# THE TERMINAL: TWO OPERATIONS, NOT A MODE SETTER
#
# `settmode(tmode_T)` is nine call sites and a three-valued mode, and every site is
# attached to an OPERATION: the editor takes the terminal, gives it back, suspends,
# resumes, sleeps, or re-asserts that it still holds it.  Exposing `musl_set_raw(int)`
# would move the syscall without moving the responsibility, so `settmode()` splits at
# the one line that was ever the host's -- `mch_settmode(tmode)` -- into `term_enter()`
# and `term_leave()`, which keep the escape sequences (`t_BE`/`t_TI`, `t_CBD`/`t_TE`)
# because those are screen work.  `cur_tmode` becomes a boolean, `mch_cur_tmode` goes
# (the two were measured equal at all eleven sites), and `tmode_T` with `TMODE_SLEEP`
# goes to the sweep.
#
# `TMODE_SLEEP` IS NOT "DISCARD INPUT" AND `musl_delay`'s PARAMETER SAYS SO.  Measured
# from `mch_settmode`: the sleep mode is the SAVED termios with ICANON and ECHO
# cleared, applied TCSANOW and not TCSAFLUSH -- nothing is flushed and nothing is
# discarded.  What is different from raw mode is that ISIG is left ON, so the INTR
# character raises SIGINT and cuts the `nanosleep` short.  `10gs` then CTRL-C recovers
# in about 1.8 s on the binary this phase was handed and on this one, and NEVER
# recovers (measured to 26 s) on a build of this phase's own output with the two
# `host_tty_set` calls deleted.  The parameter is `interruptible`.
#
# NOTHING ASKS WHETHER THIS IS A TERMINAL, which is ZERO-PLAN.md 1's decision 7 --
# "the check goes entirely" -- finally kept: phases 2 and 4 left three `isatty()`
# calls alive and this takes all three.  `mch_check_win` and `stdout_isatty` go, and
# `nv_esc`'s `out_redir` folds to the terminal arm.  `musl_is_terminal()` is NOT
# written: the two questions had different subjects (fd 1 for the size, fd 0 for the
# input) and neither survives its caller, so a host call to answer a question nobody
# asks afterwards is boundary surface for nothing.
#
# THE CORE CANNOT ACQUIRE A DESCRIPTOR AT ALL ANY MORE.  `fill_input_buf`'s
# `close(0); vim_ignored = dup(2);` arm -- the core reopening its own stdin from its
# stderr when stdin hit EOF and was not a terminal -- is the core second-guessing the
# host about where input comes from, and once the host owns the terminal that is the
# host's business.  ZERO-PLAN.md 4b's invariant becomes absolute: the core is handed
# fds 0, 1 and 2 and that is the whole of it.  The behaviour that goes is real and
# probe-only: with stdin at EOF and a TERMINAL on fd 2 the old binary reopens fd 0 and
# carries on editing (2,016 bytes drawn), where this one prints `Vim: Finished.` and
# exits (168 bytes).  Zero of 253 recorded rows reach it.
#
# ------------------------------------------------------------------------------------
# WHAT STAYS IN THE CORE, AND EACH IS A DECISION
#
# `deathtrap` STAYS AND THE HOST INSTALLS IT, which is the whole reason the signal
# phase and the terminal phase were merged into one.  A host-side deadly handler that
# merely died would leave the terminal RAW -- measured on a prototype that deleted
# `deathtrap`: the process is killed by the signal, no message, tty still raw.  Keeping
# the body reachable costs nothing and keeps all of it: `deathtrap -> preserve_exit ->
# prepare_to_exit -> term_leave()` restores the tty, writes `Vim: Caught deadly signal
# TERM`, and ends through phase 19's `vim_host_exit` -> `__builtin_longjmp` -> `return
# 1`.  MEASURED identical on both binaries, to the byte: 2,241 on SIGTERM and 2,240 on
# SIGHUP, tty back to ICANON=1 ECHO=1 ISIG=1 ONLCR=1 ICRNL=1, exit 1.
#
# `vim_handle_signal` STAYS, and it is the one core mention of any host word that is
# not a message: `kill(getpid(), got_signal)`, re-raising a deadly signal that arrived
# while the editor was not reading.  Deleting it would make a deadly signal act in the
# middle of a screen update, which no recording can see.  ``zhostonly`` names
# it as an exception with that reason rather than loosening its pattern.
#
# `ui_get_shellsize()` STAYS A QUERY, and this is the design the survey got wrong.
# Making it "do I know my size?" -- a `shell_size_known` flag set by the host and by
# every notification -- BREAKS RESIZING, and the measurement is exact: at a
# `Press ENTER` prompt `set_shellsize()` does `State = MODE_SETWSIZE; return;` and
# DISCARDS the width and height it was given; `wait_return()` then calls
# `shell_resized()`, which is `set_shellsize(0, 0, FALSE)`, which learns the new size
# ONLY from `ui_get_shellsize()`'s side effect.  With the flag, a pty resized while
# the editor sits at a Press-ENTER prompt stays 24x80 for ever (measured, twice).  So
# `mch_get_shellsize()`'s body moves to the host as `musl_get_winsize(int *, int *)` --
# which is the name ZERO-PLAN.md 4c gave it -- and `ui_get_shellsize()` keeps its
# shape.  That also disposes of the `set_termname()` trap the survey spent an hour on:
# on a pipe the host's ioctl fails, `ui_get_shellsize()` returns FAIL exactly as
# before, `t_CWS` is still emitted and the recording does not move by one byte.
set -eu

work=${1:?usage: zero20-edit.sh <work-dir> <state-dir>}
state=${2:?usage: zero20-edit.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"

# The flags are read out of the boundary's makefile rather than written here a second
# time: zero's compile line is the boundary's (ZERO-GOAL.md rule 8).
cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")
cp "$f" "$state/old.c"
# shellcheck disable=SC2086
( cd "$state" && gcc $cflags $ldflags -o old old.c ) &
pid_old=$!

python3 - "$f" <<'PY'
TAG = 'host'
import re, sys
path = sys.argv[1]
t = open(path, errors='surrogateescape').read()


def die(msg):
    sys.exit('  %-12s %s' % (TAG, msg))


def say(what):
    print('  %-12s %s' % (TAG, what))


def mentions(text, name):
    return len(re.findall(r'\b%s\b' % name, text))


def blank_runs(text):
    L = text.split('\n')
    return sum(1 for i in range(1, len(L)) if L[i] == '' and L[i - 1] == '')


def sub(old, new, n=1, tag=''):
    global t
    c = t.count(old)
    if c != n:
        die('%s: `%s` occurs %d times, expected %d'
            % (tag, old.strip().split('\n')[0][:70], c, n))
    t = t.replace(old, new)


def cut(old, n=1, tag=''):
    sub(old, '', n, tag)


def delfunc(sigline, tag=''):
    """Delete a whole definition by brace matching from its name line."""
    global t
    if t.count(sigline) != 1:
        die('%s: the definition line `%s` occurs %d times, expected 1'
            % (tag, sigline.strip()[:60], t.count(sigline)))
    i = t.index(sigline)
    k = t.index('{', i)
    d = 0
    while True:
        if t[k] == '{':
            d += 1
        elif t[k] == '}':
            d -= 1
            if d == 0:
                break
        k += 1
    st = t.rindex('\n', 0, t.rindex('\n', 0, i)) + 1
    t = t[:st] + t[t.index('\n', k) + 1:]


lines_before = len(t.split('\n'))

# ---- 0. this is the file the phase was written against -------------------------------
# Counted on the INPUT, so a later phase that moved one of these fails here and not in
# the middle of a cut.
for name, want in (('mch_signal', 18), ('signal_info', 9), ('settmode', 13),
                   ('mch_settmode', 2), ('isatty', 4), ('deathtrap', 3),
                   ('win_resize_enabled', 6), ('got_tstp', 4), ('do_resize', 6)):
    if mentions(t, name) != want:
        die('the input has %d mentions of `%s`, expected %d -- this is not the tree '
            'this phase was written against' % (mentions(t, name), name, want))
if '\\033[?2048$p' in t or '2048$p' in t:
    die('the DECRQM query for mode 2048 is in the file, so the negotiation this phase '
        'deletes as dead code is not dead')
say('the input is r19: `mch_signal` 18, `settmode` 13, `isatty` 4, and NO `\\033[?2048$p` '
    'anywhere -- which is what makes the whole mode-2048 negotiation unreachable and '
    'this phase half a deletion of code that could never run')

# ---- R. the in-band notification is always recognised; the negotiation goes ----------
sub('    else if (win_resize_enabled && argc >= 3 && arg[0] == 48)\n',
    '    else if (argc >= 3 && arg[0] == 48)\n', 1, 'R1')
# DROPPING THE `height != Rows` GUARD IS LOAD-BEARING.  The host sends a notification
# on SIGCONT as well as SIGWINCH, and a continue is usually the SAME size -- so with
# the guard the screen after `kill -STOP; kill -CONT` is never redrawn.
sub('''        if (height != Rows || width != Columns)
        {
            set_shellsize(width, height, true);
        }
''', '''        set_shellsize(width, height, true);
''', 1, 'R2')
cut('''                case 2048:
                    win_resize_setting = setting;

                    term_set_win_resize(true);
                    break;
''', 1, 'R3')
sub("    else if (first == '?' && trail == 'y' && argc == 2 && (arg[0] == 2026 || arg[0] == 2048))\n",
    "    else if (first == '?' && trail == 'y' && argc == 2 && arg[0] == 2026)\n", 1, 'R4')
# THE SUBSTRING TRAP, AND IT DECIDES THE ORDER OF THE NEXT TWO CUTS.
# `    term_set_win_resize(false);` at four spaces is a SUBSTRING of the same call at
# eight, inside did_set_termresize(), so str.count() says 2.  Delete the option's
# handler first and the count is 1; the other way round deletes the wrong line.
delfunc('did_set_termresize(optset_T *args  __attribute__((unused)) )', 'R5')
cut('static char *did_set_termresize(optset_T *args);\n', 1, 'R5b')
cut('''    {"termresize", "trz", P_STRING|P_VI_DEF,
                            (char_u *)&p_trz, PV_NONE, did_set_termresize, NULL,
                            {(char_u *)"", (char_u *)0}
                              },
''', 1, 'R5c')
cut('static char_u   *p_trz;\n', 1, 'R5d')
cut('    term_set_win_resize(false);\n', 1, 'R6')
delfunc('term_set_win_resize(bool state)\n{', 'R7')
cut('static void term_set_win_resize(bool state);\n', 1, 'R7b')
cut('static int win_resize_setting = 0;\n', 1, 'R7c')
cut('static bool win_resize_enabled = false;\n', 1, 'R7d')
say("the 'termresize' option, term_set_win_resize(), win_resize_setting and "
    'win_resize_enabled are gone, and the CSI 48 arm is unconditional and always a '
    'full redraw')

# ---- W. no SIGWINCH in the core ------------------------------------------------------
delfunc('sig_winch  (int sigarg  __attribute__((unused)) ) ', 'W1')
cut('static void sig_winch  (int) ;\n', 1, 'W1b')
delfunc('set_sigwinch_handler(void)\n{', 'W2')
delfunc('resize_func(int check_only)', 'W3')
# inchar_loop TESTS resize_func for NULL, so passing NULL is the interface and not a
# shortcut.  The resize arrives as bytes; there is nothing to call.
sub('    return inchar_loop(buf, maxlen, wtime, tb_change_cnt, WaitForChar, resize_func);\n',
    '    return inchar_loop(buf, maxlen, wtime, tb_change_cnt, WaitForChar, NULL);\n',
    1, 'W4')
delfunc('handle_resize(void)\n{', 'W5')
cut('static void handle_resize(void);\n', 1, 'W5b')
cut('static volatile sig_atomic_t do_resize = FALSE;\n', 1, 'W6')
cut('''            if (do_resize)
            {
                handle_resize();
            }

''', 1, 'W7')
cut('    {SIGWINCH,      "WINCH",    FALSE},\n', 1, 'W8')
cut('    mch_signal(SIGWINCH, sig_winch);\n\n', 1, 'W9')

# ---- I. the core asks the host for its size, not the kernel --------------------------
delfunc('mch_get_shellsize(void)\n{', 'I1')
# THE WHOLE FOUR-LINE HEAD, and not `retval = mch_get_shellsize();` alone next to a
# `retval = OK;`: `    retval = OK;` occurs in TEN functions in this file and a
# textual replacement of it breaks the editor at the first `:`.
sub('''    int     retval;

        retval = mch_get_shellsize();
''', '''    int     retval;
    int     hrows = 0;
    int     hcols = 0;

        retval = FAIL;
        if (musl_get_winsize(&hrows, &hcols) == OK)
        {
            Rows = hrows;
            Columns = hcols;
            limit_screen_size();
            retval = OK;
        }
''', 1, 'I2')

# ---- S. the core installs no handler -- but deathtrap stays --------------------------
delfunc('catch_sigint  (int sigarg  __attribute__((unused)) ) \n{', 'S1')
cut('static void catch_sigint  (int) ;\n', 1, 'S1b')
delfunc('sig_tstp  (int sigarg  __attribute__((unused)) ) \n{', 'S2')
cut('static void sig_tstp  (int) ;\n', 1, 'S2b')
delfunc('sigcont_handler  (int sigarg  __attribute__((unused)) ) \n{', 'S3')
# `static void sigcont_handler  (int) ;` IS IN THE FILE TWICE, on consecutive lines --
# a whim artefact.  An assertion of 1 fails on a correct phase.
cut('static void sigcont_handler  (int) ;\n', 2, 'S3b')
cut('static volatile sig_atomic_t sigcont_received;\n', 1, 'S3c')
# signal_info[] KEEPS EXACTLY THE TWO DEADLY ROWS AND LOSES ITS `deadly` FIELD, and
# the field goes HERE rather than in the sweep.  It was read only by catch_signals(),
# which this phase deletes -- so tools/deadfields.py finds it and removes the member,
# and leaves the three initialisers behind: `warning: excess elements in struct
# initializer`, three times, which tools/phasecheck.sh then fails on.  A field the
# edit knows is dead is the edit's to take, with its data.
sub("""static struct signalinfo
{
    int     sig;
    char    *name;
    char    deadly;
} signal_info[] =
{
    {SIGHUP,        "HUP",      TRUE},
    {SIGTERM,       "TERM",     TRUE},
    {SIGINT,        "INT",      FALSE},
    {SIGTSTP,       "TSTP",     FALSE},
    {-1,            "Unknown!", FALSE}
};
""", """static struct signalinfo
{
    int     sig;
    char    *name;
} signal_info[] =
{
    {SIGHUP,        "HUP"},
    {SIGTERM,       "TERM"},
    {-1,            "Unknown!"}
};
""", 1, 'S4')
delfunc('mch_signal(int sig, sighandler_T func)\n{', 'S5')
cut('static sighandler_T mch_signal(int sig, sighandler_T func);\n', 1, 'S5b')
delfunc('catch_signals(void (*func_deadly)(int), void (*func_other)(int))\n{', 'S6')
cut('static void catch_signals(void (*func_deadly)(int), void (*func_other)(int));\n',
    1, 'S6b')
delfunc('\nset_signals(void)\n{', 'S7')
cut('static void set_signals(void);\n', 1, 'S7b')
delfunc('reset_signals(void)\n{', 'S8')
cut('static void reset_signals(void);\n', 1, 'S8b')
cut('    reset_signals();\n', 1, 'S8c')
delfunc('catch_int_signal(void)\n{', 'S9')
cut('static void catch_int_signal(void);\n', 1, 'S9b')
sub('''    ignore_sigtstp = SIG_IGN == mch_signal(SIGTSTP, SIG_ERR);
    set_signals();
''', '''    musl_host_init();
''', 1, 'S10')
# prepare_to_exit's `mch_signal(SIGHUP, SIG_IGN)` guarded against a second SIGHUP
# during the exit path; deathtrap's own `entered == 2` test is what really guards it,
# and is measured to still do so (the deadly probes are byte-identical either side).
cut('    mch_signal(SIGHUP, SIG_IGN);\n', 1, 'S11')
cut('''            if (got_tstp && !in_mch_suspend)
            {
                exarg_T ea;

                ea.forceit = TRUE;
                ex_stop(&ea);
                got_tstp = FALSE;
            }

''', 1, 'S12')
cut('static volatile sig_atomic_t got_tstp = FALSE;\n', 1, 'S12b')
# `ignore_sigtstp` asked the kernel whether the shell that started us ignores SIGTSTP.
# That is the host's question and musl_suspend() is where it is answered.
cut('''    if (ignore_sigtstp)
    {
        return;
    }

''', 1, 'S13')
cut('static int ignore_sigtstp = FALSE;\n', 1, 'S13b')
say('mch_signal(), signal_info[]\'s three non-deadly rows, catch_signals(), '
    'set_signals(), reset_signals(), catch_int_signal(), sig_winch, sig_tstp, '
    'catch_sigint and sigcont_handler are gone.  deathtrap and vim_handle_signal STAY '
    'and the host installs deathtrap for SIGHUP and SIGTERM -- which is what keeps the '
    'terminal restored and the message printed when the editor is killed')

# ---- Y. mch_suspend asks the host ----------------------------------------------------
# Nine steps become four.  `in_mch_suspend` existed only so the core's own sig_tstp
# could tell "my stop" from "someone else's", `sigcont_received` only to drive a
# four-iteration mch_delay back-off, and BOTH questions vanish: musl_suspend()
# RETURNING is the handshake.
sub("""    static void
mch_suspend(void)
{
    in_mch_suspend = TRUE;

    out_flush();
    settmode(TMODE_COOK);
    out_flush();

    sigcont_received = FALSE;

    kill(0, SIGTSTP);

    {
        long wait_time;

        for (wait_time = 0; !sigcont_received && wait_time <= 3L; wait_time++)
        {
            mch_delay(wait_time, 0);
        }
    }
    in_mch_suspend = FALSE;

    after_sigcont();
}
""", """    static void
mch_suspend(void)
{
    out_flush();
    term_leave();
    out_flush();

    musl_suspend();

    term_enter();
}
""", 1, 'Y1')
delfunc('after_sigcont(void)\n{', 'Y2')
cut('static volatile sig_atomic_t in_mch_suspend = FALSE;\n', 1, 'Y3')

# ---- M. settmode() becomes two operations -------------------------------------------
sub('static void settmode(tmode_T tmode);\n',
    'static void term_enter(void);\n'
    'static void term_leave(void);\n'
    'static void musl_host_init(void);\n'
    'static int musl_get_winsize(int *rows, int *cols);\n'
    'static void musl_term_start(void);\n'
    'static void musl_term_stop(void);\n'
    'static int musl_tty_keys(int fd, int *bs, int *intr, int *cr, int *nlcr);\n'
    'static void musl_delay(long ms, int interruptible);\n'
    'static int musl_wait_for_input(long ms);\n'
    'static int musl_read_input(char *buf, int len);\n'
    'static void musl_suspend(void);\n', 1, 'M1')
sub('static tmode_T  cur_tmode  = TMODE_COOK ;',
    'static int      term_entered = FALSE;', 1, 'M2')
sub("""    static void
settmode(tmode_T tmode)
{
    if (!full_screen)
    {
        return;
    }

    if (tmode != cur_tmode)
    {
        if (tmode != TMODE_RAW)
        {
        }

        if (termcap_active && tmode != TMODE_SLEEP && cur_tmode != TMODE_SLEEP)
        {
              ;

            if (tmode != TMODE_RAW)
            {
                out_str( ( term_strings[(int)(KS_CBD)] ) );
                out_str_t_TE();
            }
            else
            {
                out_str_t_BE();
                out_str_t_TI();
            }
        }
        out_flush();
        mch_settmode(tmode);
        cur_tmode = tmode;
        if (tmode == TMODE_RAW)
        {
        }
        out_flush();
    }
}""", """    static void
term_enter(void)
{
    if (!full_screen || term_entered)
    {
        return;
    }

    if (termcap_active)
    {
        out_str_t_BE();
        out_str_t_TI();
    }
    out_flush();
    musl_term_start();
    term_entered = TRUE;
    out_flush();
}

    static void
term_leave(void)
{
    if (!full_screen || !term_entered)
    {
        return;
    }

    if (termcap_active)
    {
        out_str( ( term_strings[(int)(KS_CBD)] ) );
        out_str_t_TE();
    }
    out_flush();
    musl_term_stop();
    term_entered = FALSE;
    out_flush();
}""", 1, 'M3')
# EVERY CALL SITE IS TAKEN WITH A NEIGHBOURING LINE, because `    settmode(TMODE_RAW);`
# occurs three times and `    settmode(TMODE_COOK);` twice.
sub('    settmode(TMODE_RAW);\n\n    init_history();',
    '    term_enter();\n\n    init_history();', 1, 'M4')
sub('    if (exiting)\n    {\n        settmode(TMODE_RAW);\n    }',
    '    if (exiting)\n    {\n        term_enter();\n    }', 1, 'M5')
# KEEP prepare_to_exit's full_screen DANCE EXACTLY: settmode() early-returned on
# !full_screen and so does term_leave(), and this is what restores the terminal after
# a deadly signal.
sub('            full_screen = TRUE;\n            settmode(TMODE_COOK);\n            full_screen = was_full_screen;',
    '            full_screen = TRUE;\n            term_leave();\n            full_screen = was_full_screen;',
    1, 'M6')
sub('    {\n        settmode(TMODE_COOK);\n\n        if (swapping_screen() && !newline_on_exit)',
    '    {\n        term_leave();\n\n        if (swapping_screen() && !newline_on_exit)',
    1, 'M7')
sub('    settmode(TMODE_RAW);\n\n    if (need_wait_return || msg_didany)',
    '    term_enter();\n\n    if (need_wait_return || msg_didany)', 1, 'M8')
sub('    TMODE_COOK,\n    TMODE_SLEEP,\n    TMODE_RAW} tmode_T;',
    '    TMODE_COOK,\n    TMODE_RAW} tmode_T;', 1, 'M9')

# ---- D. the delay is an operation, not a mode change ---------------------------------
# ONE out_flush() WHERE THERE WERE UP TO FOUR, and it is exact: nothing is written
# between the two termios changes, so three of today's four flush nothing.
# MCH_DELAY_SETTMODE has no caller, so the policy folds to `msec > 500` inside the host.
sub("""    tmode_T     old_tmode;
    int         call_settmode;

    if (flags & MCH_DELAY_IGNOREINPUT)
    {
        call_settmode = mch_cur_tmode == TMODE_RAW
                               && (msec > 500 || (flags & MCH_DELAY_SETTMODE));
        if (call_settmode)
        {
            old_tmode = mch_cur_tmode;
            settmode(TMODE_SLEEP);
        }

        {
            struct timespec ts;

            ts.tv_sec = msec / 1000;
            ts.tv_nsec = (msec % 1000) * 1000000;
            (void)nanosleep(&ts, NULL);
        }

        if (call_settmode)
        {
            settmode(old_tmode);
        }
    }
    else
    {
        WaitForChar(msec, NULL, FALSE);
    }""", """    if (flags & MCH_DELAY_IGNOREINPUT)
    {
        out_flush();
        musl_delay(msec, TRUE);
    }
    else
    {
        WaitForChar(msec, NULL, FALSE);
    }""", 1, 'D1')

# ---- K. the termios queries are the host's ------------------------------------------
# get_tty_fd() is a STUB that returns its argument, so mch_tcgetattr()'s `if (tty_fd <
# 0)` and `if (tty_fd != fd) close(tty_fd);` are both unreachable -- reachable code
# with a constant test, which no warning sees.  That dead close() is one of the two
# this phase frees.
i = t.index('    static int\nget_tty_fd(int fd)')
j = t.index('    static void\nget_stty(void)')
t = t[:i] + t[j:]
sub("""    struct termios keys;

    if (mch_tcgetattr(fd, &keys) != -1)
    {
        info->backspace = keys.c_cc[VERASE];
        info->interrupt = keys.c_cc[VINTR];
        if (keys.c_iflag & ICRNL)
        {
            info->enter = NL;
        }
        else
        {
            info->enter = CAR;
        }
        if (keys.c_oflag & ONLCR)
        {
            info->nl_does_cr = TRUE;
        }
        else
        {
            info->nl_does_cr = FALSE;
        }
        return OK;
    }
    return FAIL;""", """    int bs = 0;
    int intr = 0;
    int cr = 0;
    int nlcr = 0;

    if (musl_tty_keys(fd, &bs, &intr, &cr, &nlcr) == OK)
    {
        info->backspace = (char_u)bs;
        info->interrupt = (char_u)intr;
        info->enter = cr ? NL : CAR;
        info->nl_does_cr = nlcr ? TRUE : FALSE;
        return OK;
    }
    return FAIL;""", 1, 'K2')
sub('if ((mch_cur_tmode == TMODE_RAW || force) && RealWaitForChar(read_cmd_fd, 0L, NULL, NULL))',
    'if ((term_entered || force) && RealWaitForChar(read_cmd_fd, 0L, NULL, NULL))',
    1, 'K3')
cut('static tmode_T mch_cur_tmode = TMODE_COOK;\n', 1, 'K4')

# ---- V. the wait is the host's, and it has TWO answers -------------------------------
# `*interrupted` is WRITE-ONLY through three functions: RealWaitForChar writes it,
# WaitForChar passes it on, inchar_loop declares it and passes &interrupted and NEVER
# READS IT -- and no warning fires, because taking a variable's address counts as a
# use.  That is the second time this phase has had to know that
# -Wunused-but-set-variable does not reach an address-taken or file-scope object; the
# other is `did_read_something` below.  So the whole efds set goes with it and
# musl_wait_for_input answers 1 ready / 0 timed out.  The EINTR retry does not
# disappear -- it moves INSIDE the host, which is also where the pending flag is
# checked on both sides of the select: only after an EINTR and a signal arriving
# outside the select is lost until the next keystroke; only before it and one arriving
# during it is lost until it returns.
i = t.index('RealWaitForChar(int fd, long msec, int *check_for_gpm')
j = t.index('    static int\nno_Magic(int x)')
t = t[:i] + ('RealWaitForChar(int fd  __attribute__((unused)) , long msec, int '
             '*check_for_gpm  __attribute__((unused)) , int *interrupted  '
             '__attribute__((unused)) )\n{\n    return musl_wait_for_input(msec);\n}'
             '\n\n') + t[j:]

# ---- T. nothing asks whether this is a terminal --------------------------------------
delfunc('mch_check_win(int argc  __attribute__((unused)) , char **argv  __attribute__((unused)) )',
        'T1')
cut('    stdout_isatty = (mch_check_win(paramp->argc, paramp->argv) != FAIL);\n\n',
    1, 'T2')
cut('static int      stdout_isatty  = TRUE ;\n', 1, 'T3')
# BOTH out_redir ARMS GO TOGETHER: folding only one leaves an `if (out_redir)` with no
# definition.
cut('            int out_redir = !stdout_isatty;\n\n', 1, 'T4')
sub("""                if (out_redir)
                {
                     fprintf(stderr, "%s", (ms)) ;
                }
                else
                {
                    msg(ms);
                }
""", """                msg(ms);
""", 1, 'T5')
sub("""                if (out_redir)
                {
                    got_int = FALSE;
                    do_cmdline_cmd((char_u *)"qa");
                }
                else
                {
                    msg(_("Type  :qa  and press <Enter> to exit Vim"));
                }
""", """                msg(_("Type  :qa  and press <Enter> to exit Vim"));
""", 1, 'T6')

# ---- F. the core cannot acquire a descriptor -----------------------------------------
cut("""        if (!did_read_something && !isatty(read_cmd_fd) && read_cmd_fd == 0)
        {
            int m = cur_tmode;

            settmode(TMODE_COOK);
            close(0);
            vim_ignored = dup(2);
            settmode(m);
        }
""", 1, 'F1')
# BY HAND, because removing the arm leaves `did_read_something` set and never read and
# tools/deadsweep.py does not act on -Wunused-but-set-variable (CLAUDE.md).
cut('    static int  did_read_something = FALSE;\n', 1, 'F2')
cut("""    if (len > 0)
    {
        did_read_something = TRUE;
    }
""", 1, 'F3')

# ---- H. the core reads through the host, and the host block --------------------------
sub('        len = read(read_cmd_fd, (char *)inbuf + inbufcount, readlen);\n',
    '        len = musl_read_input((char *)inbuf + inbufcount, (int)readlen);\n',
    1, 'H1')
sub('    else if (argc >= 3 && arg[0] == 48)\n',
    """    else if (first == '?' && argc == 1 && arg[0] == 1 && trail == 'z')
    {
        *slen = csi_len;
        key_name[0] = (int)KS_EXTRA;
        key_name[1] = (int)KE_IGNORE;
        do_cmdline_cmd((char_u *)"stop");
    }

    else if (argc >= 3 && arg[0] == 48)\n""", 1, 'H2')

HOST = '''static volatile sig_atomic_t host_winch_pending = FALSE;
static volatile sig_atomic_t host_tstp_pending = FALSE;
static volatile sig_atomic_t host_int_pending = FALSE;
static struct termios host_tty_saved;
static int host_tty_valid = FALSE;
static int host_tty_raw = FALSE;

    static void
host_catch(int sig, void (*f)(int))
{
    struct sigaction sa;

    sa.sa_handler = f;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = 0;
    sigaction(sig, &sa, NULL);
}

    static void
host_on_winch(int sigarg  __attribute__((unused)) )
{
    host_winch_pending = TRUE;
}

    static void
host_on_tstp(int sigarg  __attribute__((unused)) )
{
    host_tstp_pending = TRUE;
}

    static void
host_on_int(int sigarg  __attribute__((unused)) )
{
    host_int_pending = TRUE;
}

    static void
host_tty_set(int raw, int sleep)
{
    struct termios tnew;
    int n = 10;

    if (!host_tty_valid)
    {
        if (tcgetattr(0, &host_tty_saved) == -1)
        {
            return;
        }
        host_tty_valid = TRUE;
    }
    tnew = host_tty_saved;
    if (raw)
    {
        tnew.c_iflag &= ~(ICRNL | IXON);
        tnew.c_lflag &= ~(ICANON | ECHO | ISIG | ECHOE | IEXTEN);
        tnew.c_oflag &= ~(ONLCR | XTABS);
        tnew.c_cc[VMIN] = 1;
        tnew.c_cc[VTIME] = 0;
    }
    else if (sleep)
    {
        tnew.c_lflag &= ~(ICANON | ECHO);
        tnew.c_cc[VMIN] = 1;
        tnew.c_cc[VTIME] = 0;
    }
    while (tcsetattr(0, TCSANOW, &tnew) == -1 && errno == EINTR && n > 0)
    {
        --n;
    }
}

    static void
musl_host_init(void)
{
    host_catch(SIGHUP, deathtrap);
    host_catch(SIGTERM, deathtrap);
    host_catch(SIGWINCH, host_on_winch);
    host_catch(SIGCONT, host_on_winch);
    host_catch(SIGTSTP, host_on_tstp);
    host_catch(SIGINT, host_on_int);
    host_catch(SIGPIPE, SIG_IGN);
    host_catch(SIGALRM, SIG_IGN);
}

    static int
musl_get_winsize(int *rows, int *cols)
{
    struct winsize ws;

    if (ioctl(1, TIOCGWINSZ, &ws) != 0)
    {
        return FAIL;
    }
    if (ws.ws_row <= 0 || ws.ws_col <= 0)
    {
        return FAIL;
    }
    *rows = ws.ws_row;
    *cols = ws.ws_col;
    return OK;
}

    static void
musl_term_start(void)
{
    host_tty_raw = TRUE;
    host_tty_set(TRUE, FALSE);
}

    static void
musl_term_stop(void)
{
    host_tty_raw = FALSE;
    host_tty_set(FALSE, FALSE);
}

    static int
musl_tty_keys(int fd, int *bs, int *intr, int *cr, int *nlcr)
{
    struct termios keys;

    if (tcgetattr(fd, &keys) == -1)
    {
        return FAIL;
    }
    *bs = (int)keys.c_cc[VERASE];
    *intr = (int)keys.c_cc[VINTR];
    *cr = (keys.c_iflag & ICRNL) != 0;
    *nlcr = (keys.c_oflag & ONLCR) != 0;
    return OK;
}

    static void
musl_delay(long ms, int interruptible)
{
    struct timespec ts;
    int relax = interruptible && host_tty_raw && ms > 500;

    if (relax)
    {
        host_tty_set(FALSE, TRUE);
    }
    ts.tv_sec = ms / 1000;
    ts.tv_nsec = (ms % 1000) * 1000000;
    (void)nanosleep(&ts, NULL);
    if (relax)
    {
        host_tty_set(TRUE, FALSE);
    }
}

    static int
musl_wait_for_input(long ms)
{
    struct timeval tv;
    struct timeval *tvp;
    fd_set rfds;
    int ret;

    if (ms >= 0)
    {
        tv.tv_sec = ms / 1000;
        tv.tv_usec = (ms % 1000) * 1000;
        tvp = &tv;
    }
    else
    {
        tvp = NULL;
    }
    for (;;)
    {
        if (host_winch_pending || host_tstp_pending || host_int_pending)
        {
            return 1;
        }
        FD_ZERO(&rfds);
        FD_SET(0, &rfds);
        ret = select(1, &rfds, NULL, NULL, tvp);
        if (ret == -1 && errno == EINTR)
        {
            continue;
        }
        return ret > 0 && FD_ISSET(0, &rfds);
    }
}

    static int
musl_read_input(char *buf, int len)
{
    if (host_int_pending)
    {
        host_int_pending = FALSE;
        if (len >= 1)
        {
            buf[0] = 3;
            return 1;
        }
    }
    if (host_winch_pending)
    {
        int rows = 0;
        int cols = 0;

        host_winch_pending = FALSE;
        if (musl_get_winsize(&rows, &cols) == OK && len >= 32)
        {
            return vim_snprintf(buf, (size_t)len, "\\033[48;%d;%d;0;0t", rows, cols);
        }
    }
    if (host_tstp_pending)
    {
        host_tstp_pending = FALSE;
        if (len >= 5)
        {
            musl_memcpy(buf, "\\033[?1z", 5);
            return 5;
        }
    }
    return (int)read(0, buf, (size_t)len);
}

    static void
musl_suspend(void)
{
    host_catch(SIGTSTP, SIG_DFL);
    kill(0, SIGTSTP);
    host_catch(SIGTSTP, host_on_tstp);
}

'''
# The block goes INSIDE the launcher region phase 18 created and phase 19 filled --
# immediately above `host_jump` -- because that region is what becomes the second file
# at the split, and main() stays the last thing in the file (CLAUDE.md).
sub('\nstatic void *host_jump[5];\nstatic int host_code;\n',
    '\n' + HOST + 'static void *host_jump[5];\nstatic int host_code;\n', 1, 'H3')

# ---- what the file is now ------------------------------------------------------------
GONE = ('mch_signal set_signals reset_signals catch_signals catch_int_signal '
        'catch_sigint sig_tstp sigcont_handler sigcont_received after_sigcont '
        'in_mch_suspend ignore_sigtstp got_tstp sig_winch set_sigwinch_handler '
        'handle_resize do_resize mch_get_shellsize win_resize_setting '
        'win_resize_enabled term_set_win_resize did_set_termresize p_trz '
        'settmode mch_settmode mch_tcgetattr get_tty_fd mch_cur_tmode cur_tmode '
        'mch_check_win stdout_isatty did_read_something isatty out_redir').split()
left = [n for n in GONE if mentions(t, n)]
if left:
    die('these names should be at 0 mentions and are not: %s' % ' '.join(left))
for name, want, why in (
        ('resize_func', 6, "inchar_loop's PARAMETER, which stays: the prototype, the "
                           'definition and the three uses inside it.  The core passes '
                           'NULL, and inchar_loop tests for it, so this is the '
                           'interface and not a leftover'),
        ('deathtrap', 4, 'a prototype, the definition, and the TWO installations in '
                         'musl_host_init() -- the host installs the core\'s handler '
                         'for SIGHUP and SIGTERM rather than replacing it, and that is '
                         'what keeps the terminal restored on a deadly signal'),
        ('vim_handle_signal', 5, 'a prototype, the definition, deathtrap\'s call and '
                                 'the two in ui_inchar -- untouched'),
        ('signal_info', 4, 'the struct tag, the array, and deathtrap\'s two reads.  '
                           'Its five rows are two'),
        ('term_enter', 6, 'a prototype, the definition and four call sites'),
        ('term_leave', 5, 'a prototype, the definition and three call sites'),
        ('musl_host_init', 3, 'its prototype, its definition and the one call, from '
                              'mch_init()'),
        ('musl_suspend', 3, 'its prototype, its definition and mch_suspend()\'s call'),
        ('musl_wait_for_input', 3, 'its prototype, its definition and '
                                   'RealWaitForChar()\'s one call'),
        ('musl_read_input', 3, 'its prototype, its definition and fill_input_buf()\'s '
                               'one call'),
        ('musl_get_winsize', 4, 'its prototype, its definition, ui_get_shellsize()\'s '
                                'call and musl_read_input()\'s'),
        ('musl_delay', 3, 'its prototype, its definition and mch_delay()\'s one call'),
        ('musl_tty_keys', 3, 'its prototype, its definition and get_tty_info()\'s one '
                             'call'),
        ('host_catch', 11, 'its definition, eight installations in musl_host_init() '
                           'and two in musl_suspend()'),
        ('ioctl', 2, 'the #include and the host\'s one TIOCGWINSZ'),
        ('select', 1, 'the host\'s one select(); there is no #include for it -- it '
                      'arrives transitively through <sys/param.h> (ZERO-PLAN.md 4c)'),
):
    if mentions(t, name) != want:
        die('`%s` has %d mentions, expected %d -- %s' % (name, mentions(t, name), want, why))
if len([l for l in t.split('\n') if l.startswith('#')]) != 12:
    die('the twelve #include directives moved, and this phase adds and removes none')
if blank_runs(t) == 0:
    die('the edit left no run of two blank lines at all, which means the deletions did '
        'not happen where they were expected -- the sweep\'s canon.sh is what takes '
        'them out, and the check asserts 0 AFTER the sweep')

open(path, 'w', errors='surrogateescape').write(t)
say('%d -> %d lines.  The core installs no handler, sets no terminal mode, runs no '
    'select and asks the kernel nothing about a window; the host block is %d lines at '
    'the bottom, inside the launcher region'
    % (lines_before, len(t.split('\n')), HOST.count('\n')))
PY

# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  host         the input binary did not build with '$cflags' '$ldflags'"; exit 1; }
echo "  host         the input is $state/old, $(stat -c%s "$state/old") bytes, beside the source it was built from -- every probe in the check is a PAIR and this is the left-hand side"

# tools/phaserun.sh sweeps next, then runs pipes/zero20-check.sh.
