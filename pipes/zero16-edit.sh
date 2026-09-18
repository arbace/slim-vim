#!/bin/sh
# Zero phase 16 -- the includes nothing names.  See ZERO-GOAL.md.
#
# Usage: pipes/zero16-edit.sh <work-dir> <state-dir>     (run from the repository root)
#
# `zero-vim.c` inherited EIGHTEEN preprocessor directives from `whim-vim.c`, every one
# an `#include` of a system header, and thirteen phases removed none of them.  Six are
# now needed by nothing, and this phase takes them.
#
# THREE HAVE BEEN DEAD SINCE BEFORE THE PIPELINE STARTED, and one of the three was
# missed twice:
#
#   <sys/stat.h>  supplies nothing.  Its ONE user is `typedef struct stat stat_T;`,
#                 and nothing uses `stat_T`.  Phase 13 named this header and declined
#                 it, because ZERO-GOAL.md's charter stated the directive count as a
#                 property of the pipeline.
#   <fcntl.h>     supplies nothing at all: O_RDONLY, O_WRONLY, O_CREAT, O_APPEND,
#                 O_NONBLOCK and fcntl() are at zero mentions, and have been since
#                 phase 9 freed the symbol.
#   <iconv.h>     supplies nothing at all, and NOBODY HAD NOTICED: `iconv` occurs
#                 exactly once in zero-vim.c and that once is its own `#include`
#                 line.  whim removed the conversion layer and left the header
#                 behind.  ZERO-PLAN.md 4 says "16 directives" for this cut; it is
#                 15, and this header is why.
#
# THREE MORE DIED IN PHASES 14 AND 15, which moved what they supplied inside the file:
#
#   <string.h>    the sixteen `mem*`/`str*` functions, vendored by phase 14.
#   <ctype.h>     TEN identifiers, not five.  isalnum, iscntrl, ispunct, tolower and
#                 toupper are real calls; isalpha, isdigit, isgraph, islower and
#                 isupper are musl MACROS -- `#define isalpha(a) (0 ? isalpha(a) :
#                 (((unsigned)(a)|32)-'a') < 26)` -- so they are in no `nm -u` and a
#                 survey driven by the symbol list cannot see them.  Phase 15 took
#                 all ten.
#   <wctype.h>    towlower and towupper, and `iswupper`, which was a NAME the header
#                 had to supply while being no symbol at all: its one occurrence sat
#                 directly after a `return` inside vim_isupper(), so gcc never
#                 emitted it.  Phase 15 deleted that statement rather than vendoring
#                 a function nothing calls.
#
# WHAT THIS PHASE ASSERTS IS NOT THE LIST.  The edit below states, for each of the six,
# every identifier `zero-vim.c` took from it and requires all of them at ZERO -- but
# that is the pre-flight, not the argument.  The argument is in the check, which drops
# each SURVIVING `#include` in turn and requires the compile to fail, and runs the
# identical loop on the source this phase was handed, where it must name exactly these
# six.  A list can go stale; a computation cannot.
#
# THE ONE HEADER THAT MUST NOT BE TOUCHED, and the reason is worth writing down because
# nothing else in the tree records it.  `<sys/param.h>`'s OWN contribution is `MIN` and
# `MAX`.  Everything else it supplies arrives through three levels of musl-internal
# inclusion -- measured with `gcc -E -H`:
#
#     sys/param.h -> sys/resource.h -> sys/time.h -> sys/select.h
#
# and `select`, `gettimeofday`, `fd_set`, `FD_SET`, `FD_ZERO`, `FD_ISSET`,
# `struct timeval` and every `*_MAX` are supplied by NO OTHER HEADER IN THIS FILE --
# measured, one probe per identifier against each of the eighteen.  `zero-vim.c` has no
# `<limits.h>`, no `<sys/time.h>` and no `<sys/select.h>`.  That is a real fragility and
# it is recorded rather than repaired: repairing it means ADDING three directives, and
# the charter says no phase adds one.  If musl ever reorganises those headers the build
# breaks outright, which is the loud failure and the acceptable one.
#
# THE TYPEDEF GOES IN THE SAME EDIT AS ITS HEADER, and that is the one thing here that
# is not optional.  `typedef struct stat stat_T;` with no `<sys/stat.h>` COMPILES
# CLEANLY -- it simply declares a new, incomplete `struct stat` at file scope -- and is
# a lie: `sizeof(stat_T)` is then an error.  It is the only silent drop in this file.
#
# AND THE SWEEP CANNOT TAKE IT, for two textual reasons, both measured.
# tools/typereach.py takes as roots every identifier mentioned outside a type
# definition, and this definition's name set is {stat, stat_T}.  It is kept alive by
# (a) update_search_stat()'s local variable `searchstat_T stat;` and (b) THE
# `#include <sys/stat.h>` LINE ITSELF, whose text contains the token `stat`.  Measured:
# typereach.py says `0 unreachable` on the committed file, `0 unreachable` with only the
# include gone, `0 unreachable` with only the local renamed, and `1 unreachable --
# stat,stat_T` only when both are gone.  Thirteen sweeps have left it.  It goes here.
#
# ONE BLANK LINE GOES WITH IT.  The typedef sits between two blank lines, so deleting
# the line alone leaves a run of two, which CLAUDE.md states this tree does not have.
# tools/canon.sh would collapse it in the sweep; the edit does it, so the text the sweep
# is handed is already right.
#
# THE INPUT BINARY IS BUILT HERE with SOURCE_DATE_EPOCH=0, and that is this phase's
# whole evidence.  Nothing below changes a line of code, so the check does not offer
# behavioural probes: it rebuilds the output the same way and requires the two binaries
# to be THE SAME BYTES.  That is tier 1 of CLAUDE.md's verification table, and it
# subsumes every probe a recording could make.  SOURCE_DATE_EPOCH is required because
# version.c's `__DATE__ " " __TIME__` otherwise moves between any two builds -- measured,
# two ordinary builds of the same bytes differ at char 633.  The file name is not
# required: zero-vim.c names no __FILE__ and no __LINE__ -- measured, the same source
# built under two different names is identical.
set -eu

work=${1:?usage: zero16-edit.sh <work-dir> <state-dir>}
state=${2:?usage: zero16-edit.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"

# The flags are read out of the boundary's makefile rather than written here a
# second time: zero's compile line is the boundary's (ZERO-GOAL.md rule 8).
cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")
cp "$f" "$state/old.c"
# shellcheck disable=SC2086
( cd "$state" && SOURCE_DATE_EPOCH=0 gcc $cflags $ldflags -o old old.c ) &
pid_old=$!

python3 - "$f" <<'PY'
TAG = 'includes'
import re, sys
path = sys.argv[1]
t = open(path, errors='surrogateescape').read()


def die(msg):
    sys.exit('  %-12s %s' % (TAG, msg))


def say(what):
    print('  %-12s %s' % (TAG, what))


def mentions(text, name):
    return len(re.findall(r'\b%s\b' % name, text))


def blank_runs(text):
    L = text.split('\n')
    return sum(1 for i in range(1, len(L)) if L[i] == '' and L[i - 1] == '')


# ---- 0. the file this edit was written against ------------------------------------
# EVERY DIRECTIVE IS AN #include OF A SYSTEM HEADER, they are the first lines of the
# file, and there are eighteen.  ZERO-GOAL.md's charter is that sentence, and this is
# where it is checked rather than believed.
lines = t.split('\n')
directives = [(i, l) for i, l in enumerate(lines) if l.startswith('#')]
if len(directives) != 18:
    die('the file has %d preprocessor directives, expected 18 -- the charter says '
        'zero-vim.c inherited eighteen from whim-vim.c and that no phase adds one'
        % len(directives))
if [i for i, _ in directives] != list(range(18)):
    die('the eighteen directives are not the first eighteen lines of the file')
INC = re.compile(r'^#include <([A-Za-z0-9_/.]+)>$')
headers = []
for _, l in directives:
    m = INC.match(l)
    if not m:
        die('not an #include of a system header, and no phase may add one: %r' % l)
    headers.append(m.group(1))
if len(set(headers)) != 18:
    die('a header is included twice: %s' % ' '.join(sorted(headers)))
body = '\n'.join(lines[18:])
say('eighteen directives, every one an `#include <...>` of a system header and every '
    'one of them among the first eighteen lines -- the charter, checked rather than '
    'believed')

# ---- 1. what zero-vim.c takes from each of the six, and it must be NOTHING ----------
# This is the pre-flight and not the argument.  The argument is the check's loop, which
# drops every surviving include in turn and requires the compile to fail; a list of
# identifiers can go stale and a compile cannot.  The list is here because it says WHY
# each header is dead, which a compiler error does not.
GONE = [
    ('sys/stat.h', 'nothing: `struct stat` is named once, in a typedef nothing uses',
     'fstat lstat chmod fchmod ftruncate mkdir umask st_mode st_size st_mtim st_ino '
     'st_dev S_ISDIR S_IFMT S_IRUSR S_IWUSR'),
    ('fcntl.h', 'nothing at all -- phase 9 freed the symbol and left the header',
     'fcntl creat openat O_RDONLY O_WRONLY O_RDWR O_CREAT O_TRUNC O_APPEND O_EXCL '
     'O_NONBLOCK O_NOFOLLOW F_GETFD F_SETFD F_GETFL F_SETFL FD_CLOEXEC AT_FDCWD'),
    ('iconv.h', 'nothing at all -- whim removed the conversion layer and left the '
     'header, and nobody had noticed',
     'iconv iconv_t iconv_open iconv_close'),
    ('string.h', 'the sixteen mem*/str* functions, which phase 14 vendored',
     'memchr memcmp memcpy memmove memset strcasecmp strcat strchr strcmp strcpy '
     'strlen strncasecmp strncmp strncpy strpbrk strstr'),
    ('ctype.h', 'TEN identifiers, which phase 15 vendored -- five real calls and the '
     'five musl MACROS a survey driven by nm -u cannot see',
     'isalnum isalpha iscntrl isdigit isgraph islower ispunct isupper tolower '
     'toupper'),
    ('wctype.h', 'towlower and towupper, vendored by phase 15, and iswupper, which '
     'phase 15 deleted: a NAME with no symbol, on a line gcc never emitted',
     'iswupper towlower towupper'),
]
# EVERY LIST ABOVE IS THE MEASURED SET AND NOTHING SPECULATIVE, and there is a trap
# behind that rule.  An obvious "while we are here" addition to the ctype list is
# `isprint`, `isspace`, `isblank`, `isxdigit` -- and `isprint` OCCURS IN THIS FILE, as
# the name of the 'isprint' option in a string literal (`{"isprint", "isp", ...}`).  A
# list written from what a header offers rather than from what this file was measured
# to take refuses on a correct phase, and the message would be about ctype.
for header, why, ids in GONE:
    line = '#include <%s>\n' % header
    if t.count(line) != 1:
        die('`%s` occurs %d times, expected 1' % (line.strip(), t.count(line)))
    live = [i for i in ids.split() if mentions(body, i)]
    if live:
        die('<%s> is NOT unused: %s -- this phase removes a header only when '
            'zero-vim.c names nothing it supplies, and the phase that was to take '
            'these has not run or did not finish'
            % (header, ', '.join('%s (%d)' % (i, mentions(body, i)) for i in live)))
    say('<%-12s %s' % (header + '>', why))

# THE ONE EXCEPTION, and it is the only silent drop in this file.  `struct stat` IS
# named once, by a typedef, and a typedef of an undeclared struct tag compiles cleanly
# -- it declares a new, incomplete type -- so removing <sys/stat.h> alone would leave a
# lie that only `sizeof(stat_T)` could expose.
if mentions(body, 'stat_T') != 1:
    die('stat_T has %d mentions, expected 1 -- its own typedef and no user'
        % mentions(body, 'stat_T'))
if len(re.findall(r'\bstruct\s+stat\b', body)) != 1:
    die('`struct stat` occurs %d times, expected 1 -- the typedef'
        % len(re.findall(r'\bstruct\s+stat\b', body)))

# ---- 2. the twelve that stay, and the one that must not be touched ------------------
KEEP = ['stdio.h', 'stdlib.h', 'unistd.h', 'sys/param.h', 'time.h', 'signal.h',
        'errno.h', 'stdint.h', 'stdarg.h', 'stddef.h', 'sys/ioctl.h', 'termios.h']
if sorted(headers) != sorted(KEEP + [h for h, _, _ in GONE]):
    die('the eighteen headers are not the twelve this phase keeps and the six it '
        'takes: %s' % ' '.join(sorted(headers)))
# TWO OF THE TWELVE ARE HELD BY ALMOST NOTHING, and those are counted exactly, because
# the count IS the statement: a later phase that took them would find this check's loop
# reporting a dead include.  <stddef.h> is held by `offsetof` ALONE, nine mentions --
# `size_t` and `NULL` come from six of the twelve.  <stdint.h> is held by exactly TWO
# identifiers at one mention each: `SIZE_MAX`, which has held it all along, and
# `uintptr_t`, WHICH PHASE 14 BROUGHT -- the first thing in this pipeline's history to
# make a header MORE held rather than less, and the reason the number here is two and
# not one.  The other ten are checked for presence only: the check's loop is what proves
# each is needed, and an exact count of `select` or `stderr` here would be a number this
# phase has no argument for.
THIN = {'SIZE_MAX': 1, 'uintptr_t': 1, 'offsetof': 9}
for name, want in sorted(THIN.items()):
    k = mentions(body, name)
    if k != want:
        die('%s has %d mentions, expected %d -- it is one of the two or three things '
            'holding its header, so the count is the statement' % (name, k, want))
for name in ('MIN', 'MAX', 'select', 'gettimeofday', 'va_arg', 'tcgetattr', 'ioctl',
             'nanosleep', 'errno', 'malloc', 'printf', 'sigaction'):
    if not mentions(body, name):
        die('%s is named nowhere, so a header this phase KEEPS may be dead too -- '
            'the check drops every survivor in turn and would say which' % name)
say('the twelve that stay, each held by something this file still names: <stddef.h> '
    'by offsetof alone, <stdint.h> by SIZE_MAX and by the uintptr_t phase 14 brought, '
    'and <sys/param.h> by MIN and '
    'MAX -- plus, through sys/resource.h -> sys/time.h -> sys/select.h and no other '
    'header in this file, select, gettimeofday, fd_set, struct timeval and every '
    '*_MAX.  That chain is musl\'s and is recorded rather than repaired: repairing it '
    'means ADDING <limits.h>, <sys/time.h> and <sys/select.h>, and no phase adds a '
    'directive')

# ---- 3. the cut: six lines, the typedef, and one blank ------------------------------
runs_before = blank_runs(t)
for header, _, _ in GONE:
    t = t.replace('#include <%s>\n' % header, '', 1)
say('the six `#include` lines')

# The typedef AND one of its two blank lines: deleting the line alone leaves a run of
# two blank lines, which CLAUDE.md states this tree does not have.  canon.sh in the
# sweep would collapse it; doing it here means the text the sweep is handed is right.
OLD = '\ntypedef struct stat stat_T;\n\n'
if t.count(OLD) != 1:
    die('the stat_T typedef is not one line between two blank lines, so the blank '
        'that goes with it cannot be identified: %d matches' % t.count(OLD))
t = t.replace(OLD, '\n', 1)
say('and `typedef struct stat stat_T;` with one of its two blank lines -- the sweep '
    'has never been able to take it, because typereach.py reads the token `stat` in '
    'the `#include <sys/stat.h>` line itself, and in update_search_stat()\'s local '
    'variable, as roots')

# ---- 4. what the file is now --------------------------------------------------------
lines = t.split('\n')
directives = [(i, l) for i, l in enumerate(lines) if l.startswith('#')]
if len(directives) != 12 or [i for i, _ in directives] != list(range(12)):
    die('the file does not have exactly twelve directives on its first twelve lines '
        'after the cut: %d directives at lines %s'
        % (len(directives), ' '.join(str(i) for i, _ in directives)))
if [INC.match(l).group(1) if INC.match(l) else l for _, l in directives] != KEEP:
    die('the twelve that are left are not the twelve this phase keeps, in order')
body = '\n'.join(lines[12:])
if mentions(body, 'stat_T'):
    die('stat_T survives the cut')
if re.search(r'\bstruct\s+stat\b', body):
    die('`struct stat` survives the cut, and with no <sys/stat.h> it would be an '
        'incomplete type nothing declares')
if blank_runs(t) != runs_before:
    die('the cut left %d runs of two blank lines where there were %d'
        % (blank_runs(t), runs_before))
say('twelve directives, every one an `#include <...>`, on the first twelve lines; '
    'stat_T and `struct stat` at zero; and %d runs of two blank lines, exactly as '
    'before' % blank_runs(t))

open(path, 'w', errors='surrogateescape').write(t)
PY

# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  includes     the input binary did not build with '$cflags' '$ldflags'"; exit 1; }
echo "  includes     the input is $state/old, $(stat -c%s "$state/old") bytes, built with SOURCE_DATE_EPOCH=0 beside the source it came from -- this phase changes no code, so the check rebuilds the output the same way and requires THE SAME BYTES, which is tier 1 of CLAUDE.md's verification table and subsumes every probe a recording could make"

# tools/phaserun.sh sweeps next, then runs pipes/zero16-check.sh.
