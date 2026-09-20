#!/bin/sh
# Zero phase 24, the check -- the attributes.
# See pipes/zero24-edit.sh, and ZERO-PLAN.md 4c.
#
# Usage: pipes/zero24-check.sh <work-dir> <state-dir>    (run from the repository root)
#
# Runs after pipes/zero24-edit.sh and the sweep tools/phaserun.sh runs between them, and
# reads nothing from the edit's shell -- only the work tree and the state directory.
# What the edit left there is `old.c`, the source this phase was HANDED, and `old`, that
# source built with SOURCE_DATE_EPOCH=0 and the boundary's own flags.
#
# THIS PHASE CHANGES NO STATEMENT, so there is no behavioural probe to offer and none is
# offered -- no editor is run and nothing is staged.  What it has instead is stronger
# than any recording: THE BINARY IS THE SAME BYTES.  That is tier 1 of CLAUDE.md's
# verification table and it subsumes every screen case, every Ex-command row, every
# command line and every pty scenario at once, because the program that would be run is
# literally the same program.  It is phase 23's shape exactly.
#
# BUT THE BINARY IS ALSO BLIND TO THE ONLY DECISION IN THIS PHASE THAT COULD BE WRONG,
# and that is why there are three more sections.  An attribute emits no code: MEASURED,
# removing all six survivors as well gives a binary that is STILL `cmp`-identical, while
# `-Wformat=2` goes from 115 warnings to zero.  So `cmp` proves the 133 removals and
# respellings were harmless and says NOTHING about the six kept.  The evidence for those
# is the warnings, and it is in section 5.
#
# WHAT IS CLAIMED, in seven parts:
#
#   ARITHMETIC  computed FROM THE INPUT and not written here: the input's attributes
#               partition into unused/fallthrough/format/format_arg, the output holds
#               exactly the format and format_arg ones on lines that are byte-identical
#               to the input's, `[[fallthrough]];` appears once per GNU one, the line
#               count is unchanged and so is the count of doubled spaces before a `,`
#               or `)`.  tools/canon.sh is a NO-OP on the output.
#   PARAMETERS  with `-Wunused-parameter` turned back ON -- the one warning the sweep
#               switches off -- the output warns 92 times more than the input, EVERY
#               one of them `-Wunused-parameter` at a line that carried an attribute,
#               and not one `-Wunused-variable`.  113 sites, 92 warnings: the other 21
#               marked a parameter this build USES, and they are named.
#   FALLTHROUGH `-Wimplicit-fallthrough` is silent on both, and the control is the
#               output with all 20 statements blanked, which must warn 18 times.  The
#               two that do not are named and KEPT: each follows a case label with no
#               statement at all, where C falls through silently and gcc has nothing to
#               diagnose.  Pruning them would be pruning by the compiler's current
#               opinion of a switch, which is not what makes a fallthrough deliberate.
#   C23         `[[fallthrough]]` is taken OUT of the output and compiled six ways.  It
#               is NOT a directive -- the output still has exactly eleven, all
#               `#include` -- and C23 is not a new dependency: MEASURED and computed,
#               `-std=c11` on the whole file gives the SAME number of errors before this
#               phase and after it.
#   WARNINGS    `-Wformat=2` gives THE IDENTICAL 115 `-Wformat-nonliteral` warnings in
#               THE IDENTICAL 53 functions, before and after -- phase 22's invariant,
#               and what proves the six survivors were not disturbed.  Two controls
#               break it in opposite directions.
#   SYMBOLS     `nm -u` is THE SAME SET, as a `comm` empty in BOTH directions, and
#               `main` is still the only external symbol.
#   THE BINARY  `cmp`, with a control that moves it: one `[[fallthrough]];` replaced by
#               `break;` must give a different binary, which is what keeps the equality
#               from being two numbers agreeing (CLAUDE.md).
#
# ONE MEASUREMENT ABOUT THE TOOL RATHER THAN THE FILE, and it is CLAUDE.md's
# `-fsyntax-only` lesson arriving on a second warning.  `-fsyntax-only` does report
# `-Wunused-parameter`, `-Wformat-nonliteral` and every syntax error, so the sections
# that want those use it and are seconds instead of minutes.  It does NOT report
# `-Wimplicit-fallthrough`, which needs the CFG: measured, the control below warns 18
# times under `-c` and ZERO times under `-fsyntax-only`.  A fallthrough section written
# with `-fsyntax-only` would have passed while checking nothing.
set -eu

work=${1:?usage: zero24-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero24-check.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"
before_lines=$(cat "$state/input-lines")

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")

# The reproducible build of the OUTPUT and the four controls are written and started
# first and waited for below: they are seconds of wall time the assertions can be
# spending instead.  Every control is this phase's own product with ONE thing changed.
# shellcheck disable=SC2086
( SOURCE_DATE_EPOCH=0 gcc $cflags $ldflags -o "$tmp/new" "$f" ) &
pid_new=$!
python3 - "$f" "$tmp" <<'PY'
import re
import sys

TAG = 'attrs'
t = open(sys.argv[1], errors='surrogateescape').read()
out = sys.argv[2]


def die(msg):
    sys.exit('  %-12s %s' % (TAG, msg))


# c1 -- vim_snprintf's `format(printf, 3, 4)` removed.  Phase 22 made this ONE attribute
# the thing that type-checks every formatted message in the file.
FMT = '  __attribute__((format(printf, 3, 4))) '
if t.count(FMT) != 1:
    die('vim_snprintf\'s `%s` is not in the output exactly once, so c1 would not be a '
        'control' % FMT.strip())
c1 = t.replace(FMT, ' ', 1)

# c2 -- `_()`'s `format_arg(1)` removed.  CLAUDE.md names format_arg as what lets
# -Wformat see THROUGH the translation wrapper; this is that, measured from the far end.
ARG = 'static inline __attribute__((format_arg(1))) char *_(const char *x)'
if t.count(ARG) != 1:
    die('`%s` is not in the output exactly once, so c2 would not be a control' % ARG)
c2 = t.replace(ARG, 'static inline char *_(const char *x)', 1)

# c3 -- all 20 `[[fallthrough]];` blanked IN PLACE, so the line numbers are the output's
# and each warning can be attributed to the site it came from.
c3, n3 = re.subn(r'\[\[fallthrough\]\];', lambda m: ' ' * len(m.group(0)), t)
if not n3:
    die('there is no `[[fallthrough]];` in the output, so c3 would not be a control')

# c4 -- ONE of them replaced by `break;`, which is the only control here that changes
# the program.  Without it the `cmp` in section 7 is two numbers agreeing.
i = t.index('[[fallthrough]];')
c4 = t[:i] + 'break;' + ' ' * (len('[[fallthrough]];') - len('break;')) + \
    t[i + len('[[fallthrough]];'):]

for name, text in (('c1', c1), ('c2', c2), ('c3', c3), ('c4', c4)):
    if text == t:
        die('%s changed nothing' % name)
    open('%s/%s.c' % (out, name), 'w', errors='surrogateescape').write(text)
print('  %-12s four controls written: c1 vim_snprintf\'s format(printf, 3, 4) removed, '
      'c2 `_()`\'s format_arg(1) removed, c3 all %d `[[fallthrough]];` blanked, c4 one '
      'of them replaced by `break;`' % (TAG, n3))
PY
# c4 is a full static link and the slowest; c1, c2 and c3 are warning runs.  c3 must be
# a real compile -- see the note at the top about -fsyntax-only and the CFG.
# shellcheck disable=SC2086
( SOURCE_DATE_EPOCH=0 gcc $cflags $ldflags -o "$tmp/c4" "$tmp/c4.c" 2>"$tmp/c4.log" ) &
pid_c4=$!
( gcc -O0 -fno-stack-protector -Wformat=2 -fsyntax-only "$tmp/c1.c" 2>"$tmp/w.c1" ) &
pid_c1=$!
( gcc -O0 -fno-stack-protector -Wformat=2 -fsyntax-only "$tmp/c2.c" 2>"$tmp/w.c2" ) &
pid_c2=$!
( gcc -c -O0 -fno-stack-protector -Wall -Wextra -Wno-unused-parameter -o /dev/null "$tmp/c3.c" 2>"$tmp/w.c3" ) &
pid_c3=$!
( gcc -O0 -fno-stack-protector -Wall -Wextra -Wno-unused-parameter -fsyntax-only "$tmp/c3.c" 2>"$tmp/w.c3syn" ) &
pid_c3s=$!
# The warning runs the assertions need, all of them -fsyntax-only, which reports every
# one of these (and not -Wimplicit-fallthrough; see above).
( gcc -O0 -fno-stack-protector -fsyntax-only -Wall -Wextra "$state/old.c" 2>"$tmp/p.old" ) &
pid_po=$!
( gcc -O0 -fno-stack-protector -fsyntax-only -Wall -Wextra "$f" 2>"$tmp/p.new" ) &
pid_pn=$!
( gcc -O0 -fno-stack-protector -Wformat=2 -fsyntax-only "$state/old.c" 2>"$tmp/w.old" ) &
pid_wo=$!
( gcc -O0 -fno-stack-protector -Wformat=2 -fsyntax-only "$f" 2>"$tmp/w.new" ) &
pid_wn=$!
# These two are EXPECTED to fail -- that is the measurement -- so their status is
# discarded here rather than by `wait`, which would take `set -e` with it.
( gcc -std=c11 -fsyntax-only "$state/old.c" 2>"$tmp/c11.old" || true ) &
pid_11o=$!
( gcc -std=c11 -fsyntax-only "$f" 2>"$tmp/c11.new" || true ) &
pid_11n=$!
# tools/canon.sh must be a NO-OP: the 113 deletions take the two spaces before the
# attribute and the one after with them, and a doubled space or a space before a paren
# is something canon does not fix, so the phase would have shipped one.
cp "$f" "$tmp/canon.c"
( tools/canon.sh "$tmp/canon.c" >"$tmp/canon.log" 2>&1 ) &
pid_canon=$!

# --- 1. the source, as arithmetic on the input ------------------------------------------
python3 - "$f" "$state/old.c" "$before_lines" <<'PY'
import re
import sys

TAG = 'attrs'
new = open(sys.argv[1], errors='surrogateescape').read()
old = open(sys.argv[2], errors='surrogateescape').read()
before_lines = int(sys.argv[3])
fail = []

KINDS = ('unused', 'fallthrough', 'format', 'format_arg')


def kinds(text):
    d = dict.fromkeys(KINDS, 0)
    for m in re.finditer(r'__attribute__\(\((\w+)', text):
        d[m.group(1)] = d.get(m.group(1), 0) + 1
    return d


ko, kn = kinds(old), kinds(new)
if set(ko) - set(KINDS):
    fail.append('the INPUT holds an attribute this phase never looked at: %s'
                % ' '.join(sorted(set(ko) - set(KINDS))))
# THE ARITHMETIC, computed from the input.  Nothing here is a number this file states.
for name, want, why in (
        ('unused', 0, 'every one of the %d, and they said nothing under '
                      '-Wno-unused-parameter' % ko['unused']),
        ('fallthrough', 0, 'every one of the %d, respelled rather than removed'
                           % ko['fallthrough']),
        ('format', ko['format'], 'KEPT: it is what type-checks the arguments of every '
                                 'formatted message in the file'),
        ('format_arg', ko['format_arg'], 'KEPT: it is what lets -Wformat see THROUGH '
                                         '`_()` and `NGETTEXT`'),
):
    if kn[name] != want:
        fail.append('`%s` has %d attributes in the output, expected %d -- %s'
                    % (name, kn[name], want, why))
n_c23 = len(re.findall(r'^[ ]*\[\[fallthrough\]\];$', new, re.M))
if n_c23 != ko['fallthrough'] or new.count('[[') != ko['fallthrough']:
    fail.append('the output has %d standalone `[[fallthrough]];` and %d `[[` where the '
                'input had %d GNU fallthrough attributes -- the swap is ONE FOR ONE'
                % (n_c23, new.count('[['), ko['fallthrough']))
if '[[' in old:
    fail.append('the INPUT already held `[[`, so this phase did not introduce the C23 '
                'spelling and the count above is not its own')

# THE KEPT LINES, BYTE FOR BYTE.  This is the assertion section 5's controls are the
# other half of: they must be the same lines and not merely the same number.
OL, NL = old.split('\n'), new.split('\n')
keep = [i for i, l in enumerate(OL) if '__attribute__' in l and re.search(r'format(_arg)?\(', l)]
if [NL[i] for i in keep] != [OL[i] for i in keep]:
    moved = [i + 1 for i in keep if NL[i] != OL[i]]
    fail.append('a line carrying a kept attribute is not the line it was, byte for '
                'byte: line%s %s' % ('' if len(moved) == 1 else 's',
                                     ' '.join(str(x) for x in moved)))
if sum(NL[i].count('__attribute__') for i in keep) != ko['format'] + ko['format_arg']:
    fail.append('the %d kept attributes are not all on the %d lines this phase named'
                % (ko['format'] + ko['format_arg'], len(keep)))

# THE SHAPE OF THE EDIT.  Both are WITHIN lines, so the file is the same length and only
# the header lines and the fallthrough statements moved.
if len(NL) != len(OL) or len(NL) - 1 != before_lines:
    fail.append('the file is %d lines and the input was %d (%d recorded) -- neither '
                'edit adds or removes a line' % (len(NL) - 1, len(OL) - 1, before_lines))
else:
    changed = [i for i in range(len(OL)) if OL[i] != NL[i]]
    heads = sorted({i for i, l in enumerate(OL) if '__attribute__((unused))' in l})
    falls = sorted({i for i, l in enumerate(OL) if '__attribute__((fallthrough));' in l})
    if changed != sorted(set(heads) | set(falls)):
        fail.append('%d lines changed and the attributes sat on %d -- the two must be '
                    'the same set' % (len(changed), len(set(heads) | set(falls))))
    for i in heads:
        want = re.sub(r'(?<=\S)  __attribute__\(\(unused\)\) (?=[,)])', '', OL[i])
        if NL[i] != want:
            fail.append('line %d is %r and stripping its attributes gives %r'
                        % (i + 1, NL[i], want))
            break
    if len(falls) != ko['fallthrough']:
        fail.append('the %d fallthrough attributes are not on %d lines of their own'
                    % (ko['fallthrough'], len(falls)))

# THE TRAP, AND IT IS THE ONE THIS PHASE COULD HAVE FALLEN INTO.  Each `unused` was
# written `<declarator>  __attribute__((unused)) ` -- two spaces before, one after --
# and deleting the attribute alone leaves a doubled space or a space before a paren.
# canon.sh takes neither, so the count of `  ` before a `,` or `)` must not move.
po, pn = len(re.findall(r'  [,)]', old)), len(re.findall(r'  [,)]', new))
if po != pn:
    fail.append('%d doubled spaces before a `,` or `)` in the output where the input '
                'had %d -- the attribute must go with ITS OWN two spaces and the one '
                'after it' % (pn, po))
if re.search(r'\S  [,)]', new) and not re.search(r'\S  [,)]', old):
    fail.append('the output has a declarator followed by two spaces and a `,` or `)` '
                'where the input had none')

# THE SHAPE OF THE FILE.  Nothing here is a command, an option, a directive or a
# normal-mode key, and the check says so rather than assuming it.  `[[fallthrough]]` is
# C23 ATTRIBUTE SYNTAX AND NOT A DIRECTIVE: the eleven are still eleven.
sys.path.insert(0, 'tools')
# tools/create_cmdidxs.py -- named as a PATH so tools/implhash.sh hashes it into this
# phase's key.  implhash greps for paths and an `import` names a module, so
# without this line an edit to it changes what this phase produces and moves
# no key at all.  See CLAUDE.md on cutil.py and macros.py.  Do not delete it.
import create_cmdidxs
rows = re.findall(r'^    \[CMD_\w+\] = \{.*$', new, re.M)
if len(rows) != 98 or len(create_cmdidxs.names(sys.argv[1])) != 98:
    fail.append('cmdnames[] is not the 98 rows phase 10 left -- this phase touches no '
                'Ex command')
i = new.find('static struct vimoption options[]')
j = new.index('\n};', i)
n_opt = len(re.findall(r'^[ \t]*\{"([a-z]+)",', new[i:j], re.M))
if n_opt != 107:
    fail.append('options[] has %d rows, expected the 107 phase 20 left -- this phase '
                'removes no option' % n_opt)
d = [l for l in NL if l.startswith('#')]
if len(d) != 11 or any(not l.startswith('#include <') for l in d) or NL[:11] != d:
    fail.append('the output does not have exactly the eleven `#include` directives '
                'phase 21 left, on its first eleven lines.  `[[fallthrough]]` is a '
                'STATEMENT and not a directive, and MOVING THEM IS A LATER PHASE')
if sum(1 for k in range(1, len(NL)) if NL[k] == '' and NL[k - 1] == ''):
    fail.append('there is a run of two blank lines, which canon.sh should have taken')

if fail:
    for line in fail:
        print('  %-12s %s' % (TAG, line))
    sys.exit(1)
print('  %-12s `__attribute__` %d -> %d.  unused %d -> 0, fallthrough %d -> 0 and '
      '`[[fallthrough]];` 0 -> %d, format %d and format_arg %d KEPT on %d lines that '
      'are BYTE-IDENTICAL to the input\'s.  Every count is computed FROM THE INPUT, so '
      'this is a check on the phase and not on whatever it was handed'
      % (TAG, sum(ko.values()), sum(kn.values()), ko['unused'], ko['fallthrough'],
         n_c23, ko['format'], ko['format_arg'], len(keep)))
print('  %-12s %d lines, unchanged, and the %d that differ are exactly the %d function '
      'headers and the %d fallthrough statements -- both edits are WITHIN lines.  The '
      'doubled-space count before a `,` or `)` is %d either side, which is the trap: an '
      'attribute deleted without its own two spaces leaves something canon.sh does not '
      'fix' % ('', len(NL) - 1, len(changed), len(heads), len(falls), pn))
print('  %-12s cmdnames[] 98 unchanged, options[] 107 unchanged, and ELEVEN #includes '
      'on the first eleven lines -- `[[fallthrough]]` is C23 attribute syntax, a '
      'statement in the grammar, and adds no preprocessor line' % '')
PY

# --- 2. the 113 were parameters, and 21 of them were used ---------------------------------
# The sweep's own flags are `-Wall -Wextra -Wno-unused-parameter`, which is why the 113
# said nothing.  Here that one switch is turned back ON, which is the only way to see
# what they were suppressing.
wait $pid_po $pid_pn
python3 - "$state/old.c" "$f" "$tmp/p.old" "$tmp/p.new" <<'PY'
import re
import sys

TAG = 'attrs'
old = open(sys.argv[1], errors='surrogateescape').read()
OL = old.split('\n')


def warns(path):
    out, kinds = set(), {}
    for l in open(path, errors='surrogateescape'):
        m = re.match(r'.*?:(\d+):\d+: warning: .*\[-W([a-z-]+)=?\]$', l.rstrip())
        if m:
            kinds[m.group(2)] = kinds.get(m.group(2), 0) + 1
        m = re.match(r'.*?:(\d+):\d+: warning: unused parameter .(\w+)', l)
        if m:
            out.add((int(m.group(1)), m.group(2)))
    return out, kinds


a, ka = warns(sys.argv[3])
b, kb = warns(sys.argv[4])
if set(kb) != {'unused-parameter'} or set(ka) - {'unused-parameter'}:
    sys.exit('  %-12s with -Wunused-parameter ON the output warns about %s -- if a '
             'deletion had reached an object the compiler would have said '
             '`unused-variable`, and this section is what would catch it'
             % (TAG, ' '.join(sorted(set(kb) | set(ka)))))
new = b - a
if b < a or not new:
    sys.exit('  %-12s the output warns %d times and the input %d, and every input '
             'warning must still be there with more beside it' % (TAG, len(b), len(a)))
sites = sorted({old.count('\n', 0, m.start()) + 1
                for m in re.finditer(r'__attribute__\(\(unused\)\)', old)})
n_sites = len(re.findall(r'__attribute__\(\(unused\)\)', old))
stray = sorted(w for w in new if w[0] not in sites)
if stray:
    sys.exit('  %-12s %d of the new warnings are not on a line that carried an '
             'attribute: %s' % (TAG, len(stray), stray[:5]))
# 113 sites, 92 warnings.  The other 21 marked a parameter this build USES, and naming
# them is the point: the attribute was not redundant there, it was FALSE.  Counted PER
# SITE and not per line -- eleven lines carry more than one attribute, and one of a
# line's two can warn while the other does not.
per_line = {}
for m in re.finditer(r'__attribute__\(\(unused\)\)', old):
    i = old.count('\n', 0, m.start()) + 1
    per_line[i] = per_line.get(i, 0) + 1
short = [(i, per_line[i] - sum(1 for w in new if w[0] == i)) for i in sorted(per_line)]
used = [(i, k) for i, k in short if k]
if sum(k for _, k in used) != n_sites - len(new):
    sys.exit('  %-12s the per-site arithmetic does not add up: %d sites, %d warnings, '
             '%d unaccounted' % (TAG, n_sites, len(new),
                                 sum(k for _, k in used) - (n_sites - len(new))))


def fname(i):
    m = re.match(r'^(\w+)', OL[i - 1])
    return m.group(1) if m else '?'


print('  %-12s WITH `-Wunused-parameter` TURNED BACK ON -- the one warning the sweep '
      'switches off -- the output warns %d times and the input %d, and every one of the '
      '%d new is `-Wunused-parameter` at a line that carried an attribute.  Not one is '
      '`-Wunused-variable`, which is what a deletion that reached an object would have '
      'produced' % (TAG, len(b), len(a), len(new)))
print('  %-12s AND %d SITES GAVE %d WARNINGS, so %d OF THE %d MARKED A PARAMETER THIS '
      'BUILD USES -- the attribute was not redundant there, it was FALSE, and deleting '
      'it deletes a wrong statement rather than a useless one.  In %d functions, among '
      'them %s' % ('', n_sites, len(new), n_sites - len(new), n_sites, len(used),
                   ', '.join('%s()' % fname(i) for i, _ in used[:6])))
PY

# --- 3. the fallthroughs, and the two that are redundant ----------------------------------
# `-Wextra` enables `-Wimplicit-fallthrough=3`, so the sweep already covers this and
# tools/phasecheck.sh's silence below is the primary evidence.  It is asserted here
# separately because 20 suppressions changing spelling is exactly the kind of thing that
# can go half right, and because the control is what says the warning was ever on.
wait $pid_c3 $pid_c3s
python3 - "$f" "$tmp/w.c3" "$tmp/w.c3syn" <<'PY'
import re
import subprocess
import sys

TAG = 'attrs'
new = open(sys.argv[1], errors='surrogateescape').read()
NL = new.split('\n')
ctl = open(sys.argv[2], errors='surrogateescape').read()
syn = open(sys.argv[3], errors='surrogateescape').read()

sites = [i + 1 for i, l in enumerate(NL) if l.strip() == '[[fallthrough]];']
n = len(re.findall(r'may fall through', ctl))
if n != len(sites) - 2:
    sys.exit('  %-12s the control -- this phase\'s own output with all %d '
             '`[[fallthrough]];` blanked -- warns %d times, and the phase was measured '
             'on %d.  Two of the %d sit after a case label with NO statement, where C '
             'falls through silently and gcc has nothing to diagnose; a third one '
             'becoming redundant, or one of those two becoming live, is a change in the '
             'switch and not in this phase' % (TAG, len(sites), n, len(sites) - 2,
                                               len(sites)))
if re.search(r'may fall through', syn):
    sys.exit('  %-12s `-fsyntax-only` reported a fallthrough warning, and the note at '
             'the top of this file says it cannot -- if that has changed, the reason '
             'this section uses a real compile has changed with it' % TAG)
if not re.search(r'\bwarning\b', ctl) or '-Wimplicit-fallthrough' not in ctl:
    sys.exit('  %-12s the control produced no `-Wimplicit-fallthrough` warning at all, '
             'so this section is checking nothing' % TAG)
# WHICH TWO, AND IT IS NOT DONE BY MATCHING WARNINGS TO SITES.  gcc reports the warning
# at the last statement of the falling case, which can be hundreds of lines above the
# attribute -- measured, one is 309 lines up -- so assigning warnings to sites by
# distance gets it wrong, and did: it named line 11731, which warns.  What is computed
# instead is the STRUCTURE, independently of the compiler: a site whose preceding
# statement is a bare label has no statement to fall out of, which is where C falls
# through silently.  The two methods then have to agree on the NUMBER.
quiet = []
for s in sites:
    j = s - 2
    while j >= 0 and not NL[j].strip():
        j -= 1
    if j >= 0 and NL[j].strip().endswith(':'):
        quiet.append((s, NL[j].strip()))
if len(quiet) != len(sites) - n:
    sys.exit('  %-12s %d of the %d sites follow a bare label and the control leaves %d '
             'unwarned -- the structure and the compiler must agree on WHICH are '
             'already redundant, and they do not: %s'
             % (TAG, len(quiet), len(sites), len(sites) - n,
                ' '.join('%d %r' % q for q in quiet)))
print('  %-12s `-Wimplicit-fallthrough` is silent on the output, and the control -- all '
      '%d `[[fallthrough]];` blanked -- warns %d times.  So the C23 spelling suppresses '
      'exactly what the GNU one did and not one of the %d suppressions was lost'
      % (TAG, len(sites), n, len(sites)))
print('  %-12s %d OF THE %d ARE ALREADY REDUNDANT AND THEY ARE KEPT: %s.  Each follows '
      'a case label with no statement at all, where the language falls through silently '
      'and gcc has nothing to diagnose -- computed from the STRUCTURE and agreeing with '
      'the control on the number, which is two independent methods rather than one.  '
      'What makes a fallthrough deliberate is the author saying so, not the compiler '
      'currently asking; pruning them would be pruning by the shape of a switch that a '
      'later phase may change back'
      % ('', len(quiet), len(sites),
         ', '.join('line %d after %r' % q for q in quiet)))
print('  %-12s AND THE TOOL MATTERS: the same control under `-fsyntax-only` warns ZERO '
      'times, because -Wimplicit-fallthrough needs the CFG.  That is CLAUDE.md\'s '
      '`-fsyntax-only` lesson on a second warning -- a section written with it would '
      'have passed while checking nothing' % '')
PY

# --- 4. C23, and that it is not a new dependency -------------------------------------------
# The statement is taken OUT OF THE OUTPUT rather than written here again, so this cannot
# pass while the file says something else.
grep -m1 -o '\[\[fallthrough\]\];' "$f" > "$tmp/stmt.txt" || {
    echo '  attrs        there is no [[fallthrough]]; in the output to take'
    exit 1
}
cat > "$tmp/ft.c" <<EOF
static int f(int x)
{
    int r = 0;
    switch (x)
    {
    case 1:
        r = 1;
        $(cat "$tmp/stmt.txt")
    case 2:
        r += 2;
        break;
    }
    return r;
}
int main(void) { return f(1) - 3; }
EOF
sed 's/\[\[fallthrough\]\];/__attribute__((fallthrough));/' "$tmp/ft.c" > "$tmp/gnu.c"
for std in DEFAULT -std=c23; do
    s=$([ "$std" = DEFAULT ] && echo '' || echo "$std")
    # shellcheck disable=SC2086
    if ! gcc $s -Wall -Wextra -Wpedantic -Wimplicit-fallthrough -o "$tmp/ft" "$tmp/ft.c" 2>"$tmp/ft.err"; then
        echo "  attrs        $(cat "$tmp/stmt.txt") is REFUSED under $std, and this phase requires it:"
        sed 's/^/               /' "$tmp/ft.err" | head -4
        exit 1
    fi
    if [ -s "$tmp/ft.err" ]; then
        echo "  attrs        the C23 statement draws a diagnostic under $std -Wpedantic, and it must not:"
        sed 's/^/               /' "$tmp/ft.err" | head -4
        exit 1
    fi
    "$tmp/ft" || { echo "  attrs        the probe ran and the fallthrough did not fall through"; exit 1; }
done
for std in -std=c11 -std=c99; do
    if gcc "$std" -pedantic-errors -c -o /dev/null "$tmp/ft.c" 2>/dev/null; then
        echo "  attrs        the C23 statement is ACCEPTED under $std -pedantic-errors, and it must not be:"
        echo '               `[[]]` attributes are C23, and a check that passes there is'
        echo '               not stating what this spelling costs.'
        exit 1
    fi
    if ! gcc "$std" -pedantic-errors -c -o /dev/null "$tmp/gnu.c" 2>/dev/null; then
        echo "  attrs        the GNU spelling is REFUSED under $std -pedantic-errors, and the honest"
        echo "               comparison this phase makes is that it is NOT -- a reserved identifier"
        echo "               is pedantically clean everywhere, which is what the swap gives up."
        exit 1
    fi
done
wait $pid_11o $pid_11n || true
e_old=$(grep -c 'error:' "$tmp/c11.old" || true)
e_new=$(grep -c 'error:' "$tmp/c11.new" || true)
if [ "$e_old" != "$e_new" ] || [ "$e_old" -lt 100 ]; then
    echo "  attrs        the whole file gives $e_old errors under -std=c11 before this phase and $e_new after."
    echo "               They must be equal and large: this file has been C23 since long before"
    echo "               this phase -- enum : long, static_assert, lowercase bool, and phase 23's"
    echo "               typeof and nullptr -- and respelling 20 attributes must not move the floor."
    exit 1
fi
echo "  attrs        C23 IS NOT A NEW DEPENDENCY AND WHAT THE SPELLING COSTS IS STATED RATHER THAN GLOSSED: the statement taken out of the output compiles clean under gcc's default and -std=c23 with -Wall -Wextra -Wpedantic, and its probe runs; under -std=c11 and -std=c99 -pedantic-errors it is REFUSED, where the GNU spelling it replaces is ACCEPTED, being a reserved identifier.  So this swap alone would narrow the dialects -- and it costs nothing, because the WHOLE FILE already gives the same $e_old errors under -std=c11 before this phase and after it"

# --- 5. -Wformat=2, WHICH IS THE EVIDENCE FOR THE SIX THE BINARY CANNOT GIVE ---------------
# Phase 22's invariant, asserted here for the opposite reason: there it proved 129
# expanded argument lists came out right, here it proves six attributes were not
# disturbed.  A binary-identical build says nothing about them -- measured, removing all
# six leaves the binary cmp-identical -- so this is the only section that can.
wait $pid_wo $pid_wn $pid_c1 $pid_c2
python3 - "$tmp/w.old" "$tmp/w.new" "$tmp/w.c1" "$tmp/w.c2" <<'PY'
import re
import sys

TAG = 'attrs'


def read(path):
    """gcc quotes an identifier as 'x' or 'x' depending on the locale (phase 22) --
    match both, or the function list comes back empty and the equality below passes
    for the wrong reason."""
    txt = open(path, errors='surrogateescape').read()
    n = len(re.findall(r'\[-Wformat-nonliteral\]', txt))
    fns = [m.group(1) or m.group(2) for m in
           re.finditer(r"In function (?:‘(\w+)’|'(\w+)')", txt)]
    return n, fns


no, fo = read(sys.argv[1])
nn, fn = read(sys.argv[2])
n1, _ = read(sys.argv[3])
n2, _ = read(sys.argv[4])
if no != nn or fo != fn:
    print('  %-12s -Wformat=2 MOVED: %d warnings in %d function headings before, %d in '
          '%d after -- the six attributes this phase KEEPS are what gcc reads to produce '
          'them' % (TAG, no, len(fo), nn, len(fn)))
    a, b = set(fo), set(fn)
    if a - b:
        print('  %-12s functions that stopped warning: %s' % ('', ' '.join(sorted(a - b))))
    if b - a:
        print('  %-12s functions that started: %s' % ('', ' '.join(sorted(b - a))))
    sys.exit(1)
if no != 115 or len(set(fo)) != 53:
    print('  %-12s -Wformat=2 gives %d warnings in %d distinct functions, expected 115 '
          'in 53 -- the equality above still holds, but this is not the tree the phase '
          'was measured on' % (TAG, no, len(set(fo))))
    sys.exit(1)
# THE CONTROLS, AND THEY BREAK IT IN OPPOSITE DIRECTIONS.
if n1 != 0 or n2 <= no:
    print('  %-12s THE CONTROLS DID NOT SHOW.  Removing vim_snprintf\'s '
          'format(printf, 3, 4) gives %d warnings and must give 0 -- gcc stops checking '
          'formats at all -- and removing `_()`\'s format_arg(1) gives %d and must give '
          'MORE than %d, gcc losing the ability to see through the translation wrapper.  '
          'Without both, the equality above is two numbers agreeing (CLAUDE.md)'
          % (TAG, n1, n2, no))
    sys.exit(1)
print('  %-12s -Wformat=2: THE IDENTICAL %d `-Wformat-nonliteral` warnings in THE '
      'IDENTICAL %d functions, before and after.  THIS IS THE EVIDENCE FOR THE SIX '
      'SURVIVORS AND THE BINARY CANNOT GIVE IT: an attribute emits no code, so a '
      'cmp-identical build is equally happy without them' % (TAG, no, len(set(fo))))
print('  %-12s AND IT CAN FAIL, IN BOTH DIRECTIONS.  With vim_snprintf\'s '
      'format(printf, 3, 4) removed the count is %d -- gcc checks no format anywhere, '
      'and phase 22 is why one attribute now carries 201 `vim_snprintf` mentions.  With '
      '`_()`\'s format_arg(1) removed it is %d, %d MORE: that attribute is what lets '
      '-Wformat see THROUGH the translation wrapper, which CLAUDE.md names as the reason '
      '`_()` and `NGETTEXT` were never macro-expanded' % ('', n1, n2, n2 - no))
PY
# AND WHAT THE ATTRIBUTE BUYS, from the output's own prototype line rather than a
# retyped one: a `%d` handed a `const char *`.
grep -m1 '^static int vim_snprintf(char \*, .*format(printf, 3, 4)' "$f" > "$tmp/proto.txt" || true
grep -m1 '^typedef typeof(sizeof(0)) usize;$' "$f" > "$tmp/typedef.txt" || true
if [ ! -s "$tmp/proto.txt" ] || [ ! -s "$tmp/typedef.txt" ]; then
    echo "  attrs        vim_snprintf's prototype, or phase 23's usize typedef, is not in the"
    echo "               output in the shape this probe reads them -- the probe is built from"
    echo "               the output's own lines and not from retyped ones, so it cannot pass"
    echo "               while the file says something else."
    exit 1
fi
{ cat "$tmp/typedef.txt" "$tmp/proto.txt"
  echo 'int probe(char *b, const char *s) { return vim_snprintf(b, 10, "%d", s); }'; } > "$tmp/fmt.c"
sed 's/  __attribute__((format(printf, 3, 4))) / /' "$tmp/fmt.c" > "$tmp/nofmt.c"
cmp -s "$tmp/fmt.c" "$tmp/nofmt.c" && { echo "  attrs        the probe and its control are the same text"; exit 1; }
gcc -c -Wall -Wextra -o /dev/null "$tmp/fmt.c" 2>"$tmp/fmt.err" || true
gcc -c -Wall -Wextra -o /dev/null "$tmp/nofmt.c" 2>"$tmp/nofmt.err" || true
if ! grep -q 'expects argument of type' "$tmp/fmt.err"; then
    echo "  attrs        the %d probe did not warn WITH the attribute, so it is not a probe:"
    sed 's/^/               /' "$tmp/fmt.err" | head -4
    exit 1
fi
if grep -q 'expects argument of type' "$tmp/nofmt.err"; then
    echo "  attrs        the %d probe warned WITHOUT the attribute, so the attribute is not what catches it"
    exit 1
fi
echo "  attrs        AND WHAT IT BUYS, built from the output's OWN prototype and phase 23's OWN typedef: vim_snprintf(b, 10, \"%d\", s) handed a const char * draws $(grep -c 'expects argument of type' "$tmp/fmt.err") warning with the attribute and NOTHING AT ALL without it.  That is the whole argument for stopping at 133 removals and not 139"

# --- 6. the compile, the linkage and the libc surface ---------------------------------------
# NOTHING IS FREED AND NOTHING ARRIVES.  Deleting a diagnostic hint cannot move the libc
# surface, and a symbol ARRIVING must fail as loudly as one leaving.
cp "$state/symbols/undefined" "$tmp/before.u"
tools/phasecheck.sh "$work" "$f" "$state/symbols"
if ! cmp -s "$tmp/before.u" .cache/symbols/last/undefined; then
    echo "  attrs        the libc surface moved, and DELETING A DIAGNOSTIC HINT CANNOT MOVE IT:"
    echo "               gone: $(comm -23 "$tmp/before.u" .cache/symbols/last/undefined | tr '\n' ' ')"
    echo "               came: $(comm -13 "$tmp/before.u" .cache/symbols/last/undefined | tr '\n' ' ')"
    exit 1
fi
echo "  attrs        symbols $(cat .cache/symbols/last/before) -> $(cat .cache/symbols/last/after), and the set is IDENTICAL as a cmp -- nothing left and nothing arrived; main is still the only external symbol"

# --- 7. the binary, which is the whole of this phase's evidence for the 133 ------------------
wait $pid_canon
if ! cmp -s "$tmp/canon.c" "$f"; then
    echo "  attrs        tools/canon.sh CHANGED THE OUTPUT, and it must be a no-op:"
    diff "$f" "$tmp/canon.c" | head -6 | sed 's/^/               /'
    echo "               The 113 deletions take the two spaces before the attribute and"
    echo "               the one after with them.  If canon moved something, the edit is"
    echo "               wrong and canon is not the fix."
    exit 1
fi
echo "  attrs        tools/canon.sh is a NO-OP on the output ($(sed -n 's/.*canon *//p' "$tmp/canon.log" | head -1))"

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

wait $pid_new || { echo "  attrs        the reproducible build of the output failed"; exit 1; }
old_size=$(stat -c%s "$state/old")
new_size=$(stat -c%s "$tmp/new")
# A cmp of two files that were never written passes.  Both must exist, both must be the
# size of an editor, and the one under test must be the size make just produced.
if [ "$new_size" -lt 500000 ] || [ "$old_size" -lt 500000 ]; then
    echo "  attrs        one of the two binaries is $old_size / $new_size bytes, which is not an editor -- a cmp of two files nothing wrote passes"
    exit 1
fi
if [ "$new_size" != "$(stat -c%s "$bin")" ]; then
    echo "  attrs        the reproducible build is $new_size bytes and make produced $(stat -c%s "$bin"): the two differ by more than a timestamp, so the comparison below would not be about this boundary"
    exit 1
fi
if ! cmp -s "$state/old" "$tmp/new"; then
    echo "  attrs        THE BINARY MOVED.  This phase deletes 113 attributes that only"
    echo "               ever suppressed a diagnostic and respells 20 that only ever"
    echo "               gave one a hint, so the two binaries -- the input's and the"
    echo "               output's, both built with SOURCE_DATE_EPOCH=0 and the"
    echo "               boundary's own flags -- must be the same bytes."
    echo "               $old_size in, $new_size out.  The GNU build-id note is a hash of"
    echo "               the whole image and sits near the front, so the first difference"
    echo "               below is always that note and never the change itself:"
    cmp "$state/old" "$tmp/new" 2>&1 | sed 's/^/               /'
    exit 1
fi
echo "  attrs        THE BINARY IS BYTE-IDENTICAL, $new_size bytes either side -- tier 1 of CLAUDE.md's verification table, and the whole of this phase's evidence for the 133 it removed and respelled.  A byte-identical binary subsumes every screen case, every Ex-command row, every command line and every pty scenario at once, because the program that would be run is the same program; tools/zerodelta.sh --phase 24 runs next and corroborates rather than proves"

wait $pid_c4 || { echo "  attrs        the control c4 did not build:"; head -5 "$tmp/c4.log" | sed 's/^/               /'; exit 1; }
if cmp -s "$state/old" "$tmp/c4"; then
    echo "  attrs        THE CONTROL c4 DID NOT SHOW.  This phase's own output with one"
    echo "               \`[[fallthrough]];\` replaced by \`break;\` gives a binary IDENTICAL"
    echo "               to the input's, so the cmp above is two numbers agreeing and"
    echo "               proves nothing.  A test that cannot fail is not evidence"
    echo "               (CLAUDE.md)."
    exit 1
fi
echo "  attrs        AND IT CAN FAIL: this phase's own output with ONE \`[[fallthrough]];\` replaced by \`break;\` -- the smallest change at these 20 sites that is a change to the PROGRAM and not to a diagnostic -- differs from the input's binary in $(cmp -l "$state/old" "$tmp/c4" | wc -l) bytes"

# tools/phaserun.sh runs tools/zerodelta.sh --phase 24 after this check, and this phase
# declares NOTHING: the corpus must not move at all.
