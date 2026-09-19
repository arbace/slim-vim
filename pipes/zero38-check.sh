#!/bin/sh
# Zero phase 38, the check -- the eight terminal names go, leaving two.
# See pipes/zero38-edit.sh, and ZERO-GOAL.md.
#
# Usage: pipes/zero38-check.sh <work-dir> <state-dir>   (run from the repository root)
#
# Runs after pipes/zero38-edit.sh and the sweep tools/phaserun.sh runs between them,
# and reads nothing from the edit's shell -- only the work tree and the state
# directory.  What the edit left there is `old.c`, the source this phase was HANDED,
# and `old`, that source built with SOURCE_DATE_EPOCH=0 and the boundary's own flags.
#
# NOTHING BELOW IS A NUMBER THAT WAS OBSERVED.  Which names go is the input's table
# minus the output's; which capability tables die follows from that; what a refused
# name leaves the terminal as is MEASURED from the new binary, by asking it with no
# `+set term=` at all; and the nineteen rows are however many
# `tools/termcheck.py` names.  So the rules stay true of a file this check has never
# seen, which is what makes them rules.
#
# WHAT IS CLAIMED, in nine parts:
#
#   THE CUT      the output's table is the input's MINUS a set, every surviving row
#                byte for byte the row it was, and every capability table the removed
#                rows pointed at -- and nothing else -- gone from the file.  Which
#                tables those are is COMPUTED from the input, on text whose string
#                literals are blanked, because `builtin_xterm` is also a literal.
#   THE PARTITION  every string literal in the INPUT whose content is a removed name
#                falls in one of four classes, and in the OUTPUT only the last class
#                is left: the counted prefix tests in vim_is_xterm(), where the name
#                is five characters and not a terminal.  A leftover refuses.  This is
#                recomputed here and does not read the edit's answer.
#   THE FALLBACK  every terminal name written as a literal OUTSIDE the table names a
#                row that still exists, and the message that announces the fallback
#                names the same one.  THE CONTROL is this phase's own output with the
#                repair left out, which must move the two `-T` rows and print E437 --
#                an editor with no cursor motion.  A repair with no control is a
#                claim; this one is measured.
#   THE CLAUSE   the xterm-family special case is dead and not merely unused.  TWO
#                measurements: the output with the clause RESTORED records byte for
#                byte what the output records, so removing it changed nothing; and
#                the same two sources with a marker inside the clause enter it in
#                EVERY screen record on the input and in NONE on the output.
#   THE TABLE    the nineteen rows before and after, side by side, in this check's
#                output.  Exactly the names that lost a row moved, each from
#                resolving to a refusal at the MEASURED default, and every other row
#                is byte-identical.  TWO CONTROLS, in opposite directions: a row
#                deleted from the output's own table moves exactly one of the
#                nineteen from resolving to refused, and a removed name put back
#                moves exactly one from refused to resolving.  An instrument that
#                cannot fail is not evidence.
#   THE FAMILY   the `xterm` row was not one name: find_builtin_term()'s special case
#                handed its table to every name vim_is_xterm() accepts, and NOT ONE of
#                those is among the nineteen.  So the phase owes probes, and the names
#                are read out of vim_is_xterm()'s own prefix list in the source this
#                phase was handed: each must resolve on the old binary and be refused
#                on the new.
#   SYMBOLS      `nm -u` is THE SAME SET, as a `comm` empty in both directions, and
#                that is a statement rather than a disappointment: this phase deletes
#                DATA -- three static arrays and eight rows -- and data calls nothing.
#                `nm --extern-only --defined-only` is still exactly `main`.
#   THE CUT (2)  `awk '/^ *# *include / { exit }'`, zero.mk's own rule, on the INPUT
#                and on the OUTPUT: eleven directives, none above them, 0 errors
#                under -fsyntax-only either side, and the boundary's warning set --
#                which IS the core -> host interface -- UNCHANGED.  The input's set
#                is computed here and never written down.
#   STRUCTURE    tools/zhostonly.py, phase 20's structural check, and
#                tools/phasecheck.sh.
set -eu

work=${1:?usage: zero38-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero38-check.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"
before_lines=$(cat "$state/input-lines")

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")

# THE PRODUCT, REBUILT, and the clean is checked rather than trusted: the work tree
# still holds the binary tools/restore.sh unpacked with the previous boundary, and a
# recording of THAT would be a recording of the phase's input.  Measured, because it
# happened here first: without this, every probe below passed and tools/zerodelta.sh
# reported `term-moved was declared to move and did not` -- the delta checker reading
# the old binary, which is CLAUDE.md's "a rebuild that never happened" one level up.
make -C "$work" clean >/dev/null 2>&1 || true
[ -e "$work/zero-vim" ] && { echo "  build        the clean did not remove zero-vim, so nothing below would be a recording of this phase"; exit 1; }
if ! make -C "$work" >/dev/null 2>&1; then
    echo "  build        FAILED -- rerun by hand: make -C $work"
    exit 1
fi
new="$work/zero-vim"

# --- the controls, written first and built in parallel ----------------------------
# Each is this phase's own output with ONE thing changed, or the input with one thing
# added.  They are written by a program that reads both texts, so not one of them is
# C quoted into this file.
python3 - "$f" "$state/old.c" "$tmp" <<'PY'
import re
import sys
sys.path.insert(0, 'tools')
import cutil

TAG = 'terms'
new = open(sys.argv[1], errors='surrogateescape').read()
old = open(sys.argv[2], errors='surrogateescape').read()
out = sys.argv[3]


def die(msg):
    sys.exit('  %-12s %s' % (TAG, msg))


ROW = re.compile(r'^[ \t]*\{\s*"([^"]*)"\s*,\s*(\w+)\s*\},\n', re.M)


def table(t):
    i = t.find('static builtin_tcap_T builtin_terminals[] = {')
    if i < 0:
        die('builtin_terminals[] is not in one of the two texts')
    j = t.index('\n};', i)
    return i, j, [(m.group(1), m.group(2), m.group(0)) for m in ROW.finditer(t[i:j])]


io, jo, orows = table(old)
i_, j_, nrows = table(new)
GONE = [n for n, _t, _r in orows if n not in [x[0] for x in nrows]]
if not GONE:
    die('the output keeps every row the input had: there is nothing to check')

# c1 -- THE REPAIR LEFT OUT.  set_termname()'s fallback put back to the name it had,
# and the message with it.  Found by function extent, never by line number.
lo, hi = cutil.find_definition(new, 'set_termname')
seg = new[lo:hi]
fb = sorted({n for n, _t, _r in nrows if '"%s"' % n in seg})
if len(fb) != 1:
    die('set_termname() names %d of the surviving rows and this check needs one -- '
        'the fallback' % len(fb))
NEW_FB = fb[0]
old_lo, old_hi = cutil.find_definition(old, 'set_termname')
ofb = sorted({n for n in GONE if '"%s"' % n in old[old_lo:old_hi]})
if len(ofb) != 1:
    die('set_termname() in the INPUT names %d removed rows and this check needs one'
        % len(ofb))
OLD_FB = ofb[0]
c1 = new[:lo] + seg.replace('"%s"' % NEW_FB, '"%s"' % OLD_FB) + new[hi:]
lo, hi = cutil.find_definition(c1, 'report_term_error')
c1 = c1[:lo] + c1[lo:hi].replace("'%s'" % NEW_FB, "'%s'" % OLD_FB) + c1[hi:]
if c1 == new:
    die('the repair-left-out control changed nothing, so it is not a control')
open(out + '/c1.c', 'w', errors='surrogateescape').write(c1)

# c2 -- THE FAMILY CLAUSE RESTORED.  Located in the INPUT exactly as the edit located
# it, and the removal is asserted as an EQUALITY: the input's find_builtin_term()
# minus the clause IS the output's, character for character.
bo = cutil.blank(old)
q = [m.start() for m in re.finditer(r'"', bo)]
lits = [(q[k], q[k + 1]) for k in range(0, len(q), 2)]
flo, fhi = cutil.find_definition(old, 'find_builtin_term', bo)
hits = [(a, z) for a, z in lits if flo <= a < fhi and old[a + 1:z] in GONE]
if len(hits) != 1:
    die("find_builtin_term() in the input spells %d removed names, and this check is "
        'written against one -- the xterm-family special case' % len(hits))
a, z = hits[0]
start = old.rfind('\n', 0, a) + 1
ob = bo.index('{', old.index(')', a))
cb = cutil.match(old, ob, bo)
end = cb + 1
if end < len(old) and old[end] == '\n':
    end += 1
clause = old[start:end]
nlo, nhi = cutil.find_definition(new, 'find_builtin_term')
if old[flo:start] + old[end:fhi] != new[nlo:nhi]:
    die("the input's find_builtin_term() minus the xterm-family clause is NOT the "
        "output's, so this phase did something else to that function as well")
c2 = new[:nlo] + old[flo:start] + clause + old[end:fhi] + new[nhi:]
open(out + '/c2.c', 'w', errors='surrogateescape').write(c2)
open(out + '/clause', 'w').write(clause)

# The instrumented pair.  The marker goes through host_message(), the core's own
# declared way to reach stderr (zero phase 21), because the core has had no write()
# of its own since phase 35 -- so the instrument adds no name the file does not
# already have.
MARK = 'XTERMFAMILY'
ins = clause.replace('        {\n', '        {\n            host_message("%s\\n", -1, TRUE);\n' % MARK, 1)
if ins == clause:
    die('the xterm-family clause does not open with a braced block on its own line, '
        'so the marker cannot be put inside it')
for name, text in (('i-old', old), ('i-new', c2)):
    if text.count(clause) != 1:
        die('the clause is not in %s exactly once, so the instrumented build would '
            'not be one' % name)
    open('%s/%s.c' % (out, name), 'w', errors='surrogateescape').write(
        text.replace(clause, ins))

# c3 -- one row DELETED from the output's own table: the LAST one it names, so the
# break is derived and not a name written here.
last = nrows[-1]
if new.count(last[2]) != 1:
    die('the last row of the output table is not one line of the file')
open(out + '/c3.c', 'w', errors='surrogateescape').write(new.replace(last[2], ''))
open(out + '/c3.name', 'w').write(last[0])

# c4 -- one removed name PUT BACK, pointing at the table the output's first row
# points at, so the row is derived too.
back, tab = GONE[0], nrows[0][1]
row = '    {"%s", %s},\n' % (back, tab)
c4 = new[:i_] + new[i_:j_].replace(nrows[0][2], row + nrows[0][2], 1) + new[j_:]
if c4 == new:
    die('the put-back control changed nothing, so it is not a control')
open(out + '/c4.c', 'w', errors='surrogateescape').write(c4)
open(out + '/c4.name', 'w').write(back)
open(out + '/gone', 'w').write(' '.join(GONE))
open(out + '/fallback', 'w').write('%s %s' % (OLD_FB, NEW_FB))
PY

for v in c1 c2 c3 c4 i-old i-new; do
    # shellcheck disable=SC2086
    ( SOURCE_DATE_EPOCH=0 gcc $cflags $ldflags -o "$tmp/$v" "$tmp/$v.c" ) &
done
GONE=$(cat "$tmp/gone")

# --- 1. THE CUT, computed from the input ------------------------------------------
python3 - "$f" "$state/old.c" "$before_lines" <<'PY'
import re
import sys
sys.path.insert(0, 'tools')
import cutil

TAG = 'terms'
new = open(sys.argv[1], errors='surrogateescape').read()
old = open(sys.argv[2], errors='surrogateescape').read()
before = int(sys.argv[3])


def die(msg):
    sys.exit('  %-12s %s' % (TAG, msg))


def say(what):
    print('  %-12s %s' % (TAG, what))


def mentions(t, name):
    return len(re.findall(r'\b%s\b' % name, cutil.blank(t)))


ROW = re.compile(r'^[ \t]*\{\s*"([^"]*)"\s*,\s*(\w+)\s*\},\n', re.M)


def rowsof(t):
    i = t.index('static builtin_tcap_T builtin_terminals[] = {')
    j = t.index('\n};', i)
    return [(m.group(1), m.group(2), m.group(0)) for m in ROW.finditer(t[i:j])]


orows, nrows = rowsof(old), rowsof(new)
oname = [r[0] for r in orows]
nname = [r[0] for r in nrows]
extra = [n for n in nname if n not in oname]
if extra:
    die('the output names a terminal the input did not: %s -- this phase removes '
        'rows and adds none' % ' '.join(extra))
GONE = [n for n in oname if n not in nname]
if not GONE:
    die('the output keeps every row, so every assertion below is vacuous')
if len(nname) < 2:
    die('the output keeps %d rows, and an editor with fewer than two terminals it '
        'can name is not what this phase is' % len(nname))
# The surviving rows are the rows they were, character for character: a phase that
# repointed one at another table would pass a count and fail here.
for name, tab, text in nrows:
    was = [r for r in orows if r[0] == name][0]
    if text != was[2]:
        die('the row for %r is not the row it was: %r became %r'
            % (name, was[2].strip(), text.strip()))
say('builtin_terminals[] %d rows -> %d: %s go, %s stay, and each of the two that '
    'stay is byte for byte the row it was -- a phase that repointed one at another '
    'table would pass a count and fail here'
    % (len(orows), len(nrows), ' '.join(GONE), ' '.join(nname)))

# WHICH CAPABILITY TABLES DIE IS COMPUTED, on BLANKED text: `builtin_xterm` is also
# a string literal inside vim_is_xterm(), and a count that read that as a reference
# would report a live table dead.
tabs = sorted({t for _n, t, _r in orows})
pred = sorted(x for x in tabs
              if not any(t == x for n, t, _r in orows if n in nname))
live = sorted(x for x in tabs if x not in pred)
if not pred:
    die('every capability table the input pointed at still has a row, so this cut '
        'orphans nothing and the sweep had nothing to find')
bad = []
for x in pred:
    if mentions(new, x):
        bad.append('%s survives with %d mention(s) and has no row left'
                   % (x, mentions(new, x)))
for x in live:
    if mentions(new, x) < 2:
        bad.append('%s still has a row and has %d mention(s) left'
                   % (x, mentions(new, x)))
if bad:
    die('the capability tables did not go as the rows say they must:\n  '
        + '\n  '.join(bad))
say('%d of the %d capability tables the input pointed at have no row left and the '
    'sweep took every one -- %s; %s stay, each still pointed at.  The set is '
    'computed from the rows, on text whose string literals are blanked, because '
    '"builtin_xterm" is a literal and not a reference'
    % (len(pred), len(tabs), ' '.join(pred), ' '.join(live)))
after = new.count('\n') + (0 if new.endswith('\n') else 1)
if after >= before:
    die('the file did not shrink: %d -> %d' % (before, after))
say('the file lost %d lines, %d -> %d: the %d rows, the xterm-family clause, and '
    'the %d capability tables the sweep found under them'
    % (before - after, before, after, len(GONE), len(pred)))

# --- 2. THE PARTITION, recomputed and not read from the edit ----------------------
def literals(t):
    b = cutil.blank(t)
    q = [m.start() for m in re.finditer(r'"', b)]
    if len(q) % 2:
        die('a text has an odd number of string delimiters after blanking')
    return b, [(q[k], q[k + 1]) for k in range(0, len(q), 2)]


bo, olits = literals(old)
i = old.index('static builtin_tcap_T builtin_terminals[] = {')
j = old.index('\n};', i)
CLASS = [('row', (i, j)),
         ('family', cutil.find_definition(old, 'find_builtin_term', bo)),
         ('fallback', cutil.find_definition(old, 'set_termname', bo)),
         ('prefix', cutil.find_definition(old, 'vim_is_xterm', bo))]
part = {k: 0 for k, _ in CLASS}
loose = []
for a, z in olits:
    if old[a + 1:z] not in GONE:
        continue
    for kind, (lo, hi) in CLASS:
        if lo <= a < hi:
            part[kind] += 1
            break
    else:
        loose.append(old[a + 1:z])
if loose:
    die('the input spells a removed terminal name in a place this phase has no '
        'class for: %s' % ' '.join(sorted(set(loose))))
if part['row'] != len(GONE) or part['family'] != 1 or part['fallback'] != 1:
    die('the input partitions as %s, and this phase is written against one row per '
        'removed name, one family clause and one fallback' % part)

bn, nlits = literals(new)
lo, hi = cutil.find_definition(new, 'vim_is_xterm', bn)
left = [(a, z) for a, z in nlits if new[a + 1:z] in GONE]
stray = [new[a + 1:z] for a, z in left if not (lo <= a < hi)]
if stray:
    die('the output still spells a removed terminal name outside vim_is_xterm(): %s'
        % ' '.join(sorted(set(stray))))
if len(left) != part['prefix']:
    die('vim_is_xterm() spells a removed name %d times in the output and %d in the '
        'input' % (len(left), part['prefix']))
for a, z in left:
    if 'musl_strncasecmp' not in new[max(0, a - 80):a] \
            or not re.match(r'[\s)]*,\s*\(\d+\)', new[z + 1:z + 16]):
        die('%r survives in vim_is_xterm() other than as a counted prefix test'
            % new[a + 1:z])
say('the %d literals that spell a removed name in the input partition %d rows / 1 '
    'family clause / 1 fallback / %d prefix tests, and the output keeps ONLY the '
    'last class: %s in vim_is_xterm(), each a musl_strncasecmp with its length '
    'written out, and %r -- which stays -- begins with it'
    % (part['row'] + part['family'] + part['fallback'] + part['prefix'],
       part['row'], part['prefix'],
       ' '.join(sorted({new[a + 1:z] for a, z in left})), nname[0]))

# --- 3. THE FALLBACK NAMES A ROW THAT EXISTS --------------------------------------
# Every terminal name written as a literal OUTSIDE the table: set_termname()'s
# fallback and termcapinit()'s compiled default.  Both must be rows the output still
# has, and the message must name the same one.
named = {}
for fn in ('set_termname', 'termcapinit'):
    lo, hi = cutil.find_definition(new, fn, bn)
    got = sorted({new[a + 1:z] for a, z in nlits
                  if lo <= a < hi and new[a + 1:z] in oname})
    if len(got) != 1:
        die('%s() names %d terminals of the input table (%s) and this check needs '
            'exactly one' % (fn, len(got), ' '.join(got) or 'none'))
    if got[0] not in nname:
        die('%s() names %r, which this phase removed: a name written outside the '
            'table must be a row the table still has' % (fn, got[0]))
    named[fn] = got[0]
if named['set_termname'] != named['termcapinit']:
    die("set_termname()'s fallback is %r and termcapinit()'s compiled default is "
        '%r: after this phase they must be the same name'
        % (named['set_termname'], named['termcapinit']))
lo, hi = cutil.find_definition(new, 'report_term_error', bn)
msgs = [new[a + 1:z] for a, z in nlits if lo <= a < hi]
quoted = "'%s'" % named['set_termname']
if not [m for m in msgs if quoted in m]:
    die('report_term_error() does not name %s, so the message and the fallback '
        'disagree and nothing in the build would say so' % quoted)
if [m for m in msgs if any("'%s'" % g in m for g in GONE)]:
    die('report_term_error() still names a removed terminal')
say("set_termname()'s fallback, termcapinit()'s compiled default and "
    "report_term_error()'s message all name %r, which is a row the table still has: "
    'after this phase there is ONE name the editor falls back to'
    % named['set_termname'])

# --- the shape the checks below are built on, stated once -------------------------
print('  %-12s %s' % ('terms', 'the cut: %d rows, one dead clause and %d tables, '
                      'and one repair' % (len(GONE), len(pred))))
PY

wait

# --- 4. THE FALLBACK'S CONTROL: the repair left out --------------------------------
# A repair with no control is a claim.  This one moves exactly the two command lines
# that reach set_termname() before there is a screen, and it moves them into an
# editor with no cursor motion.
rm -rf "$tmp/rec-new" "$tmp/rec-c1" "$tmp/rec-c2"
tools/zrecord.sh "$new" "$f" "$tmp/rec-new" >/dev/null
tools/zrecord.sh "$tmp/c1" "$tmp/c1.c" "$tmp/rec-c1" >/dev/null &
tools/zrecord.sh "$tmp/c2" "$tmp/c2.c" "$tmp/rec-c2" >/dev/null &
tools/zrecord.sh "$tmp/i-old" "$tmp/i-old.c" "$tmp/rec-i-old" >/dev/null &
tools/zrecord.sh "$tmp/i-new" "$tmp/i-new.c" "$tmp/rec-i-new" >/dev/null &
wait

if ! python3 - "$tmp/rec-new" "$tmp/rec-c1" "$(cat "$tmp/fallback")" > "$tmp/fb" 2>&1 <<'PY'
"""The repair left out: exactly the rows that name a terminal on the command line."""
import os
import re
import sys


def blocks(p):
    out, cur = {}, None
    for line in open(p, errors='replace'):
        if line.startswith('=== '):
            cur = line.strip()[4:]
            out[cur] = []
        elif cur is not None:
            out[cur].append(line)
    return {k: ''.join(v) for k, v in out.items()}


new, c1 = sys.argv[1], sys.argv[2]
old_fb, new_fb = sys.argv[3].split()
moved = []
for what in ('ref-excmds.txt', 'ref-argv.txt', 'ref-pty.txt', 'ref-term.txt'):
    a, b = os.path.join(new, what), os.path.join(c1, what)
    if what == 'ref-term.txt':
        if open(a).read() != open(b).read():
            sys.exit('the repair-left-out control moved the TERMINAL table, which '
                     'the fallback has nothing to do with')
        continue
    x, y = blocks(a), blocks(b)
    moved += [(k, x[k], y[k]) for k in x if x[k] != y.get(k)]
sa = sorted(os.listdir(os.path.join(new, 'screen')))
for c in sa:
    if open(os.path.join(new, 'screen', c), errors='replace').read() \
            != open(os.path.join(c1, 'screen', c), errors='replace').read():
        moved.append(('case:' + c, '', ''))
if not moved:
    sys.exit('the repair-left-out control moved NOTHING, so the fallback repair is '
             'not load-bearing and this phase should not have made it')
if not all(k.startswith('-T ') for k, _a, _b in moved):
    sys.exit('the repair-left-out control moved records that do not name a terminal '
             'on the command line: %s' % ' '.join(k for k, _a, _b in moved))
for k, a, b in moved:
    if 'E437' in a or 'E437' not in b:
        sys.exit('%r does not go from drawing to E437 when the repair is left out' % k)
    fa = re.search(r'stream (\d+)', a)
    fb = re.search(r'stream (\d+)', b)
    if not fa or not fb or int(fb.group(1)) >= int(fa.group(1)):
        sys.exit('%r draws no less with the repair left out' % k)
print('the repair is load-bearing: with the fallback left naming %r, %d record(s) '
      'move -- %s -- each from drawing %s bytes to %s bytes and E437: Terminal '
      'capability "cm" required.  The repair points it at %r instead, and those '
      'records are the baseline\'s again'
      % (old_fb, len(moved), ', '.join(repr(k) for k, _a, _b in moved),
         re.search(r'stream (\d+)', moved[0][1]).group(1),
         re.search(r'stream (\d+)', moved[0][2]).group(1), new_fb))
PY
then
    sed 's/^/  fallback     /' "$tmp/fb"
    exit 1
fi
sed 's/^/  fallback     /' "$tmp/fb"

# --- 5. THE CLAUSE IS DEAD, TWICE --------------------------------------------------
if ! diff -r "$tmp/rec-c2" "$tmp/rec-new" >/dev/null; then
    echo "  clause       the output with the xterm-family clause RESTORED records something different, so removing it was not neutral:"
    diff -rq "$tmp/rec-c2" "$tmp/rec-new" | head -10 | sed 's/^/               /'
    exit 1
fi
hit_old=$(grep -l XTERMFAMILY "$tmp/rec-i-old"/screen/* 2>/dev/null | grep -c '' || true)
hit_new=$(grep -l XTERMFAMILY "$tmp/rec-i-new"/screen/* 2>/dev/null | grep -c '' || true)
cases=$(ls "$tmp/rec-new/screen" | grep -c '')
if [ "$hit_old" != "$cases" ] || [ "$hit_new" != 0 ]; then
    echo "  clause       the instrumented pair does not say what this phase claims: the INPUT entered the clause in $hit_old of $cases screen records and the OUTPUT in $hit_new, where $cases and 0 were due"
    exit 1
fi
echo "  clause       the xterm-family clause is dead TWICE OVER: the output with it RESTORED records byte for byte what the output records, over $cases screen cases and every command row; and the identical marker inside it, reached through host_message(), is in $hit_old of $cases screen records on the INPUT and $hit_new on the output"
echo "  clause       -- which is the finding a reader would not predict: the compiled default is $(cut -d' ' -f2 "$tmp/fallback"), the removed row sorted BEFORE it, and vim_is_xterm() answers yes to it, so EVERY startup of the input resolved through the family clause and the surviving row was never reached.  After this phase it is, and it gives the same table"

# --- 6. THE TABLE, before and after ------------------------------------------------
python3 tools/ztermcheck.py "$state/old" "$tmp/term-old" >/dev/null &
python3 tools/ztermcheck.py "$tmp/c3" "$tmp/term-c3" >/dev/null &
python3 tools/ztermcheck.py "$tmp/c4" "$tmp/term-c4" >/dev/null &
wait
cp "$tmp/rec-new/ref-term.txt" "$tmp/term-new"
echo "  terminals    the nineteen rows, before and after -- tools/ztermcheck.py, \`+set term={name}\` on a real pty (zero phase 33):"
python3 - "$tmp/term-old" "$tmp/term-new" <<'PY'
import sys
a = open(sys.argv[1]).read().splitlines()
b = open(sys.argv[2]).read().splitlines()
w = max(len(x) for x in a)
for x, y in zip(a, b):
    print('               %-*s   %s   %s'
          % (w, x, '==' if x == y else '->', y.split(' -> ', 1)[1]))
PY

if ! python3 - "$f" "$tmp/term-old" "$tmp/term-new" "$new" "$GONE" > "$tmp/rule" 2>&1 <<'PY'
"""Exactly the names that lost a row moved, and each from resolving to refused.

Nothing here is written down: the refusal's leave-behind terminal is MEASURED from
the new binary by asking it with no `+set term=` at all, exactly as
pipes/zero33.sh measures it, and the set that must move is the input's table minus
the output's.
"""
import re
import sys
import tempfile
sys.path.insert(0, 'tools')
import termcheck
import ptyrun

src, wasp, nowp, binary, gone = sys.argv[1:6]
GONE = gone.split()
was, now = open(wasp).read().splitlines(), open(nowp).read().splitlines()
if len(was) != len(now) or len(was) != len(termcheck.TERMS):
    sys.exit('the two recordings hold %d and %d rows and tools/termcheck.py names %d'
             % (len(was), len(now), len(termcheck.TERMS)))

d = tempfile.mkdtemp(prefix='ztermcheck-')
out, _ = ptyrun.session(binary, [], [b':set term? t_Co?\r', b':q!\r'],
                        cwd=d, settle=1.0, env=termcheck.ENV)
default = None
for line in out.decode('utf-8', 'replace').splitlines():
    k = line.find('term=')
    if k >= 0 and not re.search(r'\bE\d+:', line):
        default = line[k:].split()[0]
        break
if not default:
    sys.exit('the binary answered nothing with no +set term= at all: what a refused '
             'name leaves the terminal as is unmeasurable, so nothing below is a rule')

bad = []
moved = []
for x, y in zip(was, now):
    name = x[x.index("'") + 1:x.rindex("'")]
    a, b = x.split(' -> ', 1)[1], y.split(' -> ', 1)[1]
    if name in GONE:
        moved.append(name)
        if 'term=' + name not in a.split():
            bad.append('%r lost its row but did not resolve BEFORE: %s' % (name, a))
        f = b.split()
        if not [t for t in f if re.fullmatch(r'E\d+', t)] \
                or next((t for t in f if t.startswith('term=')), None) != default:
            bad.append('%r lost its row and answered %s, where a refusal and %s '
                       'were due' % (name, b, default))
    elif a != b:
        bad.append('%r kept its row and moved: %s -> %s' % (name, a, b))
if sorted(moved) != sorted(GONE):
    bad.append('the rows that moved are %s and the rows removed are %s'
               % (' '.join(sorted(moved)), ' '.join(sorted(GONE))))
if bad:
    sys.exit('the table did not move the way the cut says it must:\n  '
             + '\n  '.join(bad))
print('exactly %d of the %d rows moved, and they are exactly the names that lost a '
      'row: each went from term=<itself> to a refusal, leaving the terminal at %s -- '
      'the same answer the %d names that never had a row already gave.  The other %d '
      'are byte-identical'
      % (len(moved), len(was), default,
         len(was) - len(moved) - len([1 for x in now
                                      if not re.search(r'\bE\d+\b', x)]),
         len(was) - len(moved)))
PY
then
    sed 's/^/  terminals    /' "$tmp/rule"
    exit 1
fi
sed 's/^/  terminals    /' "$tmp/rule"

# --- 7. THE INSTRUMENT CAN FAIL, in both directions --------------------------------
if ! python3 - "$tmp/term-new" "$tmp/term-c3" "$(cat "$tmp/c3.name")" \
     "$tmp/term-c4" "$(cat "$tmp/c4.name")" > "$tmp/able" 2>&1 <<'PY'
import re
import sys
now, c3, gone3, c4, back4 = sys.argv[1:6]
base = open(now).read().splitlines()


def one(path, name, want):
    rows = open(path).read().splitlines()
    if len(rows) != len(base):
        sys.exit('the control recorded %d rows where the output recorded %d'
                 % (len(rows), len(base)))
    moved = [(a, b) for a, b in zip(base, rows) if a != b]
    if len(moved) != 1:
        sys.exit('%s the %r row moved %d rows, and exactly 1 was due'
                 % (want, name, len(moved)))
    a, b = moved[0]
    got = a[a.index("'") + 1:a.rindex("'")]
    if got != name:
        sys.exit('%s the %r row moved the %r row instead' % (want, name, got))
    return a.split(' -> ', 1)[1], b.split(' -> ', 1)[1]


a3, b3 = one(c3, gone3, 'deleting')
if 'term=' + gone3 not in a3.split() or not re.search(r'\bE\d+\b', b3):
    sys.exit('deleting the %r row went %s -> %s, where resolving -> refused was due'
             % (gone3, a3, b3))
a4, b4 = one(c4, back4, 'restoring')
if not re.search(r'\bE\d+\b', a4) or 'term=' + back4 not in b4.split():
    sys.exit('restoring the %r row went %s -> %s, where refused -> resolving was due'
             % (back4, a4, b4))
print('deleting the %r row from THIS PHASE\'S OWN table moves exactly 1 of %d rows, '
      '%s -> %s; and putting the %r row back moves exactly 1, %s -> %s.  The '
      'instrument counts rows in both directions, so a cut of eight that moved seven '
      'or nine would have been seen'
      % (gone3, len(base), a3, b3, back4, a4, b4))
PY
then
    sed 's/^/  ablefail     /' "$tmp/able"
    exit 1
fi
sed 's/^/  ablefail     /' "$tmp/able"

# --- 7b. THE XTERM FAMILY, WHICH NO HARNESS ASKS ABOUT ------------------------------
# The `xterm` row was not one name.  find_builtin_term() carried a special case that
# handed that row's table to every name vim_is_xterm() accepts, so deleting the row
# deletes the family -- and not one of those names is among the nineteen
# tools/termcheck.py asks about.  So the phase owes probes, and the names are read
# out of vim_is_xterm()'s own prefix list in the source this phase was HANDED rather
# than written here.  Each must resolve on the old binary and be refused on the new.
if ! python3 - "$state/old.c" "$state/old" "$new" > "$tmp/family" 2>&1 <<'PY'
import concurrent.futures
import re
import sys
import tempfile
sys.path.insert(0, 'tools')
import cutil
import termcheck
import ptyrun

src, oldbin, newbin = sys.argv[1], sys.argv[2], sys.argv[3]
t = open(src, errors='surrogateescape').read()
lo, hi = cutil.find_definition(t, 'vim_is_xterm')
seg = t[lo:hi]
tests = re.findall(r'musl_strncasecmp\(\(char \*\)\(name\), \(char \*\)\("([^"]*)"\), '
                   r'\((\d+)\)\)\s*(==|!=)', seg)
if not tests:
    sys.exit('vim_is_xterm() holds no counted prefix test in the shape this probe '
             'reads, so the names below cannot be derived')
names = [p for p, n, op in tests if op == '==' and len(p) == int(n)]
skip = [p for p, _n, op in tests if op == '!=']
bad = [(p, n) for p, n, op in tests if op == '==' and len(p) != int(n)]
if bad:
    sys.exit('vim_is_xterm() compares %s against a length that is not the literal\'s'
             % bad)
if not names:
    sys.exit('vim_is_xterm() accepts no prefix, so this probe would be vacuous')


def ask(binary, name):
    d = tempfile.mkdtemp(prefix='family-')
    out, _ = ptyrun.session(binary, [], [b':set term=' + name.encode() + b'\r',
                                         b':set term? t_Co?\r', b':q!\r'],
                            cwd=d, settle=1.0, env=termcheck.ENV)
    return 'E522' in out.decode('utf-8', 'replace')


with concurrent.futures.ThreadPoolExecutor(max_workers=2 * len(names)) as ex:
    was = list(ex.map(lambda n: ask(oldbin, n), names))
    now = list(ex.map(lambda n: ask(newbin, n), names))
wrong = ([n for n, r in zip(names, was) if r]
         + [n for n, r in zip(names, now) if not r])
if wrong:
    sys.exit('the xterm family did not move the way deleting its row says it must: '
             '%s' % ' '.join(sorted(set(wrong))))
print('the `xterm` row was the whole xterm FAMILY, not one name: %d prefixes read '
      "out of vim_is_xterm() in the source this phase was handed -- %s -- every one "
      'of them resolved on the binary the phase was handed and every one is E522 '
      'here.  %s is the one vim_is_xterm() already excluded, and it was E522 either '
      'way.  None of these names is among the nineteen tools/termcheck.py asks '
      'about, which is why the phase owes these probes'
      % (len(names), ' '.join(names), ' '.join(skip) or '(none)'))
PY
then
    sed 's/^/  family       /' "$tmp/family"
    exit 1
fi
sed 's/^/  family       /' "$tmp/family"

# --- 8. SYMBOLS: the same set, with its reason -------------------------------------
gcc -c -O0 -fno-stack-protector -o "$tmp/new.o" "$f"
gcc -c -O0 -fno-stack-protector -o "$tmp/old.o" "$state/old.c"
nm -u "$tmp/new.o" | awk '{print $2}' | sort > "$tmp/u-new"
nm -u "$tmp/old.o" | awk '{print $2}' | sort > "$tmp/u-old"
went=$(comm -23 "$tmp/u-old" "$tmp/u-new" | tr '\n' ' ')
came=$(comm -13 "$tmp/u-old" "$tmp/u-new" | tr '\n' ' ')
if [ -n "$went$came" ]; then
    echo "  symbols      the libc surface moved, and this phase frees nothing: gone '$went', new '$came'"
    exit 1
fi
ext=$(nm --extern-only --defined-only "$tmp/new.o" | awk '{print $NF}' | sort | tr '\n' ' ')
if [ "$ext" != "main " ]; then
    echo "  symbols      the output defines external symbols other than main: $ext"
    exit 1
fi
echo "  symbols      \`nm -u\` is THE SAME $(grep -c '' "$tmp/u-new") symbols, a comm empty in both directions -- and that is a statement and not a disappointment: this phase deletes DATA, three static arrays and $(echo "$GONE" | wc -w) rows, and data calls nothing.  \`main\` is still the only external symbol"

# --- 9. THE BOUNDARY: the cut, its directives and its interface --------------------
for side in old new; do
    src=$f
    [ "$side" = old ] && src=$state/old.c
    awk '/^ *# *include / { exit } { print }' "$src" > "$tmp/cut-$side.c"
    d=$(grep -c '^ *#' "$tmp/cut-$side.c" || true)
    n=$(grep -c '' "$tmp/cut-$side.c")
    i=$(grep -c '^ *# *include ' "$src" || true)
    if [ "$d" != 0 ] || [ "$n" -lt 1000 ]; then
        echo "  boundary     the $side cut is $n lines with $d directive(s), and the core has none"
        exit 1
    fi
    if ! gcc -fsyntax-only "$tmp/cut-$side.c" 2>"$tmp/err-$side"; then
        echo "  boundary     the $side cut is not a complete translation unit:"
        head -5 "$tmp/err-$side" | sed 's/^/               /'
        exit 1
    fi
    gcc -fsyntax-only -Wall -Wextra -Wno-unused-parameter "$tmp/cut-$side.c" 2>&1 \
        | sed -n "s/.*warning: '\\([a-zA-Z_][a-zA-Z_0-9]*\\)' used but never defined.*/\\1/p" \
        | sort -u > "$tmp/iface-$side"
    eval "${side}_lines=$n"
    eval "${side}_inc=$i"
done
if [ "$old_inc" != "$new_inc" ]; then
    echo "  boundary     the file had $old_inc #include directives and has $new_inc: this phase removes none and adds none"
    exit 1
fi
if ! cmp -s "$tmp/iface-old" "$tmp/iface-new"; then
    echo "  boundary     the core -> host interface moved, and this phase is above the boundary entirely:"
    diff "$tmp/iface-old" "$tmp/iface-new" | sed 's/^/               /'
    exit 1
fi
echo "  boundary     the cut at the first \`#include\` is $old_lines -> $new_lines lines, 0 directives and 0 errors under -fsyntax-only either side, with $old_inc directives in the file and none above them; and the interface -- the $(grep -c '' "$tmp/iface-new") names \`used but never defined\`, computed here from the input and never written down -- is UNCHANGED, because every line this phase touches is a terminal description in the core"

# --- 10. STRUCTURE ------------------------------------------------------------------
python3 tools/zhostonly.py "$f"
tools/phasecheck.sh "$work" "$f" "$state/symbols"
