#!/bin/sh
# Zero phase 13 -- no `FILE *` that is never opened.  See ZERO-GOAL.md.
#
# Usage: pipes/zero13-edit.sh <work-dir> <state-dir>     (run from the repository root)
#
# Two `static FILE *` survive in this editor and NOTHING HAS EVER OPENED EITHER OF
# THEM IN ANY BUILD OF zero-vim: `scriptin[NSCRIPT]`, which `-s {scriptfile}` filled
# and which whim removed the option for, and `redir_fd`, which `:redir > file` filled
# and which whim removed the command for.  So this phase removes the POSSIBILITY
# rather than a behaviour -- the same situation as phase 9, and the same answer:
# nothing it takes is reachable, the declared delta is nothing at all, and the
# evidence is an instrumented pair and a set of counts.
#
# THE COUNTS ARE THE ARGUMENT, and each is asserted before anything is folded:
#
#   * `scriptin[]` is assigned in exactly ONE place in the whole file, and that place
#     is `scriptin[curscript] = NULL;` inside `closescript()`.  So it is NULL for
#     ever, `== NULL` is TRUE and `!= NULL` is FALSE at every site.
#   * `redir_fd`'s only assignment is its own declaration, `= NULL`.  Same.
#   * `ui_write()` has three mentions -- a prototype, a definition and ONE call --
#     and that call passes `FALSE` for `console`.
#
# SIX ANCHORS, in three groups.
#
#   A  scriptin[] is NULL for ever.
#      1  `may_sync_undo()` loses one conjunct and SURVIVES: `u_sync()` still runs on
#         the same condition.
#      2  `is_safe_now()` loses one conjunct and SURVIVES.
#      3  `using_script()` is FALSE at both call sites -- a `&& !using_script()`
#         conjunct and a `|| using_script()` disjunct -- and the sweep then takes it.
#      4  `inchar()`'s script reader, deleted as TEXT with its local, after which
#         `if (script_char < 0)` is always true and folds.  THAT FOLD IS WHAT TAKES
#         `closescript()`'s only caller, and `fclose` and `getc` with it.
#   B  redir_fd is NULL for ever, so `redirecting()` is FALSE always and folds at
#      BOTH call sites.  Their indentation differs, which is what makes two separate
#      one-count patterns honest rather than a count of two over one pattern.
#   C  `ui_write()`'s `console` is FALSE at its one call site, so the `vim_fsync(1)`
#      it guards can never be entered.  THE PARAMETER GOES TOO, and that is what
#      makes the cut honest: leaving it would leave `__attribute__((unused))` on
#      something that will never be read again, which is phase 2's argument for
#      `check_tty(void)` -- and tools/sweep.sh compiles with -Wno-unused-parameter,
#      so an unused parameter is invisible where an unused local is not.
#
# TWO LOCALS ARE FOLDED BY HAND AND NO TOOL COVERS EITHER.
#
#   `retesc` is `FALSE` at its declaration, is written only inside the loop anchor A4
#   deletes, and is read once.  Afterwards it is a local that is READ AND NEVER
#   WRITTEN: gcc has no warning for that, tools/deadsweep.py acts on warnings, and
#   leaving it would mean `inchar()` returns an uninitialised value on a path the
#   compiler thinks exists.  `return retesc;` becomes `return FALSE;` and the
#   declaration goes.  This is phase 7's `usefilter` judgement in this phase's shape.
#
#   `did_return` is the same shape one level down: the `if (!did_return)` block the
#   redir_write extra removes is its only reader, and an `if` with an empty body is
#   not something any tool here removes either, so the block goes whole with
#   cutil.drop_if and the variable's two lines go with it.
#
# THE RECOMMENDED EXTRA IS TAKEN: `redir_write()` IS A NO-OP AFTERWARDS.  After B it
# is `{ char_u *s = str; static int cur_col = 0; if (redir_off) return; }` -- the
# sweep takes the two variables and leaves a function with five callers that cannot
# do anything.  Leaving it is the "concept the table has and the code does not" that
# whim's Phase 18 argued against, so it goes with its five call sites, and
# `redir_off` -- then written five times and read never, a file-scope static no
# warning covers -- goes with them.
#
# A SECOND EXTRA IS DECLINED AND IS A QUESTION FOR THE USER, not an oversight.  After
# this phase `typedef struct stat stat_T;` has no user and `#include <sys/stat.h>`
# and `#include <fcntl.h>` are needed by nothing.  Removing all three is free -- it
# was measured: same binary, byte-identical recording -- but it would be the FIRST
# TIME ANY ZERO PHASE CHANGES THE DIRECTIVE COUNT, and ZERO-GOAL.md's charter says
# `zero-vim.c` "inherits 18 directives from `whim-vim.c`".  That sentence is a
# statement about the pipeline, so the change belongs to whoever decides it, either
# here or as an includes phase of its own.  The count stays 18.
#
# THE INPUT BINARY IS BUILT HERE, before the edit, from the boundary's own makefile
# flags, and the source goes with it as $state/old.c.  The check needs both: there is
# no behavioural probe this phase can offer, so it instruments the source it was
# HANDED at five places and requires zero markers, with a control that must fire.
set -eu

work=${1:?usage: zero13-edit.sh <work-dir> <state-dir>}
state=${2:?usage: zero13-edit.sh <work-dir> <state-dir>}
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
TAG = 'nofile'
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


def text_edit(text, old, new, what, n=1):
    """An exact-text replacement, counted file-wide.  Never 'the first one'."""
    k = text.count(old)
    if k != n:
        die('%s -- the text occurs %d times, expected %d: %r'
            % (what, k, n, old[:70]))
    say(what)
    return text.replace(old, new)


def in_function(text, name, edit):
    span = cutil.find_definition(text, name)
    if not span:
        die('%s is not defined' % name)
    a, z = span
    return text[:a] + edit(text[a:z]) + text[z:]


HOW = {'always': cutil.fold_always, 'never': cutil.fold_never, 'drop': cutil.drop_if}


def fold(text, fn, how, pattern, what, n=1):
    """A counted cutil fold, SCOPED TO ONE DEFINITION."""
    def edit(s):
        try:
            return HOW[how](s, pattern, n, re.M)
        except ValueError as e:
            die('%s -- %s' % (what, e))
    out = in_function(text, fn, edit)
    say(what)
    return out


# ---- 0. the shape every anchor below was counted against --------------------------
BEFORE = {'scriptin': 8, 'curscript': 11, 'NSCRIPT': 3, 'saved_typebuf': 2,
          'closescript': 3, 'using_script': 3, 'script_char': 6, 'retesc': 3,
          'redir_fd': 6, 'redir_off': 7, 'redir_write': 7, 'redirecting': 4,
          'did_return': 3,
          'vim_fsync': 3, 'ui_write': 3, 'mch_write': 2, 'FILE': 2,
          'may_sync_undo': 3, 'is_safe_now': 3, 'free_typebuf': 5,
          'read_cmd_fd': 12}         # the terminal's, and untouched
for name, want in sorted(BEFORE.items()):
    k = mentions(t, name)
    if k != want:
        die('%s has %d mentions, expected %d -- the anchors below were counted '
            'against a different file' % (name, k, want))
say('scriptin 8, redir_fd 6, redirecting 4, ui_write 3, FILE 2 -- the file the six '
    'anchors were counted against')

# ---- THE INVARIANT, COMPUTED BEFORE ANYTHING IS FOLDED ------------------------------
# Every fold below rests on the two FILE* being NULL for ever, so the assignments are
# counted rather than asserted in prose.  scriptin[] is written in exactly one place,
# and that place sets it to NULL; redir_fd is written only by its own declaration.
# Anything else would make every fold a guess.
script_writes = re.findall(r'\bscriptin\s*\[[^\]]*\]\s*=[^=][^;\n]*;', t)
if script_writes != ['scriptin[curscript] = NULL;']:
    die('scriptin[] is assigned %d times and not once to NULL alone: %s'
        % (len(script_writes), ' | '.join(w[:60] for w in script_writes)))
redir_writes = re.findall(r'^[ \t]*(?:static\s+FILE\s*\*\s*)?redir_fd\s*=[^=][^;]*;$',
                          t, re.M)
if redir_writes != ['static FILE *redir_fd  = NULL ;']:
    die('redir_fd is assigned %d times and not once by its declaration alone: %s'
        % (len(redir_writes), ' | '.join(w.strip()[:60] for w in redir_writes)))
calls = re.findall(r'^[ \t]*ui_write\([^;\n]*\);$', t, re.M)
if calls != ['    ui_write(out_buf, len, FALSE);']:
    die('ui_write has %d call sites and not the one that passes FALSE: %s'
        % (len(calls), ' | '.join(c.strip()[:60] for c in calls)))
say('scriptin[] is assigned ONCE in the whole file, to NULL, inside closescript(); '
    "redir_fd only by its own declaration; ui_write() has ONE call and it passes "
    'FALSE.  That, and nothing weaker, is why every fold below may take a constant -- '
    'and it is also the whole claim of the phase: neither FILE* has ever been opened '
    'in any build of zero-vim')

# ---- A. scriptin[] is NULL for ever --------------------------------------------------
# A1  may_sync_undo: `scriptin[curscript] == NULL` is TRUE, so the conjunct goes and
#     THE FUNCTION SURVIVES -- u_sync() still runs on the test that is left.
t = text_edit(t,
              '    if ((!(State & (MODE_INSERT | MODE_CMDLINE)) || arrow_used) && scriptin[curscript] == NULL)\n',
              '    if (!(State & (MODE_INSERT | MODE_CMDLINE)) || arrow_used)\n',
              'may_sync_undo: `scriptin[curscript] == NULL` is TRUE, so the conjunct '
              'goes -- the function SURVIVES and u_sync() still runs on the rest')

# A2  is_safe_now: one line of a return expression, same constant.  Survives too.
t = text_edit(t, '        && scriptin[curscript] == NULL\n', '',
              'is_safe_now: the same conjunct, and the same survival -- '
              'stuff_empty() && typebuf.tb_len == 0 && !global_busy is what is left')

# A3  using_script() is FALSE at both call sites, and the sweep then takes it.
t = text_edit(t, ' && !using_script()', '',
              'nv_visual: `!using_script()` is TRUE, so the conjunct goes')
t = text_edit(t, ' || using_script()', '',
              'skip_showmode: `using_script()` is FALSE, so the disjunct goes -- and '
              'that was its last caller')

# A4  inchar()'s script reader, as text, with its local.  THIS IS THE ANCHOR THAT
#     TAKES closescript(), and fclose and getc with it.
t = text_edit(t,
              '    script_char = -1;\n'
              '    while (scriptin[curscript] != NULL && script_char < 0)\n'
              '    {\n'
              '        if (got_int || (script_char = getc(scriptin[curscript])) < 0)\n'
              '        {\n'
              '            closescript();\n'
              '            if (got_int)\n'
              '            {\n'
              '                retesc = TRUE;\n'
              '            }\n'
              '            else\n'
              '            {\n'
              '                return -1;\n'
              '            }\n'
              '        }\n'
              '        else\n'
              '        {\n'
              '            buf[0] = script_char;\n'
              '            len = 1;\n'
              '        }\n'
              '    }\n'
              '\n', '',
              "inchar()'s script reader: the loop needs `scriptin[curscript] != NULL`, "
              'which is FALSE, so it never ran -- and it was closescript()\'s only '
              'caller and getc()\'s')
# `retesc` IS READ AND NEVER WRITTEN AFTER A4, which draws no warning and which
# tools/deadsweep.py does not act on.  Leaving it means inchar() returns an
# uninitialised value on a path the compiler thinks exists.
if mentions(t, 'retesc') != 2:
    die('retesc has %d mentions after the loop went, expected 2 -- its declaration '
        'and its one read' % mentions(t, 'retesc'))
t = text_edit(t, '            return retesc;\n', '            return FALSE;\n',
              'inchar: `retesc` is read and never written now -- no warning covers '
              'that, and the value it would return is uninitialised, so the read '
              'becomes the FALSE it was initialised to')
t = text_edit(t, '    int         retesc = FALSE;\n', '',
              'and its declaration goes with it')

t = text_edit(t, '    int         script_char;\n', '',
              'and the script_char local itself, which nothing writes now')

# `script_char` is now written nowhere and read once, so the test is TRUE and folds.
# IT IS FOLDED LAST, after the two locals above: fold_always dedents the body it
# keeps, and `return retesc;` sits inside it -- a rewrite counted against the
# original indentation would refuse afterwards, which is what it did the first time.
t = fold(t, 'inchar', 'always', r'^    if \(script_char < 0\)$',
         'inchar: `script_char < 0` is TRUE for ever now, so the whole rest of the '
         'function is what runs -- the body is dedented one level')

# ---- B. redir_fd is NULL for ever -----------------------------------------------------
# redirecting() is `return redir_fd != NULL;`, so it is FALSE always and folds at both
# call sites.  THE TWO PATTERNS DIFFER ONLY IN INDENTATION, and that is deliberate: a
# single pattern with a count of two would fold two different shapes with one rule.
t = fold(t, 'undo_cmdmod', 'never', r'^        if \(redirecting\(\)\)$',
         "undo_cmdmod: `redirecting()` is FALSE, so unwinding :silent never resets "
         'msg_col for a redirection that is not happening')
t = fold(t, 'redir_write', 'never', r'^    if \(redirecting\(\)\)$',
         'redir_write: the same constant takes the whole body -- the fputs() and '
         "putc() block, which is putc's only caller and fputs's only NAMED one")
if mentions(t, 'redirecting') != 2:
    die('redirecting has %d mentions after both callers were folded, expected 2 -- '
        'its prototype and its definition, for the sweep' % mentions(t, 'redirecting'))

# ---- the recommended extra: the no-op that is left -------------------------------------
# redir_write() is now `{ char_u *s = str; static int cur_col = 0; if (redir_off)
# return; }`: the sweep takes the two variables and leaves a function with five
# callers that cannot do anything.  Leaving a function that cannot do anything is the
# "concept the table has and the code does not" whim's Phase 18 argued against.
t = cutil.drop_if(t, r'^    if \(!did_return\)$', 1, re.M)
say("msg_end's `if (!did_return)` block, which held one of the five calls: dropping "
    'the call alone would leave an `if` with an empty body, which is not something '
    'any tool here removes')
t = text_edit(t, '                    redir_write(p, -1);\n', '',
              "emsg_core's two calls that echoed the error's source line", 2)
t = text_edit(t, '                redir_write((char_u *)s, -1);\n', '',
              "emsg_core's call that echoed the message itself")
t = text_edit(t, '    redir_write((char_u *)str, maxlen);\n', '',
              "msg_puts_attr_len's call, which was every message the editor prints")
t = text_edit(t, 'static void redir_write(char_u *s, int maxlen);\n', '',
              "redir_write's prototype")
t, removed = cutil.delete_definition(t, 'redir_write')
if not removed:
    die('redir_write has no definition to remove')
if mentions(t, 'redir_write'):
    die('redir_write still has %d mentions' % mentions(t, 'redir_write'))
say('redir_write itself, which could no longer do anything: five call sites and the '
    'definition')

# `did_return` is now written once and read never, and `redir_off` written five times
# and read never.  A local draws -Wunused-but-set-variable, which the sweep may act
# on; a FILE-SCOPE static draws NOTHING AT ALL -- that is phase 10's `readonlymode`
# in this phase's shape -- so both go here rather than being left to a tool.
t = text_edit(t, '    int         did_return = FALSE;\n', '',
              "msg_end's `did_return`, written once and read never now")
t = text_edit(t, '        did_return = TRUE;\n', '', 'and its one write')
writes = re.findall(r'^[ \t]*redir_off = (?:TRUE|FALSE);\n', t, re.M)
if len(writes) != 5:
    die('redir_off has %d writes, expected 5 -- a phase written from a description '
        'of four would leave one behind' % len(writes))
t = re.sub(r'^[ \t]*redir_off = (?:TRUE|FALSE);\n', '', t, flags=re.M)
t = text_edit(t, 'static int  redir_off  = FALSE ;\n', '',
              'and redir_off: FIVE writes, not four, and no reader at all -- a '
              'file-scope static that is assigned and never read draws no warning, '
              'and tools/deadsweep.py acts on warnings')
if mentions(t, 'redir_off') or mentions(t, 'did_return'):
    die('redir_off or did_return survives')

# ---- C. ui_write's console -------------------------------------------------------------
# The one call passes FALSE, so the vim_fsync(1) it guards can never be entered.  The
# PARAMETER goes with it: tools/sweep.sh compiles with -Wno-unused-parameter, so an
# unused parameter is invisible where an unused local is not, and leaving
# __attribute__((unused)) on something that will never be read again is what phase 2
# argued against for check_tty(void).
t = text_edit(t, 'static void ui_write(char_u *s, int len, int console);\n',
              'static void ui_write(char_u *s, int len);\n',
              "ui_write's prototype loses the console parameter")
t = text_edit(t,
              "ui_write(char_u *s, int len, int console  __attribute__((unused)) )\n"
              '{\n'
              '\n'
              '    mch_write(s, len);\n'
              "    if (console && s[len - 1] == '\\n')\n"
              '    {\n'
              '        vim_fsync(1);\n'
              '    }\n'
              '\n'
              '}\n',
              'ui_write(char_u *s, int len)\n'
              '{\n'
              '    mch_write(s, len);\n'
              '}\n',
              'and the definition: `console` is FALSE at the one call site, so the '
              'vim_fsync(1) it guarded can never be entered, and ui_write is '
              'mch_write now -- which is what takes vim_fsync() and fsync()')
t = text_edit(t, '    ui_write(out_buf, len, FALSE);\n', '    ui_write(out_buf, len);\n',
              'and its one call site, which already passed FALSE')

# ---- what the sweep is handed, as a count rather than as trust -------------------------
AFTER = {'redirecting': 2,        # prototype and definition
         'closescript': 2,        # the same
         'vim_fsync': 2,          # the same
         'using_script': 1,       # its DEFINITION alone: it never had a prototype
         'redir_write': 0, 'redir_off': 0, 'did_return': 0, 'retesc': 0,
         'script_char': 0,
         'scriptin': 4, 'curscript': 7,   # what is left is inside the three above
         'may_sync_undo': 3, 'is_safe_now': 3,   # BOTH SURVIVE, folded
         'ui_write': 3, 'mch_write': 2,
         'read_cmd_fd': 12}
for name, want in sorted(AFTER.items()):
    k = mentions(t, name)
    if k != want:
        die('%s has %d mentions after the cut, expected %d' % (name, k, want))
say('the cut is done: redirecting, closescript and vim_fsync at two mentions each '
    '-- a prototype and a definition -- and using_script at ONE, its definition '
    'alone, having never had a prototype; scriptin 4 and curscript 7, every one of '
    'them inside a function the sweep now reads as unreachable; may_sync_undo and '
    "is_safe_now SURVIVING at three; and read_cmd_fd 12, still the terminal's")

open(path, 'w', errors='surrogateescape').write(t)
PY

# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  nofile       the input binary did not build with '$cflags' '$ldflags'"; exit 1; }
echo "  nofile       the input is $state/old, $(stat -c%s "$state/old") bytes, beside the source it was built from: nothing this phase removes is reachable, so the check instruments THAT source at five places and requires zero markers, with a control that must fire"

# tools/phaserun.sh sweeps next, then runs pipes/zero13-check.sh.
