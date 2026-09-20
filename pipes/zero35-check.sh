#!/bin/sh
# Zero phase 35, the check -- the core calls nothing but the host.
# See pipes/zero35-edit.sh, and ZERO-PLAN.md 4c.
#
# Usage: pipes/zero35-check.sh <work-dir> <state-dir>    (run from the repository root)
#
# Runs after pipes/zero35-edit.sh and the sweep tools/phaserun.sh runs between them, and
# reads nothing from the edit's shell -- only the work tree and the state directory.
# What the edit left there is `old.c`, the source this phase was HANDED, and `old`, that
# source built with SOURCE_DATE_EPOCH=0 and the boundary's own flags.
#
# WHAT IS CLAIMED, in nine parts:
#
#   ARITHMETIC  computed FROM THE INPUT and not written here: above the boundary
#               every mention of the three is the declaration or a call, the declaration
#               goes and EVERY call becomes the host name, so each ends at 0 above the
#               boundary and each host name at its prototype plus those calls plus its
#               definition.  Below it 0 -> 1, 1 -> 2 and 1 -> 2: the phase MOVES three
#               libc calls and frees none.  HOW MANY calls is read off the input.  The
#               core's block of ordinary declarations loses exactly those three lines
#               and keeps every other, and what remains is PRINTED, because an empty
#               block is this phase's whole point and a check that asserted emptiness
#               against a file that still had other libc in it would be asserting
#               somebody else's phase.
#   THE ORDER   each prototype is above every call of its name and each definition below
#               every one of them AND below the boundary, by line number.  The control
#               is the output with the three prototype lines DELETED, which must not
#               compile and must name all three.
#   LINKAGE     `nm --extern-only --defined-only` is still exactly `main`, with both
#               halves of the `static` trap built: with the keyword off the three
#               PROTOTYPES gcc refuses, and with it off the prototypes AND the
#               definitions the build is silent and three symbols become external.
#   SYMBOLS     `nm -u` is THE SAME SET, as a `comm` empty in BOTH directions.  A phase
#               that takes every `malloc`, `free` and `write` out of the core frees
#               NOTHING, and that is not a disappointment: the host calls all three, and
#               an undefined symbol leaves when its last caller leaves the FILE.  Phase
#               28 is the contrast -- it freed `gettimeofday` because the last caller
#               went -- and a reader who expects this phase to move the count is owed
#               the equality with its reason.
#   THE CUT     `awk '/^ *# *include / { exit }'`, zero.mk's own rule, on the INPUT and
#               on the OUTPUT: 0 errors under -fsyntax-only either side, and the warning
#               set -- which IS the core -> host interface, every name `used but never
#               defined` -- grows by EXACTLY `host_alloc host_free host_write`.  The
#               input's set is computed here and never written down: it has gone stale
#               twice for other phases.
#   THE BINARY  the same SIZE and NOT the same bytes, both stated as measurements.
#   THE RECORD  two full tools/zrecord.sh recordings, `diff -r` empty over 106 records,
#               with a control that moves all 106.
#   THE PROBES  ONE PER FUNCTION, on an instrumented build of this phase's own output,
#               because a byte-identical recording says the editor did the same thing
#               and not that these three carried it.  Over the 102 screen cases the
#               instrument counts every call, the largest allocation, the largest write
#               and every short write; and three sessions drive the paths by hand -- a
#               200,000-character insert, a free of a null pointer, and the largest
#               write the corpus can produce.
#   STRUCTURE   `zhostonly`, phase 20's structural check, still passes.
set -eu

work=${1:?usage: zero35-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero35-check.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"
before_lines=$(cat "$state/input-lines")

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")

# The reproducible build of the OUTPUT, the controls and the instrumented build are
# written first and waited for where each is used.  Every one of them is this phase's
# own product with ONE thing changed.
# shellcheck disable=SC2086
( SOURCE_DATE_EPOCH=0 gcc $cflags $ldflags -o "$tmp/new" "$f" ) &
pid_new=$!
python3 - "$f" "$tmp" <<'PY'
import re
import sys

TAG = 'hostcall'
t = open(sys.argv[1], errors='surrogateescape').read()
out = sys.argv[2]
L = t.split('\n')

PROTOS = ['static void *host_alloc(usize n);',
          'static void host_free(void *p);',
          'static int host_write(const char *s, int len);']
missing = [p for p in PROTOS if t.count(p + '\n') != 1]
if missing:
    sys.exit('  %-12s the output does not hold each of this phase\'s three prototypes '
             'exactly once: %s' % (TAG, ' / '.join(missing)))

# c1 -- the three prototypes DELETED.  It must not compile: that is what says they are
# load-bearing rather than decorative, and it is the control for the ordering section.
c1 = t
for p in PROTOS:
    c1 = c1.replace(p + '\n', '', 1)

# c2 -- `static` off the three PROTOTYPES only.  A hard error against the static
# definitions, which is the loud half of the linkage trap.
c2 = t
for p in PROTOS:
    c2 = c2.replace(p + '\n', p[len('static '):] + '\n', 1)

# c3 -- `static` off the prototypes AND the definitions.  THE SILENT HALF: it builds,
# and three symbols become external.
c3 = c2
for name in ('host_alloc', 'host_free', 'host_write'):
    m = re.search(r'^    static ([\w *]+)\n(%s\()' % name, c3, re.M)
    if not m:
        sys.exit('  %-12s `%s` is not defined in the `    static <type>` shape, so c3 '
                 'would not be a control' % (TAG, name))
    c3 = c3[:m.start()] + '    ' + m.group(1) + '\n' + m.group(2) + c3[m.end():]


def one(old, what):
    if t.count(old) != 1:
        sys.exit('  %-12s `%s` is not in the output exactly once, so the control built '
                 'from it would not be one' % (TAG, what))
    return old


# ca   -- host_alloc always fails.  The editor cannot draw a screen without memory, so
#         this is the maximal control: it must move EVERY record.
# cbig -- host_alloc fails only above 200,000 bytes, which in this editor is exactly one
#         allocation: the screen.  The named control, and the discriminating one.
# cf   -- host_free does nothing.  A leak, and MEASURED to move NOTHING: see below.
# cw   -- host_write writes every byte and REPORTS HALF.  mch_write() ignores the count,
#         so this too must move nothing, and that is the phase's own claim about the
#         wrapper's return value rather than an accident.
# cw2  -- host_write actually writes half.  The bytes are the screen, so it must move
#         everything the screen corpus records.
# cnull-- host_free(nullptr) called on every draw.  Not a control but a PROBE: it must
#         move nothing, which is what `free(nullptr) is defined and does nothing` means
#         for the wrapper.
ALLOC = one('    return malloc(n);\n', 'return malloc(n);')
FREE = one('    free(p);\n', 'free(p);')
WRITE = one('    return (int)write(1, s, (usize)len);\n',
            'return (int)write(1, s, (usize)len);')
MCHW = one('    vim_ignored = host_write((char *)s, len);\n',
           "mch_write()'s call")
ctl = {
    'ca': t.replace(ALLOC, '    return nullptr;\n', 1),
    'cbig': t.replace(ALLOC, '    return n > 200000 ? nullptr : malloc(n);\n', 1),
    'cf': t.replace(FREE, '    (void)p;\n', 1),
    'cw': t.replace(WRITE, '    return (int)write(1, s, (usize)len) / 2;\n', 1),
    'cw2': t.replace(WRITE, '    return (int)write(1, s, (usize)len / 2);\n', 1),
    'cnull': t.replace(MCHW, '    host_free(nullptr);\n' + MCHW, 1),
}

# probe -- the output with a counter on each of the three and a line to stderr at exit.
# Nothing is folded away and nothing is skipped: it is the product plus seven longs.
INSTR = '''static long probe_a, probe_f, probe_fnull, probe_w, probe_amax, probe_wmax, probe_wshort;

    static void
probe_num(long v)
{
    char b[24];
    int i = 24;

    if (v == 0)
    {
        b[--i] = '0';
    }
    while (v > 0)
    {
        b[--i] = (char)('0' + v % 10);
        v /= 10;
    }
    write(2, b + i, (usize)(24 - i));
}

    static void
probe_dump(void)
{
    write(2, "PROBE alloc=", 12);
    probe_num(probe_a);
    write(2, " amax=", 6);
    probe_num(probe_amax);
    write(2, " free=", 6);
    probe_num(probe_f);
    write(2, " fnull=", 7);
    probe_num(probe_fnull);
    write(2, " write=", 7);
    probe_num(probe_w);
    write(2, " wmax=", 6);
    probe_num(probe_wmax);
    write(2, " wshort=", 8);
    probe_num(probe_wshort);
    write(2, "\\n", 1);
}

'''
EXIT = one('    static void\nhost_exit(int r)\n{\n', 'host_exit()')
p = t.replace(EXIT, INSTR + EXIT + '    probe_dump();\n', 1)
p = p.replace(ALLOC, '''    probe_a++;
    if ((long)n > probe_amax)
    {
        probe_amax = (long)n;
    }
    return malloc(n);
''', 1)
p = p.replace(FREE, '''    probe_f++;
    if (p == nullptr)
    {
        probe_fnull++;
    }
    free(p);
''', 1)
p = p.replace(WRITE, '''    int w;

    probe_w++;
    if (len > probe_wmax)
    {
        probe_wmax = len;
    }
    w = (int)write(1, s, (usize)len);
    if (w >= 0 && w < len)
    {
        probe_wshort++;
    }
    return w;
''', 1)
ctl['probe'] = p

for name, text in [('c1', c1), ('c2', c2), ('c3', c3)] + sorted(ctl.items()):
    if text == t:
        sys.exit('  %-12s %s changed nothing' % (TAG, name))
    open('%s/%s.c' % (out, name), 'w', errors='surrogateescape').write(text)
print('  %-12s nine variants written: c1 the three prototypes DELETED, c2 `static` off '
      'them, c3 `static` off them AND the definitions; ca host_alloc always nullptr, '
      'cbig it fails only above 200,000 bytes, cf host_free does nothing, cw host_write '
      'writes everything and REPORTS half, cw2 it writes half, cnull host_free(nullptr) '
      'on every draw; and probe, the output with a counter on each of the three' % TAG)
PY
# c1 and c2 are expected to FAIL, so their status is discarded here rather than by
# `wait`, which would take `set -e` with it.
( gcc -O0 -fno-stack-protector -fsyntax-only "$tmp/c1.c" 2>"$tmp/e.c1" || true ) &
pid_c1=$!
( gcc -O0 -fno-stack-protector -fsyntax-only "$tmp/c2.c" 2>"$tmp/e.c2" || true ) &
pid_c2=$!
( gcc -c -O0 -fno-stack-protector -o "$tmp/c3.o" "$tmp/c3.c" 2>"$tmp/e.c3" || true ) &
pid_c3=$!
for v in ca cbig cf cw cw2 cnull probe; do
    # shellcheck disable=SC2086
    ( SOURCE_DATE_EPOCH=0 gcc $cflags $ldflags -o "$tmp/$v" "$tmp/$v.c" 2>"$tmp/e.$v" ) &
    eval "pid_$v=$!"
done
# tools/canon.sh must be a NO-OP on the output.
cp "$f" "$tmp/canon.c"
( tools/canon.sh "$tmp/canon.c" >"$tmp/canon.log" 2>&1 ) &
pid_canon=$!

# --- 1. the source, as arithmetic on the input ------------------------------------------
python3 - "$f" "$state/old.c" "$before_lines" <<'PY'
import re
import sys

TAG = 'hostcall'
new = open(sys.argv[1], errors='surrogateescape').read()
old = open(sys.argv[2], errors='surrogateescape').read()
before_lines = int(sys.argv[3])
fail = []
NL, OL = new.split('\n'), old.split('\n')

DECL = re.compile(r'^(?!static |typedef |static_assert)[A-Za-z_][\w *]*\**\w+\([^;]*\);$')
GO = ['void *malloc(usize n);',
      'void free(void *p);',
      'long write(int fd, const void *buf, usize n);']


def mentions(text, name):
    return len(re.findall(r'\b%s\b' % name, text))


def halves(lines):
    """The core and the host, split at the first `#include` and nowhere else."""
    d = [i for i, l in enumerate(lines) if re.match(r'^ *# *', l)]
    if len(d) != 11 or d != list(range(d[0], d[0] + 11)) \
            or any(not re.match(r'^#include <[A-Za-z0-9_/.]+>$', lines[i]) for i in d):
        return None, None, None
    return '\n'.join(lines[:d[0]]), '\n'.join(lines[d[0]:]), d[0]


ocore, ohost, obound = halves(OL)
ncore, nhost, nbound = halves(NL)
if ocore is None or ncore is None:
    sys.exit('  %-12s the eleven `#include` directives are not eleven consecutive lines '
             'in the %s -- the first `#include` IS the boundary and nothing else marks '
             'it' % (TAG, 'input' if ocore is None else 'output'))

# THE ARITHMETIC, AND IT IS A PARTITION OF THE INPUT AND NOT A COUNT OF IT.  The phase
# asserted `malloc` 2, `free` 3 and `write` 2 once, and phase 34 -- which rewrites
# realloc as a malloc, a copy and a free at two core sites -- made all three wrong.  What
# is checked now is the shape: above the boundary every mention of each name is a
# call-shaped token, the declaration or a call; the declaration goes, EVERY call becomes
# the host name, and the host name ends at its prototype plus those calls plus its
# definition.  How many calls there are is read off the INPUT here, exactly as the edit
# reads it, so this check states a transformation rather than a tree it once saw.
ncalls = {}
for name, hcnt, why in (
        ('malloc', 0, 'lalloc(), and phase 34\'s two'),
        ('free', 1, 'vim_free(), update_wincolor() and phase 34\'s two; and '
                    'format_overflow_error() below the boundary already did'),
        ('write', 1, 'mch_write(); and host_message() below the boundary already did')):
    occ = len(re.findall(r'\b%s\b' % name, ocore))
    paren = len(re.findall(r'(?<!\w)%s\(' % name, ocore))
    if occ != paren or paren < 2:
        fail.append('the INPUT has %d mentions of `%s` above the boundary of which %d '
                    'are call-shaped, and this phase needs every one to be the '
                    'declaration or a call, with at least one call -- %s'
                    % (occ, name, paren, why))
        ncalls[name] = None
        continue
    ncalls[name] = paren - 1
    if mentions(ohost, name) != hcnt:
        fail.append('the INPUT says `%s` %d times below the boundary, expected %d -- %s'
                    % (name, mentions(ohost, name), hcnt, why))
    elif mentions(ncore, name) != 0 or mentions(nhost, name) != hcnt + 1:
        fail.append('`%s` ends at %d mentions above the boundary and %d below, expected '
                    '0 and %d -- the phase MOVES the call, it does not remove it'
                    % (name, mentions(ncore, name), mentions(nhost, name), hcnt + 1))
# Every core write() must have gone to fd 1, because host_write() takes no descriptor.
if ncalls.get('write'):
    fd1 = len(re.findall(r'(?<!\w)write\(1, ', ocore))
    if fd1 != ncalls['write']:
        fail.append('%d of the INPUT\'s %d core write() calls are to fd 1, and '
                    'host_write() can only stand in for a write to the screen'
                    % (fd1, ncalls['write']))
for name, was in (('host_alloc', 'malloc'), ('host_free', 'free'),
                  ('host_write', 'write')):
    if mentions(old, name):
        fail.append('the INPUT already says `%s`' % name)
    elif ncalls.get(was) is not None:
        want = ncalls[was] + 2
        if mentions(new, name) != want:
            fail.append('`%s` has %d mentions, expected %d -- its prototype, the %d call '
                        'site%s it took over from `%s` and its definition'
                        % (name, mentions(new, name), want, ncalls[was],
                           '' if ncalls[was] == 1 else 's', was))

# THE BLOCK, WHICH IS WHAT THIS PHASE IS FOR.  It is found in the input the way the edit
# found it -- the run of ordinary declarations around the `malloc` line -- and the
# output's is required to be that run minus exactly the three.
seed = [i for i, l in enumerate(OL[:obound]) if l == GO[0]]
if len(seed) != 1:
    fail.append('the input does not declare `%s` exactly once above the boundary' % GO[0])
    block_before = block_after = []
else:
    lo = hi = seed[0]
    while lo > 0 and DECL.match(OL[lo - 1]):
        lo -= 1
    while hi + 1 < obound and DECL.match(OL[hi + 1]):
        hi += 1
    block_before = OL[lo:hi + 1]
    block_after = [l for l in block_before if l not in GO]
    if len(block_before) - len(block_after) != 3:
        fail.append('the input\'s block of ordinary declarations does not hold all '
                    'three of this phase\'s lines: %s' % ' / '.join(block_before))
    have = [l for i, l in enumerate(NL[:nbound])
            if DECL.match(l) and (NL[i - 1] == '' or DECL.match(NL[i - 1]))]
    if have != block_after:
        fail.append('the ordinary declarations above the boundary are %s and the '
                    'input\'s block minus the three is %s'
                    % (' / '.join(have) or 'none', ' / '.join(block_after) or 'none'))

# THE SHAPE OF THE EDIT.  Three lines out of the block -- four when the block empties,
# because a paragraph separator with nothing to separate is a run of two blank lines --
# and 21 in: three prototypes, and three five-line definitions each followed by a blank.
dropped = 3 if block_after else len(block_before) + 1
if len(NL) - 1 != before_lines + 21 - dropped or len(OL) - 1 != before_lines:
    fail.append('the file is %d lines and the input was %d (%d recorded) -- expected %d '
                'more' % (len(NL) - 1, len(OL) - 1, before_lines, 21 - dropped))
if sum(1 for k in range(1, len(NL)) if NL[k] == '' and NL[k - 1] == ''):
    fail.append('there is a run of two blank lines, which canon.sh should have taken')

# THE SHAPE OF THE FILE.  Nothing here is a command, an option or a directive, and the
# counts are the input's rather than three numbers written down.
sys.path.insert(0, 'tools')
# tools/create_cmdidxs.py -- named as a PATH so tools/implhash.sh hashes it into this
# phase's key.  implhash greps for paths and an `import` names a module, so
# without this line an edit to it changes what this phase produces and moves
# no key at all.  See CLAUDE.md on cutil.py and macros.py.  Do not delete it.
import create_cmdidxs
n_old = len(re.findall(r'^    \[CMD_\w+\] = \{.*$', old, re.M))
n_new = len(re.findall(r'^    \[CMD_\w+\] = \{.*$', new, re.M))
if n_new != n_old or len(create_cmdidxs.names(sys.argv[1])) != n_old:
    fail.append('cmdnames[] is %d rows and the input had %d -- this phase touches no Ex '
                'command' % (n_new, n_old))


def opts(text):
    i = text.find('static struct vimoption options[]')
    j = text.index('\n};', i)
    return len(re.findall(r'^[ \t]*\{"([a-z]+)",', text[i:j], re.M))


if opts(new) != opts(old):
    fail.append('options[] has %d rows and the input had %d -- this phase removes no '
                'option' % (opts(new), opts(old)))
if nbound != obound:
    fail.append('the boundary moved from line %d to line %d, and it must not: three '
                'declarations leave the core\'s block and three arrive at the end of '
                'the core -> host block, which is the same number of lines above the '
                'first `#include`' % (obound + 1, nbound + 1))

if fail:
    for line in fail:
        print('  %-12s %s' % (TAG, line))
    sys.exit(1)
print('  %-12s ABOVE THE BOUNDARY every mention of the three goes: `malloc` %d -> 0 '
      '(its declaration and %d call%s), `free` %d -> 0 (%d) and `write` %d -> 0 (%d, all '
      'to fd 1).  BELOW IT 0 -> 1, 1 -> 2 and 1 -> 2, so the phase MOVES three libc calls '
      'and removes none; `host_alloc` 0 -> %d, `host_free` 0 -> %d, `host_write` 0 -> %d.  '
      'Not one of those numbers is written down: each is the INPUT partitioned into a '
      'declaration and its calls'
      % (TAG, ncalls['malloc'] + 1, ncalls['malloc'],
         '' if ncalls['malloc'] == 1 else 's', ncalls['free'] + 1, ncalls['free'],
         ncalls['write'] + 1, ncalls['write'], ncalls['malloc'] + 2, ncalls['free'] + 2,
         ncalls['write'] + 2))
print('  %-12s THE CORE\'S BLOCK OF ORDINARY DECLARATIONS -- the libc it names, the one '
      'run above the boundary that is not `static` -- is %d lines and was %d: %s'
      % ('', len(block_after), len(block_before),
         ('%s remain, and each belongs to a phase of its own'
          % ' '.join(re.sub(r'^.*?\**(\w+)\(.*$', r'\1', l) for l in block_after))
         if block_after else
         'IT IS EMPTY.  The core names no libc function at all, and every outward call '
         'it makes is a `musl_` or a `host_`'))
print('  %-12s %d -> %d lines, %d more; cmdnames[] %d and options[] %d unmoved; the '
      'eleven #includes still eleven consecutive lines at %d'
      % ('', before_lines, len(NL) - 1, len(NL) - 1 - before_lines, n_new, opts(new),
         nbound + 1))
PY

# --- 2. declaration before use, and the control that says the declaration is needed -----
wait $pid_c1
python3 - "$f" "$tmp/e.c1" <<'PY'
import re
import sys

TAG = 'hostcall'
NL = open(sys.argv[1], errors='surrogateescape').read().split('\n')
err = open(sys.argv[2], errors='surrogateescape').read()
bound = [i for i, l in enumerate(NL) if re.match(r'^ *# *', l)][0]

out = []
for name in ('host_alloc', 'host_free', 'host_write'):
    proto = [i for i, l in enumerate(NL)
             if re.match(r'^static [\w *]*%s\(.*\);$' % name, l)]
    defn = [i for i, l in enumerate(NL)
            if l.startswith(name + '(') and i + 1 < len(NL) and NL[i + 1] == '{']
    uses = [i for i, l in enumerate(NL) if re.search(r'(?<!\w)%s\(' % name, l)
            and i not in proto and i not in defn]
    if len(proto) != 1 or len(defn) != 1 or not uses:
        sys.exit('  %-12s `%s` has %d prototypes, %d definitions and %d call sites in '
                 'the output' % (TAG, name, len(proto), len(defn), len(uses)))
    if not (proto[0] < min(uses) and max(uses) < defn[0] and bound < defn[0]):
        sys.exit('  %-12s `%s`: prototype at %d, calls at %d..%d, definition at %d, '
                 'boundary at %d -- the prototype must be ABOVE every call, the '
                 'definition BELOW every one of them and BELOW the boundary, which is '
                 'what makes it the host\'s and not the core\'s'
                 % (TAG, name, proto[0] + 1, min(uses) + 1, max(uses) + 1, defn[0] + 1,
                    bound + 1))
    out.append((name, proto[0] + 1, len(uses), min(uses) + 1, max(uses) + 1, defn[0] + 1))
# The control: with the three prototype lines gone the file must NOT compile, and the
# errors must name all three.  A declaration nothing needs is one this phase should not
# have added.
if not re.search(r'\berror\b', err):
    sys.exit('  %-12s THE CONTROL c1 DID NOT SHOW: with the three prototype lines '
             'DELETED the file still compiles, so the declarations this phase adds are '
             'not what lets the core name the host and the ordering above proves '
             'nothing' % TAG)
for name in ('host_alloc', 'host_free', 'host_write'):
    if name not in err:
        sys.exit('  %-12s the control c1 failed without naming `%s`, so it is not the '
                 'control it claims to be' % (TAG, name))
n = len(re.findall(r'error:', err))
for name, pr, k, lo, hi, dfn in out:
    print('  %-12s `%s`: prototype line %d, %d call site%s at %d%s, definition line %d, '
          'below the boundary at %d'
          % (TAG, name, pr, k, '' if k == 1 else 's', lo,
             '' if k == 1 else '..%d' % hi, dfn, bound + 1))
    TAG = ''
print('  %-12s AND THE DECLARATIONS ARE LOAD-BEARING: this phase\'s own output with the '
      'three prototype lines DELETED gives %d errors naming all three.  Without that '
      'control the three lines above are a statement about line numbers and not about '
      'the program' % ('', n))
PY

# --- 3. linkage, WHICH IS THE ASSERTION THAT MATTERS MOST ---------------------------------
# One external symbol has been the invariant since phase 0, and a phase that gives the
# core three more names to call is one that could break it quietly: a `static` missing
# from a declaration and its definition is a silently correct build with three more
# symbols in it.  tools/phasecheck.sh asserts `main` alone below; here are the two
# alternatives, measured, exactly as phase 25 measured them for its two.
wait $pid_c2
wait $pid_c3
if ! grep -q "static declaration of 'host_alloc' follows non-static declaration" "$tmp/e.c2"; then
    echo "  hostcall     THE CONTROL c2 DID NOT SHOW.  With \`static\` off the three PROTOTYPES"
    echo "               and left on the definitions, gcc must refuse:"
    sed 's/^/               /' "$tmp/e.c2" | head -4
    exit 1
fi
if [ -s "$tmp/e.c3" ] || [ ! -f "$tmp/c3.o" ]; then
    echo "  hostcall     the control c3 did not build, and the point of it is that it DOES:"
    sed 's/^/               /' "$tmp/e.c3" | head -4
    exit 1
fi
c3_ext=$(nm --extern-only --defined-only "$tmp/c3.o" | awk '{print $NF}' | sort | tr '\n' ' ')
if [ "$c3_ext" != "host_alloc host_free host_write main " ]; then
    echo "  hostcall     THE CONTROL c3 DID NOT SHOW.  With \`static\` off the prototypes AND"
    echo "               the definitions the object must define host_alloc, host_free,"
    echo "               host_write and main; it defines: $c3_ext"
    exit 1
fi
echo "  hostcall     THE \`static\` TRAP, BOTH HALVES, MEASURED ON THIS PHASE'S OWN OUTPUT: with the keyword off the three PROTOTYPES gcc REFUSES -- \"static declaration of 'host_alloc' follows non-static declaration\" -- and with it off the prototypes AND the definitions the build is SILENT and the object defines $c3_ext.  The second is the mistake this phase could have made without anything else noticing, and tools/phasecheck.sh below is what catches it"

# --- 4. the compile, the linkage and the libc surface ---------------------------------------
# NOTHING IS FREED AND THE PHASE SAYS SO AS AN EQUALITY.  Taking every `malloc`, `free`
# and `write` out of the core cannot move `nm -u`, because the HOST calls all three and
# a symbol leaves when its last caller leaves the FILE.  Phase 28 is the contrast: it
# freed `gettimeofday` because the last caller went with it.
cp "$state/symbols/undefined" "$tmp/before.u"
tools/phasecheck.sh "$work" "$f" "$state/symbols"
if ! cmp -s "$tmp/before.u" .cache/symbols/last/undefined; then
    echo "  hostcall     the libc surface moved, and MOVING A CALL ACROSS THE BOUNDARY CANNOT"
    echo "               MOVE IT -- the host calls all three where the core did:"
    echo "               gone: $(comm -23 "$tmp/before.u" .cache/symbols/last/undefined | tr '\n' ' ')"
    echo "               came: $(comm -13 "$tmp/before.u" .cache/symbols/last/undefined | tr '\n' ' ')"
    exit 1
fi
for s in malloc free write; do
    grep -qx "$s" .cache/symbols/last/undefined || {
        echo "  hostcall     \`$s\` is no longer an undefined symbol, and it must still be one:"
        echo "               this phase moves the call into the host, it does not remove it."
        exit 1
    }
done
echo "  hostcall     symbols $(cat .cache/symbols/last/before) -> $(cat .cache/symbols/last/after), and the set is IDENTICAL as a cmp -- nothing left and nothing arrived.  \`malloc\`, \`free\` and \`write\` are all three still there, which is the point: the phase MOVES them out of the core and the host calls them, and an undefined symbol leaves only when its last caller leaves the FILE.  main is still the only external symbol"

# --- 5. the cut, and the core -> host interface it prints -----------------------------------
# zero.mk's own rule, one awk clause and no judgement, on the INPUT and on the OUTPUT.
# The cut's warnings ARE the interface: every name the core uses and the host defines is
# `used but never defined` there.  The input's set is COMPUTED here, never written down.
editorcut() {
    awk '/^ *# *include / { exit } { a[NR] = $0; if (NF) last = NR } \
         END { for (i = 1; i <= last; i++) print a[i] }' "$1" > "$2"
    if grep -q '^ *#' "$2"; then
        echo "  hostcall     the cut of $1 holds a directive, so it found the wrong line"
        exit 1
    fi
    if [ "$(grep -c '' "$2")" -le 70000 ]; then
        echo "  hostcall     the cut of $1 is $(grep -c '' "$2") lines, and zero.mk's floor is 70,000 -- a cut that found line 1 would be empty and every check below would pass on nothing"
        exit 1
    fi
    gcc -O0 -fno-stack-protector -fsyntax-only "$2" 2>"$2.log" || true
    grep -c 'error:' "$2.log" > "$2.err" || true
    sed -n "s/.*warning: '\\([A-Za-z_][A-Za-z0-9_]*\\)' used but never defined.*/\\1/p" "$2.log" | sort > "$2.names"
}
editorcut "$state/old.c" "$tmp/cut-old.c"
editorcut "$f" "$tmp/cut-new.c"
for w in old new; do
    if [ "$(cat "$tmp/cut-$w.c.err")" != 0 ]; then
        echo "  hostcall     the $w cut does not parse: $(cat "$tmp/cut-$w.c.err") errors"
        grep 'error:' "$tmp/cut-$w.c.log" | head -3 | sed 's/^/               /'
        exit 1
    fi
    if [ "$(grep -c 'warning:' "$tmp/cut-$w.c.log")" != "$(grep -c '' "$tmp/cut-$w.c.names")" ]; then
        echo "  hostcall     the $w cut has a warning that is not a 'used but never defined':"
        grep 'warning:' "$tmp/cut-$w.c.log" | grep -v 'used but never defined' | head -3 | sed 's/^/               /'
        exit 1
    fi
done
head -c "$(stat -c%s "$tmp/cut-new.c")" "$f" > "$tmp/prefix.c"
cmp -s "$tmp/prefix.c" "$tmp/cut-new.c" || { echo "  hostcall     the cut is not a byte prefix of zero-vim.c"; exit 1; }
arrived=$(comm -13 "$tmp/cut-old.c.names" "$tmp/cut-new.c.names" | tr '\n' ' ')
left=$(comm -23 "$tmp/cut-old.c.names" "$tmp/cut-new.c.names" | tr '\n' ' ')
if [ "$arrived" != "host_alloc host_free host_write " ] || [ -n "$left" ]; then
    echo "  hostcall     THE CUT'S BOUNDARY SET DID NOT MOVE AS THIS PHASE CLAIMS."
    echo "               arrived: ${arrived:-nothing}"
    echo "               left:    ${left:-nothing}"
    exit 1
fi
echo "  hostcall     THE CUT -- \`make editor.c\`'s own rule, and a byte prefix of the file -- is $(grep -c '' "$tmp/cut-new.c") lines either side, 0 errors either side, and its warning set, which IS the core -> host interface, goes from $(grep -c '' "$tmp/cut-old.c.names") names to $(grep -c '' "$tmp/cut-new.c.names"): host_alloc, host_free and host_write ARRIVE and nothing leaves.  A libc dependency that was implicit in a bare declaration is now an explicit named call, and the interface growing by three is what that looks like.  The input's set is computed here and never written down"

# --- 6. the binary: the same size, and NOT the same bytes ------------------------------------
wait $pid_canon
if ! cmp -s "$tmp/canon.c" "$f"; then
    echo "  hostcall     tools/canon.sh CHANGED THE OUTPUT, and it must be a no-op:"
    diff "$f" "$tmp/canon.c" | head -6 | sed 's/^/               /'
    exit 1
fi
echo "  hostcall     tools/canon.sh is a NO-OP on the output ($(sed -n 's/.*canon *//p' "$tmp/canon.log" | head -1))"

# tools/phaserun.sh runs tools/zerodelta.sh on $work/zero-vim after this check, so the
# boundary's own binary is built here as every zero check builds it.
make -C "$work" clean >/dev/null 2>&1 || true
[ -e "$work/zero-vim" ] && { echo "  build        the clean did not remove zero-vim, so a 'rebuild' below could be no rebuild at all"; exit 1; }
if ! make -C "$work" >/dev/null 2>&1; then
    echo "  build        FAILED -- rerun by hand: make -C $work"
    exit 1
fi
bin="$work/zero-vim"
echo "  build        ok, $before_lines -> $(grep -c '' "$f") lines, $(stat -c%s "$bin") bytes"

wait $pid_new || { echo "  hostcall     the reproducible build of the output failed"; exit 1; }
old_size=$(stat -c%s "$state/old")
new_size=$(stat -c%s "$tmp/new")
if [ "$new_size" -lt 500000 ] || [ "$old_size" -lt 500000 ]; then
    echo "  hostcall     one of the two binaries is $old_size / $new_size bytes, which is not an editor"
    exit 1
fi
if [ "$new_size" != "$(stat -c%s "$bin")" ]; then
    echo "  hostcall     the reproducible build is $new_size bytes and make produced $(stat -c%s "$bin"): the two differ by more than a timestamp, so nothing below would be about this boundary"
    exit 1
fi
if cmp -s "$state/old" "$tmp/new"; then
    echo "  hostcall     THE BINARY IS BYTE-IDENTICAL, and it must not be: four call sites go"
    echo "               from a direct libc call to a call into a function of this file, and"
    echo "               three definitions arrive at the bottom of it."
    exit 1
fi
echo "  hostcall     the binary is $old_size bytes in and $new_size out, $(cmp -l "$state/old" "$tmp/new" | wc -l) of them differing.  Both are MEASUREMENTS and neither is aimed for: at -O0 a call to a static function in the same file is not the same instruction stream as a call to a libc symbol, and three definitions arrive.  So this phase cannot use tier 1 of CLAUDE.md's verification table and does not pretend to; the evidence is the recording and the probes below"

# --- 7. THE EVIDENCE: two recordings, and a control that moves all of them --------------------
rec() {
    tools/zrecord.sh "$2" "$3" "$tmp/REC-$1" >/dev/null 2>&1 &
    eval "pid_rec_$1=$!"
}
wait $pid_ca || { echo "  hostcall     the control ca did not build:"; head -5 "$tmp/e.ca" | sed 's/^/               /'; exit 1; }
rec old "$state/old" "$state/old.c"
rec new "$tmp/new" "$f"
rec ca "$tmp/ca" "$tmp/ca.c"
for pp in $pid_rec_old $pid_rec_new $pid_rec_ca; do
    wait "$pp" || { echo "  hostcall     a recording failed"; exit 1; }
done
python3 - "$tmp" <<'PY'
import filecmp
import os
import sys

TAG = 'hostcall'
tmp = sys.argv[1]


def files(d):
    out = []
    for root, _, names in os.walk(d):
        for n in names:
            out.append(os.path.relpath(os.path.join(root, n), d))
    return sorted(out)


base = files('%s/REC-new' % tmp)
if len(base) < 100:
    sys.exit('  %-12s a recording holds %d records, and a zero recording is 106 -- 102 '
             'screen cases and four sweeps.  A comparison of two things nothing wrote '
             'passes' % (TAG, len(base)))


def moved(which):
    d = '%s/REC-%s' % (tmp, which)
    if files(d) != base:
        sys.exit('  %-12s the recording of %s holds different records from the output\'s'
                 % (TAG, which))
    return [n for n in base
            if not filecmp.cmp('%s/REC-new/%s' % (tmp, n), '%s/%s' % (d, n),
                               shallow=False)]


same = moved('old')
if same:
    print('  %-12s THE RECORDING MOVED, in %d of %d records: %s'
          % (TAG, len(same), len(base), ' '.join(same[:8])))
    print('  %-12s This phase declares NOTHING.  Three libc calls became three calls '
          'into the host, each forwarding to the same libc function with the same '
          'arguments; the editor does the same thing or the phase is wrong.' % '')
    sys.exit(1)
m = moved('ca')
if len(m) != len(base):
    sys.exit('  %-12s THE CONTROL ca DID NOT SHOW: with host_alloc returning nullptr '
             'always, %d of %d records move and every one must -- an editor that cannot '
             'allocate cannot draw' % (TAG, len(m), len(base)))
print('  %-12s THE RECORDING IS BYTE-IDENTICAL, all %d records -- 102 screen cases, '
      'every Ex command typed at `:`, every command line the parser may see, the four '
      'pty scenarios and the terminal table.  lalloc() and vim_free() are on the path '
      'of essentially everything the editor does and mch_write() is every byte it '
      'draws, so the corpus HAMMERS all three of this phase\'s subjects: an empty `diff '
      '-r` is strong evidence here, where for a phase whose subject the corpus cannot '
      'reach it would be weak' % (TAG, len(base)))
print('  %-12s AND IT CAN FAIL: host_alloc returning nullptr always moves %d of %d -- '
      'every record there is' % ('', len(m), len(base)))
PY

# --- 8. THE PROBES: one per function, on the real path ----------------------------------------
# A byte-identical recording says the editor did the same thing.  It does not say that
# these three functions are what carried it, and the controls below say what each one is
# worth.  The instrument is the output with a counter on each, which prints one line to
# stderr from host_exit() -- so `zcases`, which records stderr, carries it in
# every one of the 102 cases.
wait $pid_probe || { echo "  hostcall     the instrumented build failed:"; head -5 "$tmp/e.probe" | sed 's/^/               /'; exit 1; }
for v in cbig cf cw cw2 cnull; do
    eval "wait \$pid_$v" || { echo "  hostcall     the control $v did not build:"; head -5 "$tmp/e.$v" | sed 's/^/               /'; exit 1; }
done
for v in probe cbig cf cw cw2 cnull; do
    ( tools/st.sh zcases "$tmp/$v" "$tmp/SC-$v" >/dev/null 2>&1 ) &
    eval "pid_sc_$v=$!"
done
# The three by-hand sessions, on the instrumented binary, each driving one path.
# The environment is emptied exactly as every harness empties it (CLAUDE.md): no
# $HOME, $VIM, $VIMRUNTIME or $XDG_CONFIG_HOME and no $VIMINIT or $EXINIT, so a real
# ~/.vimrc on the machine cannot reach these three sessions.
printf ':q!\r' > "$tmp/keys-q"
printf 'ihello world\033:q!\r' > "$tmp/keys-i"
session() {
    ( cd "$tmp" && env -u VIMINIT -u EXINIT HOME= VIM= VIMRUNTIME= XDG_CONFIG_HOME= \
        TERM=xterm "./$1" "$2" < "$3" > /dev/null 2> "$4" ) || true
}
session probe '+normal 200000ax' keys-q big.err
session probe '+set paste' keys-i small.err
session cnull '+set paste' keys-i null.err
for v in probe cbig cf cw cw2 cnull; do
    eval "wait \$pid_sc_$v" || { echo "  hostcall     the screen corpus failed on $v"; exit 1; }
done
python3 - "$tmp" <<'PY'
import filecmp
import os
import re
import sys

TAG = 'hostcall'
tmp = sys.argv[1]
base = sorted(os.listdir('%s/REC-new/screen' % tmp))
if len(base) != 102:
    sys.exit('  %-12s the screen corpus is %d cases and it is 102' % (TAG, len(base)))


def moved(which):
    d = '%s/SC-%s' % (tmp, which)
    if sorted(os.listdir(d)) != base:
        sys.exit('  %-12s the %s corpus holds different cases' % (TAG, which))
    return [n for n in base
            if not filecmp.cmp('%s/REC-new/screen/%s' % (tmp, n), '%s/%s' % (d, n),
                               shallow=False)]


# THE INSTRUMENT, over all 102 cases.
fields = 'alloc amax free fnull write wmax wshort'.split()
tot = {}
seen = 0
for n in base:
    text = open('%s/SC-probe/%s' % (tmp, n), errors='surrogateescape').read()
    m = re.search(r'PROBE ' + ' '.join('%s=(\\d+)' % k for k in fields), text)
    if not m:
        continue
    seen += 1
    for k, v in zip(fields, (int(x) for x in m.groups())):
        tot[k] = max(tot.get(k, 0), v) if k in ('amax', 'wmax') \
            else tot.get(k, 0) + v
if seen != 102:
    sys.exit('  %-12s the instrumented build marked %d of 102 cases, and it must mark '
             'every one: the counter is printed from host_exit(), which every case '
             'reaches' % (TAG, seen))
if not (tot['alloc'] > 10000 and tot['free'] > 5000 and tot['write'] > 500):
    sys.exit('  %-12s the instrument counts %s, and a corpus that hammers lalloc() and '
             'mch_write() cannot give numbers that small -- the counters are not on the '
             'path' % (TAG, tot))
if tot['fnull']:
    sys.exit('  %-12s host_free was handed a null pointer %d times, and the input\'s two '
             'call sites both guard against it -- vim_free() tests `x != nullptr` and '
             'update_wincolor() frees only the arm it allocated.  A null arriving means '
             'one of the two guards has gone' % (TAG, tot['fnull']))
if tot['wshort']:
    sys.exit('  %-12s host_write came up short %d times in the corpus, which is the one '
             'thing mch_write() has never coped with: it assigns the count to '
             'vim_ignored and writes no more.  A short write here would mean the '
             'recording above is comparing truncated screens' % (TAG, tot['wshort']))
print('  %-12s THE INSTRUMENT, over all 102 screen cases and marking every one of them: '
      'host_alloc %d calls, the largest %d bytes; host_free %d calls, %d of them null; '
      'host_write %d calls, the largest %d bytes, %d of them short.  That is what the '
      'byte-identical recording above was carried by'
      % (TAG, tot['alloc'], tot['amax'], tot['free'], tot['fnull'], tot['write'],
         tot['wmax'], tot['wshort']))

# THE THREE BY-HAND SESSIONS.
big = open('%s/big.err' % tmp, errors='surrogateescape').read()
small = open('%s/small.err' % tmp, errors='surrogateescape').read()
null = open('%s/null.err' % tmp, errors='surrogateescape').read()
mb = re.search(r'PROBE alloc=(\d+) amax=(\d+) free=(\d+) fnull=(\d+)', big)
ms = re.search(r'PROBE alloc=(\d+) amax=(\d+) free=(\d+) fnull=(\d+)', small)
if not mb or not ms:
    sys.exit('  %-12s a by-hand probe session printed no counter line' % TAG)
big_a, big_max, big_f = int(mb.group(1)), int(mb.group(2)), int(mb.group(3))
sm_a = int(ms.group(1))
if big_a < 100000 or big_a <= sm_a * 10:
    sys.exit('  %-12s `+normal 200000ax` made %d allocations against a bare session\'s '
             '%d, and a 200,000-character insert must make far more -- the probe is not '
             'driving lalloc()' % (TAG, big_a, sm_a))
if big_max < 100000:
    sys.exit('  %-12s the largest allocation in that session is %d bytes, and this '
             'probe is meant to drive a LARGE one through lalloc()' % (TAG, big_max))
print('  %-12s THE ALLOCATION PROBE: `+normal 200000ax` -- a 200,000-character insert -- '
      'makes %d host_alloc calls against %d for `ihello world<Esc>`, frees %d of them, '
      'and the largest single allocation is %d bytes.  EVERY allocation the editor makes '
      'goes through lalloc(), which is the one place the core said `malloc`'
      % ('', big_a, sm_a, big_f, big_max))
if 'PROBE' not in small:
    sys.exit('  %-12s the small session printed no counter line' % TAG)
if null.strip():
    sys.exit('  %-12s the cnull binary -- host_free(nullptr) on EVERY draw -- wrote to '
             'stderr: %r.  A null free must be silent and harmless' % (TAG, null[:80]))

# THE CONTROLS, on the same 102 cases.  Each is this phase's own output with ONE
# statement changed in ONE of the three functions, and what each MOVES is the measure of
# what the byte-identical recording above is worth for that function.
m = {k: moved(k) for k in ('cbig', 'cf', 'cw', 'cw2', 'cnull')}
if len(m['cbig']) < 90:
    sys.exit('  %-12s THE CONTROL cbig DID NOT SHOW: refusing the ONE allocation larger '
             'than 200,000 bytes moves %d of 102 screen cases, and it was measured to '
             'move 100' % (TAG, len(m['cbig'])))
if len(m['cw2']) != 102:
    sys.exit('  %-12s THE CONTROL cw2 DID NOT SHOW: host_write writing HALF the bytes '
             'moves %d of 102 screen cases and must move every one -- those bytes ARE '
             'the screen the corpus records' % (TAG, len(m['cw2'])))
if m['cf'] or m['cw'] or m['cnull']:
    print('  %-12s a control that was MEASURED to move nothing moved something: cf %d, '
          'cw %d, cnull %d of 102.  Each is reported here as a finding and not hidden, '
          'so a change in one is a fact to read rather than a failure to explain'
          % (TAG, len(m['cf']), len(m['cw']), len(m['cnull'])))
    sys.exit(1)
print('  %-12s THE CONTROLS, ONE PER FUNCTION AND TWO OF THEM MOVE NOTHING, WHICH IS '
      'REPORTED AND NOT HIDDEN:' % TAG)
print('  %-12s   host_alloc  refusing only the allocations above 200,000 bytes -- in '
      'this editor exactly ONE, the screen -- moves %d of 102, and the two that survive '
      'are ctrl_c_clean and ctrl_c_changed, which exit before a key is looked up '
      '(ZERO-PLAN.md 2g)' % ('', len(m['cbig'])))
print('  %-12s   host_free   doing NOTHING AT ALL moves 0 of 102.  A leak is invisible '
      'to a 106-record corpus, so the recording is NOT what says host_free is called; '
      'the instrument above is, at %d calls across the same 102 cases.  A control that '
      'moves nothing is REPORTED here and not quietly dropped' % ('', tot['free']))
print('  %-12s   host_write  writing every byte and REPORTING HALF moves 0 of 102, and '
      'writing HALF THE BYTES moves 102 of 102.  That pair is the phase\'s claim about '
      'the wrapper stated as a measurement: mch_write() ignores the count -- it assigns '
      'it to vim_ignored and writes no more -- so the return value is inert and the '
      'BYTES are everything.  A wrapper that LOOPED on a short write would be a '
      'behaviour change no recording could see, and host_write does not loop' % ('',))
print('  %-12s   host_free(nullptr) called on EVERY draw moves 0 of 102 and writes '
      'nothing to stderr, which is `free(nullptr) is defined and does nothing` measured '
      'on the wrapper rather than assumed from the standard.  The core does not rely on '
      'it -- 0 of the corpus\'s frees are null -- but the wrapper inherits it' % ('',))
PY

# --- 9. phase 20's structural check, which a phase that moves host calls owes ---------------
tools/st.sh zhostonly "$f"
echo "  hostcall     and that is phase 20's check, undisturbed.  Its vocabulary is libc's terminal, signal and descriptor names and \`write\` is deliberately NOT in it -- its own comment says so, naming mch_write as a later phase's.  THIS is that phase, and the assertion it owes is made directly above instead: \`write\` is 0 mentions above the boundary, computed from the input, which is stronger than a word list"

# tools/phaserun.sh runs tools/zerodelta.sh --phase 35 after this check, and this phase
# declares NOTHING: the corpus must not move at all.
