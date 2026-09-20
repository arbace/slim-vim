#!/bin/sh
# Zero phase 28 -- the scalar clock.
# See ZERO-PLAN.md 4c, ZERO-GOAL.md, and pipes/zero26-edit.sh, which created the thing
# this phase retires.
#
# Usage: pipes/zero28-edit.sh <work-dir> <state-dir>     (run from the repository root)
#
# WHAT THE CORE DOES WITH TIME, read out of the input rather than remembered: it STAMPS
# NOW and later ASKS HOW MANY MILLISECONDS HAVE PASSED.  That is the whole of it, at
# four places -- do_sleep's `done < msec` loop, vim_beep's 500 ms rate limit,
# handle_osc's `>= p_ost` timeout and inchar_loop's `wtime - elapsed_time` deadline --
# and NOT ONE of the four ever reads a field, prints a reading or compares two stamps
# for equality.  So the core never needs the LAYOUT of a clock, only a scalar.
#
# WHAT GOES, all of it phase 26's:
#
#   elapsed_T       8 mentions.  A core-owned TAGLESS `struct { long tv_sec; long
#                   tv_usec; }` -- phase 26's mirror of <sys/time.h>'s struct timeval,
#                   whose layout that phase had to static_assert equal.  The core
#                   stops modelling a host structure: the four objects become `long`.
#   elapsed()       6 mentions.  Its entire body is one clock read and a subtraction to
#                   milliseconds; with a scalar clock the subtraction is the caller's
#                   one operator and the function has nothing left to do.
#   musl_gettimeofday(long *, long *)
#                   7 mentions.  The host call phase 26 introduced, an out-parameter
#                   pair because a struct could not cross.  It becomes
#                   `long musl_now_ms(void)`: a value, not two stores.
#
# WHAT IT EARNS.  Read all thirteen core -> host signatures and the sentence is true:
# every one takes scalars and byte buffers only.  IT WAS ALREADY TRUE AT r27 -- phase 26
# chose `long *, long *` precisely so that `struct timeval` would not cross -- so this
# phase does not earn THAT sentence and the check does not claim it.  What it earns is
# the narrower one that was false until now: the core no longer DECLARES a type shaped
# like a libc struct, and its whole notion of time is one `long`.  `struct timeval`,
# `elapsed_T`, `elapsed` and `musl_gettimeofday` are all at 0 above the boundary
# afterwards; the host keeps its own `struct timeval`, for `select` and for the one
# `gettimeofday` call that is left in the file.
#
# WHAT `musl_now_ms()` RETURNS, AND IT IS A DECISION, NOT A DETAIL.  Milliseconds since
# a MONOTONIC ORIGIN the host chooses -- the whole second of its first call -- and not
# milliseconds since the epoch.  Every core use is a DIFFERENCE, so the origin is free,
# and the two choices are measured against each other in the check:
#
#   epoch      tv_sec * 1000 is ~1.79e12 today.  On a target where `long` is 64 bits
#              that is nothing; on one where it is 32 bits it overflows ON THE FIRST
#              CALL, every call, for ever -- signed overflow, so the standard gives no
#              value at all and -fwrapv gives a wrong one.  The clock is broken from
#              the moment the editor starts.
#   monotonic  (tv_sec - base) * 1000 overflows a 32-bit `long` after 2**31 ms, which
#              is 24.86 DAYS of editor uptime.  Until then every reading is exact.
#
# So the origin moves the 32-bit failure from "immediately" to "after 24.86 days", and
# it costs one branch and two statics IN THE HOST -- which is the part a new target
# rewrites anyway.  The base is LAZY rather than set in musl_host_init(), because an
# ordering dependency on another host function is exactly the kind of thing a host
# rewrite breaks silently, and the symptom would be base 0, epoch milliseconds and the
# overflow above.
#
# THE ORIGIN IS A WHOLE SECOND ON PURPOSE.  With `base` a second and no microsecond
# part, musl_now_ms() is epoch-milliseconds less the constant base*1000, so a
# DIFFERENCE of two readings is IDENTICAL under the two choices.  The origin is
# therefore behaviourally invisible, which is what lets the check measure the rounding
# ONCE instead of twice, and what lets it require the epoch variant's recording to be
# byte-identical to the product's.
#
# PRECISION IS NOT LOST AND THE ROUNDING POINT MOVES.  elapsed() subtracted and THEN
# divided: `(now.tv_sec - start.tv_sec) * 1000 + (now.tv_usec - start.tv_usec) / 1000`.
# musl_now_ms() divides at each reading and the caller subtracts.  Microseconds were
# already discarded either way -- the phase loses no precision the input had -- but the
# two roundings are not the same function, and MEASURED over 20,000,000 random pairs
# the difference is EXACTLY +-1 ms, both ways, never more, with the two formulas equally
# far from the true elapsed time (+0.4995 ms and +0.4996 ms mean).  The check runs that
# measurement rather than repeating it.  Whether a caller can SEE 1 ms is a separate
# question and the check answers it at each of the four.
set -eu

work=${1:?usage: zero28-edit.sh <work-dir> <state-dir>}
state=${2:?usage: zero28-edit.sh <work-dir> <state-dir>}
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
import re
import sys

TAG = 'clock'
path = sys.argv[1]
t = open(path, errors='surrogateescape').read()


def die(msg):
    sys.exit('  %-12s %s' % (TAG, msg))


def say(what):
    print('  %-12s %s' % (TAG, what))


def blank_runs(text):
    L = text.split('\n')
    return sum(1 for i in range(1, len(L)) if L[i] == '' and L[i - 1] == '')


lines = t.split('\n')
runs_before = blank_runs(t)

# ---- 0. the file this edit was written against ----------------------------------------
# ELEVEN DIRECTIVES, every one an `#include <...>`, CONTIGUOUS, and NOTHING ABOVE THEM.
# Phase 27 moved them down from the first eleven lines and made the first of them the
# boundary between the core and the host (ZERO-PLAN.md 4c); this phase edits both sides
# of that line and must know exactly where it is.
directives = [i for i, l in enumerate(lines) if l.lstrip().startswith('#')]
if len(directives) != 11:
    die('the file has %d preprocessor directives and this phase was written against 11'
        % len(directives))
if directives != list(range(directives[0], directives[0] + 11)):
    die('the eleven directives are not contiguous: %s'
        % ' '.join(str(i + 1) for i in directives))
INC = re.compile(r'^#include <([A-Za-z0-9_/.]+)>$')
if any(not INC.match(lines[i]) for i in directives):
    die('a directive is not an `#include <...>` of a system header, and no phase may '
        'add one')
cut = directives[0]
core = '\n'.join(lines[:cut])
below = '\n'.join(lines[cut:])
say('eleven `#include`s, contiguous, at lines %d-%d, and NOTHING above the first of '
    'them -- so the core is the %d lines above the boundary and the host is the %d '
    'below it' % (cut + 1, cut + 11, cut, len(lines) - cut - 1))

# ---- 1. the host region, which is where the new definition has to land -----------------
# `zhostonly` reads the host as the lines from `host_winch_pending` to the last
# brace of musl_suspend(), and requires every mention of its vocabulary -- `struct
# timeval` among them -- to be inside it.  musl_now_ms() names `struct timeval`, so it
# is defined where musl_gettimeofday was, above musl_delay, which is inside that region.
HOST = 'static volatile sig_atomic_t host_winch_pending'
hb = [i for i, l in enumerate(lines) if l.startswith(HOST)]
if len(hb) != 1:
    die('the host block does not begin exactly once with %r -- found %d' % (HOST, len(hb)))

# ---- 2. the inventory, counted here rather than remembered ------------------------------
# Every number below is what this edit is about to act on, and a count that has moved
# under the phase stops it instead of letting it cut something else.
WANT = (('elapsed_T', 8, 0), ('elapsed', 6, 0), ('elapsed_time', 3, 0),
        ('now_tv', 5, 0), ('start_tv', 20, 0), ('musl_gettimeofday', 6, 1),
        ('gettimeofday', 0, 1), ('musl_now_ms', 0, 0))
for name, ncore, nbelow in WANT:
    gc = len(re.findall(r'\b%s\b' % name, core))
    gb = len(re.findall(r'\b%s\b' % name, below))
    if (gc, gb) != (ncore, nbelow):
        die('`%s` occurs %d times above the boundary and %d below it, where this phase '
            'was written against %d and %d' % (name, gc, gb, ncore, nbelow))
tv_core = len(re.findall(r'struct timeval\b', core))
tv_below = len(re.findall(r'struct timeval\b', below))
if (tv_core, tv_below) != (0, 3):
    die('`struct timeval` occurs %d times above the boundary and %d below, where this '
        'phase was written against 0 and 3' % (tv_core, tv_below))
say('the core\'s clock is elapsed_T 8, elapsed 6, musl_gettimeofday 6 and `struct '
    'timeval` 0 -- phase 26 took the last of those; the host has musl_gettimeofday\'s '
    'definition, its one real `gettimeofday` call and three `struct timeval`')

# ---- 3. the literals ---------------------------------------------------------------------
# Phase 23 was caught out by three string literals holding `NULL`, and phase 26 applied
# the lesson rather than assuming it.  So does this one: no literal may hold any name
# this phase substitutes.
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
NAMES = re.compile(r'\b(?:elapsed_T|elapsed|now_tv|start_tv|musl_gettimeofday'
                   r'|gettimeofday|musl_now_ms)\b|struct timeval\b')
bad = [t[a:b] for a, b in S if NAMES.search(t[a:b])]
if bad:
    die('a literal holds a name this phase substitutes: %s' % ' / '.join(bad))
say('%d string and character literals, NONE holding any of the seven names -- so every '
    'substitution below is over code' % len(S))


def once(text, old, new, why):
    if text.count(old) != 1:
        die('`%s` is not in the file exactly once (%s)'
            % (old.replace('\n', '\\n')[:70], why))
    return text.replace(old, new, 1)


# ---- 4. the type and the function leave the core -----------------------------------------
# The typedef, the prototype and one of the two blank lines around them.  Deleting the
# five lines alone would leave a run of two blank lines, which no verification tier can
# see (CLAUDE.md) and which the arithmetic at the end of this edit refuses.
t = once(t, '''
typedef struct {
    long        tv_sec;
    long        tv_usec;
} elapsed_T;
static long elapsed(elapsed_T *start_tv);
''', '', 'the tagless struct and the prototype, which phase 26 wrote')

t = once(t, '''
    static long
elapsed(elapsed_T *start_tv)
{
    elapsed_T       now_tv;

    musl_gettimeofday(&now_tv.tv_sec, &now_tv.tv_usec);
    return (now_tv.tv_sec - start_tv->tv_sec) * 1000L
         + (now_tv.tv_usec - start_tv->tv_usec) / 1000L;
}
''', '', 'elapsed(), whose entire body is one clock read and one subtraction')
say('`elapsed_T` and `elapsed()` leave the core: 5 lines of declaration and 9 of '
    'definition, with one blank line of each pair, so no run of two blank lines is left '
    'behind')

# ---- 5. the four objects become `long` ----------------------------------------------------
# The declarator column is kept: this file aligns a declaration block and `long` is five
# characters shorter than `elapsed_T`.  tools/canon.sh is the check that the result is
# written the way this file writes everything else, and it is run on the output.
for old, new, who in (
        ('    elapsed_T   start_tv;\n\n     musl_gettimeofday(&start_tv.tv_sec, '
         '&start_tv.tv_usec) ;\n\n    if (hide_cursor)',
         '    long        start_tv;\n\n    start_tv = musl_now_ms();\n\n'
         '    if (hide_cursor)', 'do_sleep'),
        ('        static elapsed_T        start_tv;',
         '        static long             start_tv;', 'vim_beep'),
        ('    elapsed_T       start_tv;\n} oscstate_T;',
         '    long            start_tv;\n} oscstate_T;', 'oscstate_T'),
        ('    elapsed_T   start_tv;\n\n     musl_gettimeofday(&start_tv.tv_sec, '
         '&start_tv.tv_usec) ;\n\n    for (;;)',
         '    long        start_tv;\n\n    start_tv = musl_now_ms();\n\n'
         '    for (;;)', 'inchar_loop')):
    t = once(t, old, new, 'the clock object in %s' % who)

# ---- 6. the remaining stamps and every difference -------------------------------------------
# A stamp is `X = musl_now_ms();` and a reading is `musl_now_ms() - X`.  The leading
# space and the space before the semicolon at these sites are what macro expansion left
# behind, three pipelines ago; the replacements are written plainly and canon.sh is what
# says so.
for old, new, who in (
        ('             musl_gettimeofday(&start_tv.tv_sec, &start_tv.tv_usec) ;',
         '            start_tv = musl_now_ms();', "vim_beep's stamp"),
        ('         musl_gettimeofday(&osc_state.start_tv.tv_sec, '
         '&osc_state.start_tv.tv_usec) ;',
         '        osc_state.start_tv = musl_now_ms();', "handle_osc's stamp"),
        ('        done =  elapsed(&(start_tv)) ;',
         '        done = musl_now_ms() - start_tv;', "do_sleep's reading"),
        ('        if (!did_init ||  elapsed(&(start_tv))  > 500)',
         '        if (!did_init || musl_now_ms() - start_tv > 500)',
         "vim_beep's 500 ms rate limit"),
        ('    if ( elapsed(&(osc_state.start_tv))  >= p_ost)',
         '    if (musl_now_ms() - osc_state.start_tv >= p_ost)',
         "handle_osc's p_ost timeout"),
        ('            elapsed_time =  elapsed(&(start_tv)) ;',
         '            elapsed_time = musl_now_ms() - start_tv;',
         "inchar_loop's deadline")):
    t = once(t, old, new, who)
say('four stamps -- do_sleep, vim_beep, handle_osc, inchar_loop -- are `X = '
    'musl_now_ms();`, and the four readings are `musl_now_ms() - X`.  `-` binds tighter '
    'than `>` and `>=`, so the two comparisons need no parenthesis they did not have')

# ---- 7. the host call ------------------------------------------------------------------------
t = once(t, 'static void musl_gettimeofday(long *sec, long *usec);\n',
         'static long musl_now_ms(void);\n', "the host call's prototype")
t = once(t, 'static int host_tty_raw = FALSE;\n',
         'static int host_tty_raw = FALSE;\n'
         'static long host_now_base = 0;\n'
         'static int host_now_based = FALSE;\n',
         "the host's own state, beside the terminal's")
t = once(t, '''    static void
musl_gettimeofday(long *sec, long *usec)
{
    struct timeval tv;

    gettimeofday(&tv, nullptr);
    *sec = tv.tv_sec;
    *usec = tv.tv_usec;
}
''', '''    static long
musl_now_ms(void)
{
    struct timeval tv;

    gettimeofday(&tv, nullptr);
    if (!host_now_based)
    {
        host_now_based = TRUE;
        host_now_base = tv.tv_sec;
    }
    return (tv.tv_sec - host_now_base) * 1000L + tv.tv_usec / 1000L;
}
''', "the host call's definition, above musl_delay and inside zhostonly's region")
say('`long musl_now_ms(void)` replaces `void musl_gettimeofday(long *, long *)`: '
    'milliseconds since the WHOLE SECOND of its first call, which makes a difference of '
    'two readings identical to what an epoch-millisecond clock would give and keeps '
    '(tv_sec - base) * 1000 inside a 32-bit `long` for 24.86 days')

# ---- 8. what the file is now --------------------------------------------------------------------
L = t.split('\n')
CORE_DELTA = -6 - 10
BELOW_DELTA = 4 + 2
if len(L) - len(lines) != CORE_DELTA + BELOW_DELTA:
    die('the file moved by %d lines where %d was expected: -6 for the typedef and the '
        'prototype with a blank, -10 for elapsed() with a blank, +4 for musl_now_ms\'s '
        'longer body and +2 for the host\'s two statics'
        % (len(L) - len(lines), CORE_DELTA + BELOW_DELTA))
ndir = [i for i, l in enumerate(L) if l.lstrip().startswith('#')]
# THE BOUNDARY MOVES UP BY WHAT THE CORE LOST, and by exactly that: the core is the
# lines above the first `#include`, so the directive's index IS the core's line count.
# The two halves of the arithmetic are therefore checked separately -- a line removed
# from the host and one removed from the core sum the same and mean different things.
if ndir != list(range(directives[0] + CORE_DELTA, directives[0] + CORE_DELTA + 11)):
    die('the eleven directives are not the eleven contiguous lines at %d: they are at '
        '%s.  The first one IS the boundary, and it moves up by exactly what the core '
        'lost' % (directives[0] + CORE_DELTA + 1,
                  ' '.join(str(i + 1) for i in ndir[:3])))
if any(not INC.match(L[i]) for i in ndir):
    die('a directive is no longer an `#include <...>` of a system header')
ncore = '\n'.join(L[:ndir[0]])
nbelow = '\n'.join(L[ndir[0]:])
for name in ('elapsed_T', 'elapsed', 'now_tv', 'musl_gettimeofday'):
    n = len(re.findall(r'\b%s\b' % name, t))
    if n:
        die('`%s` still occurs %d times in the file' % (name, n))
if re.search(r'struct timeval\b', ncore):
    die('`struct timeval` is back above the boundary')
if len(re.findall(r'struct timeval\b', nbelow)) != 3:
    die('the host should still have its three `struct timeval` and has %d'
        % len(re.findall(r'struct timeval\b', nbelow)))
if len(re.findall(r'\bgettimeofday\b', t)) != 1:
    die('the bare name `gettimeofday` occurs %d times and must occur exactly once -- '
        'the one call musl_now_ms makes' % len(re.findall(r'\bgettimeofday\b', t)))
if re.search(r'\bgettimeofday\b', ncore):
    die('the core calls `gettimeofday` directly')
if len(re.findall(r'\bmusl_now_ms\b', ncore)) != 9:
    die('`musl_now_ms` occurs %d times above the boundary where 9 were expected -- the '
        'prototype, four stamps and four readings'
        % len(re.findall(r'\bmusl_now_ms\b', ncore)))
if len(re.findall(r'\bmusl_now_ms\b', nbelow)) != 1:
    die('`musl_now_ms` occurs %d times below the boundary where 1 was expected -- its '
        'definition' % len(re.findall(r'\bmusl_now_ms\b', nbelow)))
if len(re.findall(r'\belapsed_time\b', t)) != 3:
    die('`elapsed_time`, which is inchar_loop\'s own `long` and not this phase\'s, is at '
        '%d and was at 3' % len(re.findall(r'\belapsed_time\b', t)))
if blank_runs(t) != runs_before:
    die('the edit left %d runs of two blank lines where there were %d'
        % (blank_runs(t), runs_before))
say('the core has NO clock type and NO clock call of its own: elapsed_T, elapsed, '
    'now_tv, musl_gettimeofday and `struct timeval` are all at 0 above the boundary, '
    'musl_now_ms is 9 there and 1 below, and the file is %d lines against %d'
    % (len(L) - 1, len(lines) - 1))

open(path, 'w', errors='surrogateescape').write(t)
PY

# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  clock        the input binary did not build with '$cflags' '$ldflags'"; exit 1; }
echo "  clock        the input is $state/old, $(stat -c%s "$state/old") bytes, built with SOURCE_DATE_EPOCH=0 beside the source it came from -- EVERY substitution here changes code, so unlike phase 26 there is no tier 1 equality to fall back on and the recording answers for all of it"

# tools/phaserun.sh sweeps next, then runs pipes/zero28-check.sh.
