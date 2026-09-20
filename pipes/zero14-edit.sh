#!/bin/sh
# Zero phase 14 -- the strings are the editor's own.  See ZERO-GOAL.md.
#
# Usage: pipes/zero14-edit.sh <work-dir> <state-dir>     (run from the repository root)
#
# Seventeen libc symbols are string and memory work, and every one of them is pure
# computation: no descriptor, no clock, no signal, nothing the host owns.  This phase
# brings sixteen of them into `zero-vim.c` as `static musl_*` functions written from
# /root/musl/src/string/, and moves the seventeenth -- `sprintf` -- onto the printf
# this editor already carries.  `nm -u` goes 61 -> 44 and the recording does not move.
#
# THE MEASUREMENT THAT MADE THIS PHASE POSSIBLE, and it was the open question:
# gcc emits calls to `memcpy` and `memset` FOR ITSELF, for aggregate assignments and
# large zero initialisers, whatever the source calls -- so renaming every call site
# might have left both symbols undefined and forced a definition under the REAL name,
# which is external linkage and would break "nothing is global but main()".  Measured
# on this file and it does not happen: after the rename, `gcc -S` contains NOT ONE
# call to any of the seventeen, and `nm -u` loses all seventeen.  Two things bound it
# rather than luck -- gcc's -O0 inline-copy threshold is between 8 KiB and 16 KiB (a
# 8192-byte struct assignment is inlined, a 16384-byte one calls memcpy), and
# `-Wlarger-than=8192` on zero-vim.c reports exactly ONE object above 8 KiB,
# `options[]` at 13,536 bytes, which is a table nothing assigns whole, while
# `-Wframe-larger-than=8192` reports none.  The check asserts the absence from `nm -u`,
# so a later phase that adds a big aggregate and assigns it whole fails loudly.
#
# (Measured and NOT taken: `-fno-builtin` and `-ffreestanding` each ADD `abs fprintf
# labs` and remove `fputc fputs fwrite putchar`.  A different set, not a smaller
# problem, and none of it is this phase's.  ZEROCFLAGS is untouched, so this phase
# edits no makefile and zero.mk needs no change.)
#
# `sprintf` IS TWO POPULATIONS AND THE SPLIT IS THE WHOLE STORY.  Of its 22
# occurrences, THIRTEEN are ordinary call sites that become `vim_snprintf(dest, size,
# ...)`, and NINE are inside `vim_vsnprintf_typval` ITSELF -- which is what
# vim_snprintf calls.  Using the in-house printf for those nine would be circular.
# What they actually do is narrow: `f` is built twenty lines above the call and is
# `%`, an optional `h`/`l`/`ll`, and one of `p d o u x X`, with NO flags, NO width and
# NO precision -- vim does all of those itself, in `tmp[]`, before and after.  So the
# nine are "write this integer in this base", and they become `musl_fmtnum()` and
# `musl_fmtptr()`, which have no format string and are not a printf.  The `char f[6]`
# block goes with them: leaving it would draw -Wunused-but-set-variable, which is in
# -Wall and which the sweep acts on.
#
# EVERY SIZE ARGUMENT IS KNOWABLE AND NONE IS INVENTED.  Eight are `sizeof()` of a
# visible array or the constant the buffer was allocated with -- `IObuff` is
# `alloc((1024+1))` and `NameBuff` is `alloc(PATH_MAX)` -- three repeat the `alloc()`
# expression from three lines above, and ONE, `highlight_arg_to_string`'s, is a
# pointer PARAMETER where `sizeof(buf)` would be 8 and wrong.  Its bound is
# `MAX_ATTR_LEN`, and that is sound ONLY because the function has exactly one caller,
# `highlight_list_arg`, whose local is `char_u buf[MAX_ATTR_LEN]`.  Both the edit and
# the check assert that caller count: a second caller appearing later would silently
# invalidate the bound, and the assertion is what catches it.
#
# `musl_strcasecmp` AND `musl_strncasecmp` DO NOT CALL `tolower`.  musl's do, and
# musl's `tolower` in the C locale is `(unsigned)c - 'A' < 26 ? c | 32 : c` and
# nothing else, so the arithmetic is inlined here.  That is not a shortcut: `tolower`
# belongs to the character-class phase, which counts its mentions, and four new ones
# here would trip it.  The check asserts `tolower` at exactly 2 mentions after this
# phase, which is what it had before.
#
# THE INPUT BINARY IS BUILT HERE, before the edit, from the boundary's own makefile
# flags, and the source goes with it as $state/old.c.  The check needs the binary for
# its one MUST-DIFFER probe: `t_CF` is a user-settable option used as a FORMAT STRING
# into `char buf[20]`, `sprintf` has no bound, and the binary this phase is handed
# SEGFAULTS on it.  vim_snprintf truncates instead.  That is a bug fix and it is the
# only reachable input on which this phase changes what the editor does.
set -eu

work=${1:?usage: zero14-edit.sh <work-dir> <state-dir>}
state=${2:?usage: zero14-edit.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"

# The flags are read out of the boundary's makefile rather than written here a
# second time: zero's compile line is the boundary's (ZERO-GOAL.md rule 8).
cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")
cp "$f" "$state/old.c"
# shellcheck disable=SC2086
( cd "$state" && gcc $cflags $ldflags -o old old.c ) &
pid_old=$!

tools/st.sh edit zero14 "$f"

# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  strings      the input binary did not build with '$cflags' '$ldflags'"; exit 1; }
echo "  strings      the input is $state/old, $(stat -c%s "$state/old") bytes, beside the source it was built from: the check needs it for the one MUST-DIFFER probe this phase has, where t_CF overflows char buf[20] and the old binary dies of it"

# tools/phaserun.sh sweeps next, then runs pipes/zero14-check.sh.
