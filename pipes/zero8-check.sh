#!/bin/sh
# Zero phase 8, the check -- nothing can point the editor at another file any more.
# See pipes/zero8-edit.sh, and ZERO-GOAL.md.
#
# Usage: pipes/zero8-check.sh <work-dir> <state-dir>     (run from the repository root)
#
# Runs after pipes/zero8-edit.sh and the sweep tools/phaserun.sh runs between them,
# and reads nothing from the edit's shell -- only the work tree and the state
# directory.  What the edit left there is `old`, the binary this phase was HANDED,
# and `old.c`, the source it was built from, which is the left-hand side of every
# before-and-after count below.
#
# SIX THINGS ARE PROVED HERE, and the fourth is the only one that can say what this
# phase is actually for.
#
# 1. THE CUT, which is the sweep's work and not the edit's.  Seventeen functions go,
#    none of them named by the edit -- do_ecmd (328 lines), get_visual_text,
#    check_lnums_both, do_exedit, nv_gotofile, grab_file_name, prepare_help_buffer,
#    u_unch_branch, text_or_buf_locked, reset_VIsual, reset_VIsual_and_resel,
#    delbuf_msg, ex_edit, u_unchanged, otherfile, check_lnums and getargopt -- with
#    two struct fields (exarg_T.read_edit and one more the sweep found), the five
#    CMD_ enumerators, EX_ARGOPT and seven string literals.  Listing them here is a
#    RECORDING of what the sweep did, which is the only place a list of removed
#    names belongs.
#
#    THE TRAPS, ALL MEASURED, that make a copied "every name at zero mentions" loop
#    the wrong check:
#      * `check_lnums` and `check_lnums_both`, `reset_VIsual` and
#        `reset_VIsual_and_resel`, `u_unchanged` and `u_unch_branch`, `do_ecmd` and
#        `do_ecmd_cmd`, `otherfile` and `otherfile_buf` are five pairs where one
#        name is a prefix of another and only one of each pair goes.  Every count
#        here is `\b`-anchored for that reason.
#      * `"edit"` REACHES ZERO AND `"ex"` DOES NOT.  `getargopt()`'s `++edit`
#        strncmp was the last speaker of `"edit"` once the row went, and anchor 6
#        takes it; `"ex"` survives as one word of `'belloff'`'s value list.  A
#        "no mention of edit anywhere" check fails on a correct phase, and a
#        "both survive" check fails on this one.
#      * `E447: Can't find file "%s" in path` SURVIVES.  nv_gotofile() was not its
#        only speaker, so the message the `gf` probe looks for on the OLD binary is
#        still in the source afterwards -- it is the KEY that went, not the string.
#      * `readonlymode`, `do_ecmd_cmd` and `do_ecmd_lnum` are left WRITE-ONLY rather
#        than removed, and are asserted at their counts.  `readonlymode` is FALSE
#        for ever, `do_ecmd_lnum` is written through eval_vars() which is the
#        buffer-name phase's, and a struct member that is only written draws no
#        warning from anything.
#
# 2. THE LINE AGAINST THE PHASE THAT STOPS READING A BYTE (ZERO-PLAN.md P8), stated
#    as counts so that taking any of it here would fail rather than widen quietly:
#    `readfile` keeps EXACTLY 5 mentions -- its prototype, its definition and the
#    three calls in read_buffer() and open_buffer() -- and `read_buffer` 17.
#    `open_buffer` goes 6 -> 5, and that is the one number ZERO-PLAN.md 3c got
#    backwards: do_ecmd was a caller of `open_buffer`, NOT of `readfile`, so what
#    this phase costs the read path is one call site and nothing else.  The `uses`
#    line the plan wrote for P8 is corrected there.
#
# 3. `'undoreload'` IS NOT THIS PHASE'S.  `p_ur`'s only reader was inside do_ecmd,
#    so after this phase it is a global with an option row and nothing that reads
#    it -- which is the options phase's to remove, not this one's: removing a row
#    changes what `:set` answers and nothing here sweeps `:set`, so the delta could
#    not be checked, and tools/orphanopts.py refuses the opposite direction.  It is
#    asserted at exactly 2 mentions WITH its row, and the manifest carries
#    `uses options:11 files:8 mechanical` for the phase that takes it.
#
# 4. THE PROBES, on BOTH binaries, because THE CORPUS CANNOT SEE A FILE BEING
#    OPENED.  The two cases it does see are `cmd_edit`, which types `:edit` with no
#    file name and has only ever recorded `E37: No write since last change`, and
#    `key_gf`, which presses `gf` on a word naming nothing and recorded E447.  A
#    declared delta of "those two moved" is therefore consistent with a phase that
#    changed two error messages and left do_ecmd() reachable.  So the probes run the
#    binary this phase was handed beside the one it made, and the ones that matter
#    require the OLD binary to pull a file off the disk and the new one to refuse.
#
#    THE FILE IS `keys` ITSELF.  tools/zstream.py writes a session's keystrokes into
#    a file called `keys` in the run directory and feeds it on stdin, so there is
#    always one file there to open and no runner has to plant one: `:e! keys` loads
#    it, and WHAT PROVES THE BYTES ARRIVED IS THE ESCAPE IN THEM -- the keystroke
#    file holds `...\x1b:q!\r`, which tools/zscreen.py draws as `^[:q!^M`, and an
#    Escape can only be in the buffer if the file was opened.
#
#    AND THE FOUR COMMANDS ARE PROVED TO HAVE BEEN `:edit` IN DISGUISE: `:ex! keys`
#    and `:visual! keys` load the file exactly as `:e! keys` does, `:view! keys`
#    loads it AND makes `:set ro?` answer `readonly`, and `:enew!` empties the
#    buffer.  That is do_exedit's thirty lines, measured from the outside.
#
# 5. THE KEYS, AND THE HAZARD THIS PHASE DOES NOT HAVE.  No `nv_cmds[]` row is
#    touched: `gf`, `gF`, `[f` and `]f` are arms inside two handlers whose `g`, `[`
#    and `]` rows dispatch dozens of other keys.  CLAUDE.md's twelve-phase arrow-key
#    bug was a deleted row under a precomputed index, and the general guard is
#    tools/nvidxcheck.py, which tools/phasecheck.sh runs.  The specific one is here:
#    FIFTY `g*`, `[` and `]` keys are pressed on both binaries and exactly four must
#    move, which is what proves the two large handlers survived the two cuts inside
#    them.
#
# 6. A REAL TERMINAL.  Every probe above went through a pipe.  The session types
#    `:e <file>` on a pty, where the file is one the RUNNER wrote -- the editor has
#    had no way to write one since phase 6 -- and the old binary puts its line in
#    the buffer while this one answers E492.  An ordinary editing session beside it
#    is required to be identical.
#
# A record is built the way tools/zcases.py builds one and scrubbed the same way
# (tools/zrec.py).  tools/zstream.py's session() is not called directly because this
# check needs the raw stream beside the screens.
set -eu

work=${1:?usage: zero8-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero8-check.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"
before_lines=$(cat "$state/input-lines")

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# --- 1. what the sweep took, recorded -----------------------------------------------
for gone in do_ecmd get_visual_text check_lnums_both do_exedit nv_gotofile \
            grab_file_name prepare_help_buffer u_unch_branch text_or_buf_locked \
            reset_VIsual reset_VIsual_and_resel delbuf_msg ex_edit u_unchanged \
            otherfile check_lnums getargopt \
            CMD_edit CMD_enew CMD_ex CMD_view CMD_visual EX_ARGOPT read_edit; do
    n=$(grep -cw -- "$gone" "$f" || true)
    [ "$n" = 0 ] || { echo "  noedit       '$gone' still has $n mentions"; exit 1; }
done
# The literals that lose their last speaker.  The four command names went with their
# rows; E143 and E1546 were do_ecmd's, and the help buffer's 'iskeyword' was
# prepare_help_buffer's.  `"ex"` and E447 are asserted the OTHER way below.
for gone in '"edit"' '"enew"' '"view"' '"visual"' \
            'E143: Autocommands unexpectedly deleted new buffer' \
            'E1546: Cannot switch to a closing buffer' \
            '!-~,^*,^|,^\",192-255'; do
    n=$(grep -cF -- "$gone" "$f" || true)
    [ "$n" = 0 ] || { echo "  noedit       the string '$gone' still has $n mentions"; exit 1; }
done
echo "  noedit       seventeen functions, five enumerators, EX_ARGOPT, the read_edit field and seven string literals at 0 mentions -- all of it the sweep's, the edit named none of them"

# --- 2. and everything that must NOT be at zero -------------------------------------
python3 - "$f" "$state/old.c" <<'PY'
import re, sys
sys.path.insert(0, 'tools')
import create_cmdidxs
import cutil
TAG = 'noedit'
new = open(sys.argv[1], errors='surrogateescape').read()
old = open(sys.argv[2], errors='surrogateescape').read()
fail = []


def count(text, name):
    return len(re.findall(r'\b%s\b' % name, text))


# THE BARE WORDS, each with the reason it is not this phase's.  A loop that wanted
# zero for any of these would fail on a correct phase.
KEPT = {'readfile': 5,        # prototype, definition, three calls -- P8's
        'read_buffer': 17,    # P8's, untouched
        'open_buffer': 5,     # definition and four calls: do_ecmd's was the fifth
        'otherfile_buf': 3,   # `otherfile` went; this one is the name phase's
        'do_ecmd_cmd': 6,     # the field and five uses on four lines, none a write
        'do_ecmd_lnum': 2,    # the field and eval_vars()'s write -- the name phase's
        'readonlymode': 5,    # the global, three readers and one write, and it FALSE
        'p_ur': 2,            # the global and its option row: no reader -- P11's
        'getargcmd': 3,       # EX_CMDARG is on no row, so it cannot run; P9 folds it
        'EX_CMDARG': 2,       # the enumerator and do_one_cmd's test, on no row
        'check_changed': 4,   # E37 still refuses, and that is the :q phase's
        'nv_error': 46,       # the 'Q' row phase 4 pointed here
        'check_fname': 3,     # E32's speaker
        'b_ffname': 43, 'b_fname': 37}   # the buffer's name is P9's
for name, want in sorted(KEPT.items()):
    k = count(new, name)
    if k != want:
        fail.append('%s has %d mentions, expected %d -- %s'
                    % (name, k, want, 'this phase reached too far'
                       if k < want else 'something survived that should not have'))

# E447 STAYS AND `"ex"` STAYS, and both are the opposite direction from section 1.
# E447 is what the `gf` probes look for on the old binary; if it had gone with
# nv_gotofile() the probe would still pass and the assertion would be a coincidence.
if new.count('E447: Can\'t find file ') != 1:
    fail.append("E447 went, and nv_gotofile() was not its only speaker -- the KEY "
                "goes here, not the message")
if new.count('"ex"') != 1:
    fail.append('"ex" is not the one word of \'belloff\'s value list that it should '
                'be now that the row has gone')
if 'E37: No write since last change' not in new:
    fail.append('E37 went, and check_changed() is the :q phase\'s')
if new.count('E32: No file name') != 1:
    fail.append('E32: No file name went, and it is reachable through check_fname()')

# What this phase deliberately leaves to the phases after it.
for kept in ('setfname', 'fix_fname', 'expand_filename', 'eval_vars', 'do_one_cmd',
             'nv_g_cmd', 'nv_brackets', 'getexline', 'exe_commands'):
    if not count(new, kept):
        fail.append('%s went, and it is a later phase\'s or this phase only cut '
                    'inside it' % kept)
# The 'Q' row phase 4 pointed at nv_error, not deleted: a hole in nv_cmds[] moves
# every key past it onto another key's row (CLAUDE.md).  nvidxcheck.py, which
# tools/phasecheck.sh runs below, is the general form; this is the one row a zero
# phase has already touched, and this phase touches no row at all.
if not re.search(r"^ *\{'Q', nv_error,", new, re.M):
    fail.append("the 'Q' row is no longer nv_error's, and phase 4 put it there")
for key in ("'g'", r"'\['", r"'\]'"):
    if not re.search(r"^ *\{%s, nv_" % key, new, re.M):
        fail.append('the %s row of nv_cmds[] went, and this phase only cut arms '
                    'inside the two handlers it names' % key)

# 'undoreload' keeps its row: removing one is the options phase's, and
# tools/orphanopts.py refuses the opposite direction.
if '(char_u *)&p_ur, PV_NONE' not in new:
    fail.append("'undoreload' lost its option row, and that is the options phase's: "
                "a row removed here would change what :set answers, which nothing "
                'this pipeline records sweeps')

# The table.
rows = re.findall(r'^    \[CMD_\w+\] = \{.*$', new, re.M)
got = create_cmdidxs.names(sys.argv[1])
if len(rows) != 99 or len(got) != 99:
    fail.append('cmdnames[] has %d rows and names() reads %d; both must be 99'
                % (len(rows), len(got)))
for name in ('edit', 'enew', 'ex', 'view', 'visual'):
    if name in got:
        fail.append(':%s is still a command name' % name)
for name in ('earlier', 'file', 'vglobal', 'vmap', 'quit', 'print', 'append'):
    if name not in got:
        fail.append(':%s went, and it is not this phase\'s' % name)
if 'static_assert(sizeof(cmdnames) / sizeof(cmdnames[0]) == CMD_SIZE' not in new:
    fail.append('the static_assert on the row count went, and it is what catches '
                'an enumerator removed without its row')

# ANCHOR 3, FROM THE OTHER SIDE.  The one anchor outside the table and the keys: an
# edit shaped like the table forgets it, and `:file` is what must still be exempt.
m = re.search(r'^.*EX_LOCK_OK.*curbuf_locked\(\).*$', new, re.M)
if not m:
    fail.append("do_one_cmd's curbuf_locked() test went, and this phase only "
                'removed one conjunct of it')
elif 'CMD_edit' in m.group(0) or 'CMD_file' not in m.group(0):
    fail.append('the curbuf_locked() exemption is %r -- CMD_edit was to go and '
                "CMD_file to stay, `:file` being the buffer-name phase's"
                % m.group(0).strip())

# What the seventeen functions cost the old file, as a difference rather than a
# number: the input must be the file this phase was written against.
if count(old, 'do_ecmd') != 4 or count(old, 'ex_edit') != 6 or count(old, 'EX_ARGOPT') != 6:
    fail.append('the input is not the file this phase was written against: '
                'do_ecmd %d (4), ex_edit %d (6), EX_ARGOPT %d (6)'
                % (count(old, 'do_ecmd'), count(old, 'ex_edit'), count(old, 'EX_ARGOPT')))

if fail:
    for line in fail:
        print('  %-12s %s' % (TAG, line))
    print('  %-12s a "no mention anywhere" check fails on a correct phase here:' % '')
    print('  %-12s check_lnums_both, reset_VIsual_and_resel, u_unch_branch,' % '')
    print('  %-12s do_ecmd_cmd and otherfile_buf each contain a name that goes,' % '')
    print('  %-12s E447 keeps another speaker, and "ex" is a belloff value.' % '')
    sys.exit(1)
print('  %-12s kept: readfile 5, read_buffer 17, open_buffer 5 (do_ecmd was the '
      'fifth caller, NOT a caller of readfile -- ZERO-PLAN.md 3c is corrected), '
      'E447 and E32 with their other speakers' % TAG)
print('  %-12s left write-only and named rather than removed: do_ecmd_cmd 6, '
      "do_ecmd_lnum 2, readonlymode 5 (and FALSE for ever), p_ur 2 with its row -- "
      "'undoreload' is the options phase's" % '')
print('  %-12s table: 99 rows, names() reads 99, static_assert in place, and the '
      "floor is 80: 19 rows of margin (ZERO-PLAN.md decision 8)" % '')
PY

# --- 3. the compile, the linkage and the libc surface -------------------------------
# NOTHING IS FREED, AND THAT IS STATED AS AN EQUALITY.  `:edit` reached do_ecmd(),
# which reached open_buffer() and readfile() -- both of which the startup path still
# uses -- so this phase removes five commands and four keys and not the read path,
# and the undefined set must come out EXACTLY as it went in.  A symbol going would
# mean the cut reached into ZERO-PLAN.md P8's phase; a symbol arriving would mean
# the sweep left something that now links.
cp "$state/symbols/undefined" "$tmp/before.u"
tools/phasecheck.sh "$work" "$f" "$state/symbols"
if ! cmp -s "$tmp/before.u" .cache/symbols/last/undefined; then
    echo "  noedit       the libc surface moved, and this phase frees nothing:"
    echo "               gone: $(comm -23 "$tmp/before.u" .cache/symbols/last/undefined | tr '\n' ' ')"
    echo "               came: $(comm -13 "$tmp/before.u" .cache/symbols/last/undefined | tr '\n' ' ')"
    echo "               open, access and read are the byte-reader phase's (ZERO-PLAN.md P8)"
    exit 1
fi
for keep in open read close stat; do
    grep -qx "$keep" .cache/symbols/last/undefined \
        || { echo "  noedit       $keep is gone, and it is the byte-reader phase's"; exit 1; }
done
echo "  noedit       symbols $(cat .cache/symbols/last/before) -> $(cat .cache/symbols/last/after), the same set: this phase removes five commands and four keys, not the read path"

# --- 4. the enumerators, before and after -------------------------------------------
# Eighty-seven survivors renumber here, which is a lot, and every one must be a
# CMD_*: cmdnames[] is designated, so a row lands at its own enumerator whatever the
# numbering is, but nothing in the build would notice if some OTHER family had moved
# with them.  Phase 5 set the precedent.  4 s a dump, taken concurrently.
tools/enumvals.sh "$state/old.c" "$tmp/ev.old" &
pid_ev=$!
tools/enumvals.sh "$f" "$tmp/ev.new"
wait $pid_ev
python3 - "$tmp/ev.old" "$tmp/ev.new" <<'PY'
import sys
TAG = 'noedit'
o = dict(l.rsplit('=', 1) for l in open(sys.argv[1]).read().splitlines())
n = dict(l.rsplit('=', 1) for l in open(sys.argv[2]).read().splitlines())
gone, came = sorted(set(o) - set(n)), sorted(set(n) - set(o))
moved = sorted(k for k in set(o) & set(n) if o[k] != n[k])
stray = [k for k in moved if not k.startswith('CMD_')]
bad = [k for k in gone if not (k.startswith('CMD_') or k in (
    'CPO_GOTO1', 'DOCMD_RANGEOK', 'ECMD_FORCEIT', 'ECMD_HIDE', 'ECMD_NOWINENTER',
    'ECMD_OLDBUF', 'ECMD_SET_HELP', 'EX_ARGOPT', 'FNAME_REL', 'FNAME_UNESC',
    'READ_NOWINENTER'))]
if came or stray or bad:
    if came:
        print('  %-12s enumerators arrived: %s' % (TAG, ' '.join(came)))
    if stray:
        print('  %-12s enumerators outside CMD_ moved value: %s' % (TAG, ' '.join(stray)))
    if bad:
        print('  %-12s enumerators went that this phase does not account for: %s'
              % (TAG, ' '.join(bad)))
    sys.exit(1)
print('  %-12s enumerators %d -> %d: %d gone (the five CMD_, EX_ARGOPT, and ten '
      'single-constant enums the sweep took with their types), %d renumbered and '
      'every one a CMD_, none arriving'
      % (TAG, len(o), len(n), len(gone), len(moved)))
PY

# --- 5. the binary -------------------------------------------------------------------
# NOT tools/phasebuild.sh: it links the object the sweep compiled with this machine's
# default flags, which since zero phase 1 are not zero's (pipes/zero2-check.sh has
# the whole argument).  A full compile is the honest one.
make -C "$work" clean >/dev/null 2>&1 || true
if ! make -C "$work" >/dev/null 2>&1; then
    echo "  build        FAILED -- rerun by hand: make -C $work"
    exit 1
fi
bin="$work/zero-vim"
echo "  build        ok, $before_lines -> $(grep -c '' "$f") lines, $(stat -c%s "$bin") bytes"

# --- 6. the probes, on both binaries -------------------------------------------------
python3 - "$state/old" "$bin" <<'PY'
import concurrent.futures
import hashlib
import os
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, 'tools')
import zrec
import zscreen
import zstream

TAG = 'noedit'
ESC, CR = b'\x1b', b'\r'
QUIT = ESC + b':q!' + CR
old_bin, new_bin = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])


def record(binary, args, keys, timeout=10):
    """tools/zstream.py's session, with the raw stream handed back beside the screens.

    Everything else is that tool's, and for its reasons: the binary is staged as
    `vim` because argv[0] decides what the editor is, the environment is emptied so
    that no vimrc is found, and the session is its own so that a stop signal cannot
    reach this shell.  THE KEYSTROKE FILE IS THE FILE THE PROBES OPEN: it is written
    as `keys` in the run directory, so `:e! keys` needs nothing planted.
    """
    vim = zstream.stage(binary)     # argv[0], and the copy race: tools/zstream.py
    home = tempfile.mkdtemp(prefix='zero8-home-')
    env = dict(os.environ)
    env.update(TERM='xterm', HOME=home, VIM=os.path.join(home, 'novim'),
               VIMRUNTIME=os.path.join(home, 'novim'),
               XDG_CONFIG_HOME=os.path.join(home, 'xdg'))
    for k in ('LINES', 'COLUMNS', 'VIMINIT', 'EXINIT', 'MYVIMRC'):
        env.pop(k, None)
    d = tempfile.mkdtemp(prefix='zero8-run-')
    kf = os.path.join(d, 'keys')
    with open(kf, 'wb') as fh:
        fh.write(b''.join(keys))
    try:
        with open(kf, 'rb') as stdin:
            r = subprocess.run([vim] + list(args), stdin=stdin,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               env=env, cwd=d, timeout=timeout,
                               start_new_session=True)
        rc, out, err = r.returncode, r.stdout, r.stderr
    except subprocess.TimeoutExpired:
        rc, out, err = 'timeout', b'', b''
    finally:
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
    return zrec.scrub(text), out.decode('utf-8', 'replace'), len(scr.snaps)


def typed(seed, *keys):
    """tools/zcases.py's shape: type the seed under 'paste', then the real keys."""
    return (['+set paste'], [b'i' + seed + ESC, b':set nopaste' + CR] + list(keys) + [QUIT])


HELLO = b'hello'
WORD = b'nosuchfile'
SPELLINGS = ('e', 'ed', 'edit', 'enew', 'ex', 'vi', 'vis', 'vie', 'view', 'visual')

# name, (args, keys), must-differ
PROBES = [
    # --- opening a file, which is the whole phase and which no recorded case sees ---
    ('edit_keys',   typed(HELLO, b':e! keys' + CR),                     True),
    ('ex_keys',     typed(HELLO, b':ex! keys' + CR),                    True),
    ('visual_keys', typed(HELLO, b':visual! keys' + CR),                True),
    ('view_keys',   typed(HELLO, b':view! keys' + CR, b':set ro?' + CR), True),
    ('enew_bang',   typed(HELLO, b':enew!' + CR),                       True),
    # --- the four keys, which are arms inside two surviving handlers ---
    ('key_gf',      typed(WORD, b'0gf'),                                True),
    ('key_gF',      typed(WORD, b'0gF'),                                True),
    ('key_br_f',    typed(WORD, b'0[f'),                                True),
    ('key_brc_f',   typed(WORD, b'0]f'),                                True),
    # --- the two corpus cases this phase declares, run directly ---
    ('cmd_edit',    typed(b'x', b':edit' + CR),                         True),
    # --- and everything that must not move ---
    ('spell_en',    typed(HELLO, b':en' + CR),                          False),
    ('cmd_earlier', typed(HELLO, b'x', b':earlier' + CR),               False),
    ('verbose_ro',  typed(HELLO, b':verbose set ro?' + CR),             False),
    ('cmd_vglobal', typed(b'a1' + CR + b'b2' + CR + b'a3', b':v/a/d' + CR), False),
    ('cmd_vmap',    typed(HELLO, b':vmap' + CR),                        False),
    ('cmd_file',    typed(HELLO, b':file' + CR),                        False),
    ('cmd_read',    typed(HELLO, b':read keys' + CR),                   False),
    ('cmd_print',   typed(HELLO, b':print' + CR),                       False),
    ('cmd_append',  typed(HELLO, b':append' + CR, b'added' + CR, b'.' + CR), False),
    ('cmd_registers', typed(HELLO, b':registers' + CR),                 False),
    ('ctrl_g',      typed(b'a' + CR + b'b', b'\x07'),                   False),
    ('quit_modified', typed(HELLO, b':q' + CR),                         False),
    ('quit_bang',   (['+set paste'], [b'i' + HELLO + ESC, b':set nopaste' + CR, b':q!' + CR]), False),
    ('editing',     typed(b'alpha' + CR + b'beta', b'0dwA-tail' + ESC, b'u', b'yyp'), False),
] + [('spell_' + s, typed(HELLO, b':' + s.encode() + CR), True) for s in SPELLINGS]


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
E492 = 'E492: Not an editor command'

# THE FOUR THAT PULLED A FILE OFF THE DISK.  Each is required to have opened one on
# the OLD binary: a probe that only looks at the new binary passes on a phase that
# did nothing.  WHAT PROVES THE BYTES ARRIVED is the ESCAPE in them: the keystroke
# file holds `...\x1b:q!\r`, which tools/zscreen.py draws as `^[:q!^M`, and nothing
# typed at `:` can put an Escape in the buffer.
READ_IN = '^[:q!^M'
for name in ('edit_keys', 'ex_keys', 'visual_keys', 'view_keys'):
    (o, _, _), (n, _, _) = by[name]
    if READ_IN not in o:
        fail.append('%s: the keystroke file did not reach the buffer on the input '
                    'binary, so this proves nothing about opening a file' % name)
    if READ_IN in n:
        fail.append('%s: the new binary opened the file anyway' % name)
    if E492 not in n:
        fail.append('%s: the new binary does not answer E492' % name)
    if '"keys"' not in o:
        fail.append('%s: the input binary did not name the file it opened' % name)
    if '"keys"' in n:
        fail.append('%s: the new binary still names a file it opened' % name)

# `:view` IS `:edit` PLUS 'readonly', which is the whole of what do_exedit did with
# CMD_view -- and the only way to see it is to ask.
(o, _, _), (n, _, _) = by['view_keys']
if 'noreadonly' in o or 'readonly' not in o:
    fail.append('view_keys: `:set ro?` did not answer `readonly` on the input '
                'binary, so `:view` being `:edit` with the option set is not shown')
if 'noreadonly' not in n:
    fail.append('view_keys: `:set ro?` does not answer `noreadonly` now, so the '
                'option was set by something other than the command that went')

# `:enew!` IS `:edit` WITH A NULL NAME: the old binary throws the text away.
(o, _, _), (n, _, _) = by['enew_bang']
if 'hello' in o.rsplit('--- snap', 1)[-1]:
    fail.append('enew_bang: the input binary did not empty the buffer, so this '
                'proves nothing about `:enew`')
if 'hello' not in n.rsplit('--- snap', 1)[-1]:
    fail.append('enew_bang: the new binary emptied the buffer anyway')
if E492 not in n:
    fail.append('enew_bang: `:enew!` is not an unknown command')

# THE FOUR KEYS.  E447 on the old binary is the proof that the key reached
# nv_gotofile() and looked for the file; afterwards the key beeps from the same
# place every other unused g/[/] key does, which is one snapshot fewer and the same
# single bell -- so the SNAPSHOT COUNT is the check and the bell is not.
for name in ('key_gf', 'key_gF', 'key_br_f', 'key_brc_f'):
    (o, _, osnaps), (n, _, nsnaps) = by[name]
    if 'E447: Can\'t find file "nosuchfile" in path' not in o:
        fail.append('%s: the key did not look for a file on the input binary, so '
                    'this proves nothing' % name)
    if 'E447' in n:
        fail.append('%s: the key still looks for a file' % name)
    if nsnaps != osnaps - 1:
        fail.append('%s: %d snapshots against the input binary\'s %d, expected one '
                    'fewer -- the message drew a redraw of its own' % (name, nsnaps, osnaps))

# THE INHERITANCE CHECK.  whim's Phase 80 gave every row its shortest abbreviation
# and made a match require at least that many characters, so a removed name cannot
# be inherited by the next row -- but that is an argument, and `:e` silently
# becoming `:earlier` is exactly the shape of bug CLAUDE.md records for `:help` ->
# `:helpclose`.  Ten spellings each answered E37 before and answer E492 now.
for s in SPELLINGS:
    (o, _, _), (n, _, _) = by['spell_' + s]
    if E492 in o:
        fail.append(':%s already answered E492 before this phase, so it proves '
                    'nothing' % s)
    if 'E37: No write since last change' not in o:
        fail.append(':%s did not reach its own refusal on the input binary' % s)
    if E492 not in n:
        fail.append(':%s does not answer E492: a removed name has been inherited' % s)
# `:en` IS THE ELEVENTH SPELLING AND IS NOT THIS PHASE'S.  `enew`'s shortest
# abbreviation is three characters, so `:en` matched nothing before this phase
# either -- which is whim's Phase 80 rule, measured rather than argued.
(o, _, _), (n, _, _) = by['spell_en']
if E492 not in o or E492 not in n:
    fail.append('spell_en: `:en` was E492 on both sides before this phase was '
                "written -- enew's shortest abbreviation is three characters")

# THE DECLARED CASE, which the delta says moved and which this says HOW.
(o, _, _), (n, _, _) = by['cmd_edit']
if 'E37: No write since last change' not in o or 'E37' in n:
    fail.append('cmd_edit: E37 was to be the old answer -- `:edit` with no file '
                'name reached check_changed() -- and to be gone now')
if E492 not in n:
    fail.append('cmd_edit: `:edit` is not an unknown command')

# The ones that must not move are required to be DOING something, not failing alike.
(o, _, _), (n, _, _) = by['quit_modified']
if 'E37: No write since last change' not in n:
    fail.append('quit_modified: :q no longer refuses on a modified buffer, and that '
                'is the :q phase\'s to change')
(o, _, _), (n, _, _) = by['cmd_file']
if '[No Name]' not in n:
    fail.append('cmd_file: `:file` no longer reports the buffer, and it is the '
                'buffer-name phase\'s')
for name, want in (('cmd_append', 'added'), ('editing', 'alpha'),
                   ('cmd_vglobal', 'b2'), ('verbose_ro', 'noreadonly')):
    (o, _, _), (n, _, _) = by[name]
    if want not in n:
        fail.append('%s: the new binary no longer shows %r, so "it did not move" '
                    'is two failures agreeing' % (name, want))
# `:registers` prints its table, a `Press ENTER` prompt follows, and the redraw
# wipes it before the cursor comes back -- so it is in the STREAM and in no snapshot.
(o, ostream, _), (n, nstream, _) = by['cmd_registers']
if 'Type Name Content' not in nstream or 'Type Name Content' not in ostream:
    fail.append('cmd_registers: :registers printed no table, so "it did not move" '
                'is two failures agreeing')
# `:read keys` IS THE TRAP IN THE DECLARATION: phase 7 removed it, so this record
# was ALREADY E492 and naming a file it could open changes nothing.
(o, _, _), (n, _, _) = by['cmd_read']
if E492 not in o or E492 not in n:
    fail.append('cmd_read: `:read keys` was E492 on both sides before this phase '
                'was written -- zero phase 7 took it')

if fail:
    for line in fail:
        print('  %-12s %s' % (TAG, line))
    print('  %-12s the corpus cannot see a file being opened -- `cmd_edit` types' % '')
    print('  %-12s `:edit` with no file name and records E37, and `key_gf` presses' % '')
    print('  %-12s `gf` on a word naming nothing.  These are the only probes that' % '')
    print('  %-12s can tell a removed command from a changed message.' % '')
    sys.exit(1)
print('  %-12s probes: %d moved (%s), %d unchanged' % (TAG, len(moved), ' '.join(moved), len(static)))
print('  %-12s the input binary opened `keys` through :e :ex :visual and :view, '
      'answered `readonly` under the last, emptied the buffer for :enew! and found '
      'four ways to look for a file from the keyboard; ten spellings answer E492 '
      'and none did before' % '')
PY

# --- 7. fifty keys, of which exactly four may move ------------------------------------
# THE HAZARD THIS PHASE DOES NOT HAVE, asserted anyway.  No nv_cmds[] row is deleted
# or repointed here: `gf`, `gF`, `[f` and `]f` are arms inside nv_g_cmd() and
# nv_brackets(), whose `g`, `[` and `]` rows dispatch dozens of other keys.  That is
# an argument; this is the measurement, and it is what proves the two cuts inside
# those handlers took the arms and not the chain.
python3 - "$state/old" "$bin" <<'PY'
import concurrent.futures, hashlib, os, shutil, subprocess, sys, tempfile
sys.path.insert(0, 'tools')
import zrec
import zscreen
import zstream
TAG = 'noedit'
ESC, CR = b'\x1b', b'\r'
old_bin, new_bin = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])

G = ['ga', 'g8', 'g_', 'gI', 'gi', 'gJ', 'gj', 'gk', 'gv', 'gp', 'gP', 'gq', 'gu',
     'gU', 'g~', 'g?', 'gg', 'ge', 'gE', 'gm', 'gM', 'go', 'gs', 'gt', 'gT', 'g0',
     'g^', 'g$', 'g&', 'g;']
B = ['[(', '[{', '])', ']}', '[[', '[]', ']]', '][', '[p', ']p', '[P', ']P',
     "['", "]'", '[`', ']`']
MOVERS = ['gf', 'gF', '[f', ']f']
KEYS = G + B + MOVERS


def record(binary, keys):
    vim = zstream.stage(binary)     # argv[0], and the copy race: tools/zstream.py
    home = tempfile.mkdtemp(prefix='zero8-kh-')
    env = dict(os.environ)
    env.update(TERM='xterm', HOME=home, VIM=os.path.join(home, 'novim'),
               VIMRUNTIME=os.path.join(home, 'novim'),
               XDG_CONFIG_HOME=os.path.join(home, 'xdg'))
    for k in ('LINES', 'COLUMNS', 'VIMINIT', 'EXINIT', 'MYVIMRC'):
        env.pop(k, None)
    d = tempfile.mkdtemp(prefix='zero8-kr-')
    kf = os.path.join(d, 'keys')
    with open(kf, 'wb') as fh:
        fh.write(b''.join(keys))
    try:
        with open(kf, 'rb') as stdin:
            r = subprocess.run([vim, '+set paste'], stdin=stdin,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               env=env, cwd=d, timeout=10, start_new_session=True)
        rc, out = r.returncode, r.stdout
    except subprocess.TimeoutExpired:
        rc, out = 'timeout', b''
    finally:
        for p in (home, d):
            shutil.rmtree(p, ignore_errors=True)
    scr = zscreen.Screen(24, 80)
    scr.feed(out)
    text = zrec.section('exit %s' % rc) + zrec.section('bells %d' % scr.bells)
    text += zrec.section('stream sha=%s' % hashlib.sha256(out).hexdigest()[:16])
    for i, (dump, y, x, bells) in enumerate(scr.snaps):
        text += zrec.section('snap %d cursor=%d,%d bells=%d' % (i, y, x, bells), dump)
    return zrec.scrub(text)


def one(k):
    keys = [b'ialpha beta' + CR + b'nosuchfile' + ESC, b':set nopaste' + CR,
            b'gg0' + k.encode(), ESC + b':q!' + CR]
    return k, record(old_bin, keys), record(new_bin, keys)


with concurrent.futures.ThreadPoolExecutor(max_workers=len(KEYS)) as ex:
    res = list(ex.map(one, KEYS))
moved = [k for k, o, n in res if o != n]
if sorted(moved) != sorted(MOVERS):
    print('  %-12s of %d g*/[/] keys, %d moved: %s -- exactly %s were to'
          % (TAG, len(KEYS), len(moved), ' '.join(moved) or '(none)', ' '.join(MOVERS)))
    print('  %-12s a key that moved and was not to means one of the two cuts took '
          'part of the chain it sat in' % '')
    sys.exit(1)
print('  %-12s keys: %d of %d moved -- %s -- and the other %d are identical in '
      'exit, bells, snapshots and stream digest, which is what proves nv_g_cmd() '
      'and nv_brackets() survived'
      % (TAG, len(moved), len(KEYS), ' '.join(MOVERS), len(KEYS) - len(moved)))
PY

# --- 8. a real terminal, and a file the runner wrote ----------------------------------
python3 - "$state/old" "$bin" <<'PY'
import os, sys, tempfile
sys.path.insert(0, 'tools')
import ptyrun
TAG = 'noedit'
home = tempfile.mkdtemp(prefix='zero8-home-')
env = dict(os.environ, HOME=home, VIM=os.path.join(home, 'novim'),
           VIMRUNTIME=os.path.join(home, 'novim'),
           XDG_CONFIG_HOME=os.path.join(home, 'xdg'))
for k in ('VIMINIT', 'EXINIT', 'MYVIMRC'):
    env.pop(k, None)


def session(binary, keys, plant=None):
    d = tempfile.mkdtemp(prefix='zero8-pty-')
    if plant:
        with open(os.path.join(d, plant[0]), 'w') as fh:
            fh.write(plant[1])
    text, status = ptyrun.session(binary, [], keys, term='xterm', cwd=d,
                                  settle=0.6, env=env)
    return text.decode('utf-8', 'replace'), status


# `:e! planted.txt` on a pty.  THE RUNNER WRITES THE FILE, because the editor has
# had no way to write one since phase 6 -- which is what makes this a probe of
# opening one alone.  The old binary replaces the buffer with it; this one answers
# E492.
ed = [session(b, [b'ityped on a terminal\x1b', b':e! planted.txt\r', b':q!\r'],
              plant=('planted.txt', 'FROMTHEDISK\n'))
      for b in (sys.argv[1], sys.argv[2])]
if 'FROMTHEDISK' not in ed[0][0]:
    sys.exit('  %-12s the input binary opened nothing on a pty, so this proves nothing' % TAG)
if 'FROMTHEDISK' in ed[1][0]:
    sys.exit('  %-12s the new binary opened planted.txt on a pty' % TAG)
if 'E492' not in ed[1][0]:
    sys.exit('  %-12s `:e!` on a pty did not answer E492 on the new binary' % TAG)

# And an ordinary editing session, which must be identical on both.
edit = [session(b, [b'ityped here\x1b', b'0dw', b':set ruler?\r', b':q!\r'])
        for b in (sys.argv[1], sys.argv[2])]
if 'here' not in edit[0][0] or 'ruler' not in edit[0][0]:
    sys.exit('  %-12s the editing pty session did not edit on the input binary' % TAG)
if edit[0] != edit[1]:
    sys.exit('  %-12s the editing pty session moved: %r -> %r'
             % (TAG, edit[0][1], edit[1][1]))
print('  %-12s pty: the input binary opened a planted file into the buffer and this '
      'one answers E492; the editing session identical either side' % TAG)
PY
