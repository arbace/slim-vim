#!/bin/sh
# Whim phase 78, the check -- empty functions, write-only counters, and the window id.
# See pipes/whim78-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim78-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim78-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim78-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim78-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

# The counters, the id chain and the two fields are gone.
for g in autocmd_blocked autocmd_no_enter autocmd_no_leave redrawing_for_callback \
         prevwin last_win_id LOWEST_WIN_ID w_id winid prechar \
         clear_chartabsize_arg may_trigger_modechanged may_trigger_win_scrolled_resized \
         out_flush_check add_b0_fenc set_b0_dir_flag pum_may_redraw ml_setname \
         ml_preserve trigger_undo_ftplugin set_init_lang_env \
         set_init_default_printencoding set_init_3 mch_new_shellsize mch_early_init; do
    n=$(grep -cE -- "\\b$g\\b" "$f" || true)
    [ "$n" = 0 ] || { echo "  nostubs      $g still has $n mentions"; exit 1; }
done
# tr_start must SURVIVE: three positional initialisers supply it as -1, and counting
# identifiers cannot see that.  Asserting it reached zero is what this phase got wrong.
grep -qE '\btr_start\b' "$f" || { echo "  nostubs      tr_start went -- three {STATUS_GET, -1} initialisers supply it"; exit 1; }
n=$(grep -cE 'termrequest_T [a-z0-9_]+_status =  \{STATUS_GET, -1\} ;' "$f" || true)
[ "$n" = 3 ] || { echo "  nostubs      the termrequest_T initialisers changed shape ($n, expected 3)"; exit 1; }
# nv_nop stays: it is the nv_cmds row for KE_NOP and nvidxcheck guards the table.
grep -qE '\bnv_nop\b' "$f" || { echo "  nostubs      nv_nop went -- nv_cmd_idx[] is no longer a permutation"; exit 1; }
# breakcheck_count and vim_ignored stay: both are READ, whatever a write-only scan says.
grep -qE '\+\+breakcheck_count >= BREAKCHECK_SKIP' "$f" || { echo "  nostubs      breakcheck_count lost its reader"; exit 1; }
grep -qE '\bvim_ignored\b' "$f" || { echo "  nostubs      vim_ignored went -- it is the deliberate return-value sink"; exit 1; }
# block/unblock stay, now empty, because deathtrap blocks without unblocking.
for g in block_autocmds unblock_autocmds init_incsearch_state win_enter_ext create_windows \
         redraw_after_callback win_alloc getcmdline_int; do
    grep -qE "\\b$g\\b" "$f" || { echo "  nostubs      $g went -- it still has live callers"; exit 1; }
done
echo "  nostubs      no empty calls, no unread counters, no window id; nv_nop and the sinks intact"

tools/phasecheck.sh "$work" "$f" "$state/symbols"

tools/phasebuild.sh "$work" "$before_lines"

d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT
cp "$work/whim-vim" "$d/vim"

# All six calibrated against q77 first.  The search and cmdheight probes matter most:
# the winid guards live on the incremental-search path, and clear_chartabsize_arg is
# called 19 times from the width measuring that cmdheight and redraw depend on.
printf 'a\nb\nc\n' > "$d/t.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+$' '+s/^/LAST /' '+wq' t.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/t.txt")" = 'a|b|LAST c|' ] || { echo "  nostubs      the file did not load: '$(tr '\n' '|' < "$d/t.txt")'"; exit 1; }

printf 'i1\n' > "$d/i.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+normal! A-ins' '+wq' i.txt </dev/null >/dev/null 2>&1) || true
[ "$(cat "$d/i.txt")" = 'i1-ins' ] || { echo "  nostubs      insert broke: $(cat "$d/i.txt")"; exit 1; }

printf 'one1\ntwo2\n' > "$d/g.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+g/[0-9]$/s/[0-9]$/N/' '+wq' g.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/g.txt")" = 'oneN|twoN|' ] || { echo "  nostubs      :g broke: '$(tr '\n' '|' < "$d/g.txt")'"; exit 1; }

# search -- the path the winid guards sat on
printf 'x\ny\n' > "$d/s.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+/y' '+normal! A-found' '+wq' s.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/s.txt")" = 'x|y-found|' ] || { echo "  nostubs      search broke: '$(tr '\n' '|' < "$d/s.txt")'"; exit 1; }

# cmdheight -- drives the width measuring clear_chartabsize_arg is called from
printf 'c1\nc2\n' > "$d/c.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+set cmdheight=2' '+1' '+normal! A-ch' '+wq' c.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/c.txt")" = 'c1-ch|c2|' ] || { echo "  nostubs      :set cmdheight broke: '$(tr '\n' '|' < "$d/c.txt")'"; exit 1; }

printf 'm1\n' > "$d/m.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+map <buffer> Q A!' '+normal Q' '+wq' m.txt </dev/null >/dev/null 2>&1) || true
[ "$(cat "$d/m.txt")" = 'm1!' ] || { echo "  nostubs      a buffer-local mapping broke: $(cat "$d/m.txt")"; exit 1; }
echo "  nostubs      loads, inserts, :g, search, cmdheight and mappings all work"
