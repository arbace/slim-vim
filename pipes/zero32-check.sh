#!/bin/sh
# Zero phase 32, the check -- the clock crosses the boundary.
# See pipes/zero32-edit.sh, and ZERO-PLAN.md 4c.
#
# Usage: pipes/zero32-check.sh <work-dir> <state-dir>    (run from the repository root)
#
# Runs after pipes/zero32-edit.sh and the sweep tools/phaserun.sh runs between them, and
# reads nothing from the edit's shell -- only the work tree and the state directory.
# What the edit left there is `old.c`, the source this phase was HANDED, and `old`, that
# source built with SOURCE_DATE_EPOCH=0 and the boundary's own flags.
#
# WHAT IS CLAIMED, in eight parts:
#
#   ARITHMETIC  computed FROM THE INPUT: the core does not name `time` at all, the four
#               mentions it had having become none; `host_time` is 8 above the boundary
#               and 1 below; the libc prototype block loses exactly one line and keeps
#               every other entry; the core loses 7 lines and the host gains 7.
#   THE GUARANTEE
#               THE PART OF THIS PHASE THAT COULD SILENTLY REGRESS, as FOUR compiles.
#               `long time(long *tp);` was what pinned `time_T`'s width, and it is
#               replaced by a static_assert rather than deleted.  m1 shows the prototype
#               really was a check (on the INPUT, written wrong: `conflicting types for
#               'time'`); m2 shows what it did NOT check (on the INPUT, `time_T`
#               perturbed to `int` with the prototype untouched: SILENT); p1 shows the
#               hole this phase would leave without its replacement (the OUTPUT with the
#               assert deleted and `time_T` perturbed: SILENT); and p2/p3 show the
#               replacement closing it (`static assertion failed: "time_T is time_t"`).
#               The assert is therefore STRICTLY STRONGER than the prototype, and the
#               check says so with m2 rather than claiming an equivalence.
#   THE BOUNDARY
#               `make editor.c`'s cut, computed here by the same awk clause on BOTH
#               sides: 0 directives, `-fsyntax-only` with no error and no warning that
#               is not a boundary name, and the warning set compared AT RUN TIME with
#               the input's -- exactly `host_time` arriving, nothing gone, 13 -> 14.
#               The thirteen are never written out: phase 28 renamed one of them and a
#               list here would already be stale.
#   CANON       tools/canon.sh is a NO-OP on the output.
#   HOST        `zhostonly`, unchanged: `time` is not in its vocabulary and this
#               phase deliberately does not add it -- see THE TOOL THIS PHASE DOES NOT
#               EDIT below.
#   SYMBOLS     `nm -u` is THE SAME SET -- 17 names, `comm` empty in both directions --
#               and `main` is still the only external symbol.  **`time` DOES NOT LEAVE**,
#               and this is said as an equality rather than left for a reader to expect
#               otherwise: the host still calls it to implement host_time(), and a symbol
#               leaves when its last caller leaves the FILE, which is the split and not
#               this phase.  That is phase 28's sentence about `gettimeofday`, and the
#               two clocks are now in exactly the same position.
#   THE READS   THE INSTRUMENTED PAIR, and it is the evidence the recording cannot give.
#               `write(2, "TICK\n", 5)` at EVERY clock read on both sides -- on the input
#               inside vim_time() and, as a comma expression, at each of
#               ui_focus_change's two direct reads; on the output inside host_time(),
#               which is now every read there is.  The two instrumented 102-case
#               recordings must be BYTE-IDENTICAL, which is a statement about the screens
#               AND about the number and the order of the clock reads in every case.
#               Plus focus probes, because no corpus case reaches ui_focus_change at all.
#   BEHAVIOUR   the declared delta is NOTHING AT ALL: two full recordings, of the binary
#               this phase was handed and of its own, byte-identical across all 106
#               records.  tools/zerodelta.sh is run by tools/phaserun.sh after this check
#               and is the second opinion.
#
# THE CORPUS CANNOT REACH ui_focus_change AND THE PHASE SAYS SO RATHER THAN HOPING.
# `ui_focus_change()` is called from `handle_key_without_mapping`'s KE_FOCUSGAINED and
# KE_FOCUSLOST arms, and those key codes arrive as `\033[I` and `\033[O`, which
# `set_termname()` registers unconditionally.  So a keystroke file CAN drive it -- which
# ZERO-PLAN.md 2l calls a hazard (a typed Escape followed by `[` is read as a key code)
# and which is exactly what is wanted here.  The probes are:
#
#   focus        \033[O \033[I         3 TICKs on both binaries
#   focus_twice  \033[O \033[I x2      4 TICKs on both binaries
#
# and the arithmetic is worth writing down because the control turns on it.  `focus_state`
# starts MAYBE, so the first `\033[O` calls ui_focus_change(FALSE) -- which reads NOTHING,
# `in_focus &&` short-circuiting -- and the first `\033[I` calls it with TRUE, where
# `last_time` is 0, the test is true and BOTH reads happen.  On the second round the test
# is FALSE, so only the condition reads.  0 + 2 + 0 + 1, and one more for the `:q!` that
# reaches add_to_history: four.
#
# AND THE CONTROL IS THE QUESTION THE USER ASKED, MADE INTO A PROGRAM.  `hoist` is the
# output with ui_focus_change's two reads collapsed into one local -- which is what
# "could the two reads now straddle a second boundary differently" would mean if it were
# true -- and it reads the clock ONCE PER CALL, unconditionally: 1 + 1 + 1 + 1 + 1 = 5
# where the product gives 4.  So the instrument can see a collapsed read, the product
# does not collapse one, and the answer to the question is measured rather than argued:
# two reads before, two reads after, in the same two statements and the same order.
#
# A HAZARD THIS PHASE FOUND IN THE SHARED RECORDING, NOT WORKED AROUND HERE.  Comparing
# two FULL recordings is load-sensitive in exactly three records, and this phase is the
# one that would notice.  `tools/zrec.py` scrubs the undo message's elapsed time to
# `<ago>` PADDED TO THE WIDTH IT REPLACES, so the SCREEN is protected -- but the record
# also carries `--- stream <len> sha=<...>`, and that digest is taken over the RAW byte
# stream, where "0 seconds ago" and "1 second ago" are 13 bytes and 12.  MEASURED with a
# control built for it, `add_time()` reporting one second more: exactly three records
# move -- undo_after_ins, undo_block, undo_redo, which are exactly the three whose screen
# carries `<ago>` -- and in each of them exactly ONE line moves, the `--- stream` line,
# with the 24 screen lines byte-identical.  Under a 33-way concurrent `make zero-verify`
# the gap between `u_savecommon()`'s stamp and `undo_time()`'s read can straddle a second
# tick, and one such run failed here on `undo_after_ins` alone.
#
# IT IS NOT THIS PHASE'S TO FIX AND NOT THIS PHASE'S TO PAPER OVER.  Every zero phase
# since 3 compares two full recordings and every one of them is exposed; so is
# tools/zerodelta.sh, which compares against baselines recorded the same way.  Hashing
# the SCRUBBED stream in tools/zrec.py would close it, and would re-key all 33 zero
# phases and require .reference/zero-baselines to be recorded again.  A private exclusion
# HERE would be a check narrowed to fit what it saw, would leave zerodelta failing on the
# same load, and is refused: the comparison below stays an exact `diff -rq`.  The reading
# that matters for THIS phase is that the exposure is unchanged by it -- the undo path
# reads the clock the same number of times before and after, which is what the
# instrumented pair measures.
#
# THE TOOL THIS PHASE DOES NOT EDIT, and it is a decision rather than an oversight.
# ``zhostonly`` asserts that the core names none of the host's vocabulary, and
# `gettimeofday` joined that vocabulary at phase 28 for exactly this shape of reason.
# `time` is NOT added here.  Adding it would re-key phases 20, 21, 25, 26 and 27, whose
# checks run the tool on their own output, and every one of those boundaries has the core
# calling `time()` -- so each would need a named exception with a count, and four
# boundaries would have to be re-verified to buy a fact this check already asserts
# directly and more strongly: `\btime\b` is at ZERO above the boundary, computed on the
# literal-stripped text, and the `make editor.c` cut compiles with `host_time` as a
# boundary name.  The tool is still RUN, on this phase's output, so that nothing else in
# its vocabulary moved.
set -eu

work=${1:?usage: zero32-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero32-check.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"
before_lines=$(cat "$state/input-lines")

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")

# The product, the two instrumented builds and the hoisting control are written first
# and built in the background: they are seconds of wall time the assertions can be
# spending instead.
python3 - "$f" "$state/old.c" "$tmp" <<'PY'
import sys

TAG = 'wallclock'
new = open(sys.argv[1], errors='surrogateescape').read()
old = open(sys.argv[2], errors='surrogateescape').read()
out = sys.argv[3]
files = {}


def die(msg):
    sys.exit('  %-12s %s' % (TAG, msg))


# --- the four compiles that make THE GUARANTEE a measurement ---------------------------
TD = 'typedef long        time_T;'
AS = 'static_assert(_Generic((time_T)0, time_t: 1, default: 0), "time_T is time_t");\n'
PR = 'long time(long *tp);'
for text, what, where in ((new, TD, 'the output'), (new, AS, 'the output'),
                          (old, TD, 'the input'), (old, PR, 'the input')):
    if text.count(what) != 1:
        die('`%s` is not in %s exactly once, so the controls below would not be controls'
            % (what.strip(), where))
INT = 'typedef int         time_T;'
LL = 'typedef long long   time_T;'
files['m1'] = old.replace(PR, 'int time(int *tp);', 1)
files['m2'] = old.replace(TD, INT, 1)
files['p1'] = new.replace(TD, INT, 1).replace(AS, '', 1)
files['p2'] = new.replace(TD, INT, 1)
files['p3'] = new.replace(TD, LL, 1)

# --- the instrumented pair, and the control that collapses a read ------------------------
# THE SAME FIVE BYTES AT EVERY CLOCK READ ON BOTH SIDES.  On the input that is three
# places -- the wrapper and ui_focus_change's two, which bypass it -- and on the output
# it is one, because after this phase there is only one read site in the file.  The
# comma expression is used at the two bypassing reads because one of them is inside a
# condition: it ticks exactly where the read is and moves nothing.
TICK = '    write(2, "TICK\\n", 5);\n'
OW = 'vim_time(void)\n{\n    return time(nullptr);\n}'
OF = '''    if (in_focus && last_time + 2 < time(nullptr))
    {
        last_time = time(nullptr);
    }
'''
NW = 'host_time(void)\n{\n    return time(nullptr);\n}'
NF = '''    if (in_focus && last_time + 2 < host_time())
    {
        last_time = host_time();
    }
'''
for text, what, where in ((old, OW, 'the input'), (old, OF, 'the input'),
                          (new, NW, 'the output'), (new, NF, 'the output')):
    if text.count(what) != 1:
        die('`%s` is not in %s exactly once, so the instrument would not be at every '
            'clock read' % (what.replace('\n', '\\n')[:60], where))
files['t_old'] = old.replace(
    OW, 'vim_time(void)\n{\n' + TICK + '    return time(nullptr);\n}', 1).replace(
    OF, '''    if (in_focus && last_time + 2 < (write(2, "TICK\\n", 5), time(nullptr)))
    {
        last_time = (write(2, "TICK\\n", 5), time(nullptr));
    }
''', 1)
files['t_new'] = new.replace(
    NW, 'host_time(void)\n{\n' + TICK + '    return time(nullptr);\n}', 1)
files['hoist'] = files['t_new'].replace(NF, '''    long        now = host_time();

    if (in_focus && last_time + 2 < now)
    {
        last_time = now;
    }
''', 1)

for name, text in files.items():
    if text == new or text == old:
        die('%s changed nothing, so it is not a control' % name)
    open('%s/%s.c' % (out, name), 'w', errors='surrogateescape').write(text)
print('  %-12s eight controls written: m1 the input\'s `time` prototype written wrong, '
      'm2 the input\'s time_T perturbed with the prototype LEFT ALONE, p1 the output '
      'with the static_assert deleted and time_T perturbed, p2 and p3 the same '
      'perturbations WITH the assert, t_old and t_new the instrumented pair -- five '
      'bytes at every clock read on each side -- and hoist, which collapses '
      'ui_focus_change\'s two reads into one' % TAG)
PY

# shellcheck disable=SC2086
( SOURCE_DATE_EPOCH=0 gcc $cflags $ldflags -o "$tmp/new" "$f" ) &
pid_new=$!
for v in t_old t_new hoist; do
    # shellcheck disable=SC2086
    ( SOURCE_DATE_EPOCH=0 gcc $cflags $ldflags -o "$tmp/$v" "$tmp/$v.c" ) &
done
# These four are EXPECTED to differ in their diagnostics -- that IS the measurement -- so
# their status is discarded here rather than by `wait`, which would take `set -e` with it.
for v in m1 m2 p1 p2 p3; do
    ( gcc -O0 -fno-stack-protector -fsyntax-only "$tmp/$v.c" 2>"$tmp/w.$v" || true ) &
done
cp "$f" "$tmp/canon.c"
( tools/canon.sh "$tmp/canon.c" >"$tmp/canon.log" 2>&1 ) &
pid_canon=$!

# --- 1. the source, as arithmetic on the input --------------------------------------------
python3 - "$f" "$state/old.c" "$before_lines" <<'PY'
import re
import sys

TAG = 'wallclock'
new = open(sys.argv[1], errors='surrogateescape').read()
old = open(sys.argv[2], errors='surrogateescape').read()
before_lines = int(sys.argv[3])
fail = []


def strip_strings(line):
    """zhostonly's, and for the same reason: two NGETTEXT strings in this file
    say "%ld line %sed %d time", and a count that read those as calls would be counting
    English rather than code."""
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


def split(text, which):
    lines = text.split('\n')
    d = [i for i, l in enumerate(lines) if l.lstrip().startswith('#')]
    if len(d) != 11 or d != list(range(d[0], d[0] + 11)):
        sys.exit('  %-12s %s does not have eleven contiguous directives: %d at %s.  The '
                 'first one IS the boundary and every count below distinguishes the core '
                 'from the host'
                 % (TAG, which, len(d), ' '.join(str(i + 1) for i in d[:3])))
    core = '\n'.join(strip_strings(l) for l in lines[:d[0]])
    below = '\n'.join(strip_strings(l) for l in lines[d[0]:])
    return core, below, lines, d[0]


ocore, obelow, olines, ocut = split(old, 'old.c')
ncore, nbelow, nlines, ncut = split(new, 'the output')

if len(olines) - 1 != before_lines:
    fail.append('the state directory says the edit was handed %d lines and old.c has %d'
                % (before_lines, len(olines) - 1))

# THE CORE DOES NOT NAME `time`.  This is the phase's whole product and it is stated
# against the input's own count rather than against a number written here.
was = len(re.findall(r'\btime\b', ocore))
now = len(re.findall(r'\btime\b', ncore))
if was != 4:
    fail.append('the INPUT\'s core names `time` %d times and this phase was written '
                'against 4 -- the libc prototype, the wrapper\'s call and '
                'ui_focus_change\'s two' % was)
if now:
    fail.append('the output\'s core still names `time` %d times, and the whole product '
                'of this phase is that it names it none' % now)
if len(re.findall(r'\bvim_time\b', new)):
    fail.append('`vim_time` survives in the output, %d times'
                % len(re.findall(r'\bvim_time\b', new)))
for where, text, want, why in (
        ('above the boundary', ncore, 8, 'the declaration and seven call sites'),
        ('below the boundary', nbelow, 1, 'its definition')):
    n = len(re.findall(r'\bhost_time\b', text))
    if n != want:
        fail.append('`host_time` occurs %d times %s where %d were expected -- %s'
                    % (n, where, want, why))
# The call sites, as the input's own arithmetic: five that called the wrapper plus the
# two that bypassed it.
calls = len(re.findall(r'\bhost_time\(\)', ncore))
owrap = len(re.findall(r'\bvim_time\(\)', ocore))
obypass = len(re.findall(r'\btime\(nullptr\)', ocore)) - 1
if calls != owrap + obypass:
    fail.append('the core makes %d calls to host_time() and the input made %d to '
                'vim_time() and %d directly to time(nullptr) outside the wrapper'
                % (calls, owrap, obypass))
if (owrap, obypass) != (5, 2):
    fail.append('the input had %d wrapper calls and %d bypassing ones, where 5 and 2 '
                'were counted' % (owrap, obypass))
if len(re.findall(r'\btime\b', nbelow)) != len(re.findall(r'\btime\b', obelow)) + 1:
    fail.append('`time` is %d below the boundary and the input had %d there: host_time '
                'brings exactly one call with it, beside the `#include <time.h>`'
                % (len(re.findall(r'\btime\b', nbelow)),
                   len(re.findall(r'\btime\b', obelow))))
# ON THE LITERAL-STRIPPED TEXT, and the trap is this phase's own line: the
# static_assert's message is the string "time_T is time_t", so the raw file says the
# name TWICE on that line and once as a type.  A count that read the literal would be
# counting its own diagnostic.
if len(re.findall(r'\btime_t\b', ncore + nbelow)) != 1:
    fail.append('`time_t` is named %d times in the file\'s CODE and must be named once '
                '-- the static_assert, which is the only place a core name and a header '
                'name are both in scope.  The assert\'s own message says the name again '
                'and is a literal'
                % len(re.findall(r'\btime_t\b', ncore + nbelow)))
if len(re.findall(r'\btime_T\b', ncore)) != len(re.findall(r'\btime_T\b', ocore)) - 2:
    fail.append('`time_T` is %d in the core and the input had %d: the two that go are '
                'the wrapper\'s prototype and its definition head'
                % (len(re.findall(r'\btime_T\b', ncore)),
                   len(re.findall(r'\btime_T\b', ocore))))

# THE HOST BLOCK, and the shape of what crosses.  `long` and not `time_T`, because the
# definition is below the boundary and the host cannot name a core typedef once the file
# is cut -- which is musl_now_ms's own reason, and the boundary's stated property that
# every core -> host signature takes scalars and byte buffers only.
DECL = 'static void host_message(const char *msg, int len, int err);\nstatic long host_time(void);\n'
if DECL not in new:
    fail.append('`static long host_time(void);` is not on the line after '
                'host_message\'s declaration: the host block is ONE block and this is '
                'the fourteenth name in it')
if 'typedef long        time_T;' not in ncore:
    fail.append('`typedef long        time_T;` is not in the core, so host_time '
                'returning `long` would be a conversion at seven call sites rather than '
                'an assignment')
DEF = '    static long\nhost_time(void)\n{\n    return time(nullptr);\n}\n'
if new.count(DEF) != 1:
    fail.append('host_time\'s definition is not below the boundary exactly once in the '
                'shape the edit wrote')
if DEF not in nbelow + '\n':
    fail.append('host_time is defined above the boundary')

# THE LIBC PROTOTYPE BLOCK, computed on both sides rather than written here: another
# phase in flight removes two of its entries, so a stated size would already be stale.
def block(lines, which):
    at = [i for i, l in enumerate(lines) if l == 'void *malloc(usize n);']
    if len(at) != 1:
        sys.exit('  %-12s `void *malloc(usize n);` is not on a line of its own exactly '
                 'once in %s, so the prototype block cannot be found' % (TAG, which))
    a = b = at[0]
    while lines[a - 1].strip():
        a -= 1
    while lines[b + 1].strip():
        b += 1
    return lines[a:b + 1]


ob, nb = block(olines, 'old.c'), block(nlines, 'the output')
if [l for l in ob if l not in nb] != ['long time(long *tp);']:
    fail.append('the prototype block lost %s and this phase removes exactly '
                '`long time(long *tp);`'
                % ' / '.join(l for l in ob if l not in nb))
if [l for l in nb if l not in ob]:
    fail.append('the prototype block gained %s' % ' / '.join(l for l in nb if l not in ob))
if len(nb) != len(ob) - 1:
    fail.append('the prototype block is %d lines and was %d' % (len(nb), len(ob)))

# THE TWO HALVES OF THE LINE ARITHMETIC, separately.  The core is the lines above the
# first `#include`, so the boundary's index IS the core's line count -- a line removed
# from the host and one removed from the core sum the same and mean different things,
# and here they cancel exactly.
if ncut - ocut != -7:
    fail.append('the core is %d lines and was %d, a difference of %d where -7 was '
                'expected: -1 for the forward declaration, +1 for the host-block one, '
                '-6 for the definition with its blank and -1 for the libc prototype'
                % (ncut, ocut, ncut - ocut))
if (len(nlines) - ncut) - (len(olines) - ocut) != 7:
    fail.append('the host is %d lines and was %d, a difference of %d where +7 was '
                'expected: +6 for the definition with its blank and +1 for the '
                'static_assert'
                % (len(nlines) - ncut, len(olines) - ocut,
                   (len(nlines) - ncut) - (len(olines) - ocut)))
if len(nlines) != len(olines):
    fail.append('the file is %d lines and was %d, and the two halves were expected to '
                'cancel exactly' % (len(nlines) - 1, len(olines) - 1))

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
print('  %-12s THE CORE DOES NOT NAME `time` AT ALL: %d mentions in the input\'s core -- '
      'the libc prototype, the wrapper\'s call and ui_focus_change\'s TWO -- and 0 here, '
      'counted on the literal-stripped text because two NGETTEXT strings say the English '
      'word.  `host_time` is 8 above the boundary and 1 below, and its %d call sites are '
      'the input\'s %d wrapper calls plus the %d that bypassed it' % (TAG, was, calls,
                                                                      owrap, obypass))
print('  %-12s the boundary crosses as `static long host_time(void);`, on the line below '
      'host_message\'s, and NOT as `time_T`: the definition is below the boundary and the '
      'host cannot name a core typedef once the file is cut, which is musl_now_ms\'s own '
      'reason.  `typedef long        time_T;` is what makes every call site an assignment '
      'and not a conversion' % TAG)
print('  %-12s the libc prototype block is %d lines and was %d, losing `long time(long '
      '*tp);` and nothing else: %s' % (TAG, len(nb), len(ob),
                                       ' '.join(l.split('(')[0].split()[-1].lstrip('*')
                                                for l in nb)))
print('  %-12s the core is %d lines against %d (-7) and the host %d against %d (+7), so '
      'the file is %d lines either side, and `time_t` is named ONCE in the whole file -- '
      'the static_assert'
      % (TAG, ncut, ocut, len(nlines) - ncut, len(olines) - ocut, len(nlines) - 1))
PY

# --- 2. THE GUARANTEE, as four compiles ------------------------------------------------------
if ! grep -qF "conflicting types for 'time'" "$tmp/w.m1"; then
    echo "  wallclock    m1 -- the INPUT's \`long time(long *tp);\` written \`int time(int *tp);\` -- did not give \`conflicting types for 'time'\`, so the prototype this phase removes was not a check after all and there is nothing to replace:"
    sed -n '1,6p' "$tmp/w.m1"
    exit 1
fi
if [ -s "$tmp/w.m2" ]; then
    echo "  wallclock    m2 -- the INPUT's time_T perturbed to \`int\` with the prototype LEFT ALONE -- was expected to compile SILENTLY, and did not:"
    sed -n '1,6p' "$tmp/w.m2"
    exit 1
fi
if [ -s "$tmp/w.p1" ]; then
    echo "  wallclock    p1 -- the OUTPUT with the static_assert deleted and time_T perturbed to \`int\` -- was expected to compile SILENTLY, which is the hole this phase would leave, and did not:"
    sed -n '1,6p' "$tmp/w.p1"
    exit 1
fi
for v in p2 p3; do
    if ! grep -qF 'static assertion failed: "time_T is time_t"' "$tmp/w.$v"; then
        echo "  wallclock    $v -- the OUTPUT with time_T perturbed and the static_assert PRESENT -- did not fail the assertion, so the guarantee that replaces the prototype cannot be broken and is therefore not a guarantee:"
        sed -n '1,6p' "$tmp/w.$v"
        exit 1
    fi
done
echo "  wallclock    THE PROTOTYPE WAS LOAD-BEARING AND WHAT REPLACES IT IS STRONGER, in four compiles.  m1: the input's \`long time(long *tp);\` written \`int time(int *tp);\` is \`conflicting types for 'time'\` from <time.h> below it -- that WAS the guarantee, and it is what phase 26 relied on when it wrote \`typedef long time_T;\`.  m2: the same input with \`time_T\` perturbed to \`int\` and the prototype LEFT ALONE compiles in SILENCE -- so the prototype pinned \`long == time_t\` and never \`time_T == long\`.  p1: the output with the static_assert deleted and time_T perturbed compiles in silence too -- that is the regression this phase would have shipped.  p2 and p3: with the assert present, \`int\` and \`long long\` both give \`static assertion failed: \"time_T is time_t\"\`.  The one line names time_T ITSELF, which the prototype could not"

# --- 3. the editor.c cut, and its warning set compared WITH THE INPUT'S ------------------------
# `make editor.c`'s rule is one awk clause and no judgement; here it is run on both sides
# and the two prefixes held to the same three properties.  THE NAMES ARE NEVER WRITTEN
# OUT: phase 28 replaced `musl_gettimeofday` with `musl_now_ms`, so a check that spelled
# the set would fail on a tree that is exactly right.
for side in old new; do
    case $side in old) src=$state/old.c;; new) src=$f;; esac
    awk '/^ *# *include / { exit } { a[NR] = $0; if (NF) last = NR } \
         END { for (i = 1; i <= last; i++) print a[i] }' "$src" > "$tmp/ed.$side.c"
    if grep -q '^ *#' "$tmp/ed.$side.c"; then
        echo "  wallclock    the $side cut holds a directive, so it found the wrong line:"
        grep -n '^ *#' "$tmp/ed.$side.c" | head -3
        exit 1
    fi
    gcc -O0 -fno-stack-protector -Wall -Wextra -Wno-unused-parameter -fsyntax-only \
        "$tmp/ed.$side.c" 2>"$tmp/c.$side" || true
    if grep -q ': error:' "$tmp/c.$side"; then
        echo "  wallclock    the $side cut does not parse on its own:"
        grep ': error:' "$tmp/c.$side" | head -4
        exit 1
    fi
    grep -o "'[A-Za-z_][A-Za-z0-9_]*' used but never defined" "$tmp/c.$side" \
        | sed "s/' used.*//; s/^'//" | sort -u > "$tmp/b.$side"
    if grep ': warning: ' "$tmp/c.$side" | grep -qv 'used but never defined'; then
        echo "  wallclock    the $side cut has a warning that is not a boundary name:"
        grep ': warning: ' "$tmp/c.$side" | grep -v 'used but never defined' | head -3
        exit 1
    fi
done
gone=$(comm -23 "$tmp/b.old" "$tmp/b.new" | tr '\n' ' ')
came=$(comm -13 "$tmp/b.old" "$tmp/b.new" | tr '\n' ' ')
if [ -n "$gone" ] || [ "$came" != "host_time " ]; then
    echo "  wallclock    the core -> host boundary moved by something other than host_time arriving: gone [$gone] arrived [$came].  This phase adds exactly one name to it and takes none away"
    exit 1
fi
echo "  wallclock    the \`make editor.c\` cut: $(grep -c '' "$tmp/ed.old.c") lines -> $(grep -c '' "$tmp/ed.new.c"), 0 directives, 0 errors under \`-fsyntax-only\`, and the WHOLE warning set is the core -> host boundary -- $(wc -l <"$tmp/b.old") names -> $(wc -l <"$tmp/b.new"), with \`host_time\` ARRIVING and NOTHING gone, compared name by name at run time and never written out here (phase 28 renamed one of them and phase 31 renames none)"

# --- 4. canon.sh -----------------------------------------------------------------------------
wait $pid_canon || { echo "  wallclock    tools/canon.sh failed on the output:"; sed -n '1,10p' "$tmp/canon.log"; exit 1; }
if ! cmp -s "$f" "$tmp/canon.c"; then
    echo "  wallclock    tools/canon.sh is not a no-op on the output -- the new text is not written the way this file writes everything else:"
    diff "$f" "$tmp/canon.c" | sed -n '1,12p'
    exit 1
fi
echo "  wallclock    tools/canon.sh is a NO-OP on the output: host_time's declaration, its definition and the static_assert are written the way this file writes everything else"

# --- 5. the host's vocabulary is still the host's ---------------------------------------------
# UNCHANGED BY THIS PHASE, deliberately -- see the header.  It is run so that nothing
# ELSE in its vocabulary moved when a function crossed the line.
tools/st.sh zhostonly "$f"

# --- 6. the symbols, and the binary ------------------------------------------------------------
wait $pid_new || { echo "  wallclock    the output did not build with '$cflags' '$ldflags'"; exit 1; }
gcc -c -O0 -fno-stack-protector -o "$tmp/old.o" "$state/old.c"
gcc -c -O0 -fno-stack-protector -o "$tmp/new.o" "$f"
nm -u "$tmp/old.o" | awk '{print $2}' | sort > "$tmp/u.old"
nm -u "$tmp/new.o" | awk '{print $2}' | sort > "$tmp/u.new"
gone=$(comm -23 "$tmp/u.old" "$tmp/u.new" | tr '\n' ' ')
came=$(comm -13 "$tmp/u.old" "$tmp/u.new" | tr '\n' ' ')
if [ -n "$gone$came" ]; then
    echo "  wallclock    \`nm -u\` moved: gone [$gone] arrived [$came].  MOVING A CALL FROM THE CORE INTO THE HOST INSIDE ONE TRANSLATION UNIT FREES NOTHING AND NEEDS NOTHING"
    exit 1
fi
if ! grep -qx 'time' "$tmp/u.new"; then
    echo "  wallclock    \`time\` is NOT in the undefined set, and it must be: the host still calls it to implement host_time()"
    exit 1
fi
ext=$(nm --extern-only --defined-only "$tmp/new.o" | awk '{print $3}' | sort | tr '\n' ' ')
if [ "$ext" != "main " ]; then
    echo "  wallclock    the output defines external symbols other than main: $ext"
    exit 1
fi
if cmp -s "$tmp/new" "$state/old"; then
    echo "  wallclock    the output binary is byte-identical to the input's, which cannot be: a call replaces an inlined read at two sites and five lines of definition move past two thousand"
    exit 1
fi
echo "  wallclock    \`nm -u\` is THE SAME SET, $(wc -l <"$tmp/u.new") names, as a \`comm\` empty in BOTH directions, and \`main\` is still the only external symbol.  \`time\` IS STILL THERE and this phase says so as an equality, exactly as phase 28 did for \`gettimeofday\`: the host calls it to implement host_time(), and a symbol leaves when its last CALLER leaves the FILE, which is the split and not this phase.  The binary is $(stat -c%s "$tmp/new") bytes against $(stat -c%s "$state/old") and they are NOT the same bytes"

tools/phasecheck.sh "$work" "$f" "$state/symbols"

# --- 7. the reads, instrumented, and the recordings -------------------------------------------
for v in t_old t_new hoist; do
    [ -f "$tmp/$v" ] || { echo "  wallclock    the $v build did not finish"; exit 1; }
done
tools/zrecord.sh "$state/old" "$state/old.c" "$tmp/REC.old" >/dev/null 2>&1 &
pid_ro=$!
tools/zrecord.sh "$tmp/new" "$f" "$tmp/REC.new" >/dev/null 2>&1 &
pid_rn=$!
tools/st.sh zcases "$tmp/t_old" "$tmp/SC.told" >/dev/null 2>&1 &
pid_ct=$!
tools/st.sh zcases "$tmp/t_new" "$tmp/SC.tnew" >/dev/null 2>&1 &
pid_cn=$!

python3 - "$tmp" "$state/old" <<'PY'
import sys
sys.path.insert(0, 'tools')          # tools/zstream.py -- stage() is the one place a
import zstream                       # binary is renamed to `vim`, for the race its
                                     # docstring describes

TAG = 'wallclock'
tmp = sys.argv[1]
fail = []

# `\033[I` and `\033[O` are KE_FOCUSGAINED and KE_FOCUSLOST, registered unconditionally
# by set_termname(), so a keystroke file reaches ui_focus_change() -- the one clock
# reader no screen case touches.  ZERO-PLAN.md 2l calls a typed Escape followed by `[`
# a hazard; here it is the instrument.
PROBES = (('focus', [b'\x1b[O\x1b[I:q!\r'], 3),
          ('focus_twice', [b'\x1b[O\x1b[I\x1b[O\x1b[I:q!\r'], 4),
          ('edit', [b'ihi\x1b:q!\r'], 2),
          ('undo', [b'ihi\x1bu:q!\r'], 3),
          ('plainq', [b':q!\r'], 1))


def run(binary, keys):
    try:
        _, stdout, stderr, rc = zstream.session(binary, keys, timeout=8)
    except zstream.Blocked:
        return None, None
    return stderr.count(b'TICK'), rc


res = {}
for who in ('t_old', 't_new', 'hoist'):
    res[who] = {name: run(tmp + '/' + who, keys) for name, keys, _ in PROBES}

for name, _, want in PROBES:
    for who in ('t_old', 't_new'):
        got, rc = res[who][name]
        if got is None:
            fail.append('%s: the %s probe never returned' % (who, name))
            continue
        if rc != 0:
            fail.append('%s: the %s probe exited %d' % (who, name, rc))
        if got != want:
            fail.append('%s: the %s probe recorded %d clock reads and %d were expected'
                        % (who, name, got, want))
    if res['t_old'][name][0] != res['t_new'][name][0]:
        fail.append('the %s probe reads the clock %s times on the binary this phase was '
                    'handed and %s times on its own.  The phase renames a read and moves '
                    'it; it does not add or remove one'
                    % (name, res['t_old'][name][0], res['t_new'][name][0]))

# THE CONTROL IS THE QUESTION, MADE INTO A PROGRAM.  `hoist` reads the clock ONCE per
# call to ui_focus_change instead of 0, 2, 0 or 1 -- which is what collapsing the two
# reads would mean -- and `focus_twice` is where the two disagree.  `focus` does NOT
# disagree (3 either way, by a different route), and that is why the phase has two
# probes and not one: a control that only fails on one of them is a control that says
# which probe is load-bearing.
if res['hoist']['focus_twice'][0] != 5:
    fail.append('the `hoist` control -- ui_focus_change reading the clock ONCE into a '
                'local -- recorded %s clock reads on `focus_twice` and 5 were expected: '
                'one per call plus the :q!.  If collapsing the two reads does not move '
                'the probe, the probe cannot see whether they were collapsed'
                % (res['hoist']['focus_twice'][0],))
if res['hoist']['focus'][0] != res['t_new']['focus'][0]:
    fail.append('the `hoist` control moved the `focus` probe, where the arithmetic says '
                'it must not: 1 + 1 against 0 + 2, plus the :q!, is 3 either way.  If '
                'that has changed, the reasoning behind `focus_twice` needs re-doing')

if fail:
    for line in fail:
        print('  %-12s %s' % (TAG, line))
    sys.exit(1)
print('  %-12s THE READS ARE THE SAME READS, at every probe: `focus` %d, `focus_twice` '
      '%d, `edit` %d, `undo` %d, `plainq` %d -- identical on the instrumented input and '
      'the instrumented output.  ui_focus_change still reads the clock TWICE, in two '
      'statements, in the same order: at `focus_twice` the four calls read 0, 2, 0 and 1 '
      'times, because in_focus FALSE short-circuits and the second FocusGained finds '
      'last_time fresh'
      % (TAG, res['t_new']['focus'][0], res['t_new']['focus_twice'][0],
         res['t_new']['edit'][0], res['t_new']['undo'][0], res['t_new']['plainq'][0]))
print('  %-12s AND THE INSTRUMENT CAN SEE A COLLAPSED READ: `hoist`, the output with '
      'ui_focus_change\'s two reads hoisted into one local, reads ONCE PER CALL and '
      'gives `focus_twice` %d against the product\'s %d.  So "can the two reads straddle '
      'a second differently now" is answered by measurement -- the program that would '
      'make it true is a DIFFERENT program and the probe says so'
      % (TAG, res['hoist']['focus_twice'][0], res['t_new']['focus_twice'][0]))
PY

wait $pid_ct
wait $pid_cn
if ! diff -rq "$tmp/SC.told" "$tmp/SC.tnew" >"$tmp/scr.diff" 2>&1; then
    echo "  wallclock    the two INSTRUMENTED 102-case recordings differ, so the clock is read a different number of times or in a different order somewhere in the corpus:"
    sed -n '1,12p' "$tmp/scr.diff"
    exit 1
fi
marked=$(grep -l TICK "$tmp/SC.tnew"/* | wc -l)
total=$(grep -h TICK "$tmp/SC.tnew"/* | wc -l)
if [ "$marked" -lt 1 ]; then
    echo "  wallclock    the instrument marks NO screen case, so the byte-identical instrumented recording above is two empty files agreeing"
    exit 1
fi
echo "  wallclock    THE INSTRUMENTED PAIR: the same five bytes at EVERY clock read on each side -- three sites on the input (the wrapper and ui_focus_change's two, which bypass it) and one on the output, because after this phase there is only one -- and the two 102-case recordings are BYTE-IDENTICAL.  The instrument is not silent: it marks $marked of 102 cases with $total reads in all, the two it does not being ctrl_c_clean and ctrl_c_changed, which exit before a key is looked up"

wait $pid_ro
wait $pid_rn
if ! diff -rq "$tmp/REC.old" "$tmp/REC.new" >"$tmp/rec.diff" 2>&1; then
    echo "  wallclock    the declared delta is NOTHING AT ALL and the two recordings differ:"
    sed -n '1,12p' "$tmp/rec.diff"
    exit 1
fi
echo "  wallclock    the declared delta is NOTHING AT ALL and TWO FULL RECORDINGS ARE BYTE-IDENTICAL -- 102 screen cases, every Ex command, every command line, the pty scenarios and the terminal table.  On its own that would say little, the corpus never reaching ui_focus_change at all; what answers for this phase is the instrumented pair and the focus probes above"

# tools/phaserun.sh runs tools/zerodelta.sh --phase 32 after this check, and that is the
# second opinion on the same claim -- against .reference/zero-baselines rather than
# against the binary this phase was handed.
