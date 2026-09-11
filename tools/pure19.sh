#!/bin/sh
# Pure phase 19 -- the last two encoding options.  See PURE-GOAL.md.
#
# Usage: tools/pure19.sh <work-dir>      (run from the repository root)
#
# Phase 16 emptied 'fileencodings' and said so.  It was true at startup and not
# afterwards: set_option_default() special-cases the option, so `:set fencs&`
# restored ucs-bom,utf-8,default,latin1 from fencs_utf8_default -- a third
# reference that phase did not find, because it names the STRING rather than the
# function the other two called.  Measured on the shipped binary: fileencodings=
# at startup, fileencodings=ucs-bom,utf-8,default,latin1 after a reset.
#
# Three readers go, and with them the two options can finally follow:
# set_option_default() stops special-casing 'fileencodings', which is what makes
# Phase 16's claim true at every moment rather than one; readfile() stops
# choosing between an empty list and a list to walk, and takes the buffer's own
# 'fileencoding', which is the branch the empty case already took; and
# did_set_encoding() stops setting up a conversion between 'termencoding' and
# 'encoding', which convert_setup() has answered CONV_NONE to since Phase 16.
#
# 'encoding' STILL cannot go, and this is where that stops being temporary:
# p_enc is the NAME of the one encoding, compared against in twenty-nine places.
# Removing the option would mean removing the name, and the name does work.
#
# THE DELTA: none.  `:set fencs&` no longer restores a list of encodings this
# build cannot convert between, which is a correction rather than a change.
set -eu

work=${1:?usage: pure17.sh <work-dir>}
f="$work/pure-vim.c"

before_lines=$(grep -c '' "$f")
gcc -c -O0 -o "$work/sym.o" "$f" 2>/dev/null
before_syms=$(nm -u "$work/sym.o" | wc -l)

# --- cut the entry points -------------------------------------------------
python3 tools/nofencs.py "$f"

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
python3 tools/dropoptions.py "$f" --strict fileencodings termencoding
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
