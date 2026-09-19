#!/bin/sh
# Zero phase 43 -- a block number becomes a reference.
#
# Usage: pipes/zero43-edit.sh <work-dir> <state-dir>     (run from the repository root)
#
# THE MEMLINE STOPS NAMING ITS BLOCKS BY NUMBER AND HOLDS THEM.  `pe_bnum` and
# `ip_bnum` become `bhdr_T *`, `memline_T` gains `ml_root`, and `mf_get(mfp, nr,
# page_count)` becomes `mf_get(mfp, hp)`.  The hash table that turned an integer block
# number into a page then has nothing left to look up, so it goes -- with the free list
# it was keyed alongside, with `mf_blocknr_max` that handed the numbers out, and with
# `pe_page_count`, whose one reader was the argument `mf_get` no longer takes.
#
# THIS IS THE PHASE THAT BUYS THE PORT THE MOST, AND IT IS WORTH SAYING WHY IN ONE
# SENTENCE: an integer key into a side hash table becomes an object reference, which is
# the one thing a JVM has and C does not make it say.  ZERO-PLAN.md 4d lists what a port
# would have to be told about rather than translate, and the memline page is the whole
# of the list; this removes the outer half of it -- the indirection BETWEEN pages.  It
# does NOT remove the inner half: `db_index[1]` indexed to the line count, the fourteen
# `(char_u *)dp + start` interior pointers and the page arithmetic are untouched and are
# phase 44's.  A reference to a block whose innards are still a byte array is halfway.
#
# WHAT WAS THERE.  `mf_new()` handed every block an integer from a counter, inserted it
# in `mf_hash` under that integer, and the tree stored the integer; `mf_get()` took the
# integer back and hashed it to the page.  Nothing had been written to a disk since zero
# phase 6 and nothing could be read from one since phase 9, so the hash had held every
# live block for thirty-four phases and a lookup could not miss.  Four measurements say
# that in the text rather than as a story, and they are this edit's first act:
#
#   * every block `mf_new()` makes is inserted in the hash, and the only thing that ever
#     removes one is `mf_free()`, which removes it from the used list in the same breath;
#   * `mf_get()`'s two ways of failing are `nr >= mf_blocknr_max || nr < 0` and a miss,
#     and no caller passes anything but a number the tree stored;
#   * the used list is not an ordering anything reads.  `mf_used_last` is WRITE-ONLY
#     here -- phase 42 took `ml_setflags()`, its last reader -- and there is no release
#     path left to walk it: `mf_release_all` is WHIM'S, three mentions in `slim-vim.c`
#     and none in `whim-vim.c`, and phase 42 showed `mf_dont_release` to be a constant.
#     So moving a block to the head of the list is bookkeeping nothing observes, and
#     this edit keeps it anyway;
#   * `pe_page_count` is read ONCE, into the argument `mf_get()` is about to lose.
#
# SO THE HASH IS A MAP FROM A NUMBER THIS FILE INVENTS TO A POINTER IT ALREADY HAD.
#
# WHAT A WRITE-ONLY FIELD COSTS, AND WHY FOUR OF THEM ARE IN THE EDIT.  tools/sweep.sh
# finds a function nothing calls, a type nothing names and a field named nowhere outside
# its own type; it finds none of `mf_used_last`, `bh_page_count`, `pe_page_count` or
# `pe_bnum`, because every one of them is WRITTEN.  tools/deadfields.py reports 0 fields
# in this region for exactly that reason, and gcc has no warning for a struct member in
# either direction.  Phase 20's trap is the other half of it: remove a member and leave
# its initialiser and the compile says `excess elements in struct initializer`, which is
# a correct phase failing.  Every field here goes WITH its writes, in this edit, and
# every mention of every one of them is partitioned below by the function it sits in --
# a partition and not a count, because a count is a bet on the phase before this one.
#
# THE ONE STRING THIS PHASE CHANGES, SAID HERE AND NOT BURIED.  `E323: Line count wrong
# in block %ld` is the only message in the file that printed a block number, and there
# is no number left to print.  It becomes `E323: Line count wrong in block`.  It is an
# `iemsg` on the arm of `ml_find_line()` that runs when the line counts under a pointer
# block do not add up to the tree's own line count -- an integrity check, reachable only
# from a corrupt tree -- and the check measures that no record in a whole recording
# reaches it, on the binary this phase was handed, and exhibits both messages from a
# build that forces the arm.  `E298: Didn't get block nr 0?` and `E298: Didn't get block
# nr 1?` are not changed but DELETED, with the two tests that were the only thing that
# could raise them: ml_open() asked whether the first two blocks came back numbered 0
# and 1, and the question has no meaning once there are no numbers.  Both strings are
# left standing for tools/sweep.sh, which is where an unreferenced object belongs.
#
# THE ROOT IS THE ONE BLOCK THE TREE CANNOT REACH BY DESCENT, so it needs a name.
# `ml_open()` used to rely on the first block it made being number 0 and `ml_find_line()`
# started every descent at 0; `ml_append_int()` asked `mhi_key != 0` to know whether the
# block that had just overflowed was the root.  `memline_T.ml_root` is that fact written
# down, set once in `ml_open()` and never again -- the root block's IDENTITY does not
# change when the root splits, which is what makes one field enough: the split copies the
# root's contents into a NEW block and leaves the root holding one entry that points at
# it, so `ml_root` is still the root and the stack entry above it is still right.
set -eu

work=${1:?usage: zero43-edit.sh <work-dir> <state-dir>}
state=${2:?usage: zero43-edit.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"

# The flags are the boundary makefile's and are not written here a second time
# (ZERO-GOAL.md rule 8).  The check needs the binary this phase was HANDED, for the
# instrumented pair and for the two recordings, so it is built here and left in the
# state directory (tools/phaserun.sh: what passes between the parts is files).
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
n_in = t.count('\n')
TAG = 'refblocks'


def die(msg):
    sys.exit('  %-12s %s' % (TAG, msg))


def say(what):
    print('  %-12s %s' % (TAG, what))


def lines():
    return t.split('\n')


def mentions(text, name):
    return len(re.findall(r'\b(?:%s)\b' % name, text))


def blank_runs(text):
    L = text.split('\n')
    return sum(1 for i in range(1, len(L)) if L[i] == '' and L[i - 1] == '')


def swap(old, new, what, why, n=1):
    global t
    c = t.count(old)
    if c != n:
        die('%s occurs %d times, expected %d -- %s' % (what, c, n, why))
    t = t.replace(old, new)


def heads(text=None):
    """Every definition in this tree's one shape: a name at column 0 with `(` after it
    and `{` at column 0 on the next line, closed by `}` at column 0."""
    L = (text if text is not None else t).split('\n')
    out = []
    for i, l in enumerate(L):
        m = re.match(r'^([A-Za-z_]\w*)\s*\(', l)
        if m and i + 1 < len(L) and L[i + 1] == '{':
            end = i + 1
            while end < len(L) and L[end] != '}':
                end += 1
            if end < len(L):
                out.append((i, end, m.group(1)))
    return out


def owners(name, text=None):
    """{function name: how many of its lines say `name`}, with everything outside a
    definition under '<file scope>'.  This is the phase's unit of assertion: WHERE a
    name is said, not how often, because the phase before this one moves the counts."""
    src = text if text is not None else t
    L = src.split('\n')
    hs = heads(src)
    def who(i):
        for a, b, n in hs:
            if a <= i <= b:
                return n
        return '<file scope>'
    d = {}
    for i, l in enumerate(L):
        if re.search(r'\b%s\b' % name, l):
            k = who(i)
            d[k] = d.get(k, 0) + 1
    return d


def places(name, expect, what):
    """Assert the SET of functions that say `name` -- not the counts."""
    got = owners(name)
    if set(got) != set(expect):
        die('`%s` is said in %s and this phase accounts for %s -- %s'
            % (name, sorted(got), sorted(expect), what))
    say('`%s` is said in %d places and nowhere else: %s'
        % (name, len(got), ', '.join('%s %d' % kv for kv in sorted(got.items()))))
    return got


def cut(a, b, what):
    """Delete from the one occurrence of `a` up to the one occurrence of `b`."""
    global t
    for s, side in ((a, 'start'), (b, 'end')):
        if t.count(s) != 1:
            die('the %s of %s occurs %d times and a cut needs exactly one'
                % (side, what, t.count(s)))
    i, j = t.index(a), t.index(b)
    if i >= j:
        die('%s: the start is not above the end' % what)
    n = t[i:j].count('\n')
    t = t[:i] + t[j:]
    return n


# ---------------------------------------------------------------------------------
# 0.  THE FILE THIS EDIT IS HANDED, AND THE ONE PLACE A MECHANICAL EDIT MUST NOT GO.
#
# Every name below is counted and partitioned by reading LINES, so a name inside a
# string literal would be read as code (CLAUDE.md, *Rename a name across the whole
# file*).  zero-vim.c has no preprocessor and no comments, so scanning for string and
# character literals is exact; this asserts the names are not in one rather than
# arranging to skip them, which is stronger and is checkable here.
# ---------------------------------------------------------------------------------
lit = re.compile(r'"(?:[^"\\\n]|\\.)*"' r"|'(?:[^'\\\n]|\\.)*'")
LITERALS = lit.findall(t)
NAMES = ('blocknr_T', 'mf_hashitem_T', 'mf_hashtab_T', 'mhi_key', 'mhi_next',
         'mhi_prev', 'bh_hashitem', 'pe_bnum', 'ip_bnum', 'pe_page_count',
         'bh_page_count', 'mf_blocknr_max', 'mf_free_first', 'mf_used_last',
         'mf_hash', 'ml_root', 'pe_block', 'ip_block')
inlit = [n for n in NAMES if any(re.search(r'\b%s\b' % n, s) for s in LITERALS)]
if inlit:
    die('%s appear inside a string literal, so a line-oriented partition would read '
        'data as code' % ', '.join(inlit))
for new in ('ml_root', 'pe_block', 'ip_block'):
    if mentions(t, new):
        die('`%s` is already said %d times, and this phase is what introduces it'
            % (new, mentions(t, new)))
say('%d string and character literals, and not one of them holds any of the %d names '
    'this edit partitions or the 3 it introduces' % (len(LITERALS), len(NAMES) - 3))

incs = [i for i, l in enumerate(lines()) if re.match(r'^ *# *include ', l)]
directives = [i for i, l in enumerate(lines()) if re.match(r'^ *#', l)]
if len(incs) != len(directives) or not incs:
    die('the input has %d preprocessor directives and %d of them are `#include`, and '
        'this phase adds none and removes none' % (len(directives), len(incs)))
BOUNDARY = incs[0]
say('the input is %d lines with %d `#include`s and no other directive, the first at '
    'line %d -- the line between the core and the host'
    % (n_in, len(incs), BOUNDARY + 1))

# ---------------------------------------------------------------------------------
# 1.  WHERE EVERY NAME THIS PHASE REMOVES IS SAID.  A PARTITION BY PLACE.
#
# Phase 35 had to repair phase 34's counted anchors after 34 moved them; phase 42 is
# this phase's direct predecessor and it removes four fields from the same two structs.
# So nothing here is a count.  What is asserted is the SET of functions that say each
# name -- which is what the phase's argument actually rests on, and which a predecessor
# that deletes a write does not change unless it deletes the last one in a function.
# ---------------------------------------------------------------------------------
HASH_IMPL = ('mf_hash_init', 'mf_hash_free', 'mf_hash_find', 'mf_hash_add_item',
             'mf_hash_rem_item', 'mf_hash_grow')
HASH_WRAP = ('mf_ins_hash', 'mf_rem_hash', 'mf_find_hash')
FREE_LIST = ('mf_ins_free', 'mf_rem_free')

places('mhi_key', ('<file scope>', 'mf_new', 'ml_open', 'ml_append_int',
                   'mf_hash_find', 'mf_hash_add_item', 'mf_hash_rem_item',
                   'mf_hash_grow'),
       'it is the hash key, the number mf_new() hands out and the number the tree stored')
places('bh_hashitem', ('<file scope>', 'mf_new', 'ml_open', 'ml_append_int'),
       'it is the hash item embedded in every block header')
places('pe_bnum', ('<file scope>', 'ml_open', 'ml_find_line', 'ml_append_int'),
       'it is the block number a pointer entry stores')
places('ip_bnum', ('<file scope>', 'ml_find_line', 'ml_append_int', 'ml_delete_int',
                   'ml_lineadd'),
       'it is the block number a stack entry remembers')
places('pe_page_count', ('<file scope>', 'ml_open', 'ml_find_line', 'ml_append_int'),
       "it is mf_get()'s third argument, stored so the lookup could size the page")
places('bh_page_count', ('<file scope>', 'mf_new', 'mf_alloc_bhdr', 'ml_append_int'),
       'it is the page count a block header carries')
places('mf_blocknr_max', ('<file scope>', 'mf_open', 'mf_new', 'mf_get'),
       'it is the counter the block numbers came from')
places('mf_free_first', ('<file scope>', 'mf_open', 'mf_close', 'mf_new') + FREE_LIST,
       'it is the head of the free list, which is keyed by block number')
places('mf_used_last', ('<file scope>', 'mf_open', 'mf_ins_used', 'mf_rem_used'),
              'it is the tail of the used list')

# `pe_page_count` has ONE reader and it is the argument mf_get is about to lose; every
# other mention writes it.  Read off the text rather than asserted from a list.
L = lines()
pe_reads = [i for i, l in enumerate(L)
            if re.search(r'\bpe_page_count\b', l) and not re.search(
                r'\bpe_page_count\s*=', l) and 'int         pe_page_count;' not in l]
if len(pe_reads) != 1 or 'page_count =' not in L[pe_reads[0]]:
    die('`pe_page_count` has %d readers and this phase rests on its having one, the '
        "argument mf_get() is about to lose" % len(pe_reads))
say('`pe_page_count` is read ONCE in the whole file -- %s -- and that read is the third '
    'argument of mf_get(); every other mention of it is a write'
    % L[pe_reads[0]].strip())

# `mf_used_last` is WRITE-ONLY on the text this phase is handed: phase 42 removed
# ml_setflags(), which walked the used list backwards and was its last reader.
lastw = [i for i, l in enumerate(L) if re.search(r'\bmf_used_last\b', l)]
lastr = [i for i in lastw if not re.search(r'\bmf_used_last\s*=', L[i])
         and 'bhdr_T      *mf_used_last;' not in L[i]]
if lastr:
    die('`mf_used_last` is read at %s, and this phase removes it as a write-only field'
        % ', '.join(L[i].strip() for i in lastr))
say('`mf_used_last` IS WRITE-ONLY: %d mentions, its declaration and %d writes and not '
    'one read -- phase 42 took ml_setflags(), which was the last thing that walked the '
    'used list backwards.  No warning gcc emits covers a struct member in either '
    'direction, so it goes in this edit with its writes' % (len(lastw), len(lastw) - 1))

# Every block mf_new() makes is hashed, and mf_free() is the only thing that unhashes
# one -- which is why a lookup cannot miss and a pointer is the same answer.
ins = [i for i, l in enumerate(L) if re.search(r'\bmf_ins_hash\s*\(', l)]
rem = [i for i, l in enumerate(L) if re.search(r'\bmf_rem_hash\s*\(', l)]
def who(i):
    for a, b, n in heads():
        if a <= i <= b:
            return n
    return '<file scope>'
ins_in = sorted(set(who(i) for i in ins) - {'<file scope>', 'mf_ins_hash'})
rem_in = sorted(set(who(i) for i in rem) - {'<file scope>', 'mf_rem_hash'})
if ins_in != ['mf_get', 'mf_new'] or rem_in != ['mf_free', 'mf_get']:
    die('the hash is inserted into from %s and removed from from %s, and this phase '
        'rests on mf_new() and mf_get() being the only insertions and mf_free() and '
        'mf_get() the only removals' % (ins_in, rem_in))
say('THE HASH HOLDS EVERY LIVE BLOCK: it is inserted into by %s and removed from by '
    '%s, and mf_get() does both in one breath to move a block to the head of the used '
    'list -- so a lookup by a number the tree stored cannot miss, and the pointer it '
    'would have returned is the same answer' % (' and '.join(ins_in), ' and '.join(rem_in)))

# ---------------------------------------------------------------------------------
# 2.  THE TYPES.
# ---------------------------------------------------------------------------------
swap("""typedef struct block_hdr    bhdr_T;
typedef struct memfile      memfile_T;
typedef long                blocknr_T;

typedef struct mf_hashitem_S mf_hashitem_T;

struct mf_hashitem_S
{
    mf_hashitem_T   *mhi_next;
    mf_hashitem_T   *mhi_prev;
    blocknr_T       mhi_key;
};

enum { MHT_INIT_SIZE = 64 };

typedef struct mf_hashtab_S
{
    long_u          mht_mask;
    long_u          mht_count;
    mf_hashitem_T   **mht_buckets;
    mf_hashitem_T   *mht_small_buckets[MHT_INIT_SIZE];
    char            mht_fixed;
} mf_hashtab_T;

struct block_hdr
{
    mf_hashitem_T bh_hashitem;

    bhdr_T      *bh_next;
    bhdr_T      *bh_prev;
    char_u      *bh_data;
    int         bh_page_count;

    char        bh_flags;
};
""", """typedef struct block_hdr    bhdr_T;
typedef struct memfile      memfile_T;

struct block_hdr
{
    bhdr_T      *bh_next;
    bhdr_T      *bh_prev;
    char_u      *bh_data;

    char        bh_flags;
};
""", 'the block header and the hash types',
     'a block header carries a hash item and a page count, and this phase leaves it '
     'carrying two links, a page and a lock bit')

swap("""struct memfile
{
    bhdr_T      *mf_free_first;
    bhdr_T      *mf_used_first;
    bhdr_T      *mf_used_last;
    mf_hashtab_T mf_hash;
    blocknr_T   mf_blocknr_max;
    unsigned    mf_page_size;
};""", """struct memfile
{
    bhdr_T      *mf_used_first;
    unsigned    mf_page_size;
};""", 'the memfile', 'it is a free list, a used list, a hash and a counter, and this '
       'phase leaves it a used list and a page size')

swap("""typedef struct info_pointer
{
    blocknr_T   ip_bnum;""", """typedef struct info_pointer
{
    bhdr_T      *ip_block;""", "the stack entry's block",
     'a stack entry remembers the block it came down through')

swap("""struct pointer_entry
{
    blocknr_T   pe_bnum;
    linenr_T    pe_line_count;
    int         pe_page_count;
};""", """struct pointer_entry
{
    bhdr_T      *pe_block;
    linenr_T    pe_line_count;
};""", 'the pointer entry',
     'a pointer entry is a child and the number of lines under it')

swap("""    linenr_T    ml_line_count;

    memfile_T   *ml_mfp;
""", """    linenr_T    ml_line_count;

    memfile_T   *ml_mfp;
    bhdr_T      *ml_root;
""", 'the memline', 'the root is the one block no descent can reach, so it is named')

# ---------------------------------------------------------------------------------
# 3.  THE MEMFILE.  Eleven functions go, and they go HERE and not to tools/sweep.sh:
#     every one of them names a type or a field removed above, so leaving them for the
#     sweep would leave a file that does not compile for the sweep to ask gcc about.
# ---------------------------------------------------------------------------------
for name in HASH_WRAP + FREE_LIST + HASH_IMPL:
    pat = re.compile(r'^static [\w *]*%s\([^\n]*\);\n' % name, re.M)
    m = pat.search(t)
    if not m:
        die('`%s` has no forward declaration in the one shape this tree writes them' % name)
    t = t[:m.start()] + t[m.end():]
say('%d forward declarations go: %s' % (len(HASH_WRAP + FREE_LIST + HASH_IMPL),
                                        ', '.join(HASH_WRAP + FREE_LIST + HASH_IMPL)))

swap("""    mfp->mf_free_first = nullptr;
    mfp->mf_used_first = nullptr;
    mfp->mf_used_last = nullptr;
    mf_hash_init(&mfp->mf_hash);
    mfp->mf_page_size = MEMFILE_PAGE_SIZE;
    mfp->mf_blocknr_max = 0;
""", """    mfp->mf_used_first = nullptr;
    mfp->mf_page_size = MEMFILE_PAGE_SIZE;
""", "mf_open()'s body", 'it initialises what the memfile no longer has')

swap("""    while (mfp->mf_free_first != nullptr)
    {
        vim_free(mf_rem_free(mfp));
    }
    mf_hash_free(&mfp->mf_hash);
    vim_free(mfp);""", """    vim_free(mfp);""", "mf_close()'s tail",
     'it drains a free list and frees a bucket array that are both gone.  The loop '
     'above it, which frees every block on the USED list, is untouched -- and it is '
     'now the only one, because mf_free() releases a block outright')

swap("""mf_new(memfile_T *mfp, int page_count)
{
    bhdr_T      *hp;
    bhdr_T      *freep;
    char_u      *p;

    hp = nullptr;

    freep = mfp->mf_free_first;
    if (freep != nullptr && freep->bh_page_count >= page_count)
    {
        if (freep->bh_page_count > page_count)
        {
            if (hp == nullptr && (hp = mf_alloc_bhdr(mfp, page_count)) == nullptr)
            {
                return nullptr;
            }
            hp-> bh_hashitem.mhi_key  = freep-> bh_hashitem.mhi_key ;
            freep-> bh_hashitem.mhi_key  += page_count;
            freep->bh_page_count -= page_count;
        }
        else if (hp == nullptr)
        {
            if ((p = alloc((usize)mfp->mf_page_size * page_count)) == nullptr)
            {
                return nullptr;
            }
            hp = mf_rem_free(mfp);
            hp->bh_data = p;
        }
        else
        {
            freep = mf_rem_free(mfp);
            hp-> bh_hashitem.mhi_key  = freep-> bh_hashitem.mhi_key ;
            vim_free(freep);
        }
    }
    else
    {
        if (hp == nullptr && (hp = mf_alloc_bhdr(mfp, page_count)) == nullptr)
        {
            return nullptr;
        }
        hp-> bh_hashitem.mhi_key  = mfp->mf_blocknr_max;
        mfp->mf_blocknr_max += page_count;
    }
    hp->bh_flags = BH_LOCKED;
    hp->bh_page_count = page_count;
    mf_ins_used(mfp, hp);
    mf_ins_hash(mfp, hp);
""", """mf_new(memfile_T *mfp, int page_count)
{
    bhdr_T      *hp;

    if ((hp = mf_alloc_bhdr(mfp, page_count)) == nullptr)
    {
        return nullptr;
    }
    hp->bh_flags = BH_LOCKED;
    mf_ins_used(mfp, hp);
""", 'mf_new()',
     'three of its four arms split, adopt or reuse a block from the free list by '
     'BLOCK-NUMBER ARITHMETIC, and the fourth takes the next number from the counter.  '
     'What is left is the allocation all four ended in')

swap("""mf_get(memfile_T *mfp, blocknr_T nr, int page_count)
{
    bhdr_T    *hp;
    if (nr >= mfp->mf_blocknr_max || nr < 0)
    {
        return nullptr;
    }

    hp = mf_find_hash(mfp, nr);
    if (hp == nullptr)
    {
            return nullptr;
        }
    else
    {
        mf_rem_used(mfp, hp);
        mf_rem_hash(mfp, hp);
    }

    hp->bh_flags |= BH_LOCKED;
    mf_ins_used(mfp, hp);
    mf_ins_hash(mfp, hp);

    return hp;
}""", """mf_get(memfile_T *mfp, bhdr_T *hp)
{
    if (hp == nullptr)
    {
        return nullptr;
    }

    mf_rem_used(mfp, hp);

    hp->bh_flags |= BH_LOCKED;
    mf_ins_used(mfp, hp);

    return hp;
}""", 'mf_get()',
     'it is the lookup itself.  Both of its ways of failing were ways of failing to '
     'RESOLVE a number -- out of range, or absent from the hash -- and the null test '
     'that survives is the same shape for a caller: every `goto error_noblock` and '
     'every `return FAIL` below it is reached by the same line as before')

swap("""mf_free(memfile_T *mfp, bhdr_T *hp)
{
    vim_free(hp->bh_data);
    mf_rem_hash(mfp, hp);
    mf_rem_used(mfp, hp);
    mf_ins_free(mfp, hp);
}""", """mf_free(memfile_T *mfp, bhdr_T *hp)
{
    mf_rem_used(mfp, hp);
    mf_free_bhdr(hp);
}""", 'mf_free()',
     'it freed the page and kept the header on a free list under its old number, for '
     'mf_new() to split or adopt.  With no number to key it by, a released block is '
     'released: mf_free_bhdr() is the function that already did exactly this for every '
     'block in mf_close()')

n = cut("""    static void
mf_ins_hash(memfile_T *mfp, bhdr_T *hp)""", """    static void
mf_ins_used(memfile_T *mfp, bhdr_T *hp)""", 'the three hash wrappers')
say('the three one-line wrappers go, %d lines: %s' % (n, ', '.join(HASH_WRAP)))

swap("""    hp->bh_prev = nullptr;
    if (hp->bh_next == nullptr)
    {
        mfp->mf_used_last = hp;
    }
    else
    {
        hp->bh_next->bh_prev = hp;
    }
}""", """    hp->bh_prev = nullptr;
    if (hp->bh_next != nullptr)
    {
        hp->bh_next->bh_prev = hp;
    }
}""", "mf_ins_used()'s tail", 'it maintains a tail pointer nothing reads')

swap("""    if (hp->bh_next == nullptr)
    {
        mfp->mf_used_last = hp->bh_prev;
    }
    else
    {
        hp->bh_next->bh_prev = hp->bh_prev;
    }
""", """    if (hp->bh_next != nullptr)
    {
        hp->bh_next->bh_prev = hp->bh_prev;
    }
""", "mf_rem_used()'s head", 'it maintains the same tail pointer')

swap("""    hp->bh_page_count = page_count;
    return hp;
}
""", """    return hp;
}
""", "mf_alloc_bhdr()'s page count",
     'the header stops carrying a count nothing reads; the argument still sizes the '
     'allocation two lines above')

n = cut("""    static void
mf_ins_free(memfile_T *mfp, bhdr_T *hp)""", """typedef struct pointer_block    PTR_BL;""",
        'the free list and the whole hash implementation')
say('the free list and the hash implementation go, %d lines: %s, the two MHT_ '
    'enumerators and %s'
    % (n, ', '.join(FREE_LIST), ', '.join(HASH_IMPL)))

# ---------------------------------------------------------------------------------
# 4.  THE MEMLINE.
# ---------------------------------------------------------------------------------
swap("""    if (hp-> bh_hashitem.mhi_key  != 0)
    {
        iemsg(e_didnt_get_block_nr_zero);
        goto error;
    }
    pp = (PTR_BL *)(hp->bh_data);
    pp->pb_count = 1;
    pp->pb_pointer[0].pe_bnum = 1;
    pp->pb_pointer[0].pe_page_count = 1;
    pp->pb_pointer[0].pe_line_count = 1;
    mf_put(hp);

    if ((hp = ml_new_data(mfp, 1)) == nullptr)
    {
        goto error;
    }
    if (hp-> bh_hashitem.mhi_key  != 1)
    {
        iemsg(e_didnt_get_block_nr_one);
        goto error;
    }
""", """    buf->b_ml.ml_root = hp;
    pp = (PTR_BL *)(hp->bh_data);
    pp->pb_count = 1;
    pp->pb_pointer[0].pe_line_count = 1;
    mf_put(hp);

    if ((hp = ml_new_data(mfp, 1)) == nullptr)
    {
        goto error;
    }
    ((PTR_BL *)(buf->b_ml.ml_root->bh_data))->pb_pointer[0].pe_block = hp;
""", "ml_open()'s two blocks",
     'it made a pointer block and a data block and asserted they came back numbered 0 '
     'and 1, then wrote the number 1 into the root entry BEFORE the block existed.  '
     'The root is remembered instead, and the entry is filled with the block itself '
     'once there is one')

swap("""    buf->b_ml.ml_stack_size = 0;
""", """    buf->b_ml.ml_stack_size = 0;
    buf->b_ml.ml_root = nullptr;
""", "ml_open()'s preamble",
     'ml_root joins the fields ml_open() clears before it can fail, so the error path '
     'leaves a memline that names no block')

swap("""    linenr_T    t;
    blocknr_T bnum;
    linenr_T low;""", """    linenr_T    t;
    bhdr_T      *bp;
    linenr_T low;""", "ml_find_line()'s cursor",
     'the descent carries the block it is about to fetch')
swap("""    int         top;
    int         page_count;
    int         idx;
""", """    int         top;
    int         idx;
""", "ml_find_line()'s page count", "it is mf_get()'s third argument and there is none")
swap("""    bnum = 0;
    page_count = 1;
    low = 1;""", """    bp = buf->b_ml.ml_root;
    low = 1;""", 'where a descent starts',
     'it started at block number 0 because ml_open() had asserted the root was block 0')
swap("""                bnum = ip->ip_bnum;
                low = ip->ip_low;""", """                bp = ip->ip_block;
                low = ip->ip_low;""", 'where a descent resumes',
     'ML_FIND restarts from the deepest stack entry that still covers the line')
swap("""        if ((hp = mf_get(mfp, bnum, page_count)) == nullptr)""",
     """        if ((hp = mf_get(mfp, bp)) == nullptr)""", "the descent's fetch",
     'it is the lookup this phase removes')
swap("""        ip->ip_bnum = bnum;
        ip->ip_low = low;""", """        ip->ip_block = bp;
        ip->ip_low = low;""", 'what a descent pushes',
     'the stack remembers the block, not its number')
swap("""                bnum = pp->pb_pointer[idx].pe_bnum;
                page_count = pp->pb_pointer[idx].pe_page_count;
                high = low - 1;""", """                bp = pp->pb_pointer[idx].pe_block;
                high = low - 1;""", 'the step down',
     'the child is the entry itself, and its page count was only ever the argument of '
     'the lookup on the line above')
swap("""                vim_snprintf((char *)IObuff, emsg_iobuff_room(), e_line_count_wrong_in_block_nr, bnum);
                iemsg(iobuff_or(e_line_count_wrong_in_block_nr));""",
     """                iemsg(e_line_count_wrong_in_block);""", 'E323',
     'it is the one message in the file that printed a block number.  The arm above it, '
     'which reports a line past the end, keeps IObuff and its formatting')
swap("""static char e_line_count_wrong_in_block_nr[]  = "E323: Line count wrong in block %ld" ;""",
     """static char e_line_count_wrong_in_block[]  = "E323: Line count wrong in block" ;""",
     "E323's text", 'the %ld has nothing to print')

swap("""        long line_count_left;
        long line_count_right;
        int page_count_left;
        int page_count_right;
        bhdr_T      *hp_left;""", """        long line_count_left;
        long line_count_right;
        bhdr_T      *hp_left;""", "ml_append_int()'s page counts",
     'they are read out of the two blocks being labelled and stored in their entries, '
     'and no entry has the field.  gcc reports a local that is written and never read '
     'as -Wunused-but-set-variable, which tools/deadsweep.py does not act on '
     '(CLAUDE.md, *Audit for dead code*), so they go in the edit')
swap("""        blocknr_T bnum_left;
        blocknr_T bnum_right;""", """        bhdr_T      *bp_left;
        bhdr_T      *bp_right;""", "ml_append_int()'s two labels",
     'a split labels the block on each side of it, and a label is now the block')
swap("""        bnum_left = hp_left-> bh_hashitem.mhi_key ;
        bnum_right = hp_right-> bh_hashitem.mhi_key ;
        page_count_left = hp_left->bh_page_count;
        page_count_right = hp_right->bh_page_count;
""", """        bp_left = hp_left;
        bp_right = hp_right;
""", 'what a data-block split labels its halves with',
     'the number and the page count came out of the two block headers')
swap("""                if (hp-> bh_hashitem.mhi_key  != 0)
                {
                    break;
                }""", """                if (hp != buf->b_ml.ml_root)
                {
                    break;
                }""", 'the root test',
     'a pointer block that has overflowed is split in two UNLESS it is the root, which '
     'must keep its identity because the tree hangs from it.  The test was `is this '
     'block number 0`, which was the root only because ml_open() had made it first')
swap("""                pp->pb_pointer[0].pe_bnum = hp_new-> bh_hashitem.mhi_key ;
                pp->pb_pointer[0].pe_line_count = buf->b_ml.ml_line_count;
                pp->pb_pointer[0].pe_page_count = 1;
""", """                pp->pb_pointer[0].pe_block = hp_new;
                pp->pb_pointer[0].pe_line_count = buf->b_ml.ml_line_count;
""", 'the root split',
     'the root copies itself into a new block and keeps ONE entry pointing at it -- '
     'which is why ml_root is set once and never again: the block that is the root is '
     'still the root afterwards')
swap("""            bnum_left = hp-> bh_hashitem.mhi_key ;
            bnum_right = hp_new-> bh_hashitem.mhi_key ;
            page_count_left = 1;
            page_count_right = 1;
""", """            bp_left = hp;
            bp_right = hp_new;
""", 'what a pointer-block split labels its halves with',
     'the loop climbs, and each level relabels with the two blocks it has just made')

# The seven remaining stores, as a partition over the two labels: every store of a
# pointer entry's block is one of these two, and a leftover refuses.
for old, new, side in (('pe_bnum = bnum_left;', 'pe_block = bp_left;', 'left'),
                       ('pe_bnum = bnum_right;', 'pe_block = bp_right;', 'right')):
    c = t.count(old)
    if c < 1:
        die('no store of the %s label is left, and a split has two sides' % side)
    t = t.replace(old, new)
    say('%d stores of the %s label' % (c, side))
for old in ('pp->pb_pointer[pb_idx].pe_page_count = page_count_left;\n',
            'pp->pb_pointer[pb_idx + 1].pe_page_count = page_count_right;\n',
            'pp_new->pb_pointer[0].pe_page_count = page_count_right;\n'):
    c = t.count(old)
    if c < 1:
        die('a page-count store this phase accounts for is not there: %r' % old)
    t = re.sub(r'\n *' + re.escape(old.rstrip('\n')), '', t)

c = t.count('mf_get(mfp, ip->ip_bnum, 1)')
if c < 1:
    die('no stack-walk fetch is left, and the three loops that climb the tree all make one')
t = t.replace('mf_get(mfp, ip->ip_bnum, 1)', 'mf_get(mfp, ip->ip_block)')
say('%d stack-walk fetches become mf_get(mfp, ip->ip_block)' % c)

# ---------------------------------------------------------------------------------
# 5.  WHAT IS LEFT, AS A PARTITION.  Every name above is gone from the whole file, and
#     the three that replace them are in exactly the places that had them.
# ---------------------------------------------------------------------------------
GONE = ('blocknr_T', 'mf_hashitem_T', 'mf_hashtab_T', 'mhi_key', 'mhi_next', 'mhi_prev',
        'mht_mask', 'mht_count', 'mht_buckets', 'mht_small_buckets', 'mht_fixed',
        'MHT_INIT_SIZE', 'MHT_LOG_LOAD_FACTOR', 'MHT_GROWTH_FACTOR', 'bh_hashitem',
        'pe_bnum', 'ip_bnum', 'pe_page_count', 'bh_page_count', 'mf_blocknr_max',
        'mf_free_first', 'mf_used_last', 'mf_hash', 'page_count_left',
        'page_count_right', 'bnum_left', 'bnum_right') + HASH_WRAP + FREE_LIST + HASH_IMPL
left = [(n, mentions(t, n)) for n in GONE if mentions(t, n)]
if left:
    die('%s still said: %s.  If they are `blocknr_T`, `mf_hashitem_T` and '
        '`mf_hashtab_T` at one mention each, the input is UNSWEPT: phase 42 leaves '
        '`mf_hash_free_all` standing for tools/sweep.sh and its forward declaration '
        'names all three (`need 43 swept` in pipes/zero.stages)'
        % ('a name this phase removes is' if len(left) == 1
           else 'names this phase removes are',
           ', '.join('%s %d' % kv for kv in left)))
say('%d names are gone from the whole file: the two hash types and blocknr_T, their '
    'nine fields and three enumerators, the four block-number fields, the two page '
    'counts, the free list, the used tail and the eleven functions' % len(GONE))

for new, expect, what in (
        ('ml_root', ('<file scope>', 'ml_open', 'ml_append_int', 'ml_find_line'),
         'the root is set in ml_open(), tested in ml_append_int() and is where every '
         'descent starts'),
        ('pe_block', ('<file scope>', 'ml_open', 'ml_find_line', 'ml_append_int'),
         'exactly where pe_bnum was'),
        ('ip_block', ('<file scope>', 'ml_find_line', 'ml_append_int', 'ml_delete_int',
                      'ml_lineadd'), 'exactly where ip_bnum was')):
    places(new, expect, what)

# Two strings are left standing for tools/sweep.sh, which is where an object nothing
# refers to belongs; nothing that is WRITTEN is left for it, because no tool can see one.
STANDING = ('e_didnt_get_block_nr_zero', 'e_didnt_get_block_nr_one')
for name in STANDING:
    if mentions(t, name) != 1:
        die('`%s` has %d mentions and this edit leaves it at one, its own definition, '
            'which is what the sweep takes' % (name, mentions(t, name)))
say('%d names are left standing for tools/sweep.sh: %s -- each is an unreferenced '
    'file-scope object, which is -Wunused-variable and the one kind of dead thing in '
    'this phase that a tool can see' % (len(STANDING), ', '.join(STANDING)))

# ---------------------------------------------------------------------------------
# 6.  THE SHAPE OF WHAT IS WRITTEN OUT.
# ---------------------------------------------------------------------------------
if blank_runs(t):
    die('%d runs of two blank lines -- no verification tier can see paragraphing '
        '(CLAUDE.md, *Verification tiers*)' % blank_runs(t))
incs2 = [i for i, l in enumerate(lines()) if re.match(r'^ *# *include ', l)]
dirs2 = [i for i, l in enumerate(lines()) if re.match(r'^ *#', l)]
if len(incs2) != len(incs) or len(dirs2) != len(incs2):
    die('the output has %d directives and %d of them are `#include`, against %d and %d'
        % (len(dirs2), len(incs2), len(directives), len(incs)))
if incs2 != list(range(incs2[0], incs2[0] + len(incs2))):
    die('the eleven `#include`s are not contiguous any more')
n_out = t.count('\n')
say('%d -> %d lines before the sweep, %d fewer, the %d `#include`s untouched and still '
    'contiguous, and no run of two blank lines' % (n_in, n_out, n_in - n_out, len(incs2)))

open(path, 'w', errors='surrogateescape').write(t)
# The edit leaves its own output beside the input, so the check can say what the EDIT
# removed and what the SWEEP removed separately (tools/phaserun.sh: what passes between
# the parts is files).
open(state + '/edit.c', 'w', errors='surrogateescape').write(t)
open(state + '/boundary-in', 'w').write('%d\n' % (BOUNDARY + 1))
PY

# NOT tools/create_cmdidxs.py --check, for pipes/zero2-edit.sh's reason: the derived
# first-two-letters index went with the command table whim's phase 80 reduced, and the
# tool raises rather than reporting nothing.  Nothing here touches the command table.
#
# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  refblocks    the input binary did not build with '$cflags' '$ldflags'"; exit 1; }
echo "  refblocks    the input is $state/old, $(stat -c%s "$state/old") bytes, built with SOURCE_DATE_EPOCH=0 beside $state/old.c.  Every block in the tree is reached differently, so the binary is NOT byte-identical and this phase cannot use tier 1 of CLAUDE.md's verification table: the evidence is two whole recordings -- including the sixteen memline cases zero phase 40 added, which are the only part of any zero recording that asks the TREE a question -- an instrumented pair for the one message it changes, and controls that move what it must not"

# tools/phaserun.sh sweeps next, then runs pipes/zero43-check.sh.
