#!/bin/sh
# Zero phase 24 -- the attributes: 113 that say nothing, 20 that change spelling, 6 that
# stay.  See ZERO-PLAN.md 4c and ZERO-GOAL.md.
#
# Usage: pipes/zero24-edit.sh <work-dir> <state-dir>     (run from the repository root)
#
# `__attribute__` IS A GNU EXTENSION, and this file has 139 of them in a core that is
# headed for another runtime.  The phase looks at all 139, in three groups, and takes a
# different decision on each -- which is the whole of it, and the reason it stops at 133
# rather than 139 is the third group.
#
#   113  __attribute__((unused))          DELETED.  They say nothing here.
#    20  __attribute__((fallthrough));    RESPELLED `[[fallthrough]];`, the C23 form.
#     6  format / format_arg              KEPT, and they are the only ones doing work.
#
# THE 113 SAY NOTHING BECAUSE OF THE FLAGS THE SWEEP ALREADY USES.  Every dead-code
# compile in this pipeline is `-Wall -Wextra -Wno-unused-parameter`
# (tools/deadsweep.py:71, tools/phasecheck.sh:48), so an unused PARAMETER is not
# diagnosed whatever is written on it.  MEASURED: with all 113 gone the sweep's own
# command line prints nothing at all, exactly as it does today.  Upstream needs them
# because upstream compiles this file in configurations where the parameter really is
# unused and others where it is not; there are no configurations here.
#
# AND ALL 113 ARE ON PARAMETERS, WHICH IS COMPUTED AND NOT ASSUMED.  Every one sits
# inside a parenthesised group whose innermost enclosing `(` is preceded by exactly a
# function name -- the 97 lines that hold them are all function DEFINITION headers, each
# followed by a line that is `{` -- so not one is on a variable, an object, a type or a
# field.  This file has no parenthesised group spanning a line break (CLAUDE.md), so
# that is a computation on one line and not a parse of C.  The check states it a second
# way, from the compiler: with `-Wunused-parameter` turned back ON, removing the 113
# produces 92 new warnings and EVERY ONE of them is `-Wunused-parameter` at a line that
# carried an attribute -- not one `-Wunused-variable`, which is what a misplaced
# deletion would have produced.
#
# THE OTHER 21 ARE THE INTERESTING NUMBER: 113 sites, 92 warn when the attribute goes,
# so TWENTY-ONE OF THEM MARK A PARAMETER THIS BUILD USES.  `ex_cquit(exarg_T *eap)`
# reads `eap->addr_count` on its first line; `check_winopt(winopt_T *wop)` dereferences
# `wop` five times; `deathtrap(int sigarg)` compares `sigarg` against SIGHUP.  The
# attribute is not merely redundant there, it is false, and it has been false since some
# whim or zero phase made the parameter live again.  Deleting all 113 deletes 21 wrong
# statements along with 92 unnecessary ones.
#
# THE 20 ARE A ONE-FOR-ONE TEXTUAL SWAP, and `[[fallthrough]]` IS NOT A DIRECTIVE.  It
# is C23 attribute syntax -- a statement, in the grammar, spelled with brackets -- and
# the charter's rule is about PREPROCESSOR syntax: nothing here begins with `#`,
# nothing is expanded, and `gcc -E` on the output produces the same eleven headers
# pasted in and not one line more.  All 20 sites are standalone statements on lines of
# their own, so the swap cannot reach anything else; `[[` occurs ZERO times in the input
# and 20 times in the output, which is the assertion that says so.
#
# C23 IS NOT A NEW DEPENDENCY AND THE CHECK STATES WHAT IT IS RATHER THAN ASSUMING IT.
# Phase 23 measured `-std=c11` REFUSING its typedef; `[[fallthrough]]` is weaker than
# that and the difference is written down rather than glossed: gcc accepts it under
# every `-std` it has, and below C23 `-Wpedantic` says `ISO C does not support '[[]]'
# attributes before C23` and `-pedantic-errors` REFUSES it.  The GNU spelling it
# replaces is pedantically clean everywhere, being a reserved identifier.  So taken
# alone this swap narrows the dialects the file compiles under, and it costs nothing
# because the file is already C23 by four other routes -- `enum : long`,
# `static_assert`, lowercase `bool`, and phase 23's `typeof` and `nullptr`.  MEASURED,
# and computed rather than written here: `-std=c11` on the WHOLE file gives the same
# number of errors before this phase and after it.  The dialect floor does not move.
#
# THE SIX STAY, AND THE BINARY CANNOT TELL YOU WHY.  MEASURED: with all six removed the
# binary is `cmp`-IDENTICAL and `-Wformat=2` goes from 115 `-Wformat-nonliteral`
# warnings to ZERO.  They emit no code and decide what gcc will catch:
#
#   format(printf, 3, 4)   on vim_snprintf, and format(printf, 3, 0) on the two
#                          v-forms.  Phase 22 expanded seven wrappers into 129 direct
#                          calls, so this ONE attribute is now what type-checks 201
#                          `vim_snprintf` mentions' arguments.  The check takes the
#                          prototype line verbatim out of the output and hands
#                          `vim_snprintf(b, 10, "%d", s)` a `const char *`: with the
#                          attribute gcc says `format '%d' expects argument of type
#                          'int'`, and without it gcc is SILENT.
#   format_arg(1)          on `_()` and format_arg(1)/(2) on `NGETTEXT`.  CLAUDE.md
#                          names this as the reason those two are `static inline`
#                          functions rather than macros: it is what lets `-Wformat`
#                          see THROUGH the translation wrapper.  MEASURED from the
#                          other end -- remove `_()`'s and the count goes 115 -> 135,
#                          twenty formats gcc stops being able to follow.
#
# So the phase removes every attribute whose job another flag already does, and keeps
# every attribute that is itself the flag.  That is a rule and not a list, and it is
# what a later phase should apply to anything new.
#
# THE INPUT BINARY IS BUILT HERE with SOURCE_DATE_EPOCH=0, and it is this phase's whole
# evidence, exactly as at phase 23.  Neither edit generates code: `unused` suppresses a
# diagnostic and `[[fallthrough]]` is a hint to the same diagnostic machinery.  The
# check rebuilds the output the same way and requires THE SAME BYTES -- tier 1 of
# CLAUDE.md's verification table, which subsumes every screen case, every Ex-command
# row, every command line and every pty scenario at once, because the program that would
# run is the same program.  Nothing is staged and no editor is run, for that reason.
set -eu

work=${1:?usage: zero24-edit.sh <work-dir> <state-dir>}
state=${2:?usage: zero24-edit.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"

# The flags are read out of the boundary's makefile rather than written here a second
# time: zero's compile line is the boundary's (ZERO-GOAL.md rule 8).
cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")
cp "$f" "$state/old.c"
# shellcheck disable=SC2086
( cd "$state" && SOURCE_DATE_EPOCH=0 gcc $cflags $ldflags -o old old.c ) &
pid_old=$!

python3 - "$f" <<'PY'
import bisect
import re
import sys

TAG = 'attrs'
path = sys.argv[1]
t = open(path, errors='surrogateescape').read()


def die(msg):
    sys.exit('  %-12s %s' % (TAG, msg))


def say(what):
    print('  %-12s %s' % (TAG, what))


def blank_runs(text):
    L = text.split('\n')
    return sum(1 for i in range(1, len(L)) if L[i] == '' and L[i - 1] == '')


# ---- 0. the file this edit was written against --------------------------------------
# ELEVEN DIRECTIVES, every one an `#include` of a system header, on the first eleven
# lines -- ZERO-GOAL.md's charter, which phase 21 left at eleven and phase 23 asserted.
# `[[fallthrough]]` is a STATEMENT and not a directive, so this phase must leave that
# count exactly where it found it.
lines = t.split('\n')
directives = [(i, l) for i, l in enumerate(lines) if l.startswith('#')]
if len(directives) != 11 or [i for i, _ in directives] != list(range(11)):
    die('the file does not have exactly eleven preprocessor directives on its first '
        'eleven lines: %d directives at lines %s'
        % (len(directives), ' '.join(str(i) for i, _ in directives)))
INC = re.compile(r'^#include <([A-Za-z0-9_/.]+)>$')
if any(not INC.match(l) for _, l in directives):
    die('a directive is not an `#include <...>` of a system header, and no phase may '
        'add one')
if '[[' in t:
    die('`[[` already occurs %d times -- this phase introduces C23 attribute syntax, '
        'so an existing occurrence means the phase has already run or the spelling is '
        'taken' % t.count('[['))
say('eleven directives, every one an `#include <...>` on the first eleven lines, and '
    '`[[` at zero occurrences')

# ---- 1. the literals -----------------------------------------------------------------
# Phase 23 was caught out by three string literals holding `NULL` and paid for the
# lesson with a control.  The lesson is applied rather than assumed: the file is scanned
# for string and character literals -- cheap and exact here, there being no preprocessor
# and no comments -- and NO literal may hold `__attribute__`.  Two DO hold the English
# words, `"E424: Too many different highlighting attributes in use"` and `"E1501: format
# argument %d unused in $-style format: %s"`, and neither can be reached by either
# substitution below; they are reported so that the scan is visibly a measurement.
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
                die('an unterminated %s literal at line %d -- the scanner has lost its '
                    'place and every span after it would be wrong'
                    % ('string' if c == '"' else 'character', text.count('\n', 0, i) + 1))
            out.append((i, j + 1))
            i = j + 1
        else:
            i += 1
    return out


S = literal_spans(t)
bad = [t[a:b] for a, b in S if '__attribute__' in t[a:b] or '[[' in t[a:b]]
if bad:
    die('a literal holds `__attribute__` or `[[`, and no substitution below may reach '
        'inside a string: %s' % ' / '.join(bad))
words = [t[a:b] for a, b in S if re.search(r'attribute|fallthrough|unused', t[a:b])]
say('%d string and character literals, NONE holding `__attribute__` or `[[`.  Two hold '
    'the English words and neither is reachable by either substitution: %s'
    % (len(S), ' / '.join(words)))

# ---- 2. the partition: every attribute in the file is one of four kinds ---------------
# A PARTITION AND NOT A COUNT (phase 23's rule).  A fifth kind appearing is a decision
# this phase has never taken, and it must refuse rather than leave it or guess.
KINDS = ('unused', 'fallthrough', 'format', 'format_arg')
all_attrs = list(re.finditer(r'__attribute__\(\((\w+)', t))
kinds = {}
for m in all_attrs:
    kinds[m.group(1)] = kinds.get(m.group(1), 0) + 1
if set(kinds) - set(KINDS):
    die('the file holds an attribute this phase has never looked at: %s -- the three '
        'decisions below are about %s and nothing else'
        % (' '.join(sorted(set(kinds) - set(KINDS))), ' '.join(KINDS)))
say('%d `__attribute__` in the file, and every one is one of four kinds: %s'
    % (len(all_attrs), ', '.join('%s %d' % (k, kinds.get(k, 0)) for k in KINDS)))

# ---- 3. the 113: on a parameter, every one, computed -----------------------------------
# THE SHAPE IS EXACT AND IT IS THE TRAP.  Each is written `<declarator>  __attribute__(
# (unused)) ` -- TWO spaces before and ONE after -- and is followed by the `,` or `)` of
# the parameter list.  Deleting the attribute alone would leave a doubled space, or a
# space before a `)`, and tools/canon.sh does not take either; so what is deleted is the
# two spaces, the attribute and the one space, as one span, which leaves the declarator
# against its own comma.  The check requires canon.sh to be a NO-OP on the output.
UNUSED = re.compile(r'(?<=\S)  __attribute__\(\(unused\)\) (?=[,)])')
n_unused = len(UNUSED.findall(t))
if n_unused != kinds.get('unused', 0):
    die('%d of the %d `unused` attributes are written the way this edit reads them -- '
        'two spaces before, one after, and a `,` or `)` next.  Deleting the rest by a '
        'different rule would leave a doubled space or a space before a paren, and '
        'canon.sh takes neither' % (n_unused, kinds.get('unused', 0)))

# EVERY ONE IS IN A FUNCTION DEFINITION'S PARAMETER LIST, computed on the line.  No
# parenthesised group in this file spans a line break (CLAUDE.md), so the innermost
# enclosing `(` is on the same line and walking back to it is exact.  What must precede
# it is a function name and nothing else; what must follow the line is `{`.
HEAD = re.compile(r'^(?:static\s+[\w \*]+?\s*\**)?(\w+)\s*$')
unused_lines = sorted({t.count('\n', 0, m.start()) for m in
                       re.finditer(r'__attribute__\(\(unused\)\)', t)})
for i in unused_lines:
    l = lines[i]
    k = l.index('__attribute__((unused))')
    d, j = 0, -1
    for j in range(k - 1, -1, -1):
        if l[j] == ')':
            d += 1
        elif l[j] == '(':
            if d == 0:
                break
            d -= 1
    if j < 0 or not HEAD.match(l[:j]):
        die('the `unused` at line %d is not inside a function\'s parameter list -- what '
            'precedes its innermost `(` is %r, which is not a function name, so this '
            'may be an attribute on a variable, an object or a field and the phase has '
            'no decision for those' % (i + 1, l[:j]))
    if lines[i + 1] != '{':
        die('line %d holds an `unused` but is not a function DEFINITION header: the '
            'line below it is %r and not `{`' % (i + 1, lines[i + 1]))
say('%d `__attribute__((unused))`, ALL of them in the parameter list of a function '
    'DEFINITION -- %d header lines, every one followed by `{` -- so not one is on a '
    'variable, an object, a type or a field.  The sweep\'s own flags are '
    '`-Wall -Wextra -Wno-unused-parameter`, which is why they say nothing'
    % (n_unused, len(unused_lines)))

# ---- 4. the 20: a standalone statement, every one ---------------------------------------
FALL = re.compile(r'^[ ]*__attribute__\(\(fallthrough\)\);$', re.M)
n_fall = len(FALL.findall(t))
if n_fall != kinds.get('fallthrough', 0):
    die('%d of the %d `fallthrough` attributes are a whole line of their own -- the '
        'swap below is one-for-one and textual, and an attribute sharing a line with '
        'anything else is not a case it has looked at'
        % (n_fall, kinds.get('fallthrough', 0)))
say('%d `__attribute__((fallthrough));`, every one a standalone statement on a line of '
    'its own, so the swap to the C23 spelling is one-for-one and reaches nothing else'
    % n_fall)

# ---- 5. the six that stay ---------------------------------------------------------------
# Recorded as the exact LINES they sit on, so the check can require them back byte for
# byte.  This phase's rule is "remove every attribute whose job another flag already
# does, and keep every attribute that IS the flag", and these six are the second half.
KEEP = sorted({i for i, l in enumerate(lines) if re.search(r'format(_arg)?\(', l)
               and '__attribute__' in l})
keep_text = [lines[i] for i in KEEP]
n_keep = sum(l.count('__attribute__') for l in keep_text)
if n_keep != kinds.get('format', 0) + kinds.get('format_arg', 0):
    die('the `format` and `format_arg` attributes are on %d lines carrying %d of them, '
        'and there are %d in the file -- the phase must be able to name every one it '
        'keeps' % (len(KEEP), n_keep,
                   kinds.get('format', 0) + kinds.get('format_arg', 0)))
say('%d `format`/`format_arg` on %d lines KEPT, and they are the only attributes doing '
    'work nothing else does: with all six removed the binary is cmp-IDENTICAL and '
    '`-Wformat=2` goes from 115 warnings to ZERO' % (n_keep, len(KEEP)))

# ---- 6. the two substitutions ------------------------------------------------------------
runs_before = blank_runs(t)
pad_before = len(re.findall(r'  [,)]', t))
t, a = UNUSED.subn('', t)
t, b = FALL.subn(lambda m: m.group(0).replace('__attribute__((fallthrough));',
                                              '[[fallthrough]];'), t)
if a != n_unused or b != n_fall:
    die('the substitutions took %d and %d where %d and %d were counted'
        % (a, b, n_unused, n_fall))
say('%d `__attribute__((unused))` deleted with the two spaces before them and the one '
    'after, and %d `__attribute__((fallthrough));` respelled `[[fallthrough]];`'
    % (a, b))

# ---- 7. what the file is now --------------------------------------------------------------
L = t.split('\n')
if len(L) != len(lines):
    die('the file is %d lines and the input was %d -- both edits are WITHIN lines and '
        'neither may add or remove one' % (len(L) - 1, len(lines) - 1))
left = [m.group(1) for m in re.finditer(r'__attribute__\(\((\w+)', t)]
if sorted(left) != sorted(['format'] * kinds.get('format', 0)
                          + ['format_arg'] * kinds.get('format_arg', 0)):
    die('the attributes left are %s, and they must be exactly the %d format and %d '
        'format_arg' % (' '.join(sorted(left)) or 'none',
                        kinds.get('format', 0), kinds.get('format_arg', 0)))
if [L[i] for i in KEEP] != keep_text:
    die('a line carrying a kept attribute is not the line it was, byte for byte')
if len(FALL.findall(t)) or '__attribute__((unused))' in t:
    die('an `unused` or a GNU `fallthrough` survives the substitution')
if len(re.findall(r'^[ ]*\[\[fallthrough\]\];$', t, re.M)) != n_fall:
    die('the %d C23 statements are not %d standalone lines' % (n_fall, n_fall))
if len(re.findall(r'  [,)]', t)) != pad_before:
    die('the edit left %d doubled spaces before a `,` or `)` where there were %d -- '
        'deleting the attribute without its own two spaces is exactly the mistake this '
        'phase can make, and canon.sh does not take it'
        % (len(re.findall(r'  [,)]', t)), pad_before))
if blank_runs(t) != runs_before:
    die('the edit left %d runs of two blank lines where there were %d'
        % (blank_runs(t), runs_before))
changed = sum(1 for i in range(len(L)) if L[i] != lines[i])
if changed != len(unused_lines) + n_fall:
    die('%d lines changed, expected %d -- the %d headers and the %d fallthrough '
        'statements, and nothing else'
        % (changed, len(unused_lines) + n_fall, len(unused_lines), n_fall))
say('%d attributes -> %d, the same %d lines, %d changed -- the %d function headers and '
    'the %d fallthrough statements -- and the doubled-space count unmoved at %d'
    % (len(all_attrs), len(left), len(L) - 1, changed, len(unused_lines), n_fall,
       pad_before))

open(path, 'w', errors='surrogateescape').write(t)
PY

# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  attrs        the input binary did not build with '$cflags' '$ldflags'"; exit 1; }
echo "  attrs        the input is $state/old, $(stat -c%s "$state/old") bytes, built with SOURCE_DATE_EPOCH=0 beside the source it came from -- neither edit generates code, so the check rebuilds the output the same way and requires THE SAME BYTES, which is tier 1 of CLAUDE.md's verification table and subsumes every probe a recording could make"

# tools/phaserun.sh sweeps next, then runs pipes/zero24-check.sh.
