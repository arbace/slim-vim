#!/bin/sh
# Zero phase 14, the check -- the strings are the editor's own.
# See pipes/zero14-edit.sh, and ZERO-GOAL.md.
#
# Usage: pipes/zero14-check.sh <work-dir> <state-dir>    (run from the repository root)
#
# Runs after pipes/zero14-edit.sh and the sweep tools/phaserun.sh runs between them,
# and reads nothing from the edit's shell -- only the work tree and the state
# directory.  What the edit left there is `old`, the binary this phase was HANDED,
# and `old.c`, the source it was built from.
#
# SIX THINGS ARE PROVED.
#
# 1. THE SOURCE, as counts.  The seventeen bare names at 0, the sixteen musl_* at
#    their source counts plus their own definitions, `sprintf` and `f_l` at 0,
#    `vim_snprintf` 55 -> 68, and `tolower` STILL AT 2.
#
#    THE `tolower` COUNT IS NOT DECORATION.  musl's strcasecmp() and strncasecmp()
#    call tolower(); these do not, and inline `(unsigned)c - 'A' < 26 ? c | 32 : c`
#    instead, which IS musl's tolower() in the C locale -- `tolower.c` is
#    `if (isupper(c)) return c | 32; return c;` and `isupper.c` is
#    `(unsigned)c-'A' < 26`.  Inlining costs nothing and keeps this phase and the
#    character-class phase independent: that phase counts `tolower` mentions, and
#    four new ones here would trip it.
#
#    THE SINGLE CALLER IS ASSERTED AGAIN HERE, and that is the point of asserting it
#    at all.  `highlight_arg_to_string(..., char_u *buf)` takes a POINTER, so
#    sizeof(buf) is 8; its size argument is MAX_ATTR_LEN, which is only its buffer's
#    size while `highlight_list_arg` is its ONLY caller and declares `char_u
#    buf[MAX_ATTR_LEN]`.  A second caller appearing later, with a smaller buffer,
#    would silently invalidate the bound and nothing else in this tree would notice.
#    So the count is pinned at 2 -- the definition and the one call -- for ever.
#
#    AND THE CHARTER: eighteen lines starting with `#`, every one an `#include <...>`,
#    and not one comment or tab added.  This phase writes 301 lines of C into
#    zero-vim.c and none of it is a directive and none of it is a comment.
#
# 2. THE LIBC SURFACE, NAMED AS A SET AND NOT AS A COUNT -- `memchr memcmp memcpy
#    memmove memset sprintf strcasecmp strcat strchr strcmp strcpy strlen strncasecmp
#    strncmp strncpy strpbrk strstr`, seventeen, and NOTHING arriving.  61 -> 44.
#
#    THIS IS THE MEASUREMENT THE PHASE TURNS ON.  gcc emits `memcpy` and `memset`
#    FOR ITSELF, for aggregate assignments and large zero initialisers, whatever the
#    source calls -- so a rename might have left both behind and forced a definition
#    under the real name, which is external linkage.  It does not happen here:
#    `gcc -S` on the swept text contains not one call to any of the seventeen.  The
#    check asserts the `nm -u` absence, so a later phase that adds an aggregate over
#    gcc's threshold (measured between 8 KiB and 16 KiB) and assigns it whole fails
#    loudly rather than quietly reacquiring a libc symbol.
#
#    ZERO-PLAN.md 4b's invariant is asserted again beside it, unchanged.
#
# 3. THE ENUMERATORS, which must not move at all: this phase deletes no type, no
#    enum and no table row, so all 1,181 must come back with the same values.
#
# 4. THE ONE MUST-DIFFER PROBE, and it is a BUG FIX.  `t_CF` is a user-settable
#    option (options[] row "t_CF") that `term_font()` uses as a FORMAT STRING into
#    `char buf[20]`.  `sprintf` has no bound.  Measured: `:set t_CF=` + 40 X + `%d`,
#    then `:highlight Search ctermfont=3` and a search, kills the binary this phase
#    was handed -- exit -11, SIGSEGV -- and exits 0 here with the output truncated to
#    nineteen characters.  It is the ONLY reachable input on which this phase changes
#    what the editor does, and the check requires BOTH halves: the old one must die
#    and the new one must not.
#
# 5. THE FORMATS THAT RENDER DIFFERENTLY, recorded rather than declared.  `t_CF` is
#    the one place a USER-SUPPLIED format reaches the formatter, and vim's own printf
#    is not musl's: `%f` goes from `[0.000000]` to `[f]`, `%b` from nothing to
#    `[1101]`, `%*d` from a garbage int to the argument, `%z` from nothing to `[z]`.
#    `%d` and `%1$d` are identical.  `%s` SEGFAULTS ON BOTH BINARIES and is not this
#    phase's: t_CF `%s` reads a pointer out of an int argument, and it did that
#    before.  Nothing in the instrument sets t_CF, t_CF is empty under every built-in
#    terminal but `debug` (where it is "[CF%d]"), and `%d` is the only directive that
#    entry uses -- so this is a finding the check records and NOT a declared delta.
#
# 6. THE PROBES THAT MUST NOT DIFFER: thirty-two sessions on both binaries, covering
#    every one of the thirteen external sprintf sites and the number formatting the
#    nine internal ones did, plus the places where strcasecmp, strncasecmp, memcmp,
#    memcpy and strstr are the only reason the screen says what it says.
#
#    WHAT NO PROBE COVERS, AND THE PHASE SAYS SO RATHER THAN PRETENDING.  Four of the
#    vendored functions are there for code that cannot run, measured by breaking each
#    and finding that nothing moves: `musl_strpbrk` (its one site needs P_NFNAME or
#    P_NDNAME, and each of those has exactly two mentions in the file -- its own enum
#    and that one test -- so no options[] row carries either), `musl_memchr` (its one
#    site is vim_vsnprintf_typval's `%.*s`, and the only `%.*s` in the file is the
#    OSC-timeout message), `musl_strchr`'s NUL arm (both call sites pass '%') and
#    `musl_fmtptr` (nothing formats a pointer).  Their correctness rests on musl's
#    source, not on the recording.
#
#    The corpus itself is tools/zerodelta.sh --phase 14, which tools/phaserun.sh runs
#    after this check, and its declaration is NOTHING AT ALL.
set -eu

work=${1:?usage: zero14-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero14-check.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"
before_lines=$(cat "$state/input-lines")

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# --- 1. the source, as counts ---------------------------------------------------------
python3 - "$f" "$state/old.c" <<'PY'
import re, sys
sys.path.insert(0, 'tools')
import create_cmdidxs
import cutil
TAG = 'strings'
new = open(sys.argv[1], errors='surrogateescape').read()
old = open(sys.argv[2], errors='surrogateescape').read()
fail = []


def count(text, name):
    """OCCURRENCES.  `grep -c` counts LINES and disagrees with eight of the
    seventeen -- strncasecmp is 13 occurrences on 7 lines."""
    return len(re.findall(r'\b%s\b' % name, text))


SEVENTEEN = ['memmove', 'strlen', 'memset', 'strncmp', 'strcmp', 'strcpy', 'sprintf',
             'memcpy', 'strncasecmp', 'strcat', 'strcasecmp', 'strncpy', 'strstr',
             'strchr', 'memcmp', 'memchr', 'strpbrk']

# The input is the file the edit's anchors were counted against.
INPUT = {'memmove': 159, 'strlen': 127, 'memset': 79, 'strncmp': 82, 'strcmp': 62,
         'strcpy': 51, 'sprintf': 22, 'memcpy': 7, 'strncasecmp': 13, 'strcat': 6,
         'strcasecmp': 6, 'strncpy': 4, 'strstr': 3, 'strchr': 2, 'memcmp': 2,
         'memchr': 1, 'strpbrk': 2, 'vim_snprintf': 55, 'tolower': 2}
for name, want in sorted(INPUT.items()):
    if count(old, name) != want:
        fail.append('the input is not the file this phase was written against: '
                    '%s %d, expected %d' % (name, count(old, name), want))

# NOT ONE BARE NAME SURVIVES.  `(?<!_)` is what keeps musl_strlen and vim_snprintf
# from answering for strlen and sprintf.
for name in SEVENTEEN:
    k = len(re.findall(r'(?<!_)\b%s\b' % name, new))
    if k:
        fail.append('%s survives as a bare libc name %d times' % (name, k))

# And what replaced them, as counts: the source count plus the definition, plus the
# internal uses (musl_strlen is used by musl_strcat and by four size arguments,
# musl_strcpy by musl_strcat).
AFTER = {'musl_memmove': 160, 'musl_strlen': 133, 'musl_memset': 80,
         'musl_strncmp': 83, 'musl_strcmp': 63, 'musl_strcpy': 53, 'musl_memcpy': 8,
         'musl_strncasecmp': 14, 'musl_strcat': 7, 'musl_strcasecmp': 7,
         'musl_strncpy': 5, 'musl_strstr': 4, 'musl_strchr': 3, 'musl_memcmp': 3,
         'musl_memchr': 2, 'musl_strpbrk': 3,
         'musl_fmtnum': 9, 'musl_fmtptr': 2, 'musl_fmtbase': 5,
         'vim_snprintf': 68, 'vim_vsnprintf_typval': 4,
         'f_l': 0,
         # `tolower` IS THE CHARACTER-CLASS PHASE'S AND THIS PHASE ADDS NONE.
         'tolower': 2,
         # the single caller the MAX_ATTR_LEN bound rests on
         'highlight_arg_to_string': 2, 'highlight_list_arg': 11, 'MAX_ATTR_LEN': 3}
for name, want in sorted(AFTER.items()):
    k = count(new, name)
    if k != want:
        fail.append('%s has %d mentions, expected %d' % (name, k, want))

# THE BOUND, READ RATHER THAN COUNTED.  Two mentions could in principle be two calls
# and no definition, so the definition and the caller's local are matched as text.
if not re.search(r'^highlight_arg_to_string\(int .*char_u      \*buf\)$', new, re.M):
    fail.append('highlight_arg_to_string is not defined with a char_u *buf parameter')
if new.count('    ts = highlight_arg_to_string(type, iarg, sarg, buf);\n') != 1:
    fail.append('highlight_arg_to_string is not called exactly once from '
                'highlight_list_arg, and MAX_ATTR_LEN is only its size while that is '
                'true -- a second caller with a smaller buffer would make the bound '
                'wrong and nothing else here would see it')
if new.count('    char_u      buf[MAX_ATTR_LEN];\n') != 1:
    fail.append("highlight_list_arg's `char_u buf[MAX_ATTR_LEN];` is gone, and it is "
                'where site 25443\'s bound comes from')
if 'vim_snprintf((char *)buf, MAX_ATTR_LEN, "%d", iarg - 1);' not in new:
    fail.append('site 25443 does not use MAX_ATTR_LEN as its bound')

# THE THIRTEEN, each asserted present by its size argument rather than by a count.
for what, needle in [
        ('update_wincolor', 'vim_snprintf((char *)str, sizeof("!(:") +  musl_strlen((char *)(opt)) ,'),
        ('show_one_mark', 'vim_snprintf((char *)IObuff,  (1024+1) , " %c %6ld %4d ",'),
        ('ex_changes', 'vim_snprintf((char *)IObuff,  (1024+1) , "%c %3d %5ld %4d ",'),
        ('do_ascii', 'vim_snprintf((char *)IObuff + rlen, (size_t)( (1024+1)  - rlen), "%02x ",'),
        ('get_emsg_source', 'vim_snprintf((char *)Buf,  musl_strlen((char *)(sname))  +  musl_strlen((char *)(p)) ,'),
        ('get_emsg_lnum', 'vim_snprintf((char *)Buf,  musl_strlen((char *)(p))  + 20,'),
        ('option_value2string', 'vim_snprintf((char *)NameBuff, PATH_MAX, "%ld",'),
        ('deadly_signal', 'vim_snprintf((char *)IObuff,  (1024+1) , "Vim: Caught deadly signal'),
        ('recording_mode', 'vim_snprintf(s, sizeof(s), " @%c", reg_recording);'),
        ('set_color_count', 'vim_snprintf((char *)nr_colors, sizeof(nr_colors), "%d", t_colors);'),
        ('term_font', 'vim_snprintf(buf, sizeof(buf), (char *) ( term_strings[(int)(KS_CF)] ) , 9 + n);'),
        ('term_color', 'vim_snprintf(buf, sizeof(buf), format, lead, tail);')]:
    if new.count(needle) != 1:
        fail.append('%s does not call vim_snprintf with the size its destination '
                    'really has' % what)

# THE CASE FOLD IS INLINED AND IS musl's tolower(), not a simplification of it.
# The body is found with cutil.find_definition and not by searching for a header
# spelled out here: zero-vim.c puts the return type on its own line and the NAME at
# column 0, which is what tools/funcreach.py's definition regex reads, and a locator
# that knew the header's text would go stale the moment the style did.
for fn in ('musl_strcasecmp', 'musl_strncasecmp'):
    span = cutil.find_definition(new, fn)
    body = new[span[0]:span[1]] if span else ''
    if body.count("(unsigned)*l - 'A' < 26 ? *l | 32 : *l") != 2 \
            or body.count("(unsigned)*r - 'A' < 26 ? *r | 32 : *r") != 2:
        fail.append('%s does not inline the C-locale tolower -- musl tolower.c is '
                    '`if (isupper(c)) return c | 32; return c;` and isupper.c is '
                    "`(unsigned)c-'A' < 26`, and the cast is what keeps a byte over "
                    '127 out of the range test' % fn)

# THE CHARTER.  Eighteen directives, all #include; no comment and no tab added.
directives = [l for l in new.split('\n') if l.startswith('#')]
if len(directives) != 18 or any(not l.startswith('#include <') for l in directives):
    fail.append('the file has %d lines starting with #, and ZERO-GOAL.md says '
                'eighteen #includes and nothing else' % len(directives))
for tok, name in (('/*', 'a block comment'), ('\t', 'a tab')):
    if new.count(tok) != old.count(tok):
        fail.append('%s count moved %d -> %d, and this phase writes 301 lines of C '
                    'with neither' % (name, old.count(tok), new.count(tok)))
if new.count('//') != old.count('//'):
    fail.append('`//` count moved %d -> %d' % (old.count('//'), new.count('//')))

# THE TABLES, neither of which this phase touches.
rows = re.findall(r'^    \[CMD_\w+\] = \{.*$', new, re.M)
got = create_cmdidxs.names(sys.argv[1])
if len(rows) != 98 or len(got) != 98:
    fail.append('cmdnames[] has %d rows and names() reads %d; both must be 98'
                % (len(rows), len(got)))
i = new.find('static struct vimoption options[]')
j = new.index('\n};', i)
if len(re.findall(r'^[ \t]*\{"([a-z]+)",', new[i:j], re.M)) != 108:
    fail.append('options[] is not the 108 rows phase 12 left')

# THE FOUR THAT NO PROBE CAN REACH, asserted as the reason rather than as a hope.
for flag in ('P_NFNAME', 'P_NDNAME'):
    if count(new, flag) != 2:
        fail.append('%s has %d mentions, expected 2 -- its own enum and the one test '
                    'in musl_strpbrk\'s only caller.  If an options[] row ever '
                    'carries it, musl_strpbrk stops being unreachable and this '
                    "phase's claim about it has to be re-measured" % (flag, count(new, flag)))
if len(re.findall(r'%\.\*s', new)) != 1:
    fail.append('there is no longer exactly one `%.*s` in the file, and it was the '
                'only thing that could reach musl_memchr')

if fail:
    for line in fail:
        print('  %-12s %s' % (TAG, line))
    sys.exit(1)
print('  %-12s the seventeen bare names at 0 and the sixteen musl_* at their source '
      'counts; sprintf and f_l at 0 and vim_snprintf 55 -> 68; tolower STILL AT 2, '
      'the case fold being musl\'s C-locale tolower inlined, so the character-class '
      'phase counts what it counted before' % TAG)
print('  %-12s highlight_arg_to_string has ONE caller and MAX_ATTR_LEN is its bound '
      'only while that holds -- pinned at two mentions, the definition and the call'
      % '')
print('  %-12s eighteen #include lines and no other directive, no comment and no tab '
      'added; cmdnames[] 98 rows, options[] 108, both untouched' % '')
PY

# --- 2. the compile, the linkage and the libc surface -----------------------------------
# SEVENTEEN GO AND THE SET IS NAMED, not the count.  Nothing may arrive: a vendored
# function that reached for something else would show up here and nowhere else.
cp "$state/symbols/undefined" "$tmp/before.u"
tools/phasecheck.sh "$work" "$f" "$state/symbols"
comm -23 "$tmp/before.u" .cache/symbols/last/undefined > "$tmp/gone.u"
comm -13 "$tmp/before.u" .cache/symbols/last/undefined > "$tmp/came.u"
printf 'memchr\nmemcmp\nmemcpy\nmemmove\nmemset\nsprintf\nstrcasecmp\nstrcat\nstrchr\nstrcmp\nstrcpy\nstrlen\nstrncasecmp\nstrncmp\nstrncpy\nstrpbrk\nstrstr\n' > "$tmp/want.u"
if ! cmp -s "$tmp/gone.u" "$tmp/want.u" || [ -s "$tmp/came.u" ]; then
    echo "  strings      the libc surface did not move by exactly the seventeen string and memory symbols:"
    echo "               gone: $(tr '\n' ' ' < "$tmp/gone.u")"
    echo "               came: $(tr '\n' ' ' < "$tmp/came.u")"
    exit 1
fi
# gcc DOES NOT EMIT ONE OF THEM FOR ITSELF IN THIS FILE, and that is the fact the
# whole phase turns on.  Asserted from the assembly as well as from nm: a large
# aggregate assignment would put `call memcpy` back without any source line saying so.
gcc -S -O0 -fno-stack-protector -o "$tmp/z.s" "$f"
if grep -qE 'call[[:space:]]+(memcpy|memset|memmove|strlen|sprintf|strcpy|strcat|strcmp|strncmp|strchr|strstr|memchr|memcmp|strncpy|strcasecmp|strncasecmp|strpbrk)\b' "$tmp/z.s"; then
    echo "  strings      gcc emitted a call to one of the seventeen that no source line writes:"
    grep -oE 'call[[:space:]]+(memcpy|memset|memmove|strlen|sprintf|strcpy|strcat|strcmp|strncmp|strchr|strstr|memchr|memcmp|strncpy|strcasecmp|strncasecmp|strpbrk)\b' "$tmp/z.s" | sort | uniq -c | sed 's|^|               |'
    echo "               That is an aggregate assignment or a large zero initialiser"
    echo "               over gcc's -O0 threshold, which is between 8 KiB and 16 KiB."
    exit 1
fi
# THE TERMINAL, THE MESSAGE LAYER AND gcc's OWN STAY, and none of them is this
# phase's.  `tolower` and `toupper` are the character-class phase's and must be here.
for keep in read write close dup ioctl select tcgetattr tcsetattr nanosleep isatty \
            printf fflush stderr fputs fputc fwrite putchar __errno_location \
            malloc free realloc tolower toupper towlower towupper qsort bsearch; do
    grep -qx "$keep" .cache/symbols/last/undefined \
        || { echo "  strings      $keep went, and it is not this phase's: this phase is string and memory work and takes nothing else"; exit 1; }
done
# ZERO-PLAN.md 4b's INVARIANT, unchanged and asserted again.
for absent in open creat openat stat access fcntl getcwd strerror fopen fdopen \
              opendir chmod fchmod fstat lstat unlink ftruncate fclose getc putc fsync; do
    if grep -qx "$absent" .cache/symbols/last/undefined; then
        echo "  strings      $absent is undefined, and the core has neither a way to open a file nor a stdio stream since phase 13"; exit 1
    fi
done
echo "  strings      symbols $(cat .cache/symbols/last/before) -> $(cat .cache/symbols/last/after), and the set is exactly the seventeen -- with NOT ONE call to any of them left in the assembly, so gcc emits none of them for itself here and nothing had to be defined under a real name"

# --- 3. the enumerators, which must not move at all -------------------------------------
tools/enumvals.sh "$state/old.c" "$tmp/ev.old" &
pid_ev=$!
tools/enumvals.sh "$f" "$tmp/ev.new"
wait $pid_ev
python3 - "$tmp/ev.old" "$tmp/ev.new" <<'PY'
import sys
TAG = 'strings'
o = dict(l.rsplit('=', 1) for l in open(sys.argv[1]).read().splitlines())
n = dict(l.rsplit('=', 1) for l in open(sys.argv[2]).read().splitlines())
gone, came = sorted(set(o) - set(n)), sorted(set(n) - set(o))
moved = sorted(k for k in set(o) & set(n) if o[k] != n[k])
if gone or came or moved:
    for what, names in (('went', gone), ('arrived', came), ('renumbered', moved)):
        if names:
            print('  %-12s enumerators %s: %s -- this phase deletes no type, no enum '
                  'and no table row, so not one may move'
                  % (TAG, what, ' '.join(names)))
    sys.exit(1)
print('  %-12s enumerators %d -> %d, not one value moved: this phase adds functions '
      'and renames call sites and touches no type, no enum and no table' % (TAG, len(o), len(n)))
PY

# --- 4. the binary ----------------------------------------------------------------------
make -C "$work" clean >/dev/null 2>&1 || true
if ! make -C "$work" >/dev/null 2>&1; then
    echo "  build        FAILED -- rerun by hand: make -C $work"
    exit 1
fi
bin="$work/zero-vim"
echo "  build        ok, $before_lines -> $(grep -c '' "$f") lines, $(stat -c%s "$bin") bytes"

# --- 5, 6 and 7: what the two binaries do ------------------------------------------------
python3 - "$state/old" "$bin" <<'PY'
import concurrent.futures
import hashlib
import sys

sys.path.insert(0, 'tools')
import zrec
import zstream

TAG = 'strings'
ESC, CR, CG, CA = b'\x1b', b'\r', b'\x07', b'\x01'
QUIT = ESC + b':q!' + CR
old_bin, new_bin = sys.argv[1], sys.argv[2]
fail = []


def seed(text):
    return [b'i' + text + ESC, b':set nopaste' + CR]


def run(binary, args, keys):
    try:
        scr, out, err, rc = zstream.session(binary, keys, args=args)
    except zstream.Blocked:
        return None
    text = zrec.section('exit %s' % rc)
    text += zrec.section('bells %d' % scr.bells)
    text += zrec.section('stream %d sha=%s'
                         % (len(out), hashlib.sha256(out).hexdigest()[:16]))
    text += zrec.section('stderr', err.decode('utf-8', 'replace').rstrip('\n'))
    for i, (dump, y, x, bells) in enumerate(scr.snaps):
        text += zrec.section('snap %d cursor=%d,%d bells=%d' % (i, y, x, bells), dump)
    return rc, zrec.scrub(text), scr.snaps[-1][0].split('\n')[0] if scr.snaps else ''


# ---- 5. THE MUST-DIFFER PROBE, and it is a bug fix ------------------------------------
# t_CF is a user-settable option that term_font() uses as a FORMAT STRING into
# char buf[20].  sprintf has no bound; vim_snprintf does.
LONG = b'X' * 40 + b'%d'
OVERFLOW = (['+set paste'],
            seed(b'aaa bbb') + [b':set t_CF=' + LONG + CR,
                                b':highlight Search ctermfont=3' + CR,
                                b'/aaa' + CR, b':redraw!' + CR, QUIT])


# ---- 6. THE FORMATS THAT RENDER DIFFERENTLY, recorded rather than declared ------------
def tcf(fmt):
    return (['+set paste'],
            seed(b'aaa') + [b':set t_CF=' + fmt + CR,
                            b':highlight Search ctermfont=3' + CR,
                            b'/aaa' + CR, b':redraw!' + CR, QUIT])


# ---- 7. THE PROBES THAT MUST NOT DIFFER ------------------------------------------------
# Every one of the thirteen external sprintf sites, the number formatting the nine
# internal ones did, and the functions the 106-record corpus does not exercise.
LINES = b'\r'.join(b'x%d' % i for i in range(1, 40))
PROBES = [
    # site 25443, highlight_arg_to_string's "%d"
    ('hl_list',       ['+set paste'], seed(b'x'), [b':highlight' + CR, b'q']),
    ('hl_one',        ['+set paste'], seed(b'x'), [b':highlight Search' + CR, CR]),
    # site 28705, :marks -- and the one probe a wrong SIZE argument moves
    ('marks_many',    ['+set paste'], seed(b'aaa\rbbb\rccc\rddd'),
     [b'ma', b'jmb', b'jmc', b':marks' + CR, CR]),
    # site 28821, :changes
    ('changes',       ['+set paste'], seed(b'one\rtwo\rthree\rfour'),
     [b'ciwX' + ESC, b'jciwY' + ESC, b'jciwZ' + ESC, b':changes' + CR, CR]),
    # site 32356, ga's "%02x " at an offset into IObuff
    ('ga_ascii',      ['+set paste'], seed(b'A'), [b'0ga']),
    ('ga_multi',      ['+set paste'], seed(b'\xc3\xa9'), [b'0ga']),
    ('ga_combining',  ['+set paste'], seed(b'e\xcc\x81'), [b'0ga']),
    # site 53866, option_value2string's "%ld" into NameBuff
    ('set_num',       ['+set paste'], seed(b'x'),
     [b':set sw?' + CR, CR, b':set ts?' + CR, CR, b':set ul?' + CR, CR]),
    ('set_all',       ['+set paste'], seed(b'x'), [b':set all' + CR, b'q']),
    ('set_neg',       ['+set paste'], seed(b'x'),
     [b':set scrolloff=-1' + CR, b':set so?' + CR, CR]),
    ('set_big',       ['+set paste'], seed(b'x'),
     [b':set undolevels=123456789' + CR, b':set ul?' + CR, CR]),
    # site 66335, recording_mode's " @%c" into char s[4], which it fills exactly
    ('recording',     ['+set paste'], seed(b'abc'), [b'qq', b'x', b'q']),
    ('recording_reg', ['+set paste'], seed(b'abc'), [b'qZ', b'x', b'q', b'@Z']),
    # sites 71820 and 72398, the terminal table and t_CF used properly
    ('term_query',    ['+set paste'], seed(b'x'),
     [b':set term?' + CR, CR, b':set t_Co?' + CR, CR]),
    ('term_cf',       ['+set paste'], seed(b'x'),
     [b':set t_CF=[CF%d]' + CR, b':set t_CF?' + CR, CR]),
    # the nine internal conversions: every number the editor prints
    ('ctrl_g',        ['+set paste'],
     seed(b'\r'.join(b'line%d' % i for i in range(1, 60))), [b'30G', CG, CR]),
    ('search_count',  ['+set paste'],
     seed(b'\r'.join(b'aaa bbb aaa' for _ in range(20))),
     [b'gg', b'/aaa' + CR, b'n', b'n', b'n']),
    ('subst_count',   ['+set paste'],
     seed(b'\r'.join(b'aaa bbb aaa' for _ in range(30))),
     [b':%s/aaa/ZZZ/g' + CR, CR]),
    ('lines_report',  ['+set paste'], seed(LINES), [b'gg', b'20dd', CR]),
    ('shift_report',  ['+set paste'], seed(LINES), [b'gg', b'20>>', CR]),
    ('undo_report',   ['+set paste'], seed(LINES), [b'gg', b'15dd', b'u', CR]),
    ('e_number',      ['+set paste'], seed(b'x'), [b':nosuchcommandhere' + CR, CR]),
    ('ruler',         ['+set paste', '+set ruler'],
     seed(b'\r'.join(b'a longer line number %d' % i for i in range(1, 40))),
     [b'25G', b'$']),
    ('percent_ruler', ['+set paste', '+set ruler'],
     seed(b'\r'.join(b'x%d' % i for i in range(1, 200))), [b'100G']),
    # musl_strcmp, musl_strncmp, musl_strcpy, musl_strcat, musl_strstr territory
    ('map_list',      ['+set paste'], seed(b'x'), [b':map' + CR, CR]),
    ('registers',     ['+set paste'], seed(b'aaa\rbbb'),
     [b'yy', b'jyy', b':registers' + CR, b'q']),
    ('history',       ['+set paste'], seed(b'x'),
     [b':set sw=2' + CR, b':set sw=3' + CR, b':history' + CR, b'q']),
    ('version',       ['+set paste'], seed(b'x'), [b':version' + CR, b'q']),
    ('nrformats',     ['+set paste'], seed(b'0x0f 017 99 -1'),
     [b'0' + CA, b'w' + CA, b'w' + CA, b'w' + CA]),
    # musl_strncasecmp's CASE FOLD, which nothing else here reaches: measured, a
    # version that compares exactly instead moves these two and nothing else.
    ('hist_case',     ['+set paste'], seed(b'x'),
     [b':set sw=2' + CR, b':history SEARCH' + CR, b'q']),
    ('hist_case_all', ['+set paste'], seed(b'x'),
     [b':set sw=2' + CR, b':history ALL' + CR, b'q']),
    # musl_memcmp, whose two sites are :highlight's did_change test and undo:
    # measured, a memcmp that never says "equal" moves this and nothing else.
    ('hi_change_twice', ['+set paste'], seed(b'x'),
     [b':highlight Search ctermfg=1' + CR, b':highlight Search ctermfg=1' + CR,
      b':highlight Search' + CR, CR]),
    # musl_memcpy, whose reachable sites are the window-local highlight copies
    ('winhighlight',  ['+set paste'], seed(b'aaa\rbbb'),
     [b':set winhighlight=Normal:Search' + CR, b'/aaa' + CR, b':redraw' + CR]),
]

TCF = [b'[%f]', b'[%b]', b'[%*d]', b'[%z]', b'[%d]', b'[%1$d]']
jobs = ([('OVERFLOW', b, OVERFLOW) for b in (old_bin, new_bin)]
        + [('TCF' + fmt.decode(), b, tcf(fmt)) for fmt in TCF for b in (old_bin, new_bin)]
        + [(n, b, (a, list(pre) + list(keys) + [QUIT]))
           for n, a, pre, keys in PROBES for b in (old_bin, new_bin)])


def one(job):
    name, binary, (args, keys) = job
    return name, binary, run(binary, args, keys)


with concurrent.futures.ThreadPoolExecutor(max_workers=min(len(jobs), 64)) as ex:
    res = {(n, b): r for n, b, r in ex.map(one, jobs)}

# ---- 5. the overflow ------------------------------------------------------------------
o, n = res[('OVERFLOW', old_bin)], res[('OVERFLOW', new_bin)]
if o is None or n is None:
    fail.append('the t_CF overflow probe blocked, so it says nothing either way')
else:
    if o[0] != -11:
        fail.append('t_CF overflow: the binary this phase was handed exited %s and '
                    'not -11.  sprintf writing 42 bytes into char buf[20] is what '
                    'this phase fixes, and a check that cannot see it happening is '
                    'not evidence that it stopped' % (o[0],))
    if n[0] != 0:
        fail.append('t_CF overflow: this phase\'s binary exited %s, and vim_snprintf '
                    'must truncate into buf[20] and carry on' % (n[0],))
    if not n[2].startswith('X' * 19 + 'aaa'):
        fail.append('t_CF overflow: the new binary drew %r and not nineteen X and '
                    'the buffer text -- sizeof(buf) is 20, so nineteen characters '
                    'and a NUL is exactly what fits' % n[2][:40])
    if o[1] == n[1]:
        fail.append('t_CF overflow: the two records agree, so nothing was measured')

# ---- 6. the formats that render differently -------------------------------------------
# NOT A DELTA: nothing in the instrument sets t_CF, and t_CF is empty under every
# built-in terminal but `debug`, where it is "[CF%d]" and uses only %d.
MOVES = {b'[%f]', b'[%b]', b'[%*d]', b'[%z]'}
SAME = {b'[%d]', b'[%1$d]'}
for fmt in TCF:
    o, n = res[('TCF' + fmt.decode(), old_bin)], res[('TCF' + fmt.decode(), new_bin)]
    if o is None or n is None:
        fail.append('the t_CF %s probe blocked' % fmt.decode())
        continue
    if fmt in MOVES and o[1] == n[1]:
        fail.append('t_CF %s renders the same on both binaries, and vim\'s own printf '
                    'is not musl\'s: this phase changes what a USER-SET t_CF does for '
                    'the directives vim spells differently, and the check records '
                    'that rather than hiding it' % fmt.decode())
    if fmt in SAME and o[1] != n[1]:
        fail.append('t_CF %s moved, and it must not: %%d is the only directive the '
                    '`debug` terminal\'s built-in t_CF uses, and %%1$d is positional '
                    'and identical in both implementations' % fmt.decode())

# ---- 7. everything else, byte-identical -----------------------------------------------
for name, _, _, _ in PROBES:
    o, n = res[(name, old_bin)], res[(name, new_bin)]
    if o is None or n is None:
        fail.append('%s blocked, so it says nothing either way' % name)
        continue
    if o[1] != n[1]:
        fail.append('%s moved, and vendoring the strings may move NOTHING the '
                    'editor draws' % name)

if fail:
    for line in fail:
        print('  %-12s %s' % (TAG, line))
    sys.exit(1)
print('  %-12s the t_CF overflow: `:set t_CF=` + 40 X + `%%d` and a ctermfont kills '
      'the binary this phase was handed -- exit -11, SIGSEGV, sprintf writing 42 '
      'bytes into char buf[20] -- and truncates to nineteen characters here.  That '
      'is a BUG FIX and it is the only reachable input on which this phase changes '
      'what the editor does' % TAG)
print('  %-12s and the formats a USER-SET t_CF can still reach: %%f, %%b, %%*d and '
      "%%z render differently because vim's own printf is not musl's, while %%d and "
      '%%1$d are identical -- recorded here and NOT declared, because nothing in the '
      'instrument sets t_CF and the only built-in t_CF is the debug terminal\'s '
      '"[CF%%d]".  %%s segfaults on BOTH binaries and is not this phase\'s' % '')
print('  %-12s %d probes byte-identical either side: every one of the thirteen '
      'external sprintf sites, the numbers the nine internal ones formatted, and '
      'the case fold, the memcmp and the memcpy that the 106-record corpus never '
      'reaches' % ('', len(PROBES)))
PY
