#!/bin/sh
# Zero phase 27, the check -- THE MOVE, and the boundary as an assertion.
# See pipes/zero27-edit.sh, ZERO-PLAN.md 4c and .claude/briefs/zero-reorg.md 5.
#
# Usage: pipes/zero27-check.sh <work-dir> <state-dir>    (run from the repository root)
#
# Runs after pipes/zero27-edit.sh and the sweep tools/phaserun.sh runs between them, and
# reads nothing from the edit's shell -- only the work tree and the state directory.
# What the edit left there is `old.c`, the source this phase was HANDED, and `old`, that
# source built with SOURCE_DATE_EPOCH=0 and the boundary's own flags.
#
# WHAT IS CLAIMED, in eight parts:
#
#   THE MOVE      A MOVE AND NOTHING ELSE, stated as a multiset: every line of the
#                 output is a line of the input except the THIRTY-TWO this phase
#                 writes -- 20 enumerator lines and 12 static_asserts -- and NOT ONE
#                 line of the input is missing.  A phase that moved code and also
#                 changed a character of it could not say that.
#   THE CUT       the four parts the brief asks for, and the two equalities that make
#                 the cut a product: it is a PREFIX (`head -n N` is `cmp`-exact) and
#                 the cut plus the remainder IS the file, byte for byte.
#   THE BOUNDARY  the cut's warning set, computed two ways and required equal: gcc's
#                 `'X' used but never defined`, and the names DECLARED above the cut
#                 and DEFINED below it, read out of the text.  Thirteen, and they are
#                 named here so that widening the interface is loud.
#   FOUR BREAKS   the three the brief measured as SILENT in the ordinary build and
#                 caught only here -- a `#define` above the cut, an `#include` back at
#                 the top, and one core function moved below the cut -- each built
#                 both ways; and a fourth that is NOT silent and is the whole reason
#                 phase 26 came first: `#include <limits.h>` at line 1, where the
#                 twelve enumerators become their own values and the compiler says
#                 `expected identifier before numeric constant`.
#   THE CONSTANTS the twelve are in the PRODUCT and they are compiled: one derivation
#                 deliberately wrong is `static assertion failed`.  And the reason the
#                 assert restates the derivation rather than naming the enumerator is
#                 MEASURED, not argued: the same wrong enumerator with the assert
#                 written `INT_MAX == INT_MAX` builds in SILENCE.
#   THE TRAP      the `static` prototype trap in its NEW shape.  Phase 26 measured it
#                 as `error: static declaration of 'malloc' follows non-static
#                 declaration`, which needed <stdlib.h> above it.  Here there is no
#                 second declaration, so it is `'malloc' declared 'static' but never
#                 defined [-Wunused-function]` on <stdlib.h>'s own line, which is the
#                 one part of phase 26's evidence this phase had to replace -- and it
#                 is WEAKER than the brief predicted: MEASURED, it links anyway and the
#                 binary is byte-identical, so it is a warning the sweep catches.
#   SYMBOLS       `nm -u` is THE SAME SET, as a `comm` empty in BOTH directions, and
#                 `main` is still the only external symbol.  Moving definitions inside
#                 ONE translation unit frees nothing and needs nothing: THE CLAIM OF
#                 THIS PHASE IS STRUCTURAL AND NOT A SYMBOL COUNT.
#   BEHAVIOUR     the declared delta is NOTHING AT ALL.  Two full recordings, of the
#                 binary this phase was handed and of its own, are BYTE-IDENTICAL.
#                 tools/zerodelta.sh is run by tools/phaserun.sh after this check and
#                 is the second opinion.
#
# THERE IS NO `cmp` HERE AND THERE CANNOT BE.  Phases 16, 23 and 24 could each say
# "the binary is the same bytes"; this one moves 1,800 lines of definitions, so every
# address below the first of them moves and the image is a different one of the same
# size.  What replaces it is the multiset equality above -- the source is the same
# lines -- plus the recording.
#
# AND `zhostonly`, WHOSE EXCEPTIONS THIS PHASE CHANGED.  The core now writes
# `enum { SIGHUP = 1 };` for itself and `static_assert(1 == SIGHUP, "SIGHUP");` below
# the includes to check it, so `<file scope>` says SIGHUP and SIGTERM twice each where
# it said neither.  Both are outside the host region -- the region begins at
# host_winch_pending and the includes are above it -- so the tool refuses until the
# phase comes and writes the new counts beside the old, which is what it is for.
set -eu

work=${1:?usage: zero27-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero27-check.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"
before_lines=$(cat "$state/input-lines")

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")

# The product build and every control are written first and waited for below.
# shellcheck disable=SC2086
( SOURCE_DATE_EPOCH=0 gcc $cflags $ldflags -o "$tmp/new" "$f" ) &
pid_new=$!

python3 - "$f" "$tmp" <<'PY'
import re
import sys

TAG = 'boundary'
t = open(sys.argv[1], errors='surrogateescape').read()
out = sys.argv[2]
L = t.split('\n')


def die(msg):
    sys.exit('  %-12s %s' % (TAG, msg))


inc = [i for i, l in enumerate(L) if re.match(r'^ *# *include ', l)]
if not inc:
    die('the output has no `#include` at all, so there is no boundary to cut at')
first = inc[0]

# hash -- A `#define` ABOVE THE CUT.  The ordinary build is silent; the cut holds a
# directive.  It goes directly below the usize typedef, which is where a constant this
# phase writes would go and therefore where the mistake would really be made.
TD = 'typedef typeof(sizeof(0)) usize;'
if t.count(TD) != 1:
    die('`%s` is not in the output exactly once, so the `#define` control has nowhere '
        'it belongs' % TD)
files = {'hash': t.replace(TD, TD + '\n#define ZZ_A_DIRECTIVE 1', 1)}

# top -- ONE `#include` BACK AT THE TOP.  The ordinary build is silent; the cut is
# empty, and the floor is what catches it.  <stddef.h> is the header chosen for it
# because it defines NONE of the twelve, which is what makes the build silent -- see
# `limits` below, which is the SAME break with a header that does.
files['top'] = '#include <stddef.h>\n' + t

# limits -- THE CONSTRAINT THAT MADE THIS PHASE AND PHASE 26 SEPARATE, MEASURED ON THE
# PRODUCT RATHER THAN ARGUED FROM IT.  ZERO-PLAN.md 4c and the brief both say the
# twelve constants can only be written once the includes have moved, because
# `enum : int { INT_MAX = ... };` after `#include <limits.h>` is
# `enum : int { 0x7fffffff = ... };`.  With <limits.h> put back at line 1 that is
# exactly what the compiler says, at the enumerator's own line: `expected identifier
# before numeric constant`.
files['limits'] = '#include <limits.h>\n' + t

# elapsed -- ONE CORE FUNCTION MOVED BELOW THE CUT.  The ordinary build is silent -- a
# definition may sit anywhere in one translation unit -- and the cut's warning set
# gains exactly that name.  This is the boundary AS AN ASSERTION: a phase that quietly
# widened the core -> host interface would move this set and nothing else in the
# pipeline would say so.
d = [i for i, l in enumerate(L) if l.startswith('elapsed(')]
if len(d) != 1 or not L[d[0] - 1].startswith('    static ') or d[0] > first:
    die('`elapsed` is not defined exactly once above the boundary, so the control that '
        'moves one core function below it would not be a control')
s = d[0] - 1
e = d[0]
while L[e] != '}':
    e += 1
if L[e + 1] != '':
    die('`elapsed` is not followed by a blank line')
body = L[s:e + 1]
moved = L[:s] + L[e + 2:]
at = [i for i, l in enumerate(moved) if re.match(r'^ *# *include ', l)][-1]
files['elapsed'] = '\n'.join(moved[:at + 1] + [''] + body + moved[at + 1:])

# wrong / vacuous -- THE TWELVE ARE COMPILED, AND THE SHAPE OF THE ASSERT IS MEASURED.
# A WRONG DERIVATION IS WRONG IN BOTH PLACES, because the edit emits the enumerator and
# the assert's left-hand side from ONE text -- so `wrong` is `~0u >> 2` in both, which
# is what a mistake in the table would really look like, and the static_assert catches
# it against <limits.h>.  `vacuous` is the same mistake with the assert written the way
# a reader would first reach for -- `static_assert(INT_MAX == INT_MAX, ...)` -- where
# the name below the includes is the MACRO and the comparison is a tautology about the
# header.  It builds in SILENCE, which is the whole reason the assert restates the
# deriving expression instead of naming what it checks.
E = '    int { INT_MAX = (int)(~0u >> 1) };'
A = 'static_assert((int)(~0u >> 1) == INT_MAX, "INT_MAX");'
for x in (E, A):
    if t.count(x) != 1:
        die('`%s` is not in the output exactly once -- the enumerator and the assert '
            'that checks it are what this phase writes' % x)
files['wrong'] = t.replace(E, '    int { INT_MAX = (int)(~0u >> 2) };', 1) \
                  .replace(A, 'static_assert((int)(~0u >> 2) == INT_MAX, "INT_MAX");', 1)
files['vacuous'] = t.replace(E, '    int { INT_MAX = (int)(~0u >> 2) };', 1) \
                    .replace(A, 'static_assert(INT_MAX == INT_MAX, "INT_MAX");', 1)

# stat -- THE TRAP IN ITS NEW SHAPE.  With the headers below, a `static` prototype for
# a libc function is no longer an error at the declaration: there is nothing to
# conflict with, and the failure moves to the LINK.
P = 'void *malloc(usize n);'
if t.count('\n' + P + '\n') != 1:
    die('the plain prototype `%s` is not on a line of its own exactly once' % P)
files['stat'] = t.replace('\n' + P + '\n', '\nstatic ' + P + '\n', 1)

for name, text in files.items():
    if text == t:
        die('the control %s changed nothing' % name)
    open('%s/%s.c' % (out, name), 'w', errors='surrogateescape').write(text)
print('  %-12s seven controls written: hash a `#define` above the cut, top an '
      '`#include <stddef.h>` back at line 1, limits the same with `<limits.h>`, elapsed '
      'one core function moved below the cut, wrong one derivation broken, vacuous the '
      'same break with the assert naming the macro instead of restating the derivation, '
      'stat the malloc prototype made `static`' % TAG)
PY

# The one that must LINK is the slowest; the rest are warning runs.  Those expected to
# fail have their status discarded here rather than by `wait`, which would take `set -e`.
# shellcheck disable=SC2086
( SOURCE_DATE_EPOCH=0 gcc $cflags $ldflags -o "$tmp/stat" "$tmp/stat.c" 2>"$tmp/w.stat" || true ) &
pid_stat=$!
( gcc -c -O0 -fno-stack-protector -Wall -Wextra -Wno-unused-parameter -o /dev/null "$tmp/stat.c" 2>"$tmp/w.statw" || true ) &
pid_statw=$!
( gcc -c -O0 -fno-stack-protector -Wall -Wextra -Wno-unused-parameter -o /dev/null "$tmp/hash.c" 2>"$tmp/w.hash" || true ) &
pid_hash=$!
( gcc -c -O0 -fno-stack-protector -Wall -Wextra -Wno-unused-parameter -o /dev/null "$tmp/top.c" 2>"$tmp/w.top" || true ) &
pid_top=$!
( gcc -c -O0 -fno-stack-protector -Wall -Wextra -Wno-unused-parameter -o /dev/null "$tmp/elapsed.c" 2>"$tmp/w.elapsed" || true ) &
pid_elapsed=$!
( gcc -c -O0 -fno-stack-protector -Wall -Wextra -Wno-unused-parameter -o /dev/null "$tmp/vacuous.c" 2>"$tmp/w.vacuous" || true ) &
pid_vacuous=$!
( gcc -c -O0 -fno-stack-protector -o /dev/null "$tmp/limits.c" 2>"$tmp/w.limits" || true ) &
pid_limits=$!
( gcc -c -O0 -fno-stack-protector -o /dev/null "$tmp/wrong.c" 2>"$tmp/w.wrong" || true ) &
pid_wrong=$!
( gcc -c -O0 -fno-stack-protector -Wall -Wextra -Wno-unused-parameter -o /dev/null "$f" 2>"$tmp/w.new" || true ) &
pid_warn=$!
# tools/canon.sh must be a NO-OP: the twenty enumerator lines and the twelve asserts are
# new text, and canon is what says they are written the way this file writes everything
# else -- it reshapes `enum : T { ... };` onto two lines, which is how the file already
# writes its one existing `enum : long`.
cp "$f" "$tmp/canon.c"
( tools/canon.sh "$tmp/canon.c" >"$tmp/canon.log" 2>&1 ) &
pid_canon=$!

# --- 1. the move, the cut and the boundary -------------------------------------------------
python3 - "$f" "$state/old.c" "$before_lines" "$tmp" <<'PY'
import collections
import re
import subprocess
import sys

TAG = 'boundary'
new = open(sys.argv[1], errors='surrogateescape').read()
old = open(sys.argv[2], errors='surrogateescape').read()
before_lines = int(sys.argv[3])
tmp = sys.argv[4]
N, O = new.split('\n'), old.split('\n')
fail = []

# THE TWELVE, and the two texts that must agree.  Neither list is written here: the
# enumerators are read out of the output and so are the asserts, and the phase's claim
# is that each assert's left-hand side IS its enumerator's initialiser.
#
# THAT EQUALITY IS THE ONE THING NO COMPILER CAN CHECK, and it has to be read here for
# exactly the reason `vacuous` measures below: under the includes the name `INT_MAX` is
# <limits.h>'s MACRO, so a static_assert can compare the DERIVATION against the header
# but can never name the enumerator the core actually uses.  If the two texts drifted
# apart, the assert would go on holding and the core would be using the other number.


def read_constants(text):
    lines = text.split('\n')
    e, a = {}, {}
    for i, l in enumerate(lines):
        if l.startswith('enum { '):
            m = re.match(r'^enum \{ ([A-Z][A-Z0-9_]*) = (.+) \};$', l)
        elif i and lines[i - 1] == 'enum :':
            m = re.match(r'^    (?:int|long|long long|unsigned long long|usize) '
                         r'\{ ([A-Z][A-Z0-9_]*) = (.+) \};$', l)
        else:
            m = None
        if m:
            e.setdefault(m.group(1), (m.group(2), l))
    for m in re.finditer(r'^static_assert\((.+) == ([A-Z][A-Z0-9_]*), "\2"\);$',
                         text, re.M):
        a[m.group(2)] = m.group(1)
    return e, a


enums, asserts = read_constants(new)
WANT = ('INT_MAX INT_MIN LONG_MAX LONG_MIN LLONG_MAX LLONG_MIN ULLONG_MAX SIZE_MAX '
        'PATH_MAX EXIT_FAILURE SIGHUP SIGTERM').split()
for n in WANT:
    if n not in enums:
        fail.append('`%s` has no enumerator of its own in the output, and it is one of '
                    'the twelve the core must declare once the headers are below it' % n)
    elif n not in asserts:
        fail.append('`%s` has an enumerator and no static_assert, so nothing checks the '
                    'core\'s number against the header' % n)
    elif asserts[n] != enums[n][0]:
        fail.append('`%s`\'s assert compares `%s` where its enumerator is `%s` -- the '
                    'two must be the SAME TEXT, or the assert is checking something '
                    'other than what the core uses' % (n, asserts[n], enums[n][0]))
extra = sorted(set(asserts) - set(WANT))
if extra:
    fail.append('the output holds static_asserts for %s, which are not among the twelve'
                % ' '.join(extra))
# And that reading is PROVEN ABLE TO FAIL, on the one thing no compiler here can see:
# the enumerator moved and the assert left behind.  The build of such a file is silent
# and its static_assert still holds, so this reading is the only thing that catches it.
if 'INT_MAX' in enums:
    de, da = read_constants(new.replace(enums['INT_MAX'][1],
                                        enums['INT_MAX'][1].replace('~0u >> 1',
                                                                    '~0u >> 2'), 1))
    if da.get('INT_MAX') == de.get('INT_MAX', (None,))[0]:
        fail.append('with INT_MAX\'s ENUMERATOR alone changed the reading above still '
                    'says the two texts agree, so it is not checking anything')

# THE MOVE IS A MOVE.  Every line of the output is a line of the input except the 32
# this phase writes, and not one line of the input is missing.  A phase that moved code
# and altered a character of it on the way could not state this.
cn, co = collections.Counter(N), collections.Counter(O)
gone = co - cn
came = cn - co
written = {'enum :': 8}
for n in WANT:
    if n in enums and n in asserts:
        written['static_assert(%s == %s, "%s");' % (asserts[n], n, n)] = 1
        written[enums[n][1]] = written.get(enums[n][1], 0) + 1
blanks = came.pop('', 0)
if gone:
    fail.append('%d line(s) of the input are not in the output at all, so this is not a '
                'move: %s' % (sum(gone.values()),
                              ' / '.join(repr(k[:60]) for k in list(gone)[:3])))
unexpected = {k: v for k, v in came.items() if written.get(k) != v}
missing = {k for k, v in written.items() if came.get(k, 0) != v}
if unexpected:
    fail.append('the output holds %d line(s) this phase does not write: %s'
                % (sum(unexpected.values()),
                   ' / '.join(repr(k[:60]) for k in list(unexpected)[:3])))
if missing:
    fail.append('%d line(s) this phase writes are not in the output: %s'
                % (len(missing), ' / '.join(repr(k[:60]) for k in sorted(missing)[:3])))

# The arithmetic, and the blank lines no verification tier can see.
if len(O) - 1 != before_lines:
    fail.append('the state directory says the edit was handed %d lines and old.c has %d'
                % (before_lines, len(O) - 1))
added = sum(written.values())
if len(N) - len(O) != added + blanks:
    fail.append('the output is %d lines and the input was %d, a difference of %d where '
                '%d was expected -- %d written lines and %d blank'
                % (len(N) - 1, len(O) - 1, len(N) - len(O), added + blanks,
                   added, blanks))


def runs(lines):
    return sum(1 for i in range(1, len(lines)) if lines[i] == '' and lines[i - 1] == '')


if runs(N) or runs(O):
    fail.append('runs of two blank lines: %d in the input and %d in the output, and '
                'CLAUDE.md allows none' % (runs(O), runs(N)))

# THE DIRECTIVES, where they were and where they are.
od = [i for i, l in enumerate(O) if re.match(r'^ *#', l)]
nd = [i for i, l in enumerate(N) if re.match(r'^ *#', l)]
if od != list(range(11)):
    fail.append('the input did not have its eleven directives on its first eleven lines')
if len(nd) != 11 or nd != list(range(nd[0], nd[0] + 11)):
    fail.append('the output does not have eleven directives on eleven consecutive '
                'lines: %d at %s' % (len(nd), ' '.join(str(i + 1) for i in nd[:4])))
elif set(N[i] for i in nd) != set(O[i] for i in od):
    fail.append('the eleven directives are not the eleven the input had')

# --- THE CUT ---------------------------------------------------------------------------
# ONE awk CLAUSE AND NO JUDGEMENT, and the two equalities that make it a product.
cut_lines = []
for l in N:
    if re.match(r'^ *# *include ', l):
        break
    cut_lines.append(l)
last = len(cut_lines)
while last and cut_lines[last - 1] == '':
    last -= 1
cut = '\n'.join(cut_lines[:last]) + '\n'
open(tmp + '/cut.c', 'w', errors='surrogateescape').write(cut)
if cut != '\n'.join(N[:last]) + '\n':
    fail.append('the cut is not a PREFIX of the file, which is what makes it '
                'extractable by `head -n N`')
if '\n'.join(N[:len(cut_lines)]) + '\n' + '\n'.join(N[len(cut_lines):]) != new:
    fail.append('the cut plus the remainder is not the file byte for byte')
hashes = [i for i, l in enumerate(cut.split('\n')) if re.match(r'^ *#', l)]
if hashes:
    fail.append('PART 1: %d line(s) of the cut begin with a `#`, at %s'
                % (len(hashes), ' '.join(str(i + 1) for i in hashes[:4])))
# PART 2, the floor.  70,000 against 78,358 today -- eight thousand lines of margin,
# stated in the same shape and the same sentence as tools/create_cmdidxs.py's 80 and
# `orphanopts`'s 80, and to be lowered only in the phase that crosses it.
FLOOR = 70000
if last < FLOOR:
    fail.append('PART 2: the cut is %d lines, below the floor of %d.  A cut that found '
                'the wrong line would be short rather than wrong, and the floor is what '
                'says so' % (last, FLOOR))

# PART 3 and PART 4.  -fsyntax-only, which is a tenth of a second and is the
# deliverable's acceptance test -- the thing we ship parses.
w = subprocess.run(['gcc', '-O0', '-fno-stack-protector', '-Wall', '-Wextra',
                    '-Wno-unused-parameter', '-fsyntax-only', tmp + '/cut.c'],
                   capture_output=True, text=True).stderr
ERR = re.compile(r'^[^ ].*:\d+:\d+: error:.*$', re.M)
if ERR.findall(w):
    fail.append('PART 3: the cut does not compile on its own:\n    %s'
                % '\n    '.join(ERR.findall(w)[:4]))
seen = sorted(set(re.findall(r"'(\w+)' used but never defined", w)))
other = [l for l in w.split('\n')
         if ': warning: ' in l and 'used but never defined' not in l]
if other:
    fail.append('PART 4: the cut has a warning that is not a boundary name: %s'
                % other[0])

# THE BOUNDARY, COMPUTED A SECOND WAY.  A name defined below the cut and mentioned
# above it is a core -> host call, which is what the boundary IS; gcc's warning set and
# this reading of the text must be the same list.
below = set()
rest = N[len(cut_lines):]
for i, l in enumerate(rest[:-1]):
    m = re.match(r'^([A-Za-z_]\w*)\s*\(', l)
    if m and rest[i + 1].startswith('{'):
        below.add(m.group(1))
above_words = collections.Counter(re.findall(r'\b[A-Za-z_]\w*\b', cut))
textual = sorted(n for n in below if above_words[n])
if seen != textual:
    fail.append('PART 4: gcc says the boundary is %s and the text says it is %s'
                % (' '.join(seen), ' '.join(textual)))
DECLARED = ('host_exit host_message musl_delay musl_get_winsize musl_gettimeofday '
            'musl_host_init musl_read_input musl_suspend musl_term_start '
            'musl_term_stop musl_tty_keys musl_wait_for_input vim_snprintf').split()
if seen != sorted(DECLARED):
    fail.append('PART 4: the boundary is %d names and this phase declares %d.  Now: %s.  '
                'Declared: %s.  A phase that widens the core -> host interface changes '
                'this set and nothing else in the pipeline would say so'
                % (len(seen), len(DECLARED), ' '.join(seen), ' '.join(sorted(DECLARED))))

# NOT ONE PROTOTYPE MAY BE `static`, and after the move that is a LINK failure rather
# than an error at the line -- which the `stat` control measures.
PROTOS = ('void *malloc(usize n);', 'void *realloc(void *p, usize n);',
          'void free(void *p);', 'long time(long *tp);', 'int getpid(void);',
          'int kill(int pid, int sig);', 'long write(int fd, const void *buf, usize n);',
          'long labs(long n);', 'int abs(int n);')
for p in PROTOS:
    if new.count('\n' + p + '\n') != 1:
        fail.append('the prototype `%s` is not on a line of its own exactly once' % p)
    if ('static ' + p) in new:
        fail.append('the prototype `%s` is `static`, which after the move is a LINK '
                    'failure and not a diagnostic at the line' % p)

if fail:
    for line in fail:
        print('  %-12s %s' % (TAG, line))
    sys.exit(1)
open(tmp + '/boundary.txt', 'w').write('\n'.join(seen) + '\n')
print('  %-12s THE MOVE IS A MOVE: not one of the input\'s %d lines is missing from the '
      'output, and the only lines the output adds are the %d this phase writes -- %d '
      'enumerator lines for the twelve constants and 12 static_asserts -- plus %d blank '
      'where an emptied paragraph left two.  %d lines -> %d'
      % (TAG, len(O) - 1, added, added - 12, blanks, len(O) - 1, len(N) - 1))
print('  %-12s the twelve constants, each an ENUMERATOR above the boundary and a '
      'static_assert below it whose left-hand side is that enumerator\'s own '
      'initialiser, read back out of the output and required equal: %s'
      % (TAG, '  '.join('%s = %s' % (n, enums[n][0]) for n in WANT)))
print('  %-12s PATH_MAX is an ARRAY BOUND, which is why all twelve are enumerators: a '
      '`static const int` cannot appear in an array bound, a case label or an '
      'enumerator initialiser' % TAG)
print('  %-12s the eleven `#include`s were lines 1-11 and are lines %d-%d, and the cut '
      'above them is %d lines with 0 directives -- the boundary is the first one and '
      'nothing else marks it' % (TAG, nd[0] + 1, nd[-1] + 1, last))
print('  %-12s THE CUT IS A PREFIX (`head -n %d` exactly) and the cut plus the '
      'remainder IS the file, byte for byte.  It compiles ALONE with `-fsyntax-only`, '
      '0 errors, above a floor of %d lines' % (TAG, last, FLOOR))
print('  %-12s and its WHOLE warning set is the boundary: %d names, every one `used but '
      'never defined`, and gcc\'s list is identical to the names DEFINED below the cut '
      'and MENTIONED above it -- %s' % (TAG, len(seen), ' '.join(seen)))
PY

# --- 2. the three breaks the ordinary build cannot see ---------------------------------------
wait $pid_hash $pid_top $pid_elapsed $pid_vacuous $pid_wrong $pid_warn $pid_limits
if ! grep -q 'expected identifier before numeric constant' "$tmp/w.limits"; then
    echo "  boundary     with <limits.h> put back at line 1 the enumerator \`INT_MAX = (int)(~0u >> 1)\` should become \`0x7fffffff = ...\` and the compiler should say \`expected identifier before numeric constant\`.  It did not, so the constraint that separates this phase from phase 26 is not what ZERO-PLAN.md 4c says it is:"
    sed -n '1,6p' "$tmp/w.limits"
    exit 1
fi
echo "  boundary     AND THE CONSTRAINT THAT MADE THIS PHASE AND PHASE 26 SEPARATE, MEASURED ON THE PRODUCT: with \`#include <limits.h>\` put back at line 1 the twelve enumerators become their own values -- \`enum : int { 0x7fffffff = ... };\` -- and the build stops at that line with \`expected identifier before numeric constant\`.  The constants could not have been written before the move, which is why phase 26 left them and this phase has them" 
for c in hash top elapsed; do
    if [ -s "$tmp/w.$c" ]; then
        echo "  boundary     the $c control was expected to build in SILENCE -- that is the whole point of it -- and did not:"
        sed -n '1,6p' "$tmp/w.$c"
        exit 1
    fi
done
if [ -s "$tmp/w.new" ]; then
    echo "  boundary     the output does not compile silently with -Wall -Wextra:"
    sed -n '1,8p' "$tmp/w.new"
    exit 1
fi
python3 - "$tmp" <<'PY'
import re
import subprocess
import sys

TAG = 'boundary'
tmp = sys.argv[1]


def cut(path):
    o = []
    for l in open(path, errors='surrogateescape').read().split('\n'):
        if re.match(r'^ *# *include ', l):
            break
        o.append(l)
    while o and o[-1] == '':
        o.pop()
    return o


h = [l for l in cut(tmp + '/hash.c') if re.match(r'^ *#', l)]
if len(h) != 1 or 'ZZ_A_DIRECTIVE' not in h[0]:
    sys.exit('  %-12s the `#define` control did not put exactly one directive above the '
             'cut, so PART 1 is not proven able to fail: %r' % (TAG, h[:2]))
tp = cut(tmp + '/top.c')
if len(tp) != 0:
    sys.exit('  %-12s with one `#include` back at line 1 the cut should be EMPTY and is '
             '%d lines, so PART 2 is not proven able to fail' % (TAG, len(tp)))
open(tmp + '/ecut.c', 'w', errors='surrogateescape').write(
    '\n'.join(cut(tmp + '/elapsed.c')) + '\n')
w = subprocess.run(['gcc', '-O0', '-fno-stack-protector', '-Wall', '-Wextra',
                    '-Wno-unused-parameter', '-fsyntax-only', tmp + '/ecut.c'],
                   capture_output=True, text=True).stderr
got = sorted(set(re.findall(r"'(\w+)' used but never defined", w)))
base = sorted(set(open(tmp + '/boundary.txt').read().split()))
if got != sorted(base + ['elapsed']):
    sys.exit('  %-12s moving ONE core function below the cut should add exactly its name '
             'to the warning set; it gave %s against %s'
             % (TAG, ' '.join(got), ' '.join(base)))
print('  %-12s THE THREE BREAKS THE ORDINARY BUILD CANNOT SEE, each built both ways and '
      'each SILENT under -Wall -Wextra: a `#define` above the cut (PART 1 fails, 1 '
      'directive where the cut allows 0); an `#include` back at line 1 (PART 2 fails, '
      'the cut is 0 lines); and ONE core function, `elapsed`, moved below the cut, '
      'which changes the warning set by EXACTLY that name -- %d -> %d.  That last is '
      'the boundary as an assertion' % (TAG, len(base), len(got)))
PY

# --- 3. the constants are compiled, and the shape of the assert is measured ---------------------
if ! grep -q 'static assertion failed' "$tmp/w.wrong"; then
    echo "  boundary     with INT_MAX's derivation changed to (int)(~0u >> 2) the build was expected to fail on the static_assert and did not, so the twelve prove nothing:"
    sed -n '1,6p' "$tmp/w.wrong"
    exit 1
fi
if [ -s "$tmp/w.vacuous" ]; then
    echo "  boundary     the vacuous control was expected to be SILENT and was not:"
    sed -n '1,6p' "$tmp/w.vacuous"
    exit 1
fi
echo "  boundary     THE TWELVE ARE IN THE PRODUCT AND THEY ARE COMPILED: INT_MAX's derivation changed to \`(int)(~0u >> 2)\` -- in the enumerator AND in the assert, which is what a mistake in the table would really look like -- is \`static assertion failed\` against <limits.h>.  AND THE SHAPE OF THE ASSERT IS MEASURED RATHER THAN ARGUED: the SAME wrong enumerator with the assert written \`static_assert(INT_MAX == INT_MAX, ...)\` builds in SILENCE, because below the includes that name is <limits.h>'s MACRO and the comparison is a tautology about the header.  That is why each assert restates the deriving expression -- and why the equality of the two TEXTS is read out of the source in section 1, which is the only thing that can catch the enumerator drifting away from the assert"

# --- 4. the `static` trap, in the shape the move gives it, WHICH IS WEAKER ------------------------
# MEASURED, and it corrects what the brief predicted.  `.claude/briefs/zero-reorg.md` 1e
# says a `static` libc prototype above the boundary makes "the link fail".  It does not:
# gcc gives the DECLARATION below it internal linkage too (C 6.2.2p4), warns on
# <stdlib.h>'s own line -- `'malloc' declared 'static' but never defined
# [-Wunused-function]` under -Wall, `'malloc' used but never defined` without it -- and
# then links against libc anyway.  The binary it produces is BYTE-IDENTICAL to the
# product's.  So after the move this mistake is a WARNING and nothing more, and what
# catches it is the sweep's rule that the build must print NOTHING (CLAUDE.md), plus
# the source assertion in section 1 that not one of the nine prototypes is `static`.
# Phase 26 had a hard error for it and that is now unavailable: exactly one part of its
# evidence had to be replaced here, and this is it, stated as the weaker thing it is.
wait $pid_stat || true
wait $pid_statw || true
wait $pid_new || { echo "  boundary     the output did not build with '$cflags' '$ldflags'"; exit 1; }
if grep -q "static declaration of 'malloc' follows non-static declaration" "$tmp/w.stat"; then
    echo "  boundary     the \`static\` malloc prototype still gives phase 26's error, which means a declaration of malloc is still ABOVE it and the includes did not move"
    exit 1
fi
if ! grep -q "'malloc' used but never defined" "$tmp/w.stat"; then
    echo "  boundary     the \`static\` malloc prototype was expected to warn \`'malloc' used but never defined\` and did not:"
    sed -n '1,6p' "$tmp/w.stat"
    exit 1
fi
if ! grep -q "declared 'static' but never defined \[-Wunused-function\]" "$tmp/w.statw"; then
    echo "  boundary     under -Wall the \`static\` malloc prototype was expected to give \`'malloc' declared 'static' but never defined [-Wunused-function]\`, which is what the sweep's zero-warning rule catches, and did not:"
    sed -n '1,6p' "$tmp/w.statw"
    exit 1
fi
if [ ! -f "$tmp/stat" ]; then
    echo "  boundary     the \`static\` malloc prototype did not link, which is what the brief predicted -- the measurement this check records is that it DOES, so either gcc or the brief has changed and the sentence below is wrong"
    exit 1
fi
if ! cmp -s "$tmp/stat" "$tmp/new"; then
    echo "  boundary     the \`static\` malloc prototype produced a DIFFERENT binary, where the measurement is that it produces the same one -- the keyword changes the diagnostic and not the code"
    exit 1
fi
echo "  boundary     THE TRAP HAS CHANGED SHAPE AND IT IS WEAKER, WHICH THE BRIEF DID NOT PREDICT.  Phase 26 measured a \`static\` libc prototype as \`error: static declaration of 'malloc' follows non-static declaration\`, which needed <stdlib.h> ABOVE it; the brief expected it to become a link failure here.  MEASURED: it is neither.  gcc gives <stdlib.h>'s own declaration internal linkage as well, warns on THAT line -- \`'malloc' declared 'static' but never defined [-Wunused-function]\` -- links against libc regardless, and produces a binary \`cmp\`-IDENTICAL to the product's.  So the keyword changes the diagnostic and not one instruction, and what stands between the core and it is the sweep's rule that the build print NOTHING, plus the assertion in section 1 that none of the nine is \`static\`"

# --- 5. canon, and the host's vocabulary -----------------------------------------------------------
wait $pid_canon || { echo "  boundary     tools/canon.sh failed on the output:"; sed -n '1,10p' "$tmp/canon.log"; exit 1; }
if ! cmp -s "$f" "$tmp/canon.c"; then
    echo "  boundary     tools/canon.sh is not a no-op on the output -- the twenty enumerator lines and the twelve asserts are not written the way this file writes everything else:"
    diff "$f" "$tmp/canon.c" | sed -n '1,12p'
    exit 1
fi
echo "  boundary     tools/canon.sh is a NO-OP on the output: the eight \`enum : T\` are on two lines, as the file already writes its one existing \`enum : long\`"
tools/st.sh zhostonly "$f"

# --- 6. the symbols, and the binary ------------------------------------------------------------------
gcc -c -O0 -fno-stack-protector -o "$tmp/old.o" "$state/old.c"
gcc -c -O0 -fno-stack-protector -o "$tmp/new.o" "$f"
nm -u "$tmp/old.o" | awk '{print $2}' | sort > "$tmp/u.old"
nm -u "$tmp/new.o" | awk '{print $2}' | sort > "$tmp/u.new"
gone=$(comm -23 "$tmp/u.old" "$tmp/u.new" | tr '\n' ' ')
came=$(comm -13 "$tmp/u.old" "$tmp/u.new" | tr '\n' ' ')
if [ -n "$gone$came" ]; then
    echo "  boundary     \`nm -u\` moved: gone [$gone] arrived [$came].  MOVING DEFINITIONS INSIDE ONE TRANSLATION UNIT CAN FREE NOTHING AND CAN NEED NOTHING -- a symbol leaves when its last caller leaves the FILE, and this phase moves no code out of it"
    exit 1
fi
ext=$(nm --extern-only --defined-only "$tmp/new.o" | awk '{print $3}' | sort | tr '\n' ' ')
if [ "$ext" != "main " ]; then
    echo "  boundary     the output defines external symbols other than main: $ext"
    exit 1
fi
if cmp -s "$tmp/new" "$state/old"; then
    echo "  boundary     the output binary is byte-identical to the input's, which cannot be: 1,800 lines of definitions moved past the rest, so every address below the first of them moves"
    exit 1
fi
echo "  boundary     \`nm -u\` is THE SAME SET, $(wc -l <"$tmp/u.new") names, as a \`comm\` empty in BOTH directions, and \`main\` is still the only external symbol.  THE CLAIM OF THIS PHASE IS STRUCTURAL AND NOT A SYMBOL COUNT: it moves code inside one translation unit, which frees nothing.  The binary is $(stat -c%s "$tmp/new") bytes against the input's $(stat -c%s "$state/old"), and is NOT the same bytes -- there is no \`cmp\` to be had here and the recording is what answers"

# --- 7. the recording did not move ---------------------------------------------------------------------
tools/zrecord.sh "$state/old" "$state/old.c" "$tmp/REC.old" >/dev/null 2>&1 &
pid_ro=$!
tools/zrecord.sh "$tmp/new" "$f" "$tmp/REC.new" >/dev/null 2>&1 &
pid_rn=$!
wait $pid_ro
wait $pid_rn
if ! diff -rq "$tmp/REC.old" "$tmp/REC.new" >"$tmp/rec.diff" 2>&1; then
    echo "  boundary     the declared delta is NOTHING AT ALL and the two recordings differ:"
    sed -n '1,12p' "$tmp/rec.diff"
    exit 1
fi
echo "  boundary     the declared delta is NOTHING AT ALL and TWO FULL RECORDINGS ARE BYTE-IDENTICAL -- 102 screen cases, every Ex command, every command line, the pty scenarios and the terminal table"

# tools/phaserun.sh runs tools/zerodelta.sh --phase 27 after this check, and that is the
# second opinion on the same claim -- against .reference/zero-baselines rather than
# against the binary this phase was handed.
