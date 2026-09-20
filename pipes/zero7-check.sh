#!/bin/sh
# Zero phase 7, the check -- nothing can take bytes off a disk on request any more.
# See pipes/zero7-edit.sh, and ZERO-GOAL.md.
#
# Usage: pipes/zero7-check.sh <work-dir> <state-dir>     (run from the repository root)
#
# Runs after pipes/zero7-edit.sh and the sweep tools/phaserun.sh runs between them,
# and reads nothing from the edit's shell -- only the work tree and the state
# directory.  What the edit left there is `old`, the binary this phase was HANDED,
# and `old.c`, the source it was built from, which is the left-hand side of every
# before-and-after count below.
#
# FIVE THINGS ARE PROVED HERE, and the third is the only one that can say what this
# phase is actually for.
#
# 1. THE CUT, which is the sweep's work and not the edit's.  Six functions go, none
#    of them named by the edit -- ex_read, do_bang, do_shell, do_filter,
#    check_secure and prevcmd_is_set -- with the static `prevcmd`, the struct field
#    `usefilter` the edit folded away, and five strings (`"read"`, E12, E34, E319
#    and E484).  Listing them here is a RECORDING of what the sweep did, which is
#    the only place a list of removed names belongs.
#
#    THE TRAPS, ALL MEASURED, that make a copied "every name at zero mentions" loop
#    the wrong check:
#      * `secure` IS NOT `check_secure`.  The function goes; the variable keeps
#        ELEVEN mentions, because `secure` is the vimrc/tag-search flag and half the
#        editor tests it.  Only the two inside check_secure() went.
#      * THE BARE WORD `read` SURVIVES three times -- two `read(fd, ...)` calls and
#        an E222 string -- and `readfile`, `read_buffer`, `read_edit`, `readonly`,
#        `shell` and `filter` all survive at their own counts.  This phase removes
#        `:read`, not reading.
#      * `E32: No file name` SURVIVES, still reachable through check_fname() from
#        do_ecmd(); `E484: Can't open file` does NOT -- ex_read was its last
#        speaker, and after this phase nothing in the file says it.  Both are
#        asserted, in opposite directions.
#
# 2. THE LINE AGAINST THE PHASE THAT STOPS READING A BYTE (ZERO-PLAN.md P8), stated
#    as counts so that taking any of it here would fail rather than widen quietly:
#    `readfile` is required to keep EXACTLY 5 mentions -- its prototype, its
#    definition and the three calls in read_buffer() and open_buffer() -- with
#    read_buffer at 17 and open_buffer at 6.  What this phase takes is the two calls
#    that were ex_read's.  The table is checked the same way: 104 rows, names()
#    reading exactly those, the static_assert in place, and the FOUR rows of margin
#    above create_cmdidxs's floor of 100 said out loud -- the `:edit` phase is the
#    one that must lower it (ZERO-PLAN.md 3a).
#
# 3. THE PROBES, on BOTH binaries, because THE CORPUS CANNOT SEE A FILE BEING READ.
#    Every one of `zcases`'s 102 cases types its own text and names no file:
#    `cmd_read` types `:read` with no file name, so the baseline it is compared
#    against records `E32: No file name` -- an editor that FAILED to read.  A
#    declared delta of "cmd_read and read_cmd_gone moved" is therefore consistent
#    with a phase that changed two error messages and left readfile() reachable from
#    a command.  So the probes run the binary this phase was handed beside the one
#    it made, and the ones that matter require the OLD binary to pull a file off the
#    disk and the new one to refuse.
#
#    THE FILE IS `keys` ITSELF.  tools/zstream.py writes a session's keystrokes into
#    a file called `keys` in the run directory and feeds it on stdin, so there is
#    always one file there to read and no runner has to plant one: `:r keys` reads
#    it back, and the old binary answers `"keys" [noeol] 1L, 33B` with the
#    keystrokes in the buffer.
#
# 4. THE INHERITANCE CHECK.  whim's Phase 80 gave every row its shortest
#    abbreviation and made a match require at least that many characters, so a
#    removed name cannot be inherited by the next row -- but that is an argument,
#    and `:r` silently becoming `:redo` is exactly the shape of bug CLAUDE.md
#    records for `:help` -> `:helpclose`.  Six spellings are typed and each must
#    answer E492 now and something else before; `:redo`, `:redraw`, `:registers`
#    and `:reg` are required not to move at all.
#
# 5. A REAL TERMINAL.  Every probe above went through a pipe.  The session types
#    `:r <file>` on a pty, where the file is one the RUNNER wrote -- the editor has
#    had no way to write one since phase 6 -- and the old binary puts its line in
#    the buffer while this one answers E492.  An ordinary editing session beside it
#    is required to be identical.
#
# WHAT IS NOT ASSERTED, and why.  `E319: Sorry, the command is not available in this
# version` is what whim's do_shell()/do_filter() stubs answered, so it never reaches
# a SNAPSHOT: the message is drawn, a `Press ENTER` prompt follows and the next
# redraw wipes the line before the cursor comes back, which is where
# tools/zscreen.py takes its picture.  It is in the STREAM, so that is where the
# probe looks -- and its presence on the old binary is also the proof that no shell
# ever ran, the stub having refused before one could.
#
# A record is built the way `zcases` builds one and scrubbed the same way
# (tools/zrec.py).  tools/zstream.py's session() is not called directly because this
# check needs the raw stream beside the screens.
set -eu

work=${1:?usage: zero7-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero7-check.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"
before_lines=$(cat "$state/input-lines")

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# --- 1. what the sweep took, recorded -----------------------------------------------
for gone in ex_read do_bang do_shell do_filter check_secure prevcmd_is_set prevcmd \
            CMD_read usefilter; do
    n=$(grep -cw -- "$gone" "$f" || true)
    [ "$n" = 0 ] || { echo "  noread       '$gone' still has $n mentions"; exit 1; }
done
# The strings that lose their last speaker.  `"read"` is the command name; the four
# errors were said by the five functions above and by nothing else.
for gone in '"read"' "E484: Can't open file" 'E319: Sorry' 'E34: No previous command' \
            'E12: Command not allowed'; do
    n=$(grep -cF -- "$gone" "$f" || true)
    [ "$n" = 0 ] || { echo "  noread       the string '$gone' still has $n mentions"; exit 1; }
done
echo "  noread       six functions, the prevcmd static, the usefilter field and five strings at 0 mentions -- all but the field taken by the sweep"

# --- 2. and everything that must NOT be at zero -------------------------------------
python3 - "$f" "$state/old.c" <<'PY'
import re, sys
sys.path.insert(0, 'tools')
# tools/create_cmdidxs.py -- named as a PATH so tools/implhash.sh hashes it into this
# phase's key.  implhash greps for paths and an `import` names a module, so
# without this line an edit to it changes what this phase produces and moves
# no key at all.  See CLAUDE.md on cutil.py and macros.py.  Do not delete it.
import create_cmdidxs
# tools/cutil.py -- named as a PATH so tools/implhash.sh hashes it into this
# phase's key.  implhash greps for paths and an `import` names a module, so
# without this line an edit to it changes what this phase produces and moves
# no key at all.  See CLAUDE.md on cutil.py and macros.py.  Do not delete it.
import cutil
TAG = 'noread'
new = open(sys.argv[1], errors='surrogateescape').read()
old = open(sys.argv[2], errors='surrogateescape').read()
fail = []


def count(text, name):
    return len(re.findall(r'\b%s\b' % name, text))


# THE BARE WORDS, each with the reason it is not this phase's.  A loop that wanted
# zero for any of these would fail on a correct phase.
KEPT = {'secure': 11,          # the vimrc / tag-search flag: check_secure() read it
        'read': 3,             # two read(fd, ...) calls and an E222 string
        'readfile': 5,         # prototype, definition, three calls -- P8's
        'read_buffer': 17,     # P8's
        'open_buffer': 6,      # P8's
        'read_edit': 2,        # the exarg_T field :edit uses -- P7 of the plan's
        'readonly': 4,         # the option, and W10 -- P11's
        'shell': 1,            # one word of an option-name list, in a string
        'filter': 2,           # the `:filter` MODIFIER: its row and checkforcmd
        'check_fname': 4}      # do_ecmd()'s, and E32 with it
for name, want in sorted(KEPT.items()):
    k = count(new, name)
    if k != want:
        fail.append('%s has %d mentions, expected %d -- %s'
                    % (name, k, want, 'this phase reached too far'
                       if k < want else 'something survived that should not have'))

# E32 stays and E484 goes: the two are the whole difference between "no file name
# was given" and "the file could not be opened", and only the second was ex_read's.
if new.count('E32: No file name') != 1:
    fail.append('E32: No file name went, and it is reachable through check_fname() '
                'from do_ecmd(): it is not this phase\'s')
if "E484: Can't open file" in new:
    fail.append("E484: Can't open file survives, and ex_read was its last speaker")

# What this phase deliberately leaves to the phases after it.
for kept in ('check_changed', 'do_ecmd', 'setfname', 'otherfile', 'fix_fname',
             'b_ffname', 'b_fname', 'getexline', 'exe_commands', 'nv_error'):
    if not count(new, kept):
        fail.append('%s went, and it is a later phase\'s' % kept)
# The 'Q' row phase 4 pointed at nv_error, not deleted: a hole in nv_cmds[] moves
# every key past it onto another key's row (CLAUDE.md).  nvidxcheck.py, which
# tools/phasecheck.sh runs below, is the general form; this is the one row a zero
# phase has already touched.
if not re.search(r"^ *\{'Q', nv_error,", new, re.M):
    fail.append("the 'Q' row is no longer nv_error's, and phase 4 put it there")

# The table.
rows = re.findall(r'^    \[CMD_\w+\] = \{.*$', new, re.M)
got = create_cmdidxs.names(sys.argv[1])
if len(rows) != 104 or len(got) != 104:
    fail.append('cmdnames[] has %d rows and names() reads %d; both must be 104'
                % (len(rows), len(got)))
if 'read' in got:
    fail.append(':read is still a command name')
for name in ('redo', 'redraw', 'registers', 'edit', 'print', 'append'):
    if name not in got:
        fail.append(':%s went, and it is not this phase\'s' % name)
if 'static_assert(sizeof(cmdnames) / sizeof(cmdnames[0]) == CMD_SIZE' not in new:
    fail.append('the static_assert on the row count went, and it is what catches '
                'an enumerator removed without its row')

# The fold, from the other side: nothing assigns or tests a filter flag, and the
# two functions whose conditions carried it are still there.
for fn in ('do_one_cmd', 'expand_filename'):
    if not cutil.find_definition(new, fn):
        fail.append('%s went, and this phase only folded six tests inside it' % fn)

# What the five functions cost the old file, as a difference rather than a number.
if count(old, 'usefilter') != 10 or count(old, 'check_secure') != 3:
    fail.append('the input is not the file this phase was written against: '
                'usefilter %d (10), check_secure %d (3)'
                % (count(old, 'usefilter'), count(old, 'check_secure')))

if fail:
    for line in fail:
        print('  %-12s %s' % (TAG, line))
    print('  %-12s a "no mention anywhere" check fails on a correct phase here:' % '')
    print('  %-12s `secure` is not check_secure, `read` is a libc call and an' % '')
    print('  %-12s E222 string, and readfile() belongs to a later phase.' % '')
    sys.exit(1)
print('  %-12s kept: secure 11, read 3, readfile 5, read_buffer 17, open_buffer 6, '
      'check_fname 4 with E32 -- and E484 has no speaker left' % TAG)
print('  %-12s table: 104 rows, names() reads 104, static_assert in place, '
      "4 rows above create_cmdidxs's floor of 100" % TAG)
PY

# --- 3. the compile, the linkage and the libc surface -------------------------------
# NOTHING IS FREED, AND THAT IS STATED AS AN EQUALITY.  `:read` reached readfile(),
# which the startup path still uses, and the shell stubs never called a shell -- so
# this phase removes two commands and not the read path, and the undefined set must
# come out EXACTLY as it went in.  A symbol going would mean the cut reached into
# ZERO-PLAN.md P8's phase; a symbol arriving would mean the sweep left something
# that now links.
cp "$state/symbols/undefined" "$tmp/before.u"
tools/phasecheck.sh "$work" "$f" "$state/symbols"
if ! cmp -s "$tmp/before.u" .cache/symbols/last/undefined; then
    echo "  noread       the libc surface moved, and this phase frees nothing:"
    echo "               gone: $(comm -23 "$tmp/before.u" .cache/symbols/last/undefined | tr '\n' ' ')"
    echo "               came: $(comm -13 "$tmp/before.u" .cache/symbols/last/undefined | tr '\n' ' ')"
    echo "               open, access and read are the byte-reader phase's (ZERO-PLAN.md P8)"
    exit 1
fi
for keep in open read close stat; do
    grep -qx "$keep" .cache/symbols/last/undefined \
        || { echo "  noread       $keep is gone, and it is the byte-reader phase's"; exit 1; }
done
echo "  noread       symbols $(cat .cache/symbols/last/before) -> $(cat .cache/symbols/last/after), the same set: this phase removes two commands, not the read path"

# --- 4. the binary -------------------------------------------------------------------
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

# --- 5. the probes, on both binaries -------------------------------------------------
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

TAG = 'noread'
ESC, CR = b'\x1b', b'\r'
QUIT = ESC + b':q!' + CR
old_bin, new_bin = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])


def record(binary, args, keys, timeout=10):
    """tools/zstream.py's session, with the raw stream handed back beside the screens.

    Everything else is that tool's, and for its reasons: the binary is staged as
    `vim` because argv[0] decides what the editor is, the environment is emptied so
    that no vimrc is found, and the session is its own so that a stop signal cannot
    reach this shell.  THE KEYSTROKE FILE IS THE FILE THE PROBES READ: it is written
    as `keys` in the run directory, so `:r keys` needs nothing planted.
    """
    vim = zstream.stage(binary)     # argv[0], and the copy race: tools/zstream.py
    home = tempfile.mkdtemp(prefix='zero7-home-')
    env = dict(os.environ)
    env.update(TERM='xterm', HOME=home, VIM=os.path.join(home, 'novim'),
               VIMRUNTIME=os.path.join(home, 'novim'),
               XDG_CONFIG_HOME=os.path.join(home, 'xdg'))
    for k in ('LINES', 'COLUMNS', 'VIMINIT', 'EXINIT', 'MYVIMRC'):
        env.pop(k, None)
    d = tempfile.mkdtemp(prefix='zero7-run-')
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
    return zrec.scrub(text), out.decode('utf-8', 'replace')


def typed(seed, *keys):
    """zcases's shape: type the seed under 'paste', then the real keys."""
    return (['+set paste'], [b'i' + seed + ESC, b':set nopaste' + CR] + list(keys) + [QUIT])


HELLO = b'hello'

# name, (args, keys), must-differ
PROBES = [
    # --- reading, which is the whole phase and which no recorded case can see ---
    ('r_keys',     typed(HELLO, b':r keys' + CR),                      True),
    ('r_range',    typed(b'a' + CR + b'b', b':1r keys' + CR),          True),
    ('r_missing',  typed(HELLO, b':1r nosuch' + CR),                   True),
    ('r_bang',     typed(HELLO, b':r !echo piped' + CR),               True),
    # --- the inheritance check: six spellings, each E492 now and not before ---
    ('r_bare',     typed(HELLO, b':r' + CR),                           True),
    ('re_bare',    typed(HELLO, b':re' + CR),                          True),
    ('rea_bare',   typed(HELLO, b':rea' + CR),                         True),
    ('r_forceit',  typed(HELLO, b':r!' + CR),                          True),
    ('r_cat',      typed(HELLO, b':r !cat' + CR),                      True),
    # --- the two corpus cases this phase declares, run directly ---
    ('cmd_read',      typed(b'x', b':read' + CR),                      True),
    ('read_cmd_gone', typed(b'x', b':r !echo piped' + CR),             True),
    # --- and everything that must not move ---
    ('filter_gone',   typed(b'b' + CR + b'a', b':%!sort' + CR),        False),
    ('cmd_redo',      typed(HELLO, b'x', b'u', b':redo' + CR),         False),
    ('cmd_redraw',    typed(HELLO, b':redraw' + CR),                   False),
    ('cmd_registers', typed(HELLO, b':registers' + CR),                False),
    ('cmd_reg',       typed(HELLO, b':reg' + CR),                      False),
    ('cmd_undo',      typed(HELLO, b'x', b':undo' + CR),               False),
    ('cmd_edit',      typed(HELLO, b':edit' + CR),                     False),
    ('cmd_print',     typed(HELLO, b':print' + CR),                    False),
    ('cmd_append',    typed(HELLO, b':append' + CR, b'added' + CR, b'.' + CR), False),
    ('cmd_insert',    typed(HELLO, b':insert' + CR, b'ins' + CR, b'.' + CR), False),
    ('cmd_change',    typed(HELLO, b':change' + CR, b'chg' + CR, b'.' + CR), False),
    ('quit_modified', typed(HELLO, b':q' + CR),                        False),
    ('quit_bang',     (['+set paste'], [b'i' + HELLO + ESC, b':set nopaste' + CR, b':q!' + CR]), False),
    ('editing',       typed(b'alpha' + CR + b'beta', b'0dwA-tail' + ESC, b'u', b'yyp'), False),
]


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

# THE THREE THAT PULLED A FILE OFF THE DISK.  Each is required to have read one on
# the OLD binary: a probe that only looks at the new binary passes on a phase that
# did nothing.
#
# WHAT PROVES THE BYTES ARRIVED is the ESCAPE in them.  The keystroke file holds
# `...\x1b:q!\r`, which tools/zscreen.py draws as `^[:q!^M` -- and an Escape can
# only be in the buffer if the file was read, since nothing typed at `:` puts one
# there.  The file MESSAGE is not the check: `:1r keys` reads the file and leaves
# the message line blank, measured, so only `:r keys` can be asked for `"keys"`.
READ_IN = '^[:q!^M'
for name in ('r_keys', 'r_range'):
    (o, _), (n, _) = by[name]
    if READ_IN not in o:
        fail.append('%s: the keystroke file did not reach the buffer on the input '
                    'binary, so this proves nothing about reading' % name)
    if READ_IN in n:
        fail.append('%s: the new binary read the file anyway' % name)
    if E492 not in n:
        fail.append('%s: the new binary does not answer E492' % name)
(o, _), (n, _) = by['r_keys']
if '"keys"' not in o or '1L,' not in o:
    fail.append('r_keys: the input binary did not report `"keys" ... 1L,` for the '
                'file it read')
if '"keys"' in n:
    fail.append('r_keys: the new binary still names a file it read')
(o, _), (n, _) = by['r_missing']
if "E484: Can't open file nosuch" not in o:
    fail.append('r_missing: the input binary did not try to open the file')
if E492 not in n or 'E484' in n:
    fail.append('r_missing: E484 has a speaker left')

# `:r !cmd` went through do_bang() to whim's do_shell() stub, which answered E319
# BEFORE running anything -- so E319 on the old binary is also the proof that no
# shell ran.  It is in the STREAM and never in a snapshot: the message is drawn, a
# `Press ENTER` prompt follows, and the next redraw wipes the line before the cursor
# comes back, which is where tools/zscreen.py takes its picture.
(o, ostream), (n, nstream) = by['r_bang']
if 'E319: Sorry, the command is not available in this version' not in ostream:
    fail.append('r_bang: the input binary did not reach the shell stub, so this '
                'proves nothing about `:r !cmd`')
if 'E319' in nstream:
    fail.append('r_bang: the shell stub still speaks')
if E492 not in nstream:
    fail.append('r_bang: `:r !echo piped` is not an unknown command')

# THE INHERITANCE CHECK: every spelling answers E492 now, and none did before.
# `:r` becoming `:redo` would be invisible to everything else here.
for name in ('r_keys', 'r_range', 'r_missing', 'r_bang', 'r_bare', 're_bare',
             'rea_bare', 'r_forceit', 'r_cat', 'cmd_read', 'read_cmd_gone'):
    (o, _), (n, _) = by[name]
    if E492 in o:
        fail.append('%s already answered E492 before this phase, so it proves nothing' % name)
    if E492 not in n:
        fail.append('%s does not answer E492: a removed name has been inherited' % name)

# THE TWO DECLARED CASES, which the delta says moved and which this says HOW.
(o, _), (n, _) = by['cmd_read']
if 'E32: No file name' not in o or 'E32: No file name' in n:
    fail.append('cmd_read: E32 was to be the old answer and to be gone now')
(o, ostream), (n, _) = by['read_cmd_gone']
if 'bells 1' not in o or 'bells 1' not in n:
    fail.append('read_cmd_gone: the bell was to ring once either side')
if 'E319' not in ostream:
    fail.append('read_cmd_gone: `:r !echo piped` did not reach the shell stub before')

# `:%!sort` IS THE TRAP IN THE DECLARATION.  `:!` has not existed since whim, so
# this record was ALREADY E492 and `filter_gone` is not this phase's to declare --
# which is worth asserting, because the code behind it is exactly what went.
(o, _), (n, _) = by['filter_gone']
if E492 not in o or E492 not in n:
    fail.append('filter_gone: `:%!sort` was E492 on both sides before this phase '
                'was written, and declaring it would be a delta the phase did not cause')

# The ones that must not move are required to be DOING something, not failing alike.
(o, _), (n, _) = by['quit_modified']
if 'E37: No write since last change' not in n:
    fail.append('quit_modified: :q no longer refuses on a modified buffer, and that '
                'is the :q phase\'s to change')
for name, want in (('cmd_append', 'added'), ('cmd_insert', 'ins'),
                   ('cmd_change', 'chg'), ('editing', 'alpha')):
    (o, _), (n, _) = by[name]
    if want not in n:
        fail.append('%s: the new binary no longer shows %r, so "it did not move" '
                    'is two failures agreeing' % (name, want))
# `:registers` prints its table, a `Press ENTER` prompt follows, and the redraw
# wipes it before the cursor comes back -- so it is in the STREAM and in no
# snapshot, exactly as E319 is.
(o, ostream), (n, nstream) = by['cmd_registers']
if 'Type Name Content' not in nstream or 'Type Name Content' not in ostream:
    fail.append('cmd_registers: :registers printed no table, so "it did not move" '
                'is two failures agreeing')

if fail:
    for line in fail:
        print('  %-12s %s' % (TAG, line))
    print('  %-12s the corpus cannot see a file being read -- every case types' % '')
    print('  %-12s `:read` with no file name and records E32.  These are the only' % '')
    print('  %-12s probes that can tell a removed command from a changed message.' % '')
    sys.exit(1)
print('  %-12s probes: %d moved (%s), %d unchanged' % (TAG, len(moved), ' '.join(moved), len(static)))
print('  %-12s the input binary read `keys` back and opened `nosuch`; eleven '
      'spellings of :r answer E492 and none did before' % '')
PY

# --- 6. a real terminal, and a file the runner wrote ----------------------------------
python3 - "$state/old" "$bin" <<'PY'
import os, sys, tempfile
sys.path.insert(0, 'tools')
# tools/ptyrun.py -- named as a PATH so tools/implhash.sh hashes it into this
# phase's key.  implhash greps for paths and an `import` names a module, so
# without this line an edit to it changes what this phase produces and moves
# no key at all.  See CLAUDE.md on cutil.py and macros.py.  Do not delete it.
import ptyrun
TAG = 'noread'
home = tempfile.mkdtemp(prefix='zero7-home-')
env = dict(os.environ, HOME=home, VIM=os.path.join(home, 'novim'),
           VIMRUNTIME=os.path.join(home, 'novim'),
           XDG_CONFIG_HOME=os.path.join(home, 'xdg'))
for k in ('VIMINIT', 'EXINIT', 'MYVIMRC'):
    env.pop(k, None)


def session(binary, keys, plant=None):
    d = tempfile.mkdtemp(prefix='zero7-pty-')
    if plant:
        with open(os.path.join(d, plant[0]), 'w') as fh:
            fh.write(plant[1])
    text, status = ptyrun.session(binary, [], keys, term='xterm', cwd=d,
                                  settle=0.6, env=env)
    return text.decode('utf-8', 'replace'), status


# `:r planted.txt` on a pty.  THE RUNNER WRITES THE FILE, because the editor has had
# no way to write one since phase 6 -- which is what makes this a probe of reading
# alone.  The old binary puts the line in the buffer; this one answers E492.
rd = [session(b, [b'ityped on a terminal\x1b', b':r planted.txt\r', b':q!\r'],
              plant=('planted.txt', 'FROMTHEDISK\n'))
      for b in (sys.argv[1], sys.argv[2])]
if 'FROMTHEDISK' not in rd[0][0]:
    sys.exit('  %-12s the input binary read nothing on a pty, so this proves nothing' % TAG)
if 'FROMTHEDISK' in rd[1][0]:
    sys.exit('  %-12s the new binary read planted.txt on a pty' % TAG)
if 'E492' not in rd[1][0]:
    sys.exit('  %-12s `:r` on a pty did not answer E492 on the new binary' % TAG)

# And an ordinary editing session, which must be identical on both.
edit = [session(b, [b'ityped here\x1b', b'0dw', b':set ruler?\r', b':q!\r'])
        for b in (sys.argv[1], sys.argv[2])]
if 'here' not in edit[0][0] or 'ruler' not in edit[0][0]:
    sys.exit('  %-12s the editing pty session did not edit on the input binary' % TAG)
if edit[0] != edit[1]:
    sys.exit('  %-12s the editing pty session moved: %r -> %r'
             % (TAG, edit[0][1], edit[1][1]))
print('  %-12s pty: the input binary read a planted file into the buffer and this '
      'one answers E492; the editing session identical either side' % TAG)
PY
