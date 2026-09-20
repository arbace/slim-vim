#!/bin/sh
# Zero phase 38 -- the eight terminal names go, leaving two.  See ZERO-GOAL.md.
#
# Usage: pipes/zero38-edit.sh <work-dir> <state-dir>     (run from the repository root)
#
# `builtin_terminals[]` is the whole of what the core knows how to draw on: a name
# and a capability table, ten times.  An embeddable core has no business carrying
# ten terminal descriptions -- the host decides what it is attached to -- and this
# phase keeps TWO: `xterm-256color`, which is already the name `termcapinit()`
# substitutes when it is given none, and `debug`, which draws its capabilities as
# text and is the only one that can be read without a terminal at all.
#
# WHICH ROWS GO IS COMPUTED: the table MINUS the two, read out of the source.  So is
# everything that follows from it -- which capability tables die, which string
# literals have to be rewritten, and what the fallback may name.  The two names are
# the only thing written down here, and `KEEP` is where they are written.
#
# THE PARTITION, WHICH IS THE WHOLE OF THE ARGUMENT.  A terminal name in this file
# is a STRING LITERAL, so the cut is a cut inside literals -- and the same words
# appear elsewhere as identifiers (`builtin_xterm`), as prefixes (`vim_is_xterm`'s
# `musl_strncasecmp(name, "xterm", 5)`) and inside other literals
# (`"builtin_xterm"`, `"screen.xterm"`).  A textual `s/xterm//` would wreck all of
# them.  So the edit walks the file's string literals -- `cutil.blank()` preserves
# offsets and blanks literal CONTENT, so a `"` surviving in the blanked text is a
# real delimiter and the quotes pair up in order -- and every literal whose content
# EQUALS a removed name must fall in one of four classes:
#
#   row       inside builtin_terminals[]              the row itself; deleted
#   family    inside find_builtin_term()              the xterm-family special case
#   fallback  inside set_termname()                   retargeted, see below
#   prefix    inside vim_is_xterm()                   KEPT, with its reason
#
# A literal that falls in none refuses, which stays true of a file this edit has
# never seen.  Measured on the input: 11 literals, 8 + 1 + 1 + 1.
#
# THE `prefix` CLASS IS KEPT AND IS NOT AN EXCEPTION.  `vim_is_xterm()` asks whether
# a name BEGINS with `xterm` -- `musl_strncasecmp(name, "xterm", 5)`, with the
# length written out -- and `xterm-256color`, which stays, begins with it.  That
# function still has a caller (`term_is_xterm = vim_is_xterm(term)`), so the test is
# live and the literal is not a terminal name at all: it is five characters.  The
# edit requires every `prefix` literal to be an argument of a counted comparison,
# so a naked `musl_strcmp` against a name that no longer exists could not hide here.
#
# THE `family` CLASS IS DEAD CODE THE SWEEP CANNOT SEE, and this is why it goes in
# the EDIT.  `find_builtin_term()` walks the table and returns a row's table when
# `musl_strcmp(name, "xterm") == 0 && vim_is_xterm(term)` -- a test on the ROW's
# name, so the whole clause is a way of saying "the row called xterm serves the
# whole xterm family".  Once no row is called that, the first conjunct is false for
# every row and the clause can never fire; gcc has no warning for a condition that
# is false at run time, and no tool in tools/sweep.sh reads one.  It is the shape
# CLAUDE.md states for a struct field whose only reader a phase deletes: a thing the
# edit knows is dead is the edit's to take.  The edit proves it dead by COMPUTATION
# -- no surviving row carries that name -- and pipes/zero38-check.sh proves it again
# by instrumenting the clause and finding it entered 0 times where the input enters
# it on every startup.
#
# AND THE INPUT ENTERS IT ON EVERY STARTUP, which is worth knowing before anything
# here is rearranged: the compiled default is `xterm-256color`, the `xterm` row
# comes BEFORE the `xterm-256color` row, and `vim_is_xterm("xterm-256color")` is
# true -- so every startup of the input resolves through the family clause and the
# `xterm-256color` row is never reached.  After this phase it is.  Same table either
# way (`builtin_xterm`), which is why nothing in the recording moves for it.
#
# THE `fallback` CLASS IS THE ONE REPAIR, AND IT IS NOT OPTIONAL.  `set_termname()`
# answers an unknown name in two ways: at run time (`:set term=vt320`) it reports
# and FAILS, leaving the terminal alone, which is the E522 the table records; but
# before there is a screen (`starting == NO_SCREEN`, which is the `-T {term}` path)
# it substitutes a name of its own and carries on.  That name is written in the
# source, and it is `xterm` -- one of the eight this phase deletes.  Left alone, the
# cut would leave the fallback naming a terminal that no longer exists, and MEASURED
# on this phase's own output with the repair left out: `-T xterm` and
# `-T no-such-term-9x` both print `E437: Terminal capability "cm" required` and draw
# 2,045 bytes where the baseline draws 2,117 -- an editor with no cursor motion.
# That is not a capability removed on purpose, it is a dangling name.
#
# So the fallback is retargeted, and the new name is COMPUTED and not written here:
# it is the name `termcapinit()` substitutes when it is given none, which the edit
# reads out of that function and requires to be a row that stays.  After this phase
# there is ONE name the editor falls back to and one compiled default, and they are
# the same name.  The message that announces it is rewritten in the same step -- the
# format string and the name move together, as pipes/zero12-edit.sh's `[RO]` did,
# because nothing in the build checks that a message tells the truth.
#
# WHAT THE SWEEP THEN FINDS: three capability tables, `builtin_ansi`,
# `builtin_vt100` and `builtin_dumb`, as -Wunused-variable.  That set is COMPUTED
# too -- a `builtin_*` table whose only mention left, literals excluded, is its own
# definition -- and the edit asserts the set rather than naming three of them.
# `builtin_xterm` is NOT in it: `xterm-256color` still points at it, and the
# mention inside the string literal `"builtin_xterm"` is a literal and not a
# reference, which is why the count is taken on blanked text.
#
# NOT THIS PHASE'S, AND DELIBERATELY LEFT: the 256-colour add-on's test on
# `requested`, and `-T {term}` itself.  Both are the next phase's, and the second is
# what makes the fallback reachable at all -- remove `-T` and `termcapinit()` can
# only ever be handed nothing, so `set_termname()`'s no-screen arm becomes
# unreachable and the sweep takes `report_term_error()` with it.
#
# THE INPUT BINARY IS BUILT HERE, before the edit, from the boundary's own makefile
# flags, as every zero edit since phase 2 does, and the source goes with it as
# $state/old.c.  The check needs both: this phase's delta is `term-moved`, and a
# table that moved is only evidence beside the table it moved from.
set -eu

work=${1:?usage: zero38-edit.sh <work-dir> <state-dir>}
state=${2:?usage: zero38-edit.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"

# The flags are read out of the boundary's makefile rather than written here a
# second time: zero's compile line is the boundary's (ZERO-GOAL.md rule 8).
cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")
cp "$f" "$state/old.c"
# shellcheck disable=SC2086
( cd "$state" && SOURCE_DATE_EPOCH=0 gcc $cflags $ldflags -o old old.c ) &
pid_old=$!

python3 - "$f" <<'PY'
TAG = 'terms'
import re
import sys
sys.path.insert(0, 'tools')
# tools/cutil.py -- named as a PATH so tools/implhash.sh hashes it into this
# phase's key.  implhash greps for paths and an `import` names a module, so
# without this line an edit to it changes what this phase produces and moves
# no key at all.  See CLAUDE.md on cutil.py and macros.py.  Do not delete it.
import cutil

# THE ONLY THING WRITTEN DOWN IN THIS PHASE.  Everything else is computed from it
# and from the source: which rows go, which capability tables die, which literals
# have to be rewritten and what the fallback may name.
KEEP = ('xterm-256color', 'debug')

path = sys.argv[1]
t = open(path, errors='surrogateescape').read()
b = cutil.blank(t)


def die(msg):
    sys.exit('  %-12s %s' % (TAG, msg))


def say(what):
    print('  %-12s %s' % (TAG, what))


def mentions(text, name):
    """Mentions of an IDENTIFIER, with string literals excluded.

    `builtin_xterm` is written inside a string literal as well as being a table,
    and a count that read that as a reference would report a dead table as live.
    """
    return len(re.findall(r'\b%s\b' % name, cutil.blank(text)))


def defspan(name):
    r = cutil.find_definition(t, name, b)
    if r is None:
        die('%s() is not defined in this file, and the partition below is drawn '
            'against its extent' % name)
    return r


def line_of(off):
    return t.count('\n', 0, off) + 1


# ---- 0. the table, and the two rows that stay ------------------------------------
i = t.find('static builtin_tcap_T builtin_terminals[] = {')
if i < 0:
    die('builtin_terminals[] is not in this file')
j = t.index('\n};', i)
ROW = re.compile(r'^[ \t]*\{\s*"([^"]*)"\s*,\s*(\w+)\s*\},\n', re.M)
rows = [(m.group(1), m.group(2), i + m.start(), i + m.end())
        for m in ROW.finditer(t[i:j])]
if not rows:
    die('builtin_terminals[] holds no row in the {"name", table} shape, so the cut '
        'below would be vacuous')
names = [r[0] for r in rows]
if len(set(names)) != len(names):
    die('builtin_terminals[] names a terminal twice: %s' % ' '.join(names))
missing = [k for k in KEEP if k not in names]
if missing:
    die('builtin_terminals[] does not name %s, and that is a row this phase keeps'
        % ' '.join(missing))
GONE = [n for n in names if n not in KEEP]
if not GONE:
    die('builtin_terminals[] holds nothing but the two rows that stay: there is '
        'nothing here to remove, and every assertion below would be vacuous')
say('builtin_terminals[] has %d rows.  %s stay and %d go -- %s.  The removed set is '
    'the table MINUS the two, computed here, and the two are the only names this '
    'phase writes down' % (len(rows), ' and '.join(KEEP), len(GONE), ' '.join(GONE)))

# ---- 1. THE PARTITION: every literal that IS a removed name ----------------------
# cutil.blank() keeps offsets and blanks literal CONTENT, so a `"` left in the
# blanked text is a real delimiter and the quotes pair up in order.  That is what
# makes this literal-aware: the identifier `builtin_xterm`, the prefix inside
# `"screen.xterm"` and the substring of `"xterm-256color"` are all invisible to it,
# and only a literal whose WHOLE content is a removed name is classified.
quotes = [m.start() for m in re.finditer(r'"', b)]
if len(quotes) % 2:
    die('the file has an odd number of string delimiters after blanking, so the '
        'literal spans below cannot be trusted')
lits = [(quotes[k], quotes[k + 1]) for k in range(0, len(quotes), 2)]

table_span = (i, j)
CLASS = [('row', table_span),
         ('family', defspan('find_builtin_term')),
         ('fallback', defspan('set_termname')),
         ('prefix', defspan('vim_is_xterm'))]
part = {k: [] for k, _ in CLASS}
loose = []
for a, z in lits:
    if t[a + 1:z] not in GONE:
        continue
    for kind, (lo, hi) in CLASS:
        if lo <= a < hi:
            part[kind].append((a, z))
            break
    else:
        loose.append((a, z))
if loose:
    die('%d literal(s) spell a removed terminal name outside builtin_terminals[], '
        'find_builtin_term(), set_termname() and vim_is_xterm(), and this phase has '
        'no class for them: %s'
        % (len(loose), ', '.join('%r at line %d' % (t[a + 1:z], line_of(a))
                                 for a, z in loose)))
if len(part['row']) != len(GONE):
    die('builtin_terminals[] holds %d literals spelling a removed name where %d '
        'rows go' % (len(part['row']), len(GONE)))
if len(part['family']) != 1 or len(part['fallback']) != 1:
    die('find_builtin_term() spells a removed name %d times and set_termname() %d, '
        'and this phase is written against one of each'
        % (len(part['family']), len(part['fallback'])))
if not part['prefix']:
    die('vim_is_xterm() spells no removed name, so the `prefix` class below would '
        'be vacuous -- read the function before removing this')
# The `prefix` class is KEPT, and this is what makes keeping it honest: each one
# must be an argument of a COUNTED comparison, so a name compared in full could not
# sit here unnoticed.
for a, z in part['prefix']:
    if 'musl_strncasecmp' not in t[max(0, a - 80):a]:
        die('vim_is_xterm() compares %r other than as a counted prefix, so it is a '
            'terminal NAME there and not five characters' % t[a + 1:z])
    if not re.match(r'[\s)]*,\s*\(\d+\)', t[z + 1:z + 16]):
        die('the comparison of %r in vim_is_xterm() carries no written length'
            % t[a + 1:z])
say('the %d literals that spell a removed name partition exactly: %d rows, 1 in '
    'find_builtin_term() (the xterm-family special case), 1 in set_termname() (the '
    'fallback) and %d in vim_is_xterm(), which are counted PREFIX tests -- '
    'musl_strncasecmp(name, %r, N) -- and %r, which stays, begins with it'
    % (len(GONE) + 2 + len(part['prefix']), len(GONE), len(part['prefix']),
       t[part['prefix'][0][0] + 1:part['prefix'][0][1]], KEEP[0]))

# ---- 2. what the fallback may name, computed from termcapinit() ------------------
lo, hi = defspan('termcapinit')
compiled = sorted({t[a + 1:z] for a, z in lits if lo <= a < hi and t[a + 1:z] in names})
if len(compiled) != 1:
    die('termcapinit() spells %d of builtin_terminals[] names (%s), and this phase '
        'needs exactly one -- the name it substitutes when it is given none'
        % (len(compiled), ' '.join(compiled) or 'none'))
DEFAULT = compiled[0]
if DEFAULT not in KEEP:
    die("termcapinit()'s compiled default is %r, which this phase deletes: the "
        'fallback cannot be retargeted onto a row that is going' % DEFAULT)
a, z = part['fallback'][0]
OLD_FALLBACK = t[a + 1:z]
say("set_termname()'s no-screen fallback names %r, which goes; termcapinit()'s "
    'compiled default is %r, which stays.  The fallback is retargeted onto it, so '
    'after this phase there is ONE name the editor falls back to and one compiled '
    'default, and they are the same name' % (OLD_FALLBACK, DEFAULT))

# ---- 3. the family clause: dead by computation -----------------------------------
a, z = part['family'][0]
if OLD_FALLBACK in names and OLD_FALLBACK not in GONE:
    die('%r is still a row of builtin_terminals[], so the special case in '
        'find_builtin_term() is live and must not be removed' % t[a + 1:z])
start = t.rfind('\n', 0, a) + 1
head = t[start:t.index('\n', a)]
if not re.match(r'\s*if\s*\(', head) or 'vim_is_xterm' not in head:
    die('the literal %r in find_builtin_term() is not the condition of an `if` that '
        'calls vim_is_xterm(): %s' % (t[a + 1:z], head.strip()))
ob = b.index('{', t.index(')', a))
cb = cutil.match(t, ob, b)
if cb < 0:
    die("the xterm-family clause's block is not balanced")
end = cb + 1
while end < len(t) and t[end] == '\n':
    end += 1
    break
body = t[ob + 1:cb]
if body.count(';') != 1 or 'return' not in body:
    die('the xterm-family clause does more than return a table, and this phase is '
        'written against the clause that does: %s' % ' '.join(body.split()))
FAMILY = (start, end)
say('the xterm-family special case in find_builtin_term() tests the ROW\'s name '
    'against %r, and no row will carry that name: the clause can never fire again.  '
    'gcc has no warning for a condition that is false at run time and no tool in '
    'tools/sweep.sh reads one, so it is the edit\'s to take -- %d lines at line %d'
    % (OLD_FALLBACK, t.count('\n', start, end), line_of(start)))

# ---- 4. the message that announces the fallback ----------------------------------
# The message and the name move together.  Nothing in the build checks that a
# message tells the truth, so a retargeted fallback with the old name in its text
# would be a lie no harness could see.
lo, hi = defspan('report_term_error')
quoted = "'%s'" % OLD_FALLBACK
msgs = [(a, z) for a, z in lits if lo <= a < hi and quoted in t[a + 1:z]]
if not msgs:
    die('report_term_error() does not spell %s, so this phase cannot keep its '
        'message and its fallback in step' % quoted)
say('report_term_error() spells %s in %d message(s), and each is rewritten in the '
    'same step as the fallback itself -- nothing in the build checks that a message '
    'tells the truth' % (quoted, len(msgs)))

# ---- 5. ONE PASS over the original text ------------------------------------------
# Every edit below is an offset into the text as it was read.  A second pass would
# index its spans against the first pass's output; zero phase 23 measured that and
# left five of 437 names behind in a file that still compiled.
edits = []
for name, _tab, a, z in rows:
    if name in GONE:
        edits.append((a, z, ''))
edits.append(FAMILY + ('',))
a, z = part['fallback'][0]
edits.append((a, z + 1, '"%s"' % DEFAULT))
for a, z in msgs:
    edits.append((a, z + 1, '"%s"' % t[a + 1:z].replace(quoted, "'%s'" % DEFAULT)))
edits.sort()
for k in range(1, len(edits)):
    if edits[k][0] < edits[k - 1][1]:
        die('two of this phase\'s edits overlap at line %d, so applying them in one '
            'pass would corrupt the file' % line_of(edits[k][0]))
out = []
prev = 0
for a, z, rep in edits:
    out.append(t[prev:a])
    out.append(rep)
    prev = z
out.append(t[prev:])
t = ''.join(out)

# ---- 6. what the sweep is handed, computed -------------------------------------
# A `builtin_*` table whose only mention left -- literals excluded -- is its own
# definition is dead.  The rule is what is asserted; the three names it computes are
# printed, not required.
tables = sorted({tab for _n, tab, _a, _z in rows})
dead = [x for x in tables if mentions(t, x) == 1]
live = [x for x in tables if mentions(t, x) > 1]
if not dead:
    die('every capability table builtin_terminals[] pointed at still has a row, so '
        'this cut orphans nothing and the sweep has nothing to find')
for x in dead:
    if not re.search(r'^static \w+ %s\[\] = \{' % x, t, re.M):
        die('%s has one mention left and it is not its own definition' % x)
say('%d of the %d capability tables builtin_terminals[] pointed at have no row '
    'left and are the sweep\'s: %s.  %s stay, each still pointed at -- and the '
    'count is taken on BLANKED text, because "builtin_xterm" is also a string '
    'literal and a count that read that as a reference would report a live table '
    'dead' % (len(dead), len(tables), ' '.join(dead), ' '.join(live)))

# ---- 7. nothing spells a removed name any more, except the prefix tests -----------
b2 = cutil.blank(t)
q2 = [m.start() for m in re.finditer(r'"', b2)]
left = [(q2[k], q2[k + 1]) for k in range(0, len(q2), 2)
        if t[q2[k] + 1:q2[k + 1]] in GONE]
lo, hi = defspan_out = cutil.find_definition(t, 'vim_is_xterm', b2)
stray = [(a, z) for a, z in left if not (lo <= a < hi)]
if stray:
    die('%d literal(s) still spell a removed terminal name outside vim_is_xterm(): '
        '%s' % (len(stray), ', '.join('%r' % t[a + 1:z] for a, z in stray)))
if len(left) != len(part['prefix']):
    die('vim_is_xterm() holds %d literals spelling a removed name and held %d'
        % (len(left), len(part['prefix'])))
say('nothing in the output spells a removed terminal name except the %d counted '
    'prefix test(s) in vim_is_xterm(), which is the one class this partition keeps'
    % len(left))

open(path, 'w', errors='surrogateescape').write(t)
PY

# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  terms        the input binary did not build with '$cflags' '$ldflags'"; exit 1; }
echo "  terms        the input is $state/old, $(stat -c%s "$state/old") bytes, beside the source it was built from: this phase declares term-moved, and a table that moved is only evidence beside the table it moved from"

# tools/phaserun.sh sweeps next, then runs pipes/zero38-check.sh.
