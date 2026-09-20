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

tools/st.sh edit zero23 "$f"

# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  language     the input binary did not build with '$cflags' '$ldflags'"; exit 1; }
echo "  language     the input is $state/old, $(stat -c%s "$state/old") bytes, built with SOURCE_DATE_EPOCH=0 beside the source it came from -- this phase changes no statement, so the check rebuilds the output the same way and requires THE SAME BYTES, which is tier 1 of CLAUDE.md's verification table and subsumes every probe a recording could make"

# tools/phaserun.sh sweeps next, then runs pipes/zero23-check.sh.
