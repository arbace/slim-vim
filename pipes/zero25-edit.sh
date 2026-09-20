#!/bin/sh
# Zero phase 25 -- the plain host calls.  See ZERO-PLAN.md 4c and ZERO-GOAL.md.
#
# Usage: pipes/zero25-edit.sh <work-dir> <state-dir>     (run from the repository root)
#
# THE CORE REACHES THE HOST THROUGH TWO FUNCTION POINTERS, AND THE ONE REASON THEY ARE
# POINTERS IS GONE.  Phase 19 wrote `static void (*vim_host_exit)(int);` and phase 21
# wrote `static void (*vim_host_message)(const char *, int, int);`, each installed
# through a parameter of `vim_main()` that `main()` passes.  pipes/zero19-edit.sh says
# why in as many words: "a pointer the launcher installs through a parameter adds no
# external symbol, where a `musl_exit(int)` the host defines would" -- the invariant
# being `nm --extern-only --defined-only` giving exactly `main`, and the design at the
# time being TWO TRANSLATION UNITS, where the host's definition of a function the core
# calls has external linkage by construction.
#
# THE DESIGN CHANGED ON 2026-09-18 AND THE INDIRECTION DID NOT FOLLOW IT.  ZERO-PLAN.md
# 4c is now one file with two parts and the first `#include` as the boundary, so the
# host's definitions sit BELOW the core in the SAME translation unit.  A `static`
# forward declaration above and a `static` definition below is all a direct call needs,
# and nothing becomes external: the global the indirection existed to avoid does not
# appear.  So this phase spends two prototypes and gets back two objects, two
# parameters, two assignments and two arguments:
#
#     static void host_exit(int r);                            beside the nine musl_
#     static void host_message(const char *, int, int);        prototypes phase 20 left
#     host_exit(r);            in mch_exit                     1 call site
#     host_message(...);       in five core functions          8 call sites
#     vim_main(int argc, char **argv)                          the signature phase 18
#                                                              wrote, back again
#
# WHERE THE DECLARATIONS GO, AND IT IS NOT "THE TOP OF THE FILE".  Phase 20 left NINE
# `musl_` prototypes in one run -- musl_host_init, musl_get_winsize, musl_term_start,
# musl_term_stop, musl_tty_keys, musl_delay, musl_wait_for_input, musl_read_input,
# musl_suspend -- and those ARE the core's declared calls to the host.  The two go at
# the end of that run, in the order their definitions appear at the bottom of the file,
# so the boundary is ELEVEN prototypes in ONE block and not nine in a block and two
# wherever an object happened to sit.  That it is above every call site is COMPUTED
# here and asserted again in the check, by line number, and not assumed; and it will
# still be above them when a later phase moves the definitions further down, because a
# forward declaration's whole job is to make definition order not matter (CLAUDE.md).
#
# THE PROTOTYPE IS BUILT OUT OF THE DEFINITION'S OWN TWO LINES, so the two cannot
# disagree.  `    static void` + `host_exit(int r)` + `;` is the text that goes in, read
# from the file rather than retyped.
#
# `static` ON BOTH, AND IT IS THE TRAP THIS PHASE CAN FALL INTO.  A prototype that
# forgets it is either a hard error -- MEASURED, `static declaration of 'host_exit'
# follows non-static declaration` -- or, if the definition forgets it too, a SILENTLY
# CORRECT BUILD with two more external symbols.  MEASURED: `nm --extern-only
# --defined-only` on that variant prints `host_exit`, `host_message` and `main` where
# it must print `main` alone.  pipes/zero25-check.sh builds both variants.
#
# THE ASYMMETRY, AND IT IS WHY THIS PHASE COSTS TWO DECLARATIONS AND NOT FOUR.  In one
# translation unit everything above the cut is visible below it for free, so only the
# core -> host direction ever needs a name declared.  MEASURED on this file: the four
# functions that still hold a `va_list` -- `vim_snprintf`, `vim_vsnprintf`,
# `vim_vsnprintf_typval` and `skip_to_arg`, the ones a later phase moves below the
# boundary -- call TWENTY distinct core functions at FORTY-ONE sites, `emsg`, `iemsg`,
# `iobuff_or` and `emsg_iobuff_room` among them, and read `IObuff` once.  A two-file
# split would have had to answer for every one of those; phase 22's survey flagged
# exactly that and called it a genuine boundary question with three unattractive
# answers.  UNDER ONE FILE THERE IS NO QUESTION, and it is recorded here so that the
# earlier note does not send the next reader looking for a problem that the design
# dissolved rather than solved.
#
# THE BINARY WILL NOT BE BYTE-IDENTICAL AND THIS PHASE DOES NOT AIM FOR IT.  At -O0 a
# call through a pointer loads the pointer and calls the register; a direct call is a
# relative call to a known address.  Different instructions, and removing two file-scope
# objects moves everything after them.  MEASURED: the same 788,488 bytes, and 347,279 of
# them differ.  So the evidence is the RECORDING -- two full tools/zrecord.sh runs,
# byte-identical -- which is how every zero phase before 23 was checked, with a control
# for each of the two names this phase makes direct.
#
# THE INPUT BINARY IS BUILT HERE with SOURCE_DATE_EPOCH=0, and the check records from it.
set -eu

work=${1:?usage: zero25-edit.sh <work-dir> <state-dir>}
state=${2:?usage: zero25-edit.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"

# The flags are read out of the boundary's makefile rather than written here a second
# time: zero's compile line is the boundary's (ZERO-GOAL.md rule 8).
cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")
cp "$f" "$state/old.c"
# shellcheck disable=SC2086
( cd "$state" && SOURCE_DATE_EPOCH=0 gcc $cflags $ldflags -o old old.c ) &
pid_old=$!

tools/st.sh edit zero25 "$f"

# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  hostcall     the input binary did not build with '$cflags' '$ldflags'"; exit 1; }
echo "  hostcall     the input is $state/old, $(stat -c%s "$state/old") bytes, built with SOURCE_DATE_EPOCH=0 beside the source it came from -- an indirect call and a direct one are different instructions at -O0, so the binary is NOT byte-identical and the evidence is a RECORDING of each"

# tools/phaserun.sh sweeps next, then runs pipes/zero25-check.sh.
