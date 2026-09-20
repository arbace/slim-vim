#!/bin/sh
# Zero phase 16 -- the includes nothing names.  See ZERO-GOAL.md.
#
# Usage: pipes/zero16-edit.sh <work-dir> <state-dir>     (run from the repository root)
#
# `zero-vim.c` inherited EIGHTEEN preprocessor directives from `whim-vim.c`, every one
# an `#include` of a system header, and thirteen phases removed none of them.  Six are
# now needed by nothing, and this phase takes them.
#
# THREE HAVE BEEN DEAD SINCE BEFORE THE PIPELINE STARTED, and one of the three was
# missed twice:
#
#   <sys/stat.h>  supplies nothing.  Its ONE user is `typedef struct stat stat_T;`,
#                 and nothing uses `stat_T`.  Phase 13 named this header and declined
#                 it, because ZERO-GOAL.md's charter stated the directive count as a
#                 property of the pipeline.
#   <fcntl.h>     supplies nothing at all: O_RDONLY, O_WRONLY, O_CREAT, O_APPEND,
#                 O_NONBLOCK and fcntl() are at zero mentions, and have been since
#                 phase 9 freed the symbol.
#   <iconv.h>     supplies nothing at all, and NOBODY HAD NOTICED: `iconv` occurs
#                 exactly once in zero-vim.c and that once is its own `#include`
#                 line.  whim removed the conversion layer and left the header
#                 behind.  ZERO-PLAN.md 4 says "16 directives" for this cut; it is
#                 15, and this header is why.
#
# THREE MORE DIED IN PHASES 14 AND 15, which moved what they supplied inside the file:
#
#   <string.h>    the sixteen `mem*`/`str*` functions, vendored by phase 14.
#   <ctype.h>     TEN identifiers, not five.  isalnum, iscntrl, ispunct, tolower and
#                 toupper are real calls; isalpha, isdigit, isgraph, islower and
#                 isupper are musl MACROS -- `#define isalpha(a) (0 ? isalpha(a) :
#                 (((unsigned)(a)|32)-'a') < 26)` -- so they are in no `nm -u` and a
#                 survey driven by the symbol list cannot see them.  Phase 15 took
#                 all ten.
#   <wctype.h>    towlower and towupper, and `iswupper`, which was a NAME the header
#                 had to supply while being no symbol at all: its one occurrence sat
#                 directly after a `return` inside vim_isupper(), so gcc never
#                 emitted it.  Phase 15 deleted that statement rather than vendoring
#                 a function nothing calls.
#
# WHAT THIS PHASE ASSERTS IS NOT THE LIST.  The edit below states, for each of the six,
# every identifier `zero-vim.c` took from it and requires all of them at ZERO -- but
# that is the pre-flight, not the argument.  The argument is in the check, which drops
# each SURVIVING `#include` in turn and requires the compile to fail, and runs the
# identical loop on the source this phase was handed, where it must name exactly these
# six.  A list can go stale; a computation cannot.
#
# THE ONE HEADER THAT MUST NOT BE TOUCHED, and the reason is worth writing down because
# nothing else in the tree records it.  `<sys/param.h>`'s OWN contribution is `MIN` and
# `MAX`.  Everything else it supplies arrives through three levels of musl-internal
# inclusion -- measured with `gcc -E -H`:
#
#     sys/param.h -> sys/resource.h -> sys/time.h -> sys/select.h
#
# and `select`, `gettimeofday`, `fd_set`, `FD_SET`, `FD_ZERO`, `FD_ISSET`,
# `struct timeval` and every `*_MAX` are supplied by NO OTHER HEADER IN THIS FILE --
# measured, one probe per identifier against each of the eighteen.  `zero-vim.c` has no
# `<limits.h>`, no `<sys/time.h>` and no `<sys/select.h>`.  That is a real fragility and
# it is recorded rather than repaired: repairing it means ADDING three directives, and
# the charter says no phase adds one.  If musl ever reorganises those headers the build
# breaks outright, which is the loud failure and the acceptable one.
#
# THE TYPEDEF GOES IN THE SAME EDIT AS ITS HEADER, and that is the one thing here that
# is not optional.  `typedef struct stat stat_T;` with no `<sys/stat.h>` COMPILES
# CLEANLY -- it simply declares a new, incomplete `struct stat` at file scope -- and is
# a lie: `sizeof(stat_T)` is then an error.  It is the only silent drop in this file.
#
# AND THE SWEEP CANNOT TAKE IT, for two textual reasons, both measured.
# tools/typereach.py takes as roots every identifier mentioned outside a type
# definition, and this definition's name set is {stat, stat_T}.  It is kept alive by
# (a) update_search_stat()'s local variable `searchstat_T stat;` and (b) THE
# `#include <sys/stat.h>` LINE ITSELF, whose text contains the token `stat`.  Measured:
# typereach.py says `0 unreachable` on the committed file, `0 unreachable` with only the
# include gone, `0 unreachable` with only the local renamed, and `1 unreachable --
# stat,stat_T` only when both are gone.  Thirteen sweeps have left it.  It goes here.
#
# ONE BLANK LINE GOES WITH IT.  The typedef sits between two blank lines, so deleting
# the line alone leaves a run of two, which CLAUDE.md states this tree does not have.
# tools/canon.sh would collapse it in the sweep; the edit does it, so the text the sweep
# is handed is already right.
#
# THE INPUT BINARY IS BUILT HERE with SOURCE_DATE_EPOCH=0, and that is this phase's
# whole evidence.  Nothing below changes a line of code, so the check does not offer
# behavioural probes: it rebuilds the output the same way and requires the two binaries
# to be THE SAME BYTES.  That is tier 1 of CLAUDE.md's verification table, and it
# subsumes every probe a recording could make.  SOURCE_DATE_EPOCH is required because
# version.c's `__DATE__ " " __TIME__` otherwise moves between any two builds -- measured,
# two ordinary builds of the same bytes differ at char 633.  The file name is not
# required: zero-vim.c names no __FILE__ and no __LINE__ -- measured, the same source
# built under two different names is identical.
set -eu

work=${1:?usage: zero16-edit.sh <work-dir> <state-dir>}
state=${2:?usage: zero16-edit.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"

# The flags are read out of the boundary's makefile rather than written here a
# second time: zero's compile line is the boundary's (ZERO-GOAL.md rule 8).
cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")
cp "$f" "$state/old.c"
# shellcheck disable=SC2086
( cd "$state" && SOURCE_DATE_EPOCH=0 gcc $cflags $ldflags -o old old.c ) &
pid_old=$!

tools/st.sh edit zero16 "$f"

# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  includes     the input binary did not build with '$cflags' '$ldflags'"; exit 1; }
echo "  includes     the input is $state/old, $(stat -c%s "$state/old") bytes, built with SOURCE_DATE_EPOCH=0 beside the source it came from -- this phase changes no code, so the check rebuilds the output the same way and requires THE SAME BYTES, which is tier 1 of CLAUDE.md's verification table and subsumes every probe a recording could make"

# tools/phaserun.sh sweeps next, then runs pipes/zero16-check.sh.
