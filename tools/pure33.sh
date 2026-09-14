#!/bin/sh
# Pure phase 33 -- K and the tag jumps, keeping * and #.  See PURE-GOAL.md.
#
# Usage: tools/pure33.sh <work-dir>      (run from the repository root)
#
# nv_ident() is not one command, it is five, and they have nothing in common but
# the first step -- read the identifier under the cursor:
#
#     *  #  g*  g#      search for that word          -- STAY
#     K                 run 'keywordprg' on it        -- goes
#     ]  CTRL-]  g]     jump to its tag               -- goes
#
# * and # are among the most used keys in vim and are pure search, so this phase
# rewrites the function rather than deleting it.  K runs 'keywordprg' through a
# shell and phase 8 took the shell; the tag jumps build `ta `, `tj `, `ts ` or
# `he! ` and hand them to do_cmdline_cmd(), and phase 12 made every one of those
# ex_ni.  Both arms have been building commands that fail.
#
# THE DELTA: none.  These are normal-mode keys, so no Ex command moves, and no
# behaviour case presses any of them.  The phase checks the halves itself.
set -eu

work=${1:?usage: pure33.sh <work-dir>}
f="$work/pure-vim.c"

before_lines=$(grep -c '' "$f")
tools/symbols.sh "$f" .cache/symbols/before

# --- cut the entry points -------------------------------------------------
python3 tools/noident.py "$f"


tools/sweep.sh "$f"

for g in nv_K_getcmd do_nv_ident g_tag_at_cursor; do
    n=$(grep -c -- "$g" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  ident        $g still has $n mentions after the sweep"
        grep -n -- "$g" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
# and what must remain: * and # are still in the table, and still reach nv_ident
for g in "{'*', nv_ident" "{'#', nv_ident" "{POUND, nv_ident" "{Ctrl_RSB, nv_error" "{'K', nv_error"; do
    if [ "$(grep -cF -- "$g" "$f" || true)" = 0 ]; then
        echo "  ident        $g went -- * and # are the half this phase keeps"
        exit 1
    fi
done
echo "  ident        no keywordprg and no tag jump; * # and POUND still dispatch"

tools/phasecheck.sh "$work" "$f" .cache/symbols/before

make -C "$work" clean >/dev/null 2>&1 || true
if make -C "$work" >/dev/null 2>&1; then
    echo "  build        ok, $before_lines -> $(grep -c '' "$f") lines, $(stat -c%s "$work/pure-vim") bytes"
else
    echo "  build        FAILED -- rerun by hand: make -C $work"
    exit 1
fi

# THE CHECK THIS PHASE EXISTS FOR, and it needs a pty: `normal_search()` wants a
# screen, so silent Ex mode measures something that is not the feature.  See
# tools/starcheck.py, which also records what the Ex-mode version got wrong.
if python3 tools/starcheck.py "$work/pure-vim"; then
    echo "  ident        * still finds the next whole word, and skips foobar"
else
    echo "  ident        * no longer searches -- it is the half this phase keeps"
    exit 1
fi

# --- the delta, cumulative --------------------------------------------------
tools/puredelta.sh "$work/pure-vim" "$f" --term-moved --cases bomb_on,filter,read_cmd \
    helpclose intro version cd chdir lcd lchdir tcd tchdir pwd '!' language \
    tags preserve swapname mkvimrc mkexrc checktime command comclear
