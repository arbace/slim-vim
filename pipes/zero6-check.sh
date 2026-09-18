#!/bin/sh
# Zero phase 6, the check -- nothing can put bytes on a disk any more.
# See pipes/zero6-edit.sh, and ZERO-GOAL.md.
#
# Usage: pipes/zero6-check.sh <work-dir> <state-dir>     (run from the repository root)
#
# Runs after pipes/zero6-edit.sh and the sweep tools/phaserun.sh runs between them,
# and reads nothing from the edit's shell -- only the work tree and the state
# directory.  What the edit left there is `old`, the binary this phase was HANDED,
# and `old.c`, the source it was built from, which is the left-hand side of every
# before-and-after count below.
#
# FIVE THINGS ARE PROVED HERE, and the third is the only one that can say what this
# phase is actually for.
#
# 1. THE CUT, which is the sweep's work and not the edit's.  Nineteen functions go,
#    none of them named by the edit: ex_write, ex_update, ex_exit, do_write,
#    check_writable, check_overwrite, not_writing, check_readonly,
#    check_file_readonly, buf_write, buf_write_bytes, check_mtime, time_differs,
#    write_eintr, vim_fexists, mch_setperm, mch_fsetperm, mch_nodetype and
#    u_update_save_nr, with one struct field (exarg_T.append) and fourteen
#    enumerators.  Listing them here is a RECORDING of what the sweep did, which is
#    the only place a list of removed names belongs.
#
#    TWO TRAPS, BOTH MEASURED, that make a phase-4-style "every name at zero
#    mentions" loop the wrong check:
#      * `check_readonly` is ALSO A LOCAL, in readfile() -- `int check_readonly;`
#        and three uses.  After this phase `grep -cw` is 4, not 0, and a loop that
#        wanted 0 would fail on a correct phase.  What must be gone is the
#        DEFINITION, `^check_readonly(`, and the four survivors must all be inside
#        readfile(), which is asserted rather than assumed.
#      * `"write"` SURVIVES, as the name of the 'write' option, and `E32: No file
#        name` survives with it, still reachable through check_fname() from
#        do_ecmd() and ex_bang().  A "no mention of write anywhere" check would fail
#        on a correct phase just as surely.
#
# 2. THE TABLE.  105 rows, create_cmdidxs.names() reading exactly those, the
#    static_assert still there, and the five rows of margin above the tool's floor
#    of 100 said out loud -- the :edit phase is the one that must lower it
#    (ZERO-PLAN.md 3a).
#
# 3. THE PROBES, on BOTH binaries, because THE CORPUS CANNOT SEE WRITING.  Every
#    one of tools/zcases.py's 102 cases types its own text and never names a file:
#    `cmd_write` types `:write` with no file name, so the baseline it is compared
#    against records `E32: No file name` -- an editor that FAILED to write.  A
#    declared delta of "cmd_write and zz_key moved" is therefore consistent with a
#    phase that changed one error message and left buf_write() reachable.  So the
#    probes run the binary this phase was handed beside the one it made, in a
#    directory they KEEP, and the six that matter require the old binary to leave a
#    file on the disk and the new one to leave none.
#
# 4. THE INHERITANCE CHECK.  whim's Phase 80 gave every row its shortest
#    abbreviation and made a match require at least that many characters, so a
#    removed name cannot be inherited by the next row (ZERO-PLAN.md 3a) -- but that
#    is an argument, and `:w` silently becoming `:winsize` is exactly the shape of
#    bug CLAUDE.md records for `:help` -> `:helpclose`.  Eight spellings are typed
#    and each must answer E492 now and something else before.
#
# 5. A REAL TERMINAL.  `:wq` on a pty is how a person leaves this editor, and every
#    probe above went through a pipe.  The session is run on both binaries: the old
#    one writes the file and exits, the new one answers E492 and writes nothing.
#    pipes/zero2-check.sh drives a pty with `:wq` and reads the file back too, and
#    pipes/zero.stages says why that needs no `apart 2 6`: it opens the file as an
#    ARGUMENT and phase 5 already made that an unknown option, so it never reaches
#    the `:wq` -- measured identically on a phase 5 and a phase 6 tree.
#
# A record is built the way tools/zcases.py builds one and scrubbed the same way
# (tools/zrec.py), with one section added: the files the run left behind.
# tools/zstream.py's session() throws its directory away, which is the one thing a
# phase about writing files cannot do, so the runner is here.
set -eu

work=${1:?usage: zero6-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero6-check.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"
before_lines=$(cat "$state/input-lines")

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# --- 1. what the sweep took, recorded -----------------------------------------------
for gone in ex_write ex_update ex_exit do_write check_writable check_overwrite \
            not_writing check_file_readonly buf_write buf_write_bytes check_mtime \
            time_differs write_eintr vim_fexists mch_setperm mch_fsetperm \
            mch_nodetype u_update_save_nr; do
    n=$(grep -cw -- "$gone" "$f" || true)
    [ "$n" = 0 ] || { echo "  nowrite      '$gone' still has $n mentions"; exit 1; }
done
for gone in CMD_write CMD_wq CMD_xit CMD_exit CMD_update CMD_saveas; do
    n=$(grep -cw -- "$gone" "$f" || true)
    [ "$n" = 0 ] || { echo "  nowrite      '$gone' still has $n mentions"; exit 1; }
done
# The command NAMES, as strings.  `"write"` is not among them: it is the 'write'
# option's name and it stays, which is the second trap above.
for gone in '"wq"' '"xit"' '"exit"' '"update"' '"saveas"'; do
    n=$(grep -cF -- "$gone" "$f" || true)
    [ "$n" = 0 ] || { echo "  nowrite      the string $gone still has $n mentions"; exit 1; }
done
grep -q '^check_readonly(' "$f" \
    && { echo "  nowrite      check_readonly() is still defined"; exit 1; }
echo "  nowrite      18 functions and the six enumerators at 0 mentions, all taken by the sweep"

# --- 2. and the two things that must NOT be at zero ---------------------------------
python3 - "$f" "$state/old.c" <<'PY'
import re, sys
sys.path.insert(0, 'tools')
import create_cmdidxs
import cutil
TAG = 'nowrite'
new = open(sys.argv[1], errors='surrogateescape').read()
old = open(sys.argv[2], errors='surrogateescape').read()
fail = []


def count(text, name):
    return len(re.findall(r'\b%s\b' % name, text))


# check_readonly: the function is gone and the LOCAL in readfile() is not.
n = count(new, 'check_readonly')
if n != 4:
    fail.append('check_readonly has %d mentions, expected the 4 that are '
                "readfile()'s local and its uses" % n)
else:
    span = cutil.find_definition(new, 'readfile')
    if not span:
        fail.append('readfile() is not defined, and it is not this phase\'s to take')
    else:
        a, z = span
        outside = [m.start() for m in re.finditer(r'\bcheck_readonly\b', new)
                   if not (a <= m.start() < z)]
        if outside:
            fail.append('%d mentions of check_readonly are outside readfile()'
                        % len(outside))

# `"write"` is the 'write' option's name, and E32 is still reachable.
for lit, want in (('"write"', 1), ('E32: No file name', 1)):
    k = new.count(lit)
    if k != want:
        fail.append('%r occurs %d times and must occur %d: it is not this phase\'s'
                    % (lit, k, want))

# The three option globals that lose their last readers keep their rows: the
# options phase is what removes a row, and tools/orphanopts.py refuses a global
# whose row has gone (tools/zerodelta.sh runs it).
for opt in ('p_fs', 'p_write', 'p_wa'):
    k = count(new, opt)
    if k != 2:
        fail.append('%s has %d mentions, expected 2 -- its definition and its '
                    'option row, which are the options phase\'s to take' % (opt, k))

# The struct field the sweep took, and the one name that keeps its spelling.
if count(new, 'append') != 1 or '[CMD_append]' not in new:
    fail.append('exarg_T.append is not the only `append` left (%d), or the '
                ':append row went' % count(new, 'append'))

# What this phase deliberately leaves to the phases after it.
for kept in ('check_changed', 'no_write_message', 'do_bang', 'check_fname',
             'setfname', 'otherfile', 'fix_fname', 'readfile', 'b_ffname'):
    if not count(new, kept):
        fail.append('%s went, and it is a later phase\'s' % kept)

# The table.
rows = re.findall(r'^    \[CMD_\w+\] = \{.*$', new, re.M)
got = create_cmdidxs.names(sys.argv[1])
if len(rows) != 105 or len(got) != 105:
    fail.append('cmdnames[] has %d rows and names() reads %d; both must be 105'
                % (len(rows), len(got)))
for name in ('write', 'wq', 'xit', 'exit', 'update', 'saveas'):
    if name in got:
        fail.append(':%s is still a command name' % name)
if 'static_assert(sizeof(cmdnames) / sizeof(cmdnames[0]) == CMD_SIZE' not in new:
    fail.append('the static_assert on the row count went, and it is what catches '
                'an enumerator removed without its row')

# The libc the write side reached, counted in OCCURRENCES: stat( appears more than
# once on a line.  The symbol itself is the stdin phase's and stays (see below).
n_old, n_new = len(re.findall(r'\bstat\(', old)), len(re.findall(r'\bstat\(', new))
if (n_old, n_new) != (14, 8):
    fail.append('stat( is called %d times and was %d; expected 14 -> 8' % (n_new, n_old))

if fail:
    for line in fail:
        print('  %-12s %s' % (TAG, line))
    print('  %-12s a "no mention anywhere" check fails on a correct phase here:' % '')
    print('  %-12s check_readonly is a local in readfile(), and "write" is an' % '')
    print('  %-12s option name.  Both are measured, not assumed.' % '')
    sys.exit(1)
print('  %-12s kept: check_readonly as readfile()\'s local (4 mentions), "write" as '
      "the option's name, E32 through check_fname, p_fs/p_write/p_wa at their rows" % TAG)
print('  %-12s table: 105 rows, names() reads 105, static_assert in place, '
      '5 rows above create_cmdidxs\'s floor of 100' % TAG)
print('  %-12s stat( 14 -> 8 calls' % TAG)
PY

# --- 3. the compile, the linkage and the libc surface -------------------------------
# SIX SYMBOLS GO, stated as a set rather than a count: this is the first zero phase
# that frees any, and ZERO-GOAL.md measures exactly this number.  The five that a
# later phase owns are required to be STILL undefined, so a cut that reached past
# this phase's boundary fails here rather than quietly widening.
cp "$state/symbols/undefined" "$tmp/before.u"
tools/phasecheck.sh "$work" "$f" "$state/symbols"
comm -23 "$tmp/before.u" .cache/symbols/last/undefined > "$tmp/gone"
comm -13 "$tmp/before.u" .cache/symbols/last/undefined > "$tmp/came"
printf '%s\n' chmod fchmod fstat ftruncate lstat unlink | sort > "$tmp/want"
if ! cmp -s "$tmp/gone" "$tmp/want" || [ -s "$tmp/came" ]; then
    echo "  nowrite      the libc surface is not what this phase frees:"
    echo "               gone: $(tr '\n' ' ' < "$tmp/gone")"
    echo "               came: $(tr '\n' ' ' < "$tmp/came")"
    echo "               expected exactly: chmod fchmod fstat ftruncate lstat unlink"
    exit 1
fi
for keep in stat open access fsync getcwd; do
    grep -qx "$keep" .cache/symbols/last/undefined \
        || { echo "  nowrite      $keep is gone, and it is a later phase's: stat and getcwd go with the buffer's name, open and access with readfile, fsync with the options"; exit 1; }
done
echo "  nowrite      symbols $(cat .cache/symbols/last/before) -> $(cat .cache/symbols/last/after): exactly chmod fchmod fstat ftruncate lstat unlink, and stat/open/access/fsync/getcwd still needed"

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

# --- 5. the probes, in a directory they keep -----------------------------------------
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

TAG = 'nowrite'
ESC, CR = b'\x1b', b'\r'
QUIT = ESC + b':q!' + CR
old_bin, new_bin = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])


def record(binary, args, keys, timeout=10):
    """tools/zstream.py's session, except that the run directory is LOOKED IN.

    Everything else is that tool's, and for its reasons: the binary is staged as
    `vim` because argv[0] decides what the editor is, the environment is emptied so
    that no vimrc is found, and the session is its own so that a stop signal cannot
    reach this shell.
    """
    vim = zstream.stage(binary)     # argv[0], and the copy race: tools/zstream.py
    home = tempfile.mkdtemp(prefix='zero6-home-')
    env = dict(os.environ)
    env.update(TERM='xterm', HOME=home, VIM=os.path.join(home, 'novim'),
               VIMRUNTIME=os.path.join(home, 'novim'),
               XDG_CONFIG_HOME=os.path.join(home, 'xdg'))
    for k in ('LINES', 'COLUMNS', 'VIMINIT', 'EXINIT', 'MYVIMRC'):
        env.pop(k, None)
    d = tempfile.mkdtemp(prefix='zero6-run-')
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
    scr = zscreen.Screen(24, 80)
    scr.feed(out)
    left = {n: os.path.getsize(os.path.join(d, n))
            for n in sorted(os.listdir(d)) if n != 'keys'}
    shutil.rmtree(d, ignore_errors=True)
    text = zrec.section('exit %s' % rc)
    text += zrec.section('bells %d' % scr.bells)
    text += zrec.section('files %r' % left)
    text += zrec.section('stream %d sha=%s' % (len(out), hashlib.sha256(out).hexdigest()[:16]))
    text += zrec.section('stderr', err.decode('utf-8', 'replace').rstrip('\n'))
    for i, (dump, y, x, bells) in enumerate(scr.snaps):
        text += zrec.section('snap %d cursor=%d,%d bells=%d' % (i, y, x, bells), dump)
    return zrec.scrub(text), left


def typed(seed, *keys):
    """tools/zcases.py's shape: type the seed under 'paste', then the real keys."""
    return (['+set paste'], [b'i' + seed + ESC, b':set nopaste' + CR] + list(keys) + [QUIT])


def unquit(seed, *keys):
    """The same, for a command that is meant to quit by itself."""
    return (['+set paste'], [b'i' + seed + ESC, b':set nopaste' + CR] + list(keys))


HELLO = b'hello'

# name, (args, keys), must-differ
PROBES = [
    # --- writing, which is the whole phase and which no recorded case can see ---
    # The round trip is the one probe that proves the bytes reached a disk and came
    # back.  It leans on `:read`, which the next phase removes; that is harmless,
    # because make zero-verify runs this check on its own boundary and no later one.
    ('write_roundtrip', typed(b'WROTEME', b':w out.txt' + CR, b':%d' + CR,
                              b':r out.txt' + CR), True),
    ('w_named',        typed(HELLO, b':w out.txt' + CR),                True),
    ('sav_named',      typed(HELLO, b':sav out.txt' + CR),             True),
    ('up_named',       typed(HELLO, b':update out.txt' + CR),          True),
    ('wq_named',       unquit(HELLO, b':wq out.txt' + CR),             True),
    ('x_named',        unquit(HELLO, b':x out.txt' + CR),              True),
    # --- the inheritance check: eight spellings, each E492 now and not before ---
    ('w_bare',         typed(HELLO, b':w' + CR),                       True),
    ('x_bare',         typed(HELLO, b':x' + CR),                       True),
    ('wq_bare',        typed(HELLO, b':wq' + CR),                      True),
    ('up_bare',        typed(HELLO, b':up' + CR),                      True),
    ('sav_a',          typed(HELLO, b':sav a' + CR),                   True),
    ('w_bang',         typed(HELLO, b':w!' + CR),                      True),
    ('w_append',       typed(HELLO, b':w >>f' + CR),                   True),
    ('w_filter',       typed(HELLO, b':w !cat' + CR),                  True),
    # --- the two corpus cases this phase declares, run directly ---
    ('cmd_write',      typed(b'x', b':write' + CR),                    True),
    ('zz_key',         typed(b'x', b'ZZ'),                            True),
    # --- and everything that must not move ---
    ('quit_modified',  typed(HELLO, b':q' + CR),                       False),
    ('quit_bang',      unquit(HELLO, b':q!' + CR),                     False),
    ('cmd_edit',       typed(HELLO, b':edit' + CR),                    False),
    ('cmd_file',       typed(HELLO, b':file' + CR),                    False),
    ('cmd_read',       typed(HELLO, b':read' + CR),                    False),
    ('cmd_filter',     typed(b'b' + CR + b'a', b':%!sort' + CR),       False),
    ('cmd_subst',      typed(b'x', b':s/x/y/' + CR),                   False),
    ('key_undo',       typed(HELLO, b'x', b'u'),                       False),
    ('key_ctrl_g',     typed(HELLO, b'\x07'),                          False),
    ('editing',        typed(b'alpha' + CR + b'beta', b'0dwA-tail' + ESC, b'u', b'yyp'), False),
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

# THE SIX THAT WROTE A FILE.  Each is required to have left one on the OLD binary
# and none on the new: a probe that only looks at the new binary passes on a phase
# that did nothing.
for name in ('write_roundtrip', 'w_named', 'sav_named', 'up_named', 'wq_named', 'x_named'):
    (o, ofiles), (n, nfiles) = by[name]
    want = 8 if name == 'write_roundtrip' else 6
    if ofiles != {'out.txt': want}:
        fail.append('%s: the input binary left %r, not a %d-byte out.txt, so this '
                    'proves nothing about writing' % (name, ofiles, want))
    if nfiles:
        fail.append('%s: the new binary left %r on the disk' % (name, nfiles))
(o, _), (n, _) = by['write_roundtrip']
if '1L, 8B' not in o:
    fail.append('write_roundtrip: the input binary did not read its own file back')
if "E484: Can't open file out.txt" not in n:
    fail.append('write_roundtrip: the new binary found something to read back')
for name in ('wq_named', 'x_named'):
    (o, _), (n, _) = by[name]
    if 'exit 0' not in o or 'exit 1' not in n:
        fail.append('%s: the exit status did not go 0 -> 1' % name)
(o, ofiles), (n, nfiles) = by['sav_a']
if ofiles != {'a': 6}:
    fail.append('sav_a: the input binary left %r, not a 6-byte `a`' % ofiles)

# THE INHERITANCE CHECK: every spelling answers E492 now, and none did before.
# `:w` becoming `:winsize` would be invisible to everything else here.
for name in ('w_bare', 'x_bare', 'wq_bare', 'up_bare', 'sav_a', 'w_bang',
             'w_append', 'w_filter', 'w_named', 'sav_named', 'up_named',
             'wq_named', 'x_named', 'cmd_write'):
    (o, _), (n, _) = by[name]
    if E492 in o:
        fail.append('%s already answered E492 before this phase, so it proves nothing' % name)
    if E492 not in n:
        fail.append('%s does not answer E492: a removed name has been inherited' % name)

# THE TWO DECLARED CASES, which the delta says moved and which this says HOW.
(o, _), (n, _) = by['cmd_write']
if 'E32: No file name' not in o or 'E32: No file name' in n:
    fail.append('cmd_write: E32 was to be the old answer and to be gone now')
(o, _), (n, _) = by['zz_key']
if 'bells 1' not in o or 'bells 0' not in n:
    fail.append('zz_key: ZZ rang once before and must ring not at all now')
if 'E32: No file name' not in o:
    fail.append('zz_key: ZZ did not run :x on the input binary, so this proves nothing')
if E492 in n:
    fail.append('zz_key: ZZ still names a command that does not exist')
if 'exit 0' not in n:
    fail.append('zz_key: ZZ no longer quits')

# The ones that must not move are required to be DOING something, not failing alike.
(o, _), (n, _) = by['quit_modified']
if 'E37: No write since last change' not in n:
    fail.append('quit_modified: :q no longer refuses on a modified buffer, and that '
                'is the :q phase\'s to change')
# `:read` still IS a command -- it answers E32 for want of a file name, exactly as
# `:write` did before this phase, and taking it is the read phase's (ZERO-PLAN.md P6).
(o, _), (n, _) = by['cmd_read']
if 'E32: No file name' not in n or E492 in n:
    fail.append('cmd_read: `:read` is no longer a command, and it is the read phase\'s')
(o, _), (n, _) = by['editing']
if 'alpha' not in n:
    fail.append('editing: an ordinary edit no longer draws its text')

if fail:
    for line in fail:
        print('  %-12s %s' % (TAG, line))
    print('  %-12s the corpus cannot see writing -- every case types `:write` with' % '')
    print('  %-12s no file name and records E32.  These are the only probes that' % '')
    print('  %-12s can tell a removed command from a changed message.' % '')
    sys.exit(1)
print('  %-12s probes: %d moved (%s), %d unchanged' % (TAG, len(moved), ' '.join(moved), len(static)))
print('  %-12s six wrote a file on the input binary and none does now; eight '
      'spellings of :w answer E492 and none did before' % '')
PY

# --- 6. a real terminal, which is where `:wq` is how a person leaves ------------------
python3 - "$state/old" "$bin" <<'PY'
import os, sys, tempfile
sys.path.insert(0, 'tools')
import ptyrun
TAG = 'nowrite'
home = tempfile.mkdtemp(prefix='zero6-home-')
env = dict(os.environ, HOME=home, VIM=os.path.join(home, 'novim'),
           VIMRUNTIME=os.path.join(home, 'novim'),
           XDG_CONFIG_HOME=os.path.join(home, 'xdg'))
for k in ('VIMINIT', 'EXINIT', 'MYVIMRC'):
    env.pop(k, None)


def session(binary, keys):
    d = tempfile.mkdtemp(prefix='zero6-pty-')
    text, status = ptyrun.session(binary, [], keys, term='xterm', cwd=d,
                                  settle=0.6, env=env)
    left = sorted(n for n in os.listdir(d))
    return text.decode('utf-8', 'replace'), status, left, d


# `:wq out.txt` on a pty.  On the input binary it writes and quits; on this one it
# is E492, the editor is still there, and `:q!` is what ends the session -- which is
# exactly why pipes/zero2-check.sh, which drives a pty with `:wq` and asserts the
# file, is `apart 2 6` in pipes/zero.stages.
wq = [session(b, [b'ityped on a terminal\x1b', b':wq out.txt\r', b':q!\r'])
      for b in (sys.argv[1], sys.argv[2])]
if 'out.txt' not in wq[0][2]:
    sys.exit('  %-12s the input binary wrote nothing on a pty, so this proves nothing' % TAG)
if 'out.txt' in wq[1][2]:
    sys.exit('  %-12s the new binary wrote out.txt on a pty' % TAG)
if 'E492' not in wq[1][0]:
    sys.exit('  %-12s `:wq` on a pty did not answer E492 on the new binary' % TAG)

# And an ordinary editing session, which must be identical on both.
edit = [session(b, [b'ityped here\x1b', b'0dw', b':set ruler?\r', b':q!\r'])
        for b in (sys.argv[1], sys.argv[2])]
if 'here' not in edit[0][0] or 'ruler' not in edit[0][0]:
    sys.exit('  %-12s the editing pty session did not edit on the input binary' % TAG)
if edit[0][:3] != edit[1][:3]:
    sys.exit('  %-12s the editing pty session moved: %r -> %r'
             % (TAG, edit[0][1], edit[1][1]))
print('  %-12s pty: `:wq` wrote the file on the input binary and answers E492 here; '
      'the editing session identical either side' % TAG)
PY
