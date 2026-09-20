#!/bin/sh
# Zero phase 38 -- the eight terminal names go, leaving two.  See ZERO-GOAL.md.
#
# Usage: pipes/zero38-edit.sh <work-dir> <state-dir>     (run from the repository root)
#
# `builtin_terminals[]` is the whole of what the core knows how to draw on: a name
# and a capability table, ten times.  An embeddable core has no business carrying
# ten terminal descriptions -- the host decides what it is attached to -- and this
# phase keeps TWO: `xterm-256color`, which is already the name `termcapinit()`
# substitutes when it is given none, and `debug`, which draws its capabilities as
# text and is the only one that can be read without a terminal at all.
#
# WHICH ROWS GO IS COMPUTED: the table MINUS the two, read out of the source.  So is
# everything that follows from it -- which capability tables die, which string
# literals have to be rewritten, and what the fallback may name.  The two names are
# the only thing written down here, and `KEEP` is where they are written.
#
# THE PARTITION, WHICH IS THE WHOLE OF THE ARGUMENT.  A terminal name in this file
# is a STRING LITERAL, so the cut is a cut inside literals -- and the same words
# appear elsewhere as identifiers (`builtin_xterm`), as prefixes (`vim_is_xterm`'s
# `musl_strncasecmp(name, "xterm", 5)`) and inside other literals
# (`"builtin_xterm"`, `"screen.xterm"`).  A textual `s/xterm//` would wreck all of
# them.  So the edit walks the file's string literals -- `cutil.blank()` preserves
# offsets and blanks literal CONTENT, so a `"` surviving in the blanked text is a
# real delimiter and the quotes pair up in order -- and every literal whose content
# EQUALS a removed name must fall in one of four classes:
#
#   row       inside builtin_terminals[]              the row itself; deleted
#   family    inside find_builtin_term()              the xterm-family special case
#   fallback  inside set_termname()                   retargeted, see below
#   prefix    inside vim_is_xterm()                   KEPT, with its reason
#
# A literal that falls in none refuses, which stays true of a file this edit has
# never seen.  Measured on the input: 11 literals, 8 + 1 + 1 + 1.
#
# THE `prefix` CLASS IS KEPT AND IS NOT AN EXCEPTION.  `vim_is_xterm()` asks whether
# a name BEGINS with `xterm` -- `musl_strncasecmp(name, "xterm", 5)`, with the
# length written out -- and `xterm-256color`, which stays, begins with it.  That
# function still has a caller (`term_is_xterm = vim_is_xterm(term)`), so the test is
# live and the literal is not a terminal name at all: it is five characters.  The
# edit requires every `prefix` literal to be an argument of a counted comparison,
# so a naked `musl_strcmp` against a name that no longer exists could not hide here.
#
# THE `family` CLASS IS DEAD CODE THE SWEEP CANNOT SEE, and this is why it goes in
# the EDIT.  `find_builtin_term()` walks the table and returns a row's table when
# `musl_strcmp(name, "xterm") == 0 && vim_is_xterm(term)` -- a test on the ROW's
# name, so the whole clause is a way of saying "the row called xterm serves the
# whole xterm family".  Once no row is called that, the first conjunct is false for
# every row and the clause can never fire; gcc has no warning for a condition that
# is false at run time, and no tool in tools/sweep.sh reads one.  It is the shape
# CLAUDE.md states for a struct field whose only reader a phase deletes: a thing the
# edit knows is dead is the edit's to take.  The edit proves it dead by COMPUTATION
# -- no surviving row carries that name -- and pipes/zero38-check.sh proves it again
# by instrumenting the clause and finding it entered 0 times where the input enters
# it on every startup.
#
# AND THE INPUT ENTERS IT ON EVERY STARTUP, which is worth knowing before anything
# here is rearranged: the compiled default is `xterm-256color`, the `xterm` row
# comes BEFORE the `xterm-256color` row, and `vim_is_xterm("xterm-256color")` is
# true -- so every startup of the input resolves through the family clause and the
# `xterm-256color` row is never reached.  After this phase it is.  Same table either
# way (`builtin_xterm`), which is why nothing in the recording moves for it.
#
# THE `fallback` CLASS IS THE ONE REPAIR, AND IT IS NOT OPTIONAL.  `set_termname()`
# answers an unknown name in two ways: at run time (`:set term=vt320`) it reports
# and FAILS, leaving the terminal alone, which is the E522 the table records; but
# before there is a screen (`starting == NO_SCREEN`, which is the `-T {term}` path)
# it substitutes a name of its own and carries on.  That name is written in the
# source, and it is `xterm` -- one of the eight this phase deletes.  Left alone, the
# cut would leave the fallback naming a terminal that no longer exists, and MEASURED
# on this phase's own output with the repair left out: `-T xterm` and
# `-T no-such-term-9x` both print `E437: Terminal capability "cm" required` and draw
# 2,045 bytes where the baseline draws 2,117 -- an editor with no cursor motion.
# That is not a capability removed on purpose, it is a dangling name.
#
# So the fallback is retargeted, and the new name is COMPUTED and not written here:
# it is the name `termcapinit()` substitutes when it is given none, which the edit
# reads out of that function and requires to be a row that stays.  After this phase
# there is ONE name the editor falls back to and one compiled default, and they are
# the same name.  The message that announces it is rewritten in the same step -- the
# format string and the name move together, as pipes/zero12-edit.sh's `[RO]` did,
# because nothing in the build checks that a message tells the truth.
#
# WHAT THE SWEEP THEN FINDS: three capability tables, `builtin_ansi`,
# `builtin_vt100` and `builtin_dumb`, as -Wunused-variable.  That set is COMPUTED
# too -- a `builtin_*` table whose only mention left, literals excluded, is its own
# definition -- and the edit asserts the set rather than naming three of them.
# `builtin_xterm` is NOT in it: `xterm-256color` still points at it, and the
# mention inside the string literal `"builtin_xterm"` is a literal and not a
# reference, which is why the count is taken on blanked text.
#
# NOT THIS PHASE'S, AND DELIBERATELY LEFT: the 256-colour add-on's test on
# `requested`, and `-T {term}` itself.  Both are the next phase's, and the second is
# what makes the fallback reachable at all -- remove `-T` and `termcapinit()` can
# only ever be handed nothing, so `set_termname()`'s no-screen arm becomes
# unreachable and the sweep takes `report_term_error()` with it.
#
# THE INPUT BINARY IS BUILT HERE, before the edit, from the boundary's own makefile
# flags, as every zero edit since phase 2 does, and the source goes with it as
# $state/old.c.  The check needs both: this phase's delta is `term-moved`, and a
# table that moved is only evidence beside the table it moved from.
set -eu

work=${1:?usage: zero38-edit.sh <work-dir> <state-dir>}
state=${2:?usage: zero38-edit.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"

# The flags are read out of the boundary's makefile rather than written here a
# second time: zero's compile line is the boundary's (ZERO-GOAL.md rule 8).
cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")
cp "$f" "$state/old.c"
# shellcheck disable=SC2086
( cd "$state" && SOURCE_DATE_EPOCH=0 gcc $cflags $ldflags -o old old.c ) &
pid_old=$!

tools/st.sh edit zero38 "$f"

# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  terms        the input binary did not build with '$cflags' '$ldflags'"; exit 1; }
echo "  terms        the input is $state/old, $(stat -c%s "$state/old") bytes, beside the source it was built from: this phase declares term-moved, and a table that moved is only evidence beside the table it moved from"

# tools/phaserun.sh sweeps next, then runs pipes/zero38-check.sh.
