#!/bin/sh
# Pure phase 13 -- the editor stops asking the environment what language it is
# in.  See PURE-GOAL.md.
#
# Usage: tools/pure13.sh <work-dir>      (run from the repository root)
#
# `setlocale(LC_ALL, "")` reads $LANG, $LC_ALL and $LC_CTYPE at startup and
# changes how this process compares strings, classifies characters and formats
# a time.  :language lets the user change it again.  enc_locale() derives
# 'encoding' from nl_langinfo(CODESET).  All of it is the editor taking
# instruction from the environment it happens to be started in.
#
# ONE EDIT HERE IS NOT A REMOVAL, and the phase is wrong without it.
# 'encoding' compiles in as **latin1**.  It is only ever utf-8 because
# set_init_default_encoding() asks the locale at startup and overwrites the
# default with the answer.  Remove that call alone and this silently becomes a
# latin1 editor -- every multibyte motion, every :s over non-ASCII, every file
# read.  So the default becomes utf-8 in the same edit.
#
# That is not a behaviour change on this target, and it was checked rather than
# assumed: musl answers UTF-8 to nl_langinfo(CODESET) unconditionally, so the
# derived value was already utf-8, with $LANG set and with $LANG unset.  The
# change makes the encoding a property of the build instead of the machine.
#
# The four lang* options go too.  All four are wired to (char_u *)NULL -- they
# accept a value and store it nowhere -- so they are Phase 5's rule arriving
# late rather than a new decision, and no behaviour can change.
#
# THE DELTA: :language reports that it is not available.  Nothing else: the
# process runs in the C locale now, which is what it was already running in for
# every purpose this build has.
set -eu

work=${1:?usage: pure13.sh <work-dir>}
f="$work/pure-vim.c"

before_lines=$(grep -c '' "$f")
gcc -c -O0 -o "$work/sym.o" "$f" 2>/dev/null
before_syms=$(nm -u "$work/sym.o" | wc -l)

# --- cut the locale layer -------------------------------------------------
python3 tools/nolocale.py "$f"
python3 tools/retire.py "$f" language
python3 tools/dropoptions.py "$f" langmap langmenu langnoremap langremap

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

# The check this phase would be sunk without: an editor that quietly became
# latin1 passes every build and linkage test there is.
make -C "$work" clean >/dev/null 2>&1 || true
if make -C "$work" >/dev/null 2>&1; then
    echo "  build        ok, $before_lines -> $(grep -c '' "$f") lines, $(stat -c%s "$work/pure-vim") bytes"
else
    echo "  build        FAILED -- rerun by hand: make -C $work"
    exit 1
fi
enc=$( cd "$work" && printf 'x\n' > .enc.txt \
       && ./pure-vim -u NONE -i NONE -e -s -c 'redir! > .enc.out' \
              -c 'set encoding?' -c 'redir END' -c 'qall!' .enc.txt \
              </dev/null >/dev/null 2>&1
       tr -d ' \n' < .enc.out; rm -f .enc.txt .enc.out )
if [ "$enc" != "encoding=utf-8" ]; then
    echo "  encoding     got '$enc', expected encoding=utf-8"
    echo "               the locale used to supply this; the default must now carry it"
    exit 1
fi
echo "  encoding     utf-8 by compiled default, with no locale asked"

# --- the delta, cumulative --------------------------------------------------
tools/puredelta.sh "$work/pure-vim" "$f" --cases filter,read_cmd \
    helpclose intro version cd chdir lcd lchdir tcd tchdir pwd recover '!' language
