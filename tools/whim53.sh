#!/bin/sh
# Whim phase 53 -- no conversion layer, no 'encoding'.  See WHIM-GOAL.md.
#
# Usage: tools/whim53.sh <work-dir>      (run from the repository root)
#
# ++enc and the help-buffer branch were the last ways into readfile()'s and
# buf_write()'s conversion; with them gone everything behind folds.  'encoding'
# goes, the mb_* function pointers become direct calls to the UTF-8
# implementations, and the ++ff, ++enc and ++bad completion left behind goes.
# See tools/noconv.py.
#
# THE DELTA: none the harnesses record.  The probes check ++enc and :set enc are
# refused and that UTF-8 editing and a kept invalid byte are unchanged.
set -eu

work=${1:?usage: whim53.sh <work-dir>}
f="$work/whim-vim.c"

before_lines=$(grep -c '' "$f")
tools/symbols.sh "$f" .cache/symbols/before

python3 tools/noconv.py "$f"
# The row goes before the sweep and without --strict: did_set_encoding() and the
# conversion helpers read p_enc until the sweep takes them.  The post-condition
# below is the check -- and mb_init() no longer reads it, which is what makes the
# drop safe at all.
python3 tools/dropoptions.py "$f" encoding
# 'makeencoding' converted :make output, and :make went long ago; what reads it is
# plumbing.  The row first, then its buffer field once the sweep has run.
python3 tools/dropoptions.py "$f" --local makeencoding

tools/sweep.sh "$f"
python3 tools/droplocal.py "$f" b_p_menc
tools/sweep.sh "$f"

for g in need_conversion get_fio_flags check_for_bom next_fenc set_forced_fenc enc_canonize \
         force_enc p_enc iconv_fd ucs2bytes mb_ptr2len mb_head_off mb_ptr2char latin_ptr2len \
         dbcs_head_off dbcs_ptr2len get_encoding_name get_bad_name get_fileformat_name \
         input_conv output_conv convert_setup string_convert convert_input_safe p_menc b_p_menc did_set_encoding; do
    n=$(grep -cE -- "\\b$g\\b" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  noconv       $g still has $n mentions after the sweep"
        grep -nE -- "\\b$g\\b" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
echo "  noconv       no conversion, no 'encoding', no mb_* pointer, no DBCS path"

tools/phasecheck.sh "$work" "$f" .cache/symbols/before

tools/phasebuild.sh "$work" "$before_lines"

d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT
cp "$work/whim-vim" "$d/vim"
(cd "$d" && HOME="$d" ./vim -e -s '+set ts=3' '+q!' </dev/null >/dev/null 2>&1) || { echo "  noconv       the control :set ts=3 failed"; exit 1; }
if (cd "$d" && HOME="$d" ./vim -e -s '+set enc?' '+q!' </dev/null >/dev/null 2>&1); then
    echo "  noconv       :set enc? was accepted"; exit 1
fi
if (cd "$d" && HOME="$d" ./vim -e -s '+set menc?' '+q!' </dev/null >/dev/null 2>&1); then
    echo "  noconv       :set menc? was accepted"; exit 1
fi
printf 'x\n' > "$d/e.txt"
if (cd "$d" && HOME="$d" ./vim -e -s '+e ++enc=latin1 e.txt' '+q!' </dev/null >/dev/null 2>&1); then
    echo "  noconv       ++enc was accepted"; exit 1
fi
printf '\303\240\303\251\n' > "$d/u.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+1normal! gUU' '+wq' u.txt </dev/null >/dev/null 2>&1) || true
[ "$(od -An -tx1 "$d/u.txt" | tr -d ' \n')" = c380c3890a ] || { echo "  noconv       gUU over a-grave e-acute gave $(od -An -tx1 "$d/u.txt")"; exit 1; }
printf 'ok\n\377 bad\n' > "$d/ill.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+1s/ok/OK/' '+wq' ill.txt </dev/null >/dev/null 2>&1) || true
[ "$(od -An -c "$d/ill.txt" | tr -d ' \n')" = 'OK\n377bad\n' ] || { echo "  noconv       an invalid byte was not kept: $(od -An -c "$d/ill.txt" | tr -s ' ')"; exit 1; }
echo "  noconv       :set enc, :set menc and ++enc refused; UTF-8 edits and a kept invalid byte unchanged"

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
