#!/bin/sh
# Zero phase 29 -- THE CASE TABLES BECOME ONE, AND IT IS THE UNION.
#
# Usage: pipes/zero29-edit.sh <work-dir> <state-dir>     (run from the repository root)
#
# `zero-vim.c` carried TWO complete Unicode simple-case maps and they did the same job.
# vim's own `toUpper[]`/`toLower[]` have been there since whim; zero phase 15 added
# musl's as `musl_toUpper[]`/`musl_toLower[]`, range-compressed into the same
# `convertStruct` shape and read by the same `utf_convert()`, so that `towupper` and
# `towlower` could leave `nm -u`.  Which of the two the editor consults is decided by
# `'casemap'`: with `internal` set it reads vim's, without it reads musl's.  A core with
# no C library has nothing to choose between, so this phase makes it ONE table -- and
# the table is the UNION.
#
# THE SURVEY THAT PROPOSED THIS SAID THE TWO "DIFFER ON 2 OF 5 PROBES", which was
# accurate about its probe set's reach and says nothing about the truth: five characters
# cannot see 193 codepoints.  Expanded over the whole of 0..0x10FFFF -- which is what
# this edit does, and what pipes/zero29-check.sh then does again from this machine's
# libc -- the two disagree at 97 upper codepoints and 96 lower, at NONE of which both
# map to different characters, and the split is lopsided:
#
#   * vim maps and musl does not, 96 upper and 96 lower: all of Vithkuqi (U+10570..,
#     U+10597..), all of Garay (U+10D50.., U+10D70..), the enclosed Latin letters
#     U+24B6..U+24CF and U+24D0..U+24E9, Glagolitic U+2C2F/U+2C5F, the recent Latin
#     Extended-D additions (U+A7C0 U+A7C1 U+A7C7 U+A7C8 ...), U+019B, U+0264, U+1C89 and
#     U+1C8A.  vim's table is simply NEWER -- it knows Unicode 14's Vithkuqi and Unicode
#     16's Garay, and musl's casemap.h predates both.
#   * musl maps and vim does not, EXACTLY ONE: U+00DF -> U+1E9E, the sharp s.
#
# So "delete musl's and use vim's" would lose the sharp s on the non-internal arm and
# "use musl's" would lose ninety-six.  Each table knew something the other did not, and
# the union is the only answer that keeps both.  IT IS COMPUTED HERE AND NOT WRITTEN
# DOWN: the edit expands both tables, refuses on a codepoint they map differently,
# requires that no existing row covers one it is about to insert -- `utf_convert()`
# binary-searches on `rangeEnd`, so a row inside another row is unreachable -- inserts a
# `{c,c,-1,offset}` row at its sorted place, and then re-expands and requires the result
# to be exactly the union, ascending and non-overlapping.
#
# THE ONE ROW IS A DELIBERATE DIVERGENCE FROM UNICODE AND THE USER TOOK IT KNOWINGLY.
# Unicode's SIMPLE uppercase of U+00DF is U+00DF; U+1E9E is musl's tailoring, and
# putting it into vim's own table changes the DEFAULT `'casemap'`, not only the vendored
# arm: `:s/.*/\U&/` on `ß` now draws `ẞ` where it drew `ß`.  What it buys is that the
# file stops contradicting itself.  `swapchar()` has hard-coded `ß -> ẞ` for `gU`, `g~`
# and `~` all along, so today the table and the keystroke give different answers for the
# same character; after this phase they agree.
#
# WHAT IT DOES, in three parts, every one of them computed:
#
#   A  the union, INSERTED INTO VIM'S ROWS, as above.
#   B  `musl_toUpper[]` and `musl_toLower[]`, deleted with the blank line above each,
#      as ONE span from the first table's head to the second's closing brace.
#   C  `musl_towupper()` and `musl_towlower()` repointed at `toUpper[]`/`toLower[]`.
#      The two three-line wrappers STAY: they are what the non-internal arm of
#      `utf_toupper()`/`utf_tolower()` calls and what the two dead `if (c >= 0x100)`
#      arms of `vim_toupper()`/`vim_tolower()` name, and deleting them is a different
#      idea.
#
# THE FORMAT IS THE FILE'S, PROVEN AND NOT ASSUMED.  Every one of the four tables is
# parsed and re-emitted before anything is changed, and the edit refuses unless the
# re-emission is byte-identical to the text it came from.  So the rows this phase writes
# are in `tools/canon.sh`'s shape by construction rather than by resemblance.
#
# THE DELTA IS REAL AND IT RUNS ON BOTH ARMS, which is the thing a reader gets wrong
# twice over.  On the NON-INTERNAL arm -- `:set casemap=` or `casemap=keepascii`, which
# read musl's table and now read the union -- 96 upper and 96 lower codepoints gain a
# mapping they never had, and the sharp s keeps the one it had.  On the DEFAULT arm,
# which reads vim's table, the single row arrives.  Six probe sessions move and six do
# not; `pipes/zero.delta` gains no line, because the recorded corpus cannot see any of
# it.
set -eu

work=${1:?usage: zero29-edit.sh <work-dir> <state-dir>}
state=${2:?usage: zero29-edit.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"

# The flags are read out of the boundary's makefile rather than written here a second
# time: zero's compile line is the boundary's (ZERO-GOAL.md rule 8).  The check needs
# the binary this phase was HANDED, to run its twelve probes on both sides.
cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")
cp "$f" "$state/old.c"
# shellcheck disable=SC2086
( cd "$state" && gcc $cflags $ldflags -o old old.c ) &
pid_old=$!

python3 - "$f" <<'PY'
import re
import sys

TAG = 'casemap'
path = sys.argv[1]
t = open(path, errors='surrogateescape').read()
before = t.count('\n')


def die(msg):
    sys.exit('  %-12s %s' % (TAG, msg))


def say(what):
    print('  %-12s %s' % (TAG, what))


def words(text, name):
    return len(re.findall(r'\b%s\b' % name, text))


def calls(text, name):
    return len(re.findall(r'(?<![\w])%s\s*\(' % name, text))


# ---- the four tables, parsed and PROVEN to re-emit as the text they came from -------
def block(name):
    m = re.search(r'^static convertStruct %s\[\] =\n\{\n(.*?)\n\};\n' % name,
                  t, re.M | re.S)
    if not m:
        die('there is no `static convertStruct %s[]` in the input, so this phase has '
            'nothing to merge' % name)
    return m


ROW = re.compile(r'        \{(0x[0-9a-f]+),(0x[0-9a-f]+),(-?\d+),(-?\d+)\},?')


def parse(name, body):
    rows = []
    for line in body.split('\n'):
        m = ROW.fullmatch(line)
        if not m:
            die('%s has a row this phase cannot read: %r' % (name, line))
        rows.append(tuple(int(x, 0) for x in m.groups()))
    return rows


def emit(rows):
    return ',\n'.join('        {0x%x,0x%x,%d,%d}' % r for r in rows)


def expand(name, rows):
    """{codepoint: target}, EXACTLY as utf_convert() reads the row.

    A row with `step < 0` is how this file spells a single codepoint, and it works
    because `(a - lo) % step` is 0 for every a when step is -1.  So a step < 0 row
    that spanned more than one codepoint would map the whole span; none does, and
    the edit refuses rather than guessing which reading was meant.
    """
    out = {}
    for lo, hi, step, off in rows:
        if step < 0:
            if lo != hi:
                die('%s has a step < 0 row spanning more than one codepoint: '
                    '{0x%x,0x%x,%d,%d}' % (name, lo, hi, step, off))
            out[lo] = lo + off
        else:
            for c in range(lo, hi + 1, step):
                out[c] = c + off
    return out


def ascending(name, rows):
    for a, b in zip(rows, rows[1:]):
        if a[1] >= b[0]:
            die('%s is not ascending and non-overlapping at {0x%x,0x%x,%d,%d} / '
                '{0x%x,0x%x,%d,%d}, and utf_convert() binary-searches on rangeEnd'
                % ((name,) + a + b))


NAMES = ('toUpper', 'toLower', 'musl_toUpper', 'musl_toLower')
blocks = {n: block(n) for n in NAMES}
rows = {n: parse(n, blocks[n].group(1)) for n in NAMES}
for n in NAMES:
    if emit(rows[n]) != blocks[n].group(1):
        die('%s does not re-emit as the text it came from, so the rows this phase '
            'writes would not be in the file\'s own shape' % n)
    ascending(n, rows[n])
maps = {n: expand(n, rows[n]) for n in NAMES}
say('four convertStruct tables read and re-emitted BYTE FOR BYTE as the text they came '
    'from -- toUpper %d rows / %d codepoints, toLower %d / %d, musl_toUpper %d / %d, '
    'musl_toLower %d / %d -- so what this phase writes is in the file\'s shape by '
    'construction and not by resemblance'
    % tuple(x for n in NAMES for x in (len(rows[n]), len(maps[n]))))

# ---- A. the union, computed ---------------------------------------------------------
merged = {}
report = []
for vim_n, musl_n in (('toUpper', 'musl_toUpper'), ('toLower', 'musl_toLower')):
    ev, em = maps[vim_n], maps[musl_n]
    clash = sorted(c for c in set(ev) & set(em) if ev[c] != em[c])
    if clash:
        die('%s and %s map %d codepoints to DIFFERENT characters (U+%04X -> %04X / '
            '%04X is the first), and a union is not defined there'
            % (vim_n, musl_n, len(clash), clash[0], ev[clash[0]], em[clash[0]]))
    vim_only = sorted(set(ev) - set(em))
    musl_only = sorted(set(em) - set(ev))
    for c in musl_only:
        for lo, hi, step, off in rows[vim_n]:
            if lo <= c <= hi:
                die('%s already has a row covering U+%04X ({0x%x,0x%x,%d,%d}), so a '
                    'single-codepoint row for it would be unreachable'
                    % (vim_n, c, lo, hi, step, off))
    new_rows = sorted(rows[vim_n] + [(c, c, -1, em[c] - c) for c in musl_only],
                      key=lambda r: r[0])
    union = dict(ev)
    union.update(em)
    if expand(vim_n, new_rows) != union:
        die('the merged %s does not expand to the union of the two' % vim_n)
    ascending(vim_n, new_rows)
    merged[vim_n] = new_rows
    report.append((vim_n, musl_n, len(vim_only), len(musl_only), musl_only,
                   len(rows[vim_n]), len(new_rows)))

for vim_n, musl_n, nv, nm_, musl_only, r0, r1 in report:
    say('%s: %d codepoints %s maps and %s does not -- they ARRIVE on the non-internal '
        'arm -- and %d the other way (%s), which ARRIVE on the default one; 0 where both '
        'map and disagree.  %d rows -> %d'
        % (vim_n, nv, vim_n, musl_n, nm_,
           ' '.join('U+%04X' % c for c in musl_only) or 'none', r0, r1))

for n in ('toUpper', 'toLower'):
    old_text = blocks[n].group(0)
    if t.count(old_text) != 1:
        die('%s[] is not in the file exactly once' % n)
    t = t.replace(old_text, 'static convertStruct %s[] =\n{\n%s\n};\n'
                  % (n, emit(merged[n])))

# ---- B. musl's two tables, deleted with the blank line above each --------------------
i = t.index('static convertStruct musl_toUpper[] =')
j = t.index('\n};\n', t.index('static convertStruct musl_toLower[] =')) + 4
if t[i - 2:i] != '\n\n':
    die('musl_toUpper[] does not open on its own paragraph, so the deletion would '
        'leave a blank line behind or take one it should not')
cut = t[i - 1:j]
if 'musl_toLower' not in cut or cut.count('static convertStruct') != 2:
    die('the span between musl_toUpper[] and the end of musl_toLower[] is not the '
        'two tables and nothing else')
t = t[:i - 1] + t[j:]
say('musl_toUpper[] and musl_toLower[] deleted, %d lines including the blank line above '
    'each -- one span, from the first table\'s head to the second\'s closing brace, and '
    'it holds exactly two `static convertStruct`' % cut.count('\n'))

# ---- C. the two wrappers, repointed --------------------------------------------------
for w, table in (('musl_towupper', 'toUpper'), ('musl_towlower', 'toLower')):
    old_call = ('    return utf_convert(a, musl_%s, (int)sizeof(musl_%s));\n'
                % (table, table))
    new_call = '    return utf_convert(a, %s, (int)sizeof(%s));\n' % (table, table)
    if t.count(old_call) != 1:
        die('%s() does not read musl_%s[] in the one shape this phase rewrites'
            % (w, table))
    t = t.replace(old_call, new_call)
say('musl_towupper() and musl_towlower() now read toUpper[] and toLower[] -- the two '
    'wrappers STAY, being what the non-internal arm of utf_toupper()/utf_tolower() '
    'calls and what the two dead `if (c >= 0x100)` arms of vim_toupper()/vim_tolower() '
    'name; deleting them is a different idea')

# ---- what must be true of the result --------------------------------------------------
for gone in ('musl_toUpper', 'musl_toLower'):
    if words(t, gone):
        die('%s survives' % gone)
for keep, want in (('musl_towupper', 4), ('musl_towlower', 4)):
    if words(t, keep) != want:
        die('%s has %d mentions, expected %d -- its prototype, its definition, the one '
            'live call and the dead one' % (keep, words(t, keep), want))
for n in ('toUpper', 'toLower'):
    # its own definition, the two in utf_to*()'s utf_convert call, and the two the
    # repointed wrapper now makes.
    if words(t, n) != 5:
        die('%s is named %d times, expected 5 -- its definition, utf_to%s()\'s '
            'utf_convert call and the wrapper\'s' % (n, words(t, n), n[2:].lower()))
if calls(t, 'utf_convert') != 6:
    die('utf_convert is called %d times, expected the same 6 -- this phase moves no '
        'call, it changes what two of them read' % calls(t, 'utf_convert'))
L = t.split('\n')
directives = [i for i, l in enumerate(L) if l.lstrip().startswith('#')]
if len(directives) != 11 or any(not re.match(r'^ *# *include ', L[i]) for i in directives):
    die('the directives are no longer eleven #includes and nothing else')
say('musl_toUpper and musl_toLower at 0 mentions, musl_towupper and musl_towlower at '
    '4 each, toUpper and toLower at 5 each, utf_convert at the same 6 calls, and the '
    'first of eleven #includes -- the boundary -- is still line %d with no directive '
    'above it' % (directives[0] + 1))
say('the file is %d lines and the input was %d' % (t.count('\n'), before))

open(path, 'w', errors='surrogateescape').write(t)
PY

# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  casemap      the input binary did not build with '$cflags' '$ldflags'"; exit 1; }
echo "  casemap      the input is $state/old, $(stat -c%s "$state/old") bytes, beside the source it was built from: this phase moves BOTH arms of 'casemap' and no record can see it, so the check runs twelve probes on both binaries and two built controls beside them"

# tools/phaserun.sh sweeps next, then runs pipes/zero29-check.sh.
