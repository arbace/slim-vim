#!/bin/sh
# Zero phase 22, the check -- the variadic collapse.
# See pipes/zero22-edit.sh, and ZERO-PLAN.md 4c.
#
# Usage: pipes/zero22-check.sh <work-dir> <state-dir>    (run from the repository root)
#
# Runs after pipes/zero22-edit.sh and the sweep tools/phaserun.sh runs between them, and
# reads nothing from the edit's shell -- only the work tree and the state directory.
# What the edit left there is `old.c`, the source this phase was HANDED, and `old`, that
# source built with the boundary's own flags.
#
# WHAT IS CLAIMED, in four parts:
#
#   STRUCTURE   `va_start` appears EXACTLY ONCE, and in `vim_snprintf`.  That is the
#               whole product of the phase and it is asserted as a count plus an owner
#               test, which is three lines and needs no tool.  Seven names at 0
#               mentions, five helpers at their measured counts, `vim_snprintf` moved by
#               exactly the arithmetic of the edit.
#   WARNINGS    `-Wformat=2` gives THE IDENTICAL 115 `-Wformat-nonliteral` warnings IN
#               THE IDENTICAL 53 FUNCTIONS before and after.  This is the strongest
#               cheap check available and the one a mangled expansion would fail while
#               the build did not: the format-checking attribute moves from the wrapper
#               to `vim_snprintf`, and it only lands on the same expressions if every
#               argument list came out right.
#   SYMBOLS     `nm -u` is THE SAME SET, asserted as a `comm` that is empty in BOTH
#               directions.  It is 18 names here and 17 in the boundary's own binary,
#               because tools/phasecheck.sh compiles plain -O0 and so adds
#               __stack_chk_fail, which the -fno-stack-protector build does not have --
#               and that is why the assertion is the equality and not the number.  A
#               reader meeting a 129-site phase expects a symbol to fall and none can:
#               a pure restructure inside one translation unit frees nothing.  The
#               binary GROWS, which is the same fact wearing its other face, and the
#               check reports the number rather than letting it look like a mistake.
#   BEHAVIOUR   the declared delta is NOTHING AT ALL, so tools/zerodelta.sh proves the
#               recording did not move.  And the recording is NEARLY BLIND to this
#               phase, which is measured rather than asserted (see below), so the phase
#               owes probes: 263 of them on both binaries, and FOUR DELIBERATE BREAKS
#               that say what the probes can and cannot see.
#
# HOW BLIND THE RECORDING IS -- MEASURED, with the input source built again with
# `write(2, "ZW|<wrapper>|<format>\n", ...)` at the entry to each of the seven.  Across
# the 102 screen cases: `vim_snprintf_safelen` 617 entries, `smsg_attr_keep` 6,
# `vim_snprintf_add` 2, and `smsg` 0, `smsg_attr` 0, `semsg` 0, `siemsg` 0.  `semsg` IS
# 94 OF THE 129 SITES AND THE SCREEN CORPUS ENTERS IT NOT ONCE.  That is the whole
# argument for probes.  The 263 below enter `semsg` 232 times over 34 distinct formats.
#
# THE FOUR BREAKS, AND TWO OF THEM MOVE NOTHING ON PURPOSE.  Each is this phase's own
# output with one thing wrong, built and run against the input binary:
#
#   b1  both room helpers return 20 instead of IOSIZE            129 of 263 differ
#   b2  the wrong tail -- every `semsg` site reports as an        155 of 263 differ
#       ordinary message instead of an error
#   b3  `safelen_result`'s clamp reduced to `return str_l;`         0 of 263 differ
#   b4  all three guards removed                                    0 of 263 differ
#
# b3 AND b4 ARE KEPT AT ZERO RATHER THAN DROPPED.  They are the honest statement of what
# the evidence cannot reach: the clamp needs a message longer than 1,025 bytes out of
# `fileinfo`, and the guards need `IObuff == NULL` (an out-of-memory failure of the
# first two allocations the process makes) or a `semsg` under `emsg_off > 0` whose
# scribble on `IObuff` somebody then reads.  Reporting them as 0 is the difference
# between "the probes prove the guards are load-bearing" -- which would be false -- and
# "the guards are correct by construction and the probes say so about b1 and b2".
#
# WHAT THE CHECK DELIBERATELY DOES NOT ASSERT: `vim_snprintf`'s mention count BEFORE the
# edit.  Phase 21 formats its host message with `vim_snprintf`, so that number is the
# message layer's and moves under it; this phase asserts the count AFTER, as the
# transformer's own arithmetic against whatever it was handed.
set -eu

work=${1:?usage: zero22-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero22-check.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"
before_lines=$(cat "$state/input-lines")

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")

# --- 1. the four controls, written and started first because the builds are the slow bit
python3 - "$f" "$tmp" <<'PY'
import re
import sys

TAG = 'format'
t = open(sys.argv[1], errors='surrogateescape').read()
out = sys.argv[2]

ROOM = '''iobuff_room(void)
{
    if (IObuff == NULL)
    {
        return 0;
    }
    return  (1024+1) ;
}'''
EROOM = '''emsg_iobuff_room(void)
{
    if (IObuff == NULL || emsg_not_now())
    {
        return 0;
    }
    return  (1024+1) ;
}'''
OR = '''iobuff_or(const char *s)
{
    if (IObuff == NULL)
    {
        return (char *)s;
    }
    return (char *)IObuff;
}'''
CLAMP = '    return ((size_t)str_l >= str_m) ? str_m - 1 : (size_t)str_l;'
for text in (ROOM, EROOM, OR, CLAMP):
    if t.count(text) != 1:
        sys.exit('  %-12s the helper `%s` is not in the output exactly once, so the '
                 'controls below would not be controls'
                 % (TAG, text.split('(')[0].strip()))

# b1 -- a twenty-byte buffer instead of IOSIZE
b1 = t.replace(ROOM, ROOM.replace('return  (1024+1) ;', 'return 20;')) \
      .replace(EROOM, EROOM.replace('return  (1024+1) ;', 'return 20;'))
# b2 -- the wrong tail.  `emsg(` IS A SUBSTRING OF `iemsg(`, so this is by word boundary
# and not by str.replace; the naive form rewrites `iemsg(iobuff_or(` too and the build
# would catch THAT, while the same mistake made in the edit would not be caught at all.
b2, n2 = re.subn(r'(?<![A-Za-z0-9_])emsg\(iobuff_or\(', 'msg(iobuff_or(', t)
if n2 != 94:
    sys.exit('  %-12s b2 rewrote %d `emsg(iobuff_or(` tails, expected 94' % (TAG, n2))
# b3 -- safelen's clamp
b3 = t.replace(CLAMP, '    return (size_t)str_l;')
# b4 -- all three guards
b4 = t.replace(ROOM, 'iobuff_room(void)\n{\n    return  (1024+1) ;\n}') \
      .replace(EROOM, 'emsg_iobuff_room(void)\n{\n    return  (1024+1) ;\n}') \
      .replace(OR, 'iobuff_or(const char *s)\n{\n    (void)s;\n    return (char *)IObuff;\n}')
for name, text in (('b1', b1), ('b2', b2), ('b3', b3), ('b4', b4)):
    if text == t:
        sys.exit('  %-12s %s changed nothing' % (TAG, name))
    open('%s/%s.c' % (out, name), 'w', errors='surrogateescape').write(text)
print('  %-12s four controls written: b1 a 20-byte IObuff, b2 the wrong tail at all 94 '
      '`semsg` sites, b3 safelen_result\'s clamp, b4 all three guards' % TAG)
PY
pid_breaks=''
for b in b1 b2 b3 b4; do
    # shellcheck disable=SC2086
    # The stderr goes to a log rather than the terminal: these run in the
    # background while the assertions below decide, and an assertion that
    # refuses first takes the temp directory with it, so four `ld: cannot open
    # output file` lines would otherwise bury the message that actually matters.
    ( gcc $cflags $ldflags -o "$tmp/$b" "$tmp/$b.c" 2>"$tmp/$b.log" ) &
    pid_breaks="$pid_breaks $!"
done

# --- 2. the source ---------------------------------------------------------------------
python3 - "$f" "$state/old.c" <<'PY'
import re
import sys

TAG = 'format'
new = open(sys.argv[1], errors='surrogateescape').read()
old = open(sys.argv[2], errors='surrogateescape').read()
fail = []


def mentions(text, name):
    return len(re.findall(r'\b%s\b' % name, text))


# THE INPUT, so this is a check on the phase and not on whatever it was handed.
for name, want in (('smsg', 12), ('smsg_attr', 4), ('smsg_attr_keep', 2), ('semsg', 96),
                   ('siemsg', 12), ('vim_snprintf_add', 3), ('vim_snprintf_safelen', 13),
                   ('va_start', 8), ('va_list', 15), ('va_end', 10), ('va_arg', 21),
                   ('va_copy', 2)):
    if mentions(old, name) != want:
        fail.append('the input has %d mentions of `%s`, expected %d'
                    % (mentions(old, name), name, want))

# WHAT IS GONE.  Seven names, and every one of them is a function that took `...`,
# opened a va_list and handed it to vim_vsnprintf.
GONE = 'smsg smsg_attr smsg_attr_keep semsg siemsg vim_snprintf_add vim_snprintf_safelen'
left = [n for n in GONE.split() if mentions(new, n)]
if left:
    fail.append('these names should be at 0 mentions and are not: %s' % ' '.join(left))

# THE PHASE, AS ONE ASSERTION.  `va_start` once, and in vim_snprintf -- the count alone
# would pass if the survivor were any other function.
starts = [m.start() for m in re.finditer(r'\bva_start\b', new)]
if len(starts) != 1:
    fail.append('`va_start` has %d mentions, expected exactly 1 -- that single mention '
                'IS this phase' % len(starts))
else:
    heads = [(m.start(), m.group(1)) for m in re.finditer(r'^(\w+)\(', new, re.M)]
    owner = [h for p, h in heads if p < starts[0]]
    if not owner or owner[-1] != 'vim_snprintf':
        fail.append('the one `va_start` is inside `%s`, not `vim_snprintf` -- the '
                    'survivor must be the function the split moves'
                    % (owner[-1] if owner else '<none>'))

vs_want = mentions(old, 'vim_snprintf') - 1 + 129
for name, want, why in (
        ('va_list', 8, 'the prototype and definition of `vim_vsnprintf`, the same of '
                       '`vim_vsnprintf_typval` plus its local, `vim_snprintf`\'s local '
                       'and `skip_to_arg`\'s two parameters -- FOUR functions, and '
                       'ZERO-PLAN.md 4c names three'),
        ('va_end', 3, "vim_snprintf's, vim_vsnprintf_typval's two"),
        ('va_arg', 21, 'UNCHANGED, all of them inside vim_vsnprintf_typval'),
        ('va_copy', 2, 'UNCHANGED, likewise'),
        ('vim_snprintf', vs_want, 'one prototype away -- the redundant second one, '
                                  'which existed only because the message wrappers sat '
                                  'above it -- and one mention at each of the 129 sites'),
        ('vim_vsnprintf', 3, 'a prototype, the definition and vim_snprintf\'s one call: '
                             'the six calls the wrappers made are gone'),
        ('vim_vsnprintf_typval', 3, 'a prototype, the definition and vim_vsnprintf\'s '
                                    'call -- vim_snprintf_safelen called it directly '
                                    'and now goes through vim_vsnprintf, which is the '
                                    'same function with NULL for its fifth argument'),
        ('iobuff_room', 15, 'a prototype, the definition and the 13 smsg/smsg_attr/'
                            'smsg_attr_keep sites'),
        ('emsg_iobuff_room', 106, 'a prototype, the definition and the 104 semsg/siemsg '
                                  'sites'),
        ('iobuff_or', 119, 'a prototype, the definition and one at each of the 117 '
                           'message sites'),
        ('safelen_result', 13, 'a prototype, the definition and the 11 sites'),
        ('append_room', 3, 'a prototype, the definition and the one site'),
        ('emsg_not_now', 5, 'UNCHANGED, and it is a coincidence worth stating: the '
                            'phase ADDS a forward declaration and a call from '
                            'emsg_iobuff_room(), and REMOVES semsg\'s and siemsg\'s two '
                            'calls.  5 -> 5'),
        ('emsg_core', 5, 'the definition and the four calls in emsg/iemsg/internal_error'
                         ' -- semsg\'s two and siemsg\'s three are gone'),
        ('msg', 63, "+10 sites, -2 in smsg's deleted body"),
        ('emsg', 218, '+94 sites, and semsg\'s body named it not once'),
        ('iemsg', 45, '+10 sites'),
        ('msg_attr', 21, "+2 sites, -2 in smsg_attr's deleted body: UNCHANGED"),
        ('msg_attr_keep', 6, "+1 site, -2 in smsg_attr_keep's deleted body"),
        ('IObuff', 204, 'the 117 message sites, the helpers\' four, and the 15 the seven '
                        'deleted definitions took with them'),
):
    if mentions(new, name) != want:
        fail.append('`%s` has %d mentions, expected %d -- %s'
                    % (name, mentions(new, name), want, why))

# THE PROTOTYPE THE PHASE ADDS, which is the one line of the edit that is not a call-site
# rewrite.  Without it the build fails loudly; deadprotos.py does not take it away.
for p in ('static int emsg_not_now(void);', 'static size_t iobuff_room(void);',
          'static size_t emsg_iobuff_room(void);',
          'static char *iobuff_or(const char *s);',
          'static size_t safelen_result(char *str, size_t str_m, int str_l);',
          'static size_t append_room(char *str, size_t str_m);'):
    if new.count(p + '\n') != 1:
        fail.append('the declaration `%s` is not in the output exactly once' % p)

# THE SHAPE OF THE FILE.  Nothing here is a command, an option or a normal-mode key, and
# the check says so rather than assuming it.
sys.path.insert(0, 'tools')
import create_cmdidxs
rows = re.findall(r'^    \[CMD_\w+\] = \{.*$', new, re.M)
if len(rows) != 98 or len(create_cmdidxs.names(sys.argv[1])) != 98:
    fail.append('cmdnames[] is not the 98 rows phase 10 left -- this phase touches no '
                'Ex command')
i = new.find('static struct vimoption options[]')
j = new.index('\n};', i)
n_opt = len(re.findall(r'^[ \t]*\{"([a-z]+)",', new[i:j], re.M))
if n_opt != 107:
    fail.append('options[] has %d rows, expected the 107 phase 20 left -- this phase '
                'removes no option' % n_opt)
d = [l for l in new.split('\n') if l.startswith('#')]
if len(d) != 11 or any(not l.startswith('#include <') for l in d):
    fail.append('the output does not have exactly the eleven `#include` directives phase '
                '21 left.  <stdarg.h> STAYS: the one surviving va_start needs it, and it '
                'leaves at the SPLIT and not here')
L = new.split('\n')
if sum(1 for k in range(1, len(L)) if L[k] == '' and L[k - 1] == ''):
    fail.append('there is a run of two blank lines, which canon.sh should have taken')

if fail:
    for line in fail:
        print('  %-12s %s' % (TAG, line))
    sys.exit(1)
print('  %-12s `va_start` 8 -> 1 AND THE ONE IS INSIDE `vim_snprintf`; `va_list` 15 -> '
      '8, `va_end` 10 -> 3, `va_arg` and `va_copy` untouched at 21 and 2.  The eight '
      'surviving `va_list` mentions are in FOUR functions -- vim_snprintf, '
      'vim_vsnprintf, vim_vsnprintf_typval and skip_to_arg -- where ZERO-PLAN.md 4c '
      'names three' % TAG)
print('  %-12s the seven wrappers are at 0 mentions; `vim_snprintf` %d -> %d, one '
      'redundant prototype away and one mention at each of the 129 sites; five helpers '
      'at 15, 106, 119, 13 and 3; the tails at msg 63, emsg 218, iemsg 45, msg_attr 21 '
      'and msg_attr_keep 6, every one of them a function that already existed'
      % ('', mentions(old, 'vim_snprintf'), mentions(new, 'vim_snprintf')))
print('  %-12s cmdnames[] 98 unchanged, options[] 107 unchanged, eleven #includes '
      'unchanged -- <stdarg.h> stays for the one va_start and leaves at the SPLIT -- '
      'and no run of two blank lines' % '')
PY

# --- 3. -Wformat=2, THE CHECK A MANGLED ARGUMENT LIST WOULD FAIL AND THE BUILD WOULD NOT
# The wrappers carried format(printf, 1, 2) / (2, 3) / (3, 4) and vim_snprintf carries
# (3, 4).  Every expansion puts the format expression at vim_snprintf's third parameter,
# so gcc checks exactly the expressions it checked before -- the SAME warnings in the
# SAME functions.  Nothing else in this phase can say that.
gcc -O0 -fno-stack-protector -Wformat=2 -fsyntax-only "$state/old.c" 2>"$tmp/w.old" &
pid_w=$!
gcc -O0 -fno-stack-protector -Wformat=2 -fsyntax-only "$f" 2>"$tmp/w.new"
wait $pid_w
python3 - "$tmp/w.old" "$tmp/w.new" <<'PY'
import re
import sys

TAG = 'format'


def read(path):
    """gcc quotes an identifier as ‘x’ or 'x' depending on the locale, and the
    phase runs under a different one from a shell -- match both, or the function
    list comes back empty and the equality below passes for the wrong reason."""
    txt = open(path, errors='surrogateescape').read()
    n = len(re.findall(r'\[-Wformat-nonliteral\]', txt))
    fns = [m.group(1) or m.group(2) for m in
           re.finditer(r"In function (?:‘(\w+)’|'(\w+)')", txt)]
    return n, fns


no, fo = read(sys.argv[1])
nn, fn = read(sys.argv[2])
if no != nn or fo != fn:
    print('  %-12s -Wformat=2 MOVED: %d warnings in %d function headings before, %d in '
          '%d after' % (TAG, no, len(fo), nn, len(fn)))
    a, b = set(fo), set(fn)
    if a - b:
        print('  %-12s functions that stopped warning: %s' % ('', ' '.join(sorted(a - b))))
    if b - a:
        print('  %-12s functions that started: %s' % ('', ' '.join(sorted(b - a))))
    sys.exit(1)
if no != 115 or len(set(fo)) != 53:
    print('  %-12s -Wformat=2 gives %d warnings in %d distinct functions, expected 115 '
          'in 53 -- the equality above still holds, but this is not the tree the phase '
          'was measured on' % (TAG, no, len(set(fo))))
    sys.exit(1)
print('  %-12s -Wformat=2: THE IDENTICAL %d `-Wformat-nonliteral` warnings in THE '
      'IDENTICAL %d functions, before and after.  Every `semsg` format in this file is '
      '`_(e_name)` over a `static char e_name[]` array -- there is not one string '
      'literal at a semsg site anywhere -- so the coverage does not disappear, it MOVES '
      'from the wrapper\'s attribute to vim_snprintf\'s, and it only lands on the same '
      'expressions if all 129 argument lists came out right'
      % (TAG, no, len(set(fo))))
PY

# --- 4. the compile, the linkage and the libc surface ----------------------------------
# ONE comm, and it must be EMPTY IN BOTH DIRECTIONS.  This is the headline: a reader
# meeting a 129-site phase expects a symbol to fall, and none does.
cp "$state/symbols/undefined" "$tmp/before.u"
tools/phasecheck.sh "$work" "$f" "$state/symbols"
comm -23 "$tmp/before.u" .cache/symbols/last/undefined > "$tmp/gone.u"
comm -13 "$tmp/before.u" .cache/symbols/last/undefined > "$tmp/came.u"
if [ -s "$tmp/gone.u" ] || [ -s "$tmp/came.u" ]; then
    echo "  format       the libc surface MOVED, and this phase frees nothing and takes"
    echo "               nothing on:"
    echo "               gone: $(tr '\n' ' ' < "$tmp/gone.u")"
    echo "               came: $(tr '\n' ' ' < "$tmp/came.u")"
    echo "               A PURE RESTRUCTURE INSIDE ONE TRANSLATION UNIT FREES NOTHING:"
    echo "               vim_vsnprintf_typval still does every conversion, in this file,"
    echo "               and <stdarg.h>'s three names are macros and a builtin type."
    echo "               The symbols go when the formatter LEAVES, and that is the split."
    exit 1
fi
# ZERO-PLAN.md 4b, still absolute.
for absent in open creat openat stat access fcntl getcwd strerror fopen fdopen \
              opendir fclose getc putc fsync exit _exit; do
    if grep -qx "$absent" .cache/symbols/last/undefined; then
        echo "  format       $absent is undefined, and no phase since 13 has put it back"
        exit 1
    fi
done
echo "  format       symbols $(cat .cache/symbols/last/before) -> $(cat .cache/symbols/last/after), THE SAME SET as a comm that is empty in BOTH directions -- nothing left and nothing arrived.  That equality is the headline: eight functions calling va_start cannot be split and one can, but until the formatter LEAVES THE FILE no symbol can move"

# --- 5. the enumerators, before and after ----------------------------------------------
# Nothing here is an enum, so it is ASSERTED rather than assumed: 129 rewritten call
# sites in a file where several enums index a parallel table is exactly the shape of
# edit that would renumber one by accident.
tools/enumvals.sh "$state/old.c" "$tmp/ev.old" &
pid_ev=$!
tools/enumvals.sh "$f" "$tmp/ev.new"
wait $pid_ev
python3 - "$tmp/ev.old" "$tmp/ev.new" <<'PY'
import sys
TAG = 'format'
o = dict(l.rsplit('=', 1) for l in open(sys.argv[1]).read().splitlines())
n = dict(l.rsplit('=', 1) for l in open(sys.argv[2]).read().splitlines())
gone, came = sorted(set(o) - set(n)), sorted(set(n) - set(o))
moved = sorted(k for k in set(o) & set(n) if o[k] != n[k])
if gone or came or moved:
    for what, names in (('went', gone), ('arrived', came), ('renumbered', moved)):
        if names:
            print('  %-12s enumerators %s: %s' % (TAG, what, ' '.join(names[:20])))
    sys.exit(1)
print('  %-12s %d enumerators, and not one went, arrived or renumbered' % (TAG, len(o)))
PY

# --- 6. the binary ----------------------------------------------------------------------
make -C "$work" clean >/dev/null 2>&1 || true
[ -e "$work/zero-vim" ] && { echo "  build        the clean did not remove zero-vim"; exit 1; }
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
old_bytes=$(stat -c%s "$state/old")
new_bytes=$(stat -c%s "$bin")
echo "  build        ok, $before_lines -> $(grep -c '' "$f") lines, $old_bytes -> $new_bytes bytes: EXEC, no INTERP, no dynamic section, 0 relocations"
if [ "$new_bytes" -le "$old_bytes" ]; then
    echo "  build        THE BINARY DID NOT GROW, and it must: 129 call sites now carry"
    echo "               a format call and a tail call where they carried one call, and"
    echo "               at -O0 that is the expected sign.  A binary that shrank means"
    echo "               the expansion did not happen where it was counted."
    exit 1
fi

for p in $pid_breaks; do
    wait "$p" || true
done
for b in b1 b2 b3 b4; do
    if [ ! -x "$tmp/$b" ]; then
        echo "  format       the control $b did not build:"
        head -5 "$tmp/$b.log" 2>/dev/null | sed 's/^/               /'
        exit 1
    fi
done

# --- 7. the probes, because the recording is nearly blind to this phase ------------------
python3 - "$state/old" "$bin" "$tmp/b1" "$tmp/b2" "$tmp/b3" "$tmp/b4" <<'PY'
import concurrent.futures
import hashlib
import sys

sys.path.insert(0, 'tools')
import zstream

TAG = 'format'
OLD, NEW, B1, B2, B3, B4 = sys.argv[1:7]
ESC, CR, CG, CA = b'\x1b', b'\r', b'\x07', b'\x01'
QUIT = ESC + b':q!' + CR
PASTE = ['+set paste']
L4 = b'aaa' + CR + b'bbb' + CR + b'aaa' + CR + b'ccc'
L40 = CR.join(b'line%d' % i for i in range(1, 41))
P = []


def seed(text):
    return [b'i' + text + ESC, b':set nopaste' + CR]


def probe(tag, args, *keys):
    P.append((tag, args, list(keys) + [QUIT]))


# 1. the command layer: `semsg` from the Ex commands that still exist
for tag, cmd in (('set_nosuchopt', b':set nosuchoption'), ('set_badval', b':set sw=zz'),
                 ('winsize_zz', b':winsize zz'), ('later_3x', b':later 3x'),
                 ('earlier_bad', b':earlier 9q'), ('mark_ab', b':mark ab'),
                 ('delmarks_1', b':delmarks 1'), ('history_xyzzy', b':history : xyzzy'),
                 ('match_foo', b':match Foo /x/'), ('undo_99', b':undo 99'),
                 ('normal_bad', b':normal'), ('set_t_zz', b':set t_zz=x'),
                 ('map_bad', b':map <Nosuch> x'), ('unmap_bad', b':unmap zqzq'),
                 ('syntax_bad', b':nosuchcommand'), ('set_all_q', b':set invalidopt?'),
                 ('set_inv', b':set noinvalidopt'), ('hi_link_bad', b':highlight link'),
                 ('behave_bad', b':behave zz'), ('sleep_bad', b':sleep 3q'),
                 ('redir_bad', b':redir zz'), ('marks_zzz', b':marks zzz'),
                 ('set_ts_abc', b':set ts=abc'), ('set_unknown2', b':set invopt=1'),
                 ('set_ts_huge', b':set ts=99999999999999999999'),
                 ('hi_link3', b':hi link a b c'), ('hi_noeq', b':hi Comment ctermfg'),
                 ('hi_eq', b':hi Comment =x'), ('t_missing', b':set <t_zz>=x'),
                 ('t_long', b':set t_AB=' + b'x' * 200)):
    probe(tag, PASTE, *seed(b'hello'), cmd + CR)
for i, cmd in enumerate((b':hi Comment ctermfg=nosuch', b':hi Comment cterm=nosuch',
                         b':hi Comment start=', b':hi Comment guifg=nosuch',
                         b':hi NoSuchGroup', b':hi Comment nosucharg=1',
                         b':hi clear NoSuchGroup', b':hi Comment ctermbg=999')):
    probe('hi%d' % i, PASTE, *seed(b'hello'), cmd + CR)
for tag, keys in (('map_unique', (b':map q1 x' + CR, b':map <unique> q1 y' + CR)),
                  ('map_unique_ins', (b':map! q1 x' + CR, b':map! <unique> q1 y' + CR)),
                  ('abbr_unique', (b':abbr q1 x' + CR, b':abbr <unique> q1 y' + CR)),
                  ('cabbr_unique', (b':cabbr q1 x' + CR, b':cabbr <unique> q1 y' + CR))):
    probe(tag, PASTE, *seed(b'hello'), *keys)
for tag, keys in (('invreg', b'"#p'), ('emptyreg', b'"zp'), ('reg_bang', b'"!p'),
                  ('reg_caret', b'"^p'), ('record_bad', b'q!'),
                  ('e_nothing_in_reg', b'"qp')):
    probe(tag, PASTE, *seed(b'hello'), keys)

# 2. THE REGEXP ENGINE: the 18 comma-expression sites, over both engines and three
# magic settings.  These are the shape the edit is most likely to get wrong.
BADPAT = (br'\(', br'[', br'a\{1,2,3}', br'\%[', br'\%(', br'\%d99999999', br'\z1',
          br'a\@', br'\(x\)\{1,2}\{3}', br'\%#=3', br'\{', br'a\{-', br'\%v',
          br'\%[abc', br'\)', br'\|\|', br'a**', br'\%da', br'[a-', br'\@=',
          br'\%(x', br'~\{')
for eng in (1, 2):
    for magic, pfx in (('magic', b''), ('nomagic', b''), ('magic', br'\v')):
        for i, pat in enumerate(BADPAT):
            probe('re%d_%s%d_%d' % (eng, magic, len(pfx), i),
                  PASTE + ['+set re=%d %s' % (eng, magic)],
                  *seed(b'aaa'), b'/' + pfx + pat + CR)
for tag, keys in (('search_bad', b'/\\%23' + CR), ('engine_mid', b'/a\\%#=1' + CR),
                  ('empty_brackets', b'/x\\%[]' + CR),
                  ('missing_rsb', b'/x\\%[abc' + CR),
                  ('bad_in_brackets', b'/x\\%[a*]' + CR),
                  ('too_many_open', b'/' + b'\\(' * 12 + b'a' + CR),
                  ('too_many_curly', b'/' + b'\\(a\\)\\{1,2}' * 12 + CR)):
    probe(tag, PASTE, *seed(b'aaa'), keys)
for tag, keys in (('nfa_repeat', b'/\\@<=*' + CR),
                  ('nfa_repeat2', b'/a\\{1,2}\\{3,4}' + CR)):
    probe(tag, PASTE + ['+set re=2'], *seed(b'aaa'), keys)
# THE ONLY WAY TO REACH A `semsg` WITH emsg_off > 0, which is the arm
# emsg_iobuff_room()'s second half exists for.
for i, pat in enumerate((br'\(', br'[', br'a\{1,2,3}', br'\%[')):
    probe('incsearch%d' % i, PASTE + ['+set incsearch'], *seed(b'aaa'), b'/' + pat, ESC)

# 3. `smsg`: the messages the editor prints
for tag, keys in (('eq_line', b':=' + CR), ('global_print', b':g/aaa/p' + CR),
                  ('move_report', b':1,3m$' + CR), ('yank_block', b'gg\x16jjly'),
                  ('g_notfound', b':g/zzzz/d' + CR), ('v_everyline', b':v/./d' + CR),
                  ('bar_here', b':g/aaa/normal x | p' + CR)):
    probe(tag, PASTE, *seed(L4), keys)
for tag, keys in (('tilde_report', b'gg' + b'g~3j'), ('yank_lines', b'gg3yy'),
                  ('join_report', b'gg10J'), ('shift_report', b'gg10>>'),
                  ('delete_report', b'gg10dd')):
    probe(tag, PASTE, *seed(L40), keys)
probe('ctrl_a_block', PASTE, *seed(b'1' + CR + b'2' + CR + b'3'), b'gg\x16jj' + CA)
probe('g_verbose', PASTE + ['+set verbose=1'], *seed(L4), b':g/aaa/p' + CR)
probe('g_verbose9', PASTE + ['+set verbose=9'], *seed(L4), b':g/aaa/p' + CR)

# 4. the substitution report, the confirm prompt (smsg_attr_keep) and ask_yesno
for tag, keys in (('sub_one', (b':%s/aaa/ZZZ/g' + CR,)),
                  ('sub_confirm', (b':%s/aaa/ZZZ/gc' + CR, b'yn')),
                  ('ask_yesno', (b':%s/aaa/ZZZ/gc' + CR, b'a')),
                  ('sub_nomatch', (b':%s/zzzz/q/' + CR,)),
                  ('sub_badflag', (b':%s/a/b/zz' + CR,)),
                  ('sub_bigcount', (b':%s/a/b/c99999999' + CR,)),
                  ('sub_pat_bad', (b':%s/\\(/x/' + CR,)),
                  ('sub_count0', (b':%s/a/b/ 0' + CR,)),
                  ('delmarks_bad', (b':delmarks z-a' + CR,)),
                  ('norm_bar', (b':normal! x | y' + CR,)),
                  ('e_val_large2', (b':1,99999999999999999999p' + CR,)),
                  ('e_val_large3', (b':99999999999999999999' + CR,)),
                  ('undo_msg', (b'ggdd', b'u')), ('redo_msg', (b'ggdd', b'u\x12')),
                  ('undolist', (b'ggdd', b':undolist' + CR)), ('undo_none', (b'u',)),
                  ('undo_time', (b'ggdd', b':earlier 1f' + CR)),
                  ('marks', (b'ma', b':marks' + CR)),
                  ('registers', (b'yy', b':registers' + CR))):
    probe(tag, PASTE, *seed(L4), *keys)
probe('sub_many', PASTE, *seed(L40), b':%s/line/LN/g' + CR)
probe('sub_report_msg', PASTE, *seed(L40), b':%s/e/E/g' + CR)

# 5. `vim_snprintf_safelen`: CTRL-G and the ruler, which is where the clamp lives
for tag, args, s, keys in (
        ('ctrl_g_1', PASTE, b'hello', CG), ('ctrl_g_40', PASTE, L40, b'20G' + CG),
        ('ctrl_g_top', PASTE, L40, b'gg' + CG), ('ctrl_g_bot', PASTE, L40, b'G' + CG),
        ('ctrl_g_2', PASTE, L40, b'20G2' + CG),
        ('ctrl_g_shm', PASTE + ['+set shortmess='], L40, b'20G' + CG),
        ('ctrl_g_shm1', PASTE + ['+set shortmess='], b'hello', CG),
        ('big_line', PASTE, b'x' * 200, b'$' + CG),
        ('ml_get', PASTE, L40, b'G' + b'j' * 5 + CG),
        ('ruler_ru', PASTE + ['+set ruler'], L40, b'20G'),
        ('ruler_noru', PASTE + ['+set noruler'], L40, b'20G'),
        ('ruler_fmt', PASTE + ['+set ruler'], L40, b'Gllll'),
        ('ruler_virtual', PASTE + ['+set ruler ve=all'], L40, b'20G20l'),
        ('ruler_all', PASTE + ['+set ruler'], b'a' + CR + b'b' + CR + b'c', b'j'),
        ('ruler_all_shm', PASTE + ['+set ruler shortmess='], b'a' + CR + b'b', b'j')):
    probe(tag, args, *seed(s), keys)
probe('ruler_empty', PASTE + ['+set ruler'], b'')

# 6. the screens that format a great deal at once
for tag, args, s, keys in (
        ('intro', PASTE, b'x', b':intro' + CR), ('version', PASTE, b'x', b':version' + CR),
        ('ga', PASTE, b'abc', b'ga'), ('ga_multi', PASTE, 'é'.encode(), b'ga'),
        ('set_all', PASTE, b'x', b':set all' + CR),
        ('set_termcap', PASTE, b'x', b':set termcap' + CR),
        ('digraph', PASTE, b'x', b':digraphs' + CR), ('maps', PASTE, b'x', b':map' + CR),
        ('display_uhex', PASTE + ['+set display=uhex'], b'x', b'a\x16\x01' + ESC),
        ('list_mode', PASTE + ['+set list'], b'a\tb', b''),
        ('bad_command', PASTE, b'x', b':qqqq' + CR),
        ('trailing_chars', PASTE, b'x', b':history : xyz abc' + CR),
        ('e_invalid_arg', PASTE, b'x', b':set backspace=nosuch' + CR),
        ('term_sync', PASTE, b'x', b':set t_RS=x' + CR),
        ('buf_inuse', PASTE, b'x', b':bdelete' + CR),
        ('search_notfound', PASTE, b'aaa', b'/zzzz' + CR),
        ('search_wrap', PASTE + ['+set nowrapscan'], b'aaa', b'/zzzz' + CR),
        ('search_top', PASTE + ['+set nowrapscan'], b'aaa', b'?zzzz' + CR)):
    probe(tag, args, *seed(s), keys)


def run(binary, job):
    tag, args, keys = job
    try:
        scr, out, err, rc = zstream.session(binary, keys, args=args)
    except zstream.Blocked:
        return (tag, 'BLOCKED')
    body = scr.snaps[-1][0] if scr.snaps else ''
    return (tag, len(out), hashlib.sha256(out).hexdigest()[:16], rc, len(err),
            hashlib.sha256(body.encode()).hexdigest()[:16])


JOBS = [(b, j) for b in (OLD, NEW, B1, B2, B3, B4) for j in P]
with concurrent.futures.ThreadPoolExecutor(max_workers=48) as ex:
    res = list(ex.map(lambda t: run(t[0], t[1]), JOBS))
by = {}
for (b, j), r in zip(JOBS, res):
    by.setdefault(b, []).append(r)


def differ(b):
    return [x[0] for x, y in zip(by[OLD], by[b]) if x != y]


fail = []
d = differ(NEW)
if d:
    fail.append('%d of %d probes differ, and this phase declares NOTHING: %s'
                % (len(d), len(P), ' '.join(d[:25])))
n1, n2, n3, n4 = (len(differ(B1)), len(differ(B2)), len(differ(B3)), len(differ(B4)))
if n1 < 50:
    fail.append('THE CONTROL b1 DID NOT SHOW.  This phase\'s own output with both room '
                'helpers returning 20 instead of IOSIZE moved %d of %d probes, and a '
                'truncated message is the first thing a wrong buffer size would do -- '
                'two numbers agreeing prove nothing if a wrong one is not caught' % (n1, len(P)))
if n2 < 50:
    fail.append('THE CONTROL b2 DID NOT SHOW.  This phase\'s own output with every '
                '`semsg` site given `msg()` for a tail instead of `emsg()` moved %d of '
                '%d probes -- an error that no longer sets did_emsg is the mistake this '
                'phase is most able to make' % (n2, len(P)))
if n3 or n4:
    fail.append('b3 moved %d probes and b4 moved %d, and BOTH ARE DECLARED TO MOVE '
                'NOTHING.  If they now move something, the probe set has grown a reach '
                'the phase\'s own account of its evidence does not describe, and that '
                'account has to be rewritten rather than the number quietly updated'
                % (n3, n4))
if fail:
    for line in fail:
        print('  %-12s %s' % (TAG, line))
    sys.exit(1)
print('  %-12s %d probes on both binaries, 0 differ -- the Ex-command errors, %d regexp '
      'errors across both engines and three magic settings (which are the 18 '
      'comma-expression sites), the message and report sites, the substitute-confirm '
      'prompt, undo, CTRL-G and the ruler in fifteen shapes, and four incsearch probes '
      'with a bad pattern, which are the ONLY way to reach a `semsg` with emsg_off > 0'
      % (TAG, len(P), 2 * 3 * len(BADPAT)))
print('  %-12s AND THEY CAN FAIL: this phase\'s own output with both room helpers '
      'returning 20 moves %d of %d, and with every `semsg` tail made `msg()` instead of '
      '`emsg()` moves %d' % ('', n1, len(P), n2))
print('  %-12s AND TWO CONTROLS MOVE NOTHING, WHICH IS REPORTED RATHER THAN HIDDEN: '
      'safelen_result\'s clamp removed moves %d, and all three guards removed moves %d. '
      'The clamp needs a message longer than 1,025 bytes out of fileinfo, and the '
      'guards need IObuff == NULL -- an out-of-memory failure of the first two '
      'allocations the process makes.  The guards are copied verbatim from the wrappers '
      'and are correct by construction; the evidence does not reach them, and saying so '
      'is the point' % ('', n3, n4))
PY

# tools/phaserun.sh runs tools/zerodelta.sh --phase 22 after this check, and this phase
# declares NOTHING: the corpus must not move at all.
