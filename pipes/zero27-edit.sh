#!/bin/sh
# Zero phase 27 -- THE MOVE.  The first `#include` becomes the boundary.
# See ZERO-PLAN.md 4c, ZERO-GOAL.md, and .claude/briefs/zero-reorg.md 1, 4, 5, 6 and 7.
#
# Usage: pipes/zero27-edit.sh <work-dir> <state-dir>     (run from the repository root)
#
# ZERO-PLAN.md 4c's design, which the user settled and which this phase performs:
#
#   zero-vim.c  upper part  the core editor.  NO PREPROCESSOR SYNTAX AT ALL.  At its
#                           top, the musl_-prefixed prototypes: its calls to the host.
#               ----------  the first #include IS the boundary, and nothing marks it
#               lower part  the host.  The #includes, then the musl_ definitions,
#                           host_exit, host_message, and main().
#
# Everything stays `static` except `main`.  One translation unit, one gcc invocation,
# no tool changes.  What this phase produces is a POSITION in the file, and the check
# that falls out of that position is the boundary itself, enumerated by the compiler.
#
# WHAT IT DOES, in the order the constraint forces:
#
#   1  THE ELEVEN `#include`s GO DOWN, to just above the host block phases 18 and 20
#      put at the bottom of the file.  Nothing else marks the line.
#   2  THE VARIADIC LAYER GOES WITH THEM.  `va_list` is <stdarg.h>'s and the core
#      cannot declare it, so every function that holds one is on the host's side:
#      vim_snprintf, vim_vsnprintf, vim_vsnprintf_typval and skip_to_arg -- FOUR, not
#      three; skip_to_arg is the positional-argument walker and ZERO-PLAN.md missed it
#      until phase 22 counted.  Their two prototypes go with them, for the same reason.
#   3  AND WHATEVER ONLY THEY USE, COMPUTED TO A FIXPOINT rather than listed.  The
#      brief's cut reported five functions and two objects after ONE round; this edit
#      compiles the cut, moves what gcc calls unused, and compiles again until nothing
#      above the boundary is dead.  MEASURED: FIVE rounds, 15 functions and 18 objects
#      -- the formatter's whole private island, not its first layer.  The stopping
#      rule is `vim_main` and `deathtrap`, the two the HOST calls, which are unused
#      above the cut by construction and must stay there.
#   4  THE DERIVED CONSTANTS GO UP, AND THIS IS THE ONLY MOMENT THEY CAN.  `enum : int
#      { INT_MAX = (int)(~0u >> 1) };` placed AFTER `#include <limits.h>` is
#      `enum : int { 0x7fffffff = ... };`, a syntax error.  So the constants cannot be
#      written before the move and need no renaming after it: they are exactly this
#      phase's, and that is why phase 26 left them and said so.
#
# THE TWELVE CONSTANTS ARE NOT A LIST THIS PROGRAM REMEMBERS, THEY ARE WHAT THE
# COMPILER ASKS FOR.  The edit performs the move, compiles the cut ALONE, and collects
# every `'X' undeclared` and `unknown type name 'X'` it reports.  That set must be
# exactly the twelve below, or the phase stops: a thirteenth name would mean the core
# still takes something from a header and phase 26 did not finish, and a missing one
# would mean this program is declaring something nobody needs.  MEASURED on the input:
# 23 errors naming exactly these twelve.
#
#   derived   INT_MAX 14   INT_MIN 2   LONG_MAX 51  LONG_MIN 1   LLONG_MAX 3
#             LLONG_MIN 1  ULLONG_MAX 10  SIZE_MAX 1
#   asserted  PATH_MAX 12  EXIT_FAILURE 1  SIGHUP 2  SIGTERM 2
#
# `PATH_MAX` IS AN ARRAY BOUND, which is why all twelve are enumerators and not
# `static const int`: a `static const int` cannot appear in an array bound, a case
# label or an enumerator initialiser, and this one does.  MEASURED, 12 mentions above
# the cut, `char NameBuff[PATH_MAX];` and `vim_strncpy(..., PATH_MAX - 1)` among them.
#
# AN ENUMERATOR IS NOT A TYPEDEF, AND THAT IS WHY THE FAMILIAR NAMES CAN STAY.  A
# later `#define INT_MAX 0x7fffffff` governs only textual occurrences AFTER it, so the
# enumerator above the boundary and the macro below are silent together -- which is a
# different position from `size_t`, where a typedef redefinition has to be
# type-identical, and is the whole reason phase 23 renamed that one and this one
# renames none of these.
#
# AND IT IS ALSO WHY THE CROSS-CHECK HAS TO RESTATE THE DERIVATION.  Below the
# includes the name `INT_MAX` IS the macro, so `static_assert(INT_MAX == INT_MAX)`
# would be a tautology about <limits.h> and would say nothing about the core.  What
# the twelve asserts this phase writes into the file compare is the DERIVING
# EXPRESSION against the header:
#
#   static_assert((int)(~0u >> 1) == INT_MAX, "INT_MAX");
#
# and the left-hand side is not typed twice -- it is the enumerator's own initialiser,
# emitted from the same table, and the check reads both out of the output and requires
# them equal text.  That is the same cross-check phase 26 used, in the only shape the
# move leaves available, and unlike phase 26's it lives in the PRODUCT: the core
# declares, the host verifies, and the verification is the ordinary build.
#
# THE FOUR ASSERTED CONSTANTS ARE ASSERTED AND NOT DERIVED, and the file says so by
# writing them as plain numbers with the same assert beside them.  `PATH_MAX`,
# `EXIT_FAILURE`, `SIGHUP` and `SIGTERM` are policy and ABI numbers, not properties of
# the type system: nothing computes 4096 or 15 from anything, so the honest form is a
# number the host checks rather than an expression that pretends.
#
# NOTHING MOVES UP.  In ONE translation unit everything above the cut is visible below
# it, so only the core -> host direction ever needs a declaration.  MEASURED at phase
# 25: the four variadic functions call twenty distinct core functions at forty-one
# sites and read IObuff once, and not one of them costs a declaration.
#
# WHAT THE MOVE DESTROYS, said plainly, because phase 26's check was built on it.
# After this phase a wrong `void *malloc(int n);` above the boundary is no longer
# `error: conflicting types for 'malloc'` -- there is no second declaration to
# conflict with -- and a `static` one is no longer an error at the declaration but a
# LINK failure, `'malloc' used but never defined`.  That is exactly why phase 26 came
# first and wrote sixteen static_asserts against headers that were still above it.
# The check here breaks the `static` trap in its new shape.
set -eu

work=${1:?usage: zero27-edit.sh <work-dir> <state-dir>}
state=${2:?usage: zero27-edit.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"

# The flags are read out of the boundary's makefile rather than written here a second
# time: zero's compile line is the boundary's (ZERO-GOAL.md rule 8).
cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")
cp "$f" "$state/old.c"
# shellcheck disable=SC2086
( cd "$state" && SOURCE_DATE_EPOCH=0 gcc $cflags $ldflags -o old old.c ) &
pid_old=$!

tools/st.sh edit zero27 "$f" "$state"

# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  boundary     the input binary did not build with '$cflags' '$ldflags'"; exit 1; }
echo "  boundary     the input is $state/old, $(stat -c%s "$state/old") bytes, built with SOURCE_DATE_EPOCH=0 beside the source it came from.  Moving definitions inside ONE translation unit changes every address below the first of them, so this phase's evidence is a byte-identical RECORDING and an unmoved \`nm -u\`, never a cmp"

# tools/phaserun.sh sweeps next, then runs pipes/zero27-check.sh.
