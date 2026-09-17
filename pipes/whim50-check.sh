#!/bin/sh
# Whim phase 50, the check -- only LF text files.
# See pipes/whim50-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim50-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim50-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim50-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim50-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

for g in get_fileformat get_fileformat_force set_fileformat default_fileformat file_ff_differs \
         save_file_ff set_file_options set_options_bin msg_add_fileformat check_ff_value \
         force_ff force_bin p_ffs p_bin b_p_bin b_p_ff b_p_eol b_p_fixeol b_p_eof b_p_tx \
         b_start_ffc b_start_eol b_start_eof b_no_eol_lnum try_mac try_dos write_bin; do
    n=$(grep -cE -- "\\b$g\\b" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  lfonly       $g still has $n mentions after the sweep"
        grep -nE -- "\\b$g\\b" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
echo "  lfonly       no format, no binary mode, no end-of-line option"

tools/phasecheck.sh "$work" "$f" "$state/symbols"

tools/phasebuild.sh "$work" "$before_lines"

d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT
cp "$work/whim-vim" "$d/vim"

# -b must be unknown, and :set ff=dos refused, against a :set ts=3 control.
out=$(cd "$d" && ./vim -b -e -s '+q!' </dev/null 2>&1) && rc=0 || rc=$?
case "$out" in *"Unknown option argument"*) ;; *) echo "  lfonly       -b is not refused as unknown (exit $rc): $out"; exit 1 ;; esac
(cd "$d" && ./vim -e -s '+set ts=3' '+q!' </dev/null >/dev/null 2>&1) || { echo "  lfonly       the control :set ts=3 failed"; exit 1; }
if (cd "$d" && ./vim -e -s '+set ff=dos' '+q!' </dev/null >/dev/null 2>&1); then
    echo "  lfonly       :set ff=dos was accepted"; exit 1
fi

# A CR is a character: :%s/$/X/ on a CR LF file puts X after the CR, where a DOS
# file would have had it before.  And a last line with no LF gets one.
printf 'one\r\ntwo\r\n' > "$d/crlf.txt"
(cd "$d" && ./vim -e -s '+%s/$/X/' '+wq' crlf.txt </dev/null >/dev/null 2>&1) || true
if [ "$(od -An -c "$d/crlf.txt" | tr -d ' \n')" != 'one\rX\ntwo\rX\n' ]; then
    echo "  lfonly       a CR LF file was not edited as LF text: $(od -An -c "$d/crlf.txt" | tr -s ' ')"; exit 1
fi
printf 'one\ntwo' > "$d/noeol.txt"
(cd "$d" && ./vim -e -s '+w' '+q!' noeol.txt </dev/null >/dev/null 2>&1) || true
if [ "$(od -An -c "$d/noeol.txt" | tr -d ' \n')" != 'one\ntwo\n' ]; then
    echo "  lfonly       a last line was written without LF: $(od -An -c "$d/noeol.txt" | tr -s ' ')"; exit 1
fi
echo "  lfonly       -b unknown, ff refused, CR is text, and every line ends with LF"

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
