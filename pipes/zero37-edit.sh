#!/bin/sh
# Zero phase 37 -- the degenerate unions go.
# See ZERO-GOAL.md, whose charter is that the core is what a transpiler reads, and
# ZERO-PLAN.md 4c, whose rule is that the core's meaning must be on the page.
#
# Usage: pipes/zero37-edit.sh <work-dir> <state-dir>     (run from the repository root)
#
# THIS FILE HAS THIRTEEN `union` KEYWORDS AND SIX OF THEM UNION NOTHING WITH ANYTHING.
# They are not a style that was always there: they are LEFTOVERS of cuts this pipeline
# and whim's already made.  `u_header`'s four link fields were a union of a pointer and
# a swapfile block number, and the arm that named a block went with the swapfile;
# `typval_S.vval` was a union of nine arms -- a string, a list, a dictionary, a funcref,
# a float, a blob, a job, a channel and a number -- and the eval layer took eight of
# them; `estack_T.es_info` was a union of a `ufunc_T *` and a `sctx_T *`, and both went
# with the script stack.  What is left in each case is a variant type with ONE variant,
# which is a value with a longer spelling, and an EMPTY union, which is a value with no
# spelling at all.
#
# WHICH SIX IS COMPUTED AND NOT LISTED.  The edit scans the file for `union`, matches the
# braces, counts the member declarations at depth 1 and takes every union with FEWER THAN
# TWO as degenerate.  It must find both kinds -- at least one degenerate and at least one
# genuine -- so a scanner that stopped matching cannot pass by finding nothing.  Measured
# on the input: 1 member for `uh_next`, `uh_prev`, `uh_alt_next`, `uh_alt_prev` and
# `vval`, 0 for `es_info`, and 2 or 3 for `ae_u`, `lv_u`, `os_oldval`, `os_newval`,
# `rs_u`, `se_u` and `rs_un`, which stay exactly as they are.  Thirteen keywords become
# seven, and the seven that remain are the ones that are doing the job a union is for.
#
# THE EMPTY ONE IS THE ONE WITH A DIALECT ARGUMENT.  `union { } es_info;` is a GNU C
# extension: ISO C requires a struct-declaration-list to be non-empty, and gcc accepts it
# only because it accepts empty structs and unions as an extension -- `-Wpedantic` says
# so, and the check measures that the input draws exactly one such diagnostic and the
# output none.  ZERO-GOAL.md's core is meant to be readable by something that is not gcc,
# and a construct the C standard forbids is exactly the kind of latent exotic that costs
# a reader later.  It is also the cheapest possible removal: the field has ZERO uses, one
# mention in the whole file, its own declaration.
#
# WHAT THE REWRITE IS, and it is the same rule twice.  A single-member union becomes its
# member, keeping the UNION's name:
#
#       union {                              u_header_T *uh_next;
#           u_header_T *ptr;         ->
#       } uh_next;
#
# and every `uh_next.ptr` becomes `uh_next`.  The replacement text is the member's OWN
# declaration with the member's name replaced by the union's, so the type, the pointer
# stars and the internal spacing are the input's and not this program's.  The empty union
# is deleted outright, there being no member to promote and no use to rewrite.
#
# A PARTITION AND NOT A COUNT (CLAUDE.md, *Rename a name across the whole file*).  For
# each of the six names, EVERY mention outside a literal must classify as either its own
# declaration or a `.member` access on it, and a mention that is neither REFUSES.  That is
# what makes the rewrite safe rather than merely mechanical: a `uh_next` assigned or
# compared as a whole, a `sizeof(vval)`, a designated initialiser `.vval = `, or another
# struct with a field of the same name and a different member would all land in the
# leftover class and stop the phase.  The counts are read off the text here and nowhere
# written down, so this stays true of a file the phase has never seen -- which is the
# lesson phase 35 was taught when phase 34 moved its counted anchors.
#
# LITERAL-AWARE AND SINGLE-PASS, for the reason phase 23 measured.  The file has no
# preprocessor and no comments, so a string or character literal is exactly a quote and
# the escaped bytes to its match, and the scan is exact; no literal in this file holds any
# of the six names, which is asserted rather than assumed.  And every span -- six
# declarations and every accessor -- is computed against the ORIGINAL text and applied in
# ONE pass, because a second pass would index spans computed on the first pass's output
# and every offset after the first replacement is shifted.
#
# THE BINARY MUST NOT MOVE, AND THAT IS THE WHOLE OF THIS PHASE'S EVIDENCE.  A union of
# one member has the size and alignment of that member and its offset is the union's; an
# empty union contributes no storage.  So no structure layout changes, no expression
# changes value, and `uh_next.ptr` and `uh_next` name the same object at the same address.
# The check rebuilds both sides with SOURCE_DATE_EPOCH=0 and the boundary's own flags and
# requires THE SAME BYTES -- tier 1 of CLAUDE.md's verification table, which subsumes
# every screen case, every Ex-command row, every command line and every pty scenario at
# once, because the program that would be run is literally the same program.  The control
# that makes that `cmp` mean something is in the check and is a layout change of the same
# shape, in the same struct.
set -eu

work=${1:?usage: zero37-edit.sh <work-dir> <state-dir>}
state=${2:?usage: zero37-edit.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"

# The flags are read out of the boundary's makefile rather than written here a second
# time: zero's compile line is the boundary's (ZERO-GOAL.md rule 8).
cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")
cp "$f" "$state/old.c"
# shellcheck disable=SC2086
( cd "$state" && SOURCE_DATE_EPOCH=0 gcc $cflags $ldflags -o old old.c ) &
pid_old=$!

tools/st.sh edit zero37 "$f"

# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  unions       the input binary did not build with '$cflags' '$ldflags'"; exit 1; }
echo "  unions       the input is $state/old, $(stat -c%s "$state/old") bytes, built with SOURCE_DATE_EPOCH=0 beside the source it came from -- a union of ONE member has the size, the alignment and the offset of that member and an EMPTY union contributes no storage, so this phase changes no layout and no code at all, and the check rebuilds the output the same way and requires THE SAME BYTES"

# tools/phaserun.sh sweeps next, then runs pipes/zero37-check.sh.
