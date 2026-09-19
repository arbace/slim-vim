#!/bin/sh
# Zero phase 28, the check -- the scalar clock.
# See pipes/zero28-edit.sh, and ZERO-PLAN.md 4c.
#
# Usage: pipes/zero28-check.sh <work-dir> <state-dir>    (run from the repository root)
#
# Runs after pipes/zero28-edit.sh and the sweep tools/phaserun.sh runs between them, and
# reads nothing from the edit's shell -- only the work tree and the state directory.
# What the edit left there is `old.c`, the source this phase was HANDED, and `old`, that
# source built with SOURCE_DATE_EPOCH=0 and the boundary's own flags.
#
# WHAT IS CLAIMED, in eight parts:
#
#   ARITHMETIC  computed FROM THE INPUT: elapsed_T, elapsed, now_tv and
#               musl_gettimeofday are at 0, `struct timeval` is 0 above the boundary
#               and 3 below it, musl_now_ms is 9 above and 1 below, and the line count
#               moved by exactly -16 in the core and +6 in the host.
#   THE BOUNDARY
#               `make editor.c`'s cut, computed here by the same awk clause: 0
#               directives, `-fsyntax-only` with no error and no warning that is not a
#               boundary name, and the warning set STATED AS A SET -- twelve
#               `musl_`/`host_` names and `vim_snprintf`, with musl_gettimeofday
#               REPLACED by musl_now_ms and not added to.
#   THE SHAPE   every one of the thirteen signatures takes scalars and byte buffers
#               only.  IT IS COMPUTED ON THE INPUT TOO, and the input satisfies it:
#               phase 26 chose `musl_gettimeofday(long *, long *)` precisely so that
#               `struct timeval` would not cross, so this phase does NOT earn that
#               sentence and must not claim it.  What it earns is stated below.
#   THE ROUNDING
#               MEASURED, not argued.  elapsed() subtracted and then divided;
#               musl_now_ms divides at each reading and the caller subtracts.  A probe
#               compiled and run here compares the two over 20,000,000 random pairs and
#               must find the difference bounded by EXACTLY 1 ms, in both directions,
#               with the two formulas equally far from the true elapsed time.
#   CANON       tools/canon.sh is a NO-OP on the output: the four `long` declarations,
#               the eight new statements and musl_now_ms are written the way this file
#               writes everything else.
#   HOST        tools/zhostonly.py, whose vocabulary this phase EXTENDS: `gettimeofday`
#               is a host word from here, with the five core call sites phase 26 moved
#               named as exceptions at the counts they had at r20, r21 and r25.
#   SYMBOLS     `nm -u` is THE SAME SET -- 17 names, `comm` empty in both directions --
#               and `main` is still the only external symbol.  **`gettimeofday` DOES
#               NOT LEAVE**, and the check says so as an equality rather than letting a
#               reader expect a clock phase to free a clock symbol: the host still calls
#               it to implement musl_now_ms, and a symbol leaves when its last caller
#               leaves the FILE, which is the split and not this phase.
#   BEHAVIOUR   the declared delta is NOTHING AT ALL, and the 102 screen cases CANNOT
#               SEE THIS PHASE -- which is measured rather than assumed, and is why the
#               phase owes probes.  See below.
#
# THE SCREEN CORPUS IS BLIND TO THE CLOCK, AND THAT IS A MEASUREMENT.  Two full
# recordings being byte-identical would mean very little on its own here: of the 102
# cases, 95 ring the bell once and 7 not at all, and NOT ONE rings it twice -- so
# vim_beep's 500 ms rate limit is never exercised a second time and the only reading the
# corpus could see never happens.  Measured: a control whose clock NEVER ADVANCES, one
# that RUNS BACKWARDS and one that runs 1000x FAST all move 0 of the 102 cases.  Phase
# 26's control moved six, and it was not a clock control: swapping musl_gettimeofday's
# two output fields makes each reading an independent random number rather than a
# consistently wrong one, which is a different thing from a clock.
#
# SO THE PHASE OWES PROBES, and `gs` is what they are built on: `nv_g_cmd`'s `s` arm is
# `do_sleep(count * 1000)`, which is the ONE call site a keystroke file can drive and
# the one that makes real time pass inside the editor.  Four probes on the binary this
# phase was handed and on its own, required to agree:
#
#   1gs            ~1,010 ms   do_sleep's loop, measured against the wall clock
#   2gs            ~2,009 ms   and again at twice the length: the loop caps a wait at
#                              1,000 ms, so 2gs is TWO iterations and 1gs is one
#   hgshh          2 bells     vim_beep's threshold in BOTH directions in one probe:
#                              h at column 0 rings, gs lets a second pass, the next h
#                              rings because more than 500 ms have gone, and the third
#                              is suppressed because less than 500 have
#
# AND EACH HALF IS PROVEN ABLE TO FAIL, by a control aimed at THAT half:
#
#   fast    the clock runs 1000x fast.  `2gs` returns after ONE 1,000 ms wait instead
#           of two -- measured 1,008 ms against 2,009 -- so the difference `2gs - 1gs`
#           collapses from ~1,000 ms to ~0.  It terminates, which is why it is the
#           control the timing assertion uses.
#   froze   the clock never advances.  `do_sleep`'s `done` stays 0 and `1gs` NEVER
#           RETURNS -- the probe hits its timeout.
#   nobell  vim_beep's `> 500` written `> 500000`, so the second h cannot ring: 1 bell.
#   allbell     ... written `> -1`, so the third one can: 3 bells.
#           THE BELL CONTROLS MOVE THE THRESHOLD AND NOT THE CLOCK, and that is a
#           measurement about the probe rather than a preference.  A clock control that
#           breaks the rate limit breaks do_sleep FIRST -- `froze` and a backwards clock
#           were both tried, and `hgshh` blocks on each, so neither can say anything
#           about bells at all.
#   ceil    every reading rounded UP instead of down: `(tv_usec + 999) / 1000`.  This is
#           the ROUNDING question made into a control, and it perturbs every reading by
#           up to a full millisecond -- twice what the change from elapsed() can.  Its
#           probes are the product's and its FULL RECORDING is byte-identical, which is
#           the answer to "can any caller see one millisecond": no.
#
# AND ONE MORE THAT IS NOT A CONTROL BUT A DECISION.  `epoch` is musl_now_ms written the
# other way -- milliseconds since 1970 rather than since the whole second of its first
# call.  Its probes and its full recording are the product's, which is what makes the
# origin a free choice and not a behaviour change; the reason the product takes the
# monotonic one is 32-bit arithmetic, and pipes/zero28-edit.sh states it.
set -eu

work=${1:?usage: zero28-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero28-check.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"
before_lines=$(cat "$state/input-lines")

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")

# The product and the six variants are written first and built in the background: they
# are seconds of wall time the assertions can be spending instead.
python3 - "$f" "$tmp" <<'PY'
import sys

TAG = 'clock'
t = open(sys.argv[1], errors='surrogateescape').read()
out = sys.argv[2]

RET = '    return (tv.tv_sec - host_now_base) * 1000L + tv.tv_usec / 1000L;'
BEEP = '        if (!did_init || musl_now_ms() - start_tv > 500)'
if t.count(RET) != 1:
    sys.exit('  %-12s musl_now_ms does not compute its answer in exactly one line, so '
             'not one of the variants below could be built from it' % TAG)
VARIANTS = (
    ('ceil', RET,
     '    return (tv.tv_sec - host_now_base) * 1000L + (tv.tv_usec + 999) / 1000L;'),
    ('epoch', RET, '    return tv.tv_sec * 1000L + tv.tv_usec / 1000L;'),
    ('fast', RET, '    return (tv.tv_sec - host_now_base) * 1000000L + tv.tv_usec;'),
    ('froze', RET, '    return (tv.tv_sec - host_now_base) * 0L + tv.tv_usec * 0L;'),
    # THE BELL PROBE NEEDS CONTROLS OF ITS OWN, and they move vim_beep's THRESHOLD
    # rather than the clock: a clock control that breaks the rate limit breaks
    # do_sleep first, and `hgshh` then never returns at all, so it can say nothing
    # about the bells.  These two bracket the 500 -- unreachable, and always true.
    ('nobell', BEEP, BEEP.replace('> 500', '> 500000')),
    ('allbell', BEEP, BEEP.replace('> 500', '> -1')),
)
for name, old, line in VARIANTS:
    if t.count(old) != 1:
        sys.exit('  %-12s the line the %s variant rewrites is not in the output exactly '
                 'once, so it could not be a control' % (TAG, name))
    v = t.replace(old, line, 1)
    if v == t:
        sys.exit('  %-12s the %s variant changed nothing, so it is not a control'
                 % (TAG, name))
    open('%s/%s.c' % (out, name), 'w', errors='surrogateescape').write(v)
print('  %-12s six variants written: ceil (every reading rounded UP), epoch '
      '(milliseconds since 1970), fast (microseconds, so 1000x), froze (a clock that '
      'never advances), and nobell/allbell, which move vim_beep\'s 500 to 500000 and '
      'to -1' % TAG)
PY

# shellcheck disable=SC2086
( SOURCE_DATE_EPOCH=0 gcc $cflags $ldflags -o "$tmp/new" "$f" ) &
pid_new=$!
for v in ceil epoch fast froze nobell allbell; do
    # shellcheck disable=SC2086
    ( SOURCE_DATE_EPOCH=0 gcc $cflags $ldflags -o "$tmp/$v" "$tmp/$v.c" ) &
done

# tools/canon.sh must be a NO-OP: the new text is written the way this file writes
# everything else, and canon is what says so rather than an eye.
cp "$f" "$tmp/canon.c"
( tools/canon.sh "$tmp/canon.c" >"$tmp/canon.log" 2>&1 ) &
pid_canon=$!

# THE ROUNDING, as a program rather than a paragraph.  Written and run here so that the
# claim in the edit's header is a measurement at every boundary and not a memory.
cat > "$tmp/round.c" <<'EOF'
#include <stdio.h>
#include <stdlib.h>
static long old_f(long s1, long u1, long s2, long u2)
{ return (s2 - s1) * 1000L + (u2 - u1) / 1000L; }
static long now_ms(long s, long u, long b)
{ return (s - b) * 1000L + u / 1000L; }
int main(void)
{
    long b = 1000000, n = 20000000, i, worst = 0, d[3] = {0, 0, 0};
    double miss_old = 0, miss_new = 0;
    srandom(12345);
    for (i = 0; i < n; i++) {
        long s1 = b + random() % 100, u1 = random() % 1000000;
        long gap = random() % 5000000;
        long t1 = s1 * 1000000L + u1, t2 = t1 + gap;
        long s2 = t2 / 1000000L, u2 = t2 % 1000000L;
        long o = old_f(s1, u1, s2, u2);
        long w = now_ms(s2, u2, b) - now_ms(s1, u1, b);
        long delta = w - o;
        if (delta < -1 || delta > 1) { printf("RANGE %ld\n", delta); return 1; }
        d[delta + 1]++;
        if (labs(delta) > worst) worst = labs(delta);
        miss_old += (double)(o - gap / 1000);
        miss_new += (double)(w - gap / 1000);
    }
    printf("pairs %ld  minus1 %ld  same %ld  plus1 %ld  worst %ld  mean_old %+.4f  mean_new %+.4f\n",
           n, d[0], d[1], d[2], worst, miss_old / n, miss_new / n);
    return 0;
}
EOF
( gcc -O2 -o "$tmp/round" "$tmp/round.c" && "$tmp/round" > "$tmp/round.txt" ) &
pid_round=$!

# --- 1. the source, as arithmetic on the input ------------------------------------------
python3 - "$f" "$state/old.c" "$before_lines" <<'PY'
import re
import sys

TAG = 'clock'
new = open(sys.argv[1], errors='surrogateescape').read()
old = open(sys.argv[2], errors='surrogateescape').read()
before_lines = int(sys.argv[3])
fail = []


def split(text, which):
    lines = text.split('\n')
    d = [i for i, l in enumerate(lines) if l.lstrip().startswith('#')]
    if len(d) != 11 or d != list(range(d[0], d[0] + 11)):
        sys.exit('  %-12s %s does not have eleven contiguous directives: %d at %s.  '
                 'The first one IS the boundary and every count below distinguishes '
                 'the core from the host'
                 % (TAG, which, len(d), ' '.join(str(i + 1) for i in d[:3])))
    return '\n'.join(lines[:d[0]]), '\n'.join(lines[d[0]:]), lines, d[0]


ocore, obelow, olines, ocut = split(old, 'old.c')
ncore, nbelow, nlines, ncut = split(new, 'the output')

if len(olines) - 1 != before_lines:
    fail.append('the state directory says the edit was handed %d lines and old.c has %d'
                % (before_lines, len(olines) - 1))

# THE ARITHMETIC.  Nothing here is a number this file states except the product the
# edit's own header states: 0 for the four names, and the host's own counts.
for name in ('elapsed_T', 'elapsed', 'now_tv', 'musl_gettimeofday'):
    was = len(re.findall(r'\b%s\b' % name, old))
    now = len(re.findall(r'\b%s\b' % name, new))
    if now:
        fail.append('`%s` was %d in the input and is still %d in the output -- this '
                    'phase\'s whole product is that it is 0 everywhere' % (name, was, now))
if re.search(r'struct timeval\b', ncore):
    fail.append('`struct timeval` is back above the boundary, %d times'
                % len(re.findall(r'struct timeval\b', ncore)))
tvh = len(re.findall(r'struct timeval\b', nbelow))
if tvh != len(re.findall(r'struct timeval\b', obelow)):
    fail.append('`struct timeval` is %d below the boundary and the input had %d there: '
                'musl_now_ms keeps musl_gettimeofday\'s one and adds none'
                % (tvh, len(re.findall(r'struct timeval\b', obelow))))
# `\bgettimeofday\b` does NOT match inside `musl_gettimeofday` -- `_` is a word
# character -- so this counts the bare libc name, and there is exactly one: the call
# musl_now_ms itself makes, below the boundary.
bare = len(re.findall(r'\bgettimeofday\b', new))
if bare != 1:
    fail.append('the bare name `gettimeofday` occurs %d times in the output and must '
                'occur exactly once -- the call inside musl_now_ms' % bare)
if re.search(r'\bgettimeofday\b', ncore):
    fail.append('the core calls `gettimeofday` directly, which is the whole thing the '
                'host call exists to prevent')
for where, text, want, why in (
        ('above the boundary', ncore, 9,
         'the prototype, four stamps and four readings'),
        ('below the boundary', nbelow, 1, 'its definition')):
    n = len(re.findall(r'\bmusl_now_ms\b', text))
    if n != want:
        fail.append('`musl_now_ms` occurs %d times %s where %d were expected -- %s'
                    % (n, where, want, why))
# The four stamps and the four readings, each in the shape the edit wrote, counted
# rather than spot-checked: a substitution that reached one site and not another would
# still leave the totals above right.
stamps = len(re.findall(r'^\s*(?:\w+\.)?start_tv = musl_now_ms\(\);$', ncore, re.M))
reads = len(re.findall(r'musl_now_ms\(\) - (?:\w+\.)?start_tv\b', ncore))
if (stamps, reads) != (4, 4):
    fail.append('the core has %d stamps of the shape `X = musl_now_ms();` and %d '
                'readings of the shape `musl_now_ms() - X`, where 4 and 4 were '
                'expected' % (stamps, reads))
if len(re.findall(r'\belapsed_time\b', new)) != len(re.findall(r'\belapsed_time\b', old)):
    fail.append('`elapsed_time` is inchar_loop\'s own `long` and not this phase\'s, and '
                'it moved from %d to %d' % (len(re.findall(r'\belapsed_time\b', old)),
                                            len(re.findall(r'\belapsed_time\b', new))))

# THE TWO HALVES OF THE LINE ARITHMETIC, separately.  The core is the lines above the
# first `#include`, so the boundary's index IS the core's line count -- a line removed
# from the host and a line removed from the core sum the same and mean different things.
if ncut - ocut != -16:
    fail.append('the core is %d lines and was %d, a difference of %d where -16 was '
                'expected: -6 for the typedef and the prototype with a blank and -10 '
                'for elapsed() with a blank' % (ncut, ocut, ncut - ocut))
if (len(nlines) - ncut) - (len(olines) - ocut) != 6:
    fail.append('the host is %d lines and was %d, a difference of %d where +6 was '
                'expected: +4 for musl_now_ms\'s longer body and +2 for its two statics'
                % (len(nlines) - ncut, len(olines) - ocut,
                   (len(nlines) - ncut) - (len(olines) - ocut)))

# THE HOST'S TWO STATICS, and the lazy base that is the point of them.
for line in ('static long host_now_base = 0;', 'static int host_now_based = FALSE;'):
    if new.count('\n' + line + '\n') != 1:
        fail.append('`%s` is not on a line of its own exactly once below the boundary'
                    % line)
if 'if (!host_now_based)' not in nbelow:
    fail.append('musl_now_ms does not take its base LAZILY.  Setting it in '
                'musl_host_init() instead would be an ordering dependency a host '
                'rewrite breaks silently, and the symptom would be base 0, epoch '
                'milliseconds and a 32-bit overflow on every call')

# Blank-line runs, which no verification tier can see (CLAUDE.md).
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
print('  %-12s the core has NO clock of its own: elapsed_T (%d in the input), elapsed '
      '(%d), now_tv (%d) and musl_gettimeofday (%d) are all 0 in the whole file, '
      '`struct timeval` is 0 above the boundary and %d below, and the one bare '
      '`gettimeofday` left is the call musl_now_ms makes'
      % (TAG, len(re.findall(r'\belapsed_T\b', old)),
         len(re.findall(r'\belapsed\b', old)),
         len(re.findall(r'\bnow_tv\b', old)),
         len(re.findall(r'\bmusl_gettimeofday\b', old)), tvh))
print('  %-12s four stamps `X = musl_now_ms();` and four readings `musl_now_ms() - X`, '
      'the prototype above and the definition below: the core is %d lines against %d '
      '(-16) and the host %d against %d (+6)'
      % (TAG, ncut, ocut, len(nlines) - ncut, len(olines) - ocut))
PY

# --- 2 and 3. the boundary: the cut, and the shape of what crosses it -------------------
python3 - "$f" "$state/old.c" "$tmp" <<'PY'
import collections
import re
import subprocess
import sys

TAG = 'clock'
out = sys.argv[3]
fail = []


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


DECLARED = ('host_exit host_message musl_delay musl_get_winsize musl_host_init '
            'musl_now_ms musl_read_input musl_suspend musl_term_start musl_term_stop '
            'musl_tty_keys musl_wait_for_input vim_snprintf').split()
GONE = 'musl_gettimeofday'

for which, path in (('output', sys.argv[1]), ('input', sys.argv[2])):
    lines = cut(path)
    text = '\n'.join(lines) + '\n'
    open('%s/cut.%s.c' % (out, which), 'w', errors='surrogateescape').write(text)
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
    seen = sorted(set(re.findall(r"'(\w+)' used but never defined", w)))
    want = sorted(DECLARED) if which == 'output' else sorted(
        [n for n in DECLARED if n != 'musl_now_ms'] + [GONE])
    if seen != want:
        fail.append('the %s boundary is %s and this phase declares %s.  A phase that '
                    'widens the core -> host interface changes this set and nothing '
                    'else in the pipeline would say so'
                    % (which, ' '.join(seen), ' '.join(want)))
    # THE SHAPE OF WHAT CROSSES, computed from the declaration of each boundary name.
    # A parameter or return type must be `void`, an integer this file names, `usize`
    # (the core's own `typeof(sizeof(0))`) or a pointer to a character or an integer.
    # No struct, no libc typedef, no core aggregate -- in EITHER direction.
    SCALAR = re.compile(r'^(?:const +)?(?:void|int|long|char|usize) *\**$')

    def argsof(decl, name):
        """The parameter list, by brace matching rather than by `partition('(')`.
        `__attribute__((format(printf, 3, 4)))` carries parentheses and commas of its
        own, and a split on the first `(` and the last `)` reads them as parameters --
        measured, three of them."""
        i = decl.index(name) + len(name)
        while decl[i] in ' \t':
            i += 1
        d, j = 0, i
        while j < len(decl):
            if decl[j] == '(':
                d += 1
            elif decl[j] == ')':
                d -= 1
                if d == 0:
                    break
            j += 1
        inner, out, d, last = decl[i + 1:j], [], 0, 0
        for x, c in enumerate(inner):
            if c == '(':
                d += 1
            elif c == ')':
                d -= 1
            elif c == ',' and d == 0:
                out.append(inner[last:x])
                last = x + 1
        out.append(inner[last:])
        return decl[len('static'):decl.index(name)], [a.strip() for a in out]

    for name in seen:
        decl = [l for l in lines
                if re.match(r'^static\s.*\b%s\s*\(' % re.escape(name), l)
                and l.rstrip().endswith(';')]
        if len(decl) != 1:
            fail.append('the %s boundary name `%s` has %d declarations above the cut '
                        'and must have exactly one' % (which, name, len(decl)))
            continue
        ret, args = argsof(decl[0], name)
        for a in [ret] + args:
            a = re.sub(r'\s+', ' ', a).strip()
            if a == '...':
                if 'format(printf' not in decl[0]:
                    fail.append('the %s boundary name `%s` is VARIADIC and carries no '
                                '`format(printf, ...)` attribute, so nothing constrains '
                                'what crosses in its argument list' % (which, name))
                continue
            # The parameter's NAME, if it has one, is not part of its type.
            bare = re.sub(r'\b[A-Za-z_]\w* *$', '', a).strip()
            if not (SCALAR.match(a) or SCALAR.match(bare)):
                fail.append('the %s boundary name `%s` takes or returns `%s`, which is '
                            'not a scalar or a byte buffer' % (which, name, a))

if fail:
    for line in fail:
        print('  %-12s %s' % (TAG, line))
    sys.exit(1)
print('  %-12s THE BOUNDARY IS THIRTEEN NAMES, stated as a SET: %s.  `musl_gettimeofday` '
      'is REPLACED by `musl_now_ms` and not added to, and the cut is %d lines with 0 '
      'directives, no error and no warning that is not one of the thirteen'
      % (TAG, ' '.join(sorted(DECLARED)), len(cut(sys.argv[1]))))
print('  %-12s and EVERY ONE OF THE THIRTEEN TAKES SCALARS AND BYTE BUFFERS ONLY -- '
      'void, int, long, usize, char * and int *, with vim_snprintf\'s `...` held to '
      'printf arguments by `format(printf, 3, 4)` on a build that is -Wall -Wextra '
      'clean.  IT IS TRUE OF THE INPUT TOO, and this phase does not claim to have made '
      'it so: phase 26 wrote `musl_gettimeofday(long *, long *)` precisely so that '
      '`struct timeval` would not cross.  WHAT THIS PHASE EARNS is that the workaround '
      'is gone -- no host call\'s shape is decided any more by a type the core cannot '
      'name, and the core declares nothing shaped like a libc struct' % TAG)

# --- 4. the rounding, measured -------------------------------------------------------------
PY

wait $pid_round || { echo "  clock        the rounding probe did not build or did not run"; exit 1; }
python3 - "$tmp/round.txt" <<'PY'
import sys

TAG = 'clock'
w = open(sys.argv[1]).read().split()
v = dict(zip(w[0::2], w[1::2]))
worst = int(v['worst'])
if worst != 1:
    sys.exit('  %-12s the rounding probe found a worst-case disagreement of %d ms, '
             'where the whole claim of this phase is that it is exactly 1'
             % (TAG, worst))
if int(v['minus1']) == 0 or int(v['plus1']) == 0:
    sys.exit('  %-12s the rounding probe found the disagreement in only one direction '
             '(%s below, %s above), which would make the new formula systematically '
             'biased rather than differently rounded' % (TAG, v['minus1'], v['plus1']))
if abs(float(v['mean_old']) - float(v['mean_new'])) > 0.01:
    sys.exit('  %-12s the two formulas are %s and %s ms from the true elapsed time on '
             'average, and the claim is that neither is better' % (TAG, v['mean_old'],
                                                                   v['mean_new']))
print('  %-12s PRECISION IS NOT LOST AND THE ROUNDING POINT MOVES, measured over %s '
      'random pairs: elapsed() subtracted and THEN divided, musl_now_ms divides at each '
      'reading and the caller subtracts, and the two differ by EXACTLY +-1 ms and never '
      'more -- %s pairs 1 ms lower, %s the same, %s 1 ms higher.  Microseconds were '
      'already discarded either way, and neither formula is closer to the truth: %s ms '
      'against %s ms on average.  Whether a CALLER can see 1 ms is section 8\'s `ceil` '
      'control' % (TAG, v['pairs'], v['minus1'], v['same'], v['plus1'], v['mean_old'],
                   v['mean_new']))
PY

# --- 5. canon.sh -----------------------------------------------------------------------------
wait $pid_canon || { echo "  clock        tools/canon.sh failed on the output:"; sed -n '1,10p' "$tmp/canon.log"; exit 1; }
if ! cmp -s "$f" "$tmp/canon.c"; then
    echo "  clock        tools/canon.sh is not a no-op on the output -- the new text is not written the way this file writes everything else:"
    diff "$f" "$tmp/canon.c" | sed -n '1,12p'
    exit 1
fi
echo "  clock        tools/canon.sh is a NO-OP on the output: the four \`long\` declarations, the four stamps, the four readings and musl_now_ms are written the way this file writes everything else"

# --- 6. the host's vocabulary, which this phase extends --------------------------------------
python3 tools/zhostonly.py "$f"

# --- 7. the symbols -------------------------------------------------------------------------
wait $pid_new || { echo "  clock        the output did not build with '$cflags' '$ldflags'"; exit 1; }
gcc -c -O0 -fno-stack-protector -o "$tmp/old.o" "$state/old.c"
gcc -c -O0 -fno-stack-protector -o "$tmp/new.o" "$f"
nm -u "$tmp/old.o" | awk '{print $2}' | sort > "$tmp/u.old"
nm -u "$tmp/new.o" | awk '{print $2}' | sort > "$tmp/u.new"
gone=$(comm -23 "$tmp/u.old" "$tmp/u.new" | tr '\n' ' ')
came=$(comm -13 "$tmp/u.old" "$tmp/u.new" | tr '\n' ' ')
if [ -n "$gone$came" ]; then
    echo "  clock        \`nm -u\` moved: gone [$gone] arrived [$came].  THIS PHASE FREES NOTHING AND NEEDS NOTHING"
    exit 1
fi
if ! grep -qx 'gettimeofday' "$tmp/u.new"; then
    echo "  clock        \`gettimeofday\` is NOT in the undefined set, and it must be: the host still calls it to implement musl_now_ms"
    exit 1
fi
ext=$(nm --extern-only --defined-only "$tmp/new.o" | awk '{print $3}' | sort | tr '\n' ' ')
if [ "$ext" != "main " ]; then
    echo "  clock        the output defines external symbols other than main: $ext"
    exit 1
fi
echo "  clock        \`nm -u\` is THE SAME SET, $(wc -l <"$tmp/u.new") names, as a \`comm\` empty in BOTH directions, and \`main\` is still the only external symbol.  \`gettimeofday\` IS STILL THERE and this phase says so as an equality: a reader expects a clock phase to free a clock symbol, and it cannot -- the host calls it to implement musl_now_ms, and a symbol leaves when its last CALLER leaves the FILE, which is the split and not this phase.  The output is $(stat -c%s "$tmp/new") bytes against $(stat -c%s "$state/old")"

# --- 8. the probes, and the recordings -------------------------------------------------------
for v in ceil epoch fast froze nobell allbell; do
    [ -f "$tmp/$v" ] || { echo "  clock        the $v control did not build"; exit 1; }
done
tools/zrecord.sh "$state/old" "$state/old.c" "$tmp/REC.old" >/dev/null 2>&1 &
pid_ro=$!
tools/zrecord.sh "$tmp/new" "$f" "$tmp/REC.new" >/dev/null 2>&1 &
pid_rn=$!
tools/zrecord.sh "$tmp/ceil" "$tmp/ceil.c" "$tmp/REC.ceil" >/dev/null 2>&1 &
pid_rc=$!
tools/zrecord.sh "$tmp/epoch" "$tmp/epoch.c" "$tmp/REC.epoch" >/dev/null 2>&1 &
pid_re=$!

python3 - "$tmp" "$state/old" <<'PY'
import os
import sys
import time

sys.path.insert(0, 'tools')          # tools/zstream.py -- stage() is the one place a
import zstream                       # binary is renamed to `vim`, for the race its
                                     # docstring describes

TAG = 'clock'
tmp, old = sys.argv[1], sys.argv[2]
fail = []

# `gs` IS nv_g_cmd's `s` arm and it is do_sleep(count * 1000): the one call site a
# keystroke file can drive, and the only way real time passes inside the editor.
PROBES = (('1gs', [b'gs:q!\r'], 0),
          ('2gs', [b'2gs:q!\r'], 0),
          ('hgshh', [b'hgshh:q!\r'], 2))


def run(binary, keys, timeout=8):
    t0 = time.monotonic()
    try:
        _, stdout, _, rc = zstream.session(binary, keys, timeout=timeout)
    except zstream.Blocked:
        return None, None, None
    return int((time.monotonic() - t0) * 1000), stdout.count(b'\x07'), rc


res = {}
for who, path, which in (
        ('old', old, 'all'), ('new', tmp + '/new', 'all'),
        ('ceil', tmp + '/ceil', 'all'), ('epoch', tmp + '/epoch', 'all'),
        ('fast', tmp + '/fast', 'sleep'), ('froze', tmp + '/froze', 'one'),
        ('nobell', tmp + '/nobell', 'bell'), ('allbell', tmp + '/allbell', 'bell')):
    want = {'all': ('1gs', '2gs', 'hgshh'), 'sleep': ('1gs', '2gs'),
            'one': ('1gs',), 'bell': ('hgshh',)}[which]
    res[who] = {name: run(path, keys) for name, keys, _ in PROBES if name in want}

# THE PRODUCT AND THE INPUT MUST AGREE, and the timing assertion is a DIFFERENCE rather
# than an absolute: do_sleep caps a wait at 1,000 ms, so 2gs is two iterations and 1gs
# is one, and `2gs - 1gs` is a second of sleeping that no machine load can shorten.
for who in ('old', 'new', 'ceil', 'epoch'):
    for name, _, bells in PROBES:
        ms, got, rc = res[who][name]
        if ms is None:
            fail.append('%s: the %s probe never returned' % (who, name))
            continue
        if rc != 0:
            fail.append('%s: the %s probe exited %d' % (who, name, rc))
        if got != bells:
            fail.append('%s: the %s probe rang %d bell(s) and %d were expected'
                        % (who, name, got, bells))
    if res[who]['1gs'][0] is None or res[who]['2gs'][0] is None:
        continue
    one, two = res[who]['1gs'][0], res[who]['2gs'][0]
    if one < 950:
        fail.append('%s: `1gs` returned after %d ms and do_sleep(1000) cannot be shorter '
                    'than 1,000' % (who, one))
    # A LOWER BOUND ON A SLEEP, NEVER A DIFFERENCE BETWEEN TWO RUNS.  This asked for
    # `two - one >= 900` until phase 30's verify caught it: both are wall-clock times
    # taken from OUTSIDE, around whole editor runs, so each carries its own startup
    # jitter -- and under a loaded machine `one` inflated to 1,133 ms while `two` stayed
    # at 2,006, a difference of 873, and a correct phase failed.  Widening the threshold
    # would move that boundary rather than remove it, which is the lesson commit b66e982
    # recorded about a clock in the pty harness.  A lower bound cannot flake in that
    # direction: a sleep takes AT LEAST as long as it asks for, and load can only make it
    # longer.  `2gs` is two capped 1,000 ms waits, so 1,900 leaves 100 ms of slack for a
    # short final tick and none for the failure this replaces.  The `fast` control still
    # breaks it -- a clock running 1000x returns from `2gs` after one wait, measured at
    # 1,008 ms, which is below the bound.
    if two < 1900:
        fail.append('%s: `2gs` took %d ms, where two capped 1,000 ms waits were expected '
                    '-- do_sleep\'s loop is not measuring time' % (who, two))

# AND EACH HALF OF THE PROBE IS PROVEN ABLE TO FAIL, by a control aimed at THAT half.
#
# The timing: `fast` runs the clock 1000x, so `2gs` finishes after ONE 1,000 ms wait
# instead of two and the difference collapses; `froze` never advances it at all, so
# do_sleep's `done` stays 0 and `1gs` NEVER RETURNS.
fone, ftwo = res['fast']['1gs'][0], res['fast']['2gs'][0]
if fone is None or ftwo is None:
    fail.append('the `fast` control did not return, and it was chosen because it does')
elif ftwo >= 1900:
    fail.append('the `fast` control -- a clock running 1000x -- gave `2gs` %d ms, which '
                'is over the bound the assertion above uses.  It should return after ONE '
                'wait, and if it does not that assertion proves nothing'
                % ftwo)
if res['froze']['1gs'][0] is not None:
    fail.append('the `froze` control -- a clock that never advances -- returned from '
                '`1gs` after %d ms.  do_sleep\'s `done` can never reach 1,000 with a '
                'clock that does not move, so the probe is not measuring do_sleep'
                % res['froze']['1gs'][0])

# The bells: a CLOCK control cannot answer for them, because one that breaks the rate
# limit breaks do_sleep first and `hgshh` then never returns at all -- measured, `froze`
# and a backwards clock both block.  So the two bell controls move vim_beep's THRESHOLD
# and leave the clock alone, and they bracket it: 500000 puts it out of reach, -1 makes
# it always true.
if res['nobell']['hgshh'][1] != 1:
    fail.append('the `nobell` control -- vim_beep\'s 500 written 500000 -- rang %s bells '
                'on `hgshh` and 1 was expected.  The second h rings BECAUSE more than '
                '500 ms have passed, and if moving the threshold does not stop it the '
                'probe is measuring something else'
                % (res['nobell']['hgshh'][1],))
if res['allbell']['hgshh'][1] != 3:
    fail.append('the `allbell` control -- vim_beep\'s 500 written -1 -- rang %s bells on '
                '`hgshh` and 3 were expected.  The THIRD h is suppressed because fewer '
                'than 500 ms have passed, and if making the test always true does not '
                'let it ring, that half of the probe measures nothing'
                % (res['allbell']['hgshh'][1],))

if fail:
    for line in fail:
        print('  %-12s %s' % (TAG, line))
    sys.exit(1)
print('  %-12s THE PROBES: `1gs` %d ms and `2gs` %d on the binary this phase was HANDED, '
      '%d and %d on its own -- do_sleep\'s loop, at one wait and at two.  `hgshh` rings '
      '2 bells on both, which is vim_beep\'s threshold in BOTH directions in one probe: '
      'h at column 0 rings, gs lets a second pass, the next h rings because more than '
      '500 ms have gone and the third is suppressed because fewer than 500 have'
      % (TAG, res['old']['1gs'][0], res['old']['2gs'][0],
         res['new']['1gs'][0], res['new']['2gs'][0]))
print('  %-12s AND EACH HALF FAILS ON A CONTROL AIMED AT IT.  The timing: with the clock '
      'running 1000x fast `2gs` is %d ms against `1gs` %d -- one wait instead of two, '
      'the difference gone -- and with a clock that never advances `1gs` NEVER RETURNS.  '
      'The bells: a clock control cannot answer for those, because one that breaks the '
      'rate limit breaks do_sleep first and `hgshh` then blocks, so the two bell '
      'controls move vim_beep\'s 500 instead -- to 500000, and `hgshh` rings %d; to -1, '
      'and it rings %d'
      % (TAG, ftwo, fone, res['nobell']['hgshh'][1], res['allbell']['hgshh'][1]))
print('  %-12s `ceil` -- every reading rounded UP instead of down, which perturbs each '
      'one by up to a full millisecond, TWICE what section 4 measured -- gives `1gs` '
      '%d ms, `2gs` %d and 2 bells, exactly the product.  `epoch` -- milliseconds since '
      '1970 rather than since the whole second of the first call -- gives %d, %d and 2. '
      ' So no caller can see one millisecond, and the origin is a free choice'
      % (TAG, res['ceil']['1gs'][0], res['ceil']['2gs'][0],
         res['epoch']['1gs'][0], res['epoch']['2gs'][0]))
PY

wait $pid_ro
wait $pid_rn
wait $pid_rc
wait $pid_re
for v in old ceil epoch; do
    if ! diff -rq "$tmp/REC.$v" "$tmp/REC.new" >"$tmp/rec.diff" 2>&1; then
        echo "  clock        the declared delta is NOTHING AT ALL and the recording of \`$v\` differs from the output's:"
        sed -n '1,12p' "$tmp/rec.diff"
        exit 1
    fi
done
python3 - "$tmp/REC.new/screen" <<'PY'
import os
import sys

# THE CORPUS IS BLIND TO THE CLOCK, and this is that measurement rather than a claim:
# vim_beep's rate limit is the only reading a screen case could see, and no case rings
# the bell twice, so there is never a second bell for the limit to suppress.  It is the
# reason section 8 has probes at all, and it is asserted so that a case that DID start
# ringing twice would arrive as a failure here rather than as a silent strengthening
# nobody noticed.
d = sys.argv[1]
bells = []
for name in sorted(os.listdir(d)):
    for line in open(os.path.join(d, name)):
        if line.startswith('--- bells '):
            bells.append(int(line.split()[2]))
            break
if max(bells) > 1:
    sys.exit('  %-12s %d of the %d screen cases now ring the bell more than once, so '
             'the corpus CAN see vim_beep\'s rate limit and this phase\'s empty '
             'declaration needs re-arguing rather than asserting'
             % ('clock', sum(1 for b in bells if b > 1), len(bells)))
print('  %-12s the declared delta is NOTHING AT ALL and FOUR FULL RECORDINGS ARE '
      'BYTE-IDENTICAL -- the binary this phase was handed, its own, `ceil` and `epoch` '
      '-- across 102 screen cases, every Ex command, every command line, the pty '
      'scenarios and the terminal table.  AND THE CORPUS IS BLIND TO THE CLOCK, '
      'measured: %d of the %d cases ring the bell once and %d not at all, and NOT ONE '
      'rings it twice, so vim_beep\'s 500 ms limit -- the only reading a screen case '
      'could see -- is never asked to suppress anything.  That is why this phase owes '
      'the probes above, and they are what answer for it'
      % ('clock', sum(1 for b in bells if b == 1), len(bells),
         sum(1 for b in bells if b == 0)))
PY

# tools/phaserun.sh runs tools/zerodelta.sh --phase 28 after this check, and that is the
# second opinion on the same claim -- against .reference/zero-baselines rather than
# against the binary this phase was handed.
