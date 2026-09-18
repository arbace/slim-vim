#!/bin/sh
# Zero phase 16, the check -- the includes nothing names.
# See pipes/zero16-edit.sh, and ZERO-GOAL.md.
#
# Usage: pipes/zero16-check.sh <work-dir> <state-dir>    (run from the repository root)
#
# Runs after pipes/zero16-edit.sh and the sweep tools/phaserun.sh runs between them,
# and reads nothing from the edit's shell -- only the work tree and the state
# directory.  What the edit left there is `old.c`, the source this phase was HANDED,
# and `old`, that source built with SOURCE_DATE_EPOCH=0 and the boundary's own flags.
#
# THIS PHASE CHANGES NO CODE, so there is no behavioural probe to offer and none is
# offered.  What it has instead is stronger than any recording: THE BINARY IS THE SAME
# BYTES.  That is tier 1 of CLAUDE.md's verification table -- "pure formatting: the
# binary is byte-identical (cmp)" -- and a byte-identical binary subsumes every screen
# case, every Ex-command row, every command line and every pty scenario at once, because
# the program that would be run is literally the same program.  tools/zerodelta.sh
# --phase 16 still runs, from tools/phaserun.sh after this check, and it corroborates;
# it is not the evidence.
#
# THE ARGUMENT IS A COMPUTATION AND NOT A LIST, and section 3 is the whole phase.  A
# phase that deleted six named headers proves only that six named headers were
# deletable.  What this proves is EVERY INCLUDE THAT SURVIVES IS NEEDED and EVERY
# INCLUDE THAT WENT WAS NOT, by removing each one in turn and asking the compiler:
#
#   on the output    12 compiles, and EVERY ONE MUST FAIL.  A dead include that
#                    survived this phase would be a compile that succeeded.
#   on the input     18 compiles, and EXACTLY SIX MUST SUCCEED -- the six this phase
#                    removed -- while the other twelve fail.  That is the same loop
#                    proving it can fail, in the same run, on the same code path: it
#                    is phase 13's ui_write() control in this phase's shape.
#
# Measured: the two loops together are 30 compiles and about 5 seconds, run at once.
# gcc 15 defaults to C23, where an implicit function declaration is a HARD ERROR, so a
# header that still supplies a function, a type, a macro constant or an enum constant
# cannot be dropped quietly -- there is no -Wimplicit-* to look for because there is
# nothing left to warn about.
#
# THE ONE SILENT DROP IN THIS FILE, and section 2 is where it is caught.  Removing
# <sys/stat.h> while keeping `typedef struct stat stat_T;` COMPILES CLEANLY: the typedef
# declares a new, incomplete `struct stat` at file scope.  Only `sizeof(stat_T)` would
# ever have exposed it.  So the typedef is required at zero mentions and `struct stat`
# with it, and section 3's loop would NOT have caught this one on its own.
#
# WHAT MUST NOT MOVE, and each is asserted rather than assumed:
#
#   * the libc surface, as a `cmp` OF THE WHOLE SET.  This phase frees nothing and
#     nothing arrives -- it is phase 5's, 11's and 12's equality, and a symbol
#     ARRIVING must fail as loudly as one leaving.
#   * `main` the only external symbol (tools/phasecheck.sh).  Phases 14 and 15 added
#     twenty-eight `static` definitions of what were libc functions, and that check is
#     what says the keyword was not forgotten; this phase re-asserts it for free.
#   * `FILE` at zero mentions, and nothing that could open or name a file called --
#     ZERO-PLAN.md 4b's invariant, which <fcntl.h> and <sys/stat.h> leaving makes
#     visible in the directive list for the first time.
#   * `cmdnames[]`, `nv_cmds[]` and `options[]`, none of which this phase touches.
#   * the blank-line paragraphing, which no verification tier can see: CLAUDE.md says
#     this tree has no run of two blank lines, and deleting the typedef between its two
#     blanks would have made one.
#
# WHY THE cmp IS AS SENSITIVE AS IT IS.  gcc writes a GNU build-id note near the front
# of the image, and it is a hash of the whole output -- so ANY difference anywhere moves
# it and the FIRST difference cmp reports is always that note, at char 633 of this
# binary.  Measured three ways on the stand-in: two ordinary builds of the same bytes
# differ there (which is why SOURCE_DATE_EPOCH=0 is set on both sides), a one-character
# change to one string literal differs there, and the phase's own output does not differ
# at all.
set -eu

work=${1:?usage: zero16-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero16-check.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"
before_lines=$(cat "$state/input-lines")

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")

# The reproducible build of the OUTPUT is started first and waited for in section 5:
# it is three seconds of wall time that sections 1 to 3 can be spending instead.  It is
# built from $f directly, and neither the file's name nor its path reaches the image --
# measured, `old.c` in $state and `zero-vim.c` in $work give identical bytes, because
# zero-vim.c names no __FILE__ and no __LINE__ and gcc is not given -g.
# shellcheck disable=SC2086
( SOURCE_DATE_EPOCH=0 gcc $cflags $ldflags -o "$tmp/new" "$f" ) &
pid_new=$!

# --- 1. the directives, which are the whole of what this phase changed ----------------
python3 - "$f" "$state/old.c" <<'PY'
import re, sys
TAG = 'includes'
new = open(sys.argv[1], errors='surrogateescape').read()
old = open(sys.argv[2], errors='surrogateescape').read()
fail = []

KEEP = ['stdio.h', 'stdlib.h', 'unistd.h', 'sys/param.h', 'time.h', 'signal.h',
        'errno.h', 'stdint.h', 'stdarg.h', 'stddef.h', 'sys/ioctl.h', 'termios.h']
GONE = ['sys/stat.h', 'fcntl.h', 'iconv.h', 'string.h', 'ctype.h', 'wctype.h']
INC = re.compile(r'^#include <([A-Za-z0-9_/.]+)>$')


def directives(text):
    L = text.split('\n')
    return [(i, l) for i, l in enumerate(L) if l.startswith('#')]


def headers(text, where):
    out = []
    for i, l in directives(text):
        m = INC.match(l)
        if not m:
            fail.append('%s has a directive that is not an #include of a system '
                        'header: %r -- the charter is that zero-vim.c stays pure C '
                        'without a preprocessor' % (where, l))
        else:
            out.append(m.group(1))
    return out


# THE INPUT, so that "six went" is a difference and not a number.
if [i for i, _ in directives(old)] != list(range(18)):
    fail.append('the input did not have eighteen directives on its first eighteen '
                'lines, so this is not the file the phase was written against')
old_h = headers(old, 'the input')
if sorted(old_h) != sorted(KEEP + GONE):
    fail.append('the input is not the eighteen headers this phase was written '
                'against: %s' % ' '.join(sorted(old_h)))

# THE OUTPUT.
d = directives(new)
if [i for i, _ in d] != list(range(12)):
    fail.append('the output has %d directives, at lines %s -- twelve are expected and '
                'they must be the first twelve lines of the file'
                % (len(d), ' '.join(str(i) for i, _ in d)))
new_h = headers(new, 'the output')
if new_h != KEEP:
    fail.append('the twelve that are left are not the twelve this phase keeps, in '
                'order: %s' % ' '.join(new_h))
for h in GONE:
    if '#include <%s>' % h in new:
        fail.append('<%s> is still included' % h)

# NOTHING BUT #include, ANYWHERE.  The charter's other half, and this is the only phase
# that has ever had a reason to look.
for bad in ('#define', '#undef', '#if', '#ifdef', '#ifndef', '#elif', '#else',
            '#endif', '#pragma', '#line', '#error', '#include_next'):
    if re.search(r'^\s*%s\b' % re.escape(bad), new, re.M):
        fail.append('%s appears in zero-vim.c, and no phase may add a directive that '
                    'is not an #include of a system header' % bad)

# --- 2. what the six supplied, at zero -- and the one silent drop ---------------------
# The six identifier sets are the MEASURED ones: what zero-vim.c was measured to take
# from each header, and nothing speculative.  A list written from what a header OFFERS
# refuses on a correct phase -- `isprint` is in this file, as the name of the 'isprint'
# option in a string literal, and it is not a ctype call.
SUPPLIED = {
    'sys/stat.h': 'fstat lstat chmod fchmod ftruncate mkdir umask st_mode st_size',
    'fcntl.h': 'fcntl creat openat O_RDONLY O_WRONLY O_RDWR O_CREAT O_TRUNC '
               'O_APPEND O_EXCL O_NONBLOCK F_GETFD F_SETFD FD_CLOEXEC',
    'iconv.h': 'iconv iconv_t iconv_open iconv_close',
    'string.h': 'memchr memcmp memcpy memmove memset strcasecmp strcat strchr '
                'strcmp strcpy strlen strncasecmp strncmp strncpy strpbrk strstr',
    'ctype.h': 'isalnum isalpha iscntrl isdigit isgraph islower ispunct isupper '
               'tolower toupper',
    'wctype.h': 'iswupper towlower towupper',
}
body = '\n'.join(new.split('\n')[12:])
for header, ids in sorted(SUPPLIED.items()):
    live = [i for i in ids.split() if re.search(r'\b%s\b' % i, body)]
    if live:
        fail.append('<%s> was removed and zero-vim.c still names %s'
                    % (header, ', '.join(live)))

# THE SILENT ONE.  A typedef of an undeclared struct tag compiles, so section 3's loop
# could not have caught this: <sys/stat.h> is droppable WITH the typedef in place, and
# what is left is a lie that only sizeof(stat_T) would expose.
if re.search(r'\bstat_T\b', body):
    fail.append('stat_T survives with no <sys/stat.h>: the typedef would declare a '
                'NEW, INCOMPLETE `struct stat` and compile cleanly, which is the only '
                'silent drop in this file')
if re.search(r'\bstruct\s+stat\b', body):
    fail.append('`struct stat` survives with no <sys/stat.h>')
if len(re.findall(r'\bstat_T\b', old)) != 1:
    fail.append('the input had %d stat_T mentions, expected 1 -- "its only user is its '
                'own typedef" was not true of the file this ran on'
                % len(re.findall(r'\bstat_T\b', old)))

# --- what must NOT have moved --------------------------------------------------------
# `FILE` is phase 13's and the cheapest re-assertion of ZERO-PLAN.md 4b's invariant --
# and this is the phase that makes it visible in the DIRECTIVE list, <fcntl.h> and
# <sys/stat.h> being the two headers a file-opening core would need.
if re.search(r'\bFILE\b', new):
    fail.append('FILE is named in zero-vim.c, and phase 13 took it to zero')
for absent in ('open', 'creat', 'openat', 'fopen', 'fdopen', 'opendir', 'stat',
               'access', 'fcntl', 'getcwd', 'strerror', 'fclose', 'getc', 'putc',
               'fsync', 'mkdir', 'rename', 'unlink', 'readlink'):
    if re.search(r'(?<![\w.>])%s\s*\(' % absent, new):
        fail.append('%s( is called in the source, and the core has had no way to name '
                    'or open anything since phase 13' % absent)

# THE PARAGRAPHING, WHICH NO VERIFICATION TIER CAN SEE.  The typedef sat between two
# blank lines; deleting the line alone would leave a run of two, and neither a
# byte-identical binary nor an identical token stream would show it.


def runs(text):
    L = text.split('\n')
    return sum(1 for i in range(1, len(L)) if L[i] == '' and L[i - 1] == '')


if runs(new) != runs(old):
    fail.append('runs of two blank lines: %d in the output against %d in the input. '
                'The typedef sat between two blanks and one of them goes with it; no '
                'verification tier can see this, which is why it is counted'
                % (runs(new), runs(old)))

# The tables this phase does not touch.
sys.path.insert(0, 'tools')
import create_cmdidxs
rows = re.findall(r'^    \[CMD_\w+\] = \{.*$', new, re.M)
got = create_cmdidxs.names(sys.argv[1])
if len(rows) != 98 or len(got) != 98:
    fail.append('cmdnames[] has %d rows and names() reads %d; both must be 98, and '
                'this phase touches no table' % (len(rows), len(got)))
i = new.find('static struct vimoption options[]')
j = new.index('\n};', i)
if len(re.findall(r'^[ \t]*\{"([a-z]+)",', new[i:j], re.M)) != 108:
    fail.append('options[] is not the 108 rows phase 12 left')

# And the line count: EIGHT lines and no more -- the six `#include` lines, the stat_T
# typedef and one of its two blank lines.  Nothing else may go, and the sweep between
# the edit and this check must have found nothing, which is what a phase that removes
# no code predicts.
if len(new.split('\n')) != len(old.split('\n')) - 8:
    fail.append('the file lost %d lines, expected 8 -- six `#include` lines, the '
                'stat_T typedef and one of its two blanks'
                % (len(old.split('\n')) - len(new.split('\n'))))

if fail:
    for line in fail:
        print('  %-12s %s' % (TAG, line))
    sys.exit(1)
print('  %-12s eighteen directives -> TWELVE, every one an `#include <...>` of a '
      'system header on the first twelve lines, and no #define, #if or #pragma '
      'anywhere: <sys/stat.h>, <fcntl.h>, <iconv.h>, <string.h>, <ctype.h> and '
      '<wctype.h> are gone' % TAG)
print('  %-12s and with <sys/stat.h> its only user, `typedef struct stat stat_T;` -- '
      'the ONE silent drop in this file, because a typedef of an undeclared struct '
      'tag compiles cleanly and declares a new, incomplete type.  The loop below '
      'could not have caught it' % '')
print('  %-12s nothing else moved: FILE still at 0, nothing that could open or name a '
      'file is called, cmdnames[] 98 rows, options[] 108, and the same number of runs '
      'of two blank lines -- which no verification tier can see' % '')
PY

# --- 3. THE PHASE: every surviving include is needed, and every one that went was not --
# Thirty compiles, run at once.  This is what makes the phase a computation rather than
# a list, and the second loop is what proves the first can fail.
python3 - "$f" "$state/old.c" <<'PY'
import concurrent.futures
import os
import re
import subprocess
import sys
import tempfile

TAG = 'includes'
CC = ['gcc', '-fsyntax-only', '-O0', '-w', '-fmax-errors=1']


def drop(src, i, d, tag):
    L = open(src, errors='surrogateescape').read().split('\n')
    # The two loops run at once in one directory, and both index from zero: a name
    # made from the index alone has each file written and unlinked twice.
    out = os.path.join(d, '%s%d.c' % (tag, i))
    open(out, 'w', errors='surrogateescape').write('\n'.join(L[:i] + L[i + 1:]))
    return L[i], out


def run(job):
    src, i, d, tag = job
    line, path = drop(src, i, d, tag)
    r = subprocess.run(CC + [path], capture_output=True, text=True)
    os.unlink(path)
    why = ''
    for l in r.stderr.split('\n'):
        if 'error:' in l:
            why = re.sub(r'.*error: ', '', l).strip()
            break
    return src, line, r.returncode == 0, why


def includes(src):
    L = open(src, errors='surrogateescape').read().split('\n')
    return [i for i, l in enumerate(L) if l.startswith('#')]


new, old = sys.argv[1], sys.argv[2]
d = tempfile.mkdtemp(prefix='zero16-drop-')
jobs = ([(new, i, d, 'out') for i in includes(new)]
        + [(old, i, d, 'in') for i in includes(old)])
with concurrent.futures.ThreadPoolExecutor(max_workers=min(16, len(jobs))) as ex:
    res = list(ex.map(run, jobs))
os.rmdir(d)

fail = []
# THE OUTPUT: every surviving include must be NEEDED, so every compile must FAIL.
kept = [(l, ok, why) for s, l, ok, why in res if s == new]
if len(kept) != 12:
    fail.append('the output has %d includes to test, expected 12' % len(kept))
dead = [l for l, ok, _ in kept if ok]
if dead:
    fail.append('%d include(s) survive this phase and are needed by NOTHING: %s -- a '
                'phase whose whole subject is the includes may not leave a dead one'
                % (len(dead), ', '.join(l.strip() for l in dead)))

# THE INPUT: exactly the six this phase removed must have been droppable, and the
# twelve it kept must not.  This is the same loop, on the same code path, required to
# produce a non-empty answer -- without it the zero above is a test that cannot fail.
was = [(l, ok) for s, l, ok, why in res if s == old]
if len(was) != 18:
    fail.append('the input has %d includes to test, expected 18' % len(was))
droppable = sorted(l.strip() for l, ok in was if ok)
WANT = sorted('#include <%s>' % h for h in
              ('sys/stat.h', 'fcntl.h', 'iconv.h', 'string.h', 'ctype.h', 'wctype.h'))
if droppable != WANT:
    fail.append('on the source this phase was HANDED the identical loop finds %d '
                'droppable include(s), %s -- it must find exactly the six this phase '
                'removes, or the loop above is a check that cannot fail'
                % (len(droppable), ', '.join(droppable) or 'none'))

if fail:
    for line in fail:
        print('  %-12s %s' % (TAG, line))
    sys.exit(1)
print('  %-12s EVERY SURVIVING INCLUDE IS NEEDED, computed and not listed: each of '
      'the twelve dropped in turn, and all twelve compiles FAIL.  gcc 15 defaults to '
      'C23, where an implicit declaration is a hard error, so a header that still '
      'supplies a function, a type or a macro constant cannot go quietly' % TAG)
for l, ok, why in kept:
    print('  %-12s   %-24s %s' % ('', l.replace('#include ', ''), why[:78]))
print('  %-12s and the same loop on the source this phase was handed finds EXACTLY '
      'the six it removes -- that is this check proving it can fail, in the same run '
      'and on the same code path' % '')
PY

# --- 4. the compile, the linkage and the libc surface --------------------------------
# NOTHING IS FREED AND NOTHING ARRIVES.  Stated as a `cmp` of the whole undefined set,
# which is phase 5's, 11's and 12's equality: a symbol ARRIVING must fail as loudly as
# one leaving.  A header is not code, so this is what the phase predicts.
cp "$state/symbols/undefined" "$tmp/before.u"
tools/phasecheck.sh "$work" "$f" "$state/symbols"
if ! cmp -s "$tmp/before.u" .cache/symbols/last/undefined; then
    echo "  includes     the libc surface moved, and REMOVING AN #include CANNOT MOVE IT:"
    echo "               gone: $(comm -23 "$tmp/before.u" .cache/symbols/last/undefined | tr '\n' ' ')"
    echo "               came: $(comm -13 "$tmp/before.u" .cache/symbols/last/undefined | tr '\n' ' ')"
    exit 1
fi
echo "  includes     symbols $(cat .cache/symbols/last/before) -> $(cat .cache/symbols/last/after), and the set is IDENTICAL as a cmp -- this phase frees nothing and nothing arrives, which is what removing a header that supplied nothing must do; main is still the only external symbol, which is also what says phases 14 and 15 did not forget a 'static' keyword"

# --- 5. the binary, which is the whole of this phase's evidence -----------------------
# tools/phaserun.sh runs tools/zerodelta.sh on $work/zero-vim after this check, so the
# boundary's own binary is built here as every zero check builds it.
make -C "$work" clean >/dev/null 2>&1 || true
[ -e "$work/zero-vim" ] && { echo "  build        the clean did not remove zero-vim, so a 'rebuild' below could be no rebuild at all"; exit 1; }
if ! make -C "$work" >/dev/null 2>&1; then
    echo "  build        FAILED -- rerun by hand: make -C $work"
    exit 1
fi
bin="$work/zero-vim"
echo "  build        ok, $before_lines -> $(grep -c '' "$f") lines, $(stat -c%s "$bin") bytes"

wait $pid_new || { echo "  includes     the reproducible build of the output failed"; exit 1; }
old_size=$(stat -c%s "$state/old")
new_size=$(stat -c%s "$tmp/new")
# A cmp of two files that were never written passes.  Both must exist, both must be the
# size of an editor, and the one under test must be the size make just produced.
if [ "$new_size" -lt 500000 ] || [ "$old_size" -lt 500000 ]; then
    echo "  includes     one of the two binaries is $old_size / $new_size bytes, which is not an editor -- a cmp of two files nothing wrote passes"
    exit 1
fi
if [ "$new_size" != "$(stat -c%s "$bin")" ]; then
    echo "  includes     the reproducible build is $new_size bytes and make produced $(stat -c%s "$bin"): the two differ by more than a timestamp, so the comparison below would not be about this boundary"
    exit 1
fi
if ! cmp -s "$state/old" "$tmp/new"; then
    echo "  includes     THE BINARY MOVED.  This phase removes six '#include' lines and one"
    echo "               typedef and must change no code at all, so the two binaries -- the"
    echo "               input's and the output's, both built with SOURCE_DATE_EPOCH=0 and"
    echo "               the boundary's own flags -- must be the same bytes."
    echo "               $old_size in, $new_size out.  The GNU build-id note is a hash of"
    echo "               the whole image and sits near the front, so the first difference"
    echo "               below is always that note and never the change itself:"
    cmp "$state/old" "$tmp/new" 2>&1 | sed 's/^/               /'
    exit 1
fi
echo "  includes     THE BINARY IS BYTE-IDENTICAL, $new_size bytes either side -- tier 1 of CLAUDE.md's verification table, and the whole of this phase's evidence.  A byte-identical binary subsumes every screen case, every Ex-command row, every command line and every pty scenario at once, because the program that would be run is the same program; tools/zerodelta.sh --phase 16 runs next and corroborates rather than proves"
