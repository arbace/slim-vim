#!/bin/sh
# Zero phase 7 -- the editor loses every way to read a file.  See ZERO-GOAL.md.
#
# Usage: pipes/zero7-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# The other half of taking the filesystem away.  Phase 6 removed the six commands
# that put bytes on a disk; this one removes the command that takes them off it,
# `:read`, and with it the `:r !cmd` arm -- the last caller of the filter and shell
# plumbing whim left as stubs.  What remains of reading a file is `readfile()`
# itself, which the startup path still uses and which is the "nothing reads a byte"
# phase's (ZERO-PLAN.md P8); this phase asserts that it is untouched, by count.
#
# THREE ANCHORS, AND ONE FOLD THAT IS A JUDGEMENT.  Everything else is the sweep's
# (ZERO-GOAL.md rule 1: removal is computed, not listed), and six functions go
# without one of them being named here:
#
#   1. the `CMD_read` enumerator of `enum CMD_index`, one line;
#   2. the `cmdnames[]` row, one physical line, designated `[CMD_read] = {`;
#   3. `do_one_cmd`'s `if (ea.cmdidx == CMD_read) {...}` -- the parse that turns
#      `:r!` and `:r !cmd` into a filter -- deleted as TEXT rather than folded,
#      because its condition names the enumerator that is going.  It must go in the
#      same edit as anchor 1 or nothing declares what it reads.
#
# THE JUDGEMENT: `exarg_T.usefilter`.  Phase 6 removed one of its two writers
# (`:w >>` and `:w !cmd`) and anchor 3 removes the other, so after this edit the
# field is WRITTEN NOWHERE -- and `do_one_cmd` memsets the struct, so every reader
# is constantly FALSE.  No tool here can see that: tools/deadfields.py removes a
# field nothing NAMES, and gcc has no warning for a struct member that is only
# read.  So the six readers are folded by hand and the field goes with them, which
# is phase 4's argument for `exmode_active` in a smaller shape.  Measured on this
# input: folding costs 13 lines and gives a BYTE-IDENTICAL recording -- the fold
# changes no behaviour at all, it removes a test whose answer was already fixed.
#
# The alternative, leaving the field, was measured too and is a worse tree for the
# same 209 lines: `usefilter` would survive as a member nothing writes, seven tests
# of it would survive as dead branches, and the next phase to read this file would
# have to work out for itself that they can never be taken.
#
# THE TEXT THIS EDIT LEAVES DOES NOT COMPILE, and that is stated here because
# nothing else would say it.  One mention of `usefilter` survives the cut, in
# `ex_read` -- the function whose only reference was the row that just went -- and
# the field it names is gone.  The invariant at the end is the honest form of that,
# computed rather than listed: every surviving mention is inside a function
# definition, and no surviving `cmdnames[]` row names that function, which is the
# whole argument that funcreach.py takes it in the sweep's first round.
# tools/phasecheck.sh in pipes/zero7-check.sh is where "it compiles" is asserted.
#
# NO HANDLER IS DELETED BY NAME.  The row is the only reference a command handler
# has, so taking the row is what makes `ex_read` unreachable, and `do_bang`,
# `do_shell`, `do_filter`, `check_secure` and `prevcmd_is_set` follow it -- `:!` has
# not existed since whim, and phase 6 swept `ex_write`, which held `do_bang`'s other
# call (`:w !cmd`).  The check records the six as a measurement of what the sweep
# did.
#
# THE ROW FLOOR.  `cmdnames[]` goes 105 -> 104 rows, and create_cmdidxs's `names()`
# refuses a table of fewer than 100 -- a regex that stops matching otherwise yields
# a plausible all-zero index, so the floor is deliberate.  tools/zexcmds.py
# enumerates the table through it, so crossing the floor would stop zero's command
# sweep rather than give a wrong answer.  After this phase the margin is FOUR rows,
# and ZERO-PLAN.md 3a gives it to the `:edit` phase, which must lower the floor.
#
# NO ENUMERATOR DUMP, for phase 6's reason.  Deleting one renumbers 46 survivors and
# every one is a `CMD_*`: `cmdnames[]` is DESIGNATED, so a row lands at its own
# enumerator whatever the numbering is, the `static_assert` on the row count catches
# a dropped pair, and all 104 surviving names are dispatched by tools/zexcmds.py
# inside the declared delta.  There is no derived first-two-letters index in this
# file -- whim's Phase 80 took it with the 489 stub rows -- so nothing else depends
# on a position.
#
# THE INPUT BINARY IS BUILT HERE, before the edit, from the boundary's own makefile
# flags, exactly as pipes/zero2-edit.sh, zero4-edit.sh, zero5-edit.sh and
# zero6-edit.sh do it.  THE CORPUS CANNOT SEE THAT A FILE WAS READ: every one of
# tools/zcases.py's 102 cases types its own text and names no file, so `cmd_read`
# types `:read` with no file name and has only ever recorded `E32: No file name`.
# The only evidence that this phase removed reading rather than one error message is
# a probe that requires the OLD binary to pull a file off the disk, and that needs
# the old binary.  The source goes with it, as $state/old.c, for the before-and-
# after counts the check takes.
set -eu

work=${1:?usage: zero7-edit.sh <work-dir> <state-dir>}
state=${2:?usage: zero7-edit.sh <work-dir> <state-dir>}
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
TAG = 'noread'
import re, sys
sys.path.insert(0, 'tools')
import create_cmdidxs
import cutil
import funcreach
path = sys.argv[1]
t = open(path, errors='surrogateescape').read()

ROWS_BEFORE, ROWS_AFTER, FLOOR = 105, 104, 100
# The names whose survivors are the reason the text does not compile yet.
DYING = ('CMD_read', 'usefilter')


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


def within_struct(text, tag, old, new, what, n=1):
    """The same, inside one struct body: cutil.find_definition is functions only."""
    m = re.search(r'^struct %s\n\{\n' % re.escape(tag), text, re.M)
    if not m:
        die('struct %s is not defined where this phase expects it' % tag)
    o = text.index('{', m.start())
    c = cutil.match(text, o)
    if c < 0:
        die('struct %s does not close' % tag)
    body = text[o:c + 1]
    k = body.count(old)
    if k != n:
        die('%s -- %r occurs %d times in struct %s, expected %d'
            % (what, old[:60], k, tag, n))
    say(what)
    return text[:o] + body.replace(old, new) + text[c + 1:]


# ---- 0. the table and the field, at the shape the anchors were counted on ---------
n = len(rows(t))
if n != ROWS_BEFORE:
    die('cmdnames[] has %d rows, expected %d -- the anchors below were counted '
        'against a different table' % (n, ROWS_BEFORE))
if len(create_cmdidxs.names(path)) != ROWS_BEFORE:
    die('create_cmdidxs names() does not read %d rows out of this table' % ROWS_BEFORE)
BEFORE = {'CMD_read': 3, 'usefilter': 10, 'ex_read': 2, 'readfile': 7,
          'read_buffer': 17, 'open_buffer': 6}
for name, want in sorted(BEFORE.items()):
    k = mentions(t, name)
    if k != want:
        die('%s has %d mentions, expected %d -- the anchors below were counted '
            'against a different file' % (name, k, want))
writes = len(re.findall(r'\busefilter\s*=', t))
if writes != 2:
    die('usefilter is assigned %d times, expected the 2 that anchor 3 removes -- '
        'phase 6 took the other two with `:w >>` and `:w !cmd`' % writes)
say('cmdnames[] 105 rows, CMD_read 3 mentions, usefilter 10 -- the field, the two '
    'writes anchor 3 removes and seven reads')

# ---- 1. the CMD_read enumerator ---------------------------------------------------
# Its value is a position in cmdnames[], which is designated, so the 46 survivors
# after it renumber and the table follows -- see the head of this file for why that
# needs no DWARF dump.
if t.count('    CMD_read,\n') != 1:
    die('the CMD_read enumerator is not one line of its own')
t = t.replace('    CMD_read,\n', '')
say('the CMD_read enumerator of enum CMD_index')

# ---- 2. the cmdnames[] row --------------------------------------------------------
# The row is the only reference a command handler has, which is what makes ex_read
# and the five functions under it the sweep's and not this program's.
m = re.search(r'^    \[CMD_read\] = \{.*\n', t, re.M)
if not m:
    die('cmdnames[] has no [CMD_read] row')
t = t[:m.start()] + t[m.end():]
n = len(rows(t))
if n != ROWS_AFTER:
    die('cmdnames[] has %d rows after the cut, expected %d' % (n, ROWS_AFTER))
say('the cmdnames[] row; %d -> %d, and create_cmdidxs names() refuses under %d, so '
    'the margin is %d rows -- the :edit phase spends it (ZERO-PLAN.md 3a)'
    % (ROWS_BEFORE, ROWS_AFTER, FLOOR, ROWS_AFTER - FLOOR))

# ---- 3. do_one_cmd's `:r!` and `:r !cmd` parse ------------------------------------
# Deleted as text rather than folded: the condition names the enumerator that has
# just gone, so there is nothing left to fold against.  It has no else.
t = within(t, 'do_one_cmd', """    if (ea.cmdidx == CMD_read)
    {
        if (ea.forceit)
        {
            ea.usefilter = TRUE;
            ea.forceit = FALSE;
        }
        else if (*ea.arg == '!')
        {
            ++ea.arg;
            ea.usefilter = TRUE;
        }
    }

""", '', 'do_one_cmd no longer parses `:r!` or `:r !cmd`: usefilter loses its last '
       'two writes')

# ---- 4. the field nothing writes any more, and its seven readers ------------------
# THE JUDGEMENT OF THIS PHASE, and the one thing here no tool could have found: a
# struct member that is read and never written draws no warning, and deadfields.py
# removes only a member nothing names.  do_one_cmd memsets `ea`, so every test below
# is constantly FALSE and each is folded with its polarity stated.
if re.search(r'\busefilter\s*=', t):
    die('usefilter is still assigned after anchor 3, so the fold below would be wrong')
t = within(t, 'do_one_cmd', '(ea.argt & EX_CMDARG) && !ea.usefilter',
           'ea.argt & EX_CMDARG',
           'EX_CMDARG takes its argument command whatever the (dead) filter flag said')
t = within(t, 'do_one_cmd', '(ea.argt & EX_TRLBAR) && !ea.usefilter',
           'ea.argt & EX_TRLBAR',
           'and EX_TRLBAR separates a trailing command')
t = within(t, 'do_one_cmd', ' || ea.usefilter)', ')',
           'and only :global and :vglobal keep a backslash-newline in their argument')
t = within(t, 'expand_filename', 'if (!eap->usefilter && !escaped)', 'if (!escaped)',
           'expand_filename escapes a replacement unless it was escaped already')
t = in_function(t, 'expand_filename', lambda s: cutil.fold_never(
    s, r'^[ \t]*if \(eap->usefilter &&.*\)$', 1, re.M))
say('and no longer escapes `!` for a shell, which only a filter needed')
t = within(t, 'expand_filename', '(eap->argt & EX_NOSPC) && !eap->usefilter',
           'eap->argt & EX_NOSPC',
           'and EX_NOSPC refuses a second file name whatever it said')
t = within_struct(t, 'exarg', '    int         usefilter;\n', '',
                  'the exarg field itself, written by nothing since anchor 3')

# ---- 5. what is left, and why it does not compile yet -----------------------------
# Every surviving mention of the two names is inside a function definition, and no
# surviving cmdnames[] row names that function -- which is the whole argument that
# the sweep takes it.  Stated as a computation rather than as a list of handlers.
blanked = cutil.blank(t)
defs = funcreach.definitions(t, blanked)
spans = sorted((a, z, name) for name, (a, z) in defs.items())
left, holders = 0, {}
for e in DYING:
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
    % (left, '' if left == 1 else 's', ' and '.join(DYING), ', '.join(sorted(holders))))

open(path, 'w', errors='surrogateescape').write(t)
PY

# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  noread       the input binary did not build with '$cflags' '$ldflags'"; exit 1; }
echo "  noread       the input is $state/old, $(stat -c%s "$state/old") bytes, beside the source it was built from: the corpus cannot see a file being read, so the probes need a binary that still reads one"

# tools/phaserun.sh sweeps next, then runs pipes/zero7-check.sh.
