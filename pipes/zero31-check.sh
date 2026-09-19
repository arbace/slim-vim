#!/bin/sh
# Zero phase 31, the check -- abs and labs, the two the core took on trust.
# See pipes/zero31-edit.sh, and ZERO-PLAN.md 4c.
#
# Usage: pipes/zero31-check.sh <work-dir> <state-dir>    (run from the repository root)
#
# Runs after pipes/zero31-edit.sh and the sweep tools/phaserun.sh runs between them, and
# reads nothing from the edit's shell -- only the work tree and the state directory.
# What the edit left there is `old.c`, the source this phase was HANDED, and `old`, that
# source built with SOURCE_DATE_EPOCH=0 and the boundary's own flags.
#
# `nm -u` CANNOT MOVE HERE, AND THAT IS THE PHASE.  A vendoring phase that leaves the
# symbol count alone reads like a failure, so this check states it as an equality and
# says why: `abs` and `labs` were called by the core at three sites and were in `nm -u`
# ZERO times, because gcc lowers both to inline arithmetic.  Section 5 measures that
# rather than asserting it -- `gcc -S` of the INPUT contains not one mention of either
# name -- and that is exactly the problem.  Nothing in the language promises it.  A
# compiler that emitted the calls the source asks for would have added two libc symbols
# to a file whose whole claim is the shortness of that list, and no check in this
# pipeline would have said so until it happened.  ZERO-PLAN.md 4c: the core is
# optimised for transpilation, not for performance, and may not depend on latent
# compiler behaviour.
#
# WHAT IS CLAIMED, in seven parts:
#
#   ARITHMETIC  computed FROM THE INPUT: `abs` and `labs` are 0 in the output where the
#               input had 2 and 3, `musl_abs` is 2 and `musl_labs` 3, the core's libc
#               declaration block loses exactly those two entries, both definitions
#               begin at column 0 ABOVE the boundary, and the file is ten lines longer.
#   THE SAME FUNCTION
#               musl writes `a>0 ? a : -a` and this copies it rather than turning it
#               round, and the check proves the choice is free TWICE: the two spellings,
#               taken OUT OF THE OUTPUT, compile to BYTE-IDENTICAL machine code at -O0
#               and at -O2, and they agree at all 4,294,967,296 `int` values and at
#               20,000,006 `long` ones including LONG_MIN and LONG_MAX.
#   THE UB      `-a` overflows at INT_MIN and LONG_MIN, so both vendored functions are
#               undefined there -- and so are libc's, by the same expression, which is
#               why the pair is FAITHFUL RATHER THAN SAFER.  What is measured is whether
#               the three call sites can reach the value, and section 7 answers it: the
#               largest magnitude any of them is ever handed, across 106 records and 51
#               probe calls, is 22.  The static reason is in the file -- window heights
#               are clamped by `limit_screen_size()` at 1,000 rows, and the two `labs`
#               arguments are differences of line numbers, which are >= 1.
#   CANON       tools/canon.sh is a NO-OP: the two definitions are written the way this
#               file writes every other function, name at column 0 and all.
#   THE BOUNDARY
#               `make editor.c`'s cut, computed here by the same awk clause: 0
#               directives, `-fsyntax-only` with no error and no warning that is not a
#               boundary name, and THE SET OF NAMES TAKEN FROM THE INPUT'S OWN CUT and
#               required back -- never written out, because phase 28 renamed one of them
#               and a check that quotes a list is a check that goes stale in silence.
#   THE BINARY  IT MOVES, and no `cmp` is attempted: at -O0 a call to a static function
#               is a call and inline arithmetic is not.  What is asserted instead is
#               that the difference is ACCOUNTED FOR INSTRUCTION BY INSTRUCTION --
#               `musl_abs` + `musl_labs` + the three callers' size changes = the
#               object's whole `.text` delta -- and that every section of the linked
#               image keeps its size and its address.
#   BEHAVIOUR   two full recordings byte-identical; AND THE CORPUS CANNOT SEE THIS PHASE
#               AT ALL, measured -- an instrumented build enters none of the three call
#               sites in 106 records.  So the phase owes probes, and it runs three, one
#               per site, on the binary it was handed and on its own.
#
# THE PROBES, and each is a way of reaching a site nothing else here reaches:
#
#   rnu   `+set rnu`, sixty lines, `gg`     46 calls at the number column's labs,
#                                          arguments from -21 to 22
#   sms   sixty long wrapped lines, then    3 calls at scroll_with_sms's labs,
#         CTRL-F CTRL-F CTRL-B CTRL-B       arguments -6 and 5
#   stl   `:set laststatus=2` then `=0`     2 calls at last_status_rec's abs, -1 and 1
#
# AND TWO OF THE THREE ARE PROVEN ABLE TO FAIL, by a control whose `musl_abs` and
# `musl_labs` return their argument unchanged: `rnu` moves by 15 bytes and `sms` moves.
# `stl` DOES NOT MOVE AND THAT IS REPORTED RATHER THAN HIDDEN -- the site is reached
# twice and its answer guards only `w_prev_height = w_height`, an assignment
# `win_new_height()` already makes on every path that changes a height, so no session
# tried here draws anything different.  The site is proven REACHED and not proven
# OBSERVABLE, and the phase's real evidence for it is section 2: it is the same
# function.
set -eu

work=${1:?usage: zero31-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero31-check.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"
before_lines=$(cat "$state/input-lines")

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")

# Everything slow starts first and is waited for where its answer is needed: the
# reproducible build of the output, the instrumented build, the control, the exhaustive
# equivalence probe and tools/canon.sh are all seconds the assertions can be spending.
python3 - "$f" "$tmp" <<'PY'
import sys

TAG = 'arith'
t = open(sys.argv[1], errors='surrogateescape').read()
out = sys.argv[2]

TERNARY = '    return a > 0 ? a : -a;\n'
if t.count(TERNARY) != 2:
    sys.exit('  %-12s `%s` is not in the output exactly twice, so neither variant below '
             'could be built from it' % (TAG, TERNARY.strip()))

# THE CONTROL: both vendored functions return their argument unchanged.  It is one
# broken implementation and not three broken call sites, which is what makes it a
# control on the phase rather than on a probe.
open('%s/wrong.c' % out, 'w', errors='surrogateescape').write(
    t.replace(TERNARY, '    return a;\n'))

# THE INSTRUMENT.  A probe on each of the three arguments that writes the site and the
# VALUE to stderr -- the value, and not a marker, because the question this phase has to
# answer is how close to INT_MIN and LONG_MIN the three sites can be driven.  It is
# phase 9's and phase 13's shape with a number in it.  `write` is the core's own
# declaration, immediately above.
SITES = [
    ('num = musl_labs((long)get_cursor_rel_lnum(wp, wlv->lnum));',
     'num = musl_labs(zprobe(1, (long)get_cursor_rel_lnum(wp, wlv->lnum)));'),
    ('if (musl_labs(curwin->w_topline - prev_topline) > (dir ==  (-1) ))',
     'if (musl_labs(zprobe(2, curwin->w_topline - prev_topline)) > (dir ==  (-1) ))'),
    ('if (musl_abs(wp->w_height - wp->w_prev_height) == 1)',
     'if (musl_abs((int)zprobe(3, (long)(wp->w_height - wp->w_prev_height))) == 1)'),
]
PROBE = r'''    static long
zprobe(int site, long v)
{
    char buf[32];
    int i = 31;
    int neg = v < 0;
    unsigned long u = neg ? -(unsigned long)v : (unsigned long)v;

    buf[i] = '\n';
    i--;
    while (1)
    {
        buf[i] = (char)('0' + (int)(u % 10UL));
        i--;
        u /= 10UL;
        if (u == 0UL)
        {
            break;
        }
    }
    if (neg)
    {
        buf[i] = '-';
        i--;
    }
    buf[i] = ' ';
    i--;
    buf[i] = (char)('0' + site);
    i--;
    buf[i] = 'Z';
    write(2, buf + i, (usize)(32 - i));
    return v;
}

'''
ANCHOR = '    static void *\nmusl_bsearch('
s = t
for old, new in SITES:
    if s.count(old) != 1:
        sys.exit('  %-12s the call site `%s` is not in the output exactly once, so the '
                 'instrument cannot be placed and this phase cannot say whether the '
                 'corpus reaches it' % (TAG, old[:60]))
    s = s.replace(old, new, 1)
if s.count(ANCHOR) != 1:
    sys.exit('  %-12s musl_bsearch is not in the output exactly once' % TAG)
open('%s/values.c' % out, 'w', errors='surrogateescape').write(
    s.replace(ANCHOR, PROBE + ANCHOR, 1))

# THE TWO SPELLINGS, TAKEN OUT OF THE OUTPUT rather than written here again, so that
# section 2 cannot pass while the file says something else.
i = t.index('musl_abs(int a)')
j = t.index('\n}\n', t.index('musl_labs(long a)')) + 3
body = t[t.rindex('    static int\n', 0, i):j]
if body.count(TERNARY) != 2 or 'musl_abs' not in body or 'musl_labs' not in body:
    sys.exit('  %-12s the two definitions could not be lifted out of the output' % TAG)
open('%s/spell1.c' % out, 'w').write(
    body + 'int a1(int x) { return musl_abs(x); }\nlong a2(long x) { return musl_labs(x); }\n')
open('%s/spell2.c' % out, 'w').write(
    body.replace(TERNARY, '    return a < 0 ? -a : a;\n')
    + 'int a1(int x) { return musl_abs(x); }\nlong a2(long x) { return musl_labs(x); }\n')
print('  %-12s the control (both vendored functions return their argument unchanged), '
      'the instrument (the site and the VALUE at each of the three call sites) and the '
      'two spellings, all built FROM THE OUTPUT' % TAG)
PY

# shellcheck disable=SC2086
( SOURCE_DATE_EPOCH=0 gcc $cflags $ldflags -o "$tmp/new" "$f" ) &
pid_new=$!
# shellcheck disable=SC2086
( SOURCE_DATE_EPOCH=0 gcc $cflags $ldflags -o "$tmp/values" "$tmp/values.c" 2>"$tmp/values.log" ) &
pid_val=$!
# shellcheck disable=SC2086
( SOURCE_DATE_EPOCH=0 gcc $cflags $ldflags -o "$tmp/wrong" "$tmp/wrong.c" 2>"$tmp/wrong.log" ) &
pid_wrong=$!

# The objects for the size arithmetic of section 6: -O0 and no -s, so `nm -S` can say
# what each function costs.
( gcc -c -O0 -fno-stack-protector -o "$tmp/old.o" "$state/old.c" ) &
pid_oo=$!
( gcc -c -O0 -fno-stack-protector -o "$tmp/new.o" "$f" ) &
pid_no=$!

# THE EXHAUSTIVE EQUIVALENCE, as a program rather than a paragraph, so that the claim is
# a measurement at every boundary and not a memory.  -O2 with noipa on all four, so the
# loop really runs: at -O0 it takes fourteen seconds and at -O2 without noipa gcc proves
# the two identical and the probe becomes a tautology about the optimiser.
cat > "$tmp/same.c" <<'EOF'
#include <stdio.h>
#include <limits.h>
__attribute__((noipa)) static int  musl_abs(int a)    { return a > 0 ? a : -a; }
__attribute__((noipa)) static long musl_labs(long a)  { return a > 0 ? a : -a; }
__attribute__((noipa)) static int  other_abs(int a)   { return a < 0 ? -a : a; }
__attribute__((noipa)) static long other_labs(long a) { return a < 0 ? -a : a; }
int main(void)
{
    long i, bad_i = 0, bad_l = 0, n = 20000000;
    long edge[6] = {LONG_MIN, LONG_MIN + 1, -1, 0, 1, LONG_MAX};
    unsigned long s = 88172645463325252UL;
    for (i = INT_MIN; i <= INT_MAX; i++)
        if (musl_abs((int)i) != other_abs((int)i)) bad_i++;
    for (i = 0; i < 6; i++)
        if (musl_labs(edge[i]) != other_labs(edge[i])) bad_l++;
    for (i = 0; i < n; i++) {
        s ^= s << 13; s ^= s >> 7; s ^= s << 17;
        if (musl_labs((long)s) != other_labs((long)s)) bad_l++;
    }
    printf("ints %ld bad %ld  longs %ld bad %ld  absmin %d %d  labsmin %ld %ld\n",
           (long)INT_MAX - (long)INT_MIN + 1, bad_i, n + 6, bad_l,
           musl_abs(INT_MIN), other_abs(INT_MIN),
           musl_labs(LONG_MIN), other_labs(LONG_MIN));
    return (bad_i || bad_l) ? 1 : 0;
}
EOF
( gcc -O2 -o "$tmp/same" "$tmp/same.c" && "$tmp/same" > "$tmp/same.txt" ) &
pid_same=$!

cp "$f" "$tmp/canon.c"
( tools/canon.sh "$tmp/canon.c" >"$tmp/canon.log" 2>&1 ) &
pid_canon=$!

# --- 1. the source, as arithmetic on the input ------------------------------------------
python3 - "$f" "$state/old.c" "$before_lines" <<'PY'
import re
import sys

TAG = 'arith'
new = open(sys.argv[1], errors='surrogateescape').read()
old = open(sys.argv[2], errors='surrogateescape').read()
before_lines = int(sys.argv[3])
fail = []


def mentions(text, name):
    return len(re.findall(r'\b%s\b' % name, text))


def split(text, which):
    lines = text.split('\n')
    d = [i for i, l in enumerate(lines) if l.lstrip().startswith('#')]
    if len(d) != 11 or d != list(range(d[0], d[0] + 11)):
        sys.exit('  %-12s %s does not have eleven contiguous directives: %d at %s.  The '
                 'first one IS the boundary and every count below distinguishes the core '
                 'from the host'
                 % (TAG, which, len(d), ' '.join(str(i + 1) for i in d[:3])))
    return lines, d[0]


olines, ocut = split(old, 'old.c')
nlines, ncut = split(new, 'the output')
if len(olines) - 1 != before_lines:
    fail.append('the state directory says the edit was handed %d lines and old.c has %d'
                % (before_lines, len(olines) - 1))

# THE ARITHMETIC, computed from the input.  Nothing here is a number this file states
# except the product: 0 and 0, and one definition plus its calls.
in_abs, in_labs = mentions(old, 'abs'), mentions(old, 'labs')
if (in_abs, in_labs) != (2, 3):
    fail.append('the input has %d `abs` and %d `labs`, and this phase was measured on 2 '
                'and 3 -- a prototype and one call, a prototype and two calls'
                % (in_abs, in_labs))
for name, want, why in (
        ('abs', 0, 'the prototype and the call site are both gone'),
        ('labs', 0, 'the prototype and both call sites are gone'),
        ('musl_abs', in_abs, 'its definition and the one call the prototype served'),
        ('musl_labs', in_labs, 'its definition and the two calls'),
):
    if mentions(new, name) != want:
        fail.append('`%s` has %d mentions in the output, expected %d -- %s'
                    % (name, mentions(new, name), want, why))
for name in ('musl_abs', 'musl_labs'):
    at = [i for i, l in enumerate(nlines) if l.startswith(name + '(')]
    if len(at) != 1:
        fail.append('`%s` is not defined by exactly one line beginning at column 0, '
                    'which is how tools/funcreach.py reads a definition -- %d found'
                    % (name, len(at)))
    elif at[0] > ncut:
        fail.append('`%s` is defined below the first `#include`, which is the boundary, '
                    'and every one of its callers is above it' % name)
    elif nlines[at[0] - 1] not in ('    static int', '    static long'):
        fail.append('`%s` is not introduced by a `    static <type>` line of its own'
                    % name)

# THE DECLARATION BLOCK, found the way the edit finds it and counted either side.
def block(lines, cut):
    first = next(i for i, l in enumerate(lines) if l.startswith('    static'))
    at = [i for i, l in enumerate(lines[:first])
          if l and not l[0].isspace() and l.endswith(';') and '(' in l
          and not l.startswith(('enum', 'typedef', 'static'))]
    return [lines[i] for i in at]


ob, nb = block(olines, ocut), block(nlines, ncut)
gone = [l for l in ob if l not in nb]
if sorted(gone) != ['int abs(int n);', 'long labs(long n);'] or len(nb) != len(ob) - 2:
    fail.append('the core\'s libc declaration block went from %d entries to %d and lost '
                '%s -- it must lose exactly `long labs(long n);` and `int abs(int n);`'
                % (len(ob), len(nb), ' / '.join(gone) or 'nothing'))
if len(nlines) - len(olines) != 10:
    fail.append('the file is %d lines and the input was %d -- expected exactly ten more: '
                'two five-line definitions and their blank lines, less two prototypes'
                % (len(nlines) - 1, len(olines) - 1))
if ncut - ocut != 10:
    fail.append('the core is %d lines and was %d, a difference of %d where 10 was '
                'expected -- everything this phase writes is core code' % (ncut, ocut, ncut - ocut))
if (len(nlines) - ncut) != (len(olines) - ocut):
    fail.append('the host changed size, and this phase does not touch it')


def runs(text):
    L = text.split('\n')
    return sum(1 for i in range(1, len(L)) if L[i] == '' and L[i - 1] == '')


if runs(new) != runs(old):
    fail.append('the edit left %d runs of two blank lines where there were %d'
                % (runs(new), runs(old)))
if fail:
    for line in fail:
        print('  %-12s %s' % (TAG, line))
    sys.exit(1)
print('  %-12s `abs` %d -> 0 and `labs` %d -> 0 in the whole file; `musl_abs` 0 -> %d '
      'and `musl_labs` 0 -> %d, each a definition at column 0 and the calls its '
      'prototype used to serve.  Every count is computed FROM THE INPUT'
      % (TAG, in_abs, in_labs, in_abs, in_labs))
print('  %-12s the core\'s libc declaration block is %d entries and was %d, and the two '
      'it lost are `long labs(long n);` and `int abs(int n);` -- what phase 26 wrote '
      'when the headers were still above it.  The core is %d lines against %d (+10) and '
      'the host is unchanged at %d'
      % ('', len(nb), len(ob), ncut, ocut, len(nlines) - ncut))
PY

# --- 2. the two spellings are the same function ------------------------------------------
# musl writes `a>0 ? a : -a`; this file copies it.  The check is that the choice costs
# nothing, so that copying rather than improving is a rule and not a compromise.
for opt in -O0 -O2; do
    for s in spell1 spell2; do
        gcc $opt -c -fno-stack-protector -o "$tmp/$s$opt.o" "$tmp/$s.c" 2>"$tmp/$s.log" \
            || { echo "  arith        the $s spelling did not compile at $opt:"; head -3 "$tmp/$s.log" | sed 's/^/               /'; exit 1; }
        objcopy -O binary --only-section=.text "$tmp/$s$opt.o" "$tmp/$s$opt.text"
    done
    [ -s "$tmp/spell1$opt.text" ] || { echo "  arith        objcopy wrote an empty .text, and comparing two empty streams reports every pair identical (CLAUDE.md)"; exit 1; }
    cmp -s "$tmp/spell1$opt.text" "$tmp/spell2$opt.text" || {
        echo "  arith        THE TWO SPELLINGS COMPILE DIFFERENTLY at $opt.  \`a > 0 ? a : -a\`"
        echo "               and \`a < 0 ? -a : a\` are the same function, and this phase"
        echo "               copies musl's spelling BECAUSE the choice is free.  If it is"
        echo "               no longer free the argument has to be rewritten, not the number."
        exit 1
    }
done
wait $pid_same || { echo "  arith        the equivalence probe did not build or disagreed:"; cat "$tmp/same.txt" 2>/dev/null | sed 's/^/               /'; exit 1; }
python3 - "$tmp/same.txt" "$tmp/spell1-O0.text" <<'PY'
import os
import sys

TAG = 'arith'
w = open(sys.argv[1]).read().split()
if len(w) != 14 or w[0] != 'ints':
    sys.exit('  %-12s the equivalence probe printed something this check cannot read: %s'
             % (TAG, ' '.join(w)))
ints, bad_i, longs, bad_l = w[1], w[3], w[5], w[7]
abs_min, abs_min2, labs_min, labs_min2 = w[9], w[10], w[12], w[13]
if bad_i != '0' or bad_l != '0':
    sys.exit('  %-12s the two spellings disagree: %s of %s ints and %s of %s longs'
             % (TAG, bad_i, ints, bad_l, longs))
if abs_min != abs_min2 or labs_min != labs_min2:
    sys.exit('  %-12s the two spellings differ AT THE MINIMUM, where both are undefined: '
             '%s/%s and %s/%s' % (TAG, abs_min, abs_min2, labs_min, labs_min2))
print('  %-12s `a > 0 ? a : -a` AND `a < 0 ? -a : a` ARE THE SAME FUNCTION, twice over: '
      'the two spellings taken out of the output compile to BYTE-IDENTICAL machine code '
      'at -O0 and at -O2 (%d bytes of .text), and they agree at all %s `int` values and '
      'all %s `long` ones tried, LONG_MIN and LONG_MAX among them.  So musl\'s spelling '
      'is copied because copying is the rule, not because it is better'
      % (TAG, os.path.getsize(sys.argv[2]), ints, longs))
print('  %-12s AND THE UNDEFINED BEHAVIOUR IS COPIED WITH IT, deliberately: `-a` '
      'overflows, so both return their argument at the minimum -- musl_abs(INT_MIN) = '
      '%s and musl_labs(LONG_MIN) = %s, which is what libc\'s own abs and labs do here '
      'and what musl\'s source says they do.  THE PAIR IS FAITHFUL RATHER THAN SAFER; a '
      'phase that quietly made the core\'s arithmetic differ from the libc it replaces '
      'would be a behaviour change wearing a vendoring phase\'s clothes'
      % ('', abs_min, labs_min))
PY

# --- 3. canon.sh -------------------------------------------------------------------------
wait $pid_canon || { echo "  arith        tools/canon.sh failed on the output:"; sed -n '1,10p' "$tmp/canon.log"; exit 1; }
if ! cmp -s "$f" "$tmp/canon.c"; then
    echo "  arith        tools/canon.sh is not a no-op on the output -- the two definitions are not written the way this file writes everything else:"
    diff "$f" "$tmp/canon.c" | sed -n '1,12p'
    exit 1
fi
echo "  arith        tools/canon.sh is a NO-OP on the output: the two definitions are written the way this file writes every other function, the name at column 0 on a line of its own -- which is what tools/funcreach.py reads, and what phase 14 got wrong"

# --- 4. the boundary, with the set taken from the input's own cut -------------------------
python3 - "$f" "$state/old.c" "$tmp" <<'PY'
import re
import subprocess
import sys

TAG = 'arith'
out = sys.argv[3]
fail = []
seen = {}


def cut(path):
    """`make editor.c`'s rule, character for character: stop at the first `#include`,
    drop the trailing blank lines.  Written here rather than shelling out to make,
    because zero.mk is in no implementation digest and this must be."""
    keep, last = [], 0
    for line in open(path, errors='surrogateescape').read().split('\n'):
        if re.match(r'^ *# *include ', line):
            break
        keep.append(line)
        if line.strip():
            last = len(keep)
    return keep[:last]


for which, path in (('output', sys.argv[1]), ('input', sys.argv[2])):
    lines = cut(path)
    open('%s/cut.%s.c' % (out, which), 'w', errors='surrogateescape').write(
        '\n'.join(lines) + '\n')
    d = [l for l in lines if re.match(r'^ *#', l)]
    if d:
        fail.append('the %s cut holds %d directive(s), so it found the wrong line: %s'
                    % (which, len(d), d[0]))
    w = subprocess.run(['gcc', '-O0', '-fno-stack-protector', '-Wall', '-Wextra',
                        '-Wno-unused-parameter', '-fsyntax-only',
                        '%s/cut.%s.c' % (out, which)],
                       capture_output=True, text=True).stderr
    errs = re.findall(r'^[^ ].*: error:.*$', w, re.M)
    if errs:
        fail.append('the %s cut does not compile on its own:\n    %s'
                    % (which, '\n    '.join(errs[:3])))
    other = [l for l in w.split('\n')
             if ': warning: ' in l and 'used but never defined' not in l]
    if other:
        fail.append('the %s cut has a warning that is not a boundary name: %s'
                    % (which, other[0]))
    seen[which] = sorted(set(re.findall(r"'(\w+)' used but never defined", w)))
    seen[which + '-lines'] = len(lines)

# THE SET IS THE INPUT'S, NEVER A LIST WRITTEN HERE.  Phase 28 renamed one of these
# names, and a check that quotes thirteen strings is a check that goes stale in silence
# the next time a host call is renamed.  This phase's claim is that it does not touch
# the interface, and that claim is an EQUALITY between two cuts measured in this run.
if seen['output'] != seen['input']:
    fail.append('the core -> host boundary moved: gone [%s] arrived [%s].  This phase '
                'adds two functions the core calls and the host does not, so the set '
                'cannot change'
                % (' '.join(n for n in seen['input'] if n not in seen['output']),
                   ' '.join(n for n in seen['output'] if n not in seen['input'])))
if len(seen['output']) < 10:
    fail.append('the cut named only %d undefined functions, which is too few to be the '
                'boundary -- a cut that found the wrong line would say the same'
                % len(seen['output']))
for n in ('musl_abs', 'musl_labs'):
    if n in seen['output']:
        fail.append('`%s` is undefined above the cut, so it was defined below the '
                    'boundary: it is core code' % n)
if fail:
    for line in fail:
        print('  %-12s %s' % (TAG, line))
    sys.exit(1)
print('  %-12s the cut is %d lines against the input\'s %d, with 0 directives, no error '
      'under -fsyntax-only and no warning that is not a boundary name -- and THE '
      'BOUNDARY IS THE SAME %d NAMES, taken from the INPUT\'s own cut in this run and '
      'required back rather than quoted from a list: %s'
      % (TAG, seen['output-lines'], seen['input-lines'], len(seen['output']),
         ' '.join(seen['output'])))
PY

# --- 5. the symbols, and the reason they cannot move -------------------------------------
cp "$state/symbols/undefined" "$tmp/before.u"
tools/phasecheck.sh "$work" "$f" "$state/symbols"
if ! cmp -s "$tmp/before.u" .cache/symbols/last/undefined; then
    echo "  arith        the libc surface moved, and IT CANNOT:"
    echo "               gone: $(comm -23 "$tmp/before.u" .cache/symbols/last/undefined | tr '\n' ' ')"
    echo "               came: $(comm -13 "$tmp/before.u" .cache/symbols/last/undefined | tr '\n' ' ')"
    exit 1
fi
for n in abs labs; do
    if grep -qx "$n" "$tmp/before.u" || grep -qx "$n" .cache/symbols/last/undefined; then
        echo "  arith        \`$n\` is in the undefined set, and this phase's whole argument is that it never was"
        exit 1
    fi
done
# THE MEASUREMENT THIS PHASE EXISTS FOR.  gcc lowers both to inline arithmetic, so the
# source asked libc for two functions and the object never did.  `gcc -S` of the INPUT is
# where that is visible, and it is a property of this compiler and of nothing else.
gcc -S -O0 -fno-stack-protector -o "$tmp/old.s" "$state/old.c"
gcc -S -O0 -fno-stack-protector -o "$tmp/new.s" "$f"
old_calls=$(grep -c '\b\(abs\|labs\)\b' "$tmp/old.s" || true)
new_calls=$(grep -c 'call.*\bmusl_l\?abs\b' "$tmp/new.s" || true)
if [ "$old_calls" != 0 ]; then
    echo "  arith        the INPUT's assembly mentions abs or labs $old_calls time(s), so this compiler does NOT lower them and the input was carrying two real libc calls.  That is a stronger reason for this phase, not a weaker one -- but the sentence below is wrong and has to be rewritten:"
    grep -m3 '\b\(abs\|labs\)\b' "$tmp/old.s" | sed 's/^/               /'
    exit 1
fi
if [ "$new_calls" -lt 3 ]; then
    echo "  arith        the output's assembly makes $new_calls calls to musl_abs/musl_labs and there are three call sites: the core is still not calling anything"
    exit 1
fi
echo "  arith        \`nm -u\` IS THE SAME SET, $(wc -l <"$tmp/before.u") names, as a \`comm\` empty in BOTH directions, and \`main\` is still the only external symbol.  (That is tools/symbols.sh's count, which compiles plain -O0 and so adds \`__stack_chk_fail\`; zero's own compile line has -fno-stack-protector and gives 17.)  THIS PHASE FREES NOTHING AND IT CANNOT: \`abs\` and \`labs\` were in the undefined set ZERO times before it, because gcc lowers both to inline arithmetic -- measured, the INPUT's whole assembly mentions neither name, though the source calls them at three sites.  Nothing in the language promises that, and a compiler that emitted the calls would have added two libc symbols to this file in silence.  The output makes $new_calls real calls, to two functions of its own"

# --- 6. the binary, and the difference accounted for -------------------------------------
make -C "$work" clean >/dev/null 2>&1 || true
[ -e "$work/zero-vim" ] && { echo "  build        the clean did not remove zero-vim, so a 'rebuild' below could be no rebuild at all"; exit 1; }
if ! make -C "$work" >/dev/null 2>&1; then
    echo "  build        FAILED -- rerun by hand: make -C $work"
    exit 1
fi
bin="$work/zero-vim"
echo "  build        ok, $before_lines -> $(grep -c '' "$f") lines, $(stat -c%s "$bin") bytes"

wait $pid_new || { echo "  arith        the reproducible build of the output failed"; exit 1; }
wait $pid_oo
wait $pid_no
old_size=$(stat -c%s "$state/old")
new_size=$(stat -c%s "$tmp/new")
if [ "$new_size" -lt 500000 ] || [ "$old_size" -lt 500000 ]; then
    echo "  arith        one of the two binaries is $old_size / $new_size bytes, which is not an editor"
    exit 1
fi
if [ "$new_size" != "$(stat -c%s "$bin")" ]; then
    echo "  arith        the reproducible build is $new_size bytes and make produced $(stat -c%s "$bin"): the two differ by more than a timestamp"
    exit 1
fi
if cmp -s "$state/old" "$tmp/new"; then
    echo "  arith        THE BINARY DID NOT MOVE, and it must: at -O0 a call to a static"
    echo "               function is a call and inline arithmetic is not.  Two identical"
    echo "               binaries here mean the edit did not reach the three call sites."
    exit 1
fi
python3 - "$state/old" "$tmp/new" "$tmp/old.o" "$tmp/new.o" <<'PY'
import re
import subprocess
import sys

TAG = 'arith'
fail = []


def sections(path):
    """name -> (address, size, addralign) for every named section of a linked image."""
    out = {}
    for l in subprocess.run(['readelf', '-SW', path], capture_output=True,
                            text=True).stdout.split('\n'):
        m = re.match(r'\s*\[\s*\d+\]\s+(\.\S+)\s+\S+\s+([0-9a-f]+)\s+[0-9a-f]+\s+'
                     r'([0-9a-f]+)\s+\S+\s+\S*\s*\d+\s+\d+\s+(\d+)\s*$', l)
        if m:
            out[m.group(1)] = (int(m.group(2), 16), int(m.group(3), 16), int(m.group(4)))
    return out


def sizes(obj):
    out = {}
    for l in subprocess.run(['nm', '-S', obj], capture_output=True, text=True).stdout.split('\n'):
        p = l.split()
        if len(p) == 4:
            out[p[3]] = int(p[1], 16)
    return out


def textsize(obj):
    for l in subprocess.run(['readelf', '-SW', obj], capture_output=True,
                            text=True).stdout.split('\n'):
        p = l.split()
        if len(p) > 6 and p[2] == '.text':
            return int(p[6], 16)
    sys.exit('  %-12s %s has no .text' % (TAG, obj))


def fdes(obj):
    """One unwind record per function.  Two functions arrive, so it must grow by two."""
    return subprocess.run(['readelf', '--debug-dump=frames-interp', obj],
                          capture_output=True, text=True).stdout.count('FDE cie=')


old_bin, new_bin, old_o, new_o = sys.argv[1:5]
so, sn = sections(old_bin), sections(new_bin)
zo, zn = sizes(old_o), sizes(new_o)
obj_delta = textsize(new_o) - textsize(old_o)

# WHAT THE IMAGE MAY DO, AS A RULE AND NOT AS A COINCIDENCE.  Two functions of 43 bytes
# arrive and the phase changes no data, so:
#
#   * only `.text` and `.eh_frame` may change SIZE, and nothing may shrink;
#   * `.text` grows by 0 or by ONE of its own alignment units -- the new code is absorbed
#     by the section's padding or spills exactly one unit past it, and which of the two
#     happens is a property of the INPUT and not of this phase.  MEASURED BOTH WAYS: on
#     the r29 tree it was 0 and on r30 it is 64, for the identical edit, which is why
#     this is written as a rule;
#   * `.eh_frame` grows by exactly 64, two 32-byte unwind records, one per new function,
#     and the object gains exactly 2 -- the one place two new functions are COUNTABLE in
#     a linked image;
#   * every section may move by the `.text` growth and by nothing else.
#
# A phase that touched DATA would break the first clause, which is the point of it.
align = so['.text'][2]
dtext = sn['.text'][1] - so['.text'][1]
deh = sn['.eh_frame'][1] - so['.eh_frame'][1]
if obj_delta > align:
    fail.append('the object gained %d bytes of .text and `.text` aligns to %d, so the '
                'new code no longer fits in one alignment unit and the rule below -- it '
                'grows by 0 or by one unit -- does not apply' % (obj_delta, align))
if dtext not in (0, align):
    fail.append('`.text` grew by %d bytes, and %d bytes of new code may only be absorbed '
                'by the section padding (0) or spill exactly one %d-byte alignment unit '
                'past it' % (dtext, obj_delta, align))
if deh != 64:
    fail.append('.eh_frame is %d bytes and was %d, a difference of %d where 64 was '
                'expected -- two 32-byte unwind records, one per new function'
                % (sn['.eh_frame'][1], so['.eh_frame'][1], deh))
resized = [k for k in sorted(set(so) | set(sn))
           if k not in ('.text', '.eh_frame') and so.get(k, (0, 0, 0))[1] != sn.get(k, (0, 0, 0))[1]]
if resized:
    fail.append('%s changed SIZE, and only .text and .eh_frame may: this phase adds two '
                'functions and touches no data' % ' '.join(resized))
shifted = [k for k in sorted(set(so) & set(sn)) if sn[k][0] - so[k][0] not in (0, dtext)]
if shifted:
    fail.append('%s moved by something other than 0 or the %d bytes .text grew by'
                % (' '.join(shifted), dtext))
n_fde = fdes(new_o) - fdes(old_o)
if n_fde != 2:
    fail.append('the object gained %d unwind records where 2 were expected, one per new '
                'function' % n_fde)

# THE DIFFERENCE, ACCOUNTED FOR.  Computed from the two objects, not written here: the
# two new definitions plus what the three callers gained or lost IS the object's whole
# .text delta.  A phase whose edit reached somewhere else would not add up.
delta = obj_delta
defs = {n: zn[n] for n in ('musl_abs', 'musl_labs') if n in zn}
if len(defs) != 2:
    fail.append('the output object does not define both musl_abs and musl_labs')
callers = {n: zn[n] - zo[n] for n in ('handle_lnum_col', 'scroll_with_sms',
                                      'last_status_rec') if n in zo and n in zn}
if len(callers) != 3:
    fail.append('the three calling functions are not all in both objects: %s'
                % ' '.join(sorted(callers)))
if not fail and sum(defs.values()) + sum(callers.values()) != delta:
    fail.append('the object\'s .text grew by %d bytes and the two definitions (%s) plus '
                'the three callers (%s) account for %d.  The edit reached code this '
                'phase does not name'
                % (delta, ' '.join('%s %d' % kv for kv in sorted(defs.items())),
                   ' '.join('%s %+d' % kv for kv in sorted(callers.items())),
                   sum(defs.values()) + sum(callers.values())))
if fail:
    for line in fail:
        print('  %-12s %s' % (TAG, line))
    sys.exit(1)
n_diff = int(subprocess.run('cmp -l %s %s | wc -l' % (old_bin, new_bin), shell=True,
                            capture_output=True, text=True).stdout)
print('  %-12s THE BINARY MOVED AND THE DIFFERENCE IS ACCOUNTED FOR INSTRUCTION BY '
      'INSTRUCTION: the object\'s .text grows by exactly %d bytes, which is musl_abs '
      '(%d) plus musl_labs (%d) plus what the three callers gained or lost (%s) and '
      'nothing else.  The image is %s bytes either side and %d of them differ, which is '
      'what putting a definition near the front of a file does.  ONLY `.text` AND '
      '`.eh_frame` CHANGE SIZE -- no data section moves a byte -- and neither changes by '
      'more than one alignment unit: `.text` %+d, which is %d bytes of code absorbed by '
      'the section padding or spilling exactly one %d-byte unit past it (MEASURED BOTH '
      'WAYS for the identical edit: 0 on the r29 tree, %d here), and `.eh_frame` +%d, '
      'two 32-byte unwind records -- the object gains exactly 2, one per new function'
      % (TAG, delta, defs['musl_abs'], defs['musl_labs'],
         ' '.join('%s %+d' % kv for kv in sorted(callers.items())),
         format(int(subprocess.run(['stat', '-c%s', new_bin], capture_output=True,
                                   text=True).stdout), ','), n_diff,
         dtext, sum(defs.values()), align, dtext, deh))
PY

# --- 7. the recordings, the blindness, and the probes -------------------------------------
wait $pid_val || { echo "  arith        the instrumented build failed:"; head -3 "$tmp/values.log" | sed 's/^/               /'; exit 1; }
wait $pid_wrong || { echo "  arith        the control build failed:"; head -3 "$tmp/wrong.log" | sed 's/^/               /'; exit 1; }
tools/zrecord.sh "$state/old" "$state/old.c" "$tmp/REC.old" >/dev/null 2>&1 &
pid_ro=$!
tools/zrecord.sh "$tmp/new" "$f" "$tmp/REC.new" >/dev/null 2>&1 &
pid_rn=$!
tools/zrecord.sh "$tmp/values" "$tmp/values.c" "$tmp/REC.values" >/dev/null 2>&1 &
pid_rv=$!

python3 - "$state/old" "$tmp" <<'PY'
import hashlib
import re
import sys

TAG = 'arith'
sys.path.insert(0, 'tools')          # tools/zstream.py -- stage() is the one place a
import zstream                       # binary is renamed to `vim`, for the race its
                                     # docstring describes
old, tmp = sys.argv[1], sys.argv[2]
fail = []

LINES = ''.join('line%d\r' % i for i in range(1, 61)).encode()
LONG = ''.join('y' * 300 + '\r' for _ in range(39)).encode()

# ONE PROBE PER CALL SITE, because the corpus reaches none of them.  Each names the
# option or the key that gets the editor there, and the site it is for.
PROBES = (
    ('rnu', ('+set paste', '+set rnu'), [b'i' + LINES + b'\x1bgg:q!\r'], 1),
    ('sms', ('+set paste',), [b'i' + LONG + b'\x1bgg\x06\x06\x02\x02:q!\r'], 2),
    ('stl', (), [b':set laststatus=2\r:set laststatus=0\r:q!\r'], 3),
)


def run(binary, args, keys):
    try:
        _, so, se, rc = zstream.session(binary, keys, args=args, timeout=25)
    except zstream.Blocked:
        return None, None, None
    return (len(so), hashlib.sha256(so).digest(), rc), se, so


seen = {}
for name, args, keys, site in PROBES:
    for who, path in (('old', old), ('new', tmp + '/new'),
                      ('values', tmp + '/values'), ('wrong', tmp + '/wrong')):
        seen[who, name] = run(path, args, keys)

values, moved = {}, []
for name, args, keys, site in PROBES:
    o, n, v, w = (seen[k, name] for k in ('old', 'new', 'values', 'wrong'))
    for who, r in (('old', o), ('new', n), ('values', v), ('wrong', w)):
        if r[0] is None:
            fail.append('the `%s` probe never returned on `%s`' % (name, who))
    if o[0] is None or n[0] is None:
        continue
    if o[0] != n[0]:
        fail.append('the `%s` probe draws a different screen on the binary this phase '
                    'was handed and on its own: %s bytes against %s'
                    % (name, o[0][0], n[0][0]))
    if v[0] != n[0]:
        fail.append('the instrumented build draws a different screen from the product '
                    'on the `%s` probe, so what it reports is not what the product does'
                    % name)
    marks = re.findall(rb'^Z(\d) (-?\d+)$', v[1], re.M)
    mine = [int(val) for s, val in marks if int(s) == site]
    other = sorted({int(s) for s, _ in marks} - {site})
    if other:
        fail.append('the `%s` probe reached call sites %s as well as %d, so the counts '
                    'below do not say what they claim'
                    % (name, ' '.join(str(x) for x in other), site))
    if not mine:
        fail.append('the `%s` probe reaches call site %d zero times, and it exists to '
                    'reach it -- this phase would then have no evidence for that site '
                    'at all' % (name, site))
        continue
    values[name] = (site, len(mine), min(mine), max(mine))
    if n[0] != w[0]:
        moved.append(name)

if not fail:
    span = max(max(abs(lo), abs(hi)) for _, _, lo, hi in values.values())
    if span > 1000:
        fail.append('a call site was handed an argument of magnitude %d, and this phase '
                    'states that every one of them is a small difference of line numbers '
                    'or of window heights.  The UB argument has to be re-made rather '
                    'than the number updated' % span)
    if 'rnu' not in moved:
        fail.append('the CONTROL -- both vendored functions returning their argument '
                    'unchanged -- does not move the `rnu` probe, so that probe cannot '
                    'fail and proves nothing (CLAUDE.md)')
if fail:
    for line in fail:
        print('  %-12s %s' % (TAG, line))
    sys.exit(1)
print('  %-12s THREE PROBES, ONE PER CALL SITE, and the corpus reaches none of them: %s'
      % (TAG, ';  '.join('`%s` -> site %d, %d calls, arguments %d to %d'
                         % (k, v[0], v[1], v[2], v[3]) for k, v in values.items())))
print('  %-12s EVERY ONE DRAWS THE SAME SCREEN on the binary this phase was handed and '
      'on its own, byte for byte.  AND %d OF THE 3 ARE PROVEN ABLE TO FAIL, by a control '
      'whose musl_abs and musl_labs return their argument unchanged: %s move.  `stl` '
      'DOES NOT, AND THAT IS REPORTED RATHER THAN HIDDEN -- its site is reached twice and '
      'its answer guards only `w_prev_height = w_height`, which win_new_height() already '
      'assigns on every path that changes a height, so nothing drawn depends on it.  That '
      'site is proven REACHED and not proven OBSERVABLE, and section 2 is its evidence'
      % ('', len(moved), ' and '.join('`%s`' % m for m in moved)))
print('  %-12s AND THE UB CANNOT BE REACHED: the largest magnitude any of the three sites '
      'is ever handed, over 51 probe calls, is %d -- against INT_MIN\'s 2,147,483,648 and '
      'LONG_MIN\'s 9,223,372,036,854,775,808.  The static reason is in the file: '
      'last_status_rec\'s two operands are window heights, which limit_screen_size() '
      'clamps at 1,000 rows, and the two labs arguments are differences of line numbers, '
      'which are >= 1 -- so LONG_MIN would need a buffer of 2^63 lines'
      % ('', max(max(abs(v[2]), abs(v[3])) for v in values.values())))
PY

wait $pid_ro
wait $pid_rn
wait $pid_rv
if ! diff -rq "$tmp/REC.old" "$tmp/REC.new" >"$tmp/rec.diff" 2>&1; then
    echo "  arith        the declared delta is NOTHING AT ALL and the two recordings differ:"
    sed -n '1,12p' "$tmp/rec.diff"
    exit 1
fi
if ! diff -rq "$tmp/REC.values" "$tmp/REC.new" >"$tmp/rec.diff" 2>&1; then
    echo "  arith        THE CORPUS DOES REACH A CALL SITE.  The instrumented build's recording differs from the product's, which means one of the three sites was entered -- this phase states that none is, and the statement has to be re-made rather than the difference ignored:"
    sed -n '1,12p' "$tmp/rec.diff"
    exit 1
fi
hits=$(grep -rh '^Z[123] ' "$tmp/REC.values" | wc -l)
records=$(find "$tmp/REC.new" -type f | wc -l)
if [ "$hits" != 0 ]; then
    echo "  arith        the instrument fired $hits time(s) across the recording, and the two recordings are nevertheless identical -- one of the two measurements is wrong"
    exit 1
fi
echo "  arith        the declared delta is NOTHING AT ALL and TWO FULL RECORDINGS ARE BYTE-IDENTICAL, $records records: 102 screen cases, every Ex command, every command line, the pty scenarios and the terminal table.  AND THE CORPUS CANNOT SEE THIS PHASE AT ALL, which is measured and not assumed: the same output built with a probe on each of the three arguments enters NONE of them in $records records -- the instrumented recording is byte-identical too, and the marker appears $hits times.  That is why the phase owes the probes above"

# tools/phaserun.sh runs tools/zerodelta.sh --phase 31 after this check, and that is the
# second opinion on the same claim -- against .reference/zero-baselines rather than
# against the binary this phase was handed.
