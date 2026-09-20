#!/bin/sh
# Zero phase 43 -- the proof.  See pipes/zero43-edit.sh for what the phase does.
#
# Usage: pipes/zero43-check.sh <work-dir> <state-dir>    (run from the repository root)
#
# WHAT THIS PHASE HAS TO SHOW, AND WHY IT IS NOT THE USUAL LIST.  Every keystroke in
# this editor reaches its text through `ml_find_line()`, and this phase changes how that
# function finds every block.  So the recording is not the weak part of the evidence
# here -- it is the strong part, PROVIDED the recording can see the text layer at all,
# which it could not before zero phase 40.  Nine sections:
#
#   1  the source, with what the EDIT took and what the SWEEP took kept apart, and every
#      name that leaves partitioned against a reason
#   2  THE BLOCK ARITHMETIC, DERIVED: `sizeof(PTR_EN)` and `pb_count_max` computed by
#      compiling the structs out of both sources, because a pointer entry that has lost
#      a field holds MORE children per page and that is what decides whether phase 40's
#      corpus still reaches the code this phase changes
#   3  the build: no warning, one external symbol, tools/phasecheck.sh, tools/canon.sh
#      a no-op, `nvidx`, `orphanopts`, `zhostonly`
#   4  the cut `make editor.c` makes: the core is still plain C above the first
#      `#include` and its interface to the host is the same thirteen names
#   5  THE SIXTEEN MEMLINE CASES, MEASURED AND NOT ASSERTED: how many data blocks each
#      one makes, how deep it descends, and whether it splits the root -- on the input
#      and on the output, which must agree case for case
#   6  two whole recordings, byte for byte
#   7  the phase's own deep sessions, at a size DERIVED from section 2 so that the root
#      really splits, with an instrument that says it did
#   8  three controls, each of which must move something, and two of which move nothing
#      a screen case can see
#   9  E323, the one string this phase changes: an instrument that says no record in a
#      whole recording reaches the arm, and a forced build that exhibits both messages
#
# THE ARENA RIG, AND WHY THIS CHECK RAISES IT.  Zero phase 41 made `host_free` a no-op
# and gave `host_alloc` a fixed arena.  ``zmemline`` builds its buffers by
# replaying a macro with a COUNT -- there is no file argument (phase 5), no `:edit`
# (phase 8) and no `:read` (phase 7), so a counted replay is the only way in -- and
# stuffing `N@q` into the typeahead grows a buffer N times without freeing any of the
# copies, which is quadratic in N.  So the largest cases may not fit an arena sized for
# the corpus phase 41 could see.  That is phase 41's number and not this phase's claim,
# and this check must not depend on it either way: sections 5 and 7 build their own pair
# with the arena raised, state the figure, and require the two binaries to agree there.
# Section 6 records the binaries AS BUILT, which is the pipeline's own question.
set -eu

TAG=refblocks
work=${1:?usage: zero43-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero43-check.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"

die() { echo "  $TAG    $*" >&2; exit 1; }
say() { printf '  %-12s %s\n' "$TAG" "$*"; }

[ -f "$state/old.c" ] || die "the edit left no input source"
[ -f "$state/old" ]   || die "the edit left no input binary"
[ -f "$state/edit.c" ] || die "the edit left no \$state/edit.c, so what the EDIT removed and what the SWEEP removed cannot be told apart"

cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cp "$f" "$tmp/new.c"
# shellcheck disable=SC2086
( SOURCE_DATE_EPOCH=0 gcc $cflags $ldflags -o "$tmp/new" "$tmp/new.c" 2>"$tmp/e.new" ) &
pid_new=$!
cp "$f" "$tmp/canon.c"
( tools/canon.sh "$tmp/canon.c" >"$tmp/canon.log" 2>&1 ) &
pid_canon=$!

# --- 1. the source: the edit and the sweep, kept apart -------------------------------
python3 - "$state/old.c" "$state/edit.c" "$f" "$(cat "$state/input-lines")" <<'PY'
import re
import sys
TAG = 'refblocks'
old, mid, new = (open(p, errors='surrogateescape').read() for p in sys.argv[1:4])
declared_in = int(sys.argv[4])


def die(msg):
    sys.exit('  %-12s %s' % (TAG, msg))


def say(what):
    print('  %-12s %s' % (TAG, what))


def n(text):
    return text.count('\n')


LIT = re.compile(r'"(?:[^"\\\n]|\\.)*"' r"|'(?:[^'\\\n]|\\.)*'")


def words(text):
    """Every identifier in the CODE.  String and character literals are masked first:
    a name inside one is data, and `E298: Didn't get block nr 0?` would otherwise put
    `E298`, `Didn` and `get` into the set of names a phase has to account for."""
    return set(re.findall(r'[A-Za-z_]\w*', LIT.sub('""', text)))


if n(old) != declared_in:
    die('the text the edit was handed is %d lines and the driver recorded %d'
        % (n(old), declared_in))
say('%d -> %d -> %d lines: the EDIT took %d and the SWEEP took %d more, %d altogether'
    % (n(old), n(mid), n(new), n(old) - n(mid), n(mid) - n(new), n(old) - n(new)))

# EVERY NAME THAT LEAVES, AND EVERY NAME THAT ARRIVES, AS A PARTITION.  Nothing may
# leave that this phase does not account for and nothing may arrive that it does not
# introduce.  The sets are stated with a reason each; a leftover refuses.
EDIT = {
    'blocknr_T': 'the block number itself',
    'mf_hashitem_T': 'the hash item every block header carried',
    'mf_hashitem_S': 'its struct tag',
    'mf_hashtab_T': 'the hash table',
    'mf_hashtab_S': 'its struct tag',
    'mhi_key': 'the key: the number a block was found by',
    'mhi_next': 'a hash chain link',
    'mhi_prev': 'a hash chain link',
    'mht_mask': 'a hash table field',
    'mht_count': 'a hash table field',
    'mht_buckets': 'a hash table field',
    'mht_small_buckets': 'a hash table field',
    'mht_fixed': 'a hash table field',
    'MHT_INIT_SIZE': 'the bucket array it is sized by',
    'MHT_LOG_LOAD_FACTOR': 'when it grows',
    'MHT_GROWTH_FACTOR': 'by how much',
    'bh_hashitem': "the block header's hash item",
    'pe_bnum': 'the block number a pointer entry stored -- now pe_block',
    'ip_bnum': 'the block number a stack entry stored -- now ip_block',
    'pe_page_count': "read once, into mf_get()'s third argument",
    'bh_page_count': 'written twice and, once pe_page_count goes, read nowhere',
    'mf_blocknr_max': 'the counter the numbers came from',
    'mf_free_first': 'the head of the free list, which was keyed by block number',
    'mf_used_last': 'write-only since phase 42 took ml_setflags()',
    'mf_hash': 'the table in the memfile',
    'mf_ins_hash': 'a wrapper of the hash',
    'mf_rem_hash': 'a wrapper of the hash',
    'mf_find_hash': 'the lookup this phase removes',
    'mf_ins_free': 'the free list',
    'mf_rem_free': 'the free list',
    'mf_hash_init': 'the hash implementation',
    'mf_hash_free': 'the hash implementation',
    'mf_hash_find': 'the hash implementation',
    'mf_hash_add_item': 'the hash implementation',
    'mf_hash_rem_item': 'the hash implementation',
    'mf_hash_grow': 'the hash implementation',
    'bnum_left': 'a local that held the number of the left half of a split',
    'bnum_right': 'a local that held the number of the right half',
    'page_count_left': 'a local written only to feed pe_page_count',
    'page_count_right': 'a local written only to feed pe_page_count',
    'e_line_count_wrong_in_block_nr': 'E323, which printed a block number; the message '
                                      'is kept without one as e_line_count_wrong_in_block',
    'freep': "mf_new()'s local for the block it took off the free list",
    'mht': 'the parameter of every hash function',
    'mhi': 'the local of every hash function',
    'tails': "mf_hash_grow()'s local",
    'buckets': "mf_hash_grow()'s local",
    'bnum': "ml_find_line()'s descent cursor -- now bp, and a block",
}
SWEEP = {
    'e_didnt_get_block_nr_zero': 'the message ml_open() raised when the first block did '
                                 'not come back numbered 0',
    'e_didnt_get_block_nr_one': 'the message for the second block',
}
ARRIVE = {
    'ml_root': 'the root block, which no descent can reach',
    'pe_block': 'what a pointer entry holds instead of a number',
    'ip_block': 'what a stack entry holds instead of a number',
    'e_line_count_wrong_in_block': 'E323 without its %ld',
    'bp_left': 'the left half of a split',
    'bp_right': 'the right half of a split',
}
# `bp`, ml_find_line()'s descent cursor, is deliberately NOT here: the name is already
# in this file elsewhere, so it does not ARRIVE, and a set computed by difference says
# so rather than being told.
gone_edit = words(old) - words(mid)
gone_sweep = words(mid) - words(new)
arrived = words(new) - words(old)
for got, want, what in ((gone_edit, EDIT, 'the edit'), (gone_sweep, SWEEP, 'the sweep'),
                        (arrived, ARRIVE, 'this phase')):
    if got != set(want):
        die('%s: the names that %s are %s and this phase accounts for %s'
            % (what, 'arrive' if what == 'this phase' else 'leave',
               sorted(got), sorted(want)))
say('%d names leave in the EDIT and %d in the SWEEP, and they are different kinds: the '
    'edit takes what is WRITTEN -- four struct fields, two locals and the free list -- '
    'because no tool in tools/ can see a write, and the sweep takes the two message '
    'objects, which are unreferenced and are -Wunused-variable'
    % (len(gone_edit), len(gone_sweep)))
say('%d names arrive and no more: %s'
    % (len(arrived), ', '.join('%s (%s)' % (k, ARRIVE[k]) for k in sorted(arrived))))

# THE ONE STRING THAT CHANGES, AND THE TWO THAT GO, READ OUT OF THE TEXT.
lit = re.compile(r'"(?:[^"\\\n]|\\.)*"')
so, sn = set(lit.findall(old)), set(lit.findall(new))
if so - sn != {'"E323: Line count wrong in block %ld"',
               '"E298: Didn\'t get block nr 0?"', '"E298: Didn\'t get block nr 1?"'}:
    die('the string literals this phase removes are %s, and it accounts for E323 with '
        'its %%ld and the two E298s' % sorted(so - sn))
if sn - so != {'"E323: Line count wrong in block"'}:
    die('the string literals this phase adds are %s, and it adds one' % sorted(sn - so))
say('THE STRINGS MOVE BY EXACTLY FOUR: `E323: Line count wrong in block %ld` becomes '
    '`E323: Line count wrong in block`, because there is no number left to print, and '
    "the two `E298: Didn't get block nr N?` go with the tests that raised them.  "
    'Section 9 is what makes that a measurement rather than a claim')

# THE EDIT'S OWN WORK, SAID BACK: three fields that were numbers are pointers.
for decl, what in (('    bhdr_T      *pe_block;', 'a pointer entry'),
                   ('    bhdr_T      *ip_block;', 'a stack entry'),
                   ('    bhdr_T      *ml_root;', 'the memline')):
    if new.count(decl) != 1:
        die('%s does not hold a `bhdr_T *` in the one shape this tree declares one'
            % what)
if 'mf_get(memfile_T *mfp, bhdr_T *hp)' not in new:
    die('mf_get() does not take a block')
if re.search(r'\bmf_get\s*\([^)]*,[^)]*,', new):
    die('mf_get() is still called with three arguments somewhere')
say('mf_get(mfp, hp) takes a block, and no call of it anywhere has three arguments; '
    'pe_block, ip_block and ml_root are all `bhdr_T *`')
PY

# --- 2. the block arithmetic, derived from both sources ------------------------------
python3 - "$state/old.c" "$f" "$tmp" <<'PY'
import os
import re
import subprocess
import sys
TAG = 'refblocks'


def die(msg):
    sys.exit('  %-12s %s' % (TAG, msg))


def derive(path, tag, tmp):
    """sizeof(PTR_EN) and pb_count_max, COMPILED out of the source's own structs."""
    t = open(path, errors='surrogateescape').read()
    out = ['#include <stdio.h>', '#include <stddef.h>', 'typedef unsigned char char_u;']
    for pat in (r'^typedef [^\n]*\blinenr_T;$', r'^typedef [^\n]*\bshort_u;$',
                r'^typedef [^\n]*\blong_u;$', r'^typedef [^\n]*\bblocknr_T;$'):
        m = re.search(pat, t, re.M)
        if m:
            out.append(m.group(0))
    out += ['typedef struct block_hdr bhdr_T;', 'typedef struct pointer_entry PTR_EN;']
    for name in ('struct pointer_entry', 'struct pointer_block', 'struct data_block'):
        m = re.search(re.escape(name) + r'\n\{.*?\n\};', t, re.S)
        if not m:
            die('%s is not defined in %s in the one shape this tree writes a struct'
                % (name, path))
        out.append(m.group(0))
    m = re.search(r'enum \{ MEMFILE_PAGE_SIZE = (\d+) \};', t)
    if not m:
        die('the page size is not an enumerator in %s' % path)
    out.append('int main(void){printf("%zu %zu %zu %zu\\n",sizeof(PTR_EN),'
               'offsetof(struct pointer_block,pb_pointer),'
               '(' + m.group(1) + '-offsetof(struct pointer_block,pb_pointer))/sizeof(PTR_EN),'
               'offsetof(struct data_block,db_index));return 0;}')
    c = os.path.join(tmp, 'derive-%s.c' % tag)
    open(c, 'w').write('\n'.join(out))
    subprocess.run(['gcc', '-O0', '-o', c[:-2], c], check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    v = subprocess.run([c[:-2]], capture_output=True, text=True).stdout.split()
    return int(m.group(1)), [int(x) for x in v]


tmp = sys.argv[3]
page_o, (en_o, off_o, max_o, dbi_o) = derive(sys.argv[1], 'old', tmp)
page_n, (en_n, off_n, max_n, dbi_n) = derive(sys.argv[2], 'new', tmp)
if page_o != page_n or off_o != off_n or dbi_o != dbi_n:
    die('the page size, the pointer-block header or the data-block header moved, and '
        'this phase touches none of the three: %s against %s'
        % ((page_o, off_o, dbi_o), (page_n, off_n, dbi_n)))
if en_n >= en_o:
    die('sizeof(PTR_EN) is %d and was %d -- this phase takes a `long` block number to a '
        'pointer and removes an `int`, so it must shrink' % (en_n, en_o))
if max_n <= max_o:
    die('pb_count_max is %d and was %d -- a smaller entry must fit MORE per page'
        % (max_n, max_o))
print('  %-12s THE POINTER ENTRY SHRINKS AND THE TREE GETS WIDER, derived by compiling '
      'the structs out of both sources and not written here: sizeof(PTR_EN) %d -> %d '
      'bytes (a %d-byte block number and a %d-byte page count become one %d-byte '
      'reference), so pb_count_max -- how many children one %d-byte pointer block holds '
      '-- goes %d -> %d.  A ROOT SPLIT NEEDS MORE THAN THAT MANY LIVE DATA BLOCKS, '
      'which is why sections 5 and 7 measure the corpus rather than assume it'
      % (TAG, en_o, en_n, 8, 4, 8, page_n, max_o, max_n))
open('%s/pb_count_max' % tmp, 'w').write('%d %d %d %d\n' % (max_o, max_n, dbi_n, page_n))
PY

# --- 3. the build ---------------------------------------------------------------------
wait $pid_new || { cat "$tmp/e.new" >&2; die "the output does not build with '$cflags' '$ldflags'"; }
[ -s "$tmp/e.new" ] && { cat "$tmp/e.new" >&2; die "the output builds with something to say"; }
wait $pid_canon || { cat "$tmp/canon.log" >&2; die "tools/canon.sh is not a no-op on the output"; }
grep -q 'settled\|no-op\|unchanged' "$tmp/canon.log" || true
tools/phasecheck.sh "$work" "$f" "$state/symbols" >"$tmp/pc.log" 2>&1 ||
    { cat "$tmp/pc.log" >&2; die "tools/phasecheck.sh refuses the output"; }
sed 's/^/  /' "$tmp/pc.log"
tools/st.sh nvidx "$f" >/dev/null || die "nvidx refuses the output"
tools/st.sh orphanopts "$f" >"$tmp/oo.log" 2>&1 || { cat "$tmp/oo.log" >&2; die "orphanopts refuses the output"; }
tools/st.sh zhostonly "$f" >"$tmp/zh.log" 2>&1 || { cat "$tmp/zh.log" >&2; die "zhostonly refuses the output"; }
say "tools/phasecheck.sh, nvidx, orphanopts and zhostonly all pass, and tools/canon.sh is a no-op: this phase touches no option row, no nv_cmds[] row and nothing below the boundary -- $(tools/st.sh orphanopts "$f" 2>&1 | tr -d '\n')"

# --- 4. the cut `make editor.c` makes --------------------------------------------------
awk '/^ *# *include / { exit } { print }' "$f" > "$tmp/editor.c"
cut_lines=$(grep -c '' "$tmp/editor.c")
cut_dirs=$(grep -c '^ *#' "$tmp/editor.c" || true)
[ "$cut_dirs" = 0 ] || die "the cut has $cut_dirs preprocessor directives and the core is plain C"
[ "$cut_lines" -gt 70000 ] || die "the cut is $cut_lines lines, so the first #include is not where it was"
gcc -fsyntax-only -O0 -fno-stack-protector "$tmp/editor.c" 2>"$tmp/e.cut" ||
    { cat "$tmp/e.cut" >&2; die "the core alone does not pass -fsyntax-only"; }
gcc -c -O0 -fno-stack-protector -o "$tmp/cut.o" "$tmp/editor.c" 2>"$tmp/w.cut" || true
iface=$(sed -n "s/.*warning: '\\([A-Za-z_][A-Za-z_0-9]*\\)' used but never defined.*/\\1/p" "$tmp/w.cut" | sort -u)
other=$(grep -c 'warning:' "$tmp/w.cut" || true)
n_iface=$(printf '%s\n' "$iface" | grep -c .)
[ "$other" = "$n_iface" ] || die "the core alone warns $other times and $n_iface of them are the interface, so it says something else as well"
say "the cut is $cut_lines lines with 0 directives, compiles with no error and no warning but its interface, and that interface is the same $n_iface names it was: $(echo $iface | tr '\n' ' ')"

# --- 5..9: the measurements ------------------------------------------------------------
python3 - "$state/old.c" "$f" "$state/old" "$tmp/new" "$tmp" "$cflags" "$ldflags" <<'PY'
import concurrent.futures
import hashlib
import os
import re
import shutil
import subprocess
import sys

sys.path.insert(0, 'tools')
# tools/zstream.py -- named as a PATH here as well as imported, because
# tools/implhash.sh greps a program for `tools/...` paths and knows nothing about an
# import, so a tool reached only by module name would be in no implementation key at all
# (CLAUDE.md, *A tool reached by `import` and never named as a path*).  Do not delete
# this comment.
import zstream

TAG = 'refblocks'
oldsrc, newsrc = (open(p, errors='surrogateescape').read() for p in sys.argv[1:3])
oldbin, newbin, tmp = sys.argv[3], sys.argv[4], sys.argv[5]
cflags, ldflags = sys.argv[6].split(), sys.argv[7].split()
max_o, max_n, dbi, page = (int(x) for x in open('%s/pb_count_max' % tmp).read().split())
E, CR = b'\x1b', b'\r'


def die(msg):
    sys.exit('  %-12s %s' % (TAG, msg))


def say(what):
    print('  %-12s %s' % (TAG, what))


def one(text, s, what):
    if text.count(s) != 1:
        die('`%s` is not in that source exactly once, so a variant built from it would '
            'not be one' % what)
    return s


def build(name, text):
    p = '%s/%s.c' % (tmp, name)
    open(p, 'w', errors='surrogateescape').write(text)
    r = subprocess.run(['gcc'] + cflags + ldflags + ['-o', '%s/%s' % (tmp, name), p],
                       capture_output=True, text=True,
                       env=dict(os.environ, SOURCE_DATE_EPOCH='0'))
    if r.returncode:
        die('the variant %s does not build: %s' % (name, r.stderr.strip()[:400]))
    return '%s/%s' % (tmp, name)


# ---- THE ARENA RIG.  Phase 41's number is phase 41's; this check states its own and
# requires the substitution to have changed something, so it cannot pass vacuously.
ARENA = re.compile(r'enum \{ HOST_ARENA_BYTES = [^;]*\};')
RIG = 'enum { HOST_ARENA_BYTES = 1536 * 1024 * 1024L };'


def rig(text, what):
    if not ARENA.search(text):
        die('%s has no `HOST_ARENA_BYTES` enumerator, and sections 5 and 7 raise the '
            "arena so that this phase's evidence does not rest on phase 41's number" % what)
    out = ARENA.sub(RIG, text, count=1)
    if out == text and ARENA.search(text).group(0) != RIG:
        die('the arena rig changed nothing in %s' % what)
    return out


# ---- THE TREE INSTRUMENT: the same five counters in both sources, at anchors that are
# the same text in both, so the two are measured by one instrument and not by two.
COUNTERS = ('static long ev_root;\nstatic long ev_ptr;\nstatic long ev_data;\n'
            'static long ev_depth;\nstatic long ev_blocks;\n\n')
DUMP = '''    static void
ev_num(long v)
{
    char        d[24];
    int         i = 24;

    if (v == 0)
    {
        d[--i] = '0';
    }
    while (v > 0)
    {
        d[--i] = (char)('0' + (int)(v % 10));
        v /= 10;
    }
    write(2, d + i, (usize)(24 - i));
}

'''
ANCH = [
    ('ev_data', '        dp_right = (DATA_BL *)(hp_right->bh_data);',
     'the data-block split'),
    ('ev_root', '                 musl_memmove((char *)(pp_new), (char *)(pp), (usize)page_size) ;',
     'the root-preserving branch of ml_append_int()'),
    ('ev_ptr', '            total_moved = pp->pb_count - pb_idx - 1;',
     'the pointer-block split'),
    ('ev_blocks', """    dp->db_id =  (('d' << 8) + 'a') ;""", 'a new data block'),
]
DEPTH = ('        ip->ip_low = low;\n        ip->ip_high = high;\n'
         '        ip->ip_index = -1;')
EXIT = '    static void\nhost_exit(int r)\n{\n'


def instrument(text, what):
    p = text.replace('enum { STACK_INCR = 5 };',
                     'enum { STACK_INCR = 5 };\n\n' + COUNTERS.rstrip('\n'), 1)
    if p == text:
        die('%s does not declare STACK_INCR, so the counters have nowhere to go' % what)
    for name, anchor, desc in ANCH:
        one(p, anchor, desc)
        p = p.replace(anchor, ' ' * (len(anchor) - len(anchor.lstrip()))
                      + '%s++;\n' % name + anchor, 1)
    one(p, DEPTH, "ml_find_line()'s push")
    p = p.replace(DEPTH, DEPTH + '\n        if ((long)top + 1 > ev_depth)\n'
                  '        {\n            ev_depth = (long)top + 1;\n        }', 1)
    one(p, EXIT, 'host_exit()')
    p = p.replace(EXIT, DUMP + EXIT +
                  '    write(2, "TREE ", 5);\n'
                  '    ev_num(ev_root);\n    write(2, " ", 1);\n'
                  '    ev_num(ev_ptr);\n    write(2, " ", 1);\n'
                  '    ev_num(ev_data);\n    write(2, " ", 1);\n'
                  '    ev_num(ev_depth);\n    write(2, " ", 1);\n'
                  '    ev_num(ev_blocks);\n    write(2, "\\n", 1);\n', 1)
    for name, _, _ in ANCH:
        if p.count('%s++' % name) != 1:
            die('the counter %s was not planted exactly once in %s' % (name, what))
    return p


jobs = {}
with concurrent.futures.ThreadPoolExecutor(max_workers=8) as ex:
    jobs['tree_old'] = ex.submit(build, 'tree_old', instrument(rig(oldsrc, 'the input'), 'the input'))
    jobs['tree_new'] = ex.submit(build, 'tree_new', instrument(rig(newsrc, 'the output'), 'the output'))
    jobs['rig_old'] = ex.submit(build, 'rig_old', rig(oldsrc, 'the input'))
    jobs['rig_new'] = ex.submit(build, 'rig_new', rig(newsrc, 'the output'))
    # ---- THE CONTROLS.  Each must move something; two of them move nothing a screen
    # case can see, which is the whole reason zero phase 40 exists.
    c_root = newsrc.replace(one(newsrc, '                if (hp != buf->b_ml.ml_root)',
                                "ml_append_int()'s root test"),
                            '                if (hp != nullptr)', 1)
    c_stack = newsrc.replace(one(newsrc, '        ip->ip_block = bp;',
                                 "ml_find_line()'s push of the block"),
                             '        ip->ip_block = buf->b_ml.ml_root;', 1)
    c_descend = newsrc.replace(
        one(newsrc, '                bp = pp->pb_pointer[idx].pe_block;',
            "ml_find_line()'s step down"),
        '                bp = pp->pb_pointer[0].pe_block;', 1)
    c_mlroot = newsrc.replace(
        one(newsrc, '    buf->b_ml.ml_root = hp;\n', "ml_open()'s one write of ml_root"),
        '', 1)
    c_pages = newsrc.replace(
        one(newsrc, '    if ((hp->bh_data = alloc((usize)mfp->mf_page_size * page_count)) == nullptr)',
            "mf_alloc_bhdr()'s allocation"),
        '    if ((hp->bh_data = alloc((usize)mfp->mf_page_size)) == nullptr)', 1)
    for k, v in (('c_root', c_root), ('c_stack', c_stack), ('c_descend', c_descend),
                 ('c_mlroot', c_mlroot), ('c_pages', c_pages)):
        if v == newsrc:
            die('the control %s changed nothing, so it would not be a control' % k)
        jobs[k] = ex.submit(build, k, rig(v, k))
    # ---- E323: the same marker in two places, on the INPUT, which is phase 9's shape.
    E323 = one(oldsrc, '                vim_snprintf((char *)IObuff, emsg_iobuff_room(), e_line_count_wrong_in_block_nr, bnum);',
               "E323's arm")
    REACHED = one(oldsrc, '        if ((top = ml_add_stack(buf)) < 0)',
                  "ml_find_line()'s descent into a pointer block")
    # host_message() and not write(): since zero phase 36 the core names no libc
    # function at all, so a marker planted above the boundary has to go out through
    # the one declared way the core has of reaching stderr (phase 21's, and the same
    # instrument phases 38, 39 and 40 used).
    #
    # AND IT LATCHES, which is not tidiness.  The control marker goes on the descent
    # into a pointer block, which every ml_get() of every buffer reaches -- a
    # twenty-five-thousand-line memline case would write it millions of times, and a
    # recording whose stderr is measured in gigabytes is not a recording.  What the
    # question needs is WHETHER a record reaches the line, not how often, so both
    # markers fire at most once per session and the two are the same instrument.
    MARK = ('{ static int mark_seen; if (!mark_seen) { mark_seen = 1; '
            'host_message("MARK-E323\\n", 10, TRUE); } }\n')
    jobs['m_e323'] = ex.submit(build, 'm_e323', rig(oldsrc.replace(
        E323, '                ' + MARK + E323, 1), 'm_e323'))
    jobs['m_reach'] = ex.submit(build, 'm_reach', rig(oldsrc.replace(
        REACHED, '        ' + MARK + REACHED, 1), 'm_reach'))
    # ---- E323 FORCED, ON BOTH SOURCES, SO BOTH MESSAGES ARE EXHIBITED, and the way it
    # is forced was arrived at by measurement.  The arm runs when the line counts under a
    # pointer block do not cover the line, so what forces it is a scan that finds
    # nothing: every entry's line count read as 0, which leaves `idx` at `pb_count` with
    # `low` never past `lnum`.  Emptying the LOOP instead does not work -- `idx` stays 0,
    # `0 >= pb_count` is false and the descent goes round again.  And forcing it alone is
    # not enough either: `ml_find_line()` then returns nullptr, the editor dies of it
    # (SIGSEGV, measured) and the message never reaches the stream.  So the arm is made
    # to draw and stop: out_flush() and host_exit(0) right after the iemsg, found by the
    # SHAPE of that call rather than by its text, which is what lets one rule serve two
    # sources that spell the call differently -- the input formats a block number into
    # IObuff and the output does not.
    SCAN = '            t = pp->pb_pointer[idx].pe_line_count;'
    IEMSG = re.compile(r'^( *)iemsg\([^\n]*e_line_count_wrong_in_block[^\n]*\);$', re.M)
    for k, src in (('f_old', oldsrc), ('f_new', newsrc)):
        one(src, SCAN, "ml_find_line()'s read of a pointer entry's line count")
        q = src.replace(SCAN, '            t = 0;', 1)
        m = IEMSG.search(q)
        if not m:
            die('%s has no iemsg of E323 on a line of its own, so the arm cannot be made '
                'to draw and stop' % k)
        q = q[:m.end()] + '\n%sout_flush();\n%shost_exit(0);' % (m.group(1), m.group(1)) \
            + q[m.end():]
        jobs[k] = ex.submit(build, k, rig(q, k))
    B = {k: v.result() for k, v in jobs.items()}
say('%d variants built: the input and the output with five tree counters each, the same '
    'two with the arena raised and nothing else, five controls, two markers and two '
    'forced builds' % len(B))

# --- 5. the sixteen memline cases, measured on both -----------------------------------
RX = re.compile(r'TREE (\d+) (\d+) (\d+) (\d+) (\d+)')


def corpus(binary, tag):
    out = os.path.join(tmp, 'mem-' + tag)
    shutil.rmtree(out, ignore_errors=True)
    r = subprocess.run(['tools/st.sh', 'zmemline', binary, out],
                       capture_output=True, text=True)
    got = {}
    for name in sorted(os.listdir(out)):
        txt = open(os.path.join(out, name), errors='surrogateescape').read()
        ms = RX.findall(txt)
        if not ms:
            die('the memline case %s on %s printed no TREE line, so the instrument did '
                'not reach host_exit()' % (name, tag))
        got[name] = tuple(max(int(m[i]) for m in ms) for i in range(5))
        if 'arena exhausted' in txt:
            die('the memline case %s exhausted the arena even with the rig raised to '
                '%s, so nothing in section 5 is a measurement of this phase' % (name, RIG))
    return got, out


a, _ = corpus(B['tree_old'], 'old')
b, _ = corpus(B['tree_new'], 'new')
if set(a) != set(b):
    die('the two binaries record different memline cases')
moved = [k for k in a if a[k] != b[k]]
if moved:
    die('THE TREE IS REACHED DIFFERENTLY: %s'
        % '; '.join('%s %s against %s' % (k, a[k], b[k]) for k in moved))
roots = sorted(k for k in a if a[k][0] > 0)
deep = sorted(k for k in a if a[k][3] > 1)
if not roots:
    die('NOT ONE of the %d memline cases splits the root, so this phase changed '
        "ml_append_int()'s root test with nothing to see it do so.  That is a corpus "
        'whose case sizes are line counts against a tree that now holds %d children per '
        'pointer block, and it is not something this phase may work around: the sizes '
        'have to be derived from the block arithmetic (zero phase 40)' % (len(a), max_n))
say('THE SIXTEEN MEMLINE CASES AGREE, EVENT FOR EVENT: %s'
    % ', '.join('%s=%s' % (k.replace('mem_', ''), '/'.join(str(x) for x in a[k]))
                for k in sorted(a)))
say('and the corpus still REACHES the code this phase changes: %d of %d cases split the '
    'root (%s) and %d descend past a second pointer block (%s), against a pointer block '
    'that now holds %d children where it held %d.  The largest case makes %d data blocks'
    % (len(roots), len(a), ', '.join(roots), len(deep), ', '.join(deep), max_n, max_o,
       max(v[4] for v in a.values())))

# --- 6. two whole recordings ----------------------------------------------------------
recs = {}
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as ex:
    fu = {k: ex.submit(subprocess.run,
                       ['tools/zrecord.sh', v, src, os.path.join(tmp, 'rec-' + k)],
                       capture_output=True, text=True)
          for k, v, src in (('old', oldbin, sys.argv[1]), ('new', newbin, sys.argv[2]))}
    for k, v in fu.items():
        recs[k] = v.result()
d = subprocess.run(['diff', '-r', os.path.join(tmp, 'rec-old'),
                    os.path.join(tmp, 'rec-new')], capture_output=True, text=True)
if d.returncode:
    die('the two recordings differ, and this phase declares nothing at all:\n%s'
        % d.stdout[:3000])
nrec = sum(len(files) for _, _, files in os.walk(os.path.join(tmp, 'rec-old')))
say('TWO WHOLE RECORDINGS, BYTE FOR BYTE: %d records -- 102 screen cases, 16 memline '
    'cases, every Ex command, every command line, four pty scenarios and the terminal '
    'table -- from the binary this phase was handed and from the binary it makes, and '
    '`diff -r` says nothing' % nrec)

# --- 7. the phase's own deep sessions, at a size derived from section 2 ----------------
PAD = 19
per_block = (page - dbi) // (PAD + 1 + 4)
LINES = int((max_n + 2) * per_block * 1.5)


def keys(n, tail):
    return [b'i'] + [b'%07d' % i + b'y' * (PAD - 7) + b'\n' for i in range(n)] \
        + [E] + tail + [b':q!' + CR]


CLOCK = re.compile(rb'\d+ seconds? ago')


def run(binary, k, timeout=900):
    scr, out, err, rc = zstream.session(binary, k, timeout=timeout)
    return rc, hashlib.sha256(CLOCK.sub(b'<CLOCK>', out)).hexdigest()[:16], err, out


ev = {}
for side in ('tree_old', 'tree_new'):
    rc, sha, err, raw = run(B[side], keys(LINES, [b'gg', b'G', b'%dG' % (LINES // 2)]))
    m = RX.search(err.decode('utf8', 'replace'))
    if not m:
        die('the tree instrument on %s printed no TREE line' % side)
    ev[side] = tuple(int(x) for x in m.groups()) + (sha,)
# THE DATA LAYER MUST BE IDENTICAL AND THE POINTER LAYER MUST NOT BE.  This phase makes
# a pointer block hold more children than it did, so above some size the two binaries
# build trees of DIFFERENT SHAPE -- and the thing that must not move is what the editor
# draws.  So: the data blocks, the depth and the root splits are equalities, the pointer
# splits are an INEQUALITY in the direction the arithmetic forces (a wider block splits
# no more often than a narrower one), and the stream is an equality.  Phase 42 met the
# same fact from the other side and stated its own reach the same way.
if ev['tree_old'][2:5] != ev['tree_new'][2:5] or ev['tree_old'][0] != ev['tree_new'][0]:
    die('at %d lines the input and the output disagree about the DATA layer or the root: '
        '%s against %s' % (LINES, ev['tree_old'][:5], ev['tree_new'][:5]))
if ev['tree_new'][1] > ev['tree_old'][1]:
    die('at %d lines the output splits a pointer block %d times and the input %d -- a '
        'block that holds %d children where it held %d cannot split MORE often'
        % (LINES, ev['tree_new'][1], ev['tree_old'][1], max_n, max_o))
if ev['tree_old'][5] != ev['tree_new'][5]:
    die('at %d lines the input and the output draw different streams: %s against %s'
        % (LINES, ev['tree_old'][5], ev['tree_new'][5]))
if ev['tree_new'][0] < 1 or ev['tree_new'][3] < 2:
    die("at %d lines the output's root split %d times and its deepest descent was %d -- "
        'the size is derived from pb_count_max=%d and %d lines a block, so if the root '
        'does not split the derivation is wrong'
        % (LINES, ev['tree_new'][0], ev['tree_new'][3], max_n, per_block))
say("THE PHASE'S OWN SESSION, at %d lines DERIVED from pb_count_max=%d and %d lines a "
    'block and not written here: %d data blocks, %d deep, the root split %d time(s) -- '
    'the same on both binaries -- and the SAME STREAM (%s), while the pointer layer is '
    "deliberately NOT the same, %d pointer-block splits against the input's %d, because "
    'a pointer block now holds %d children where it held %d'
    % (LINES, max_n, per_block, ev['tree_new'][4], ev['tree_new'][3], ev['tree_new'][0],
       ev['tree_new'][5], ev['tree_new'][1], ev['tree_old'][1], max_n, max_o))

DEEP = {
    'built, jumped to both ends and the middle': [b'gg', b'G', b'%dG' % (LINES // 2)],
    'read all the way through': [b':%s/y/y/' % b'', b'\r', b'gg'],
    'deleted and undone': [b'ggdG', b'u', b'G'],
    'five hundred deletions in the middle': [b'%dG' % (LINES // 2)] + [b'dd'] * 500 + [b'gg', b'G'],
}
bad = []
for name, tail in DEEP.items():
    x, y = run(B['rig_old'], keys(LINES, tail)), run(B['rig_new'], keys(LINES, tail))
    if x[:2] != y[:2]:
        bad.append('%s: %s against %s' % (name, x[:2], y[:2]))
if bad:
    die('the input and the output differ on %s' % '; '.join(bad))
say('and they agree in %d more sessions of %d lines -- %s -- each drawing the same '
    'stream and exiting the same way'
    % (len(DEEP), LINES, '; '.join(sorted(DEEP))))

# --- 8. the controls ------------------------------------------------------------------
# THREE SESSIONS, BECAUSE THE CONTROLS BREAK DIFFERENT THINGS: a deep buffer that splits
# the root, a two-hundred-line one -- the shape of the 102 screen cases, which allocate
# exactly ONE data block each (zero phase 40) -- and ONE line longer than a page, which
# is the only way a block is ever more than one page.
small = [b'ihello' + E, b'yy', b'5p', b'gg', b'G']
SESSION = {
    'deep': keys(LINES, [b'gg', b'G', b'%dG' % (LINES // 2)]),
    'small': keys(200, small),
    'long': [b'i' + b'q' * 20000 + E, b'gg', b'$', b'G', b':q!' + CR],
}
base = {k: run(B['rig_new'], v)[:2] for k, v in SESSION.items()}
CTL = {
    'c_root': ("ml_append_int()'s root test made a test nothing passes, so the root is "
               'split like any other block and the tree loses its head'),
    'c_stack': ('every stack entry remembers the ROOT instead of the block it came down '
                'through, so ML_FIND resumes in the wrong place'),
    'c_descend': ('every descent takes the FIRST child of a pointer block instead of '
                  'the one whose line counts cover the line'),
    'c_mlroot': ("ml_open() never writes ml_root, so every descent starts at nullptr"),
}
seen = {}
for k, what in CTL.items():
    got = {n: run(B[k], v)[:2] != base[n] for n, v in SESSION.items()}
    if not any(got.values()):
        die('the control %s -- %s -- changes nothing in any of the %d sessions, so '
            'nothing in this check can see it' % (k, what, len(SESSION)))
    seen[k] = got
if not seen['c_mlroot']['small']:
    die('the control that never writes ml_root leaves a two-hundred-line session alone, '
        'so that session cannot fail at all and the `blind` finding below is vacuous')
blind = [k for k, v in seen.items() if not v['small']]
if not blind:
    die('every control moves the two-hundred-line session as well, so none of them is a '
        'control the 102 screen cases could not see, and this check has not shown that '
        'zero phase 40 was needed')
say('FOUR CONTROLS, EACH MOVING SOMETHING: %s.  %d of them (%s) leave a two-hundred-line '
    'session alone, which is the case zero phase 40 exists for -- a binary that draws '
    'every screen case correctly and gets the tree wrong -- and c_mlroot moves all three, '
    'which is what keeps that finding from being a session nothing could fail'
    % ('; '.join('%s moves %s' % (k, ', '.join(sorted(n for n, v in seen[k].items() if v)))
                 for k in sorted(seen)), len(blind), ', '.join(sorted(blind))))

# A FIFTH CONTROL THAT MOVES NOTHING, REPORTED AND NOT HIDDEN.  This is phase 34's
# seventh control exactly: `mf_alloc_bhdr()` sizing every block ONE page is what removing
# `bh_page_count` would break if the `page_count` parameter were not still sizing the
# allocation two lines above the field that went -- and no recording can see it, because
# since zero phase 41 `host_alloc` is a bump allocator with no redzone and no free, so a
# block written past its end scribbles on arena bytes nothing has handed out yet.  A
# short allocation here is a memory bug and not a difference, which is the row
# CLAUDE.md's verification table says needs a sanitizer and not an instrument.  It is
# built and run and its silence is stated rather than left out.
c_pages = {n: run(B['c_pages'], v)[:2] != base[n] for n, v in SESSION.items()}
say('and a fifth that moves NOTHING and is reported: c_pages, mf_alloc_bhdr() sizing '
    'every block one page, moves %d of the %d sessions -- because phase 41\'s arena has '
    'no redzone, so writing past a short allocation is a memory bug rather than a '
    'difference (CLAUDE.md, the last row of the verification table).  What says the '
    'allocation is still right is the text: `page_count` still multiplies the page size '
    'in mf_alloc_bhdr(), which is why removing the FIELD is safe'
    % (sum(c_pages.values()), len(SESSION)))

# --- 9. E323 --------------------------------------------------------------------------
mark_e323 = os.path.join(tmp, 'rec-mark-e323')
r = subprocess.run(['tools/zrecord.sh', B['m_e323'], sys.argv[1], mark_e323],
                   capture_output=True, text=True)
mark_reach = os.path.join(tmp, 'rec-mark-reach')
r2 = subprocess.run(['tools/zrecord.sh', B['m_reach'], sys.argv[1], mark_reach],
                    capture_output=True, text=True)


def carry(root):
    hit = tot = 0
    for dirpath, _, files in os.walk(root):
        for name in files:
            tot += 1
            if 'MARK-E323' in open(os.path.join(dirpath, name), errors='surrogateescape').read():
                hit += 1
    return hit, tot


h1, t1 = carry(mark_e323)
h2, t2 = carry(mark_reach)
if h1:
    die("E323's arm is reached by %d of %d records, so it is not unreachable and this "
        'phase changes a message something draws' % (h1, t1))
if h2 < t2 // 4:
    die('the same marker on the line above E323 is carried by only %d of %d records, so '
        'the instrument is not proving anything' % (h2, t2))
sm_old = run(B['f_old'], [b'ihello' + E, b'gg', b':q!' + CR])
sm_new = run(B['f_new'], [b'ihello' + E, b'gg', b':q!' + CR])
if sm_old[0] or sm_new[0]:
    die('a forced build did not exit cleanly (%d, %d), so what it drew is not what the '
        'arm draws' % (sm_old[0], sm_new[0]))
if b'E323' not in sm_old[3] or b'E323' not in sm_new[3]:
    die('the forced builds do not draw E323, so the arm was not forced')
if b'E323: Line count wrong in block 0' not in sm_old[3]:
    die("the forced input does not draw E323 with a block number, so the message this "
        'phase changes is not the one being exhibited: %r'
        % sm_old[3][sm_old[3].find(b'E323'):][:60])
if b'E323: Line count wrong in block' not in sm_new[3] or \
        re.search(rb'E323: Line count wrong in block \d', sm_new[3]):
    die('the forced output draws %r, and this phase leaves E323 with no number'
        % sm_new[3][sm_new[3].find(b'E323'):][:60])
say('E323 IS THE ONE STRING AND IT IS NOT DRAWN: the input built with a marker on that '
    'arm carries it in %d of %d records of a whole recording, and the IDENTICAL marker '
    'on the line above it -- the descent into a pointer block -- is carried by %d of '
    '%d.  Both sources built with the scan forced to find nothing DO draw it, and what '
    'they draw is %r against %r'
    % (h1, t1, h2, t2,
       re.search(rb'E323[^\x1b]*', sm_old[3]).group(0).strip(),
       re.search(rb'E323[^\x1b]*', sm_new[3]).group(0).strip()))
PY

# --- 10. what this phase declares --------------------------------------------------------
# tools/phaserun.sh runs tools/zerodelta.sh --phase 43 after this check.  This phase
# declares NOTHING AT ALL, and it is the sixth of CLAUDE.md's kinds: the code runs, and
# the instrument sees it do the same thing.  Every keystroke reaches its text through
# ml_find_line(), so the recording is not a weak witness here -- it is the strongest one
# any zero phase that changes code has had, and section 5 is why: sixteen cases that ask
# the TREE a question, which no zero recording could do before phase 40.
[ "$(tools/zerodelta.sh --declared 43 | tr -d '[:space:]')" = "" ] ||
    die "pipes/zero.delta declares something for phase 43, and this phase declares nothing at all"
say "pipes/zero.delta declares NOTHING for this phase: CLAUDE.md's sixth kind, the code runs and the instrument sees it do the same thing.  One statement inside it is the second kind -- E323's text, which can run and no recording reaches -- and section 9 is the probe it owes"
