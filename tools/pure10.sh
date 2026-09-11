#!/bin/sh
# Pure phase 10 -- the editor stops writing shell scripts, and stops drawing a
# completion menu.  See PURE-GOAL.md.
#
# Usage: tools/pure10.sh <work-dir>      (run from the repository root)
#
# Two cuts, both at the boundary between the editor and everything outside it.
#
# WILDCARDS.  `expand_wildcards()` has two expanders behind it and only one is
# the editor's own.  `gen_expand_wildcards()` walks directories itself and
# handles *, ?, [...], ~ and $VAR without leaving the process; what it cannot do
# it hands to `mch_expand_wildcards()`, which sniffs 'shell' for csh, zsh or
# bash, picks one of five quoting styles, writes a shell function into a
# temporary file, runs it and parses back a NUL-separated list.  That second one
# is the editor doing the shell's job in 250 lines.  Shell-out itself STAYS --
# `:!`, `:%!`, `:r !` are untouched -- but the editor stops generating shell to
# expand a pattern.  What reaches it is now passed through literally.
#
# WILDMENU.  'wildmenu' draws the completion matches in the status line and
# rebinds the arrow keys to walk them; 'wildoptions'=pum draws the same matches
# as a popup.  Both are a display of what Tab completion already computed.
#
# The second cut is the one that needed doing by hand, and the reason is worth
# keeping: p_wmnu is read at thirteen places, and the dead-code sweep counts
# references.  A variable that is never assigned TRUE makes every one of those
# branches unreachable and every one of them is still a reference, so the sweep
# sees a live option.  Folding it to FALSE at the source turns thirteen
# reachability questions into the one question the sweep can answer.
#
# The popup form goes for the mirror image of that reason: with the option gone
# `cmdline_pum_active()` can only answer FALSE while still being CALLED ten
# times, which keeps two hundred lines alive that can no longer run.  The popup
# menu ITSELF stays -- pum_display() has a second caller in insert-mode
# completion -- and only the command line's use of it is cut.
#
# THE DELTA: `:e {a,b}.txt` and backticks in a file argument stop expanding and
# name a file literally; `:e *.c`, `:e ~/x`, `:e $HOME/x` and file-name
# completion are the native path and do not move.  'wildmenu' and the `pum`
# value of 'wildoptions' stop existing; Tab completion behaves as it does with
# `set nowildmenu`, which is what this build now always is.  No Ex command
# changes, and the libc surface does not move at all -- shell-out keeps fork,
# execvp, pipe and waitpid, and opendir/readdir are held by the TEMP DIRECTORY
# (vim_opentempdir, and delete_recursive via readdir_core) as much as by the
# native expander, so cutting the expander would not take them either.  That
# was expected.  This phase buys complexity, not dependencies.
set -eu

work=${1:?usage: pure10.sh <work-dir>}
f="$work/pure-vim.c"

before_lines=$(grep -c '' "$f")

# --- cut the two entry points ---------------------------------------------
python3 tools/nowild.py "$f"
python3 tools/nowildmenu.py "$f"
python3 tools/dropoptions.py "$f" wildmenu

sweep=0
while :; do
    sweep=$((sweep + 1))
    was=$(sha256sum "$f" | cut -d' ' -f1)
    a=$(python3 tools/deadsweep.py "$f" | tail -1)
    c=$(python3 tools/deadprotos.py "$f" | tail -1)
    b=$(python3 tools/typereach.py "$f" --delete | tail -1)
    d=$(python3 tools/funcreach.py "$f" --delete | tail -1)
    echo "  sweep $sweep      $a; $c; $b; $d"
    [ "$(sha256sum "$f" | cut -d' ' -f1)" = "$was" ] && break
    [ "$sweep" -ge 15 ] && { echo "  sweep        not converging"; exit 1; }
done

tools/canon.sh "$f"

warn=$(gcc -c -O0 -Wall -Wextra -Wno-unused-parameter -o /dev/null "$f" 2>&1 \
       | grep 'warning:' | grep -cv 'implicit-fallthrough' || true)
if [ "$warn" != 0 ]; then
    echo "  warnings     $warn besides the fall-throughs -- the sweep is not finished"
    gcc -c -O0 -Wall -Wextra -Wno-unused-parameter -o /dev/null "$f" 2>&1 \
        | grep 'warning:' | grep -v 'implicit-fallthrough' | head -5 | sed 's/^/               /'
    exit 1
fi

# Phase 8's invariant, checked again because this phase moved a declaration:
# nowild.py reuses the slot the shell expander's prototype held, and a
# declaration that loses its `static` hands external linkage to a definition
# that never said so itself.  nm the OBJECT -- a static binary defines 1,400
# symbols of its own and would bury the answer.
gcc -c -O0 -o "$work/nm.o" "$f" 2>/dev/null
ext=$(nm --extern-only --defined-only "$work/nm.o" | awk '{print $NF}' | grep -v '^main$' || true)
rm -f "$work/nm.o"
if [ -n "$ext" ]; then
    echo "  linkage      these became external: $ext"
    exit 1
fi
echo "  linkage      nm on the object still prints exactly main"

make -C "$work" clean >/dev/null 2>&1 || true
if make -C "$work" >/dev/null 2>&1; then
    echo "  build        ok, $before_lines -> $(grep -c '' "$f") lines, $(stat -c%s "$work/pure-vim") bytes"
else
    echo "  build        FAILED -- rerun by hand: make -C $work"
    exit 1
fi

# --- the delta, cumulative --------------------------------------------------
tools/puredelta.sh "$work/pure-vim" "$f" helpclose intro version
