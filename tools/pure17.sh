#!/bin/sh
# Pure phase 17 -- the editor stops re-reading a file it has already read.
# See PURE-GOAL.md.
#
# Usage: tools/pure17.sh <work-dir>      (run from the repository root)
#
# vim watches the files it holds.  check_timestamps() walks every buffer and
# stats its file -- from the main loop, from insert mode, from the Press ENTER
# prompt, and whenever the terminal regains focus -- and buf_check_timestamp()
# does the same for one buffer on entering it.  If the file moved underneath it
# prompts, and with 'autoread' it reloads.
#
# That is the editor initiating filesystem traffic on its own account.  Phase 15
# retired :checktime, which removed the COMMAND; this removes the POLLING, which
# is what actually reached the disk.  What is left is an editor that reads a
# file when told to and writes it when told to.
#
# NOT touched: check_mtime(), which buf_write() calls before overwriting a file
# that changed since it was read.  That is not polling -- it happens only when
# the user asks to write, and it is what stops a write silently clobbering
# someone else's edit.  b_mtime_read is still recorded on read, so it still
# works.
#
# 'autoread' cannot go: it is PV_BOTH, and its row is what initialises the
# global.  It stays, and now decides nothing.
#
# THE DELTA: none the harness records.  Nothing it does changes a file behind
# the editor's back, so nothing it does reaches this code.
set -eu

work=${1:?usage: pure17.sh <work-dir>}
f="$work/pure-vim.c"

before_lines=$(grep -c '' "$f")
gcc -c -O0 -o "$work/sym.o" "$f" 2>/dev/null
before_syms=$(nm -u "$work/sym.o" | wc -l)

# --- cut the entry points -------------------------------------------------
python3 tools/nostat.py "$f"

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
