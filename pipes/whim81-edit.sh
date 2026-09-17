#!/bin/sh
# Whim phase 81 -- one line, one command.  See WHIM-GOAL.md.
#
# Usage: pipes/whim81-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# An Ex line could hold several commands separated by `|`, and end in a `"`
# comment.  Both existed for scripts -- a vimrc, a sourced file, a function body --
# and this editor reads none: every command it runs was typed, came from `+cmd`, or
# came from a mapping's right-hand side.  So a line is one command now, and `|` and
# `"` are ordinary characters in its argument.
#
# THE MACHINERY IS SMALL AND IN ONE PLACE.  separate_nextcmd() split a bar-splitting
# (EX_TRLBAR) command's argument at the first unescaped `|`, `"` or newline;
# check_nextcmd(), find_nextcmd(), ends_excmd() and ends_excmd2() each knew the same
# three characters; and a handful of callers knew them again -- :substitute's tail,
# the trailing-characters check in do_one_cmd, :append's `:a|text`, `:|` printing the
# line, and the whole-line `:" comment`.
#
# A NEWLINE STILL ENDS A COMMAND.  "One line, one command" is exactly that rule, and
# the newline branch of separate_nextcmd is kept as it was, backslash and all.
#
# DECIDED BEFORE THIS WAS WRITTEN, and each is probed below:
#   `a|b`      the bar is argument text.  A command without EX_EXTRA reports E488
#              trailing characters; one with it takes the bar as part of its argument.
#   `a " x`    the quote is argument text too, so a trailing comment is an error or
#              an argument, and `:" x` is E492.
#   `\|`       means nothing special: the backslash stays, so `:map Q A\|b` maps to
#              `A\|b` where it used to map to `A|b`.  `\"` likewise.  CTRL-V handling
#              is unchanged.
#
# KEPT, deliberately: EX_NOTRLCOM.  Its comment meaning is gone, but it still decides
# whether separate_nextcmd strips trailing spaces, and that is what lets a mapping's
# right-hand side end in a space.  Behaviour, not comment syntax, so it stays.
#
# THE DELTA.  No behaviour case, no terminal row and no swept command uses a bar or a
# comment, so the cumulative list is phase 80's unchanged.  What moves is probed
# directly: a corpus of lines through the q80 binary and this one, with the lines
# expected to differ written out, and everything else required identical.
set -eu

work=${1:?usage: whim81-edit.sh <work-dir> <state-dir>}
state=${2:?usage: whim81-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

cp "$f" "$state/old.c"
(cd "$state" && gcc -O0 -static -s -w -o old old.c) &
pid_old=$!

python3 - "$f" <<'PY'
TAG = 'onecommand'
import re, sys
sys.path.insert(0, 'tools')
import cutil
path = sys.argv[1]
t = open(path, errors='surrogateescape').read()

def die(msg):
    sys.exit('  %-12s %s' % (TAG, msg))

def say(what):
    print('  %-12s %s' % (TAG, what))

def fold_never(text, pattern, what, n=1):
    try:
        out = cutil.fold_never(text, pattern, n, re.M)
    except ValueError as e:
        die('%s -- %s' % (what, e))
    say(what)
    return out

def fold_always(text, pattern, what, n=1):
    try:
        out = cutil.fold_always(text, pattern, n, re.M)
    except ValueError as e:
        die('%s -- %s' % (what, e))
    say(what)
    return out

def drop_if(text, pattern, what, n=1):
    try:
        out = cutil.drop_if(text, pattern, n, re.M)
    except ValueError as e:
        die('%s -- %s' % (what, e))
    say(what)
    return out

def term(text, frag, repl, what, n=1):
    k = text.count(frag)
    if k != n:
        die('%s -- the fragment occurs %d times, expected %d' % (what, k, n))
    say(what)
    return text.replace(frag, repl)

def lines(text, pattern, what, n=1):
    rx = re.compile(r'^[ \t]*' + pattern + r'[ \t]*\n', re.M)
    k = len(rx.findall(text))
    if k != n:
        die('%s -- %d lines match, expected %d' % (what, k, n))
    say(what)
    return rx.sub('', text)

# ---- 1: the invariants the folds rest on -------------------------------------------
# separate_nextcmd has exactly one caller, and it passes FALSE for keep_backslash.
calls = re.findall(r'\bseparate_nextcmd\(([^;]*)\);', t)
calls = [c for c in calls if not c.startswith('exarg_T')]
if calls != ['&ea, FALSE']:
    die('separate_nextcmd is called as %r, expected once with FALSE' % calls)
# :append, :insert and :change take no EX_EXTRA, so `:a|text` can no longer reach
# ex_append with a bar at the start of its argument: do_one_cmd refuses it first.
for c in ('append', 'insert', 'change'):
    m = re.search(r'^    \[CMD_%s\] = \{.*\(long_u\)\(([^)]*)\)' % c, t, re.M)
    if not m or 'EX_EXTRA' in m.group(1):
        die(':%s is not a command without EX_EXTRA' % c)
say('confirmed: one caller of separate_nextcmd, and :append, :insert, :change take no argument')

# ---- 2: the splitter ---------------------------------------------------------------
t = term(t, '''        else if ((*p == '"' && !(eap->argt & EX_NOTRLCOM) && ((eap->cmdidx != CMD_at && eap->cmdidx != CMD_star) || p != eap->arg)) || (*p == '|' && eap->cmdidx != CMD_append && eap->cmdidx != CMD_change && eap->cmdidx != CMD_insert) || *p == '\\n')''',
         '''        else if (*p == '\\n')''', 'separate_nextcmd splits at a newline and nothing else')
t = term(t, 'if ((eap->argt & (EX_CTRLV | EX_XFILE)) || keep_backslash)',
         'if (eap->argt & (EX_CTRLV | EX_XFILE))', 'its one caller never keeps a backslash')
t = fold_always(t, r'^[ \t]*if \(!keep_backslash\)$', 'so a backslash before a newline always goes')

t = term(t, '''    int comment_char = '"';

    return (c == NUL || c == '|' || c == comment_char || c == '\\n');''',
         '''    return (c == NUL || c == '\\n');''', 'ends_excmd: the end of the line')
t = term(t, '''    if (c == NUL || c == '|' || c == '\\n')
    {
        return TRUE;
    }
    return c == '"';''', '''    return (c == NUL || c == '\\n');''', 'ends_excmd2: the same')
t = term(t, "    while (*p != '|' && *p != '\\n')\n", "    while (*p != '\\n')\n", 'find_nextcmd: the next line')
t = term(t, "    if (*s == '|' || *s == '\\n')\n", "    if (*s == '\\n')\n", 'check_nextcmd: the same')

# ---- 3: the callers that knew the characters themselves ----------------------------
t = term(t, "if (!(ea.argt & EX_EXTRA) && *ea.arg != NUL && *ea.arg != '\"' && (*ea.arg != '|' || (ea.argt & EX_TRLBAR) == 0))",
         'if (!(ea.argt & EX_EXTRA) && *ea.arg != NUL)', 'a bar or a quote after a command is trailing characters')
t = term(t, "if (*ea.cmd == NUL || comment_start(ea.cmd, starts_with_colon) || (ea.nextcmd = check_nextcmd(ea.cmd)) != NULL)",
         'if (*ea.cmd == NUL || (ea.nextcmd = check_nextcmd(ea.cmd)) != NULL)', 'a line that is a comment is not empty')
t = lines(t, r'int         starts_with_colon = FALSE;', 'do_one_cmd no longer asks where the colon was')
t = drop_if(t, r'^[ \t]*if \(comment_start\(eap->cmd, starts_with_colon\)\)$', 'the modifier parser skips no comment')
t = drop_if(t, r"^[ \t]*if \(\*eap->cmd == ':'\)$", 'and records no colon')
t = lines(t, r'int     starts_with_colon = FALSE;', 'nor keeps the flag')
t = term(t, "if ((*eap->cmd == '|' || (exmode_active && eap->cmd != (char_u *)exmode_plus + 1)))",
         'if (exmode_active && eap->cmd != (char_u *)exmode_plus + 1)', '`:|` no longer prints the line')
t = term(t, "    if (*cmd && *cmd != '\"')\n    {\n        set_nextcmd(eap, cmd);",
         "    if (*cmd)\n    {\n        set_nextcmd(eap, cmd);", ':substitute takes no trailing comment')
t = fold_never(t, r"^[ \t]*if \(\*eap->arg == '\|'\)$", ':append takes no text after a bar')

for pat, what in ((r"'\|'", 'a bar'), (r"'\"'", 'a quote')):
    for fn in ('separate_nextcmd', 'ends_excmd', 'ends_excmd2', 'find_nextcmd', 'check_nextcmd', 'do_one_cmd'):
        sp = cutil.find_definition(t, fn)
        if not sp:
            die('%s is not defined' % fn)
        if re.search(pat, t[sp[0]:sp[1]]):
            die('%s still tests for %s' % (fn, what))
if 'comment_start(' in t.replace('comment_start(char_u', ''):
    die('comment_start still has a caller')
say('no command parser tests for a bar or a quote')

open(path, 'w', errors='surrogateescape').write(t)
PY

wait $pid_old

# tools/phaserun.sh sweeps next, then runs pipes/whim81-check.sh.
