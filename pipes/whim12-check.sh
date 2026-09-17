#!/bin/sh
# Whim phase 12, the check -- UTF-8, and no other encoding, ever.
# See pipes/whim12-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim12-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim12-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim12-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim12-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

# The named check, asked of the OBJECT and after the sweep.  Asking it of the
# source before the sweep gets the wrong answer: iconv_string() is still there
# at that point and it is the sweep that removes it.
tools/phasecheck.sh "$work" "$f" "$state/symbols"
if [ "$(cat .cache/symbols/last/after)" -ge "$(cat .cache/symbols/last/before)" ]; then
    echo "  symbols      this phase must lower the count"
    exit 1
fi

# The named check, asked of the compiled object and after the sweep.  Asking the
# SOURCE beforehand gets the wrong answer: iconv_string() is still there at that
# point and it is the sweep that removes it.
left=$(grep '^iconv' .cache/symbols/last/undefined | tr '\n' ' ' || true)
if [ -n "$left" ]; then
    echo "  iconv        still linked: $left"
    echo "               a dependency that is never reached is still a dependency"
    exit 1
fi
echo "  iconv        no longer linked at all"

tools/phasebuild.sh "$work" "$before_lines"

# Two checks no build can make: the editor must still be a UTF-8 editor, and it
# must refuse to be anything else.  An editor that silently became latin1 passes
# everything above.
enc=$( cd "$work" && printf 'x\n' > .e.txt \
       && ./whim-vim -u NONE -i NONE -e -s -c 'redir! > .e.out' \
              -c 'set encoding?' -c 'redir END' -c 'qall!' .e.txt \
              </dev/null >/dev/null 2>&1
       tr -d ' \n' < .e.out; rm -f .e.txt .e.out )
if [ "$enc" != "encoding=utf-8" ]; then
    echo "  encoding     got '$enc', expected encoding=utf-8"
    exit 1
fi
ok=$( cd "$work" && printf '\303\240\303\251\n' > .u.txt \
      && ./whim-vim -u NONE -i NONE -e -s -c 'normal gUU' -c 'wq' .u.txt \
             </dev/null >/dev/null 2>&1
      od -An -tx1 < .u.txt | tr -d ' \n'; rm -f .u.txt )
if [ "$ok" != "c380c3890a" ]; then
    echo "  utf-8        gUU over 'a-grave e-acute' gave $ok, expected c380c3890a"
    echo "               the editor is no longer handling UTF-8 as UTF-8"
    exit 1
fi
echo "  utf-8        multibyte case conversion still works, and 'encoding' is utf-8"

# --- the delta, cumulative --------------------------------------------------
tools/whimdelta.sh "$work/whim-vim" "$f" --cases bomb_on,filter,read_cmd \
    helpclose intro version cd chdir lcd lchdir tcd tchdir pwd '!' language \
    tags preserve swapname mkvimrc mkexrc checktime
