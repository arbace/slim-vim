#!/bin/sh
# Zero phase 44's check -- de-page the leaf.
#
# Usage: pipes/zero44-check.sh <work-dir> <state-dir>   (run from the repository root)
#
# THE DECLARED DELTA IS NOTHING AT ALL AND IT IS THE WEAKEST KIND THERE IS.  The code
# changes, the binary moves, and the claim is that a replacement does what the thing
# it replaces did -- which is zero phases 14 and 15's kind and no other.  There is no
# `cmp` to be had: every line of the buffer is stored somewhere else now.  So the
# recordings are the floor and not the evidence, and what carries the phase is the
# controls: eleven builds of this phase's own output with one thing changed, eight of
# which MUST move a recording and three of which must not, each of the three with the
# reason it cannot be seen written beside it.
#
# WHAT IS CHECKED, in the order it is cheapest to fail:
#
#   1  the product builds from a tree the clean really emptied
#   2  THE PARTITION.  Every mention of db_free, db_txt_start, db_txt_end, db_index,
#      the stolen top bit, ML_APPEND_MARK and offsetof(DATA_BL) is gone -- and the
#      input's count of each is read off the input, never written here
#   3  the representation, read out of the output: the record's three members, the
#      block's three, and the static_assert that keeps a leaf inside its page
#   4  THE LIFETIME RULE as a partition over every assignment to a record's text
#   5  two full recordings, byte for byte the input's, and identical to each other
#   6  the memline corpus REACHES the tree, measured with an instrumented pair
#   7  WHAT THE REPRESENTATION COSTS THE ARENA, which is the one resource claim a
#      per-line allocation owes and which no recording can make
#   8  the controls
#   9  nm -u unchanged both ways, the cut, and the ordinary phase checks
#
# WHY SECTION 6 EXISTS AND WHY IT IS THIS PHASE'S AND NOT PHASE 40'S.  Before phase
# 40 a zero-vim with one line deleted from ml_find_line()'s descent recorded all 102
# screen cases byte for byte.  This phase rewrites the leaf that corpus was built to
# see, so it owes the measurement in both directions: the output must still reach the
# splits, and the input's own numbers are taken in the same run with the same
# instrument, so that "it reaches them" is a comparison and not an assertion.
#
# ONE PATH IS REMOVED ON PURPOSE AND THE SECTION SAYS SO.  A line longer than a page
# used to make the data block two pages -- phase 40's MLBIGLINE marker, reached by
# three of the sixteen cases.  A record is a pointer, so there is no such thing any
# more, and the marker has no anchor in the output at all.  That is the one number
# that may go down.
set -eu

work=${1:?usage: zero44-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero44-check.sh <work-dir> <state-dir>}
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
python3 - "$f" "$state/old.c" "$state/gone" "$state/dbmax" <<'PY'
import re
import sys

new = open(sys.argv[1], errors='surrogateescape').read()
old = open(sys.argv[2], errors='surrogateescape').read()
gone = [l.rstrip('\n').rsplit('\t', 1) for l in open(sys.argv[3]) if l.strip()]
dbmax = int(open(sys.argv[4]).read())
BIT = '((unsigned)1 << ((sizeof(unsigned) * 8) - 1))'


def die(tag, msg):
    sys.exit('  %-12s %s' % (tag, msg))


def w(t, n):
    return len(re.findall(r'\b%s\b' % re.escape(n), t))


# --- 2. the partition ------------------------------------------------------------
# The input's counts are the edit's measurement of the input, re-read here off the
# INPUT rather than trusted: a number written into this file would be a fact about a
# boundary that was, not about the one that arrives.
for name, n in gone:
    n = int(n)
    here = old.count(BIT) if name == BIT else w(old, name)
    if here != n:
        die('partition', 'the edit recorded %s at %d mentions of the input and it '
            'has %d' % (name, n, here))
    if (new.count(BIT) if name == BIT else w(new, name)) != 0:
        die('partition', '%s survives into the output' % name)
if 'offsetof(DATA_BL' in new:
    die('partition', 'a data block is still measured with offsetof')
if old.count('offsetof(DATA_BL') != 2:
    die('partition', 'the input does not measure a data block with offsetof twice')
if new.count('offsetof(PTR_BL') != 1 or old.count('offsetof(PTR_BL') != 1:
    die('partition', "ml_new_ptr's offsetof moved, and a POINTER block is still a "
        'page and is not this phase\'s')
ptr_in = len(re.findall(r'\(char_u? \*\)dp[a-z_]* *\+', old.replace('(char *)dp', '(char_u *)dp')))
ptr_out = len(re.findall(r'\(char_u? \*\)dp[a-z_]* *\+', new.replace('(char *)dp', '(char_u *)dp')))
if ptr_in == 0 or ptr_out != 0:
    die('partition', 'interior pointers into a data block: %d in the input, %d in the '
        'output, and this phase leaves none' % (ptr_in, ptr_out))
print('  %-12s %s all 0 in the output; %d interior pointers of the shape '
      '`(char_u *)dp + start` in the input and 0 here; offsetof(DATA_BL) 2 -> 0 and '
      'offsetof(PTR_BL) 1 -> 1'
      % ('partition', ', '.join('%s %s -> 0' % ('the top bit' if n == BIT else n, c)
                                for n, c in gone), ptr_in))

# --- the division between the edit and the sweep, stated ------------------------
# ML_APPEND_MARK is reachable code that can never be true once ml_flush_line()'s
# fallback goes, so no sweep can see it and the EDIT takes it.  ML_DEL_NOPROP is a
# flag with no caller left, which deadenums.py takes -- and it is the only thing the
# sweep finds in this whole phase.
if w(old, 'ML_DEL_NOPROP') != 2 or w(new, 'ML_DEL_NOPROP') != 0:
    die('division', 'ML_DEL_NOPROP is %d in the input and %d in the output, and this '
        'phase leaves it for the sweep to take from 2 to 0'
        % (w(old, 'ML_DEL_NOPROP'), w(new, 'ML_DEL_NOPROP')))
print('  %-12s the edit takes ML_APPEND_MARK, which no sweep can see -- three arms of '
      'a flag whose one caller was ml_flush_line()\'s fallback -- and leaves '
      'ML_DEL_NOPROP, 2 -> 0, which is the whole of what the sweep finds' % 'division')

# --- 3. the representation ------------------------------------------------------
def struct(t, name):
    m = re.search(r'^struct %s\n\{\n(.*?)^\};$' % name, t, re.M | re.S)
    if not m:
        die('record', 'struct %s is not in the output' % name)
    return [l.strip() for l in m.group(1).split('\n') if l.strip()]


rec = struct(new, 'data_line')
blk = struct(new, 'data_block')
if [r.split()[-1] for r in rec] != ['*dl_text;', 'dl_len;', 'dl_marked;']:
    die('record', 'struct data_line is not the three members this phase writes: '
        + ' '.join(rec))
if [b.split()[-1] for b in blk] != ['db_id;', 'db_line_count;', 'db_line[DB_LINE_MAX];']:
    die('record', 'struct data_block is not a header and an array of records: '
        + ' '.join(blk))
if w(new, 'DB_LINE_MAX') < 3:
    die('record', 'DB_LINE_MAX is named %d times and the capacity is read in at '
        'least three places' % w(new, 'DB_LINE_MAX'))
if 'static_assert(sizeof(DATA_BL) <= MEMFILE_PAGE_SIZE' not in new:
    die('record', 'nothing asserts that a leaf still fits the page memfile hands it')
print('  %-12s a leaf is `{%s}` x %d with a two-member header, and the compiler is '
      'what says it fits a page' % ('record', ' '.join(rec), dbmax))

# --- 4. THE LIFETIME RULE -------------------------------------------------------
# Stated as a partition and not as prose: a record's text is written in exactly the
# places that CREATE a record or REPLACE one, and nothing frees it.  That is what
# makes the rule true, and a phase that added a sixth writer or a free would fail
# here rather than in six months.
def enclosing(t, i):
    for m in re.finditer(r'^([a-zA-Z_][a-zA-Z0-9_]*)\(', t[:i], re.M):
        pass
    j = t.rfind('\n}\n', 0, i)
    seg = t[j:i] if j > 0 else t[:i]
    ms = re.findall(r'^([a-zA-Z_][a-zA-Z0-9_]*)\(', seg, re.M)
    return ms[0] if ms else '<file scope>'


writes = {}
for m in re.finditer(r'\.dl_text\s*=[^=]', new):
    fn = enclosing(new, m.start())
    writes[fn] = writes.get(fn, 0) + 1
want = {'ml_open': 1, 'ml_append_int': 3, 'ml_flush_line': 1}
if writes != want:
    die('lifetime', 'a record\'s text is written in %s and the rule this phase pins '
        'says %s' % (writes, want))
m = re.search(r'^ml_flush_line\(buf_T \*buf\)\n\{.*?^\}$', new, re.M | re.S)
if m is None:
    die('lifetime', 'ml_flush_line is not in the output to be read')
if 'vim_free' in m.group(0) and 'ML_ALLOCATED' not in m.group(0):
    die('lifetime', 'ml_flush_line frees something and it is not the ML_ALLOCATED arm')
if 'vim_free(new_line)' in m.group(0):
    die('lifetime', 'ml_flush_line still frees the replacement it just stored, so the '
        'record and b_ml would both own it')
if re.search(r'free\([^)]*db_line', new):
    die('lifetime', "the output frees a record's text, so a pointer ml_get() returned "
        'does not outlive its line')
print('  %-12s a record\'s text is written in exactly %d places -- %s -- and freed in '
      'none, so A POINTER ml_get() RETURNED IS VALID FOR THE LIFETIME OF THE PROCESS, '
      'where before it was invalidated by any insert, delete, flush or split in the '
      'same block'
      % ('lifetime', sum(want.values()),
         ', '.join('%s x%d' % (k, want[k]) for k in sorted(want))))

# --- ml_line_alloced() is NOT simplified, and that is deliberate ----------------
# It looks like an invitation now that every line is a separate allocation, and it is
# not one: del_bytes() shortens ml_line_len IN PLACE when it is true, and nothing
# would write that length back into the record.  ML_LINE_DIRTY still means "a
# replacement is pending", which is a different thing from "the text is allocated".
if 'ML_LINE_DIRTY' not in new or w(new, 'ml_line_alloced') != w(old, 'ml_line_alloced'):
    die('pending', 'ml_line_alloced() moved: it still has to mean "a replacement for '
        'this line is pending" and not "this line\'s text is allocated"')
print('  %-12s ml_line_alloced() and ML_LINE_DIRTY are untouched: del_bytes() shortens '
      'ml_line_len in place under them and nothing would write that length back'
      % 'pending')
PY

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
# Five markers, each a once-per-process host_message() -- the core's own declared way
# to stderr, phase 21's, which adds no name the file does not already have.  Phase
# 40's seventh, MLBIGLINE, has no anchor in the output because the path is gone.
MARK_PY='
import re
import sys

OUT = len(sys.argv) > 3 and sys.argv[3] == "new"
MARKS = [
    ("MLSPLITDATA",
     (r"^        if \(\(hp_new = ml_new_data\(mfp[^\n]*$" if OUT
      else r"^        page_count = \(\(space_needed \+ [^\n]*$"), "before", None),
    ("MLSPLITPTR",  r"^                hp_new = ml_new_ptr\(mfp\);$",      "before", None),
    ("MLSPLITROOT", r"^ *musl_memmove\(\(char \*\)\(pp_new\), [^\n]*$",    "before", None),
    ("MLIDXNZ",     r"^                ip->ip_index = idx;$",              "after",  "idx > 0"),
    ("MLDEEP",      r"^        if \(\(top = ml_add_stack\(buf\)\) < 0\)$", "before",
     "++zprobe_lvl >= 2"),
]
if not OUT:
    MARKS.append(("MLBIGLINE", r"^        page_count = \(\(space_needed \+ [^\n]*$",
                  "after", "page_count > 1"))
t = open(sys.argv[1], errors="surrogateescape").read()
# The depth counter is declared where ml_find_line() STARTS ITS DESCENT.  That used to
# be `bnum = 1;` and zero phase 43 deleted it with block numbers themselves, so the
# anchor is the line beside it that says the same thing about the search rather than
# about the representation: the low end of the range the descent begins with.  (No
# apostrophe below: MARK_PY is a single-quoted shell string.)
decl = re.compile(r"^    low = 1;$", re.M)
if len(decl.findall(t)) != 1:
    sys.exit("the probe cannot declare its depth counter: the file has %d `low = 1;`, "
             "and the descent in ml_find_line has to start somewhere this can name"
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
"""The output reaches at least what the input reached, and the screen corpus reaches
none of it -- which is why this phase is checkable at all."""
import os
import sys

nm, om, ns = sys.argv[1], sys.argv[2], sys.argv[3]
mnew, mold = sys.argv[4].split(), sys.argv[5].split()


def hits(d, marks):
    out = {m: 0 for m in marks}
    for n in sorted(os.listdir(d)):
        t = open(os.path.join(d, n), errors='replace').read()
        for m in marks:
            if m in t:
                out[m] += 1
    return out


new, old, scr = hits(nm, mnew), hits(om, mold), hits(ns, mnew)
if any(v == 0 for v in new.values()):
    sys.exit('the corpus reaches none of: %s -- a corpus that MEANS to reach a split '
             'and does not is the defect zero phase 40 exists to end'
             % ' '.join(k for k, v in new.items() if v == 0))
low = [k for k in mnew if new[k] < old[k]]
if low:
    sys.exit('the output reaches %s less often than the input did (%s against %s), so '
             'this phase narrowed the instrument it depends on'
             % (' '.join(low), ' '.join(str(new[k]) for k in low),
                ' '.join(str(old[k]) for k in low)))
if any(scr.values()):
    sys.exit('%s is reached by the 102 screen cases, so the memline corpus is not what '
             'makes the text layer visible on this boundary'
             % ' '.join(k for k, v in scr.items() if v))
if 'MLBIGLINE' not in old or old['MLBIGLINE'] == 0:
    sys.exit('the input never made a data block more than one page, so the path this '
             'phase removes was not there to remove')
print('  %-12s %s  (the input: %s) and 0 of the 102 screen cases reach any of them; '
      'MLBIGLINE, a data block of more than one page, was %d of 16 on the input and '
      'HAS NO ANCHOR HERE -- a record is a pointer, so the path is gone'
      % ('probe', '  '.join('%s %d' % (k, new[k]) for k in mnew),
         '  '.join('%s %d' % (k, old[k]) for k in mnew), old['MLBIGLINE']))
PY
then
    exit 1
fi

# --- 7. what a record representation costs the arena ------------------------------
# A LINE'S TEXT IS NOW ITS OWN ALLOCATION, so this is the one thing about the phase a
# byte-identical recording cannot say anything about: the editor asks the host for
# memory a different number of times, in different sizes, and with nothing freed
# (zero phase 41) what an arena must hold is a session's TRAFFIC and not its live
# data.  So it is measured, on both sides, with one instrument.
#
# THE NUMBER IS NOT A GUESS AND IT WAS FOUND TWICE.  Written against r39/r40 this
# counter reproduces phase 41's own published high-water for the non-memline corpus
# to the byte -- 1,734,544 -- and phase 41, rebased onto phase 40, independently
# reproduced the memline figure this section measures.  Two instruments written apart
# agreeing to the byte is why the bound below can be this tight.
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
"""The heaviest session's allocation traffic, this phase's output against its input."""
import os
import re
import sys


def peak(d):
    best, who = 0, ''
    for n in sorted(os.listdir(d)):
        t = open(os.path.join(d, n), errors='replace').read()
        for m in re.finditer(r'ZA=(\d+)', t):
            if int(m.group(1)) > best:
                best, who = int(m.group(1)), n
    return best, who


new, nwho = peak(sys.argv[1])
old, owho = peak(sys.argv[2])
if old == 0 or new == 0:
    sys.exit('  %-12s the counter recorded nothing, so this section would be vacuous'
             % 'arena')
# A record representation must not change the ORDER of the traffic, and the bound is
# PROVEN ABLE TO FAIL rather than chosen: ml_alloc_line() over-allocating by one page
# a line -- the blunder this section is for -- asks for 304,354,000 bytes, 1.52 times
# the input, against the real output's 1.007.  A quarter as much again is the line
# between them, and the measured ratio is printed beside it rather than hidden.
if new * 4 > old * 5:
    sys.exit('  %-12s the heaviest session asks for %d bytes where the input asked %d, '
             'a quarter as much again: a per-line allocation is meant to cost the arena '
             'about what the page arena cost it' % ('arena', new, old))
print('  %-12s the heaviest memline session asks the host for %d bytes where the input '
      'asked %d, %+.1f%% (%s either side); nothing is freed, so that is TRAFFIC and not '
      'live data, and it is the one cost of this phase no recording can see'
      % ('arena', new, old, 100.0 * (new - old) / old, nwho if nwho == owho else
         '%s and %s' % (nwho, owho)))
PY
then
    exit 1
fi

# --- 8. the controls -------------------------------------------------------------
# Eleven builds of this phase's own output with ONE thing changed.  Eight must move a
# recording; three must not, and each of those three is a measured statement about
# what the corpus cannot see rather than a control that failed.
CTL_PY='
import os
import re
import sys

MUST = {
  "copy":   (r"^    text = alloc\(\(usize\)len\);$", "    text = line;"),
  "len":    (r"^            dp->db_line\[idx\]\.dl_len = buf->b_ml\.ml_line_len;$", ""),
  "mark":   (r"\.dl_marked = TRUE;$", None),
  "shift":  (r"\(usize\)\(count - idx - 1\) \* sizeof\(DATA_LN\)", None),
  "ins":    (r"&dp->db_line\[db_idx \+ 2\]\), \(char \*\)\(&dp->db_line\[db_idx \+ 1\]\)", None),
  "split":  (r"\(usize\)\(lines_moved\) \* sizeof\(DATA_LN\)", None),
  "idx":    (r"^        buf->b_ml\.ml_line_ptr = dp->db_line\[idx\]\.dl_text;$", None),
  "getlen": (r"^        buf->b_ml\.ml_line_len = dp->db_line\[idx\]\.dl_len;$", None),
}
BLIND = {
  "poison": (r"^            dp->db_line\[idx\]\.dl_text = new_line;$", None),
  "cap":    (r"^    if \(dp->db_line_count < DB_LINE_MAX\)$", None),
  "dbmax":  (r"^enum \{ DB_LINE_MAX = \d+ \};$", "enum { DB_LINE_MAX = 1 };"),
}
REWRITE = {
  "mark":   lambda s: s.replace("TRUE", "FALSE"),
  "shift":  lambda s: s.replace("- 1)", "- 2)"),
  "ins":    lambda s: "&dp->db_line[db_idx + 1]), (char *)(&dp->db_line[db_idx + 2])",
  "split":  lambda s: s.replace("(lines_moved)", "(lines_moved - 1)"),
  "idx":    lambda s: s.replace("[idx]", "[0]"),
  "getlen": lambda s: s.rstrip(";") + " - 1;",
  "poison": lambda s: ("            (void) musl_memset((char *)(dp->db_line[idx].dl_text), "
                       "(0x5a), ((usize)dp->db_line[idx].dl_len)) ;\n" + s),
  "cap":    lambda s: s.replace("<", "<="),
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
    d = os.path.join(out, name)
    os.makedirs(d, exist_ok=True)
    open(os.path.join(d, "zero-vim.c"), "w", errors="surrogateescape").write(t)
    names.append(name)
# the capacity control needs BOTH tests moved or the block-full arm contradicts it
p = os.path.join(out, "cap", "zero-vim.c")
t = open(p, errors="surrogateescape").read()
t = t.replace("if (dp->db_line_count >= DB_LINE_MAX && db_idx",
              "if (dp->db_line_count > DB_LINE_MAX && db_idx", 1)
open(p, "w", errors="surrogateescape").write(t)
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
pids=''
for c in $all_ctl; do
    ( tools/st.sh zcases "$tmp/ctl/$c/zero-vim" "$tmp/ctl/$c/screen" >/dev/null 2>&1
      tools/st.sh zmemline "$tmp/ctl/$c/zero-vim" "$tmp/ctl/$c/memline" >/dev/null 2>&1 ) &
    pids="$pids $!"
done
for p in $pids; do wait "$p" || true; done
if ! python3 - "$tmp/rec1" "$tmp/ctl" "$all_ctl" "$must_ctl" <<'PY'
"""Eight controls that must move a recording and three that are measured not to."""
import filecmp
import os
import sys

base, ctl, every, must = sys.argv[1], sys.argv[2], sys.argv[3].split(), sys.argv[4].split()
WHY = {
    'poison': 'the text a record stops owning, overwritten the moment it is replaced: '
              '0 of 118 is the lifetime rule measured, nothing reads a replaced line '
              'through a pointer it kept',
    'cap': 'the capacity bound off by one: a leaf is 1,040 bytes of a 4,096-byte page, '
           'so the 65th record lands in the page\'s spare room and nothing notices -- '
           'the bound is soft until a block is allocated at its own size',
    'dbmax': 'DB_LINE_MAX = 1, a leaf per line: the fanout is invisible to the corpus '
             'in both directions, which is why the value is chosen by REACHABILITY '
             'and not by a recording',
}
rows = []
for c in every:
    moved = 0
    total = 0
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
             'thing the corpus CANNOT see -- the measurement has changed and the '
             'reason written beside it is now wrong' % ('controls', ' '.join(bad)))
print('  %-12s %d that must move a recording do: %s'
      % ('controls', len(must),
         '  '.join('%s %d/%d' % (c, m, t) for c, m, t in rows if c in must)))
for c, m, t in rows:
    if c not in must:
        print('  %-12s %s 0/%d -- %s' % ('blind', c, t, WHY[c]))
PY
then
    exit 1
fi

# --- 9. the symbols, the cut, and the ordinary checks -----------------------------
gcc -c -O0 -fno-stack-protector -o "$tmp/new.o" "$f" 2>/dev/null
gcc -c -O0 -fno-stack-protector -o "$tmp/old.o" "$state/old.c" 2>/dev/null
nm -u "$tmp/new.o" | awk '{print $2}' | sort > "$tmp/u.new"
nm -u "$tmp/old.o" | awk '{print $2}' | sort > "$tmp/u.old"
if [ -n "$(comm -3 "$tmp/u.old" "$tmp/u.new")" ]; then
    echo "  symbols      this phase frees no libc symbol and needs none, and the set moved:"
    comm -3 "$tmp/u.old" "$tmp/u.new" | sed 's/^/               /'
    exit 1
fi
echo "  symbols      $(grep -c '' "$tmp/u.new") undefined names, the input's set exactly, a comm empty both ways: a per-line allocation asks the host for nothing the editor did not already ask it for"

awk '/^ *# *include / { exit } { a[NR] = $0; if (NF) last = NR } END { for (i = 1; i <= last; i++) print a[i] }' "$f" > "$tmp/cut.c"
awk '/^ *# *include / { exit } { a[NR] = $0; if (NF) last = NR } END { for (i = 1; i <= last; i++) print a[i] }' "$state/old.c" > "$tmp/cut.old.c"
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
