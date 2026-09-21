#!/bin/sh
# Zero phase 14, the check -- the strings are the editor's own.
# See pipes/zero14-edit.sh, and ZERO-GOAL.md.
#
# Usage: pipes/zero14-check.sh <work-dir> <state-dir>    (run from the repository root)
#
# Runs after pipes/zero14-edit.sh and the sweep tools/phaserun.sh runs between them,
# and reads nothing from the edit's shell -- only the work tree and the state
# directory.  What the edit left there is `old`, the binary this phase was HANDED,
# and `old.c`, the source it was built from.
#
# SIX THINGS ARE PROVED.
#
# 1. THE SOURCE, as counts.  The seventeen bare names at 0, the sixteen musl_* at
#    their source counts plus their own definitions, `sprintf` and `f_l` at 0,
#    `vim_snprintf` 55 -> 68, and `tolower` STILL AT 2.
#
#    THE `tolower` COUNT IS NOT DECORATION.  musl's strcasecmp() and strncasecmp()
#    call tolower(); these do not, and inline `(unsigned)c - 'A' < 26 ? c | 32 : c`
#    instead, which IS musl's tolower() in the C locale -- `tolower.c` is
#    `if (isupper(c)) return c | 32; return c;` and `isupper.c` is
#    `(unsigned)c-'A' < 26`.  Inlining costs nothing and keeps this phase and the
#    character-class phase independent: that phase counts `tolower` mentions, and
#    four new ones here would trip it.
#
#    THE SINGLE CALLER IS ASSERTED AGAIN HERE, and that is the point of asserting it
#    at all.  `highlight_arg_to_string(..., char_u *buf)` takes a POINTER, so
#    sizeof(buf) is 8; its size argument is MAX_ATTR_LEN, which is only its buffer's
#    size while `highlight_list_arg` is its ONLY caller and declares `char_u
#    buf[MAX_ATTR_LEN]`.  A second caller appearing later, with a smaller buffer,
#    would silently invalidate the bound and nothing else in this tree would notice.
#    So the count is pinned at 2 -- the definition and the one call -- for ever.
#
#    AND THE CHARTER: eighteen lines starting with `#`, every one an `#include <...>`,
#    and not one comment or tab added.  This phase writes 301 lines of C into
#    zero-vim.c and none of it is a directive and none of it is a comment.
#
# 2. THE LIBC SURFACE, NAMED AS A SET AND NOT AS A COUNT -- `memchr memcmp memcpy
#    memmove memset sprintf strcasecmp strcat strchr strcmp strcpy strlen strncasecmp
#    strncmp strncpy strpbrk strstr`, seventeen, and NOTHING arriving.  61 -> 44.
#
#    THIS IS THE MEASUREMENT THE PHASE TURNS ON.  gcc emits `memcpy` and `memset`
#    FOR ITSELF, for aggregate assignments and large zero initialisers, whatever the
#    source calls -- so a rename might have left both behind and forced a definition
#    under the real name, which is external linkage.  It does not happen here:
#    `gcc -S` on the swept text contains not one call to any of the seventeen.  The
#    check asserts the `nm -u` absence, so a later phase that adds an aggregate over
#    gcc's threshold (measured between 8 KiB and 16 KiB) and assigns it whole fails
#    loudly rather than quietly reacquiring a libc symbol.
#
#    ZERO-PLAN.md 4b's invariant is asserted again beside it, unchanged.
#
# 3. THE ENUMERATORS, which must not move at all: this phase deletes no type, no
#    enum and no table row, so all 1,181 must come back with the same values.
#
# 4. THE ONE MUST-DIFFER PROBE, and it is a BUG FIX.  `t_CF` is a user-settable
#    option (options[] row "t_CF") that `term_font()` uses as a FORMAT STRING into
#    `char buf[20]`.  `sprintf` has no bound.  Measured: `:set t_CF=` + 40 X + `%d`,
#    then `:highlight Search ctermfont=3` and a search, kills the binary this phase
#    was handed -- exit -11, SIGSEGV -- and exits 0 here with the output truncated to
#    nineteen characters.  It is the ONLY reachable input on which this phase changes
#    what the editor does, and the check requires BOTH halves: the old one must die
#    and the new one must not.
#
# 5. THE FORMATS THAT RENDER DIFFERENTLY, recorded rather than declared.  `t_CF` is
#    the one place a USER-SUPPLIED format reaches the formatter, and vim's own printf
#    is not musl's: `%f` goes from `[0.000000]` to `[f]`, `%b` from nothing to
#    `[1101]`, `%*d` from a garbage int to the argument, `%z` from nothing to `[z]`.
#    `%d` and `%1$d` are identical.  `%s` SEGFAULTS ON BOTH BINARIES and is not this
#    phase's: t_CF `%s` reads a pointer out of an int argument, and it did that
#    before.  Nothing in the instrument sets t_CF, t_CF is empty under every built-in
#    terminal but `debug` (where it is "[CF%d]"), and `%d` is the only directive that
#    entry uses -- so this is a finding the check records and NOT a declared delta.
#
# 6. THE PROBES THAT MUST NOT DIFFER: thirty-two sessions on both binaries, covering
#    every one of the thirteen external sprintf sites and the number formatting the
#    nine internal ones did, plus the places where strcasecmp, strncasecmp, memcmp,
#    memcpy and strstr are the only reason the screen says what it says.
#
#    WHAT NO PROBE COVERS, AND THE PHASE SAYS SO RATHER THAN PRETENDING.  Four of the
#    vendored functions are there for code that cannot run, measured by breaking each
#    and finding that nothing moves: `musl_strpbrk` (its one site needs P_NFNAME or
#    P_NDNAME, and each of those has exactly two mentions in the file -- its own enum
#    and that one test -- so no options[] row carries either), `musl_memchr` (its one
#    site is vim_vsnprintf_typval's `%.*s`, and the only `%.*s` in the file is the
#    OSC-timeout message), `musl_strchr`'s NUL arm (both call sites pass '%') and
#    `musl_fmtptr` (nothing formats a pointer).  Their correctness rests on musl's
#    source, not on the recording.
#
#    The corpus itself is tools/zerodelta.sh --phase 14, which tools/phaserun.sh runs
#    after this check, and its declaration is NOTHING AT ALL.

# THE BODY IS GO: tools/go/internal/check/zero14.go and tools/go/internal/check/zero14probes.go, run through tools/st.sh.
# The tools it runs, named as PATHS so tools/implhash.sh hashes them into
# this phase's key -- a path the program does not name is a dependency no key
# sees.  Do not delete these lines.
#   tools/enumvals.sh
#   tools/phasecheck.sh
#   tools/st.sh
set -eu

work=${1:?usage: zero14-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero14-check.sh <work-dir> <state-dir>}
exec tools/st.sh check zero14 "$work" "$state"
