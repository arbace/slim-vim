#!/bin/sh
# Zero phase 36, the check -- the core's libc prototype block empties.
# See pipes/zero36-edit.sh, and ZERO-PLAN.md 4c.
#
# Usage: pipes/zero36-check.sh <work-dir> <state-dir>    (run from the repository root)
#
# Runs after pipes/zero36-edit.sh and the sweep tools/phaserun.sh runs between them, and
# reads nothing from the edit's shell -- only the work tree and the state directory.
# What the edit left there is `old.c`, the source this phase was HANDED, and `old`, that
# source built with SOURCE_DATE_EPOCH=0 and the boundary's own flags.
#
# WHAT IS CLAIMED, in ten parts:
#
#   ARITHMETIC  computed FROM THE INPUT and not written here.  Above the boundary every
#               mention of `getpid` and `kill` falls in a class this phase rewrites, and
#               both end at 0; `mch_get_pid` and `b0_pid` end at 0, the sweep having
#               taken the prototype and the field the edit orphaned; `host_raise` ends
#               at three, a prototype, a call and a definition.  The core's block of
#               ordinary declarations loses exactly two lines, and what remains is
#               PRINTED, because an empty block is this phase's whole point.
#   THE CLAIM   and it is measured from the CUT, not from the block, because those are
#               two different assertions and only the first is the claim.  A bare
#               `extern` declaration is INVISIBLE to `-fsyntax-only` -- gcc warns `used
#               but never defined` for a `static` function and says nothing about an
#               ordinary one -- so what is measured is `nm -u` of an OBJECT of the cut
#               alone: the set of names the core needs from outside itself.  Every name
#               in it must be DEFINED BELOW THE BOUNDARY in this same file, computed;
#               the identical computation on the INPUT finds exactly two that are not,
#               `getpid` and `kill`, and that is the control.  The cut also defines no
#               external symbol at all.
#   VOCABULARY  tools/zhostonly.py, phase 20's structural check, plus the stronger thing
#               this boundary can say: above the first `#include` the ONLY words of that
#               tool's host vocabulary left are `SIGHUP` and `SIGTERM`, the two the core
#               NAMES because it prints them.
#   THE FOLD    NOT TAKEN, and asserted as a byte comparison rather than left to be
#               believed: `deathtrap()` is identical in and out, and `vim_handle_signal()`
#               differs in exactly one line.  See the edit for the survey.
#   THE ORDER   the prototype is above the call, the definition below it, below the
#               boundary AND inside the host region.  The control is the output with the
#               prototype line deleted, which must not compile and must name it.
#   LINKAGE     `nm --extern-only --defined-only` is still exactly `main`, with both
#               halves of the `static` trap built.
#   SYMBOLS     `nm -u` is THE SAME SET, as a `comm` empty in both directions, and
#               `getpid` and `kill` are both still in it.  A phase that takes the last
#               core mention of two libc names frees NEITHER, because the host calls
#               both and a symbol leaves when its last caller leaves the FILE.
#   THE BINARY  the same SIZE or not, stated as a measurement, and NOT the same bytes.
#   THE RECORD  two full tools/zrecord.sh recordings, `diff -r` empty over 106 records,
#               with one control that MOVES all 106 and one that moves NONE, both on the
#               line this phase deletes.
#   THE PROBES  THE CORPUS CANNOT SEE EITHER HALF OF THIS PHASE, and that is measured
#               rather than assumed: an instrumented input counts the b0_pid write in
#               every one of the 102 screen cases and the re-raise in NONE of them.  So
#               the phase owes probes, and they are a forced deferral driven identically
#               into both binaries, with two controls.
set -eu

work=${1:?usage: zero36-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero36-check.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"
before_lines=$(cat "$state/input-lines")

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")

# The reproducible build of the OUTPUT, the controls, the instrument and the forced
# probes are written first and waited for where each is used.  Every one of them is this
# phase's own product, or the source it was handed, with ONE thing changed.
# shellcheck disable=SC2086
( SOURCE_DATE_EPOCH=0 gcc $cflags $ldflags -o "$tmp/new" "$f" ) &
pid_new=$!
python3 - "$f" "$state/old.c" "$tmp" <<'PY'
import re
import sys

TAG = 'noclib'
t = open(sys.argv[1], errors='surrogateescape').read()
old = open(sys.argv[2], errors='surrogateescape').read()
out = sys.argv[3]

PROTO = 'static void host_raise(int sig);'
if t.count(PROTO + '\n') != 1:
    sys.exit('  %-12s the output does not hold `%s` exactly once' % (TAG, PROTO))

# c1 -- the prototype DELETED.  It must not compile: that is what says the declaration is
# load-bearing rather than decorative, and it is the control for the ordering section.
c1 = t.replace(PROTO + '\n', '', 1)

# c2 -- `static` off the PROTOTYPE only.  A hard error against the static definition.
c2 = t.replace(PROTO + '\n', PROTO[len('static '):] + '\n', 1)

# c3 -- `static` off the prototype AND the definition.  THE SILENT HALF: it builds, and
# one more symbol becomes external.
m = re.search(r'^    static (void)\n(host_raise\()', c2, re.M)
if not m:
    sys.exit('  %-12s `host_raise` is not defined in the `    static <type>` shape, so '
             'c3 would not be a control' % TAG)
c3 = c2[:m.start()] + '    ' + m.group(1) + '\n' + m.group(2) + c2[m.end():]


def one(text, s, what):
    if text.count(s) != 1:
        sys.exit('  %-12s `%s` is not in that source exactly once, so a control built '
                 'from it would not be one' % (TAG, what))
    return s


# THE TWO CONTROLS ON THE LINE THIS PHASE DELETES, both built from the INPUT, because the
# line is not in the output to change.
#   cml  -- the write replaced by `return FAIL;`.  THE SAME LINE, replaced rather than
#           removed: if the corpus never executed it, nothing would move.  It must move
#           every record.
#   cpid -- the write kept and its VALUE changed.  b0_pid has no reader, so this must
#           move nothing, and that is `write-only` measured rather than argued.
WRITE = one(old, '        long_to_char(mch_get_pid(), b0p->b0_pid);\n',
            "ml_open()'s write of b0_pid")
ctl = {
    'cml': old.replace(WRITE, '        return FAIL;\n', 1),
    'cpid': old.replace(WRITE, '        long_to_char(0x5a5a5a5aL, b0p->b0_pid);\n', 1),
}

# THE INSTRUMENT, on the INPUT, because only the input still has both halves of this
# phase in it.  Three counters and a line to stderr from host_exit(), which every case
# reaches: the write this phase deletes, every entry to vim_handle_signal(), and the
# re-raise this phase moves.  NOTHING above the boundary calls libc here -- the counters
# are plain increments and the printing is done below the boundary, where <unistd.h> is.
# Phase 30's check learned that the hard way (`apart 30 35`): a check that CALLS libc
# from above the boundary is a dependency on the core still declaring it, and from this
# phase the core declares none.
INSTR = '''static long probe_b0, probe_vhs, probe_raise;

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
    write(2, "PROBE b0=", 9);
    probe_num(probe_b0);
    write(2, " vhs=", 5);
    probe_num(probe_vhs);
    write(2, " raise=", 7);
    probe_num(probe_raise);
    write(2, "\\n", 1);
}

'''
EXIT = one(old, '    static void\nhost_exit(int r)\n{\n', 'host_exit()')
RERAISE = one(old, 'kill(getpid(), got_signal);', "vim_handle_signal()'s re-raise")
VHS = one(old, 'vim_handle_signal(int sig)\n{\n', "vim_handle_signal()'s head")
# The counters are file scope and must be declared above their FIRST use, which is in
# ml_open(); the two printing helpers sit at the bottom beside host_exit(), which is
# where <unistd.h> is in scope.
DECLS = 'static long probe_b0, probe_vhs, probe_raise;\n\n'
if 'probe_b0' in old:
    sys.exit('  %-12s the input already says `probe_b0`' % TAG)
p = old.replace('    static int\nml_open(buf_T *buf)\n{\n',
                DECLS + '    static int\nml_open(buf_T *buf)\n{\n', 1)
if p == old:
    sys.exit('  %-12s ml_open() is not defined in this tree\'s shape' % TAG)
p = p.replace(WRITE, '        probe_b0++;\n' + WRITE, 1)
p = p.replace(VHS, VHS + '    probe_vhs++;\n', 1)
p = p.replace(RERAISE, 'probe_raise++;\n                                 ' + RERAISE, 1)
p = p.replace(EXIT, INSTR.replace(DECLS, '', 1) + EXIT + '    probe_dump();\n', 1)
ctl['probe'] = p

# THE FORCED PROBE, the same two statements appended to mch_init() in BOTH sources.  The
# corpus cannot reach the deferral -- the instrument above is what says so -- so the
# phase drives it by hand: vim_handle_signal(SIGTERM) with `blocked` still TRUE records
# the signal and returns FALSE, and vim_handle_signal(-2) unblocks and re-raises it.
# That is exactly the path `kill(getpid(), got_signal)` was on, and the path
# `host_raise(got_signal)` is on now.
INIT = '    out_flush();\n\n    musl_host_init();\n\n}\n'
FORCE = ('    out_flush();\n\n    musl_host_init();\n\n'
         '    (void)vim_handle_signal(SIGTERM);\n    (void)vim_handle_signal(-2);\n\n}\n')
forced = {}
for side, text in (('in', old), ('out', t)):
    one(text, INIT, 'mch_init()\'s tail')
    base = text.replace(INIT, FORCE, 1)
    call = 'kill(getpid(), got_signal);' if side == 'in' else 'host_raise(got_signal);'
    one(base, call, 'the re-raise in the %sput' % side)
    forced['pf' + side] = base
    # drop -- the re-raise deleted.  The deferred signal is simply lost, and the editor
    # does NOT die of it: the control that says the probe reaches the re-raise at all.
    forced['pf%s_drop' % side] = base.replace(call, '', 1)
    # hup -- the re-raise given SIGHUP instead of the signal that was deferred.  The
    # control that says the ARGUMENT crosses and not merely the call.
    forced['pf%s_hup' % side] = base.replace(call, call.replace('got_signal', 'SIGHUP'), 1)

variants = [('c1', c1, t), ('c2', c2, t), ('c3', c3, t)] \
    + [(k, v, old) for k, v in sorted(ctl.items())] \
    + [(k, v, old if 'in' in k else t) for k, v in sorted(forced.items())]
for name, text, base in variants:
    if text == base:
        sys.exit('  %-12s the variant %s changed nothing, so it would not be a control'
                 % (TAG, name))
    open('%s/%s.c' % (out, name), 'w', errors='surrogateescape').write(text)
print('  %-12s eleven variants written: c1 the prototype DELETED, c2 `static` off it, c3 '
      '`static` off it AND the definition; cml the deleted line replaced by `return '
      'FAIL;` and cpid the same line writing a constant, both on the INPUT; probe, the '
      'input with a counter on the write, on vim_handle_signal and on the re-raise; and '
      'six forced-deferral binaries, the input and the output each plain, with the '
      're-raise dropped, and with the re-raise given the wrong signal' % TAG)
PY
# c1 and c2 are expected to FAIL, so their status is discarded here rather than by
# `wait`, which would take `set -e` with it.
( gcc -O0 -fno-stack-protector -fsyntax-only "$tmp/c1.c" 2>"$tmp/e.c1" || true ) &
pid_c1=$!
( gcc -O0 -fno-stack-protector -fsyntax-only "$tmp/c2.c" 2>"$tmp/e.c2" || true ) &
pid_c2=$!
( gcc -c -O0 -fno-stack-protector -o "$tmp/c3.o" "$tmp/c3.c" 2>"$tmp/e.c3" || true ) &
pid_c3=$!
for v in cml cpid probe pfin pfout pfin_drop pfout_drop pfin_hup pfout_hup; do
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

TAG = 'noclib'
new = open(sys.argv[1], errors='surrogateescape').read()
old = open(sys.argv[2], errors='surrogateescape').read()
before_lines = int(sys.argv[3])
fail = []
NL, OL = new.split('\n'), old.split('\n')

DECL = re.compile(r'^(?!static |typedef |static_assert)[A-Za-z_][\w *]*\**\w+\([^;]*\);$')
GO = ['int getpid(void);', 'int kill(int pid, int sig);']


def mentions(text, name):
    return len(re.findall(r'\b%s\b' % name, text))


def halves(lines):
    """The core and the host, split at the first `#include` and nowhere else."""
    d = [i for i, l in enumerate(lines) if re.match(r'^ *# *', l)]
    if len(d) != 11 or d != list(range(d[0], d[0] + 11)) \
            or any(not re.match(r'^#include <[A-Za-z0-9_/.]+>$', lines[i]) for i in d):
        return None, None, None
    return '\n'.join(lines[:d[0]]), '\n'.join(lines[d[0]:]), d[0]


def body(lines, name):
    """A definition's own lines, in this tree's one shape."""
    h = [i for i, l in enumerate(lines)
         if re.match(r'^%s\s*\(' % name, l) and i + 1 < len(lines) and lines[i + 1] == '{']
    if len(h) != 1:
        return None
    e = h[0]
    while e < len(lines) and lines[e] != '}':
        e += 1
    return lines[h[0] - 1:e + 1] if e < len(lines) else None


ocore, ohost, obound = halves(OL)
ncore, nhost, nbound = halves(NL)
if ocore is None or ncore is None:
    sys.exit('  %-12s the eleven `#include` directives are not eleven consecutive lines '
             'in the %s -- the first `#include` IS the boundary and nothing else marks '
             'it' % (TAG, 'input' if ocore is None else 'output'))

# THE ARITHMETIC, AND IT IS A PARTITION OF THE INPUT AND NOT A COUNT OF IT.  Above the
# boundary every mention of each name is a call-shaped token, and each ends at 0; below
# it `kill` gains the one host_raise() makes and `getpid` gains two, its first.  How many
# there were is read off the INPUT here, exactly as the edit reads it.
for name, ocore_n, nhost_n, why in (
        ('getpid', None, 1, 'mch_get_pid()\'s body and the re-raise; and NOTHING below '
                            'the boundary said it before'),
        ('kill', None, 2, 'the re-raise; and musl_suspend()\'s `kill(0, SIGTSTP)` below '
                          'the boundary already did')):
    occ = len(re.findall(r'\b%s\b' % name, ocore))
    paren = len(re.findall(r'(?<!\w)%s\(' % name, ocore))
    if occ != paren or paren < 2:
        fail.append('the INPUT has %d mentions of `%s` above the boundary of which %d '
                    'are call-shaped, and this phase needs every one to be the '
                    'declaration or a call, with at least one call -- %s'
                    % (occ, name, paren, why))
        continue
    if mentions(ncore, name) != 0:
        fail.append('`%s` still has %d mentions above the boundary, and the phase takes '
                    'every one' % (name, mentions(ncore, name)))
    if mentions(nhost, name) != nhost_n:
        fail.append('`%s` ends at %d mentions below the boundary, expected %d -- %s'
                    % (name, mentions(nhost, name), nhost_n, why))
n_getpid = len(re.findall(r'(?<!\w)getpid\(', ocore))
n_kill = len(re.findall(r'(?<!\w)kill\(', ocore))

# `getpid` IS AVOIDED AND `kill` IS MOVED, and the difference is the shape of the phase.
for name, o, n, why in (
        ('mch_get_pid', 3, 0, 'its definition, its forward declaration and its one call '
                              'site -- the edit takes the first, the sweep the second, '
                              'and the third is the write'),
        ('b0_pid', 2, 0, 'its declaration and the ONE write, with no read anywhere: the '
                         'edit takes the write and tools/deadfields.py the field'),
        ('host_raise', 0, 3, 'a prototype, the one call site it takes over from the '
                             're-raise, and a definition')):
    if mentions(old, name) != o or mentions(new, name) != n:
        fail.append('`%s` goes from %d mentions to %d and this phase was written against '
                    '%d -> %d -- %s'
                    % (name, mentions(old, name), mentions(new, name), o, n, why))

# THE BLOCK, WHICH IS WHAT THIS PHASE IS FOR.  Found in the input the way the edit found
# it, and the output's is required to be that run minus exactly the two.
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
    if len(block_before) - len(block_after) != 2:
        fail.append('the input\'s block of ordinary declarations does not hold both of '
                    'this phase\'s lines: %s' % ' / '.join(block_before))
    have = [l for i, l in enumerate(NL[:nbound])
            if DECL.match(l) and (NL[i - 1] == '' or DECL.match(NL[i - 1]))]
    if have != block_after:
        fail.append('the ordinary declarations above the boundary are %s and the '
                    'input\'s block minus the two is %s'
                    % (' / '.join(have) or 'none', ' / '.join(block_after) or 'none'))

# THE FOLD THAT WAS SURVEYED AND NOT TAKEN.  deathtrap() must be identical in and out;
# vim_handle_signal() must differ in exactly one line, the re-raise.
od, nd = body(OL, 'deathtrap'), body(NL, 'deathtrap')
if od is None or nd is None:
    fail.append('deathtrap() is not defined exactly once in one of the two files')
elif od != nd:
    fail.append('deathtrap() is NOT identical in and out, and this phase surveyed the '
                '`entered` fold and did not take it: %d lines in, %d out'
                % (len(od), len(nd)))
ov, nv = body(OL, 'vim_handle_signal'), body(NL, 'vim_handle_signal')
if ov is None or nv is None or len(ov) != len(nv):
    fail.append('vim_handle_signal() is not the same shape in and out')
else:
    diff = [i for i in range(len(ov)) if ov[i] != nv[i]]
    if len(diff) != 1 or 'kill(getpid(), ' not in ov[diff[0]] \
            or 'host_raise(' not in nv[diff[0]]:
        fail.append('vim_handle_signal() differs in %d lines and this phase changes '
                    'exactly one, the re-raise: %s'
                    % (len(diff), ' / '.join('%r -> %r' % (ov[i], nv[i])
                                             for i in diff[:3])))

# THE SHAPE OF THE FILE.  Nothing here is a command, an option or a directive, and the
# counts are the input's rather than numbers written down.
sys.path.insert(0, 'tools')
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
if sum(1 for k in range(1, len(NL)) if NL[k] == '' and NL[k - 1] == ''):
    fail.append('there is a run of two blank lines, which canon.sh should have taken')

# THE LINE ARITHMETIC, every term read off the INPUT and the OUTPUT and none of them
# written down.  IN, above the boundary: one prototype.  OUT, all above the boundary:
# ml_open()'s write, mch_get_pid()'s definition with the blank after it, the block (and
# its trailing blank, because it empties), and the two lines the SWEEP took -- the
# `static long mch_get_pid(void);` prototype and the `b0_pid` field.  BELOW the boundary:
# host_raise()'s definition with the blank after it.
gp = body(OL, 'mch_get_pid')
hr = body(NL, 'host_raise')
sweptaway = [i for i, l in enumerate(OL)
             if re.match(r'^static [\w *]+mch_get_pid\(.*\);$', l)
             or re.match(r'^\s*char_u\s+b0_pid\[\d+\];$', l)]
if gp is None or hr is None or len(sweptaway) != 2:
    fail.append('mch_get_pid() is not defined exactly once in the input (%s), or '
                'host_raise() in the output (%s), or the two lines the sweep takes are '
                'not exactly two in the input (%d)'
                % (gp is not None, hr is not None, len(sweptaway)))
else:
    above_in = 1
    above_out = 1 + (len(gp) + 1) + (2 if block_after else len(block_before) + 1) \
        + len(sweptaway)
    below_in = len(hr) + 1
    if len(NL) - 1 != before_lines + above_in + below_in - above_out \
            or len(OL) - 1 != before_lines:
        fail.append('the file is %d lines and the input was %d (%d recorded) -- expected '
                    '%d: %d in above the boundary and %d below, %d out above it'
                    % (len(NL) - 1, len(OL) - 1, before_lines,
                       before_lines + above_in + below_in - above_out, above_in,
                       below_in, above_out))
    if nbound != obound - (above_out - above_in):
        fail.append('the boundary moved from line %d to line %d and every one of the %d '
                    'lines that go and the %d that arrives above it says it should move '
                    'up by %d' % (obound + 1, nbound + 1, above_out, above_in,
                                  above_out - above_in))

if fail:
    for line in fail:
        print('  %-12s %s' % (TAG, line))
    sys.exit(1)
print('  %-12s ABOVE THE BOUNDARY both names go: `getpid` %d -> 0 (its declaration and '
      '%d calls, one in mch_get_pid() and one in the re-raise) and `kill` %d -> 0 (its '
      'declaration and %d call, the re-raise).  BELOW IT `getpid` 0 -> 1 and `kill` 1 -> '
      '2, both in host_raise(); so ONE of the two is MOVED and the other is AVOIDED '
      'outright -- `mch_get_pid` %d -> 0 and `b0_pid` %d -> 0, a write-only field and the '
      'function that fed it.  `host_raise` 0 -> 3'
      % (TAG, n_getpid, n_getpid - 1, n_kill, n_kill - 1,
         len(re.findall(r'\bmch_get_pid\b', old)), len(re.findall(r'\bb0_pid\b', old))))
print('  %-12s THE CORE\'S BLOCK OF ORDINARY DECLARATIONS -- the libc it names, the one '
      'run above the boundary that is not `static` -- is %d lines and was %d: %s'
      % ('', len(block_after), len(block_before),
         ('%s remain, and each belongs to a phase of its own'
          % ' '.join(re.sub(r'^.*?\**(\w+)\(.*$', r'\1', l) for l in block_after))
         if block_after else
         'IT IS EMPTY.  The core names no libc function at all'))
print('  %-12s THE FOLD WAS SURVEYED AND NOT TAKEN: deathtrap() is byte-identical in and '
      'out, %d lines either side, and vim_handle_signal() differs in exactly one line.  '
      '`entered` has three reachable values since phase 17 and every one of them is read '
      '-- 0 by the entry guard, 1 and 2 by BOTH the double-signal arm and `v_dying = '
      'entered`, which getout() tests -- so there is no fold to take and the phase says '
      'so here rather than leaving it to be believed' % ('', len(od)))
print('  %-12s %d -> %d lines, %d fewer; cmdnames[] %d and options[] %d unmoved; the '
      'eleven #includes still eleven consecutive lines, at %d where they were %d'
      % ('', before_lines, len(NL) - 1, before_lines - (len(NL) - 1), n_new, opts(new),
         nbound + 1, obound + 1))
PY

# --- 2. THE CLAIM: the cut, and what the core needs from outside itself -------------------
# zero.mk's own rule, one awk clause and no judgement, on the INPUT and on the OUTPUT.
editorcut() {
    awk '/^ *# *include / { exit } { a[NR] = $0; if (NF) last = NR } \
         END { for (i = 1; i <= last; i++) print a[i] }' "$1" > "$2"
    if grep -q '^ *#' "$2"; then
        echo "  noclib       the cut of $1 holds a directive, so it found the wrong line"
        exit 1
    fi
    if [ "$(grep -c '' "$2")" -le 70000 ]; then
        echo "  noclib       the cut of $1 is $(grep -c '' "$2") lines, and zero.mk's floor is 70,000 -- a cut that found line 1 would be empty and every check below would pass on nothing"
        exit 1
    fi
    gcc -c -O0 -fno-stack-protector -o "$2.o" "$2" 2>"$2.log" || true
    grep -c 'error:' "$2.log" > "$2.err" || true
    sed -n "s/.*warning: '\\([A-Za-z_][A-Za-z0-9_]*\\)' used but never defined.*/\\1/p" "$2.log" | sort > "$2.names"
}
editorcut "$state/old.c" "$tmp/cut-old.c"
editorcut "$f" "$tmp/cut-new.c"
for w in old new; do
    if [ "$(cat "$tmp/cut-$w.c.err")" != 0 ] || [ ! -f "$tmp/cut-$w.c.o" ]; then
        echo "  noclib       the $w cut does not compile: $(cat "$tmp/cut-$w.c.err") errors"
        grep 'error:' "$tmp/cut-$w.c.log" | head -3 | sed 's/^/               /'
        exit 1
    fi
    if [ "$(grep -c 'warning:' "$tmp/cut-$w.c.log")" != "$(grep -c '' "$tmp/cut-$w.c.names")" ]; then
        echo "  noclib       the $w cut has a warning that is not a 'used but never defined':"
        grep 'warning:' "$tmp/cut-$w.c.log" | grep -v 'used but never defined' | head -3 | sed 's/^/               /'
        exit 1
    fi
    if [ -n "$(nm --extern-only --defined-only "$tmp/cut-$w.c.o")" ]; then
        echo "  noclib       the $w cut DEFINES an external symbol, and the core defines none -- main is the host's:"
        nm --extern-only --defined-only "$tmp/cut-$w.c.o" | head -3 | sed 's/^/               /'
        exit 1
    fi
done
head -c "$(stat -c%s "$tmp/cut-new.c")" "$f" > "$tmp/prefix.c"
cmp -s "$tmp/prefix.c" "$tmp/cut-new.c" || { echo "  noclib       the cut is not a byte prefix of zero-vim.c"; exit 1; }
arrived=$(comm -13 "$tmp/cut-old.c.names" "$tmp/cut-new.c.names" | tr '\n' ' ')
left=$(comm -23 "$tmp/cut-old.c.names" "$tmp/cut-new.c.names" | tr '\n' ' ')
if [ "$arrived" != "host_raise " ] || [ -n "$left" ]; then
    echo "  noclib       THE CUT'S BOUNDARY SET DID NOT MOVE AS THIS PHASE CLAIMS."
    echo "               arrived: ${arrived:-nothing}"
    echo "               left:    ${left:-nothing}"
    exit 1
fi
echo "  noclib       THE CUT -- \`make editor.c\`'s own rule, and a byte prefix of the file -- is $(grep -c '' "$tmp/cut-old.c") lines in and $(grep -c '' "$tmp/cut-new.c") out, 0 errors either side, and its warning set, which is the core -> host interface, goes from $(grep -c '' "$tmp/cut-old.c.names") names to $(grep -c '' "$tmp/cut-new.c.names"): host_raise ARRIVES and nothing leaves.  Neither cut defines an external symbol -- \`main\` is below the boundary and is the host's"
# AND THE CLAIM ITSELF, which the warning set CANNOT make: a bare `extern` declaration is
# invisible to -fsyntax-only, so what says the core calls no libc is `nm -u` of an object
# of the cut ALONE, partitioned against the definitions below the boundary.  The same
# computation on the INPUT is the control, and it finds exactly two.
python3 - "$f" "$tmp/cut-new.c.o" "$state/old.c" "$tmp/cut-old.c.o" <<'PY'
import re
import subprocess
import sys

TAG = 'noclib'


def below(path):
    """Every function DEFINED below the boundary, in this tree's one shape."""
    L = open(path, errors='surrogateescape').read().split('\n')
    b = [i for i, l in enumerate(L) if re.match(r'^ *# *', l)][0]
    out = set()
    for i in range(b, len(L) - 1):
        m = re.match(r'^([A-Za-z_]\w*)\s*\(', L[i])
        if m and L[i + 1] == '{':
            out.add(m.group(1))
    return out


def needs(obj):
    r = subprocess.run(['nm', '-u', obj], capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit('  %-12s nm -u failed on %s' % (TAG, obj))
    return sorted(l.split()[-1] for l in r.stdout.splitlines() if l.strip())


res = {}
for side, src, obj in (('new', sys.argv[1], sys.argv[2]),
                       ('old', sys.argv[3], sys.argv[4])):
    u = needs(obj)
    if len(u) < 5:
        sys.exit('  %-12s the %s cut needs %d names from outside itself, and an editor '
                 'core that asked its host for almost nothing would mean nm read the '
                 'wrong object' % (TAG, side, len(u)))
    d = below(src)
    res[side] = (u, [x for x in u if x not in d])
if res['old'][1] != ['getpid', 'kill']:
    sys.exit('  %-12s THE CONTROL DID NOT SHOW.  The identical computation on the INPUT '
             'must find exactly `getpid` and `kill` outside this file; it finds %s -- so '
             'the emptiness measured on the output would be two numbers agreeing rather '
             'than a phase' % (TAG, res['old'][1] or 'nothing'))
if res['new'][1]:
    sys.exit('  %-12s THE CORE STILL NEEDS %s FROM OUTSIDE THIS FILE, and the claim is '
             'not writable: every name the cut needs must be DEFINED below the boundary'
             % (TAG, ' '.join(res['new'][1])))
print('  %-12s THE CLAIM, AND IT IS MEASURED FROM THE CUT AND NOT FROM THE BLOCK.  `nm '
      '-u` on an object of the cut ALONE -- the core, and nothing of the host -- is the '
      'set of names the core needs from outside itself: %d names in and %d out.  EVERY '
      'ONE of the %d is defined BELOW the boundary in this same file, computed from the '
      'text and not listed here; the input\'s %d are not, and they are `%s` -- so the '
      'emptiness is a phase and not two numbers agreeing.'
      % (TAG, len(res['old'][0]), len(res['new'][0]), len(res['new'][0]),
         len(res['old'][1]), '` and `'.join(res['old'][1])))
print('  %-12s IT IS EMPTY.  The core names no libc function at all: above the first '
      '`#include` there is not one declaration that is not `static`, and every outward '
      'call the editor makes is a `musl_` or a `host_` defined below that line.  %s'
      % ('', ' '.join(res['new'][0])))
PY

# --- 3. the vocabulary the core has left ---------------------------------------------------
python3 tools/zhostonly.py "$f"
python3 - "$f" "$state/old.c" <<'PY'
import re
import sys

sys.path.insert(0, 'tools')
import zhostonly

TAG = 'noclib'
res = {}
for side, path in (('new', sys.argv[1]), ('old', sys.argv[2])):
    L = open(path, errors='surrogateescape').read().split('\n')
    b = [i for i, l in enumerate(L) if re.match(r'^ *# *', l)][0]
    hits = {}
    for i in range(b):
        if L[i].startswith('#'):
            continue
        for m in zhostonly.VOCAB.finditer(zhostonly.strip_strings(L[i])):
            hits.setdefault(re.sub(r'[ \t]+', ' ', m.group(0)), []).append(i + 1)
    res[side] = hits
if sorted(res['old']) != ['SIGHUP', 'SIGTERM', 'getpid', 'kill']:
    sys.exit('  %-12s the INPUT\'s core says %s of tools/zhostonly.py\'s vocabulary, and '
             'this phase was written against SIGHUP SIGTERM getpid kill'
             % (TAG, ' '.join(sorted(res['old'])) or 'nothing'))
if sorted(res['new']) != ['SIGHUP', 'SIGTERM']:
    sys.exit('  %-12s the core still says %s of the host\'s vocabulary above the '
             'boundary' % (TAG, ' '.join(sorted(res['new']))))
print('  %-12s AND THE CORE\'S WHOLE REMAINING VOCABULARY OF THE HOST IS TWO WORDS.  '
      'Above the first `#include`, tools/zhostonly.py\'s host vocabulary now matches only '
      '`SIGHUP` (%d times) and `SIGTERM` (%d) -- the two deadly signals the editor NAMES '
      'because it PRINTS them, in signal_info[], in deathtrap\'s own test and in the '
      'core\'s `enum`.  The input said `getpid` %d times and `kill` %d as well, and those '
      'were the only mentions of any host word in the core that were not a message'
      % (TAG, len(res['new']['SIGHUP']),
         len(res['new']['SIGTERM']), len(res['old']['getpid']), len(res['old']['kill'])))
PY

# --- 4. declaration before use, and the control that says the declaration is needed -------
wait $pid_c1
python3 - "$f" "$tmp/e.c1" <<'PY'
import re
import sys

TAG = 'noclib'
NL = open(sys.argv[1], errors='surrogateescape').read().split('\n')
err = open(sys.argv[2], errors='surrogateescape').read()
bound = [i for i, l in enumerate(NL) if re.match(r'^ *# *', l)][0]
hb = [i for i, l in enumerate(NL)
      if l.startswith('static volatile sig_atomic_t host_winch_pending')]
he = [i for i, l in enumerate(NL) if l.startswith('musl_suspend(')]
if len(hb) != 1 or len(he) != 1:
    sys.exit('  %-12s the host region does not begin and end exactly once' % TAG)
end = he[0]
while end < len(NL) and NL[end] != '}':
    end += 1

name = 'host_raise'
proto = [i for i, l in enumerate(NL) if re.match(r'^static [\w *]*%s\(.*\);$' % name, l)]
defn = [i for i, l in enumerate(NL)
        if l.startswith(name + '(') and i + 1 < len(NL) and NL[i + 1] == '{']
uses = [i for i, l in enumerate(NL) if re.search(r'(?<!\w)%s\(' % name, l)
        and i not in proto and i not in defn]
if len(proto) != 1 or len(defn) != 1 or len(uses) != 1:
    sys.exit('  %-12s `%s` has %d prototypes, %d definitions and %d call sites in the '
             'output' % (TAG, name, len(proto), len(defn), len(uses)))
if not (proto[0] < uses[0] < defn[0] and bound < defn[0] and hb[0] <= defn[0] <= end):
    sys.exit('  %-12s `%s`: prototype at %d, call at %d, definition at %d, boundary at '
             '%d, host region %d-%d -- the prototype must be ABOVE the call, the '
             'definition BELOW it, below the boundary AND inside the host region, '
             'because its body says `kill` and `getpid` and tools/zhostonly.py reads '
             'that region and no other'
             % (TAG, name, proto[0] + 1, uses[0] + 1, defn[0] + 1, bound + 1, hb[0] + 1,
                end + 1))
if not re.search(r'\berror\b', err) or name not in err:
    sys.exit('  %-12s THE CONTROL c1 DID NOT SHOW: with the prototype line DELETED the '
             'file must fail to compile and must name `%s`.  Without that the line '
             'numbers above are a statement about a file and not about a program'
             % (TAG, name))
print('  %-12s `%s`: prototype line %d, one call site at line %d, definition line %d, '
      'which is below the boundary at %d and inside the %d-line host region.  AND THE '
      'DECLARATION IS LOAD-BEARING: the same output with that one line deleted gives %d '
      'errors naming it'
      % (TAG, name, proto[0] + 1, uses[0] + 1, defn[0] + 1, bound + 1, end + 1 - hb[0],
         len(re.findall(r'error:', err))))
PY

# --- 5. linkage, WHICH IS THE ASSERTION THAT MATTERS MOST -----------------------------------
wait $pid_c2
wait $pid_c3
if ! grep -q "static declaration of 'host_raise' follows non-static declaration" "$tmp/e.c2"; then
    echo "  noclib       THE CONTROL c2 DID NOT SHOW.  With \`static\` off the PROTOTYPE and"
    echo "               left on the definition, gcc must refuse:"
    sed 's/^/               /' "$tmp/e.c2" | head -4
    exit 1
fi
if [ -s "$tmp/e.c3" ] || [ ! -f "$tmp/c3.o" ]; then
    echo "  noclib       the control c3 did not build, and the point of it is that it DOES:"
    sed 's/^/               /' "$tmp/e.c3" | head -4
    exit 1
fi
c3_ext=$(nm --extern-only --defined-only "$tmp/c3.o" | awk '{print $NF}' | sort | tr '\n' ' ')
if [ "$c3_ext" != "host_raise main " ]; then
    echo "  noclib       THE CONTROL c3 DID NOT SHOW.  With \`static\` off the prototype AND"
    echo "               the definition the object must define host_raise and main; it"
    echo "               defines: $c3_ext"
    exit 1
fi
echo "  noclib       THE \`static\` TRAP, BOTH HALVES, MEASURED ON THIS PHASE'S OWN OUTPUT: with the keyword off the PROTOTYPE gcc REFUSES -- \"static declaration of 'host_raise' follows non-static declaration\" -- and with it off the prototype AND the definition the build is SILENT and the object defines $c3_ext.  The second is the mistake this phase could have made without anything else noticing, and tools/phasecheck.sh below is what catches it"

# --- 6. the compile, the linkage and the libc surface ---------------------------------------
# NOTHING IS FREED AND THE PHASE SAYS SO AS AN EQUALITY.  Taking the last core mention of
# `getpid` and `kill` cannot move `nm -u`: host_raise() calls both, and a symbol leaves
# when its last caller leaves the FILE.  Phase 28 is the contrast -- it freed
# `gettimeofday` because the last caller went with it.
cp "$state/symbols/undefined" "$tmp/before.u"
tools/phasecheck.sh "$work" "$f" "$state/symbols"
if ! cmp -s "$tmp/before.u" .cache/symbols/last/undefined; then
    echo "  noclib       the libc surface moved, and NEITHER HALF OF THIS PHASE CAN MOVE IT --"
    echo "               host_raise() calls kill() and getpid() where vim_handle_signal() did,"
    echo "               and mch_get_pid()'s getpid() was one of two:"
    echo "               gone: $(comm -23 "$tmp/before.u" .cache/symbols/last/undefined | tr '\n' ' ')"
    echo "               came: $(comm -13 "$tmp/before.u" .cache/symbols/last/undefined | tr '\n' ' ')"
    exit 1
fi
for s in getpid kill; do
    grep -qx "$s" .cache/symbols/last/undefined || {
        echo "  noclib       \`$s\` is no longer an undefined symbol, and it must still be one:"
        echo "               host_raise() calls both, and musl_suspend() calls kill as well."
        exit 1
    }
done
echo "  noclib       symbols $(cat .cache/symbols/last/before) -> $(cat .cache/symbols/last/after), and the set is IDENTICAL as a cmp -- nothing left and nothing arrived.  \`getpid\` and \`kill\` are both still there, which is the point: one of them MOVED into the host and the other was AVOIDED, and the avoided one had a second call site -- the re-raise -- that moved rather than going.  An undefined symbol leaves only when its last caller leaves the FILE.  main is still the only external symbol"

# --- 7. the binary, and canon -----------------------------------------------------------------
wait $pid_canon
if ! cmp -s "$tmp/canon.c" "$f"; then
    echo "  noclib       tools/canon.sh CHANGED THE OUTPUT, and it must be a no-op:"
    diff "$f" "$tmp/canon.c" | head -6 | sed 's/^/               /'
    exit 1
fi
echo "  noclib       tools/canon.sh is a NO-OP on the output ($(sed -n 's/.*canon *//p' "$tmp/canon.log" | head -1))"

make -C "$work" clean >/dev/null 2>&1 || true
[ -e "$work/zero-vim" ] && { echo "  build        the clean did not remove zero-vim, so a 'rebuild' below could be no rebuild at all"; exit 1; }
if ! make -C "$work" >/dev/null 2>&1; then
    echo "  build        FAILED -- rerun by hand: make -C $work"
    exit 1
fi
bin="$work/zero-vim"
echo "  build        ok, $before_lines -> $(grep -c '' "$f") lines, $(stat -c%s "$bin") bytes"

wait $pid_new || { echo "  noclib       the reproducible build of the output failed"; exit 1; }
old_size=$(stat -c%s "$state/old")
new_size=$(stat -c%s "$tmp/new")
if [ "$new_size" -lt 500000 ] || [ "$old_size" -lt 500000 ]; then
    echo "  noclib       one of the two binaries is $old_size / $new_size bytes, which is not an editor"
    exit 1
fi
if [ "$new_size" != "$(stat -c%s "$bin")" ]; then
    echo "  noclib       the reproducible build is $new_size bytes and make produced $(stat -c%s "$bin"): the two differ by more than a timestamp, so nothing below would be about this boundary"
    exit 1
fi
if cmp -s "$state/old" "$tmp/new"; then
    echo "  noclib       THE BINARY IS BYTE-IDENTICAL, and it must not be: a statement goes,"
    echo "               a function goes, a call site becomes a call into another function"
    echo "               of this file and a definition arrives."
    exit 1
fi
echo "  noclib       the binary is $old_size bytes in and $new_size out, $(cmp -l "$state/old" "$tmp/new" | wc -l) of them differing.  Both are MEASUREMENTS and neither is aimed for: a function leaves, a definition arrives, and at -O0 a call to a static function in this file is not the instruction stream of a call to a libc symbol.  So this phase cannot use tier 1 of CLAUDE.md's verification table and does not pretend to; the evidence is the recording and the probes below"

# --- 8. THE EVIDENCE: two recordings, and two controls on the line this phase deletes ---------
rec() {
    tools/zrecord.sh "$2" "$3" "$tmp/REC-$1" >/dev/null 2>&1 &
    eval "pid_rec_$1=$!"
}
wait $pid_cml || { echo "  noclib       the control cml did not build:"; head -5 "$tmp/e.cml" | sed 's/^/               /'; exit 1; }
wait $pid_cpid || { echo "  noclib       the control cpid did not build:"; head -5 "$tmp/e.cpid" | sed 's/^/               /'; exit 1; }
rec old "$state/old" "$state/old.c"
rec new "$tmp/new" "$f"
rec cml "$tmp/cml" "$tmp/cml.c"
rec cpid "$tmp/cpid" "$tmp/cpid.c"
for pp in $pid_rec_old $pid_rec_new $pid_rec_cml $pid_rec_cpid; do
    wait "$pp" || { echo "  noclib       a recording failed"; exit 1; }
done
python3 - "$tmp" <<'PY'
import filecmp
import os
import sys

TAG = 'noclib'
tmp = sys.argv[1]


def files(d):
    out = []
    for root, _, names in os.walk(d):
        for n in names:
            out.append(os.path.relpath(os.path.join(root, n), d))
    return sorted(out)


base = files('%s/REC-old' % tmp)
if len(base) < 100:
    sys.exit('  %-12s a recording holds %d records, and a zero recording is 106 -- 102 '
             'screen cases and four sweeps.  A comparison of two things nothing wrote '
             'passes' % (TAG, len(base)))


def moved(which):
    d = '%s/REC-%s' % (tmp, which)
    if files(d) != base:
        sys.exit('  %-12s the recording of %s holds different records from the input\'s'
                 % (TAG, which))
    return [n for n in base
            if not filecmp.cmp('%s/REC-old/%s' % (tmp, n), '%s/%s' % (d, n),
                               shallow=False)]


same = moved('new')
if same:
    print('  %-12s THE RECORDING MOVED, in %d of %d records: %s'
          % (TAG, len(same), len(base), ' '.join(same[:8])))
    print('  %-12s This phase declares NOTHING.  A write nothing reads goes, and one '
          'libc call becomes a call into the host that makes the same libc call with '
          'the same signal.' % '')
    sys.exit(1)
m_cml = moved('cml')
m_cpid = moved('cpid')
if len(m_cml) != len(base):
    sys.exit('  %-12s THE CONTROL cml DID NOT SHOW: with the deleted line REPLACED by '
             '`return FAIL;` -- the same line, in the same place -- %d of %d records '
             'move and every one must.  If the corpus never executed that line, nothing '
             'below would be evidence' % (TAG, len(m_cml), len(base)))
if m_cpid:
    print('  %-12s a control that was MEASURED to move nothing moved something: cpid %d '
          'of %d.  It is reported here as a finding and not hidden'
          % (TAG, len(m_cpid), len(base)))
    sys.exit(1)
print('  %-12s THE RECORDING IS BYTE-IDENTICAL, all %d records -- 102 screen cases, '
      'every Ex command typed at `:`, every command line the parser may see, the four '
      'pty scenarios and the terminal table' % (TAG, len(base)))
print('  %-12s AND THE TWO CONTROLS ARE THE PHASE ITSELF, on the ONE line it deletes:'
      % '')
print('  %-12s   the same line replaced by `return FAIL;` moves %d of %d records.  So '
      'ml_open() runs and that statement is executed, and the empty diff above is not '
      'the corpus missing the code' % ('', len(m_cml), len(base)))
print('  %-12s   the same line writing a CONSTANT instead of the pid moves %d of %d.  '
      'That is `b0_pid is write-only` measured rather than argued: nothing in any build '
      'of zero-vim reads block zero back, because the swap file it belonged to is a disk '
      'format this editor has not had since the filesystem phases.  A control that moves '
      'nothing is REPORTED here and not quietly dropped' % ('', len(m_cpid), len(base)))
PY

# --- 9. THE PROBES: the corpus cannot see either half, measured, and then the forced pair ----
wait $pid_probe || { echo "  noclib       the instrumented build failed:"; head -5 "$tmp/e.probe" | sed 's/^/               /'; exit 1; }
for v in pfin pfout pfin_drop pfout_drop pfin_hup pfout_hup; do
    eval "wait \$pid_$v" || { echo "  noclib       the forced binary $v did not build:"; head -5 "$tmp/e.$v" | sed 's/^/               /'; exit 1; }
done
( python3 tools/zcases.py "$tmp/probe" "$tmp/SC-probe" >/dev/null 2>&1 ) &
pid_sc=$!
# THE FORCED SESSIONS.  The environment is emptied exactly as every harness empties it
# (CLAUDE.md): no $HOME, $VIM, $VIMRUNTIME or $XDG_CONFIG_HOME and no $VIMINIT or
# $EXINIT, so a real ~/.vimrc on the machine cannot reach them.
printf ':q!\r' > "$tmp/keys"
session() {
    rc=0
    ( cd "$tmp" && env -u VIMINIT -u EXINIT HOME= VIM= VIMRUNTIME= XDG_CONFIG_HOME= \
        TERM=xterm "./$1" < keys > "$1.out" 2> "$1.err" ) || rc=$?
    echo "$rc" > "$tmp/$1.rc"
}
for v in pfin pfout pfin_drop pfout_drop pfin_hup pfout_hup; do
    session "$v"
done
wait $pid_sc || { echo "  noclib       the screen corpus failed on the instrumented build"; exit 1; }
python3 - "$tmp" <<'PY'
import os
import re
import sys

TAG = 'noclib'
tmp = sys.argv[1]
base = sorted(os.listdir('%s/SC-probe' % tmp))
if len(base) != 102:
    sys.exit('  %-12s the screen corpus is %d cases and it is 102' % (TAG, len(base)))

fields = 'b0 vhs raise'.split()
tot = {k: 0 for k in fields}
cases = {k: 0 for k in fields}
seen = 0
for n in base:
    text = open('%s/SC-probe/%s' % (tmp, n), errors='surrogateescape').read()
    m = re.search(r'PROBE ' + ' '.join('%s=(\\d+)' % k for k in fields), text)
    if not m:
        continue
    seen += 1
    v = dict(zip(fields, (int(x) for x in m.groups())))
    for k in fields:
        tot[k] += v[k]
        cases[k] += 1 if v[k] else 0
if seen != 102:
    sys.exit('  %-12s the instrumented build marked %d of 102 cases, and it must mark '
             'every one: the counter is printed from host_exit(), which every case '
             'reaches' % (TAG, seen))
if cases['b0'] != 102 or tot['b0'] < 102:
    sys.exit('  %-12s the write this phase deletes runs in %d of 102 cases (%d times in '
             'all), and ml_open() is on the path of every buffer the editor opens -- a '
             'counter that small is not on the path' % (TAG, cases['b0'], tot['b0']))
if tot['raise']:
    sys.exit('  %-12s the re-raise fired %d times in the corpus, and this phase\'s '
             'probes were written because it fires NONE: no recorded case sends the '
             'editor a deadly signal, so `got_signal` is never set and the deferral '
             'never has anything to re-raise' % (TAG, tot['raise']))
print('  %-12s THE CORPUS CANNOT SEE EITHER HALF OF THIS PHASE, AND THAT IS MEASURED, '
      'and the two halves are invisible for OPPOSITE reasons.  An instrumented build of '
      'the INPUT, over all 102 screen cases and marking every one of them: the b0_pid '
      'write runs in %d of 102 cases, %d times in all -- it is on the path of every '
      'buffer the editor opens, and the recording still does not move, because nothing '
      'reads the field.  The RE-RAISE fires %d times, in %d cases: nothing in the corpus '
      'sends the editor a deadly signal, so `got_signal` is never set and the deferral '
      'has nothing to re-raise.  vim_handle_signal() itself is entered only %d times in '
      '%d cases -- REPORTED and not pinned, because this phase cannot move it: '
      'ui_inchar() calls it only around a wait longer than 100 ms, and a corpus whose '
      'stdin is a file of keystrokes almost never waits'
      % (TAG, cases['b0'], tot['b0'], tot['raise'], cases['raise'], tot['vhs'],
         cases['vhs']))
PY
python3 - "$tmp" <<'PY'
import sys

TAG = 'noclib'
tmp = sys.argv[1]


def got(v):
    out = open('%s/%s.out' % (tmp, v), 'rb').read()
    err = open('%s/%s.err' % (tmp, v), 'rb').read()
    rc = int(open('%s/%s.rc' % (tmp, v)).read())
    return out, err, rc


for kind, what in (('', 'the forced deferral'),
                   ('_drop', 'the re-raise DELETED'),
                   ('_hup', 'the re-raise given SIGHUP')):
    i, o = got('pfin' + kind), got('pfout' + kind)
    if i != o:
        sys.exit('  %-12s %s does not behave the same on the two binaries: in %d bytes '
                 'out / %d err / rc %d, out %d / %d / %d'
                 % (TAG, what, len(i[0]), len(i[1]), i[2], len(o[0]), len(o[1]), o[2]))
probe = got('pfin')
drop = got('pfin_drop')
hup = got('pfin_hup')
if b'Vim: Caught deadly signal TERM' not in probe[0] or b'Vim: Finished.' not in probe[0]:
    sys.exit('  %-12s the forced deferral did not reach deathtrap(): the screen does not '
             'carry `Vim: Caught deadly signal TERM`.  %r' % (TAG, probe[0][-90:]))
if probe[2] != 1:
    sys.exit('  %-12s the forced deferral exits %d and preserve_exit() ends in getout(1)'
             % (TAG, probe[2]))
if b'Caught deadly signal' in drop[0] or drop[0] == probe[0]:
    sys.exit('  %-12s THE CONTROL `drop` DID NOT SHOW: with the re-raise deleted the '
             'deferred signal must simply be lost and the editor must NOT die of it -- '
             'so the probe above would not be reaching the re-raise at all' % TAG)
if b'Vim: Caught deadly signal HUP' not in hup[0] or hup[0] == probe[0]:
    sys.exit('  %-12s THE CONTROL `hup` DID NOT SHOW: with the re-raise given SIGHUP '
             'instead of the signal that was deferred the editor must report HUP -- so '
             'the probe above would not be carrying the ARGUMENT across' % TAG)
print('  %-12s THE PROBE THIS PHASE THEREFORE OWES, and it is driven identically into '
      'BOTH binaries: two statements appended to mch_init(), `vim_handle_signal(SIGTERM)` '
      'with `blocked` still TRUE and then `vim_handle_signal(-2)`, which is exactly the '
      'deferral the corpus never reaches.  The input and the output agree in EVERY byte '
      'of stdout (%d), stderr (%d) and status (%d), and the screen carries `Vim: Caught '
      'deadly signal TERM` and `Vim: Finished.` -- so `host_raise(got_signal)` raises '
      'what `kill(getpid(), got_signal)` raised, on the same process, at the same moment'
      % (TAG, len(probe[0]), len(probe[1]), probe[2]))
print('  %-12s AND IT CAN FAIL, TWICE, identically on both binaries:' % '')
print('  %-12s   the re-raise DELETED -- the deferred signal is lost, the editor does '
      'NOT die of it and runs on to end of input: %d bytes against %d.  So the probe '
      'really does go through the line this phase rewrites'
      % ('', len(drop[0]), len(probe[0])))
print('  %-12s   the re-raise given SIGHUP instead of the signal that was deferred: the '
      'screen says `Caught deadly signal HUP`, %d bytes against %d.  So the ARGUMENT '
      'crosses the boundary and not merely the call' % ('', len(hup[0]), len(probe[0])))
PY

# tools/phaserun.sh runs tools/zerodelta.sh --phase 36 after this check, and this phase
# declares NOTHING: the corpus must not move at all.
