#!/bin/sh
# Zero phase 15, the check -- the character classes, the numbers and the sort.
# See pipes/zero15-edit.sh, and ZERO-GOAL.md.
#
# Usage: pipes/zero15-check.sh <work-dir> <state-dir>    (run from the repository root)
#
# Runs after pipes/zero15-edit.sh and the sweep tools/phaserun.sh runs between them,
# and reads nothing from the edit's shell -- only the work tree and the state
# directory.  What the edit left there is `old`, the binary this phase was HANDED,
# and `old.c`, the source it was built from.
#
# THE DECLARED DELTA IS NOTHING AT ALL, AND IT IS A THIRD KIND OF EMPTY DECLARATION.
# Phase 9's was code that could not run; phase 13's was a possibility that had never
# existed; this one is an EQUALITY.  The code this phase replaces runs constantly --
# `towupper` alone is entered 892 times in a trivial session, before 'casemap' has
# even been applied -- and what is claimed is that the replacement computes the same
# answer.  So there is no must-differ probe, every behavioural probe is a
# MUST-NOT-DIFFER, and the weight of the evidence sits on equivalence instead:
#
#   tools/muslcase.py --verify   re-derives all 1,114,112 codepoints from THIS
#                                MACHINE'S libc through ctypes and compares them
#                                with the 187 + 171 rows the phase shipped.  The
#                                table is checked against the only authority there
#                                is, not remembered.
#   tools/muslctype.py --verify  slices the seventeen functions OUT OF THE SOURCE
#                                THIS PHASE PRODUCED, compiles them with -Wall
#                                -Wextra and runs them beside libc's.
#
# Both are proven able to fail: perturbing one `convertStruct` offset, one `& 0x5f`,
# one comparator direction and one `return` in the binary search each makes the
# matching tool refuse.
#
# THE HEADER CONTRACT IS ASSERTED HERE AND NOT LEFT TO PHASE 16.  A copy of the
# produced source with `#include <ctype.h>` and `#include <wctype.h>` deleted must
# compile SILENTLY, and the same deletion on the source this phase was HANDED must
# fail.  That is a check that can fail in both directions, and it is what phase 16
# needs to be true before it can move.  Neither copy is left in the tree: this phase
# changes no directive, and the count stays 18.
#
# FIVE THINGS ARE PROVED.
#
# 1. THE SOURCE, as counts.  Nothing <ctype.h> or <wctype.h> provides is CALLED
#    anywhere, `iswupper` is gone, and the seventeen musl_ functions are defined
#    once each.  The count is call-shaped and not `\b`-shaped: "isprint" is also an
#    option name in a string literal, and a word count says 1 on a file that calls
#    it nowhere.
#
#    THE TRAPS, ALL MEASURED:
#      * `nm -u` UNDER-REPORTS <ctype.h> BY FIVE NAMES.  isalpha, isdigit, isgraph,
#        islower and isupper are function-like macros in musl, so a source that
#        calls them has no undefined symbol to show for it.  A check written from
#        the symbol list alone passes on a phase that left all seventeen sites.
#      * `latin1flags`, `latin1upper` and `latin1lower` MUST SURVIVE.  They are read
#        only from the unreachable arms this phase deliberately does not touch, and
#        a check that expected them to go would fail on a correct phase.
#      * `utf_convert` GAINS two callers and keeps its own.
#      * THE BINARY GROWS.  805,544 against 803,912 on this phase's input: the 358
#        rows are data the image did not carry before, and the musl objects they
#        replace were smaller, because musl packs the same mapping into 16,998 bytes
#        of two-level base-6 table.  A phase check that assumed removal means
#        shrinkage would fail here.
#
# 2. THE LIBC SURFACE, NAMED AS A SET AND NOT AS A COUNT -- `atoi atol bsearch
#    isalnum iscntrl ispunct qsort tolower toupper towlower towupper` and nothing
#    else -- with the terminal, the memory and the message layer asserted still
#    there, and ZERO-PLAN.md 4b's invariant asserted again.
#
# 3. THE TWO EQUIVALENCE TOOLS, above.
#
# 4. FOURTEEN PROBE SESSIONS ON BOTH BINARIES, byte-identical, each required to be
#    doing something.  The corpus is ASCII-only and seeds itself by typing, so it
#    cannot reach Unicode case folding, `'casemap'`, the four bsearch tables or the
#    sort at all -- which is exactly why `tools/zerodelta.sh` saying "nothing moved"
#    is not enough on its own.
#
# 5. AND THE SORT, WHICH NO RECORD CAN SEE.  `:undolist` is wiped by the Press-ENTER
#    redraw before the `\x1b[?25h` that ends a step, so its row order is read out of
#    the raw stdout stream.  It is compared rather than sha'd because the rows carry
#    "0 seconds ago", which is the one nondeterminism the corpus scrubs.
set -eu

work=${1:?usage: zero15-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero15-check.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"
before_lines=$(cat "$state/input-lines")

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# --- 1. the source, as counts ---------------------------------------------------------
python3 - "$f" "$state/old.c" <<'PY'
import re
import sys
sys.path.insert(0, 'tools')
import create_cmdidxs
TAG = 'vendor'
new = open(sys.argv[1], errors='surrogateescape').read()
old = open(sys.argv[2], errors='surrogateescape').read()
fail = []


def calls(text, name):
    return len(re.findall(r'(?<![\w])%s\s*\(' % name, text))


def words(text, name):
    return len(re.findall(r'\b%s\b' % name, text))


# Everything the two headers provide, called nowhere.  This is phase 16's contract.
PROVIDED = ('isalnum isalpha isblank iscntrl isdigit isgraph islower isprint '
            'ispunct isspace isupper isxdigit isascii toascii tolower toupper '
            'iswalnum iswalpha iswblank iswcntrl iswdigit iswgraph iswlower '
            'iswprint iswpunct iswspace iswupper iswxdigit towlower towupper '
            'towctrans wctrans wctype iswctype').split()
left = [n for n in PROVIDED if calls(new, n)]
if left:
    fail.append('<ctype.h>/<wctype.h> still has a user: %s' % ' '.join(left))
if words(new, 'iswupper'):
    fail.append('iswupper survives, and it was the dead statement')
for tname in ('wint_t', 'wctype_t', 'wctrans_t'):
    if words(new, tname):
        fail.append('%s is still named, and it is <wctype.h>\'s' % tname)

# And the input DID have those users, so the assertion above is one that can fail.
had = [n for n in PROVIDED if calls(old, n)]
if sorted(had) != sorted('isalnum isalpha isdigit isgraph islower ispunct iscntrl '
                         'isupper iswupper tolower toupper towlower towupper'.split()):
    fail.append('the input is not the file this phase was written against: it calls '
                '%s' % ' '.join(sorted(had)))
if not words(old, 'iswupper'):
    fail.append('the input did not name iswupper, so deleting it proves nothing')

# The seventeen definitions, once each.
for name in ('musl_isdigit', 'musl_isalpha', 'musl_isupper', 'musl_islower',
             'musl_isgraph', 'musl_isspace', 'musl_isalnum', 'musl_iscntrl',
             'musl_ispunct', 'musl_tolower', 'musl_toupper', 'musl_atoi',
             'musl_atol', 'musl_bsearch', 'musl_qsort', 'musl_towupper',
             'musl_towlower'):
    if len(re.findall(r'^%s\(' % name, new, re.M)) != 1:
        fail.append('%s is not defined exactly once' % name)

# THE 44 REWRITTEN CALL SITES, AS A RULE AND NOT AS REMEMBERED NUMBERS.  For every
# name N, the produced source must call `musl_N` exactly as often as the INPUT called
# `N`, plus however often the vendored text itself names `musl_N` -- its definition
# header, its prototype if it has one, and the vendored bodies that call it
# (musl_ispunct calls musl_isalnum; musl_atoi and musl_atol call musl_isdigit and
# musl_isspace).  Both halves are read here rather than written down, so the check
# says "every call site moved and none was invented" on whatever input it is handed
# instead of on the one it was written against.
BLOCK = open('tools/musl-ctype.txt').read() + open('tools/musl-case.txt').read()
for name in ('tolower', 'toupper', 'towlower', 'towupper', 'isalnum', 'iscntrl',
             'ispunct', 'isalpha', 'isdigit', 'isgraph', 'islower', 'isupper',
             'isspace', 'atoi', 'atol', 'qsort', 'bsearch'):
    want = calls(old, name) + calls(BLOCK, 'musl_' + name)
    got = calls(new, 'musl_' + name)
    if got != want:
        fail.append('musl_%s is called %d times, expected %d -- the %d sites the input '
                    'called %s at, plus the %d times the vendored text names it'
                    % (name, got, want, calls(old, name), name,
                       calls(BLOCK, 'musl_' + name)))
moved = sum(calls(old, n) for n in
            'tolower toupper towlower towupper isalnum iscntrl ispunct isalpha '
            'isdigit isgraph islower isupper isspace atoi atol qsort bsearch'.split())
if moved != 44:
    fail.append('the input has %d call sites to rewrite, not the 44 this phase was '
                'written against' % moved)

# THE TABLES SIT BESIDE VIM'S, THEY DO NOT REPLACE THEM -- also as a rule: whatever
# the input said about toUpper[] and toLower[], the output must say the same, and must
# say it about musl_toUpper[] and musl_toLower[] too (a definition plus the two
# mentions in each wrapper's utf_convert call).  THIS IS WHAT CATCHES A PHASE THAT
# WIRED musl_towupper TO THE WRONG TABLE, which no count of call sites would see.
for name in ('toUpper', 'toLower'):
    want = words(old, name)
    if words(new, name) != want or words(new, 'musl_' + name) != want:
        fail.append('%s is named %d times and musl_%s %d, and both must be %d -- vim '
                    'KEEPS its own case tables and musl\'s sit BESIDE them'
                    % (name, words(new, name), name, words(new, 'musl_' + name), want))
if calls(new, 'utf_convert') != calls(old, 'utf_convert') + 2:
    fail.append('utf_convert is called %d times, expected %d -- its own callers plus '
                'the two wrappers this phase adds'
                % (calls(new, 'utf_convert'), calls(old, 'utf_convert') + 2))

# THESE MUST SURVIVE.  They are read only from the unreachable Latin-1 arms this
# phase deliberately leaves alone, and a check that expected them at 0 would fail on
# a correct phase.  Seventeen statements that cannot run are a phase of their own.
for name, want in (('latin1flags', 3), ('latin1upper', 2), ('latin1lower', 2),
                   ('sort_strings', 3), ('sort_compare', 2)):
    k = words(new, name)
    if k != want:
        fail.append('%s has %d mentions, expected %d -- the folded Latin-1 arms and '
                    'the sort are not this phase\'s' % (name, k, want))

# No preprocessor arrived, and none left: the two headers are phase 16's.
directives = [l for l in new.splitlines() if l.startswith('#')]
if len(directives) != 18 or any(not l.startswith('#include <') for l in directives):
    fail.append('the directives are not the 18 #includes they were')
if '#include <ctype.h>' not in new or '#include <wctype.h>' not in new:
    fail.append('a header was removed, and removing them is phase 16\'s')
# The tables and the options, neither of which this phase touches.
rows = re.findall(r'^    \[CMD_\w+\] = \{.*$', new, re.M)
got = create_cmdidxs.names(sys.argv[1])
if len(rows) != 98 or len(got) != 98:
    fail.append('cmdnames[] has %d rows and names() reads %d; both must be 98'
                % (len(rows), len(got)))
i = new.find('static struct vimoption options[]')
j = new.index('\n};', i)
if len(re.findall(r'^[ \t]*\{"([a-z]+)",', new[i:j], re.M)) != 108:
    fail.append('options[] is not the 108 rows phase 12 left')
if fail:
    for line in fail:
        print('  %-12s %s' % (TAG, line))
    print('  %-12s nm -u under-reports <ctype.h> by FIVE macro names; latin1flags,' % '')
    print('  %-12s latin1upper and latin1lower SURVIVE, being read only from the' % '')
    print('  %-12s unreachable arms this phase does not touch.' % '')
    sys.exit(1)
print('  %-12s nothing <ctype.h> or <wctype.h> provides is called anywhere and '
      'iswupper is gone -- while the input called twelve of them and named iswupper, '
      'so the assertion is one that can fail; seventeen musl_ definitions, 44 '
      'rewritten call sites; vim keeps toUpper[] and toLower[] and musl\'s sit '
      'BESIDE them, utf_convert at six callers; latin1flags 3, latin1upper 2 and '
      'latin1lower 2 SURVIVING, because the seventeen other statements that cannot '
      'run are a phase of their own; 18 directives, both headers still there '
      'because removing them is phase 16\'s' % TAG)
PY

# --- 2. the two equivalence tools, which are the weight of this phase's evidence -------
python3 tools/muslcase.py --verify "$f"
python3 tools/muslctype.py --verify "$f"

# --- 3. the header contract, in both directions ---------------------------------------
# A check that can only pass is not a check: the SAME deletion is applied to the
# source this phase was handed, and it must fail.  Neither copy goes near the tree.
sed '/^#include <ctype.h>$/d; /^#include <wctype.h>$/d' "$f" > "$tmp/noinc.c"
sed '/^#include <ctype.h>$/d; /^#include <wctype.h>$/d' "$state/old.c" > "$tmp/noinc-old.c"
if ! gcc -c -O0 -Wall -Wextra -Wno-unused-parameter -o /dev/null "$tmp/noinc.c" \
        2>"$tmp/noinc.log" || [ -s "$tmp/noinc.log" ]; then
    echo "  vendor       the produced source does not compile without <ctype.h> and <wctype.h>, so phase 16 could not remove them:"
    head -5 "$tmp/noinc.log" | sed 's/^/               /'
    exit 1
fi
if gcc -c -O0 -Wall -Wextra -Wno-unused-parameter -o /dev/null "$tmp/noinc-old.c" \
        2>/dev/null; then
    echo "  vendor       the INPUT also compiles without the two headers, so this check cannot fail and proves nothing"
    exit 1
fi
olderr=$(gcc -c -O0 -o /dev/null "$tmp/noinc-old.c" 2>&1 | grep -c 'error:' || true)
echo "  vendor       the produced source compiles SILENTLY with #include <ctype.h> and <wctype.h> deleted, and the source this phase was handed gives $olderr errors under the same deletion -- that pair, and not a grep, is what says phase 16 can move"

# --- 4. the compile, the linkage and the libc surface ----------------------------------
# ELEVEN SYMBOLS GO AND THE SET IS NAMED, not the count.  Five more identifiers left
# the source with no symbol to show for it, because musl spells them as macros.
cp "$state/symbols/undefined" "$tmp/before.u"
tools/phasecheck.sh "$work" "$f" "$state/symbols"
comm -23 "$tmp/before.u" .cache/symbols/last/undefined > "$tmp/gone.u"
comm -13 "$tmp/before.u" .cache/symbols/last/undefined > "$tmp/came.u"
printf 'atoi\natol\nbsearch\nisalnum\niscntrl\nispunct\nqsort\ntolower\ntoupper\ntowlower\ntowupper\n' > "$tmp/want.u"
if ! cmp -s "$tmp/gone.u" "$tmp/want.u" || [ -s "$tmp/came.u" ]; then
    echo "  vendor       the libc surface did not move by exactly the eleven:"
    echo "               gone: $(tr '\n' ' ' < "$tmp/gone.u")"
    echo "               came: $(tr '\n' ' ' < "$tmp/came.u")"
    exit 1
fi
# WHAT MUST STAY.  The terminal, the memory, the message layer, the clock, the
# signals and gcc's own -- none of which is pure computation and none of which is
# this phase's.
for keep in read write close dup ioctl select tcgetattr tcsetattr nanosleep isatty \
            printf fflush stderr malloc free realloc time gettimeofday \
            sigaction kill raise getpid exit _exit __errno_location; do
    grep -qx "$keep" .cache/symbols/last/undefined \
        || { echo "  vendor       $keep went, and it is not this phase's: this phase takes only what is a function of its arguments"; exit 1; }
done
# ZERO-PLAN.md 4b's invariant, asserted again: still no way to acquire a descriptor.
for absent in open creat openat stat access fcntl getcwd strerror fopen fdopen \
              opendir fclose getc putc fsync; do
    if grep -qx "$absent" .cache/symbols/last/undefined; then
        echo "  vendor       $absent is undefined, and the core has had no way to open a file since phase 13"; exit 1
    fi
done
echo "  vendor       symbols $(cat .cache/symbols/last/before) -> $(cat .cache/symbols/last/after), the set is exactly atoi atol bsearch isalnum iscntrl ispunct qsort tolower toupper towlower towupper -- and FIVE MORE identifiers left the source with no symbol to show for it, isalpha isdigit isgraph islower isupper being macros in musl, which is why phase 16 needs this phase's own count and not nm -u"

# --- 5. the enumerators, before and after -----------------------------------------------
# NOTHING GOES AND NOTHING ARRIVES: this phase adds functions and data, touches no
# enum, and the two new tables are `convertStruct` rows rather than constants.
tools/enumvals.sh "$state/old.c" "$tmp/ev.old" &
pid_ev=$!
tools/enumvals.sh "$f" "$tmp/ev.new"
wait $pid_ev
python3 - "$tmp/ev.old" "$tmp/ev.new" <<'PY'
import sys
TAG = 'vendor'
o = dict(l.rsplit('=', 1) for l in open(sys.argv[1]).read().splitlines())
n = dict(l.rsplit('=', 1) for l in open(sys.argv[2]).read().splitlines())
gone, came = sorted(set(o) - set(n)), sorted(set(n) - set(o))
moved = sorted(k for k in set(o) & set(n) if o[k] != n[k])
if gone or came or moved:
    for what, s in (('went', gone), ('arrived', came), ('renumbered', moved)):
        if s:
            print('  %-12s enumerators %s: %s' % (TAG, what, ' '.join(s)))
    sys.exit(1)
print('  %-12s enumerators %d -> %d: not one went, arrived or renumbered -- this '
      'phase adds functions and two convertStruct tables and touches no enum'
      % (TAG, len(o), len(n)))
PY

# --- 6. the structural tools, none of whose tables this phase touches -------------------
python3 tools/nvidxcheck.py "$f"
python3 tools/orphanopts.py "$f"

# --- 7. the binary ----------------------------------------------------------------------
make -C "$work" clean >/dev/null 2>&1 || true
if ! make -C "$work" >/dev/null 2>&1; then
    echo "  build        FAILED -- rerun by hand: make -C $work"
    exit 1
fi
bin="$work/zero-vim"
# STILL ABSOLUTELY STATIC (phase 0 and phase 1).
if ! readelf -h "$bin" | grep -q 'Type:.*EXEC'; then
    echo "  vendor       the binary is no longer EXEC"; exit 1
fi
if readelf -l "$bin" | grep -q INTERP; then
    echo "  vendor       the binary grew an INTERP"; exit 1
fi
if readelf -d "$bin" 2>/dev/null | grep -q 'Dynamic section'; then
    echo "  vendor       the binary grew a dynamic section"; exit 1
fi
echo "  build        ok, $before_lines -> $(grep -c '' "$f") lines, $(stat -c%s "$bin") bytes -- and it GROWS, because the 358 convertStruct rows are data the image did not carry and musl packed the same mapping into 16,998 bytes"

# --- 8. fourteen probe sessions on both binaries, byte-identical --------------------------
python3 - "$state/old" "$bin" <<'PY'
import concurrent.futures
import hashlib
import os
import re
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, 'tools')
import zrec
import zscreen
import zstream

TAG = 'vendor'
ESC, CR = b'\x1b', b'\r'
QUIT = ESC + b':q!' + CR
old_bin, new_bin = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])

# An ASCII letter beside a Latin-1, a Greek, a Cyrillic, a circled Latin and a
# Coptic.  The first three are where musl's table and vim's AGREE and an ASCII
# fallback does not; the last two are where musl's and vim's DISAGREE.  A probe text
# that held only the first three would pass a phase that had routed the calls to
# vim's table, and one that held only the last two would pass an ASCII fallback.
SCRIPTS = 'eé gα cа xⓐ sⱟ'.encode()


def record(binary, args, keys, timeout=10):
    vim = zstream.stage(binary)     # argv[0], and the copy race: tools/zstream.py
    home = tempfile.mkdtemp(prefix='zero15-home-')
    env = dict(os.environ)
    env.update(TERM='xterm', HOME=home, VIM=os.path.join(home, 'novim'),
               VIMRUNTIME=os.path.join(home, 'novim'),
               XDG_CONFIG_HOME=os.path.join(home, 'xdg'))
    for k in ('LINES', 'COLUMNS', 'VIMINIT', 'EXINIT', 'MYVIMRC'):
        env.pop(k, None)
    d = tempfile.mkdtemp(prefix='zero15-run-')
    kf = os.path.join(d, 'keys')
    with open(kf, 'wb') as fh:
        fh.write(b''.join(keys))
    try:
        with open(kf, 'rb') as stdin:
            r = subprocess.run([vim] + list(args), stdin=stdin,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               env=env, cwd=d, timeout=timeout,
                               start_new_session=True)
        rc, out, err = r.returncode, r.stdout, r.stderr
    except subprocess.TimeoutExpired:
        rc, out, err = 'timeout', b'', b''
    shutil.rmtree(home, ignore_errors=True)
    shutil.rmtree(d, ignore_errors=True)
    scr = zscreen.Screen(24, 80)
    scr.feed(out)
    text = zrec.section('exit %s' % rc)
    text += zrec.section('bells %d' % scr.bells)
    text += zrec.section('stream %d sha=%s'
                         % (len(out), hashlib.sha256(out).hexdigest()[:16]))
    text += zrec.section('stderr', err.decode('utf-8', 'replace').rstrip('\n'))
    for i, (dump, y, x, bells) in enumerate(scr.snaps):
        text += zrec.section('snap %d cursor=%d,%d bells=%d' % (i, y, x, bells), dump)
    return zrec.scrub(text), out


def typed(seed, *keys):
    return (['+set paste'],
            [b'i' + seed + ESC, b':set nopaste' + CR] + list(keys) + [QUIT])


# name, (args, keys), what the NEW binary must still be SHOWING.  A record that is
# equal because both binaries did nothing is two failures agreeing.
PROBES = [
    # towupper/towlower under every 'casemap' the option can hold.
    ('case_default',   typed(SCRIPTS, b'gUU'),                              'Α'),
    ('case_lower',     typed(SCRIPTS, b'gUU', b'guu'),                      'α'),
    ('case_empty',     typed(SCRIPTS, b':set casemap=' + CR, b'gUU'),       'Α'),
    ('case_keepascii', typed(SCRIPTS, b':set casemap=keepascii' + CR, b'gUU'), 'Α'),
    ('case_internal',  typed(SCRIPTS, b':set casemap=internal' + CR, b'gUU'), 'Α'),
    ('case_tilde',     typed(SCRIPTS, b'0' + b'~' * 20),                    'Α'),
    # bsearch: key_names_table, including the two rows both spelled "Tab".
    ('map_keys',       typed(b'alpha', b':map <Tab> x' + CR, b':map <S-Tab> y' + CR,
                             b':map <Esc> z' + CR, b':map' + CR),           '<S-Tab>'),
    # bsearch: highlight_tab and color_name_tab, and two of the seven atoi sites.
    ('hl_cterm',       typed(b'alpha', b':highlight Foo ctermfg=4 cterm=bold,reverse' + CR,
                             b':highlight Foo' + CR),                       'Foo'),
    ('hl_colorname',   typed(b'alpha', b':highlight Foo ctermfg=Blue cterm=NONE' + CR,
                             b':highlight Foo' + CR),                       'Foo'),
    # bsearch: char_class_tab, and the three classifier loops in regatom().
    ('char_classes',   typed(b'a1!Z x', b'/[[:alnum:]]' + CR, b'/[[:punct:]]' + CR,
                             b'/[[:alpha:]]' + CR, b'/[[:graph:]]' + CR,
                             b'/[[:cntrl:]]' + CR, b'/[[:digit:]]' + CR),   'alnum'),
    # atoi and atol at the sites a keyboard can reach.
    ('verbose_z',      typed(b'alpha' + CR + b'beta' + CR + b'gamma',
                             b':3verbose set ai?' + CR, b':z2' + CR),       'autoindent'),
    ('search_offset',  typed(b'alpha beta gamma', b'0', b'/beta/e+2' + CR),  'beta'),
    ('term_colors',    typed(b'alpha', b':set t_Co=256' + CR, b':set t_Co?' + CR), '256'),
    # the chartab the 892 startup calls build, asked for through a word motion.
    ('isk_at',         typed('café naïve'.encode(), b':set isk=@' + CR,
                             b'0', b'dw'),                                  'na'),
]


def one(probe):
    name, (args, keys), want = probe
    return (name, record(old_bin, args, keys), record(new_bin, args, keys), want)


with concurrent.futures.ThreadPoolExecutor(max_workers=len(PROBES)) as ex:
    results = list(ex.map(one, PROBES))

fail = []
for name, o, n, want in results:
    if o[0] != n[0]:
        fail.append('%s MOVED, and nothing in this phase may move a record' % name)
    if want is not None:
        shown = n[0] + n[1].decode('utf-8', 'replace')
        if want not in shown:
            fail.append('%s: the new binary no longer shows %r, so "it did not move" '
                        'is two failures agreeing' % (name, want))

# THE SORT, WHICH NO RECORD CAN SEE.  :undolist is wiped by the Press-ENTER redraw
# before the \x1b[?25h that ends a step, so the rows are read out of the raw stream;
# and they carry "0 seconds ago", so the ORDER is compared and not a digest.
UNDO = (['+set paste'],
        [b'ione' + ESC, b':set nopaste' + CR, b'otwo' + ESC, b'u', b'othree' + ESC,
         b'u', b'ofour' + ESC, b'u', b'u', b'ofive' + ESC, b':undolist' + CR, QUIT])


def undo_order(binary):
    _, out = record(binary, UNDO[0], UNDO[1])
    if b'number changes' not in out:
        return None
    i = out.index(b'number changes')
    return tuple(x.decode() for x in re.findall(rb'\r\r\n\s*(\d+)\x1b', out[i:i + 400]))


oo, no = undo_order(old_bin), undo_order(new_bin)
if oo is None or no is None:
    fail.append(':undolist printed no table on one of the binaries, so the sort was '
                'never reached and the comparison below proves nothing')
elif len(oo) < 4:
    fail.append(':undolist listed %d rows, and a sort of fewer than two is not a '
                'sort' % len(oo))
elif oo != no:
    fail.append(':undolist row order moved: %s -> %s' % (' '.join(oo), ' '.join(no)))

if fail:
    for line in fail:
        print('  %-12s %s' % (TAG, line))
    sys.exit(1)
print('  %-12s fourteen probe sessions byte-identical either side and each doing its '
      'work -- six that exercise towupper/towlower under every \'casemap\' the option '
      'can hold, over an ASCII, a Latin-1, a Greek, a Cyrillic, a circled Latin and a '
      'Coptic letter (the first three separate an ASCII fallback, the last two '
      'separate vim\'s own table, and a text with only one group would pass one of '
      'them); four for the four bsearch tables, including the two rows both spelled '
      '"Tab"; three for atoi and atol; and one for the chartab the 892 startup calls '
      'build.  The corpus reaches none of this: every one of its 102 cases seeds '
      'itself by typing ASCII' % TAG)
print('  %-12s and :undolist, read out of the raw stream because the Press-ENTER '
      'redraw wipes it: %s either side.  `uh_seq` is `++b_u_seq_last`, one assignment '
      'in the file, so no two keys can be equal and the stable insertion sort and '
      'musl\'s smoothsort cannot disagree -- which tools/muslctype.py proves the '
      'other way, by showing they DO disagree on three equal keys'
      % ('', ' '.join(oo)))
PY
