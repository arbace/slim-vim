#!/bin/sh
# Zero phase 23, the check -- `nullptr` and `usize`.
# See pipes/zero23-edit.sh, and ZERO-PLAN.md 4c.
#
# Usage: pipes/zero23-check.sh <work-dir> <state-dir>    (run from the repository root)
#
# Runs after pipes/zero23-edit.sh and the sweep tools/phaserun.sh runs between them, and
# reads nothing from the edit's shell -- only the work tree and the state directory.
# What the edit left there is `old.c`, the source this phase was HANDED, and `old`, that
# source built with SOURCE_DATE_EPOCH=0 and the boundary's own flags.
#
# THIS PHASE CHANGES NO STATEMENT, so there is no behavioural probe to offer and none is
# offered.  What it has instead is stronger than any recording: THE BINARY IS THE SAME
# BYTES.  That is tier 1 of CLAUDE.md's verification table, and it subsumes every screen
# case, every Ex-command row, every command line and every pty scenario at once, because
# the program that would be run is literally the same program.  tools/zerodelta.sh
# --phase 23 still runs, from tools/phaserun.sh after this check, and corroborates; it
# is not the evidence.  It is phase 16's shape exactly, on three thousand edits instead
# of seven.
#
# WHAT IS CLAIMED, in five parts:
#
#   ARITHMETIC  the counts are computed FROM THE INPUT and not written here: every
#               `NULL` outside a literal became a `nullptr`, every `size_t` became a
#               `usize`, the three literals are UNCHANGED, and `usize` gained exactly
#               one for its own typedef.  So the check is about this phase and not about
#               whatever it was handed.
#   LANGUAGE    the typedef is taken OUT OF THE OUTPUT and compiled four ways: gcc's
#               default and `-std=c23` must ACCEPT it, `-std=c11` and `-std=c99` must
#               REFUSE it.  C23 is a real dependency of this file and is stated rather
#               than assumed.  In the same translation unit, with the REAL <stddef.h>
#               arriving after it, `_Generic((usize)0, size_t: 1, default: 0)` proves
#               `usize` IS `size_t` -- the same type, not merely the same width -- and
#               `sizeof(nullptr) == sizeof(void *)` proves the other half of why the
#               thirty casts could go.
#   SYMBOLS     `nm -u` is THE SAME SET, as a `comm` empty in BOTH directions, and `main`
#               is still the only external symbol.  A rename inside one translation unit
#               cannot move either, and a symbol ARRIVING must fail as loudly as one
#               leaving.
#   THE BINARY  `cmp` of the input's binary and the output's, both built with
#               SOURCE_DATE_EPOCH=0 and the boundary's own flags.  This is the whole
#               evidence.
#   THE CONTROL and it is the point.  The same output with the literal exclusion
#               REMOVED -- a plain `\bNULL\b` -> `nullptr` over the whole text, which
#               rewrites the three strings -- MUST give a different binary.  Measured:
#               1,598 bytes differ, 1,354 of them in `.rodata`, and `strings` reports
#               `[nullptr]`, `nullptr` and an E1507 message that names a C keyword at
#               the user.  Without that control the `cmp` above is a pair of numbers
#               agreeing, and CLAUDE.md is explicit that a test that cannot fail is not
#               evidence.
#
# AND ONE CONTROL THAT MOVES NOTHING, REPORTED RATHER THAN DROPPED.  Reverting one
# `usize` to `size_t` compiles cleanly and gives a byte-identical binary, because the
# `#include`s are still at the TOP of the file and `size_t` is therefore still declared
# above every line of it.  That is the honest statement of what this phase's evidence
# cannot reach: the rename is not yet load-bearing, and it becomes so at phase 26, where
# the same control is three hard errors.  It is phase 22's b3/b4 in this phase's shape.
set -eu

work=${1:?usage: zero23-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero23-check.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"
before_lines=$(cat "$state/input-lines")

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")

# The reproducible build of the OUTPUT and the two controls are started first and waited
# for below: they are three seconds of wall time each that sections 1 to 3 can be
# spending instead.  The controls are written by python from the output, so they are
# this phase's own product with one thing changed and nothing else.
# shellcheck disable=SC2086
( SOURCE_DATE_EPOCH=0 gcc $cflags $ldflags -o "$tmp/new" "$f" ) &
pid_new=$!
python3 - "$f" "$tmp" <<'PY'
import re
import sys

TAG = 'language'
t = open(sys.argv[1], errors='surrogateescape').read()
out = sys.argv[2]

# c1 -- THE LITERAL EXCLUSION REMOVED.  This is the whole mistake this phase can make,
# and it is exactly `sed 's/\bNULL\b/nullptr/g'` on the finished file: the only `NULL`
# left in it are the three inside string literals.
c1, n1 = re.subn(r'\bNULL\b', 'nullptr', t)
if n1 != 3:
    sys.exit('  %-12s c1 rewrote %d `NULL`, expected the three inside string literals '
             '-- there is nothing else left for a literal-unaware sed to find, so this '
             'control would not be the control' % (TAG, n1))
# c2 -- one `usize` back to `size_t`.  Declared to change NOTHING, and reported.
SIG = 'musl_memcpy(void *dest, const void *src, usize n)'
if t.count(SIG) != 1:
    sys.exit('  %-12s the vendored signature `%s` is not in the output exactly once'
             % (TAG, SIG))
c2 = t.replace(SIG, SIG.replace('usize', 'size_t'), 1)
for name, text in (('c1', c1), ('c2', c2)):
    if text == t:
        sys.exit('  %-12s %s changed nothing' % (TAG, name))
    open('%s/%s.c' % (out, name), 'w', errors='surrogateescape').write(text)
print('  %-12s two controls written: c1 the literal exclusion removed -- the plain sed, '
      'which rewrites the three strings -- and c2 one vendored `usize` reverted to '
      '`size_t`' % TAG)
PY
pid_ctl=''
for c in c1 c2; do
    # shellcheck disable=SC2086
    # The stderr goes to a log rather than the terminal: these run in the background
    # while the assertions below decide, and an assertion that refuses first takes the
    # temp directory with it, so two `ld: cannot open output file` lines would otherwise
    # bury the message that actually matters.
    ( SOURCE_DATE_EPOCH=0 gcc $cflags $ldflags -o "$tmp/$c" "$tmp/$c.c" 2>"$tmp/$c.log" ) &
    pid_ctl="$pid_ctl $!"
done

# --- 1. the source, as arithmetic on the input ------------------------------------------
python3 - "$f" "$state/old.c" "$before_lines" <<'PY'
import bisect
import re
import sys

TAG = 'language'
new = open(sys.argv[1], errors='surrogateescape').read()
old = open(sys.argv[2], errors='surrogateescape').read()
before_lines = int(sys.argv[3])
fail = []


def mentions(text, name):
    return len(re.findall(r'\b%s\b' % name, text))


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
                sys.exit('  %-12s an unterminated literal in %s' % (TAG, sys.argv[1]))
            out.append((i, j + 1))
            i = j + 1
        else:
            i += 1
    return out


def outside(text, name):
    """How many `name` are NOT inside a string or character literal."""
    S = literal_spans(text)
    starts = [a for a, _ in S]
    k = 0
    for m in re.finditer(r'\b%s\b' % name, text):
        j = bisect.bisect_right(starts, m.start()) - 1
        if not (j >= 0 and S[j][0] <= m.start() < S[j][1]):
            k += 1
    return k


# THE ARITHMETIC, computed from the input.  Nothing here is a number this file states.
in_null, in_size = mentions(old, 'NULL'), mentions(old, 'size_t')
lit_null = in_null - outside(old, 'NULL')
lit_size = in_size - outside(old, 'size_t')
if lit_null != 3 or lit_size != 0:
    fail.append('the input has %d `NULL` and %d `size_t` inside literals, expected 3 '
                'and 0 -- the exclusion rule is about a set this phase has looked at'
                % (lit_null, lit_size))
for name, want, why in (
        ('NULL', lit_null, 'exactly the literals: the E1507 message, "[NULL]" and '
                           '"NULL", and nothing else in %d' % in_null),
        ('size_t', 0, 'every one of the %d, there being no literal to spare' % in_size),
        ('nullptr', in_null - lit_null, 'one at each `NULL` outside a literal'),
        ('usize', in_size + 1, 'one at each `size_t`, plus its own typedef'),
        ('typeof', 1, 'the typedef and nowhere else'),
):
    if mentions(new, name) != want:
        fail.append('`%s` has %d mentions, expected %d -- %s'
                    % (name, mentions(new, name), want, why))

# THE THREE LITERALS, UNCHANGED, quoted in full.  This is the assertion the control
# below is the other half of: CLAUDE.md's rule that the check for DATA is the strings.
WANT = ['"E1507: Internal error: ap_types or ap_types[idx] is NULL: %d: %s"',
        '"[NULL]"', '"NULL"']
for lit in WANT:
    if old.count(lit) != 1 or new.count(lit) != 1:
        fail.append('the literal %s occurs %d times in the input and %d in the output, '
                    'and must occur once in each -- a rename that reached inside a '
                    'string changes DATA' % (lit, old.count(lit), new.count(lit)))
if [new[a:b] for a, b in literal_spans(new) if re.search(r'\b(NULL|nullptr)\b', new[a:b])] \
        != [old[a:b] for a, b in literal_spans(old) if re.search(r'\bNULL\b', old[a:b])]:
    fail.append('the literals mentioning `NULL` are not the same literals in the same '
                'order as in the input')

# THE ONE NEW LINE, and where it is.
TYPEDEF = 'typedef typeof(sizeof(0)) usize;'
L = new.split('\n')
if new.count(TYPEDEF + '\n') != 1 or L[12] != TYPEDEF:
    fail.append('`%s` is not on line 13 of the output exactly once -- it belongs '
                'directly below the includes, so that when phase 26 moves them to the '
                'bottom it is the first line of the core' % TYPEDEF)
intro = re.findall(r'^[^\n]*\btypedef\b[^\n]*\busize\b[^\n]*$', new, re.M)
if intro != [TYPEDEF]:
    fail.append('`usize` is introduced by %s and not by one typedef -- it is a TYPE '
                'NAME and not a static object' % (' / '.join(intro) or 'nothing'))
if len(L) - 1 != before_lines + 2:
    fail.append('the file is %d lines and the input was %d -- expected exactly two '
                'more, the typedef and its blank line' % (len(L) - 1, before_lines))

# THE CAST THE HAZARD USED TO NEED.  Gone, and its shape is gone with it.
if re.search(r'\(\s*void\s*\*\s*\)\s*nullptr\b', new):
    fail.append('a `(void *)nullptr` survives: the cast existed for the variadic '
                'hazard of an UNTYPED null constant, and `nullptr` is typed')
n_cast = len(re.findall(r'\(void \*\)NULL\b', old))
if n_cast != 30:
    fail.append('the input has %d `(void *)NULL`, and this phase was measured on 30'
                % n_cast)

# THE SHAPE OF THE FILE.  Nothing here is a command, an option, a directive or a
# normal-mode key, and the check says so rather than assuming it.
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
d = [l for l in L if l.startswith('#')]
if len(d) != 11 or any(not l.startswith('#include <') for l in d) or L[:11] != d:
    fail.append('the output does not have exactly the eleven `#include` directives '
                'phase 21 left, on its first eleven lines.  MOVING THEM IS PHASE 26')
if sum(1 for k in range(1, len(L)) if L[k] == '' and L[k - 1] == ''):
    fail.append('there is a run of two blank lines, which canon.sh should have taken')

if fail:
    for line in fail:
        print('  %-12s %s' % (TAG, line))
    sys.exit(1)
print('  %-12s `NULL` %d -> %d and `nullptr` 0 -> %d; `size_t` %d -> 0 and `usize` 0 -> '
      '%d, the extra one being its own typedef.  Every count is computed FROM THE '
      'INPUT, so this is a check on the phase and not on whatever it was handed'
      % (TAG, in_null, lit_null, in_null - lit_null, in_size, in_size + 1))
print('  %-12s THE THREE LITERALS ARE UNCHANGED, and they are the whole of what a '
      'line-wise sed would have got wrong: %s' % ('', ', '.join(WANT)))
print('  %-12s %d `(void *)NULL` became plain `nullptr` -- the cast existed for the '
      'variadic hazard of an untyped null constant, and there is not one '
      '`(void *)nullptr` left; eleven vendored signatures took `usize` with everything '
      'else, and they have been the core\'s own since phases 14 and 15, so no contract '
      'with anybody moved' % ('', n_cast))
print('  %-12s eleven #includes still on the first eleven lines -- MOVING THEM IS PHASE '
      '26 -- cmdnames[] 98, options[] 107, %d -> %d lines and no run of two blank lines'
      % ('', before_lines, len(L) - 1))
PY

# --- 2. C23, and that `usize` IS `size_t` ------------------------------------------------
# The typedef is taken OUT OF THE OUTPUT rather than written here again, so this cannot
# pass while the file says something else.
sed -n '13p' "$f" > "$tmp/typedef.txt"
grep -qx 'typedef typeof(sizeof(0)) usize;' "$tmp/typedef.txt" || {
    echo "  language     line 13 of the output is not the typedef: $(cat "$tmp/typedef.txt")"
    exit 1
}
{
    cat "$tmp/typedef.txt"
    echo 'static usize probe(void) { return sizeof(usize); }'
    echo '#include <stddef.h>'
    echo 'static_assert(_Generic((usize)0, size_t: 1, default: 0), "usize IS size_t");'
    echo 'static_assert(sizeof(nullptr) == sizeof(void *), "nullptr is pointer-sized");'
    echo 'int main(void) { return (int)probe() - (int)sizeof(size_t); }'
} > "$tmp/g.c"
for std in DEFAULT -std=c23; do
    s=$([ "$std" = DEFAULT ] && echo '' || echo "$std")
    # shellcheck disable=SC2086
    if ! gcc $s -Wall -Wextra -Wpedantic -o "$tmp/g" "$tmp/g.c" 2>"$tmp/g.err"; then
        echo "  language     the typedef is REFUSED under $std, and this phase requires it:"
        sed 's/^/               /' "$tmp/g.err" | head -4
        exit 1
    fi
done
"$tmp/g" || { echo "  language     the probe ran and disagreed: sizeof(usize) is not sizeof(size_t)"; exit 1; }
for std in -std=c11 -std=c99; do
    if gcc "$std" -o /dev/null "$tmp/g.c" 2>/dev/null; then
        echo "  language     the typedef is ACCEPTED under $std, and it must not be:"
        echo '               "typeof" is C23, and a check that passes under C11 is not'
        echo '               stating the dependency this file has.'
        exit 1
    fi
done
echo "  language     C23 IS A REAL DEPENDENCY AND IT IS STATED: the typedef taken out of line 13 of the output compiles under gcc's default and -std=c23 and is REFUSED under -std=c11 and -std=c99.  It is not a NEW dependency -- this file already needs C23 for \`enum : long\`, \`static_assert\` and lowercase \`bool\`/\`true\`/\`false\`"
echo "  language     AND THE DERIVATION HOLDS: with the real <stddef.h> arriving after it in the same translation unit, _Generic((usize)0, size_t: 1, default: 0) is 1 -- \`usize\` IS \`size_t\`, the same TYPE and not merely the same width, on any target rather than on this one -- and sizeof(nullptr) == sizeof(void *), which is why the thirty casts could go"

# --- 3. the compile, the linkage and the libc surface ------------------------------------
# NOTHING IS FREED AND NOTHING ARRIVES.  A rename inside one translation unit cannot
# move the libc surface, and a symbol ARRIVING must fail as loudly as one leaving.
cp "$state/symbols/undefined" "$tmp/before.u"
tools/phasecheck.sh "$work" "$f" "$state/symbols"
if ! cmp -s "$tmp/before.u" .cache/symbols/last/undefined; then
    echo "  language     the libc surface moved, and RENAMING A TYPE CANNOT MOVE IT:"
    echo "               gone: $(comm -23 "$tmp/before.u" .cache/symbols/last/undefined | tr '\n' ' ')"
    echo "               came: $(comm -13 "$tmp/before.u" .cache/symbols/last/undefined | tr '\n' ' ')"
    exit 1
fi
echo "  language     symbols $(cat .cache/symbols/last/before) -> $(cat .cache/symbols/last/after), and the set is IDENTICAL as a cmp -- nothing left and nothing arrived; main is still the only external symbol"

# --- 4. the binary, which is the whole of this phase's evidence ---------------------------
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

wait $pid_new || { echo "  language     the reproducible build of the output failed"; exit 1; }
old_size=$(stat -c%s "$state/old")
new_size=$(stat -c%s "$tmp/new")
# A cmp of two files that were never written passes.  Both must exist, both must be the
# size of an editor, and the one under test must be the size make just produced.
if [ "$new_size" -lt 500000 ] || [ "$old_size" -lt 500000 ]; then
    echo "  language     one of the two binaries is $old_size / $new_size bytes, which is not an editor -- a cmp of two files nothing wrote passes"
    exit 1
fi
if [ "$new_size" != "$(stat -c%s "$bin")" ]; then
    echo "  language     the reproducible build is $new_size bytes and make produced $(stat -c%s "$bin"): the two differ by more than a timestamp, so the comparison below would not be about this boundary"
    exit 1
fi
if ! cmp -s "$state/old" "$tmp/new"; then
    echo "  language     THE BINARY MOVED.  This phase renames two names and deletes"
    echo "               thirty casts whose reason has evaporated, and must change no"
    echo "               code at all, so the two binaries -- the input's and the"
    echo "               output's, both built with SOURCE_DATE_EPOCH=0 and the"
    echo "               boundary's own flags -- must be the same bytes."
    echo "               $old_size in, $new_size out.  The GNU build-id note is a hash of"
    echo "               the whole image and sits near the front, so the first difference"
    echo "               below is always that note and never the change itself:"
    cmp "$state/old" "$tmp/new" 2>&1 | sed 's/^/               /'
    exit 1
fi
echo "  language     THE BINARY IS BYTE-IDENTICAL, $new_size bytes either side -- tier 1 of CLAUDE.md's verification table, and the whole of this phase's evidence.  A byte-identical binary subsumes every screen case, every Ex-command row, every command line and every pty scenario at once, because the program that would be run is the same program; tools/zerodelta.sh --phase 23 runs next and corroborates rather than proves"

# --- 5. the controls, and the first of them is the point ----------------------------------
for p in $pid_ctl; do
    wait "$p" || true
done
for c in c1 c2; do
    if [ ! -x "$tmp/$c" ]; then
        echo "  language     the control $c did not build:"
        head -5 "$tmp/$c.log" 2>/dev/null | sed 's/^/               /'
        exit 1
    fi
done
if cmp -s "$state/old" "$tmp/c1"; then
    echo "  language     THE CONTROL c1 DID NOT SHOW.  This phase's own output with the"
    echo "               literal exclusion removed -- the plain sed, which rewrites"
    echo "               \"[NULL]\", \"NULL\" and the E1507 message -- gives a binary"
    echo "               IDENTICAL to the input's, so the cmp above is two numbers"
    echo "               agreeing and proves nothing.  A test that cannot fail is not"
    echo "               evidence (CLAUDE.md)."
    exit 1
fi
diff_bytes=$(cmp -l "$state/old" "$tmp/c1" | wc -l)
objcopy -O binary --only-section=.rodata "$state/old" "$tmp/old.rodata"
objcopy -O binary --only-section=.rodata "$tmp/c1" "$tmp/c1.rodata"
if [ ! -s "$tmp/old.rodata" ] || [ ! -s "$tmp/c1.rodata" ]; then
    echo "  language     objcopy wrote an empty .rodata, and comparing two empty streams reports every pair of binaries identical (CLAUDE.md)"
    exit 1
fi
rodata_bytes=$(cmp -l "$tmp/old.rodata" "$tmp/c1.rodata" | wc -l)
if [ "$rodata_bytes" -lt 1000 ]; then
    echo "  language     c1 differs in $rodata_bytes bytes of .rodata, and the three strings it rewrites are 84 characters between them -- expected over a thousand"
    exit 1
fi
if ! strings -a "$tmp/c1" | grep -qx '\[nullptr\]'; then
    echo "  language     c1's .rodata does not contain '[nullptr]', so the control did not do the thing it is a control for"
    exit 1
fi
if ! cmp -s "$state/old" "$tmp/c2"; then
    echo "  language     THE CONTROL c2 MOVED, AND IT IS DECLARED TO MOVE NOTHING."
    echo "               One vendored parameter reverted from \`usize\` to \`size_t\`"
    echo "               must give the same bytes while the #includes are still at the"
    echo "               top of the file: the two are THE SAME TYPE.  If it now moves"
    echo "               something, this phase's account of its own evidence has to be"
    echo "               rewritten rather than the number quietly updated."
    exit 1
fi
echo "  language     AND IT CAN FAIL: this phase's own output with the literal exclusion removed -- the plain \`sed 's/\\bNULL\\b/nullptr/g'\`, which is the one mistake this phase can make -- differs from the input's binary in $diff_bytes bytes, $rodata_bytes of them in .rodata, and \`strings\` finds '[nullptr]' where the editor's data said '[NULL]'.  That is CLAUDE.md's rule that the check for DATA is the strings, arriving on a phase nobody expected it on"
echo "  language     AND ONE CONTROL MOVES NOTHING, WHICH IS REPORTED RATHER THAN HIDDEN: one vendored \`usize\` reverted to \`size_t\` is byte-identical, because the #includes are still at the TOP and \`size_t\` is still declared above every line of the file.  The rename is not load-bearing YET; at phase 26, which moves them, the same control is three hard errors"

# tools/phaserun.sh runs tools/zerodelta.sh --phase 23 after this check, and this phase
# declares NOTHING: the corpus must not move at all.
