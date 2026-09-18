#!/bin/sh
# Zero phase 21 -- the messages are the editor's, the writing is the host's.
# See ZERO-GOAL.md.
#
# Usage: pipes/zero21-edit.sh <work-dir> <state-dir>     (run from the repository root)
#
# ZERO-PLAN.md 4c's second step, and the half of it that is not the screen:
# "`printf` for the messages that appear before there is a screen, which is itself a
# question for the host".  This phase answers it.  Every byte this file has ever put
# on a stream instead of a screen goes through one call the launcher installs, in
# EXACTLY phase 19's shape:
#
#     static void (*vim_host_message)(const char *msg, int len, int err);
#     vim_main(int argc, char **argv, void (*exit_fn)(int),
#              void (*message_fn)(const char *, int, int))
#         vim_host_message = message_fn;
#     host_message()   beside host_exit(), in the launcher, write(err ? 2 : 1, ...)
#
# and `<stdio.h>` goes with them: TWELVE DIRECTIVES BECOME ELEVEN.  That is the second
# time a zero phase has removed one (phase 16 was the first), and it is the same
# argument -- this is the header the phase's symbols came from, the charter permits a
# removal and forbids an addition, and from here the "no stdio stream" invariant phase
# 13 asserted is visible in the directive list as well as in `nm -u`.
#
# UNLIKE PHASE 20, THIS ONE REALLY FREES SYMBOLS, and the reason is the rule phase 20
# stated: a symbol leaves when its last CALLER leaves the file.  `printf` and
# `fprintf` were being CALLED here, not merely mentioned, and deleting the calls
# deletes the callers.  `nm -u` 24 -> 17, the gone set exactly
# `fflush fputc fputs fwrite printf putchar stderr`, and NOTHING arrives.
#
# FOUR OF THOSE SEVEN ARE NAMED NOWHERE IN THE SOURCE.  `fputc`, `fputs`, `fwrite` and
# `putchar` are what gcc emits for `printf("%s", x)` and `fprintf(stderr, "%s", x)`;
# the file has never contained the word.  They were PREDICTED to leave with the
# construct and then VERIFIED by building -- which is the whole reason
# pipes/zero21-check.sh states the claim as one `comm` with an empty `arrived` side
# rather than as a count.
#
# ------------------------------------------------------------------------------------
# THE INVENTORY, MEASURED ON THE INPUT: 20 STATEMENTS IN FIVE FUNCTIONS
#
#   msg_puts_printf     2 printf, 2 fprintf   whatever message was being printed,
#                                             `info_message` choosing the stream
#   exit_scroll         1 printf, 1 fprintf   "\n" / "\r\n" on the way out
#   report_term_error   7 fprintf             `'<term>' not known, defaulting to
#                                             'xterm'`, before there is a screen
#   set_termname        1 fflush              ELEVEN LINES BELOW the call above, and
#                                             not inside report_term_error at all
#   mainerr             6 fprintf             the version banner and the argv refusal
#
# THE BRIEF THIS PHASE WAS WRITTEN FROM COUNTED 21 STATEMENTS IN SIX FUNCTIONS, and
# the sixth was `nv_esc`'s `Type :qa! and press <Enter> to abandon all changes`.  It
# went at phase 20, with `stdout_isatty` and the `out_redir` arm it sat in.  So
# `fprintf` is SIXTEEN here and not seventeen and `stderr` is seventeen and not
# eighteen, and the edit counts the input rather than trusting the survey.
#
# FORMATTING STAYS IN THE CORE, and that is what turns 20 statements into 8 call
# sites.  `vim_snprintf` has been the only formatter in the file since phase 14, so
# the two multi-part speakers assemble into a local buffer and hand over one string,
# and the other six sites are one call each with the text unchanged.  MEASURED with a
# SOCK_SEQPACKET socketpair as fd 2, which preserves write boundaries exactly: `-Q`
# was 6 writes of 96 bytes and is 1 write of 96 bytes; `-T no-such-term-9x` was 5 of
# 54 and is 1 of 54.  The same bytes, one syscall.
#
# THE BOUND THAT COMES WITH THE BUFFER, STATED RATHER THAN DISCOVERED.  `mainerr`'s
# `str` and `report_term_error`'s `term` are both argv, so a 1024-byte buffer caps a
# message that used to be unbounded.  MEASURED on both binaries: an unknown option of
# 900 characters is byte-identical, 995 bytes of stderr either side, and one of 2,000 is
# 2,095 bytes on the input and exactly 1,023 here; a `-T` of 900 is identical at 939 and
# one of 2,000 is 2,039 against the same 1,023.  The turn is at 930, where 1,025 becomes
# 1,023.  The cap is deliberate -- `IOSIZE` is 1024 and it is what every other message
# in this editor is built in -- and pipes/zero21-check.sh pins both halves of it, the
# identity at 900 and the exact cap at 2,000, so neither can drift unnoticed.
#
# ------------------------------------------------------------------------------------
# WHAT IS NOT DONE HERE, AND IT IS A DECISION AND NOT AN OVERSIGHT
#
# `msg_puts_printf()` STAYS, ALL 75 LINES OF IT, and so does `exit_scroll`'s printf
# arm.  `msg_use_printf()` is not dead: it returns TRUE in 23 of 106 records -- once in
# each `mainerr` record, from `mch_exit` -> `exit_scroll()`'s else arm ->
# `msg_clr_eos_force()`, where `full_screen` is FALSE and the body it guards therefore
# does nothing.  It is never true at `msg_puts_attr()`'s call site, so
# `msg_puts_printf()` is entered ZERO times against a control that marks 100 of 102
# screens.  That is phase 12's kind of dead and not phase 9's: the branch CAN be taken
# and never is.  Folding it at `msg_clr_eos_force()` would run `screen_fill()` with no
# valid screen; folding it at `msg_puts_attr()` would hand a message to
# `msg_puts_display()` on a screen the test has just called unusable.  Removing it is a
# separate phase with a separate question -- "the screen is always usable in this
# build" -- and phase 12's kind of evidence to gather, and it would free nothing,
# because the symbols are gone HERE.
#
# `__errno_location` IS NOT THIS PHASE'S EITHER, and it is said out loud because a
# reader who sees stdio leave will look for it.  MEASURED: `errno` is 3 mentions --
# `#include <errno.h>` and two uses, `host_tty_set`'s `tcsetattr(...) == -1 && errno ==
# EINTR` and `musl_wait_for_input`'s `ret == -1 && errno == EINTR`.  Phase 20 moved both
# INTO the host block and kept them.  They leave when the file splits, not here, and
# this phase's `comm` requires `__errno_location` still present for exactly that reason.
#
# `write` IS NOT ADDED TO tools/zhostonly.py's VOCAB, and the reason is that it would
# be false: `mch_write()` still holds one `write(1, ...)`, which is ZERO-PLAN.md 4c's
# remaining step and not this one.  What IS assertable, and what pipes/zero21-check.sh
# asserts instead, is that the whole file now has exactly TWO bare `write()` call sites
# -- `mch_write`'s and `host_message`'s -- where before this phase it had one and a
# stdio layer beside it.  Adding the stdio words to that tool's VOCAB is impossible for
# a different reason and worth writing down: phase 20's own output says `fprintf`
# sixteen times in the core, so a VOCAB that forbade it would fail `make zero-verify`
# at r20.
#
# THE COUNTING TRAP, WHICH IS PHASE 19'S `exit` TRAP WITH DIFFERENT WORDS.
# `assert printf at 0 mentions` FAILS ON A CORRECT PHASE.  `printf` is 13 words in the
# input and only THREE are calls: nine are `__attribute__((format(printf, ...)))` on
# `smsg`/`smsg_attr`/`semsg`/`siemsg`/`vim_snprintf` and two `format(printf,3,0)`
# prototypes, and one is inside the string `"E767: Too many arguments for printf()"`.
# 13 -> 10 is the true figure.  `assert 'printf(' at 0` fails on `vim_snprintf(`,
# `msg_use_printf(`, `msg_puts_printf(` and `vim_vsnprintf_typval(`.  The assertions
# that work are `fprintf` 16 -> 0, `stderr` 17 -> 0, `fflush` 1 -> 0, `printf`
# 13 -> 10, and `nm -u`.
set -eu

work=${1:?usage: zero21-edit.sh <work-dir> <state-dir>}
state=${2:?usage: zero21-edit.sh <work-dir> <state-dir>}
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
TAG = 'message'
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


lines_before = len(t.split('\n'))
runs_before = blank_runs(t)

# ---- 0. this is the file the phase was written against -------------------------------
# Counted on the INPUT, so a later phase that moved one of these fails here and not in
# the middle of a cut.  `fprintf` is 16 and not the brief's 17, and `stderr` 17 and not
# 18, because phase 20 took nv_esc's with the out_redir arm.
for name, want in (('fprintf', 16), ('stderr', 17), ('fflush', 1), ('printf', 13),
                   ('errno', 3), ('msg_use_printf', 6), ('msg_puts_printf', 3),
                   ('info_message', 9), ('vim_host_exit', 3), ('host_exit', 2),
                   ('FILE', 0), ('stdout', 0)):
    if mentions(t, name) != want:
        die('the input has %d mentions of `%s`, expected %d -- this is not the tree '
            'this phase was written against' % (mentions(t, name), name, want))
for name in ('vim_host_message', 'host_message', 'message_fn'):
    if mentions(t, name):
        die('`%s` already has %d mentions -- a name this phase introduces is taken'
            % (name, mentions(t, name)))
stmts = re.findall(r'(?m)^\s*(?:printf|fprintf|fflush)\(', t)
if len(stmts) != 20:
    die('%d statements begin with printf(, fprintf( or fflush(, expected the 20 the '
        'inventory names -- 4 in msg_puts_printf, 2 in exit_scroll, 7 in '
        'report_term_error, 1 in set_termname and 6 in mainerr' % len(stmts))
if t.count('#include <stdio.h>\n') != 1:
    die('<stdio.h> is not included exactly once, so the directive this phase removes '
        'is not the one it was written against')
say('the input is r20: 20 statements put bytes on a stream -- `fprintf` 16, `printf` '
    '13 words of which THREE are calls, `fflush` 1 -- and `FILE` and `stdout` are '
    'both at 0, which phase 13 is what left')

# ---- 1. the pointer, at the top, because its readers are scattered -------------------
# A file-scope OBJECT and not a prototype: CLAUDE.md's rule is that objects do not
# inherit linkage from a declaration, so the keyword is written here and is why
# `nm --extern-only` still prints one name.  Phase 19 put `vim_host_exit` immediately
# above its one reader; this one has EIGHT, the earliest of them 37,000 lines up, so it
# goes with the two musl_ prototypes that are already the file's boundary declarations.
sub('static int musl_towupper(int a);\nstatic int musl_towlower(int a);\n',
    'static int musl_towupper(int a);\nstatic int musl_towlower(int a);\n\n'
    'static void (*vim_host_message)(const char *msg, int len, int err);\n', 1, 'P1')

# ---- 2. msg_puts_printf, four sites, one for one -------------------------------------
# The `if (info_message)` shape is KEPT rather than folded to `!info_message`, so this
# phase changes which primitive writes and nothing about which stream is chosen.  It is
# also what keeps `info_message` at 9 mentions, which is the anchor that says so.
sub('''                if (info_message)
                {
                     printf("%s", ((char *)buf)) ;
                }
                else
                {
                     fprintf(stderr, "%s", ((char *)buf)) ;
                }
''', '''                if (info_message)
                {
                    vim_host_message((char *)buf, -1, FALSE);
                }
                else
                {
                    vim_host_message((char *)buf, -1, TRUE);
                }
''', 1, 'M1')
sub('''            if (info_message)
            {
                 printf("%s", ((char *)p)) ;
            }
            else
            {
                 fprintf(stderr, "%s", ((char *)p)) ;
            }
''', '''            if (info_message)
            {
                vim_host_message((char *)p, -1, FALSE);
            }
            else
            {
                vim_host_message((char *)p, -1, TRUE);
            }
''', 1, 'M2')

# ---- 3. exit_scroll, two sites, one for one ------------------------------------------
sub('''            if (info_message)
            {
                 printf("%s", ("\\n")) ;
            }
            else
            {
                 fprintf(stderr, "%s", ("\\r\\n")) ;
            }
''', '''            if (info_message)
            {
                vim_host_message("\\n", -1, FALSE);
            }
            else
            {
                vim_host_message("\\r\\n", -1, TRUE);
            }
''', 1, 'E1')

# ---- 4. report_term_error, seven statements into one ---------------------------------
# It runs from set_termname from termcapinit, which is the function that sets
# `full_screen = TRUE` afterwards -- so this message is emitted while there is no
# screen at all, which is the literal reading of ZERO-PLAN.md 4c's "the messages that
# appear before there is a screen".
sub('''report_term_error(char *error_msg, char_u *term)
{
     fprintf(stderr, "%s", ("\\r\\n")) ;
    if (error_msg != NULL)
    {
         fprintf(stderr, "%s", (error_msg)) ;
         fprintf(stderr, "%s", ("\\r\\n")) ;
    }
     fprintf(stderr, "%s", ("'")) ;
     fprintf(stderr, "%s", ((char *)term)) ;
     fprintf(stderr, "%s", (_("' not known, defaulting to 'xterm'"))) ;
     fprintf(stderr, "%s", ("\\r\\n")) ;
}
''', '''report_term_error(char *error_msg, char_u *term)
{
    char        buf[1024];

    if (error_msg != NULL)
    {
        vim_snprintf(buf, sizeof(buf), "\\r\\n%s\\r\\n'%s%s\\r\\n", error_msg, (char *)term, _("' not known, defaulting to 'xterm'"));
    }
    else
    {
        vim_snprintf(buf, sizeof(buf), "\\r\\n'%s%s\\r\\n", (char *)term, _("' not known, defaulting to 'xterm'"));
    }
    vim_host_message(buf, -1, TRUE);
}
''', 1, 'R1')

# ---- 5. the fflush, which is NOT where a reader expects it ---------------------------
# It is in set_termname, eleven lines BELOW the report_term_error() call and after
# set_string_option_direct("term", ...).  A phase that read "seven fprintf and one
# fflush in report_term_error" would edit the wrong function; it is anchored on its
# neighbour above so that it cannot be taken from anywhere else.
sub('''                set_string_option_direct((char_u *)"term", -1, term, OPT_FREE, 0);
                 fflush(stderr) ;
''', '''                set_string_option_direct((char_u *)"term", -1, term, OPT_FREE, 0);
''', 1, 'F1')

# ---- 6. mainerr, six statements into one ---------------------------------------------
# A LOCAL buffer and not IObuff: mainerr runs from command_line_scan, after
# common_init_1/common_init_2, and IObuff's state there is not this phase's business.
# The blank line after the opening brace becomes the declaration, which is what
# CLAUDE.md's "no blank line after an opening brace" wanted anyway.
sub('''mainerr(int         n, char_u      *str)
{

    init_longVersion();
     fprintf(stderr, "%s", (longVersion)) ;
     fprintf(stderr, "%s", ("\\n")) ;
     fprintf(stderr, "%s", (_(main_errors[n]))) ;
    if (str != NULL)
    {
         fprintf(stderr, "%s", (": \\"")) ;
         fprintf(stderr, "%s", ((char *)str)) ;
         fprintf(stderr, "%s", ("\\"")) ;
    }

    mch_exit(1);
}
''', '''mainerr(int         n, char_u      *str)
{
    char        buf[1024];

    init_longVersion();
    if (str != NULL)
    {
        vim_snprintf(buf, sizeof(buf), "%s\\n%s: \\"%s\\"", longVersion, _(main_errors[n]), (char *)str);
    }
    else
    {
        vim_snprintf(buf, sizeof(buf), "%s\\n%s", longVersion, _(main_errors[n]));
    }
    vim_host_message(buf, -1, TRUE);

    mch_exit(1);
}
''', 1, 'A1')

# ---- 7. the host installs it, through a parameter and not a global -------------------
sub('''    static int
vim_main(int argc, char **argv, void (*exit_fn)(int))
{

    vim_host_exit = exit_fn;
''', '''    static int
vim_main(int argc, char **argv, void (*exit_fn)(int), void (*message_fn)(const char *, int, int))
{

    vim_host_exit = exit_fn;
    vim_host_message = message_fn;
''', 1, 'V1')

# ---- 8. the launcher -------------------------------------------------------------------
# host_message() goes beside host_exit(), which is where phase 19 put the other half of
# this boundary, and main() stays the last thing in the file (CLAUDE.md).  `len < 0`
# means NUL-terminated; every one of today's eight call sites passes -1, and the
# parameter is there because the host should not have to scan and because vim_snprintf
# returns the exact length for free at the two sites that assemble.  THE LAUNCHER MAY
# CALL musl_strlen: it is in the same translation unit, it is the host's own code, and
# at the split it goes into the host file with it.
OLD = '''static void *host_jump[5];
static int host_code;

    static void
host_exit(int r)
{
    host_code = r;
    __builtin_longjmp(host_jump, 1);
}

    int
main(int argc, char **argv)
{
    if (__builtin_setjmp(host_jump) != 0)
    {
        return host_code;
    }
    return vim_main(argc, argv, host_exit);
}
'''
NEW = '''static void *host_jump[5];
static int host_code;

    static void
host_exit(int r)
{
    host_code = r;
    __builtin_longjmp(host_jump, 1);
}

    static void
host_message(const char *msg, int len, int err)
{
    int         n = len;
    int         off = 0;

    if (n < 0)
    {
        n = (int)musl_strlen(msg);
    }
    while (off < n)
    {
        int w = (int)write(err ? 2 : 1, msg + off, (size_t)(n - off));

        if (w <= 0)
        {
            return;
        }
        off += w;
    }
}

    int
main(int argc, char **argv)
{
    if (__builtin_setjmp(host_jump) != 0)
    {
        return host_code;
    }
    return vim_main(argc, argv, host_exit, host_message);
}
'''
if not t.endswith(OLD):
    die("zero-vim.c does not end with phase 19's twenty-line launcher, so this is not "
        'the file this phase was written against')
t = t[:len(t) - len(OLD)] + NEW

# ---- 9. the header the symbols came from ------------------------------------------------
# ZERO-GOAL.md's charter: a phase may REMOVE a directive and may never add one.  This is
# the second removal in the pipeline; phase 16 was the first, and made the argument.
sub('#include <stdio.h>\n', '', 1, 'H1')

# ---- what the file is now ---------------------------------------------------------------
for name in ('fprintf', 'stderr', 'fflush'):
    if mentions(t, name):
        die('`%s` still has %d mentions' % (name, mentions(t, name)))
if re.findall(r'(?m)^\s*(?:printf|fprintf|fflush)\(', t):
    die('a statement still begins with printf(, fprintf( or fflush(')
for name, want, why in (
        ('printf', 10, 'the counting trap: nine `format(printf, ...)` attributes and '
                       'the string "E767: Too many arguments for printf()".  NONE is a '
                       'call, and `assert printf at 0` fails on a correct phase'),
        ('vim_host_message', 10, 'the declaration, the installation in vim_main and the '
                                 'EIGHT call sites -- 4 in msg_puts_printf, 2 in '
                                 'exit_scroll, 1 in report_term_error, 1 in mainerr'),
        ('host_message', 2, "the launcher's definition and the argument main() passes.  "
                            '`vim_host_message` is a DIFFERENT word and \\b does not '
                            'match inside it, which is why these two counts are '
                            'separate -- phase 19 learnt that with host_exit'),
        ('vim_host_exit', 3, "phase 19's, untouched"),
        ('host_exit', 2, "phase 19's, untouched"),
        ('msg_use_printf', 6, 'a prototype, a definition and four call sites -- '
                              'UNTOUCHED, and deliberately: it returns TRUE 23 times in '
                              '106 records'),
        ('msg_puts_printf', 3, 'a prototype, a definition and one call -- all 75 lines '
                               'stay, and only what they call changes'),
        ('info_message', 9, 'untouched, because the four sites that read it kept their '
                            '`if (info_message)` shape'),
        ('errno', 3, "phase 21 is not the errno phase: the #include and two uses, both "
                     'inside phase 20\'s host block'),
        ('vim_snprintf', 73, 'FOUR more than the input -- the two multi-part speakers '
                             'each assemble in two arms, with the only formatter the '
                             'file has had since phase 14'),
        ('musl_strlen', 134, "one more than the input: host_message's, in the len < 0 "
                             'arm'),
):
    if mentions(t, name) != want:
        die('`%s` has %d mentions, expected %d -- %s' % (name, mentions(t, name), want, why))
d = [l for l in t.split('\n') if l.startswith('#')]
if len(d) != 11 or any(not l.startswith('#include <') for l in d):
    die('the output does not have exactly ELEVEN #include directives and nothing else '
        '-- this phase removes <stdio.h> and adds none')
if blank_runs(t) != runs_before:
    die('the edit left %d runs of two blank lines where there were %d'
        % (blank_runs(t), runs_before))

open(path, 'w', errors='surrogateescape').write(t)
say('%d -> %d lines.  Every byte that leaves this editor other than the screen goes '
    'through one `vim_host_message(msg, len, err)` the launcher installs; <stdio.h> is '
    'gone and the directive count is 11'
    % (lines_before, len(t.split('\n'))))
PY

# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  message      the input binary did not build with '$cflags' '$ldflags'"; exit 1; }
echo "  message      the input is $state/old, $(stat -c%s "$state/old") bytes, beside the source it was built from -- the recording, the write boundaries on fd 2 and the instrumented pair are all PAIRS, and this is the left-hand side"

# tools/phaserun.sh sweeps next, then runs pipes/zero21-check.sh.
