#!/bin/sh
# Zero phase 35 -- the core calls nothing but the host.  ZERO-PLAN.md 4c, ZERO-GOAL.md.
#
# Usage: pipes/zero35-edit.sh <work-dir> <state-dir>     (run from the repository root)
#
# THREE LIBC FUNCTIONS ARE LEFT IN THE CORE AND THIS PHASE MOVES ALL THREE.  Everything
# else the core still asks the operating system for went out through a named call in an
# earlier phase -- the terminal, the signals, the window size and the sleep at phase 20,
# the exit at 19, the messages at 21, the clock at 26 and 28 -- and what survived is the
# three the editor uses so constantly that nobody looked at them: `malloc`, `free` and
# `write`.  The user's words, 2026-09-19: "malloc, free and write should be moved to
# host, then I guess there is no functional dependency in core beyond host."
#
#   malloc   its prototype and every call of it -- lalloc(), and since phase 34 the
#            malloc-copy-free that replaced ga_grow_inner's and get_keystroke's realloc
#   free     its prototype and every call -- vim_free(), update_wincolor(), and phase
#            34's two again
#   write    its prototype and mch_write() -- every byte the editor draws
#
# HOW MANY OF EACH IS READ OFF THE TEXT AND NOT WRITTEN HERE.  This phase asserted the
# counts once, was handed a boundary where phase 34 had changed two of them, and refused;
# what it asserts now is a PARTITION -- every mention above the boundary is the
# declaration or a call, and each call is rewritten -- which is the same claim about a
# file this phase has never seen (CLAUDE.md, *Rename a name across the whole file*).
#
# so the core gets three declarations and the host three definitions:
#
#     static void *host_alloc(usize n);        beside host_exit and host_message,
#     static void host_free(void *p);          at the end of the ONE run of
#     static int host_write(const char *s, int len);   core -> host prototypes
#
# THE WRAPPERS ARE FAITHFUL AND NOT IMPROVED, which is the trap this phase could fall
# into without any recording seeing it.  mch_write() is
#
#     vim_ignored = (int)write(1, (char *)s, len);
#
# -- ONE write(2), no loop, and the count assigned to the variable this tree keeps for
# results it means to ignore.  A short write therefore LOSES those bytes today, and
# host_write() must lose them too: a wrapper that looped would be a behaviour change in
# a phase that declares none, and the corpus cannot tell the two apart because nothing
# in it makes a write to fd 1 come up short.  The same rule for the other two:
# host_alloc() returns what malloc() returned, nullptr included, so lalloc()'s
# clear_sb_text()/do_outofmem_msg() failure path is reached exactly as before; and
# host_free() calls free(), so it is null-safe for the same reason free() is.  The core
# does not rely on that -- vim_free() tests `x != nullptr` and update_wincolor() frees
# only the arm it allocated -- but the wrapper inherits it rather than adding a test.
#
# WHY host_write() DROPS THE DESCRIPTOR AND THE OTHER TWO KEEP THEIR SIGNATURE.  The
# core's two neighbours on this boundary already name no fd: phase 20's
# `musl_read_input(char *buf, int len)` reads fd 0 inside the host, and phase 21's
# `host_message(const char *msg, int len, int err)` chooses between fd 2 and fd 1 from a
# FLAG, not from a number the core passes.  A descriptor is the host's idea of where the
# screen is; `host_write(s, len)` is the core's -- "these bytes go to the screen" -- and
# it is the output side of musl_read_input, spelled the same way.  host_alloc() and
# host_free() have no such question: a size and a pointer are all there ever was.
#
# THE INT RETURN IS THE ONE PLACE A CAST MOVES.  `(int)write(...)` in the core becomes
# `(int)write(...)` in the host, so the value mch_write() stores in vim_ignored is the
# same bits; what changes is which side of the boundary the narrowing happens on, and
# it happens where the libc type is visible, which is the point of the whole file split.
#
# WHAT THIS PHASE IS FOR, AND IT IS A PROPERTY OF THE BLOCK AND NOT OF THESE THREE
# NAMES.  Above the first `#include` the core carries a run of ORDINARY (non-`static`)
# declarations -- the libc it calls, declared by hand since the headers went below it at
# phase 27.  This edit does not assume what is in that run: it finds it, requires the
# three lines it owns to be in it, takes exactly those three out, and prints what is
# left.  When the run is EMPTY the core names no libc function at all, and every
# outward call it makes is a `musl_` or a `host_`.  That is the arc's claim, and the
# check states it as a measurement of the output rather than as a sentence written here.
#
# THE INPUT BINARY IS BUILT HERE with SOURCE_DATE_EPOCH=0, and the check records from it.
set -eu

work=${1:?usage: zero35-edit.sh <work-dir> <state-dir>}
state=${2:?usage: zero35-edit.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"

# The flags are read out of the boundary's makefile rather than written here a second
# time: zero's compile line is the boundary's (ZERO-GOAL.md rule 8).
cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")
cp "$f" "$state/old.c"
# shellcheck disable=SC2086
( cd "$state" && SOURCE_DATE_EPOCH=0 gcc $cflags $ldflags -o old old.c ) &
pid_old=$!

tools/st.sh edit zero35 "$f" "$state"

# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  hostcall     the input binary did not build with '$cflags' '$ldflags'"; exit 1; }
echo "  hostcall     the input is $state/old, $(stat -c%s "$state/old") bytes, built with SOURCE_DATE_EPOCH=0 beside the source it came from -- every call of the three changes from a direct libc call to a call into the host and three definitions arrive, so the binary is NOT byte-identical and the evidence is a RECORDING of each, with a control and a probe for every one of the three"

# tools/phaserun.sh sweeps next, then runs pipes/zero35-check.sh.
