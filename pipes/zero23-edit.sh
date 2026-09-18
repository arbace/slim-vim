#!/bin/sh
# Zero phase 23 -- `nullptr` and `usize`: the two the language supplies.
# See ZERO-PLAN.md 4c and ZERO-GOAL.md.
#
# Usage: pipes/zero23-edit.sh <work-dir> <state-dir>     (run from the repository root)
#
# ZERO-PLAN.md 4c settled the design on 2026-09-18: THERE IS NO SPLIT INTO TWO FILES,
# there is one file with two parts, and THE FIRST `#include` IS THE BOUNDARY.  The core
# is the prefix above it and must name nothing a header supplies.  Four phases get
# there; this is the first, and it is deliberately the smallest, BECAUSE IT IS THE ONE
# THAT CAN BE CHECKED BY `cmp`.
#
# WHAT IT DOES.  Two names the core takes from a header are replaced by two the
# LANGUAGE supplies, so that the core owes the header nothing for either:
#
#   NULL    -> nullptr, a C23 KEYWORD.  Nothing is declared, no enumerator, no line.
#   size_t  -> usize, with ONE new line, `typedef typeof(sizeof(0)) usize;`.
#
# NEITHER IS A NEW DEPENDENCY.  gcc here defaults to C23 -- measured, `__STDC_VERSION__`
# is `202311L` -- and this file already depends on it for `enum : long`, `static_assert`
# and the lowercase `bool`/`true`/`false` it uses throughout.  The check states that
# dependency as a measurement rather than leaving it implicit: it takes the typedef line
# OUT OF THE OUTPUT and compiles it under gcc's default, `-std=c23`, `-std=c11` and
# `-std=c99`, where the first two must accept it and the last two must refuse.
#
# WHY `typeof(sizeof(0))` AND NOT `unsigned long`.  `sizeof(0)` HAS type `size_t` by
# definition, so the typedef IS `size_t` on any conforming implementation -- the check
# proves it with `_Generic((usize)0, size_t: 1, default: 0)` against the real
# `<stddef.h>`, which is the same TYPE and not merely the same width.  The alternative
# that was on the table, `typedef unsigned long size_t;`, is correct on this target and
# SILENTLY WRONG on one where `size_t` is not `unsigned long`; and it is silent when it
# is right, so nothing here could tell the two apart.  A derivation cannot be wrong on
# a target this repository has never seen.
#
# THE ONE THING IN THIS PHASE THAT CAN GO WRONG IS THE LITERALS, and it is measured
# rather than reasoned about.  THREE STRING LITERALS IN THIS FILE CONTAIN `NULL`:
#
#   "E1507: Internal error: ap_types or ap_types[idx] is NULL: %d: %s"
#   "[NULL]"                      the printf layer's stand-in for a null %s argument
#   "NULL"                        what `ga_print` writes for an empty growarray
#
# and NO literal contains `size_t`.  A line-wise `sed` rewrites all three: measured, the
# binary then differs by 1,598 bytes -- 50 in `.text`, 174 in `.data` and 1,354 in
# `.rodata` -- and `strings` shows `[nullptr]`, `nullptr` and an E1507 message that
# names a C keyword at the user.  With the three excluded the binary is `cmp`-IDENTICAL.
# That is CLAUDE.md's rule that the check for data is the STRINGS, arriving on a phase
# nobody expected it on, and pipes/zero23-check.sh builds the literal-unaware form as a
# control and requires it to differ.
#
# So the substitution below is not a `sed`.  It scans the file for string and character
# literals first -- which is cheap and exact here, this file having no preprocessor and
# no comments -- and rewrites `\bNULL\b` and `\bsize_t\b` ONLY OUTSIDE them.  BOTH NAMES
# ARE REWRITTEN IN ONE PASS over the original text, and that is not tidiness: a second
# pass would index literal spans computed on the first pass's OUTPUT, and every span
# after the first replacement is shifted.  Measured, the two-pass form leaves five of
# the 437 `size_t` behind -- and leaves a file that still COMPILES and is still
# byte-identical, because `<stddef.h>` is still above it.  The mistake is invisible to
# everything in this phase but the count.
#
# THE THIRTY `(void *)NULL` BECOME PLAIN `nullptr`, which is a decision and not a
# mechanical consequence.  The cast exists for exactly one hazard: an untyped null
# constant in a VARIADIC argument position passes a four-byte `int` where the callee
# reads an eight-byte pointer, and gcc does not warn.  `nullptr` is TYPED --
# `sizeof(nullptr) == sizeof(void *)` -- so the hazard is gone and the cast says nothing
# a reader needs.  Twenty-eight of the thirty are the regexp parser's comma expressions,
# `return (emsg(...), rc_did_emsg = TRUE, (void *)NULL);`, where the cast was carrying
# the comma expression's type; nullptr_t converts to any pointer type on return, so
# they are the same program, which the `cmp` says.  Doing it here rather than later is
# what keeps those thirty sites from being touched twice.
#
# WHAT THE EDIT DOES NOT ASSERT, and it is deliberate: the NUMBER of `NULL` or `size_t`
# in its input.  This is one rule applied to every occurrence, and it is correct for any
# count; pinning the count would make the phase refuse on a tree that is merely bigger
# without making a wrong substitution any more visible.  What it does assert is
# STRUCTURAL and cannot shrink quietly -- the eleven directives, `usize` and `nullptr`
# at zero, and the classification below, which is a partition and not a count.
#
# EVERY `size_t` IS IN A POSITION A TYPEDEF SERVES, and that is what makes the rename
# safe rather than merely mechanical.  The edit classifies all 437 into CASTS (202,
# `(size_t)` and `((size_t)`) and DECLARATIONS (235: parameter, local, struct field and
# return type), and requires the two classes to cover every one with nothing left over.
# A leftover would be a use that is not a type name -- a case label, an array bound, a
# `sizeof(size_t)` -- and there are none.  The partition is computed from the text, so
# it stays true of a file this phase has never seen.
#
# THE ELEVEN VENDORED SIGNATURES CHANGE WITH EVERYTHING ELSE, AND THAT IS NOT AN
# INTERFACE CHANGE.  `musl_memcpy musl_memmove musl_memset musl_memcmp musl_memchr
# musl_strncpy musl_strncmp musl_strncasecmp musl_bsearch musl_qsort` take `usize`
# parameters and `musl_strlen` returns one.  They have been the core's OWN `static`
# definitions since phases 14 and 15 -- nothing outside this file calls them and nothing
# forces libc's spelling on them -- so renaming their parameter type changes no
# contract with anybody.
#
# THE `#include`s STAY WHERE THEY ARE.  Moving them to the bottom is phase 26, and it is
# what makes this phase's own rename load-bearing rather than cosmetic.  Until then
# `size_t` is still DECLARED above every line of this file, which has one consequence
# the check reports rather than hides: reverting a `usize` to `size_t` still compiles
# and still gives a byte-identical binary.  That control moves nothing here on purpose.
#
# THE INPUT BINARY IS BUILT HERE with SOURCE_DATE_EPOCH=0, and it is this phase's whole
# evidence.  Nothing below changes a statement, so the check rebuilds the output the
# same way and requires THE SAME BYTES -- tier 1 of CLAUDE.md's verification table,
# which subsumes every screen case, every Ex-command row, every command line and every
# pty scenario at once, because the program that would run is the same program.
# SOURCE_DATE_EPOCH is required because version.c's `__DATE__ " " __TIME__` otherwise
# moves between any two builds; the file's NAME is not, zero-vim.c naming no `__FILE__`
# and no `__LINE__` and gcc not being given `-g`.
set -eu

work=${1:?usage: zero23-edit.sh <work-dir> <state-dir>}
state=${2:?usage: zero23-edit.sh <work-dir> <state-dir>}
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

TAG = 'language'
path = sys.argv[1]
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


# ---- 0. the file this edit was written against --------------------------------------
# ELEVEN DIRECTIVES, every one an `#include` of a system header, on the first eleven
# lines.  That is ZERO-GOAL.md's charter and phase 21 left it; this phase adds a line
# directly below them and must know exactly where they end.
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
for name in ('usize', 'nullptr'):
    if mentions(t, name):
        die('`%s` already occurs %d times -- this phase introduces it, so an existing '
            'mention means the phase has already run or the name is taken'
            % (name, mentions(t, name)))
say('eleven directives, every one an `#include <...>` on the first eleven lines, and '
    '`usize` and `nullptr` at zero mentions')

# ---- 1. the literals, which are the one thing here that can go wrong -----------------
# A scanner and not a regex.  This file has no preprocessor and no comments, so a string
# or character literal is exactly a quote, the escaped bytes to the matching quote, and
# nothing may cross a newline -- which is asserted, so a scanner that lost its place
# would refuse rather than mask half the file.
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
starts = [a for a, _ in S]


def in_literal(p):
    k = bisect.bisect_right(starts, p) - 1
    return k >= 0 and S[k][0] <= p < S[k][1]


# THE THREE, NAMED.  They are named because the phase must be able to say afterwards
# that they are UNCHANGED, and because a fourth one appearing is a fact worth refusing
# on: it would be a message this phase has never looked at.
WANT = ['"E1507: Internal error: ap_types or ap_types[idx] is NULL: %d: %s"',
        '"[NULL]"', '"NULL"']
holding = [t[a:b] for a, b in S if re.search(r'\bNULL\b', t[a:b])]
if sorted(holding) != sorted(WANT):
    die('the literals containing `NULL` are not the three this phase knows about: %s'
        % (' / '.join(sorted(holding)) or 'none'))
if [t[a:b] for a, b in S if re.search(r'\bsize_t\b', t[a:b])]:
    die('a literal contains `size_t`, which no literal in this file ever has')
say('%d string and character literals, THREE of which contain `NULL` -- the E1507 '
    'message, "[NULL]" and "NULL" -- and none of which contains `size_t`.  A line-wise '
    'sed rewrites all three and moves 1,598 bytes of the binary' % len(S))

# ---- 2. every `size_t` is in a position a typedef serves -----------------------------
# A PARTITION AND NOT A COUNT: casts and declarations must cover every occurrence with
# nothing left over.  A leftover is a use that is not a type name -- a case label, an
# array bound, a `sizeof(size_t)` -- which a typedef could not serve.  Computed, so it
# stays true of a file this phase has never seen.
cast = decl = 0
for m in re.finditer(r'\bsize_t\b', t):
    after = t[m.end():].lstrip()
    if t[:m.start()].rstrip().endswith('(') and after.startswith(')'):
        cast += 1
    elif re.match(r'(\*\s*)*[A-Za-z_,)]', after):
        decl += 1
    else:
        die('`size_t` at line %d is neither a cast nor a declaration, so it is a '
            'position a typedef may not serve: %r'
            % (t.count('\n', 0, m.start()) + 1, t[m.start() - 30:m.end() + 30]))
say('%d mentions of `size_t`, ALL of them type-name positions: %d casts and %d '
    'declarations, and nothing left over' % (cast + decl, cast, decl))

# ---- 3. the substitution: one pass, outside literals ---------------------------------
# ONE PASS OVER THE ORIGINAL TEXT, for both names.  Two passes would index spans
# computed on the first pass's output, and measured, that leaves five of the 437
# `size_t` behind -- in a file that still compiles and whose binary is still identical.
NEW = {'NULL': 'nullptr', 'size_t': 'usize'}
runs_before = blank_runs(t)
parts, last, n = [], 0, dict.fromkeys(NEW, 0)
for m in re.finditer(r'\b(%s)\b' % '|'.join(NEW), t):
    if in_literal(m.start()):
        continue
    parts.append(t[last:m.start()])
    parts.append(NEW[m.group(1)])
    last = m.end()
    n[m.group(1)] += 1
parts.append(t[last:])
t = ''.join(parts)
say('`NULL` -> `nullptr` at %d sites and `size_t` -> `usize` at %d, in one pass and '
    'outside every literal' % (n['NULL'], n['size_t']))

# ---- 4. the cast the hazard used to need ---------------------------------------------
t, n_cast = re.subn(r'\(void \*\)nullptr\b', 'nullptr', t)
if not n_cast:
    die('no `(void *)NULL` site was found, and the phase states there are thirty -- the '
        'convention that made the untyped spelling survivable is not written the way '
        'this edit reads it')
say('%d `(void *)nullptr` -> `nullptr`: the cast existed for the variadic hazard, and '
    '`nullptr` is typed, so it says nothing a reader needs' % n_cast)

# ---- 5. the one new line -------------------------------------------------------------
# DIRECTLY BELOW THE ELEVEN INCLUDES, so that when phase 26 moves them to the bottom the
# typedef is the first line of the core.  It is a TYPEDEF and not a `static` anything:
# `usize` is a type name, and every one of its 437 uses is a type-name position.
ANCHOR = '#include <termios.h>\n\n'
TYPEDEF = 'typedef typeof(sizeof(0)) usize;'
if t.count(ANCHOR) != 1:
    die('the last `#include` is not followed by exactly one blank line, so there is no '
        'unambiguous place for the typedef')
t = t.replace(ANCHOR, ANCHOR + TYPEDEF + '\n\n', 1)

# ---- 6. what the file is now ----------------------------------------------------------
lines = t.split('\n')
directives = [(i, l) for i, l in enumerate(lines) if l.startswith('#')]
if len(directives) != 11 or [i for i, _ in directives] != list(range(11)):
    die('the eleven directives are no longer the first eleven lines')
if lines[12] != TYPEDEF:
    die('the typedef did not land on line 13, below the includes and their blank: %r'
        % lines[12])
if t.count(TYPEDEF + '\n') != 1:
    die('the typedef is not in the file exactly once')
for name, want in (('NULL', 3), ('size_t', 0)):
    if mentions(t, name) != want:
        die('`%s` has %d mentions after the cut, expected %d'
            % (name, mentions(t, name), want))
if [t[a:b] for a, b in literal_spans(t) if re.search(r'\bNULL\b', t[a:b])] != holding:
    die('the three literals holding `NULL` are not the three they were')
intro = re.findall(r'^[^\n]*\btypedef\b[^\n]*\busize\b[^\n]*$', t, re.M)
if intro != [TYPEDEF] or 'static' in TYPEDEF:
    die('`usize` is introduced by something other than exactly one typedef: %s -- it is '
        'a TYPE NAME and not a static object, and every one of its uses is a type-name '
        'position' % (' / '.join(intro) or 'nothing'))
if blank_runs(t) != runs_before:
    die('the edit left %d runs of two blank lines where there were %d'
        % (blank_runs(t), runs_before))
say('the three `NULL` literals are the only `NULL` left, `size_t` is at zero, `usize` '
    'is a typedef on line 13 and %d runs of two blank lines, exactly as before'
    % blank_runs(t))

open(path, 'w', errors='surrogateescape').write(t)
PY

# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  language     the input binary did not build with '$cflags' '$ldflags'"; exit 1; }
echo "  language     the input is $state/old, $(stat -c%s "$state/old") bytes, built with SOURCE_DATE_EPOCH=0 beside the source it came from -- this phase changes no statement, so the check rebuilds the output the same way and requires THE SAME BYTES, which is tier 1 of CLAUDE.md's verification table and subsumes every probe a recording could make"

# tools/phaserun.sh sweeps next, then runs pipes/zero23-check.sh.
