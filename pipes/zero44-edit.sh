#!/bin/sh
# Zero phase 44 -- de-page the leaf.  See ZERO-GOAL.md.
#
# Usage: pipes/zero44-edit.sh <work-dir> <state-dir>     (run from the repository root)
#
# A DATA BLOCK STOPS BEING A PAGE OF BYTES AND BECOMES AN ARRAY OF LINE RECORDS.
# Until this phase a leaf of the memline tree is a header, an index of byte offsets
# growing UP from the header, and a text arena growing DOWN from the end of the
# page, with the two meeting at `db_free` bytes of gap.  A line's text lives inside
# the block, so inserting a line in the middle memmoves the arena and rewrites every
# index below it; a line that grows past the gap is appended-and-deleted into another
# block; and a line longer than a page makes the block two pages.  After this phase
# the leaf is
#
#     struct data_line { char_u *dl_text; colnr_T dl_len; char dl_marked; };
#     struct data_block { short_u db_id; linenr_T db_line_count;
#                         DATA_LN db_line[DB_LINE_MAX]; };
#
# and a line's text is its own allocation.  Inserting a line shifts records, not
# bytes; replacing a line stores a pointer.
#
# WHY IT IS CHEAP NOW AND WAS NOT BEFORE.  The arena exists for exactly one reason,
# to avoid a malloc per line, and ZERO-GOAL.md's charter has retired that reason: "A
# GARBAGE COLLECTOR IS ASSUMED FROM HERE ON".  Zero phase 41 made host_alloc a bump
# allocator and host_free a return, so a per-line allocation costs a pointer bump and
# freeing costs nothing.  This phase spends that.
#
# AND WHAT IT SPENDS IS MEASURED, by the check's own counter and on both sides:
# the heaviest memline session asks the host for 201,927,792 bytes where the input
# asks 200,438,864, +0.7%.  A leaf page per 64 lines costs about what a leaf page per
# 78 lines and its arena cost, and the per-line text is what the arena used to hold
# inside the page.  With nothing freed that figure is a session's TRAFFIC and not its
# live data, which is why it is two hundred megabytes and why zero phase 41's arena
# is a gigabyte -- a number that phase and this one arrived at from opposite ends
# with instruments written apart, agreeing to the byte.
#
# THE TARGET REPRESENTATION IS TODAY'S DIRTY-LINE PATH MADE PERMANENT, which is why
# the rewrite can be this small.  `buf->b_ml.ml_line_ptr` under ML_LINE_DIRTY is
# ALREADY a separately allocated `char_u *` with `ml_line_len` beside it -- that is
# what ml_replace_len() builds and what del_bytes() edits in place when
# ml_line_alloced() is true.  ml_flush_line()'s job was to copy that buffer back into
# the page; here it stores the pointer, and the sixty-line "does the new text still
# fit" branch under it -- the memmove, the index fixup and the append-then-delete
# fallback -- has nothing left to decide.
#
# WHAT GOES, EVERY ONE OF IT MEASURED ON THE INPUT AND ASSERTED AS A PARTITION AND
# NOT AS A COUNT (below, `classify`):
#
#   db_free           14 mentions      the gap, in bytes
#   db_txt_start      29               the arena's low water
#   db_txt_end         6               the arena's high water
#   db_index          34               the offset index, declared `unsigned [1]`
#   the top bit       17               DB_MARKED, stolen from an offset, now a field
#   (char_u *)dp +    14               every interior pointer into the page
#   offsetof(DATA_BL)  2               there is nothing left to measure
#   ML_APPEND_MARK     5               its one caller was the fallback that goes
#
# THE THIRD offsetof IS NOT THIS PHASE'S.  ml_new_ptr()'s
# `offsetof(PTR_BL, pb_pointer)` measures a POINTER block, which is still a page of
# entries and is not the leaf.  De-paging the branch is a phase of its own and would
# change the tree's fanout on purpose; this one leaves it alone and says so.
#
# DB_LINE_MAX IS A FREE PARAMETER NOW AND IT IS CHOSEN BY MEASUREMENT.  A leaf used
# to hold as many lines as fitted in a page -- 78 of `zmemline`'s 47-byte
# lines on the boundary this was first written against -- and nothing decides it any
# more, so the value is a tuning knob.  The corpus CANNOT SEE IT: measured,
# DB_LINE_MAX of 32, 64, 128 and even 1 all record the 102 screen cases and the 16
# memline cases byte for byte, so no argument from "the recording agrees" is worth
# anything here.  What it does decide is how much of the tree the corpus REACHES, and
# that is measured, with zero phase 40's own markers, ON THIS PHASE'S ACTUAL INPUT:
#
#     DB_LINE_MAX   SPLITDATA  SPLITPTR  SPLITROOT  IDXNZ  DEEP
#         32           16         5          5        16     5
#         64           16         1          1        16     1
#        128           16         0          0        16     0
#        255           14         0          0        14     0
#     r43, the input  16         1          1        16     1
#
# 64 IS TAKEN BECAUSE IT REACHES EXACTLY WHAT THE INPUT REACHES, and 255 -- the value
# that would fill the page -- is the one that must not be chosen: it reaches no
# pointer-block split at all, so the natural-looking choice, the one that wastes
# nothing, would blind the instrument on the very phase that rewrites the tree.
#
# THE MARGIN IS ONE CASE AND IT HAS BEEN NARROWING UNDER THIS PHASE, which is worth
# writing down rather than discovering.  The same table taken on r40 read 6/5/1/0 in
# the SPLITROOT column, so 128 was a live choice then and reaches ZERO now: zero
# phase 42 took `pe_old_lnum` out of PTR_EN and phase 43 took the block number and the
# page count, and pb_count_max has gone 127 -> 170 -> 255 while the corpus's buffer
# sizes have not moved.  Measured directly on r43: mem_deep_jumps makes 321 data
# blocks on the input and 391 here, against a pb_count_max of 255, and no other case
# reaches 255 on either side.  So a PTR_EN of 8 bytes would put pb_count_max at 511
# and take even 64 to zero -- at which point the corpus needs resizing or DB_LINE_MAX
# needs lowering (32 reaches 5), and that is the phase that shrinks PTR_EN to decide,
# not this one.
#
# THE LEAF IS STILL ALLOCATED AS ONE MEMFILE PAGE and that is deliberate scope.
# sizeof(DATA_BL) is 1,040 bytes of a 4,096-byte page, which the edit asserts with a
# static_assert rather than leaving to be discovered.  Allocating a block at its own
# size means giving memfile a byte size where it has a page count, which is block
# NUMBERING as well as block size -- the machinery zero phase 43 has just rewritten --
# and a phase that replaced the leaf's representation and changed how blocks are
# allocated in one act would have two claims and one set of evidence.  It is named
# here so it is not lost: it would take the leaf from 112 bytes a line to 64, and it
# would make an off-by-one in the capacity bound VISIBLE, which today it is not (the
# check measures that and reports it).  Two findings of the same neighbourhood go with
# it, and phase 43 has already taken one of them from the other side: `pe_page_count`
# and `bh_page_count` were constant 1 after this phase and are gone before it.
#
# NOTHING IS FREED, AND THAT IS THE LIFETIME RULE.  A record owns its text and never
# gives it back: ml_flush_line() stores the replacement and drops the old pointer,
# ml_delete_int() drops a record's, and neither calls vim_free().  So
#
#     A POINTER RETURNED BY ml_get*() IS VALID FOR THE LIFETIME OF THE PROCESS.
#
# which is strictly weaker than what 341 call sites needed before, where the pointer
# was into a page and any insert or delete in the same block, any flush of any line
# in it, and any split invalidated it.  The check states the rule as a partition over
# every assignment to `dl_text` in the output, and probes it with a build that
# poisons the text a record stops owning.
#
# HOW THE EDIT IS WRITTEN, because phases 42 and 43 rewrite the same functions.
# Nothing here is anchored to a line this phase does not itself replace: every region
# is found by the function it is in and by its own first and last line, every call
# whose arity changes is rewritten by DROPPING ITS LAST ARGUMENT rather than by
# matching the argument, every `ml_flags |=` statement inside a replaced region is
# carried forward as it was found, and every local that the rewrite stops using is
# removed by COMPUTING that its name is left mentioned once.  A phase that wrote
# `ML_LOCKED_DIRTY` out would break on phase 42, which removes it.
set -eu

work=${1:?usage: zero44-edit.sh <work-dir> <state-dir>}
state=${2:?usage: zero44-edit.sh <work-dir> <state-dir>}
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

path, state = sys.argv[1], sys.argv[2]
DB_LINE_MAX = 64

# The mark used to be the top bit of an offset.  Zero phase 9's macro expansion left
# it spelled out, in two forms -- the bit and its complement -- and this is the text,
# not a description of it.
BIT = '((unsigned)1 << ((sizeof(unsigned) * 8) - 1))'

# The five names the leaf stops having, and the one flag whose only caller goes with
# ml_flush_line()'s fallback.  Each is counted on the input and required to be 0 on
# the output, and -- which is the part that matters -- every MENTION is classified.
GONE = ('db_free', 'db_txt_start', 'db_txt_end', 'db_index', 'ML_APPEND_MARK')

# Where a mention of a gone name is allowed to be in the input.  A mention anywhere
# else is a rule this edit does not have, and it refuses rather than leaving it.
HOMES = ('<file scope>', 'ml_open', 'ml_get_buf', 'ml_append_int', 'ml_delete_int',
         'ml_setmarked', 'ml_firstmarked', 'ml_clearmarked', 'ml_flush_line',
         'ml_new_data')


def die(msg):
    print('  leaf         ' + msg)
    sys.exit(1)


def say(msg):
    print('  leaf         ' + msg)


def mentions(t, name):
    return len(re.findall(r'\b%s\b' % re.escape(name), t))


t0 = open(path, errors='surrogateescape').read()
lines = t0.split('\n')
n_in = len(lines)


# --- finding things --------------------------------------------------------
def func(name):
    """(head, end) line indices of NAME's definition, head being its `static` line."""
    hits = [i for i, l in enumerate(lines) if l.startswith(name + '(')]
    if len(hits) != 1:
        die('%s is not a definition head exactly once (%d), so this edit cannot '
            'find the function it is about' % (name, len(hits)))
    head = hits[0] - 1
    if not lines[head].lstrip().startswith('static'):
        die('%s has no `static` line above its name' % name)
    i = hits[0]
    while lines[i] != '{':
        i += 1
    depth = 0
    while True:
        depth += lines[i].count('{') - lines[i].count('}')
        if depth == 0:
            return head, i
        i += 1


def one(lo, hi, pat):
    """The single line in [lo,hi] matching PAT."""
    hits = [i for i in range(lo, hi + 1) if re.search(pat, lines[i])]
    if len(hits) != 1:
        die('%r matches %d lines where this edit needs exactly one' % (pat, len(hits)))
    return hits[0]


def first(lo, hi, pat):
    """The first line in [lo,hi] matching PAT, which must exist."""
    for i in range(lo, hi + 1):
        if re.search(pat, lines[i]):
            return i
    die('%r matches nothing where this edit needs it' % pat)


def stmt_end(a):
    """Last index of the statement starting at A, following any `else` chain."""
    i = a
    while True:
        depth, seen, j = 0, False, i
        while True:
            depth += lines[j].count('{') - lines[j].count('}')
            seen = seen or '{' in lines[j]
            if (seen and depth == 0) or (not seen and lines[j].rstrip().endswith(';')):
                break
            j += 1
        k = j + 1
        while k < len(lines) and lines[k].strip() == '':
            k += 1
        if k < len(lines) and lines[k].strip().startswith('else'):
            i = k
            continue
        return j


def enclosing(i):
    """The name of the function whose definition contains line I."""
    for j in range(i, -1, -1):
        if lines[j] == '}':
            return '<file scope>'
        m = re.match(r'^([a-zA-Z_][a-zA-Z0-9_]*)\(', lines[j])
        if m and j > 0 and lines[j - 1].lstrip().startswith('static'):
            return m.group(1)
    return '<file scope>'


def carry(lo, hi, indent):
    """The `ml_flags |=` statements inside [lo,hi], re-indented.

    They are CARRIED and not written: ML_LOCKED_DIRTY and ML_LOCKED_POS are zero
    phase 42's to remove, and an edit that spelled them would break on it.
    """
    return [' ' * indent + lines[i].strip()
            for i in range(lo, hi + 1) if re.search(r'ml_flags \|=', lines[i])]


def last_arg(i, callee, new=None):
    """Line I's call to CALLEE loses its last argument, or gets NEW in its place.

    The argument is found by PLACE and never by its text, because what it says is
    zero phase 42's and zero phase 43's to change and what it IS is this phase's.
    """
    m = re.search(re.escape(callee) + r'\(', lines[i])
    if m is None:
        die('line %d does not call %s' % (i + 1, callee))
    depth, j, commas = 1, m.end(), []
    while True:
        c = lines[i][j]
        if c == '(':
            depth += 1
        elif c == ')':
            depth -= 1
            if depth == 0:
                break
        elif c == ',' and depth == 1:
            commas.append(j)
        j += 1
    if not commas:
        die('%s is called with one argument, so there is no last one to name' % callee)
    was = lines[i][commas[-1] + 1:j]
    lines[i] = lines[i][:commas[-1]] + ((', ' + new) if new else '') + lines[i][j:]
    return was


# --- the partition, before anything is changed -----------------------------
before = {}
strays = []
for name in GONE + (BIT,):
    pat = r'\b%s\b' % re.escape(name) if name != BIT else re.escape(name)
    hits = [i for i, l in enumerate(lines) if re.search(pat, l)]
    if not hits:
        die('%s is not in the input at all, so this phase has already run or the '
            'leaf is not the one it was written against' % name)
    before[name] = t0.count(BIT) if name == BIT else mentions(t0, name)
    for i in hits:
        if enclosing(i) not in HOMES:
            strays.append('%s in %s (line %d)' % (name, enclosing(i), i + 1))
if strays:
    die('a name this phase removes is mentioned where it has no rule: '
        + '; '.join(strays[:5]))
say('the input mentions %s -- %s times between them, the top bit %d more -- and every '
    'mention is in the struct, the enumerator or one of the eight memline functions '
    'this edit rewrites'
    % (', '.join(GONE), sum(before[n] for n in GONE), before[BIT]))


# --- 1. the typedef, the record and the block ------------------------------
i = lines.index('typedef struct data_block       DATA_BL;')
lines.insert(i + 1, 'typedef struct data_line        DATA_LN;')

a = lines.index('struct data_block')
b = a
while lines[b] != '};':
    b += 1
members = [l.strip() for l in lines[a + 2:b] if l.strip()]
if len(members) != 6 or members[-1] != 'unsigned    db_index[1];':
    die('struct data_block is not the header-index-arena block this phase replaces: '
        + ' '.join(members))
lines[a:b + 1] = [
    'enum { DB_LINE_MAX = %d };' % DB_LINE_MAX,
    '',
    'struct data_line',
    '{',
    '    char_u      *dl_text;',
    '    colnr_T     dl_len;',
    '    char        dl_marked;',
    '};',
    '',
    'struct data_block',
    '{',
    '    short_u     db_id;',
    '    linenr_T    db_line_count;',
    '    DATA_LN     db_line[DB_LINE_MAX];',
    '};',
    '',
    'static_assert(sizeof(DATA_BL) <= MEMFILE_PAGE_SIZE, "a leaf is one memfile page");',
]

# --- 2. one line's text is its own allocation ------------------------------
# It goes immediately ABOVE ml_open(), which is its first caller, so it needs no
# forward declaration and no place in the block of them -- and so that the edit
# depends on the function it is about and not on whatever else is nearby.  (It was
# anchored on long_to_char()'s declaration until zero phase 42 deleted that with
# block zero, which is the anchor refusing and being moved rather than loosened.)
lo, _hi = func('ml_open')
lines[lo:lo] = [
    '    static char_u *',
    'ml_alloc_line(char_u *line, colnr_T len)',
    '{',
    '    char_u      *text;',
    '',
    '    text = alloc((usize)len);',
    '    if (text != nullptr)',
    '    {',
    '         musl_memmove((char *)(text), (char *)(line), (usize)(len)) ;',
    '    }',
    '',
    '    return text;',
    '}',
    '',
]

# --- 3. ml_new_data has no page count --------------------------------------
i = one(0, len(lines) - 1, r'^static bhdr_T \*ml_new_data\(memfile_T \*')
was = last_arg(i, 'ml_new_data')
if was.strip() != 'int':
    die('ml_new_data\'s prototype does not end in a plain `int` parameter: ' + was)

lo, hi = func('ml_new_data')
was = last_arg(lo + 1, 'ml_new_data')
if 'page_count' not in was:
    die('ml_new_data\'s last parameter is not the page count: ' + was)
was = last_arg(one(lo, hi, r'mf_new\('), 'mf_new', '1')
if 'page_count' not in was:
    die('ml_new_data does not hand its page count to mf_new: ' + was)
a = one(lo, hi, r'^    dp->db_txt_start = dp->db_txt_end = ')
b = one(lo, hi, r'^    dp->db_free = ')
if b != a + 1:
    die('ml_new_data does not set the arena on two consecutive lines')
del lines[a:b + 1]

# --- 4. ml_open's one empty line -------------------------------------------
lo, hi = func('ml_open')
a = one(lo, hi, r'^    dp->db_index\[0\] = --dp->db_txt_start;$')
b = one(lo, hi, r'^    \*\(\(char_u \*\)dp \+ dp->db_txt_start\) = NUL;$')
lines[a:b + 1] = [
    '    dp->db_line[0].dl_text = ml_alloc_line((char_u *)"", 1);',
    '    if (dp->db_line[0].dl_text == nullptr)',
    '    {',
    '        goto error;',
    '    }',
    '    dp->db_line[0].dl_len = 1;',
    '    dp->db_line_count = 1;',
]
lo, hi = func('ml_open')
last_arg(one(lo, hi, r'ml_new_data\('), 'ml_new_data')

# --- 5. ml_get_buf reads a record ------------------------------------------
lo, hi = func('ml_get_buf')
a = one(lo, hi, r'^        idx = lnum - buf->b_ml\.ml_locked_low;$')
b = one(lo, hi, r'^        buf->b_ml\.ml_line_len = end - start;$')
lines[a:b + 1] = [
    '        idx = lnum - buf->b_ml.ml_locked_low;',
    '',
    '        buf->b_ml.ml_line_ptr = dp->db_line[idx].dl_text;',
    '        buf->b_ml.ml_line_len = dp->db_line[idx].dl_len;',
]

# --- 6. ml_append_int ------------------------------------------------------
lo, hi = func('ml_append_int')
a = one(lo, hi, r'^    int         line_count;$')
lines[a + 1:a + 1] = ['    char_u      *text;']

lo, hi = func('ml_append_int')
a = one(lo, hi, r'^    space_needed = len \+ ')
lines[a:a + 1] = [
    '    text = ml_alloc_line(line, len);',
    '    if (text == nullptr)',
    '    {',
    '        goto theend;',
    '    }',
]

lo, hi = func('ml_append_int')
a = one(lo, hi, r'db_free < space_needed && db_idx == line_count - 1')
lines[a] = ('    if (dp->db_line_count >= DB_LINE_MAX && db_idx == line_count - 1'
            ' && lnum < buf->b_ml.ml_line_count)')

lo, hi = func('ml_append_int')
a = one(lo, hi, r'^    if \(\(long\)dp->db_free >= space_needed\)$')
b = stmt_end(first(a, hi, r'if \(flags & ML_APPEND_MARK\)'))
lines[a:b + 1] = [
    '    if (dp->db_line_count < DB_LINE_MAX)',
    '    {',
    '        if (line_count > db_idx + 1)',
    '        {',
    '             musl_memmove((char *)(&dp->db_line[db_idx + 2]), '
    '(char *)(&dp->db_line[db_idx + 1]), '
    '(usize)(line_count - db_idx - 1) * sizeof(DATA_LN)) ;',
    '        }',
    '        dp->db_line[db_idx + 1].dl_text = text;',
    '        dp->db_line[db_idx + 1].dl_len = len;',
    '        dp->db_line[db_idx + 1].dl_marked = FALSE;',
    '        ++(dp->db_line_count);',
]

lo, hi = func('ml_append_int')
a = one(lo, hi, r'^            lines_moved = line_count - db_idx - 1;$')
b = one(lo, hi, r'offsetof\(DATA_BL, db_index\)')
lines[a:b + 1] = [
    '            lines_moved = line_count - db_idx - 1;',
    '            in_left = (lines_moved != 0);',
    '        }',
    '',
]

lo, hi = func('ml_append_int')
last_arg(one(lo, hi, r'ml_new_data\('), 'ml_new_data')

lo, hi = func('ml_append_int')
a = one(lo, hi, r'^        if \(!in_left\)$')
b = stmt_end(a)
for head in (r'^        if \(lines_moved\)$', r'^        if \(in_left\)$'):
    k = b + 1
    while lines[k].strip() == '':
        k += 1
    if not re.search(head, lines[k]):
        die('the split arm is not the three statements this edit replaces, at ' + lines[k])
    b = stmt_end(k)
lines[a:b + 1] = [
    '        if (!in_left)',
    '        {',
    '            dp_right->db_line[0].dl_text = text;',
    '            dp_right->db_line[0].dl_len = len;',
    '            dp_right->db_line[0].dl_marked = FALSE;',
    '            ++line_count_right;',
    '        }',
    '        if (lines_moved)',
    '        {',
    '             musl_memmove((char *)(&dp_right->db_line[line_count_right]), '
    '(char *)(&dp->db_line[db_idx + 1]), '
    '(usize)(lines_moved) * sizeof(DATA_LN)) ;',
    '            line_count_right += lines_moved;',
    '            line_count_left -= lines_moved;',
    '        }',
    '',
    '        if (in_left)',
    '        {',
    '            dp_left->db_line[line_count_left].dl_text = text;',
    '            dp_left->db_line[line_count_left].dl_len = len;',
    '            dp_left->db_line[line_count_left].dl_marked = FALSE;',
    '            ++line_count_left;',
    '        }',
]

# --- 7. ml_delete_int ------------------------------------------------------
lo, hi = func('ml_delete_int')
a = one(lo, hi, r'^    line_start = ')
b = stmt_end(a + 1)
if 'db_index[idx - 1]' not in '\n'.join(lines[a:b + 1]):
    die('the line_size computation is not the two-armed one this edit removes')
del lines[a:b + 1]

lo, hi = func('ml_delete_int')
a = one(lo, hi, r'^        text_start = dp->db_txt_start;$')
b = one(lo, hi, r'^        --\(dp->db_line_count\);$')
lines[a:b + 1] = [
    '        if (idx < count - 1)',
    '        {',
    '             musl_memmove((char *)(&dp->db_line[idx]), (char *)(&dp->db_line[idx + 1]), '
    '(usize)(count - idx - 1) * sizeof(DATA_LN)) ;',
    '        }',
    '        --(dp->db_line_count);',
]

# --- 8. the mark is a field ------------------------------------------------
lo, hi = func('ml_setmarked')
a = one(lo, hi, r'^    dp->db_index\[lnum - curbuf->b_ml\.ml_locked_low\] \|= ')
lines[a] = '    dp->db_line[lnum - curbuf->b_ml.ml_locked_low].dl_marked = TRUE;'
for name in ('ml_firstmarked', 'ml_clearmarked'):
    lo, hi = func(name)
    a = one(lo, hi, r'^            if \(\(dp->db_index\[i\]\) & ')
    b = one(lo, hi, r'^                \(dp->db_index\[i\]\) &= ')
    lines[a:b + 1] = [
        '            if (dp->db_line[i].dl_marked)',
        '            {',
        '                dp->db_line[i].dl_marked = FALSE;',
    ]

# --- 9. ml_flush_line stores the pointer -----------------------------------
lo, hi = func('ml_flush_line')
a = one(lo, hi, r'^            idx = lnum - buf->b_ml\.ml_locked_low;$')
b = stmt_end(first(a, hi, r'^            if \(\(int\)dp->db_free >= extra\)$'))
kept = carry(a, b, 12)
lines[a:b + 1] = [
    '            idx = lnum - buf->b_ml.ml_locked_low;',
    '',
    '            dp->db_line[idx].dl_text = new_line;',
    '            dp->db_line[idx].dl_len = buf->b_ml.ml_line_len;',
] + ([''] + kept if kept else [])
lo, hi = func('ml_flush_line')
a = one(lo, hi, r'^        vim_free\(new_line\);$')
del lines[a:a + 2]

# --- 10. ML_APPEND_MARK has no caller left ---------------------------------
left = [i for i, l in enumerate(lines) if re.search(r'\bML_APPEND_MARK\b', l)]
if len(left) != 1 or not lines[left[0]].startswith('enum { ML_APPEND_MARK'):
    die('ML_APPEND_MARK is still mentioned %d times and not only by its own '
        'enumerator, so the flag has a caller this edit did not see' % len(left))
del lines[left[0]]

# --- 11. the locals the rewrite stopped using ------------------------------
# COMPUTED, not listed: a declaration whose name is left mentioned once in its own
# function is mentioned only by itself.  This is what takes `space_needed`,
# `page_count`, `offset`, `from`, `to`, `data_moved`, `line_start`, `line_size`,
# `text_start`, `old_line`, `old_len`, `new_len`, `extra`, `start`, `end`, `count`
# and ml_flush_line's `i` -- and what leaves `page_size`, `total_moved` and
# ml_delete_int's `i`, each of which the pointer-block half still reads.
DECL = re.compile(r'^\s+(?:static\s+)?[A-Za-z_][A-Za-z0-9_]*(?:\s+\*?[A-Za-z_][A-Za-z0-9_]*)*'
                  r'\s+\*?([A-Za-z_][A-Za-z0-9_]*)\s*(?:=[^;]*)?;$')
# `return OK;` has the shape of a declaration and is not one.  The first word of a
# declaration is a type, never one of these.
NOTDECL = ('return', 'goto', 'break', 'continue', 'case', 'else', 'do')
dropped_locals = []
for name in ('ml_open', 'ml_get_buf', 'ml_append_int', 'ml_delete_int',
             'ml_setmarked', 'ml_firstmarked', 'ml_clearmarked', 'ml_flush_line',
             'ml_new_data'):
    while True:
        lo, hi = func(name)
        body = '\n'.join(lines[lo:hi + 1])
        for i in range(lo, hi + 1):
            m = DECL.match(lines[i])
            if m and lines[i].split()[0] in NOTDECL:
                continue
            if m and mentions(body, m.group(1)) == 1:
                dropped_locals.append('%s:%s' % (name, m.group(1)))
                del lines[i]
                break
        else:
            break
say('%d locals the rewrite stopped using, found by counting their own name: %s'
    % (len(dropped_locals), ' '.join(dropped_locals)))

# --- the partition again, on the output ------------------------------------
t = '\n'.join(lines)
for name in GONE:
    if mentions(t, name) != 0:
        die('%s survives the edit with %d mentions' % (name, mentions(t, name)))
if t.count(BIT) != 0:
    die('the stolen top bit survives the edit %d times' % t.count(BIT))
if re.search(r'\(char_u? \*\)dp[a-z_]* *\+', t.replace('(char *)dp', '(char_u *)dp')):
    die('an interior pointer into a data block survives the edit')
if 'offsetof(DATA_BL' in t:
    die('a data block is still being measured with offsetof')
if t.count('offsetof(PTR_BL') != 1:
    die('ml_new_ptr\'s offsetof is not where it was: a POINTER block is still a '
        'page and is not this phase\'s')
for name in ('dl_text', 'dl_len', 'dl_marked', 'DB_LINE_MAX', 'ml_alloc_line'):
    if mentions(t, name) == 0:
        die('%s is not in the output, so the replacement did not land' % name)

# The lifetime rule, as a partition over every assignment to a record's text.
owners = [(enclosing(i), lines[i].strip()) for i, l in enumerate(lines)
          if re.search(r'\.dl_text\s*=[^=]', l)]
want = {'ml_open': 1, 'ml_append_int': 3, 'ml_flush_line': 1}
got = {}
for fn, _ in owners:
    got[fn] = got.get(fn, 0) + 1
if got != want:
    die('a record\'s text is assigned in %s, and the lifetime rule this phase pins '
        'says it is assigned in exactly %s' % (got, want))
say('a record\'s text is assigned in exactly %d places -- %s -- and freed in none, '
    'so a pointer ml_get() returned stays readable for the life of the process'
    % (len(owners), ', '.join('%s x%d' % (k, want[k]) for k in sorted(want))))

open(path, 'w', errors='surrogateescape').write(t)
open(state + '/gone', 'w').write(
    '\n'.join('%s\t%d' % (n, before[n]) for n in GONE + (BIT,)) + '\n')
open(state + '/dbmax', 'w').write('%d\n' % DB_LINE_MAX)
say('%d -> %d lines: the leaf is an array of %d records and a line\'s text is its own '
    'allocation' % (n_in, len(lines), DB_LINE_MAX))
PY

# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  leaf         the input binary did not build with '$cflags' '$ldflags'"; exit 1; }
echo "  leaf         the input is $state/old, $(stat -c%s "$state/old") bytes, beside the source it was built from: this phase rewrites the storage of every line and owes two recordings that do not move"

# tools/phaserun.sh sweeps next, then runs pipes/zero44-check.sh.
