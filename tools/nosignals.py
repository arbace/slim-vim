r"""Five signals, not twenty-one.

Usage:
    python3 tools/nosignals.py <file>

`signal_info[]` has twenty-one entries and five handlers.  Reviewed one at a
time, four earn their keep and the rest do not.

WHAT STAYS, and why:

  * **SIGWINCH** -- `sig_winch()` sets `do_resize`, read in nine places.  Without
    it the editor never learns the terminal changed size.
  * **SIGINT** -- `catch_sigint()` sets `got_int`, read in **222 places**.  That
    number is the argument: `got_int` is how every long operation is
    interruptible.  Drop the handler and CTRL-C reverts to its default action,
    which kills the process and loses the buffer -- turning "stop that" into
    "lose your work".
  * **SIGTSTP** -- CTRL-Z and `:suspend`, through `sig_tstp()` and `got_tstp`.
    It is the only caller of `raise`.
  * **SIGHUP and SIGTERM**, reaching `deathtrap()`.  Its historical job was
    preserving files and it cannot do that any more -- Phase 21 emptied
    `ml_sync_all()` and Phase 24 removed `preserve_exit()`'s loop.  What it
    still does is the reason to keep it: `prepare_to_exit()` runs
    `settmode(TMODE_COOK)` and `stoptermcap()`, so a killed editor **puts the
    terminal back**.  Without that the user's shell is left in raw mode with no
    echo and they have to type `reset` blind.  A wedged terminal is a worse
    failure than a crash.

WHAT GOES, sixteen entries and three handlers:

  * `SIGPWR` -> `catch_sigpwr()`, which calls `ml_sync_all()` -- **an empty
    function** since Phase 21.  A handler installed to do nothing.
  * `SIGUSR1` -> `catch_sigusr1()`, which sets `got_sigusr1`, **which nothing
    reads**.  It is assigned and never examined, so `-Wunused-variable` does not
    fire and the sweep would never find it.
  * `SIGQUIT`, `SIGILL`, `SIGTRAP`, `SIGABRT`, `SIGFPE`, `SIGBUS`, `SIGSEGV`,
    `SIGSYS`, `SIGALRM`, `SIGVTALRM`, `SIGPROF`, `SIGXCPU`, `SIGXFSZ`,
    `SIGUSR2`, `SIGPIPE` -- there is no `fork` and no pipe since Phase 8, and
    the rest describe conditions with nobody left to report them to.
  * `sigaltstack` and its stack, which existed so a SIGSEGV caused by stack
    overflow could still run a handler -- and SEGV no longer reaches one.
    `sysconf` goes with it: `_SC_SIGSTKSZ` was its last caller, the other having
    gone with `mch_total_mem()` in Phase 21.
  * `may_core_dump()`, which re-raises to produce a core there is nobody to read.

THE COST, stated because it is real: **a crash no longer restores the
terminal.**  SIGSEGV and SIGBUS take their default action, so a segfault leaves
the tty raw exactly as it would for any other program.  That was decided
deliberately -- the alternative is keeping a handler for conditions this editor
should not have, to tidy up after a bug that should not exist.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cutil

TABLE = '''{
    {SIGHUP,        "HUP",      TRUE},
    {SIGTERM,       "TERM",     TRUE},
    {SIGINT,        "INT",      FALSE},
    {SIGWINCH,      "WINCH",    FALSE},
    {SIGTSTP,       "TSTP",     FALSE},
    {-1,            "Unknown!", FALSE}
}'''

KEEP = ('SIGHUP', 'SIGTERM', 'SIGINT', 'SIGWINCH', 'SIGTSTP')


def cut(text, pattern, what, count=1, flags=re.M):
    text, n = re.subn(pattern, '', text, count=count, flags=flags)
    if n != count:
        sys.exit('nosignals: %s -- expected %d, matched %d' % (what, count, n))
    return text


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    text = path.read_text(errors='surrogateescape')

    # --- the table ----------------------------------------------------------
    b = cutil.blank(text)
    k = text.index('} signal_info[] =')
    o = b.index('{', k + 10)
    c = cutil.match(text, o, b)
    was = len(re.findall(r'\{SIG', text[o:c]))
    text = text[:o] + TABLE + text[c + 1:]
    print('  nosignals    signal_info: %d entries -> %d' % (was, len(KEEP)))

    # --- the three handlers nothing needs -----------------------------------
    for name in ('catch_sigusr1', 'catch_sigpwr', 'may_core_dump',
                 'init_signal_stack', 'get_signal_stack_size'):
        text, ok = cutil.delete_definition(text, name)
        if not ok:
            sys.exit('nosignals: %s is not defined at file scope' % name)
    for pat, what, cnt in (
            (r'^[ \t]*mch_signal\(SIGUSR1, catch_sigusr1\);\n', 'the SIGUSR1 install', 1),
            (r'^[ \t]*mch_signal\(SIGPWR, catch_sigpwr\);\n', 'the SIGPWR install', 1),
            (r'^[ \t]*may_core_dump\(\);\n', 'the may_core_dump calls', 2),
            (r'^[ \t]*signal_stack = alloc\(get_signal_stack_size\(\)\);\n',
             'the signal stack', 1),
            (r'^[ \t]*init_signal_stack\(\);\n', 'its install', 1),
            (r'^static char \*signal_stack;\n', 'signal_stack', 1),
            (r'^static stack_t sigstk;\n', 'sigstk', 1),
            (r'^static volatile sig_atomic_t got_sigusr1  = FALSE ;\n', 'got_sigusr1', 1)):
        text = cut(text, pat, what, count=cnt)
    print('  nosignals    SIGPWR, whose handler called an empty function; '
          'SIGUSR1, whose flag nothing reads')

    # --- the alternate stack, which only a SEGV handler wanted --------------
    text = text.replace('            sa.sa_flags = SA_ONSTACK;\n',
                        '            sa.sa_flags = 0;\n', 1)
    print('  nosignals    the alternate signal stack: sigaltstack, sysconf')

    # --- and the test for a signal that can no longer arrive ----------------
    text = cut(text,
               r'[ \t]*if \(sig != SIGPWR\)\n[ \t]*\{\n'
               r'[ \t]*got_int = TRUE;\n[ \t]*\}\n',
               'the SIGPWR test')
    text = text.replace('                             got_signal = sig;\n',
                        '                             got_signal = sig;\n'
                        '                             got_int = TRUE;\n', 1)
    print('  nosignals    the test for a signal that can no longer arrive')

    # --- and deathtrap's own tests, for signals that can no longer reach it --
    # `in_mch_delay && sigarg == SIGQUIT` and the early return for
    # HUP/QUIT/TERM/PWR/USR1/USR2 were written when all six could arrive here.
    # Two can.  Left alone they would be a lie in the one function whose
    # remaining job is to be trustworthy.
    text = cutil.drop_if(
        text, r'^[ \t]*if \(in_mch_delay && sigarg == SIGQUIT\)$', flags=re.M)
    text, n = re.subn(
        r'\(0 \|\| sigarg == SIGHUP \|\| sigarg == SIGQUIT \|\| sigarg == SIGTERM'
        r' \|\| sigarg == SIGPWR \|\| sigarg == SIGUSR1 \|\| sigarg == SIGUSR2\)',
        '(sigarg == SIGHUP || sigarg == SIGTERM)', text, count=1)
    if n != 1:
        sys.exit("nosignals: deathtrap's early-return test is not where this expects")
    print("  nosignals    deathtrap stops testing for signals it cannot be sent")

    # --- and the one line that makes keeping SIGHUP and SIGTERM worth it ----
    # THE CLAIM WAS FALSE WHEN THIS PHASE WAS WRITTEN.  `prepare_to_exit()`
    # calls `settmode(TMODE_COOK)` to put the terminal back, and settmode opens
    # with `if (!full_screen) return;` -- while `deathtrap()` sets
    # `full_screen = FALSE` several lines before it gets there.  So the editor
    # printed "Vim: Caught deadly signal TERM", emitted stoptermcap's escapes,
    # exited, and left the terminal with ICANON and ECHO off.  Measured on the
    # slave side of a pty, before and after this phase: identical, and wrong
    # both times.  Upstream has the same hole.
    #
    # The fix is additive, so the ordinary exit path is untouched: settmode()
    # still runs and still does everything it does when full_screen is set, and
    # the two lines after it are exactly what settmode() would have done --
    # idempotent if it already did.
    # SCOPED TO prepare_to_exit: `settmode(TMODE_COOK);` at this indent also
    # appears in buf_write(), and an unanchored substitution took that one --
    # the same mistake this pipeline has made twice before with `case 't':` and
    # `char_u *tagname;`.
    #
    # And it uses settmode() rather than mch_settmode(), because mch_settmode()
    # is defined 89,000 lines further down with no forward declaration left to
    # reach it -- Phase 8 removed the ones nothing needed.  Lending
    # full_screen for the length of the call is enough: the guard exists to
    # avoid drawing on a screen that is not there, and putting the terminal
    # back is not drawing.
    import funcreach
    blanked = cutil.blank(text)
    a0, z0 = funcreach.definitions(text, blanked)['prepare_to_exit']
    body = text[a0:z0]
    old_line = '        settmode(TMODE_COOK);\n'
    if old_line not in body:
        sys.exit("nosignals: prepare_to_exit's settmode is not where this expects")
    body = body.replace(old_line,
        '        // settmode() returns at once when !full_screen, and deathtrap()\n'
        '        // clears it before this runs -- so on the way out from a signal\n'
        '        // the one thing this function exists for never happened: the\n'
        '        // terminal was left with ICANON and ECHO off and the shell that\n'
        '        // got it back was unusable.  The guard is there to avoid drawing\n'
        '        // on a screen that is not there, and putting the terminal back is\n'
        '        // not drawing, so it is lent full_screen for the length of the\n'
        '        // call.  Upstream has the same hole.\n'
        '        {\n'
        '            int was_full_screen = full_screen;\n'
        '\n'
        '            full_screen = TRUE;\n'
        '            settmode(TMODE_COOK);\n'
        '            full_screen = was_full_screen;\n'
        '        }\n', 1)
    text = text[:a0] + body + text[z0:]
    print('  nosignals    a killed editor puts the terminal back, which is what '
          'SIGHUP and SIGTERM are kept for')

    path.write_text(text, errors='surrogateescape')
    left = sorted(set(re.findall(r'\bSIG[A-Z0-9]+\b', text)))
    print('  nosignals    signals named in the file: %s' % ' '.join(left))


if __name__ == '__main__':
    main()
