#!/bin/sh
# Zero phase 27 -- THE MOVE.  The first `#include` becomes the boundary.
# See ZERO-PLAN.md 4c, ZERO-GOAL.md, and .claude/briefs/zero-reorg.md 1, 4, 5, 6 and 7.
#
# Usage: pipes/zero27-edit.sh <work-dir> <state-dir>     (run from the repository root)
#
# ZERO-PLAN.md 4c's design, which the user settled and which this phase performs:
#
#   zero-vim.c  upper part  the core editor.  NO PREPROCESSOR SYNTAX AT ALL.  At its
#                           top, the musl_-prefixed prototypes: its calls to the host.
#               ----------  the first #include IS the boundary, and nothing marks it
#               lower part  the host.  The #includes, then the musl_ definitions,
#                           host_exit, host_message, and main().
#
# Everything stays `static` except `main`.  One translation unit, one gcc invocation,
# no tool changes.  What this phase produces is a POSITION in the file, and the check
# that falls out of that position is the boundary itself, enumerated by the compiler.
#
# WHAT IT DOES, in the order the constraint forces:
#
#   1  THE ELEVEN `#include`s GO DOWN, to just above the host block phases 18 and 20
#      put at the bottom of the file.  Nothing else marks the line.
#   2  THE VARIADIC LAYER GOES WITH THEM.  `va_list` is <stdarg.h>'s and the core
#      cannot declare it, so every function that holds one is on the host's side:
#      vim_snprintf, vim_vsnprintf, vim_vsnprintf_typval and skip_to_arg -- FOUR, not
#      three; skip_to_arg is the positional-argument walker and ZERO-PLAN.md missed it
#      until phase 22 counted.  Their two prototypes go with them, for the same reason.
#   3  AND WHATEVER ONLY THEY USE, COMPUTED TO A FIXPOINT rather than listed.  The
#      brief's cut reported five functions and two objects after ONE round; this edit
#      compiles the cut, moves what gcc calls unused, and compiles again until nothing
#      above the boundary is dead.  MEASURED: FIVE rounds, 15 functions and 18 objects
#      -- the formatter's whole private island, not its first layer.  The stopping
#      rule is `vim_main` and `deathtrap`, the two the HOST calls, which are unused
#      above the cut by construction and must stay there.
#   4  THE DERIVED CONSTANTS GO UP, AND THIS IS THE ONLY MOMENT THEY CAN.  `enum : int
#      { INT_MAX = (int)(~0u >> 1) };` placed AFTER `#include <limits.h>` is
#      `enum : int { 0x7fffffff = ... };`, a syntax error.  So the constants cannot be
#      written before the move and need no renaming after it: they are exactly this
#      phase's, and that is why phase 26 left them and said so.
#
# THE TWELVE CONSTANTS ARE NOT A LIST THIS PROGRAM REMEMBERS, THEY ARE WHAT THE
# COMPILER ASKS FOR.  The edit performs the move, compiles the cut ALONE, and collects
# every `'X' undeclared` and `unknown type name 'X'` it reports.  That set must be
# exactly the twelve below, or the phase stops: a thirteenth name would mean the core
# still takes something from a header and phase 26 did not finish, and a missing one
# would mean this program is declaring something nobody needs.  MEASURED on the input:
# 23 errors naming exactly these twelve.
#
#   derived   INT_MAX 14   INT_MIN 2   LONG_MAX 51  LONG_MIN 1   LLONG_MAX 3
#             LLONG_MIN 1  ULLONG_MAX 10  SIZE_MAX 1
#   asserted  PATH_MAX 12  EXIT_FAILURE 1  SIGHUP 2  SIGTERM 2
#
# `PATH_MAX` IS AN ARRAY BOUND, which is why all twelve are enumerators and not
# `static const int`: a `static const int` cannot appear in an array bound, a case
# label or an enumerator initialiser, and this one does.  MEASURED, 12 mentions above
# the cut, `char NameBuff[PATH_MAX];` and `vim_strncpy(..., PATH_MAX - 1)` among them.
#
# AN ENUMERATOR IS NOT A TYPEDEF, AND THAT IS WHY THE FAMILIAR NAMES CAN STAY.  A
# later `#define INT_MAX 0x7fffffff` governs only textual occurrences AFTER it, so the
# enumerator above the boundary and the macro below are silent together -- which is a
# different position from `size_t`, where a typedef redefinition has to be
# type-identical, and is the whole reason phase 23 renamed that one and this one
# renames none of these.
#
# AND IT IS ALSO WHY THE CROSS-CHECK HAS TO RESTATE THE DERIVATION.  Below the
# includes the name `INT_MAX` IS the macro, so `static_assert(INT_MAX == INT_MAX)`
# would be a tautology about <limits.h> and would say nothing about the core.  What
# the twelve asserts this phase writes into the file compare is the DERIVING
# EXPRESSION against the header:
#
#   static_assert((int)(~0u >> 1) == INT_MAX, "INT_MAX");
#
# and the left-hand side is not typed twice -- it is the enumerator's own initialiser,
# emitted from the same table, and the check reads both out of the output and requires
# them equal text.  That is the same cross-check phase 26 used, in the only shape the
# move leaves available, and unlike phase 26's it lives in the PRODUCT: the core
# declares, the host verifies, and the verification is the ordinary build.
#
# THE FOUR ASSERTED CONSTANTS ARE ASSERTED AND NOT DERIVED, and the file says so by
# writing them as plain numbers with the same assert beside them.  `PATH_MAX`,
# `EXIT_FAILURE`, `SIGHUP` and `SIGTERM` are policy and ABI numbers, not properties of
# the type system: nothing computes 4096 or 15 from anything, so the honest form is a
# number the host checks rather than an expression that pretends.
#
# NOTHING MOVES UP.  In ONE translation unit everything above the cut is visible below
# it, so only the core -> host direction ever needs a declaration.  MEASURED at phase
# 25: the four variadic functions call twenty distinct core functions at forty-one
# sites and read IObuff once, and not one of them costs a declaration.
#
# WHAT THE MOVE DESTROYS, said plainly, because phase 26's check was built on it.
# After this phase a wrong `void *malloc(int n);` above the boundary is no longer
# `error: conflicting types for 'malloc'` -- there is no second declaration to
# conflict with -- and a `static` one is no longer an error at the declaration but a
# LINK failure, `'malloc' used but never defined`.  That is exactly why phase 26 came
# first and wrote sixteen static_asserts against headers that were still above it.
# The check here breaks the `static` trap in its new shape.
set -eu

work=${1:?usage: zero27-edit.sh <work-dir> <state-dir>}
state=${2:?usage: zero27-edit.sh <work-dir> <state-dir>}
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
import collections
import os
import re
import subprocess
import sys

TAG = 'boundary'
path = sys.argv[1]
state = sys.argv[2]
t = open(path, errors='surrogateescape').read()
BASE = t.split('\n')


def die(msg):
    sys.exit('  %-12s %s' % (TAG, msg))


def say(what):
    print('  %-12s %s' % (TAG, what))


def blank_runs(lines):
    return sum(1 for i in range(1, len(lines)) if lines[i] == '' and lines[i - 1] == '')


# ---- the twelve constants -------------------------------------------------------------
# Eight derived and four asserted.  The initialiser text is used TWICE -- as the
# enumerator above the boundary and as the left-hand side of the static_assert below it
# -- and it is written here ONCE, so the derivation and the thing that checks it cannot
# drift apart.  The check reads both back out of the output and requires them equal.
CONST = (
    ('int',                'INT_MAX',      '(int)(~0u >> 1)'),
    ('int',                'INT_MIN',      '-(int)(~0u >> 1) - 1'),
    ('long',               'LONG_MAX',     '(long)(~0ul >> 1)'),
    ('long',               'LONG_MIN',     '-(long)(~0ul >> 1) - 1'),
    ('long long',          'LLONG_MAX',    '(long long)(~0ull >> 1)'),
    ('long long',          'LLONG_MIN',    '-(long long)(~0ull >> 1) - 1'),
    ('unsigned long long', 'ULLONG_MAX',   '~0ull'),
    ('usize',              'SIZE_MAX',     '(usize)-1'),
    (None,                 'PATH_MAX',     '4096'),
    (None,                 'EXIT_FAILURE', '1'),
    (None,                 'SIGHUP',       '1'),
    (None,                 'SIGTERM',      '15'),
)

HOST = 'static volatile sig_atomic_t host_winch_pending'
TYPEDEF = 'typedef typeof(sizeof(0)) usize;'
VPROTO = 'static int vim_vsnprintf('
# The four that hold a `va_list`.  They are named because `va_list` is <stdarg.h>'s and
# the core cannot declare it; EVERYTHING ELSE that moves is computed from them.
VARIADIC = ('vim_snprintf', 'vim_vsnprintf', 'skip_to_arg', 'vim_vsnprintf_typval')
# The other direction of the boundary: the host calls these, so they are unused ABOVE
# the cut by construction and stay there.  They are the stopping rule of the fixpoint.
KEEP = {'vim_main', 'deathtrap'}

# ---- 0. the file this edit was written against ------------------------------------------
# ELEVEN DIRECTIVES, every one an `#include` of a system header, on the first eleven
# lines -- what phase 21 left and what phases 23 and 26 each asserted in turn.  This is
# the LAST phase for which that sentence is true, and making it false is the point.
d = [(i, l) for i, l in enumerate(BASE) if l.startswith('#')]
if len(d) != 11 or [i for i, _ in d] != list(range(11)):
    die('the input does not have exactly eleven preprocessor directives on its first '
        'eleven lines: %d at %s' % (len(d), ' '.join(str(i) for i, _ in d)))
INC = re.compile(r'^#include <([A-Za-z0-9_/.]+)>$')
if any(not INC.match(l) for _, l in d):
    die('a directive is not an `#include <...>` of a system header')
if BASE[11] != '':
    die('the eleventh `#include` is not followed by a blank line, so the block this '
        'edit lifts is not the shape it was written against')
hb = [i for i, l in enumerate(BASE) if l.startswith(HOST)]
if len(hb) != 1:
    die('the host block does not begin exactly once with %r -- found %d.  It is where '
        'the includes are going and there is nowhere else to put them' % (HOST, len(hb)))
if BASE.count(TYPEDEF) != 1:
    die('`%s` is not in the input exactly once -- phase 23 put it below the last '
        '`#include` and the constants go beneath it' % TYPEDEF)
if blank_runs(BASE) != 0:
    die('the input already holds %d runs of two blank lines, and this edit empties '
        'whole paragraphs -- it can only preserve a zero' % blank_runs(BASE))
say('eleven directives, every one an `#include <...>` on the first eleven lines, the '
    'host block beginning exactly once, and not one run of two blank lines: %s'
    % ' '.join('<%s>' % INC.match(l).group(1) for _, l in d))

# ---- 1. the four kinds of thing that can move --------------------------------------------


def fspan(n):
    """A function definition: the `    static T` line through the `}` at column 0."""
    i = [k for k, l in enumerate(BASE) if l.startswith(n + '(')]
    if len(i) != 1:
        die('`%s` is not defined exactly once at column 0 -- found %d' % (n, len(i)))
    s = i[0] - 1
    if not re.match(r'^    static ', BASE[s]):
        die('`%s` is not preceded by its `    static T` line: %r' % (n, BASE[s]))
    e = i[0]
    while BASE[e] != '}':
        e += 1
    if BASE[e + 1] != '':
        die('`%s` is not followed by a blank line' % n)
    return s, e


def ospan(n):
    """A file-scope object: one line."""
    i = [k for k, l in enumerate(BASE) if re.match(r'^static [^(=]*\b%s\b' % n, l)]
    if len(i) != 1:
        die('`%s` is not declared at file scope exactly once -- found %d' % (n, len(i)))
    return i[0], i[0]


def espan(first):
    """An enum block: the `enum` head through the line holding its `};`."""
    e = first
    while '};' not in BASE[e]:
        e += 1
        if e - first > 512 or e >= len(BASE):
            die('the enum block at line %d does not close within 512 lines' % (first + 1))
    return first, e


def enum_names(s, e):
    body = '\n'.join(BASE[s:e + 1])
    body = body[body.index('{') + 1:body.rindex('}')]
    return [m.group(1) for m in
            (re.match(r'\s*([A-Za-z_]\w*)', p) for p in body.split(',')) if m]


# Every enum block above the host block, read once, with its own names counted inside
# its own body.  An enumerator is invisible to every warning gcc has (CLAUDE.md), so a
# block only the moved code names has to be found by counting rather than by compiling
# -- and the counting is done with one word histogram per round, not one regex per
# name, because there are seven hundred blocks and two megabytes of text.
WORD = re.compile(r'\b[A-Za-z_]\w*\b')
ENUMS, i = [], 12
while i < hb[0]:
    if re.match(r'^enum\b', BASE[i]):
        s, e = espan(i)
        names = enum_names(s, e)
        ENUMS.append((s, e, names,
                      collections.Counter(WORD.findall('\n'.join(BASE[s:e + 1])))))
        i = e + 1
    else:
        i += 1
if len(ENUMS) < 400:
    die('only %d enum blocks were found above the host block, where this file is '
        'written almost entirely in them -- the head pattern has stopped matching and '
        'every dead one below would go unnoticed' % len(ENUMS))

ENAME = {s: (names[0] if names else '?') for s, _, names, _ in ENUMS}

P0 = [i for i, l in enumerate(BASE) if l.startswith(VPROTO)]
if len(P0) != 1 or not BASE[P0[0] + 3].strip().endswith(';') \
        or BASE[P0[0] - 1] != '' or BASE[P0[0] + 4] != '':
    die('the two `va_list` prototypes are not the four-line block between blank lines '
        'this edit lifts')
p0 = P0[0]


def build(funcs, objs, enums, consts=True):
    """The whole file, with `funcs`, `objs` and `enums` moved below the includes."""
    drop = set(range(0, 12)) | set(range(p0 - 1, p0 + 4))
    items = []
    for n in funcs:
        s, e = fspan(n)
        drop |= set(range(s, e + 2))
        items.append(('f', s, BASE[s:e + 1]))
    for n in objs:
        s, e = ospan(n)
        drop |= {s}
        items.append(('o', s, BASE[s:e + 1]))
    for s in enums:
        s, e = espan(s)
        drop |= set(range(s, e + 1))
        items.append(('e', s, BASE[s:e + 1]))
    items.sort(key=lambda x: x[1])

    low = BASE[0:11] + ['']
    if consts:
        low += ['static_assert(%s == %s, "%s");' % (v, n, n) for _, n, v in CONST] + ['']
    for k in 'eo':
        got = [b for t_, _, b in items if t_ == k]
        for b in got:
            low += b + ([''] if k == 'e' else [])
        if got and k == 'o':
            low += ['']
    low += BASE[p0:p0 + 4] + ['']
    for t_, _, b in items:
        if t_ == 'f':
            low += b + ['']

    up = []
    if consts:
        for ty, n, v in CONST:
            up += ['enum { %s = %s };' % (n, v)] if ty is None else \
                  ['enum :', '    %s { %s = %s };' % (ty, n, v)]

    o = []
    for i, l in enumerate(BASE):
        if i == hb[0]:
            o += low
        if i in drop:
            continue
        o.append(l)
        if consts and l == TYPEDEF:
            o += [''] + up
    # A paragraph whose every line went leaves two blank lines meeting, and CLAUDE.md
    # allows no run of two -- nor can any verification tier see one.
    r, collapsed = [], 0
    for l in o:
        if l == '' and r and r[-1] == '':
            collapsed += 1
            continue
        r.append(l)
    return r, collapsed, drop


def cut(L):
    o = []
    for l in L:
        if re.match(r'^ *# *include ', l):
            break
        o.append(l)
    while o and o[-1] == '':
        o.pop()
    return '\n'.join(o) + '\n'


# gcc echoes the offending source line, and this file is full of strings like
# "E685: Internal error: %s" -- so an error is recognised by its POSITION in the
# diagnostic and never by the word.  Reading it the other way makes every compile of
# this particular file look like a failure.
ERR = re.compile(r'^[^ ].*:\d+:\d+: error:.*$', re.M)


def compile_cut(L, name):
    p = os.path.join(state, name)
    open(p, 'w', errors='surrogateescape').write(cut(L))
    return subprocess.run(['gcc', '-c', '-O0', '-fno-stack-protector', '-Wall',
                           '-Wextra', '-Wno-unused-parameter', '-o', '/dev/null', p],
                          capture_output=True, text=True).stderr


# ---- 2. the move, and the twelve names the compiler asks for ------------------------------
# THE LIST IS NOT REMEMBERED, IT IS ASKED FOR.  Move the includes and the variadic
# layer, compile the cut ALONE, and collect every name it says is undeclared.  That set
# must be exactly the twelve this phase declares: a thirteenth would mean the core still
# takes something from a header and phase 26 did not finish, and a missing one would
# mean this program declares something nobody needs.
L0, _, _ = build(VARIADIC, [], [], consts=False)
w0 = compile_cut(L0, 'cut0.c')
asked = sorted(set(re.findall(r"'(\w+)' undeclared", w0))
               | set(re.findall(r"unknown type name '(\w+)'", w0)))
want = sorted(n for _, n, _ in CONST)
if asked != want:
    die('the cut asks for %d names and this phase declares %d.  Asked for: %s.  '
        'Declared: %s.  A name in the first list and not the second is something the '
        'core still takes from a header; one in the second and not the first is a '
        'declaration nobody needs'
        % (len(asked), len(want), ' '.join(asked) or '(none)', ' '.join(want)))
core0 = '\n'.join(BASE[11:hb[0]])
counts = {n: len(re.findall(r'\b%s\b' % n, core0)) for _, n, _ in CONST}
if any(c < 1 for c in counts.values()):
    die('a constant this phase declares does not occur above the host block at all: %s'
        % ' '.join(n for n, c in counts.items() if c < 1))
say('the move alone leaves the cut with %d errors naming EXACTLY the twelve constants '
    'this phase declares and nothing else' % len(ERR.findall(w0)))
say('their counts above the host block, re-measured here: %s'
    % '  '.join('%s %d' % (n, counts[n]) for _, n, _ in CONST))

# ---- 3. the fixpoint: whatever only the moved code uses -------------------------------------
funcs, objs, enums, rounds = list(VARIADIC), [], [], []
for _ in range(16):
    L, _c, drop = build(funcs, objs, enums)
    w = compile_cut(L, 'cutr.c')
    if ERR.findall(w):
        die('the cut does not compile once the constants are in place:\n    %s'
            % '\n    '.join(ERR.findall(w)[:4]))
    nf = sorted(set(re.findall(r"'(\w+)' defined but not used \[-Wunused-function\]", w))
                - KEEP)
    nv = sorted(set(re.findall(r"'(\w+)' defined but not used \[-Wunused-variable\]", w))
                - KEEP)
    # The enum blocks, counted on the text the cut actually is: a block none of whose
    # names occurs above the boundary outside its own body belongs below it, exactly as
    # a dead function does, and no warning will ever say so.
    above = collections.Counter(WORD.findall(
        '\n'.join(l for i, l in enumerate(BASE[:hb[0]]) if i not in drop)))
    ne = []
    for s, e, names, own in ENUMS:
        if s in enums or s in drop or not names:
            continue
        if all(above[n] == own[n] for n in names):
            ne.append(s)
    rounds.append((nf, nv, ne))
    if not nf and not nv and not ne:
        break
    funcs += nf
    objs += nv
    enums += ne
else:
    die('the fixpoint did not settle in 16 rounds')
L, collapsed, _ = build(funcs, objs, enums)

# ---- 4. what the file is now -----------------------------------------------------------------
w = compile_cut(L, 'cut.c')
if ERR.findall(w):
    die('the finished cut does not compile:\n    %s'
        % '\n    '.join(ERR.findall(w)[:4]))
boundary = sorted(set(re.findall(r"'(\w+)' used but never defined", w)))
left = sorted(set(re.findall(r"'(\w+)' defined but not used", w)) - KEEP)
if left:
    die('the fixpoint left %s unused above the boundary' % ' '.join(left))
hashes = [i for i, l in enumerate(cut(L).split('\n')) if re.match(r'^ *#', l)]
if hashes:
    die('%d lines above the boundary begin with a `#`, at %s'
        % (len(hashes), ' '.join(str(i + 1) for i in hashes[:5])))
if blank_runs(L) != 0:
    die('the output holds %d runs of two blank lines' % blank_runs(L))
inc_at = [i for i, l in enumerate(L) if l.startswith('#')]
if len(inc_at) != 11 or inc_at != list(range(inc_at[0], inc_at[0] + 11)):
    die('the output does not have exactly eleven directives on eleven consecutive '
        'lines: %d at %s' % (len(inc_at), ' '.join(str(i + 1) for i in inc_at)))

open(os.path.join(state, 'moved'), 'w').write('\n'.join(
    ['func %s' % n for n in funcs] + ['obj %s' % n for n in objs]
    + ['enum %s' % BASE[s].strip() for s in enums]) + '\n')
open(os.path.join(state, 'boundary'), 'w').write('\n'.join(boundary) + '\n')
open(path, 'w', errors='surrogateescape').write('\n'.join(L))

say('the fixpoint settled in %d rounds: %d functions, %d objects and %d enum blocks go '
    'below the boundary, and every one after the four that hold a `va_list` was named '
    'by gcc or counted, never by this program'
    % (len(rounds), len(funcs), len(objs), len(enums)))
for i, (nf, nv, ne) in enumerate(rounds):
    if nf or nv or ne:
        say('  round %d: %s' % (i, ' '.join(
            nf + nv + ['enum{%s}' % ENAME[s] for s in ne])))
say('%d lines -> %d, %d blank line(s) collapsed where an emptied paragraph left two, '
    'the eleven `#include`s now at lines %d-%d, and NOTHING above them begins with a `#`'
    % (len(BASE) - 1, len(L) - 1, collapsed, inc_at[0] + 1, inc_at[-1] + 1))
say('THE CUT IS %d LINES, COMPILES WITH 0 ERRORS AND NOTHING ABOVE IT IS DEAD, and its '
    'whole warning set is the boundary: %d names, every one `used but never defined` -- '
    '%s' % (len(cut(L).split('\n')) - 1, len(boundary), ' '.join(boundary)))
PY

# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  boundary     the input binary did not build with '$cflags' '$ldflags'"; exit 1; }
echo "  boundary     the input is $state/old, $(stat -c%s "$state/old") bytes, built with SOURCE_DATE_EPOCH=0 beside the source it came from.  Moving definitions inside ONE translation unit changes every address below the first of them, so this phase's evidence is a byte-identical RECORDING and an unmoved \`nm -u\`, never a cmp"

# tools/phaserun.sh sweeps next, then runs pipes/zero27-check.sh.
