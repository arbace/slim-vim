#!/bin/sh
# Zero phase 26, the check -- the header types and macros the core can own.
# See pipes/zero26-edit.sh, and ZERO-PLAN.md 4c.
#
# Usage: pipes/zero26-check.sh <work-dir> <state-dir>    (run from the repository root)
#
# Runs after pipes/zero26-edit.sh and the sweep tools/phaserun.sh runs between them, and
# reads nothing from the edit's shell -- only the work tree and the state directory.
# What the edit left there is `old.c`, the source this phase was HANDED, `old`, that
# source built with SOURCE_DATE_EPOCH=0 and the boundary's own flags, and `minmax.txt`,
# the two expansions read back out of <sys/param.h> through the preprocessor.
#
# WHAT IS CLAIMED, in seven parts:
#
#   ARITHMETIC  computed FROM THE INPUT: the eight names the core took from a header
#               are at 0 above the host block and at their own counts below it, the
#               eleven directives are where they were, the line count moved by exactly
#               the 24 lines the edit adds, and tools/canon.sh is a NO-OP.
#   THE CLOCK   THE ONLY THING THAT CHANGES CODE, stated as an equality: with the clock
#               ALONE reverted, the binary is `cmp`-IDENTICAL to the one the phase was
#               handed.  So the other six substitutions and the nine prototypes are
#               tier 1 of CLAUDE.md's verification table -- the same program -- and
#               only the clock has anything left to prove.
#   THE HEADERS the whole reason this phase comes BEFORE the move.  Sixteen
#               `static_assert`s compare every core-owned spelling against the header
#               type it replaces, and every one of them NAMES a header type, so not one
#               could be written after the move.  With a control that breaks one.
#   MISMATCHES  four deliberately wrong declarations, each of which the headers above
#               catch, and each named: conflicting types for time, for malloc, for
#               getpid, and the `static` trap.  They are the negative half of the same
#               property.
#   THE TAG     `struct timeval` with a TAG, which the brief calls a hard error.  It is
#               not, in this dialect, and the check says so with the measurement rather
#               than repeating the claim: silent under C23, `error: redefinition of
#               'struct timeval'` under -std=c11 and -std=c17.  Which is why the layout
#               is asserted in THE HEADERS and not left to a diagnostic.
#   SYMBOLS     `nm -u` is THE SAME SET, as a `comm` empty in BOTH directions, and
#               `main` is still the only external symbol.  A rename and a wrapper in
#               one translation unit free nothing and cost nothing.
#   BEHAVIOUR   the declared delta is NOTHING AT ALL.  Two full recordings, of the
#               binary this phase was handed and of its own, are BYTE-IDENTICAL -- and
#               the recording is NOT blind to what moved: a control whose
#               `musl_gettimeofday` writes the two fields the wrong way round moves six
#               of the 102 screen cases.  tools/zerodelta.sh is run by
#               tools/phaserun.sh after this check and is the second opinion.
#
# THE CONTROL IS SCREEN CASES AND NOT A WHOLE RECORDING, and that is a measurement
# about the harness rather than a shortcut.  A binary whose clock runs backwards has
# timeouts that never expire, so tools/zpty.py waits out its deadline, writes `stalled`
# and exits 1 -- correct behaviour on a deliberately broken editor, and two minutes of
# it.  Letting that exit status reach `set -e` would make a good control into a flaky
# check, so the control is `zcases` alone, which drives pipes, has its own
# per-case timeout and is where six of the seven measured differences were.
#
# AND `zhostonly`, WHOSE EXCEPTIONS THIS PHASE CHANGED.  The tool named `struct
# timeval` in the core twice -- "the clock's, not this phase's" -- and this is that
# phase, so both exceptions go; `kill` acquires one, because the core's call to it now
# has a prototype at file scope and the prototype is the same fact the tool already
# excepts inside vim_handle_signal.  An exception that stops being true is what the
# tool exists to notice, and it noticed.
set -eu

work=${1:?usage: zero26-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero26-check.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"
before_lines=$(cat "$state/input-lines")

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")

# The product build and every control are written first and waited for below: they are
# seconds of wall time the assertions can be spending instead.
# shellcheck disable=SC2086
( SOURCE_DATE_EPOCH=0 gcc $cflags $ldflags -o "$tmp/new" "$f" ) &
pid_new=$!

python3 - "$f" "$tmp" <<'PY'
import re
import sys

TAG = 'headers'
t = open(sys.argv[1], errors='surrogateescape').read()
out = sys.argv[2]


def die(msg):
    sys.exit('  %-12s %s' % (TAG, msg))


# r0 -- THE CLOCK ALONE REVERTED.  Everything else this phase did stays.  If the
# binary of this is the binary the phase was handed, then the six renames, the macro
# expansions and the nine prototypes generate not one different instruction, and the
# clock is the only thing a recording has to answer for.
r0 = t
STRUCT = ('typedef struct {\n    long        tv_sec;\n    long        tv_usec;\n'
          '} elapsed_T;')
if r0.count(STRUCT) != 1:
    die('the tagless elapsed_T is not in the output exactly once')
r0 = r0.replace(STRUCT, 'typedef struct timeval elapsed_T;', 1)
for a, b in (('static long elapsed(elapsed_T *start_tv);',
              'static long elapsed(struct timeval *start_tv);'),
             ('elapsed(elapsed_T *start_tv)\n{', 'elapsed(struct timeval *start_tv)\n{'),
             ('    elapsed_T       now_tv;', '    struct timeval  now_tv;'),
             ('static void musl_gettimeofday(long *sec, long *usec);\n', ''),
             ('''    static void
musl_gettimeofday(long *sec, long *usec)
{
    struct timeval tv;

    gettimeofday(&tv, nullptr);
    *sec = tv.tv_sec;
    *usec = tv.tv_usec;
}

''', '')):
    if r0.count(a) != 1:
        die('`%s` is not in the output exactly once, so the clock cannot be reverted '
            'and the equality below would not be one' % a.replace('\n', '\\n')[:60])
    r0 = r0.replace(a, b, 1)
r0, n = re.subn(r'musl_gettimeofday\(&([\w.]+)\.tv_sec, &\1\.tv_usec\)',
                lambda m: 'gettimeofday(&(%s), nullptr)' % m.group(1), r0)
if n != 5:
    die('%d musl_gettimeofday call sites were reverted where 5 were expected' % n)

# x0 -- THE POSITIVE CROSS-CHECK, and the thing the move destroys.  Sixteen
# static_asserts, every one naming a header type: after the eleven includes move below
# the core, `size_t`, `uintptr_t`, `time_t`, `sig_atomic_t`, `struct timeval` and
# `offsetof` are all still in scope HERE and nowhere above.
ASSERTS = '''
static_assert(sizeof(elapsed_T) == sizeof(struct timeval), "elapsed_T size");
static_assert(__builtin_offsetof(elapsed_T, tv_sec) == __builtin_offsetof(struct timeval, tv_sec), "tv_sec");
static_assert(__builtin_offsetof(elapsed_T, tv_usec) == __builtin_offsetof(struct timeval, tv_usec), "tv_usec");
static_assert(sizeof(((elapsed_T *)0)->tv_sec) == sizeof(((struct timeval *)0)->tv_sec), "tv_sec width");
static_assert(sizeof(((elapsed_T *)0)->tv_usec) == sizeof(((struct timeval *)0)->tv_usec), "tv_usec width");
static_assert(_Generic((usize)0, uintptr_t: 1, default: 0), "uintptr_t");
static_assert(_Generic((usize)0, size_t: 1, default: 0), "size_t");
static_assert(_Generic((time_T)0, time_t: 1, default: 0), "time_T");
static_assert(_Generic((int)0, sig_atomic_t: 1, default: 0), "sig_atomic_t");
static_assert(_Generic(time, long (*)(long *): 1, default: 0), "time");
static_assert(__builtin_offsetof(buffblock_T, b_str) == offsetof(buffblock_T, b_str), "buffblock_T");
static_assert(__builtin_offsetof(hlname_T, hn_key) == offsetof(hlname_T, hn_key), "hlname_T");
static_assert(__builtin_offsetof(DATA_BL, db_index) == offsetof(DATA_BL, db_index), "DATA_BL");
static_assert(__builtin_offsetof(PTR_BL, pb_pointer) == offsetof(PTR_BL, pb_pointer), "PTR_BL");
static_assert(__builtin_offsetof(msgchunk_T, sb_text) == offsetof(msgchunk_T, sb_text), "msgchunk_T");
static_assert(__builtin_offsetof(bt_regprog_T, program) == offsetof(bt_regprog_T, program), "bt_regprog_T");
'''
x0 = t + ASSERTS
# x0bad -- ONE of them wrong, so the sixteen cannot pass by not being compiled.
x0bad = t + ASSERTS.replace(
    '__builtin_offsetof(elapsed_T, tv_usec) == __builtin_offsetof(struct timeval, tv_usec)',
    '__builtin_offsetof(elapsed_T, tv_usec) == __builtin_offsetof(struct timeval, tv_sec)', 1)

# m1..m4 -- THE NEGATIVE HALF.  Each is one declaration this phase writes, written
# wrong, and each is caught by the header that is still above it.
MIS = (('m1', 'long time(long *tp);', 'int time(int *tp);', "conflicting types for 'time'"),
       ('m2', 'void *malloc(usize n);', 'void *malloc(int n);', "conflicting types for 'malloc'"),
       ('m3', 'int getpid(void);', 'long getpid(void);', "conflicting types for 'getpid'"),
       ('m4', 'void *malloc(usize n);', 'static void *malloc(usize n);',
        "static declaration of 'malloc' follows non-static declaration"))
files = {'r0': r0, 'x0': x0, 'x0bad': x0bad}
for name, old, new, _ in MIS:
    if t.count(old) != 1:
        die('`%s` is not in the output exactly once, so %s would not be a control'
            % (old, name))
    files[name] = t.replace(old, new, 1)

# swap -- the one control that changes the PROGRAM, so the byte-identical recording in
# section 7 is an assertion and not two numbers agreeing.
SW = '    *sec = tv.tv_sec;\n    *usec = tv.tv_usec;'
if t.count(SW) != 1:
    die('musl_gettimeofday does not assign its two outputs exactly once')
files['swap'] = t.replace(SW, '    *sec = tv.tv_usec;\n    *usec = tv.tv_sec;', 1)

for name, text in files.items():
    if text == t:
        die('%s changed nothing' % name)
    open('%s/%s.c' % (out, name), 'w', errors='surrogateescape').write(text)

# tag -- the eleven includes and nothing else, with the core's struct given the TAG the
# brief says is a hard error.  A probe and not a whole file, because the point is the
# dialect and the whole file does not compile under -std=c11 (phase 23's `typeof`).
inc = '\n'.join(text for text in t.split('\n')[:11])
open('%s/tag.c' % out, 'w').write(
    inc + '\ntypedef struct timeval { long tv_sec; long tv_usec; } elapsed_T;\n')
print('  %-12s eight controls written: r0 the clock alone reverted, x0 sixteen '
      'static_asserts against the headers, x0bad one of them wrong, m1 m2 m3 m4 the '
      'four mismatched declarations, swap musl_gettimeofday writing its two fields the '
      'wrong way round, tag the struct with a tag' % TAG)
PY

# r0 and swap are full static links and the slowest; the rest are warning runs.
# shellcheck disable=SC2086
( SOURCE_DATE_EPOCH=0 gcc $cflags $ldflags -o "$tmp/r0" "$tmp/r0.c" ) &
pid_r0=$!
# shellcheck disable=SC2086
( SOURCE_DATE_EPOCH=0 gcc $cflags $ldflags -o "$tmp/swap" "$tmp/swap.c" ) &
pid_swap=$!
( gcc -O0 -fno-stack-protector -Wall -Wextra -Wno-unused-parameter -fsyntax-only "$tmp/x0.c" 2>"$tmp/w.x0" ) &
pid_x0=$!
# These are EXPECTED to fail -- that is the measurement -- so their status is discarded
# here rather than by `wait`, which would take `set -e` with it.
( gcc -O0 -fno-stack-protector -fsyntax-only "$tmp/x0bad.c" 2>"$tmp/w.x0bad" || true ) &
pid_x0bad=$!
for m in m1 m2 m3 m4; do
    ( gcc -O0 -fno-stack-protector -fsyntax-only "$tmp/$m.c" 2>"$tmp/w.$m" || true ) &
done
( gcc -fsyntax-only "$tmp/tag.c" 2>"$tmp/w.tag23" || true ) &
( gcc -std=c11 -fsyntax-only "$tmp/tag.c" 2>"$tmp/w.tagc11" || true ) &
( gcc -std=c17 -fsyntax-only "$tmp/tag.c" 2>"$tmp/w.tagc17" || true ) &
# tools/canon.sh must be a NO-OP: the tagless struct, the prototype block and
# musl_gettimeofday are new text and canon is what says they are written the way this
# file writes everything else.
cp "$f" "$tmp/canon.c"
( tools/canon.sh "$tmp/canon.c" >"$tmp/canon.log" 2>&1 ) &
pid_canon=$!

# --- 1. the source, as arithmetic on the input ------------------------------------------
python3 - "$f" "$state/old.c" "$before_lines" "$state/minmax.txt" <<'PY'
import re
import sys

TAG = 'headers'
new = open(sys.argv[1], errors='surrogateescape').read()
old = open(sys.argv[2], errors='surrogateescape').read()
before_lines = int(sys.argv[3])
mm = [l.strip() for l in open(sys.argv[4]).read().split('\n') if l.strip()]
fail = []

HOST = 'static volatile sig_atomic_t host_winch_pending'


def split(text):
    lines = text.split('\n')
    hb = [i for i, l in enumerate(lines) if l.startswith(HOST)]
    if len(hb) != 1:
        sys.exit('  %-12s the host block does not begin exactly once with %r -- found '
                 '%d.  Every count below distinguishes the core from the host and '
                 'without the line there is nothing to distinguish'
                 % (TAG, HOST, len(hb)))
    return '\n'.join(lines[11:hb[0]]), '\n'.join(lines[hb[0]:]), lines


ocore, ohost, olines = split(old)
ncore, nhost, nlines = split(new)

if len(olines) - 1 != before_lines:
    fail.append('the state directory says the edit was handed %d lines and old.c has '
                '%d' % (before_lines, len(olines) - 1))

# THE ARITHMETIC, computed from the input.  Nothing here is a number this file states
# except the two the edit's own header states as its product: 0 in the core, and the
# host block's own.
for name, in_host in (('time_t', 0), ('sig_atomic_t', 3), ('uintptr_t', 0),
                      ('size_t', 0), ('MIN', 0), ('MAX', 0), ('offsetof', 0)):
    was = len(re.findall(r'\b%s\b' % name, ocore))
    now = len(re.findall(r'\b%s\b' % name, ncore))
    if now:
        fail.append('`%s` was %d in the core and is still %d -- the phase\'s whole '
                    'product is that it is 0' % (name, was, now))
    h = len(re.findall(r'\b%s\b' % name, nhost))
    if h != in_host:
        fail.append('`%s` is %d in the host block and was expected at %d -- the host '
                    'is below the boundary and keeps its own headers'
                    % (name, h, in_host))
tvc = len(re.findall(r'struct timeval\b', ncore))
tvh = len(re.findall(r'struct timeval\b', nhost))
if tvc:
    fail.append('`struct timeval` is still %d in the core' % tvc)
if tvh != len(re.findall(r'struct timeval\b', ohost)) + 1:
    fail.append('`struct timeval` is %d in the host block and the input had %d there: '
                'musl_gettimeofday adds exactly one'
                % (tvh, len(re.findall(r'struct timeval\b', ohost))))

# The substitutions, each as the input's count arriving at its destination.
# `time_T` IS THE ONE THAT IS NOT A SIMPLE SUM, and the arithmetic says why: the input
# already spells the type `time_T` wherever it is the editor's own, and the phase turns
# the OTHER spelling into it -- except in the typedef itself, whose `time_t` becomes
# `long` and is the core taking the width.  So the output has the input's `time_T` plus
# the input's `time_t` less that one.
for name, want, why in (
        (r'\btime_T\b',
         len(re.findall(r'\btime_T\b', old)) + len(re.findall(r'\btime_t\b', old)) - 1,
         'the input\'s %d `time_T` plus its %d `time_t`, less the one in `typedef '
         'time_t time_T;`, which becomes `long`'
         % (len(re.findall(r'\btime_T\b', old)), len(re.findall(r'\btime_t\b', old)))),
        (r'\b__builtin_offsetof\b', len(re.findall(r'\boffsetof\b', old)),
         'every `offsetof` in the input'),
        (r'\bmusl_gettimeofday\b', 5 + 2,
         'the five call sites, the prototype and the definition')):
    n = len(re.findall(name, new))
    if n != want:
        fail.append('`%s` occurs %d times in the output where %d were expected -- %s'
                    % (name.strip('\\b'), n, want, why))
# `\bgettimeofday\b` does NOT match inside `musl_gettimeofday` -- `_` is a word
# character -- so this counts the bare name alone, and after this phase there is
# exactly one: the call musl_gettimeofday itself makes, in the host block.
bare = len(re.findall(r'\bgettimeofday\b', new))
if bare != 1:
    fail.append('the bare name `gettimeofday` occurs %d times in the output and must '
                'occur exactly once -- the call inside musl_gettimeofday, in the host '
                'block' % bare)
if re.search(r'\bgettimeofday\b', ncore):
    fail.append('the core still calls `gettimeofday` directly, which is the one libc '
                'call this phase could not leave as it was: its argument is a struct')

# THE MACRO EXPANSION, checked against the header rather than against this file.  The
# two templates come out of the preprocessor in the edit; here the output is required
# to hold exactly 7 and 16 more instances of each shape than the input did, with the
# repeated argument really repeated -- which is what a macro does and what a
# hand-written "expansion" gets wrong.
for tmpl in mm:
    pat = re.escape(tmpl).replace('ZZA', '(?P<a>.+?)', 1).replace('ZZB', '(?P<b>.+?)', 1)
    pat = pat.replace('ZZA', '(?P=a)').replace('ZZB', '(?P=b)')
    was = len(re.findall(pat, old))
    now = len(re.findall(pat, new))
    want = 7 if '<' in tmpl else 16
    if now - was != want:
        fail.append('the shape %r occurs %d times in the output and %d in the input, a '
                    'difference of %d where %d was expected'
                    % (tmpl, now, was, now - was, want))
if re.search(r'\b(MIN|MAX)\(', new):
    fail.append('a `MIN(` or `MAX(` survives in the output')

# The line arithmetic and the directives.
added = 10 + 3 + 1 + 10
if len(nlines) - len(olines) != added:
    fail.append('the output is %d lines and the input was %d, a difference of %d where '
                '%d was expected -- 10 for the prototype block, 3 for the tagless '
                'struct, 1 for musl_gettimeofday\'s prototype and 10 for its definition'
                % (len(nlines) - 1, len(olines) - 1,
                   len(nlines) - len(olines), added))
d = [(i, l) for i, l in enumerate(nlines) if l.startswith('#')]
if len(d) != 11 or [i for i, _ in d] != list(range(11)):
    fail.append('the output does not have exactly eleven directives on its first '
                'eleven lines: %d at %s' % (len(d), ' '.join(str(i) for i, _ in d)))

# NOT ONE PROTOTYPE MAY BE `static`.  This is the trap the brief names, asserted on the
# product and not only broken in a control.
PROTOS = ('void *malloc(usize n);', 'void *realloc(void *p, usize n);',
          'void free(void *p);', 'long time(long *tp);', 'int getpid(void);',
          'int kill(int pid, int sig);', 'long write(int fd, const void *buf, usize n);',
          'long labs(long n);', 'int abs(int n);')
for p in PROTOS:
    if new.count('\n' + p + '\n') != 1:
        fail.append('the prototype `%s` is not on a line of its own exactly once' % p)
    if ('static ' + p) in new:
        fail.append('the prototype `%s` is `static`, which gives the core an internal '
                    'function that is never defined' % p)

# Blank-line runs, which no verification tier can see (CLAUDE.md).
def runs(text):
    L = text.split('\n')
    return sum(1 for i in range(1, len(L)) if L[i] == '' and L[i - 1] == '')


if runs(new) != runs(old):
    fail.append('the edit left %d runs of two blank lines where there were %d'
                % (runs(new), runs(old)))

if fail:
    for line in fail:
        print('  %-12s %s' % (TAG, line))
    sys.exit(1)
print('  %-12s the core takes NOTHING from a header but the twelve constants phase 27 '
      'moves: size_t time_t sig_atomic_t uintptr_t `struct timeval` MIN MAX offsetof '
      'are all 0 above the host block, which keeps its own 3 sig_atomic_t and 3 '
      '`struct timeval`' % TAG)
print('  %-12s the substitutions are the input\'s own counts arriving: %d time_t -> '
      'time_T, %d offsetof -> __builtin_offsetof, 7 MIN and 16 MAX expanded to the '
      'shapes the preprocessor gives for <sys/param.h> (%s), and 5 gettimeofday call '
      'sites through musl_gettimeofday'
      % (TAG, len(re.findall(r'\btime_t\b', old)),
         len(re.findall(r'\boffsetof\b', old)), ' and '.join(mm)))
print('  %-12s nine plain prototypes, each on a line of its own and NOT ONE of them '
      '`static`: %s' % (TAG, ' '.join(p.split('(')[0].split()[-1].lstrip('*')
                                      for p in PROTOS)))
print('  %-12s %d lines -> %d, exactly the %d the edit adds, eleven directives on the '
      'first eleven lines, and the blank-line runs unmoved at %d'
      % (TAG, len(olines) - 1, len(nlines) - 1, added, runs(new)))
PY

# --- 2. the headers verify the core, which is why this phase comes before the move -----
wait $pid_x0 || { echo "  headers      the sixteen static_asserts against the headers did not compile:"; sed -n '1,12p' "$tmp/w.x0"; exit 1; }
if [ -s "$tmp/w.x0" ]; then
    echo "  headers      the sixteen static_asserts compiled but were not silent:"
    sed -n '1,12p' "$tmp/w.x0"
    exit 1
fi
wait $pid_x0bad || true
if ! grep -q 'static assertion failed' "$tmp/w.x0bad"; then
    echo "  headers      x0bad -- one static_assert deliberately comparing elapsed_T's tv_usec against struct timeval's tv_sec -- did NOT fail, so the sixteen above prove nothing:"
    sed -n '1,8p' "$tmp/w.x0bad"
    exit 1
fi
echo "  headers      SIXTEEN static_asserts, silent: sizeof and both field offsets of the tagless elapsed_T against <sys/time.h>'s struct timeval, _Generic saying usize IS uintptr_t and IS size_t, time_T IS time_t, int IS sig_atomic_t and time IS long(long *), and __builtin_offsetof == <stddef.h>'s offsetof at all six types.  EVERY ONE NAMES A HEADER TYPE, so not one of them can be written after phase 27 moves the includes -- which is the whole argument for doing this first.  The control with one comparison wrong fails, so they are compiled and not merely present"

for m in m1 m2 m3 m4; do
    case $m in
        m1) want="conflicting types for 'time'"; what="long time(long *tp) written int time(int *tp)";;
        m2) want="conflicting types for 'malloc'"; what="void *malloc(usize n) written void *malloc(int n)";;
        m3) want="conflicting types for 'getpid'"; what="int getpid(void) written long getpid(void)";;
        m4) want="static declaration of 'malloc' follows non-static declaration"; what="the malloc prototype made static -- THE TRAP";;
    esac
    if ! grep -qF "$want" "$tmp/w.$m"; then
        echo "  headers      $m ($what) did not give \`$want\`, so the header above it is not checking this declaration:"
        sed -n '1,6p' "$tmp/w.$m"
        exit 1
    fi
done
echo "  headers      and the negative half: four wrong declarations, four errors from the headers that are still above them -- conflicting types for time, for malloc and for getpid, and \`static declaration of 'malloc' follows non-static declaration\` for the trap the brief names.  AFTER THE MOVE the last of those becomes a link failure and the other three become nothing at all"

# --- 3. the tag, and the claim that is no longer true ------------------------------------
if [ -s "$tmp/w.tag23" ]; then
    echo "  headers      the tagged struct was expected to be SILENT under this file's own dialect and was not:"
    sed -n '1,6p' "$tmp/w.tag23"
    exit 1
fi
for s in c11 c17; do
    if ! grep -q "redefinition of 'struct timeval'" "$tmp/w.tag$s"; then
        echo "  headers      the tagged struct did not give \`error: redefinition of 'struct timeval'\` under -std=$s:"
        sed -n '1,6p' "$tmp/w.tag$s"
        exit 1
    fi
done
echo "  headers      THE TAG IS FORBIDDEN FOR A BETTER REASON THAN THE BRIEF GIVES.  \`typedef struct timeval { long tv_sec; long tv_usec; } elapsed_T;\` after the eleven includes is SILENT under gcc's default dialect -- C23 permits a struct to be redeclared with the same members -- and is \`error: redefinition of 'struct timeval'\` under -std=c11 and -std=c17.  So the diagnostic the brief relied on does not exist here, the core must simply not define a libc TAG, and the layout equality is asserted in section 2 instead"

# --- 4. canon.sh ---------------------------------------------------------------------------
wait $pid_canon || { echo "  headers      tools/canon.sh failed on the output:"; sed -n '1,10p' "$tmp/canon.log"; exit 1; }
if ! cmp -s "$f" "$tmp/canon.c"; then
    echo "  headers      tools/canon.sh is not a no-op on the output -- the new text is not written the way this file writes everything else:"
    diff "$f" "$tmp/canon.c" | sed -n '1,12p'
    exit 1
fi
echo "  headers      tools/canon.sh is a NO-OP on the output: the tagless struct, the nine prototypes and musl_gettimeofday are written the way this file writes everything else"

# --- 5. the host's vocabulary is still the host's ------------------------------------------
tools/st.sh zhostonly "$f"

# --- 6. the symbols, and the binary ---------------------------------------------------------
wait $pid_new || { echo "  headers      the output did not build with '$cflags' '$ldflags'"; exit 1; }
wait $pid_r0 || { echo "  headers      the clock-reverted control did not build"; exit 1; }
wait $pid_swap || { echo "  headers      the swapped-clock control did not build"; exit 1; }

gcc -c -O0 -fno-stack-protector -o "$tmp/old.o" "$state/old.c"
gcc -c -O0 -fno-stack-protector -o "$tmp/new.o" "$f"
nm -u "$tmp/old.o" | awk '{print $2}' | sort > "$tmp/u.old"
nm -u "$tmp/new.o" | awk '{print $2}' | sort > "$tmp/u.new"
gone=$(comm -23 "$tmp/u.old" "$tmp/u.new" | tr '\n' ' ')
came=$(comm -13 "$tmp/u.old" "$tmp/u.new" | tr '\n' ' ')
if [ -n "$gone$came" ]; then
    echo "  headers      \`nm -u\` moved: gone [$gone] arrived [$came].  A rename and a wrapper inside ONE translation unit can free nothing and can need nothing"
    exit 1
fi
ext=$(nm --extern-only --defined-only "$tmp/new.o" | awk '{print $3}' | sort | tr '\n' ' ')
if [ "$ext" != "main " ]; then
    echo "  headers      the output defines external symbols other than main: $ext"
    exit 1
fi
echo "  headers      \`nm -u\` is THE SAME SET, $(wc -l <"$tmp/u.new") names, as a \`comm\` empty in BOTH directions, and \`main\` is still the only external symbol"

if ! cmp -s "$tmp/r0" "$state/old"; then
    echo "  headers      THE CLOCK IS NOT THE ONLY THING THAT MOVED: with the clock alone reverted the binary is not the one this phase was handed"
    cmp "$tmp/r0" "$state/old" | sed -n '1,4p'
    exit 1
fi
if cmp -s "$tmp/new" "$state/old"; then
    echo "  headers      the output binary is byte-identical to the input's, which cannot be: musl_gettimeofday adds a call and two stores at five sites, so the clock control in section 7 would not be a control"
    exit 1
fi
if cmp -s "$tmp/swap" "$tmp/new"; then
    echo "  headers      the swapped-clock control produced the same binary as the output, so it is not a control"
    exit 1
fi
echo "  headers      THE CLOCK IS THE ONLY THING THAT CHANGES CODE, as an equality: with it ALONE reverted the binary is \`cmp\`-IDENTICAL to the $(stat -c%s "$state/old")-byte one this phase was handed.  So the six renames, the 23 macro expansions and the nine prototypes are tier 1 of CLAUDE.md's table -- literally the same program -- and only the clock has anything left to answer for.  The output is $(stat -c%s "$tmp/new") bytes"

# --- 7. the recording did not move, and it is not blind to what did --------------------------
tools/zrecord.sh "$state/old" "$state/old.c" "$tmp/REC.old" >/dev/null 2>&1 &
pid_ro=$!
tools/zrecord.sh "$tmp/new" "$f" "$tmp/REC.new" >/dev/null 2>&1 &
pid_rn=$!
# THE CONTROL IS THE 102 SCREEN CASES AND NOT A WHOLE RECORDING, and the reason is the
# control itself: a binary whose clock runs backwards is one whose timeouts do not
# expire, and tools/zpty.py duly waits out its deadline, writes `stalled` and exits 1.
# That is the harness behaving correctly on a deliberately broken editor, and making it
# `set -e`'s business would turn a good control into a flaky check.  zcases.py drives
# pipes, has its own per-case timeout, and is where six of the seven differences were
# measured, so it is the cheap half of the recording and the half that answers.
tools/st.sh zcases "$tmp/swap" "$tmp/SCR.swap" >/dev/null 2>&1 &
pid_rs=$!
wait $pid_ro
wait $pid_rn
wait $pid_rs || true
if ! diff -rq "$tmp/REC.old" "$tmp/REC.new" >"$tmp/rec.diff" 2>&1; then
    echo "  headers      the declared delta is NOTHING AT ALL and the two recordings differ:"
    sed -n '1,12p' "$tmp/rec.diff"
    exit 1
fi
moved=$(diff -rq "$tmp/REC.new/screen" "$tmp/SCR.swap" 2>&1 | wc -l)
if [ "$moved" -lt 1 ]; then
    echo "  headers      the swapped-clock control moves NOTHING in the 102 screen cases, so the byte-identical recording above is two numbers agreeing"
    exit 1
fi
names=$(diff -rq "$tmp/REC.new/screen" "$tmp/SCR.swap" 2>&1 | sed -n 's/.*screen\/\([A-Za-z0-9_]*\) .*/\1/p' | tr '\n' ' ')
echo "  headers      the declared delta is NOTHING AT ALL and TWO FULL RECORDINGS ARE BYTE-IDENTICAL -- 102 screen cases, every Ex command, every command line, the pty scenarios and the terminal table.  And the recording is NOT blind to what moved: the control whose musl_gettimeofday writes its two fields the wrong way round moves $moved of the 102 screen cases ($names)"

# tools/phaserun.sh runs tools/zerodelta.sh --phase 26 after this check, and that is the
# second opinion on the same claim -- against .reference/zero-baselines rather than
# against the binary this phase was handed.
