#!/bin/sh
# Zero phase 32 -- the clock crosses the boundary.
# See ZERO-PLAN.md 4c, ZERO-GOAL.md, pipes/zero26-edit.sh (which wrote the core's libc
# prototypes) and pipes/zero28-edit.sh (the scalar clock, whose musl_now_ms is this
# phase's sibling).
#
# Usage: pipes/zero32-edit.sh <work-dir> <state-dir>     (run from the repository root)
#
# THE CORE READS TWO CLOCKS AND ONLY ONE OF THEM HAS CROSSED.  Phase 28 gave the
# elapsed-milliseconds clock to the host as `long musl_now_ms(void)`.  The other one --
# the wall clock, `time(2)`, which the editor stamps a history entry and an undo header
# with -- is still the core's: `time_T vim_time(void) { return time(nullptr); }` at
# five call sites, `long time(long *tp);` in the core's own libc prototype block, and
# TWO MORE CALLS THAT BYPASS THE WRAPPER ALTOGETHER, inside `ui_focus_change()`.  This
# phase is the user's two steps, in order.
#
#   STEP ONE   the two standalone `time(nullptr)` in ui_focus_change become `vim_time()`.
#              After it, `time(` has exactly ONE call site above the boundary: the one
#              inside the wrapper.
#   STEP TWO   the wrapper moves below the boundary as `host_time()`, declared in the
#              core's host block beside host_exit, host_message and the musl_ set, and
#              `long time(long *tp);` leaves the core -- the host takes `time` from
#              <time.h>, which is one of the eleven includes.
#
# THE PROTOTYPE IS LOAD-BEARING AND REMOVING IT WOULD SILENTLY REGRESS.  `typedef long
# time_T;` is phase 26's, and it is correct ONLY because `long time(long *tp);` sits
# above <time.h>'s own declaration of the same function: gcc compares the two and says
# `conflicting types for 'time'` if they disagree -- MEASURED by phase 26's `m1`
# control, and measured again here.  Phase 26's sixteen static_asserts were a control in
# ITS check and are NOT in the product (the twelve that survive below the includes are
# phase 27's constants), so once the prototype goes there is nothing left comparing the
# core's width to the host's, and `host_time()` returning a narrower type than `time_t`
# would truncate in silence on a target where the two differ.  So the prototype is
# REPLACED, not merely deleted:
#
#     static_assert(_Generic((time_T)0, time_t: 1, default: 0), "time_T is time_t");
#
# below the includes, beside the twelve.  pipes/zero32-check.sh measures that it holds
# AND that it fails when `time_T` is perturbed to `int` -- a guarantee you cannot break
# is not one.
#
# `host_time()` RETURNS `long`, NOT `time_T`, AND THAT IS A DECISION.  Its DEFINITION is
# below the boundary, and `time_T` is a core typedef declared above it: when the file is
# finally cut at the first `#include` the host half cannot name it.  `musl_now_ms()`
# returns `long` for exactly that reason and this is its sibling, so the two halves of
# the clock cross in the same shape -- and the boundary's stated property, that every
# core -> host signature takes scalars and byte buffers only (pipes/zero28-check.sh),
# survives a fourteenth name.  Nothing is converted at any call site: `time_T` IS `long`
# in this file, the check asserts the typedef line itself, and the static_assert above
# pins that `long` to `time_t`.
#
# WHAT DOES NOT CHANGE, AND THE CHECK MEASURES IT RATHER THAN ARGUING IT.
# `ui_focus_change()` reads the clock TWICE, in two separate statements --
# `if (in_focus && last_time + 2 < ...)` and then `last_time = ...` -- and it still
# does: two reads, the same two statements, the same order.  The pair could always
# straddle a second boundary between the test and the store, and it can still, neither
# more nor less often: what changes is the spelling of the read, not how many there are
# or when.  pipes/zero32-check.sh instruments every clock read on BOTH binaries and
# requires the same count in the same records, with a control that collapses the two
# reads into one and moves it.
#
# THE ENGLISH WORD `time` IS NOT A CALL.  `op_shift()`'s NGETTEXT strings say "%ld line
# %sed %d time" / "times", and ``zhostonly`` learned the same lesson about
# `"close buffer"`: every count here is taken with string and character literals blanked
# out, and the substitutions are exact multi-line blocks, never a bare `time` -> anything.
set -eu

work=${1:?usage: zero32-edit.sh <work-dir> <state-dir>}
state=${2:?usage: zero32-edit.sh <work-dir> <state-dir>}
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

TAG = 'wallclock'
path = sys.argv[1]
t = open(path, errors='surrogateescape').read()


def die(msg):
    sys.exit('  %-12s %s' % (TAG, msg))


def say(what):
    print('  %-12s %s' % (TAG, what))


def blank_runs(text):
    L = text.split('\n')
    return sum(1 for i in range(1, len(L)) if L[i] == '' and L[i - 1] == '')


def strip_strings(line):
    """Blank out string and character literals.  zhostonly's, and for the same
    reason: this file says "%ld line %sed %d time" in two NGETTEXT strings, and a count
    that read those as calls would be counting English."""
    out = []
    i, n = 0, len(line)
    while i < n:
        c = line[i]
        if c in '"\'':
            q = c
            out.append(' ')
            i += 1
            while i < n:
                if line[i] == '\\':
                    i += 2
                    continue
                if line[i] == q:
                    break
                i += 1
            i += 1
            continue
        out.append(c)
        i += 1
    return ''.join(out)


def code(lines):
    return '\n'.join(strip_strings(l) for l in lines)


lines = t.split('\n')
runs_before = blank_runs(t)

# ---- 0. the file this edit was written against -----------------------------------------
# ELEVEN DIRECTIVES, every one an `#include <...>`, CONTIGUOUS, and NOTHING ABOVE THEM.
# Phase 27 made the first of them the boundary between the core and the host
# (ZERO-PLAN.md 4c); this phase edits both sides of that line and must know where it is.
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
if '#include <time.h>' not in [lines[i] for i in directives]:
    die('<time.h> is not among the eleven includes.  It is what will declare `time()` '
        'for the host once the core stops declaring it, and what the static_assert this '
        'phase adds compares `time_T` against')
cut = directives[0]
core = code(lines[:cut])
below = code(lines[cut:])
say('eleven `#include`s, contiguous, at lines %d-%d, <time.h> among them, and NOTHING '
    'above the first of them -- so the core is the %d lines above the boundary and the '
    'host is the %d below it' % (cut + 1, cut + 11, cut, len(lines) - cut - 1))

# ---- 1. the inventory, counted here rather than remembered -------------------------------
# Every number is what this edit is about to act on, taken on the literal-stripped text.
WANT = (('time', 4, 1), ('vim_time', 7, 0), ('host_time', 0, 0), ('time_T', 10, 0),
        ('time_t', 0, 0), ('musl_now_ms', 9, 1))
for name, ncore, nbelow in WANT:
    gc = len(re.findall(r'\b%s\b' % name, core))
    gb = len(re.findall(r'\b%s\b' % name, below))
    if (gc, gb) != (ncore, nbelow):
        die('`%s` occurs %d times above the boundary and %d below it, where this phase '
            'was written against %d and %d' % (name, gc, gb, ncore, nbelow))
say('the core says `time` FOUR times -- the libc prototype, vim_time\'s own call, and '
    'ui_focus_change\'s TWO, which bypass the wrapper -- and `vim_time` seven: a '
    'prototype, a definition and five call sites.  Below the boundary `time` is the one '
    '`#include <time.h>`, and musl_now_ms, the clock that has already crossed, is 9 '
    'above and 1 below')

# ---- 2. the core's own libc prototype block, computed ------------------------------------
# The block is the run of non-blank lines around `long time(long *tp);`, not a line
# number and not a count this file states: another phase in flight removes two of its
# entries, and a written size would already be stale.
TP = 'long time(long *tp);'
at = [i for i, l in enumerate(lines) if l == TP]
if len(at) != 1:
    die('`%s` is not on a line of its own exactly once above the boundary -- it is '
        'phase 26\'s, and it is what this phase removes' % TP)
a = b = at[0]
while lines[a - 1].strip():
    a -= 1
while lines[b + 1].strip():
    b += 1
if b >= cut:
    die('the prototype block runs past the boundary, so it is not the block phase 26 '
        'wrote')
if any(not re.match(r'^[A-Za-z_].*\);$', l) for l in lines[a:b + 1]):
    die('the block around `%s` is not all prototypes: %s'
        % (TP, ' / '.join(l for l in lines[a:b + 1]
                          if not re.match(r'^[A-Za-z_].*\);$', l))))
if any(l.startswith('static ') for l in lines[a:b + 1]):
    die('a prototype in the block is `static`, which phase 26 forbade: it would give '
        'the core an internal function that is never defined')
say('the core\'s libc prototype block is %d lines (%d-%d), every one a plain '
    'non-`static` prototype: %s.  This phase takes `time` out of it and leaves %d'
    % (b - a + 1, a + 1, b + 1,
       ' '.join(l.split('(')[0].split()[-1].lstrip('*') for l in lines[a:b + 1]),
       b - a))

# ---- 3. the literals ----------------------------------------------------------------------
# Phase 23 was caught out by three string literals holding `NULL`; 26 and 28 applied the
# lesson rather than assuming it.  So does this one.
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
NAMES = re.compile(r'\b(?:vim_time|host_time|time_T|time_t)\b')
bad = [t[a2:b2] for a2, b2 in S if NAMES.search(t[a2:b2])]
if bad:
    die('a literal holds a name this phase substitutes: %s' % ' / '.join(bad))
english = [t[a2:b2] for a2, b2 in S if re.search(r'\btime\b', t[a2:b2])]
say('%d string and character literals, NONE holding `vim_time`, `host_time`, `time_T` '
    'or `time_t` -- and %d holding the English word `time` (%s), which is why no '
    'substitution below is a bare name'
    % (len(S), len(english), ' / '.join(x[:34] for x in english)))


def once(text, old, new, why):
    if text.count(old) != 1:
        die('`%s` is not in the file exactly once (%s)'
            % (old.replace('\n', '\\n')[:70], why))
    return text.replace(old, new, 1)


# ---- 4. STEP ONE: ui_focus_change stops bypassing the wrapper -------------------------------
# TWO READS BEFORE AND TWO READS AFTER.  The condition reads the clock and the body
# reads it again; nothing is hoisted into a local, because that would be a different
# program -- the two reads could always fall either side of a second tick and they still
# can, exactly as often.  The check instruments both binaries and requires the same
# count, with a control that DOES hoist and moves it.
t = once(t, '''    if (in_focus && last_time + 2 < time(nullptr))
    {
        last_time = time(nullptr);
    }
''', '''    if (in_focus && last_time + 2 < vim_time())
    {
        last_time = vim_time();
    }
''', "ui_focus_change's two standalone clock reads, which are the whole of step one")
mid = code(t.split('\n')[:cut])
if len(re.findall(r'\btime\s*\(', mid)) != 2:
    die('`time(` occurs %d times above the boundary after step one, where 2 were '
        'expected -- the prototype and the one call inside the wrapper'
        % len(re.findall(r'\btime\s*\(', mid)))
say('STEP ONE: ui_focus_change\'s two direct `time(nullptr)` are `vim_time()`.  STILL '
    'TWO READS, in the same two statements, in the same order -- and `time(` above the '
    'boundary is now the prototype and ONE call site, the wrapper\'s own')

# ---- 5. STEP TWO: the wrapper becomes the host's ---------------------------------------------
t, n_ren = re.subn(r'\bvim_time\b', 'host_time', t)
if n_ren != 9:
    die('%d `vim_time` were renamed where 9 were counted -- the prototype, the '
        'definition, five call sites and the two step one just made' % n_ren)

t = once(t, 'static time_T host_time(void);\n', '',
         "the core's own forward declaration, in the block of them")
t = once(t, 'static void host_message(const char *msg, int len, int err);\n',
         'static void host_message(const char *msg, int len, int err);\n'
         'static long host_time(void);\n',
         'the core\'s HOST BLOCK, where host_exit, host_message and the nine musl_ '
         'names are declared')
# The definition leaves with one of the two blank lines around it, so no run of two is
# left behind -- which no verification tier can see (CLAUDE.md).
t = once(t, '''
    static time_T
host_time(void)
{
    return time(nullptr);
}
''', '', 'the definition, which is one clock read and nothing else')
# It lands between musl_now_ms and musl_delay: beside the clock that crossed at phase
# 28, and INSIDE the region `zhostonly` reads as the host.
t = once(t, '''    static void
musl_delay(long ms, int interruptible)
''', '''    static long
host_time(void)
{
    return time(nullptr);
}

    static void
musl_delay(long ms, int interruptible)
''', 'the host block, immediately below musl_now_ms -- the clock\'s other half')
say('STEP TWO: `vim_time` is `host_time` at all %d mentions; its declaration moves from '
    'the forward-declaration block to the host block, as `static long host_time(void);` '
    '-- `long` and not `time_T`, because the DEFINITION is below the boundary and the '
    'host cannot name a core typedef once the file is cut; and the definition lands '
    'between musl_now_ms and musl_delay' % n_ren)

# ---- 6. the prototype the core no longer needs, and what replaces it ---------------------------
t = once(t, TP + '\n', '',
         "phase 26's prototype for time(): nothing above the boundary calls it now")
t = once(t, 'static_assert(15 == SIGTERM, "SIGTERM");\n',
         'static_assert(15 == SIGTERM, "SIGTERM");\n'
         'static_assert(_Generic((time_T)0, time_t: 1, default: 0), "time_T is time_t");\n',
         'the twelve constants phase 27 put below the includes, which is the only place '
         'in the file where a core name and a header name are both in scope')
say('`%s` leaves the core -- the block goes %d lines to %d -- and '
    '`static_assert(_Generic((time_T)0, time_t: 1, default: 0), "time_T is time_t");` '
    'joins the twelve below the includes.  THE PROTOTYPE WAS THE GUARANTEE: gcc compared '
    'it with <time.h>\'s and would have said `conflicting types for \'time\'`.  The '
    'assertion says the same thing about the same two types, and the check proves it can '
    'fail' % (TP, b - a + 1, b - a))

# ---- 7. what the file is now ---------------------------------------------------------------------
L = t.split('\n')
CORE_DELTA = -1 + 1 - 6 - 1
BELOW_DELTA = 6 + 1
if len(L) - len(lines) != CORE_DELTA + BELOW_DELTA:
    die('the file moved by %d lines where %d was expected'
        % (len(L) - len(lines), CORE_DELTA + BELOW_DELTA))
ndir = [i for i, l in enumerate(L) if l.lstrip().startswith('#')]
# THE BOUNDARY MOVES UP BY WHAT THE CORE LOST, and by exactly that: the core is the
# lines above the first `#include`, so the directive's index IS the core's line count.
if ndir != list(range(cut + CORE_DELTA, cut + CORE_DELTA + 11)):
    die('the eleven directives are not the eleven contiguous lines at %d: they are at '
        '%s.  The first one IS the boundary, and it moves up by exactly what the core '
        'lost' % (cut + CORE_DELTA + 1, ' '.join(str(i + 1) for i in ndir[:3])))
if any(not INC.match(L[i]) for i in ndir):
    die('a directive is no longer an `#include <...>` of a system header')
ncore = code(L[:ndir[0]])
nbelow = code(L[ndir[0]:])
if re.search(r'\btime\b', ncore):
    die('`time` is still named %d times above the boundary, and the whole product of '
        'this phase is that the core does not name it at all'
        % len(re.findall(r'\btime\b', ncore)))
if len(re.findall(r'\bvim_time\b', t)):
    die('`vim_time` survives somewhere in the file')
if len(re.findall(r'\bhost_time\b', ncore)) != 8:
    die('`host_time` occurs %d times above the boundary where 8 were expected -- the '
        'declaration and seven call sites'
        % len(re.findall(r'\bhost_time\b', ncore)))
if len(re.findall(r'\bhost_time\b', nbelow)) != 1:
    die('`host_time` occurs %d times below the boundary where 1 was expected -- its '
        'definition' % len(re.findall(r'\bhost_time\b', nbelow)))
if len(re.findall(r'\btime\b', nbelow)) != 2:
    die('`time` occurs %d times below the boundary where 2 were expected -- '
        '`#include <time.h>` and host_time\'s call.  `time_t` is not one of them: `_` '
        'is a word character, so `\\btime\\b` does not match inside it'
        % len(re.findall(r'\btime\b', nbelow)))
if len(re.findall(r'\btime_t\b', nbelow)) != 1:
    die('`time_t` occurs %d times below the boundary where 1 was expected -- the '
        'static_assert' % len(re.findall(r'\btime_t\b', nbelow)))
if len(re.findall(r'\btime_T\b', ncore)) != 8:
    die('`time_T` occurs %d times above the boundary where 8 were expected -- the input '
        'had 10 and the two that go are the prototype\'s and the definition\'s'
        % len(re.findall(r'\btime_T\b', ncore)))
if 'typedef long        time_T;' not in ncore:
    die('`typedef long        time_T;` is not in the core.  host_time returns `long`, '
        'so the core\'s clock type being `long` is what makes every call site an '
        'assignment and not a conversion')
if blank_runs(t) != runs_before:
    die('the edit left %d runs of two blank lines where there were %d'
        % (blank_runs(t), runs_before))
say('THE CORE DOES NOT NAME `time` AT ALL -- four mentions to none -- `host_time` is 8 '
    'above the boundary and 1 below, `time_t` is named once in the whole file and it is '
    'the static_assert, and the file is %d lines against %d'
    % (len(L) - 1, len(lines) - 1))

open(path, 'w', errors='surrogateescape').write(t)
PY

# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  wallclock    the input binary did not build with '$cflags' '$ldflags'"; exit 1; }
echo "  wallclock    the input is $state/old, $(stat -c%s "$state/old") bytes, built with SOURCE_DATE_EPOCH=0 beside the source it came from -- a call replaces an inlined one and 5 lines of definition move past 2,000, so the binary WILL move and no tier 1 equality is available: the recording answers, and the instrumented pair answers for the two reads"

# tools/phaserun.sh sweeps next, then runs pipes/zero32-check.sh.
