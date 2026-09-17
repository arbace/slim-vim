#!/bin/sh
# Zero phase 9, the check -- nothing in the editor reads a byte any more.
# See pipes/zero9-edit.sh, and ZERO-GOAL.md.
#
# Usage: pipes/zero9-check.sh <work-dir> <state-dir>     (run from the repository root)
#
# Runs after pipes/zero9-edit.sh and the sweep tools/phaserun.sh runs between them,
# and reads nothing from the edit's shell -- only the work tree and the state
# directory.  What the edit left there is `old`, the binary this phase was HANDED,
# and `old.c`, the source it was built from: the left-hand side of every
# before-and-after count, and the thing this check builds twice more.
#
# THE HONEST PROBLEM, AND WHAT IS DONE ABOUT IT.  There is no behavioural probe for
# this phase, and no dishonest one is offered instead.  `readfile()` was ALREADY
# unreachable when the phase was handed the tree -- phases 5 through 8 took the
# file argument, the bare `-`, and every command that could name a file -- so
# nothing this editor can be given reached it before the cut either, and every
# recording is byte-identical across the phase BY CONSTRUCTION.  A probe that
# "moved" would mean the phase was wrong.
#
# So the evidence is an INSTRUMENTED PAIR, built from the source the phase was
# handed, and it is the whole of what this phase can prove:
#
#   probe   old.c with `(void)write(2, "READFILE-ENTERED\n", 17);` as readfile()'s
#           first statement.  Recorded with tools/zrecord.sh: ZERO of the 106
#           records may carry the marker.  That is the claim -- on the binary this
#           phase was handed, nothing the instrument can do enters readfile().
#   ctl     old.c with the IDENTICAL instrument in open_buffer(), which IS reached.
#           104 of the same 106 records carry it.  That is the proof the probe can
#           fail: a marker written from a function the editor calls does arrive, in
#           the same recording, through the same grep.
#
# The two that do not carry it under `ctl` are ref-pty.txt and ref-term.txt, and
# the reason is the instrument and not the editor: both drive a real pty and keep
# what was DRAWN, where the other three keep stderr separately.  They are named
# here so that a third one going quiet would be a failure rather than a shrug.
#
# EIGHT ADVERSARIAL SESSIONS run on both instrumented binaries, and they are the
# part that asks whether anything could still get in: `:file /etc/hostname` and
# then `G`, an insert and an undo, `:bdelete`, `:new`, `:ball`, `:buffer 1`, and
# the `%` and `#` registers.  Naming a buffer after a real file that exists and
# then making the editor want its contents is the shape of every way back into
# `readfile()` there was.  Each must mark under `ctl` and must not under `probe`:
# a session that reaches neither proves nothing, and that is checked.
#
# AND THE RECORDINGS ARE COMPARED DIRECTLY, old binary against new, rather than
# only through .reference/zero-baselines: `diff -rq` over two full tools/zrecord.sh
# recordings, which is what "this phase declares nothing at all" means measured
# between the two binaries themselves.  tools/zerodelta.sh runs afterwards and says
# the same thing against whim-vim's frozen behaviour.
#
# SIX THINGS THE SOURCE MUST SAY, and the traps that make the obvious check wrong,
# are in sections 1 and 2.
set -eu

work=${1:?usage: zero9-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero9-check.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"
before_lines=$(cat "$state/input-lines")

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# The two instrumented builds are started first and waited for in section 6: they
# are three and a half seconds each of wall time that the source checks below can
# be spending instead.  The flags are the boundary's, as everywhere (rule 8).
cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")
mkdir -p "$tmp/i"
python3 - "$state/old.c" "$tmp/i" <<'PY'
import sys
src, out = sys.argv[1], sys.argv[2]
MARK = '    (void)write(2, "READFILE-ENTERED\\n", 17);\n'
t = open(src, errors='surrogateescape').read()
for fn, name in (('readfile', 'probe.c'), ('open_buffer', 'ctl.c')):
    heads = [l for l in t.split('\n') if l.startswith(fn + '(')]
    if len(heads) != 1:
        sys.exit('  %-12s %s is not one definition head in the input source'
                 % ('nobyte', fn))
    head = heads[0] + '\n{\n'
    if t.count(head) != 1:
        sys.exit('  %-12s %s does not open exactly once in the input source'
                 % ('nobyte', fn))
    open('%s/%s' % (out, name), 'w', errors='surrogateescape').write(
        t.replace(head, head + MARK))
PY
# shellcheck disable=SC2086
( cd "$tmp/i" && gcc $cflags $ldflags -o probe probe.c ) &
pid_probe=$!
# shellcheck disable=SC2086
( cd "$tmp/i" && gcc $cflags $ldflags -o ctl ctl.c ) &
pid_ctl=$!

# --- 1. what the sweep took, recorded -----------------------------------------------
# SIXTEEN FUNCTIONS, none of them named by the edit.  Listing them here is a
# RECORDING of what the sweep did, which is the only place a list of removed names
# belongs (ZERO-GOAL.md rule 1).  The edit named four anchors, all inside
# open_buffer(), and `readfile` is 787 lines of the 1,183 that went.
for gone in readfile read_buffer read_eintr readfile_linenr filemess \
            msg_add_fname msg_add_lines msg_add_eol after_pathsep \
            dir_of_file_exists fix_help_buffer gettail_sep mch_isdir \
            set_rw_fname u_find_first_changed utf_ptr2len_len \
            read_stdin read_fifo check_readonly \
            READ_NEW READ_STDIN READ_BUFFER READ_FIFO READ_FILTER READ_NOFILE \
            READ_KEEP_UNDO READ_DUMMY; do
    n=$(grep -cw -- "$gone" "$f" || true)
    [ "$n" = 0 ] || { echo "  nobyte       '$gone' still has $n mentions"; exit 1; }
done
echo "  nobyte       sixteen functions, read_stdin, read_fifo, check_readonly and the eight READ_ enumerators at 0 mentions -- all of it the sweep's, the edit named none of them"

# --- 2. the source, in both directions ----------------------------------------------
python3 - "$f" "$state/old.c" <<'PY'
import re, sys
sys.path.insert(0, 'tools')
import create_cmdidxs
import cutil
TAG = 'nobyte'
new = open(sys.argv[1], errors='surrogateescape').read()
old = open(sys.argv[2], errors='surrogateescape').read()
fail = []


def count(text, name):
    return len(re.findall(r'\b%s\b' % name, text))


# THE TWENTY-FOUR STRING LITERALS the message layer was the last to say.  filemess(),
# msg_add_fname(), msg_add_lines() and msg_add_eol() are the whole of what printed
# `"keys" [noeol] 1L, 30B` after a read, and the last thing that could reach them was
# `:read`/`:edit`, which phases 7 and 8 took.
GONE_STRINGS = [
    '"%s%ldL, %lldB"', '"%s%ld line, "', '"%s%ld lines, "', '"%lld byte"',
    '"%lld bytes"', '"[noeol]"', '"[READ ERRORS]"', '"[New DIRECTORY]"',
    '"[Incomplete last line]"', '"[long lines split]"', '"[ILLEGAL BYTE in line %ld]"',
    '"[File too big]"', '"[Permission Denied]"', '"[fifo]"', '"[socket]"',
    '"is a directory"', '"is not a file"', '"Illegal file name"', '"-stdin-"',
    '"Vim: Reading from stdin...\\n"', '"\\" "',
    '"E200: *ReadPre autocommands made the file unreadable"',
    '"E201: *ReadPre autocommands must not change current buffer"',
    '"E812: Autocommands changed buffer or buffer name"',
]
still = [s for s in GONE_STRINGS if s in new]
if still:
    fail.append('%d of the 24 strings the message layer was the last to say are '
                'still here: %s' % (len(still), ' '.join(still[:4])))
missing = [s for s in GONE_STRINGS if s not in old]
if missing:
    fail.append('the input did not say %s, so this phase is being checked against '
                'a file it was not written for' % ' '.join(missing[:4]))

# AND THE OTHER DIRECTION, which is where a copied "no mention anywhere" loop fails.
# `"[RO]"` and `"[readonly]"` each lose ONE speaker -- readfile's -- and keep the
# rest; CTRL-G's counter is fileinfo's and is not readfile's at all.
for lit, want in (('"[RO]"', 2), ('"[readonly]"', 1), ('"%ld line --%d%%--"', 1)):
    if new.count(lit) != want:
        fail.append('%s occurs %d times, expected %d -- readfile was one speaker '
                    'of the first two and none of the third' % (lit, new.count(lit), want))

# THE BARE WORDS, each with the reason it is not this phase's.  A loop that wanted
# zero for any of these would fail on a correct phase.
KEPT = {'open_buffer': 5,        # the definition and four callers, now open_buffer()
        'read_cmd_fd': 12,       # the terminal's, on 11 lines: fill_input_buf, mch_settmode
        'b_ffname': 32,          # 43 before: the buffer's name is phase 10's
        'b_fname': 29,           # 37 before, same reason
        'b_sfname': 26,          # untouched
        'setfname': 2,           # 3 before: set_rw_fname was its second caller
        'check_fname': 3,        # E32's speaker, and reachable
        'readonlymode': 3,       # 5 before -- readfile held two.  Phase 8 asserted 5
        'msg_scrolled_ign': 2,   # a declaration and one reader; see below
        'b_mtime_read': 3, 'b_mtime_read_ns': 3,   # write-only now; phase 10's
        'b_orig_size': 3, 'b_orig_mode': 3,
        'buf_store_time': 3,     # 4 before: readfile was one of its two callers
        'set_b0_fname': 4,       # the other writer of those fields
        'ml_open': 3,            # open_buffer still calls it, and must
        'p_ur': 2,               # 'undoreload', still the options phase's
        'check_changed': 4,      # E37 still refuses: the :q phase's
        'nv_error': 46,          # the 'Q' row phase 4 pointed here
        'secure': 11,            # the vimrc flag, not check_secure (phase 7's trap)
        'eval_vars': 4, 'expand_filename': 3, 'fix_fname': 3,
        'vim_FullName': 3, 'mch_FullName': 3, 'mch_dirname': 5}
for name, want in sorted(KEPT.items()):
    k = count(new, name)
    if k != want:
        fail.append('%s has %d mentions, expected %d -- %s'
                    % (name, k, want, 'this phase reached too far'
                       if k < want else 'something survived that should not have'))

# msg_scrolled_ign IS A LEFTOVER AND IS NAMED AS ONE.  It had four writers, all of
# them inside filemess() and readfile(), and one reader.  After this phase it is
# FALSE for ever with the reader still testing it, and NOTHING SEES THAT: gcc has no
# warning for a variable that is only read, tools/deadsweep.py removes what is
# unused rather than what is constant, and deadfields.py is about struct members.
# So it is asserted at 2 mentions, read-only, and handed on rather than folded here.
writes = re.findall(r'\bmsg_scrolled_ign\b\s*=', new)
if len(writes) != 1 or 'static int      msg_scrolled_ign  = FALSE ;' not in new:
    fail.append('msg_scrolled_ign is assigned %d times: after this phase the only '
                'one left must be its initialiser, FALSE' % len(writes))
span = cutil.find_definition(new, 'msg_puts_attr_len')
if not span or 'msg_scrolled_ign' not in new[span[0]:span[1]]:
    fail.append('msg_puts_attr_len no longer reads msg_scrolled_ign, and this phase '
                'removed its writers and not its reader')

# THE FOUR FIELDS THAT BECOME WRITE-ONLY, and why no tool here can take them.
# tools/deadfields.py removes a field nothing NAMES; these are still named, by the
# writes in buf_store_time() and set_b0_fname().  Nothing reads any of them now, and
# they go with the buffer's name in phase 10.
for fld in ('b_mtime_read', 'b_mtime_read_ns', 'b_orig_size', 'b_orig_mode'):
    reads = [m for m in re.finditer(r'\b%s\b' % fld, new)
             if not re.match(r'\s*=[^=]', new[m.end():m.end() + 3])]
    decl = re.search(r'^    \w+[ \t]+%s;$' % fld, new, re.M)
    if not decl:
        fail.append('%s is no longer a field of buf_T, and this phase leaves it '
                    'write-only rather than removing it' % fld)
    if len(reads) != 1:
        fail.append('%s is read %d times outside an assignment; after this phase '
                    'every mention but the declaration must be a write'
                    % (fld, len(reads) - 1))

# E32 STAYS, and it is the message a later phase's probe looks for.
if new.count('E32: No file name') != 1:
    fail.append('E32: No file name went, and it is reachable through check_fname()')
if 'E37: No write since last change' not in new:
    fail.append("E37 went, and check_changed() is the :q phase's")
for kept in ('open_buffer', 'ml_open', 'buflist_new', 'do_one_cmd', 'nv_g_cmd',
             'msg_puts_attr_len', 'fileinfo', 'get_spec_reg'):
    if not count(new, kept):
        fail.append('%s went, and it is a later phase\'s or this phase only cut '
                    'inside it' % kept)

# THE TABLE DID NOT MOVE.  No cmdnames[] row and no enumerator of enum CMD_index is
# touched here -- this phase deletes no command -- so the count is the same 99 phase
# 8 left, and the floor it lowered to 80 has its 19 rows of margin still.
rows = re.findall(r'^    \[CMD_\w+\] = \{.*$', new, re.M)
got = create_cmdidxs.names(sys.argv[1])
# THE FLOOR, ASSERTED BY USING IT rather than by grepping for the number.  Phase 8
# lowered it from 100 to 80 in the commit that took the table under 100, and this is
# the checked call that refuses below it: 99 rows must still clear the bar.
try:
    create_cmdidxs.names_from_cmdnames(sys.argv[1])
except SystemExit as e:
    fail.append('the checked parser refuses this table -- the row floor is no '
                'longer below 99: %s' % e)
if len(rows) != 99 or len(got) != 99:
    fail.append('cmdnames[] has %d rows and names() reads %d; both must be 99, '
                'unchanged: this phase removes no command' % (len(rows), len(got)))
if len(re.findall(r'^    \[CMD_\w+\] = \{.*$', old, re.M)) != 99:
    fail.append('the input does not have 99 rows, so this is not the file this '
                'phase was written against')
if 'static_assert(sizeof(cmdnames) / sizeof(cmdnames[0]) == CMD_SIZE' not in new:
    fail.append('the static_assert on the row count went, and it is what catches '
                'an enumerator removed without its row')
for name in ('file', 'quit', 'print', 'append', 'registers'):
    if name not in got:
        fail.append(':%s went, and no command is this phase\'s' % name)

# What the sixteen functions cost the old file, as a difference rather than a
# number: the input must be the file this phase was written against.
for name, want in (('readfile', 5), ('read_buffer', 17), ('open_buffer', 5),
                   ('read_stdin', 23), ('check_readonly', 4), ('readonlymode', 5)):
    if count(old, name) != want:
        fail.append('the input is not the file this phase was written against: '
                    '%s %d, expected %d' % (name, count(old, name), want))

if fail:
    for line in fail:
        print('  %-12s %s' % (TAG, line))
    print('  %-12s a "no mention anywhere" check fails on a correct phase here:' % '')
    print('  %-12s check_readonly was readfile\'s LOCAL and reaches 0 only now,' % '')
    print('  %-12s readonlymode goes 5 -> 3 where phase 8 asserted 5, "[RO]" and' % '')
    print('  %-12s "[readonly]" each keep a speaker, and read_cmd_fd is the' % '')
    print('  %-12s terminal\'s and does not move at all.' % '')
    sys.exit(1)
print('  %-12s the 24 strings gone and "[RO]" 3 -> 2, "[readonly]" 2 -> 1 and '
      "CTRL-G's counter kept: readfile was one speaker of the first two and none "
      'of the third' % TAG)
print('  %-12s kept: open_buffer 5, read_cmd_fd 12 on 11 lines (the terminal\'s), '
      'b_ffname 32 and b_fname 29 (phase 10\'s), setfname 2 (set_rw_fname was its '
      'second caller), E32 and E37 with their speakers' % '')
print('  %-12s left and named rather than folded: msg_scrolled_ign at 2 mentions, '
      'FALSE for ever with one reader in msg_puts_attr_len, and b_mtime_read, '
      'b_mtime_read_ns, b_orig_size and b_orig_mode write-only -- phase 10\'s' % '')
print('  %-12s table: 99 rows and names() reads 99, unchanged -- this phase '
      'removes no command, and the floor keeps its 19 rows of margin' % '')
PY

# --- 3. the compile, the linkage and the libc surface -------------------------------
# THREE SYMBOLS GO AND THE SET IS NAMED, not the count.  `access`, `fcntl` and
# `open` were readfile()'s and nothing else's.  `read`, `close` and `dup` STAY and
# are the terminal's alone -- fill_input_buf() and mch_settmode() -- which is why a
# check that read "the file symbols went" would be wrong here.  `stat`, `getcwd` and
# `strerror` are phase 10's and `fsync` the FILE* phase's: ZERO-PLAN row 9 lists
# fsync under the name phase and is corrected there, its only caller being ui_write.
cp "$state/symbols/undefined" "$tmp/before.u"
tools/phasecheck.sh "$work" "$f" "$state/symbols"
comm -23 "$tmp/before.u" .cache/symbols/last/undefined > "$tmp/gone.u"
comm -13 "$tmp/before.u" .cache/symbols/last/undefined > "$tmp/came.u"
printf 'access\nfcntl\nopen\n' > "$tmp/want.u"
if ! cmp -s "$tmp/gone.u" "$tmp/want.u" || [ -s "$tmp/came.u" ]; then
    echo "  nobyte       the libc surface did not move by exactly access, fcntl and open:"
    echo "               gone: $(tr '\n' ' ' < "$tmp/gone.u")"
    echo "               came: $(tr '\n' ' ' < "$tmp/came.u")"
    exit 1
fi
for keep in stat getcwd strerror fsync read close dup; do
    grep -qx "$keep" .cache/symbols/last/undefined \
        || { echo "  nobyte       $keep went, and it is not this phase's: read, close and dup are the terminal's, stat, getcwd and strerror are phase 10's, fsync the FILE* phase's"; exit 1; }
done
echo "  nobyte       symbols $(cat .cache/symbols/last/before) -> $(cat .cache/symbols/last/after), and the set is exactly access fcntl open; read close dup stat getcwd strerror fsync all still undefined"

# --- 4. the enumerators, before and after -------------------------------------------
# SEVENTEEN GO AND NOTHING RENUMBERS, which is the opposite of phase 8 and is worth
# the four seconds either side to say.  typereach.py deletes seventeen whole
# anonymous enum definitions -- the eight READ_ flags and nine single-constant
# enums -- and a whole definition leaving takes no survivor's value with it.  The
# dump is what turns that from an argument into a measurement.
tools/enumvals.sh "$state/old.c" "$tmp/ev.old" &
pid_ev=$!
tools/enumvals.sh "$f" "$tmp/ev.new"
wait $pid_ev
python3 - "$tmp/ev.old" "$tmp/ev.new" <<'PY'
import sys
TAG = 'nobyte'
o = dict(l.rsplit('=', 1) for l in open(sys.argv[1]).read().splitlines())
n = dict(l.rsplit('=', 1) for l in open(sys.argv[2]).read().splitlines())
gone, came = sorted(set(o) - set(n)), sorted(set(n) - set(o))
moved = sorted(k for k in set(o) & set(n) if o[k] != n[k])
WANT = sorted(['READ_NEW', 'READ_STDIN', 'READ_BUFFER', 'READ_FIFO', 'READ_FILTER',
               'READ_NOFILE', 'READ_KEEP_UNDO', 'READ_DUMMY', 'BF_NEW_W',
               'CONV_RESTLEN', 'CPO_FNAMER', 'NOTDONE', 'O_EXTRA', 'SHM_LAST',
               'SHM_LINES', 'SHM_OVER', 'SHM_OVERALL'])
if gone != WANT or came or moved:
    if gone != WANT:
        print('  %-12s enumerators gone: %s' % (TAG, ' '.join(gone)))
        print('  %-12s expected exactly: %s' % ('', ' '.join(WANT)))
    if came:
        print('  %-12s enumerators arrived: %s' % (TAG, ' '.join(came)))
    if moved:
        print('  %-12s enumerators moved value, and none may: %s'
              % (TAG, ' '.join(moved)))
    sys.exit(1)
print('  %-12s enumerators %d -> %d: 17 whole anonymous definitions gone, NOT ONE '
      'survivor renumbered and none arriving -- no parallel table can have shifted'
      % (TAG, len(o), len(n)))
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

# --- 6. the instrumented pair, which is the whole of this phase's evidence -----------
wait $pid_probe || { echo "  nobyte       the readfile() probe did not build"; exit 1; }
wait $pid_ctl   || { echo "  nobyte       the open_buffer() control did not build"; exit 1; }
tools/zrecord.sh "$tmp/i/probe" "$tmp/i/probe.c" "$tmp/REC.probe" >/dev/null &
pid_rp=$!
tools/zrecord.sh "$tmp/i/ctl" "$tmp/i/ctl.c" "$tmp/REC.ctl" >/dev/null &
pid_rc=$!
tools/zrecord.sh "$state/old" "$state/old.c" "$tmp/REC.old" >/dev/null &
pid_ro=$!
tools/zrecord.sh "$bin" "$f" "$tmp/REC.new" >/dev/null &
pid_rn=$!
rc=0
wait $pid_rp || rc=1
wait $pid_rc || rc=1
wait $pid_ro || rc=1
wait $pid_rn || rc=1
[ "$rc" = 0 ] || { echo "  nobyte       a harness failed on one of the four recordings"; exit 1; }

total=$(find "$tmp/REC.probe" -type f | wc -l)
marked=$(grep -rl 'READFILE-ENTERED' "$tmp/REC.probe" | wc -l)
cmarked=$(grep -rl 'READFILE-ENTERED' "$tmp/REC.ctl" | wc -l)
cquiet=$(grep -rL 'READFILE-ENTERED' "$tmp/REC.ctl" | sed "s|$tmp/REC.ctl/||" | sort | tr '\n' ' ')
if [ "$total" != 106 ]; then
    echo "  nobyte       a recording is $total files, not the 106 this phase counted"
    exit 1
fi
if [ "$marked" != 0 ]; then
    echo "  nobyte       $marked of $total records ENTERED readfile() on the binary this phase was handed:"
    grep -rl 'READFILE-ENTERED' "$tmp/REC.probe" | sed "s|^|               |"
    echo "               so this phase removes code that CAN run, and the cut is wrong"
    exit 1
fi
if [ "$cmarked" != 104 ] || [ "$cquiet" != "ref-pty.txt ref-term.txt " ]; then
    echo "  nobyte       the control marked $cmarked of $total records, quiet in: $cquiet"
    echo "               it must be 104, quiet only in ref-pty.txt and ref-term.txt,"
    echo "               which keep what was DRAWN on a pty and not stderr.  Without"
    echo "               that the zero above is a probe that cannot fail."
    exit 1
fi
echo "  nobyte       the instrumented pair: readfile() entered by 0 of $total records, open_buffer() by $cmarked of $total through the identical instrument -- that, and nothing else, is what says this phase removed code that could not run"

# The eight adversarial sessions, on both instrumented binaries.
python3 - "$tmp/i/probe" "$tmp/i/ctl" <<'PY'
import concurrent.futures
import sys
sys.path.insert(0, 'tools')
import zstream
TAG = 'nobyte'
ESC, CR = b'\x1b', b'\r'
QUIT = ESC + b':q!' + CR
PASTE = ['+set paste']
SEED = [b'ialpha' + ESC, b':set nopaste' + CR]
# NAMING A BUFFER AFTER A FILE THAT EXISTS is the shape of every way back into
# readfile() there was: `:file` sets b_ffname, and open_buffer()'s outer arm was
# `if (curbuf->b_ffname != NULL)`.  So each of these gives the buffer a real name
# and then asks the editor for something that used to load it.
NAMED = SEED + [b':file /etc/hostname' + CR]
SESSIONS = [
    ('file_then_G',   NAMED + [b'G', QUIT]),
    ('file_then_ins', NAMED + [b'ihi' + ESC, b'u', QUIT]),
    ('file_bdelete',  NAMED + [b':bdelete' + CR, QUIT]),
    ('file_reg_pct',  NAMED + [b'"%p', QUIT]),
    ('new_window',    SEED + [b':new' + CR, QUIT]),
    ('ball',          SEED + [b':ball' + CR, QUIT]),
    ('buffer_1',      SEED + [b':buffer 1' + CR, QUIT]),
    ('reg_hash',      SEED + [b'"#p', QUIT]),
]


def one(job):
    name, binary, keys = job
    try:
        scr, out, err, rc = zstream.session(binary, keys, args=PASTE)
    except zstream.Blocked:
        return name, binary, None, 0
    return name, binary, rc, err.count(b'READFILE-ENTERED')


probe, ctl = sys.argv[1], sys.argv[2]
jobs = [(n, b, k) for n, k in SESSIONS for b in (probe, ctl)]
with concurrent.futures.ThreadPoolExecutor(max_workers=len(jobs)) as ex:
    res = list(ex.map(one, jobs))
got = {}
fail = []
for name, binary, rc, marks in res:
    if rc is None:
        fail.append('%s blocked, so it says nothing either way' % name)
    got[(name, binary)] = marks
for name, _ in SESSIONS:
    p, c = got.get((name, probe)), got.get((name, ctl))
    if p:
        fail.append('%s entered readfile() %d times on the binary this phase was '
                    'handed' % (name, p))
    if not c:
        fail.append('%s never reached open_buffer() either, so it proves nothing: '
                    'a session that gets nowhere is not an adversary' % name)
if fail:
    for line in fail:
        print('  %-12s %s' % (TAG, line))
    sys.exit(1)
print('  %-12s eight adversarial sessions -- :file on a real file and then G, an '
      'insert and an undo, :bdelete, the %% register, :new, :ball, :buffer 1 and '
      'the # register -- each reached open_buffer() and not one reached readfile()'
      % TAG)
PY

# --- 7. the two recordings, compared directly ----------------------------------------
# WHAT "DECLARES NOTHING AT ALL" MEANS, measured between the two binaries themselves
# rather than only against .reference/zero-baselines: every one of the 102 screen
# cases, the 111 Ex-command rows, the 30 command lines, the four pty scenarios and
# the nineteen terminal rows, byte for byte.  tools/zerodelta.sh says the same thing
# against whim-vim's frozen behaviour immediately after this check returns.
if ! diff -rq "$tmp/REC.old" "$tmp/REC.new" > "$tmp/recdiff" 2>&1; then
    echo "  nobyte       the recording moved, and this phase declares nothing at all:"
    sed 's|^|               |' "$tmp/recdiff" | head -10
    exit 1
fi
echo "  nobyte       two full recordings, the binary this phase was handed and the one it made: identical, all $total records -- 102 screen cases, 111 command rows, 30 command lines, the pty and the terminal table"

# --- 8. and the ones that must not move are required to be DOING something -----------
# "It did not move" is two failures agreeing unless each side is shown to work.  The
# sessions here are the ones a phase that takes the read path would break first, and
# every one is required to be identical AND to show its own answer.
python3 - "$state/old" "$bin" <<'PY'
import concurrent.futures
import hashlib
import sys
sys.path.insert(0, 'tools')
import zrec
import zstream
TAG = 'nobyte'
ESC, CR = b'\x1b', b'\r'
QUIT = ESC + b':q!' + CR


def typed(seed, *keys):
    return (['+set paste'], [b'i' + seed + ESC, b':set nopaste' + CR] + list(keys) + [QUIT])


HELLO = b'hello'
# name, (args, keys), a string the NEW binary must still show
CASES = [
    ('editing',      typed(b'alpha' + CR + b'beta', b'0dwA-tail' + ESC, b'u', b'yyp'), 'alpha'),
    ('cmd_file',     typed(HELLO, b':file' + CR),                    '[No Name]'),
    ('ctrl_g',       typed(b'a' + CR + b'b', b'\x07'),               '[No Name]'),
    ('registers',    typed(HELLO, b'yy', b':registers' + CR),        None),
    ('reg_percent',  typed(HELLO, b'A ' + ESC + b'"%p' + ESC),       'hello'),
    ('reg_hash',     typed(HELLO, b'A ' + ESC + b'"#p' + ESC),       'hello'),
    ('quit_modified', typed(HELLO, b':q' + CR),                      'E37: No write since last change'),
    ('quit_bang',    (['+set paste'], [b'i' + HELLO + ESC, b':set nopaste' + CR, b':q!' + CR]), None),
]


def record(binary, args, keys):
    try:
        scr, out, err, rc = zstream.session(binary, keys, args=args)
    except zstream.Blocked:
        return 'BLOCKED', ''
    text = zrec.section('exit %s' % rc) + zrec.section('bells %d' % scr.bells)
    text += zrec.section('stream %d sha=%s'
                         % (len(out), hashlib.sha256(out).hexdigest()[:16]))
    text += zrec.section('stderr', err.decode('utf-8', 'replace').rstrip('\n'))
    for i, (dump, y, x, bells) in enumerate(scr.snaps):
        text += zrec.section('snap %d cursor=%d,%d bells=%d' % (i, y, x, bells), dump)
    return zrec.scrub(text), out.decode('utf-8', 'replace')


def one(c):
    name, (args, keys), want = c
    return name, record(sys.argv[1], args, keys), record(sys.argv[2], args, keys), want


with concurrent.futures.ThreadPoolExecutor(max_workers=len(CASES)) as ex:
    res = list(ex.map(one, CASES))
fail = []
for name, o, n, want in res:
    if o[0] != n[0]:
        fail.append('%s moved, and this phase declares nothing at all' % name)
    if want is not None and want not in n[0]:
        fail.append('%s: the new binary no longer shows %r, so "it did not move" is '
                    'two failures agreeing' % (name, want))
# `:registers` prints its table, a Press ENTER prompt follows and the redraw wipes
# it before the cursor comes back -- so it is in the STREAM and in no snapshot.
for name, o, n, _ in res:
    if name == 'registers' and ('Type Name Content' not in n[1]
                                or 'Type Name Content' not in o[1]):
        fail.append('registers: :registers printed no table, so "it did not move" '
                    'is two failures agreeing')
if fail:
    for line in fail:
        print('  %-12s %s' % (TAG, line))
    sys.exit(1)
print('  %-12s identical either side and each still doing its own work: an ordinary '
      'editing session, :file and CTRL-G (still [No Name]), :registers with its '
      'table, the %% and # registers, :q on a modified buffer (still E37) and :q!'
      % TAG)
PY
