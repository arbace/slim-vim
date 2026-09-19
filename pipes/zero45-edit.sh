#!/bin/sh
# Zero phase 45 -- fold the node types.  See ZERO-GOAL.md.
#
# Usage: pipes/zero45-edit.sh <work-dir> <state-dir>     (run from the repository root)
#
# THE MEMFILE GOES, AND WITH IT THE LAST THING BETWEEN THE TREE AND ITS NODES.
# Until this phase a memline node is TWO allocations: a `bhdr_T` of four members --
# two list pointers, a `char_u *bh_data` and a lock flag -- and, hanging off it, a
# 4,096-byte PAGE that is cast to `PTR_BL *` or `DATA_BL *` depending on the two-byte
# id at its front.  A `memfile_T` of two members owns the list head and the page size.
# After this phase
#
#     struct block_hdr    { short_u bh_id; };
#     struct pointer_block{ bhdr_T pb_hdr; short_u pb_count; PTR_EN pb_pointer[PB_COUNT_MAX]; };
#     struct data_block   { bhdr_T db_hdr; linenr_T db_line_count; DATA_LN db_line[DB_LINE_MAX]; };
#
# and a node is ONE allocation AT ITS OWN SIZE: 1,040 bytes for a leaf and 4,088 for a
# branch, against 4,128 for either of them before.  `bhdr_T` is the node's tag and the
# first member of both, so `(PTR_BL *)hp` and `(bhdr_T *)pp` are the same address and
# the file needs no union; `memfile_T` has nothing left to hold and is gone; and the
# question "does this buffer have a memline" is `ml_root` where it was `ml_mfp`.
#
# THIS IS THE THING ZERO PHASE 44 NAMED AND DECLINED, in its own words: "Allocating a
# block at its own size means giving memfile a byte size where it has a page count ...
# It is named here so it is not lost: it would take the leaf from 112 bytes a line to
# 64, and it would MAKE AN OFF-BY-ONE IN THE CAPACITY BOUND VISIBLE, which today it is
# not."  Both halves are measured by the check rather than repeated: the leaf's node
# cost falls from 64.5 bytes a line to 16.25, and phase 44's own `cap` control -- the
# leaf capacity test widened by one -- moves 0 of 118 records on the input and 4 of 118
# here, in one run, with the input's binary built from the source beside it.
#
# WHAT THE FANOUT DOES, WHICH IS THE ONE THING THIS PHASE COULD HAVE DESTROYED.
# `pb_count_max` was computed per block as
# `(mf_page_size - offsetof(PTR_BL, pb_pointer)) / sizeof(PTR_EN)`, which is
# (4096 - 8) / 16 = 255, and it is the tree's fanout.  Zero phase 40's corpus reaches a
# ROOT SPLIT in exactly one of its sixteen cases, `mem_deep_jumps`, because that case
# builds 391 data blocks and 391 > 255; the other fifteen and all 102 screen cases
# reach none of it.  A phase that took `sizeof(PTR_EN)` to 8 would put the fanout at
# 511, and 391 < 511 would take root-split coverage to ZERO -- silently, because the
# instrument would still run and still pass.  So:
#
#   * PTR_EN IS NOT TOUCHED.  It is `{bhdr_T *pe_block; linenr_T pe_line_count;}` here
#     exactly as it was there, 16 bytes either side -- and a `static_assert` says so
#     rather than leaving it to be rediscovered.
#   * THE NEW STRUCT HAS THE SAME OFFSET.  `bhdr_T` is two bytes and `pb_count` two,
#     so `pb_pointer` starts at 8 as it did when `pb_id`, `pb_count` and
#     `pb_count_max` were three shorts.  PB_COUNT_MAX = 255 is therefore the number the
#     input computes and not a number chosen, and the second `static_assert` states it
#     that way: `PB_COUNT_MAX == (4096 - 8) / sizeof(PTR_EN)`, which FAILS TO COMPILE
#     if a later phase narrows the entry.
#
# The check measures the consequence and not just the arithmetic: the five markers of
# zero phase 40's instrument, on this phase's output and on its input in the same run,
# case by case.  And a control builds this phase's output with PB_COUNT_MAX = 511 and
# reports what it costs -- 0 of 118 records move and MLSPLITPTR, MLSPLITROOT and MLDEEP
# go 1 -> 0, which is the hazard demonstrated rather than described.
#
# WHAT GOES, MEASURED ON THE INPUT AND ASSERTED AS A PARTITION AND NOT AS A COUNT
# (below, `classify`).  Every mention of every one of these is in file scope, in one of
# the ten `mf_*` functions, in one of the eleven memline functions, or -- for `ml_mfp`
# alone -- in one of the seven places outside the memline that ask whether a buffer has
# one.  A mention anywhere else is a rule this edit does not have, and it refuses.
#
#   bh_next bh_prev       15 mentions   the used list, whose one consumer was mf_close
#   bh_data               24            the page hanging off the header
#   bh_flags               5            the lock: nothing can evict a block
#   mf_used_first          6            the list head
#   mf_page_size           6            the page size, read in four places
#   memfile memfile_T     27            the type and its tag
#   ml_mfp                25            the handle, and the "is it open" question
#   pb_id db_id            9            two tags where the node has one
#   pb_count_max           3            a field written once and read once
#   MEMFILE_PAGE_SIZE      3
#   the ten mf_* names    47            mf_open mf_close mf_new mf_get mf_put mf_free
#                                       mf_ins_used mf_rem_used mf_alloc_bhdr mf_free_bhdr
#   mfp                   55            no function holds a handle on a memfile
#   page_count page_size   8
#
# AND WHAT THE SWEEP TAKES, STATED HERE AS THE OTHER HALF OF THE SAME PARTITION, which
# is zero phase 43's form: `BH_LOCKED`, whose only three readers were mf_new, mf_get and
# mf_put, and `e_block_was_not_locked`, the E293 mf_put raised.  The edit leaves each at
# exactly ONE mention -- its own definition -- and the check requires the sweep to take
# both to zero and to take NOTHING ELSE.
#
# NOTHING IS FREED THAT WAS NOT FREED BEFORE, and the lifetime rule is unchanged.
# `mf_close()` walked the used list at ml_close() and freed every block on it, and the
# used list was exactly the set of live nodes -- so `ml_free_tree()` walks the TREE
# instead and frees the same set.  It is recursive and the depth is the tree's height,
# which is 3 on the heaviest case the corpus has.  `mf_free()`'s two call sites in
# ml_delete_int() become `vim_free(hp)`, one allocation where there were two.  A control
# measures that removing both is invisible, for the reason ZERO-GOAL.md's charter gives:
# host_free() returns without doing anything.
#
# THE ZEROING IS KEPT AND IT IS LOAD-BEARING ONCE.  mf_new() memset the page to 0 and
# the two constructors call alloc_clear() instead, which is the same act.  It matters in
# exactly one place: ml_open()'s error path runs ml_free_tree() over a root whose single
# pointer entry has not been filled in yet, and a zeroed `pe_block` is the nullptr that
# walk stops on.  A control measures that the host's arena happens to hand out zeroed
# memory anyway -- which is a fact about the host and not a promise to the core.
#
# HOW THE EDIT IS WRITTEN.  Every region is found by the function it is in and by its
# own first and last line; every local the fold stops using is removed by COMPUTING that
# its name is left mentioned once in its own function, never by listing it; and the two
# id constants are carried as they are found rather than spelled, because `(('p' << 8) +
# 't')` is zero phase 9's macro expansion and not this phase's text.  No line number is
# pinned and no line this phase does not itself replace is quoted.
set -eu

work=${1:?usage: zero45-edit.sh <work-dir> <state-dir>}
state=${2:?usage: zero45-edit.sh <work-dir> <state-dir>}
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

# The fanout, and the whole reason it is a literal rather than a computation: see the
# header above.  It is the number the input computes, and the output asserts it.
PB_COUNT_MAX = 255

# The names the fold removes, with the rule that each of them is only ever mentioned in
# one of HOMES below.  Counted on the input, required 0 on the output.
GONE = ('bh_next', 'bh_prev', 'bh_data', 'bh_flags',
        'mf_used_first', 'mf_page_size', 'memfile', 'memfile_T', 'ml_mfp',
        'pb_id', 'db_id', 'pb_count_max', 'MEMFILE_PAGE_SIZE',
        'mf_open', 'mf_close', 'mf_new', 'mf_get', 'mf_put', 'mf_free',
        'mf_ins_used', 'mf_rem_used', 'mf_alloc_bhdr', 'mf_free_bhdr',
        'mfp', 'page_count', 'page_size')

# The other half of the partition: what the EDIT leaves at exactly one mention -- its
# own definition -- for the SWEEP to take.  Stated here so that a sweep which took
# something else, or nothing, fails in the check.
FORSWEEP = ('BH_LOCKED', 'e_block_was_not_locked')

# Where a mention of a gone name is allowed to be in the input.  The ten mf_* functions
# and the eleven memline ones are this phase's whole subject; the seven others are the
# places that ask whether a buffer has a memline at all, which is the one question
# ml_mfp answered for anybody else.
HOMES = ('<file scope>',
         'mf_open', 'mf_close', 'mf_new', 'mf_get', 'mf_put', 'mf_free',
         'mf_ins_used', 'mf_rem_used', 'mf_alloc_bhdr', 'mf_free_bhdr',
         'ml_open', 'ml_close', 'ml_get_buf', 'ml_append_int', 'ml_delete_int',
         'ml_setmarked', 'ml_firstmarked', 'ml_clearmarked', 'ml_flush_line',
         'ml_new_data', 'ml_new_ptr', 'ml_find_line', 'ml_lineadd',
         'ml_append_flags', 'ml_replace_len',
         'buf_clear_file', 'buf_freeall', 'create_windows', 'curbuf_reusable',
         'get_nolist_virtcol', 'getout', 'open_buffer')


def die(msg):
    print('  node         ' + msg)
    sys.exit(1)


def say(msg):
    print('  node         ' + msg)


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
        die('%s is not a definition head exactly once (%d), so this edit cannot find '
            'the function it is about' % (name, len(hits)))
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


def all_of(lo, hi, pat):
    return [i for i in range(lo, hi + 1) if re.search(pat, lines[i])]


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


def defn(head_pat):
    """[head, end] of the definition whose name line matches HEAD_PAT."""
    a = one(0, len(lines) - 1, head_pat)
    i = a
    while lines[i] != '{':
        i += 1
    depth = 0
    while True:
        depth += lines[i].count('{') - lines[i].count('}')
        if depth == 0:
            return a - 1, i
        i += 1


def struct(name):
    """[a, b] of `struct NAME { ... };`, and its members."""
    a = lines.index('struct ' + name)
    b = a
    while lines[b] != '};':
        b += 1
    return a, b, [l.strip() for l in lines[a + 2:b] if l.strip()]


def cut(a, b):
    """Delete [a,b], and the blank line either side of it that would pair up."""
    if b + 1 < len(lines) and lines[b + 1].strip() == '':
        b += 1
    del lines[a:b + 1]
    if a > 0 and a < len(lines) and lines[a - 1].strip() == '' and lines[a].strip() == '':
        del lines[a]


# --- the partition, before anything is changed -----------------------------
before = {}
strays = []
for name in GONE + FORSWEEP:
    hits = [i for i, l in enumerate(lines) if re.search(r'\b%s\b' % name, l)]
    if not hits:
        die('%s is not in the input at all, so this phase has already run or the '
            'memfile is not the one it was written against' % name)
    # The COUNT is mentions and the classification is lines: mf_rem_used has
    # `hp->bh_prev->bh_next = hp->bh_next;`, two mentions on one line, and the check
    # re-reads the count off the input the same way.
    before[name] = mentions(t0, name)
    for i in hits:
        if enclosing(i) not in HOMES:
            strays.append('%s in %s (line %d)' % (name, enclosing(i), i + 1))
if strays:
    die('a name this phase removes is mentioned where it has no rule: '
        + '; '.join(strays[:5]))
say('the input mentions %s -- %d times between them -- and every mention is in file '
    'scope, in one of the ten mf_* functions, in one of the eleven memline functions, '
    'or in one of the seven that ask whether a buffer has a memline'
    % (', '.join(GONE), sum(before[n] for n in GONE)))

# The fanout, read off the INPUT rather than written here: the page size, the offset of
# the entry array in the struct the input has, and the width of an entry.
page = int(re.search(r'enum \{ MEMFILE_PAGE_SIZE = (\d+) \};', t0).group(1))
_a, _b, pbm = struct('pointer_block')
if [m.split()[-1] for m in pbm] != ['pb_id;', 'pb_count;', 'pb_count_max;', 'pb_pointer[1];']:
    die('struct pointer_block is not the page of entries this phase counts: ' + ' '.join(pbm))
if (page - 8) // 16 != PB_COUNT_MAX:
    die('the input computes a fanout of %d and this phase fixes it at %d; the corpus\'s '
        'root-split coverage is measured against the first number'
        % ((page - 8) // 16, PB_COUNT_MAX))
say('the input\'s fanout is (%d - 8) / 16 = %d, and that is the number this phase '
    'fixes: zero phase 40 reaches a ROOT SPLIT in one of sixteen cases because that '
    'case builds more data blocks than this' % (page, PB_COUNT_MAX))


# --- 1. struct block_hdr becomes the node's tag, and nothing else ----------
a, b, members = struct('block_hdr')
if members != ['bhdr_T      *bh_next;', 'bhdr_T      *bh_prev;',
               'char_u      *bh_data;', 'char        bh_flags;']:
    die('struct block_hdr is not the four-member page header this phase folds: '
        + ' '.join(members))
lines[a:b + 1] = [
    'struct block_hdr',
    '{',
    '    short_u     bh_id;',
    '};',
]

# --- 2. struct memfile has nothing left to hold ---------------------------
a, b, members = struct('memfile')
if members != ['bhdr_T      *mf_used_first;', 'unsigned    mf_page_size;']:
    die('struct memfile is not the two-member one this phase folds away: '
        + ' '.join(members))
cut(a, b)
del lines[lines.index('typedef struct memfile      memfile_T;')]

# --- 3. memline_T loses its handle on one ---------------------------------
i = lines.index('    memfile_T   *ml_mfp;')
if lines[i + 1] != '    bhdr_T      *ml_root;':
    die('ml_mfp is not the line above ml_root, so the memline is not the one this '
        'edit reads')
del lines[i]

# --- 4. the memfile layer itself ------------------------------------------
i = lines.index('enum { MEMFILE_PAGE_SIZE = %d };' % page)
if lines[i + 2] != 'static void mf_ins_used(memfile_T *, bhdr_T *);':
    die('the memfile block does not start where this edit expects')
j = i + 2
while lines[j].startswith('static ') and 'mf_' in lines[j]:
    j += 1
cut(i, j - 1)

for head in (r'^mf_open\(void\)$',
             r'^mf_close\(memfile_T \*mfp, int del_file\)$',
             r'^mf_new\(memfile_T \*mfp, int page_count\)$',
             r'^mf_get\(memfile_T \*mfp, bhdr_T \*hp\)$',
             r'^mf_put\(bhdr_T \*hp\)$',
             r'^mf_free\(memfile_T \*mfp, bhdr_T \*hp\)$',
             r'^mf_ins_used\(memfile_T \*mfp, bhdr_T \*hp\)$',
             r'^mf_rem_used\(memfile_T \*mfp, bhdr_T \*hp\)$',
             r'^mf_alloc_bhdr\(memfile_T \*mfp, int page_count\)$',
             r'^mf_free_bhdr\(bhdr_T \*hp\)$'):
    a, b = defn(head)
    cut(a, b)

# --- 5. a branch is a counted array of entries and not a page -------------
a, b, _ = struct('pointer_block')
lines[a:b + 1] = [
    'enum { PB_COUNT_MAX = %d };' % PB_COUNT_MAX,
    '',
    'struct pointer_block',
    '{',
    '    bhdr_T      pb_hdr;',
    '    short_u     pb_count;',
    '    PTR_EN      pb_pointer[PB_COUNT_MAX];',
    '};',
]

a, b, members = struct('data_block')
if [m.split()[-1] for m in members] != ['db_id;', 'db_line_count;', 'db_line[DB_LINE_MAX];']:
    die('struct data_block is not the leaf zero phase 44 left: ' + ' '.join(members))
lines[a + 2] = '    bhdr_T      db_hdr;'

i = one(0, len(lines) - 1, r'^static_assert\(sizeof\(DATA_BL\) <= MEMFILE_PAGE_SIZE,')
lines[i:i + 1] = [
    'static_assert(sizeof(PTR_EN) == 16, "a pointer entry is one node reference and one line count");',
    'static_assert(PB_COUNT_MAX == (%d - 8) / sizeof(PTR_EN), "the fanout the 4096-byte page gave, kept when the page went");' % page,
    'static_assert(sizeof(DATA_BL) == 16 + DB_LINE_MAX * sizeof(DATA_LN), "a leaf is its tag, its count and its records");',
]

# --- 6. the two constructors allocate a node at its own size --------------
# The id constants are CARRIED out of the definitions being replaced and never spelled:
# `(('p' << 8) + 't')` is zero phase 9's macro expansion, and an edit that wrote it out
# would be quoting somebody else's text.
def carried_id(head_pat, field):
    lo, hi = defn(head_pat)
    i = one(lo, hi, r'->%s =' % field)
    return lines[i].split('=', 1)[1].rstrip().rstrip(';').strip()


DA = carried_id(r'^ml_new_data\(memfile_T \*mfp\)$', 'db_id')
PT = carried_id(r'^ml_new_ptr\(memfile_T \*mfp\)$', 'pb_id')
if '<< 8' not in DA or '<< 8' not in PT or DA == PT:
    die('the two block ids are not the two distinct constants this edit carries: '
        '%r and %r' % (DA, PT))

i = lines.index('static bhdr_T *ml_new_data(memfile_T *);')
lines[i] = 'static bhdr_T *ml_new_data(void);'
i = lines.index('static bhdr_T *ml_new_ptr(memfile_T *);')
lines[i] = 'static bhdr_T *ml_new_ptr(void);'

a, b = defn(r'^ml_new_data\(memfile_T \*mfp\)$')
lines[a:b + 1] = [
    '    static bhdr_T *',
    'ml_new_data(void)',
    '{',
    '    DATA_BL     *dp;',
    '',
    '    dp =  (DATA_BL *)alloc_clear(sizeof(DATA_BL)) ;',
    '    if (dp == nullptr)',
    '    {',
    '        return nullptr;',
    '    }',
    '',
    '    dp->db_hdr.bh_id = %s;' % DA,
    '    dp->db_line_count = 0;',
    '',
    '    return (bhdr_T *)dp;',
    '}',
]

a, b = defn(r'^ml_new_ptr\(memfile_T \*mfp\)$')
lines[a:b + 1] = [
    '    static bhdr_T *',
    'ml_new_ptr(void)',
    '{',
    '    PTR_BL      *pp;',
    '',
    '    pp =  (PTR_BL *)alloc_clear(sizeof(PTR_BL)) ;',
    '    if (pp == nullptr)',
    '    {',
    '        return nullptr;',
    '    }',
    '',
    '    pp->pb_hdr.bh_id = %s;' % PT,
    '    pp->pb_count = 0;',
    '',
    '    return (bhdr_T *)pp;',
    '}',
]

# --- 7. a closed buffer gives its nodes back by walking the tree ----------
# mf_close() walked the used list, which held exactly the nodes the tree reaches.
lo, _hi = func('ml_alloc_line')
lines[lo:lo] = [
    '    static void',
    'ml_free_tree(bhdr_T *hp)',
    '{',
    '    PTR_BL      *pp;',
    '    int         i;',
    '',
    '    if (hp == nullptr)',
    '    {',
    '        return;',
    '    }',
    '    if (hp->bh_id == %s)' % PT,
    '    {',
    '        pp = (PTR_BL *)(hp);',
    '        for (i = 0; i < (int)pp->pb_count; ++i)',
    '        {',
    '            ml_free_tree(pp->pb_pointer[i].pe_block);',
    '        }',
    '    }',
    '    vim_free(hp);',
    '}',
    '',
]

# --- 8. ml_open opens nothing -----------------------------------------------
lo, hi = func('ml_open')
a = one(lo, hi, r'^    mfp = mf_open\(\);$')
b = stmt_end(a + 1)
c = b + 1
while lines[c].strip() == '':
    c += 1
if lines[c] != '    buf->b_ml.ml_mfp = mfp;':
    die('mf_open is not followed by its failure arm and the assignment to ml_mfp')
del lines[a:c + 1]

lo, hi = func('ml_open')
i = one(lo, hi, r'^    if \(\(hp = ml_new_ptr\(mfp\)\) == nullptr\)$')
lines[i] = '    if ((hp = ml_new_ptr()) == nullptr)'
i = one(lo, hi, r'^    pp = \(PTR_BL \*\)\(hp->bh_data\);$')
lines[i] = '    pp = (PTR_BL *)(hp);'
del lines[one(lo, hi, r'^    mf_put\(hp\);$')]

lo, hi = func('ml_open')
i = one(lo, hi, r'^    if \(\(hp = ml_new_data\(mfp\)\) == nullptr\)$')
lines[i] = '    if ((hp = ml_new_data()) == nullptr)'
i = one(lo, hi, r'->pb_pointer\[0\]\.pe_block = hp;$')
lines[i] = lines[i].replace('ml_root->bh_data', 'ml_root')
i = one(lo, hi, r'^    dp = \(DATA_BL \*\)\(hp->bh_data\);$')
lines[i] = '    dp = (DATA_BL *)(hp);'

lo, hi = func('ml_open')
a = one(lo, hi, r'^error:$')
b = one(lo, hi, r'^    buf->b_ml\.ml_mfp = nullptr;$')
lines[a:b + 1] = [
    'error:',
    '    ml_free_tree(buf->b_ml.ml_root);',
    '    buf->b_ml.ml_root = nullptr;',
]

# --- 9. ml_close frees the tree it has -------------------------------------
lo, hi = func('ml_close')
i = one(lo, hi, r'^    if \(buf->b_ml\.ml_mfp == nullptr\)$')
lines[i] = '    if (buf->b_ml.ml_root == nullptr)'
i = one(lo, hi, r'^    mf_close\(buf->b_ml\.ml_mfp, del_file\);$')
lines[i] = '    ml_free_tree(buf->b_ml.ml_root);'
i = one(lo, hi, r'^    buf->b_ml\.ml_mfp = nullptr;$')
lines[i] = '    buf->b_ml.ml_root = nullptr;'

# --- 10. the three functions that took a handle on the memfile ------------
lo, hi = func('ml_append_int')
i = one(lo, hi, r'^    mfp = buf->b_ml\.ml_mfp;$')
if not re.match(r'^    page_size = mfp->mf_page_size;$', lines[i + 1]):
    die('the page size is not read where this edit expects')
del lines[i:i + 2]
if lines[i - 1].strip() == '' and lines[i].strip() == '':
    del lines[i]

lo, hi = func('ml_delete_int')
i = one(lo, hi, r'^    mfp = buf->b_ml\.ml_mfp;$')
b = stmt_end(i + 1)
if 'return FAIL' not in '\n'.join(lines[i:b + 1]):
    die('the memfile null test in ml_delete_int is not the arm this edit rewrites')
lines[i:b + 1] = [
    '    if (buf->b_ml.ml_root == nullptr)',
    '    {',
    '        return FAIL;',
    '    }',
]

lo, hi = func('ml_find_line')
i = one(lo, hi, r'^    mfp = buf->b_ml\.ml_mfp;$')
if lines[i + 1].strip() != '':
    die('the memfile handle in ml_find_line is not followed by a blank line')
del lines[i:i + 2]

# --- 11. everywhere else, ml_mfp was the question "is this buffer loaded" --
for i, l in enumerate(lines):
    if re.search(r'\bml_mfp\b', l):
        lines[i] = re.sub(r'\bml_mfp\b', 'ml_root', l)

# --- 12. a node is reached without its header -----------------------------
for i, l in enumerate(lines):
    if '->bh_data' in l:
        lines[i] = re.sub(r'\(([A-Za-z_][A-Za-z0-9_]*) \*\)\(([A-Za-z_][A-Za-z0-9_]*)->bh_data\)',
                          r'(\1 *)(\2)', l)

# --- 13. one tag, in the node ---------------------------------------------
for i, l in enumerate(lines):
    if re.search(r'\b(pb_id|db_id)\b', l):
        lines[i] = re.sub(r'\b[A-Za-z_][A-Za-z0-9_]*->(?:pb_id|db_id)\b', 'hp->bh_id', l)

# --- 14. nothing can evict a block, so nothing locks one ------------------
for name in ('ml_append_int', 'ml_delete_int', 'ml_find_line', 'ml_lineadd'):
    while True:
        lo, hi = func(name)
        hits = all_of(lo, hi, r'^\s*mf_put\([^)]*\);$')
        if not hits:
            break
        i = hits[0]
        del lines[i]
        if i > 0 and i < len(lines) and lines[i - 1].strip() == '' and lines[i].strip() == '':
            del lines[i]

# --- 15. a block is its own pointer ---------------------------------------
while True:
    hits = [i for i, l in enumerate(lines) if re.search(r'\bmf_get\(', l)]
    if not hits:
        break
    i = hits[0]
    m = re.match(r'^(\s*)if \(\(hp = mf_get\(mfp, ([a-z>_.\[\]-]+)\)\) == nullptr\)$', lines[i])
    if not m:
        die('an mf_get is not the guarded assignment this edit rewrites: ' + lines[i])
    lines[i:stmt_end(i) + 1] = ['%shp = %s;' % (m.group(1), m.group(2))]

# --- 16. ml_append_int ----------------------------------------------------
lo, hi = func('ml_append_int')
i = one(lo, hi, r'^        if \(\(hp_new = ml_new_data\(mfp\)\) == nullptr\)$')
lines[i] = '        if ((hp_new = ml_new_data()) == nullptr)'
i = one(lo, hi, r'if \(pp->pb_count < pp->pb_count_max\)$')
lines[i] = lines[i].replace('pp->pb_count_max', 'PB_COUNT_MAX')
i = one(lo, hi, r'^                hp_new = ml_new_ptr\(mfp\);$')
lines[i] = '                hp_new = ml_new_ptr();'
# The root split copied the whole PAGE, which is how a node's contents moved while its
# header sat somewhere else.  The header is IN the node now, so what moves is the count
# and the entries that are in use -- which is also less than the page ever copied.
i = one(lo, hi, r'^ *musl_memmove\(\(char \*\)\(pp_new\), \(char \*\)\(pp\), \(usize\)page_size\) ;$')
lines[i:i + 1] = [
    '                pp_new->pb_count = pp->pb_count;',
    '                 musl_memmove((char *)(&pp_new->pb_pointer[0]), (char *)(&pp->pb_pointer[0]), (usize)pp->pb_count * sizeof(PTR_EN)) ;',
]

# --- 17. ml_delete_int releases a node by freeing it ----------------------
lo, hi = func('ml_delete_int')
freed = all_of(lo, hi, r'\bmf_free\(mfp, hp\);$')
if len(freed) != 2:
    die('ml_delete_int releases a block in %d places and this edit knows two' % len(freed))
for i in freed:
    lines[i] = lines[i].replace('mf_free(mfp, hp);', 'vim_free(hp);')

# --- 18. ml_find_line reads the tag off the node --------------------------
lo, hi = func('ml_find_line')
a = one(lo, hi, r'^\s+dp = \(DATA_BL \*\)\(hp\);$')
if not re.search(r'if \(hp->bh_id ==\s', lines[a + 1]):
    die('the leaf test does not follow the cast it replaces: ' + lines[a + 1])
del lines[a]
lo, hi = func('ml_find_line')
i = one(lo, hi, r'^\s+pp = \(PTR_BL \*\)\(dp\);$')
lines[i] = lines[i].replace('(dp)', '(hp)')
lo, hi = func('ml_find_line')
a = one(lo, hi, r'^error_block:$')
if lines[a + 1] != 'error_noblock:':
    die('error_block and error_noblock are not adjacent once the lock has gone')
del lines[a + 1]

# --- 19. the locals the fold stopped using --------------------------------
# COMPUTED, not listed: a declaration whose name is left mentioned once in its own
# function is mentioned only by itself.
DECL = re.compile(r'^\s+(?:static\s+)?[A-Za-z_][A-Za-z0-9_]*(?:\s+\*?[A-Za-z_][A-Za-z0-9_]*)*'
                  r'\s+\*?([A-Za-z_][A-Za-z0-9_]*)\s*(?:=[^;]*)?;$')
NOTDECL = ('return', 'goto', 'break', 'continue', 'case', 'else', 'do')
dropped = []
for name in ('ml_open', 'ml_close', 'ml_get_buf', 'ml_append_int', 'ml_delete_int',
             'ml_setmarked', 'ml_firstmarked', 'ml_clearmarked', 'ml_flush_line',
             'ml_new_data', 'ml_new_ptr', 'ml_find_line', 'ml_lineadd'):
    while True:
        lo, hi = func(name)
        body = '\n'.join(lines[lo:hi + 1])
        for i in range(lo, hi + 1):
            m = DECL.match(lines[i])
            if m and lines[i].split()[0] in NOTDECL:
                continue
            if m and mentions(body, m.group(1)) == 1:
                dropped.append('%s:%s' % (name, m.group(1)))
                del lines[i]
                break
        else:
            break
say('%d locals the fold stopped using, found by counting their own name: %s'
    % (len(dropped), ' '.join(dropped)))


# --- the partition again, on the output ------------------------------------
t = '\n'.join(lines)
for name in GONE:
    if mentions(t, name) != 0:
        die('%s survives the edit with %d mentions' % (name, mentions(t, name)))
for name in FORSWEEP:
    if mentions(t, name) != 1:
        die('%s is left at %d mentions and the edit leaves exactly one -- its own '
            'definition -- for the sweep to take' % (name, mentions(t, name)))
for name in ('PB_COUNT_MAX', 'bh_id', 'pb_hdr', 'db_hdr', 'ml_free_tree'):
    if mentions(t, name) == 0:
        die('%s is not in the output, so the replacement did not land' % name)
# THE OPEN-BUFFER PREDICATE MOVED 1:1, stated as a partition over the FUNCTIONS that
# ask it rather than as a count of mentions.  ml_root is compared with nullptr nowhere
# in the input, so there is nothing to disentangle: every function that asked ml_mfp
# asks ml_root, and the one that is added asked the same question through a local copy.
def askers(text, field):
    ls = text.split('\n')
    hit = [i for i, l in enumerate(ls) if re.search(r'\b%s\b *(==|!=) *nullptr' % field, l)]
    out = []
    for i in hit:
        for j in range(i, -1, -1):
            if ls[j] == '}':
                out.append('<file scope>')
                break
            m = re.match(r'^([a-zA-Z_][a-zA-Z0-9_]*)\(', ls[j])
            if m and j > 0 and ls[j - 1].lstrip().startswith('static'):
                out.append(m.group(1))
                break
    return sorted(set(out))


was, now = askers(t0, 'ml_mfp'), askers(t, 'ml_root')
if askers(t0, 'ml_root'):
    die('ml_root is already compared with nullptr in the input, so this edit cannot '
        'say that the open-buffer question moved onto it')
if sorted(set(was) | {'ml_delete_int'}) != now:
    die('the "is this buffer\'s memline open" question is asked in %s and it was asked '
        'in %s; the only one this edit adds is ml_delete_int, which asked it through a '
        'local copy of the handle' % (now, was))
say('the question "does this buffer have a memline" moved from ml_mfp to ml_root in '
    'all %d functions that asked it, plus ml_delete_int, which asked it through its own '
    'copy of the handle -- and ml_root was compared with nullptr in none of them before'
    % len(was))
# THE INPUT IS ASKED FIRST, and that is what `need 45 swept` is.  Blank lines are the
# one thing no verification tier can see, so this edit asserts that it leaves no run of
# two -- and the assertion is only about THIS edit if the text it was handed had none.
# Measured: phase 44's edit leaves one at line 33,815 of its own unswept output, which
# its sweep's canon removes, so on unswept text the output test would fire and blame
# this phase for the previous one's residue.
if re.search(r'\n\n\n', t0):
    die('the input already has a run of two blank lines, so this edit cannot say it '
        'left none: it needs swept text (pipes/zero.stages, `need 45 swept`)')
if re.search(r'\n\n\n', t):
    die('the edit left a run of two blank lines, which no verification tier can see')

open(path, 'w', errors='surrogateescape').write(t)
open(state + '/gone', 'w').write(
    '\n'.join('%s\t%d' % (n, before[n]) for n in GONE) + '\n')
open(state + '/forsweep', 'w').write('\n'.join(FORSWEEP) + '\n')
open(state + '/fanout', 'w').write('%d\n' % PB_COUNT_MAX)
say('%d -> %d lines: a node is ONE allocation at its own size, `bhdr_T` is its tag and '
    'the first member of both kinds, and there is no memfile' % (n_in, len(lines)))
PY

# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  node         the input binary did not build with '$cflags' '$ldflags'"; exit 1; }
echo "  node         the input is $state/old, $(stat -c%s "$state/old") bytes, beside the source it was built from: this phase changes how every block is allocated and reached, and owes two recordings that do not move"

# tools/phaserun.sh sweeps next, then runs pipes/zero45-check.sh.
