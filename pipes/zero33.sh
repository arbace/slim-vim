#!/bin/sh
# Zero phase 33 -- the terminal table is asked with `+set term={name}`.
#                  See ZERO-GOAL.md, ZERO-PLAN.md 4c.
#
# Usage: pipes/zero33.sh <work-dir>      (run from the repository root)
#
# NO SOURCE CHANGE AT ALL: r33's zero-vim.c is its input's, byte for byte, and this
# phase asserts it first and last.  What changes is one fifth of how every later
# phase is measured.  This is zero phase 3's shape exactly -- the other phase that
# changes no source and replaces an instrument -- and it is here for the same reason:
# a harness that cannot see a phase must be fixed BEFORE the phase, never after.
#
# WHAT WAS WRONG WITH THE OLD QUESTION.  ``ztermcheck`` put the name it was
# asking about in `$TERM`, which is `tools/termcheck.py`'s question and whim's.  But
# whim phase 19 removed the `getenv("TERM")` from `termcapinit()` -- "the terminal is
# what the build says" -- and left a compiled `"xterm-256color"` in its place.  So
# every row of `.reference/zero-baselines/ref-term.txt` read
#
#     TERM='vt100'              -> term=xterm-256color t_Co=256
#
# and the table was as many ways of recording that the environment does nothing.
# MEASURED, and this is the finding that makes the phase rather than the argument:
# a prototype that DELETED eight of the ten built-in terminal names and three of the
# nine capability tables -- 118 lines of terminal description -- passed
# `tools/zcompare.py` against the real baselines DECLARING NOTHING AT ALL.  A phase
# is allowed to declare nothing only when the instrument could have seen it; here it
# could not.
#
# WHAT THE NEW QUESTION IS.  `+set term={name}`, which reaches `did_set_term()`
# rather than `termcapinit()`'s compiled default, and which is `+{command}` -- the
# one facility ZERO-PLAN.md decision 8 promises to survive every phase.  It is NOT
# `-T {term}`: measured, a `-T` harness records nothing but `(none)` against a binary
# with no `-T`, which is precisely the failure the tool's own docstring exists to
# prevent, and `-T` is being abandoned.  `tools/termcheck.py` is imported and
# untouched -- it is named by tools/whimdelta.sh and tools/verify.sh and its bytes
# are in every whim stage's key (ZERO-GOAL.md rule 9).
#
# WHY RE-RECORDING THE BASELINES IS LEGITIMATE, which is the delicate part.
# CLAUDE.md's rule is "never regenerate it from the current binary, which would make
# the comparison self-fulfilling".  The mistake it names is a pipeline re-recording
# from its OWN OUTPUT.  Zero phase 0 does the opposite and pipes/zero0.sh enforces
# it: the baselines come from `whim-vim.c`, the pipeline's immutable input, built
# with WHIM's compile line, recorded three times and required identical.  Nothing
# zero produces is on the recording side.  The same input, the same compile line,
# the same five harnesses; one of the five now asks its question a different way.
# Section 4 below is the independent check that the answer is the same one
# everywhere, which is the property a baseline must have and a self-fulfilling one
# cannot be tested for.  `pipes/zero0.sh` REFUSES a differing baseline set rather
# than overwriting it, so the incantation is
#
#     rm -rf .reference/zero-baselines .cache/r0 && make zero-phase-0
#
# and `rm -rf .cache/r0` alone is not enough.  Measured: without the first path it
# exits 1 naming ref-term.txt; with it, 31 s.
#
# NOTHING HERE IS A NUMBER THAT WAS OBSERVED.  The table has as many rows as
# `tools/termcheck.py` has names; which of them resolve is read out of
# `builtin_terminals[]` in the source the phase was handed; and what a REFUSED name
# leaves the terminal as is measured from the binary, by asking it with no
# `+set term=` at all.  So the rules below stay true of the phase that deletes eight
# of those names, and of anything else that changes the table -- they say what the
# table MEANS, and the recording itself is what says what it currently is.
#
# WHAT THIS PHASE PROVES, in order, each depending on the one before:
#
#   1. the tree is untouched: zero-vim.c is what the phase was handed;
#   2. it builds with the boundary's flags, is still absolutely static, and `main` is
#      still the only external symbol.  Every SOURCE fact is the input's by the sha
#      in 1; these are facts about a binary that was rebuilt;
#   3. THE NEW TABLE MEANS WHAT IT CLAIMS: one row per name asked, every name in
#      `builtin_terminals[]` resolving TO ITSELF, and every other name refused with
#      an `E5NN` AND the terminal left at the compiled default;
#   4. IT IS THE SAME TABLE EVERYWHERE.  `whim-vim.c`, built with whim's own line,
#      records exactly those rows -- and so does every recorded boundary binary, one
#      digest across all of them.  THAT is what makes the re-record safe: the
#      baseline and every phase's recording move together, so no earlier phase's
#      declared delta changes;
#   5. THE INSTRUMENT IS DETERMINISTIC: three whole recordings of that binary, byte
#      for byte identical, stream digests included;
#   6. THE INSTRUMENT CAN FAIL, AND THE ONE IT REPLACES CANNOT.  A scratch copy of
#      the source with ONE row deleted from `builtin_terminals[]` must move EXACTLY
#      that name's row, from resolving to refused -- and must move NOTHING AT ALL
#      when the same names are asked the old way.  A corpus that cannot fail is not
#      evidence, and that pair is the whole of this phase in one measurement;
#   7. the declared delta holds -- NOTHING, and nothing new: tools/zerodelta.sh
#      --phase 33 against the re-recorded .reference/zero-baselines.
set -eu

work=${1:?usage: zero33.sh <work-dir>}
f="$work/zero-vim.c"
base=.reference/zero-baselines

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# --- 0. the baselines must already be the new shape -------------------------
# A tier 3 hit on phase 0 records nothing, and this phase's whole comparison is
# against what phase 0 wrote.  Name the fix here rather than letting section 7 fail
# with a diff and no explanation.  The SHAPE is the test, not the content: a row per
# name termcheck.py asks about, each labelled with the question this phase asks.
if [ -f "$base/ref-term.txt" ]; then
    if ! python3 - "$base/ref-term.txt" <<'PY'
import sys
sys.path.insert(0, 'tools')
import termcheck
rows = open(sys.argv[1]).read().splitlines()
bad = [r for r in rows if not r.startswith(":set term='")]
sys.exit(0 if len(rows) == len(termcheck.TERMS) and not bad else 1)
PY
    then
        echo "  baselines    $base/ref-term.txt is not the table this phase asks for:"
        head -2 "$base/ref-term.txt" | sed 's/^/                 /'
        echo "               Zero phase 0 records it, from whim-vim.c -- the pipeline's"
        echo "               immutable input -- and REFUSES to overwrite a set that"
        echo "               differs, so a changed harness needs both paths removed:"
        echo "                 rm -rf .reference/zero-baselines .cache/r0 && make zero-phase-0"
        exit 1
    fi
fi

# --- 1. the tree is untouched ----------------------------------------------
before=$(sha256sum "$f" | cut -c1-64)

# --- 2. the build, with the boundary's flags -------------------------------
# whim-vim.c takes about as long as zero-vim.c to compile and nothing depends on
# it until section 4, so it is built alongside.  Whim's OWN line, -O0 -static -s:
# these baselines are whim's behaviour and must be measured with whim's flags.
if [ -f whim-vim.c ]; then
    ( gcc -O0 -static -s -o "$tmp/whim-vim" whim-vim.c ) >/dev/null 2>&1 &
    whim_pid=$!
else
    whim_pid=
fi

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
# in section 1 and there is nothing to assert about it.  `main` alone is a fact about
# a binary that was compiled again, and it is a RULE the whole tree states -- nothing
# is global but main().  The undefined count is REPORTED and not pinned: a number
# this phase cannot move is not a check, it is a thing to go stale.
gcc -c -O0 -fno-stack-protector -o "$tmp/new.o" "$f"
nm -u "$tmp/new.o" | awk '{print $2}' | sort > "$tmp/undef"
ext=$(nm --extern-only --defined-only "$tmp/new.o" | awk '{print $NF}' | sort | tr '\n' ' ')
if [ "$ext" != "main " ]; then
    echo "  symbols      the output defines external symbols other than main: $ext"
    exit 1
fi
echo "  symbols      \`main\` is still the only external symbol, over $(grep -c '' "$tmp/undef") undefined"

# --- 3. the new table means what it claims ---------------------------------
tools/st.sh ztermcheck "$bin" "$tmp/term" >/dev/null
if ! python3 - "$f" "$tmp/term" "$bin" > "$tmp/rule" 2>&1 <<'PY'
"""The recording's partition IS builtin_terminals[], and nothing here is a constant.

Three rules, each read out of something other than this file:

  * one row per name tools/termcheck.py asks about, in that order;
  * a name that builtin_terminals[] lists resolves TO ITSELF -- `term=<name>` and no
    error, which is the only thing that says the name reached a table;
  * any other name is refused with an E<digits> code AND leaves the terminal at the
    compiled default -- which is MEASURED from the binary, by asking it with no
    `+set term=` at all, rather than written down as "xterm-256color".
"""
import re
import sys
import tempfile
sys.path.insert(0, 'tools')
import termcheck
# tools/ptyrun.py -- named as a PATH so tools/implhash.sh hashes it into this
# phase's key.  implhash greps for paths and an `import` names a module, so
# without this line an edit to it changes what this phase produces and moves
# no key at all.  See CLAUDE.md on cutil.py and macros.py.  Do not delete it.
import ptyrun

src, rec, binary = sys.argv[1], sys.argv[2], sys.argv[3]

text = open(src, errors='surrogateescape').read()
try:
    i = text.index('builtin_terminals[] = {')
    j = text.index('\n};', i)
except ValueError:
    sys.exit('builtin_terminals[] is not in the source: nothing to check the table against')
resolves = re.findall(r'\{\s*"([^"]*)"', text[i:j])
if not resolves:
    sys.exit('builtin_terminals[] holds no named row: the rule below would be vacuous')

# What a REFUSED name leaves the terminal as, measured and not assumed.
d = tempfile.mkdtemp(prefix='ztermcheck-')
out, _ = ptyrun.session(binary, [], [b':set term? t_Co?\r', b':q!\r'],
                        cwd=d, settle=1.0, env=termcheck.ENV)
default = None
for line in out.decode('utf-8', 'replace').splitlines():
    k = line.find('term=')
    if k >= 0 and not re.search(r'\bE\d+:', line):
        default = line[k:].split()[0]
        break
if not default:
    sys.exit('the binary answered nothing with no +set term= at all: the default is unmeasurable')

rows = open(rec).read().splitlines()
asked = [r[r.index("'") + 1:r.rindex("'")] for r in rows]
if asked != list(termcheck.TERMS):
    sys.exit('the table asks about %r, and tools/termcheck.py names %r'
             % (asked, list(termcheck.TERMS)))

bad = []
for row, name in zip(rows, asked):
    answer = row.split(' -> ', 1)[1]
    fields = answer.split()
    got = next((x for x in fields if x.startswith('term=')), None)
    err = [x for x in fields if re.fullmatch(r'E\d+', x)]
    if name in resolves:
        if err or got != 'term=' + name:
            bad.append('%-22r resolves in builtin_terminals[] and answered %s' % (name, answer))
    else:
        if not err or got != default:
            bad.append('%-22r is in no row of builtin_terminals[] and answered %s, '
                       'where a refusal and %s were due' % (name, answer, default))
if bad:
    sys.exit('the table does not mean what builtin_terminals[] says:\n  '
             + '\n  '.join(bad))

n_ref = len(asked) - len([x for x in asked if x in resolves])
print('%d rows: %d names builtin_terminals[] carries, each resolving to itself, '
      'and %d refused with an E5NN and left at %s'
      % (len(rows), len(rows) - n_ref, n_ref, default))
PY
then
    sed 's/^/  table        /' "$tmp/rule"
    exit 1
fi
sed 's/^/  table        /' "$tmp/rule"

# --- 4. it is the same table everywhere ------------------------------------
# THE CLAIM THAT MAKES THE RE-RECORD SAFE, and it is measured rather than argued.
# The baseline is recorded from whim-vim.c and every later phase's recording is
# compared against it, so what has to be true is not that the baseline is "right"
# but that the new question gets the SAME ANSWER from the pipeline's input and from
# every binary the pipeline has ever produced.  Then the baseline and every
# recording move together, and no earlier phase's declared delta can change.
if [ -n "$whim_pid" ] && wait "$whim_pid"; then
    tools/st.sh ztermcheck "$tmp/whim-vim" "$tmp/term-whim" >/dev/null
    if ! cmp -s "$tmp/term" "$tmp/term-whim"; then
        echo "  same         whim-vim.c -- the pipeline's immutable input, and where the baselines come from -- records a DIFFERENT table:"
        diff "$tmp/term-whim" "$tmp/term" | head -20 | sed 's/^/               /'
        exit 1
    fi
    echo "  same         whim-vim, built -O0 -static -s, records the identical table: the baseline is this table and not a third thing"
else
    echo "  same         no whim-vim.c to build -- the input's own recording not rechecked"
fi

# Every recorded boundary, where there are any.  A scratch root has no .build-zero
# (tools/verifypass.sh links tools/, pipes/ and the baselines and nothing else), so
# this is the strong form of the same statement and runs where the data is.
if [ -d .build-zero ]; then
    mkdir -p "$tmp/bins" "$tmp/rows"
    n=0
    # UP TO THIS PHASE, and not `r*.tar`.  The claim is that the table has not
    # moved between whim-vim and here, which is a statement about the boundaries
    # that existed when this phase ran; a later phase is entitled to move the
    # table, and zero phase 38 does -- it removes eight of the ten names.  An
    # unbounded glob turned that entitlement into this check failing, which is a
    # phase asserting something about its own future.  `make zero-verify` never
    # saw it (a verify scratch root has no .build-zero), so it would have struck
    # only a sequential `make zero-repass` in the repository root.
    self=$(basename "$0" .sh | sed 's/^zero//')
    i=-1
    while [ "$((i += 1))" -le "$self" ]; do
        t=.build-zero/r$i.tar
        [ -f "$t" ] || continue
        r=r$i
        tar -xOf "$t" ./zero-vim > "$tmp/bins/$r" 2>/dev/null \
            || tar -xOf "$t" zero-vim > "$tmp/bins/$r" 2>/dev/null || continue
        [ -s "$tmp/bins/$r" ] || continue
        chmod +x "$tmp/bins/$r"
        tools/st.sh ztermcheck "$tmp/bins/$r" "$tmp/rows/$r" >/dev/null &
        n=$((n + 1))
        if [ $((n % 8)) = 0 ]; then wait; fi
    done
    wait
    if [ "$n" = 0 ]; then
        echo "  boundaries   .build-zero holds no boundary binary -- the table not rechecked across the pipeline"
    else
        bad=0
        for r in "$tmp/rows"/*; do
            if ! cmp -s "$tmp/term" "$r"; then
                echo "  boundaries   $(basename "$r") records a different table:"
                diff "$r" "$tmp/term" | head -6 | sed 's/^/               /'
                bad=1
            fi
        done
        if [ "$bad" != 0 ]; then
            echo "               The baseline and the recordings do NOT move together, and re-recording would change an earlier phase's declared delta."
            exit 1
        fi
        echo "  boundaries   all $n recorded boundary binaries up to r$self record the SAME table as whim-vim and as this one, one digest across every one of them"
    fi
else
    echo "  boundaries   no .build-zero here -- the pipeline-wide check runs where the tars are"
fi

# --- 5. the instrument is deterministic ------------------------------------
# The whole recording, not just the part that moved: the stream digests are inside
# it, so a redraw that drew the same result differently would fail here.
for r in 1 2 3; do
    tools/zrecord.sh "$bin" "$f" "$tmp/run$r"
    if [ "$r" != 1 ] && ! diff -r "$tmp/run1" "$tmp/run$r" >/dev/null; then
        echo "  instrument   run $r differs from run 1 -- not deterministic, not an instrument:"
        diff -rq "$tmp/run1" "$tmp/run$r" | head -10 | sed 's/^/               /'
        exit 1
    fi
done
cases=$(ls "$tmp/run1/screen" | grep -c '')
cmds=$(grep -c '^=== ' "$tmp/run1/ref-excmds.txt")
argvs=$(grep -c '^=== ' "$tmp/run1/ref-argv.txt")
ptys=$(grep -c '^=== ' "$tmp/run1/ref-pty.txt")
terms=$(grep -c '' "$tmp/run1/ref-term.txt")
echo "  instrument   $cases cases, $cmds commands, $argvs command lines, $ptys pty scenarios, $terms terminals: 3 identical runs, digests included"

# --- 6. the instrument can fail, and the one it replaces cannot -------------
# ONE ROW of builtin_terminals[] deleted -- whichever name the source's own table
# lists LAST before its terminator, so the break is derived and not a name written
# here.  The new question must see exactly that row move, from resolving to refused;
# the old question, asked of the same two binaries, must see NOTHING AT ALL.  That
# pair is this phase's entire justification, and it is the reason the break is a
# terminal row and not phase 3's do_addsub().
gone=$(python3 - "$f" "$tmp/broken.c" <<'PY'
import re
import sys
src, dst = sys.argv[1], sys.argv[2]
t = open(src, errors='surrogateescape').read()
i = t.index('builtin_terminals[] = {')
j = t.index('\n};', i)
rows = [r for r in t[i:j].split('\n') if re.match(r'\s*\{\s*"', r)]
if not rows:
    sys.exit('builtin_terminals[] has no named row to delete: the break cannot be made')
row = rows[-1]
if t.count(row + '\n') != 1:
    sys.exit('%r is not one line of the file, so deleting it would delete more' % row)
open(dst, 'w', errors='surrogateescape').write(t.replace(row + '\n', ''))
print(re.match(r'\s*\{\s*"([^"]*)"', row).group(1))
PY
)
mkdir -p "$tmp/broken"
mv "$tmp/broken.c" "$tmp/broken/zero-vim.c"
cp "$work/Makefile" "$tmp/broken/Makefile"
if ! make -C "$tmp/broken" >/dev/null 2>&1; then
    echo "  ablefail     the patched copy did not build -- the break is wrong, not the corpus"
    exit 1
fi
tools/st.sh ztermcheck "$tmp/broken/zero-vim" "$tmp/broken-term" >/dev/null
if ! python3 - "$tmp/term" "$tmp/broken-term" "$gone" > "$tmp/moved" 2>&1 <<'PY'
"""Exactly the deleted name's row moved, and it moved from resolving to refused."""
import re
import sys
was, now, gone = (open(sys.argv[1]).read().splitlines(),
                  open(sys.argv[2]).read().splitlines(), sys.argv[3])
if len(was) != len(now):
    sys.exit('the broken build recorded %d rows where the input recorded %d' % (len(now), len(was)))
moved = [(a, b) for a, b in zip(was, now) if a != b]
if len(moved) != 1:
    sys.exit('deleting the %r row moved %d rows, and exactly 1 was due' % (gone, len(moved)))
a, b = moved[0]
name = a[a.index("'") + 1:a.rindex("'")]
if name != gone:
    sys.exit('deleting the %r row moved the %r row instead' % (gone, name))
before, after = a.split(' -> ', 1)[1], b.split(' -> ', 1)[1]
if 'term=' + gone not in before.split() or not re.search(r'\bE\d+\b', after):
    sys.exit('the %r row went %s -> %s, where resolving -> refused was due' % (gone, before, after))
print('deleting the %r row from builtin_terminals[] moves EXACTLY 1 of %d rows here, '
      '%s -> %s' % (gone, len(was), before, after))
PY
then
    sed 's/^/  ablefail     /' "$tmp/moved"
    diff "$tmp/term" "$tmp/broken-term" | head -10 | sed 's/^/               /'
    exit 1
fi

# The question this phase replaces, written out here because it no longer exists in
# tools/: the name in $TERM, no file argument, and the same scrape.  It is the four
# lines that were `ztermcheck`'s ask() up to this phase.
python3 - "$bin" "$tmp/broken/zero-vim" "$tmp/old-in" "$tmp/old-broken" <<'PY'
import concurrent.futures, shutil, sys, tempfile
sys.path.insert(0, 'tools')
import termcheck, ptyrun


def old(binary, t):
    """ztermcheck's ask() as it stood before zero phase 33."""
    d = tempfile.mkdtemp(prefix='ztermcheck-')
    try:
        text, _ = ptyrun.session(binary, [], [b':set term? t_Co?\r', b':q!\r'],
                                 term=t, cwd=d, settle=1.0, env=termcheck.ENV)
    finally:
        shutil.rmtree(d, ignore_errors=True)
    got = []
    for x in text.decode('utf-8', 'replace').splitlines():
        for kw in ('term=', 't_Co='):
            i = x.find(kw)
            if i >= 0:
                got.append(x[i:].split()[0])
    return 'TERM=%-20s -> %s' % (repr(t), ' '.join(got) or '(none)')


for binary, out in ((sys.argv[1], sys.argv[3]), (sys.argv[2], sys.argv[4])):
    with concurrent.futures.ThreadPoolExecutor(max_workers=len(termcheck.TERMS)) as ex:
        rows = list(ex.map(lambda t: old(binary, t), termcheck.TERMS))
    open(out, 'w').write('\n'.join(rows) + '\n')
PY
if grep -q '(none)' "$tmp/old-in"; then
    echo "  ablefail     the old question recorded (none) on an unbroken binary -- the control is broken, not the editor"
    exit 1
fi
if ! cmp -s "$tmp/old-in" "$tmp/old-broken"; then
    echo "  ablefail     the OLD question saw the deleted row, which contradicts the reason for this phase:"
    diff "$tmp/old-in" "$tmp/old-broken" | head -10 | sed 's/^/               /'
    exit 1
fi
distinct=$(sed 's/.*-> //' "$tmp/old-in" | sort -u | grep -c '')
printf '  %-12s %s, and 0 of %s under the question this replaces -- whose %s rows carry %s distinct answer between them\n' \
    "ablefail" "$(cat "$tmp/moved")" "$(grep -c '' "$tmp/old-in")" "$(grep -c '' "$tmp/old-in")" "$distinct"

# --- 7. the declared delta, against the input's own behaviour ---------------
tools/zerodelta.sh "$bin" "$f" --phase 33

# --- 1, concluded: nothing in the tree moved -------------------------------
after=$(sha256sum "$f" | cut -c1-64)
if [ "$before" != "$after" ]; then
    echo "  source       zero-vim.c was modified by a phase that must not modify it"
    exit 1
fi
echo "  source       zero-vim.c unchanged, $(grep -c '' "$f") lines: r33 is its input's tree, and only the instrument moved"
