#!/bin/sh
# Zero phase 42 -- the swap file's residue.  See ZERO-GOAL.md and ZERO-PLAN.md 4a.
#
# Usage: pipes/zero42-edit.sh <work-dir> <state-dir>     (run from the repository root)
#
# THE FILESYSTEM WENT AT PHASES 6 TO 10 AND THE SWAP FILE'S MACHINERY DID NOT.  memline
# and memfile still keep the bookkeeping of a file that is written to a disk: a header
# block with the editor's version and the buffer's name in it, a translation table for
# blocks that have not been written out yet, a dirtiness state machine, and a record of
# where each block's lines USED to be.  None of it can be reached and none of it is read.
#
# EVERY ONE OF THESE FOUR GROUPS IS INVISIBLE TO EVERY TOOL IN tools/, AND FOR ONE
# REASON: they are all WRITTEN.  tools/deadfields.py takes a field named nowhere outside
# its own type, and each of these is named; tools/deadsweep.py asks gcc, and gcc has no
# warning for a struct member nothing reads, for an enumerator that is only ever OR-ed
# into a word nothing tests, or for a file-scope object that is read and never assigned.
# Run against the input, deadfields.py reports 0 fields.  So this is an EDIT and not a
# sweep, and the division of labour is stated rather than hoped for: the edit takes
# everything that is written, and the check names what is left standing for the sweep and
# what the sweep then found.
#
#   1  BLOCK ZERO.  `struct block0` is the swap file's header.  Its fields -- the two
#      identifying bytes, the version string, the page size, the file name and the four
#      magic numbers -- are WRITTEN in ml_open() and ml_setflags() and READ NOWHERE, in
#      any build of zero-vim, and the edit proves that as a partition over every mention
#      of every one of them: a declaration, an assignment, or a call that copies INTO the
#      field.  Nothing may yield a value.  The field list is read out of the struct rather
#      than typed here, because zero phase 36 already took `b0_pid` and a typed list would
#      be a phase out of date.
#
#      THE TWO SURVIVING BLOCKS MOVE DOWN BY ONE.  ml_open() allocated block nr 0 for the
#      header, 1 for the root pointer block and 2 for the first data block, and with the
#      header gone the pointer block is 0 and the data block 1.  Five numbers say so, and
#      two of them are outside ml_open(): ml_find_line() starts its descent at the root,
#      and ml_append_int() recognises the root by its block number when a split reaches
#      the top of the tree and the root has to be kept where the reader starts.  The
#      check's controls are on those two.
#
#   2  NEGATIVE BLOCK NUMBERS.  mf_trans_add() returns before it does anything unless a
#      block number is negative, and a block number is negative only if mf_new() is called
#      with `negative` TRUE.  THE CHAIN IS COMPUTED HERE AND NOT ASSERTED FROM A SURVEY:
#      mf_new()'s callers pass FALSE or ml_new_data()'s own parameter; ml_new_data()'s
#      callers pass FALSE or `flags & ML_APPEND_NEW`; ML_APPEND_NEW is set only by
#      ml_append()'s `newfile`; and `newfile` is FALSE at every ml_append() call site in
#      the file.  So `negative` is FALSE at every reachable call, no block number is ever
#      negative, mf_trans_add() is a no-op, the translation table is always empty and
#      ml_find_line()'s `bnum < 0` arm is unreachable.  The phase removes the whole
#      island: two functions, three memfile fields, the parameter, and the two flags whose
#      only purpose was to choose between marking a block dirty and calling the no-op.
#
#   3  THE DIRTINESS, WRITE-ONLY IN ALL THREE OF ITS LAYERS.  `mf_dirty` is a three-valued
#      field with six writes and two reads, and EACH READ IS THE CONDITION OF AN `if`
#      WHOSE ONLY STATEMENT WRITES THE FIELD AGAIN -- so nothing outside the field ever
#      learns its value, which the edit checks structurally.  `BH_DIRTY` is set three
#      times and never tested: `bh_flags` is read in exactly one place and that read
#      tests BH_LOCKED.  And ML_LOCKED_DIRTY and ML_LOCKED_POS, the memline's own pair,
#      are read at exactly one place between them -- the two arguments mf_put() is about
#      to stop taking.  mf_put() becomes `mf_put(bhdr_T *hp)`, which clears BH_LOCKED and
#      is the whole of what it did that anything reads.
#
#   4  pe_old_lnum, AND THE TWO LOCALS THAT EXIST ONLY TO FEED IT.  Seven writes, no read.
#      Four of the seven are the only statement of an `if`, and the two variables those
#      `if`s test are computed by a fourteen-line branch and used nowhere else -- so once
#      the field goes, gcc says `-Wunused-but-set-variable` for both, which
#      tools/deadsweep.py does not act on (CLAUDE.md, *Audit for dead code*).  The same is
#      true of ml_find_line()'s `dirty`, which was mf_put()'s third argument.  All three
#      are therefore the edit's.
#
#      AND mf_dont_release, WHICH IS A CONSTANT.  `static int mf_dont_release = FALSE;`,
#      read twice and ASSIGNED NOWHERE IN THE FILE.  No warning gcc emits covers a
#      file-scope object in either direction, so nothing here has ever been able to see
#      it.
#
# THE FANOUT CHANGES AND THAT IS NOT A BEHAVIOUR.  `pe_old_lnum` is a member of PTR_EN,
# the pointer-block entry, so taking it makes each entry smaller and more of them fit in
# a page.  The tree the editor builds for a given buffer is therefore shaped differently
# after this phase, which is a representation and not an observable -- and the check does
# not leave that to be believed: it drives both binaries to sixty thousand lines, where
# an instrumented build says the root pointer block really does overflow and the
# root-preserving branch really does run, and requires the two to draw the same screen.
#
# WHAT THIS PHASE DOES NOT TAKE.  `BH_LOCKED` looks like BH_DIRTY's twin and is not: it
# is read, by mf_put()'s `e_block_was_not_locked` assertion.  Measured -- a binary whose
# mf_put() SETS the bit instead of clearing it draws exactly the same 102 screen cases,
# because the only reader is an internal-error test that then never fires -- so it is
# unreachable EVIDENCE and not unreachable code, and the bit stays.
#
# THE INPUT BINARY IS BUILT HERE with SOURCE_DATE_EPOCH=0, and the check records from it.
# The edit also leaves its own output in $state/edit.c, so the check can state what the
# EDIT removed and what the SWEEP removed separately rather than as one number.
set -eu

work=${1:?usage: zero42-edit.sh <work-dir> <state-dir>}
state=${2:?usage: zero42-edit.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"

# The flags are read out of the boundary's makefile rather than written here a second
# time: zero's compile line is the boundary's (ZERO-GOAL.md rule 8).
cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")
cp "$f" "$state/old.c"
# shellcheck disable=SC2086
( cd "$state" && SOURCE_DATE_EPOCH=0 gcc $cflags $ldflags -o old old.c ) &
pid_old=$!

python3 - "$f" "$state" <<'PY'
import re
import sys

path = sys.argv[1]
state = sys.argv[2]
t = open(path, errors='surrogateescape').read()
TAG = 'swapres'


def die(msg):
    sys.exit('  %-12s %s' % (TAG, msg))


def say(what):
    print('  %-12s %s' % (TAG, what))


def mentions(text, name):
    return len(re.findall(r'\b(?:%s)\b' % name, text))


def blank_runs(text):
    L = text.split('\n')
    return sum(1 for i in range(1, len(L)) if L[i] == '' and L[i - 1] == '')


def lines():
    return t.split('\n')


def swap(old, new, what, why, n=1):
    global t
    c = t.count(old)
    if c != n:
        die('%s occurs %d times, expected %d -- %s' % (what, c, n, why))
    t = t.replace(old, new)


def drop(old, what, why, n=1):
    swap(old, '', what, why, n)


def partition(name, classes, what):
    """Every line that says `name` falls in exactly one class, and a leftover refuses.
    classes is a list of (label, pattern); returns {label: [line indices]}."""
    L = lines()
    seen = [i for i, l in enumerate(L) if re.search(r'\b(?:%s)\b' % name, l)]
    out = {}
    for label, pat in classes:
        out[label] = []
    for i in seen:
        hit = [label for label, pat in classes if re.search(pat, L[i])]
        if len(hit) != 1:
            die('`%s` at line %d -- %s -- falls in %d of the %d classes this phase '
                'accounts for (%s), and every mention must fall in exactly one'
                % (name, i + 1, L[i].strip(), len(hit), len(classes),
                   ', '.join(label for label, _ in classes)))
        out[hit[0]].append(i)
    for label, pat in classes:
        if not out[label]:
            die('the class `%s` of `%s` holds no mention of it, so it is not a class of '
                'this tree' % (label, name))
    say('%s: %d mentions, every one in a class this phase accounts for -- %s'
        % (what, len(seen), ', '.join('%s %d' % (label, len(out[label]))
                                      for label, _ in classes)))
    return out


def body(name):
    """The half-open line range of a definition in this tree's one shape: the name at
    column 0 with `(` after it, `{` at column 0 next, closed by `}` at column 0, with
    the return type on the indented line above."""
    L = lines()
    heads = [i for i, l in enumerate(L)
             if re.match(r'^%s\s*\(' % name, l) and i + 1 < len(L) and L[i + 1] == '{']
    if len(heads) != 1:
        die('`%s` is defined %d times at column 0 and this phase needs exactly one'
            % (name, len(heads)))
    end = heads[0]
    while end < len(L) and L[end] != '}':
        end += 1
    if end >= len(L):
        die('`%s` does not close at column 0' % name)
    if not re.match(r'^    [\w *]+$', L[heads[0] - 1]):
        die("the line above `%s`'s head is %r, and every definition in this tree "
            'carries its return type there, indented' % (name, L[heads[0] - 1]))
    return heads[0] - 1, end + 1


def cut_defn(name, why):
    """Take a whole definition out, with the blank line that separates it."""
    lo, hi = body(name)
    L = lines()
    if L[hi] != '':
        die("`%s`'s definition is not followed by a blank line" % name)
    drop('\n'.join(L[lo:hi + 1]) + '\n', "`%s`'s definition" % name, why)
    return hi + 1 - lo


def cut_range(lo, hi, what, why):
    """Take lines [lo, hi) out, as one counted replacement of their exact text."""
    L = lines()
    drop('\n'.join(L[lo:hi]) + '\n', what, why)
    return hi - lo


def cut_at(idx, what, why):
    """Delete the given lines, by the indices a partition computed a moment ago, after
    checking that each is still the line that was classified."""
    global t
    L = lines()
    was = [L[i] for i in idx]
    for i in sorted(idx, reverse=True):
        del L[i]
    t = '\n'.join(L)
    return was


def only(pred, what, lo=0, hi=None, n=1):
    L = lines()
    hi = len(L) if hi is None else hi
    got = [i for i in range(lo, hi) if pred(L[i])]
    if len(got) != n:
        die('%s: %d lines where this phase needs %d -- %s'
            % (what, len(got), n,
               ' '.join('%d:%s' % (i + 1, L[i].strip()) for i in got[:6]) or 'none'))
    return got if n != 1 else got[0]


lines_before = len(lines()) - 1
runs_before = blank_runs(t)
directives_before = [i for i, l in enumerate(lines()) if re.match(r'^ *# *', l)]
say('the input is %d lines with %d preprocessor directives, the first at line %d -- '
    'this phase adds no directive and removes none'
    % (lines_before, len(directives_before), directives_before[0] + 1))

# =====================================================================================
# PART 1 -- THE SWAP FILE'S HEADER BLOCK.  `struct block0` is nine fields, and every
# one of them is WRITTEN and NONE is READ.  That is the whole argument, and it is a
# partition over every mention rather than a count: a declaration, an assignment, or a
# call that copies INTO the field.  Nothing may yield its value.
# =====================================================================================
# The field list is READ OUT OF THE STRUCT and not written here: phase 36 already took
# `b0_pid`, so a list typed from a survey would be one name long.
L = lines()
sb = only(lambda l: l == 'struct block0', '`struct block0`')
if L[sb + 1] != '{':
    die('`struct block0` does not open on the line below its tag')
end = sb + 2
while end < len(L) and L[end] != '};':
    end += 1
FIELDS = [re.match(r'^    [\w ]+?(\w+) *(\[[^]]*\])?;$', L[i]).group(1)
          for i in range(sb + 2, end)]
if len(FIELDS) < 5 or any(not f.startswith('b0_') for f in FIELDS):
    die('`struct block0` has members %s, and this phase was written against a header '
        'block whose every field is a `b0_`' % ' '.join(FIELDS))
say('`struct block0` is the swap file\'s header block and has %d fields: %s'
    % (len(FIELDS), ' '.join(FIELDS)))
ANY = '|'.join(FIELDS)
cls = partition(ANY, [
    ('its declaration', r'^    (char_u|long|int|short) +(%s) *(\[[^]]*\])?;$' % ANY),
    ('assigned', r'^\s*b0p-> *(%s)\b *(\[[^]]*\])? *=[^=]' % ANY),
    ('copied into', r'^\s*musl_(memmove|strncpy)\(\(char \*\)\((b0p->(%s))\b|'
                    r'^\s*long_to_char\([^,]+, b0p->(%s)\);$' % (ANY, ANY))],
    'the fields of `struct block0`')
if len(cls['its declaration']) != len(FIELDS):
    die('`struct block0` declares %d of the %d fields this phase was written against'
        % (len(cls['its declaration']), len(FIELDS)))
nwrite = len(cls['assigned']) + len(cls['copied into'])
# ml_open's preamble: from the mf_new that takes block zero to the line before the
# pointer block's, LOCATED rather than quoted.
lo_open, hi_open = body('ml_open')
start = only(lambda l: re.match(r'^    if \(\(hp = mf_new\(', l), "ml_open()'s first "
             'block allocation', lo_open, hi_open)
stop = only(lambda l: re.match(r'^    if \(\(hp = ml_new_ptr\(', l), "ml_open()'s "
            'pointer-block allocation', lo_open, hi_open)
L = lines()
pre = L[start:stop]
for f in FIELDS + ['set_b0_fname', 'long_to_char', 'mf_sync', 'BLOCK0_ID0', 'B0_DIRTY']:
    if not any(re.search(r'\b%s\b' % f, l) for l in pre):
        die('ml_open()\'s block-zero preamble (lines %d-%d) does not mention `%s`, so '
            'it is not the region this phase was written for' % (start + 1, stop, f))
outside = [i for i in range(lo_open, hi_open)
           if not start <= i < stop and re.search(r'\bb0p\b', L[i])
           and not re.match(r'^    ZERO_BL ', L[i])]
if outside:
    die('ml_open() says `b0p` outside the preamble at %s'
        % ' '.join('%d' % (i + 1) for i in outside))
b0decl = only(lambda l: re.match(r'^    ZERO_BL +\*b0p;$', l), "ml_open()'s `b0p`",
              lo_open, hi_open)
npre = cut_range(start, stop, "ml_open()'s block-zero preamble",
                 'it is the only place in the file that allocates block zero, and every '
                 'write to the header it then fills is inside it')
drop(L[b0decl] + '\n', "ml_open()'s `b0p` declaration",
     'the preamble this edit has just taken was its only user', n=2)
say("ml_open()'s block-zero preamble is %d lines and they are gone: the mf_new() that "
    'took block nr 0, %d of the %d header writes, the set_b0_fname() call, the mf_put() '
    'and the mf_sync()' % (npre, nwrite - 2, nwrite))

# THE TWO SURVIVING BLOCKS MOVE DOWN BY ONE.  Block zero is no longer allocated, so the
# pointer block is now block nr 0 and the data block block nr 1.  Three numbers in
# ml_open and two elsewhere say so, and each is the tree's own spelling of "the root".
lo_open, hi_open = body('ml_open')
swap('    if (hp-> bh_hashitem.mhi_key  != 1)\n    {\n        iemsg(e_didnt_get_block_nr_one);\n',
     '    if (hp-> bh_hashitem.mhi_key  != 0)\n    {\n        iemsg(e_didnt_get_block_nr_zero);\n',
     "ml_open()'s test that the pointer block is block nr 1",
     'the pointer block is the first block allocated now, so it is block nr 0')
swap('    pp->pb_pointer[0].pe_bnum = 2;\n', '    pp->pb_pointer[0].pe_bnum = 1;\n',
     "ml_open()'s pointer to the first data block",
     'the data block is the second block allocated now, so it is block nr 1')
swap('    if (hp-> bh_hashitem.mhi_key  != 2)\n    {\n        iemsg(e_didnt_get_block_nr_two);\n',
     '    if (hp-> bh_hashitem.mhi_key  != 1)\n    {\n        iemsg(e_didnt_get_block_nr_one);\n',
     "ml_open()'s test that the data block is block nr 2",
     'the data block is the second block allocated now, so it is block nr 1')
lo_find, hi_find = body('ml_find_line')
# only() here is the assertion and not the index: the line must be INSIDE ml_find_line()
# and nowhere else, so that the replacement below cannot land in some other function that
# happens to spell it the same way.
only(lambda l: l == '    bnum = 1;', "ml_find_line()'s root block", lo_find, hi_find)
swap('    bnum = 1;\n    page_count = 1;\n', '    bnum = 0;\n    page_count = 1;\n',
     "ml_find_line()'s root block number",
     'the tree is rooted at the pointer block, which is block nr 0 now')
lo_app, hi_app = body('ml_append_int')
only(lambda l: l == '                if (hp-> bh_hashitem.mhi_key  != 1)',
     "ml_append_int()'s test for the root pointer block", lo_app, hi_app)
swap('                if (hp-> bh_hashitem.mhi_key  != 1)\n',
     '                if (hp-> bh_hashitem.mhi_key  != 0)\n',
     "ml_append_int()'s test for the root pointer block",
     'a split that reaches the root must keep the root where the reader starts, and '
     'that is block nr 0 now')
say('the two surviving blocks move down by one: the pointer block is block nr 0 and '
    'the data block block nr 1, in ml_open()\'s three tests, ml_find_line()\'s root and '
    'ml_append_int()\'s root split')

# ml_setflags() exists ONLY to write the header's dirty byte and to mark the block
# dirty, and both are write-only state.  It goes with its two call sites.
cls = partition('ml_setflags', [
    ('its forward declaration', r'^static void ml_setflags\(buf_T \*buf\);$'),
    ('its definition', r'^ml_setflags\(buf_T \*buf\)$'),
    ('a call site', r'^\s*ml_setflags\((curbuf|buf)\);$')], '`ml_setflags`')
cut_at(cls['a call site'], "the calls of ml_setflags()",
       'it writes nothing that anything reads')
cut_defn('ml_setflags',
         "its body writes the header's dirty byte, sets BH_DIRTY and calls mf_sync(), "
         'and every one of the three is write-only state this phase removes')

# =====================================================================================
# PART 2 -- THE NEGATIVE BLOCK NUMBERS, WHICH NOTHING CAN PRODUCE.  mf_trans_add()
# returns at once unless a block number is negative; a negative one needs
# mf_new(.., negative, ..); the chain of call sites that could set that argument is
# COMPUTED here and every one of them is FALSE.
# =====================================================================================
L = lines()
ml_app_calls = [i for i, l in enumerate(L)
                if re.search(r'(?<!\w)ml_append\(', l)
                and not re.match(r'^static int ml_append\(', l)
                and not re.match(r'^ml_append\(', l)]
bad = [i for i in ml_app_calls if not re.search(r',\s*FALSE\)', L[i])]
if bad:
    die('ml_append() is called at %d sites and %d of them do not pass FALSE for '
        '`newfile` -- %s' % (len(ml_app_calls), len(bad),
                             ' '.join('%d:%s' % (i + 1, L[i].strip()) for i in bad[:4])))
flag_calls = [i for i, l in enumerate(L)
              if re.search(r'(?<!\w)ml_append_flags\(', l)
              and not re.match(r'^static int ml_append_flags\(', l)
              and not re.match(r'^ml_append_flags\(', l)]
if len(flag_calls) != 2:
    die('ml_append_flags() has %d call sites and this phase was written against two'
        % len(flag_calls))
newdata_calls = [i for i, l in enumerate(L)
                 if re.search(r'(?<!\w)ml_new_data\(', l)
                 and not re.match(r'^static bhdr_T \*ml_new_data\(', l)
                 and not re.match(r'^ml_new_data\(', l)]
mfnew_calls = [i for i, l in enumerate(L)
               if re.search(r'(?<!\w)mf_new\(', l) and not re.match(r'^mf_new\(', l)]
say('the chain that could make a block number negative, computed: ml_append() has %d '
    'call sites and ALL %d pass FALSE for `newfile`; ml_append_flags() has %d, one the '
    'ml_append() that has just been shown FALSE and one ML_APPEND_UNDO; ml_new_data() '
    'has %d, one FALSE and one `flags & ML_APPEND_NEW`; mf_new() has %d, two FALSE and '
    'one ml_new_data()\'s own parameter.  So `negative` is FALSE at every reachable '
    'call and mf_trans_add() returns OK before it does anything'
    % (len(ml_app_calls), len(ml_app_calls), len(flag_calls), len(newdata_calls),
       len(mfnew_calls)))

# mf_new loses `negative` and the branch under it.
swap('mf_new(memfile_T *mfp, int negative, int page_count)',
     'mf_new(memfile_T *mfp, int page_count)', "mf_new()'s signature",
     '`negative` is FALSE at every call site')
swap('    if (!negative && freep != nullptr && freep->bh_page_count >= page_count)',
     '    if (freep != nullptr && freep->bh_page_count >= page_count)',
     "mf_new()'s test of the free list", '`negative` is FALSE')
swap("""        if (negative)
        {
            hp-> bh_hashitem.mhi_key  = mfp->mf_blocknr_min--;
            mfp->mf_neg_count++;
        }
        else
        {
            hp-> bh_hashitem.mhi_key  = mfp->mf_blocknr_max;
            mfp->mf_blocknr_max += page_count;
        }
""", """        hp-> bh_hashitem.mhi_key  = mfp->mf_blocknr_max;
        mfp->mf_blocknr_max += page_count;
""", "mf_new()'s negative branch",
     'the only arm that ever ran is the positive one')
swap('static bhdr_T *ml_new_data(memfile_T *, int, int);',
     'static bhdr_T *ml_new_data(memfile_T *, int);', "ml_new_data()'s declaration", '')
swap('ml_new_data(memfile_T *mfp, int negative, int page_count)',
     'ml_new_data(memfile_T *mfp, int page_count)', "ml_new_data()'s signature", '')
swap('    if ((hp = mf_new(mfp, negative, page_count)) == nullptr)',
     '    if ((hp = mf_new(mfp, page_count)) == nullptr)',
     "ml_new_data()'s call of mf_new()", '')
swap('    if ((hp = ml_new_data(mfp, FALSE, 1)) == nullptr)',
     '    if ((hp = ml_new_data(mfp, 1)) == nullptr)', "ml_open()'s call of ml_new_data()", '')
swap('        if ((hp_new = ml_new_data(mfp, flags & ML_APPEND_NEW, page_count)) == nullptr)',
     '        if ((hp_new = ml_new_data(mfp, page_count)) == nullptr)',
     "ml_append_int()'s call of ml_new_data()",
     '`flags & ML_APPEND_NEW` is 0 at every call of ml_append_flags()')
swap('    if ((hp = mf_new(mfp, FALSE, 1)) == nullptr)',
     '    if ((hp = mf_new(mfp, 1)) == nullptr)', "ml_new_ptr()'s call of mf_new()", '')

# ml_append loses `newfile`, and ML_APPEND_NEW with it.
swap('static int ml_append(linenr_T lnum, char_u *line, colnr_T len, int newfile);',
     'static int ml_append(linenr_T lnum, char_u *line, colnr_T len);',
     "ml_append()'s declaration", '')
swap('ml_append(linenr_T    lnum, char_u      *line, colnr_T     len, int         newfile)',
     'ml_append(linenr_T    lnum, char_u      *line, colnr_T     len)',
     "ml_append()'s signature", '')
swap('    return ml_append_flags(lnum, line, len, newfile ? ML_APPEND_NEW : 0);',
     '    return ml_append_flags(lnum, line, len, 0);', "ml_append()'s body",
     '`newfile` is FALSE at every call site, so the flag it chose is never set')
t, n = re.subn(r'(?<!\w)ml_append\(((?:[^()]|\([^()]*\))*), *FALSE\)', r'ml_append(\1)', t)
if n != len(ml_app_calls):
    die('%d ml_append() call sites were rewritten and %d were counted' % (n, len(ml_app_calls)))
say('ml_append() loses `newfile` at its declaration, its definition and all %d call '
    'sites, and ml_append_flags() is called with a flag word that can no longer hold '
    'ML_APPEND_NEW' % n)

# ml_append_int's two ML_APPEND_NEW tests, and the ML_LOCKED_POS they set.
swap("""        buf->b_ml.ml_flags |= ML_LOCKED_DIRTY;
        if (!(flags & ML_APPEND_NEW))
        {
            buf->b_ml.ml_flags |= ML_LOCKED_POS;
        }
""", '', "ml_append_int()'s in-place ML_LOCKED_DIRTY and ML_LOCKED_POS",
     'both bits are written and neither is ever tested')
swap("""        if (lines_moved || in_left)
        {
            buf->b_ml.ml_flags |= ML_LOCKED_DIRTY;
        }
        if (!(flags & ML_APPEND_NEW) && db_idx >= 0 && in_left)
        {
            buf->b_ml.ml_flags |= ML_LOCKED_POS;
        }
""", '', "ml_append_int()'s split-block ML_LOCKED_DIRTY and ML_LOCKED_POS",
     'both bits are written and neither is ever tested')

# =====================================================================================
# PART 3 -- THE DIRTY STATE MACHINE, WRITE-ONLY IN ALL THREE OF ITS LAYERS.
# =====================================================================================
cls = partition('bh_flags', [
    ('its declaration', r'^    char        bh_flags;$'),
    ('a write', r'bh_flags (\|)?= '),
    ('the one read', r'^    flags = hp->bh_flags;$')], '`bh_flags`')
L = lines()
lo_put, hi_put = body('mf_put')
tests = [i for i in range(lo_put, hi_put) if re.search(r'flags & BH_', L[i])]
if len(tests) != 1 or 'BH_LOCKED' not in L[tests[0]]:
    die('the block header flags are tested at %d places and this phase needs exactly '
        'one, mf_put()\'s test of BH_LOCKED' % len(tests))
say('BH_DIRTY IS WRITTEN AND NEVER TESTED: `bh_flags` has %d mentions, %d of them '
    'writes and ONE read, and that read tests BH_LOCKED and nothing else'
    % (sum(len(v) for v in cls.values()), len(cls['a write'])))

cls = partition('mf_dirty', [
    ('its declaration', r'^    mfdirty_T   mf_dirty;$'),
    ('a write', r'mf_dirty = MF_DIRTY_'),
    ('a read', r'mf_dirty (==|!=) MF_DIRTY_')], '`mf_dirty`')
L = lines()
for i in cls['a read']:
    if not re.match(r'^\s*if \(.*mf_dirty (==|!=) MF_DIRTY_\w+\)$', L[i]):
        die('the read of `mf_dirty` at line %d is not the condition of an `if`' % (i + 1))
    inner = [j for j in range(i + 2, len(L)) if L[j].strip() != '']
    if L[i + 1].strip() != '{' or not re.search(r'mf_dirty = MF_DIRTY_', L[inner[0]]) \
            or L[inner[0] + 1].strip() != '}':
        die('the `if` at line %d does not guard exactly one statement, and that '
            'statement must be another write of `mf_dirty` for the field to be '
            'write-only' % (i + 1))
say('THE MEMFILE DIRTINESS IS A WRITE-ONLY STATE MACHINE: `mf_dirty` has %d writes and '
    '%d reads, and each read is the condition of an `if` whose only statement writes '
    '`mf_dirty` again -- so nothing outside the field ever learns its value'
    % (len(cls['a write']), len(cls['a read'])))

# THE THIRD LAYER: ml_flags' two locked bits.  ML_LOCKED_DIRTY and ML_LOCKED_POS are
# read at exactly one place between them, mf_put()'s two arguments, and mf_put is about
# to stop taking them.
cls = partition('ML_LOCKED_DIRTY|ML_LOCKED_POS', [
    ('its enumerator', r'^enum \{ ML_LOCKED_(DIRTY|POS) = 0x0[48] \};$'),
    ('set', r'ml_flags \|= '),
    ('cleared', r'ml_flags &= ~\(ML_LOCKED_DIRTY \| ML_LOCKED_POS\);$'),
    ("mf_put()'s two arguments", r'^\s*mf_put\(mfp, buf->b_ml\.ml_locked, ')],
    '`ML_LOCKED_DIRTY` and `ML_LOCKED_POS`')
cut_at(cls['set'] + cls['cleared'], 'the writes of the memline lock bits',
       'neither bit is tested anywhere but mf_put()\'s two arguments')
swap('        mf_put(mfp, buf->b_ml.ml_locked, buf->b_ml.ml_flags & ML_LOCKED_DIRTY, buf->b_ml.ml_flags & ML_LOCKED_POS);\n',
     '        mf_put(buf->b_ml.ml_locked);\n',
     "ml_find_line()'s release of the locked block",
     'the two bits it passed chose between marking a block dirty, which nothing tests, '
     'and calling mf_trans_add(), which returns at once')

# =====================================================================================
# PART 2b -- mf_put() loses both of its state arguments, and mf_trans_add() with them.
# =====================================================================================
swap("""mf_put(memfile_T   *mfp, bhdr_T      *hp, int         dirty, int         infile)
{
    int         flags;

    flags = hp->bh_flags;

    if ((flags & BH_LOCKED) == 0)
    {
        iemsg(e_block_was_not_locked);
    }
    flags &= ~BH_LOCKED;
    if (dirty)
    {
        flags |= BH_DIRTY;
        if (mfp->mf_dirty != MF_DIRTY_YES_NOSYNC)
        {
            mfp->mf_dirty = MF_DIRTY_YES;
        }
    }
    hp->bh_flags = flags;
    if (infile)
    {
        mf_trans_add(mfp, hp);
    }
}""", """mf_put(bhdr_T *hp)
{
    if ((hp->bh_flags & BH_LOCKED) == 0)
    {
        iemsg(e_block_was_not_locked);
    }
    hp->bh_flags &= ~BH_LOCKED;
}""", "mf_put()'s definition",
     'what is left of it is the one thing it did that anything reads: clearing BH_LOCKED')
put_calls = [i for i, l in enumerate(lines()) if re.search(r'(?<!\w)mf_put\(mfp, ', l)]
t, n = re.subn(r'(?<!\w)mf_put\(mfp, ([\w>.\[\]+ -]+?), \w+, (TRUE|FALSE)\);',
               r'mf_put(\1);', t)
if n != len(put_calls):
    die('%d mf_put() call sites were rewritten and %d still pass a memfile -- %s'
        % (n, len(put_calls), ' '.join(
            '%d:%s' % (i + 1, lines()[i].strip()) for i in put_calls[:4])))
say('mf_put() is `mf_put(bhdr_T *hp)`: it clears BH_LOCKED, which is the one bit '
    'anything tests, and its %d call sites lose the two arguments that chose between '
    'writing BH_DIRTY and calling mf_trans_add()' % n)

# mf_trans_add() and mf_trans_del() have no callers left but one, and that one is the
# arm under `bnum < 0`, which the chain above has shown unreachable.
swap("""                if (bnum < 0)
                {
                    bnum2 = mf_trans_del(mfp, bnum);
                    if (bnum != bnum2)
                    {
                        bnum = bnum2;
                        pp->pb_pointer[idx].pe_bnum = bnum;
                        dirty = TRUE;
                    }
                }

""", '', "ml_find_line()'s translation of a negative block number",
     'no block number in any build of zero-vim is ever negative')
drop('    blocknr_T bnum2;\n', "ml_find_line()'s `bnum2`", 'its one use has gone')
drop('static int  mf_trans_add(memfile_T *, bhdr_T *);\n', "mf_trans_add()'s declaration",
     '')
ntrans = cut_defn('mf_trans_add', 'it returned OK before doing anything unless a block '
                  'number was negative, and none ever is')
ntrans += cut_defn('mf_trans_del', 'its one call site was the arm under `bnum < 0`')

# The three memfile fields that only the negative blocks used.
for f, what in (('mf_trans', 'the translation table'),
                ('mf_blocknr_min', 'the lowest negative block number'),
                ('mf_neg_count', 'the count of negative blocks')):
    if mentions(t, f) > 4:
        die('`%s` has %d mentions and everything that used it has gone' % (f, mentions(t, f)))
swap('    if (nr >= mfp->mf_blocknr_max || nr <= mfp->mf_blocknr_min)',
     '    if (nr >= mfp->mf_blocknr_max || nr < 0)', "mf_get()'s bounds test",
     '`mf_blocknr_min` is -1 from mf_open() onwards and only the negative branch of '
     'mf_new() ever moved it, so `nr <= -1` is `nr < 0`')
swap("""    if (hp-> bh_hashitem.mhi_key  < 0)
    {
        vim_free(hp);
        mfp->mf_neg_count--;
    }
    else
    {
        mf_ins_free(mfp, hp);
    }
""", """    mf_ins_free(mfp, hp);
""", "mf_free()'s negative-block arm", 'no block number is ever negative')
drop('    mf_hash_init(&mfp->mf_trans);\n', "mf_open()'s initialisation of mf_trans", '')
drop('    mfp->mf_blocknr_min = -1;\n', "mf_open()'s initialisation of mf_blocknr_min", '')
drop('    mfp->mf_neg_count = 0;\n', "mf_open()'s initialisation of mf_neg_count", '')
drop('    mf_hash_free_all(&mfp->mf_trans);\n', "mf_close()'s free of mf_trans", '')
drop('    mf_hashtab_T mf_trans;\n', 'the `mf_trans` field', '')
drop('    blocknr_T   mf_blocknr_min;\n', 'the `mf_blocknr_min` field', '')
drop('    blocknr_T   mf_neg_count;\n', 'the `mf_neg_count` field', '')
say('the negative-block machinery is gone: mf_trans_add() and mf_trans_del() (%d lines), '
    'the three memfile fields that served them, mf_get()\'s lower bound and mf_free()\'s '
    'negative arm' % ntrans)

swap("""    if (curbuf->b_ml.ml_mfp != nullptr)
    {
        curbuf->b_ml.ml_mfp->mf_dirty = MF_DIRTY_YES_NOSYNC;
    }

""", '', "the MF_DIRTY_YES_NOSYNC that is set around a buffer reload",
     'nothing reads it but the line that puts it back')
swap("""    if (curbuf->b_ml.ml_mfp != nullptr && curbuf->b_ml.ml_mfp->mf_dirty == MF_DIRTY_YES_NOSYNC)
    {
        curbuf->b_ml.ml_mfp->mf_dirty = MF_DIRTY_YES;
    }

""", '', 'the MF_DIRTY_YES_NOSYNC that is read back', 'its setter has just gone')
swap('    mfp->mf_used_last = nullptr;\n    mfp->mf_dirty = MF_DIRTY_NO;\n',
     '    mfp->mf_used_last = nullptr;\n', "mf_open()'s initialisation of mf_dirty", '')
swap('    hp->bh_flags = BH_LOCKED | BH_DIRTY;\n    mfp->mf_dirty = MF_DIRTY_YES;\n',
     '    hp->bh_flags = BH_LOCKED;\n', "mf_new()'s two dirty marks",
     'neither is ever tested')
drop('    mfdirty_T   mf_dirty;\n', "the `mf_dirty` field", 'it is write-only')
drop("""typedef enum {
    MF_DIRTY_NO = 0,
    MF_DIRTY_YES,
    MF_DIRTY_YES_NOSYNC,
} mfdirty_T;

""", '`mfdirty_T`', 'the one field of that type has gone')


# mf_sync()'s whole body was a write of mf_dirty and a `return FAIL`.  Its two call
# sites have gone with ml_open()'s preamble and ml_setflags(), so it goes here rather
# than to the sweep: the field its body writes is about to stop existing.
if mentions(t, 'mf_sync') != 1:
    die('`mf_sync` has %d mentions and the edit has left it exactly one, its own '
        'definition -- the ml_open() call went with the preamble and the ml_setflags() '
        'call with the function' % mentions(t, 'mf_sync'))
cut_defn('mf_sync', 'its body writes `mf_dirty` and returns FAIL, and it has no '
         'caller left')

# ml_find_line()'s `dirty` was the argument mf_put() has just stopped taking.
lo_find, hi_find = body('ml_find_line')
cls = partition('dirty', [
    ('its declaration', r'^    int         dirty;$'),
    ('a write', r'^\s*dirty = (TRUE|FALSE);$')], "ml_find_line()'s `dirty`")
cut_at(cls['its declaration'] + cls['a write'], "ml_find_line()'s `dirty`",
       'the mf_put() argument it fed has gone, and the warning gcc emits for a local '
       'that is written and never read is one tools/deadsweep.py does not act on')

# =====================================================================================
# PART 4 -- pe_old_lnum, WRITE-ONLY, AND THE TWO LOCALS THAT EXIST ONLY TO FEED IT.
# =====================================================================================
cls = partition('pe_old_lnum', [
    ('its declaration', r'^    linenr_T    pe_old_lnum;$'),
    ('a write', r'^\s*(pp|pp_new)->pb_pointer\[[^]]*\]\.pe_old_lnum = \w+;$')],
    '`pe_old_lnum`')
say('`pe_old_lnum` IS WRITE-ONLY: %d writes and not one read.  tools/deadfields.py '
    'cannot see it -- that tool takes a field named nowhere outside its own type -- so '
    'the field goes in the EDIT, with its writes' % len(cls['a write']))
cut_at(cls['a write'], 'the writes of `pe_old_lnum`', 'nothing reads the field')
drop('    linenr_T    pe_old_lnum;\n', 'the `pe_old_lnum` field', '')
# Four of the seven writes were the only statement of an `if`, and an `if` with an
# empty body is what is left.  They are taken by their shape and counted.
L = lines()
empties = [i for i in range(len(L) - 2)
           if re.match(r'^\s*if \(lnum_(left|right)( != 0)?\)$', L[i])
           and L[i + 1].strip() == '{' and L[i + 2].strip() == '}']
if len(empties) != 4:
    die('%d `if (lnum_left|lnum_right)` blocks are empty now and this phase was written '
        'against four' % len(empties))
cut_at([j for i in empties for j in (i, i + 1, i + 2)], 'the four emptied `if` blocks',
       'each held one statement and it was a write of `pe_old_lnum`')
# And the two locals are now written and never read.  gcc says
# -Wunused-but-set-variable, which tools/deadsweep.py does not act on, so they are the
# edit's (CLAUDE.md, *Audit for dead code*).
cls = partition('lnum_left|lnum_right', [
    ('its declaration', r'^        linenr_T lnum_(left|right);$'),
    ('a write', r'^\s*lnum_(left|right) = (lnum \+ [12]|0);$')],
    "ml_append_int()'s `lnum_left` and `lnum_right`")
swap("""        if (db_idx < 0)
        {
            lnum_left = lnum + 1;
            lnum_right = 0;
        }
        else
        {
            lnum_left = 0;
            if (in_left)
            {
                lnum_right = lnum + 2;
            }
            else
            {
                lnum_right = lnum + 1;
            }
        }
""", '', 'the branch that computed lnum_left and lnum_right',
     'both are written and never read once `pe_old_lnum` has gone, and that is a '
     'warning tools/deadsweep.py does not act on')
if mentions(t, 'lnum_left') != 2 or mentions(t, 'lnum_right') != 2:
    die('`lnum_left` has %d mentions and `lnum_right` %d, and the branch this edit has '
        'just taken should leave each with its declaration and its one reset'
        % (mentions(t, 'lnum_left'), mentions(t, 'lnum_right')))
drop('        linenr_T lnum_left;\n', 'the `lnum_left` declaration', '')
drop('        linenr_T lnum_right;\n', 'the `lnum_right` declaration', '')
drop('            lnum_left = 0;\n            lnum_right = 0;\n',
     'the reset of lnum_left and lnum_right', '')

# mf_dont_release: a `static int` that is READ TWICE AND NEVER ASSIGNED.
cls = partition('mf_dont_release', [
    ('its declaration, with its only value', r'^static int      mf_dont_release  = FALSE ;$'),
    ('a read', r'(\|\| mf_dont_release\)| && !mf_dont_release\))')],
    '`mf_dont_release`')
L = lines()
assigns = [i for i, l in enumerate(L)
           if re.search(r'\bmf_dont_release\b\s*=', l) and i not in cls[
               'its declaration, with its only value']]
if assigns:
    die('`mf_dont_release` is assigned at %s, so it is not the constant this phase takes'
        % ' '.join(str(i + 1) for i in assigns))
say('`mf_dont_release` IS A CONSTANT: %d mentions, its own declaration with `FALSE` and '
    '%d reads, and NOT ONE assignment anywhere in the file -- and no warning gcc emits '
    'covers a file-scope object in either direction'
    % (sum(len(v) for v in cls.values()), len(cls['a read'])))
swap(' || mf_dont_release)', ')', "ml_get_buf()'s test of mf_dont_release",
     'it is FALSE for ever, so the disjunct is the other operand')
swap(' && !mf_dont_release)', ')', "ml_find_line()'s test of mf_dont_release",
     'it is FALSE for ever, so the conjunct is the other operands')
drop('static int      mf_dont_release  = FALSE ;\n', 'the `mf_dont_release` declaration',
     'both of its readers have gone')

# =====================================================================================
# WHAT IS LEFT FOR THE SWEEP, and it is named rather than hoped for.  Everything below
# is unreachable now and every one of them is a kind tools/sweep.sh finds: an unused
# static function, an unused static object, a type nothing reaches, an enumerator
# nothing mentions.  Nothing that is WRITTEN is in this list -- that is the whole
# division of labour, and a write-only field or a set-and-never-tested bit is the
# edit's because no tool in tools/ can see one.
LEFT = {
    'set_b0_fname': 'a static function with no caller left',
    'long_to_char': 'a static function with no caller left',
    'mf_hash_free_all': 'a static function with no caller left',
    'ml_setflags': 'a forward declaration of a function that is gone',
    'Version': 'a static object nothing reads',
    'e_didnt_get_block_nr_two': 'a static object nothing reads',
    'ZERO_BL': 'a type nothing reaches',
    'NR_TRANS': 'a type nothing reaches',
    'BH_DIRTY': 'an enumerator nothing mentions',
    'MFS_ZERO': 'an enumerator nothing mentions',
    'ML_APPEND_NEW': 'an enumerator nothing mentions',
    'ML_LOCKED_POS': 'an enumerator nothing mentions',
    'ML_LOCKED_DIRTY': 'an enumerator nothing mentions',
}
for name, why in sorted(LEFT.items()):
    if mentions(t, name) == 0:
        die('the edit has already taken `%s`, which it leaves for the sweep (%s) -- so '
            'the two halves of this phase no longer divide as its check states' % (name, why))
say('%d names are left standing for tools/sweep.sh: %s.  Each is a kind that sweep '
    'finds; nothing that is WRITTEN is among them, because no tool in tools/ can see a '
    'write' % (len(LEFT), ', '.join(sorted(LEFT))))

# GONE ALREADY, AND ASSERTED RATHER THAN BELIEVED: every name the edit itself owns.
for name in ('mf_dirty', 'mfdirty_T', 'MF_DIRTY_NO', 'MF_DIRTY_YES', 'MF_DIRTY_YES_NOSYNC',
             'mf_sync', 'mf_trans', 'mf_trans_add', 'mf_trans_del',
             'mf_blocknr_min', 'mf_neg_count', 'pe_old_lnum', 'mf_dont_release',
             'lnum_left', 'lnum_right', 'bnum2', 'newfile'):
    if mentions(t, name) != 0:
        die('`%s` still has %d mentions and the edit owns every one of them'
            % (name, mentions(t, name)))
# `b0p` is left only inside set_b0_fname(), which the sweep takes; `negative` is an
# ordinary English word in this file as well as a parameter name, so what is asserted is
# the SIGNATURES it has left rather than a count of the word.
if mentions(t, 'b0p') != 2:
    die('`b0p` has %d mentions and the edit leaves two, both of them inside '
        'set_b0_fname(), which tools/deadsweep.py takes' % mentions(t, 'b0p'))
for sig in ('mf_new(memfile_T *mfp, int page_count)',
            'ml_new_data(memfile_T *mfp, int page_count)',
            'ml_append(linenr_T    lnum, char_u      *line, colnr_T     len)',
            'mf_put(bhdr_T *hp)'):
    if t.count(sig) != 1:
        die('`%s` is not in the output exactly once, so a signature this phase '
            'narrowed is not the one it meant' % sig)

# ---- the paragraphs the cuts emptied -------------------------------------------------
# Three of the cuts above took every line of a paragraph and left the blank line either
# side of it, which is a run of two blank lines -- something this file has none of and
# no verification tier can see (CLAUDE.md, *Verification tiers*).  tools/canon.sh would
# take them in the sweep, but a file the edit hands on is a file this phase is
# responsible for, so they go here and they are COUNTED: the input has no such run at
# all, so every one of them is this edit's.
if runs_before != 0:
    die('the input already holds %d runs of two blank lines, and this file has none -- '
        'so the arithmetic below could not tell this edit\'s from the input\'s' % runs_before)
L = lines()
made = [i for i in range(1, len(L)) if L[i] == '' and L[i - 1] == '']
cut_at(made, 'one blank line from each paragraph the cuts emptied',
       'a paragraph separator with nothing left to separate is the run of two blank '
       'lines this file does not have')
say('%d paragraphs were emptied outright and one blank line goes from each' % len(made))
if blank_runs(t) != 0:
    die('the edit left %d runs of two blank lines' % blank_runs(t))
L = lines()
d2 = [i for i, l in enumerate(L) if re.match(r'^ *# *', l)]
if len(d2) != len(directives_before) or d2 != list(range(d2[0], d2[0] + len(d2))):
    die('the output does not have the same %d contiguous directives the input had -- '
        'this phase adds none and removes none' % len(directives_before))
open(path, 'w', errors='surrogateescape').write(t)
# The check states what the EDIT took and what the SWEEP took, separately, and this is
# how it can: the text the edit hands on, kept beside the text it was handed.
open('%s/edit.c' % state, 'w', errors='surrogateescape').write(t)
say('%d -> %d lines before the sweep, %d fewer, the %d `#include`s untouched and still '
    'contiguous, and no run of two blank lines'
    % (lines_before, len(L) - 1, lines_before - (len(L) - 1), len(d2)))
PY

# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  swapres      the input did not build with '$cflags' '$ldflags'"; exit 1; }
echo "  swapres      the input is $state/old, $(stat -c%s "$state/old") bytes, built with SOURCE_DATE_EPOCH=0 beside the source it came from, and $state/edit.c is the text this edit hands to the sweep.  Code is removed and the block numbers of a memline move, so the binary is NOT byte-identical and this phase cannot use tier 1 of CLAUDE.md's verification table: the evidence is two recordings, an instrumented pair for each half, and a stress corpus deep enough to split the root"
