#!/bin/sh
# Phase 1 -- freeze the configuration.  See SLIM-GOAL.md.
#
# Usage: tools/phase1.sh <work-dir>       (run from the repository root)
#
# This is the one phase that changes what the editor DOES, and it is the reason
# the baselines exist.  Everything it does is a fixed edit to a fixed upstream
# file, so it is a checked-in patch -- 1,297 lines across 13 files -- plus
# twelve deletions.  As an agent it took 17 minutes to retype; as a patch it is
# a second, and what it costs instead is honesty about drift: when upstream
# moves under one of these hunks the patch fails, loudly, at the hunk, which is
# exactly when a human should look.
#
# What the patch contains, and why each part is not derivable from anything in
# the tree:
#
#   +extra_search   four edits, and upstream has no configure flag for it.
#                   --enable-search-extra does not exist and autoconf ignores
#                   an unknown --enable-* silently, so it looks like it worked.
#   no tlib         the tinfo/ncurses/termcap search existed only to satisfy
#                   tgetent(), which this build never calls.
#   term.c          571 of the patch's lines: five built-in terminal tables
#                   deleted, six names added, the 8-colour rows, t_BE dropped,
#                   and the unknown-$TERM fallback moved from ansi to xterm --
#                   which matters more than it sounds, because builtin_ansi has
#                   no key definitions at all, so under it the arrow keys
#                   quietly corrupt the buffer and it looks like the editor
#                   mishandling a motion.
#   optiondefs.h    the 18 option defaults.  P_VI_DEF decides which half of the
#                   {vi, vim} pair to edit, and 'history', 'ruler' and
#                   'compatible' do not carry it, so both halves are set.
#   map.c           the four mappings, through upstream's own init_mappings()
#                   hook.  Non-ASCII left-hand sides are universal character
#                   names, so the file stays pure ASCII.
#   screen.c        the 'lazyredraw' fix: redrawing() and messaging() called
#                   char_avail() whenever p_lz was set, and under -e -s that
#                   reads ahead on stdin, where end of input means "quit".  A
#                   single -c that reported a change was enough to abandon
#                   every -c after it, silently, with status 0.
#
# The generated files -- auto/config.h, auto/config.mk, auto/pathdef.c -- are
# patched rather than reconfigured, which is the same thing by a shorter route:
# the phase's whole point is that they stop being generated.
set -eu

work=${1:?usage: phase1.sh <work-dir>}
jobs=$(nproc 2>/dev/null || echo 4)
base=.reference/baselines

# --- the edits ------------------------------------------------------------
if ! patch -p1 -d "$work" --forward --silent < tools/patches/phase1.patch; then
    echo "  patch        FAILED -- upstream has moved under one of these hunks."
    echo "               That is a result, not a breakage: see which hunk, and"
    echo "               carry the edit forward in SLIM-GOAL.md's Phase 1 terms."
    exit 1
fi
echo "  patch        $(grep -c '^--- a/' tools/patches/phase1.patch) files, $(grep -c '^[+-][^+-]' tools/patches/phase1.patch) changed lines"

# --- the configure machinery, gone ---------------------------------------
# Nothing generates anything from here on, so the generators are dead weight
# and their presence would let a later phase quietly re-run one.
for f in auto/configure config.h.in config.mk.dist config.mk.in configure \
         configure.ac link.sh osdef.sh osdef1.h.in osdef2.h.in pathdef.sh \
         toolcheck; do
    rm -f "$work/src/$f"
done
echo "  frozen       12 configure files removed"

make -C "$work/src" clean >/dev/null 2>&1 || true
make -C "$work/src" -j"$jobs" >/dev/null 2>&1
echo "  build        $work/src/vim"

# --- this is where behaviour is allowed to change, so this is where it is
# --- pinned.  All four harnesses, against the recorded baselines.
if [ ! -d "$base" ]; then
    echo "  baselines    absent -- first pass, nothing to compare against."
    echo "               Record them from this binary before Phase 2."
    exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
bin="$work/src/vim"
fail=0

check() {
    name=$1; shift
    if "$@" >"$tmp/$name.log" 2>&1; then
        printf '  %-12s matches the baseline\n' "$name"
    else
        printf '  %-12s DIFFERS from the baseline\n' "$name"
        head -12 "$tmp/$name.log" | sed 's/^/                 /'
        fail=1
    fi
}

check behaviour sh -c "python3 tools/behaviour.py '$bin' '$tmp/b' >/dev/null && diff -rq '$base/behaviour' '$tmp/b'"
check exsweep   sh -c "python3 tools/exsweep.py '$bin' '$work/src/ex_cmds.h' '$tmp/s' >/dev/null && diff '$base/ref-exsweep.txt' '$tmp/s'"
check pty       sh -c "python3 tools/ptycheck.py '$bin' '$tmp/y' >/dev/null && diff '$base/ref-pty.txt' '$tmp/y'"
check term      sh -c "python3 tools/termcheck.py '$bin' '$tmp/m' >/dev/null && diff '$base/ref-term.txt' '$tmp/m'"

if [ "$fail" != 0 ]; then
    echo "               Phase 1 is the only phase that may change behaviour,"
    echo "               and it may only change it in the ways already recorded."
    echo "               A difference here is either an upstream change that"
    echo "               reached compiled code -- say which patch -- or a bug."
    exit 1
fi
