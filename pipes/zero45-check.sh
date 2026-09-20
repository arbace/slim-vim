#!/bin/sh
# Zero phase 45's check -- fold the node types.
#
# Usage: pipes/zero45-check.sh <work-dir> <state-dir>   (run from the repository root)
#
# THE DECLARED DELTA IS NOTHING AT ALL AND IT IS ZERO PHASES 14, 15 AND 44'S WEAKEST
# KIND.  The code changes, the binary moves, and the claim is that a replacement does
# what the thing it replaces did.  There is no `cmp` to be had: every block in the
# editor is allocated differently, reached differently and tagged differently.  So the
# recordings are the floor and not the evidence, and what carries the phase is twelve
# builds of its own output with one thing changed -- nine that MUST move a recording
# and three that are MEASURED not to, each of the three with the reason written beside
# it and, for the one that matters most, a second measurement that shows what it DID
# move.
#
# WHAT IS CHECKED, in the order it is cheapest to fail:
#
#   1  the product builds from a tree the clean really emptied
#   2  THE PARTITION, and it is a partition over the file's WHOLE VOCABULARY: exactly
#      29 identifiers leave and exactly 5 arrive, string literals excluded, and each
#      side is accounted for name by name -- 25 the edit takes, 2 the sweep takes, 2
#      that go with a function this phase deletes, and the five the fold writes
#   3  the representation, read out of the output, and SIZEOF(PTR_EN) == 16 COMPILED
#      AGAINST BOTH CUTS -- the input's and the output's -- because the tree's fanout
#      is computed from it and the corpus's root-split coverage rests on the fanout
#   4  one allocation per node, at its own size, stated as a partition over every
#      allocation the memline makes
#   5  two full recordings, byte for byte the input's, and identical to each other
#   6  the corpus REACHES the tree exactly as it did, marker by marker and case by case
#   7  what the node costs the arena, measured on both sides
#   8  the controls
#   9  ZERO PHASE 44'S PREDICTION, MEASURED: its own capacity control, built from this
#      phase's input and from its output in the same run
#  10  nm -u unchanged both ways, the cut, and the ordinary phase checks
#
# WHY SECTION 3 COMPILES SOMETHING RATHER THAN READING IT.  `pb_count_max` was
# `(page - offsetof(PTR_BL, pb_pointer)) / sizeof(PTR_EN)` and is now the enumerator
# PB_COUNT_MAX; the two agree at 255 only because `PTR_EN` is still 16 bytes.  At 8 the
# fanout would be 511, `mem_deep_jumps`'s 391 data blocks would fall under it, and the
# ONE case of sixteen that reaches a root split would stop reaching it -- while every
# recording still matched and every check still passed.  That is the defect zero phase
# 40 exists to have ended, so it is asserted in the source, compiled on both sides, and
# then MEASURED in section 6 and demonstrated by a control in section 8.
set -eu

work=${1:?usage: zero45-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero45-check.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"
before_lines=$(cat "$state/input-lines")

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# THE PRODUCT, REBUILT, and the clean is checked rather than trusted: the work tree
# still holds the binary tools/restore.sh unpacked with the previous boundary, and a
# recording of THAT would be a recording of the phase's input.
make -C "$work" clean >/dev/null 2>&1 || true
[ -e "$work/zero-vim" ] && { echo "  build        the clean did not remove zero-vim, so nothing below would be a recording of this phase"; exit 1; }
if ! make -C "$work" >/dev/null 2>&1; then
    echo "  build        FAILED -- rerun by hand: make -C $work"
    exit 1
fi
new="$work/zero-vim"
old="$state/old"

# --- 2, 3 and 4: the source, before anything is run ------------------------------
python3 - "$f" "$state/old.c" "$state/gone" "$state/forsweep" "$state/fanout" <<'PY'
import re
import sys

new = open(sys.argv[1], errors='surrogateescape').read()
old = open(sys.argv[2], errors='surrogateescape').read()
gone = [l.rstrip('\n').rsplit('\t', 1) for l in open(sys.argv[3]) if l.strip()]
forsweep = [l.strip() for l in open(sys.argv[4]) if l.strip()]
fanout = int(open(sys.argv[5]).read())

# Two names go with a function this phase deletes and are named here rather than in the
# edit, because the edit removes them by removing what holds them: mf_close()'s own
# local, and the label ml_find_line() stops needing once no block can fail to be got.
WITHTHEIROWNER = ('nextp', 'error_noblock')
# What the fold writes.  Five, and no more: a phase that had to invent a sixth name to
# say what a node is would be a phase that had not folded anything.
WRITTEN = ('PB_COUNT_MAX', 'bh_id', 'pb_hdr', 'db_hdr', 'ml_free_tree')


def die(tag, msg):
    sys.exit('  %-12s %s' % (tag, msg))


def w(t, n):
    return len(re.findall(r'\b%s\b' % re.escape(n), t))


def code(t):
    """T with every string and character literal blanked.

    zero-vim.c has no comments and no preprocessor, so this is exact: a name inside
    "E293: Block was not locked" is data, and a partition that counted it would report
    three words leaving that no code ever named.
    """
    out = []
    i, n = 0, len(t)
    while i < n:
        c = t[i]
        if c in '"\'':
            q = c
            out.append(' ')
            i += 1
            while i < n and t[i] != q:
                i += 2 if t[i] == '\\' else 1
            i += 1
            continue
        out.append(c)
        i += 1
    return ''.join(out)


# --- 2. THE PARTITION, over the whole vocabulary ---------------------------------
oldn = set(re.findall(r'\b[A-Za-z_][A-Za-z0-9_]*\b', code(old)))
newn = set(re.findall(r'\b[A-Za-z_][A-Za-z0-9_]*\b', code(new)))
left, came = oldn - newn, newn - oldn
want_left = set(n for n, _ in gone) | set(forsweep) | set(WITHTHEIROWNER)
if left != want_left:
    die('partition', 'the names that leave are %s and this phase accounts for %s'
        % (sorted(left), sorted(want_left)))
if came != set(WRITTEN):
    die('partition', 'the names that arrive are %s and this phase writes %s'
        % (sorted(came), sorted(WRITTEN)))
# The input's counts are the edit's measurement of the input, re-read here off the
# INPUT rather than trusted: a number written into this file would be a fact about a
# boundary that was, not about the one that arrives.
for name, n in gone:
    if w(old, name) != int(n):
        die('partition', 'the edit recorded %s at %s mentions of the input and it has %d'
            % (name, n, w(old, name)))
print('  %-12s the file\'s whole vocabulary moves by %d names out and %d in: %s -- %d '
      'mentions -- the edit\'s; %s the sweep\'s; %s with the function that held them; '
      'and %s written'
      % ('partition', len(left), len(came), ', '.join(n for n, _ in gone),
         sum(int(c) for _, c in gone), ', '.join(forsweep),
         ', '.join(WITHTHEIROWNER), ', '.join(WRITTEN)))

# --- the division between the edit and the sweep, stated -------------------------
# BH_LOCKED is an enumerator nothing mentions and e_block_was_not_locked is the E293
# mf_put() raised; deadenums.py and deadsweep.py take one each, and they are the whole
# of what the sweep finds in this phase.  The edit left each at exactly one mention.
for name in forsweep:
    if w(old, name) < 2:
        die('division', '%s has %d mentions in the input, so leaving it for the sweep '
            'would not be leaving anything' % (name, w(old, name)))
print('  %-12s the edit takes the %d names above, every one of which is reachable code '
      'no sweep could see, and leaves %s at one mention each -- their own definitions -- '
      'which is the whole of what the sweep finds'
      % ('division', len(gone), ' and '.join(forsweep)))


# --- 3. the representation -------------------------------------------------------
def struct(t, name, tag='record'):
    m = re.search(r'^struct %s\n\{\n(.*?)^\};$' % name, t, re.M | re.S)
    if not m:
        die(tag, 'struct %s is not in the output' % name)
    return [l.strip() for l in m.group(1).split('\n') if l.strip()]


hdr = struct(new, 'block_hdr')
ptr = struct(new, 'pointer_block')
dat = struct(new, 'data_block')
if [x.split()[-1] for x in hdr] != ['bh_id;']:
    die('record', 'struct block_hdr is not the node\'s one-member tag: ' + ' '.join(hdr))
if [x.split()[-1] for x in ptr] != ['pb_hdr;', 'pb_count;', 'pb_pointer[PB_COUNT_MAX];']:
    die('record', 'struct pointer_block is not a tag, a count and a fixed array of '
        'entries: ' + ' '.join(ptr))
if [x.split()[-1] for x in dat] != ['db_hdr;', 'db_line_count;', 'db_line[DB_LINE_MAX];']:
    die('record', 'struct data_block is not a tag, a count and a fixed array of '
        'records: ' + ' '.join(dat))
if not ptr[0].startswith('bhdr_T') or not dat[0].startswith('bhdr_T'):
    die('record', 'the tag is not the FIRST member of both node types, so (PTR_BL *)hp '
        'and (bhdr_T *)pp would not be the same address')
if re.search(r'\bmemfile\b', code(new)) or re.search(r'\bmemfile\b', code(old)) is None:
    die('record', 'there is still a memfile in the output, or there was none in the input')
if not re.search(r'enum \{ PB_COUNT_MAX = %d \};' % fanout, new):
    die('record', 'PB_COUNT_MAX is not the %d the edit fixed it at' % fanout)
print('  %-12s a node is `{%s}` and then either `{%s}` or `{%s}`, the tag first in '
      'both, and there is no memfile in the file at all'
      % ('record', ' '.join(hdr), ' '.join(ptr[1:]), ' '.join(dat[1:])))

# --- 4. ONE allocation per node, at its own size ---------------------------------
# Stated as a partition over the two constructors: each makes exactly one allocation,
# for the size of its own struct, and clears it.  The input made FOUR -- a bhdr_T and a
# page of mf_page_size for each of the two kinds -- and the page was 4,096 bytes
# whichever kind asked for it.
def body(t, head):
    m = re.search(r'^%s\n\{\n(.*?)^\}$' % re.escape(head), t, re.M | re.S)
    if not m:
        die('alloc', '%s is not in the output to be read' % head)
    return m.group(1)


for head, want in (('ml_new_data(void)', 'DATA_BL'), ('ml_new_ptr(void)', 'PTR_BL')):
    b = body(new, head)
    got = re.findall(r'\b(alloc\w*)\(sizeof\((\w+)\)\)', b)
    if got != [('alloc_clear', want)]:
        die('alloc', '%s allocates %s, and a node is ONE alloc_clear of sizeof(%s)'
            % (head, got, want))
    if len(re.findall(r'\balloc\w*\(', b)) != 1:
        die('alloc', '%s asks for memory more than once' % head)
for head in ('ml_new_data(memfile_T *mfp)', 'ml_new_ptr(memfile_T *mfp)'):
    if re.search(r'^%s$' % re.escape(head), old, re.M) is None:
        die('alloc', 'the input\'s %s is not where this check reads it' % head)
ab = body(old, 'mf_alloc_bhdr(memfile_T *mfp, int page_count)')
if len(re.findall(r'\balloc\w*\(', ab)) != 2 or 'mf_page_size' not in ab:
    die('alloc', 'the input does not make TWO allocations per node, a header and a page '
        'of mf_page_size')
print('  %-12s each constructor makes ONE allocation, alloc_clear(sizeof(DATA_BL)) and '
      'alloc_clear(sizeof(PTR_BL)): where the input allocated a bhdr_T AND a page of '
      'mf_page_size for each of the two kinds, four allocations of 4,128 bytes between '
      'them where there are now two of 1,040 and 4,088' % 'alloc')
PY

# --- 3b. sizeof(PTR_EN) == 16, COMPILED, on both cuts ----------------------------
# The cut is `make editor.c`: the lines above the first #include, which is the boundary
# between the core and the host (zero phase 27).  Asserting on the CUT and not on the
# whole file is what makes this a statement about the editor rather than about a
# header, and it is the strongest place to put it: the cut has no preprocessor in it at
# all, so `static_assert` is reading the core's own type and nothing else's.
cutof() { awk '/^ *# *include / { exit } { a[NR] = $0; if (NF) last = NR } END { for (i = 1; i <= last; i++) print a[i] }' "$1" > "$2"; }
cutof "$f" "$tmp/cut.c"
cutof "$state/old.c" "$tmp/cut.old.c"
for side in new old; do
    src=$tmp/cut.c
    [ "$side" = old ] && src=$tmp/cut.old.c
    cp "$src" "$tmp/en.$side.c"
    printf 'static_assert(sizeof(PTR_EN) == 16, "the tree fanout is computed from this");\n' >> "$tmp/en.$side.c"
    if ! gcc -fsyntax-only "$tmp/en.$side.c" 2>"$tmp/en.$side.err"; then
        echo "  fanout       sizeof(PTR_EN) is NOT 16 on the $side side, so the tree's fanout has moved and zero phase 40's root-split coverage is not what it was:"
        sed 's/^/               /' "$tmp/en.$side.err" | head -3
        exit 1
    fi
    cp "$src" "$tmp/bad.$side.c"
    printf 'static_assert(sizeof(PTR_EN) == 8, "the control");\n' >> "$tmp/bad.$side.c"
    if gcc -fsyntax-only "$tmp/bad.$side.c" 2>/dev/null; then
        echo "  fanout       the $side cut accepts sizeof(PTR_EN) == 8 as well as == 16, so the assertion above is not an assertion"
        exit 1
    fi
done
echo "  fanout       sizeof(PTR_EN) == 16 compiles against BOTH cuts and == 8 compiles against neither, so the entry is the width it was and PB_COUNT_MAX is (4096 - 8) / 16 = 255 either side"

# --- 5. two full recordings, and they are the input's ----------------------------
tools/zrecord.sh "$new" "$f" "$tmp/rec1" >/dev/null
tools/zrecord.sh "$new" "$f" "$tmp/rec2" >/dev/null
tools/zrecord.sh "$old" "$state/old.c" "$tmp/rec0" >/dev/null
if ! diff -rq "$tmp/rec1" "$tmp/rec2" >/dev/null; then
    echo "  record       two recordings of the same binary differ, so nothing below is evidence"
    diff -rq "$tmp/rec1" "$tmp/rec2" | head -3 | sed 's/^/               /'
    exit 1
fi
if ! diff -rq "$tmp/rec0" "$tmp/rec1" >/dev/null; then
    echo "  record       the output does not record what the input records:"
    diff -rq "$tmp/rec0" "$tmp/rec1" | head -5 | sed 's/^/               /'
    exit 1
fi
echo "  record       $(ls "$tmp/rec1/screen" | wc -l) screen cases, $(ls "$tmp/rec1/memline" | wc -l) memline cases and four tables, byte for byte the input's, twice"

# --- 6. the corpus reaches the tree, measured on both sides ----------------------
# Zero phase 40's five markers, each a once-per-process host_message() -- the core's own
# declared way to stderr, phase 21's, which adds no name the file does not already have.
# Three of the five anchors are lines THIS PHASE REWROTE, so each side names its own.
MARK_PY='
import re
import sys

OUT = len(sys.argv) > 3 and sys.argv[3] == "new"
MARKS = [
    ("MLSPLITDATA",
     (r"^        if \(\(hp_new = ml_new_data\(\)\) == nullptr\)$" if OUT
      else r"^        if \(\(hp_new = ml_new_data\(mfp\)\) == nullptr\)$"), "before", None),
    ("MLSPLITPTR",
     (r"^                hp_new = ml_new_ptr\(\);$" if OUT
      else r"^                hp_new = ml_new_ptr\(mfp\);$"), "before", None),
    ("MLSPLITROOT",
     (r"^                pp_new->pb_count = pp->pb_count;$" if OUT
      else r"^ *musl_memmove\(\(char \*\)\(pp_new\), \(char \*\)\(pp\), \(usize\)page_size\) ;$"),
     "before", None),
    ("MLIDXNZ",     r"^                ip->ip_index = idx;$",              "after",  "idx > 0"),
    ("MLDEEP",      r"^        if \(\(top = ml_add_stack\(buf\)\) < 0\)$", "before",
     "++zprobe_lvl >= 2"),
]
t = open(sys.argv[1], errors="surrogateescape").read()
# The depth counter is declared where ml_find_line() starts its descent -- the low end
# of the range, which this phase does not touch.  (No apostrophe below: MARK_PY is a
# single-quoted shell string.)
decl = re.compile(r"^    low = 1;$", re.M)
if len(decl.findall(t)) != 1:
    sys.exit("the probe cannot declare its depth counter: the file has %d `low = 1;`"
             % len(decl.findall(t)))
t = decl.sub("    int zprobe_lvl = 0;\n    low = 1;", t, 1)
for name, pat, where, cond in MARKS:
    hits = list(re.finditer(pat, t, re.M))
    if len(hits) != 1:
        sys.exit("the anchor for %s is in the source %d times, expected 1" % (name, len(hits)))
    m = hits[0]
    body = ("{ static int z_%s = 0; if (!z_%s) { z_%s = 1; "
            "host_message(\"%s\\n\", -1, TRUE); } }" % (name, name, name, name))
    ins = ("        if (%s) %s\n" % (cond, body)) if cond else ("        " + body + "\n")
    t = t[:m.start()] + (ins + t[m.start():]) if where == "before" \
        else t[:m.end() + 1] + ins + t[m.end() + 1:]
open(sys.argv[2], "w", errors="surrogateescape").write(t)
print(" ".join(m[0] for m in MARKS))
'
mkdir -p "$tmp/pnew" "$tmp/pold"
cp "$work/Makefile" "$tmp/pnew/Makefile"
cp "$work/Makefile" "$tmp/pold/Makefile"
if ! marks_new=$(python3 -c "$MARK_PY" "$f" "$tmp/pnew/zero-vim.c" new 2>&1); then
    echo "  probe        the instrument could not be built from this phase's output:"
    printf '%s\n' "$marks_new" | sed 's/^/               /'
    exit 1
fi
if ! marks_old=$(python3 -c "$MARK_PY" "$state/old.c" "$tmp/pold/zero-vim.c" 2>&1); then
    echo "  probe        the instrument could not be built from this phase's input:"
    printf '%s\n' "$marks_old" | sed 's/^/               /'
    exit 1
fi
( make -C "$tmp/pnew" >/dev/null 2>&1 ) &
pn=$!
( make -C "$tmp/pold" >/dev/null 2>&1 ) &
po=$!
wait $pn || { echo "  probe        the instrumented output did not build"; exit 1; }
wait $po || { echo "  probe        the instrumented input did not build"; exit 1; }
tools/st.sh zmemline "$tmp/pnew/zero-vim" "$tmp/pnew-mem" >/dev/null &
mn=$!
tools/st.sh zmemline "$tmp/pold/zero-vim" "$tmp/pold-mem" >/dev/null &
mo=$!
tools/st.sh zcases "$tmp/pnew/zero-vim" "$tmp/pnew-scr" >/dev/null &
sn=$!
wait $mn; wait $mo; wait $sn
if ! python3 - "$tmp/pnew-mem" "$tmp/pold-mem" "$tmp/pnew-scr" "$marks_new" "$marks_old" <<'PY'
"""The output reaches what the input reached, CASE BY CASE and not only in total."""
import os
import sys

nm, om, ns = sys.argv[1], sys.argv[2], sys.argv[3]
mnew, mold = sys.argv[4].split(), sys.argv[5].split()


def per(d, marks):
    out = {}
    for n in sorted(os.listdir(d)):
        t = open(os.path.join(d, n), errors='replace').read()
        out[n] = set(m for m in marks if m in t)
    return out


new, old, scr = per(nm, mnew), per(om, mold), per(ns, mnew)
if sorted(new) != sorted(old):
    sys.exit('the two sides did not record the same cases')
moved = [n for n in new if new[n] != old[n]]
if moved:
    sys.exit('%s reach a different part of the tree than they did: %s'
             % (' '.join(moved),
                '; '.join('%s %s against %s' % (n, sorted(new[n]), sorted(old[n]))
                          for n in moved[:3])))
tot = {m: sum(1 for n in new if m in new[n]) for m in mnew}
if any(v == 0 for v in tot.values()):
    sys.exit('the corpus reaches none of: %s -- a corpus that MEANS to reach a split '
             'and does not is the defect zero phase 40 exists to end'
             % ' '.join(k for k, v in tot.items() if v == 0))
if any(scr.values()):
    sys.exit('%s is reached by the 102 screen cases, so the memline corpus is not what '
             'makes the text layer visible on this boundary'
             % ' '.join(sorted(set().union(*scr.values()))))
root = [n for n in new if 'MLSPLITROOT' in new[n]]
print('  %-12s %s -- the same markers in the same cases as the input, case by case; '
      'the ROOT SPLIT is reached by %d of %d, %s, and 0 of the 102 screen cases reach '
      'any of them'
      % ('probe', '  '.join('%s %d' % (m, tot[m]) for m in mnew),
         len(root), len(new), ' '.join(sorted(root))))
PY
then
    exit 1
fi

# --- 7. what a node costs the arena ----------------------------------------------
# A node was a 32-byte header and a 4,096-byte page, two allocations, for a leaf and a
# branch alike; it is one allocation of 1,040 or 4,088.  The recording cannot see that
# -- it is the same screens either way -- so it is measured, on both sides, with zero
# phase 44's own counter.
ARENA_PY='
import re
import sys
t = open(sys.argv[1], errors="surrogateescape").read()
EDITS = [
    (r"^static int host_code;$", "static long z_arena;\nstatic int host_code;"),
    (r"^host_alloc\(usize n\)\n\{$",
     "host_alloc(usize n)\n{\n    z_arena += (long)((n + 15) & ~(usize)15);"),
    (r"^    host_code = r;$",
     "    host_code = r;\n"
     "    { char b[48]; char d[24]; int i = 0; int k = 0; long v = z_arena;\n"
     "      b[i++] = 90; b[i++] = 65; b[i++] = 61;\n"
     "      if (v == 0) { d[k++] = 48; }\n"
     "      while (v > 0) { d[k++] = (char)(48 + (v % 10)); v /= 10; }\n"
     "      while (k > 0) { b[i++] = d[--k]; }\n"
     "      b[i++] = 10; host_message(b, i, TRUE); }"),
]
for pat, rep in EDITS:
    hits = list(re.finditer(pat, t, re.M))
    if len(hits) != 1:
        sys.exit("the arena counter anchor %r is in the source %d times, expected 1"
                 % (pat, len(hits)))
    t = t[:hits[0].start()] + rep + t[hits[0].end():]
open(sys.argv[2], "w", errors="surrogateescape").write(t)
'
mkdir -p "$tmp/anew" "$tmp/aold"
cp "$work/Makefile" "$tmp/anew/Makefile"
cp "$work/Makefile" "$tmp/aold/Makefile"
if ! out=$(python3 -c "$ARENA_PY" "$f" "$tmp/anew/zero-vim.c" 2>&1) \
        || ! out=$(python3 -c "$ARENA_PY" "$state/old.c" "$tmp/aold/zero-vim.c" 2>&1); then
    echo "  arena        the counter could not be built:"
    printf '%s\n' "$out" | sed 's/^/               /'
    exit 1
fi
( make -C "$tmp/anew" >/dev/null 2>&1 ) &
an=$!
( make -C "$tmp/aold" >/dev/null 2>&1 ) &
ao=$!
wait $an || { echo "  arena        the instrumented output did not build"; exit 1; }
wait $ao || { echo "  arena        the instrumented input did not build"; exit 1; }
tools/st.sh zmemline "$tmp/anew/zero-vim" "$tmp/anew-mem" >/dev/null &
an=$!
tools/st.sh zmemline "$tmp/aold/zero-vim" "$tmp/aold-mem" >/dev/null &
ao=$!
wait $an; wait $ao
if ! python3 - "$tmp/anew-mem" "$tmp/aold-mem" <<'PY'
"""Every memline session's allocation traffic, this phase's output against its input."""
import os
import re
import sys


def per(d):
    out = {}
    for n in sorted(os.listdir(d)):
        t = open(os.path.join(d, n), errors='replace').read()
        v = [int(m.group(1)) for m in re.finditer(r'ZA=(\d+)', t)]
        out[n] = max(v) if v else 0
    return out


new, old = per(sys.argv[1]), per(sys.argv[2])
if sorted(new) != sorted(old) or not new or min(old.values()) == 0:
    sys.exit('  %-12s the counter recorded nothing, so this section would be vacuous'
             % 'arena')
# A node stops being a header plus a page, so EVERY session must ask for less.  This is
# a direction and not a bound: a phase that made the editor allocate more while the
# screens stayed the same would be a phase whose whole claim had failed.
worse = [n for n in new if new[n] >= old[n]]
if worse:
    sys.exit('  %-12s %s ask the host for at least as much as the input did (%s), and '
             'one allocation of 1,040 bytes where there were two of 32 and 4,096 must '
             'cost less in every session'
             % ('arena', ' '.join(worse[:3]),
                ' '.join('%d/%d' % (new[n], old[n]) for n in worse[:3])))
pn = max(new, key=lambda k: new[k])
print('  %-12s all %d memline sessions ask the host for LESS than the input: the '
      'heaviest, %s, asks %d bytes where it asked %d, %+.1f%%, and the biggest fall is '
      '%s at %+.1f%%; nothing is freed, so that is a session\'s TRAFFIC and not its '
      'live data'
      % ('arena', len(new), pn, new[pn], old[pn], 100.0 * (new[pn] - old[pn]) / old[pn],
         min(new, key=lambda k: new[k] / old[k]),
         100.0 * min((new[k] - old[k]) / old[k] for k in new)))
PY
then
    exit 1
fi

# --- 8. the controls -------------------------------------------------------------
# Twelve builds of this phase's own output with ONE thing changed.  Nine must move a
# recording; three must not, and each of those three is a measured statement about what
# the corpus cannot see rather than a control that failed.
CTL_PY='
import os
import re
import sys

MUST = {
  "newdata_tag": (r"^(    dp->db_hdr\.bh_id = )(.*);$", None),
  "newptr_tag":  (r"^(    pp->pb_hdr\.bh_id = )(.*);$", None),
  "leaftest":    (r"^        if \(hp->bh_id ==  \(\(.d. << 8\) \+ .a.\) \)$", None),
  "rootcount":   (r"^                pp_new->pb_count = pp->pb_count;\n", ""),
  "rootcopy":    (r"^ *musl_memmove\(\(char \*\)\(&pp_new->pb_pointer\[0\]\), "
                  r"\(char \*\)\(&pp->pb_pointer\[0\]\)[^\n]*\n", ""),
  "ptrcap":      (r"if \(pp->pb_count < PB_COUNT_MAX\)", None),
  "ptrsize":     (r"^    pp =  \(PTR_BL \*\)alloc_clear\(sizeof\(PTR_BL\)\) ;$",
                  "    pp =  (PTR_BL *)alloc_clear(sizeof(DATA_BL)) ;"),
  "datasize":    (r"^    dp =  \(DATA_BL \*\)alloc_clear\(sizeof\(DATA_BL\)\) ;$",
                  "    dp =  (DATA_BL *)alloc_clear(sizeof(DATA_BL) / 2) ;"),
  "leafcap":     (r"^    if \(dp->db_line_count < DB_LINE_MAX\)$", None),
}
BLIND = {
  "fanout":  (r"^enum \{ PB_COUNT_MAX = (\d+) \};$", None),
  "noclear": (r"alloc_clear\(sizeof\(DATA_BL\)\)", "alloc(sizeof(DATA_BL))"),
  "nofree":  (r"^    vim_free\(hp\);\n", ""),
}
REWRITE = {
  # A node whose tag is neither of the two constants: the tag is CARRIED out of the
  # line and one is added to it, so this file spells no character literal -- CTL_PY is
  # a single-quoted shell string and an apostrophe would end it.
  "newdata_tag": lambda s: re.sub(r"^(.*= )(.*);$", r"\1(\2) + 1;", s),
  "newptr_tag":  lambda s: re.sub(r"^(.*= )(.*);$", r"\1(\2) + 1;", s),
  "leaftest": lambda s: s.replace("==", "!=", 1),
  "ptrcap":   lambda s: s.replace("<", "<="),
  "leafcap":  lambda s: s.replace("<", "<="),
  "fanout":   lambda s: "enum { PB_COUNT_MAX = 511 };",
}
t0 = open(sys.argv[1], errors="surrogateescape").read()
out = sys.argv[2]
names = []
for name, (pat, lit) in list(MUST.items()) + list(BLIND.items()):
    hits = list(re.finditer(pat, t0, re.M))
    if len(hits) != 1:
        sys.exit("the %s control anchor matches %d lines, expected 1" % (name, len(hits)))
    m = hits[0]
    rep = lit if lit is not None else REWRITE[name](m.group(0))
    t = t0[:m.start()] + rep + t0[m.end():]
    if t == t0:
        sys.exit("the %s control changed nothing, so it would not be a control" % name)
    if name == "leafcap":
        # the capacity control needs BOTH tests moved or the block-full arm contradicts it
        t = t.replace("if (dp->db_line_count >= DB_LINE_MAX && db_idx",
                      "if (dp->db_line_count > DB_LINE_MAX && db_idx", 1)
    if name == "fanout":
        # the static_assert states the fanout the page gave, so a control that changes
        # the fanout has to move the assert with it or nothing would compile
        t = re.sub(r"static_assert\(PB_COUNT_MAX == \(\d+ - 8\)",
                   "static_assert(PB_COUNT_MAX == (8192 - 16)", t, count=1)
    d = os.path.join(out, name)
    os.makedirs(d, exist_ok=True)
    open(os.path.join(d, "zero-vim.c"), "w", errors="surrogateescape").write(t)
    names.append(name)
print(" ".join(names))
print(" ".join(MUST))
'
mkdir -p "$tmp/ctl"
if ! ctl=$(python3 -c "$CTL_PY" "$f" "$tmp/ctl" 2>&1); then
    echo "  controls     a control could not be made from this phase's output:"
    printf '%s\n' "$ctl" | sed 's/^/               /'
    exit 1
fi
all_ctl=$(printf '%s\n' "$ctl" | sed -n 1p)
must_ctl=$(printf '%s\n' "$ctl" | sed -n 2p)
pids=''
for c in $all_ctl; do
    cp "$work/Makefile" "$tmp/ctl/$c/Makefile"
    ( make -C "$tmp/ctl/$c" >/dev/null 2>&1 ) &
    pids="$pids $!"
done
for p in $pids; do
    wait "$p" || { echo "  controls     a control did not build -- the break is wrong, not the corpus"; exit 1; }
done
# The fanout control is the one whose whole point is that a RECORDING cannot see it, so
# it is instrumented as well as recorded: what it moves is the marker set.
python3 -c "$MARK_PY" "$tmp/ctl/fanout/zero-vim.c" "$tmp/ctl/fanout/marked.c" new >/dev/null
mkdir -p "$tmp/fan"
cp "$work/Makefile" "$tmp/fan/Makefile"
cp "$tmp/ctl/fanout/marked.c" "$tmp/fan/zero-vim.c"
( make -C "$tmp/fan" >/dev/null 2>&1 ) &
fanpid=$!
pids=''
for c in $all_ctl; do
    ( tools/st.sh zcases "$tmp/ctl/$c/zero-vim" "$tmp/ctl/$c/screen" >/dev/null 2>&1
      tools/st.sh zmemline "$tmp/ctl/$c/zero-vim" "$tmp/ctl/$c/memline" >/dev/null 2>&1 ) &
    pids="$pids $!"
done
wait $fanpid || { echo "  controls     the instrumented fanout control did not build"; exit 1; }
tools/st.sh zmemline "$tmp/fan/zero-vim" "$tmp/fan-mem" >/dev/null 2>&1 || true
for p in $pids; do wait "$p" || true; done
if ! python3 - "$tmp/rec1" "$tmp/ctl" "$all_ctl" "$must_ctl" "$tmp/fan-mem" "$marks_new" <<'PY'
"""Nine controls that must move a recording and three that are measured not to."""
import filecmp
import os
import sys

base, ctl, every, must = sys.argv[1], sys.argv[2], sys.argv[3].split(), sys.argv[4].split()
fan, marks = sys.argv[5], sys.argv[6].split()
WHY = {
    'fanout': 'PB_COUNT_MAX = 511, which is what an 8-byte PTR_EN would give: THE '
              'FANOUT IS INVISIBLE TO A RECORDING, and what it really costs is below',
    'noclear': 'alloc() for alloc_clear(): the host\'s arena is a bump pointer over '
               'fresh pages, so the memory is already zero -- which is a fact about '
               'this host and not a promise the core may rest on, and ml_open\'s error '
               'path does rest on it',
    'nofree': 'ml_free_tree() walking the tree and freeing NOTHING, so a closed buffer '
              'keeps every node it had: ZERO-GOAL.md\'s charter says host_free() '
              'returns without doing anything, so what a core gives back is '
              'unobservable by construction',
}
rows = []
for c in every:
    moved = total = 0
    for part in ('screen', 'memline'):
        b, n = os.path.join(base, part), os.path.join(ctl, c, part)
        if not os.path.isdir(n):
            sys.exit('the %s control recorded nothing at all' % c)
        for name in sorted(os.listdir(b)):
            total += 1
            p = os.path.join(n, name)
            if not (os.path.exists(p) and filecmp.cmp(os.path.join(b, name), p, shallow=False)):
                moved += 1
    rows.append((c, moved, total))
bad = [c for c, m, _ in rows if c in must and m == 0]
if bad:
    sys.exit('  %-12s %s moved no record at all, so this check would pass on a binary '
             'that had lost the thing they break' % ('controls', ' '.join(bad)))
bad = [c for c, m, _ in rows if c not in must and m != 0]
if bad:
    sys.exit('  %-12s %s moved a record, and each of those three is stated here as a '
             'thing the corpus CANNOT see -- the measurement has changed and the reason '
             'written beside it is now wrong' % ('controls', ' '.join(bad)))
print('  %-12s %d that must move a recording do: %s'
      % ('controls', len(must),
         '  '.join('%s %d/%d' % (c, m, t) for c, m, t in rows if c in must)))
for c, m, t in rows:
    if c not in must:
        print('  %-12s %s 0/%d -- %s' % ('blind', c, t, WHY[c]))

# What the fanout control really costs, which is the whole reason section 3 compiles a
# static_assert instead of trusting arithmetic.
hit = {m: 0 for m in marks}
for n in sorted(os.listdir(fan)):
    t = open(os.path.join(fan, n), errors='replace').read()
    for m in marks:
        if m in t:
            hit[m] += 1
lost = [m for m in marks if hit[m] == 0]
if not lost:
    sys.exit('  %-12s PB_COUNT_MAX = 511 still reaches every marker, so the fanout does '
             'NOT decide the corpus\'s coverage and this phase\'s central claim is '
             'wrong' % 'fanout')
print('  %-12s and what PB_COUNT_MAX = 511 costs, which no recording showed: %s -- '
      '%s go to 0.  391 data blocks is more than 255 and less than 511, so an 8-byte '
      'PTR_EN would take the root split out of the corpus WITHOUT MOVING ONE RECORD'
      % ('fanout', '  '.join('%s %d' % (m, hit[m]) for m in marks), ' '.join(lost)))
PY
then
    exit 1
fi

# --- 9. zero phase 44's prediction, measured -------------------------------------
# Phase 44 wrote that allocating a block at its own size "would make an off-by-one in
# the capacity bound VISIBLE, which today it is not", and measured its own `cap` control
# at 0 of 118.  The same edit is made here to the INPUT and to the OUTPUT and both are
# recorded in this run, so the claim is a comparison and not a quotation.
OLDCAP_PY='
import sys
t = open(sys.argv[1], errors="surrogateescape").read()
n = t.replace("    if (dp->db_line_count < DB_LINE_MAX)",
              "    if (dp->db_line_count <= DB_LINE_MAX)", 1)
n = n.replace("if (dp->db_line_count >= DB_LINE_MAX && db_idx",
              "if (dp->db_line_count > DB_LINE_MAX && db_idx", 1)
if n == t:
    sys.exit("the leaf capacity bound is not where zero phase 44 left it")
open(sys.argv[2], "w", errors="surrogateescape").write(n)
'
mkdir -p "$tmp/oldcap"
cp "$work/Makefile" "$tmp/oldcap/Makefile"
if ! out=$(python3 -c "$OLDCAP_PY" "$state/old.c" "$tmp/oldcap/zero-vim.c" 2>&1); then
    echo "  prediction   phase 44's own control could not be made from this phase's input:"
    printf '%s\n' "$out" | sed 's/^/               /'
    exit 1
fi
make -C "$tmp/oldcap" >/dev/null 2>&1 || { echo "  prediction   phase 44's control did not build on the input"; exit 1; }
tools/st.sh zcases "$tmp/oldcap/zero-vim" "$tmp/oldcap/screen" >/dev/null 2>&1 || true
tools/st.sh zmemline "$tmp/oldcap/zero-vim" "$tmp/oldcap/memline" >/dev/null 2>&1 || true
if ! python3 - "$tmp/rec0" "$tmp/oldcap" "$tmp/rec1" "$tmp/ctl/leafcap" <<'PY'
import filecmp
import os
import sys


def moved(base, cand):
    m = t = 0
    for part in ('screen', 'memline'):
        b, n = os.path.join(base, part), os.path.join(cand, part)
        if not os.path.isdir(n):
            sys.exit('  %-12s %s recorded nothing at all' % ('prediction', cand))
        for name in sorted(os.listdir(b)):
            t += 1
            p = os.path.join(n, name)
            if not (os.path.exists(p) and filecmp.cmp(os.path.join(b, name), p, shallow=False)):
                m += 1
    return m, t


oi, ti = moved(sys.argv[1], sys.argv[2])
oo, to = moved(sys.argv[3], sys.argv[4])
if oi != 0:
    sys.exit('  %-12s the leaf capacity bound widened by one moves %d of %d records on '
             'the INPUT, where zero phase 44 measured 0 -- so the comparison below is '
             'not the one that phase set up' % ('prediction', oi, ti))
if oo == 0:
    sys.exit('  %-12s the leaf capacity bound widened by one still moves nothing, so '
             'allocating a block at its own size did NOT make the off-by-one visible '
             'and zero phase 44\'s prediction is unmet' % 'prediction')
print('  %-12s zero phase 44 wrote that allocating a block at its own size would make '
      'an off-by-one in the capacity bound VISIBLE.  Its own control, the leaf capacity '
      'test widened by one, moves %d of %d records on this phase\'s INPUT -- the 0 of '
      '118 that phase recorded -- and %d of %d here.  A leaf is 1,040 bytes of its own '
      'allocation now and was 1,040 bytes of a 4,096-byte page'
      % ('prediction', oi, ti, oo, to))
PY
then
    exit 1
fi

# --- 10. the symbols, the cut, and the ordinary checks ---------------------------
gcc -c -O0 -fno-stack-protector -o "$tmp/new.o" "$f" 2>/dev/null
gcc -c -O0 -fno-stack-protector -o "$tmp/old.o" "$state/old.c" 2>/dev/null
nm -u "$tmp/new.o" | awk '{print $2}' | sort > "$tmp/u.new"
nm -u "$tmp/old.o" | awk '{print $2}' | sort > "$tmp/u.old"
if [ -n "$(comm -3 "$tmp/u.old" "$tmp/u.new")" ]; then
    echo "  symbols      this phase frees no libc symbol and needs none, and the set moved:"
    comm -3 "$tmp/u.old" "$tmp/u.new" | sed 's/^/               /'
    exit 1
fi
echo "  symbols      $(grep -c '' "$tmp/u.new") undefined names, the input's set exactly, a comm empty both ways: a node allocated at its own size asks the host for nothing the editor did not already ask it for"

cut_lines=$(grep -c '' "$tmp/cut.c")
if [ "$cut_lines" -lt 70000 ]; then
    echo "  cut          the core is $cut_lines lines, so the cut found the wrong line"
    exit 1
fi
if [ "$(grep -c '^ *#' "$tmp/cut.c")" != 0 ]; then
    echo "  cut          the core holds a directive"
    exit 1
fi
gcc -fsyntax-only -Wall -Wextra -Wno-unused-parameter "$tmp/cut.c" 2>"$tmp/cut.warn" || {
    echo "  cut          the core does not parse on its own"; exit 1; }
iface() { grep -o "'[a-zA-Z_][a-zA-Z0-9_]*' used but never defined" "$1" | sort -u; }
gcc -fsyntax-only -Wall -Wextra -Wno-unused-parameter "$tmp/cut.old.c" 2>"$tmp/cut.old.warn" || true
if ! diff <(iface "$tmp/cut.old.warn") <(iface "$tmp/cut.warn") >/dev/null; then
    echo "  cut          the core -> host interface moved, and this phase adds no host call:"
    diff <(iface "$tmp/cut.old.warn") <(iface "$tmp/cut.warn") | sed 's/^/               /'
    exit 1
fi
echo "  cut          the core is $cut_lines lines and was $(grep -c '' "$tmp/cut.old.c"), 0 directives, 0 errors, and the interface is the input's $(iface "$tmp/cut.warn" | wc -l) names unchanged"

after_lines=$(grep -c '' "$f")
echo "  source       $before_lines -> $after_lines lines; the binary is $(stat -c%s "$new") bytes against the input's $(stat -c%s "$old")"

tools/st.sh zhostonly "$f"
tools/phasecheck.sh "$work" "$f" "$state/symbols"
