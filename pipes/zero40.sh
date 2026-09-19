#!/bin/sh
# Zero phase 40 -- the instrument learns to see the text layer.
#                  See ZERO-GOAL.md, ZERO-PLAN.md.
#
# Usage: pipes/zero40.sh <work-dir>      (run from the repository root)
#
# NO SOURCE CHANGE AT ALL: r40's zero-vim.c is its input's, byte for byte, and this
# phase asserts it first and last.  What changes is what every later phase is
# measured with.  This is zero phase 3's shape and zero phase 33's -- the two other
# phases that change no source and replace or repair an instrument -- and it is here
# for the same reason both of those were: a harness that cannot see a phase must be
# fixed BEFORE the phase, never after.
#
# WHAT WAS WRONG.  The editor holds its text in a memline: a memfile of 4,096-byte
# pages, a tree of pointer blocks over data blocks, with every pointer entry
# carrying the number of lines under it.  MEASURED with an instrumented build of
# the source this phase was handed: every one of `tools/zcases.py`'s 102 screen
# cases allocates EXACTLY ONE data block.  So the root pointer block holds exactly
# one entry for the whole session, `ml_find_line()` never chooses among entries --
# `idx` is 0 every time -- and `pe_line_count` is never the number that decides
# which child a line is in.  A `zero-vim` with
#
#     pp->pb_pointer[idx].pe_line_count--;
#
# deleted from `ml_find_line()`'s ML_DELETE arm therefore records all 102 cases
# BYTE FOR BYTE, and the Ex sweep, the argv records, the pty scenarios and the
# terminal table cannot see a text layer at all.  Forty phases had been verified by
# an instrument blind to the data structure the whole editor stands on.
#
# WHAT THE NEW PART IS.  `tools/zmemline.py`, the sixth part of a recording
# (`tools/zrecord.sh`): 16 cases that build buffers of 200 to 25,000 lines IN THE
# EDITOR -- there is no file argument (phase 5), no `:edit` (phase 8) and no
# `:read` (phase 7) -- churn them in the middle, and read them back.  Every line
# begins with its own line number, so a screen drawn with `'number'` shows the
# tree's answer beside the question; `zcompare.py` compares them under a `mem:`
# token beside `case:`.
#
# NOTHING HERE IS A NUMBER THAT WAS OBSERVED.  The page size, the data-block
# header, the pointer-entry size and `pb_count_max` are DERIVED by compiling the
# struct definitions out of the source the phase was handed; the line counts the
# corpus uses are read out of `tools/zmemline.py` itself; and which case reaches
# which part of the tree is MEASURED with an instrumented build rather than
# intended.  A corpus that means to reach a root split and does not is exactly the
# defect this phase exists to end, so the phase is not allowed to assert it -- it
# has to show it.
#
# AND A MEMLINE RECORD CARRIES NO STREAM DIGEST, which is this phase's one
# departure from `tools/zcases.py`'s record and was forced by a measurement.  An
# undo in a buffer this size reports its age, and the editor writes the message and
# then positions the cursor to clear the rest of the line -- so `0 seconds ago`
# emits `\033[24;40H\033[K` and `1 second ago` emits `\033[24;39H\033[K`, a COLUMN
# derived from the width of a timestamp, which `tools/zrec.py`'s scrub cannot reach
# because it rewrites the age's TEXT and this is arithmetic on its length.  It was
# caught as a one-byte stream difference in `mem_undo_big`, once in 48 whole
# recordings of one binary, with every screen identical either way.  The digest is
# replaced by the count of `\033[?25h` -- where a redraw ends -- and what replaces
# it as evidence is section 6's clock control, which is stronger than a digest: it
# says the record does not depend on the clock AT ALL, rather than that two runs of
# it happened to agree.
#
# WHY RE-RECORDING THE BASELINES IS LEGITIMATE is zero phase 33's argument and is
# not repeated here: the baselines come from `whim-vim.c`, the pipeline's immutable
# input, built with WHIM's compile line, recorded three times and required
# identical, and nothing zero produces is on the recording side.  A new PART of a
# recording is a new file in that set, so phase 0 must record it:
#
#     rm -rf .reference/zero-baselines .cache/r0 && make zero-phase-0
#
# and `rm -rf .cache/r0` alone is not enough -- `pipes/zero0.sh` refuses a set that
# differs rather than overwriting it.
#
# WHAT THIS PHASE PROVES, in order, each depending on the one before:
#
#   1. the tree is untouched: zero-vim.c is what the phase was handed;
#   2. it builds with the boundary's flags, is still absolutely static, and `main`
#      is still the only external symbol;
#   3. THE CORPUS IS SIZED AGAINST THE SOURCE.  The block arithmetic is computed
#      from the struct definitions in the file, and the corpus's own smallest and
#      largest builds are required to clear the derived one-block and root-split
#      thresholds;
#   4. THE DEPTH IS REACHED, AND THE OLD CORPUS DOES NOT REACH IT.  One
#      instrumented build, seven markers on the seven paths, run under BOTH
#      corpora: every marker must be in at least one memline record and in NONE of
#      the 102.  That pair is the premise of the phase and its coverage in one
#      measurement;
#   5. THE INSTRUMENT IS DETERMINISTIC: three whole recordings of that binary, byte
#      for byte identical;
#   6. THE INSTRUMENT CAN FAIL, AND THE ONE IT JOINS CANNOT.  Five scratch builds.
#      Two corruptions of the tree's line bookkeeping -- one in the descent, one in
#      the deferred adjustment -- must move memline records and must move NONE of
#      the 102.  A third, in the descent CACHE, must move exactly the cases the
#      probe in section 4 says descend past one pointer level, which is a rule and
#      not a list.  A fourth must move NOTHING AT ALL although it reshapes the tree
#      completely, so that the corpus is shown to record BEHAVIOUR and not tree
#      shape.  And the fifth is about the RECORD and not the editor: both clocks
#      the core can read are replaced by counters that run away from the wall, and
#      no memline record may move -- while some of the 102 must, which is what
#      keeps that from being a control with no effect;
#   7. the declared delta holds -- NOTHING, and nothing new: tools/zerodelta.sh
#      --phase 40 against .reference/zero-baselines.
set -eu

work=${1:?usage: zero40.sh <work-dir>}
f="$work/zero-vim.c"
base=.reference/zero-baselines

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# --- 0. the baselines must already hold the new part ------------------------
# A tier 3 hit on phase 0 records nothing, and section 7's comparison is against
# what phase 0 wrote.  Name the fix here rather than letting it fail with a diff
# and no explanation.
if [ -d "$base" ] && [ ! -d "$base/memline" ]; then
    echo "  baselines    $base has no memline/ -- it is the recording of five parts"
    echo "               and a recording is six now (tools/zrecord.sh).  Zero phase 0"
    echo "               records them, from whim-vim.c -- the pipeline's immutable"
    echo "               input -- and REFUSES to overwrite a set that differs, so"
    echo "               BOTH paths have to go:"
    echo "                 rm -rf .reference/zero-baselines .cache/r0 && make zero-phase-0"
    exit 1
fi

# --- 1. the tree is untouched ----------------------------------------------
before=$(sha256sum "$f" | cut -c1-64)

# --- 2. the build, with the boundary's flags -------------------------------
make -C "$work" clean >/dev/null 2>&1 || true
if ! make -C "$work" >/dev/null 2>&1; then
    echo "  build        FAILED -- rerun by hand: make -C $work"
    exit 1
fi
bin="$work/zero-vim"
type=$(readelf -h "$bin" | awk -F: '$1 ~ /^ *Type$/ { sub(/^ +/, "", $2); split($2, t, " "); print t[1] }')
interp=$(readelf -l "$bin" | grep -c 'INTERP' || true)
dynamic=$(readelf -d "$bin" | grep -c '^There is no dynamic section in this file\.$' || true)
relocs=$(readelf -r "$bin" | grep -c '^There are no relocations in this file\.$' || true)
if [ "$type" != EXEC ] || [ "$interp" != 0 ] || [ "$dynamic" != 1 ] || [ "$relocs" != 1 ]; then
    echo "  static       NOT absolutely static: type $type, INTERP $interp, no-dynamic $dynamic, no-relocations $relocs"
    exit 1
fi
echo "  build        ok, $(stat -c%s "$bin") bytes: EXEC, no INTERP, no dynamic section, 0 relocations"

# The source is the input's, so every fact about the TEXT is inherited from the sha
# in section 1.  `main` alone is a fact about a binary that was compiled again, and
# it is a rule the whole tree states.  The undefined count is REPORTED and not
# pinned: a number this phase cannot move is not a check.
gcc -c -O0 -fno-stack-protector -o "$tmp/new.o" "$f"
ext=$(nm --extern-only --defined-only "$tmp/new.o" | awk '{print $NF}' | sort | tr '\n' ' ')
if [ "$ext" != "main " ]; then
    echo "  symbols      the output defines external symbols other than main: $ext"
    exit 1
fi
echo "  symbols      \`main\` is still the only external symbol, over $(nm -u "$tmp/new.o" | grep -c '') undefined"

# --- 3. the corpus is sized against the source's own arithmetic -------------
# The struct definitions are lifted out of the file the phase was handed and
# compiled, so page_size, offsetof(DATA_BL, db_index), sizeof(PTR_EN) and
# pb_count_max are the EDITOR's numbers and not this script's.  The corpus's own
# build sizes then have to clear the thresholds those numbers imply.
if ! python3 - "$f" > "$tmp/sizes" 2>&1 <<'PY'
"""Derive the memline block arithmetic from the source, and size the corpus by it.

Nothing below is a constant: the four typedefs, the page-size enumerator and the
three struct definitions are found by name in the source the phase was handed and
compiled into a tiny program, and the line counts are read out of
tools/zmemline.py's own SIZES, which build() fills as the cases are built.
"""
import os
import re
import subprocess
import sys
import tempfile

sys.path.insert(0, 'tools')
import zmemline

src = sys.argv[1]
text = open(src, errors='surrogateescape').read()

parts = []
for name in ('char_u', 'short_u', 'linenr_T', 'blocknr_T', 'PTR_EN'):
    m = re.search(r'^typedef [^\n;]*\b%s;$' % name, text, re.M)
    if not m:
        sys.exit('typedef %s is not in the source: the arithmetic cannot be derived' % name)
    parts.append(m.group(0))
m = re.search(r'^enum \{ MEMFILE_PAGE_SIZE = (\d+) \};$', text, re.M)
if not m:
    sys.exit('MEMFILE_PAGE_SIZE is not an enumerator in the source')
parts.append(m.group(0))
for name in ('pointer_entry', 'pointer_block', 'data_block'):
    m = re.search(r'^struct %s\n\{.*?^\};$' % name, text, re.M | re.S)
    if not m:
        sys.exit('struct %s is not in the source' % name)
    parts.append(m.group(0))

prog = '\n'.join(parts) + r'''
int printf(const char *, ...);
int main(void) {
    printf("%d %d %d %d %d\n", (int)MEMFILE_PAGE_SIZE,
        (int)__builtin_offsetof(struct data_block, db_index),
        (int)__builtin_offsetof(struct pointer_block, pb_pointer),
        (int)sizeof(struct pointer_entry), (int)sizeof(unsigned));
    return 0;
}
'''
d = tempfile.mkdtemp(prefix='zero40-derive-')
c = os.path.join(d, 'd.c')
open(c, 'w').write(prog)
subprocess.run(['gcc', '-O0', '-o', os.path.join(d, 'd'), c], check=True)
page, data_hdr, ptr_hdr, ptr_en, idx = map(
    int, subprocess.run([os.path.join(d, 'd')], capture_output=True, text=True,
                        check=True).stdout.split())

# A line costs its index entry plus its text and a NUL; a pointer block points at
# pb_count_max children; the root gains a level when it needs one more than that.
per_block = (page - data_hdr) // (zmemline.LINE_BYTES + 1 + idx)
pb_count_max = (page - ptr_hdr) // ptr_en
root_split = (pb_count_max + 1) * per_block

sizes = sorted(set(zmemline.SIZES))
if not sizes:
    sys.exit('tools/zmemline.py builds no buffer at all: the corpus would be vacuous')
if sizes[0] <= per_block:
    sys.exit('the corpus\'s smallest buffer is %d lines and one data block holds %d, '
             'so its smallest case need not have a tree at all' % (sizes[0], per_block))
if sizes[-1] <= root_split:
    sys.exit('the corpus\'s largest buffer is %d lines and the root pointer block '
             'holds %d children of %d lines each, so %d lines are needed before it '
             'can split' % (sizes[-1], pb_count_max, per_block, root_split))
print('page %d, data header %d, index %d, PTR_EN %d: a %d-byte line packs %d to a '
      'block and pb_count_max is %d, so the root splits past %d lines'
      % (page, data_hdr, idx, ptr_en, zmemline.LINE_BYTES, per_block, pb_count_max,
         root_split))
print('%d cases build %s lines: %d past one block, %d past the root split'
      % (len(zmemline.CASES), ','.join(str(s) for s in sizes),
         len([s for s in sizes if s > per_block]),
         len([s for s in sizes if s > root_split])))
PY
then
    sed 's/^/  arithmetic   /' "$tmp/sizes"
    exit 1
fi
sed 's/^/  arithmetic   /' "$tmp/sizes"

# --- 4. the depth is reached, and the old corpus does not reach it -----------
# ONE instrumented build, seven markers, run under both corpora.  Each marker is a
# once-per-process host_message() -- the core's own declared way to stderr, phase
# 21's, which adds no name the file does not already have -- so a record carries a
# marker if and only if that path ran in that session.
MARK_PY='
import sys
MARKS = [
    ("MLSPLITDATA",
     "        page_count = ((space_needed +  (__builtin_offsetof(DATA_BL, db_index)) ) + page_size - 1) / page_size;\n",
     "before", None, ""),
    ("MLBIGLINE",
     "        page_count = ((space_needed +  (__builtin_offsetof(DATA_BL, db_index)) ) + page_size - 1) / page_size;\n",
     "after", "page_count > 1", ""),
    ("MLSPLITPTR",
     "                hp_new = ml_new_ptr(mfp);\n",
     "before", None, "        ++zprobe_ptr;\n"),
    ("MLSIBSPLIT",
     "                if (hp-> bh_hashitem.mhi_key  != 1)\n                {\n                    break;\n                }\n",
     "before", "zprobe_ptr == 1", ""),
    ("MLSPLITROOT",
     "                 musl_memmove((char *)(pp_new), (char *)(pp), (usize)page_size) ;\n",
     "before", None, ""),
    ("MLIDXNZ",
     "                ip->ip_index = idx;\n",
     "after", "idx > 0", ""),
    ("MLDEEP",
     "        if ((top = ml_add_stack(buf)) < 0)\n",
     "before", "++zprobe_lvl >= 2", ""),
]
DECLS = [("    bnum = 1;\n", "    int zprobe_lvl = 0;\n"),
         ("            if (pp->pb_count < pp->pb_count_max)\n", "            int zprobe_ptr = 0;\n")]
t = open(sys.argv[1], errors="surrogateescape").read()
for anchor, decl in DECLS:
    if t.count(anchor) != 1:
        sys.exit("the probe anchor %r is in the source %d times, expected 1"
                 % (anchor.strip(), t.count(anchor)))
    t = t.replace(anchor, decl + anchor, 1)
for name, anchor, where, cond, extra in MARKS:
    if t.count(anchor) != 1:
        sys.exit("the probe anchor for %s is in the source %d times, expected 1"
                 % (name, t.count(anchor)))
    body = ("{ static int z_%s = 0; if (!z_%s) { z_%s = 1; "
            "host_message(\"%s\\n\", -1, TRUE); } }\n" % (name, name, name, name))
    ins = extra + ("        if (%s) %s" % (cond, body) if cond else "        " + body)
    t = t.replace(anchor, ins + anchor if where == "before" else anchor + ins, 1)
open(sys.argv[2], "w", errors="surrogateescape").write(t)
print(" ".join(m[0] for m in MARKS))
'
mkdir -p "$tmp/probe"
if ! marks=$(python3 -c "$MARK_PY" "$f" "$tmp/probe/zero-vim.c" 2>&1); then
    echo "  probe        the instrument could not be built from this source:"
    printf '%s\n' "$marks" | sed 's/^/               /'
    exit 1
fi
cp "$work/Makefile" "$tmp/probe/Makefile"

# The four controls of section 6 are built alongside, because six gcc runs in
# parallel cost what one costs.  Each is ONE line of the input rewritten, and each
# anchor is required to be in the file exactly once.
CTL_PY='
import sys
EDITS = {
  "descent": [("            pp->pb_pointer[idx].pe_line_count--;\n", "")],
  "lineadd": [("        pp->pb_pointer[ip->ip_index].pe_line_count += count;\n", "")],
  "cache":   [("            if (ip->ip_low <= lnum && ip->ip_high >= lnum)\n",
               "            if (ip->ip_low <= lnum && ip->ip_high + 1 >= lnum)\n")],
  "reshape": [("    pp->pb_count_max =  (short_u)(((mfp)->mf_page_size - __builtin_offsetof(PTR_BL, pb_pointer)) / sizeof(PTR_EN)) ;\n",
               "    pp->pb_count_max =  (short_u)(((mfp)->mf_page_size - __builtin_offsetof(PTR_BL, pb_pointer)) / sizeof(PTR_EN) / 4) ;\n")],
  # Both clocks the core can still read, each replaced by a counter that runs
  # away from the wall: the wall clock by seven seconds a call and the elapsed
  # millisecond clock by 997 a call.  Nothing the editor DOES changes.
  "clock":   [("host_time(void)\n{\n    return time(nullptr);\n}\n",
               "host_time(void)\n{\n    static long z_t = 2000000000L;\n    z_t += 7;\n    return z_t;\n}\n"),
              ("musl_now_ms(void)\n{\n    struct timeval tv;\n",
               "musl_now_ms(void)\n{\n    static long z_ms = 0;\n    z_ms += 997;\n    return z_ms;\n    struct timeval tv;\n")],
}
t = open(sys.argv[1], errors="surrogateescape").read()
for old, new in EDITS[sys.argv[3]]:
    if t.count(old) != 1:
        sys.exit("a %s control anchor is in the source %d times, expected 1"
                 % (sys.argv[3], t.count(old)))
    t = t.replace(old, new, 1)
open(sys.argv[2], "w", errors="surrogateescape").write(t)
'
for c in descent lineadd cache reshape clock; do
    mkdir -p "$tmp/$c"
    if ! out=$(python3 -c "$CTL_PY" "$f" "$tmp/$c/zero-vim.c" "$c" 2>&1); then
        echo "  ablefail     a control could not be made from this source:"
        printf '%s\n' "$out" | sed 's/^/               /'
        exit 1
    fi
    cp "$work/Makefile" "$tmp/$c/Makefile"
done
# The reshape control's tree is measured and not asserted, so it gets a probe too.
mkdir -p "$tmp/reprobe"
python3 -c "$MARK_PY" "$tmp/reshape/zero-vim.c" "$tmp/reprobe/zero-vim.c" >/dev/null
cp "$work/Makefile" "$tmp/reprobe/Makefile"

pids=''
for d in probe descent lineadd cache reshape clock reprobe; do
    ( make -C "$tmp/$d" >/dev/null 2>&1 ) &
    pids="$pids $!"
done
for p in $pids; do
    if ! wait "$p"; then
        echo "  ablefail     an instrumented or control copy did not build -- the break is wrong, not the corpus"
        exit 1
    fi
done

python3 tools/zmemline.py "$tmp/probe/zero-vim" "$tmp/probe-mem" >/dev/null
python3 tools/zcases.py "$tmp/probe/zero-vim" "$tmp/probe-screen" >/dev/null
python3 tools/zmemline.py "$tmp/reprobe/zero-vim" "$tmp/reprobe-mem" >/dev/null
if ! python3 - "$tmp/probe-mem" "$tmp/probe-screen" "$marks" "$tmp/deep" > "$tmp/cover" 2>&1 <<'PY'
"""Every marker in at least one memline record, and in NONE of the 102.

The second half is the premise of the whole phase and the first is its coverage,
and both are counted rather than intended.  The names of the cases that reach
MLDEEP -- ml_find_line descending through a second pointer block -- are written
out for section 6, which requires the descent-cache control to move exactly them.
"""
import os
import sys

memdir, scrdir, marks, deepfile = sys.argv[1], sys.argv[2], sys.argv[3].split(), sys.argv[4]
if not marks:
    sys.exit('the probe placed no marker at all, so this check would be vacuous')


def hits(d):
    out = {}
    for n in sorted(os.listdir(d)):
        t = open(os.path.join(d, n), errors='replace').read()
        out[n] = set(m for m in marks if m in t)
    return out


mem, scr = hits(memdir), hits(scrdir)
missing = [m for m in marks if not any(m in v for v in mem.values())]
if missing:
    sys.exit('the memline corpus reaches none of: %s\n'
             'A corpus that MEANS to reach a split and does not is the defect this '
             'phase exists to end.' % ' '.join(missing))
seen = sorted(set().union(*scr.values())) if scr else []
if seen:
    sys.exit('%d of the %d screen cases already reach %s, so the premise of this '
             'phase is wrong on this boundary and the corpus below is not what makes '
             'the text layer visible'
             % (len([1 for v in scr.values() if v]), len(scr), ' '.join(seen)))
deep = sorted(n for n, v in mem.items() if 'MLDEEP' in v)
if not deep:
    sys.exit('no memline case descends past one pointer block')
open(deepfile, 'w').write('\n'.join(deep) + '\n')
print('%d markers on the memline tree, each in at least one of %d memline records '
      'and in 0 of %d screen cases:' % (len(marks), len(mem), len(scr)))
print('  ' + '  '.join('%s %d' % (m, len([1 for v in mem.values() if m in v]))
                       for m in marks))
PY
then
    sed 's/^/  probe        /' "$tmp/cover"
    exit 1
fi
sed 's/^/  probe        /' "$tmp/cover"

# --- 5. the instrument is deterministic ------------------------------------
# The whole recording, not just the new part: the stream digests are inside it, so
# a redraw that drew the same result differently would fail here.
for r in 1 2 3; do
    tools/zrecord.sh "$bin" "$f" "$tmp/run$r"
    if [ "$r" != 1 ] && ! diff -r "$tmp/run1" "$tmp/run$r" >/dev/null; then
        echo "  instrument   run $r differs from run 1 -- not deterministic, not an instrument:"
        diff -rq "$tmp/run1" "$tmp/run$r" | head -10 | sed 's/^/               /'
        exit 1
    fi
done
cases=$(ls "$tmp/run1/screen" | grep -c '')
mems=$(ls "$tmp/run1/memline" | grep -c '')
cmds=$(grep -c '^=== ' "$tmp/run1/ref-excmds.txt")
argvs=$(grep -c '^=== ' "$tmp/run1/ref-argv.txt")
ptys=$(grep -c '^=== ' "$tmp/run1/ref-pty.txt")
terms=$(grep -c '' "$tmp/run1/ref-term.txt")
echo "  instrument   $cases cases, $mems memline cases, $cmds commands, $argvs command lines, $ptys pty scenarios, $terms terminals: 3 identical runs"

# --- 6. the instrument can fail, and the one it joins cannot ----------------
# Four controls, and the shape of each is stated before its result.  The two
# corruptions must move memline records; the descent-cache one must move exactly
# the cases section 4 MEASURED as descending past one pointer block; and the
# reshape must move nothing although it changes the tree.  Every one of them must
# leave the 102 screen cases alone, which is what says the old corpus is blind and
# not merely lucky.
for c in descent lineadd cache reshape clock; do
    python3 tools/zmemline.py "$tmp/$c/zero-vim" "$tmp/mem-$c" >/dev/null
    python3 tools/zcases.py "$tmp/$c/zero-vim" "$tmp/scr-$c" >/dev/null
done
if ! python3 - "$tmp/run1" "$tmp" "$tmp/deep" "$tmp/probe-mem" "$tmp/reprobe-mem" \
        > "$tmp/ablefail" 2>&1 <<'ZPY'
"""The five controls, each with the claim it is there to settle.

`descent` and `lineadd` corrupt the two places a pointer entry's line count is
maintained -- immediately, while ml_find_line descends, and afterwards, in
ml_lineadd's deferred adjustment -- and each must move memline records.  `cache`
breaks ml_find_line's ML_FIND stack so it accepts a line one past a block's range,
and must move EXACTLY the cases the probe measured as descending past one pointer
block, which is a rule and not a list.  `reshape` quarters pb_count_max: the tree
becomes a different tree and the editor's behaviour does not change, so the corpus
must record it byte for byte -- and the probe is asked whether the tree really did
move, so that the control cannot pass for being no control at all.  `clock` runs
both clocks the core can read away from the wall and must move NO memline record,
which is what says the record carries no timestamp; it must move some of the 102,
which is what says the clock really changed, and those are the undo cases, whose
stream digest this corpus deliberately does not keep.

The first four must move none of the 102.  That is not a detail: it is the whole
premise of the phase, that the corpus the pipeline already had cannot see the text
layer at all.
"""
import os
import sys

run1, tmp, deepfile, probe_mem, reprobe_mem = sys.argv[1:6]
CORRUPT = ('descent', 'lineadd', 'cache', 'reshape')


def read(d):
    return {n: open(os.path.join(d, n), errors='replace').read()
            for n in sorted(os.listdir(d))}


def moved(a, b):
    return sorted(n for n in set(a) | set(b) if a.get(n) != b.get(n))


base_mem = read(os.path.join(run1, 'memline'))
base_scr = read(os.path.join(run1, 'screen'))
out = {c: (read(os.path.join(tmp, 'mem-' + c)), read(os.path.join(tmp, 'scr-' + c)))
       for c in CORRUPT + ('clock',)}

by, byscr = {}, {}
for c in CORRUPT + ('clock',):
    by[c], byscr[c] = moved(base_mem, out[c][0]), moved(base_scr, out[c][1])

bad = []
for c in CORRUPT:
    if byscr[c]:
        bad.append('the %s control moved %d of the %d SCREEN cases (%s), so the old '
                   'corpus is not blind to it and this phase has the wrong premise'
                   % (c, len(byscr[c]), len(base_scr), ' '.join(byscr[c][:5])))
deep = [l for l in open(deepfile).read().split('\n') if l]
for c in ('descent', 'lineadd'):
    if not by[c]:
        bad.append('the %s control moved NO memline record: a corpus that cannot fail '
                   'is not evidence' % c)
if by['cache'] != deep:
    bad.append('the cache control moved %s, and the cases the probe measured as '
               'descending past one pointer block are %s -- the two must be the same '
               'set, or the deep cases are decoration'
               % (' '.join(by['cache']) or '(nothing)', ' '.join(deep)))
if by['reshape']:
    bad.append('the reshape control moved %s: quartering pb_count_max changes the '
               'TREE and not the editor, so a corpus that moves is recording the '
               'data structure rather than the behaviour' % ' '.join(by['reshape']))
if by['clock']:
    bad.append('the clock control moved %s: a memline record must not depend on what '
               'time it is, and the stream digest this corpus drops was dropped for '
               'exactly that' % ' '.join(by['clock']))
if not byscr['clock']:
    bad.append('the clock control moved none of the %d screen cases either, so it '
               'changed nothing and its empty memline result proves nothing'
               % len(base_scr))

# And the reshape control has to be a control: its tree must really be different.
was = set(n for n, t in read(probe_mem).items() if 'MLSPLITROOT' in t)
now = set(n for n, t in read(reprobe_mem).items() if 'MLSPLITROOT' in t)
if now <= was:
    bad.append('quartering pb_count_max left the same %d cases splitting the root, so '
               'the control changed no tree and its empty result proves nothing'
               % len(was))

if bad:
    sys.exit('\n'.join(bad))
print('5 controls, and 0 of the %d screen cases moved by any of the four corruptions:'
      % len(base_scr))
print('  descent  pe_line_count-- gone from ml_find_line: %d of %d memline records move'
      % (len(by['descent']), len(base_mem)))
print("  lineadd  ml_lineadd's deferred adjustment gone:  %d of %d move"
      % (len(by['lineadd']), len(base_mem)))
print('  cache    ML_FIND stack one line too wide:        %d of %d move, and they are '
      'exactly the %d the probe measured descending past one pointer block'
      % (len(by['cache']), len(base_mem), len(deep)))
print('  reshape  pb_count_max quartered:                 0 of %d move, while the root '
      'split goes from %d cases to %d' % (len(base_mem), len(was), len(now)))
print('  clock    both clocks run away from the wall:     0 of %d move, and %d of the '
      '%d screen cases do (%s) -- the record carries no timestamp, and the control is '
      'not a no-op' % (len(base_mem), len(byscr['clock']), len(base_scr),
                       ' '.join(byscr['clock'])))
ZPY
then
    sed 's/^/  ablefail     /' "$tmp/ablefail"
    echo "               A corpus that cannot fail is not evidence, and one that"
    echo "               fails differently is not this corpus."
    exit 1
fi
sed 's/^/  ablefail     /' "$tmp/ablefail"

# --- 7. the declared delta, against the input's own behaviour ---------------
tools/zerodelta.sh "$bin" "$f" --phase 40

# --- 1, concluded: nothing in the tree moved -------------------------------
after=$(sha256sum "$f" | cut -c1-64)
if [ "$before" != "$after" ]; then
    echo "  source       zero-vim.c was modified by a phase that must not modify it"
    exit 1
fi
echo "  source       zero-vim.c unchanged, $(grep -c '' "$f") lines: r40 is its input's tree, and only the instrument moved"
