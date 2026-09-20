#!/bin/sh
# Zero phase 10 -- the buffer has no name.  See ZERO-GOAL.md.
#
# Usage: pipes/zero10-edit.sh <work-dir> <state-dir>     (run from the repository root)
#
# Phases 6, 7 and 8 took every way to ASK for a file and phase 9 took the machinery
# that read one.  What is left of the filesystem in this editor is a NAME: three
# char_u* fields on every buffer -- `b_ffname`, `b_sfname`, `b_fname` -- and the one
# command that could still set them, `:file`.  This phase takes the command, stops
# `buflist_new()` naming the buffer it makes, and folds the sixteen places that ask
# what the name is.  After it the three fields are written nowhere, the sweep takes
# them, and `[No Name]` is no longer one of the answers the editor can give but the
# only one.
#
# IT IS ALSO WHERE THE CORE STOPS ASKING THE FILESYSTEM QUESTIONS OF ITS OWN ACCORD.
# Three libc symbols go, and each for the reason of one part below:
#
#   stat      `mch_getperm()`, reached from `find_file_in_path()`, which part G
#             makes unreachable: CTRL-F and CTRL-P extract a word from the buffer
#             and nothing looks for it on a disk.
#   getcwd    `mch_dirname()`, whose three callers were `shorten_fname()`,
#             `shorten_fnames()` and `mch_FullName()`.  Part F takes the second and
#             the sweep the other two.
#   strerror  `mch_dirname()`'s error arm, and nothing else's.
#
# SEVEN PARTS, A to G, and every removal that is not one of them is the sweep's
# (ZERO-GOAL.md rule 1).  Sixty functions go and this file names not one of them.
#
#   A  `:file` goes: the enumerator, the cmdnames[] row, and BOTH of do_one_cmd's
#      CMD_file tests -- the `curbuf_locked()` conjunct phase 8 deliberately kept,
#      and the second test below it.  All in one edit with the enumerator, or the
#      text does not compile.  `ex_file` -> `rename_buffer` -> `setfname` then die
#      by the sweep; `fileinfo()` SURVIVES, having three other callers.
#   B  `buflist_new()` never names: its one call site already passes NULL, NULL, so
#      both parameters go with the `fname_expand`/`stat`/`buflist_findname_stat`
#      prologue, the `if (ffname != NULL)` assignment, the failure arm's frees and
#      the `st.st_dev` block.
#   C  the sixteen folds, one per site, each with the constant it takes written out
#      here.  `== NULL` is TRUE and folds always; `!= NULL` is FALSE and folds
#      never.
#   D  `EX_XFILE` reaches zero rows -- `:file` was its last one -- so do_one_cmd's
#      `expand_filename()` call can never be entered.  Folding it never is what
#      hands the sweep 32 functions and some 1,300 lines, the same shape as phase
#      8's EX_ARGOPT.
#   E  `readonlymode` and `b_dev_valid`'s assignment, each write-only after C and
#      B, and neither of them anything a warning or a sweep tool can see.
#   F  `shorten_fnames()` loses the cwd it fetched for a now-empty
#      `shorten_buf_fname()`.
#   G  `find_file_name_in_path()`'s `FNAME_EXP` arm.
#
# FOLD `buflist_name_nr` AT ITS CALLERS, NEVER IN PLACE, and the agent that surveyed
# this phase made the mistake first.  Its body is `buf = buflist_findnr(fnum); if
# (buf == NULL || buf->b_fname == NULL) return FAIL; *fname = buf->b_fname; ...
# return OK;`.  Folding the whole `if` away gives a function that returns OK with
# `*fname` never written -- a silent behaviour change in the direction that crashes.
# What is true is that it returns FAIL ALWAYS, so the fold belongs at
# `getaltfname()` and at `ex_display()`, and only then is it uncalled and the
# sweep's.
#
# THREE SITES HAVE AN `else` AND cutil.fold_always REFUSES THEM, by design: keeping
# a body and dropping an else is not what it does.  fileinfo(), set_b0_fname() and
# get_trans_bufname() use the local fold_always_else() below, which keeps the if
# body dedented four columns -- right only because each of the three is written one
# level inside its function, which was read and not assumed, phase 8's anchor 5
# being what a wrong dedent costs.  And FOUR MORE are a function whose whole body is
# the `if`: buf_spname(), buf_get_fname(), check_fname() and getaltfname().
# fold_always there leaves an unreachable `return buf->b_fname;` behind -- measured
# -- which no sweep tool removes and which would keep `b_fname` alive for ever.
# Those four are exact-text rewrites of the body.
#
# THE TWO FOLDS IN eval_vars() ARE NOT MADE, and that is a correction to the brief
# this phase was written from.  Both of its `if (b_fname == NULL)` arms are inside a
# function part D makes unreachable: `expand_filename()` and
# `expand_wildcards_eval()` are its only callers and both go.  Folding inside text
# the sweep deletes changes no output and states nothing, so rule 1 applies -- the
# check requires `eval_vars` at 0 mentions afterwards, which is the assertion that
# replaces the fold.
#
# WHAT THIS PHASE NEEDS OF PHASES 7, 8 AND 9, and none of it can be a `uses` line,
# packages.sh refusing one inside a package: `:read` was one of the six EX_XFILE
# rows and phase 7 took it; four more went with the :edit family in phase 8, which
# is why :file is the LAST and part D exists at all; and `set_rw_fname` was
# `setfname`'s second caller and went with `readfile` in phase 9, which is what
# leaves `rename_buffer` as its only one.
#
# THE INPUT BINARY IS BUILT HERE, before the edit, from the boundary's own makefile
# flags, as every zero edit since phase 2 does, and the source goes with it as
# $state/old.c.  The check needs both: `:file NEWNAME` is the one thing that proves
# the old binary could name a buffer at all, and no recording can see it.
set -eu

work=${1:?usage: zero10-edit.sh <work-dir> <state-dir>}
state=${2:?usage: zero10-edit.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"

# The flags are read out of the boundary's makefile rather than written here a
# second time: zero's compile line is the boundary's (ZERO-GOAL.md rule 8).
cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")
cp "$f" "$state/old.c"
# shellcheck disable=SC2086
( cd "$state" && gcc $cflags $ldflags -o old old.c ) &
pid_old=$!

python3 - "$f" <<'PY'
TAG = 'noname'
import re, sys
sys.path.insert(0, 'tools')
# tools/cutil.py -- named as a PATH so tools/implhash.sh hashes it into this
# phase's key.  implhash greps for paths and an `import` names a module, so
# without this line an edit to it changes what this phase produces and moves
# no key at all.  See CLAUDE.md on cutil.py and macros.py.  Do not delete it.
import cutil
path = sys.argv[1]
t = open(path, errors='surrogateescape').read()

FIELDS = ('b_ffname', 'b_sfname', 'b_fname')


def die(msg):
    sys.exit('  %-12s %s' % (TAG, msg))


def say(what):
    print('  %-12s %s' % (TAG, what))


def mentions(text, name):
    return len(re.findall(r'\b%s\b' % name, text))


def text_edit(text, old, new, what, n=1):
    """An exact-text replacement, counted file-wide.  Never 'the first one'."""
    k = text.count(old)
    if k != n:
        die('%s -- the text occurs %d times, expected %d: %r'
            % (what, k, n, old[:70]))
    say(what)
    return text.replace(old, new)


def in_function(text, name, edit):
    span = cutil.find_definition(text, name)
    if not span:
        die('%s is not defined' % name)
    a, z = span
    return text[:a] + edit(text[a:z]) + text[z:]


def within(text, fn, old, new, what, n=1):
    """Exact text replaced inside ONE definition, counted there and not file-wide."""
    def edit(s):
        k = s.count(old)
        if k != n:
            die('%s -- %r occurs %d times in %s, expected %d'
                % (what, old[:60], k, fn, n))
        return s.replace(old, new)
    out = in_function(text, fn, edit)
    say(what)
    return out


HOW = {'always': cutil.fold_always, 'never': cutil.fold_never, 'drop': cutil.drop_if}


def fold(text, fn, how, pattern, what, n=1):
    """A counted cutil fold, SCOPED TO ONE DEFINITION.

    File-wide would be wrong here and not merely loose: `if (buf->b_ffname ==
    NULL)` is the whole of close_buffer's fold and the head of set_b0_fname's,
    written identically at the same indent, so a file-wide count of 1 fails and a
    count of 2 would fold two different shapes with one rule.
    """
    def edit(s):
        try:
            return HOW[how](s, pattern, n, re.M)
        except ValueError as e:
            die('%s -- %s' % (what, e))
    out = in_function(text, fn, edit)
    say(what)
    return out


def fold_always_else(text, fn, ifline, what):
    """`if (TRUE) { A } else { B }` inside fn: keep A, lose the test and B.

    cutil.fold_always refuses a block with an else, deliberately, and this is the
    shape three sites here have.  The body is dedented four columns.
    """
    def edit(s):
        if s.count(ifline) != 1:
            die('%s -- the if line occurs %d times in %s, expected 1'
                % (what, s.count(ifline), fn))
        b = cutil.blank(s)
        i = s.index(ifline)
        o = b.index('{', i + len(ifline) - 1)
        c = cutil.match(s, o, b)
        if c < 0:
            die('%s -- unbalanced block' % what)
        end_if = s.index('\n', c) + 1
        m = re.match(r'[ \t]*else[ \t]*\n[ \t]*\{', s[end_if:])
        if not m:
            die('%s -- the block has no else, so cutil.fold_always is the tool' % what)
        o2 = end_if + m.end() - 1
        c2 = cutil.match(s, o2, b)
        if c2 < 0:
            die('%s -- unbalanced else block' % what)
        body = s[s.index('\n', o) + 1:s.rfind('\n', 0, c) + 1]
        if not all(l.startswith('    ') or not l.strip() for l in body.splitlines()):
            die('%s -- the if body is not written one level in, and dedenting it '
                'would move code to a column it was never at' % what)
        body = ''.join(l[4:] if l.startswith('    ') else l
                       for l in body.splitlines(keepends=True))
        return s[:i] + body + s[s.index('\n', c2) + 1:]
    out = in_function(text, fn, edit)
    say(what)
    return out


def assignments(text, name):
    """Every write to field `name`: `x->name =`, and `(x->name) =` as slim spells it."""
    return [m.start() for m in re.finditer(r'\b%s\b\s*\)?\s*=[^=]' % name, text)]


def uses(text, name):
    """Every USE of field `name` -- a mention through `->`, so not its declaration."""
    return [m.start() for m in re.finditer(r'->\s*%s\b' % name, text)]


def functions_holding(text, offsets, names):
    """Which of `names` the offsets fall inside; refuses one that falls in none."""
    spans = {}
    for n in names:
        sp = cutil.find_definition(text, n)
        if sp:
            spans[n] = sp
    got = set()
    for off in offsets:
        for n, (a, z) in spans.items():
            if a <= off < z:
                got.add(n)
                break
        else:
            die('a mention at line %d is in none of %s -- this phase was counted '
                'against a different file'
                % (text.count('\n', 0, off) + 1, ' '.join(sorted(names))))
    return got


# ---- 0. the shape every anchor below was counted against --------------------------
BEFORE = {'b_ffname': 32, 'b_sfname': 26, 'b_fname': 29,
          'CMD_file': 4,          # the enumerator, the row and do_one_cmd's two tests
          'EX_XFILE': 4,          # the enumerator, the row, do_one_cmd, separate_nextcmd
          'buflist_new': 3,       # prototype, definition, the one call in create_windows
          'buflist_name_nr': 3,   # definition, getaltfname, ex_display
          'buf_spname': 7, 'buf_get_fname': 3, 'fileinfo': 4,
          'check_fname': 3,       # E32's speaker, reachable from get_spec_reg
          'readonlymode': 3,      # the definition, open_buffer's read, one write
          'mch_dirname': 5,       # shorten_fname, shorten_fnames, mch_FullName
          'shorten_buf_fname': 2,
          'check_changed': 4,     # E37 still refuses: the :q phase's
          'no_write_message': 3,  # the same
          'p_ur': 2, 'p_ro': 2,   # 'undoreload' and 'readonly': the options phase's
          'read_cmd_fd': 12,      # the terminal's: fill_input_buf, mch_settmode
          'vim_fsync': 3,         # ui_write's, and the FILE* phase's
          'scriptin': 8, 'redir_fd': 6}
for name, want in sorted(BEFORE.items()):
    k = mentions(t, name)
    if k != want:
        die('%s has %d mentions, expected %d -- the anchors below were counted '
            'against a different file' % (name, k, want))
say('b_ffname 32, b_sfname 26, b_fname 29, CMD_file 4, EX_XFILE 4 -- the file the '
    'seven parts were counted against')

# THE INVARIANT, COMPUTED BEFORE ANYTHING IS FOLDED.  Every fold below rests on the
# three fields being NULL for ever, so the writes are enumerated and each is
# required to be somewhere this phase accounts for: buflist_new (part B rewrites
# it), shorten_buf_fname (part C folds its only branch away), and setfname and
# rename_buffer, which part A leaves with no reference at all.  A write anywhere
# else means every fold below is a guess.
WRITERS = {'buflist_new', 'setfname', 'rename_buffer', 'shorten_buf_fname'}
offs = []
for fld in FIELDS:
    offs += assignments(t, fld)
got = functions_holding(t, offs, WRITERS)
if got != WRITERS:
    die('the writes to %s live in %s, expected exactly %s'
        % ('/'.join(FIELDS), ' '.join(sorted(got)), ' '.join(sorted(WRITERS))))
say('%d writes to b_ffname, b_sfname and b_fname, and every one is in buflist_new, '
    'setfname, rename_buffer or shorten_buf_fname -- the four this phase accounts '
    'for.  That, and nothing weaker, is why every fold below may take a constant'
    % len(offs))

# ---- A. :file goes -----------------------------------------------------------------
# The cmdnames[] row is the only reference a command handler has, so taking the row
# is what makes ex_file unreachable.  The enumerator and both do_one_cmd tests must
# go in the SAME edit or the text does not compile.
t = text_edit(t, '    CMD_file,\n', '',
              'the CMD_file enumerator of enum CMD_index')
rows = re.findall(r'^    \[CMD_file\] = \{.*\n', t, re.M)
if len(rows) != 1:
    die('the cmdnames[] row for :file matches %d lines, expected 1' % len(rows))
t = t.replace(rows[0], '')
say('the cmdnames[] row [CMD_file] = {...}, one physical line: ex_file has no other '
    'reference, and rename_buffer and setfname no other caller')
# THE CONJUNCT PHASE 8 KEPT.  `ea.cmdidx != CMD_file` is TRUE for ever once no row
# carries the enumerator, so it is dropped rather than folded: the other two terms
# of the test are live and the exemption was :file's alone.
t = text_edit(t,
              '    if (!(ea.argt & (EX_CMDWIN | EX_LOCK_OK)) && ea.cmdidx != CMD_file && curbuf_locked())\n',
              '    if (!(ea.argt & (EX_CMDWIN | EX_LOCK_OK)) && curbuf_locked())\n',
              "do_one_cmd's curbuf_locked() exemption: `ea.cmdidx != CMD_file` is "
              'TRUE for ever, and phase 8 kept it saying this phase would take it')
t = text_edit(t,
              '    if (ea.cmdidx == CMD_file && *ea.arg != NUL && curbuf_locked())\n'
              '    {\n'
              '        goto doend;\n'
              '    }\n\n', '',
              "do_one_cmd's second CMD_file test, deleted as text rather than "
              'folded: its condition names the enumerator that is going')
if mentions(t, 'CMD_file'):
    die('CMD_file still has %d mentions' % mentions(t, 'CMD_file'))

# ---- B. buflist_new never names ------------------------------------------------------
# Its one call site is create_windows', `buflist_new(NULL, NULL, 1L, BLN_LISTED)`,
# and has been since phase 5 took the file argument.  So ffname and sfname are NULL
# on entry, for ever, and everything the function does with them folds to what it
# did: fname_expand() leaves two NULLs alone, the stat() is never reached because
# `sfname == NULL` short-circuits, and the buflist_findname_stat() lookup is guarded
# by `ffname != NULL`.
t = text_edit(t,
              'static buf_T *buflist_new(char_u *ffname_arg, char_u *sfname_arg, linenr_T lnum, int flags);\n',
              'static buf_T *buflist_new(linenr_T lnum, int flags);\n',
              "buflist_new's prototype loses both name parameters")
t = text_edit(t,
              'buflist_new(char_u      *ffname_arg, char_u      *sfname_arg, linenr_T    lnum, int         flags)\n',
              'buflist_new(linenr_T    lnum, int         flags)\n',
              'and so does its definition')
t = within(t, 'buflist_new',
           '    char_u      *ffname = ffname_arg;\n'
           '    char_u      *sfname = sfname_arg;\n'
           '    buf_T       *buf;\n'
           '    stat_T      st;\n',
           '    buf_T       *buf;\n',
           'the two locals the parameters fed, and the stat_T nothing fills now')
t = within(t, 'buflist_new',
           '    fname_expand(curbuf, &ffname, &sfname);\n'
           '\n'
           '    if (sfname == NULL ||  stat(((char *)sfname), (&st))  < 0)\n'
           '    {\n'
           '        st.st_dev = ( dev_t )-1;\n'
           '    }\n'
           '    if (ffname != NULL && !(flags & (BLN_DUMMY | BLN_NEW)) && (buf = buflist_findname_stat(ffname, &st)) != NULL)\n'
           '    {\n'
           '        vim_free(ffname);\n'
           '        if (lnum != 0)\n'
           '        {\n'
           '            buflist_setfpos(buf, (flags & BLN_NOCURWIN) ? NULL : curwin, lnum, (colnr_T)0, FALSE);\n'
           '        }\n'
           '\n'
           '        if ((flags & BLN_NOOPT) == 0)\n'
           '        {\n'
           '            buf_copy_options(buf, 0);\n'
           '        }\n'
           '\n'
           '        return buf;\n'
           '    }\n'
           '\n', '',
           'the prologue and the lookup: fname_expand() on two NULLs, a stat() the '
           '`sfname == NULL` disjunct already short-circuited, and the search for '
           'an existing buffer of the same name, whose guard `ffname != NULL` is '
           'FALSE -- no buffer can be found by a name that is not given')
t = within(t, 'buflist_new',
           '        if (buf == NULL)\n'
           '        {\n'
           '            vim_free(ffname);\n'
           '            return NULL;\n'
           '        }\n',
           '        if (buf == NULL)\n'
           '        {\n'
           '            return NULL;\n'
           '        }\n',
           "the alloc failure arm's vim_free(ffname): there is no ffname to free")
t = within(t, 'buflist_new',
           '    if (ffname != NULL)\n'
           '    {\n'
           '        buf->b_ffname = ffname;\n'
           '        buf->b_sfname = vim_strsave(sfname);\n'
           '    }\n'
           '\n', '',
           'the assignment that named the buffer -- `ffname != NULL` is FALSE, and '
           'this is the statement the whole phase is about')
t = within(t, 'buflist_new',
           '    if ((ffname != NULL && (buf->b_ffname == NULL || buf->b_sfname == NULL)) || buf->b_wininfo == NULL)\n'
           '    {\n'
           '        if (buf->b_sfname != buf->b_ffname)\n'
           '        {\n'
           '             vim_free(buf->b_sfname);\n'
           '             (buf->b_sfname) = NULL;\n'
           '        }\n'
           '        else\n'
           '        {\n'
           '            buf->b_sfname = NULL;\n'
           '        }\n'
           '         vim_free(buf->b_ffname);\n'
           '         (buf->b_ffname) = NULL;\n'
           '        if (buf != curbuf)\n',
           '    if (buf->b_wininfo == NULL)\n'
           '    {\n'
           '        if (buf != curbuf)\n',
           'the failure arm: its first disjunct is FALSE, so only the wininfo '
           'allocation can fail, and the two names it freed are not there to free')
t = within(t, 'buflist_new', '    buf->b_fname = buf->b_sfname;\n', '',
           'b_fname = b_sfname, which is NULL = NULL')
t = within(t, 'buflist_new',
           '    if (st.st_dev == ( dev_t )-1)\n'
           '    {\n'
           '        buf->b_dev_valid = false;\n'
           '    }\n'
           '    else\n'
           '    {\n'
           '        buf->b_dev_valid = true;\n'
           '        buf->b_dev = st.st_dev;\n'
           '        buf->b_ino = st.st_ino;\n'
           '    }\n',
           '    buf->b_dev_valid = false;\n',
           'the device block: `st.st_dev` was set to -1 by the prologue that has '
           'gone, so the TRUE arm is the one that ran and b_dev_valid is false')
t = text_edit(t, '    curbuf = buflist_new(NULL, NULL, 1L, BLN_LISTED);\n',
              '    curbuf = buflist_new(1L, BLN_LISTED);\n',
              "the one call site, create_windows', which already passed NULL, NULL")
span = cutil.find_definition(t, 'buflist_new')
for gone in ('ffname', 'sfname', 'st'):
    if mentions(t[span[0]:span[1]], gone):
        die('%s is still named inside buflist_new' % gone)
say('buflist_new names nothing: ffname, sfname and st are gone from it')

# ---- C. the sixteen folds, with the constant each takes --------------------------------
# `b_ffname`, `b_sfname` and `b_fname` are NULL for ever, proved above.  So
# `== NULL` is TRUE and folds ALWAYS, `!= NULL` is FALSE and folds NEVER, and every
# site below says which it is.

# C1  open_buffer: `curbuf->b_ffname != NULL` is FALSE, so the whole test is FALSE.
#     This is readonlymode's only reader, which part E then finishes.
t = fold(t, 'open_buffer', 'never',
         r'^    if \(readonlymode && curbuf->b_ffname != NULL && \(curbuf->b_flags & BF_NEVERLOADED\)\)$',
         'open_buffer: `b_ffname != NULL` is FALSE, so a buffer can never be made '
         "read-only for being a never-loaded file -- and this was readonlymode's "
         'only reader')

# C2  can_unload_buffer: both names are NULL, so `fname` is NULL and E937 takes its
#     own [No Name] fallback.  Exact text: a declaration and a call, not an if.
t = text_edit(t,
              '        char_u *fname = buf->b_fname != NULL ? buf->b_fname : buf->b_ffname;\n'
              '\n'
              '        semsg(_(e_attempt_to_delete_buffer_that_is_in_use_str), fname != NULL ? fname : (char_u *)"[No Name]");\n',
              '        semsg(_(e_attempt_to_delete_buffer_that_is_in_use_str), (char_u *)"[No Name]");\n',
              'can_unload_buffer: `fname` is NULL either way, so E937 names the '
              'buffer "[No Name]" -- which is what it printed before')

# C3  close_buffer: `b_ffname == NULL` is TRUE.
t = fold(t, 'close_buffer', 'always', r'^    if \(buf->b_ffname == NULL\)$',
         'close_buffer: `b_ffname == NULL` is TRUE, so an unloaded buffer is always '
         'deleted rather than kept for its name')

# C4  curbuf_reusable: a conjunct of a return expression, TRUE for ever.
t = text_edit(t, 'curbuf != NULL && curbuf->b_ffname == NULL && curbuf->b_nwindows <= 1',
              'curbuf != NULL && curbuf->b_nwindows <= 1',
              'curbuf_reusable: `b_ffname == NULL` is TRUE, so the conjunct goes '
              'rather than being kept with a fixed answer')

# C5  getaltfname: buflist_name_nr() is FAIL ALWAYS -- see the head of this file for
#     why the fold is here and not inside it.  Exact text, because fold_always on a
#     body that returns leaves `return fname;` behind, unreachable and alive.
t = text_edit(t,
              '    char_u      *fname;\n'
              '    linenr_T    dummy;\n'
              '\n'
              '    if (buflist_name_nr(0, &fname, &dummy) == FAIL)\n'
              '    {\n'
              '        if (errmsg)\n'
              '        {\n'
              '            emsg(_(e_no_alternate_file));\n'
              '        }\n'
              '        return NULL;\n'
              '    }\n'
              '    return fname;\n',
              '    if (errmsg)\n'
              '    {\n'
              '        emsg(_(e_no_alternate_file));\n'
              '    }\n'
              '    return NULL;\n',
              'getaltfname: buflist_name_nr() is FAIL ALWAYS, so the alternate file '
              'is E23 and NULL -- which is what the `#` register already answered')

# C6  fileinfo: buf_spname() is non-NULL ALWAYS, so the special-name arm is taken
#     and the home_replace() arm cannot be.  It has an else.
t = fold_always_else(t, 'fileinfo', '    if (name != NULL)\n',
                     'fileinfo: buf_spname() never returns NULL now, so CTRL-G '
                     'prints the special name and never a path -- the else arm, '
                     'which read b_fname and b_ffname, cannot be entered')

# C7, C8  buf_spname and buf_get_fname: each is one `if` and a second `return`.
#     Exact text, because fold_always would leave that second return unreachable.
t = text_edit(t,
              'buf_spname(buf_T *buf)\n'
              '{\n'
              '    if (buf->b_fname == NULL)\n'
              '    {\n'
              '        return buf_get_fname(buf);\n'
              '    }\n'
              '    return NULL;\n'
              '}\n',
              'buf_spname(buf_T *buf)\n'
              '{\n'
              '    return buf_get_fname(buf);\n'
              '}\n',
              'buf_spname: `b_fname == NULL` is TRUE, so it answers for every '
              'buffer and can no longer return NULL')
t = text_edit(t,
              'buf_get_fname(buf_T *buf)\n'
              '{\n'
              '    if (buf->b_fname == NULL)\n'
              '    {\n'
              '        return (char_u *)_("[No Name]");\n'
              '    }\n'
              '    return buf->b_fname;\n'
              '}\n',
              'buf_get_fname(buf_T *buf)\n'
              '{\n'
              '    return (char_u *)_("[No Name]");\n'
              '}\n',
              'buf_get_fname: the same, and "[No Name]" is now the only name the '
              'editor has for a buffer')

# C9  check_changed_any: `buf_spname(buf) != NULL` is TRUE.
t = text_edit(t,
              '        if (semsg(_(e_no_write_since_last_change_for_buffer_str), buf_spname(buf) != NULL ? buf_spname(buf) : buf->b_fname))\n',
              '        if (semsg(_(e_no_write_since_last_change_for_buffer_str), buf_spname(buf)))\n',
              'check_changed_any: buf_spname() is non-NULL, so E162 names the '
              'buffer through it and never through b_fname')

# C10 check_fname: `b_ffname == NULL` is TRUE, so E32 is what it always says.  It
#     STAYS -- get_spec_reg's `%` still calls it, which is why "E32: No file name"
#     survives this phase where the word "file" does not.
t = text_edit(t,
              'check_fname(void)\n'
              '{\n'
              '    if (curbuf->b_ffname == NULL)\n'
              '    {\n'
              '        emsg(_(e_no_file_name));\n'
              '        return FAIL;\n'
              '    }\n'
              '    return OK;\n'
              '}\n',
              'check_fname(void)\n'
              '{\n'
              '    emsg(_(e_no_file_name));\n'
              '    return FAIL;\n'
              '}\n',
              'check_fname: E32 for every buffer, and it stays because the `%` '
              'register still asks it')

# C11 shorten_buf_fname: `b_fname != NULL` is FALSE, so the body can never run and
#     the function is empty.  Part F then removes its only call.
t = fold(t, 'shorten_buf_fname', 'never',
         r'^    if \(buf->b_fname != NULL && !path_with_url\(buf->b_fname\) && \(force \|\| buf->b_sfname == NULL \|\| mch_isFullName\(buf->b_sfname\)\)\)$',
         'shorten_buf_fname: `b_fname != NULL` is FALSE, so there is no path to '
         'shorten and the function has nothing left to do')

# C12 file_name_at_cursor: the buffer's name is what a relative path was resolved
#     against.  NULL is what it passes now, which is the value it held.
t = text_edit(t,
              '    return file_name_in_line(ml_get_curline(), curwin->w_cursor.col, options, count, curbuf->b_ffname, file_lnum);\n',
              '    return file_name_in_line(ml_get_curline(), curwin->w_cursor.col, options, count, NULL, file_lnum);\n',
              'file_name_at_cursor: `curbuf->b_ffname` is the NULL it passes now')

# C13 set_b0_fname: `b_ffname == NULL` is TRUE, so block zero's name field is empty
#     and the stat()/home_replace() arm cannot run.  It has an else.
t = fold_always_else(t, 'set_b0_fname', '    if (buf->b_ffname == NULL)\n',
                     "set_b0_fname: `b_ffname == NULL` is TRUE, so block zero's "
                     'file name is empty -- and the stat() in the arm that goes is '
                     'one of the two this phase takes')

# C14 get_spec_reg: the `%` register is the buffer's name.
t = text_edit(t, '            *argp = curbuf->b_fname;\n', '            *argp = NULL;\n',
              'get_spec_reg: the `%` register is `b_fname`, which is NULL -- the '
              'register already yielded nothing, and check_fname() above it still '
              'says E32')

# C15 ex_display, twice.  The `"%` block's guard is FALSE; the `"#` block's inner
#     test is buflist_name_nr(), FAIL ALWAYS, so the whole outer block does nothing.
t = fold(t, 'ex_display', 'never',
         r"^    if \(curbuf->b_fname != NULL && \(arg == NULL \|\| vim_strchr\(arg, '%'\) != NULL\) && !got_int && !message_filtered\(curbuf->b_fname\)\)$",
         'ex_display: the `"%` line of :registers needs a buffer name and there is '
         'none -- it was already never printed')
t = fold(t, 'ex_display', 'drop',
         r"^    if \(\(arg == NULL \|\| vim_strchr\(arg, '#'\) != NULL\) && !got_int\)$",
         'ex_display: and the `"#` block goes whole, because buflist_name_nr() '
         'inside it is FAIL ALWAYS and the block holds nothing else -- which is '
         "what makes that function uncalled and the sweep's")

# C16 get_trans_bufname: buf_spname() is non-NULL, so the status line and :ls take
#     the special name.  It has an else.
t = fold_always_else(t, 'get_trans_bufname', '    if (buf_spname(buf) != NULL)\n',
                     'get_trans_bufname: buf_spname() is non-NULL, so every window '
                     'and every :ls row reads "[No Name]" -- as they already did')

if mentions(t, 'buflist_name_nr') != 1:
    die('buflist_name_nr has %d mentions after both callers were folded, expected '
        '1 -- its definition, for the sweep' % mentions(t, 'buflist_name_nr'))

# ---- D. EX_XFILE reaches zero rows ------------------------------------------------------
# `:file` was the last cmdnames[] row carrying EX_XFILE, exactly as `:read` and the
# four :edit-family rows were EX_ARGOPT's in phases 7 and 8.  So do_one_cmd's
# expand_filename() call can never be entered, and folding it never is what hands
# the sweep the whole command-line expansion layer.
left = [r for r in re.findall(r'^    \[CMD_\w+\] = \{.*$', t, re.M) if 'EX_XFILE' in r]
if left:
    die('%d cmdnames[] rows still carry EX_XFILE, so the fold below would be a '
        'guess: %s' % (len(left), left[0][:60]))
say('no cmdnames[] row carries EX_XFILE any more -- :file was the last, as :read '
    "was EX_ARGOPT's in phase 7 and the :edit family in phase 8")
t = fold(t, 'do_one_cmd', 'never',
         r'^    if \(\(ea\.argt & EX_XFILE\) && expand_filename\(&ea, cmdlinep, &errormsg\) == FAIL\)$',
         "do_one_cmd's expand_filename() call: `ea.argt & EX_XFILE` is 0 for every "
         'command, so this is the anchor the sweep reads the whole '
         'filename-expansion layer from')
t = text_edit(t, '            if (eap->argt & (EX_CTRLV | EX_XFILE))\n',
              '            if (eap->argt & EX_CTRLV)\n',
              "separate_nextcmd's CTRL-V test: the EX_XFILE disjunct is 0 for every "
              'row, and dropping it is what takes the enumerator to zero mentions')
if mentions(t, 'EX_XFILE') != 1:
    die('EX_XFILE has %d mentions, expected 1 -- its own definition, for the sweep'
        % mentions(t, 'EX_XFILE'))

# ---- E. the two write-only leftovers -------------------------------------------------
# NOTHING SEES EITHER OF THESE.  A file-scope static that is assigned and never read
# draws no warning, tools/deadsweep.py acts on warnings, and tools/deadfields.py
# removes a field nothing NAMES -- a field only written is still named.  So both go
# here, by hand, and the sweep takes what they orphan.
t = fold(t, 'did_set_readonly', 'drop',
         r'^    if \(!curbuf->b_p_ro && \(args->os_flags & OPT_LOCAL\) == 0\)$',
         "did_set_readonly's readonlymode write, with the `if` around it: C1 took "
         'the only reader, and an `if` with an empty body is not something any tool '
         'here removes')
t = text_edit(t, 'static int      readonlymode  = FALSE ;\n', '',
              'and the definition of readonlymode, which phase 8 asserted at 5 '
              'mentions and phase 9 at 3')
t = within(t, 'buflist_new', '    buf->b_dev_valid = false;\n', '',
           "b_dev_valid's one surviving assignment, which part B left: every reader "
           'is inside a function the sweep takes, and deadfields.py cannot remove a '
           'field that is still written')

# ---- F. shorten_fnames stops asking where it is ---------------------------------------
# shorten_buf_fname() is empty after C11, so the cwd shorten_fnames() fetched for it
# is fetched for nothing.  mch_dirname() is getcwd()'s and strerror()'s only caller
# here, once the sweep has taken shorten_fname() and mch_FullName().
t = within(t, 'shorten_fnames',
           '    char_u      dirname[ PATH_MAX ];\n'
           '    buf_T       *buf;\n'
           '\n'
           '    mch_dirname(dirname,  PATH_MAX );\n'
           '     buf = curbuf;\n'
           '    shorten_buf_fname(buf, dirname, force);\n'
           '\n', '',
           'shorten_fnames: the cwd, and the call to a function with an empty body')
t = text_edit(t, 'static void shorten_fnames(int force);\n',
              'static void shorten_fnames(void);\n',
              'and its prototype takes void, because an unused PARAMETER is what '
              "tools/sweep.sh's -Wno-unused-parameter cannot see -- phase 9's "
              'anchor 4 measured that')
t = text_edit(t, 'shorten_fnames(int force)\n', 'shorten_fnames(void)\n',
              'the definition with it')
t = text_edit(t, '    shorten_fnames(FALSE);\n', '    shorten_fnames();\n',
              'and its one call site')

# ---- G. nothing looks a name up on a disk -----------------------------------------------
# find_file_name_in_path() is CTRL-F's and CTRL-P's, through file_name_at_cursor().
# The FNAME_EXP arm searched 'path' for the word under the cursor and mch_getperm()ed
# each candidate; the other arm returns the word itself.  Folding the arm never is
# the charter reading of "no filesystem access": the editor extracts text and asks
# nothing.  find_file_in_path() and its mch_getperm() are then the sweep's, and
# stat() goes with them.
t = fold(t, 'find_file_name_in_path', 'never', r'^    if \(options & FNAME_EXP\)$',
         'find_file_name_in_path: the `path` search arm goes, so CTRL-F and CTRL-P '
         'both extract the word under the cursor and neither consults a disk -- '
         'this is the fold that frees stat()')

# ---- what the sweep is handed, as a count rather than as trust -------------------------
# EVERY SURVIVING MENTION OF THE THREE FIELDS IS INSIDE ONE OF FIVE FUNCTIONS, and
# not one of the five has a reference the sweep can reach: setfname and
# rename_buffer through the row part A removed, otherfile_buf and buf_setino
# through setfname, eval_vars through the expand_filename() call part D folded, and
# buflist_name_nr through the two callers part C folded -- which is the whole point
# of folding it AT its callers rather than inside it.
# THE EDIT ITSELF LEAVES WRITES -- inside those five -- which is why the claim is
# stated this way and not as "nothing writes them": it is the argument that the
# sweep's first round can start, exactly as phases 6, 7 and 8 state theirs, and
# deadfields.py takes the three fields once funcreach.py has taken the five.
READERS = {'setfname', 'rename_buffer', 'otherfile_buf', 'buf_setino', 'eval_vars',
           'buflist_name_nr'}
offs, writes = [], 0
for fld in FIELDS:
    offs += uses(t, fld)
    writes += len(assignments(t, fld))
got = functions_holding(t, offs, READERS)
if got != READERS:
    die('the surviving mentions of the three fields are in %s, expected exactly %s'
        % (' '.join(sorted(got)), ' '.join(sorted(READERS))))
say('%d mentions of b_ffname, b_sfname and b_fname are left, %d of them writes, and '
    'every one is inside setfname, rename_buffer, otherfile_buf, buf_setino, '
    'eval_vars or buflist_name_nr -- none of which has a caller the sweep can '
    'reach' % (len(offs), writes))

AFTER = {'CMD_file': 0, 'EX_XFILE': 1, 'buflist_name_nr': 1, 'readonlymode': 0,
         'shorten_buf_fname': 1, 'check_fname': 3, 'buf_get_fname': 3,
         'check_changed': 4, 'no_write_message': 3, 'p_ur': 2, 'p_ro': 2,
         'read_cmd_fd': 12, 'vim_fsync': 3, 'scriptin': 8, 'redir_fd': 6}
for name, want in sorted(AFTER.items()):
    k = mentions(t, name)
    if k != want:
        die('%s has %d mentions after the cut, expected %d' % (name, k, want))
say('the cut is done: CMD_file 0, EX_XFILE 1 (its own definition), buflist_name_nr '
    '1, readonlymode 0 -- and read_cmd_fd 12, vim_fsync 3, scriptin 8 and redir_fd '
    "6 untouched, each of them a later phase's")

open(path, 'w', errors='surrogateescape').write(t)
PY

# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  noname       the input binary did not build with '$cflags' '$ldflags'"; exit 1; }
echo "  noname       the input is $state/old, $(stat -c%s "$state/old") bytes, beside the source it was built from: :file NEWNAME is the only evidence the old binary could name a buffer at all, and no recording can see it"

# tools/phaserun.sh sweeps next, then runs pipes/zero10-check.sh.
