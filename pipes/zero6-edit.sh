#!/bin/sh
# Zero phase 6 -- the editor loses every way to write a file.  See ZERO-GOAL.md.
#
# Usage: pipes/zero6-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# A core does not own a disk.  Reading and writing files is the host's business
# (ZERO-GOAL.md, the charter), and this is the first half of taking the filesystem
# away: the six Ex commands that put bytes on a disk -- `:write :wq :xit :exit
# :update :saveas` -- and, with them, everything only they reached.
#
# FOUR ANCHORS, AND NOT ONE FOLD.  Everything else is the sweep's (ZERO-GOAL.md
# rule 1: removal is computed, not listed).  The alternative was measured: an edit
# that also deletes `ex_write`, `ex_update`, `ex_exit`, `do_write`, `check_writable`,
# `check_overwrite`, `not_writing` and `check_readonly` by name produces a
# BYTE-IDENTICAL swept file, in 3 rounds against 4 and 17 seconds against 22.  So
# the eight names are not written here: the table row is the only reference a
# command handler has, and taking the row is what makes the handler unreachable.
#
#   1. the six enumerators of `enum CMD_index`, one line each;
#   2. the six `cmdnames[]` rows, one physical line each, designated `[CMD_x] = {`;
#   3. `nv_Zet`'s `ZZ`, which runs the string "x": `do_cmdline_cmd("x")` -> "q!";
#   4. `do_one_cmd`'s `:w>>` / `:w!` parse, an `if (ea.cmdidx == CMD_write ||
#      ea.cmdidx == CMD_update) {...}` with no else -- deleted as TEXT rather than
#      folded, because its condition names two enumerators that are going.  It must
#      go in the same edit as anchor 1 or nothing declares what it reads.
#
# `ZZ` BECOMES `q!`, WHICH IS A DECISION AND NOT A CONSEQUENCE.  `nv_Zet` runs a
# command STRING, so nothing here breaks at compile time: left alone, `ZZ` would
# type `:x` at a command that no longer exists and answer E492.  The user's settled
# decision is that ZZ is ZQ, and `case:zz_key` moves either way -- E32 today, E492
# if the string is left, nothing at all with `q!` -- so this phase owns it and says
# so rather than leaving a dead command named in the source.  ZERO-PLAN.md gives it
# to the `:q` phase; that row is annotated as built.
#
# THE TEXT THIS EDIT LEAVES DOES NOT COMPILE, and that is stated here because
# nothing else would say it.  Six mentions of the six enumerators survive the cut --
# `CMD_saveas` five times and `CMD_wq` once -- every one of them inside `ex_write`,
# `do_write` or `ex_exit`, which are exactly the functions whose only reference was
# the row that just went.  `funcreach.py` deletes them in the sweep's first round,
# and `tools/phasecheck.sh` in pipes/zero6-check.sh is where "it compiles" is
# asserted.  The invariant below is the honest form of that: every surviving mention
# is inside a function definition, and no surviving `cmdnames[]` row names that
# function.
#
# THE ROW FLOOR.  `cmdnames[]` goes 111 -> 105 rows, and
# `tools/create_cmdidxs.py`'s `names()` REFUSES a table of fewer than 100 -- a regex
# that stops matching otherwise yields a plausible all-zero index, so the floor is
# deliberate.  ``zexcmds`` enumerates the table through it, so crossing the
# floor would stop zero's command sweep rather than give a wrong answer.  After this
# phase the margin is FIVE ROWS.  ZERO-PLAN.md 3a: the `:edit` phase is the one that
# spends it, and it is the phase that must lower the floor.
#
# NO ENUMERATOR DUMP HERE, and phase 5 had one for a reason that does not apply.
# Deleting the six renumbers 89 survivors, all of them `CMD_*` -- measured with
# tools/enumvals.sh: 1,323 enumerator values in, 1,303 out, 20 gone (the six plus
# fourteen single-constant explicit-value enums the sweep takes with their types),
# 89 moved and every one a command index.  Phase 5's `main_errors[]` was a table
# indexed by the enumerators it removed, with the rows written in order, so a wrong
# index was invisible to the build and DWARF was the only witness.  `cmdnames[]` is
# DESIGNATED: a row lands at its own enumerator whatever the numbering is, the
# `static_assert` on the row count catches a dropped pair, and every one of the 105
# names is dispatched by `zexcmds` in the declared delta.  Three checks the
# build cannot dodge, and none of them needs the values.
#
# NOT tools/create_cmdidxs.py --check, for pipes/zero2-edit.sh's reason: the derived
# first-two-letters index went with the table whim reduced, and the tool raises
# rather than reporting nothing.  Its `names()` is called, which is the part that
# still means something here.
#
# THE INPUT BINARY IS BUILT HERE, before the edit, from the boundary's own makefile
# flags, exactly as pipes/zero2-edit.sh, zero4-edit.sh and zero5-edit.sh do it.  It
# is not decoration: THE CORPUS CANNOT SEE WRITING.  ``zcases``'s `cmd_write`
# types `:write` with no file name and has only ever recorded `E32: No file name`,
# so every screen the baselines hold is of an editor that failed to write.  The only
# evidence that this phase removed writing rather than one error message is a probe
# that requires the OLD binary to leave a file on the disk, and that needs the old
# binary.  The source goes with it, as $state/old.c, for the before-and-after counts
# the check takes.
set -eu

work=${1:?usage: zero6-edit.sh <work-dir> <state-dir>}
state=${2:?usage: zero6-edit.sh <work-dir> <state-dir>}
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
TAG = 'nowrite'
import re, sys
sys.path.insert(0, 'tools')
import create_cmdidxs
import cutil
import funcreach
path = sys.argv[1]
t = open(path, errors='surrogateescape').read()

# The six commands, and nothing else: every other name in `cmdnames[]` stays.
SIX = ('CMD_exit', 'CMD_saveas', 'CMD_update', 'CMD_write', 'CMD_wq', 'CMD_xit')
ROWS_BEFORE, ROWS_AFTER, FLOOR = 111, 105, 100


def die(msg):
    sys.exit('  %-12s %s' % (TAG, msg))


def say(what):
    print('  %-12s %s' % (TAG, what))


def rows(text):
    return re.findall(r'^    \[CMD_\w+\] = \{.*$', text, re.M)


def literal(text, old, new, what, n=1):
    k = text.count(old)
    if k != n:
        die('%s -- %r occurs %d times, expected %d' % (what, old[:50], k, n))
    return text.replace(old, new)


def within(text, fn, old, new, what, n=1):
    """Replace exact text inside one function, counted there and not file-wide."""
    span = cutil.find_definition(text, fn)
    if not span:
        die('%s is not defined' % fn)
    a, z = span
    body = text[a:z]
    k = body.count(old)
    if k != n:
        die('%s -- %r occurs %d times in %s, expected %d'
            % (what, old[:50], k, fn, n))
    return text[:a] + body.replace(old, new) + text[z:]


# ---- 0. the table this phase edits, at the shape the anchors were counted on -----
n = len(rows(t))
if n != ROWS_BEFORE:
    die('cmdnames[] has %d rows, expected %d -- the anchors below were counted '
        'against a different table' % (n, ROWS_BEFORE))
if len(create_cmdidxs.names(path)) != ROWS_BEFORE:
    die('create_cmdidxs.names() does not read %d rows out of this table' % ROWS_BEFORE)

# ---- 1. the six enumerators of enum CMD_index ------------------------------------
# One line each, in the run that numbers the commands.  Their values are positions
# in cmdnames[], which is designated, so the 89 survivors after them renumber and
# the table follows -- see the head of this file for why that needs no DWARF dump.
for e in SIX:
    t = literal(t, '    %s,\n' % e, '', 'the %s enumerator' % e)
say('six enumerators of enum CMD_index: %s' % ' '.join(s[4:] for s in SIX))

# ---- 2. the six cmdnames[] rows ---------------------------------------------------
# The row is the only reference a command handler has, which is what makes the
# handlers the sweep's and not this program's.
for e in SIX:
    m = re.search(r'^    \[%s\] = \{.*\n' % e, t, re.M)
    if not m:
        die('cmdnames[] has no [%s] row' % e)
    t = t[:m.start()] + t[m.end():]
n = len(rows(t))
if n != ROWS_AFTER:
    die('cmdnames[] has %d rows after the cut, expected %d' % (n, ROWS_AFTER))
say('six cmdnames[] rows; %d -> %d, and create_cmdidxs.names() refuses under %d, '
    'so the margin is %d rows -- the :edit phase spends it (ZERO-PLAN.md 3a)'
    % (ROWS_BEFORE, ROWS_AFTER, FLOOR, ROWS_AFTER - FLOOR))

# ---- 3. ZZ ------------------------------------------------------------------------
# A decision, not a consequence: see the head of this file.  It is scoped to nv_Zet,
# because "q!" is already there as ZQ's and a file-wide count would be two.
t = within(t, 'nv_Zet', 'do_cmdline_cmd((char_u *)"x");',
           'do_cmdline_cmd((char_u *)"q!");',
           'ZZ is ZQ: nv_Zet runs "q!" where it ran "x"')
say('ZZ is ZQ: nv_Zet runs the string "q!" where it ran "x", which is this '
    'phase\'s decision and moves case:zz_key')

# ---- 4. do_one_cmd's :w>> and :w! parse -------------------------------------------
# Deleted as text rather than folded: the condition names two enumerators that have
# just gone, so there is nothing left to fold against.  It has no else.
t = within(t, 'do_one_cmd', """    if (ea.cmdidx == CMD_write || ea.cmdidx == CMD_update)
    {
        if (*ea.arg == '>')
        {
            if (*++ea.arg != '>')
            {
                errormsg = _(e_use_w_or_w_gt_gt);
                goto doend;
            }
            ea.arg = skipwhite(ea.arg + 1);
            ea.append = TRUE;
        }
        else if (*ea.arg == '!' && ea.cmdidx == CMD_write)
        {
            ++ea.arg;
            ea.usefilter = TRUE;
        }
    }

""", '', 'do_one_cmd no longer parses `:w >>file` or `:w !cmd`')
say('do_one_cmd\'s `:w>>` and `:w!` parse, deleted as text: its condition named '
    'two of the enumerators above')

# ---- 5. what is left, and why it does not compile yet -----------------------------
# Every surviving mention of the six is inside a function definition, and no
# surviving cmdnames[] row names that function -- which is the whole argument that
# the sweep takes them.  Stated as a computation rather than as a list of handlers.
blanked = cutil.blank(t)
defs = funcreach.definitions(t, blanked)
spans = sorted((a, z, name) for name, (a, z) in defs.items())
left, holders = 0, {}
for e in SIX:
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
say('%d mentions of the six are left, all inside %s, and no surviving row names '
    'any of them: the text does not compile until the sweep has run, and '
    'tools/phasecheck.sh is where that is asserted'
    % (left, ', '.join(sorted(holders))))

open(path, 'w', errors='surrogateescape').write(t)
PY

# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  nowrite      the input binary did not build with '$cflags' '$ldflags'"; exit 1; }
echo "  nowrite      the input is $state/old, $(stat -c%s "$state/old") bytes, beside the source it was built from: the corpus cannot see writing, so the probes need a binary that still writes"

# tools/phaserun.sh sweeps next, then runs pipes/zero6-check.sh.
