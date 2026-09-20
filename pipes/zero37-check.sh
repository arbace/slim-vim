#!/bin/sh
# Zero phase 37, the check -- the degenerate unions go.
# See pipes/zero37-edit.sh, and ZERO-GOAL.md.
#
# Usage: pipes/zero37-check.sh <work-dir> <state-dir>    (run from the repository root)
#
# Runs after pipes/zero37-edit.sh and the sweep tools/phaserun.sh runs between them, and
# reads nothing from the edit's shell -- only the work tree and the state directory.
# What the edit left there is `old.c`, the source this phase was HANDED, and `old`, that
# source built with SOURCE_DATE_EPOCH=0 and the boundary's own flags.
#
# THIS PHASE CHANGES NO STATEMENT AND NO LAYOUT, so there is no behavioural probe to
# offer and none is offered.  What it has instead is stronger than any recording: THE
# BINARY IS THE SAME BYTES.  That is tier 1 of CLAUDE.md's verification table, and it
# subsumes every screen case, every Ex-command row, every command line and every pty
# scenario at once, because the program that would be run is literally the same program.
# It is phase 16's and phase 23's kind of empty declaration -- THE STRONGEST OF THE FIVE
# and not the weakest -- and this check says which kind it is rather than leaving a
# reader to guess.
#
# WHAT IS CLAIMED, in eight parts:
#
#   ARITHMETIC  the whole of it is RECOMPUTED FROM THE INPUT by the edit's own scanner,
#               run again here: the input's thirteen unions are classified by member
#               count, the six with fewer than two members must be gone and the seven
#               with two or more must survive BYTE FOR BYTE, each degenerate name must
#               keep its declaration and every `.member` access on it must be a plain
#               field reference.  Not one of those numbers is written in this file, which
#               is the lesson phase 35 was taught when phase 34 moved its counted
#               anchors.
#   THE DIALECT the empty union's own argument, MEASURED.  `union { } es_info;` is a GNU
#               C extension: gcc reports `union has no members [-Wpedantic]` on the input
#               exactly once and on the output not at all, with the rest of the pedantic
#               diagnostic set unmoved, and a minimal probe shows the same construct is a
#               hard ERROR under `-pedantic-errors` while its non-empty twin is silent.
#   SYMBOLS     `nm -u` is THE SAME SET, as a `comm` empty in BOTH directions, and `main`
#               is still the only external symbol.  Deleting a wrapper type inside one
#               translation unit cannot move either, and a symbol ARRIVING must fail as
#               loudly as one leaving.
#   THE CUT     `awk '/^ *# *include / { exit }'`, zero.mk's own rule, on the INPUT and on
#               the OUTPUT: 0 directives and 0 errors under `-fsyntax-only` either side,
#               and the warning set -- which IS the core -> host interface -- IDENTICAL,
#               computed at run time from the input and never written down.
#   THE BINARY  `cmp` of the input's binary and the output's, both built with
#               SOURCE_DATE_EPOCH=0 and the boundary's own flags.  This is the whole
#               evidence.
#   THE CONTROL and it is the point.  c1 is this phase's own output with the two fields it
#               PROMOTED -- `uh_next` and `uh_prev` -- exchanged: a pure layout
#               permutation of the very struct this phase rewrites, which compiles and
#               must give a DIFFERENT binary.  Measured: 31,038 bytes differ.  Without it
#               the `cmp` above is a pair of numbers agreeing, and CLAUDE.md is explicit
#               that a test that cannot fail is not evidence.
#   TWO THAT MOVE NOTHING, REPORTED RATHER THAN DROPPED.  c2 puts the EMPTY union back
#               and c3 puts one SINGLE-MEMBER union back with its `.member` accesses --
#               this phase run backwards on one field each.  Both must be byte-identical,
#               which is the phase's own claim stated in the other direction: a union of
#               one member and a plain field are the same program, and an empty union is
#               no program at all.  If either ever moves, this phase's account of itself
#               has to be rewritten rather than the number quietly updated.
#   STRUCTURE   tools/canon.sh is a no-op on the output, and `zhostonly` -- phase
#               20's structural check -- still passes.
#
# AND TWO FULL RECORDINGS, WHICH ARE A CHECK ON THE HARNESS AND NOT ON THE PHASE.  With a
# byte-identical binary a `tools/zrecord.sh` of each side compares a program with itself,
# so an empty `diff -r` says the instrument is deterministic and says nothing about the
# edit.  They are run because it is cheaper to measure that than to assert it, and this
# comment is what keeps them from being read as the evidence.  The evidence is the `cmp`.
set -eu

work=${1:?usage: zero37-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero37-check.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"
before_lines=$(cat "$state/input-lines")

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")

# The reproducible build of the OUTPUT and the three controls are started first and
# waited for below.  Every control is this phase's own product with ONE thing changed.
# shellcheck disable=SC2086
( SOURCE_DATE_EPOCH=0 gcc $cflags $ldflags -o "$tmp/new" "$f" ) &
pid_new=$!
python3 - "$f" "$state/old.c" "$tmp" <<'PY'
import re
import sys

TAG = 'unions'
new = open(sys.argv[1], errors='surrogateescape').read()
old = open(sys.argv[2], errors='surrogateescape').read()
out = sys.argv[3]


def die(msg):
    sys.exit('  %-12s %s' % (TAG, msg))


# THE CONTROLS ARE BUILT FROM THE INPUT'S OWN TEXT, not from C quoted here.  A check
# that quotes C is a dependency on spelling (CLAUDE.md, and zero 22-23 measured it), and
# a control is the one place that dependency would be invisible.
#
# c1 -- THE TWO FIELDS THIS PHASE PROMOTED, EXCHANGED.  A pure layout permutation of
#       `struct u_header`: the same program, different offsets.  It must build and it
#       must give a different binary, and that is what says the `cmp` below is about
#       this struct's layout and not about two numbers agreeing.
# c2 -- THE EMPTY UNION PUT BACK.  Declared to change nothing.
# c3 -- ONE SINGLE-MEMBER UNION PUT BACK, with its `.member` accesses.  This phase run
#       backwards on one field, and declared to change nothing.
def scan(text, which):
    """Every `union { ... } name;` in the text, with its member count.  The edit's own
    scanner, run again here on the INPUT, so the classification is recomputed and not
    remembered."""
    found = []
    for m in re.finditer(r'\bunion\b', text):
        j = m.end()
        while j < len(text) and text[j] in ' \t\n':
            j += 1
        if j >= len(text) or text[j] != '{':
            die('the `union` at line %d of the %s is not followed by a brace'
                % (text.count('\n', 0, m.start()) + 1, which))
        depth, k, members = 0, j, 0
        while k < len(text):
            c = text[k]
            if c == '{':
                depth += 1
            elif c == '}':
                depth -= 1
                if depth == 0:
                    break
            elif c == ';' and depth == 1:
                members += 1
            k += 1
        tail = re.match(r'([ \t]*)([A-Za-z_]\w*)[ \t]*;', text[k + 1:])
        if not tail:
            die('the union at line %d of the %s does not end `} <name>;`'
                % (text.count('\n', 0, m.start()) + 1, which))
        start = text.rindex('\n', 0, m.start()) + 1
        found.append({'name': tail.group(2), 'members': members,
                      'indent': text[start:m.start()], 'start': start,
                      'body': text[j + 1:k], 'end': k + 1 + tail.end(),
                      'text': text[start:k + 1 + tail.end() + 1]})
    return found


IN = scan(old, 'input')
deg = [u for u in IN if u['members'] < 2]
gen = [u for u in IN if u['members'] >= 2]
if len(deg) < 2 or not gen:
    die('the input has %d degenerate unions and %d genuine ones, and this check needs at '
        'least two of the first and one of the second -- a scanner that stopped matching '
        'would pass by finding nothing' % (len(deg), len(gen)))

# c1: the first two single-member fields the phase promoted, whose promoted declarations
# are adjacent lines in the output.  Which two is computed; the text is the output's.
promoted = []
for u in deg:
    if not u['members']:
        continue
    mm = re.match(r'^(.*?)([A-Za-z_]\w*)[ \t]*;$', u['body'].strip(), re.S)
    if not mm:
        die('the single member of `%s` is not one `<type> <name>;`' % u['name'])
    promoted.append((u['name'], u['indent'] + mm.group(1) + u['name'] + ';\n'))
pair = None
for (n1, d1), (n2, d2) in zip(promoted, promoted[1:]):
    if new.count(d1 + d2) == 1:
        pair = (n1, n2, d1, d2)
        break
if pair is None:
    die('no two promoted declarations are adjacent lines in the output, so the layout '
        'control cannot be built out of this phase\'s own subject')
c1 = new.replace(pair[2] + pair[3], pair[3] + pair[2], 1)

# c2: the empty union put back where it was, computed from the input -- the line above it
# in the input is the anchor, and it is the input's text and not this file's.
empty = [u for u in deg if not u['members']]
if len(empty) != 1:
    die('the input has %d empty unions and this check was written for one' % len(empty))
e = empty[0]
above = old[old.rindex('\n', 0, e['start'] - 1) + 1:e['start']]
if new.count(above) != 1 or old.count(above + e['text']) != 1:
    die('the line above the empty union is not a unique anchor in both texts, so c2 '
        'cannot be put back where it was')
c2 = new.replace(above, above + e['text'], 1)

# c3: one single-member union put back, with its accesses.  The declaration line splits
# the output, both halves get the `.member` back, and the input's own union text goes in
# between -- so the control is the phase reversed and not a rewrite of it.
s = [u for u in deg if u['members']][-1]
mm = re.match(r'^(.*?)([A-Za-z_]\w*)[ \t]*;$', s['body'].strip(), re.S)
if not mm:
    die('the single member of `%s` is not one `<type> <name>;`' % s['name'])
member = mm.group(2)
decl = s['indent'] + mm.group(1) + s['name'] + ';\n'
if new.count(decl) != 1:
    die('`%s` is not declared exactly once in the output as the promoted field' % s['name'])
i = new.index(decl)
c3 = (re.sub(r'\b%s\b' % s['name'], '%s.%s' % (s['name'], member), new[:i])
      + s['text']
      + re.sub(r'\b%s\b' % s['name'], '%s.%s' % (s['name'], member),
               new[i + len(decl):]))

for name, text in (('c1', c1), ('c2', c2), ('c3', c3)):
    if text == new:
        die('%s changed nothing, so it would not be a control' % name)
    open('%s/%s.c' % (out, name), 'w', errors='surrogateescape').write(text)
print('  %-12s three controls written, every one of them built from the input\'s own '
      'text and not from C quoted in the check: c1 the two fields this phase PROMOTED '
      '(`%s` and `%s`) EXCHANGED -- a pure layout permutation of the struct it rewrites, '
      'which must move the binary; c2 the empty union `%s` put back; c3 the '
      'single-member union `%s` put back with its %d `.%s` accesses -- this phase run '
      'backwards on one field'
      % (TAG, pair[0], pair[1], e['name'], s['name'],
         len(re.findall(r'\b%s\b' % s['name'], new)) - 1, member))
PY
pid_ctl=''
for c in c1 c2 c3; do
    # shellcheck disable=SC2086
    # The stderr goes to a log rather than the terminal: these build in the background
    # while the assertions below decide, and an assertion that refuses first takes the
    # temp directory with it.
    ( SOURCE_DATE_EPOCH=0 gcc $cflags $ldflags -o "$tmp/$c" "$tmp/$c.c" 2>"$tmp/$c.log" ) &
    pid_ctl="$pid_ctl $!"
done

# The pedantic measurement, on both sides, in the background: it is a full parse of an
# eighty-thousand-line file twice and nothing below section 2 depends on it.
( gcc $cflags -fsyntax-only -Wpedantic "$state/old.c" 2>"$tmp/ped-old.txt" || true ) &
pid_po=$!
( gcc $cflags -fsyntax-only -Wpedantic "$f" 2>"$tmp/ped-new.txt" || true ) &
pid_pn=$!

# tools/canon.sh must be a NO-OP on the output.
cp "$f" "$tmp/canon.c"
( tools/canon.sh "$tmp/canon.c" >"$tmp/canon.log" 2>&1 ) &
pid_canon=$!

# --- 1. the source, as arithmetic on the input ------------------------------------------
python3 - "$f" "$state/old.c" "$before_lines" <<'PY'
import re
import sys

TAG = 'unions'
new = open(sys.argv[1], errors='surrogateescape').read()
old = open(sys.argv[2], errors='surrogateescape').read()
before_lines = int(sys.argv[3])
fail = []
NL, OL = new.split('\n'), old.split('\n')


def scan(text, which):
    found = []
    for m in re.finditer(r'\bunion\b', text):
        j = m.end()
        while j < len(text) and text[j] in ' \t\n':
            j += 1
        if j >= len(text) or text[j] != '{':
            sys.exit('  %-12s the `union` at line %d of the %s is not followed by a '
                     'brace' % (TAG, text.count('\n', 0, m.start()) + 1, which))
        depth, k, members = 0, j, 0
        while k < len(text):
            c = text[k]
            if c == '{':
                depth += 1
            elif c == '}':
                depth -= 1
                if depth == 0:
                    break
            elif c == ';' and depth == 1:
                members += 1
            k += 1
        tail = re.match(r'([ \t]*)([A-Za-z_]\w*)[ \t]*;', text[k + 1:])
        if not tail:
            sys.exit('  %-12s the union at line %d of the %s does not end `} <name>;`'
                     % (TAG, text.count('\n', 0, m.start()) + 1, which))
        start = text.rindex('\n', 0, m.start()) + 1
        found.append({'name': tail.group(2), 'members': members,
                      'indent': text[start:m.start()], 'body': text[j + 1:k],
                      'line': text.count('\n', 0, m.start()) + 1,
                      'text': text[start:k + 1 + tail.end() + 1]})
    return found


def halves(lines, which):
    """The core and the host, split at the first `#include` and nowhere else."""
    d = [i for i, l in enumerate(lines) if re.match(r'^ *#', l)]
    if not d or d != list(range(d[0], d[0] + len(d))) \
            or any(not re.match(r'^ *# *include <[A-Za-z0-9_/.]+>$', lines[i]) for i in d):
        sys.exit('  %-12s the `#include` directives are not a run of consecutive lines '
                 'in the %s -- the first of them IS the boundary and nothing else marks '
                 'it' % (TAG, which))
    return d[0], len(d)


obound, ondir = halves(OL, 'input')
nbound, nndir = halves(NL, 'output')

# THE CLASSIFICATION, RECOMPUTED.  Nothing here is a name or a count this file states.
IN = scan(old, 'input')
OUT = scan(new, 'output')
deg = [u for u in IN if u['members'] < 2]
gen = [u for u in IN if u['members'] >= 2]
if not deg or not gen:
    fail.append('the input has %d degenerate unions and %d genuine ones, and this phase '
                'needs both kinds to exist -- a scanner that stopped matching would pass '
                'by finding nothing' % (len(deg), len(gen)))
if any(u['line'] > obound for u in IN):
    fail.append('a union is defined below the boundary, in the host, and this phase is '
                'about the CORE')

# THE SEVEN THAT STAY, BYTE FOR BYTE.  Their text is taken out of the INPUT and required
# to occur once in the output, so a phase that had rewritten one of them -- which is the
# mistake that would change a layout -- fails here and not at the `cmp` alone.
for u in gen:
    if new.count(u['text']) != 1 or old.count(u['text']) != 1:
        fail.append('the genuine union `%s` (%d members) does not occur exactly once in '
                    'both texts: %d in, %d out -- a union with two or more members is '
                    'doing the job a union is for and this phase must not touch it'
                    % (u['name'], u['members'], old.count(u['text']),
                       new.count(u['text'])))
if [u['name'] for u in OUT] != [u['name'] for u in gen]:
    fail.append('the output\'s unions are %s and the input\'s genuine ones are %s'
                % (' '.join(u['name'] for u in OUT) or 'none',
                   ' '.join(u['name'] for u in gen)))
n_key_in = len(re.findall(r'\bunion\b', old))
n_key_out = len(re.findall(r'\bunion\b', new))
if n_key_in != len(IN) or n_key_out != len(gen):
    fail.append('`union` is %d keywords in the input and %d in the output, and the scan '
                'found %d unions in and %d genuine -- every keyword must be one of the '
                'definitions the scan classified'
                % (n_key_in, n_key_out, len(IN), len(gen)))

# THE SIX THAT GO, EACH AS A PARTITION OF ITS OWN MENTIONS IN THE INPUT.
lines_gone = 0
for u in deg:
    n_in = len(re.findall(r'\b%s\b' % u['name'], old))
    n_out = len(re.findall(r'\b%s\b' % u['name'], new))
    if u['members']:
        mm = re.match(r'^(.*?)([A-Za-z_]\w*)[ \t]*;$', u['body'].strip(), re.S)
        if not mm:
            fail.append('the single member of `%s` is not one `<type> <name>;`' % u['name'])
            continue
        member, decl = mm.group(2), u['indent'] + mm.group(1) + u['name'] + ';'
        acc = len(re.findall(r'\b%s\.%s\b' % (u['name'], member), old))
        if acc != n_in - 1:
            fail.append('`%s` has %d mentions in the INPUT of which %d are `.%s` '
                        'accesses, and every mention but its own declaration must be one '
                        '-- the partition is what makes the rewrite safe'
                        % (u['name'], n_in, acc, member))
        elif n_out != n_in:
            fail.append('`%s` has %d mentions in the output and %d in the input, and the '
                        'two must be EQUAL: the union\'s own name survives on the '
                        'promoted declaration and on every one of the %d accesses, which '
                        'are now plain field references.  What goes is the MEMBER\'s '
                        'name, `%s`, and that is asserted below as the access shape '
                        'rather than as a count -- other structs in this file have a '
                        'member of the same name' % (u['name'], n_out, n_in, acc, member))
        if new.count(decl + '\n') != 1:
            fail.append('`%s` is not declared exactly once in the output as `%s`, which '
                        'is its member\'s OWN declaration with the union\'s name -- the '
                        'type, the stars and the spacing are the input\'s'
                        % (u['name'], decl.strip()))
        if re.search(r'\b%s\s*\.\s*%s\b' % (u['name'], member), new):
            fail.append('a `%s.%s` access survives in the output' % (u['name'], member))
    else:
        if n_in != 1:
            fail.append('the empty union `%s` has %d mentions in the input, and an empty '
                        'union has no member to access, so its declaration is the only '
                        'one there can be' % (u['name'], n_in))
        if n_out:
            fail.append('`%s` still has %d mentions in the output' % (u['name'], n_out))
    lines_gone += u['text'].count('\n') - (1 if u['members'] else 0)

# THE LINE ARITHMETIC, computed from the spans above and not written here.
if len(OL) - 1 != before_lines:
    fail.append('the input is %d lines and the driver recorded %d'
                % (len(OL) - 1, before_lines))
if len(NL) - 1 != before_lines - lines_gone:
    fail.append('the file is %d lines and the input was %d -- the six declarations are '
                '%d lines shorter between them' % (len(NL) - 1, len(OL) - 1, lines_gone))
if nndir != ondir:
    fail.append('the file has %d directives and had %d: this phase adds none and removes '
                'none' % (nndir, ondir))
if obound - nbound != lines_gone:
    fail.append('the boundary moved by %d lines and the file by %d: every line this '
                'phase touches is above the first `#include`'
                % (obound - nbound, lines_gone))

# THE SHAPE OF THE FILE.  Nothing here is a command, an option or a normal-mode key, and
# the counts are the input's rather than three numbers written down.
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
if sum(1 for k in range(1, len(NL)) if NL[k] == '' and NL[k - 1] == ''):
    fail.append('there is a run of two blank lines, which canon.sh should have taken')

if fail:
    for line in fail:
        print('  %-12s %s' % (TAG, line))
    sys.exit(1)
print('  %-12s `union` %d -> %d, AND WHICH SIX GO IS COMPUTED AND NOT LISTED: the input '
      'is scanned, the braces matched and the members counted at depth 1, and a union '
      'with fewer than two is degenerate.  THE %d THAT GO: %s.  THE %d THAT STAY ARE '
      'DOING THE JOB A UNION IS FOR and their text occurs once in BOTH files, byte for '
      'byte: %s'
      % (TAG, n_key_in, n_key_out, len(deg),
         ', '.join('%s (%s)' % (u['name'], 'empty' if not u['members'] else '1 member')
                   for u in deg),
         len(gen), ', '.join('%s (%d)' % (u['name'], u['members']) for u in gen)))
print('  %-12s EACH OF THE SIX IS A PARTITION OF ITS OWN MENTIONS IN THE INPUT -- the '
      'declaration and `.member` accesses, with nothing left over: %s.  Every access is '
      'now a plain field reference and not one survives; each promoted field is declared '
      'by its MEMBER\'S own declaration carrying the UNION\'S name, so the type, the '
      'stars and the internal spacing are the input\'s and not the phase\'s'
      % ('', ', '.join('%s 1 + %d' % (u['name'],
                                      len(re.findall(r'\b%s\b' % u['name'], old)) - 1)
                       for u in deg)))
print('  %-12s %d -> %d lines, %d fewer and every one of them above the boundary, which '
      'moved by the same %d; %d directives unmoved, cmdnames[] %d and options[] %d '
      'unchanged, and no run of two blank lines'
      % ('', before_lines, len(NL) - 1, lines_gone, lines_gone, nndir, n_new, opts(new)))
PY

# --- 2. the empty union's own argument, measured -------------------------------------------
# `union { } es_info;` is a GNU C extension and ISO C forbids it.  That is the reason the
# phase gives for the empty one, so it is measured rather than asserted: gcc names it on
# the input and not on the output, the rest of the pedantic diagnostic set does not move,
# and a minimal probe shows the same construct is a hard ERROR under `-pedantic-errors`
# while its non-empty twin is silent -- which is the probe proving it can pass, in the
# same run.
printf 'typedef struct { long a; union { } b; } S;\nS s;\nint main(void) { return (int)sizeof(S) + (int)s.a; }\n' > "$tmp/iso-empty.c"
printf 'typedef struct { long a; union { int c; } b; } S;\nS s;\nint main(void) { return (int)sizeof(S) + (int)s.a; }\n' > "$tmp/iso-full.c"
if gcc -pedantic-errors -fsyntax-only "$tmp/iso-empty.c" 2>"$tmp/iso-empty.log"; then
    echo "  unions       gcc ACCEPTS an empty union under -pedantic-errors, so this phase's"
    echo "               dialect argument for es_info does not hold and the sentence has to"
    echo "               be rewritten rather than the check relaxed."
    exit 1
fi
grep -q 'union has no members' "$tmp/iso-empty.log" || {
    echo "  unions       the ISO probe failed for some other reason than the empty union:"
    head -3 "$tmp/iso-empty.log" | sed 's/^/               /'
    exit 1
}
gcc -pedantic-errors -fsyntax-only "$tmp/iso-full.c" 2>"$tmp/iso-full.log" || {
    echo "  unions       the control probe -- the SAME struct with a one-member union -- does"
    echo "               not compile under -pedantic-errors either, so the probe above says"
    echo "               nothing about emptiness:"
    head -3 "$tmp/iso-full.log" | sed 's/^/               /'
    exit 1
}
wait $pid_po
wait $pid_pn
po=$(grep -c 'has no members' "$tmp/ped-old.txt" || true)
pn=$(grep -c 'has no members' "$tmp/ped-new.txt" || true)
to=$(grep -c 'warning:\|error:' "$tmp/ped-old.txt" || true)
tn=$(grep -c 'warning:\|error:' "$tmp/ped-new.txt" || true)
if [ "$po" != 1 ] || [ "$pn" != 0 ] || [ "$((to - tn))" != 1 ]; then
    echo "  unions       THE PEDANTIC MEASUREMENT DID NOT COME OUT AS THE PHASE CLAIMS."
    echo "               'has no members': $po in the input, $pn in the output, and the"
    echo "               whole diagnostic set went $to -> $tn, a difference of $((to - tn))"
    echo "               where it must be exactly the one line this phase removes."
    exit 1
fi
echo "  unions       THE EMPTY UNION'S OWN ARGUMENT, MEASURED AND NOT ASSERTED: gcc reports \`union has no members [-Wpedantic]\` $po time on the input and $pn on the output, and the rest of the pedantic diagnostic set does not move -- $to -> $tn, a difference of exactly one.  A minimal probe confirms the construct is a HARD ERROR under -pedantic-errors and that the identical struct with a ONE-member union is silent, so the probe is proven able to pass in the same run.  ZERO-GOAL.md's core is meant to be read by something that is not gcc, and a construct ISO C forbids is exactly the latent exotic that costs a reader later"

# --- 3. the compile, the linkage and the libc surface ---------------------------------------
# NOTHING IS FREED AND NOTHING ARRIVES.  Deleting a wrapper type inside one translation
# unit cannot move the libc surface, and a symbol ARRIVING must fail as loudly as one
# leaving.
cp "$state/symbols/undefined" "$tmp/before.u"
tools/phasecheck.sh "$work" "$f" "$state/symbols"
if ! cmp -s "$tmp/before.u" .cache/symbols/last/undefined; then
    echo "  unions       the libc surface moved, and DELETING A WRAPPER TYPE CANNOT MOVE IT:"
    echo "               gone: $(comm -23 "$tmp/before.u" .cache/symbols/last/undefined | tr '\n' ' ')"
    echo "               came: $(comm -13 "$tmp/before.u" .cache/symbols/last/undefined | tr '\n' ' ')"
    exit 1
fi
echo "  unions       symbols $(cat .cache/symbols/last/before) -> $(cat .cache/symbols/last/after), and the set is IDENTICAL as a cmp -- nothing left and nothing arrived; main is still the only external symbol"

# --- 4. the cut, and the core -> host interface it prints -------------------------------------
# zero.mk's own rule, one awk clause and no judgement, on the INPUT and on the OUTPUT.
# The cut's warnings ARE the interface: every name the core uses and the host defines is
# `used but never defined` there.  The input's set is COMPUTED here, never written down.
editorcut() {
    awk '/^ *# *include / { exit } { a[NR] = $0; if (NF) last = NR } \
         END { for (i = 1; i <= last; i++) print a[i] }' "$1" > "$2"
    if grep -q '^ *#' "$2"; then
        echo "  unions       the cut of $1 holds a directive, so it found the wrong line"
        exit 1
    fi
    if [ "$(grep -c '' "$2")" -le 70000 ]; then
        echo "  unions       the cut of $1 is $(grep -c '' "$2") lines, and zero.mk's floor is 70,000 -- a cut that found line 1 would be empty and every check below would pass on nothing"
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
        echo "  unions       the $w cut does not parse: $(cat "$tmp/cut-$w.c.err") errors"
        grep 'error:' "$tmp/cut-$w.c.log" | head -3 | sed 's/^/               /'
        exit 1
    fi
    if [ "$(grep -c 'warning:' "$tmp/cut-$w.c.log")" != "$(grep -c '' "$tmp/cut-$w.c.names")" ]; then
        echo "  unions       the $w cut has a warning that is not a 'used but never defined':"
        grep 'warning:' "$tmp/cut-$w.c.log" | grep -v 'used but never defined' | head -3 | sed 's/^/               /'
        exit 1
    fi
done
head -c "$(stat -c%s "$tmp/cut-new.c")" "$f" > "$tmp/prefix.c"
cmp -s "$tmp/prefix.c" "$tmp/cut-new.c" || { echo "  unions       the cut is not a byte prefix of zero-vim.c"; exit 1; }
if ! cmp -s "$tmp/cut-old.c.names" "$tmp/cut-new.c.names"; then
    echo "  unions       THE CUT'S BOUNDARY SET MOVED, AND THIS PHASE CROSSES NO BOUNDARY:"
    echo "               gone: $(comm -23 "$tmp/cut-old.c.names" "$tmp/cut-new.c.names" | tr '\n' ' ')"
    echo "               came: $(comm -13 "$tmp/cut-old.c.names" "$tmp/cut-new.c.names" | tr '\n' ' ')"
    exit 1
fi
echo "  unions       THE CUT -- \`make editor.c\`'s own rule, and a byte prefix of the file -- is $(grep -c '' "$tmp/cut-old.c") lines in and $(grep -c '' "$tmp/cut-new.c") out, 0 directives and 0 errors under -fsyntax-only either side, and its warning set, which IS the core -> host interface, is the SAME $(grep -c '' "$tmp/cut-new.c.names") names as a cmp.  The input's set is computed here and never written down"

wait $pid_canon
if ! cmp -s "$tmp/canon.c" "$f"; then
    echo "  unions       tools/canon.sh CHANGED THE OUTPUT, and it must be a no-op:"
    diff "$f" "$tmp/canon.c" | head -6 | sed 's/^/               /'
    exit 1
fi
echo "  unions       tools/canon.sh is a NO-OP on the output ($(sed -n 's/.*canon *//p' "$tmp/canon.log" | head -1))"

# --- 5. the binary, which is the whole of this phase's evidence ---------------------------
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

wait $pid_new || { echo "  unions       the reproducible build of the output failed"; exit 1; }
old_size=$(stat -c%s "$state/old")
new_size=$(stat -c%s "$tmp/new")
# A cmp of two files that were never written passes.  Both must exist, both must be the
# size of an editor, and the one under test must be the size make just produced.
if [ "$new_size" -lt 500000 ] || [ "$old_size" -lt 500000 ]; then
    echo "  unions       one of the two binaries is $old_size / $new_size bytes, which is not an editor -- a cmp of two files nothing wrote passes"
    exit 1
fi
if [ "$new_size" != "$(stat -c%s "$bin")" ]; then
    echo "  unions       the reproducible build is $new_size bytes and make produced $(stat -c%s "$bin"): the two differ by more than a timestamp, so the comparison below would not be about this boundary"
    exit 1
fi
if ! cmp -s "$state/old" "$tmp/new"; then
    echo "  unions       THE BINARY MOVED.  A union of ONE member has the size, the"
    echo "               alignment and the offset of that member, and an EMPTY union"
    echo "               contributes no storage, so this phase changes no layout and no"
    echo "               code at all and the two binaries -- the input's and the"
    echo "               output's, both built with SOURCE_DATE_EPOCH=0 and the boundary's"
    echo "               own flags -- must be the same bytes.  THIS IS A FINDING AND NOT"
    echo "               A NUMBER TO UPDATE: something about one of these six is not what"
    echo "               the phase says it is.  $old_size in, $new_size out."
    echo "               The GNU build-id note is a hash of the whole image and sits near"
    echo "               the front, so the first difference below is always that note:"
    cmp "$state/old" "$tmp/new" 2>&1 | sed 's/^/               /'
    exit 1
fi
echo "  unions       THE BINARY IS BYTE-IDENTICAL, $new_size bytes either side -- tier 1 of CLAUDE.md's verification table, and the whole of this phase's evidence.  A byte-identical binary subsumes every screen case, every Ex-command row, every command line and every pty scenario at once, because the program that would be run is the same program.  This phase's declared delta is NOTHING AT ALL, and that is the STRONGEST of the five kinds of empty declaration and not the weakest: it is phase 16's and phase 23's kind"

# --- 6. the controls, and the first of them is the point --------------------------------------
for p in $pid_ctl; do
    wait "$p" || true
done
for c in c1 c2 c3; do
    if [ ! -x "$tmp/$c" ]; then
        echo "  unions       the control $c did not build, and every one of them must:"
        head -5 "$tmp/$c.log" 2>/dev/null | sed 's/^/               /'
        exit 1
    fi
done
if cmp -s "$tmp/new" "$tmp/c1"; then
    echo "  unions       THE CONTROL c1 DID NOT SHOW.  This phase's own output with the two"
    echo "               fields it PROMOTED exchanged -- a pure layout permutation of the"
    echo "               very struct it rewrites -- gives a binary IDENTICAL to the output's,"
    echo "               so the cmp above is two numbers agreeing and proves nothing about"
    echo "               layout.  A test that cannot fail is not evidence (CLAUDE.md)."
    exit 1
fi
c1_bytes=$(cmp -l "$tmp/new" "$tmp/c1" | wc -l)
if [ "$c1_bytes" -lt 1000 ]; then
    echo "  unions       c1 differs in $c1_bytes bytes, and exchanging two fields of a struct"
    echo "               the undo layer touches everywhere must move far more than that --"
    echo "               a difference that small is the build-id note and nothing else."
    exit 1
fi
for c in c2 c3; do
    if ! cmp -s "$tmp/new" "$tmp/$c"; then
        echo "  unions       THE CONTROL $c MOVED, AND IT IS DECLARED TO MOVE NOTHING."
        echo "               $c is this phase run BACKWARDS on one field: a union of one"
        echo "               member put back around a plain field, or an empty union put"
        echo "               back into a struct.  Either must give the same bytes, because"
        echo "               that equivalence is the whole of the phase's argument.  If it"
        echo "               now moves something, the account has to be rewritten rather"
        echo "               than the number quietly updated.  $(cmp -l "$tmp/new" "$tmp/$c" | wc -l) bytes differ."
        exit 1
    fi
done
echo "  unions       AND IT CAN FAIL: c1 -- this phase's own output with the two fields it PROMOTED EXCHANGED, a pure layout permutation of the struct it rewrites -- builds cleanly and differs from it in $c1_bytes bytes.  So the binary IS sensitive to the layout of this struct, and the byte-identical result above is a measurement of the layout not moving rather than of nothing having happened"
echo "  unions       AND TWO CONTROLS MOVE NOTHING, WHICH IS REPORTED RATHER THAN HIDDEN: c2 puts the EMPTY union back and c3 puts one SINGLE-MEMBER union back with every one of its \`.member\` accesses -- this phase run backwards on one field each -- and both are byte-identical to the output.  That is the phase's claim stated in the other direction, which is the only direction a control can state it in: a union of one member and a plain field are the same program, and an empty union is no program at all"

# --- 7. two recordings, WHICH CHECK THE HARNESS AND NOT THE PHASE -----------------------------
# With a byte-identical binary each recording is of the same program, so an empty `diff
# -r` says the instrument is deterministic and says nothing about the edit.  It is run
# because measuring that is cheaper than asserting it, and this section says which it is
# so that nobody reads it as the evidence.  The evidence is the cmp above.
tools/zrecord.sh "$state/old" "$state/old.c" "$tmp/REC-old" >/dev/null 2>&1 &
pid_ro=$!
tools/zrecord.sh "$tmp/new" "$f" "$tmp/REC-new" >/dev/null 2>&1 &
pid_rn=$!
wait $pid_ro || { echo "  unions       the recording of the input failed"; exit 1; }
wait $pid_rn || { echo "  unions       the recording of the output failed"; exit 1; }
python3 - "$tmp" <<'PY'
import filecmp
import os
import sys

TAG = 'unions'
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
if files('%s/REC-old' % tmp) != base:
    sys.exit('  %-12s the two recordings hold different records' % TAG)
moved = [n for n in base
         if not filecmp.cmp('%s/REC-new/%s' % (tmp, n), '%s/REC-old/%s' % (tmp, n),
                            shallow=False)]
if moved:
    sys.exit('  %-12s the recording moved in %d of %d records -- from two runs of the '
             'SAME BYTES, which means the instrument is not deterministic and every '
             'recording-based zero phase is in question: %s'
             % (TAG, len(moved), len(base), ' '.join(moved[:8])))
print('  %-12s two full tools/zrecord.sh recordings, all %d records identical -- 102 '
      'screen cases, every Ex command typed at `:`, every command line the parser may '
      'see, the four pty scenarios and the terminal table.  THIS IS A CHECK ON THE '
      'HARNESS AND NOT ON THE PHASE: the two binaries are the same bytes, so what it '
      'measures is that the instrument is deterministic, and it is reported in those '
      'words rather than offered as evidence for the edit' % (TAG, len(base)))
PY

# --- 8. phase 20's structural check, which every phase that touches the core owes ------------
tools/st.sh zhostonly "$f"
echo "  unions       and that is phase 20's check, undisturbed: none of the six names this phase removes is in its vocabulary, and the host block is untouched"

# tools/phaserun.sh runs tools/zerodelta.sh --phase 37 after this check, and this phase
# declares NOTHING: the corpus must not move at all.
