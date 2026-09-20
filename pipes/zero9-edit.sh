#!/bin/sh
# Zero phase 9 -- nothing reads a byte.
# See ZERO-GOAL.md.
#
# Usage: pipes/zero9-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# Phases 6, 7 and 8 took every way to ASK for a file: the six commands that put
# bytes on a disk, the one that takes them off it, and the five that point the
# editor at another one.  What was left of reading a file is the machinery under
# those commands -- `readfile()`, 787 lines, and the two arms of `open_buffer()`
# that call it.  This phase takes those arms, and the sweep takes the machinery.
#
# READFILE() WAS ALREADY UNREACHABLE WHEN THIS PHASE WAS HANDED THE TREE, and that
# is the whole of what makes the phase delicate rather than difficult.  Its three
# call sites are one in `read_buffer()` and two in `open_buffer()`, and
# `read_buffer`'s only callers are those same two arms; the outer arm needs
# `curbuf->b_ffname != NULL` and the inner one needs a `read_stdin` argument that,
# since phase 5 removed the file argument and the bare `-`, all four callers pass
# as FALSE.  So no input this editor can be given reaches it, and gcc keeps it only
# because it cannot prove `b_ffname != NULL` never holds.  The difference this
# phase makes is between code that cannot run and code that is not there -- and
# because it IS that, no behavioural probe can see it.  pipes/zero9-check.sh says
# what stands in for one: the input source built twice, instrumented.
#
# FOUR ANCHORS, ALL INSIDE open_buffer(), and everything else is the sweep's
# (ZERO-GOAL.md rule 1: removal is computed, not listed).  Sixteen functions go
# without one of them being named here.
#
#   1. the `if (curbuf->b_ffname != NULL) {...} else if (read_stdin) {...}` pair,
#      as exact text with the blank line after it.  That is the entire cut: the two
#      arms hold all three calls into the read path.
#   2. `int read_fifo = FALSE;` -- set nowhere once anchor 1 has gone, read twice.
#   3. `else if (retval == OK && !read_stdin && !read_fifo)` -> `else if (retval ==
#      OK)`, which is where anchor 2's second reader was.
#   4. the signature: `open_buffer(int read_stdin, exarg_T *eap, int flags_arg)` ->
#      `open_buffer(void)`, the `int flags = flags_arg;` local, and the four call
#      sites, every one of which already passes `FALSE, NULL, 0`.
#
# ANCHOR 4 IS WHAT TAKES read_stdin TO ZERO, and it is measured rather than argued.
# Without it `open_buffer` keeps three parameters that nothing reads, and THE SWEEP
# CANNOT SEE THEM: tools/sweep.sh compiles with `-Wno-unused-parameter`, so an
# unused parameter is invisible where an unused local is not -- measured, anchors
# 1-3 alone leave the `int flags = flags_arg;` local deleted by the sweep's own
# unused-variable pass and `read_stdin` alive at exactly ONE mention, the parameter
# nothing reads.  Both swept files are 82,572 lines and differ in exactly five
# lines -- the signature and the four calls -- and THE TWO RECORDINGS ARE
# BYTE-IDENTICAL, as are the two binaries' sizes.  So the fold costs nothing, says
# what is true, and is taken.
#
# THERE IS NO PROTOTYPE FOR open_buffer.  It is defined above its first call, so
# the `static int open_buffer(...)` line the proto block would hold does not exist
# and a phase that edits one fails loudly.  Anchor 4 edits the definition alone.
#
# THE FURTHER FOLD IS DECLINED, DELIBERATELY.  After anchor 1, `retval` in
# `open_buffer` is `OK` from its initialiser to its return and nothing between can
# change it, so `if (retval != OK) return retval;` is dead, the function could be
# `void`, and the two `open_buffer() == FAIL` guards in the `ml_*` layer can never
# hold.  That is memline tidy and not the read path; this phase asserts `retval` at
# its 5 mentions and says it is constant, and leaves the fold to a later one.
#
# THE INPUT BINARY IS BUILT HERE, before the edit, from the boundary's own makefile
# flags, exactly as pipes/zero2-edit.sh and zero4- through zero8-edit.sh do it, and
# the source goes with it as $state/old.c.  The check needs BOTH: the binary is the
# left-hand side of every "this did not move" comparison, and the source is what it
# builds twice more, instrumented, for the only evidence this phase has.
set -eu

work=${1:?usage: zero9-edit.sh <work-dir> <state-dir>}
state=${2:?usage: zero9-edit.sh <work-dir> <state-dir>}
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
TAG = 'nobyte'
import re, sys
sys.path.insert(0, 'tools')
# tools/cutil.py -- named as a PATH so tools/implhash.sh hashes it into this
# phase's key.  implhash greps for paths and an `import` names a module, so
# without this line an edit to it changes what this phase produces and moves
# no key at all.  See CLAUDE.md on cutil.py and macros.py.  Do not delete it.
import cutil
path = sys.argv[1]
t = open(path, errors='surrogateescape').read()


def die(msg):
    sys.exit('  %-12s %s' % (TAG, msg))


def say(what):
    print('  %-12s %s' % (TAG, what))


def mentions(text, name):
    return len(re.findall(r'\b%s\b' % name, text))


def in_function(text, name, edit):
    span = cutil.find_definition(text, name)
    if not span:
        die('%s is not defined' % name)
    a, z = span
    return text[:a] + edit(text[a:z]) + text[z:]


def within(text, fn, old, new, what, n=1):
    """Replace exact text inside one function, counted there and not file-wide."""
    def edit(s):
        k = s.count(old)
        if k != n:
            die('%s -- %r occurs %d times in %s, expected %d'
                % (what, old[:60], k, fn, n))
        return s.replace(old, new)
    out = in_function(text, fn, edit)
    say(what)
    return out


# ---- 0. the shape the anchors below were counted on -------------------------------
# open_buffer AT EXACTLY 5 IS WHY THIS PHASE NEEDS SWEPT TEXT (`need 9 swept`).  On
# the text phase 8's EDIT leaves there are six: do_ecmd still exists to make the
# sixth, `(void)open_buffer(FALSE, eap, readfile_flags);`, and it is the one call
# site anchor 4's rewrite would not match -- so the count refuses here rather than
# leaving a three-argument call to a no-argument function for the sweep to hide.
k = mentions(t, 'open_buffer')
if k != 5:
    die('open_buffer has %d mentions, expected 5 -- the definition and four callers, '
        'every one of them `open_buffer(FALSE, NULL, 0)`.  On the text phase 8\'s '
        'EDIT leaves there are six: do_ecmd is still there to make '
        '`(void)open_buffer(FALSE, eap, readfile_flags);`, which anchor 4 would not '
        'rewrite.  This phase needs swept text' % k)
BEFORE = {'readfile': 5,           # prototype, definition, and the three calls
          'read_buffer': 17,       # its own, and the two calls in the arms
          'read_stdin': 23,        # readfile's local, read_buffer's and open_buffer's
          'read_fifo': 9,          # the same shape: anchor 2 is open_buffer's
          'check_readonly': 4,     # readfile's local -- it reaches 0 here, not at 6
          'msg_scrolled_ign': 6,   # a declaration, four writers and one reader
          'filemess': 11,
          'read_cmd_fd': 12}       # the terminal's, and untouched: 11 lines, 12 mentions
for name, want in sorted(BEFORE.items()):
    k = mentions(t, name)
    if k != want:
        die('%s has %d mentions, expected %d -- the anchors below were counted '
            'against a different file' % (name, k, want))
say('open_buffer 5, readfile 5, read_buffer 17, read_stdin 23 -- the file the four '
    'anchors were counted against')

# ---- 1. the two arms, which hold every call into the read path --------------------
# Exact text, counted inside open_buffer and not file-wide, with the blank line
# after it.  Nothing here is folded: both arms go whole.
ARMS = """    if (curbuf->b_ffname != NULL)
    {
        int old_msg_silent = msg_silent;
        int perm;
        perm = mch_getperm(curbuf->b_ffname);
        if (perm >= 0 && (S_ISFIFO(perm) || S_ISSOCK(perm)))
        {
                read_fifo = TRUE;
        }
        if (shortmess(SHM_FILEINFO))
        {
            msg_silent = 1;
        }
        retval = readfile(curbuf->b_ffname, curbuf->b_fname, (linenr_T)0, (linenr_T)0, (linenr_T) LONG_MAX , eap, flags | READ_NEW | (read_fifo ? READ_FIFO : 0));
        if (read_fifo)
        {
            if (retval == OK)
            {
                retval = read_buffer(FALSE, eap, flags);
            }
        }
        msg_silent = old_msg_silent;
        if (bt_help(curbuf))
        {
            fix_help_buffer();
        }
    }
    else if (read_stdin)
    {
        retval = readfile(NULL, NULL, (linenr_T)0, (linenr_T)0, (linenr_T) LONG_MAX , NULL, flags | (READ_NEW + READ_STDIN));
        if (retval == OK)
        {
            retval = read_buffer(TRUE, eap, flags);
        }
    }

"""
t = within(t, 'open_buffer', ARMS, '',
           "open_buffer's two read arms, 36 lines: both calls to readfile(), both "
           'to read_buffer(), and the fifo test between them')

# ---- 2. read_fifo, written nowhere now --------------------------------------------
t = within(t, 'open_buffer', '    int         read_fifo = FALSE;\n', '',
           'the read_fifo local: anchor 1 was its only writer')

# ---- 3. the unchanged() test, where its second reader was -------------------------
# read_stdin and read_fifo are both FALSE here for ever, so the conjuncts are true
# and the fold states that rather than keeping two tests with fixed answers.
t = within(t, 'open_buffer',
           '    else if (retval == OK && !read_stdin && !read_fifo)\n',
           '    else if (retval == OK)\n',
           'the unchanged() arm: !read_stdin and !read_fifo were both constantly true')

# ---- 4. the signature, and the four callers ---------------------------------------
# What takes read_stdin to 0.  Left alone, three parameters nothing reads survive
# behind the sweep's -Wno-unused-parameter; see the head of this file.
t = within(t, 'open_buffer',
           'open_buffer(int         read_stdin, exarg_T     *eap, int         flags_arg)\n',
           'open_buffer(void)\n',
           'open_buffer(void): read_stdin, eap and flags_arg are read by nothing '
           'now, and there is no prototype to follow')
t = within(t, 'open_buffer', '    int         flags = flags_arg;\n', '',
           'the flags local, which only the deleted arms passed on')
CALLS = 4
k = t.count('open_buffer(FALSE, NULL, 0)')
if k != CALLS:
    die('open_buffer is called %d times as `open_buffer(FALSE, NULL, 0)`, expected '
        '%d -- every caller already passes FALSE, NULL and 0, and a caller that '
        'does not is one this fold would change' % (k, CALLS))
t = t.replace('open_buffer(FALSE, NULL, 0)', 'open_buffer()')
say('the four call sites -- enter_buffer, ml_append_flags, ml_replace_len and '
    'create_windows -- every one of which passed FALSE, NULL, 0')

# ---- 5. what is left, and what is deliberately left ------------------------------
# retval is OK from its initialiser to its return: nothing between them assigns it
# now.  So `if (retval != OK) return retval;` is dead, open_buffer could be void,
# and the two `open_buffer() == FAIL` guards in the ml_ layer can never hold.  That
# is memline tidy and not the read path -- stated here as a count so that a later
# phase taking it has to move this number.
span = cutil.find_definition(t, 'open_buffer')
if not span:
    die('open_buffer no longer parses as a definition')
body = t[span[0]:span[1]]
for gone in ('read_stdin', 'read_fifo', 'eap', 'flags', 'readfile', 'read_buffer'):
    if mentions(body, gone):
        die('%s is still named inside open_buffer' % gone)
assigns = re.findall(r'\bretval\b\s*=[^=]', body)
if len(assigns) != 1 or mentions(body, 'retval') != 5:
    die('retval is assigned %d times in open_buffer and mentioned %d: this phase '
        'leaves exactly one assignment, the initialiser, and 5 mentions'
        % (len(assigns), mentions(body, 'retval')))
say('open_buffer is %d lines and calls nothing that reads: retval is OK from its '
    'initialiser to its return, so `if (retval != OK) return retval;` is dead and '
    'the two ml_ guards can never hold -- left for a later tidy, not folded here'
    % body.count('\n'))

# WHAT THE SWEEP IS HANDED, as a count rather than as trust.  Unlike phases 6, 7 and
# 8, this edit leaves text that COMPILES: nothing it removed was named from outside
# what it removed, so there is no dangling enumerator and no handler without a row.
# `readfile` goes 5 -> 3 -- a prototype, a definition and the one call inside
# read_buffer(), which now has no caller of its own -- and `read_buffer` 17 -> 15,
# of which FOURTEEN are readfile's own local `int read_buffer = (flags &
# READ_BUFFER);` and one is the definition.  That is why the count is not zero and
# why the function is still dead.
after = {'readfile': 3, 'read_buffer': 15, 'read_stdin': 20, 'read_fifo': 4}
for name, want in sorted(after.items()):
    k = mentions(t, name)
    if k != want:
        die('%s has %d mentions after the cut, expected %d' % (name, k, want))
say('readfile 5 -> 3 and read_buffer 17 -> 15, and the survivors are not calls: a '
    "prototype, two definitions and fourteen mentions of readfile's own local of "
    'the same name.  read_buffer and fix_help_buffer are the two entry points the '
    'sweep starts from, and they are exactly the two -Wunused-function warnings '
    'this text produces')

open(path, 'w', errors='surrogateescape').write(t)
PY

# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  nobyte       the input binary did not build with '$cflags' '$ldflags'"; exit 1; }
echo "  nobyte       the input is $state/old, $(stat -c%s "$state/old") bytes, beside the source it was built from: no recording can see this phase, so the check builds that source twice more with readfile() and open_buffer() instrumented"

# tools/phaserun.sh sweeps next, then runs pipes/zero9-check.sh.
