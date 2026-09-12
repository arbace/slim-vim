#!/bin/sh
# Pure phase 7 -- the editor stops asking the environment what language it is
# in.  See PURE-GOAL.md.
#
# Usage: tools/pure11.sh <work-dir>      (run from the repository root)
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
tools/symbols.sh "$f" .cache/symbols/before

# --- cut the locale layer -------------------------------------------------
python3 tools/nolocale.py "$f"
python3 tools/retire.py "$f" language
python3 tools/dropoptions.py "$f" langmap langmenu langnoremap langremap

tools/sweep.sh "$f"

tools/canon.sh "$f"




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
