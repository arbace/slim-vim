#!/bin/sh
# Zero phase 36 -- the core's libc prototype block empties.  ZERO-PLAN.md 4c, ZERO-GOAL.md.
#
# Usage: pipes/zero36-edit.sh <work-dir> <state-dir>     (run from the repository root)
#
# TWO LINES ARE LEFT IN THE CORE'S BLOCK OF ORDINARY DECLARATIONS AND THIS PHASE TAKES
# BOTH.  Phase 35 took `malloc`, `free` and `write`, the three the editor uses so
# constantly that nobody had looked at them, and wrote its own programs so that the phase
# which empties the block would need no further edit to the machinery:
#
#     int getpid(void);
#     int kill(int pid, int sig);
#
# THEY ARE REACHED TWO DIFFERENT WAYS AND ONLY ONE OF THEM NEEDS A HOST CALL.
#
#   getpid   IS AVOIDABLE OUTRIGHT, not moved.  `mch_get_pid()` is `return (long)getpid();`
#            and has exactly ONE caller, `long_to_char(mch_get_pid(), b0p->b0_pid)` in
#            ml_open().  `b0_pid` is the process id written into block zero of a swap
#            file, and it has exactly TWO mentions in the whole file -- its own
#            declaration and that write.  IT IS WRITE-ONLY: nothing in any build of
#            zero-vim reads it back, because the swap file it belonged to is a disk
#            format this editor has not had since the filesystem phases took every way
#            to name a file.  So the write goes, mch_get_pid() goes with it, and `getpid`
#            leaves the core without anybody calling a host.  Zero phase 20 saw this
#            coming and said so -- "`b0_pid` is written and never read, so one line frees
#            it whenever block zero is somebody's phase".  This is that phase.
#   kill     NEEDS A HOST CALL.  Its one core site is in vim_handle_signal():
#            `kill(getpid(), got_signal);`, re-raising a deadly signal that arrived while
#            the editor was not reading.  It becomes `host_raise(got_signal);`, and the
#            host defines
#
#                static void host_raise(int sig);
#
#            beside host_exit, host_message, host_time, host_alloc, host_free and
#            host_write.  IT TAKES NO PID, and that is the whole shape of it: a core that
#            can no longer ask for its own process id must not be handed one.  What the
#            core says is "raise this signal on me"; WHICH process that is, is the host's
#            idea, exactly as fd 1 is the host's idea of where the screen is
#            (host_write, phase 35) and fd 0 the host's idea of where the keyboard is
#            (musl_read_input, phase 20).
#
# THE DEFINITION GOES INSIDE THE HOST BLOCK AND NOT BELOW IT, which is phase 26's lesson
# about musl_gettimeofday and phase 28's about musl_now_ms.  `zhostonly` reads the
# host region as the lines from `host_winch_pending` to musl_suspend's last brace, and
# host_raise's body says `kill` and `getpid`; a definition below musl_suspend would put
# two host words outside the region and the tool would refuse.  So it is written
# immediately above musl_suspend, which is the last function of that region.
#
# THE NAME PASSES `zhostonly`'s PATTERN FOR THE REASON `musl_gettimeofday` DOES.
# `raise` is in that tool's vocabulary and `\braise\b` cannot match inside `host_raise`,
# because `_` is a word character -- the same trick that lets `musl_gettimeofday` sit in
# the host block while the bare `gettimeofday` is a word the core may not say.  And
# host_raise's body calls `kill(getpid(), sig)` rather than libc's `raise()`: `raise` has
# not been an undefined symbol of this file since phase 20, and a wrapper that reached
# for it would ADD a libc symbol in a phase whose whole subject is the core's last two.
#
# WHAT THIS PHASE IS FOR.  When the block is empty the core names no libc function at
# all.  The edit does not assert that -- it finds the block, takes the two lines it owns
# out of it, and prints what is left, exactly as phase 35's does; the check states the
# claim as a measurement of the OUTPUT, and computes it from `make editor.c`'s cut rather
# than from the block, because those are two different assertions and only the first is
# the claim.  A bare declaration is invisible to the cut -- gcc warns `used but never
# defined` for a `static` function and says nothing about an `extern` one -- so what the
# check measures is `nm -u` of an object of the CUT ALONE, which is the set of names the
# core needs from outside itself.
#
# THE FOLD THAT IS NOT THERE, SURVEYED AND NOT TAKEN.  Phase 17 removed deathtrap()'s
# `entered >= 3` ladder as code no build of zero-vim could reach, which leaves `entered`
# able to reach 2 and no further, and the question was put whether that makes anything
# around the `if (entered == 2)` arm foldable.  Measured, it does not: `entered` has
# exactly three reachable values and EVERY ONE OF THEM IS READ.  0 is read by the guard
# `if (entered == 0 && ...)`, which is what distinguishes the first entry from a nested
# one; 1 and 2 are told apart TWICE -- by `if (entered == 2)`, the double-signal arm
# which calls getout(1) and never returns, and by `v_dying = entered;`, whose value
# reaches getout()'s two `if (v_dying <= 1)` tests and selects the buffer cleanup there.
# So the counter is genuinely three-valued, no two of its states are interchangeable, and
# there is no fold to take.  This edit therefore leaves deathtrap() alone, and the check
# asserts that as a byte comparison of the function in and out rather than leaving it to
# be believed.
#
# THE INPUT BINARY IS BUILT HERE with SOURCE_DATE_EPOCH=0, and the check records from it.
set -eu

work=${1:?usage: zero36-edit.sh <work-dir> <state-dir>}
state=${2:?usage: zero36-edit.sh <work-dir> <state-dir>}
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

TAG = 'noclib'
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


def defn(lines, name):
    """The half-open line range of a definition, in this tree's one shape: the name at
    column 0 with `(` after it, `{` at column 0 on the next line, closed by `}` at
    column 0.  The same shape zhostonly reads."""
    heads = [i for i, l in enumerate(lines)
             if re.match(r'^%s\s*\(' % name, l) and i + 1 < len(lines)
             and lines[i + 1] == '{']
    if len(heads) != 1:
        die('`%s` is defined %d times at column 0, and this phase needs exactly one'
            % (name, len(heads)))
    end = heads[0]
    while end < len(lines) and lines[end] != '}':
        end += 1
    if end >= len(lines):
        die('`%s` does not close at column 0' % name)
    # The return type sits on the line above, indented: `    static long`.
    if not re.match(r'^    [\w *]+$', lines[heads[0] - 1]):
        die('the line above `%s`\'s head is %r and every definition in this tree carries '
            'its return type there, indented' % (name, lines[heads[0] - 1]))
    return heads[0] - 1, end + 1


L = t.split('\n')
lines_before = len(L) - 1
runs_before = blank_runs(t)

# ---- 0. the boundary, and the file this edit was written against ---------------------
# THE FIRST `#include` IS THE BOUNDARY and nothing else marks it (ZERO-PLAN.md 4c).
# This phase adds one declaration and one definition and no directive at all, and it
# must leave that shape exactly where it found it.
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
# calls, written out by hand since phase 27 put the headers below it.  It is located by
# walking out from the line this phase owns, so the arithmetic below is about the block
# the input really has -- phase 35's shape, and the reason it has that shape is that this
# phase is the one that empties it.
DECL = re.compile(r'^(?!static |typedef |static_assert)[A-Za-z_][\w *]*\**\w+\([^;]*\);$')
GO = ['int getpid(void);', 'int kill(int pid, int sig);']
seed = [i for i, l in enumerate(L[:boundary]) if l == GO[0]]
if len(seed) != 1:
    die("the core does not declare `%s` exactly once, so this phase has not been handed "
        'the file it was written for' % GO[0])
lo = hi = seed[0]
while lo > 0 and DECL.match(L[lo - 1]):
    lo -= 1
while hi + 1 < boundary and DECL.match(L[hi + 1]):
    hi += 1
block_before = L[lo:hi + 1]
for line in GO:
    if line not in block_before:
        die('`%s` is not in the core\'s block of ordinary declarations, which is %s'
            % (line, ' / '.join(block_before)))
if L[lo - 1] != '' or L[hi + 1] != '':
    die('the block is not a paragraph of its own -- line %d is %r and line %d is %r'
        % (lo, L[lo - 1], hi + 2, L[hi + 1]))
block_after = [l for l in block_before if l not in GO]
say('the core\'s block of ordinary declarations is lines %d-%d, %d of them: %s'
    % (lo + 1, hi + 1, len(block_before),
       ' '.join(re.sub(r'^.*?\**(\w+)\(.*$', r'\1', l) for l in block_before)))

# ---- 2. the two names above the boundary, AS A PARTITION AND NOT A COUNT -------------
# Every mention of each name above the boundary is put into one of the classes this
# phase's rule serves, and a leftover refuses (CLAUDE.md, *Rename a name across the
# whole file*).  A count measured once is a fact about the tree that was measured; a
# partition is a fact about the tree that arrives, and phase 34 cost phase 35 a re-run
# for exactly that difference.  The classes:
#
#   getpid   its own declaration; the call inside mch_get_pid(), which goes with the
#            function; and the call on the re-raise line, which is rewritten.
#   kill     its own declaration; and the call on the re-raise line.
#
# Nothing else above the boundary may say either word.
core, host = '\n'.join(L[:boundary]), '\n'.join(L[boundary:])
gp_lo, gp_hi = defn(L, 'mch_get_pid')
if gp_hi > boundary:
    die('mch_get_pid() is defined below the boundary, and this phase is about what the '
        'CORE says')
RERAISE = re.compile(r'^(\s*)kill\(getpid\(\), (\w+)\);$')
raise_lines = [i for i in range(boundary) if RERAISE.match(L[i])]
if len(raise_lines) != 1:
    die('`kill(getpid(), <name>);` is %d lines above the boundary and this phase needs '
        'exactly one, the deferred deadly signal vim_handle_signal() re-raises'
        % len(raise_lines))
rl = raise_lines[0]
indent, deferred = RERAISE.match(L[rl]).groups()
classes = {'getpid': {'declaration': [lo + block_before.index(GO[0])],
                      'mch_get_pid()': list(range(gp_lo, gp_hi)),
                      'the re-raise': [rl]},
           'kill': {'declaration': [lo + block_before.index(GO[1])],
                    'the re-raise': [rl]}}
for name, cls in classes.items():
    seen = [i for i in range(boundary) if re.search(r'\b%s\b' % name, L[i])]
    owned = {i for ls in cls.values() for i in ls}
    stray = [i for i in seen if i not in owned]
    if stray:
        die('`%s` is said above the boundary at %s, which is in none of the classes this '
            'phase rewrites (%s) -- and this phase will not delete a declaration whose '
            'every use it cannot account for'
            % (name, ' '.join('%d:%s' % (i + 1, L[i].strip()) for i in stray[:4]),
               ', '.join(cls)))
    for what, ls in cls.items():
        if not any(re.search(r'\b%s\b' % name, L[i]) for i in ls):
            die('the class `%s` of `%s` holds no mention of it' % (what, name))
    say('`%s` above the boundary: %d mention%s, and every one falls in a class this '
        'phase rewrites -- %s'
        % (name, len(seen), '' if len(seen) == 1 else 's',
           ', '.join('%s at %s' % (what, ' '.join(str(i + 1) for i in ls
                                                  if re.search(r'\b%s\b' % name, L[i])))
                     for what, ls in cls.items())))
for name, nhost in (('getpid', 0), ('kill', 1)):
    if mentions(host, name) != nhost:
        die('`%s` has %d mentions below the boundary and this phase was written against '
            '%d -- musl_suspend() stops the process group with `kill(0, SIGTSTP)` and '
            'nothing below the boundary asks for a pid'
            % (name, mentions(host, name), nhost))
if mentions(t, 'host_raise'):
    die('`host_raise` is already a name in this file')

# ---- 3. getpid is AVOIDED: the write of b0_pid, and the function that fed it ---------
# The entry point is the write.  mch_get_pid() has to go in the EDIT and not be left to
# the sweep, because the declaration of `getpid` goes with it and a body calling an
# undeclared function is not a file any sweep can compile.  Its PROTOTYPE and the FIELD
# are the sweep's: tools/deadprotos.py and tools/deadfields.py find both, and this phase
# asserts afterwards that they did rather than deleting them by hand.
proto_gp = [i for i in range(len(L)) if re.match(r'^static [\w *]+mch_get_pid\(.*\);$', L[i])]
callers = [i for i in range(len(L))
           if re.search(r'(?<!\w)mch_get_pid\(', L[i]) and not gp_lo <= i < gp_hi
           and i not in proto_gp]
if len(proto_gp) != 1 or len(callers) != 1:
    die('mch_get_pid() has %d forward declarations and %d call sites outside its own '
        'definition, and this phase needs one of each -- the prototype tools/deadprotos.py '
        'takes, and ml_open()\'s write of b0_pid' % (len(proto_gp), len(callers)))
WRITE = re.compile(r'^\s*long_to_char\(mch_get_pid\(\), (\w+)->b0_pid\);$')
if not WRITE.match(L[callers[0]]):
    die('mch_get_pid()\'s one call site is %r, and this phase was written against '
        'ml_open()\'s `long_to_char(mch_get_pid(), b0p->b0_pid);`' % L[callers[0]])
b0 = [i for i, l in enumerate(L) if re.search(r'\bb0_pid\b', l)]
field = [i for i in b0 if re.match(r'^\s*char_u\s+b0_pid\[\d+\];$', L[i])]
if len(b0) != 2 or len(field) != 1 or b0 != sorted(field + [callers[0]]):
    die('`b0_pid` has %d mentions and this phase needs exactly two, its own declaration '
        'and the one write: %s'
        % (len(b0), ' '.join('%d:%s' % (i + 1, L[i].strip()) for i in b0)))
say('`b0_pid` is WRITE-ONLY: %d mentions in the whole file, its declaration at line %d '
    'and ml_open()\'s write at line %d, and not one read.  So the write is the entry '
    'point, mch_get_pid() (lines %d-%d) is its only feeder, and `getpid` leaves the core '
    'without a host call'
    % (len(b0), field[0] + 1, callers[0] + 1, gp_lo + 1, gp_hi))
swap(L[callers[0]] + '\n', '', "ml_open()'s write of b0_pid",
     'it is the only mention of the field that is not its declaration, and the only '
     'caller of mch_get_pid()')
swap('\n'.join(L[gp_lo:gp_hi]) + '\n\n', '', 'mch_get_pid()\'s definition',
     'its one caller has just gone, and its body is the only other place the core says '
     '`getpid`')

# ---- 4. kill is MOVED: the re-raise becomes a call into the host ----------------------
swap('%skill(getpid(), %s);\n' % (indent, deferred),
     '%shost_raise(%s);\n' % (indent, deferred),
     "vim_handle_signal()'s re-raise of a deferred deadly signal",
     'the core asks the host to raise the signal on this process; WHICH process that is '
     'is the host\'s idea, exactly as fd 1 is under host_write')

# ---- 5. the two declarations leave the core's block -----------------------------------
# AS ONE REPLACEMENT OF THE WHOLE BLOCK, because of what happens when it empties.  The
# block is a paragraph, a blank line either side of it; take its last line away and what
# is left is two blank lines in a row, which tools/canon.sh removes and this file has
# none of.  So when nothing is left the block's trailing blank goes with it, and the line
# arithmetic below is COMPUTED from that rather than written out.  Phase 35 wrote this
# arm and could not exercise it; this phase is the one that does.
old_block = '\n'.join(block_before) + '\n'
if block_after:
    swap(old_block, '\n'.join(block_after) + '\n', "the core's block of declarations",
         'the two this phase owns come out of it and the rest stay where they are')
    dropped = len(GO)
else:
    swap(old_block + '\n', '', "the core's block of declarations AND its trailing "
         'blank line',
         'the block is empty now, and a paragraph separator with nothing to separate '
         'is the run of two blank lines this file does not have')
    dropped = len(block_before) + 1

# ---- 6. one prototype at the end of the core -> host block ----------------------------
# The boundary is ONE run of prototypes (phase 25), and this one goes at its end, where
# phase 32 put host_time and phase 35 its three.
PROTO = 'static void host_raise(int sig);'
swap('static long host_time(void);\n', 'static long host_time(void);\n%s\n' % PROTO,
     'the last of the core -> host prototypes',
     'the boundary is ONE block, and this belongs at the end of it rather than wherever '
     'a declaration happened to fit')

# ---- 7. and the host defines it, INSIDE the host block --------------------------------
# Not below it.  `zhostonly` reads the host region as the lines from
# host_winch_pending to musl_suspend's last brace, and this body says `kill` and
# `getpid`; a definition below musl_suspend would put two host words outside the region
# and the tool would refuse.  Phase 26 learned that for musl_gettimeofday and phase 28
# for musl_now_ms.
DEF = '''    static void
host_raise(int sig)
{
    kill(getpid(), sig);
}

'''
swap('    static void\nmusl_suspend(void)\n{\n', DEF + '    static void\nmusl_suspend(void)\n{\n',
     "musl_suspend()'s head, the last function of the host region",
     'the definition goes immediately above it, so that it is INSIDE the region '
     'zhostonly reads and its two host words are where every other one is')

# ---- 8. what the file is now -----------------------------------------------------------
L = t.split('\n')
boundary = [i for i, l in enumerate(L) if re.match(r'^ *# *', l)][0]
core, host = '\n'.join(L[:boundary]), '\n'.join(L[boundary:])
for name, ncore, nhost in (('getpid', 0, 1), ('kill', 0, 2), ('mch_get_pid', 1, 0)):
    if mentions(core, name) != ncore or mentions(host, name) != nhost:
        die('`%s` ends at %d mentions above the boundary and %d below, expected %d and '
            '%d' % (name, mentions(core, name), mentions(host, name), ncore, nhost))
if mentions(t, 'host_raise') != 3:
    die('`host_raise` has %d mentions and it must have three -- its prototype, the one '
        'call site it took over from `kill` and its definition' % mentions(t, 'host_raise'))
if mentions(t, 'b0_pid') != 1:
    die('`b0_pid` has %d mentions and the edit leaves exactly one, its own declaration, '
        'for tools/deadfields.py to take' % mentions(t, 'b0_pid'))

# THE BLOCK AFTER, and the sentence this phase exists to make true.  Every other edit
# above the boundary is BELOW the block, so the block still starts where it started.
have = L[lo:lo + len(block_after)]
if have != block_after:
    die('the ordinary declarations left above the boundary are %s and the input\'s '
        'block minus the two is %s'
        % (' / '.join(have) or 'none', ' / '.join(block_after) or 'none'))
if block_after and (L[lo - 1] != '' or L[lo + len(block_after)] != ''):
    die('what is left of the block is not a paragraph of its own')
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
        '`static`, and the check states what that means as a measurement of the cut '
        'rather than as a sentence written here' % len(block_before))

# DECLARATION BEFORE USE, COMPUTED, and the definition INSIDE the host region.
p = [i for i, l in enumerate(L) if l == PROTO]
d = [i for i, l in enumerate(L) if l.startswith('host_raise(') and L[i + 1] == '{']
uses = [i for i, l in enumerate(L)
        if re.search(r'(?<!\w)host_raise\(', l) and i not in p and i not in d]
if len(p) != 1 or len(d) != 1 or len(uses) != 1:
    die('`host_raise` has %d prototypes, %d definitions and %d call sites'
        % (len(p), len(d), len(uses)))
hb = [i for i, l in enumerate(L)
      if l.startswith('static volatile sig_atomic_t host_winch_pending')]
he = [i for i, l in enumerate(L) if l.startswith('musl_suspend(')]
if len(hb) != 1 or len(he) != 1:
    die('the host region does not begin and end exactly once -- zhostonly reads '
        'it from `host_winch_pending` to musl_suspend\'s last brace')
end = he[0]
while end < len(L) and L[end] != '}':
    end += 1
if not (p[0] < uses[0] < d[0]):
    die('`host_raise`: prototype at %d, call at %d, definition at %d -- the prototype '
        'must be above the call and the definition below it'
        % (p[0] + 1, uses[0] + 1, d[0] + 1))
if not (boundary < d[0] and hb[0] <= d[0] <= end):
    die('`host_raise` is defined at line %d, and it must be below the boundary (%d) and '
        'INSIDE the host region (%d-%d): its body says `kill` and `getpid`, and every '
        'mention of a host word lives in that region' % (d[0] + 1, boundary + 1, hb[0] + 1, end + 1))
say('`host_raise`: prototype line %d, one call site at line %d, definition line %d, '
    'which is below the boundary at %d and inside the %d-line host region '
    'zhostonly reads' % (p[0] + 1, uses[0] + 1, d[0] + 1, boundary + 1,
                                  end + 1 - hb[0]))

# ---- 9. the arithmetic, every term of it computed from what was found -----------------
added = 1 + len(DEF.split('\n')) - 1
removed = 1 + (gp_hi - gp_lo) + 1 + dropped
if len(L) - 1 != lines_before + added - removed:
    die('the file is %d lines and the input was %d -- expected %d: one prototype and a '
        '%d-line definition in, and ml_open()\'s write, mch_get_pid()\'s %d lines with '
        'the blank after it and %d out of the core\'s block'
        % (len(L) - 1, lines_before, lines_before + added - removed,
           added - 1, gp_hi - gp_lo, dropped))
if blank_runs(t) != runs_before:
    die('the edit left %d runs of two blank lines where there were %d'
        % (blank_runs(t), runs_before))
d2 = [i for i, l in enumerate(L) if re.match(r'^ *# *', l)]
if len(d2) != 11 or d2 != list(range(d2[0], d2[0] + 11)) or d2[0] != boundary:
    die('the output does not have the same eleven contiguous `#include` directives -- '
        'this phase adds a DECLARATION and a DEFINITION, never a directive')
say('%d -> %d lines before the sweep, the eleven #includes untouched at line %d, and no '
    'run of two blank lines.  tools/deadprotos.py and tools/deadfields.py are left '
    '`static long mch_get_pid(void);` and `b0_pid` to find'
    % (lines_before, len(L) - 1, boundary + 1))

open(path, 'w', errors='surrogateescape').write(t)
PY

# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  noclib       the input binary did not build with '$cflags' '$ldflags'"; exit 1; }
echo "  noclib       the input is $state/old, $(stat -c%s "$state/old") bytes, built with SOURCE_DATE_EPOCH=0 beside the source it came from -- one call site changes from a direct libc call to a call into the host, a definition arrives and a function goes, so the binary is NOT byte-identical and the evidence is a RECORDING with probes for both halves of the phase"

# tools/phaserun.sh sweeps next, then runs pipes/zero36-check.sh.
