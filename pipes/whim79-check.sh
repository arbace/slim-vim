#!/bin/sh
# Whim phase 79, the check -- the constant-return predicates.
# See pipes/whim79-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim79-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim79-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim79-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim79-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

# Every constant-return predicate, and the second-order stub, must be gone.
for g in in_vim9script tabline_height pum_visible current_win_nr current_tab_nr \
         check_more only_one_window check_timestamps stl_connected pum_under_menu \
         ins_compl_win_active ins_compl_lnum_in_range ins_compl_active \
         has_cursormoved wc_use_keyname script_get pum_redraw_in_same_position \
         has_textchanged has_insertcharpre get_cellwidth \
         check_can_set_curbuf_forceit check_can_set_curbuf_disabled \
         bt_terminal bt_quickfix bomb_size at_ins_compl_key append_arg_number \
         skip_for_popup may_have_range need_check_timestamps; do
    n=$(grep -cE -- "\\b$g\\b" "$f" || true)
    [ "$n" = 0 ] || { echo "  noconstfn    $g still has $n mentions"; exit 1; }
done

# vim9script IS DELIBERATELY NOT IN THAT LOOP.  Four mentions survive and none is the
# identifier: three former-file banner comments (vim9script.pro twice, vim9script.c)
# and the [CMD_vim9script] row, where it is the command NAME -- a string literal.  A
# bare word count cannot tell an identifier from a comment or a string, and asserting
# zero here fails on a phase that did exactly the right thing.  Phase 78 made this
# mistake twice in one script, both times an assertion contradicting a correct edit.
if grep -E '\bvim9script\b' "$f" | grep -qvE '^(// |    \[CMD_vim9script\] = )'; then
    echo "  noconstfn    the vim9script identifier survives outside the banners and the command row"
    grep -nE '\bvim9script\b' "$f" | grep -vE ':(// |    \[CMD_vim9script\] = )'
    exit 1
fi

# The four that return a VARIABLE must all survive untouched.  This is the assertion
# that would have caught the classifier error described in the header.
for g in get_hislen is_maphash_valid get_search_pat get_text_locked_msg; do
    grep -qE "\\b$g\\b" "$f" || { echo "  noconstfn    $g went -- it returns a variable and must stay"; exit 1; }
done

# did_set_number_relativenumber is a constant AND stays: it is a function pointer in
# two option-table rows, where folding means nothing and deleting breaks the rows.
n=$(grep -cE '^[ \t]*did_set_number_relativenumber, NULL,$' "$f" || true)
[ "$n" = 2 ] || { echo "  noconstfn    the two did_set_number_relativenumber option rows are $n, expected 2"; exit 1; }
grep -qE '\bdid_set_number_relativenumber\(optset_T' "$f" || { echo "  noconstfn    did_set_number_relativenumber lost its definition"; exit 1; }

# The quit path must still have the guards that actually refuse.
for g in getout ex_quit ex_exit check_changed check_changed_any before_quit_autocmds \
         not_exiting do_write curbufIsChanged; do
    grep -qE "\\b$g\\b" "$f" || { echo "  noconstfn    $g went -- :q and :wq still need it"; exit 1; }
done
# and both branches of the exit decision must survive in each of the two commands
for fn in ex_quit ex_exit; do
    n=$(awk "/^$fn\\(exarg_T/,/^\\}\$/" "$f" | grep -cE 'getout\(0\);' || true)
    [ "$n" = 1 ] || { echo "  noconstfn    $fn has $n getout(0) calls, expected 1"; exit 1; }
    n=$(awk "/^$fn\\(exarg_T/,/^\\}\$/" "$f" | grep -cE 'not_exiting\(save_exiting\);' || true)
    [ "$n" = 2 ] || { echo "  noconstfn    $fn has $n not_exiting calls, expected 2"; exit 1; }
done
echo "  noconstfn    28 constants folded, 4 variable-returning stubs intact, quit guards intact"

tools/phasecheck.sh "$work" "$f" "$state/symbols"

tools/phasebuild.sh "$work" "$before_lines"

d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT
cp "$work/whim-vim" "$d/vim"

# --- the quit probes.  All five calibrated against q78 before this phase was written,
# --- because check_more() feeds every condition that decides whether getout(0) runs.
# --- An editor that refuses to quit, or quits without writing, fails here and not in
# --- the compiler.
# EVERY ONE OF THESE CAPTURES THE STATUS AS `rc=0; cmd || rc=$?`, NOT `cmd; rc=$?`.
# Under `set -e` a command whose status is not tested aborts the script, and the
# second probe runs :q on a MODIFIED file, which exits 1 on purpose -- so the plain
# form killed the phase on exactly the behaviour it exists to check, after the build
# and before a single probe had run.  `cmd || rc=$?` is a tested context and is safe.
printf 'a\nb\n' > "$d/q1.txt"
rc=0
(cd "$d" && HOME="$d" ./vim -e -s '+q' q1.txt </dev/null >/dev/null 2>&1) || rc=$?
[ "$rc" = 0 ] || { echo "  noconstfn    :q on an unmodified file exited $rc, expected 0"; exit 1; }
[ "$(tr '\n' '|' < "$d/q1.txt")" = 'a|b|' ] || { echo "  noconstfn    :q changed the file"; exit 1; }

printf 'a\nb\n' > "$d/q2.txt"
rc=0
(cd "$d" && HOME="$d" ./vim -e -s '+normal! A-mod' '+q' q2.txt </dev/null >/dev/null 2>&1) || rc=$?
[ "$rc" = 1 ] || { echo "  noconstfn    :q on a MODIFIED file exited $rc, expected 1 -- it must refuse"; exit 1; }
[ "$(tr '\n' '|' < "$d/q2.txt")" = 'a|b|' ] || { echo "  noconstfn    :q wrote a modified file it should have refused"; exit 1; }

printf 'a\nb\n' > "$d/q3.txt"
rc=0
(cd "$d" && HOME="$d" ./vim -e -s '+normal! A-mod' '+q!' q3.txt </dev/null >/dev/null 2>&1) || rc=$?
[ "$rc" = 0 ] || { echo "  noconstfn    :q! exited $rc, expected 0"; exit 1; }
[ "$(tr '\n' '|' < "$d/q3.txt")" = 'a|b|' ] || { echo "  noconstfn    :q! wrote the file"; exit 1; }

printf 'a\nb\n' > "$d/q4.txt"
rc=0
(cd "$d" && HOME="$d" ./vim -e -s '+1' '+normal! A-wq' '+wq' q4.txt </dev/null >/dev/null 2>&1) || rc=$?
[ "$rc" = 0 ] || { echo "  noconstfn    :wq exited $rc, expected 0"; exit 1; }
[ "$(tr '\n' '|' < "$d/q4.txt")" = 'a-wq|b|' ] || { echo "  noconstfn    :wq did not write: '$(tr '\n' '|' < "$d/q4.txt")'"; exit 1; }

printf 'a\nb\n' > "$d/q5.txt"
rc=0
(cd "$d" && HOME="$d" ./vim -e -s '+1' '+normal! A-x' '+x' q5.txt </dev/null >/dev/null 2>&1) || rc=$?
[ "$rc" = 0 ] || { echo "  noconstfn    :x exited $rc, expected 0"; exit 1; }
[ "$(tr '\n' '|' < "$d/q5.txt")" = 'a-x|b|' ] || { echo "  noconstfn    :x did not write: '$(tr '\n' '|' < "$d/q5.txt")'"; exit 1; }
echo "  noconstfn    :q refuses a modified file, :q! discards, :wq and :x write and exit"

# --- six general probes, all calibrated against q78.  The substitution and :g cases
# --- cover do_one_cmd's range parsing, which steps 2, 3 and 10 all edit.
printf 'a\nb\nc\n' > "$d/t.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+$' '+s/^/LAST /' '+wq' t.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/t.txt")" = 'a|b|LAST c|' ] || { echo "  noconstfn    a range and a substitution broke: '$(tr '\n' '|' < "$d/t.txt")'"; exit 1; }

printf 'k1\ndrop\nk2\n' > "$d/g.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+g/drop/d' '+wq' g.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/g.txt")" = 'k1|k2|' ] || { echo "  noconstfn    :g broke: '$(tr '\n' '|' < "$d/g.txt")'"; exit 1; }

printf 'o1\n' > "$d/sw.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+set shiftwidth=8' '+normal! >>' '+wq' sw.txt </dev/null >/dev/null 2>&1) || true
[ "$(cat "$d/sw.txt")" = '        o1' ] || { echo "  noconstfn    :set and >> broke: '$(cat "$d/sw.txt")'"; exit 1; }

printf 'q1\nq2\n' > "$d/w.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+1' '+normal! A-e' '+wq' w.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/w.txt")" = 'q1-e|q2|' ] || { echo "  noconstfn    writing broke: '$(tr '\n' '|' < "$d/w.txt")'"; exit 1; }

printf 'z1\nz2\n' > "$d/m.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+1' '+normal! ma' '+2' "+normal! 'aA-mk" '+wq' m.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/m.txt")" = 'z1-mk|z2|' ] || { echo "  noconstfn    marks broke: '$(tr '\n' '|' < "$d/m.txt")'"; exit 1; }

printf 'r1\nr2\nr3\n' > "$d/u.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+2' '+normal! dd' '+normal! u' '+wq' u.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/u.txt")" = 'r1|r2|r3|' ] || { echo "  noconstfn    undo broke: '$(tr '\n' '|' < "$d/u.txt")'"; exit 1; }
echo "  noconstfn    ranges, :g, :set, writing, marks and undo all work"

# --- the delta, cumulative --------------------------------------------------
tools/whimdelta.sh "$work/whim-vim" "$f" --term-moved --cases bomb_on,filter,read_cmd,retab,sort_u,sort_n,ff_dos,binary_mode,format_gq,format_comment,open_comment \
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
    setlocal setglobal \
    lmap lnoremap lmapclear \
    jumps clearjumps
