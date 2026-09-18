#!/bin/sh
# Zero phase 12, the check -- the options nothing reads.
# See pipes/zero12-edit.sh, and ZERO-GOAL.md.
#
# Usage: pipes/zero12-check.sh <work-dir> <state-dir>    (run from the repository root)
#
# Runs after pipes/zero12-edit.sh and the sweep tools/phaserun.sh runs between them,
# and reads nothing from the edit's shell -- only the work tree and the state
# directory.  What the edit left there is `old`, the binary this phase was HANDED,
# and `old.c`, the source it was built from.
#
# EVERY VISIBLE EFFECT OF THIS PHASE IS OUTSIDE THE INSTRUMENT, and that is the one
# thing to understand about this check.  `tools/zexcmds.py` records `exit`, `bells`,
# `stderr`, `text` and `msgs` for the `set` row and NO stream digest, so even a
# change to what `:set` prints in the stream would be invisible there; no recorded
# case or row asks `:set ro?`, `:set fsync?`, `:set write?`, `:set wa?`, `:set
# undoreload?` or `:set prompt?`; bare `:set` does not move, because none of the six
# differs from its default and the listing is wiped by the Press-ENTER redraw before
# zscreen.py takes its picture; and no case sets `'readonly'`, so the W10 warning and
# the two `[RO]` indicators are never drawn.  A phase that did nothing and a phase
# that did everything have the SAME RECORDING.  So the probes are not a supplement
# here, they are the check.
#
# SIX THINGS ARE PROVED, and the fourth is the phase.
#
# 1. THE CUT.  Six rows go, of a computed seven; two functions go BY NAME and with
#    the reason stated (`change_warning` and `did_set_readonly` -- see the edit); and
#    the sweep then takes the six globals, `SHM_RO`, `BV_RO`, `BV_FS`, the static
#    string `w_readonly` and the `b_did_warn` field.
#
#    THE TRAPS, ALL MEASURED:
#      * `'modified'` STAYS and has no reader of `p_mod` either.  Decision 5 keeps
#        it -- the state it reports lives in `b_changed` -- and `dropoptions.py`
#        refuses a PV_BUF row anyway.  A check that wanted every readerless row gone
#        would fail on a correct phase.
#      * `b_did_warn` becomes dead only after BOTH `change_warning` and
#        `did_set_readonly` have gone.  Remove one and it is a field with one reader
#        and one writer, which no tool reports.
#      * `w_readonly` is a `static char *` INSIDE `change_warning()`, not at file
#        scope, so a check that greps for it at file scope finds nothing either way.
#      * `'paste'` IS EXEMPT FOR EVER (ZERO-PLAN.md 2d and decision 8, the user's
#        standing promise): `p_paste` 12 mentions and its five `*_nopaste` save slots
#        at four each, before and after, and `+{command}` untouched.  The next person
#        to widen the computation must meet this assertion, not just the comment.
#
# 2. THE FLAG LETTERS ARE NOT TOUCHED, AND IT IS ASSERTED RATHER THAN DESCRIBED.
#    `'cpoptions'` and `'shortmess'` each have a validity list that is a separate
#    string literal from the value, so removing a letter from a list could not move
#    `:set cpo?` or `:set shm?` -- but it WOULD turn `:set shm=F`, accepted silently,
#    into `E539: Illegal character`, and no corpus case, Ex row, argv row or pty
#    scenario types `:set shm=`.  That is exactly the change ZERO-GOAL.md rule 2
#    exists to prevent, so both literals are compared character for character against
#    the input, and four probes require `:set shm=F` and `:set cpo=g` to be accepted
#    on both binaries and `:set shm=y` and `:set cpo=<a non-letter>` to answer E539 on
#    both -- `h` is in neither list, `'cpoptions'` having only `H`.  Measured here:
#    23 of `'cpoptions'` 60 letters and 14 of `'shortmess'` 23 are inert, and THIS
#    PHASE MAKES EXACTLY ONE MORE SO -- `'shortmess'`'s `r`.
#
# 3. THE ROW FLOOR, WHICH THIS PHASE CROSSES.  `tools/orphanopts.py` refused a table
#    it parsed fewer than 100 distinct `&p_xx` out of, and this phase takes the count
#    102 -> 96.  `tools/zerodelta.sh` runs that tool beside its harnesses, so crossing
#    the floor would not fail this phase -- it would fail the delta check of EVERY
#    zero phase after it.  The floor is 80 now, lowered in this phase's own commit
#    with the reason in the tool's docstring, the same number and the same argument as
#    `tools/create_cmdidxs.py`'s so that the two floors stay one idea.  The check
#    requires the floor to be BELOW the count it will meet -- by using it, not by
#    grepping for the number -- and requires the tool's output on this source to be
#    byte-identical to its output on the input: no option global is orphaned, in
#    either direction.
#
# 4. THE PROBES, ON BOTH BINARIES, WHICH ARE THE WHOLE EVIDENCE.  Thirteen must move
#    and thirteen must not.  `ro_w10` is the one that shows the phase removing
#    BEHAVIOUR rather than a row: `:set ro` on an unmodified buffer, then an insert,
#    and the old binary prints `W10: Warning: Changing a readonly file` and PAUSES A
#    SECOND -- 1,008 ms measured against 3 ms here, the same shape as phase 2's
#    2,010 ms -> 5 ms.  The message is never in a snapshot: it is drawn, a Press-ENTER
#    follows and the redraw wipes it, exactly as zero7-check's E319, so the assertion
#    is on the STREAM and on the elapsed time.  THE BUFFER MUST BE UNMODIFIED WHEN
#    `:set ro` RUNS -- `change_warning()` returned early on `b_did_warn ||
#    curbufIsChanged()` -- so a probe that types its seed first shows nothing on
#    either binary.
#
# 5. AND `:set all` IS IN NO HARNESS.  It is the only thing that lists every option
#    name, so it is the only way to see four rows cease to exist; `readonly`, `fsync`,
#    `prompt` and `undoreload` are in the old stream and absent from this one.
#
# 6. THE LINE AGAINST THE PHASE AFTER THIS ONE, stated as counts: `scriptin` 8,
#    `redir_fd` 6 and `vim_fsync` 3, with `fclose`, `getc`, `putc` and `fsync`
#    asserted STILL undefined.  `fsync` is still reached from `ui_write` and is the
#    FILE* phase's.
#
# A record is built the way tools/zcases.py builds one and scrubbed the same way
# (tools/zrec.py).
set -eu

work=${1:?usage: zero12-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero12-check.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"
before_lines=$(cat "$state/input-lines")

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# --- 1. what went, recorded -----------------------------------------------------------
for gone in b_p_ro b_p_fs b_did_warn change_warning did_set_readonly w_readonly \
            SHM_RO BV_RO BV_FS p_fs p_ro p_ur p_write p_wa p_prompt; do
    n=$(grep -cw -- "$gone" "$f" || true)
    [ "$n" = 0 ] || { echo "  noopts       '$gone' still has $n mentions"; exit 1; }
done
# The three literals that lose their last speaker: W10 was change_warning's, and the
# two indicators were fileinfo()'s and win_redr_status's.
for gone in 'W10: Warning: Changing a readonly file' '[RO]' '[readonly]'; do
    n=$(grep -cF -- "$gone" "$f" || true)
    [ "$n" = 0 ] || { echo "  noopts       the string '$gone' still has $n mentions"; exit 1; }
done
echo "  noopts       six option globals, two buffer-local fields, b_did_warn, change_warning, did_set_readonly, w_readonly, SHM_RO, BV_RO and BV_FS at 0 mentions, with W10 and both [RO] indicators -- the two functions by name and with the reason, the rest the sweep's"

# --- 2. and everything that must NOT be at zero -------------------------------------
python3 - "$f" "$state/old.c" <<'PY'
import re, sys
sys.path.insert(0, 'tools')
import create_cmdidxs
TAG = 'noopts'
new = open(sys.argv[1], errors='surrogateescape').read()
old = open(sys.argv[2], errors='surrogateescape').read()
fail = []


def count(text, name):
    return len(re.findall(r'\b%s\b' % name, text))


def table(text):
    i = text.find('static struct vimoption options[]')
    j = text.index('\n};', i)
    return text[i:j]


# THE ROWS, AS A SET DIFFERENCE RATHER THAN AS A COUNT.
rows_old = set(re.findall(r'^[ \t]*\{"([a-z]+)",', table(old), re.M))
rows_new = set(re.findall(r'^[ \t]*\{"([a-z]+)",', table(new), re.M))
WENT = {'fsync', 'prompt', 'readonly', 'undoreload', 'write', 'writeany'}
if rows_old - rows_new != WENT or rows_new - rows_old:
    fail.append('the option rows that went are %s and %s arrived; exactly %s must go'
                % (' '.join(sorted(rows_old - rows_new)) or 'none',
                   ' '.join(sorted(rows_new - rows_old)) or 'none',
                   ' '.join(sorted(WENT))))
g_old = set(re.findall(r'&(p_[a-z0-9_]+)\b', table(old)))
g_new = set(re.findall(r'&(p_[a-z0-9_]+)\b', table(new)))
if (len(g_old), len(g_new)) != (102, 96):
    fail.append('the distinct option globals went %d -> %d, expected 102 -> 96'
                % (len(g_old), len(g_new)))
# modeline_whitelist[] outlives the options it names unless it is told.
m = re.search(r'modeline_whitelist\[\][^;]*?\{(.*?)\n\};', new, re.S)
if m:
    for name in WENT:
        if '"%s"' % name in m.group(1):
            fail.append('%r is still in modeline_whitelist[], which outlives the '
                        'option it names' % name)

# 'modified' STAYS, and it is the one row with no reader of its own global that must
# not go: ZERO-PLAN.md decision 5, the state it reports living in b_changed.
if 'modified' not in rows_new or count(new, 'p_mod') != 2 or count(new, 'did_set_modified') != 3:
    fail.append("'modified' moved: its row must stay, p_mod at 2 and did_set_modified "
                'at 3 -- decision 5 keeps it, and it is now the only option row with '
                'no reader of its own global')

# 'paste' IS EXEMPT FOR EVER -- ZERO-PLAN.md 2d and decision 8, the user's standing
# promise -- and so is `+{command}`.  This is the assertion, not only the comment.
if 'paste' not in rows_new or count(new, 'p_paste') != 12:
    fail.append("'paste' moved, and it is EXEMPT FOR EVER (ZERO-PLAN.md 2d): "
                'p_paste has %d mentions, expected 12' % count(new, 'p_paste'))
for slot in ('p_ai_nopaste', 'p_et_nopaste', 'p_sts_nopaste', 'p_tw_nopaste',
             'p_wm_nopaste'):
    if count(new, slot) != 4 or count(old, slot) != 4:
        fail.append("%s has %d mentions, expected 4 -- it is one of 'paste''s five "
                    'save slots, which orphanopts.py reports and tolerates and which '
                    'nothing here may "fix"' % (slot, count(new, slot)))

# THE FLAG LETTERS ARE NOT TOUCHED, asserted character for character.  Removing a
# letter from a validity list cannot move `:set cpo?` or `:set shm?` -- the value is
# a different literal -- so nothing in the instrument would see it.
CPO = ('return did_set_option_listflag(*varp, (char_u *) '
       '"aAbBcCdDeEfFgHiIjJkKlLmMnoOpPqrRsStuvwWxXyZz$!%*-+<>#{|&/\\\\.;~" , '
       'args->os_errbuf, args->os_errbuflen);')
SHM = ('return did_set_option_listflag(*varp, (char_u *) "rmfixlnwaWtToOsAIcCqFSu" , '
       'args->os_errbuf, args->os_errbuflen);')
for what, lit in (("'cpoptions'", CPO), ("'shortmess'", SHM)):
    if new.count(lit) != 1 or old.count(lit) != 1:
        fail.append("%s's validity list is not the literal this phase was written "
                    'against (%d in the input, %d here) -- it must be untouched, '
                    'character for character' % (what, old.count(lit), new.count(lit)))

# AND WHICH LETTERS ARE INERT, computed either side.  A letter in a validity list
# with no enumerator of that value is accepted and means nothing, which is what
# upstream does for every feature a build lacks.  This phase makes exactly one more
# so: 'shortmess''s `r`, whose SHM_RO goes with the [RO] indicator.
CPO_LIST = 'aAbBcCdDeEfFgHiIjJkKlLmMnoOpPqrRsStuvwWxXyZz$!%*-+<>#{|&/\\.;~'
SHM_LIST = 'rmfixlnwaWtToOsAIcCqFSu'


def inert(text, prefix, letters):
    have = set(dict(re.findall(r"%s(\w+) = '(.)'" % prefix, text)).values())
    return ''.join(c for c in letters if c not in have)


cpo_i, shm_i = inert(new, 'CPO_', CPO_LIST), inert(new, 'SHM_', SHM_LIST)
cpo_i_old, shm_i_old = inert(old, 'CPO_', CPO_LIST), inert(old, 'SHM_', SHM_LIST)
if cpo_i != cpo_i_old:
    fail.append("the inert 'cpoptions' letters moved, %r -> %r, and this phase "
                'touches no CPO_' % (cpo_i_old, cpo_i))
if set(shm_i) - set(shm_i_old) != {'r'} or set(shm_i_old) - set(shm_i):
    fail.append("the inert 'shortmess' letters went %r -> %r; exactly `r` must be "
                'added, SHM_RO going with the [RO] indicator' % (shm_i_old, shm_i))

# THE LINE AGAINST THE PHASE AFTER THIS ONE.
KEPT = {'scriptin': 8, 'redir_fd': 6, 'vim_fsync': 3,   # the FILE* phase's
        'read_cmd_fd': 12,                              # the terminal's
        'bufIsChanged': 7,                              # phase 11's, untouched
        'curbufIsChanged': 6,   # 7 before: change_warning's early return read it
        'fileinfo': 3, 'win_redr_status': 5}
for name, want in sorted(KEPT.items()):
    k = count(new, name)
    if k != want:
        fail.append('%s has %d mentions, expected %d' % (name, k, want))

# fileinfo() keeps five %s and win_redr_status keeps its other two indicators.
if not re.search(r'"\\"%s%s%s%s%s", curbufIsChanged\(\)', new):
    fail.append("fileinfo's CTRL-G format is not %s%s%s%s%s: the format string and "
                'the argument had to move together, and nothing in the build checks '
                'a vim_snprintf_safelen count')
for keep in ('[Modified]', '[Not edited]', '[Read errors]', '[Help]', '[+]'):
    if keep not in new:
        fail.append('%r went, and this phase removes only the read-only indicators'
                    % keep)

# THE TABLE.  No command row moves: this phase removes no command.
rows = re.findall(r'^    \[CMD_\w+\] = \{.*$', new, re.M)
got = create_cmdidxs.names(sys.argv[1])
if len(rows) != 98 or len(got) != 98:
    fail.append('cmdnames[] has %d rows and names() reads %d; both must be 98 -- '
                'this phase removes no command' % (len(rows), len(got)))
if 'static_assert(sizeof(cmdnames) / sizeof(cmdnames[0]) == CMD_SIZE' not in new:
    fail.append('the static_assert on the row count went')
for name in ('set', 'quit', 'registers'):
    if name not in got:
        fail.append(':%s went, and this phase removes no row' % name)

# What the six rows cost the old file, as a difference rather than a number.
for name, want in (('change_warning', 7), ('did_set_readonly', 3), ('b_p_ro', 10),
                   ('b_p_fs', 7), ('b_did_warn', 4), ('p_paste', 12)):
    if count(old, name) != want:
        fail.append('the input is not the file this phase was written against: '
                    '%s %d, expected %d' % (name, count(old, name), want))

if fail:
    for line in fail:
        print('  %-12s %s' % (TAG, line))
    print("  %-12s the seven rows with no reader are computed; SIX are dropped." % '')
    print("  %-12s 'modified' is the seventh and decision 5 keeps it, and 'paste'" % '')
    print('  %-12s is exempt for ever and is not in the set at all.' % '')
    sys.exit(1)
print('  %-12s rows: 114 -> 108 and 102 -> 96 distinct globals, the set that went '
      'being exactly fsync prompt readonly undoreload write writeany, none arriving '
      'and none left in modeline_whitelist[]' % TAG)
print("  %-12s kept: 'modified' with p_mod 2 and did_set_modified 3 -- decision 5, "
      'and it is now the only row with no reader of its own global -- and '
      "'paste' with p_paste 12 and its five save slots at four each, EXEMPT FOR "
      'EVER (ZERO-PLAN.md 2d)' % '')
print('  %-12s the two validity lists are untouched character for character; 23 of '
      "'cpoptions' 60 letters and 14 of 'shortmess' 23 are inert, and this phase "
      "makes exactly one more so -- 'shortmess''s `r`" % '')
print('  %-12s the later phase\'s line: scriptin 8, redir_fd 6, vim_fsync 3; the '
      'table is 98 rows and untouched' % '')
PY

# --- 3. the row floor, which this phase crosses ---------------------------------------
# tools/orphanopts.py refused a table it parsed fewer than 100 distinct `&p_xx` out
# of; this phase takes the count to 96.  tools/zerodelta.sh runs it beside its
# harnesses, so the floor is checked here BY USING IT -- the tool must not refuse --
# and by requiring its verdict on this source to be byte-identical to its verdict on
# the input.  Grepping for the number would prove nothing about either.
python3 tools/orphanopts.py "$state/old.c" > "$tmp/orph.old" 2>&1 || {
    echo "  noopts       orphanopts refuses the INPUT, so this phase is being checked against a file it was not written for"; cat "$tmp/orph.old"; exit 1; }
python3 tools/orphanopts.py "$f" > "$tmp/orph.new" 2>&1 || {
    echo "  noopts       orphanopts refuses this source -- the row floor is no longer below 96, and that would fail the delta check of every zero phase after this one, not this one:"
    sed 's/^/               /' "$tmp/orph.new"; exit 1; }
if ! cmp -s "$tmp/orph.old" "$tmp/orph.new"; then
    echo "  noopts       orphanopts says something different about this source than about the input:"
    diff "$tmp/orph.old" "$tmp/orph.new" | sed 's/^/               /'
    exit 1
fi
echo "  noopts       the row floor is crossed and moved in this phase's own commit: orphanopts accepts 96 distinct globals and says exactly what it said about the input -- five non-pointer orphans, which are 'paste''s save slots, and every option pointer still has the row that sets it"

# --- 4. the compile, the linkage and the libc surface -------------------------------
# NOTHING IS FREED, AND THE CHECK STATES IT AS AN EQUALITY -- a `cmp` of the whole
# undefined set, so a symbol arriving fails too.  `ui_delay` loses a caller and
# `fsync` is still reached from `ui_write`, which is the FILE* phase's.
cp "$state/symbols/undefined" "$tmp/before.u"
tools/phasecheck.sh "$work" "$f" "$state/symbols"
if ! cmp -s "$tmp/before.u" .cache/symbols/last/undefined; then
    echo "  noopts       the libc surface moved, and this phase frees nothing:"
    echo "               gone: $(comm -23 "$tmp/before.u" .cache/symbols/last/undefined | tr '\n' ' ')"
    echo "               came: $(comm -13 "$tmp/before.u" .cache/symbols/last/undefined | tr '\n' ' ')"
    exit 1
fi
for keep in fclose getc putc fsync read write close dup; do
    grep -qx "$keep" .cache/symbols/last/undefined \
        || { echo "  noopts       $keep went, and it is not this phase's: fclose, getc, putc and fsync are the FILE* phase's"; exit 1; }
done
for absent in open access fcntl stat getcwd strerror chmod fchmod fstat lstat unlink; do
    if grep -qx "$absent" .cache/symbols/last/undefined; then
        echo "  noopts       $absent is undefined again, and nothing here may add one"; exit 1
    fi
done
echo "  noopts       symbols $(cat .cache/symbols/last/before) -> $(cat .cache/symbols/last/after), the same set as a cmp -- an option row is not a libc call, and fsync is still reached from ui_write"

# --- 5. the enumerators, before and after -------------------------------------------
# THREE GO AND NOTHING RENUMBERS, and the reason it needs saying is BV_RO: it is
# UNPINNED, so BV_SI, the next survivor, would follow it down.  tools/deadenums.py
# pins BV_SI in the sweep and tools/enumvals.sh --verify reports it there; this is
# the independent dump either side that says no OTHER survivor moved.
tools/enumvals.sh "$state/old.c" "$tmp/ev.old" &
pid_ev=$!
tools/enumvals.sh "$f" "$tmp/ev.new"
wait $pid_ev
python3 - "$tmp/ev.old" "$tmp/ev.new" <<'PY'
import sys
TAG = 'noopts'
o = dict(l.rsplit('=', 1) for l in open(sys.argv[1]).read().splitlines())
n = dict(l.rsplit('=', 1) for l in open(sys.argv[2]).read().splitlines())
gone, came = sorted(set(o) - set(n)), sorted(set(n) - set(o))
moved = sorted(k for k in set(o) & set(n) if o[k] != n[k])
WANT = ['BV_FS', 'BV_RO', 'SHM_RO']
if gone != WANT or came or moved:
    if gone != WANT:
        print('  %-12s the enumerators that went are %s, expected exactly %s'
              % (TAG, ' '.join(gone), ' '.join(WANT)))
    if came:
        print('  %-12s enumerators arrived: %s' % (TAG, ' '.join(came)))
    if moved:
        print('  %-12s survivors renumbered: %s -- BV_RO is unpinned and BV_SI is '
              'the next survivor, so this is the direction that goes wrong'
              % (TAG, ' '.join(moved)))
    sys.exit(1)
if n.get('BV_SI') != o.get('BV_SI'):
    print('  %-12s BV_SI moved, and it is the survivor after BV_RO' % TAG)
    sys.exit(1)
print('  %-12s enumerators %d -> %d: BV_FS, BV_RO and SHM_RO go, BV_SI keeps its '
      'value where deadenums.py pinned it, and NOT ONE OTHER SURVIVOR MOVED'
      % (TAG, len(o), len(n)))
PY

# --- 6. the binary -------------------------------------------------------------------
make -C "$work" clean >/dev/null 2>&1 || true
if ! make -C "$work" >/dev/null 2>&1; then
    echo "  build        FAILED -- rerun by hand: make -C $work"
    exit 1
fi
bin="$work/zero-vim"
echo "  build        ok, $before_lines -> $(grep -c '' "$f") lines, $(stat -c%s "$bin") bytes"

# --- 7. the probes, on both binaries, which are the whole evidence ---------------------
python3 - "$state/old" "$bin" <<'PY'
import concurrent.futures
import hashlib
import os
import shutil
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, 'tools')
import zrec
import zscreen

TAG = 'noopts'
ESC, CR = b'\x1b', b'\r'
QUIT = ESC + b':q!' + CR
CTRL_G = b'\x07'
old_bin, new_bin = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])


def record(binary, args, keys, timeout=10):
    """tools/zstream.py's session, with the raw stream and the ELAPSED TIME back.

    The elapsed time is why this is not zstream.session(): `change_warning()` ends
    in `ui_delay(1002L, TRUE)`, and a second of wall clock is the clearest evidence
    there is that the warning was really drawn and not merely a string in the binary.
    """
    stage = tempfile.mkdtemp(prefix='zero12-bin-')
    vim = os.path.join(stage, 'vim')
    shutil.copy2(binary, vim)
    os.chmod(vim, 0o755)
    home = tempfile.mkdtemp(prefix='zero12-home-')
    env = dict(os.environ)
    env.update(TERM='xterm', HOME=home, VIM=os.path.join(home, 'novim'),
               VIMRUNTIME=os.path.join(home, 'novim'),
               XDG_CONFIG_HOME=os.path.join(home, 'xdg'))
    for k in ('LINES', 'COLUMNS', 'VIMINIT', 'EXINIT', 'MYVIMRC'):
        env.pop(k, None)
    d = tempfile.mkdtemp(prefix='zero12-run-')
    kf = os.path.join(d, 'keys')
    with open(kf, 'wb') as fh:
        fh.write(b''.join(keys))
    t0 = time.time()
    try:
        with open(kf, 'rb') as stdin:
            r = subprocess.run([vim] + list(args), stdin=stdin,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               env=env, cwd=d, timeout=timeout,
                               start_new_session=True)
        rc, out, err = r.returncode, r.stdout, r.stderr
    except subprocess.TimeoutExpired:
        rc, out, err = 'timeout', b'', b''
    ms = int((time.time() - t0) * 1000)
    shutil.rmtree(stage, ignore_errors=True)
    shutil.rmtree(home, ignore_errors=True)
    shutil.rmtree(d, ignore_errors=True)
    scr = zscreen.Screen(24, 80)
    scr.feed(out)
    text = zrec.section('exit %s' % rc)
    text += zrec.section('bells %d' % scr.bells)
    text += zrec.section('stream %d sha=%s' % (len(out), hashlib.sha256(out).hexdigest()[:16]))
    text += zrec.section('stderr', err.decode('utf-8', 'replace').rstrip('\n'))
    for i, (dump, y, x, bells) in enumerate(scr.snaps):
        text += zrec.section('snap %d cursor=%d,%d bells=%d' % (i, y, x, bells), dump)
    return zrec.scrub(text), out.decode('utf-8', 'replace'), ms


def typed(seed, *keys):
    return (['+set paste'], [b'i' + seed + ESC, b':set nopaste' + CR] + list(keys) + [QUIT])


def plain(*keys):
    """No seed: the buffer is UNMODIFIED, which change_warning() requires."""
    return (['+set paste'], [b':set nopaste' + CR] + list(keys) + [QUIT])


HELLO = b'hello'
GONE = ('ro', 'fsync', 'write', 'wa', 'undoreload', 'prompt')

# name, (args, keys), must-differ
PROBES = [
    # --- the one that shows BEHAVIOUR going, not a row ------------------------------
    ('ro_w10',        (['+set paste'], [b':set ro' + CR, b':set nopaste' + CR, b'ix' + ESC, CTRL_G, QUIT]), True),
    # --- the two indicators, each reached by nothing else ----------------------------
    ('ro_ctrlg',      plain(b':set ro' + CR, CTRL_G),                True),
    ('ro_shm_r',      plain(b':set shm=r' + CR, b':set ro' + CR, CTRL_G), True),
    ('ro_statusline', (['+set paste', '+set laststatus=2'], [b':set nopaste' + CR, b':set ro' + CR, QUIT]), True),
    # --- the only thing that lists every option name ---------------------------------
    ('set_all',       plain(b':set all' + CR),                       True),
    # --- setting it, and asking it ----------------------------------------------------
    ('set_readonly',  plain(b':set readonly' + CR),                  True),
    ('set_ro',        plain(b':set ro' + CR),                        True),
    # --- everything that must not move ------------------------------------------------
    ('paste_roundtrip', (['+set paste'], [b'ione two' + ESC, b':set nopaste' + CR, b':set paste?' + CR, QUIT]), False),
    ('mod_query',     typed(HELLO, b':set modified?' + CR),          False),
    ('shm_query',     plain(b':set shm?' + CR),                      False),
    ('cpo_query',     plain(b':set cpo?' + CR),                      False),
    ('shm_F',         plain(b':set shm=F' + CR, b':set shm?' + CR),  False),
    ('shm_bad',       plain(b':set shm=y' + CR),                     False),
    ('cpo_g',         plain(b':set cpo=g' + CR, b':set cpo?' + CR),  False),
    ('cpo_bad',       plain(b':set cpo=h' + CR),                     False),
    ('nu_query',      plain(b':set nu?' + CR),                       False),
    ('bare_set',      plain(b':set' + CR),                           False),
    ('set_listing',   plain(b':set all&' + CR, b':set ai?' + CR),    False),
    ('ctrl_g',        typed(b'a' + CR + b'b', CTRL_G),               False),
    ('undo_case',     typed(b'alpha', b'x', b'u'),                   False),
    ('editing',       typed(b'alpha' + CR + b'beta', b'0dwA-tail' + ESC, b'u', b'yyp'), False),
] + [('q_' + n, plain(b':set ' + n.encode() + b'?' + CR), True) for n in GONE]


def one(probe):
    name, (args, keys), differ = probe
    return (name, record(old_bin, args, keys), record(new_bin, args, keys), differ)


with concurrent.futures.ThreadPoolExecutor(max_workers=len(PROBES)) as ex:
    results = list(ex.map(one, PROBES))

fail, moved, static = [], [], []
for name, o, n, differ in results:
    same = o[0] == n[0]
    if differ and same:
        fail.append('%s was to move and did not' % name)
    if not differ and not same:
        fail.append('%s moved and was not to' % name)
    (static if same else moved).append(name)

by = {name: (o, n) for name, o, n, _ in results}
W10 = 'W10: Warning: Changing a readonly file'

# THE PROBE.  `:set ro` on an UNMODIFIED buffer, then an insert.  The old binary
# draws W10 and pauses a second; the message is never in a snapshot -- a Press-ENTER
# follows and the redraw wipes it -- so the assertion is on the stream, and the
# second is asserted as phase 2 asserts its 2,010 ms -> 5 ms.
(o, ostream, oms), (n, nstream, nms) = by['ro_w10']
if W10 not in ostream:
    fail.append('ro_w10: the input binary did not warn, so this proves nothing -- '
                'change_warning() returns early on b_did_warn || curbufIsChanged(), '
                'so the buffer must be UNMODIFIED when `:set ro` runs')
if oms < 500:
    fail.append('ro_w10: the input binary took %d ms and the warning ends in '
                'ui_delay(1002L, TRUE); under half a second means it never drew it'
                % oms)
if W10 in nstream:
    fail.append('ro_w10: this binary still warns')
if nms > 400:
    fail.append('ro_w10: this binary took %d ms, so something is still pausing' % nms)

# The two indicators, each reached by nothing else.
(o, ostream, _), (n, nstream, _) = by['ro_ctrlg']
if '[readonly]' not in ostream:
    fail.append("ro_ctrlg: the input binary did not print [readonly] -- note it is "
                "[readonly] and not [RO], because 'shortmess' default has no `r`")
if '[readonly]' in nstream or '[RO]' in nstream:
    fail.append('ro_ctrlg: an indicator survives')
(o, ostream, _), (n, nstream, _) = by['ro_shm_r']
if '[RO]' not in ostream:
    fail.append('ro_shm_r: the input binary did not print [RO] with shm=r, and it is '
                'the only probe that reaches SHM_RO')
if '[RO]' in nstream:
    fail.append('ro_shm_r: [RO] survives')
(o, ostream, _), (n, nstream, _) = by['ro_statusline']
if '[RO]' not in ostream:
    fail.append("ro_statusline: the input binary drew no [RO] on the status line, "
                'and win_redr_status is reached by nothing else here')
if '[RO]' in nstream:
    fail.append('ro_statusline: the status line still draws [RO]')

# `:set all` is in no harness and is the only thing that lists every option name.
(o, ostream, _), (n, nstream, _) = by['set_all']
for name in ('readonly', 'fsync', 'prompt', 'undoreload'):
    if name not in ostream:
        fail.append('set_all: the input binary did not list %r, so this proves '
                    'nothing' % name)
    if name in nstream:
        fail.append('set_all: %r is still listed' % name)
if 'paste' not in nstream or 'modified' not in nstream:
    fail.append("set_all: 'paste' or 'modified' is no longer listed, and both stay")

# Every spelling of the six, asked and set: an answer before, E518 after.
for n_ in GONE:
    (o, ostream, _), (nn, nstream, _) = by['q_' + n_]
    if 'E518' in ostream:
        fail.append(':set %s? already answered E518 before this phase, so it proves '
                    'nothing' % n_)
    if 'E518: Unknown option: %s?' % n_ not in nstream:
        fail.append(':set %s? does not answer E518 now' % n_)
for name, spelling in (('set_readonly', 'readonly'), ('set_ro', 'ro')):
    (o, ostream, _), (nn, nstream, _) = by[name]
    if 'E518' in ostream:
        fail.append(':set %s was already unknown before this phase' % spelling)
    if 'E518: Unknown option: %s' % spelling not in nstream:
        fail.append(':set %s does not answer E518 now, so something can still mark a '
                    'buffer read only' % spelling)

# THE FLAG-LETTER DECISION, ASSERTED.  `:set shm=F` and `:set cpo=g` name letters
# with no enumerator left and are accepted SILENTLY on both binaries; a letter that
# is not in the validity list answers E539 on both.  That pair is what says the
# validity lists were not touched.
for name, want in (('shm_F', 'shortmess=F'), ('cpo_g', 'cpoptions=g')):
    (o, ostream, _), (nn, nstream, _) = by[name]
    for tag, stream in (('the input binary', ostream), ('this one', nstream)):
        if want not in stream or 'E539' in stream:
            fail.append('%s: %s did not accept the inert letter silently and answer '
                        '%r' % (name, tag, want))
for name in ('shm_bad', 'cpo_bad'):
    (o, ostream, _), (nn, nstream, _) = by[name]
    for tag, stream in (('the input binary', ostream), ('this one', nstream)):
        if 'E539' not in stream:
            fail.append('%s: %s did not answer E539, so "the validity list is '
                        'untouched" is two failures agreeing' % (name, tag))

# The rest of the must-not-move half, required to be DOING something.
(o, ostream, _), (nn, nstream, _) = by['paste_roundtrip']
if 'paste' not in nstream:
    fail.append("paste_roundtrip: `:set paste?` answered nothing, and 'paste' is the "
                'exempt option the whole corpus depends on')
(o, ostream, _), (nn, nstream, _) = by['mod_query']
if 'modified' not in nstream:
    fail.append("mod_query: `:set modified?` answered nothing, and 'modified' is the "
                'row decision 5 keeps')
(o, ostream, _), (nn, nstream, _) = by['ctrl_g']
if '[Modified]' not in nstream:
    fail.append('ctrl_g: CTRL-G no longer says [Modified], and this phase removes '
                'only the read-only indicators from that line')
for name, want in (('editing', 'alpha'), ('shm_query', 'shortmess='),
                   ('cpo_query', 'cpoptions='), ('nu_query', 'number')):
    (o, ostream, _), (nn, nstream, _) = by[name]
    if want not in nstream:
        fail.append('%s: the new binary no longer shows %r, so "it did not move" is '
                    'two failures agreeing' % (name, want))

if fail:
    for line in fail:
        print('  %-12s %s' % (TAG, line))
    print('  %-12s EVERY VISIBLE EFFECT OF THIS PHASE IS OUTSIDE THE INSTRUMENT:' % '')
    print('  %-12s no recorded case or row asks any of the six, bare `:set` does' % '')
    print('  %-12s not move, and zexcmds.py keeps no stream digest for the `set`' % '')
    print('  %-12s row.  These probes are not a supplement, they are the check.' % '')
    sys.exit(1)
print('  %-12s probes: %d moved (%s), %d unchanged' % (TAG, len(moved), ' '.join(moved), len(static)))
print('  %-12s ro_w10 is the phase: `:set ro` then an insert draws `W10: Warning: '
      'Changing a readonly file` and pauses %d ms on the binary this phase was '
      'handed, and %d ms here with no warning at all' % ('', by['ro_w10'][0][2], by['ro_w10'][1][2]))
print('  %-12s and the flag letters are asserted rather than described: `:set shm=F` '
      'and `:set cpo=g` are accepted silently on BOTH binaries and `:set shm=y` '
      'answers E539 on both -- the validity lists were not touched' % '')
print('  %-12s what did not move is doing its work: `:set paste?`, `:set modified?`, '
      '`:set shm?`, `:set cpo?`, `:set nu?`, bare `:set`, `:set all&`, CTRL-G with '
      '[Modified], undo and an ordinary editing session' % '')
PY
