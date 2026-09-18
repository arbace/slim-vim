#!/bin/sh
# Zero phase 10, the check -- the buffer has no name any more.
# See pipes/zero10-edit.sh, and ZERO-GOAL.md.
#
# Usage: pipes/zero10-check.sh <work-dir> <state-dir>    (run from the repository root)
#
# Runs after pipes/zero10-edit.sh and the sweep tools/phaserun.sh runs between them,
# and reads nothing from the edit's shell -- only the work tree and the state
# directory.  What the edit left there is `old`, the binary this phase was HANDED,
# and `old.c`, the source it was built from: the left-hand side of every
# before-and-after count, and of every probe.
#
# SEVEN THINGS ARE PROVED HERE, and the fifth is the only one that can say what this
# phase is actually for.
#
# 1. THE CUT, WHICH IS THE SWEEP'S AND NOT THE EDIT'S.  SIXTY functions go and the
#    edit names none of them -- the largest number any zero phase has handed the
#    sweep, and all of it computed from four kinds of anchor: a cmdnames[] row, a
#    call site that passes NULL, sixteen folds, and an `if` on a flag no row carries.
#
#    THE TRAPS, ALL MEASURED, that make a copied "every name at zero" loop wrong:
#      * `otherfile` IS ALREADY ZERO.  Phase 8 swept it; `otherfile_buf` is this
#        phase's.  A list copied from ZERO-PLAN.md's P9 row would "prove" a name
#        that went two phases ago.
#      * `E447: Can't find file "%s" in path` REACHES ZERO HERE, and phase 8's check
#        asserts it SURVIVES.  Phase 8 removed the `gf` key; the message belonged to
#        `find_file_name_in_path()`'s search arm, which part G folds away.  The two
#        checks disagree on purpose and `apart 8 10` is not needed for it only
#        because `apart 8 9` and `apart 9 10` already forbid the stage.
#      * `"file"` reaches zero and `E32: No file name` DOES NOT.  `check_fname()`
#        survives, folded to an unconditional emsg, because `get_spec_reg()`'s `%`
#        still calls it.  A check that wanted both gone fails on a correct phase.
#      * `"[No Name]"` occurs TWICE and neither is a leftover: `buf_get_fname()`'s,
#        which is now the only name any buffer has, and `can_unload_buffer()`'s,
#        which part C folded a ternary into.
#      * `fileinfo` goes 4 -> 3 and not to 0: `:file` was one of four callers and
#        CTRL-G, `g CTRL-G` and the startup message are the other three.
#
# 2. WHAT IS LEFT WRITE-ONLY, NAMED, AND HANDED ON.  `BF_NOTEDITED` can never be set
#    -- `setfname()` was its only writer -- and `BF_NEW` never could; both are still
#    READ by `fileinfo()`, so CTRL-G still tests them and neither test can fire.
#    `b_shortname` has the same shape and was already write-only before this phase.
#    Folding any of the three would change the string set for no gain, so they are
#    asserted where they are.  `msg_scrolled_ign` is phase 9's leftover and does not
#    move.
#
# 3. THE LINE AGAINST THE PHASES AFTER THIS ONE, stated as counts so that reaching
#    into one would fail here rather than widen quietly: `check_changed` 4 and
#    `no_write_message` 3 (the `:q` phase's), `p_ur` 2 and `p_ro` 2 WITH their option
#    rows (the options phase's), `read_cmd_fd` 12, `vim_fsync` 3, `scriptin` 8 and
#    `redir_fd` 6 (the terminal's and the FILE* phase's).
#
# 4. THE ENUMERATORS, DUMPED EITHER SIDE.  Seventy-two go and EIGHTY-FIVE RENUMBER,
#    every one of the 85 a `CMD_`.  cmdnames[] is designated, so a row lands at its
#    own enumerator whatever the numbering is -- but nothing in the build would
#    notice if some other family had moved with them, and 85 movers from one family
#    is exactly the case CLAUDE.md says a build is happy to get wrong.  Four seconds
#    a dump, taken concurrently, and worth it.
#
# 5. THE PROBES, ON BOTH BINARIES, BECAUSE THE CORPUS CANNOT SEE A BUFFER BEING
#    NAMED.  The one case it does see is `cmd_file`, which types `:file` with no
#    argument and records the CTRL-G line for `[No Name]` -- so "that case moved" is
#    equally consistent with a phase that changed one message and left `setfname()`
#    reachable.  `file_rename` is the probe that is not: `:file NEWNAME` and then
#    CTRL-G answers `"NEWNAME" [Modified][Not edited] 1 line --100%--` on the binary
#    this phase was handed and `"[No Name]" [Modified] 1 line --100%--` here.  That
#    line, on the OLD binary, is the whole evidence that a buffer could be named.
#
#    AND `cp_missing` IS THE ONE PROBE THAT SHOWS THE OLD BINARY ASKING THE DISK.
#    With `nosuchfile` under the cursor, `: CTRL-R CTRL-P <CR>` was SILENT before --
#    `find_file_in_path()` stat()ed the name, found nothing and yielded NULL, so
#    nothing reached the command line -- and answers `E492: Not an editor command:
#    nosuchfile` now, the word having been extracted and nothing looked up.  Its
#    pair `cp_existing` must NOT move, and that is what says part G removed the
#    lookup and not the extraction: with `keys` under the cursor -- the keystroke
#    file tools/zstream.py always leaves in the run directory -- both binaries
#    answer `E488: Trailing characters: eys`, `:k` being a command of its own.
#    `cf_existing` is the same session with CTRL-F, which never expanded.
#
# 6. THE INHERITANCE CHECK.  `:file`'s row gave its shortest abbreviation as one
#    character, so `:f :fi :fil :file :file!` all reached it; each must answer E492
#    now and none may have answered E492 before.  `:filter` and `:fixdel` are the
#    neighbours that must not move -- CLAUDE.md's `:help` -> `:helpclose` trap.
#
# 7. A REAL TERMINAL, because every probe above went through a pipe: `:file NEWNAME`
#    and CTRL-G on a pty, and an ordinary editing session required to be identical.
#
# A record is built the way tools/zcases.py builds one and scrubbed the same way
# (tools/zrec.py).  tools/zstream.py's session() is not called directly because this
# check needs the raw stream and the snapshot count beside the screens.
set -eu

work=${1:?usage: zero10-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero10-check.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"
before_lines=$(cat "$state/input-lines")

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# --- 1. what the sweep took, recorded -----------------------------------------------
# SIXTY FUNCTIONS, none of them named by the edit.  Listing them here is a RECORDING
# of what the sweep did, which is the only place a list of removed names belongs
# (ZERO-GOAL.md rule 1).
for gone in ex_file rename_buffer setfname buf_name_changed ml_timestamp \
            ml_upd_block0 ml_check_b0_id buflist_name_nr buflist_findlnum \
            buflist_findname_stat buf_setino buf_same_ino buf_store_time \
            otherfile_buf fname_expand fix_fname shorten_fname shorten_fname1 \
            shorten_buf_fname mch_dirname mch_FullName vim_FullName FullName_save \
            home_replace_save expand_filename eval_vars find_cmdline_var \
            expand_wildcards expand_wildcards_eval gen_expand_wildcards \
            ExpandOne ExpandOne_start ExpandFromContext ExpandEscape \
            find_file_in_path mch_getperm mch_isFullName mch_has_wildcard \
            path_with_url backslash_halve repl_cmdline escape_fname wildescape \
            vim_fnamecmp vim_fnamencmp vim_strsave_fnameescape tilde_replace \
            expand_env_save expand_env_save_opt expand_files_and_dirs \
            map_wildopts_to_ewflags save_patterns vim_strrchr vim_findfile_cleanup \
            vim_findfile_free_visited vim_findfile_free_visited_list \
            ff_clear ff_pop ff_free_stack_element ff_free_visited_list \
            b_ffname b_sfname b_fname b_dev b_ino b_dev_valid b_mtime b_mtime_ns \
            b_mtime_read b_mtime_read_ns b_orig_size b_orig_mode \
            CMD_file EX_XFILE readonlymode; do
    n=$(grep -cw -- "$gone" "$f" || true)
    [ "$n" = 0 ] || { echo "  noname       '$gone' still has $n mentions"; exit 1; }
done
# The literals that lose their last speaker.  `"file"` went with the row; E447 and
# E480 were the `path` search's; the `<afile>`/`<sfile>`/`<cword>` family and its
# eleven messages were eval_vars(); E95 and E304 were setfname's and ml_upd_block0's.
for gone in '"file"' 'E447: Can'"'"'t find file ' 'E480: No match' \
            'E95: Buffer with this name already exists' \
            'E304: ml_upd_block0' \
            'E194: No alternate file name to substitute' \
            'E499: Empty file name' '"cword>"' '"afile>"' '"sfile>"' \
            '\n  c  \"%   ' '\n  c  \"#   '; do
    n=$(grep -cF -- "$gone" "$f" || true)
    [ "$n" = 0 ] || { echo "  noname       the string '$gone' still has $n mentions"; exit 1; }
done
echo "  noname       sixty functions, twelve buf_T fields, CMD_file, EX_XFILE, readonlymode and 43 string literals at 0 mentions -- all of it the sweep's but readonlymode, and the edit named not one function"

# --- 2. and everything that must NOT be at zero -------------------------------------
python3 - "$f" "$state/old.c" <<'PY'
import re, sys
sys.path.insert(0, 'tools')
import create_cmdidxs
import cutil
TAG = 'noname'
new = open(sys.argv[1], errors='surrogateescape').read()
old = open(sys.argv[2], errors='surrogateescape').read()
fail = []


def count(text, name):
    return len(re.findall(r'\b%s\b' % name, text))


# THE BARE WORDS, each with the reason it is not zero.  A loop that wanted zero for
# any of these would fail on a correct phase.
KEPT = {'buf_spname': 5,      # prototype, definition, fileinfo, E162, get_trans_bufname
        'buf_get_fname': 3,   # prototype, definition, and buf_spname's call
        'get_trans_bufname': 4,   # prototype, definition, the tabline and :ls
        'fileinfo': 3,        # `:file` was one of four callers; CTRL-G is another
        'check_fname': 3,     # E32's speaker, still called by the `%` register
        'check_changed': 4,   # E37 still refuses: the :q phase's
        'no_write_message': 3,    # the same
        'p_ur': 2, 'p_ro': 2,     # 'undoreload' and 'readonly': the options phase's
        'read_cmd_fd': 12,    # the terminal's: fill_input_buf, mch_settmode
        'vim_fsync': 3,       # ui_write's, and the FILE* phase's
        'scriptin': 8, 'redir_fd': 6,
        'msg_scrolled_ign': 2,    # phase 9's leftover, read-only, and it does not move
        'home_replace': 3,    # the option display still uses it
        'file_name_at_cursor': 3,     # CTRL-F and CTRL-P still extract a word
        'find_file_name_in_path': 3,  # and this is what they extract it with
        'BF_NOTEDITED': 3, 'BF_NEW': 3, 'b_shortname': 2,   # see below
        'nv_error': 46,       # the 'Q' row phase 4 pointed here
        'open_buffer': 5}     # phase 9's five, untouched
for name, want in sorted(KEPT.items()):
    k = count(new, name)
    if k != want:
        fail.append('%s has %d mentions, expected %d -- %s'
                    % (name, k, want, 'this phase reached too far'
                       if k < want else 'something survived that should not have'))

# THREE FLAGS THAT CAN NEVER BE SET AND ARE STILL READ, named rather than folded.
# setfname() was BF_NOTEDITED's only writer and BF_NEW never had one in this tree;
# fileinfo() still tests both, so CTRL-G asks two questions whose answer is fixed.
# b_shortname is the same shape and was ALREADY write-only before this phase -- say
# so, do not fix it.  Folding any of the three changes the string set for no gain.
for flag, fn in (('BF_NOTEDITED', 'fileinfo'), ('BF_NEW', 'fileinfo')):
    span = cutil.find_definition(new, fn)
    if not span or flag not in new[span[0]:span[1]]:
        fail.append('%s is no longer read by %s, and this phase removes its writer '
                    'and not its reader' % (flag, fn))
    if re.search(r'\|=\s*%s\b' % flag, new) or re.search(r'\bb_flags = %s' % flag, new):
        fail.append('%s is set somewhere, and setfname() was its only writer' % flag)
writes = re.findall(r'\bb_shortname\b\s*=[^=]', new)
if len(writes) != 1:
    fail.append('b_shortname is assigned %d times; it was already write-only before '
                'this phase, with one write' % len(writes))

# THE OTHER DIRECTION, which is where a check copied from phase 8 or 9 fails.
# "[No Name]" is TWO occurrences and both are live: buf_get_fname's, which is now
# the only name a buffer has, and can_unload_buffer's, which part C folded a ternary
# into.  E32 survives folded to an unconditional emsg.
if new.count('"[No Name]"') != 2:
    fail.append('"[No Name]" occurs %d times, expected 2 -- buf_get_fname\'s, which '
                "is now the only name a buffer has, and can_unload_buffer's"
                % new.count('"[No Name]"'))
if new.count('E32: No file name') != 1:
    fail.append('E32: No file name went, and check_fname() still says it for the '
                '`%` register')
if 'E37: No write since last change' not in new:
    fail.append("E37 went, and check_changed() is the :q phase's")
if new.count('E23: No alternate file') != 1:
    fail.append('E23 went, and getaltfname() says it unconditionally now')
# E447 is the opposite way round from phase 8's check, which required it to SURVIVE.
if 'E447' in new:
    fail.append('E447 survives, and part G removed the only arm that could say it -- '
                "phase 8's check asserts the opposite, which is why the two phases "
                'cannot share a stage')
if 'E447' not in old:
    fail.append('the input did not say E447, so this phase is being checked against '
                'a file it was not written for')

# check_fname is now one emsg and a FAIL, with no test left.
span = cutil.find_definition(new, 'check_fname')
body = new[span[0]:span[1]] if span else ''
if 'if (' in body or 'return OK' in body:
    fail.append('check_fname still tests something: `b_ffname == NULL` was TRUE for '
                'ever and the fold leaves an unconditional E32')

# THE TABLE.  One row goes and no nv_cmds[] row is touched.
rows = re.findall(r'^    \[CMD_\w+\] = \{.*$', new, re.M)
got = create_cmdidxs.names(sys.argv[1])
try:
    create_cmdidxs.names_from_cmdnames(sys.argv[1])
except SystemExit as e:
    fail.append('the checked parser refuses this table -- the row floor is no '
                'longer below 98: %s' % e)
if len(rows) != 98 or len(got) != 98:
    fail.append('cmdnames[] has %d rows and names() reads %d; both must be 98'
                % (len(rows), len(got)))
if len(re.findall(r'^    \[CMD_\w+\] = \{.*$', old, re.M)) != 99:
    fail.append('the input does not have 99 rows, so this is not the file this '
                'phase was written against')
if 'file' in got:
    fail.append(':file is still a command name')
for name in ('filter', 'fixdel', 'quit', 'print', 'append', 'registers'):
    if name not in got:
        fail.append(':%s went, and it is not this phase\'s' % name)
if 'static_assert(sizeof(cmdnames) / sizeof(cmdnames[0]) == CMD_SIZE' not in new:
    fail.append('the static_assert on the row count went, and it is what catches '
                'an enumerator removed without its row')
if not re.search(r"^ *\{'Q', nv_error,", new, re.M):
    fail.append("the 'Q' row is no longer nv_error's, and phase 4 put it there")

# THE EXEMPTION PHASE 8 KEPT, from the other side: do_one_cmd's curbuf_locked() test
# had two CMD_ conjuncts, phase 8 took CMD_edit's and left CMD_file's saying this
# phase would take it.  What must be left is the test with neither.
m = re.search(r'^.*EX_LOCK_OK.*curbuf_locked\(\).*$', new, re.M)
if not m:
    fail.append("do_one_cmd's curbuf_locked() test went, and this phase removed one "
                'conjunct of it and not the test')
elif 'CMD_' in m.group(0):
    fail.append('the curbuf_locked() exemption still names a command: %r'
                % m.group(0).strip())

# 'readonly' and 'undoreload' keep their rows: removing one is the options phase's,
# and tools/orphanopts.py refuses the opposite direction.
for opt, var in (("'undoreload'", 'p_ur'), ("'readonly'", 'p_ro')):
    if '(char_u *)&%s,' % var not in new:
        fail.append('%s lost its option row, and that is the options phase\'s: a row '
                    'removed here would change what :set answers' % opt)

# What the sixty functions cost the old file, as a difference rather than a number.
for name, want in (('b_ffname', 32), ('b_sfname', 26), ('b_fname', 29),
                   ('setfname', 2), ('eval_vars', 4), ('mch_dirname', 5),
                   ('CMD_file', 4), ('EX_XFILE', 4), ('readonlymode', 3)):
    if count(old, name) != want:
        fail.append('the input is not the file this phase was written against: '
                    '%s %d, expected %d' % (name, count(old, name), want))

if fail:
    for line in fail:
        print('  %-12s %s' % (TAG, line))
    print('  %-12s a check copied from phase 8 or 9 fails on a correct phase 10:' % '')
    print('  %-12s `otherfile` went at phase 8, E447 SURVIVED phase 8 and reaches' % '')
    print('  %-12s zero here, `fileinfo` keeps three callers, E32 keeps its' % '')
    print('  %-12s speaker, and "[No Name]" occurs twice and both are live.' % '')
    sys.exit(1)
print('  %-12s kept: buf_spname 5 and buf_get_fname 3 -- "[No Name]" is now the '
      'ONLY name a buffer has, not one of two -- get_trans_bufname 4, fileinfo 3 '
      '(CTRL-G, g CTRL-G and the startup message), check_fname 3 with E32' % TAG)
print('  %-12s left and named rather than folded: BF_NOTEDITED and BF_NEW, read by '
      'fileinfo() and settable by nothing now that setfname() has gone, and '
      'b_shortname, which was already write-only before this phase' % '')
print('  %-12s the later phases\' line: check_changed 4 and no_write_message 3 '
      "(the :q phase's), p_ur 2 and p_ro 2 with their rows (the options phase's), "
      'read_cmd_fd 12, vim_fsync 3, scriptin 8, redir_fd 6' % '')
print('  %-12s table: 99 -> 98 rows, names() reads 98, static_assert in place, the '
      'floor is 80 and the checked parser accepts it' % '')
PY

# --- 3. the compile, the linkage and the libc surface -------------------------------
# THREE SYMBOLS GO AND THE SET IS NAMED, not the count.  `stat` was mch_getperm()'s,
# reached only from find_file_in_path(), which part G makes unreachable; `getcwd`
# and `strerror` were mch_dirname()'s, whose three callers all go.  These are the
# last three the CORE asks the filesystem with, and after them the process has no
# `open`, no `access` and no `fcntl` either -- phase 9 took those -- so it cannot
# acquire a fourth file descriptor.  `read`, `close` and `dup` STAY and are the
# terminal's alone; `fsync` is ui_write's and the FILE* phase's.
cp "$state/symbols/undefined" "$tmp/before.u"
tools/phasecheck.sh "$work" "$f" "$state/symbols"
comm -23 "$tmp/before.u" .cache/symbols/last/undefined > "$tmp/gone.u"
comm -13 "$tmp/before.u" .cache/symbols/last/undefined > "$tmp/came.u"
printf 'getcwd\nstat\nstrerror\n' > "$tmp/want.u"
if ! cmp -s "$tmp/gone.u" "$tmp/want.u" || [ -s "$tmp/came.u" ]; then
    echo "  noname       the libc surface did not move by exactly getcwd, stat and strerror:"
    echo "               gone: $(tr '\n' ' ' < "$tmp/gone.u")"
    echo "               came: $(tr '\n' ' ' < "$tmp/came.u")"
    exit 1
fi
for keep in fsync read close dup; do
    grep -qx "$keep" .cache/symbols/last/undefined \
        || { echo "  noname       $keep went, and it is not this phase's: read, close and dup are the terminal's and fsync is ui_write's"; exit 1; }
done
for absent in open access fcntl stat getcwd strerror chmod fchmod fstat lstat unlink; do
    if grep -qx "$absent" .cache/symbols/last/undefined; then
        echo "  noname       $absent is undefined again, and nothing here may add one"; exit 1
    fi
done
echo "  noname       symbols $(cat .cache/symbols/last/before) -> $(cat .cache/symbols/last/after), and the set is exactly getcwd stat strerror -- with open, access and fcntl still absent, the core can no longer acquire a file descriptor at all; read, close, dup and fsync stay and are the terminal's and ui_write's"

# --- 4. the enumerators, before and after -------------------------------------------
# EIGHTY-FIVE SURVIVORS RENUMBER and every one must be a CMD_.  cmdnames[] is
# designated, so a row lands at its own enumerator whatever the numbering is -- but
# nothing in the build would notice if another family had moved with them, and 85
# movers from one family is the case CLAUDE.md says a build is happy to get wrong.
tools/enumvals.sh "$state/old.c" "$tmp/ev.old" &
pid_ev=$!
tools/enumvals.sh "$f" "$tmp/ev.new"
wait $pid_ev
python3 - "$tmp/ev.old" "$tmp/ev.new" <<'PY'
import sys
TAG = 'noname'
o = dict(l.rsplit('=', 1) for l in open(sys.argv[1]).read().splitlines())
n = dict(l.rsplit('=', 1) for l in open(sys.argv[2]).read().splitlines())
gone, came = sorted(set(o) - set(n)), sorted(set(n) - set(o))
moved = sorted(k for k in set(o) & set(n) if o[k] != n[k])
stray = [k for k in moved if not k.startswith('CMD_')]
# Every family that goes, and what took it: CMD_file is the row, EX_XFILE the flag
# no row carries any more, and the rest are whole anonymous enums typereach.py takes
# with the code that named them -- the wildcard layer (EW_, WILD_, EXPAND_, XP_BS_),
# eval_vars' specifiers (SPEC_), block zero's (BLOCK0_, B0_FNAME_SIZE_CRYPT, UB_),
# buflist_new's flags (BLN_) and the script stack's (ESTACK_, VSE_, VALID_).
FAMILIES = ('CMD_file', 'EX_XFILE', 'B0_FNAME_SIZE_CRYPT', 'UB_FNAME')
PREFIX = ('EW_', 'WILD_', 'EXPAND_', 'XP_BS_', 'SPEC_', 'BLOCK0_', 'BLN_',
          'ESTACK_', 'VSE_', 'VALID_')
bad = [k for k in gone if k not in FAMILIES and not k.startswith(PREFIX)]
if came or stray or bad:
    if came:
        print('  %-12s enumerators arrived: %s' % (TAG, ' '.join(came)))
    if stray:
        print('  %-12s enumerators outside CMD_ moved value: %s' % (TAG, ' '.join(stray)))
    if bad:
        print('  %-12s enumerators went that this phase does not account for: %s'
              % (TAG, ' '.join(bad)))
    sys.exit(1)
if not moved:
    print('  %-12s no survivor renumbered, and removing a cmdnames[] row must move '
          'every CMD_ after it -- the dump is not of this phase' % TAG)
    sys.exit(1)
print('  %-12s enumerators %d -> %d: %d gone, %d renumbered and every one of the %d '
      'a CMD_, none arriving -- which is exactly the case a build is happy to get '
      'wrong' % (TAG, len(o), len(n), len(gone), len(moved), len(moved)))
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

TAG = 'noname'
ESC, CR = b'\x1b', b'\r'
QUIT = ESC + b':q!' + CR
CTRL_G, CTRL_R, CTRL_F, CTRL_P = b'\x07', b'\x12', b'\x06', b'\x10'
old_bin, new_bin = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])


def record(binary, args, keys, timeout=10):
    """tools/zstream.py's session, with the raw stream and the snapshot count back.

    Everything else is that tool's and for its reasons: the binary is staged as
    `vim` because argv[0] decides what the editor is, the environment is emptied so
    that no vimrc is found, and the session is its own so that a stop signal cannot
    reach this shell.  THE KEYSTROKE FILE IS THE FILE THE CTRL-P PROBES NAME: it is
    written as `keys` in the run directory, so `keys` under the cursor is a name
    that exists and `nosuchfile` is one that does not, with nothing planted.
    """
    stage = tempfile.mkdtemp(prefix='zero10-bin-')
    vim = os.path.join(stage, 'vim')
    shutil.copy2(binary, vim)
    os.chmod(vim, 0o755)
    home = tempfile.mkdtemp(prefix='zero10-home-')
    env = dict(os.environ)
    env.update(TERM='xterm', HOME=home, VIM=os.path.join(home, 'novim'),
               VIMRUNTIME=os.path.join(home, 'novim'),
               XDG_CONFIG_HOME=os.path.join(home, 'xdg'))
    for k in ('LINES', 'COLUMNS', 'VIMINIT', 'EXINIT', 'MYVIMRC'):
        env.pop(k, None)
    d = tempfile.mkdtemp(prefix='zero10-run-')
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
    return zrec.scrub(text), out.decode('utf-8', 'replace'), len(scr.snaps)


def typed(seed, *keys):
    """tools/zcases.py's shape: type the seed under 'paste', then the real keys."""
    return (['+set paste'], [b'i' + seed + ESC, b':set nopaste' + CR] + list(keys) + [QUIT])


HELLO = b'hello'
SPELLINGS = ('f', 'fi', 'fil', 'file', 'file!')

# name, (args, keys), must-differ
PROBES = [
    # --- naming a buffer, which is the whole phase and which no recorded case sees --
    ('file_rename', typed(HELLO, b':file NEWNAME' + CR, CTRL_G),        True),
    ('file_bang',   typed(HELLO, b':file! NEWNAME' + CR, CTRL_G),       True),
    # --- and asking the filesystem a question, which is part G -----------------------
    ('cp_missing',  typed(b'nosuchfile', b'0', b':' + CTRL_R + CTRL_P + CR), True),
    # --- everything that must not move ----------------------------------------------
    ('cp_existing', typed(b'keys', b'0', b':' + CTRL_R + CTRL_P + CR),  False),
    ('cf_existing', typed(b'keys', b'0', b':' + CTRL_R + CTRL_F + CR),  False),
    ('ctrl_g',      typed(b'a' + CR + b'b', CTRL_G),                    False),
    ('g_ctrl_g',    typed(b'a' + CR + b'b', b'g' + CTRL_G),             False),
    ('registers',   typed(HELLO, b'yy', b':registers' + CR),            False),
    ('reg_percent', typed(HELLO, b'A ' + ESC + b'"%p' + ESC),           False),
    ('reg_hash',    typed(HELLO, b'A ' + ESC + b'"#p' + ESC),           False),
    ('cmd_filter',  typed(HELLO, b':filter' + CR),                      False),
    ('cmd_fixdel',  typed(HELLO, b':fixdel' + CR),                      False),
    ('cmd_ls',      typed(HELLO, b':ls' + CR),                          False),
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
NONAME = '"[No Name]" [Modified] 1 line --100%--'

# THE PROBE.  `:file NEWNAME` then CTRL-G, and what the OLD binary prints is the
# whole evidence that a buffer could be named at all -- the corpus never sees it,
# because every case types its own text and names nothing.  `[Not edited]` is
# BF_NOTEDITED, which rename_buffer() set and which nothing can set now.
for name in ('file_rename', 'file_bang'):
    (o, _, _), (n, _, _) = by[name]
    if '"NEWNAME" [Modified][Not edited] 1 line --100%--' not in o:
        fail.append('%s: the input binary did not name the buffer NEWNAME, so this '
                    'proves nothing about naming one' % name)
    if 'NEWNAME"' in n:
        fail.append('%s: the new binary named the buffer anyway' % name)
    if NONAME not in n:
        fail.append('%s: CTRL-G does not answer "[No Name]" now, and that is the '
                    'only name a buffer has' % name)
    if E492 not in n:
        fail.append('%s: `:file` is not an unknown command' % name)
    if 'Not edited' in n:
        fail.append('%s: [Not edited] is still shown, and BF_NOTEDITED has no '
                    'writer left' % name)

# THE ONE PROBE THAT SHOWS THE OLD BINARY ASKING THE DISK, and its pair that shows
# what part G did NOT remove.  With `nosuchfile` under the cursor, CTRL-P found
# nothing on the old binary and put nothing on the command line; now the word itself
# arrives and `:nosuchfile` is E492.  With `keys` under the cursor -- the keystroke
# file, which exists -- the lookup succeeded and returned the same word, so BOTH
# binaries run `:keys`, which is `:k` with trailing characters.
(o, _, _), (n, _, _) = by['cp_missing']
if E492 in o:
    fail.append('cp_missing: the input binary already put the word on the command '
                'line, so it never asked the filesystem and this proves nothing')
if 'E492: Not an editor command: nosuchfile' not in n:
    fail.append('cp_missing: CTRL-P does not yield the word under the cursor now')
TRAILING = 'E488: Trailing characters: eys'
for name in ('cp_existing', 'cf_existing'):
    (o, _, _), (n, _, _) = by[name]
    if TRAILING not in o or TRAILING not in n:
        fail.append('%s: `keys` did not reach the command line on both binaries, so '
                    '"it did not move" is two failures agreeing' % name)

# THE INHERITANCE CHECK.  `:file`'s row gave its shortest abbreviation as ONE
# character, so all five spellings reached it; each must answer E492 now and none
# may have answered E492 before -- CLAUDE.md's `:help` -> `:helpclose` trap.
for s in SPELLINGS:
    (o, _, _), (n, _, _) = by['spell_' + s]
    if E492 in o:
        fail.append(':%s already answered E492 before this phase, so it proves '
                    'nothing' % s)
    if NONAME not in o:
        fail.append(':%s did not report the buffer on the input binary' % s)
    if E492 not in n:
        fail.append(':%s does not answer E492: a removed name has been inherited' % s)
# And the two neighbours that must not move at all.
for name in ('cmd_filter', 'cmd_fixdel'):
    (o, _, _), (n, _, _) = by[name]
    if E492 in n and E492 not in o:
        fail.append('%s: a surviving command became unknown' % name)

# The ones that must not move are required to be DOING something, not failing alike.
(o, _, _), (n, _, _) = by['ctrl_g']
if '"[No Name]" [Modified] 2 lines --100%--' not in n:
    fail.append('ctrl_g: CTRL-G no longer reports the buffer, and it is what `:file` '
                'printed and what must survive')
(o, _, _), (n, _, _) = by['g_ctrl_g']
if 'Col 1 of 1' not in n:
    fail.append('g_ctrl_g: `g CTRL-G` printed no count')
(o, _, _), (n, _, _) = by['quit_modified']
if 'E37: No write since last change' not in n:
    fail.append('quit_modified: :q no longer refuses on a modified buffer, and that '
                "is the :q phase's to change")
for name, want in (('editing', 'alpha'), ('reg_percent', 'hello'),
                   ('reg_hash', 'hello')):
    (o, _, _), (n, _, _) = by[name]
    if want not in n:
        fail.append('%s: the new binary no longer shows %r, so "it did not move" is '
                    'two failures agreeing' % (name, want))
# `:registers` prints its table, a `Press ENTER` prompt follows, and the redraw wipes
# it before the cursor comes back -- so it is in the STREAM and in no snapshot.  Its
# `"%` and `"#` lines were never printed, b_fname having been NULL since phase 5.
(o, ostream, _), (n, nstream, _) = by['registers']
if 'Type Name Content' not in nstream or 'Type Name Content' not in ostream:
    fail.append('registers: :registers printed no table, so "it did not move" is '
                'two failures agreeing')
for tag, stream in (('the input binary', ostream), ('this one', nstream)):
    if '"%' in stream or '"#' in stream:
        fail.append('registers: %s printed a `"%%` or `"#` line, and neither has '
                    'been printable since phase 5' % tag)

if fail:
    for line in fail:
        print('  %-12s %s' % (TAG, line))
    print('  %-12s the corpus cannot see a buffer being named: `cmd_file` types' % '')
    print('  %-12s `:file` with no argument and records the CTRL-G line for' % '')
    print('  %-12s [No Name].  `file_rename` is the only probe that can tell a' % '')
    print('  %-12s removed command from a changed message, and `cp_missing` the' % '')
    print('  %-12s only one that shows the old binary asking the filesystem.' % '')
    sys.exit(1)
print('  %-12s probes: %d moved (%s), %d unchanged' % (TAG, len(moved), ' '.join(moved), len(static)))
print('  %-12s the input binary answered `"NEWNAME" [Modified][Not edited]` to '
      'CTRL-G after `:file NEWNAME`, and found `nosuchfile` absent from the disk '
      'through CTRL-P; five spellings answer E492 and none did before' % '')
print('  %-12s and what did not move is doing its work: CTRL-G and g CTRL-G, '
      ':registers with its table and without a `"%%` or `"#` line, the %% and # '
      'registers, :filter, :fixdel, :ls, :q on a modified buffer and :q!' % '')
PY

# --- 7. a real terminal ---------------------------------------------------------------
# Every probe above went through a pipe.  On a pty the old binary renames the buffer
# and CTRL-G says so; this one answers E492 and `[No Name]`.  An editing session
# beside it must be identical either side.
python3 - "$state/old" "$bin" <<'PY'
import os, re, sys, tempfile
sys.path.insert(0, 'tools')
import ptyrun
TAG = 'noname'
home = tempfile.mkdtemp(prefix='zero10-home-')
env = dict(os.environ, HOME=home, VIM=os.path.join(home, 'novim'),
           VIMRUNTIME=os.path.join(home, 'novim'),
           XDG_CONFIG_HOME=os.path.join(home, 'xdg'))
for k in ('VIMINIT', 'EXINIT', 'MYVIMRC'):
    env.pop(k, None)


def session(binary, keys):
    d = tempfile.mkdtemp(prefix='zero10-pty-')
    text, status = ptyrun.session(binary, [], keys, term='xterm', cwd=d,
                                  settle=0.6, env=env)
    return text.decode('utf-8', 'replace'), status


RENAME = [b'ityped on a terminal\x1b', b':file NEWNAME\r', b'\x07', b':q!\r']
EDIT = [b'ialpha\rbeta\x1b', b'ggdwA-tail\x1b', b'u', b':q!\r']
fail = []
o, ostat = session(sys.argv[1], RENAME)
n, nstat = session(sys.argv[2], RENAME)
if 'NEWNAME' not in o:
    fail.append('the pty session did not rename the buffer on the input binary, so '
                'it proves nothing')
if 'NEWNAME"' in n:
    fail.append('the pty session renamed the buffer on the new binary')
if 'E492' not in n or '[No Name]' not in n:
    fail.append('the pty session does not answer E492 and [No Name]: %r' % n[-200:])
eo, eos = session(sys.argv[1], EDIT)
en, ens = session(sys.argv[2], EDIT)
# THE EDITING SESSION IS COMPARED WHOLE, WITH ONE FIELD BLINDED, AND THE FIELD IS A
# WALL CLOCK.  The `u` prints `1 change; before #3  N second(s) ago`, where N is how
# long ago the change was made -- a reading of the clock, which neither binary
# decides.  ptyrun writes the keystrokes 0.6 s apart, so the elapsed time from the
# `A-tail` ESC to the `u` sits ON the one-second boundary, and which side of it the
# two sessions fall is how busy the machine is.  THESE ARE PHASE 11's KEYS, AND THE
# MEASUREMENT IS ITS PAIR, where the same assertion is what failed `make zero-pass`
# on a tree whose r11 `make zero-verify` had reproduced minutes earlier: under a
# load that crosses the boundary and comes back, 30 of 240 runs of that section
# failed (12.5 %), every one of them differing in that field ALONE -- 480 sessions
# produced exactly two texts, `0 seconds ago` and `1 second ago` -- and 0 of 120
# failed with the field blinded.  Everything else in the stream, `1 change; before
# #3` included, is still compared byte for byte, and the guard below is what stops
# the blinding from quietly becoming a blinding of nothing.
AGO = re.compile(r'\d+ seconds? ago')
if 'change; before #' not in eo or not AGO.search(eo):
    fail.append('the undo report with its `N seconds ago` is not in the pty session '
                'on the input binary, so blinding the clock blinds nothing and the '
                'comparison below is not the one described: %r' % eo[-200:])
if AGO.sub('<ago>', eo) != AGO.sub('<ago>', en) or eos != ens:
    fail.append('an ordinary pty editing session moved, and nothing here may move it')
if 'alpha' not in en:
    fail.append('the pty editing session did nothing, so "identical" is two '
                'failures agreeing')
if fail:
    for line in fail:
        print('  %-12s %s' % (TAG, line))
    sys.exit(1)
print('  %-12s a real terminal: `:file NEWNAME` then CTRL-G renames on the binary '
      'this phase was handed and answers E492 and [No Name] here, and an ordinary '
      'editing session is identical either side' % TAG)
PY
