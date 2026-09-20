#!/bin/sh
# Zero phase 4 -- no streaming Ex.  See ZERO-GOAL.md.
#
# Usage: pipes/zero4-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# An embeddable core is driven by a host through a screen and a keyboard.  Ex mode
# is the opposite arrangement: the editor takes stdin over, prints its own prompt,
# reads a line at a time and writes the result back on stdout, and it brings a
# second mode with it -- silent mode, which redirects the whole message layer into
# `printf` and buffers stdout through setvbuf().  Both are entered from the command
# line (`-e`, `-E`, `-s`, `-v`) or from the keyboard (`Q`, `gQ`), and neither has
# any meaning for a core that is handed its input and its screen.
#
# WHAT GOES.  `do_exmode()` and `getexmodeline()`, the loop and the line reader;
# `nv_exmode()` and `nv_g_cmd`'s `case 'Q'`, the two keys that call them; the four
# command-line options; and then the two globals they were the only writers of --
# `exmode_active` (49 mentions) and `silent_mode` (23) -- which become constantly
# FALSE and fold away at every one of their readers.
#
# THE TWO COUNTS ARE ASSERTED BEFORE THE CUT AND AFTER IT, and so are the other
# nineteen identifiers that go with them.  A fold is only sound while the variable
# really is constant, so "every mention is accounted for" is the whole argument:
# 49 and 23 before, 0 and 0 after, counted by `\b` because `pending_exmode_active`
# contains `exmode_active` and a plain substring count says 53.
#
# EVERY FOLD IS COUNTED AND SCOPED TO ONE FUNCTION (tools/cutil.py), because the
# polarity is not the same at every site and a fold applied to "the first one" of
# several is a guess:
#
#   * `if (exmode_active)`            folds NEVER -- the body is Ex mode's
#   * `if (!exmode_active)`           folds ALWAYS -- the body is everyone else's
#   * `if (exmode_active != EXMODE_NORMAL)` in msg_start() folds **ALWAYS**, because
#     0 != 1 is TRUE.  It reads like its neighbours and is their opposite, and
#     getting it backwards would quietly give every message Ex mode's newline.
#
# WHAT STAYS, and the reader that forces each:
#   * `getexline()` -- `:append`, `:insert` and `:change` read their lines through
#     it, not through the Ex-mode reader.  It keeps `ex_at` and `nv_colon`.
#   * `exe_commands()` -- it runs the `+{command}` list, which is how every harness
#     here drives the editor.  Only its last statement, an `if (!exmode_active)`,
#     folds.
#   * everything the argv phase owns: `case NUL`'s else arm (`EDIT_STDIN`,
#     `read_cmd_fd = 2`), `case '-'` and `had_minmin`, the file argument,
#     `ME_TOO_MANY_ARGS` and its `main_errors[]` row, `case 'T'`, the `+cmd` arm.
#   * `cmdwin` and `want_full_screen`, which lose a reader each and keep one.
#
# `-s` IS NOT IN THE DECLARED DELTA and the reason is worth stating: it was never
# an option on its own.  `case 's'` set silent mode only `if (exmode_active)` and
# called `mainerr(ME_UNKNOWN_OPTION)` otherwise, so `vim -s` already failed before
# this phase and fails in the same way after it.  `-e`, `-E`, `-e -s` and `-v` do
# move, and are declared in pipes/zero.delta.
#
# THREE FUNCTIONS ARE DELETED BY NAME rather than left to the sweep.  A function
# whose address is taken is reachable as far as gcc is concerned: `getexmodeline`
# is passed to `do_cmdline()` and compared with `getline_equal()`, so -Wunused-
# function never names it, and `do_exmode` keeps it alive through a call the sweep
# would have to remove first.  `nv_exmode` goes the same way, because an `nv_cmds[]`
# row is a reference: the row is REPOINTED at `nv_error` and never deleted -- a
# deleted row shifts `nv_cmd_idx[]` and every key past the hole resolves to another
# key's handler (CLAUDE.md; `nvidx` is what would catch it).
#
# SIX WRITE-ONLY LEFTOVERS GO BY HAND, because no warning covers a variable that is
# assigned and never read: `ex_pressedreturn`, `ex_no_reprint` (seven writes),
# `ex_exitval`, `previous_got_int`, `use_plus_cmd` and `exmode_was`.  gcc's
# -Wunused-but-set-variable sees a local, not a file-scope static, and
# tools/deadsweep.py only deletes what gcc names.
#
# THE SWEEP TAKES the rest: `exmode_active`, `silent_mode`, `pending_exmode_active`,
# `s_vbuf`, `exmode_plus`, `e_at_end_of_file`, the `getexmodeline` and `nv_exmode`
# prototypes, the three single-constant enums (`EXMODE_NORMAL`, `EXMODE_VIM`,
# `BO_EX` -- each with an explicit value, so nothing renumbers), and
# `mch_input_isatty()`, with the fifth of the five `isatty()` calls.
#
# `check_tty()` IS PHASE 2'S AS MUCH AS THIS ONE'S.  Phase 2 took its warning branch
# and kept the `if (exmode_active)` one deliberately, saying Ex mode was a later
# phase's.  This is that phase, and nothing is left -- which is why `isatty` goes
# from five calls to four here and not there.  It is deleted by name rather than
# folded, for the reason given at the site.
#
# THAT INPUT BINARY IS BUILT HERE, before the edit, from the boundary's own makefile
# flags, exactly as pipes/zero2-edit.sh does it: pipes/zero4-check.sh requires the
# OLD binary to enter Ex mode and the new one to refuse, which is the difference
# between a probe and a formality.
set -eu

work=${1:?usage: zero4-edit.sh <work-dir> <state-dir>}
state=${2:?usage: zero4-edit.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"

# The flags are read out of the boundary's makefile rather than written here a
# second time: zero's compile line is the boundary's (ZERO-GOAL.md rule 8).
cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")
cp "$f" "$state/old.c"
# shellcheck disable=SC2086
( cd "$state" && gcc $cflags $ldflags -o old old.c ) &
pid_old=$!

python3 - "$f" <<'PY'
TAG = 'noexmode'
import re, sys
sys.path.insert(0, 'tools')
import cutil
path = sys.argv[1]
t = open(path, errors='surrogateescape').read()


def die(msg):
    sys.exit('  %-12s %s' % (TAG, msg))


def say(what):
    print('  %-12s %s' % (TAG, what))


def mentions(text, name):
    return len(re.findall(r'\b%s\b' % name, text))


def line(body):
    """A whole line, by its trimmed text: the anchor is exact and countable."""
    return r'^[ \t]*' + re.escape(body) + r'$'


def head(body):
    """A line that starts with this and runs on: the 200-column conditions."""
    return r'^[ \t]*' + re.escape(body) + r'.*$'


def in_function(text, name, edit):
    span = cutil.find_definition(text, name)
    if not span:
        die('%s is not defined' % name)
    a, z = span
    return text[:a] + edit(text[a:z]) + text[z:]


def guarded_body(s, m):
    """The block an `if` guards, for the break/continue audit below."""
    b = cutil.blank(s)
    lp = s.index('(', m.start())
    rp = cutil.match(s, lp, b)
    o = rp + 1
    while o < len(s) and s[o] in ' \t\n':
        o += 1
    return s[o:cutil.match(s, o, b)]


def fold(kind, fn, pattern, what, n=1):
    """A counted fold inside one function, its polarity stated by the caller.

    A kept body is audited for `break` and `continue` first: fold_always leaves
    the body where it was, so neither changes which loop it binds to, but a body
    that carries one is a body whose condition was doing more than choosing, and
    that is worth failing on rather than assuming.
    """
    def edit(s):
        if kind == 'always':
            for m in re.finditer(pattern, s, re.M):
                if re.search(r'\b(break|continue)\b', guarded_body(s, m)):
                    die('%s -- the body kept by this fold carries a break or continue' % what)
        try:
            f = cutil.fold_always if kind == 'always' else cutil.fold_never
            return f(s, pattern, n, re.M)
        except ValueError as e:
            die('%s -- %s' % (what, e))
    out = in_function(text_of[0], fn, edit)
    say(what)
    return out


def within(fn, old, new, what=None, n=1):
    """Replace exact text inside one function, counted there and not file-wide.

    `what` is optional: a second or third edit that finishes the one above it
    has nothing of its own to say.
    """
    def edit(s):
        k = s.count(old)
        if k != n:
            die('%s -- %r occurs %d times in %s, expected %d'
                % (what or 'in ' + fn, old, k, fn, n))
        return s.replace(old, new)
    out = in_function(text_of[0], fn, edit)
    if what:
        say(what)
    return out


def literal(old, new, what, n=1):
    t = text_of[0]
    k = t.count(old)
    if k != n:
        die('%s -- %r occurs %d times, expected %d' % (what, old, k, n))
    say(what)
    return t.replace(old, new)


def drop_definition(name, what):
    t, ok = cutil.delete_definition(text_of[0], name)
    if not ok:
        die('%s -- %s is not defined' % (what, name))
    say(what)
    return t


text_of = [t]


def do(new):
    text_of[0] = new


# ---- 0. the invariants the cut rests on -------------------------------------------
# The whole argument for folding is that these two are constant, and the only
# evidence for that is that every mention is accounted for.  Asserted before, and
# required to be zero after.
BEFORE = {'exmode_active': 49, 'silent_mode': 23, 'pending_exmode_active': 4,
          'exmode_plus': 3, 'exmode_was': 2, 'do_exmode': 4, 'getexmodeline': 6,
          'nv_exmode': 3, 'EXMODE_NORMAL': 6, 'EXMODE_VIM': 5, 'BO_EX': 2,
          'ex_pressedreturn': 7, 'ex_no_reprint': 11, 'ex_exitval': 3,
          'previous_got_int': 4, 'use_plus_cmd': 5, 's_vbuf': 4,
          'e_at_end_of_file': 2, 'noexmode': 4, 'check_tty': 2,
          'mch_input_isatty': 2}
for name, want in sorted(BEFORE.items()):
    k = mentions(t, name)
    if k != want:
        die('%s has %d mentions, expected %d -- the anchors below were counted '
            'against a different file' % (name, k, want))
if len(re.findall(r'\bisatty\(', t)) != 5:
    die('isatty is called %d times, expected 5' % len(re.findall(r'\bisatty\(', t)))
say('21 identifiers at their counted mentions: exmode_active 49, silent_mode 23, isatty 5 calls')

# ---- 1. the two keys, and the three functions they reach ---------------------------
# The row is REPOINTED, never deleted (CLAUDE.md, `nvidx`).
do(literal("     {'Q', nv_exmode, NV_NCW, 0} ,\n",
           "     {'Q', nv_error, NV_NCW, 0} ,\n",
           "the 'Q' row points at nv_error, so Q beeps like any unused key"))
do(literal("""    case 'Q':
        if (!check_text_locked(cap->oap) && !checkclearopq(oap))
        {
            do_exmode(TRUE);
        }
        break;

""", '', "gQ's arm of nv_g_cmd, which falls to default: clearopbeep"))
do(drop_definition('nv_exmode', 'nv_exmode'))
do(drop_definition('do_exmode', 'do_exmode, the Ex-mode loop'))

# `getexmodeline`'s last live reference is one disjunct of do_cmdline's 200-column
# while condition, and nothing else in the file mentions it outside a fold below.
# Miss it and the reader survives, silently, with its 263 lines.
do(literal('(getline_equal(fgetline, cookie, getexmodeline) || getline_equal(fgetline, cookie, getexline))',
           'getline_equal(fgetline, cookie, getexline)',
           "do_cmdline stops asking whether it is reading Ex-mode lines"))
do(drop_definition('getexmodeline', 'getexmodeline, the Ex-mode line reader'))

# ---- 2. the four command-line options ----------------------------------------------
# They fall to `default: mainerr(ME_UNKNOWN_OPTION)`, which is what any other
# unknown letter does.  These go BEFORE the `case NUL` fold below, because until
# they do there are two `if (exmode_active)` in command_line_scan and a counted
# fold refuses -- loudly, which is the point.
for opt, body in (('e', '                exmode_active = EXMODE_NORMAL;\n'),
                  ('E', '                exmode_active = EXMODE_VIM;\n'),
                  ('s', '                if (exmode_active)\n'
                        '                {\n'
                        '                    silent_mode = TRUE;\n'
                        '                }\n'
                        '                else\n'
                        '                {\n'
                        '                    mainerr(ME_UNKNOWN_OPTION, (char_u *)argv[0]);\n'
                        '                }\n'),
                  ('v', '                exmode_active = 0;\n')):
    do(literal("            case '%s':\n%s                break;\n\n" % (opt, body), '',
               "-%s is an unknown option" % opt))

# ---- 3. every reader of exmode_active, in file order -------------------------------
do(fold('never', 'do_ecmd', line('if (exmode_active)'),
        'do_ecmd no longer puts the cursor on the last line'))
do(fold('never', 'ex_substitute', line('if (exmode_active)'),
        'ex_substitute keeps its 85-line interactive else'))
do(within('do_one_cmd', 'if (sourcing || exmode_active)', 'if (sourcing)',
          'do_one_cmd asks only whether it is sourcing'))
do(fold('never', 'ex_range_without_command',
        line('if (exmode_active && eap->cmd != (char_u *)exmode_plus + 1)'),
        'a bare range is no longer an implicit :print'))
do(fold('never', 'parse_command_modifiers',
        head('if (*eap->cmd == NUL && exmode_active && '),
        'an empty Ex-mode line is no longer the + command'))
do(fold('never', 'do_exedit',
        line('if (exmode_active && (eap->cmdidx == CMD_visual || eap->cmdidx == CMD_view))'),
        ':visual, :vi and :view lose the branch that left Ex mode'))
do(within('do_exedit', '\n    int         exmode_was = exmode_active;\n', '\n',
          'and exmode_was, which only that branch read'))
do(fold('never', 'ex_read', line('if (empty && exmode_active)'),
        ':read stops deleting the empty line it read into'))
do(fold('never', 'cmdline_erase_chars', line('if (exmode_active)'),
        'backspacing off the start of a command line leaves Normal mode again'))
do(fold('never', 'getcmdline_int', head('if (exmode_active && c != ESC && '),
        'a trailing backslash no longer continues a command line'))
do(fold('never', 'getcmdline_int',
        line('if (exmode_active && (ex_normal_busy == 0 || typebuf.tb_len > 0))'),
        'and ESC on a command line is an abort again'))
do(within('compute_cmdrow', 'if (exmode_active || (msg_scrolled != 0 && !updating_screen))',
          'if (msg_scrolled != 0 && !updating_screen)',
          'compute_cmdrow asks only about the scroll'))
do(fold('never', 'readfile', line('if (exmode_active)'),
        'readfile leaves the cursor on the first line read'))
do(fold('never', 'vgetorpeek', line('if (pending_exmode_active)'),
        'an interrupted nested main_loop has no Ex mode to return to'))
do(within('vgetorpeek', 'if (typebuf.tb_len > 0 && advance && !exmode_active)',
          'if (typebuf.tb_len > 0 && advance)',
          'and the partial command is shown whenever there is one'))
do(within('msg_strtrunc', ' && !exmode_active && msg_silent == 0)',
          ' && msg_silent == 0)', 'msg_strtrunc truncates as it does on a screen'))
do(within('msg_may_trunc', '(shortmess(SHM_TRUNC) && !exmode_active)',
          'shortmess(SHM_TRUNC)', 'and so does msg_may_trunc'))
do(fold('always', 'wait_return', line('if (!exmode_active)'),
        'wait_return moves the command row, both times', 2))
do(fold('never', 'wait_return', line('else if (exmode_active)'),
        "and no longer answers its own prompt with a space"))
# THE POLARITY TRAP.  0 != EXMODE_NORMAL is TRUE, so this one folds ALWAYS while
# both of its neighbours fold never.
do(fold('always', 'msg_start', line('if (exmode_active != EXMODE_NORMAL)'),
        'msg_start keeps the cmdline_row it set after a newline (0 != 1 is TRUE)'))
do(within('msg_puts_display', 'if (cmdline_row > 0 && !exmode_active)',
          'if (cmdline_row > 0)', 'msg_puts_display scrolls the command row'))
do(within('msg_puts_display', ' && !msg_no_more && !exmode_active)', ' && !msg_no_more)',
          'and the more-prompt is offered whenever the screen is full'))
do(within('screen_puts_len', '\n                || exmode_active\n', '\n',
          'a character is redrawn when it changed, and not otherwise'))
do(within('set_shellsize_inner', ' || State == MODE_CONFIRM || exmode_active)',
          ' || State == MODE_CONFIRM)', 'a resize repeats the message only at a prompt'))
do(fold('always', 'vim_main2', line('if (!exmode_active)'),
        'vim_main2 stops scrolling messages at startup'))
do(fold('never', 'vim_main2', line('if (exmode_active)'),
        'and clears the screen, and leaves the cursor where the file put it', 2))
do(fold('never', 'main_loop', line('if (noexmode && global_busy && !exmode_active && previous_got_int)'),
        'CTRL-C in a :global no longer drops into Ex mode'))
# fold_never rewrote the `else if` that followed into an `if`, so this one is
# written without the `else` it had a moment ago.
do(fold('always', 'main_loop', line('if (!global_busy || !exmode_active)'),
        'and swallows the interrupt as it always did outside :global'))
do(fold('always', 'main_loop', line('if (!exmode_active)'),
        'the main loop stops scrolling messages'))
do(within('main_loop', 'if (skip_redraw || exmode_active)', 'if (skip_redraw)',
          'and redraws unless the last command asked it not to'))
do(fold('never', 'main_loop', line('if (exmode_active)'),
        'and runs normal_cmd, which is now the only thing it can run'))
do(fold('never', 'getout', line('if (exmode_active)'),
        'the exit status is the one getout was given'))
do(fold('never', 'command_line_scan', line('if (exmode_active)'),
        "a bare `-` is stdin again, which the argv phase owns"))
# check_tty() IS DELETED HERE RATHER THAN FOLDED, and the reason is a gap in the
# sweep worth naming.  Folding its one branch leaves `int input_isatty;
# input_isatty = mch_input_isatty();` -- a local that is written and never read, which
# gcc reports as -Wunused-but-set-variable, and tools/deadsweep.py acts only on
# -Wunused-variable and -Wunused-function.  Measured: the sweep reports it as "left
# alone 1" and settles with the warning still there, which tools/phasecheck.sh then
# fails on.  So the function and its one call in main() go by name, and
# mch_input_isatty() -- whose only caller it was -- is what the sweep takes, with the
# fifth isatty() call.
do(drop_definition('check_tty', 'check_tty, which has nothing left to ask'))
do(within('main', '\n    check_tty();\n', '\n', 'and its call in main'))
# exe_commands MUST SURVIVE: it is what runs `+{command}`, and every harness here
# drives the editor with one.  Only its last statement folds.
do(fold('always', 'exe_commands', line('if (!exmode_active)'),
        'exe_commands stops scrolling messages, and keeps running +cmd'))

# ---- 4. every reader of silent_mode, in file order ---------------------------------
do(within('change_warning', 'if (msg_silent == 0 && !silent_mode)', 'if (msg_silent == 0)',
          "the 'readonly' warning pauses whenever it is shown"))
do(within('print_line', '\n    int         save_silent = silent_mode;\n', '\n',
          'print_line prints on the screen, once'))
do(within('print_line', '\n    silent_mode = FALSE;\n', '\n'))
do(fold('never', 'print_line', line('if (save_silent)'),
        'and no longer flushes a line it never buffered'))
do(fold('always', 'msg_puts_printf', line('if (!(silent_mode && p_verbose == 0))'),
        'msg_puts_printf writes what it is given'))
do(within('msg_puts_printf', 'if (*p != NUL && !(silent_mode && p_verbose == 0))',
          'if (*p != NUL)', 'including the last piece'))
do(fold('never', 'do_set', line('if (silent_mode && did_show)'),
        ':set prints its listing on the screen'))
do(within('showoneopt', '\n    int         save_silent = silent_mode;\n', '\n',
          'and so does one option'))
do(within('showoneopt', '\n    silent_mode = FALSE;\n', '\n'))
do(within('showoneopt', '\n    silent_mode = save_silent;\n', '\n'))
do(fold('never', 'exit_scroll', line('if (silent_mode)'),
        'exiting scrolls the screen as it does from Normal mode'))
do(within('typed_ahead', 'return (!silent_mode && char_avail());', 'return char_avail();',
          "typed_ahead is char_avail() again -- slim's 'lazyredraw' fix had only one caller"))
do(fold('never', 'set_termname', line('if (silent_mode)'),
        'a terminal is set up whenever one is named'))
do(fold('always', 'ui_write', line('if (!(silent_mode && p_verbose == 0))'),
        'ui_write writes'))
do(fold('never', 'read_error_exit', line('if (silent_mode)'),
        'a read error is reported before the exit, not instead of it'))
# This is the whole of setvbuf, and the file's only mention of stdout.
do(fold('never', 'main', line('if (silent_mode)'),
        'main stops buffering stdout: setvbuf and stdout leave the binary'))
do(within('main', 'if (params.want_full_screen && !silent_mode)',
          'if (params.want_full_screen)', 'and sets up the terminal when it is asked to'))

# ---- 5. what nothing reads any more, and no warning names --------------------------
# A file-scope static that is written and never read draws no warning at all, and a
# local one draws -Wunused-but-set-variable, which tools/deadsweep.py does not act
# on.  Six of them, and they are invisible to every tool here.
do(literal('\nstatic int      ex_pressedreturn = FALSE;\n', '\n', 'ex_pressedreturn'))
do(within('parse_command_modifiers', '\n                ex_pressedreturn = TRUE;\n', '\n',
          'and its one remaining write'))
do(literal('\nstatic int ex_no_reprint  = FALSE ;\n', '\n', 'ex_no_reprint'))
do(literal('\n    ex_no_reprint = TRUE;\n', '\n', 'and its seven writes', 6))
do(literal('\n        ex_no_reprint = TRUE;\n', '\n', 'and the seventh'))
do(literal('\nstatic int      ex_exitval  = 0 ;\n', '\n', 'ex_exitval'))
do(within('emsg_core', '\n        ex_exitval = 1;\n\n', '\n', 'and its one write'))
do(within('main_loop', '\n    volatile int previous_got_int = FALSE;\n', '\n',
          'previous_got_int, which only the Ex-mode arm read'))
do(within('main_loop', '\n            previous_got_int = TRUE;\n', '\n'))
do(within('main_loop', """        else
        {
            previous_got_int = FALSE;
        }
""", ''))
do(fold('never', 'parse_command_modifiers', line('if (use_plus_cmd)'),
        'use_plus_cmd: the two arms of the :visual range rewrite', 2))
do(fold('never', 'parse_command_modifiers', line('else if (use_plus_cmd)'),
        'and the + command it stood for'))
do(within('parse_command_modifiers', '\n    int     use_plus_cmd = FALSE;\n', '\n',
          'and the flag itself'))

# ---- 6. main_loop's second parameter, and the label it jumped to -------------------
# `noexmode` said "return instead of entering Ex mode", which is now what the
# function does unconditionally; `theend:` was that return, and an unused label is
# a warning, which tools/phasecheck.sh fails on.
do(literal('\nstatic void main_loop(int cmdwin, int noexmode);\n',
           '\nstatic void main_loop(int cmdwin);\n', "main_loop's prototype"))
do(literal('main_loop(int         cmdwin, int         noexmode)\n',
           'main_loop(int         cmdwin)\n', 'its definition'))
do(literal('\n    main_loop(FALSE, FALSE);\n', '\n    main_loop(FALSE);\n', 'and its one caller'))
do(within('main_loop', """
theend:
    current_oap = prev_oap;
""", """
    current_oap = prev_oap;
""", 'the theend: label, which nothing jumps to now'))

# ---- 7. what is left is exactly what the sweep can take -----------------------------
# Every use is gone; what remains of each name is its definition, and each of those
# is a kind tools/sweep.sh deletes -- a static with no reader (-Wunused-variable), a
# prototype with no definition (deadprotos.py), an enumerator nothing names
# (deadenums.py), a function nothing calls (deadsweep.py, then funcreach.py).  Stated
# as a number per name, so a use that survived shows up here and not as a warning
# five minutes later.  pipes/zero4-check.sh requires 0 of all 21 after the sweep.
AFTER = {'exmode_active': 1, 'silent_mode': 1, 'pending_exmode_active': 1,
         'exmode_plus': 1, 'exmode_was': 0, 'do_exmode': 0, 'getexmodeline': 1,
         'nv_exmode': 1, 'EXMODE_NORMAL': 1, 'EXMODE_VIM': 1, 'BO_EX': 1,
         'ex_pressedreturn': 0, 'ex_no_reprint': 0, 'ex_exitval': 0,
         'previous_got_int': 0, 'use_plus_cmd': 0, 's_vbuf': 1,
         'e_at_end_of_file': 1, 'noexmode': 0, 'check_tty': 0,
         'mch_input_isatty': 1}
t = text_of[0]
for name, want in sorted(AFTER.items()):
    k = mentions(t, name)
    if k != want:
        die('%s has %d mentions after the cut, expected %d -- %s'
            % (name, k, want, 'a use survived' if k > want else 'more went than was meant to'))
# `E501: At end-of-file` is not checked here: it is the initialiser of
# `e_at_end_of_file`, whose last reader was do_exmode, and the string leaves with the
# variable in the sweep.  The check asks for it afterwards.
if 'Entering Ex mode' in t:
    die("'Entering Ex mode' survives the edit")
say('every use of all 21 is gone; eleven lone definitions and mch_input_isatty '
    'are what the sweep takes')

open(path, 'w', errors='surrogateescape').write(t)
PY

# NOT tools/create_cmdidxs.py --check: the derived first-two-letters index went with
# the command table whim reduced, and there are no `ex_cmdidxs.h` banners left for it
# to find -- it raises rather than reporting nothing (pipes/zero2-edit.sh says the
# same).  Nothing here touches the command table.
#
# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  noexmode     the input binary did not build with '$cflags' '$ldflags'"; exit 1; }
echo "  noexmode     the input binary is $state/old, $(stat -c%s "$state/old") bytes, for the check's before-and-after"

# tools/phaserun.sh sweeps next, then runs pipes/zero4-check.sh.
