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

tools/st.sh edit zero24 "$f"

# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  attrs        the input binary did not build with '$cflags' '$ldflags'"; exit 1; }
echo "  attrs        the input is $state/old, $(stat -c%s "$state/old") bytes, built with SOURCE_DATE_EPOCH=0 beside the source it came from -- neither edit generates code, so the check rebuilds the output the same way and requires THE SAME BYTES, which is tier 1 of CLAUDE.md's verification table and subsumes every probe a recording could make"

# tools/phaserun.sh sweeps next, then runs pipes/zero24-check.sh.
