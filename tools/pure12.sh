#!/bin/sh
# Pure phase 12 -- :! keeps its name and loses its process.  See PURE-GOAL.md.
#
# Usage: tools/pure12.sh <work-dir>      (run from the repository root)
#
# `:!cmd`, `:[range]!cmd`, `:r !cmd`, `:w !cmd` and `:shell` keep their names,
# their ranges and their parsing.  What goes is everything under them -- the
# fork, the exec, the pipe, the wait -- and the temporary file with them,
# because a temp file is not interface.  It exists only because a Unix shell
# needs a file to read a range out of, and there is no longer a shell.
#
# THE PLACEMENT IS THE PHASE.  do_filter() calls vim_tempname() BEFORE it
# reaches mch_call_shell(), so stubbing the shell alone leaves the whole
# temporary-directory layer alive, assembling a file for a command that will
# never run.  Measured on a scratch build before this was written: cutting at
# mch_call_shell removes 6 libc symbols; cutting at do_filter/do_shell/
# get_cmd_output removes 16.
#
# This is also the seam to keep in mind for whatever comes after pure-vim.  An
# embedded editor with no process of its own may still be given a filter by its
# host, and do_filter() and do_shell() are exactly where that would attach --
# which is a reason to leave the two of them named and reporting rather than
# retired to ex_ni.
#
# THE DELTA: filtering and shelling out report "E319: Sorry, the command is not
# available in this version" instead of running anything.  :language completion
# stops listing locales, silently, because it got them from `locale -a`.
set -eu

work=${1:?usage: pure12.sh <work-dir>}
f="$work/pure-vim.c"

before_lines=$(grep -c '' "$f")
before_syms=$(gcc -c -O0 -o "$work/sym.o" "$f" 2>/dev/null && nm -u "$work/sym.o" | wc -l)

# --- cut above the temp file ----------------------------------------------
python3 tools/noshellout.py "$f"

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

gcc -c -O0 -o "$work/nm.o" "$f" 2>/dev/null
ext=$(nm --extern-only --defined-only "$work/nm.o" | awk '{print $NF}' | grep -v '^main$' || true)
if [ -n "$ext" ]; then
    echo "  linkage      these became external: $ext"
    exit 1
fi
echo "  linkage      nm on the object still prints exactly main"

# This is the first pure phase whose point is the SYMBOL count, so it is
# checked rather than reported.  A phase that shrank the source while leaving
# the surface where it was would have cut in the wrong place, which is exactly
# the mistake this one exists to avoid.
after_syms=$(nm -u "$work/nm.o" | wc -l)
nm -u "$work/sym.o" | awk '{print $2}' | sort > "$work/sym.before"
nm -u "$work/nm.o"  | awk '{print $2}' | sort > "$work/sym.after"
gone=$(comm -23 "$work/sym.before" "$work/sym.after" | tr '\n' ' ')
rm -f "$work/nm.o" "$work/sym.o" "$work/sym.before" "$work/sym.after"
if [ "$after_syms" -ge "$before_syms" ]; then
    echo "  symbols      $before_syms -> $after_syms; this phase must lower it"
    exit 1
fi
echo "  symbols      $before_syms -> $after_syms, gone: $gone"

make -C "$work" clean >/dev/null 2>&1 || true
if make -C "$work" >/dev/null 2>&1; then
    echo "  build        ok, $before_lines -> $(grep -c '' "$f") lines, $(stat -c%s "$work/pure-vim") bytes"
else
    echo "  build        FAILED -- rerun by hand: make -C $work"
    exit 1
fi

# --- the delta, cumulative --------------------------------------------------
tools/puredelta.sh "$work/pure-vim" "$f" --cases filter,read_cmd \
    helpclose intro version cd chdir lcd lchdir tcd tchdir pwd recover '!' 
