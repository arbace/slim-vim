#!/bin/sh
# Pure phase 18 -- a file name means the file of that name.  See PURE-GOAL.md.
#
# Usage: tools/pure18.sh <work-dir>      (run from the repository root)
#
# 'path' searching is the last of the three ways this editor knew where files
# live, after globbing (Phase 11) and 'tags' (Phase 14).  vim_findfile() walks a
# path list downward and upward, remembers directories it has visited so a
# symlink loop cannot trap it, and can be asked for the second match and the
# third -- 866 lines behind :find, :sfind, :tabfind and gf.
#
# :find, :sfind and :tabfind are retired: the whole of what they do is the
# search.
#
# gf IS KEPT, and resolves the name literally.  It is the one place a user names
# a file from inside the buffer rather than on a command line, and taking it
# away would be taking away the naming rather than the searching.  Fifteen lines
# against eight hundred and sixty-six, and it reaches the filesystem no
# differently from :e.
#
# 'path' and 'suffixesadd' cannot go -- PV_BOTH and PV_BUF, and a row is what
# initialises its global.  They stay, and now decide nothing.
#
# THE DELTA: gf opens the name under the cursor if there is a file of that name
# rather than searching 'path' for one.  NO Ex command moves, and that is Phase
# 14's lesson again rather than a surprise: retiring a command only shows in the
# sweep if it used to SUCCEED, and :find, :sfind and :tabfind already failed for
# want of an argument.
set -eu

work=${1:?usage: pure17.sh <work-dir>}
f="$work/pure-vim.c"

before_lines=$(grep -c '' "$f")
gcc -c -O0 -o "$work/sym.o" "$f" 2>/dev/null
before_syms=$(nm -u "$work/sym.o" | wc -l)

# --- cut the entry points -------------------------------------------------
python3 tools/nofind.py "$f"
python3 tools/retire.py "$f" find sfind tabfind

sweep() {
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
}

sweep

tools/canon.sh "$f"

if ! gcc -c -O0 -Wall -Wextra -Wno-unused-parameter -o /dev/null "$f" \
        2>"$work/gcc.txt"; then
    echo "  compile      FAILED -- the cut did not leave valid C"
    grep -m5 'error:' "$work/gcc.txt" | sed 's/^/               /'
    exit 1
fi
warn=$(grep 'warning:' "$work/gcc.txt" | grep -cv 'implicit-fallthrough' || true)
if [ "$warn" != 0 ]; then
    echo "  warnings     $warn besides the fall-throughs -- the sweep is not finished"
    grep 'warning:' "$work/gcc.txt" | grep -v 'implicit-fallthrough' | head -5 \
        | sed 's/^/               /'
    exit 1
fi
rm -f "$work/gcc.txt"

gcc -c -O0 -o "$work/nm.o" "$f" 2>/dev/null
ext=$(nm --extern-only --defined-only "$work/nm.o" | awk '{print $NF}' | grep -v '^main$' || true)
if [ -n "$ext" ]; then
    echo "  linkage      these became external: $ext"
    exit 1
fi
echo "  linkage      nm on the object still prints exactly main"

nm -u "$work/sym.o" | awk '{print $2}' | sort > "$work/sym.before"
nm -u "$work/nm.o"  | awk '{print $2}' | sort > "$work/sym.after"
gone=$(comm -23 "$work/sym.before" "$work/sym.after" | tr '\n' ' ')
after_syms=$(nm -u "$work/nm.o" | wc -l)
rm -f "$work/nm.o" "$work/sym.o" "$work/sym.before" "$work/sym.after"
# Reported, not checked: this phase removes a habit rather than a dependency,
# and stat() stays for everything the user does ask for.
echo "  symbols      $before_syms -> $after_syms${gone:+, gone: $gone}"

make -C "$work" clean >/dev/null 2>&1 || true
if make -C "$work" >/dev/null 2>&1; then
    echo "  build        ok, $before_lines -> $(grep -c '' "$f") lines, $(stat -c%s "$work/pure-vim") bytes"
else
    echo "  build        FAILED -- rerun by hand: make -C $work"
    exit 1
fi

# --- the delta, cumulative --------------------------------------------------
tools/puredelta.sh "$work/pure-vim" "$f" --cases bomb_on,filter,read_cmd \
    helpclose intro version cd chdir lcd lchdir tcd tchdir pwd '!' language \
    tags preserve swapname mkvimrc mkexrc checktime
