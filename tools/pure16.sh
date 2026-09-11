#!/bin/sh
# Pure phase 16 -- UTF-8, and no other encoding, ever.  See PURE-GOAL.md.
#
# Usage: tools/pure16.sh <work-dir>      (run from the repository root)
#
# Phase 13 made 'encoding' a property of the build rather than of the machine.
# This makes it not a setting at all: mb_init() accepts utf-8 and returns
# "invalid argument" for anything else, so `:set enc=latin1` fails the way a
# misspelt value fails, and the latin1 and DBCS character paths lose their only
# caller and are swept.
#
# THE CONVERSION LAYER IS CUT AT ITS ENTRY POINTS, NOT UNPICKED FROM ITS
# CALLERS, and that is the whole shape of this phase.  readfile() is 1,758 lines
# with conversion woven through a retry loop, partial-character carry-over and a
# `goto retry`; buf_write() is much the same.  Excising that by hand is the kind
# of surgery that compiles, passes a symbol check, and corrupts a file on some
# path nobody tested.  Instead six functions answer differently -- my_iconv_open
# fails, convert_setup produces CONV_NONE, string_convert returns NULL,
# check_for_bom finds none, make_bom writes none -- and every one of those is an
# answer the callers already branch on.  iconv failing is the case upstream
# supports for a system without it.
#
# Only then are the branches that can no longer be taken deleted, and only
# because the calls inside them are what keep iconv, iconv_open and iconv_close
# in the symbol table.  A dependency linked in and never reached is exactly what
# this pipeline exists to remove.
#
# 'encoding' CANNOT be dropped even though it is PV_NONE: its row is what
# initialises p_enc, read in twenty-nine places, so removing it would leave a
# NULL global -- Phase 14's trap in its other form.  It stays, reports utf-8,
# and refuses anything else.
#
# THE DELTA: a byte-order mark becomes three ordinary bytes at the top of the
# buffer, which is what ignoring it means, and the bomb_on behaviour case moves
# because of it.  Of the six encoding options only 'charconvert' can actually
# GO: 'fileencodings' and 'termencoding' are PV_NONE and not reached by name,
# and dropping either still segfaults, because readfile() dereferences p_fencs
# and did_set_encoding() dereferences p_tenc.  'fileencodings' keeps its row
# and loses its content instead.  'fileencoding' and 'bomb' are PV_BUF.  A row
# is what INITIALISES its global; an option is only inert when nothing reads
# that global any more, and tools/dropoptions.py now checks exactly that.
set -eu

work=${1:?usage: pure16.sh <work-dir>}
f="$work/pure-vim.c"

before_lines=$(grep -c '' "$f")
gcc -c -O0 -o "$work/sym.o" "$f" 2>/dev/null
before_syms=$(nm -u "$work/sym.o" | wc -l)

# --- cut the entry points -------------------------------------------------
python3 tools/noenc.py "$f"

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
python3 tools/dropoptions.py "$f" --strict charconvert
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

# The named check, asked of the OBJECT and after the sweep.  Asking it of the
# source before the sweep gets the wrong answer: iconv_string() is still there
# at that point and it is the sweep that removes it.
left=$(nm -u "$work/nm.o" | awk '{print $2}' | grep '^iconv' | tr '\n' ' ' || true)
if [ -n "$left" ]; then
    echo "  iconv        still linked: $left"
    echo "               a dependency that is never reached is still a dependency"
    exit 1
fi
echo "  iconv        no longer linked at all"

nm -u "$work/sym.o" | awk '{print $2}' | sort > "$work/sym.before"
nm -u "$work/nm.o"  | awk '{print $2}' | sort > "$work/sym.after"
gone=$(comm -23 "$work/sym.before" "$work/sym.after" | tr '\n' ' ')
after_syms=$(nm -u "$work/nm.o" | wc -l)
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

# Two checks no build can make: the editor must still be a UTF-8 editor, and it
# must refuse to be anything else.  An editor that silently became latin1 passes
# everything above.
enc=$( cd "$work" && printf 'x\n' > .e.txt \
       && ./pure-vim -u NONE -i NONE -e -s -c 'redir! > .e.out' \
              -c 'set encoding?' -c 'redir END' -c 'qall!' .e.txt \
              </dev/null >/dev/null 2>&1
       tr -d ' \n' < .e.out; rm -f .e.txt .e.out )
if [ "$enc" != "encoding=utf-8" ]; then
    echo "  encoding     got '$enc', expected encoding=utf-8"
    exit 1
fi
ok=$( cd "$work" && printf '\303\240\303\251\n' > .u.txt \
      && ./pure-vim -u NONE -i NONE -e -s -c 'normal gUU' -c 'wq' .u.txt \
             </dev/null >/dev/null 2>&1
      od -An -tx1 < .u.txt | tr -d ' \n'; rm -f .u.txt )
if [ "$ok" != "c380c3890a" ]; then
    echo "  utf-8        gUU over 'a-grave e-acute' gave $ok, expected c380c3890a"
    echo "               the editor is no longer handling UTF-8 as UTF-8"
    exit 1
fi
echo "  utf-8        multibyte case conversion still works, and 'encoding' is utf-8"

# --- the delta, cumulative --------------------------------------------------
tools/puredelta.sh "$work/pure-vim" "$f" --cases bomb_on,filter,read_cmd \
    helpclose intro version cd chdir lcd lchdir tcd tchdir pwd '!' language \
    tags preserve swapname mkvimrc mkexrc checktime
