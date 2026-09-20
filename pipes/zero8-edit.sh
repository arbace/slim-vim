#!/bin/sh
# Zero phase 8 -- the editor loses every way to name something else to edit.
# See ZERO-GOAL.md.
#
# Usage: pipes/zero8-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# Phases 6 and 7 took the commands that put bytes on a disk and the one that takes
# them off it.  This one takes the commands that point the editor AT a file --
# `:edit :enew :ex :visual :view` -- and the four Normal-mode keys that do the same
# thing from the buffer's own text, `gf gF [f ]f`.  What is left of opening
# anything is `readfile()` and `open_buffer()`, which the startup path still uses
# and which are the "nothing reads a byte" phase's (ZERO-PLAN.md P8); this phase
# asserts by count that both are untouched.
#
# WHAT THE FIVE COMMANDS ACTUALLY WERE, measured on the input binary in a directory
# holding a file called `keys`: `do_exedit` is thirty lines -- a lock guard, a
# `readonlymode` save/set/restore testing CMD_view and CMD_enew, `setpcmark()` and
# one `do_ecmd()` call.  So `:ex` and `:visual` are `:edit` spelled differently
# (their Ex-mode escape has had nothing to escape from since phase 4), `:view` is
# `:edit` with `'readonly'` set, and `:enew` is `:edit` with a NULL file name.  One
# handler, `ex_edit`, is all five rows, which is why they go together.
#
# SIX ANCHORS, and everything else is the sweep's (ZERO-GOAL.md rule 1: removal is
# computed, not listed).  Sixteen functions go without one of them being named
# here, seventeen with anchor 6:
#
#   1. five enumerators of `enum CMD_index`, one line each;
#   2. five `cmdnames[]` rows, one physical line each, designated `[CMD_x] = {`;
#   3. `do_one_cmd`'s `curbuf_locked()` exemption, which names `CMD_edit` in a
#      conjunct -- `CMD_file` STAYS, being the `:file` phase's.  It must go in the
#      same edit as anchor 1 or nothing declares what it reads, and it is the one
#      anchor outside the table and the keys: an edit shaped like the table forgets
#      it, and the build is what catches that.
#   4. `nv_g_cmd`'s `case 'f': case 'F': nv_gotofile(cap); break;` arm.  `gf` and
#      `gF` fall to `default: clearopbeep` with the rest of the unused `g` keys.
#   5. `nv_brackets`'s `if (cap->nchar == 'f') { nv_gotofile(cap); } else { ... }`,
#      where the else is the whole rest of the function.  `[f` and `]f` fall into
#      the chain that ends in `clearopbeep`.
#   6. `do_one_cmd`'s `if (ea.argt & EX_ARGOPT) { while (... getargopt(&ea) ...) }`.
#
# NO `nv_cmds[]` ROW IS TOUCHED, and that is the hazard this phase does not have.
# There is no row for `gf`, `gF`, `[f` or `]f`: they are arms inside two handlers
# whose `g`, `[` and `]` rows dispatch dozens of other keys, so nothing is deleted
# from the table and nothing renumbers.  The check presses fifty of those keys on
# both binaries and requires exactly four to move.
#
# ANCHOR 5 IS NOT A `cutil.fold_never`, AND THE REASON IS INDENTATION.  fold_never
# keeps an `else` body by dedenting it four columns, which is right when the body
# was written one level in.  This one was not: upstream's `else` here has no braces
# at all (the `if` is inside `#ifdef FEAT_SEARCHPATH`), so slim's bracing pass put
# a `{`/`}` round the rest of the function and left every line at the function's
# own four columns.  Dedenting would put forty lines at column zero and no tool
# here would ever say so -- CLAUDE.md's "one thing no tier can see".  So the head
# and the matching closer are deleted as counted text, by brace matching, and the
# body keeps the indentation it already had.
#
# ANCHOR 6 IS WORTH ITS LINES, and it is measured rather than argued.  `EX_ARGOPT`
# -- `++ff=`, `++enc=`, `++bin`, `++edit` -- was on five rows: `:read`, which phase
# 7 took, and these four.  After anchor 2 it is on NONE, so the block can never be
# entered, `getargopt()` can never run, and `exarg_T.read_edit` is written by
# nothing and read by nothing.  Deleting the block hands all three to the sweep.
# Measured: 30 lines, one more function, and a recording BYTE-IDENTICAL to the one
# the five anchors alone produce -- `++edit` was only ever accepted by the commands
# this phase removes, so there is nothing to declare.
#
# `EX_CMDARG` REACHES ZERO ROWS TOO AND IS LEFT ALONE, deliberately.  Its two
# fields are `do_ecmd_cmd`, which after this phase has four mentions and no writer,
# and `do_ecmd_lnum`, which has two -- and `do_ecmd_lnum` is written through
# `eval_vars()`, which is the buffer-name phase's.  Folding round that is that
# phase's to do; this one names the counts so that a later widening has to move
# them.
#
# `'undoreload'` STAYS, AND THE ROW IS NOT THIS PHASE'S.  `p_ur` has three mentions
# -- the declaration, one reader inside `do_ecmd` and the option row -- and after
# this phase two and no reader.  Removing the row would change what `:set ur?`
# answers, which nothing here sweeps, so the delta could not be checked; and
# ``orphanopts`` refuses the opposite direction, a global whose row has
# gone.  The check asserts `p_ur` at exactly 2 with its row intact, and the
# manifest carries `uses options:11 files:8 mechanical` for the phase that takes it.
#
# THE ROW FLOOR IS CROSSED HERE, AND THE FLOOR MOVES IN THIS COMMIT.  `cmdnames[]`
# goes 104 -> 99 and create_cmdidxs's `names()` refused a table of fewer than 100 --
# not with "too few rows" but with `no command table found in either shape`, because
# names() tries both parsers with check=False and neither answer clears the bar.
# `zexcmds` enumerates zero's whole Ex sweep through names(), so the old
# floor would have stopped the sweep, tools/zerodelta.sh, the recording and every
# later phase's check rather than giving a wrong answer.  ZERO-PLAN.md decision 8:
# lowered deliberately, to 80, in the phase that crosses it and in the same commit,
# with the reason in the tool's own docstring.  The margin is 19 rows and the next
# row the plan removes is `:file`'s.
#
# THE TEXT THIS EDIT LEAVES DOES NOT COMPILE, as phases 6 and 7 leave theirs, and
# the invariant at the end is the honest form of that, computed rather than listed:
# every surviving mention of a deleted enumerator is inside a function definition,
# and no surviving `cmdnames[]` row names that function -- which is the whole
# argument that funcreach.py takes it in the sweep's first round.
# tools/phasecheck.sh in pipes/zero8-check.sh is where "it compiles" is asserted.
#
# NO HANDLER IS DELETED BY NAME.  The row is the only reference a command handler
# has, so taking the five rows is what makes `ex_edit` unreachable, and `do_exedit`,
# `do_ecmd` and thirteen more follow it.  The check records the sixteen as a
# measurement of what the sweep did.
#
# THE INPUT BINARY IS BUILT HERE, before the edit, from the boundary's own makefile
# flags, exactly as pipes/zero2-edit.sh, zero4-edit.sh, zero5-edit.sh, zero6-edit.sh
# and zero7-edit.sh do it.  THE CORPUS SEES TWO CASES OF THIS PHASE and neither of
# them opens a file: `cmd_edit` types `:edit` with no file name and `key_gf` presses
# `gf` on a word that names nothing.  The only evidence that this phase removed
# opening a file rather than two error messages is a probe that requires the OLD
# binary to pull one off the disk, and that needs the old binary.  The source goes
# with it, as $state/old.c, for the before-and-after counts the check takes.
set -eu

work=${1:?usage: zero8-edit.sh <work-dir> <state-dir>}
state=${2:?usage: zero8-edit.sh <work-dir> <state-dir>}
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
TAG = 'noedit'
import re, sys
sys.path.insert(0, 'tools')
# tools/create_cmdidxs.py -- named as a PATH so tools/implhash.sh hashes it into this
# phase's key.  implhash greps for paths and an `import` names a module, so
# without this line an edit to it changes what this phase produces and moves
# no key at all.  See CLAUDE.md on cutil.py and macros.py.  Do not delete it.
import create_cmdidxs
# tools/cutil.py -- named as a PATH so tools/implhash.sh hashes it into this
# phase's key.  implhash greps for paths and an `import` names a module, so
# without this line an edit to it changes what this phase produces and moves
# no key at all.  See CLAUDE.md on cutil.py and macros.py.  Do not delete it.
import cutil
# tools/funcreach.py -- named as a PATH so tools/implhash.sh hashes it into this
# phase's key.  implhash greps for paths and an `import` names a module, so
# without this line an edit to it changes what this phase produces and moves
# no key at all.  See CLAUDE.md on cutil.py and macros.py.  Do not delete it.
import funcreach
path = sys.argv[1]
t = open(path, errors='surrogateescape').read()

ROWS_BEFORE, ROWS_AFTER, FLOOR = 104, 99, 80
GOING = ('CMD_edit', 'CMD_enew', 'CMD_ex', 'CMD_visual', 'CMD_view')


def die(msg):
    sys.exit('  %-12s %s' % (TAG, msg))


def say(what):
    print('  %-12s %s' % (TAG, what))


def rows(text):
    return re.findall(r'^    \[CMD_\w+\] = \{.*$', text, re.M)


def mentions(text, name):
    return len(re.findall(r'\b%s\b' % name, text))


def in_function(text, name, edit):
    span = cutil.find_definition(text, name)
    if not span:
        die('%s is not defined' % name)
    a, z = span
    return text[:a] + edit(text[a:z]) + text[z:]


def within(text, fn, old, new, what, n=1):
    """Replace exact text inside one function, counted there and not file-wide."""
    def edit(s):
        k = s.count(old)
        if k != n:
            die('%s -- %r occurs %d times in %s, expected %d'
                % (what, old[:60], k, fn, n))
        return s.replace(old, new)
    out = in_function(text, fn, edit)
    say(what)
    return out


# ---- 0. the shape the anchors below were counted on -------------------------------
n = len(rows(t))
if n != ROWS_BEFORE:
    die('cmdnames[] has %d rows, expected %d -- the anchors below were counted '
        'against a different table' % (n, ROWS_BEFORE))
if len(create_cmdidxs.names(path)) != ROWS_BEFORE:
    die('create_cmdidxs names() does not read %d rows out of this table' % ROWS_BEFORE)
BEFORE = {'CMD_edit': 3, 'CMD_enew': 4, 'CMD_ex': 2, 'CMD_view': 3, 'CMD_visual': 2,
          'ex_edit': 6, 'do_exedit': 3, 'nv_gotofile': 3,
          'EX_ARGOPT': 6, 'getargopt': 3, 'read_edit': 2,
          'readfile': 5, 'open_buffer': 6, 'p_ur': 4}
for name, want in sorted(BEFORE.items()):
    k = mentions(t, name)
    if k != want:
        die('%s has %d mentions, expected %d -- the anchors below were counted '
            'against a different file' % (name, k, want))
# EX_ARGOPT's five rows are what anchor 6 rests on: four here and `:read`'s, which
# phase 7 took.  Counted, so that a row arriving would refuse rather than leave a
# reachable block with no way in.
argopt_rows = [r for r in rows(t) if 'EX_ARGOPT' in r]
if len(argopt_rows) != 4:
    die('EX_ARGOPT is on %d cmdnames[] rows, expected the 4 this phase removes'
        % len(argopt_rows))
say('cmdnames[] %d rows, ex_edit on 5 of them, EX_ARGOPT on 4, readfile 5 and '
    'open_buffer 6 -- the line against the byte-reader phase' % ROWS_BEFORE)

# ---- 1. the five enumerators ------------------------------------------------------
# Their values are positions in cmdnames[], which is designated, so the survivors
# after them renumber and the table follows -- see pipes/zero8-check.sh for the
# DWARF dump that requires every non-CMD_ name to hold its value anyway.
for e in GOING:
    line = '    %s,\n' % e
    if t.count(line) != 1:
        die('the %s enumerator is not one line of its own' % e)
    t = t.replace(line, '')
say('five enumerators of enum CMD_index: %s' % ' '.join(GOING))

# ---- 2. the five cmdnames[] rows --------------------------------------------------
# The row is the only reference a command handler has, which is what makes ex_edit
# and the fifteen functions under it the sweep's and not this program's.
for e in GOING:
    m = re.search(r'^    \[%s\] = \{.*\n' % e, t, re.M)
    if not m:
        die('cmdnames[] has no [%s] row' % e)
    t = t[:m.start()] + t[m.end():]
n = len(rows(t))
if n != ROWS_AFTER:
    die('cmdnames[] has %d rows after the cut, expected %d' % (n, ROWS_AFTER))
say('the five cmdnames[] rows; %d -> %d, which is under the floor create_cmdidxs '
    "names() had -- lowered to %d in this phase's own commit (ZERO-PLAN.md "
    'decision 8), so the margin is %d rows'
    % (ROWS_BEFORE, ROWS_AFTER, FLOOR, ROWS_AFTER - FLOOR))

# ---- 3. do_one_cmd's curbuf_locked() exemption ------------------------------------
# The one anchor outside the table and the keys.  CMD_file stays: `:file` is the
# buffer-name phase's, and it is exempt here for the same reason `:edit` was.
t = within(t, 'do_one_cmd', 'ea.cmdidx != CMD_edit && ', '',
           'do_one_cmd no longer exempts :edit from the curbuf_locked() refusal, '
           'and :file still is')

# ---- 4. nv_g_cmd's gf and gF ------------------------------------------------------
# `case 'f':` alone occurs six times in this function; the four-line block occurs
# once.  Both keys fall to `default: clearopbeep`, where every other unused g key is.
t = within(t, 'nv_g_cmd', """    case 'f':
    case 'F':
        nv_gotofile(cap);
        break;

""", '', "nv_g_cmd's `gf` and `gF` arm")

# ---- 5. nv_brackets's [f and ]f ---------------------------------------------------
# Deleted as counted text and not folded, because the else body is already at the
# function's own indentation -- see the head of this file.  The closer is found by
# brace matching and required to be a line of its own, so a differently shaped else
# refuses instead of eating the wrong block.
HEAD = """    if (cap->nchar == 'f')
    {
        nv_gotofile(cap);
    }
    else
    {
"""


def cut_brackets(s):
    k = s.count(HEAD)
    if k != 1:
        die('nv_brackets: the `[f` head occurs %d times, expected 1' % k)
    i = s.index(HEAD)
    o = i + len(HEAD) - 2           # the else's `{`
    if s[o] != '{':
        die('nv_brackets: the else does not open where this phase expects it')
    c = cutil.match(s, o, cutil.blank(s))
    if c < 0:
        die("nv_brackets: the else's block does not close")
    a = s.rfind('\n', 0, c) + 1
    z = s.index('\n', c) + 1
    if s[a:z] != '    }\n':
        die('nv_brackets: the else closes with %r, not a line of its own' % s[a:z])
    return s[:i] + s[i + len(HEAD):a] + s[z:]


t = in_function(t, 'nv_brackets', cut_brackets)
say("nv_brackets's `[f` and `]f` arm, keeping the else that is the rest of the "
    'function at the indentation it already had')

# ---- 6. do_one_cmd's ++opt parse --------------------------------------------------
# EX_ARGOPT is on no row after anchor 2, so this block can never be entered.
# Deleting it is what makes getargopt() unreachable and exarg_T.read_edit a field
# nothing names -- both the sweep's, neither named here.
t = within(t, 'do_one_cmd', """    if (ea.argt & EX_ARGOPT)
    {
        while (ea.arg[0] == '+' && ea.arg[1] == '+')
        {
            if (getargopt(&ea) == FAIL)
            {
                errormsg = _(e_invalid_argument);
                goto doend;
            }
        }
    }

""", '', 'do_one_cmd no longer parses `++opt`: EX_ARGOPT is on no row, so '
         'getargopt() is unreachable and read_edit is written by nothing')

# ---- 7. what is left, and why it does not compile yet -----------------------------
# Every surviving mention of a deleted enumerator is inside a function definition,
# and no surviving cmdnames[] row names that function -- which is the whole argument
# that the sweep takes it.  Stated as a computation rather than as a list of handlers.
blanked = cutil.blank(t)
defs = funcreach.definitions(t, blanked)
spans = sorted((a, z, name) for name, (a, z) in defs.items())
left, holders = 0, {}
for e in GOING:
    for m in re.finditer(r'\b%s\b' % e, t):
        left += 1
        who = [name for a, z, name in spans if a <= m.start() < z]
        if not who:
            die('%s is still named at file scope, at offset %d -- this phase only '
                'knows the shape where what is left is inside a function'
                % (e, m.start()))
        holders.setdefault(who[-1], set()).add(e)
survivors = rows(t)
for fn in sorted(holders):
    if any(re.search(r'\b%s\b' % fn, r) for r in survivors):
        die('%s still has a cmdnames[] row, so it is not the sweep\'s to take' % fn)
say('%d mention%s of %s left, inside %s, and no surviving row names it: the text '
    'does not compile until the sweep has run, and tools/phasecheck.sh is where '
    'that is asserted'
    % (left, '' if left == 1 else 's',
       ' and '.join(sorted(set().union(*holders.values()))), ', '.join(sorted(holders))))

open(path, 'w', errors='surrogateescape').write(t)
PY

# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  noedit       the input binary did not build with '$cflags' '$ldflags'"; exit 1; }
echo "  noedit       the input is $state/old, $(stat -c%s "$state/old") bytes, beside the source it was built from: the corpus only sees :edit with no file name and gf on a word that names nothing, so the probes need a binary that still opens one"

# tools/phaserun.sh sweeps next, then runs pipes/zero8-check.sh.
