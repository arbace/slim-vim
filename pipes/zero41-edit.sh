#!/bin/sh
# Zero phase 41 -- freeing is free.  ZERO-GOAL.md's charter bullet, "A GARBAGE
# COLLECTOR IS ASSUMED FROM HERE ON".
#
# Usage: pipes/zero41-edit.sh <work-dir> <state-dir>     (run from the repository root)
#
# `host_alloc` BECOMES A BUMP ALLOCATOR AND `host_free` RETURNS WITHOUT DOING ANYTHING.
# Phase 35 moved `malloc` and `free` across the boundary and wrote the two wrappers that
# forwarded to them; this phase changes what is behind those two names and nothing else.
# The charter's words: "No real collector is built: `host_alloc` becomes a bump allocator
# in the host with enough arena for the test suite and `host_free` returns without doing
# anything, which is a change entirely below the boundary and touches no core line."
#
# THE CLAIM IS "FREEING IS NOW FREE" AND NOT "THE CORE STOPPED FREEING".  Every
# `host_free` call the core makes is still there and still made; what it costs is a
# store of a parameter and a return.  Some later phase may delete the calls, and it
# will be able to, which is the point of doing this one first.
#
# WHAT THE CORPUS ASKED FOR, MEASURED AND NOT GUESSED.  The input source was built with
# a counter on host_alloc that totals every request, rounded as the allocator below
# rounds it, and dumped from host_exit() -- which every session reaches.  Over the whole
# of tools/zrecord.sh, 268 sessions in 122 records, the largest single session asked for
# 200,458,672 bytes, and two separate recordings gave that same number.  It is ONE case:
#
#   the heaviest memline case, mem_deep_jumps, 25,000 lines     200,458,672
#   the next three memline cases                    53,134,304 / 52,559,280 / 52,506,976
#   the heaviest of the 102 screen cases                          1,722,512
#   a buffer of 100,000 lines                                    12,862,224
#   a buffer of 300,000 lines           35,157,264   (~112 bytes a line, LINEAR)
#   200,000 characters into ONE line                         20,013,114,624 (QUADRATIC)
#
# THE ARENA COULD NOT HAVE BEEN SIZED BEFORE ZERO PHASE 40, and that is worth saying
# plainly rather than leaving in the manifest.  The heaviest of the 102 screen cases asks
# for 1,722,512 bytes and the heaviest of phase 40's 16 memline cases asks for 115 TIMES
# MORE.  A phase written one boundary earlier would have measured the 102, found 1.7 MB,
# and sized an arena from a corpus that provably cannot reach the text layer at all --
# which is the defect phase 40 exists to have ended, arriving one phase later in a shape
# nobody predicted.  A 64 MiB arena was in fact written here first and the recording
# refused it: `THE RECORDING MOVED, in 1 of 122 records: memline/mem_deep_jumps`, the case
# dying with `host arena exhausted: 67108864 bytes, 67058640 used, request 60263`.
#
# THE LAST ROW IS THE REASON A FIXED ARENA IS A STATEMENT ABOUT THE WORKLOAD AND NOT
# ABOUT THE EDITOR, and it is written here rather than discovered later.  With nothing
# freed, what an arena must hold is not the live data but the TRAFFIC, and this editor's
# traffic is quadratic in the length of a single line being typed: `+normal 200000ax`
# wants twenty gigabytes.  No fixed arena covers that, so the choice is not "how big is
# safe" but "which workloads are covered".
#
# THE SIZE IS 1 GiB AND THE FIRST ARGUMENT FOR IT WAS WRONG, WHICH IS RECORDED HERE
# BECAUSE THE MEASUREMENT THAT KILLED IT IS WORTH MORE THAN THE NUMBER.  This phase first
# chose 64 MiB and justified the ceiling by saying the abort path costs the arena times
# the harness's concurrency -- "64 MiB across 64 threads is 4 GiB on a 62 GiB machine".
# That is FALSE except for a runaway session.  An ordinary session's resident memory is
# its TRAFFIC, which the arena does not change; an untouched arena page costs nothing at
# all.  Measured: the same source at 64 MiB and at 1 GiB produces a byte-identical image,
# 772,872 either way, because .bss is NOBITS.  So the size buys exactly one thing -- how
# far a runaway goes before it dies loudly -- and costs exactly one thing, address space.
# At 1,073,741,824 bytes it is 5.36 times the measured high-water, which is what lets the
# check keep a four-times rule with no weakening to justify.
#
# THE ARENA COSTS NOTHING TO STORE, WHICH IS MEASURED TOO AND IS WHY IT CAN BE THIS
# GENEROUS.  It is a file-scope object with no initialiser, so it is `.bss`, which is
# `NOBITS`: the section header records a size and the file holds no bytes.  Measured on
# this pipeline's own compile line, `.bss` goes from 24,600 bytes to 67,133,528 and the
# IMAGE SHRINKS, 781,064 -> 772,872, because musl's allocator is no longer linked in.
#
# FOUR PARTS, AND THE LAST TWO ARE NOT OPTIONAL.
#
#   1  host_alloc   the arena, the offset, and an abort that NAMES the arena, what is
#                   used and the request that did not fit.  Not nullptr and not silent:
#                   lalloc()'s out-of-memory path would turn a wall into a message and
#                   carry on, and a phase whose declared delta is nothing must not have
#                   a way of quietly doing less.
#   2  host_free    `(void)p;`.
#   3  format_overflow_error()'s `free(argcopy)`     BELOW the boundary, and phase 35
#   4  adjust_types()'s `realloc(*ap_types, ...)`    left both deliberately.
#
# PARTS 3 AND 4 ARE WHAT MAKES THIS PHASE CORRECT RATHER THAN NEARLY CORRECT, and
# neither is in the core.  The formatter's private island -- the four functions phase 27
# moved BELOW the includes because they need `va_list` -- still called libc's `free` and
# libc's `realloc` directly, on pointers that came from `alloc_clear()`, which is to say
# from `host_alloc`.  Phase 35 saw them and left them, naming `free`'s one below-boundary
# mention as "format_overflow_error() below the boundary", and phase 34 saw the other and
# said in as many words that the remaining `realloc` "is the host's and is not this
# phase's".  Both were right while `host_alloc` WAS `malloc`: the two allocators were one
# allocator.  This phase is where they stop being one, and a `free()` or a `realloc()` of
# an arena pointer is undefined behaviour from the line below.  So they move here, and
# the realloc moves by phase 34's own rewrite -- allocate, copy, free -- with phase 34's
# own traps read off this site:
#
#     TRAP 1  `realloc(nullptr, n)` is `malloc(n)`.  Not reachable here: the null case is
#             the OTHER arm of the same `if`, which calls alloc_clear().
#     TRAP 2  on failure `realloc` leaves the old block valid and allocated.  The
#             `return FAIL` is above everything this edit adds, so it still does.
#     TRAP 3  `realloc` does not initialise what it grows, and this site does not expect
#             it to: the loop below fills `[*num_posarg, arg)` itself.  The copy takes
#             the `*num_posarg` entries that were there, the loop fills the rest, and the
#             contents are what they were.
#
# NEITHER IS REACHED BY THE CORPUS AND ONE CANNOT BE REACHED AT ALL, which is why the
# check owns a probe for them instead of a recording.  `format_overflow_error()` is
# called only when `get_unsigned_int`'s `overflow_err` is true, and that argument is
# `tvs != nullptr`, and `vim_vsnprintf_typval` has ONE caller in this file, passing
# nullptr -- so it is phase 9's and phase 17's kind, code no build of zero-vim can run.
# `adjust_types()` needs a positional format spec and no string literal in the file holds
# one, so it takes a runtime format to reach; the check reaches it with one.
#
# WHAT THIS PHASE DOES NOT DO, AND IT IS MEASURED RATHER THAN OVERLOOKED.  `malloc`,
# `free` and `realloc` were the only users of `<stdlib.h>`, and with them gone the
# directive is dead: the check builds the output without it and the binary is
# BYTE-IDENTICAL.  It stays.  ZERO-GOAL.md permits a phase to remove a directive and
# phase 13 is the precedent for declining -- it measured that removing three of them was
# free and wrote "the count stays 18" into its own program.  The eleven stay eleven here
# for the same reason: this phase's subject is the allocator, the removal is free
# whenever somebody asks for it, and a phase that changes two things cannot say which one
# a difference came from.
#
# THE CORE IS NOT TOUCHED, AND THE EDIT ASSERTS IT RATHER THAN CLAIMING IT.  The text
# above the first `#include` must be byte-identical in and out.  The check states the
# same thing the way the project states it -- `cmp` of `make editor.c`'s own cut.
#
# THE INPUT BINARY IS BUILT HERE with SOURCE_DATE_EPOCH=0, and the check records from it.
set -eu

work=${1:?usage: zero41-edit.sh <work-dir> <state-dir>}
state=${2:?usage: zero41-edit.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"

# The flags are read out of the boundary's makefile rather than written here a second
# time: zero's compile line is the boundary's (ZERO-GOAL.md rule 8).
cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")
cp "$f" "$state/old.c"
# shellcheck disable=SC2086
( cd "$state" && SOURCE_DATE_EPOCH=0 gcc $cflags $ldflags -o old old.c ) &
pid_old=$!

python3 - "$f" "$state" <<'PY'
import re
import sys

TAG = 'arena'
path = sys.argv[1]
state = sys.argv[2]
t = open(path, errors='surrogateescape').read()


def die(msg):
    sys.exit('  %-12s %s' % (TAG, msg))


def say(what):
    print('  %-12s %s' % (TAG, what))


def blank_runs(text):
    L = text.split('\n')
    return sum(1 for i in range(1, len(L)) if L[i] == '' and L[i - 1] == '')


def swap(old, new, what, why):
    global t
    if t.count(old) != 1:
        die('%s occurs %d times, expected 1 -- %s' % (what, t.count(old), why))
    t = t.replace(old, new, 1)


L = t.split('\n')
lines_before = len(L) - 1
runs_before = blank_runs(t)

# ---- 0. the boundary, and the file this edit was written against ---------------------
# THE FIRST `#include` IS THE BOUNDARY and nothing else marks it (ZERO-PLAN.md 4c).
# This phase adds no directive and removes none -- see the header on <stdlib.h> -- so
# the eleven contiguous lines phase 27 left must be exactly where they were found.
directives = [i for i, l in enumerate(L) if re.match(r'^ *# *', l)]
if len(directives) != 11:
    die('the file holds %d preprocessor directives and this phase was written against '
        'the eleven `#include`s phase 21 left' % len(directives))
if directives != list(range(directives[0], directives[0] + 11)):
    die('the eleven directives are not eleven consecutive lines')
if any(not re.match(r'^#include <[A-Za-z0-9_/.]+>$', L[i]) for i in directives):
    die('a directive is not an `#include <...>` of a system header, and no phase may '
        'add one')
boundary = directives[0]
core_before = '\n'.join(L[:boundary])
say('the boundary is line %d, the first of the eleven `#include`s, and there is not a '
    'directive above it' % (boundary + 1))

# ---- 1. no literal holds any of the three names -------------------------------------
# Phase 23 was caught out by three string literals holding `NULL`, and the lesson is
# applied rather than assumed (CLAUDE.md, *Rename a name across the whole file*).  Every
# rewrite below is an exact replacement of a unique run of text rather than a
# substitution, so this is belt and braces -- but the PARTITION in section 2 counts
# `\bname\b` over the whole file, and a name in a literal would land in it.
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
                    'place' % ('string' if c == '"' else 'character',
                               text.count('\n', 0, i) + 1))
            out.append((i, j + 1))
            i = j + 1
        else:
            i += 1
    return out


spans = literal_spans(t)
NAMES = ('malloc', 'free', 'realloc')
for name in NAMES:
    bad = [t[a:b] for a, b in spans if re.search(r'\b%s\b' % name, t[a:b])]
    if bad:
        die('a literal holds the name `%s`: %s' % (name, ' / '.join(bad[:3])))
say('%d string and character literals, and not one of them holds `malloc`, `free` or '
    '`realloc`, so every mention the partition below classifies is code' % len(spans))

# ---- 2. THE PARTITION -- every mention of the three, and what class it is in ----------
# A PARTITION AND NOT A COUNT (CLAUDE.md, and phase 35's own section 2, which learned it
# the hard way).  How many mentions there are is read off the text and never written
# down; what is written down is that every one falls in a class this phase rewrites, and
# that a mention in no class REFUSES rather than surviving into a file where `free` means
# something else.  `\b` does not match inside `host_free`, `vim_free` or
# `realloc_cmdbuff` -- `_` is a word character -- so these are the bare libc names.
#
# THE CLASSES ARE THE FOUR PARTS, and each is a run of text that must be in the file
# exactly once.  They are written out here so the classification and the rewrite are the
# same text and cannot drift.
ALLOC_OLD = '''    static void *
host_alloc(usize n)
{
    return malloc(n);
}
'''
FREE_OLD = '''    static void
host_free(void *p)
{
    free(p);
}
'''
OVERFLOW_OLD = '        free(argcopy);\n'
REALLOC_OLD = '''        else
        {
            new_types =  realloc(((char **)*ap_types), (arg * sizeof(const char *))) ;
        }

        if (new_types == nullptr)
        {
            return FAIL;
        }

'''
CLASSES = (
    ("host_alloc()'s body", ALLOC_OLD),
    ("host_free()'s body", FREE_OLD),
    ("format_overflow_error()'s free of argcopy", OVERFLOW_OLD),
    ("adjust_types()'s realloc of *ap_types, with the failure test below it",
     REALLOC_OLD),
)
for what, text in CLASSES:
    if t.count(text) != 1:
        die('%s is in the file %d times and must be there exactly once, so this phase '
            'has not been handed the file it was written for' % (what, t.count(text)))

# Every mention, bucketed into the class whose text holds it.  What is left over is what
# this phase would silently not rewrite, and it is what refuses.
covered = []
for _, text in CLASSES:
    a = t.index(text)
    covered.append((a, a + len(text)))
total = {}
stray = []
for name in NAMES:
    n_here = 0
    for m in re.finditer(r'\b%s\b' % name, t):
        if any(a <= m.start() and m.end() <= b for a, b in covered):
            n_here += 1
        else:
            stray.append((name, t.count('\n', 0, m.start()) + 1))
    total[name] = n_here
if stray:
    die('%d mention%s of one of the three is in none of the four classes this phase '
        'rewrites: %s -- this phase will not leave a libc allocator call behind on a '
        'pointer the arena handed out' % (len(stray), '' if len(stray) == 1 else 's',
                                          ' '.join('%s:%d' % s for s in stray[:6])))
# AND ALL OF THEM ARE BELOW THE BOUNDARY, which is the host-only claim stated as a
# place before it is stated as a `cmp`.
for name in NAMES:
    if re.search(r'\b%s\b' % name, core_before):
        die('`%s` is mentioned above the boundary, and phases 34 and 35 took the core\'s '
            'last one -- this phase changes the host and nothing else' % name)
for new in ('host_arena', 'host_arena_used', 'host_arena_say', 'host_arena_num',
            'host_arena_exhausted', 'HOST_ARENA_BYTES'):
    if re.search(r'\b%s\b' % new, t):
        die('`%s` is already a name in this file' % new)
say('THE PARTITION HOLDS: `malloc` %d mentions, `free` %d and `realloc` %d, every one of '
    'them below the boundary and inside one of the four runs of text this phase '
    'rewrites -- host_alloc\'s body, host_free\'s body, format_overflow_error\'s free of '
    'argcopy and adjust_types\'s realloc of *ap_types.  Nothing else in the file says '
    'any of the three'
    % (total['malloc'], total['free'], total['realloc']))

# ---- 3. host_alloc becomes the arena --------------------------------------------------
# THE ALIGNMENT IS THE TYPE SYSTEM'S AND NOT ARITHMETIC WRITTEN HERE.  The arena is an
# array of `max_align_t`, so its address has the strictest alignment any object in this
# translation unit can require, and the offset is rounded to `alignof(max_align_t)` --
# which is that requirement spelled as itself.  Both names come from <stddef.h>, which is
# one of the eleven and is ABOVE this code: everything in the launcher region is below
# the boundary, which is the whole reason the host may name a header type at all.
#
# ROUNDED TO THE ALIGNMENT AND NOT TO `sizeof(max_align_t)`, and the difference is
# measured: sizeof is 32 here and alignof is 16, so allocating whole elements would waste
# half of every small request -- 19,268,544 bytes against 12,862,224 for the same
# 100,000-line buffer.  The array's element type is what provides the alignment; the
# index is in bytes.
#
# THE TWO TESTS ARE ONE `if` AND BOTH ARE NEEDED.  `want < n` is the rounding overflowing,
# which is the only way `want` can be smaller than what was asked for; `want > sizeof -
# used` is the arena being full, written that way round because `used` is never above
# `sizeof` and the subtraction therefore cannot wrap.
#
# THE MESSAGE IS BUILT BY HAND AND NOT BY vim_snprintf().  The editor's own formatter is
# above the boundary and visible from here, and calling it would be a call into
# alloc_clear() from the failure path of the allocator.  Two helpers and a `char[160]`
# instead; the longest message this can produce is 92 characters.
ALLOC_NEW = '''enum { HOST_ARENA_BYTES = 1024 * 1024 * 1024 };

static max_align_t host_arena[HOST_ARENA_BYTES / sizeof(max_align_t)];
static usize host_arena_used;

    static int
host_arena_say(char *b, int at, const char *s)
{
    usize       n = musl_strlen(s);

    musl_memcpy(b + at, s, n);
    return at + (int)n;
}

    static int
host_arena_num(char *b, int at, usize v)
{
    char        d[24];
    int         i = 24;

    if (v == 0)
    {
        d[--i] = '0';
    }
    while (v > 0)
    {
        d[--i] = (char)('0' + (int)(v % 10));
        v /= 10;
    }
    while (i < 24)
    {
        b[at++] = d[i++];
    }
    return at;
}

    static void
host_arena_exhausted(usize n)
{
    char        m[160];
    int         at = 0;

    at = host_arena_say(m, at, "zero-vim: host arena exhausted: ");
    at = host_arena_num(m, at, sizeof(host_arena));
    at = host_arena_say(m, at, " bytes, ");
    at = host_arena_num(m, at, host_arena_used);
    at = host_arena_say(m, at, " used, request ");
    at = host_arena_num(m, at, n);
    at = host_arena_say(m, at, "\\n");
    host_message(m, at, TRUE);
    host_exit(1);
}

    static void *
host_alloc(usize n)
{
    usize       want = (n + (alignof(max_align_t) - 1)) & ~(usize)(alignof(max_align_t) - 1);
    char        *p;

    if (want < n || want > sizeof(host_arena) - host_arena_used)
    {
        host_arena_exhausted(n);
    }
    p = (char *)host_arena + host_arena_used;
    host_arena_used += want;
    return p;
}
'''
swap(ALLOC_OLD, ALLOC_NEW, "host_alloc()'s definition",
     'the arena, its offset, the two message helpers and the abort go where the one '
     'call of malloc() was, so the allocator and its data stay one paragraph of the '
     'launcher region')

# ---- 4. host_free returns ---------------------------------------------------------------
FREE_NEW = '''    static void
host_free(void *p)
{
    (void)p;
}
'''
swap(FREE_OLD, FREE_NEW, "host_free()'s definition",
     'this is the whole of "freeing is now free": the parameter is named so the '
     'signature does not move and discarded so the build is silent')

# ---- 5. the formatter island's free ------------------------------------------------------
swap(OVERFLOW_OLD, '        host_free(argcopy);\n',
     "format_overflow_error()'s free of argcopy",
     'argcopy came from alloc_clear(), which is host_alloc(), and from the line above '
     'this one libc\'s free() of that pointer is undefined.  It is the same rename '
     'phase 35 made at every core site, made at the one site below the boundary')

# ---- 6. the formatter island's realloc ---------------------------------------------------
REALLOC_NEW = '''        else
        {
            new_types = (const char **)host_alloc(arg * sizeof(const char *));
        }

        if (new_types == nullptr)
        {
            return FAIL;
        }

        if (*ap_types != nullptr)
        {
            musl_memcpy((char **)new_types, *ap_types, (usize)*num_posarg * sizeof(const char *));
            host_free((char **)*ap_types);
        }

'''
swap(REALLOC_OLD, REALLOC_NEW, "adjust_types()'s realloc of *ap_types",
     'phase 34\'s rewrite at the one site phase 34 left: allocate, copy what was there, '
     'free the old block.  The old size is `*num_posarg` entries, which the function '
     'already has, and the guard is the same `*ap_types != nullptr` the arm above tests')

# ---- 7. what the file is now --------------------------------------------------------------
L = t.split('\n')
d = [i for i, l in enumerate(L) if re.match(r'^ *# *', l)]
if len(d) != 11 or d != list(range(d[0], d[0] + 11)) or d[0] != boundary:
    die('the output does not have the same eleven contiguous `#include` directives at '
        'the same line -- this phase adds no directive, removes none and moves none')
for name in NAMES:
    n = len(re.findall(r'\b%s\b' % name, t))
    if n != 0:
        die('`%s` still has %d mentions after every class was rewritten' % (name, n))

# THE CORE IS BYTE-IDENTICAL, which is this phase's central claim and is asserted here
# before the check states it as `make editor.c`'s own `cmp`.  Not "no core line changed"
# counted somehow -- the same bytes.
core_after = '\n'.join(L[:d[0]])
if core_after != core_before:
    die('the text above the boundary is not what it was: this phase is below it '
        'entirely, and a difference there is a bug in one of the four replacements')
say('`malloc`, `free` and `realloc` are 0 mentions in the whole file, and the %d lines '
    'above the boundary are BYTE-IDENTICAL to the input\'s -- the eleven #includes are '
    'untouched at line %d' % (d[0], d[0] + 1))

# The arithmetic, computed rather than written: the four replacements' own line counts.
grew = sum(len(new.split('\n')) - len(old.split('\n')) for old, new in
           ((ALLOC_OLD, ALLOC_NEW), (FREE_OLD, FREE_NEW),
            (OVERFLOW_OLD, '        host_free(argcopy);\n'),
            (REALLOC_OLD, REALLOC_NEW)))
if len(L) - 1 != lines_before + grew:
    die('the file is %d lines and the input was %d -- the four replacements are %d lines '
        'more between them' % (len(L) - 1, lines_before, grew))
if blank_runs(t) != runs_before:
    die('the edit left %d runs of two blank lines where there were %d'
        % (blank_runs(t), runs_before))
say('%d -> %d lines, %d more, which is exactly what the four replacements are worth; no '
    'run of two blank lines' % (lines_before, len(L) - 1, grew))

open('%s/arena-bytes' % state, 'w').write('%d\n' % (1024 * 1024 * 1024))
open(path, 'w', errors='surrogateescape').write(t)
PY

# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  arena        the input binary did not build with '$cflags' '$ldflags'"; exit 1; }
echo "  arena        the input is $state/old, $(stat -c%s "$state/old") bytes, built with SOURCE_DATE_EPOCH=0 beside the source it came from -- host_alloc stops calling malloc and host_free stops calling free, so the binary is NOT byte-identical and the evidence is a RECORDING, an instrument that measures the arena the corpus really asks for, and controls on the guard, on the bump and on the two rewrites below the boundary the corpus cannot reach"

# tools/phaserun.sh sweeps next, then runs pipes/zero41-check.sh.
