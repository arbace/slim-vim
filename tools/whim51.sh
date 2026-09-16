#!/bin/sh
# Whim phase 51 -- a byte that is not UTF-8 is kept as it is.  See WHIM-GOAL.md.
#
# Usage: tools/whim51.sh <work-dir>      (run from the repository root)
#
# Since Phase 12 an invalid byte was read as '?', the buffer made read-only, and
# a forced :w wrote the '?'.  Now the byte is kept, shown as <ff>, written back
# unchanged, and the buffer stays writable; "[ILLEGAL BYTE in line N]" is still
# reported.  ++bad goes, since keeping is the only behaviour left.  See
# tools/keepbytes.py.
#
# THE DELTA: none the harnesses record -- no case has an invalid byte.  The probe
# below is the check, against what Phase 12 did.
set -eu

work=${1:?usage: whim51.sh <work-dir>}
f="$work/whim-vim.c"

before_lines=$(grep -c '' "$f")
tools/symbols.sh "$f" .cache/symbols/before

python3 tools/keepbytes.py "$f"

tools/sweep.sh "$f"

for g in get_bad_opt bad_char_behavior b_bad_char BAD_REPLACE; do
    n=$(grep -cE -- "\\b$g\\b" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  keepbytes    $g still has $n mentions after the sweep"
        grep -nE -- "\\b$g\\b" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
echo "  keepbytes    nothing replaces, drops or chooses what to do with an invalid byte"

tools/phasecheck.sh "$work" "$f" .cache/symbols/before

tools/phasebuild.sh "$work" "$before_lines"

d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT
cp "$work/whim-vim" "$d/vim"

# The control: a valid UTF-8 edit still works.
printf 'caf\303\251\n' > "$d/u.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+s/\%u00e9/E/' '+wq' u.txt </dev/null >/dev/null 2>&1) || true
[ "$(cat "$d/u.txt")" = cafE ] || { echo "  keepbytes    the control failed: a UTF-8 edit gave '$(cat "$d/u.txt")'"; exit 1; }

# An invalid byte comes back as it went in, and the buffer is not read-only.
printf 'ok\n\377 bad\n' > "$d/ill.txt"
# +1s, not +s: Ex mode starts on the last line, and an :s that does not match
# there is an error that stops the commands after it -- including the :wq.
(cd "$d" && HOME="$d" ./vim -e -s '+1s/ok/OK/' '+wq' ill.txt </dev/null >/dev/null 2>&1) || true
if [ "$(od -An -c "$d/ill.txt" | tr -d ' \n')" != 'OK\n377bad\n' ]; then
    echo "  keepbytes    an invalid byte was not written back unchanged: $(od -An -c "$d/ill.txt" | tr -s ' ')"; exit 1
fi
ro=$(cd "$d" && HOME="$d" ./vim -e -s '+set ro?' '+q!' ill.txt </dev/null 2>&1 | tr -d ' \n')
[ "$ro" = noreadonly ] || { echo "  keepbytes    reading an invalid byte made the buffer '$ro'"; exit 1; }
if (cd "$d" && HOME="$d" ./vim -e -s '+e ++bad=keep ill.txt' '+q!' </dev/null >/dev/null 2>&1); then
    echo "  keepbytes    ++bad=keep was accepted"; exit 1
fi
echo "  keepbytes    an invalid byte is written back unchanged, the buffer stays writable, ++bad is refused"

# --- the delta, cumulative --------------------------------------------------
tools/whimdelta.sh "$work/whim-vim" "$f" --term-moved --cases bomb_on,filter,read_cmd,retab,sort_u,sort_n,ff_dos,binary_mode \
    helpclose intro version cd chdir lcd lchdir tcd tchdir pwd '!' language \
    tags preserve swapname mkvimrc mkexrc checktime command comclear colorscheme \
    abbreviate noreabbrev abclear iabbrev inoreabbrev iabclear cabbrev cnoreabbrev cabclear \
    sleep smile vim9script autocmd augroup doautocmd doautoall noautocmd sandbox filetype \
    tab tabedit tabfirst tabmove tablast tabnext tabnew tabonly tabprevious tabNext tabrewind tabs redrawtabline \
    browse confirm mode open tmap tmapclear tnoremap \
    all args argadd argdelete argdedupe argglobal arglocal argument first last rewind \
    sargument sall sfirst slast srewind \
    aboveleft ball belowright botright horizontal leftabove new only resize rightbelow \
    sbuffer sbNext sball sbfirst sblast sbnext sbprevious sbrewind split sunhide sview \
    syncbind topleft unhide vertical vnew vsplit \
    buffer bNext bdelete bfirst blast brewind buffers bwipeout files ls \
    bnext bprevious keepalt \
    center left retab right sort uniq \
    qall quitall wall wqall xall \
    startinsert startreplace startgreplace stopinsert \
    noswapfile \
    setlocal setglobal
