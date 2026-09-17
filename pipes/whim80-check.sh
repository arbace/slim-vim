#!/bin/sh
# Whim phase 80, the check -- the Ex command table, cut to the commands that exist.
# See pipes/whim80-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim80-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim80-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim80-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim80-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")
REMOVED=$(sed -n "/^REMOVED='$/,/^'$/p" pipes/whim80-edit.sh | sed '1d;$d')

# Nothing the rows took with them may be named any more.
for g in cmd_namelen cmdidxs1 cmdidxs2 command_count e_command_table_needs_to_be_updated_run_make_cmdidxs \
         if_level ex_ni ex_script_ni get_wincmd_addr_type \
         ADDR_ARGUMENTS ADDR_BUFFERS ADDR_LOADED_BUFFERS ADDR_QUICKFIX ADDR_QUICKFIX_VALID ADDR_TABS ADDR_TABS_RELATIVE; do
    n=$(grep -cE -- "\\b$g\\b" "$f" || true)
    [ "$n" = 0 ] || { echo "  cmdtable     $g still has $n mentions"; exit 1; }
done
for c in $REMOVED; do
    case $c in *[!A-Za-z0-9]*) continue ;; esac
    if grep -qE "\\bCMD_$c\\b" "$f"; then
        echo "  cmdtable     CMD_$c survives"; exit 1
    fi
done
n=$(grep -cE '^    \[CMD_\w+\] = \{\(char_u \*\)"' "$f")
[ "$n" = 111 ] || { echo "  cmdtable     $n rows, expected 111"; exit 1; }
grep -qE '^    \[CMD_\w+\] = .*sizeof\("' "$f" && { echo "  cmdtable     a row still carries its name length"; exit 1; }
echo "  cmdtable     111 rows, no index, nothing names a removed command or address type"

tools/phasecheck.sh "$work" "$f" "$state/symbols"

tools/phasebuild.sh "$work" "$before_lines"

d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT
cp "$state/old" "$state/words" "$d/"

# --- 9: every prefix of every name, through both binaries --------------------------
# Step 1 proved the lookup tables agree.  This proves the editors do: each word
# goes in as `+word`, alone, on a three-line file, and the exit status, what it
# wrote to stderr, the file afterwards and anything left in the directory must be
# the same.  The one word allowed to differ is `if`.  Words the old table resolved
# to :stop or :suspend are left out, as the sweep leaves those commands out.
cp "$work/whim-vim" "$d/new"
python3 - "$d" <<'PY'
import concurrent.futures, os, shutil, subprocess, sys, tempfile
d = sys.argv[1]
home = tempfile.mkdtemp(prefix='cmdtable-home-', dir=d)
env = dict(os.environ, HOME=home, VIM=home + '/novim', VIMRUNTIME=home + '/novim',
           XDG_CONFIG_HOME=home + '/xdg')
for k in ('VIMINIT', 'EXINIT', 'MYVIMRC'):
    env.pop(k, None)
stage = {}
for b in ('old', 'new'):
    os.makedirs('%s/%s.bin' % (d, b))
    shutil.copy2('%s/%s' % (d, b), '%s/%s.bin/vim' % (d, b))
    stage[b] = '%s/%s.bin/vim' % (d, b)

words = []
for line in open(d + '/words'):
    w, old = line.rstrip('\n').split('\t')
    if old not in ('stop', 'suspend'):
        words.append(w)

# Command lines, not words: the address parser lost five switches' worth of arms,
# and these reach every address form on the commands that kept one.
LINES = ['%d', '.d', '$d', '2;3d', '1,2d', '3,1d', 'd 2', '2d 2', "'<,'>d", '*d', '-1d', '+1d',
         '2q', '%q', '$q', '.q', '0q', '1,2q', '%undo', '2undo', '0undo', '%messages', '3messages',
         '%normal Ax', '2,3>', '%<', 'g/a/d', 'v/a/d', '2k a', 'ka', "2mark b", '%s/a/X/g', '%&&',
         '2,3m0', '1t$', '1co$', '2,3j', '%p', '%#', '%l', '=', '1z', '.=', '2,3y', '0put', '$put',
         '2,3w! w.txt', '2,$w >> f.txt', 'r f.txt', '0r f.txt', '2cq', '%cq', '1,2~', '%@a',
         '2*', 'wq!', '2,3x', 'up', 'sav s.txt', 'e!', 'ene', 'vi', 'vie', 'ex', 'f n.txt',
         'set ts=3|%s/a/X/|w', 'ma b|2d|w', 'nmap|%s/a/X/|w', "dl", "dp", "2dl 2", 'Print', '2P',
         '++', '--', '{', '}', '!', '!ls', '#', '&', '1,2&', 'k', 'ke', 'sg', 'si', 'sI', 'sr', 'sc',
         'buffer|%s/a/X/|w', 'if 1|%s/a/X/|w', 'lua|%s/a/X/|w', 'n|%s/a/X/|w', 'h|%s/a/X/|w']
BAR = 'a stub no longer splits its line at the bar'
DIFFER = {'if': 'accepted, now an error', 'if 1|%s/a/X/|w': 'accepted, now an error',
          'buffer|%s/a/X/|w': BAR, 'n|%s/a/X/|w': BAR}
# h| is the control: :help's row never had EX_TRLBAR, so its bar was never a
# separator, and it must come out the same.

def run(b, cmd):
    w = tempfile.mkdtemp(prefix='c-', dir=d)
    try:
        open(w + '/f.txt', 'w').write('a\nba\nca\n')
        r = subprocess.run([stage[b], '-e', '-s', '+' + cmd, '+q!', 'f.txt'], cwd=w, env=env,
                           stdin=subprocess.DEVNULL, capture_output=True, timeout=20,
                           start_new_session=True)
        left = sorted(os.listdir(w))
        body = open(w + '/f.txt', errors='replace').read() if os.path.exists(w + '/f.txt') else None
        return (r.returncode, r.stderr, left, body)
    except subprocess.TimeoutExpired:
        return ('TIMEOUT',)
    finally:
        shutil.rmtree(w, ignore_errors=True)

todo = sorted(set(words) | set(LINES))
with concurrent.futures.ThreadPoolExecutor(max_workers=os.cpu_count() or 1) as ex:
    old = dict(zip(todo, ex.map(lambda c: run('old', c), todo)))
    new = dict(zip(todo, ex.map(lambda c: run('new', c), todo)))
got = sorted(c for c in todo if old[c] != new[c])
if got != sorted(DIFFER):
    print('  cmdtable     old and new binaries differ on %d command lines:' % len(got))
    for c in got[:20]:
        print('                 %-18r old %r' % (c, old[c][:2]))
        print('                 %-18s new %r' % ('', new[c][:2]))
    print('                 expected exactly: %s' % sorted(DIFFER))
    sys.exit(1)
if old['if'][0] != 0 or new['if'][0] != 1:
    sys.exit('  cmdtable     :if was expected to go from exit 0 to 1: %r -> %r' % (old['if'][:1], new['if'][:1]))
for c in ('buffer|%s/a/X/|w', 'n|%s/a/X/|w'):
    if old[c][3] != 'X\nbX\ncX\n' or new[c][3] != 'a\nba\nca\n':
        sys.exit('  cmdtable     %r: expected the old binary to substitute and write, the new not to: %r -> %r'
                 % (c, old[c][3], new[c][3]))
print('  cmdtable     %d words and %d command lines through both binaries: identical but for %s'
      % (len(words), len(LINES), ', '.join('%s (%s)' % kv for kv in sorted(DIFFER.items()))))
PY

# --- the delta, cumulative --------------------------------------------------
# Phase 79's list, and every removed row: the sweep dispatches the names in the
# table, so a row that goes is a row whose result goes.
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
    jumps clearjumps \
    $REMOVED
