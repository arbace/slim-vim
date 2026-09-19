#!/bin/sh
# Zero phase 35 -- the core calls nothing but the host.  ZERO-PLAN.md 4c, ZERO-GOAL.md.
#
# Usage: pipes/zero35-edit.sh <work-dir> <state-dir>     (run from the repository root)
#
# THREE LIBC FUNCTIONS ARE LEFT IN THE CORE AND THIS PHASE MOVES ALL THREE.  Everything
# else the core still asks the operating system for went out through a named call in an
# earlier phase -- the terminal, the signals, the window size and the sleep at phase 20,
# the exit at 19, the messages at 21, the clock at 26 and 28 -- and what survived is the
# three the editor uses so constantly that nobody looked at them: `malloc`, `free` and
# `write`.  The user's words, 2026-09-19: "malloc, free and write should be moved to
# host, then I guess there is no functional dependency in core beyond host."
#
#   malloc   its prototype and every call of it -- lalloc(), and since phase 34 the
#            malloc-copy-free that replaced ga_grow_inner's and get_keystroke's realloc
#   free     its prototype and every call -- vim_free(), update_wincolor(), and phase
#            34's two again
#   write    its prototype and mch_write() -- every byte the editor draws
#
# HOW MANY OF EACH IS READ OFF THE TEXT AND NOT WRITTEN HERE.  This phase asserted the
# counts once, was handed a boundary where phase 34 had changed two of them, and refused;
# what it asserts now is a PARTITION -- every mention above the boundary is the
# declaration or a call, and each call is rewritten -- which is the same claim about a
# file this phase has never seen (CLAUDE.md, *Rename a name across the whole file*).
#
# so the core gets three declarations and the host three definitions:
#
#     static void *host_alloc(usize n);        beside host_exit and host_message,
#     static void host_free(void *p);          at the end of the ONE run of
#     static int host_write(const char *s, int len);   core -> host prototypes
#
# THE WRAPPERS ARE FAITHFUL AND NOT IMPROVED, which is the trap this phase could fall
# into without any recording seeing it.  mch_write() is
#
#     vim_ignored = (int)write(1, (char *)s, len);
#
# -- ONE write(2), no loop, and the count assigned to the variable this tree keeps for
# results it means to ignore.  A short write therefore LOSES those bytes today, and
# host_write() must lose them too: a wrapper that looped would be a behaviour change in
# a phase that declares none, and the corpus cannot tell the two apart because nothing
# in it makes a write to fd 1 come up short.  The same rule for the other two:
# host_alloc() returns what malloc() returned, nullptr included, so lalloc()'s
# clear_sb_text()/do_outofmem_msg() failure path is reached exactly as before; and
# host_free() calls free(), so it is null-safe for the same reason free() is.  The core
# does not rely on that -- vim_free() tests `x != nullptr` and update_wincolor() frees
# only the arm it allocated -- but the wrapper inherits it rather than adding a test.
#
# WHY host_write() DROPS THE DESCRIPTOR AND THE OTHER TWO KEEP THEIR SIGNATURE.  The
# core's two neighbours on this boundary already name no fd: phase 20's
# `musl_read_input(char *buf, int len)` reads fd 0 inside the host, and phase 21's
# `host_message(const char *msg, int len, int err)` chooses between fd 2 and fd 1 from a
# FLAG, not from a number the core passes.  A descriptor is the host's idea of where the
# screen is; `host_write(s, len)` is the core's -- "these bytes go to the screen" -- and
# it is the output side of musl_read_input, spelled the same way.  host_alloc() and
# host_free() have no such question: a size and a pointer are all there ever was.
#
# THE INT RETURN IS THE ONE PLACE A CAST MOVES.  `(int)write(...)` in the core becomes
# `(int)write(...)` in the host, so the value mch_write() stores in vim_ignored is the
# same bits; what changes is which side of the boundary the narrowing happens on, and
# it happens where the libc type is visible, which is the point of the whole file split.
#
# WHAT THIS PHASE IS FOR, AND IT IS A PROPERTY OF THE BLOCK AND NOT OF THESE THREE
# NAMES.  Above the first `#include` the core carries a run of ORDINARY (non-`static`)
# declarations -- the libc it calls, declared by hand since the headers went below it at
# phase 27.  This edit does not assume what is in that run: it finds it, requires the
# three lines it owns to be in it, takes exactly those three out, and prints what is
# left.  When the run is EMPTY the core names no libc function at all, and every
# outward call it makes is a `musl_` or a `host_`.  That is the arc's claim, and the
# check states it as a measurement of the output rather than as a sentence written here.
#
# THE INPUT BINARY IS BUILT HERE with SOURCE_DATE_EPOCH=0, and the check records from it.
set -eu

work=${1:?usage: zero35-edit.sh <work-dir> <state-dir>}
state=${2:?usage: zero35-edit.sh <work-dir> <state-dir>}
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

TAG = 'hostcall'
path = sys.argv[1]
state = sys.argv[2]
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
# Phase 27 moved the eleven directives down here, so "eleven on the first eleven lines"
# -- which phases 21 to 26 asserted -- is now ELEVEN CONTIGUOUS LINES AT THE BOUNDARY
# with not one directive above them.  This phase adds declarations and definitions and
# no directive at all, and it must leave that shape exactly where it found it.
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
say('the boundary is line %d, the first of the eleven `#include`s, and there is not a '
    'directive above it' % (boundary + 1))

# ---- 1. the core's block of ordinary declarations, FOUND rather than assumed ---------
# Everything the core declares is `static` except this one run: the libc functions it
# calls, written out by hand since phase 27 put the headers below it.  ZERO-GOAL.md
# phase 27 records why none of them may be `static` -- gcc gives libc's own declaration
# internal linkage to match, warns `'malloc' declared 'static' but never defined`, links
# anyway, and the sweep's rule that the build print NOTHING is what stands between the
# core and that.  The run is located by walking out from the line this phase owns, so
# the arithmetic below is about the block the input really has.
DECL = re.compile(r'^(?!static |typedef |static_assert)[A-Za-z_][\w *]*\**\w+\([^;]*\);$')
seed = [i for i, l in enumerate(L[:boundary]) if l == 'void *malloc(usize n);']
if len(seed) != 1:
    die("the core does not declare `void *malloc(usize n);` exactly once, so this "
        'phase has not been handed the file it was written for')
lo = hi = seed[0]
while lo > 0 and DECL.match(L[lo - 1]):
    lo -= 1
while hi + 1 < boundary and DECL.match(L[hi + 1]):
    hi += 1
block_before = L[lo:hi + 1]
GO = ['void *malloc(usize n);',
      'void free(void *p);',
      'long write(int fd, const void *buf, usize n);']
for line in GO:
    if line not in block_before:
        die('`%s` is not in the core\'s block of ordinary declarations, which is %s'
            % (line, ' / '.join(block_before)))
if L[lo - 1] != '' or L[hi + 1] != '':
    die('the block is not a paragraph of its own -- line %d is %r and line %d is %r'
        % (lo, L[lo - 1], hi + 2, L[hi + 1]))
say('the core\'s block of ordinary declarations is lines %d-%d, %d of them, and every '
    'one is a libc function the core calls: %s'
    % (lo + 1, hi + 1, len(block_before),
       ' '.join(re.sub(r'^.*?\**(\w+)\(.*$', r'\1', l) for l in block_before)))

# ---- 2. the three names, above the boundary and below it -----------------------------
# A PARTITION AND NOT A COUNT, and the difference is the whole of what this section
# learned.  It used to assert `malloc` 2, `free` 3 and `write` 2 -- the counts measured
# once, on one boundary -- and phase 34 then rewrote `realloc` as a malloc, a copy and a
# free at two core sites, which took them to 4 and 5 and made every one of those numbers
# wrong.  The anchors refused, which is what counted anchors are for; but a count is a
# fact about the tree that was measured and a partition is a fact about the tree that
# arrives (CLAUDE.md, *Rename a name across the whole file*).  So: EVERY occurrence of
# each name above the boundary must be a call-shaped token -- the declarator of its own
# prototype, or a call of it -- and there must be at least one of each.  A mention that
# is neither, an address taken or a variable of the name, refuses here rather than
# surviving into a file whose declaration is gone.  How MANY calls there are is read off
# the text and never written down.
core, host = '\n'.join(L[:boundary]), '\n'.join(L[boundary:])
ncalls = {}
for name, nhost, why in (
        ('malloc', 0, 'lalloc(), and whatever else has come to ask for memory'),
        ('free', 1, 'vim_free(), update_wincolor() and the rest; and '
                    'format_overflow_error() below the boundary'),
        ('write', 1, 'mch_write(); and host_message() below the boundary')):
    occ = len(re.findall(r'\b%s\b' % name, core))
    paren = len(re.findall(r'(?<!\w)%s\(' % name, core))
    if occ != paren:
        die('`%s` has %d mentions above the boundary and only %d of them are followed by '
            '`(` -- every one must be the declaration or a call, and this phase will not '
            'rewrite what it cannot classify' % (name, occ, paren))
    if paren < 2:
        die('`%s` is %d call-shaped mentions above the boundary, and this phase needs its '
            'declaration and at least one call -- %s' % (name, paren, why))
    if mentions(host, name) != nhost:
        die('`%s` has %d mentions below the boundary and this phase was written against '
            '%d -- %s' % (name, mentions(host, name), nhost, why))
    ncalls[name] = paren - 1
# `write` LOSES ITS FIRST ARGUMENT, so unlike the other two its rewrite is not a rename
# and the descriptor has to be checked rather than assumed: host_write(s, len) writes to
# the screen, and the host is where fd 1 is named.  Every core call must be to fd 1.
fd1 = len(re.findall(r'(?<!\w)write\(1, ', core))
if fd1 != ncalls['write']:
    die('%d of the core\'s %d write() calls are to fd 1 -- host_write() takes no '
        'descriptor, so a write to anything else is a call this phase cannot move'
        % (fd1, ncalls['write']))
for name in ('host_alloc', 'host_free', 'host_write'):
    if mentions(t, name):
        die('`%s` is already a name in this file' % name)
say('the partition holds: above the boundary `malloc` is its declaration and %d call%s, '
    '`free` its declaration and %d, `write` its declaration and %d -- every one to fd 1 '
    '-- and NOTHING above the boundary mentions any of the three in any other way.  '
    'Below it: 0, 1 and 1, which is where they are going'
    % (ncalls['malloc'], '' if ncalls['malloc'] == 1 else 's', ncalls['free'],
       ncalls['write']))

# ---- 3. the three declarations leave the core's block --------------------------------
# AS ONE REPLACEMENT OF THE WHOLE BLOCK, because of what happens when it empties.  The
# block is a paragraph, a blank line either side of it; take its last line away one at a
# time and what is left is two blank lines in a row, which tools/canon.sh removes and
# this file has none of.  So when nothing is left the block's trailing blank goes with
# it, and the line arithmetic below is COMPUTED from that rather than written out.
block_after = [l for l in block_before if l not in GO]
old_block = '\n'.join(block_before) + '\n'
if block_after:
    swap(old_block, '\n'.join(block_after) + '\n', "the core's block of declarations",
         'the three this phase owns come out of it and the rest stay where they are')
    dropped = len(GO)
else:
    swap(old_block + '\n', '', "the core's block of declarations AND its trailing "
         'blank line',
         'the block is empty now, and a paragraph separator with nothing to separate '
         'is the run of two blank lines this file does not have')
    dropped = len(block_before) + 1

# ---- 4. and three arrive at the end of the core -> host boundary block ----------------
# The boundary is ONE run of prototypes (phase 25), and these three go at its end in the
# order their definitions appear at the bottom of the file.
PROTOS = ['static void *host_alloc(usize n);',
          'static void host_free(void *p);',
          'static int host_write(const char *s, int len);']
swap('static void host_message(const char *msg, int len, int err);\n',
     'static void host_message(const char *msg, int len, int err);\n%s\n'
     % '\n'.join(PROTOS),
     "the last of the core -> host prototypes phase 25 left",
     'the boundary is ONE block, and these three belong at the end of it rather than '
     'wherever a declaration happened to fit')

# ---- 5. every call site, COMPUTED -----------------------------------------------------
# Section 2 established that every mention above the boundary is a call, so rewriting
# them all is a substitution over the core half and a count that has to come out at the
# number already read.  The core half only: the host below calls free() and write() for
# itself and must not be touched.  `(?<!\w)` is what keeps `vim_free(` and `host_free(`
# out of it -- `_` is a word character -- and it is why this can be a substitution at all.
L = t.split('\n')
bnd = [i for i, l in enumerate(L) if re.match(r'^ *# *', l)][0]
core, host = '\n'.join(L[:bnd]), '\n'.join(L[bnd:])
done = {}
core, done['malloc'] = re.subn(r'(?<!\w)malloc\(', 'host_alloc(', core)
core, done['free'] = re.subn(r'(?<!\w)free\(', 'host_free(', core)
# `write` drops the descriptor, and the `(int)` cast goes with it: host_write() returns
# int, having narrowed inside the host where the libc type is visible.  The cast form is
# taken first so the bare form cannot strip the call out from under it.
core, cast = re.subn(r'\(int\)write\(1, ', 'host_write(', core)
core, bare = re.subn(r'(?<!\w)write\(1, ', 'host_write(', core)
done['write'] = cast + bare
for name in ('malloc', 'free', 'write'):
    if done[name] != ncalls[name]:
        die('%d `%s` call sites were rewritten and section 2 counted %d'
            % (done[name], name, ncalls[name]))
    if re.search(r'\b%s\b' % name, core):
        die('`%s` still appears above the boundary after its call sites were rewritten'
            % name)
t = core + '\n' + host
say('%d call site%s rewritten to `host_alloc`, %d to `host_free` and %d to `host_write` '
    '(%d of them shedding an `(int)` cast that the host now does) -- every one COMPUTED '
    'from the text, and no mention of any of the three left above the boundary'
    % (done['malloc'], '' if done['malloc'] == 1 else 's', done['free'], done['write'],
       cast))

# ---- 6. the host defines the three, below the boundary -------------------------------
# Each is the libc call and nothing else.  `host_write` is where the descriptor lives
# now, and the `(int)` cast that mch_write() used to do.
DEFS = '''    static void *
host_alloc(usize n)
{
    return malloc(n);
}

    static void
host_free(void *p)
{
    free(p);
}

    static int
host_write(const char *s, int len)
{
    return (int)write(1, s, (usize)len);
}

'''
swap('    int\nmain(int argc, char **argv)\n{\n',
     DEFS + '    int\nmain(int argc, char **argv)\n{\n',
     "the launcher's head, the last function in the file",
     'the three definitions go immediately above it, below host_exit and host_message '
     'and in the order their prototypes are written')

# ---- 7. what the file is now ----------------------------------------------------------
L = t.split('\n')
boundary = [i for i, l in enumerate(L) if re.match(r'^ *# *', l)][0]
core, host = '\n'.join(L[:boundary]), '\n'.join(L[boundary:])
for name, ncore, nhost in (('malloc', 0, 1), ('free', 0, 2), ('write', 0, 2)):
    if mentions(core, name) != ncore or mentions(host, name) != nhost:
        die('`%s` ends at %d mentions above the boundary and %d below, expected %d and '
            '%d' % (name, mentions(core, name), mentions(host, name), ncore, nhost))
for name, was in (('host_alloc', 'malloc'), ('host_free', 'free'),
                  ('host_write', 'write')):
    want = ncalls[was] + 2
    if mentions(t, name) != want:
        die('`%s` has %d mentions, expected %d -- its prototype, the %d call sites it '
            'took over from `%s` and its definition'
            % (name, mentions(t, name), want, ncalls[was], was))

# THE BLOCK AFTER, and the sentence this phase exists to make true.  Every other edit
# this phase makes is BELOW the block, so the block still starts where it started and is
# read back by index rather than by another search.
have = L[lo:lo + len(block_after)]
if have != block_after:
    die('the ordinary declarations left above the boundary are %s and the input\'s '
        'block minus the three is %s'
        % (' / '.join(have) or 'none', ' / '.join(block_after) or 'none'))
if L[lo - 1] != '' or L[lo + len(block_after)] != '':
    die('what is left of the block is not a paragraph of its own')
# AND NOWHERE ELSE ABOVE THE BOUNDARY, which needs one more test than DECL.  Macro
# expansion left a handful of ordinary STATEMENTS at column 0 -- `win_comp_scroll(wp);`,
# `win_free_lsize(wp);` -- and they match the shape of a declaration exactly.  What tells
# the two apart is the line above: a file-scope declaration follows a blank line or
# another declaration, and a statement follows the statement before it.
stray = [i for i in range(boundary)
         if DECL.match(L[i]) and (L[i - 1] == '' or DECL.match(L[i - 1]))
         and not (lo <= i < lo + len(block_after))]
if stray:
    die('an ordinary declaration is above the boundary and outside the block: %s'
        % ' / '.join('%d:%s' % (i + 1, L[i]) for i in stray[:4]))
open('%s/block-before' % state, 'w').write('\n'.join(block_before) + '\n')
open('%s/block-after' % state, 'w').write(''.join(l + '\n' for l in block_after))
if block_after:
    say('the core\'s block of ordinary declarations is %d lines and was %d: %s remain, '
        'and each is a libc function some LATER phase owns'
        % (len(block_after), len(block_before),
           ' '.join(re.sub(r'^.*?\**(\w+)\(.*$', r'\1', l) for l in block_after)))
else:
    say('THE CORE\'S BLOCK OF ORDINARY DECLARATIONS IS EMPTY: it was %d lines and it is '
        'now none.  Above the first `#include` there is no declaration that is not '
        '`static`, so the core names no libc function at all and every outward call it '
        'makes is a `musl_` or a `host_`' % len(block_before))

# DECLARATION BEFORE USE, COMPUTED.  The prototype must be above every call and the
# definition below every one of them -- the same assertion phase 25 wrote for the two
# names it made direct, and for the same reason: it is what makes the declaration
# load-bearing rather than decorative.
for name, proto in zip(('host_alloc', 'host_free', 'host_write'), PROTOS):
    p = [i for i, l in enumerate(L) if l == proto]
    d = [i for i, l in enumerate(L) if l.startswith(name + '(') and L[i + 1] == '{']
    uses = [i for i, l in enumerate(L)
            if re.search(r'(?<!\w)%s\(' % name, l) and i not in p and i not in d]
    if len(p) != 1 or len(d) != 1 or not uses:
        die('`%s` has %d prototypes, %d definitions and %d call sites'
            % (name, len(p), len(d), len(uses)))
    if not (p[0] < min(uses) and max(uses) < d[0] and d[0] > boundary):
        die('`%s`: prototype at %d, calls at %d..%d, definition at %d, boundary at %d '
            '-- the prototype must be above every call, the definition below every one '
            'and the definition below the boundary'
            % (name, p[0] + 1, min(uses) + 1, max(uses) + 1, d[0] + 1, boundary + 1))
    say('`%s`: prototype line %d, %d call site%s at %s, definition line %d, which is '
        'below the boundary at %d'
        % (name, p[0] + 1, len(uses), '' if len(uses) == 1 else 's',
           ' '.join(str(u + 1) for u in uses), d[0] + 1, boundary + 1))

if len(L) - 1 != lines_before + 21 - dropped:
    die('the file is %d lines and the input was %d -- expected %d more: three '
        'prototypes and three five-line definitions with a blank line after each is 21 '
        'in, and %d out of the core\'s block'
        % (len(L) - 1, lines_before, 21 - dropped, dropped))
if blank_runs(t) != runs_before:
    die('the edit left %d runs of two blank lines where there were %d'
        % (blank_runs(t), runs_before))
d = [i for i, l in enumerate(L) if re.match(r'^ *# *', l)]
if len(d) != 11 or d != list(range(d[0], d[0] + 11)) or d[0] != boundary:
    die('the output does not have the same eleven contiguous `#include` directives -- '
        'this phase adds DECLARATIONS and DEFINITIONS, never a directive')
say('%d -> %d lines, the eleven #includes untouched at line %d, and no run of two '
    'blank lines' % (lines_before, len(L) - 1, boundary + 1))

open(path, 'w', errors='surrogateescape').write(t)
PY

# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  hostcall     the input binary did not build with '$cflags' '$ldflags'"; exit 1; }
echo "  hostcall     the input is $state/old, $(stat -c%s "$state/old") bytes, built with SOURCE_DATE_EPOCH=0 beside the source it came from -- every call of the three changes from a direct libc call to a call into the host and three definitions arrive, so the binary is NOT byte-identical and the evidence is a RECORDING of each, with a control and a probe for every one of the three"

# tools/phaserun.sh sweeps next, then runs pipes/zero35-check.sh.
