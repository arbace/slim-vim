#!/bin/sh
# Whim phase 81, the check -- one line, one command.
# See pipes/whim81-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim81-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim81-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim81-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim81-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

for g in comment_start starts_with_colon; do
    n=$(grep -cE -- "\\b$g\\b" "$f" || true)
    [ "$n" = 0 ] || { echo "  onecommand   $g still has $n mentions"; exit 1; }
done

tools/phasecheck.sh "$work" "$f" "$state/symbols"

tools/phasebuild.sh "$work" "$before_lines"

d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT
cp "$state/old" "$d/"

# --- the corpus, through q80's binary and this one ----------------------------------
# Each case is a list of +commands on a three-line file, then `+w! out.txt` and `+q!`.
# Recorded: exit status, stderr, and what was written.  DIFFER is the declared delta,
# each with the reason; every other case must be identical.
cp "$work/whim-vim" "$d/new"
python3 - "$d" <<'PY'
import concurrent.futures, os, shutil, subprocess, sys, tempfile
d = sys.argv[1]
home = tempfile.mkdtemp(prefix='onecommand-home-', dir=d)
env = dict(os.environ, HOME=home, VIM=home + '/novim', VIMRUNTIME=home + '/novim',
           XDG_CONFIG_HOME=home + '/xdg')
for k in ('VIMINIT', 'EXINIT', 'MYVIMRC'):
    env.pop(k, None)
stage = {}
for b in ('old', 'new'):
    os.makedirs('%s/%s.bin' % (d, b))
    shutil.copy2('%s/%s' % (d, b), '%s/%s.bin/vim' % (d, b))
    stage[b] = '%s/%s.bin/vim' % (d, b)

BAR = 'a bar is argument text'
QUOTE = 'a quote is argument text'
ESC = 'a backslash before a bar stays'
DIFFER = {
    ('%s/a/X/|%s/b/Y/',): BAR,
    ('set ts=3|%s/a/X/',): BAR,
    ('1d|1d',): BAR,
    ('2|',): BAR,
    ('|',): BAR,
    ('1a|new',): BAR,
    ('map Q A|b', 'normal Q'): BAR,
    ('nmap Q A|b', 'normal Q'): BAR,
    ('" a comment',): QUOTE,
    ('"',): QUOTE,
    ('set ts=3 " a comment',): QUOTE,
    ('%s/a/X/ " a comment',): QUOTE,
    ('1d " a comment',): QUOTE,
    ('map Q A\\|b', 'normal Q'): ESC,
}
SAME = [
    ('%s/a/X/',), ('%s/a/X/', '%s/b/Y/'), ('%s/a\\|b/Q/g',), ('g/a\\|c/d',), ('g/b/s/a/Z/',),
    ('%s/a/"/',), ('%s/"/q/',), ('normal! A"x',), ('normal! A|x',), ('map Q AX', 'normal Q'),
    ('map Q A"b', 'normal Q'), ('map Q A\x16|b', 'normal Q'), ('set ts=3',), ('2,3d',), ('2d 2',),
    ('%s/a/X/\n%s/b/Y/',), ('1d\n1d',), ('$',), ('2',), ('%p',), ('1a',), ('%j',),
    ('map Q A\\"b', 'normal Q'), ('let x = 1',), ('echo "x"',), ('@"',), ('2*',), ('undo',), ('map Q A b ', 'normal Q'),
]

def run(b, cmds):
    w = tempfile.mkdtemp(prefix='c-', dir=d)
    try:
        open(w + '/f.txt', 'w').write('a\nba\nca\n')
        argv = [stage[b], '-e', '-s'] + ['+' + c for c in cmds] + ['+w! out.txt', '+q!', 'f.txt']
        r = subprocess.run(argv, cwd=w, env=env, stdin=subprocess.DEVNULL, capture_output=True,
                           timeout=20, start_new_session=True)
        out = open(w + '/out.txt', errors='replace').read() if os.path.exists(w + '/out.txt') else None
        return (r.returncode, r.stderr, out)
    except subprocess.TimeoutExpired:
        return ('TIMEOUT',)
    finally:
        shutil.rmtree(w, ignore_errors=True)

todo = sorted(set(DIFFER) | set(SAME))
with concurrent.futures.ThreadPoolExecutor(max_workers=os.cpu_count() or 1) as ex:
    old = dict(zip(todo, ex.map(lambda c: run('old', c), todo)))
    new = dict(zip(todo, ex.map(lambda c: run('new', c), todo)))
got = sorted(c for c in todo if old[c] != new[c])
if got != sorted(DIFFER):
    print('  onecommand   old and new binaries differ on %d cases, expected %d:' % (len(got), len(DIFFER)))
    for c in sorted(set(got) ^ set(DIFFER)):
        print('                 %-36r old %r' % (c, old[c]))
        print('                 %-36s new %r' % ('', new[c]))
    sys.exit(1)
# The mapping cases are only evidence if they show WHAT the rhs became.
# -e -s starts on the last line, so the mapping appends there.
want = {('map Q A|b', 'normal Q'): 'a\nba\nca|b\n', ('map Q A\\|b', 'normal Q'): 'a\nba\nca\\|b\n'}
for c, body in want.items():
    if new[c][2] != body:
        sys.exit('  onecommand   %r wrote %r, expected %r' % (c, new[c][2], body))
if old[('%s/a/X/|%s/b/Y/',)][2] != 'X\nYX\ncX\n' or new[('%s/a/X/|%s/b/Y/',)][2] != 'a\nba\nca\n':
    sys.exit('  onecommand   the bar case did not show a split before and none after: %r -> %r'
             % (old[('%s/a/X/|%s/b/Y/',)][2], new[('%s/a/X/|%s/b/Y/',)][2]))
print('  onecommand   %d cases through both binaries: %d differ exactly as declared, %d identical'
      % (len(todo), len(DIFFER), len(SAME)))
PY
