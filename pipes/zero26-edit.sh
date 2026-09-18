#!/bin/sh
# Zero phase 26 -- the header types and macros the core can own.
# See ZERO-PLAN.md 4c, ZERO-GOAL.md, and .claude/briefs/zero-reorg.md 1 and 7.
#
# Usage: pipes/zero26-edit.sh <work-dir> <state-dir>     (run from the repository root)
#
# ZERO-PLAN.md 4c's design is that the FIRST `#include` becomes the boundary: the core
# is the prefix above it and has no preprocessor syntax at all.  That is phase 27's
# move.  This phase is the part of it that can be done BEFORE the move, and doing it
# before is the whole point -- see THE ORDERING below.
#
# WHAT THE CORE STILL TAKES FROM A HEADER, and what it gets instead.  Every count is
# `grep -ow` above the host block and every one is re-measured from the input here:
#
#   time_t          6   ->  `typedef long time_T;` and `time_T` at the other five.
#                           The core chooses the width, as phase 23 made it choose
#                           usize's.  What PINS the choice is the `time` prototype
#                           below: `long time(long *)` is accepted against <time.h>
#                           only where `time_t` IS `long`.
#   sig_atomic_t    2   ->  spelled `volatile int`, and the name disappears.  The
#                           THREE in the host block keep it: they are below the
#                           boundary and <signal.h> is theirs.
#   uintptr_t       1   ->  `usize`.  One cast, `(unsigned long long)(uintptr_t)p`.
#   struct timeval  4   ->  a core-owned TAGLESS struct with two `long` fields, and
#                           `musl_gettimeofday(long *sec, long *usec)` in the host
#                           block for the five calls.  This is the ONE item that
#                           changes code; see THE CLOCK.
#   MIN 7 / MAX 16  ->      expanded at 19 lines to the text <sys/param.h> gives,
#                           READ FROM THE HEADER rather than written here.
#   offsetof        9   ->  `__builtin_offsetof`, which ZERO-PLAN.md 4c settled.
#   ten libc calls  ->      plain prototypes: malloc realloc free time getpid kill
#                           write labs abs -- nine, `gettimeofday` being the tenth and
#                           the one that cannot stay, its argument being a struct.
#
# THE DERIVED CONSTANTS ARE NOT THIS PHASE'S.  `enum : int { INT_MAX = ... };` placed
# after `#include <limits.h>` is `enum : int { 0x7fffffff = ... };`, a syntax error, so
# the twelve constants LONG_MAX INT_MAX PATH_MAX ULLONG_MAX LLONG_MAX INT_MIN SIGHUP
# SIGTERM LONG_MIN LLONG_MIN SIZE_MAX EXIT_FAILURE can only be written once the
# includes have moved.  They belong to phase 27 with the move, and they are the only
# header-supplied names this phase leaves in the core.
#
# THE ORDERING -- WHY THIS IS A PHASE OF ITS OWN AND WHY IT COMES FIRST.  Every
# declaration here REPLACES something a header above it still supplies, so the ordinary
# build cross-checks every one of them for free, and after the move there is nothing
# left to check against.  MEASURED, four ways, each a control in the check:
#
#   `int time(int *tp);`            error: conflicting types for 'time'
#   `void *malloc(int n);`          error: conflicting types for 'malloc'
#   `long getpid(void);`            error: conflicting types for 'getpid'
#   `static void *malloc(usize n);` error: static declaration of 'malloc' follows
#                                   non-static declaration
#
# THE LAST IS THE TRAP THE BRIEF NAMES, AND THE ORDERING CHANGES ITS SHAPE.  After the
# move a `static` prototype is a LINK failure -- gcc says `'malloc' used but never
# defined` -- because there is no other declaration to conflict with.  Here it is a
# hard error at the declaration itself, which is cheaper and points at the line.
#
# AND THE POSITIVE FORM IS WHAT THE MOVE DESTROYS.  Fifteen `static_assert`s compare
# every core-owned spelling against the header type it replaces -- `_Generic((time_T)0,
# time_t: ...)`, `_Generic((usize)0, uintptr_t: ...)`, `sizeof(elapsed_T) ==
# sizeof(struct timeval)`, `__builtin_offsetof(T, m) == offsetof(T, m)` at all six
# types -- and every one of them names a header type, so not one can be written once
# the headers are below.  They are a control in the check, not in the product.
#
# THE TAG IS STILL FORBIDDEN, AND THE REASON IN THE BRIEF IS NO LONGER TRUE.  The brief
# says a core-defined `struct timeval` tag is a hard `error: redefinition`.  MEASURED
# here: it is NOT, under the dialect this file compiles in.  C23 permits a struct to be
# redeclared with the same members, and gcc 15 takes it in silence both ways round --
# `-std=c11` and `-std=c17` give `error: redefinition of 'struct timeval'` and `-std=c23`
# gives nothing.  So the tagless struct is mandatory for a better reason than a
# diagnostic: the core must not define a libc TAG at all, and the layout equality has to
# be ASSERTED rather than left to an error C23 has removed.  The check does both --
# the tag control under c11 and under the file's own dialect, and the three
# `static_assert`s on the layout.
#
# THE CLOCK IS THE ONLY THING THAT CHANGES CODE, and the check proves that as an
# equality rather than claiming it.  Everything above is a rename or a macro expansion
# that the preprocessor was already performing, so it cannot generate a different
# instruction; `gettimeofday(&start_tv, nullptr)` becoming
# `musl_gettimeofday(&start_tv.tv_sec, &start_tv.tv_usec)` at five sites can and does.
# MEASURED: with the clock alone reverted, the binary is `cmp`-IDENTICAL to the one
# this phase was handed -- 788,488 bytes -- so the other six items and the nine
# prototypes are tier 1 of CLAUDE.md's verification table, and the clock is the only
# thing a recording has to answer for.  It does: MEASURED, the two recordings are
# BYTE-IDENTICAL, and the recording is NOT blind to the clock -- `musl_gettimeofday`
# writing the two fields the wrong way round moves SEVEN records.
#
# WHERE `musl_gettimeofday` GOES, AND IT IS NOT A FREE CHOICE.  It is defined inside
# the host block, immediately above `musl_delay`, because `tools/zhostonly.py` reads
# the host region as the lines from `host_winch_pending` to the last brace of
# `musl_suspend()` and requires every mention of `struct timeval` to be inside it.  A
# definition below `musl_suspend` would be outside the region and the tool would refuse.
set -eu

work=${1:?usage: zero26-edit.sh <work-dir> <state-dir>}
state=${2:?usage: zero26-edit.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"

# The flags are read out of the boundary's makefile rather than written here a second
# time: zero's compile line is the boundary's (ZERO-GOAL.md rule 8).
cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")
cp "$f" "$state/old.c"
# shellcheck disable=SC2086
( cd "$state" && SOURCE_DATE_EPOCH=0 gcc $cflags $ldflags -o old old.c ) &
pid_old=$!

# MIN and MAX ARE READ FROM THE HEADER, not written here.  Two macro calls with
# distinctive arguments go through the preprocessor and come back as the expansion the
# header actually defines; the edit turns that into its template by replacing the two
# arguments.  If <sys/param.h> ever spelled MIN differently this phase would expand it
# differently, which is the only honest meaning of "the exact text the header gives".
printf '#include <sys/param.h>\nMIN(ZZA,ZZB)\nMAX(ZZA,ZZB)\n' > "$state/minmax-probe.c"
grep ZZA <"$state/minmax-probe.c" >/dev/null
gcc -E -P "$state/minmax-probe.c" | grep ZZA > "$state/minmax.txt"
test "$(wc -l <"$state/minmax.txt")" = 2

python3 - "$f" "$state/minmax.txt" <<'PY'
import re
import sys

TAG = 'headers'
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

# ---- 0. the file this edit was written against --------------------------------------
# ELEVEN DIRECTIVES, every one an `#include` of a system header, on the first eleven
# lines -- ZERO-GOAL.md's charter.  This phase adds no directive and moves none: the
# move is phase 27's, and a phase that quietly did it here would make every
# cross-check below impossible rather than merely wrong.
directives = [(i, l) for i, l in enumerate(lines) if l.startswith('#')]
if len(directives) != 11 or [i for i, _ in directives] != list(range(11)):
    die('the file does not have exactly eleven preprocessor directives on its first '
        'eleven lines: %d directives at lines %s'
        % (len(directives), ' '.join(str(i) for i, _ in directives)))
INC = re.compile(r'^#include <([A-Za-z0-9_/.]+)>$')
if any(not INC.match(l) for _, l in directives):
    die('a directive is not an `#include <...>` of a system header, and no phase may '
        'add one')
headers = [INC.match(l).group(1) for _, l in directives]
for want in ('stdlib.h', 'unistd.h', 'sys/param.h', 'time.h', 'signal.h', 'stdint.h',
             'stddef.h'):
    if want not in headers:
        die('<%s> is not among the eleven includes, and it is one of the headers this '
            'phase replaces: the cross-check it depends on would not happen' % want)
say('eleven directives, every one an `#include <...>` on the first eleven lines, and '
    'the seven headers this phase takes from are all among them: %s'
    % ' '.join('<%s>' % h for h in headers))

# ---- 1. the host block, which is the other side of the boundary ----------------------
# The core is everything above it.  Phase 27 puts the eleven includes here; today the
# line is already exactly where the host block begins, and the counts below are the
# counts that matter -- a `sig_atomic_t` in the host is not this phase's business and a
# `sig_atomic_t` in the core is.
HOST = 'static volatile sig_atomic_t host_winch_pending'
hb = [i for i, l in enumerate(lines) if l.startswith(HOST)]
if len(hb) != 1:
    die('the host block does not begin exactly once with %r -- found %d.  Without it '
        'this phase cannot tell a core mention from a host one' % (HOST, len(hb)))
host_at = hb[0]
core = '\n'.join(lines[11:host_at])
host = '\n'.join(lines[host_at:])

# ---- 2. the inventory, as a partition and not a list ----------------------------------
# What the core still takes from a header, counted here rather than remembered.  Each
# number is checked against what the substitution below actually does, so a count that
# has moved under this phase stops it instead of letting it cut something else.
WANT = (('time_t', 6, 0), ('sig_atomic_t', 2, 3), ('uintptr_t', 1, 0),
        ('size_t', 0, 0), ('MIN', 7, 0), ('MAX', 16, 0), ('offsetof', 9, 0))
for name, ncore, nhost in WANT:
    gc = len(re.findall(r'\b%s\b' % name, core))
    gh = len(re.findall(r'\b%s\b' % name, host))
    if (gc, gh) != (ncore, nhost):
        die('`%s` occurs %d times in the core and %d in the host block, where this '
            'phase was written against %d and %d' % (name, gc, gh, ncore, nhost))
tv_core = len(re.findall(r'struct timeval\b', core))
tv_host = len(re.findall(r'struct timeval\b', host))
if (tv_core, tv_host) != (4, 2):
    die('`struct timeval` occurs %d times in the core and %d in the host block, where '
        'this phase was written against 4 and 2' % (tv_core, tv_host))
say('the core takes eight things from a header: time_t 6, sig_atomic_t 2, uintptr_t 1, '
    'struct timeval 4, MIN 7, MAX 16, offsetof 9 -- and size_t 0, phase 23 having taken '
    'it.  The host block keeps its own sig_atomic_t 3 and struct timeval 2')

# ---- 3. the literals ------------------------------------------------------------------
# Phase 23 was caught out by three string literals holding `NULL`.  The lesson is
# applied rather than assumed: no literal may hold any name this phase substitutes.
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
NAMES = re.compile(r'\b(?:time_t|sig_atomic_t|uintptr_t|MIN|MAX|offsetof|gettimeofday)'
                   r'\b|struct timeval\b')
bad = [t[a:b] for a, b in S if NAMES.search(t[a:b])]
if bad:
    die('a literal holds a name this phase substitutes, and no substitution below may '
        'reach inside a string: %s' % ' / '.join(bad))
say('%d string and character literals, NONE holding any of the eight names or '
    '`gettimeofday` -- so every substitution below is over code' % len(S))

# ---- 4. the nine libc prototypes ------------------------------------------------------
# PLAIN, NEVER `static`.  A `static` prototype gives the core an internal function
# that is never defined; here that is `error: static declaration of 'malloc' follows
# non-static declaration` and after the move it is a link failure.  The check breaks it
# both ways.
#
# Their types are the core's statement of the ABI, and <stdlib.h>, <unistd.h> and
# <time.h> above them are what makes it a statement that can be wrong out loud.
ANCHOR = 'typedef typeof(sizeof(0)) usize;\n'
BLOCK = """
void *malloc(usize n);
void *realloc(void *p, usize n);
void free(void *p);
long time(long *tp);
int getpid(void);
int kill(int pid, int sig);
long write(int fd, const void *buf, usize n);
long labs(long n);
int abs(int n);
"""
if t.count(ANCHOR) != 1:
    die('`%s` is not in the file exactly once -- phase 23 put it directly below the '
        'last `#include` and this phase declares the libc calls beneath it'
        % ANCHOR.strip())
t = t.replace(ANCHOR, ANCHOR + BLOCK, 1)
say('nine plain prototypes below the usize typedef -- malloc realloc free time getpid '
    'kill write labs abs -- and NOT ONE of them `static`.  gettimeofday is the tenth '
    'and is the one that cannot stay: its argument is a struct')

# ---- 5. time_t -> time_T, and the core owns the width ----------------------------------
TD = 'typedef time_t      time_T;'
if t.count(TD) != 1:
    die('`%s` is not in the file exactly once' % TD)
t = t.replace(TD, 'typedef long        time_T;', 1)
t, n_time = re.subn(r'\btime_t\b', 'time_T', t)
if n_time != 5:
    die('%d further `time_t` were rewritten where 5 were counted' % n_time)
say('`typedef time_t time_T;` -> `typedef long time_T;` and %d further `time_t` -> '
    '`time_T`.  `long time(long *)` above is what pins the width against <time.h>'
    % n_time)

# ---- 6. sig_atomic_t -> volatile int, in the core only ----------------------------------
for old, new in (('static volatile sig_atomic_t full_screen ',
                  'static volatile int full_screen '),
                 ('static volatile sig_atomic_t got_int ',
                  'static volatile int got_int ')):
    if t.count(old) != 1:
        die('`%s` is not in the file exactly once' % old.strip())
    t = t.replace(old, new, 1)
say('the core\'s two `volatile sig_atomic_t` objects -- full_screen and got_int -- are '
    'spelled `volatile int`, and the host block\'s three are left alone')

# ---- 7. uintptr_t -> usize --------------------------------------------------------------
UP = '(unsigned long long)(uintptr_t)p'
if t.count(UP) != 1:
    die('`%s` is not in the file exactly once -- it is the one cast that names '
        'uintptr_t' % UP)
t = t.replace(UP, '(unsigned long long)(usize)p', 1)
say('the one `(uintptr_t)` cast, in musl_fmtptr, is `(usize)` -- the same type, and '
    'the check asserts that with _Generic against <stdint.h>')

# ---- 8. struct timeval -> a TAGLESS core struct, and the clock through the host --------
# TAGLESS IS MANDATORY.  A tag would be the core defining a libc name, and C23 would
# not even complain about it (measured; see the header of this file), so the layout
# equality has to be asserted instead -- which the check does, against the header that
# is still above.
TV = 'typedef struct timeval elapsed_T;'
if t.count(TV) != 1:
    die('`%s` is not in the file exactly once' % TV)
t = t.replace(TV, 'typedef struct {\n    long        tv_sec;\n    long        tv_usec;\n'
                  '} elapsed_T;', 1)
for old, new in (('static long elapsed(struct timeval *start_tv);',
                  'static long elapsed(elapsed_T *start_tv);'),
                 ('elapsed(struct timeval *start_tv)\n{',
                  'elapsed(elapsed_T *start_tv)\n{'),
                 ('    struct timeval  now_tv;', '    elapsed_T       now_tv;')):
    if t.count(old) != 1:
        die('`%s` is not in the file exactly once' % old.replace('\n', '\\n'))
    t = t.replace(old, new, 1)

GT = re.compile(r'gettimeofday\(&(\(?[A-Za-z_][\w.]*(?:->[\w.]+)?\)?), nullptr\)')


def gsub(m):
    e = m.group(1)
    if e.startswith('(') and e.endswith(')'):
        e = e[1:-1]
    return 'musl_gettimeofday(&%s.tv_sec, &%s.tv_usec)' % (e, e)


t, n_gt = GT.subn(gsub, t)
if n_gt != 5:
    die('%d `gettimeofday(&X, nullptr)` calls were rewritten where 5 were counted' % n_gt)

PROTO = 'static void musl_delay(long ms, int interruptible);\n'
if t.count(PROTO) != 1:
    die('musl_delay\'s prototype is not in the file exactly once, so the new one has '
        'nowhere it belongs')
t = t.replace(PROTO, 'static void musl_gettimeofday(long *sec, long *usec);\n' + PROTO, 1)
DEF = '    static void\nmusl_delay(long ms, int interruptible)\n'
if t.count(DEF) != 1:
    die('musl_delay\'s definition is not in the file exactly once')
t = t.replace(DEF, '''    static void
musl_gettimeofday(long *sec, long *usec)
{
    struct timeval tv;

    gettimeofday(&tv, nullptr);
    *sec = tv.tv_sec;
    *usec = tv.tv_usec;
}

''' + DEF, 1)
say('`elapsed_T` is the core\'s own TAGLESS `struct { long tv_sec; long tv_usec; }`, '
    'the three other `struct timeval` in the core are it, and the %d '
    '`gettimeofday(&X, nullptr)` calls go through `musl_gettimeofday(long *, long *)` '
    '-- defined in the host block above musl_delay, which is inside the region '
    'tools/zhostonly.py reads' % n_gt)

# ---- 9. offsetof -> __builtin_offsetof --------------------------------------------------
# ZERO-PLAN.md 4c settled this.  The plain-C alternative `(usize)&(((T *)0)->m)` was
# measured to compile, to run, and to static_assert equal to libc's offsetof -- but
# `-Wpedantic` says it is not an integer constant expression, so it could never be an
# enumerator.  None of these nine needs to be one, so it stays a real option and not a
# reason to change: one gcc extension in one construct is cheaper to explain than a
# UB-by-the-letter idiom in nine places.
t, n_off = re.subn(r'\boffsetof\b', '__builtin_offsetof', t)
if n_off != 9:
    die('%d `offsetof` were rewritten where 9 were counted' % n_off)
say('%d `offsetof` -> `__builtin_offsetof`, which is what <stddef.h> expands it to '
    'here.  The check asserts the two are equal at all six types' % n_off)

# ---- 10. MIN and MAX, expanded to the text the header gives -----------------------------
tmpl = {}
for line in open(sys.argv[2]).read().split('\n'):
    line = line.strip()
    if not line:
        continue
    if 'ZZA' not in line or 'ZZB' not in line:
        die('the preprocessed probe line %r does not mention both arguments -- the '
            'expansion could not be turned into a template' % line)
    tmpl['MIN' if '<' in line else 'MAX'] = line
if sorted(tmpl) != ['MAX', 'MIN']:
    die('the preprocessed probe gave %d templates and not one for MIN and one for MAX'
        % len(tmpl))


def expand(text):
    total = {'MIN': 0, 'MAX': 0}
    while True:
        m = re.search(r'\b(MIN|MAX)\(', text)
        if not m:
            break
        i = m.end() - 1
        d, j = 0, i
        while j < len(text):
            if text[j] == '(':
                d += 1
            elif text[j] == ')':
                d -= 1
                if d == 0:
                    break
            j += 1
        else:
            die('an unbalanced `%s(` at line %d'
                % (m.group(1), text.count('\n', 0, m.start()) + 1))
        inner = text[i + 1:j]
        d, k = 0, None
        for x, c in enumerate(inner):
            if c == '(':
                d += 1
            elif c == ')':
                d -= 1
            elif c == ',' and d == 0:
                k = x
                break
        if k is None:
            die('`%s(%s)` at line %d has no top-level comma, so it is not the two-'
                'argument macro this phase expands'
                % (m.group(1), inner, text.count('\n', 0, m.start()) + 1))
        a, b = inner[:k].strip(), inner[k + 1:].strip()
        if '\n' in inner:
            die('a `%s(` at line %d spans a line break, which this file does not do '
                '(CLAUDE.md) and this expansion could not keep'
                % (m.group(1), text.count('\n', 0, m.start()) + 1))
        text = (text[:m.start()]
                + tmpl[m.group(1)].replace('ZZA', a).replace('ZZB', b)
                + text[j + 1:])
        total[m.group(1)] += 1
    return text, total


minmax_lines = len({t.count('\n', 0, m.start()) for m in re.finditer(r'\b(MIN|MAX)\(', t)})
t, n_mm = expand(t)
if (n_mm['MIN'], n_mm['MAX']) != (7, 16):
    die('%d MIN and %d MAX were expanded where 7 and 16 were counted'
        % (n_mm['MIN'], n_mm['MAX']))
say('%d MIN and %d MAX on %d lines expanded to the header\'s own text -- %s and %s, '
    'read back through the preprocessor and not written into this program'
    % (n_mm['MIN'], n_mm['MAX'], minmax_lines, tmpl['MIN'], tmpl['MAX']))

# ---- 11. what the file is now -----------------------------------------------------------
L = t.split('\n')
added = 10 + 3 + 1 + 10
if len(L) != len(lines) + added:
    die('the file is %d lines and the input was %d -- this phase adds exactly %d: 10 '
        'for the prototype block, 3 for the tagless struct, 1 for '
        'musl_gettimeofday\'s prototype and 10 for its definition'
        % (len(L) - 1, len(lines) - 1, added))
newlines = t.split('\n')
host2 = [i for i, l in enumerate(newlines) if l.startswith(HOST)]
if len(host2) != 1:
    die('the host block no longer begins exactly once with %r' % HOST)
ncore = '\n'.join(newlines[11:host2[0]])
nhost = '\n'.join(newlines[host2[0]:])
for name in ('time_t', 'sig_atomic_t', 'uintptr_t', 'size_t', 'MIN', 'MAX', 'offsetof'):
    n = len(re.findall(r'\b%s\b' % name, ncore))
    if n:
        die('`%s` still occurs %d times in the core' % (name, n))
if re.search(r'struct timeval\b', ncore):
    die('`struct timeval` still occurs in the core')
if len(re.findall(r'\bsig_atomic_t\b', nhost)) != 3:
    die('the host block no longer has its three `sig_atomic_t`')
if len(re.findall(r'struct timeval\b', nhost)) != 3:
    die('the host block should have three `struct timeval` -- its two and '
        'musl_gettimeofday\'s -- and has %d'
        % len(re.findall(r'struct timeval\b', nhost)))
if len([l for l in newlines if l.startswith('#')]) != 11:
    die('the file no longer has exactly eleven directives')
if blank_runs(t) != runs_before:
    die('the edit left %d runs of two blank lines where there were %d'
        % (blank_runs(t), runs_before))
say('the core is clean: size_t, time_t, sig_atomic_t, uintptr_t, struct timeval, MIN, '
    'MAX and offsetof are ALL at 0 above the host block, the eleven directives are '
    'where they were, and the only header-supplied names left are the twelve constants '
    'phase 27 takes with the move')

open(path, 'w', errors='surrogateescape').write(t)
PY

# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  headers      the input binary did not build with '$cflags' '$ldflags'"; exit 1; }
echo "  headers      the input is $state/old, $(stat -c%s "$state/old") bytes, built with SOURCE_DATE_EPOCH=0 beside the source it came from -- the clock is the only item that changes code, so the check reverts IT alone and requires THE SAME BYTES back, and the recording answers for the clock"

# tools/phaserun.sh sweeps next, then runs pipes/zero26-check.sh.
