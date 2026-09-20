#!/bin/sh
# Zero phase 34, the check -- the core stops reallocating.
# See pipes/zero34-edit.sh, and ZERO-PLAN.md 4c.
#
# Usage: pipes/zero34-check.sh <work-dir> <state-dir>    (run from the repository root)
#
# Runs after pipes/zero34-edit.sh and the sweep tools/phaserun.sh runs between them, and
# reads nothing from the edit's shell -- only the work tree and the state directory.
# What the edit left there is `old.c`, the source this phase was HANDED, and `old`, that
# source built with SOURCE_DATE_EPOCH=0 and the boundary's own flags.
#
# WHAT IS CLAIMED, in seven parts:
#
#   ARITHMETIC  computed FROM THE INPUT: `realloc` 3 -> 0 above the boundary and 1 -> 1
#               below it, the libc prototype block one line shorter than the input's
#               (counted, never stated -- phases 31 and 35 also shrink it), the file
#               +10 lines, the directives unmoved relative to the text, and
#               tools/canon.sh a NO-OP.
#   THE HARNESS THE PHASE'S REAL EVIDENCE, because every way this rewrite can be wrong
#               is a memory bug and no screen recording can see one.  ga_grow_inner(),
#               musl_memcpy(), musl_memset(), garray_T and get_keystroke's extension
#               block are EXTRACTED AT RUN TIME from the input source and from the
#               output, wrapped in the same driver, built with AddressSanitizer and
#               driven from empty through eight doublings, through a failed
#               allocation, and through the 100-byte extension.  The two transcripts
#               must be IDENTICAL and neither may report a finding.
#   CONTROLS    seven, each a way the rewrite could be wrong, SIX OF WHICH MOVE and one
#               of which does not -- which is reported rather than hidden (zero phases
#               22 and 31 set that precedent).  Each mover is required to give its own
#               named sanitizer finding, so "the harness noticed" is not one bucket.
#   THE GUARD   what `if (gap->ga_data != nullptr)` actually buys, measured in both
#               directions.  It changes NO behaviour here -- a null `ga_data` implies
#               `ga_maxlen == 0` implies `old_len == 0`, and musl_memcpy's `for (; n;
#               n--)` never dereferences -- and the check says so.  What it buys is on
#               the page: a driver whose musl_memcpy announces a null source reports 0
#               from the output and 8 from the unguarded control.
#   SYMBOLS     `nm -u` is THE SAME SET, as a `comm` empty in BOTH directions, and
#               `realloc` is STILL IN IT.  A reader expects a phase that removes a call
#               to move the count; this one does not, because adjust_types() is below
#               the boundary and still calls it.  Phases 14, 15 and 21 each require
#               `realloc` to be undefined and all three still pass.
#   THE CUT     `make editor.c`'s rule run on both sides: 0 directives, 0 errors under
#               `-fsyntax-only`, and the whole warning set -- the core -> host boundary
#               -- IDENTICAL to the input's, compared name by name at run time.
#   BEHAVIOUR   the declared delta is NOTHING AT ALL, and here that is STRONG evidence
#               and not weak.  ga_grow_inner is on the path of every growarray: an
#               instrumented build of the INPUT marks 2,739 first grows and 1,550
#               later ones in 104 of the 106 records, and the IDENTICAL instrument on
#               the OUTPUT marks the same 2,739 and 1,550.  Two full recordings are
#               byte-identical, and a build whose copy length is 0 moves 102 of the 102
#               screen cases.
#
# THE SHRINK QUESTION IS ANSWERED AND NOT ASSUMED.  `musl_memcpy` copies the OLD size at
# both sites, which is wrong if either site can ever ask for less than it has.  Neither
# can: the same instrument marks a shrink at 0 of 106 records, ga_grow_inner's only
# caller enters it only when `ga_maxlen - ga_len < n`, and get_keystroke adds 100
# immediately above the call.  The input's own `musl_memset(pp + old_len, 0, new_len -
# old_len)` already relied on it -- the length is unsigned -- so the property is the
# input's and not this phase's to establish.
#
# WHY THE UNIT HARNESS AND NOT A PROBE ON THE EDITOR.  get_keystroke's extension is
# UNREACHABLE in a recording, and that was measured rather than guessed: an instrumented
# build of the input marks each of the five `continue` paths in its loop at 0 of 106
# records, so `len` never exceeds one ui_inchar() and `maxlen` never falls below 10.  A
# pty session feeding a partial escape sequence sixty times does not reach it either.
# Extracting the block is the only instrument that can drive it, and it drives the
# input's version and the output's through the same driver.
set -eu

work=${1:?usage: zero34-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero34-check.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"
before_lines=$(cat "$state/input-lines")

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")

# The product build and the two instrumented full builds are written first and waited
# for below: they are seconds of wall time the assertions can be spending instead.
# The product build's result is a FLAG FILE and not a `wait` on its pid: section 3 runs
# eleven driver builds with a bare `wait`, which reaps every background job including
# this one, and a later `wait $pid_new` would then fail for having nothing to wait for
# -- measured, and it reported the build as broken when the build was fine.
# shellcheck disable=SC2086
( SOURCE_DATE_EPOCH=0 gcc $cflags $ldflags -o "$tmp/new" "$f" && : > "$tmp/new.ok" ) &
cp "$f" "$tmp/canon.c"
( tools/canon.sh "$tmp/canon.c" >"$tmp/canon.log" 2>&1 ) &
pid_canon=$!

# --- 1. the source, as arithmetic on the input ------------------------------------------
python3 - "$f" "$state/old.c" "$before_lines" <<'PY'
import re
import sys

TAG = 'realloc'
new = open(sys.argv[1], errors='surrogateescape').read()
old = open(sys.argv[2], errors='surrogateescape').read()
before_lines = int(sys.argv[3])
fail = []

O, N = old.split('\n'), new.split('\n')
if len(O) - 1 != before_lines:
    fail.append('the state directory says the edit was handed %d lines and old.c has %d'
                % (before_lines, len(O) - 1))


def split(L):
    d = [i for i, l in enumerate(L) if re.match(r'^ *#', l)]
    if not d or d != list(range(d[0], d[0] + len(d))):
        sys.exit('  %-12s the directives are not one consecutive block, so there is no '
                 'boundary and nothing below distinguishes a core call from a host one'
                 % TAG)
    return d, '\n'.join(L[:d[0]]), '\n'.join(L[d[0]:])


od, ocore, ohost = split(O)
nd, ncore, nhost = split(N)

# WHAT WENT AND WHAT DID NOT.  `\brealloc\b` does not match inside `realloc_cmdbuff`.
oc, oh = len(re.findall(r'\brealloc\b', ocore)), len(re.findall(r'\brealloc\b', ohost))
nc, nh = len(re.findall(r'\brealloc\b', ncore)), len(re.findall(r'\brealloc\b', nhost))
if (oc, oh) != (3, 1):
    fail.append('the input has %d `realloc` in the core and %d in the host, where 3 and '
                '1 were expected' % (oc, oh))
if nc != 0:
    fail.append('`realloc` still occurs %d times in the core, and the phase\'s whole '
                'product is that it is 0' % nc)
if nh != oh:
    fail.append('the host\'s `realloc` went from %d to %d: adjust_types() is below the '
                'boundary, is the HOST\'s, and is the reason the symbol does not leave'
                % (oh, nh))
if 'adjust_types' not in nhost:
    fail.append('adjust_types() is not in the host part of the output, and it is what '
                'the surviving `realloc` belongs to')

# THE PROTOTYPE BLOCK, counted from the input.  Phases 31 and 35 also shrink it, so the
# number is never written here -- only the difference, which is one.  A plain libc
# prototype is the ONLY file-scope declaration in the core that is not `static`, which is
# what makes this a partition and not a guess.
def protos(text):
    return [l for l in text.split('\n')
            if re.match(r'^(?:void \*|void |long |int )[a-z_]+\(', l) and l.endswith(';')
            and not l.startswith('static')]


op, np = protos(ocore), protos(ncore)
if len(op) - len(np) != 1:
    fail.append('the core\'s plain libc prototype block is %d lines and the input\'s was '
                '%d, a difference of %d where 1 was expected.  Input: %s.  Output: %s'
                % (len(np), len(op), len(op) - len(np), ' '.join(op), ' '.join(np)))
if 'void *realloc(void *p, usize n);' in ncore:
    fail.append('the core still declares realloc')
lost = sorted(set(op) - set(np))
if lost != ['void *realloc(void *p, usize n);']:
    fail.append('the prototype block lost [%s] and not realloc\'s line alone'
                % ' / '.join(lost))
if set(np) - set(op):
    fail.append('the prototype block GAINED %s' % ' / '.join(sorted(set(np) - set(op))))

# THE TWO REWRITES, read back off the output, each with the property that makes it
# faithful rather than merely similar.
GA = """    new_len = (usize)gap->ga_itemsize * (gap->ga_len + n);
    old_len = (usize)gap->ga_itemsize * gap->ga_maxlen;
    pp = malloc(new_len);
    if (pp == nullptr)
    {
        return FAIL;
    }
    if (gap->ga_data != nullptr)
    {
        musl_memcpy(pp, gap->ga_data, old_len);
        free(gap->ga_data);
    }
     musl_memset((pp + old_len), (0), (new_len - old_len)) ;
"""
KS = """            char_u  *t_buf = buf;
            int     t_buflen = buflen;

            buflen += 100;
            buf = malloc(buflen);
            if (buf == nullptr)
            {
                vim_free(t_buf);
            }
            else
            {
                musl_memcpy(buf, t_buf, t_buflen);
                free(t_buf);
            }
"""
if new.count(GA) != 1:
    fail.append('ga_grow_inner\'s rewrite is not in the output exactly once, with the '
                'copy and the free guarded by `ga_data != nullptr` (trap 1), the '
                '`return FAIL` above anything being freed (trap 2) and the tail-zeroing '
                'statement unmoved below the copy (trap 3)')
if new.count(KS) != 1:
    fail.append('get_keystroke\'s rewrite is not in the output exactly once, with the '
                'old size saved as `t_buflen` beside `t_buf`, `vim_free(t_buf)` left '
                'exactly where the input had it, and the success-path free being '
                '`free()` -- vim_free declines while really_exiting and realloc did not')
if 'vim_free(t_buf);' not in new or new.count('vim_free(t_buf);') != 1:
    fail.append('the input\'s own `vim_free(t_buf)` failure path is not in the output '
                'exactly once')

# The line arithmetic and the boundary.
added = 5 + 6 - 1
if len(N) - len(O) != added:
    fail.append('the output is %d lines and the input was %d, a difference of %d where '
                '%d was expected -- 5 at ga_grow_inner, 6 at get_keystroke and -1 for '
                'the prototype' % (len(N) - 1, len(O) - 1, len(N) - len(O), added))
if len(nd) != len(od):
    fail.append('the output has %d directives and the input %d' % (len(nd), len(od)))
elif [N[i] for i in nd] != [O[i] for i in od]:
    fail.append('the directives are not the ones the input had')
elif nd[0] - od[0] != len(N) - len(O):
    fail.append('the boundary moved by %d lines and the file by %d: every line this '
                'phase touches is above the first `#include`'
                % (nd[0] - od[0], len(N) - len(O)))


def runs(text):
    L = text.split('\n')
    return sum(1 for i in range(1, len(L)) if L[i] == '' and L[i - 1] == '')


if runs(new) != runs(old):
    fail.append('the edit and the sweep left %d runs of two blank lines where there '
                'were %d' % (runs(new), runs(old)))

if fail:
    for line in fail:
        print('  %-12s %s' % (TAG, line))
    sys.exit(1)
print('  %-12s `realloc` is 3 -> 0 above the boundary and %d -> %d below it.  THE '
      'SYMBOL DOES NOT LEAVE and this phase does not claim it does: adjust_types(), in '
      'the formatter island phase 27 moved down, is the host\'s and still calls it'
      % (TAG, oh, nh))
print('  %-12s the core\'s plain libc prototype block is %d lines where the input\'s was '
      '%d, and the one it lost is `void *realloc(void *p, usize n);` -- counted from the '
      'input, never stated here, because phases 31 and 35 shrink the same block'
      % (TAG, len(np), len(op)))
print('  %-12s both rewrites are in the output exactly once: ga_grow_inner with the copy '
      'and the free GUARDED by `ga_data != nullptr`, its `return FAIL` above anything '
      'being freed, and its tail-zeroing statement unmoved below the copy; '
      'get_keystroke with the old size saved as `t_buflen` beside `t_buf`, the '
      '`vim_free(t_buf)` failure path untouched, and `free()` on the success path'
      % TAG)
print('  %-12s %d lines -> %d, exactly the %d this phase adds, the %d directives are the '
      'input\'s own and the boundary moved by exactly the lines the file gained.  '
      'Blank-line runs unmoved at %d'
      % (TAG, len(O) - 1, len(N) - 1, added, len(nd), runs(new)))
PY

# --- 2. canon.sh ---------------------------------------------------------------------------
wait $pid_canon || { echo "  realloc      tools/canon.sh failed on the output:"; sed -n '1,10p' "$tmp/canon.log"; exit 1; }
if ! cmp -s "$f" "$tmp/canon.c"; then
    echo "  realloc      tools/canon.sh is not a no-op on the output -- the new lines are not written the way this file writes everything else:"
    diff "$f" "$tmp/canon.c" | sed -n '1,12p'
    exit 1
fi
echo "  realloc      tools/canon.sh is a NO-OP on the output: the eleven new lines are written the way this file writes everything else"

tools/st.sh orphanopts "$f"
tools/st.sh nvidx "$f"
tools/st.sh zhostonly "$f"

# --- 3. THE UNIT HARNESS: the two functions, extracted from both sources ---------------------
# The failure modes of this rewrite are a leak, a double free, a use after free and an
# overread, and NOT ONE of them shows in a screen recording -- an overread of a heap
# block whose bytes are then overwritten is invisible even in principle.  So the two
# rewritten sites are extracted from the input source and from the output, dropped into
# the same driver, and run under AddressSanitizer.
cat > "$tmp/mkdriver.py" <<'PYEOF'
import sys


def fn(t, head, rtype):
    i = t.index('\n' + head)
    j = t.index('\n{\n', i)
    d, k = 0, j + 1
    while True:
        if t[k] == '{':
            d += 1
        elif t[k] == '}':
            d -= 1
            if d == 0:
                break
        k += 1
    return rtype + '\n' + t[i + 1:k + 2]


def block(t, head, need):
    i = t.index(head)
    j = t.index('{', i)
    d, k = 0, j
    while True:
        if t[k] == '{':
            d += 1
        elif t[k] == '}':
            d -= 1
            if d == 0:
                break
        k += 1
    b = t[i:k + 1]
    if need not in b:
        sys.exit('the extracted block does not hold %r' % need)
    return b


src = open(sys.argv[1], errors='surrogateescape').read()
out = sys.argv[2]
nullwatch = len(sys.argv) > 3 and sys.argv[3] == '--nullwatch'

ga = fn(src, 'ga_grow_inner(garray_T *gap, int n)', '    static int')
mcpy = fn(src, 'musl_memcpy(void *dest, const void *src, usize n)', '    static void *')
mset = fn(src, 'musl_memset(void *dest, int c, usize n)', '    static void *')
ks = block(src, '        else if (maxlen < 10)', 'buflen += 100;')
gt = src[src.index('typedef struct growarray'):
         src.index('} garray_T;') + len('} garray_T;')]
if nullwatch:
    # The ONE line that turns the driver into an instrument for trap 1: it says when a
    # null reaches the copy, which is what the guard exists to prevent and what no
    # sanitizer reports, musl_memcpy being a plain loop and not libc's memcpy.
    anchor = '    const unsigned char *s = src;\n'
    if mcpy.count(anchor) != 1:
        sys.exit('musl_memcpy does not have its `const unsigned char *s = src;` line')
    mcpy = mcpy.replace(
        anchor, anchor + '    if (src == nullptr) { printf("MEMCPY-NULL n=%d\\n", (int)n); }\n', 1)

HEAD = r'''
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

typedef unsigned char char_u;
typedef typeof(sizeof(0)) usize;
enum { OK = 1 };
enum { FAIL = 0 };
static void *musl_memcpy(void *dest, const void *src, usize n);
static void *musl_memset(void *dest, int c, usize n);
static int ga_grow_inner(garray_T *gap, int n);
static int n_vim_free = 0;
static void vim_free(void *x) { if (x != nullptr) { ++n_vim_free; free(x); } }
'''

TAIL = r'''
static void hexline(const char *tag, const unsigned char *p, int n)
{
    int i;
    printf("%s", tag);
    for (i = 0; i < n; i++) { printf(" %02x", p[i]); }
    printf("\n");
}

/* A -- from EMPTY through eight doublings, the live region written after every grow and
   read back before the next.  Step 1 is the null-ga_data case, which on a full
   recording of the editor is 2,739 of ga_grow_inner's 4,289 calls.  Reading the live
   region back is the ONLY thing that says the copy happened; checking the tail is
   zero is the only thing that says the memset still runs after it. */
static void test_grow(void)
{
    garray_T ga = { 0, 0, 0, 0, nullptr };
    int step, i, r;
    unsigned char *d;

    ga.ga_itemsize = 1;
    ga.ga_growsize = 4;
    printf("A.start data=%s maxlen=%d\n", ga.ga_data == nullptr ? "null" : "set", ga.ga_maxlen);
    for (step = 1; step <= 8; step++)
    {
        int want = ga.ga_len + 3;
        r = ga_grow_inner(&ga, want - ga.ga_len);
        d = ga.ga_data;
        printf("A.%d r=%d len=%d maxlen=%d data=%s\n", step, r, ga.ga_len, ga.ga_maxlen,
               d == nullptr ? "null" : "set");
        if (r != OK) { continue; }
        for (i = ga.ga_len; i < ga.ga_maxlen; i++)
        {
            if (d[i] != 0) { printf("A.%d TAIL-NOT-ZERO at %d = %02x\n", step, i, d[i]); }
        }
        for (i = 0; i < ga.ga_len; i++)
        {
            if (d[i] != (unsigned char)(0xA0 + i))
            { printf("A.%d LOST at %d = %02x want %02x\n", step, i, d[i], (unsigned char)(0xA0 + i)); }
        }
        ga.ga_len = want;
        for (i = 0; i < ga.ga_len; i++) { d[i] = (unsigned char)(0xA0 + i); }
        hexline("A.live", d, ga.ga_len);
    }
    free(ga.ga_data);
}

/* A2 -- six INDEPENDENT growarrays grown once each, so the null-ga_data path is taken
   seven times in the run and the --nullwatch driver has something to count. */
static void test_fresh(void)
{
    int k, r;
    for (k = 1; k <= 6; k++)
    {
        garray_T ga = { 0, 0, 0, 0, nullptr };
        ga.ga_itemsize = k;
        ga.ga_growsize = k + 1;
        r = ga_grow_inner(&ga, 2);
        printf("A2.%d r=%d maxlen=%d itemsize=%d\n", k, r, ga.ga_maxlen, ga.ga_itemsize);
        free(ga.ga_data);
    }
}

/* B -- THE FAILURE PATH.  realloc leaves the old block valid and allocated, so
   ga_grow_inner must return FAIL with ga_data untouched and NOTHING freed.  The
   allocation is made to fail by asking for more than the sanitizer's allocator will
   give, rather than by interposing anything.  The grow that follows is what turns a
   premature free into a use-after-free the harness can name. */
static void test_grow_fail(void)
{
    garray_T ga = { 0, 0, 0, 0, nullptr };
    int i, r;
    unsigned char *before;

    ga.ga_itemsize = 1;
    ga.ga_growsize = 4;
    r = ga_grow_inner(&ga, 16);
    printf("B.setup r=%d\n", r);
    ga.ga_len = 16;
    for (i = 0; i < 16; i++) { ((unsigned char *)ga.ga_data)[i] = (unsigned char)(0x50 + i); }
    before = ga.ga_data;

    r = ga_grow_inner(&ga, 600 * 1024 * 1024);
    printf("B.fail r=%d same=%d maxlen=%d\n", r, ga.ga_data == before, ga.ga_maxlen);
    hexline("B.after", ga.ga_data, 16);
    r = ga_grow_inner(&ga, 8);
    printf("B.again r=%d\n", r);
    hexline("B.live", ga.ga_data, 16);
    free(ga.ga_data);
}

/* C -- get_keystroke's 100-byte extension, driven directly.  It is UNREACHABLE in a
   recording: an instrumented build of the input marks each of the five `continue` paths
   in its loop at 0 of 106 records, so `len` never exceeds one ui_inchar() and `maxlen`
   never falls below 10.  This block is the only instrument that can see it. */
static void test_keystroke(void)
{
    char_u *buf;
    int buflen = 150;
    int len = 115;
    int maxlen;
    int i;

    n_vim_free = 0;
    buf = malloc(buflen);
    for (i = 0; i < buflen; i++) { buf[i] = (char_u)(i * 7 + 1); }
    maxlen = (buflen - 6 - len) / 3;
    printf("C.before buflen=%d len=%d maxlen=%d\n", buflen, len, maxlen);
    if (buf == nullptr)
    {
        printf("C.unreachable\n");
    }
KSBLOCK
    printf("C.after buflen=%d maxlen=%d buf=%s vim_frees=%d\n", buflen, maxlen,
           buf == nullptr ? "null" : "set", n_vim_free);
    if (buf != nullptr)
    {
        for (i = 0; i < len; i++)
        {
            if (buf[i] != (char_u)(i * 7 + 1)) { printf("C LOST at %d\n", i); }
        }
        hexline("C.live", buf, 16);
        free(buf);
    }
}

int main(void)
{
    setbuf(stdout, nullptr);
    test_grow();
    test_fresh();
    test_grow_fail();
    test_keystroke();
    return 0;
}
'''

open(out, 'w').write(gt + HEAD + '\n' + ga + '\n' + mcpy + '\n' + mset + '\n'
                     + TAIL.replace('KSBLOCK', ks))
PYEOF

# THE SEVEN CONTROLS.  Each is one way the rewrite could be wrong, applied to the
# OUTPUT, and each is named by what it breaks rather than by a number.
python3 - "$f" "$tmp" <<'PY'
import sys

t = open(sys.argv[1], errors='surrogateescape').read()
out = sys.argv[2]
C = {}
C['c_copynew'] = ('musl_memcpy(pp, gap->ga_data, old_len);',
                  'musl_memcpy(pp, gap->ga_data, new_len);')
C['c_nocopy'] = ('musl_memcpy(pp, gap->ga_data, old_len);',
                 'musl_memcpy(pp, gap->ga_data, 0);')
C['c_freefail'] = ("""    pp = malloc(new_len);
    if (pp == nullptr)
    {
        return FAIL;
    }""", """    pp = malloc(new_len);
    if (pp == nullptr)
    {
        free(gap->ga_data);
        return FAIL;
    }""")
C['c_noguard'] = ("""    if (gap->ga_data != nullptr)
    {
        musl_memcpy(pp, gap->ga_data, old_len);
        free(gap->ga_data);
    }""", """    musl_memcpy(pp, gap->ga_data, old_len);
    free(gap->ga_data);""")
C['c_keycopy'] = ('musl_memcpy(buf, t_buf, t_buflen);',
                  'musl_memcpy(buf, t_buf, buflen);')
C['c_keynofree'] = ("""                musl_memcpy(buf, t_buf, t_buflen);
                free(t_buf);""", """                musl_memcpy(buf, t_buf, t_buflen);""")
C['c_keyfreeboth'] = ("""            if (buf == nullptr)
            {
                vim_free(t_buf);
            }
            else
            {
                musl_memcpy(buf, t_buf, t_buflen);
                free(t_buf);
            }""", """            vim_free(t_buf);
            if (buf != nullptr)
            {
                musl_memcpy(buf, t_buf, t_buflen);
            }""")
for name, (a, b) in C.items():
    if t.count(a) != 1:
        sys.exit('  %-12s the control %s has no unique anchor in the output' % ('realloc', name))
    open('%s/%s.c' % (out, name), 'w', errors='surrogateescape').write(t.replace(a, b, 1))
print('  %-12s seven controls written on the output: c_copynew copies new_len where the '
      'block is old_len, c_nocopy copies nothing, c_freefail frees the old block on the '
      'failure path where the original does not, c_noguard drops the `ga_data != '
      'nullptr` guard, c_keycopy copies buflen where the block is t_buflen, c_keynofree '
      'leaves the old buffer allocated, c_keyfreeboth frees it on both paths' % 'realloc')
PY

ASANOPT='allocator_may_return_null=1:max_allocation_size_mb=256:detect_leaks=1'
for v in old new c_copynew c_nocopy c_freefail c_noguard c_keycopy c_keynofree c_keyfreeboth; do
    case $v in old) src=$state/old.c;; new) src=$f;; *) src=$tmp/$v.c;; esac
    python3 "$tmp/mkdriver.py" "$src" "$tmp/d.$v.c"
    ( gcc -O0 -g -fsanitize=address -o "$tmp/d.$v" "$tmp/d.$v.c" 2>"$tmp/dbuild.$v" ) &
done
python3 "$tmp/mkdriver.py" "$f" "$tmp/d.nw_new.c" --nullwatch
python3 "$tmp/mkdriver.py" "$tmp/c_noguard.c" "$tmp/d.nw_noguard.c" --nullwatch
for v in nw_new nw_noguard; do
    ( gcc -O0 -g -fsanitize=address -o "$tmp/d.$v" "$tmp/d.$v.c" 2>"$tmp/dbuild.$v" ) &
done
wait
for v in old new c_copynew c_nocopy c_freefail c_noguard c_keycopy c_keynofree c_keyfreeboth nw_new nw_noguard; do
    [ -x "$tmp/d.$v" ] || { echo "  realloc      the unit driver for $v did not build:"; sed -n '1,8p' "$tmp/dbuild.$v"; exit 1; }
done

run_driver() {
    ASAN_OPTIONS=$ASANOPT "$tmp/d.$1" >"$tmp/raw.$1" 2>&1 || true
    sed -E 's/==[0-9]+==/==PID==/g; s/0x[0-9a-f]+/0xADDR/g; s#/[^ ]*/d\.[a-z_]+\.c#DRIVER.c#g; s/:[0-9]+:[0-9]+/:L:C/g' "$tmp/raw.$1" > "$tmp/run.$1"
}
for v in old new c_copynew c_nocopy c_freefail c_noguard c_keycopy c_keynofree c_keyfreeboth nw_new nw_noguard; do
    run_driver "$v"
done
# The transcript must be reproducible, or nothing below it means anything.
run_driver new
cp "$tmp/run.new" "$tmp/run.new2"
run_driver new
if ! cmp -s "$tmp/run.new" "$tmp/run.new2"; then
    echo "  realloc      two runs of the output's unit driver differ, so the comparison below is not one:"
    diff "$tmp/run.new2" "$tmp/run.new" | sed -n '1,8p'
    exit 1
fi
for v in old new; do
    if grep -q 'ERROR: \|SUMMARY: ' "$tmp/run.$v"; then
        echo "  realloc      the $v unit driver reports a sanitizer finding, and neither may:"
        grep -m2 'ERROR: \|SUMMARY: ' "$tmp/run.$v"
        exit 1
    fi
done
if ! cmp -s "$tmp/run.old" "$tmp/run.new"; then
    echo "  realloc      THE REWRITE IS NOT THE SAME FUNCTION: the input's ga_grow_inner and get_keystroke block and the output's give different transcripts:"
    diff "$tmp/run.old" "$tmp/run.new" | sed -n '1,14p'
    exit 1
fi
for want in 'A.start data=null maxlen=0' 'B.fail r=0 same=1 maxlen=16' 'B.again r=1' \
            'C.before buflen=150 len=115 maxlen=9' 'C.after buflen=250 maxlen=43 buf=set vim_frees=0'; do
    grep -qxF "$want" "$tmp/run.new" || {
        echo "  realloc      the unit transcript does not hold \`$want\`, so it is not driving what this check says it drives:"
        sed -n '1,20p' "$tmp/run.new"; exit 1; }
done
if grep -q 'LOST at \|TAIL-NOT-ZERO' "$tmp/run.new"; then
    echo "  realloc      the output's unit driver loses bytes across a grow, or leaves the new tail non-zero:"
    grep -m4 'LOST at \|TAIL-NOT-ZERO' "$tmp/run.new"
    exit 1
fi
echo "  realloc      THE UNIT HARNESS: ga_grow_inner(), musl_memcpy(), musl_memset(), garray_T and get_keystroke's extension block, EXTRACTED AT RUN TIME from $state/old.c and from the output and run through the same AddressSanitizer driver -- eight doublings from an empty growarray, six independent first grows, a failed allocation and the 100-byte extension.  The two transcripts are IDENTICAL, $(grep -c '' "$tmp/run.new") lines, neither reports a finding, no byte is lost across a grow and every new tail is zero.  \`B.fail r=0 same=1\` IS TRAP 2: the allocation failed, ga_data is the block it was, and the grow after it reads that block back intact"

# THE CONTROLS.  Six move and one does not, and the one that does not is the finding.
for c in c_copynew:heap-buffer-overflow c_freefail:heap-use-after-free \
         c_keycopy:heap-buffer-overflow c_keynofree:detected c_keyfreeboth:heap-use-after-free; do
    name=${c%%:*}; want=${c#*:}
    if cmp -s "$tmp/run.new" "$tmp/run.$name"; then
        echo "  realloc      the control $name changes nothing in the unit harness, so the harness is not testing what this phase claims"
        exit 1
    fi
    if ! grep -q "$want" "$tmp/run.$name"; then
        echo "  realloc      the control $name was expected to give \`$want\` and gave:"
        grep -m2 'ERROR: \|SUMMARY: ' "$tmp/run.$name" || sed -n '1,6p' "$tmp/run.$name"
        exit 1
    fi
done
if cmp -s "$tmp/run.new" "$tmp/run.c_nocopy"; then
    echo "  realloc      c_nocopy, which copies nothing at all, gives the same transcript as the output"
    exit 1
fi
if ! grep -q 'LOST at ' "$tmp/run.c_nocopy"; then
    echo "  realloc      c_nocopy does not lose bytes, so the transcript is not reading the copy back"
    exit 1
fi
echo "  realloc      SIX CONTROLS MOVE, each with its own named finding and not one bucket: c_copynew (copies new_len) heap-buffer-overflow READ past the old block -- which is INVISIBLE to any recording, the overread bytes being overwritten by the memset that follows; c_freefail (frees on the failure path) heap-use-after-free at the grow that follows; c_keycopy heap-buffer-overflow; c_keynofree a LeakSanitizer report; c_keyfreeboth heap-use-after-free.  c_nocopy gives no sanitizer finding at all and is caught by the transcript instead, $(grep -c 'LOST at ' "$tmp/run.c_nocopy") bytes lost"

# THE GUARD, measured in both directions rather than asserted.
if ! cmp -s "$tmp/run.new" "$tmp/run.c_noguard"; then
    echo "  realloc      c_noguard was measured to change NOTHING in this harness and now changes something, which is a better result than the one this check was written against -- read the diff and rewrite this paragraph:"
    diff "$tmp/run.new" "$tmp/run.c_noguard" | sed -n '1,10p'
    exit 1
fi
nw_new=$(grep -c 'MEMCPY-NULL' "$tmp/run.nw_new" || true)
nw_ng=$(grep -c 'MEMCPY-NULL' "$tmp/run.nw_noguard" || true)
if [ "$nw_new" != 0 ] || [ "$nw_ng" -lt 7 ]; then
    echo "  realloc      the null watch reports $nw_new nulls reaching the copy in the output and $nw_ng in the unguarded control, where 0 and at least 7 were expected"
    exit 1
fi
echo "  realloc      THE GUARD BUYS NOTHING HERE AND IS KEPT ANYWAY, and that is reported rather than hidden.  c_noguard -- the rewrite WITHOUT \`if (gap->ga_data != nullptr)\` -- gives a byte-identical unit transcript and no sanitizer finding, because a null ga_data implies ga_maxlen == 0 implies old_len == 0, musl_memcpy's \`for (; n; n--)\` never dereferences and free(nullptr) is a no-op.  What the guard buys is on the PAGE, which is what ZERO-PLAN.md 4c's transpilation rule asks for: the same driver with musl_memcpy announcing a null source reports $nw_new from the output and $nw_ng from the unguarded control.  A null passed to a copy is not something the core may leave for a runtime to be lenient about"

# --- 4. the symbols, and the binary ---------------------------------------------------------
[ -f "$tmp/new.ok" ] || { echo "  realloc      the output did not build with '$cflags' '$ldflags'"; exit 1; }
gcc -c -O0 -fno-stack-protector -o "$tmp/old.o" "$state/old.c"
gcc -c -O0 -fno-stack-protector -o "$tmp/new.o" "$f"
nm -u "$tmp/old.o" | awk '{print $2}' | sort > "$tmp/u.old"
nm -u "$tmp/new.o" | awk '{print $2}' | sort > "$tmp/u.new"
gone=$(comm -23 "$tmp/u.old" "$tmp/u.new" | tr '\n' ' ')
came=$(comm -13 "$tmp/u.old" "$tmp/u.new" | tr '\n' ' ')
if [ -n "$gone$came" ]; then
    echo "  realloc      \`nm -u\` moved: gone [$gone] arrived [$came].  THIS IS AN EQUALITY AND THE PHASE PREDICTS IT: the core stops calling realloc and adjust_types(), below the boundary, does not, so the symbol stays"
    exit 1
fi
grep -qx realloc "$tmp/u.new" || {
    echo "  realloc      \`realloc\` is NOT undefined any more, and this phase does not claim to free it: adjust_types() is the host's and still calls it.  Phases 14, 15 and 21 each require it to be there"
    exit 1; }
grep -qx malloc "$tmp/u.new" && grep -qx free "$tmp/u.new" || {
    echo "  realloc      \`malloc\` or \`free\` left, and the rewrite is written over both"
    exit 1; }
ext=$(nm --extern-only --defined-only "$tmp/new.o" | awk '{print $3}' | sort | tr '\n' ' ')
if [ "$ext" != "main " ]; then
    echo "  realloc      the output defines external symbols other than main: $ext"
    exit 1
fi
echo "  realloc      \`nm -u\` is THE SAME SET, $(wc -l <"$tmp/u.new") names, as a \`comm\` empty in BOTH directions, and \`main\` is still the only external symbol.  \`realloc\` IS STILL IN IT, which is what a reader will not expect: the core no longer calls it, adjust_types() below the boundary does, and phases 14, 15 and 21 each assert it is there"
echo "  realloc      the binary is $(stat -c%s "$tmp/new") bytes against the input's $(stat -c%s "$state/old").  This phase is NOT tier 1 of CLAUDE.md's table and does not pretend to be: one call becomes a test, a call, a copy loop and a free, and at -O0 that is different instructions"

tools/phasecheck.sh "$work" "$f" "$state/symbols"

# --- 5. the editor.c cut, and its warning set compared WITH THE INPUT'S ----------------------
# `make editor.c`'s rule is one awk clause and no judgement; here it is run on both sides
# and the two prefixes are held to the same three properties.  The boundary names are
# never written out: a check that spelled the set would fail on a tree that is right.
for side in old new; do
    case $side in old) src=$state/old.c;; new) src=$f;; esac
    awk '/^ *# *include / { exit } { a[NR] = $0; if (NF) last = NR } \
         END { for (i = 1; i <= last; i++) print a[i] }' "$src" > "$tmp/ed.$side.c"
    if grep -q '^ *#' "$tmp/ed.$side.c"; then
        echo "  realloc      the $side cut holds a directive, so it found the wrong line:"
        grep -n '^ *#' "$tmp/ed.$side.c" | head -3
        exit 1
    fi
    gcc -O0 -fno-stack-protector -Wall -Wextra -Wno-unused-parameter -fsyntax-only \
        "$tmp/ed.$side.c" 2>"$tmp/w.$side" || true
    if grep -q ': error:' "$tmp/w.$side"; then
        echo "  realloc      the $side cut does not parse on its own:"
        grep ': error:' "$tmp/w.$side" | head -4
        exit 1
    fi
    grep -o "'[A-Za-z_][A-Za-z0-9_]*' used but never defined" "$tmp/w.$side" \
        | sed "s/' used.*//; s/^'//" | sort -u > "$tmp/b.$side"
    if grep ': warning: ' "$tmp/w.$side" | grep -qv 'used but never defined'; then
        echo "  realloc      the $side cut has a warning that is not a boundary name:"
        grep ': warning: ' "$tmp/w.$side" | grep -v 'used but never defined' | head -3
        exit 1
    fi
done
if ! cmp -s "$tmp/b.old" "$tmp/b.new"; then
    echo "  realloc      the core -> host boundary moved: gone [$(comm -23 "$tmp/b.old" "$tmp/b.new" | tr '\n' ' ')] arrived [$(comm -13 "$tmp/b.old" "$tmp/b.new" | tr '\n' ' ')].  malloc and free are declared non-static and are not in this set, and dropping realloc's prototype removes nothing from it"
    exit 1
fi
echo "  realloc      the \`make editor.c\` cut: $(grep -c '' "$tmp/ed.old.c") lines -> $(grep -c '' "$tmp/ed.new.c"), 0 directives, 0 errors under \`-fsyntax-only\`, and the WHOLE warning set is the core -> host boundary -- $(wc -l <"$tmp/b.new") names, IDENTICAL to the input's, compared name by name at run time"

# --- 6. the instrumented pair on the two FULL binaries --------------------------------------
# The same three questions the unit harness answers about the function, asked of the
# editor: how often ga_data is null on entry, how often it is not, and whether the
# allocation can ever shrink.  The instrument is textually identical on both sides -- it
# is inserted at a line both sources have -- so a difference in the counts would be a
# difference in the branch mix and nothing else.
python3 - "$state/old.c" "$f" "$tmp" <<'PY'
import sys

ANCH = '    new_len = (usize)gap->ga_itemsize * (gap->ga_len + n);\n'
INS = ANCH + """    if (gap->ga_data == nullptr) { write(2, "GA-NULL\\n", 8); } else { write(2, "GA-HAVE\\n", 8); }
    if ((usize)gap->ga_itemsize * (usize)gap->ga_maxlen > new_len) { write(2, "GA-SHRINK\\n", 10); }
"""
for src, name in ((sys.argv[1], 'i_old'), (sys.argv[2], 'i_new')):
    t = open(src, errors='surrogateescape').read()
    if t.count(ANCH) != 1:
        sys.exit('  %-12s ga_grow_inner\'s new_len line is not in %s exactly once, so '
                 'the instrument cannot be identical on the two sides' % ('realloc', src))
    open('%s/%s.c' % (sys.argv[3], name), 'w',
         errors='surrogateescape').write(t.replace(ANCH, INS, 1))
PY
for v in i_old i_new c_ncopy_full; do
    case $v in
        c_ncopy_full) cp "$tmp/c_nocopy.c" "$tmp/c_ncopy_full.c";;
    esac
done
# shellcheck disable=SC2086
for v in i_old i_new c_ncopy_full; do
    ( SOURCE_DATE_EPOCH=0 gcc $cflags $ldflags -o "$tmp/$v" "$tmp/$v.c" ) &
done
wait
for v in i_old i_new c_ncopy_full; do
    [ -x "$tmp/$v" ] || { echo "  realloc      the instrumented build $v did not link"; exit 1; }
done

# --- 7. the recordings: the declared delta is NOTHING AT ALL ---------------------------------
tools/zrecord.sh "$state/old" "$state/old.c" "$tmp/REC.old" >/dev/null 2>&1 &
pid_ro=$!
tools/zrecord.sh "$tmp/new" "$f" "$tmp/REC.new" >/dev/null 2>&1 &
pid_rn=$!
tools/zrecord.sh "$tmp/i_old" "$tmp/i_old.c" "$tmp/REC.i_old" >/dev/null 2>&1 &
pid_io=$!
tools/zrecord.sh "$tmp/i_new" "$tmp/i_new.c" "$tmp/REC.i_new" >/dev/null 2>&1 &
pid_in=$!
# The control is the 102 screen cases and not a whole recording: it is the cheap half,
# and a binary whose growarrays never keep their contents is one whose pty scenarios
# would be a coin toss.
tools/st.sh zcases "$tmp/c_ncopy_full" "$tmp/SCR.nocopy" >/dev/null 2>&1 &
pid_rc=$!
wait $pid_ro
wait $pid_rn
wait $pid_io
wait $pid_in
wait $pid_rc || true
if ! diff -rq "$tmp/REC.old" "$tmp/REC.new" >"$tmp/rec.diff" 2>&1; then
    echo "  realloc      the declared delta is NOTHING AT ALL and the two recordings differ:"
    sed -n '1,12p' "$tmp/rec.diff"
    exit 1
fi
python3 - "$tmp" <<'PY'
import os
import sys

TAG = 'realloc'
tmp = sys.argv[1]


def marks(rec, token):
    hit, total, files = 0, 0, 0
    for root, _, names in os.walk(rec):
        for n in names:
            files += 1
            c = open(os.path.join(root, n), 'rb').read().count(token.encode())
            if c:
                hit += 1
                total += c
    return hit, total, files


fail = []
seen = {}
for side in ('i_old', 'i_new'):
    for tok in ('GA-NULL\n', 'GA-HAVE\n', 'GA-SHRINK\n'):
        seen[(side, tok)] = marks(tmp + '/REC.' + side, tok)
    if seen[(side, 'GA-SHRINK\n')][1] != 0:
        fail.append('the %s instrument marks a SHRINK %d times: musl_memcpy copies the '
                    'OLD size at both sites and that is only right because neither can '
                    'ask for less than it has' % (side, seen[(side, 'GA-SHRINK\n')][1]))
for tok in ('GA-NULL\n', 'GA-HAVE\n'):
    if seen[('i_old', tok)] != seen[('i_new', tok)]:
        fail.append('the identical instrument marks `%s` %s on the input and %s on the '
                    'output: the two take the branch a different number of times'
                    % (tok.strip(), seen[('i_old', tok)], seen[('i_new', tok)]))
nh, nt, nf = seen[('i_new', 'GA-NULL\n')]
hh, ht, _ = seen[('i_new', 'GA-HAVE\n')]
if nf < 100:
    fail.append('a recording is %d records, and a measurement over a corpus nothing '
                'wrote passes.  The count is REPORTED and not pinned: it was 106 when '
                'this phase was written and is 122 since zero phase 40 added the '
                'memline corpus' % nf)
if nt < 1000 or ht < 500:
    fail.append('ga_grow_inner is called %d times with a null ga_data and %d times with '
                'one, and this phase\'s claim that a byte-identical recording is STRONG '
                'evidence rests on it being the hot path it was measured to be'
                % (nt, ht))
if fail:
    for line in fail:
        print('  %-12s %s' % (TAG, line))
    sys.exit(1)
print('  %-12s THE INSTRUMENTED PAIR, identical text inserted at a line both sources '
      'have: ga_grow_inner runs %d times per recording on the INPUT and %d on the '
      'OUTPUT -- %d of them with `ga_data == nullptr`, which is trap 1 and is the '
      'MAJORITY case and not an edge -- in %d of the %d records, the two that do not '
      'mark being ref-pty.txt and ref-term.txt.  A SHRINK is marked 0 times on either '
      'side, which is why copying the old size is right'
      % (TAG, nt + ht, nt + ht, nt, nh, nf))
PY
moved=$(diff -rq "$tmp/REC.new/screen" "$tmp/SCR.nocopy" 2>&1 | wc -l)
if [ "$moved" -lt 100 ]; then
    echo "  realloc      the control whose ga_grow_inner copies nothing moves only $moved of the 102 screen cases, where 102 were measured -- the byte-identical recording above would then be two numbers agreeing"
    exit 1
fi
echo "  realloc      the declared delta is NOTHING AT ALL and TWO FULL RECORDINGS ARE BYTE-IDENTICAL -- 102 screen cases, every Ex command, every command line, the pty scenarios and the terminal table.  AND HERE THAT IS STRONG EVIDENCE RATHER THAN THE WEAK KIND, because ga_grow_inner is on the path of every growarray in the editor: the control that keeps the rewrite and copies NOTHING moves $moved of the 102 screen cases"

# tools/phaserun.sh runs tools/zerodelta.sh --phase 34 after this check, and that is the
# second opinion on the same claim -- against .reference/zero-baselines rather than
# against the binary this phase was handed.
