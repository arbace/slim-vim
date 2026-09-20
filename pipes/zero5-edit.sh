#!/bin/sh
# Zero phase 5 -- the command line is `+{command}` and `-T {term}`.  See ZERO-GOAL.md.
#
# Usage: pipes/zero5-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# A core is handed its buffer by a host, not by a shell.  What is left of
# `command_line_scan()` after phases 2 and 4 is five things -- `+cmd`, `-T`, a bare
# `-`, `--` and a file argument -- and the last three are the three that name a
# FILE or a STREAM to edit.  They go, and argv ends as exactly two options: the
# commands to run and the terminal to assume.  Everything else is what every other
# unknown word already was, `mainerr(ME_UNKNOWN_OPTION)`.
#
# WHAT GOES, in the parser:
#   * the file-argument branch -- the `else` arm: the ME_TOO_MANY_ARGS guard,
#     `parmp->edit_type = EDIT_FILE`, the `vim_strsave()` and the `buflist_add()`
#     that put the name in the buffer list.  The arm is REPLACED by
#     `mainerr(ME_UNKNOWN_OPTION)` rather than deleted: with no arm at all a bare
#     word matches neither `+` nor `-`, `argv[0][argv_idx]` is not NUL, and the
#     `while` never advances -- an infinite loop, not an error.
#   * `case NUL`, the bare `-`: EDIT_STDIN, `read_cmd_fd = 2` and its own
#     ME_TOO_MANY_ARGS guard.  It falls to `default:`, so `-` is an unknown option.
#   * `case '-'`, which is where `--` ended the options, with `had_minmin` and the
#     two `&& !had_minmin` tests that read it.  `--foo` already went to
#     ME_UNKNOWN_OPTION from inside that case and goes there from `default:` now;
#     what changes is `--` itself, which used to mean "every word after this is a
#     file name" and now means nothing.
#   * `ME_TOO_MANY_ARGS`, whose two call sites were exactly those two branches, and
#     its row in `main_errors[]`.
#
# THE ENUMERATOR IS THE ROW INDEX, so the two go together and the survivors
# renumber: `main_errors[n]` is what `mainerr(n)` prints, ME_ARG_MISSING moves 2->1,
# ME_GARBAGE 3->2 and ME_EXTRA_CMD 4->3.  That is the renumbering CLAUDE.md warns
# about, done deliberately -- the table and the enum are edited from one parse of
# both, and pipes/zero5-check.sh compares the DWARF enumerator values of the binary
# this phase was handed with the ones it made and requires exactly those three to
# have moved.  The dump of the input is taken HERE, in the background, because after
# the edit there is nothing left to dump it from.
#
# `main_errors[]` has SIX rows and had five enumerators; the sixth, "Invalid
# argument for", is unreachable already and was before this phase -- nothing names
# index 5.  It is whim's leftover, not this phase's, and it stays: this phase
# removes the row an enumerator it removes points at, and nothing else.
#
# WHAT `params.edit_type` THEN IS.  Nothing assigns it, so it is EDIT_NONE for
# ever, and its two readers in vim_main2() fold: `== EDIT_STDIN` never, which takes
# `read_stdin()`'s only call with it, and `!= EDIT_STDIN` always, which keeps
# `newline_on_exit` under the two conditions that were already there.  The field,
# the three EDIT_* enumerators, `read_stdin()` and `buflist_add()` are then what the
# sweep takes -- tools/deadfields.py for the field (there is no ml_recover() in this
# file, so a struct is no longer a disk format), deadenums.py for the three
# single-constant enums, each with an explicit value so nothing renumbers, and
# deadsweep.py for the two functions and whatever they orphan.
#
# WHERE THE LINE IS AGAINST THE LATER PHASES, and why it is there:
#   * `readfile()`'s stdin half -- its `read_stdin` PARAMETER and the arms that read
#     it, in readfile(), read_buffer() and open_buffer() -- is the "nothing reads a
#     byte" phase's (ZERO-PLAN.md P8).  This phase removes the FUNCTION
#     `read_stdin()`, which is argv's entry point into that code; the parameter's 23
#     mentions are asserted UNCHANGED, so a phase that took them here would fail.
#   * `read_cmd_fd` keeps its definition and its twelve remaining mentions.  Nothing assigns it
#     now, so it is 0 for ever and folding it is the stdin phase's; a file-scope
#     static that is read and never written draws no warning, so the sweep will not
#     touch it either way.  Only the assignment was argv's.
#   * the buffer's NAME is the "buffer has no name" phase's (P9).  Nothing here
#     touches `b_ffname`, `b_sfname` or `b_fname`: what goes is the one call that
#     ever gave the startup buffer a name from argv.  `create_windows()` already
#     opens an unnamed buffer when argv named none -- that is the `(none)` row of
#     `zargv` -- so the startup path is the one that was always there.
#
# WHAT IS KEPT, and asserted by name in the check: `+{command}` with MAX_ARG_CMDS
# and ME_EXTRA_CMD; `-T {term}` with want_argument, ME_GARBAGE and
# mainerr_arg_missing; ME_UNKNOWN_OPTION as the answer to everything else;
# `exe_commands()` and the `+cmd` execution path; and `'paste'`, which every case of
# the corpus seeds itself with (ZERO-PLAN.md 2d).
#
# THERE IS NO usage() TO LEAVE ALONE.  The brief warns that the help text may still
# advertise options that no longer exist; in this file it does not exist either --
# `grep -i usage zero-vim.c` finds nothing, whim having removed it, and `--help` is
# already `Unknown option argument: "--help"` in .reference/zero-baselines/
# ref-argv.txt.  Nothing here prints a list of options to keep true.
#
# THE INPUT BINARY IS BUILT HERE, before the edit, from the boundary's own makefile
# flags, exactly as pipes/zero2-edit.sh and pipes/zero4-edit.sh do it: the check
# requires the OLD binary to open the file and the new one to refuse, which is the
# difference between a probe and a formality.
set -eu

work=${1:?usage: zero5-edit.sh <work-dir> <state-dir>}
state=${2:?usage: zero5-edit.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"

# The flags are read out of the boundary's makefile rather than written here a
# second time: zero's compile line is the boundary's (ZERO-GOAL.md rule 8).
cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")
cp "$f" "$state/old.c"
# shellcheck disable=SC2086
( cd "$state" && gcc $cflags $ldflags -o old old.c ) &
pid_old=$!

# The enumerator values of the text this phase is HANDED.  It has to be taken
# before the edit, and it is the left-hand side of the check's renumbering proof.
tools/enumvals.sh "$f" "$state/enums-before" &
pid_enums=$!

python3 - "$f" <<'PY'
TAG = 'noargv'
import re, sys
sys.path.insert(0, 'tools')
# tools/cutil.py -- named as a PATH so tools/implhash.sh hashes it into this
# phase's key.  implhash greps for paths and an `import` names a module, so
# without this line an edit to it changes what this phase produces and moves
# no key at all.  See CLAUDE.md on cutil.py and macros.py.  Do not delete it.
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


def in_function(text, name, edit):
    span = cutil.find_definition(text, name)
    if not span:
        die('%s is not defined' % name)
    a, z = span
    return text[:a] + edit(text[a:z]) + text[z:]


def fold(kind, fn, pattern, what, n=1):
    """A counted fold inside one function, its polarity stated by the caller."""
    def edit(s):
        try:
            f = cutil.fold_always if kind == 'always' else cutil.fold_never
            return f(s, pattern, n, re.M)
        except ValueError as e:
            die('%s -- %s' % (what, e))
    out = in_function(text_of[0], fn, edit)
    say(what)
    return out


def within(fn, old, new, what=None, n=1):
    """Replace exact text inside one function, counted there and not file-wide."""
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


text_of = [t]


def do(new):
    text_of[0] = new


# ---- 0. the invariants the cut rests on -------------------------------------------
# Every identifier this phase removes, at the mentions it has before it, plus the
# ones it must NOT move: `read_stdin` as a parameter (23 of its 26 mentions belong
# to the phase that stops reading bytes) and the five kept ME_* / MAX_ARG_CMDS.
BEFORE = {'had_minmin': 4, 'edit_type': 7, 'EDIT_NONE': 3, 'EDIT_FILE': 2,
          'EDIT_STDIN': 4, 'ME_TOO_MANY_ARGS': 3, 'buflist_add': 3,
          'read_stdin': 26, 'read_cmd_fd': 13, 'ME_UNKNOWN_OPTION': 3,
          'ME_ARG_MISSING': 2, 'ME_GARBAGE': 2, 'ME_EXTRA_CMD': 2,
          'MAX_ARG_CMDS': 4, 'want_argument': 4, 'mainerr_arg_missing': 3,
          'exe_commands': 3}
for name, want in sorted(BEFORE.items()):
    k = mentions(t, name)
    if k != want:
        die('%s has %d mentions, expected %d -- the anchors below were counted '
            'against a different file' % (name, k, want))
say('17 identifiers at their counted mentions: had_minmin 4, edit_type 7, '
    'read_stdin 26 (23 of them a parameter)')

# ---- 1. the parser: three ways to name a file or a stream --------------------------
# A bare word is an unknown option, which is what every other unrecognised argument
# already is.  THE ARM IS REPLACED, NOT DELETED: with neither `+` nor `-` matching
# and no else, argv_idx stays 1, `argv[0][1]` is not NUL for any word longer than
# one character, and the loop never advances.
do(within('command_line_scan', """        else
        {
            argv_idx = -1;

            if (parmp->edit_type != EDIT_NONE)
            {
                mainerr(ME_TOO_MANY_ARGS, (char_u *)argv[0]);
            }
            parmp->edit_type = EDIT_FILE;

            if ((p = vim_strsave((char_u *)argv[0])) == NULL)
            {
                mch_exit(2);
            }

            (void)buflist_add(p, BLN_CURBUF | BLN_LISTED);

        }
""", """        else
        {
            mainerr(ME_UNKNOWN_OPTION, (char_u *)argv[0]);
        }
""", 'a file argument is an unknown option: buflist_add loses its only caller'))
do(within('command_line_scan', '\n    char_u      *p = NULL;\n', '\n',
          'and `p`, which only that arm used'))

# `-` alone: the editor took stdin over as a buffer and moved its keyboard to fd 2.
do(within('command_line_scan', """            case NUL:
                if (parmp->edit_type != EDIT_NONE)
                {
                    mainerr(ME_TOO_MANY_ARGS, (char_u *)argv[0]);
                }
                parmp->edit_type = EDIT_STDIN;
                read_cmd_fd = 2;
                argv_idx = -1;
                break;

""", '', 'a bare `-` is an unknown option: EDIT_STDIN and read_cmd_fd = 2 go'))

# `--`: after it every word was a file name, which there is no longer such a thing
# as.  `--foo` reached ME_UNKNOWN_OPTION from inside this case and reaches it from
# `default:` now; only `--` itself changes.
do(within('command_line_scan', """            case '-':
                if (argv[0][argv_idx])
                {
                    mainerr(ME_UNKNOWN_OPTION, (char_u *)argv[0]);
                }
                had_minmin = TRUE;
                argv_idx = -1;
                break;

""", '', '`--` no longer ends the options'))
do(within('command_line_scan', '\n    int         had_minmin = FALSE;\n', '\n',
          'and had_minmin, the flag it set'))
do(within('command_line_scan', "if (argv[0][0] == '+' && !had_minmin)",
          "if (argv[0][0] == '+')", 'so +cmd is +cmd wherever it appears'))
do(within('command_line_scan', "else if (argv[0][0] == '-' && !had_minmin)",
          "else if (argv[0][0] == '-')", 'and an option is an option'))

# ---- 2. ME_TOO_MANY_ARGS, and the row it indexes -----------------------------------
# One parse of both lists, and the edit is computed from it: the enumerators are
# main_errors[]'s indices, so the two cannot be edited separately without the
# numbering being a guess.  The sixth row is named and kept, because it is already
# unreachable and is not this phase's.
t = text_of[0]
GONE = 'ME_TOO_MANY_ARGS'
enums = re.search(r'(?:^enum \{ ME_\w+ = \d+ \};\n)+', t, re.M)
if not enums:
    die('the ME_* enumerators are not a run of `enum { NAME = N };` lines')
pairs = re.findall(r'^enum \{ (ME_\w+) = (\d+) \};$', enums.group(0), re.M)
if [int(v) for _, v in pairs] != list(range(len(pairs))):
    die('the ME_* enumerators are not 0..%d in order: %r' % (len(pairs) - 1, pairs))
table = re.search(r'^static char \*\(main_errors\[\]\) =\n\{\n(.*?)^\};\n', t, re.M | re.S)
if not table:
    die('main_errors[] is not where it was')
rows = table.group(1).splitlines(keepends=True)
if len(rows) != len(pairs) + 1:
    die('main_errors[] has %d rows for %d enumerators; this phase only knows the '
        'shape where the one extra row is the unreachable one whim left'
        % (len(rows), len(pairs)))
names = [n for n, _ in pairs]
if GONE not in names:
    die('%s is not among the ME_* enumerators' % GONE)
i = names.index(GONE)
if 'Too many edit arguments' not in rows[i]:
    die('main_errors[%d] is %r, which is not %s\'s row' % (i, rows[i].strip(), GONE))
kept = [n for n in names if n != GONE]
do(t.replace(enums.group(0),
             ''.join('enum { %s = %d };\n' % (n, k) for k, n in enumerate(kept)))
    .replace(table.group(0),
             'static char *(main_errors[]) =\n{\n%s};\n'
             % ''.join(r for k, r in enumerate(rows) if k != i)))
say('%s and its row go; %s' % (GONE, ', '.join(
    '%s %d->%d' % (n, names.index(n), k) for k, n in enumerate(kept) if names.index(n) != k)))
say('main_errors[] keeps its sixth row, %s, which no enumerator named before this '
    'phase either' % rows[-1].strip().rstrip(',').strip())

# ---- 3. what params.edit_type is once nothing assigns it ---------------------------
# EDIT_NONE, for ever.  Its two readers are in one function and their polarity is
# opposite, so each is stated rather than found.
do(fold('never', 'vim_main2', line('if (params.edit_type == EDIT_STDIN)'),
        'vim_main2 no longer reads a buffer from stdin: read_stdin loses its call'))
do(within('vim_main2', ' && params.edit_type != EDIT_STDIN)', ')',
          'and sets newline_on_exit on the two conditions that are left'))

# ---- 4. what is left is exactly what the sweep can take -----------------------------
# Each name is down to its definition, and each definition is a kind tools/sweep.sh
# deletes: a struct field nothing outside a type names (deadfields.py), an
# enumerator nothing names (deadenums.py -- three single-constant enums, each with
# an explicit value, so nothing renumbers), a function nothing calls (deadsweep.py,
# then funcreach.py) and its prototype (deadprotos.py).  Stated as a number per
# name, so a use that survived shows up here and not as a warning five minutes
# later.  pipes/zero5-check.sh requires 0 of all six after the sweep.
AFTER = {'had_minmin': 0, 'edit_type': 1, 'EDIT_NONE': 1, 'EDIT_FILE': 1,
         'EDIT_STDIN': 1, 'ME_TOO_MANY_ARGS': 0, 'buflist_add': 2,
         'read_stdin': 25, 'read_cmd_fd': 12, 'ME_UNKNOWN_OPTION': 3,
         'ME_ARG_MISSING': 2, 'ME_GARBAGE': 2, 'ME_EXTRA_CMD': 2,
         'MAX_ARG_CMDS': 4, 'want_argument': 4, 'mainerr_arg_missing': 3,
         'exe_commands': 3}
t = text_of[0]
for name, want in sorted(AFTER.items()):
    k = mentions(t, name)
    if k != want:
        die('%s has %d mentions after the cut, expected %d -- %s'
            % (name, k, want, 'a use survived' if k > want else 'more went than was meant to'))
if 'Too many edit arguments' in t:
    die("'Too many edit arguments' survives the edit")
say('every use of the six is gone; the field, three enumerators, read_stdin and '
    'buflist_add are what the sweep takes')

open(path, 'w', errors='surrogateescape').write(t)
PY

# NOT create_cmdidxs --check, for pipes/zero2-edit.sh's reason: the derived
# first-two-letters index went with the command table whim reduced, and the tool
# raises rather than reporting nothing.  Nothing here touches the command table.
#
# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  noargv       the input binary did not build with '$cflags' '$ldflags'"; exit 1; }
wait $pid_enums || { echo "  noargv       the input's enumerator values could not be dumped"; exit 1; }
echo "  noargv       the input is $state/old, $(stat -c%s "$state/old") bytes, and $(grep -c '' "$state/enums-before") enumerator values, for the check's before-and-after"

# tools/phaserun.sh sweeps next, then runs pipes/zero5-check.sh.
