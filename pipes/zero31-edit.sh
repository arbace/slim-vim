#!/bin/sh
# Zero phase 31 -- abs and labs, the two the core took on trust.
# See ZERO-PLAN.md 4c, and ZERO-GOAL.md.
#
# Usage: pipes/zero31-edit.sh <work-dir> <state-dir>     (run from the repository root)
#
# THE CORE IS OPTIMISED FOR TRANSPILATION, NOT FOR PERFORMANCE, AND SO IT MAY NOT
# DEPEND ON LATENT COMPILER BEHAVIOUR (ZERO-PLAN.md 4c, the user's rule of
# 2026-09-19).  This phase is the first application of it, and it is the reason the
# phase exists at all -- because by every number this pipeline usually reports, it
# does nothing.
#
# `abs` and `labs` are CALLED by the core, at three sites, and appear in `nm -u`
# ZERO times.  gcc lowers both to inline arithmetic -- measured on the input, `gcc
# -S` of the whole file contains not one mention of either name -- and NOTHING IN
# THE LANGUAGE PROMISES THAT.  A compiler that emitted the calls the source
# literally asks for would silently have added two libc symbols to a file whose
# whole claim is the shortness of that list.  So this phase FREES NO SYMBOL and must
# say so as an equality rather than let a reader expect a vendoring phase to move
# the count: what it removes is a dependence on behaviour nothing states.
#
# WHAT IT DOES, in three parts:
#
#   the two prototypes    `long labs(long n);` and `int abs(int n);`, which zero
#                         phase 26 wrote into the core's block of libc declarations
#                         when the headers were still above it.  The block loses two
#                         of its entries and nothing else changes in it.
#   the three call sites  8152 `musl_labs((long)get_cursor_rel_lnum(...))` in the
#                         number column, 41824 `musl_labs(curwin->w_topline -
#                         prev_topline)` in scroll_with_sms, and 77379
#                         `musl_abs(wp->w_height - wp->w_prev_height)` in
#                         last_status_rec.  The line numbers are where they were
#                         when this was written and nothing below depends on them.
#   the two definitions   `static musl_abs` and `static musl_labs`, in the `musl_`
#                         block phases 14 and 15 built, immediately above
#                         `musl_bsearch` so that the four `<stdlib.h>` scalar
#                         functions the core owns -- musl_atoi, musl_atol, musl_abs,
#                         musl_labs -- sit together and above every use.
#
# MUSL'S SPELLING IS COPIED AND NOT IMPROVED, which is phase 14's rule applied to
# two more functions.  /root/musl/src/stdlib/abs.c and labs.c are one line each:
#
#     int abs(int a) { return a>0 ? a : -a; }
#     long labs(long a) { return a>0 ? a : -a; }
#
# `a > 0 ? a : -a` and `a < 0 ? -a : a` ARE THE SAME FUNCTION, and the check proves
# it twice rather than arguing it: the two spellings compile to BYTE-IDENTICAL
# machine code at -O0 and at -O2, and they agree at every one of the 4,294,967,296
# `int` values.  Having established that, the rule is to write what musl writes.
#
# AND THE UNDEFINED BEHAVIOUR IS COPIED WITH IT.  `-a` overflows at `INT_MIN` and at
# `LONG_MIN`, so `musl_abs(INT_MIN)` is undefined -- and so is `abs(INT_MIN)`, and so
# is musl's own `abs`, by exactly the same expression.  THE VENDORED PAIR IS
# FAITHFUL RATHER THAN SAFER, deliberately: a phase that quietly made the core's
# arithmetic differ from the libc it is replacing would be a behaviour change
# wearing a vendoring phase's clothes.  What the check does instead is measure
# whether the three call sites can reach the value, and the answer is no in one case
# by a clamp in this file and in the other two by the arithmetic of line numbers.
#
# THE INPUT BINARY IS BUILT HERE with SOURCE_DATE_EPOCH=0, and the check needs it for
# more than a comparison: the corpus CANNOT SEE any of the three call sites (measured
# -- an instrumented build enters none of them in 106 records), so this phase owes
# probes of its own, and those probes are run on the binary this phase was handed and
# on its own and required to draw the same screen.
set -eu

work=${1:?usage: zero31-edit.sh <work-dir> <state-dir>}
state=${2:?usage: zero31-edit.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"

# The flags are read out of the boundary's makefile rather than written here a second
# time: zero's compile line is the boundary's (ZERO-GOAL.md rule 8).
cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")
cp "$f" "$state/old.c"
# shellcheck disable=SC2086
( cd "$state" && SOURCE_DATE_EPOCH=0 gcc $cflags $ldflags -o old old.c ) &
pid_old=$!

python3 - "$f" <<'PY'
import bisect
import re
import sys

TAG = 'arith'
path = sys.argv[1]
t = open(path, errors='surrogateescape').read()


def die(msg):
    sys.exit('  %-12s %s' % (TAG, msg))


def say(what):
    print('  %-12s %s' % (TAG, what))


def mentions(text, name):
    return len(re.findall(r'\b%s\b' % name, text))


def blank_runs(text):
    L = text.split('\n')
    return sum(1 for i in range(1, len(L)) if L[i] == '' and L[i - 1] == '')


before_lines = t.count('\n')
runs_before = blank_runs(t)

# ---- 0. the file this edit was written against ---------------------------------------
# ELEVEN DIRECTIVES, contiguous, every one an `#include` of a system header -- and
# since zero phase 27 THEY ARE NOT AT THE TOP.  The first of them is the boundary
# between the core and the host, so everything this phase writes must land ABOVE it.
lines = t.split('\n')
d = [i for i, l in enumerate(lines) if l.lstrip().startswith('#')]
if len(d) != 11 or d != list(range(d[0], d[0] + 11)):
    die('the file does not have exactly eleven contiguous preprocessor directives: '
        '%d at %s' % (len(d), ' '.join(str(i + 1) for i in d[:4])))
INC = re.compile(r'^#include <[A-Za-z0-9_/.]+>$')
if any(not INC.match(lines[i]) for i in d):
    die('a directive is not an `#include <...>` of a system header, and no phase may '
        'add one')
cut = d[0]
for name in ('musl_abs', 'musl_labs'):
    if mentions(t, name):
        die('`%s` already occurs %d times -- this phase introduces it, so an existing '
            'mention means the phase has already run or the name is taken'
            % (name, mentions(t, name)))
say('eleven contiguous `#include <...>` directives, the first at line %d and the '
    'boundary between the core and the host; `musl_abs` and `musl_labs` at zero'
    % (cut + 1))

# ---- 1. the two prototypes, found as a BLOCK rather than by line number ---------------
# Zero phase 26 wrote the core its own libc declarations while the headers were still
# above them to be cross-checked against, and zero phase 27 moved the headers below.
# The block is the run of top-level declarations above the first `static`: a line at
# column 0 that is a declaration and ends in `;`.  It is computed, so this refuses on a
# file whose shape has moved instead of deleting whatever is on lines 31 and 32.
first_static = next(i for i, l in enumerate(lines) if l.startswith('    static'))
proto = [i for i, l in enumerate(lines[:first_static])
         if l and not l[0].isspace() and l.endswith(';') and '(' in l
         and not l.startswith(('enum', 'typedef', 'static'))]
if not proto or proto != list(range(proto[0], proto[0] + len(proto))):
    die('the core\'s libc declarations are not one contiguous block above the first '
        '`static`: %d lines at %s'
        % (len(proto), ' '.join(str(i + 1) for i in proto[:4])))
block = [lines[i] for i in proto]
GO = ['long labs(long n);', 'int abs(int n);']
for line in GO:
    if block.count(line) != 1:
        die('`%s` is not in the core\'s libc declaration block exactly once -- the '
            'block is: %s' % (line, ' | '.join(block)))
    if t.count(line + '\n') != 1:
        die('`%s` is not a line of its own exactly once in the whole file' % line)
    t = t.replace(line + '\n', '', 1)
say('the core declares %d libc functions above the first `static` and will declare '
    '%d: `long labs(long n);` and `int abs(int n);` go, and they are the two the '
    'core asked libc for and never got' % (len(block), len(block) - 2))

# ---- 2. the three call sites, by a literal-aware single pass -------------------------
# CLAUDE.md, *Rename a name across the whole file*: literal-aware, because a name in a
# string is DATA, and single-pass, because a literal span is an OFFSET and every offset
# after the first replacement is wrong.  Measured here: no literal in this file contains
# either name, so the exclusion is belt and braces -- and a rename that did not have it
# would be a guess.  `\babs\b` does not match inside `musl_abs`: `_` is a word character.
def literal_spans(text):
    out = []
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c == '"' or c == "'":
            j = i + 1
            while j < n:
                if text[j] == '\\':
                    j += 2
                    continue
                if text[j] == c or text[j] == '\n':
                    break
                j += 1
            if j >= n or text[j] != c:
                die('an unterminated %s literal at line %d -- the scanner has lost its '
                    'place and every span after it would be wrong'
                    % ('string' if c == '"' else 'character',
                       text.count('\n', 0, i) + 1))
            out.append((i, j + 1))
            i = j + 1
        else:
            i += 1
    return out


S = literal_spans(t)
starts = [a for a, _ in S]
holding = [t[a:b] for a, b in S if re.search(r'\b(abs|labs)\b', t[a:b])]
if holding:
    die('a string or character literal mentions `abs` or `labs`, so a rename would '
        'change what the editor PRINTS: %s' % ' / '.join(holding[:3]))
NEW = {'abs': 'musl_abs', 'labs': 'musl_labs'}
parts, last, n = [], 0, dict.fromkeys(NEW, 0)
for m in re.finditer(r'\b(labs|abs)\b', t):
    k = bisect.bisect_right(starts, m.start()) - 1
    if k >= 0 and S[k][0] <= m.start() < S[k][1]:
        continue
    parts.append(t[last:m.start()])
    parts.append(NEW[m.group(1)])
    last = m.end()
    n[m.group(1)] += 1
parts.append(t[last:])
t = ''.join(parts)
if (n['labs'], n['abs']) != (2, 1):
    die('the rename reached %d `labs` and %d `abs`, and this phase was measured on 2 '
        'and 1 -- the two prototypes are already gone, so what is left is exactly the '
        'call sites' % (n['labs'], n['abs']))
say('the three call sites are the core\'s own now: two `labs` -- the number column\'s '
    'relative line number and scroll_with_sms\'s topline difference -- and one `abs`, '
    'last_status_rec\'s window-height difference.  One pass, outside every literal, '
    'and %d literals were scanned and none mentions either name' % len(S))

# ---- 3. the two definitions, copied from musl -----------------------------------------
# /root/musl/src/stdlib/abs.c and labs.c, whole:
#
#     int abs(int a) { return a>0 ? a : -a; }
#     long labs(long a) { return a>0 ? a : -a; }
#
# WRITTEN THE WAY THIS FILE WRITES A FUNCTION -- the name at column 0 on a line of its
# own, which is what tools/funcreach.py reads a definition by, and which phase 14 got
# wrong and paid a restyle phase for.  tools/canon.sh is the check that the rest of the
# shape is right, and it must be a no-op on the output.
#
# MUSL'S TERNARY IS COPIED AND NOT TURNED ROUND.  `a < 0 ? -a : a` is the same function
# -- the check proves it as byte-identical machine code and over all 2^32 ints -- so
# there is nothing to gain by writing it differently and one more difference from the
# source of record to explain.
DEFS = '''    static int
musl_abs(int a)
{
    return a > 0 ? a : -a;
}

    static long
musl_labs(long a)
{
    return a > 0 ? a : -a;
}

'''
ANCHOR = '    static void *\nmusl_bsearch('
if t.count(ANCHOR) != 1:
    die('`musl_bsearch`\'s definition is not in the file exactly once, so there is no '
        'unambiguous place for these two: they belong with musl_atoi and musl_atol, '
        'the other <stdlib.h> functions the core owns')
t = t.replace(ANCHOR, DEFS + ANCHOR, 1)

# ---- 4. what the file is now -----------------------------------------------------------
lines = t.split('\n')
d = [i for i, l in enumerate(lines) if l.lstrip().startswith('#')]
if len(d) != 11 or d != list(range(d[0], d[0] + 11)):
    die('the eleven directives are no longer eleven contiguous lines')
for name, want in (('abs', 0), ('labs', 0), ('musl_abs', 2), ('musl_labs', 3)):
    if mentions(t, name) != want:
        die('`%s` has %d mentions after the cut, expected %d' % (name, mentions(t, name), want))
for name in ('musl_abs', 'musl_labs'):
    at = [i for i, l in enumerate(lines) if l.startswith(name + '(')]
    if len(at) != 1:
        die('`%s` is not defined by exactly one line beginning at column 0, which is '
            'how tools/funcreach.py reads a definition' % name)
    if at[0] > d[0]:
        die('`%s` is defined BELOW the first `#include`, which is the boundary: it is '
            'core code and every one of its callers is above the line' % name)
if t.count('\n') != before_lines + 10:
    die('the file is %d lines and the input was %d -- expected exactly ten more, the '
        'two five-line definitions and their two blank lines less the two prototypes'
        % (t.count('\n'), before_lines))
if blank_runs(t) != runs_before:
    die('the edit left %d runs of two blank lines where there were %d'
        % (blank_runs(t), runs_before))
say('`abs` and `labs` are at 0 mentions in the whole file, `musl_abs` at 2 and '
    '`musl_labs` at 3 -- a definition and its calls -- both defined at column 0 above '
    'the boundary, %d -> %d lines and the blank-line runs exactly as before'
    % (before_lines, t.count('\n')))

open(path, 'w', errors='surrogateescape').write(t)
PY

# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  arith        the input binary did not build with '$cflags' '$ldflags'"; exit 1; }
echo "  arith        the input is $state/old, $(stat -c%s "$state/old") bytes, built with SOURCE_DATE_EPOCH=0 beside the source it came from.  THE BINARY WILL MOVE and no cmp is attempted: at -O0 a call to a static function is a call and inline arithmetic is not, so the check accounts for the difference instruction by instruction and takes its behavioural evidence from recordings and from probes"

# tools/phaserun.sh sweeps next, then runs pipes/zero31-check.sh.
