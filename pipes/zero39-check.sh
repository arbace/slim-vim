#!/bin/sh
# Zero phase 39, the check -- `-T {term}` goes, and the command line is `+{command}`.
# See pipes/zero39-edit.sh, and ZERO-GOAL.md.
#
# Usage: pipes/zero39-check.sh <work-dir> <state-dir>   (run from the repository root)
#
# Runs after pipes/zero39-edit.sh and the sweep tools/phaserun.sh runs between them,
# and reads nothing from the edit's shell -- only the work tree and the state
# directory.  What the edit left there is `old.c`, the source this phase was HANDED,
# `old`, that source built with SOURCE_DATE_EPOCH=0 and the boundary's own flags, and
# `enums-before`, that binary's DWARF enumerator values.
#
# NOTHING BELOW IS A NUMBER THAT WAS OBSERVED.  Which option letters went is the
# input's `switch (c)` minus the output's; which command lines must therefore move is
# computed from those letters over `zargv`'s own list; what a refused terminal
# name leaves the terminal as is measured from the new binary; and the boundary's
# interface is computed from the input.  So the rules stay true of a file this check
# has never seen, which is what makes them rules.
#
# WHAT IS CLAIMED, in nine parts:
#
#   THE CUT      the option letters are gone, `want_argument`, `mainerr_arg_missing`,
#                ME_GARBAGE, ME_ARG_MISSING and `requested` are at 0 mentions, the
#                parser is ONE `if (argv[0][0] == '+')` and one else, `mparm_T` has no
#                `term` member and every `.term` left belongs to another struct.
#   THE ROWS     main_errors[] is indexed by the ME_* enumerators, so the check is
#                DWARF and not the build: exactly the two enumerators removed are
#                gone, exactly ME_EXTRA_CMD moved, and by exactly one.
#   THE COMMAND LINE  `zargv`'s thirty invocations, before and after, side by
#                side.  A row must move IF AND ONLY IF one of its words is an option
#                spelling the removed letters -- computed from the two switches, not
#                written here -- and each row that moves must have done something
#                ELSE on the binary this phase was handed, or it proves nothing.
#   THE FALLBACK the three statements after the refusal cannot run.  TWO measurements:
#                the output with the whole arm RESTORED, report_default_term() and all,
#                records byte for byte what the output records; and the same marker in
#                the same place, reached through host_message(), is in exactly the `-T`
#                records on the INPUT and in NONE on that control.
#   THE ARM      and the half that stays is entered: the same instrumented pair,
#                asked `+set term={unknown}` on a real pty, takes the no-screen test's
#                arm on both, which is what makes the fold ALWAYS and not a guess.
#   THE MESSAGE  report_term_error() still runs -- it is the run-time refusal's, not
#                the fallback's, which is the payoff phase 38 predicted and did NOT
#                get -- and it no longer promises a default that cannot happen.  Both
#                halves on a pty, with E522 and the terminal unchanged either side.
#   256-COLOUR   the test does NOT fold, and that is measured in both directions: with
#                the name test forced TRUE exactly one row of the terminal table moves,
#                with it forced FALSE eighteen do.  And folding `requested` into `term`
#                is neutral where the two differ -- the `builtin_` spellings of both
#                surviving names answer identically on both binaries.
#   SYMBOLS      `nm -u` is THE SAME SET, as a `comm` empty in both directions: this
#                phase deletes a parser arm and calls nothing new.  `nm --extern-only
#                --defined-only` is still exactly `main`.
#   THE CUT (2)  zero.mk's own rule on the INPUT and the OUTPUT: eleven directives,
#                none above them, 0 errors under -fsyntax-only either side, and the
#                boundary's warning set -- computed here and never written down --
#                UNCHANGED.  Then `zhostonly` and tools/phasecheck.sh.
set -eu

work=${1:?usage: zero39-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero39-check.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"
before_lines=$(cat "$state/input-lines")

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")

# THE PRODUCT, REBUILT, and the clean is checked rather than trusted: the work tree
# still holds the binary tools/restore.sh unpacked with the previous boundary, and a
# recording of THAT would be a recording of the phase's input (pipes/zero38-check.sh
# measured that happening).
make -C "$work" clean >/dev/null 2>&1 || true
[ -e "$work/zero-vim" ] && { echo "  build        the clean did not remove zero-vim, so nothing below would be a recording of this phase"; exit 1; }
if ! make -C "$work" >/dev/null 2>&1; then
    echo "  build        FAILED -- rerun by hand: make -C $work"
    exit 1
fi
new="$work/zero-vim"

# --- the controls, written first and built in parallel ----------------------------
# Each is this phase's own output with ONE thing changed, or the input with one thing
# added, and each is located by parsing both texts.  Not one line of C is quoted here.
python3 - "$f" "$state/old.c" "$tmp" <<'PY'
import re
import sys
sys.path.insert(0, 'tools')
import cutil

TAG = 'controls'
new = open(sys.argv[1], errors='surrogateescape').read()
old = open(sys.argv[2], errors='surrogateescape').read()
out = sys.argv[3]


def die(msg):
    sys.exit('  %-12s %s' % (TAG, msg))


def arm(t):
    """The `if (termp == nullptr)` arm of set_termname(): its extent and its text."""
    lo, hi = cutil.find_definition(t, 'set_termname')
    seg = t[lo:hi]
    b = cutil.blank(seg)
    m = re.search(r'^[ \t]*if \(termp == nullptr\)$', seg, re.M)
    if not m:
        die('set_termname() has no `termp == nullptr` arm in one of the two texts')
    k = seg.rfind('\n', 0, m.start()) + 1
    o = b.index('{', m.end())
    c = cutil.match(seg, o, b)
    end = c + 1
    if end < len(seg) and seg[end] == '\n':
        end += 1
    return lo + k, lo + end, seg[k:end]


ao, zo, blk_old = arm(old)
an, zn, blk_new = arm(new)
if blk_old == blk_new:
    die('the output keeps the input\'s refusal arm, so there is nothing to check')
if 'report_default_term' in blk_new or 'NO_SCREEN' in blk_new:
    die('the output\'s refusal arm still tests `starting` or calls '
        'report_default_term(), so this phase did not do what it says')

# c1 -- THE ARM RESTORED, with the function that went with it.  The definition goes
# back immediately above set_termname(), which is where one TU needs it and nowhere
# else; a prototype would be a second thing to keep in step.
lo, hi = cutil.find_definition(old, 'report_default_term')
rdt = old[lo:hi]
if rdt in new:
    die('report_default_term() is still in the output, so the sweep did not take it')
c1 = new[:an] + blk_old + new[zn:]
slo, _shi = cutil.find_definition(c1, 'set_termname')
c1 = c1[:slo] + rdt + '\n' + c1[slo:]
if c1 == new:
    die('the arm-restored control changed nothing, so it is not a control')
open(out + '/c1.c', 'w', errors='surrogateescape').write(c1)

# The instrumented pair: the SAME two markers at the SAME two places, in the input
# and in that control.  The marker goes through host_message(), the core's own
# declared way to reach stderr (zero phase 21), so it adds no name the file does not
# already have.  Both positions are computed from the block's own structure.
def mark(text, label):
    a, z, blk = arm(text)
    b = cutil.blank(blk)
    g = re.search(r'^[ \t]*if \(starting != NO_SCREEN\)$', blk, re.M)
    if not g:
        die('%s: the restored arm does not test `starting`' % label)
    o = b.index('{', g.end())
    c = cutil.match(blk, o, b)
    nl = blk.index('\n', o) + 1
    tail = blk.index('\n', c) + 1
    if not blk[tail:].strip():
        die('%s: nothing follows the refusal, so the fallback marker has nowhere to go'
            % label)
    ins = (blk[:nl]
           + '                    host_message("NOSCREENARM\\n", -1, TRUE);\n'
           + blk[nl:tail]
           + '                host_message("FALLBACK\\n", -1, TRUE);\n'
           + blk[tail:])
    return text[:a] + ins + text[z:]


open(out + '/i-old.c', 'w', errors='surrogateescape').write(mark(old, 'i-old'))
open(out + '/i-new.c', 'w', errors='surrogateescape').write(mark(c1, 'i-new'))

# cT / cF -- THE 256-COLOUR NAME TEST forced each way, on the output's own text.  The
# needle is read out of the file; neither control is a fold this phase performs.
m = re.search(r'musl_strstr\(\(char \*\)term, "([^"]*)"\) != nullptr', new)
if not m:
    die('the 256-colour name test is not a musl_strstr on `term` in the output')
if new.count(m.group(0)) != 1:
    die('the 256-colour name test is not in the output exactly once')
for name, lit in (('cT', '(TRUE)'), ('cF', '(FALSE)')):
    open('%s/%s.c' % (out, name), 'w', errors='surrogateescape').write(
        new.replace(m.group(0), lit))
open(out + '/needle', 'w').write(m.group(1))

# The option letters this phase removed, from the two parsers.  Everything the
# command-line half of this check asserts is computed from this set.
def letters(t):
    lo, hi = cutil.find_definition(t, 'command_line_scan')
    seg = t[lo:hi]
    b = cutil.blank(seg)
    i = b.find('switch (c)')
    if i < 0:
        return []
    o = b.index('{', i)
    c = cutil.match(seg, o, b)
    return re.findall(r"^[ \t]*case '(.)':$", seg[o + 1:c], re.M)


was, now = letters(old), letters(new)
if not was:
    die('the input\'s parser accepts no option letter, so this phase removed nothing')
if now:
    die('the output still accepts the option letter(s) %s' % ' '.join(now))
open(out + '/letters', 'w').write(''.join(was))

# c5 -- THE INPUT WITH THE OPTION LETTER AND NOTHING ELSE TAKEN OUT: the `case`
# arms deleted from its first switch and every other line left exactly where it is,
# `want_argument` and its block and the second switch and the two ME_* rows and the
# fallback all still there.  This is the phase decomposed: if the letter is the whole
# of what changes behaviour, c5 records what the OUTPUT records, and everything else
# this phase does is invisible to the instrument.
lo, hi = cutil.find_definition(old, 'command_line_scan')
seg = old[lo:hi]
b = cutil.blank(seg)
o = b.index('{', b.find('switch (c)'))
c = cutil.match(seg, o, b)
body = seg[o + 1:c]
for x in was:
    pat = r'\n[ \t]*case \'%s\':\n(?:[^\n]*\n)*?[ \t]*break;\n' % re.escape(x)
    if len(re.findall(pat, body)) != 1:
        die('the input\'s switch does not hold one `case %r: ... break;` arm' % x)
    body = re.sub(pat, '\n', body)
c5 = old[:lo] + seg[:o + 1] + body + seg[c:] + old[hi:]
if c5 == old:
    die('the letter-only control changed nothing, so it is not a control')
open(out + '/c5.c', 'w', errors='surrogateescape').write(c5)
print('  %-12s five controls written from the two texts: the refusal arm restored, '
      'the instrumented pair, and the 256-colour name test forced each way.  The '
      'removed option letters are %s, read out of the two parsers'
      % (TAG, ' '.join('-' + x for x in was)))
PY

for v in c1 c5 i-old i-new cT cF; do
    # shellcheck disable=SC2086
    ( SOURCE_DATE_EPOCH=0 gcc $cflags $ldflags -o "$tmp/$v" "$tmp/$v.c" ) &
done
LETTERS=$(cat "$tmp/letters")

# --- 1. THE CUT -------------------------------------------------------------------
python3 - "$f" "$state/old.c" "$before_lines" "$LETTERS" <<'PY'
import re
import sys
sys.path.insert(0, 'tools')
import cutil

TAG = 'cmdline'
new = open(sys.argv[1], errors='surrogateescape').read()
old = open(sys.argv[2], errors='surrogateescape').read()
before, LETTERS = int(sys.argv[3]), sys.argv[4]


def die(msg):
    sys.exit('  %-12s %s' % (TAG, msg))


def say(what):
    print('  %-12s %s' % (TAG, what))


def mentions(t, name):
    return len(re.findall(r'\b%s\b' % name, cutil.blank(t)))


GONE = ('want_argument', 'mainerr_arg_missing', 'ME_GARBAGE', 'ME_ARG_MISSING',
        'requested', 'report_default_term')
left = ['%s %d' % (n, mentions(new, n)) for n in GONE if mentions(new, n)]
if left:
    die('these were to go and did not: %s' % ', '.join(left))
for n in GONE:
    if not mentions(old, n):
        die('%s was not in the input either, so its absence proves nothing' % n)
for n in ('ME_UNKNOWN_OPTION', 'ME_EXTRA_CMD', 'MAX_ARG_CMDS', 'exe_commands',
          'p_paste', 'did_set_term', 'report_term_error', 'set_termname'):
    if not mentions(new, n):
        die('%s went, and it is not this phase\'s' % n)

# THE PARSER, as a shape and not as text: one `+` test, one else, no switch, and the
# option letters gone.
lo, hi = cutil.find_definition(new, 'command_line_scan')
seg = new[lo:hi]
if 'switch' in cutil.blank(seg):
    die('command_line_scan() still holds a switch')
for name in ('c', 'want_argument'):
    if mentions(seg, name):
        die('command_line_scan() still declares `%s`' % name)
if len(re.findall(r'^[ \t]*if \(argv\[0\]\[0\] == \'\+\'\)$', seg, re.M)) != 1:
    die('command_line_scan() does not test for exactly one `+`')
if len(re.findall(r'^[ \t]*else$', seg, re.M)) != 2:
    die('command_line_scan() does not have the two elses this phase leaves -- the '
        '`+cmd` arm\'s inner one and the unknown-option arm')
if mentions(seg, 'ME_UNKNOWN_OPTION') != 1:
    die('command_line_scan() answers ME_UNKNOWN_OPTION %d times, and after this '
        'phase there is ONE arm that answers anything'
        % mentions(seg, 'ME_UNKNOWN_OPTION'))
say('the command line is `+{command}` and nothing else: one `+` test, one arm that '
    'answers ME_UNKNOWN_OPTION, no switch and no option letter -- %s went, and with '
    'them want_argument, mainerr_arg_missing, ME_GARBAGE, ME_ARG_MISSING and the '
    '`requested` the fallback needed'
    % ' '.join('-' + x for x in LETTERS))

# THE FIELD, and why it could not be the sweep's.
if re.search(r'^[ \t]*char_u +\*term;\n', new[new.rindex('{', 0, new.index('} mparm_T;')):
                                             new.index('} mparm_T;')], re.M):
    die('mparm_T still has its `term` member')
owners = sorted(set(re.findall(r'(\w+)\s*(?:\.|->)\s*term\b', cutil.blank(new))))
if [x for x in owners if x in ('params', 'parmp')]:
    die('something still names mparm_T\'s `term` field: %s' % ' '.join(owners))
if not owners:
    die('nothing names a `.term` member at all, so deadfields.py could have taken '
        'the field and this phase need not have -- read the file')
say('mparm_T has no `term` member, and the %d `.term` mentions left all belong to '
    'another struct (%s): deadfields.py matches by NAME, which is why the member was '
    'the edit\'s and not the sweep\'s'
    % (len(re.findall(r'(?:\.|->)\s*term\b', cutil.blank(new))), ' '.join(owners)))

after = new.count('\n') + (0 if new.endswith('\n') else 1)
if after >= before:
    die('the file did not shrink: %d -> %d' % (before, after))
say('the file lost %d lines, %d -> %d: the parser arm, the two rows, the field, the '
    'unreachable fallback and the one function the sweep found under it'
    % (before - after, before, after))
PY

# --- 2. THE ROWS: main_errors[] is indexed by enumerators, so DWARF says ------------
tools/enumvals.sh "$f" "$tmp/enums-after"
python3 - "$state/enums-before" "$tmp/enums-after" "$f" "$state/old.c" <<'PY'
import re
import sys
TAG = 'enums'


def die(msg):
    sys.exit('  %-12s %s' % (TAG, msg))


def load(p):
    return dict(l.rstrip('\n').split('=', 1) for l in open(p) if '=' in l)


before, after = load(sys.argv[1]), load(sys.argv[2])
new = open(sys.argv[3], errors='surrogateescape').read()
old = open(sys.argv[4], errors='surrogateescape').read()


def pairs(t):
    return dict(re.findall(r'^enum \{ (ME_\w+) = (\d+) \};$', t, re.M))


was, now = pairs(old), pairs(new)
GONE = sorted(set(was) - set(now))
if not GONE:
    die('the output keeps every ME_* enumerator, so nothing here is checked')
MOVED = {n: (was[n], now[n]) for n in now if was.get(n) != now[n]}
fail = []
for n in GONE:
    if n not in before:
        fail.append('%s was not in the input binary at all, so its removal proves '
                    'nothing' % n)
    if n in after:
        fail.append('%s survives in the binary with value %s' % (n, after[n]))
for n, (a, b) in sorted(MOVED.items()):
    if before.get(n) != a or after.get(n) != b:
        fail.append('%s is %s -> %s in DWARF and %s -> %s in the source'
                    % (n, before.get(n), after.get(n), a, b))
    if int(b) != int(a) - len(GONE):
        fail.append('%s moved by %d and %d rows went' % (n, int(a) - int(b), len(GONE)))
still = [n for n in before if n not in GONE and n not in MOVED]
moved = [n for n in still if n in after and after[n] != before[n]]
if moved:
    fail.append('%d enumerators renumbered and were not to: %s'
                % (len(moved), ' '.join(sorted(moved)[:8])))
lost = [n for n in still if n not in after]
if lost:
    fail.append('%d enumerators left the binary and were not to: %s'
                % (len(lost), ' '.join(sorted(lost)[:8])))
# the table is as long as the enumerators, plus the one row whim left unreachable
rows = re.search(r'^static char \*\(main_errors\[\]\) =\n\{\n(.*?)^\};\n',
                 new, re.M | re.S)
if not rows or len(rows.group(1).splitlines()) != len(now) + 1:
    fail.append('main_errors[] has %s rows for %d enumerators'
                % (len(rows.group(1).splitlines()) if rows else 'no', len(now)))
if fail:
    for line in fail:
        print('  %-12s %s' % (TAG, line))
    print('  %-12s main_errors[] is indexed by these, and the build cannot see a' % '')
    print('  %-12s wrong index.  DWARF can.' % '')
    sys.exit(1)
print('  %-12s %d in, %d out; %s gone with their rows and %s by exactly %d, the '
      'number of rows that went; %d unmoved.  main_errors[] is %d rows for %d '
      'enumerators, the extra one being whim\'s unreachable leftover'
      % (TAG, len(before), len(after), ' and '.join(GONE),
         ' and '.join('%s %s->%s' % (n, a, b) for n, (a, b) in sorted(MOVED.items())),
         len(GONE), len(still) - len(moved),
         len(rows.group(1).splitlines()), len(now)))
PY

# --- 3. THE RECORDINGS, and the controls' -----------------------------------------
rm -rf "$tmp/rec-new" "$tmp/rec-old" "$tmp/rec-c1" "$tmp/rec-c5" "$tmp/rec-i-old" "$tmp/rec-i-new"
wait
tools/zrecord.sh "$new" "$f" "$tmp/rec-new" >/dev/null &
tools/zrecord.sh "$state/old" "$state/old.c" "$tmp/rec-old" >/dev/null &
tools/zrecord.sh "$tmp/c1" "$tmp/c1.c" "$tmp/rec-c1" >/dev/null &
tools/zrecord.sh "$tmp/c5" "$tmp/c5.c" "$tmp/rec-c5" >/dev/null &
tools/zrecord.sh "$tmp/i-old" "$tmp/i-old.c" "$tmp/rec-i-old" >/dev/null &
tools/zrecord.sh "$tmp/i-new" "$tmp/i-new.c" "$tmp/rec-i-new" >/dev/null &
wait

# --- 4. THE COMMAND LINE, before and after, side by side ---------------------------
echo "  argv         zargv's thirty invocations, before and after -- a row moves if and only if one of its words spells a removed option letter:"
if ! python3 - "$tmp/rec-old" "$tmp/rec-new" "$LETTERS" > "$tmp/argv" 2>&1 <<'PY'
import os
import re
import sys
sys.path.insert(0, 'tools')
import zrec

old_dir, new_dir, LETTERS = sys.argv[1], sys.argv[2], sys.argv[3]
was = zrec.blocks(open(os.path.join(old_dir, 'ref-argv.txt'), errors='replace').read())
now = zrec.blocks(open(os.path.join(new_dir, 'ref-argv.txt'), errors='replace').read())
if sorted(was) != sorted(now):
    sys.exit('the two recordings hold different invocations')
if not was:
    sys.exit('the recording holds no invocation at all')


def names_a_letter(name):
    """An invocation that spells one of the removed letters as an option."""
    return any(w.startswith('-') and len(w) > 1 and w[1] in LETTERS
               for w in name.split())


def gist(block):
    ex = re.search(r'--- exit (\S+)', block)
    st = re.search(r'--- stream (\d+)', block)
    err = [l for l in block.splitlines()
           if l and not l.startswith('---') and not l.startswith('VIM - Vi')]
    return '%s exit %s, %s bytes drawn%s' % (
        'blocked' if 'blocked' in block else '', ex.group(1) if ex else '?',
        st.group(1) if st else '?', (', ' + err[-1].strip()) if err else '')


bad, moved = [], []
UNKNOWN = 'Unknown option argument'
for name in sorted(was):
    a, b = was[name], now[name]
    want = names_a_letter(name)
    if want and a == b:
        bad.append('%r spells a removed option and did not move' % name)
    if not want and a != b:
        bad.append('%r moved and spells no removed option' % name)
    if want:
        moved.append(name)
        # It must have done something ELSE before, or it proves nothing about `-T`.
        if UNKNOWN in a:
            bad.append('%r was already an unknown option, so moving it proves nothing'
                       % name)
        if UNKNOWN not in b:
            bad.append('%r is not an unknown option now: %s' % (name, gist(b)))
    print('               %-22s %-46s -> %s'
          % (repr(name), gist(a), gist(b) if a != b else '(identical)'))
if not moved:
    sys.exit('no invocation spells a removed option letter, so this check is vacuous')
if bad:
    sys.exit('\n'.join(bad))
print('               %d of %d invocations moved, and they are exactly the %d that '
      'spell %s: each did something else on the binary this phase was handed -- '
      'started and drew, or answered a DIFFERENT error -- and each is `%s` now'
      % (len(moved), len(was), len(moved),
         ' or '.join('-' + x for x in LETTERS), UNKNOWN))
PY
then
    sed 's/^/  argv         /' "$tmp/argv"
    exit 1
fi
cat "$tmp/argv"

# And nothing else in the recording moved: the screens, the Ex commands, the pty
# scenarios and the terminal table are the input's, byte for byte.
for what in screen ref-excmds.txt ref-pty.txt ref-term.txt; do
    if ! diff -r "$tmp/rec-old/$what" "$tmp/rec-new/$what" >/dev/null; then
        echo "  argv         $what moved, and this phase touches only the command line:"
        diff -rq "$tmp/rec-old/$what" "$tmp/rec-new/$what" | head -5 | sed 's/^/               /'
        exit 1
    fi
done
echo "  argv         the 102 screen cases, the Ex-command rows, the pty scenarios and the nineteen terminal rows are the input's byte for byte: this phase moves command lines and nothing else"

# THE PHASE DECOMPOSED, which is also the instrument shown able to fail.  c5 is the
# INPUT with the option letter taken out of its parser and NOTHING else changed --
# want_argument, the argument switch, both ME_* rows, the field, the fallback and
# `requested` all still there.  It must record what the OUTPUT records, byte for
# byte: the letter is the whole of what moves behaviour, and everything else this
# phase does is invisible to every part of a recording.
if ! diff -r "$tmp/rec-c5" "$tmp/rec-new" >/dev/null; then
    echo "  letter       the INPUT with only the option letter removed records something different from this phase's output, so the phase changes behaviour by more than the letter:"
    diff -rq "$tmp/rec-c5" "$tmp/rec-new" | head -10 | sed 's/^/               /'
    exit 1
fi
if diff -r "$tmp/rec-c5" "$tmp/rec-old" >/dev/null; then
    echo "  letter       removing the option letter from the input changed NOTHING, so the instrument cannot see this phase at all"
    exit 1
fi
echo "  letter       the phase decomposed: the INPUT with ONLY the \`case\` arm deleted -- want_argument, the argument switch, both ME_* rows, the field, the unreachable fallback and \`requested\` all left in place -- records byte for byte what this phase's output records, and differs from the input.  So the option letter is the whole of what moves behaviour here, and the other five cuts are invisible to every part of a recording"

# --- 5. THE FALLBACK IS UNREACHABLE, twice ----------------------------------------
if ! diff -r "$tmp/rec-c1" "$tmp/rec-new" >/dev/null; then
    echo "  fallback     the output with the refusal arm RESTORED records something different, so removing it was not neutral:"
    diff -rq "$tmp/rec-c1" "$tmp/rec-new" | head -10 | sed 's/^/               /'
    exit 1
fi
hit_old=$(grep -rl FALLBACK "$tmp/rec-i-old" 2>/dev/null | grep -c '' || true)
hit_new=$(grep -rl FALLBACK "$tmp/rec-i-new" 2>/dev/null | grep -c '' || true)
rows_old=$(grep -c FALLBACK "$tmp/rec-i-old/ref-argv.txt" 2>/dev/null || true)
# HOW MANY ROWS ARE DUE, computed from the INPUT's own recording and not from the
# argument list: on the input the fallback is reached exactly where
# report_term_error() printed, so the rows that say `not known` ARE the rows that
# fell back -- and each of them must be one that spells a removed option letter.
want=$(python3 - "$tmp/rec-old/ref-argv.txt" "$LETTERS" <<'PY'
import sys
sys.path.insert(0, 'tools')
import zrec
blocks = zrec.blocks(open(sys.argv[1], errors='replace').read())
LETTERS = sys.argv[2]
hit = [n for n, b in blocks.items() if 'not known' in b]
for n in hit:
    if not any(w.startswith('-') and len(w) > 1 and w[1] in LETTERS
               for w in n.split()):
        sys.exit('%r fell back and spells no removed option letter' % n)
print(len(hit))
PY
) || { echo "  fallback     the input's own recording does not say which rows fell back"; exit 1; }
if [ "$hit_new" != 0 ]; then
    echo "  fallback     the marker fires in $hit_new file(s) of the control built from THIS PHASE'S output, where 0 was due -- the fallback is reachable"
    exit 1
fi
if [ "$hit_old" = 0 ] || [ "$rows_old" != "$want" ]; then
    echo "  fallback     the identical marker fires in $hit_old file(s) and $rows_old command row(s) of the INPUT, where $want command rows were due: the instrument cannot fail, so it is not evidence"
    exit 1
fi
echo "  fallback     the three statements after the refusal cannot run, TWICE OVER: the output with the whole arm RESTORED -- report_default_term() and all -- records byte for byte what the output records, over every screen case, command row, pty scenario and terminal row; and the identical marker inside the fallback, reached through host_message(), fires in $rows_old command row(s) of the INPUT -- the ones that name a terminal on the command line, which is the ONLY way in -- and in $hit_new records of the control"

# --- 6. THE ARM THAT STAYS IS ENTERED, and the message with it ---------------------
if ! python3 - "$tmp/i-old" "$tmp/i-new" "$state/old" "$new" > "$tmp/arm" 2>&1 <<'PY'
"""`:set term={unknown}` at run time: the no-screen test is TRUE there, and the
message no longer promises a default that cannot happen."""
import concurrent.futures
import re
import sys
import tempfile
sys.path.insert(0, 'tools')
import termcheck
import ptyrun

i_old, i_new, old, new = sys.argv[1:5]


def ask(binary, name):
    d = tempfile.mkdtemp(prefix='zero39-')
    out, _ = ptyrun.session(binary, ['+set term=' + name], [b':set term? t_Co?\r',
                                                            b':q!\r'],
                            cwd=d, settle=1.0, env=termcheck.ENV)
    return out.decode('utf-8', 'replace')


# A name no row of the table carries, found rather than written: the last row of
# tools/termcheck.py's list that the new binary refuses.
with concurrent.futures.ThreadPoolExecutor(max_workers=8) as ex:
    answers = dict(zip(termcheck.TERMS,
                       ex.map(lambda t: ask(new, t), termcheck.TERMS)))
unknown = [t for t in termcheck.TERMS if t and 'E522' in answers[t]]
if not unknown:
    sys.exit('the new binary refuses no terminal name at all, so there is no '
             'run-time refusal to measure')
name = unknown[0]

with concurrent.futures.ThreadPoolExecutor(max_workers=4) as ex:
    marks = dict(zip(('i-old', 'i-new'),
                     ex.map(lambda b: ask(b, name), (i_old, i_new))))
    plain = dict(zip(('old', 'new'), ex.map(lambda b: ask(b, name), (old, new))))
for k, s in marks.items():
    if 'NOSCREENARM' not in s:
        sys.exit('%s does not take the no-screen test\'s arm on `:set term=%s`, so '
                 'the fold this phase made is not ALWAYS' % (k, name))
    if 'FALLBACK' in s:
        sys.exit('%s reaches the fallback at run time' % k)
for k, s in plain.items():
    if 'E522' not in s:
        sys.exit('%s does not refuse `:set term=%s`' % (k, name))
    if "'%s' not known" % name not in s:
        sys.exit('%s does not report the name at all' % k)
promise = re.compile(r"not known, defaulting to '([^']*)'")
was, now = promise.search(plain['old']), promise.search(plain['new'])
if not was:
    sys.exit('the binary this phase was handed did not promise a default, so there '
             'was nothing here to take away')
if now:
    sys.exit('the new binary still promises %r, and there is no fallback to make '
             'that true' % now.group(1))
term = re.compile(r'term=\S+ ')
if term.findall(plain['old']) != term.findall(plain['new']):
    sys.exit('the terminal the editor is left at moved: %r -> %r'
             % (term.findall(plain['old']), term.findall(plain['new'])))
print('`:set term=%s` on a real pty takes the no-screen arm on BOTH instrumented '
      'builds and reaches the fallback on neither: the test this phase folded is '
      'true wherever the arm is reached.  report_term_error() still runs -- it is '
      "the run-time refusal's and not the fallback's -- and says `'%s' not known` "
      "where it said `defaulting to '%s'`, with E522 and the terminal it is left at "
      'unchanged' % (name, name, was.group(1)))
PY
then
    sed 's/^/  arm          /' "$tmp/arm"
    exit 1
fi
sed 's/^/  arm          /' "$tmp/arm"

# --- 7. THE 256-COLOUR TEST DOES NOT FOLD ------------------------------------------
tools/st.sh ztermcheck "$tmp/cT" "$tmp/term-cT" >/dev/null &
tools/st.sh ztermcheck "$tmp/cF" "$tmp/term-cF" >/dev/null &
wait
if ! python3 - "$tmp/rec-new/ref-term.txt" "$tmp/term-cT" "$tmp/term-cF" \
     "$(cat "$tmp/needle")" "$state/old" "$new" > "$tmp/colours" 2>&1 <<'PY'
"""The name test is live in BOTH directions, so folding it would change behaviour.

And `requested` -> `term` is neutral where the two differ: the `builtin_` spelling of
a surviving name, which is the only input for which the stripped prefix matters.
"""
import concurrent.futures
import sys
import tempfile
sys.path.insert(0, 'tools')
import termcheck
import ptyrun

base, cT, cF, needle, old, new = sys.argv[1:7]
rows = open(base).read().splitlines()


def moved(path):
    other = open(path).read().splitlines()
    if len(other) != len(rows):
        sys.exit('a control recorded %d rows where the output recorded %d'
                 % (len(other), len(rows)))
    return [a[a.index("'") + 1:a.rindex("'")] for a, b in zip(rows, other) if a != b]


up, down = moved(cT), moved(cF)
if not up or not down:
    sys.exit('forcing the name test TRUE moved %d rows and FALSE moved %d: a test '
             'that cannot be seen either way is one this phase could have folded'
             % (len(up), len(down)))
if set(up) & set(down):
    sys.exit('%s moves whichever way the test is forced, so neither control says '
             'what the test decides' % ' '.join(sorted(set(up) & set(down))))

# The two surviving names disagree on it, which is the whole reason it cannot fold.
resolving = [r[r.index("'") + 1:r.rindex("'")] for r in rows if 'E5' not in r]
if not set(up) <= set(resolving):
    sys.exit('forcing the test TRUE moved a row that does not resolve at all: %s'
             % ' '.join(sorted(set(up) - set(resolving))))


def ask(binary, name):
    d = tempfile.mkdtemp(prefix='zero39-')
    out, _ = ptyrun.session(binary, ['+set term=' + name], [b':set term? t_Co?\r',
                                                            b':q!\r'],
                            cwd=d, settle=1.0, env=termcheck.ENV)
    s = out.decode('utf-8', 'replace')
    got = []
    for line in s.splitlines():
        for kw in ('term=', 't_Co='):
            i = line.find(kw)
            if i >= 0:
                got.append(line[i:].split()[0])
    return ' '.join(got)


names = ['builtin_' + n for n in resolving]
with concurrent.futures.ThreadPoolExecutor(max_workers=2 * len(names)) as ex:
    was = list(ex.map(lambda n: ask(old, n), names))
    now = list(ex.map(lambda n: ask(new, n), names))
diff = [n for n, a, b in zip(names, was, now) if a != b]
if diff:
    sys.exit('folding `requested` into `term` moved %s, which is exactly the input '
             'the stripped prefix makes different' % ' '.join(diff))
if not [a for a in was if a]:
    sys.exit('the `builtin_` spellings answered nothing on either binary, so the '
             'neutrality of the fold is untested')
print('the %r test does NOT fold and this phase does not pretend it does: forcing it '
      'TRUE moves %d of %d terminal rows (%s) and forcing it FALSE moves %d (%s...), '
      'so both arms are reached at run time and either fold would be a behaviour '
      'change.  And folding `requested` into `term` is neutral where the two differ: '
      '%s answer identically on both binaries -- %s'
      % (needle, len(up), len(rows), ' '.join(up), len(down), ' '.join(down[:3]),
         ' and '.join(names), ' / '.join(now)))
PY
then
    sed 's/^/  colours      /' "$tmp/colours"
    exit 1
fi
sed 's/^/  colours      /' "$tmp/colours"

# --- 8. SYMBOLS: the same set, with its reason -------------------------------------
gcc -c -O0 -fno-stack-protector -o "$tmp/new.o" "$f"
gcc -c -O0 -fno-stack-protector -o "$tmp/old.o" "$state/old.c"
nm -u "$tmp/new.o" | awk '{print $2}' | sort > "$tmp/u-new"
nm -u "$tmp/old.o" | awk '{print $2}' | sort > "$tmp/u-old"
went=$(comm -23 "$tmp/u-old" "$tmp/u-new" | tr '\n' ' ')
came=$(comm -13 "$tmp/u-old" "$tmp/u-new" | tr '\n' ' ')
if [ -n "$went$came" ]; then
    echo "  symbols      the libc surface moved, and this phase frees nothing: gone '$went', new '$came'"
    exit 1
fi
ext=$(nm --extern-only --defined-only "$tmp/new.o" | awk '{print $NF}' | sort | tr '\n' ' ')
if [ "$ext" != "main " ]; then
    echo "  symbols      the output defines external symbols other than main: $ext"
    exit 1
fi
echo "  symbols      \`nm -u\` is THE SAME $(grep -c '' "$tmp/u-new") symbols, a comm empty in both directions -- and that is a statement and not a disappointment: what this phase removes is a parser arm and an unreachable fallback, and neither was anything's last caller.  \`main\` is still the only external symbol"

# --- 9. THE BOUNDARY: the cut, its directives and its interface --------------------
for side in old new; do
    src=$f
    [ "$side" = old ] && src=$state/old.c
    # zero.mk's rule ENTIRE, trailing-blank-line drop included: `if (NF) last`
    # is why `make editor.c` is one line shorter than a naive prefix, and a check
    # that reports the prefix's number disagrees with the product by one for ever.
    awk '/^ *# *include / { exit } { a[NR] = $0; if (NF) last = NR } \
         END { for (i = 1; i <= last; i++) print a[i] }' "$src" > "$tmp/cut-$side.c"
    d=$(grep -c '^ *#' "$tmp/cut-$side.c" || true)
    n=$(grep -c '' "$tmp/cut-$side.c")
    i=$(grep -c '^ *# *include ' "$src" || true)
    if [ "$d" != 0 ] || [ "$n" -lt 1000 ]; then
        echo "  boundary     the $side cut is $n lines with $d directive(s), and the core has none"
        exit 1
    fi
    if ! gcc -fsyntax-only "$tmp/cut-$side.c" 2>"$tmp/err-$side"; then
        echo "  boundary     the $side cut is not a complete translation unit:"
        head -5 "$tmp/err-$side" | sed 's/^/               /'
        exit 1
    fi
    gcc -fsyntax-only -Wall -Wextra -Wno-unused-parameter "$tmp/cut-$side.c" 2>&1 \
        | sed -n "s/.*warning: '\\([a-zA-Z_][a-zA-Z_0-9]*\\)' used but never defined.*/\\1/p" \
        | sort -u > "$tmp/iface-$side"
    eval "${side}_lines=$n"
    eval "${side}_inc=$i"
done
if [ "$old_inc" != "$new_inc" ]; then
    echo "  boundary     the file had $old_inc #include directives and has $new_inc: this phase removes none and adds none"
    exit 1
fi
if ! cmp -s "$tmp/iface-old" "$tmp/iface-new"; then
    echo "  boundary     the core -> host interface moved, and this phase is above the boundary entirely:"
    diff "$tmp/iface-old" "$tmp/iface-new" | sed 's/^/               /'
    exit 1
fi
echo "  boundary     the cut at the first \`#include\` is $old_lines -> $new_lines lines, 0 directives and 0 errors under -fsyntax-only either side, with $old_inc directives in the file and none above them; and the interface -- the $(grep -c '' "$tmp/iface-new") names \`used but never defined\`, computed here from the input and never written down -- is UNCHANGED, because every line this phase touches is the core talking to itself"

# --- 10. STRUCTURE ------------------------------------------------------------------
tools/st.sh zhostonly "$f"
tools/phasecheck.sh "$work" "$f" "$state/symbols"
