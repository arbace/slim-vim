#!/bin/sh
# Zero phase 25, the check -- the plain host calls.
# See pipes/zero25-edit.sh, and ZERO-PLAN.md 4c.
#
# Usage: pipes/zero25-check.sh <work-dir> <state-dir>    (run from the repository root)
#
# Runs after pipes/zero25-edit.sh and the sweep tools/phaserun.sh runs between them, and
# reads nothing from the edit's shell -- only the work tree and the state directory.
# What the edit left there is `old.c`, the source this phase was HANDED, and `old`, that
# source built with SOURCE_DATE_EPOCH=0 and the boundary's own flags.
#
# THE BINARY IS NOT BYTE-IDENTICAL AND THIS CHECK DOES NOT ASK FOR IT.  Phases 23 and 24
# rested on `cmp`, which is tier 1 of CLAUDE.md's verification table; this phase cannot,
# because an indirect call through a function pointer and a direct call are different
# instructions at -O0 and removing two file-scope objects moves everything after them.
# MEASURED: the same 788,488 bytes, 347,279 of them differing.  So this phase goes back
# to the evidence every zero phase before 23 used -- A RECORDING -- with a control for
# EACH of the two names it makes direct, because "the recording did not move" is only
# worth something if a change at those two sites would move it.
#
# WHAT IS CLAIMED, in seven parts:
#
#   ARITHMETIC  computed FROM THE INPUT and not written here: `vim_host_exit` 3 -> 0 and
#               `vim_host_message` 10 -> 0, `host_exit` 2 -> 3 and `host_message` 2 ->
#               10, `exit_fn` and `message_fn` 2 -> 0, five lines fewer, the eleven
#               #includes where they were, cmdnames[] 98 and options[] 107 unmoved, and
#               tools/canon.sh a NO-OP on the output.
#   THE ORDER   the prototype is above every call and the definition below every one of
#               them, BY LINE NUMBER -- which is what makes the declaration load-bearing
#               and what will keep it serving when a later phase moves the definitions
#               further down.  The control is the output with the two prototype lines
#               DELETED, which must not compile.
#   LINKAGE     THE ASSERTION THAT MATTERS MOST.  `nm --extern-only --defined-only` is
#               still exactly `main`, and two controls say what the alternative was: with
#               `static` off the two PROTOTYPES gcc REFUSES -- `static declaration of
#               'host_exit' follows non-static declaration` -- and with it off the
#               prototypes AND the definitions the build is SILENT and `nm` prints
#               `host_exit` and `host_message` beside `main`.  That second one is the
#               mistake this phase could have made without anything else noticing.
#   SYMBOLS     `nm -u` is THE SAME SET, as a `comm` empty in BOTH directions.  This
#               phase frees NOTHING and says so as an equality: `exit` does not come
#               back, because the host's definition still does not call it -- phase 19's
#               __builtin_longjmp launcher is untouched.
#   THE BINARY  the same SIZE and NOT the same bytes, both stated as measurements.
#   THE RECORD  two full tools/zrecord.sh recordings, `diff -r` empty, with one control
#               per name: `host_code = r;` -> `r + 1` in host_exit moves 105 of the 106
#               records, and host_message's `write(err ? 2 : 1, ...)` with the streams
#               swapped moves 24 of the 30 command lines AND NOTHING ELSE -- which is
#               phase 21's own finding, that everything reaching host_message is a
#               message printed before there is a screen.
#   STRUCTURE   tools/zhostonly.py, phase 20's structural check, still passes.  Renaming
#               nine call sites cannot disturb it -- `host_exit` and `host_message` are
#               not in its vocabulary, which is libc's terminal and signal names -- and
#               a phase that moves host calls about is exactly the one that should say so
#               rather than assume it.
set -eu

work=${1:?usage: zero25-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero25-check.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"
before_lines=$(cat "$state/input-lines")

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")

# The reproducible build of the OUTPUT and the five controls are written and started
# first and waited for below.  Every control is this phase's own product with ONE thing
# changed.
# shellcheck disable=SC2086
( SOURCE_DATE_EPOCH=0 gcc $cflags $ldflags -o "$tmp/new" "$f" ) &
pid_new=$!
python3 - "$f" "$tmp" <<'PY'
import re
import sys

TAG = 'hostcall'
t = open(sys.argv[1], errors='surrogateescape').read()
out = sys.argv[2]


def die(msg):
    sys.exit('  %-12s %s' % (TAG, msg))


L = t.split('\n')
protos = [l for l in L if re.match(r'^static \w+ host_(exit|message)\([^\n]*\);$', l)]
if len(protos) != 2:
    die('the output does not hold exactly the two `static` prototypes this phase adds: '
        '%s' % (' / '.join(protos) or 'none'))

# c1 -- the two prototypes DELETED.  It must not compile: that is what says they are
# load-bearing rather than decorative, and it is the control for the ordering section.
c1 = t
for p in protos:
    c1 = c1.replace(p + '\n', '', 1)
if c1.count('\n') != t.count('\n') - 2:
    die('deleting the two prototype lines did not remove exactly two lines')

# c2 -- `static` off the two PROTOTYPES only.  A hard error against the static
# definitions, which is the loud half of the linkage trap.
c2 = t
for p in protos:
    c2 = c2.replace(p + '\n', p[len('static '):] + '\n', 1)

# c3 -- `static` off the prototypes AND the definitions.  THE SILENT HALF: it builds,
# and two symbols become external.
c3 = c2
for name in ('host_exit', 'host_message'):
    m = re.search(r'^    static (\w+)\n(%s\()' % name, c3, re.M)
    if not m:
        die('`%s` is not defined in the `    static <type>` shape, so c3 would not be '
            'a control' % name)
    c3 = c3[:m.start()] + '    ' + m.group(1) + '\n' + m.group(2) + c3[m.end():]

# c4 -- host_exit's own statement, `host_code = r;` -> `host_code = r + 1;`.  The core
# calls host_exit DIRECTLY now; this is what says the call arrives.  It is phase 18's
# control, which was `exit(r);` -> `exit(r + 1);` before there was a launcher.
EXIT = '    host_code = r;\n'
if t.count(EXIT) != 1:
    die('`%s` is not in the output exactly once, so c4 would not be a control'
        % EXIT.strip())
c4 = t.replace(EXIT, '    host_code = r + 1;\n', 1)

# c5 -- host_message's two streams swapped.  The same statement for the other name.
MSG = 'write(err ? 2 : 1, msg + off'
if t.count(MSG) != 1:
    die('`%s` is not in the output exactly once, so c5 would not be a control' % MSG)
c5 = t.replace(MSG, 'write(err ? 1 : 2, msg + off', 1)

for name, text in (('c1', c1), ('c2', c2), ('c3', c3), ('c4', c4), ('c5', c5)):
    if text == t:
        die('%s changed nothing' % name)
    open('%s/%s.c' % (out, name), 'w', errors='surrogateescape').write(text)
print("  %-12s five controls written: c1 the two prototypes DELETED, c2 `static` off "
      'them, c3 `static` off them AND the definitions, c4 host_exit\'s `host_code = r;` '
      '-> `r + 1`, c5 host_message\'s two streams swapped' % TAG)
PY
# c1 and c2 are expected to FAIL, so their status is discarded here rather than by
# `wait`, which would take `set -e` with it.
( gcc -O0 -fno-stack-protector -fsyntax-only "$tmp/c1.c" 2>"$tmp/e.c1" || true ) &
pid_c1=$!
( gcc -O0 -fno-stack-protector -fsyntax-only "$tmp/c2.c" 2>"$tmp/e.c2" || true ) &
pid_c2=$!
( gcc -c -O0 -fno-stack-protector -o "$tmp/c3.o" "$tmp/c3.c" 2>"$tmp/e.c3" || true ) &
pid_c3=$!
# shellcheck disable=SC2086
( SOURCE_DATE_EPOCH=0 gcc $cflags $ldflags -o "$tmp/c4" "$tmp/c4.c" 2>"$tmp/e.c4" ) &
pid_c4=$!
# shellcheck disable=SC2086
( SOURCE_DATE_EPOCH=0 gcc $cflags $ldflags -o "$tmp/c5" "$tmp/c5.c" 2>"$tmp/e.c5" ) &
pid_c5=$!
# tools/canon.sh must be a NO-OP on the output.
cp "$f" "$tmp/canon.c"
( tools/canon.sh "$tmp/canon.c" >"$tmp/canon.log" 2>&1 ) &
pid_canon=$!

# --- 1. the source, as arithmetic on the input ------------------------------------------
python3 - "$f" "$state/old.c" "$before_lines" <<'PY'
import re
import sys

TAG = 'hostcall'
new = open(sys.argv[1], errors='surrogateescape').read()
old = open(sys.argv[2], errors='surrogateescape').read()
before_lines = int(sys.argv[3])
fail = []
NL, OL = new.split('\n'), old.split('\n')


def mentions(text, name):
    return len(re.findall(r'\b%s\b' % name, text))


# THE ARITHMETIC, computed from the input.  Every `want` below is stated as a
# transformation of what the input holds, so this is a check on the phase and not on
# whatever it was handed.
for name, want_old, want_new, why in (
        ('vim_host_exit', 3, 0, 'its declaration, its one assignment and its one call'),
        ('vim_host_message', 10, 0, 'its declaration, its one assignment and EIGHT '
                                    'calls'),
        ('exit_fn', 2, 0, "vim_main's third parameter and the assignment reading it"),
        ('message_fn', 2, 0, "vim_main's fourth parameter and its assignment"),
        ('host_exit', 2, 3, 'two -- the definition and main()\'s argument -- become '
                            'three: the prototype, the call in mch_exit and the '
                            'definition'),
        ('host_message', 2, 10, 'the same, with EIGHT calls'),
        ('vim_main', 2, 2, 'its definition and the one call from the launcher'),
        ('main', 1, 1, 'still the only bare `main` in the file'),
):
    if mentions(old, name) != want_old:
        fail.append('the INPUT has %d mentions of `%s` and this phase was written '
                    'against %d -- %s' % (mentions(old, name), name, want_old, why))
    elif mentions(new, name) != want_new:
        fail.append('`%s` has %d mentions in the output, expected %d -- %s'
                    % (name, mentions(new, name), want_new, why))

# THE TWO PROTOTYPES, AND THAT THEY DECLARE WHAT IS DEFINED.  Built here the same way
# the edit built them -- out of the definition's own two lines -- so a prototype that
# had drifted from its definition would show up as text and not only as a compile error.
protos = []
for name in ('host_exit', 'host_message'):
    m = re.search(r'^    (static \w+)\n(%s\([^\n]*\))\n\{\n' % name, new, re.M)
    if not m:
        fail.append('`%s` is not defined `    static <type>` / declarator / `{` in the '
                    'output' % name)
        continue
    protos.append('%s %s;' % (m.group(1), m.group(2)))
if len(protos) == 2:
    want = [p for p in protos]
    have = [l for l in NL if re.match(r'^static \w+ host_(exit|message)\(.*\);$', l)]
    if have != want:
        fail.append('the output\'s two prototypes are %s and the definitions say they '
                    'should be %s' % (' / '.join(have) or 'none', ' / '.join(want)))
    block = [i for i, l in enumerate(NL) if l == 'static void musl_suspend(void);']
    if len(block) != 1 or NL[block[0] + 1:block[0] + 3] != want:
        fail.append('the two prototypes are not the two lines below phase 20\'s last '
                    '`musl_` prototype -- the core -> host boundary is ONE block of '
                    'eleven')
    if not any('static void (*vim_host' in l for l in OL):
        fail.append('the INPUT held no `static void (*vim_host...)` object, so this is '
                    'not the file this phase was written against')

# THE SHAPE OF THE EDIT.  Five lines fewer, and the ONLY lines that move are the ones
# named: two object declarations with their blank lines, two prototypes, vim_main's
# head with its two assignments and their blank line, main's one statement, and the
# nine call sites.
if len(NL) - 1 != before_lines - 5 or len(OL) - 1 != before_lines:
    fail.append('the file is %d lines and the input was %d (%d recorded) -- expected '
                'exactly five fewer' % (len(NL) - 1, len(OL) - 1, before_lines))
if sum(1 for k in range(1, len(NL)) if NL[k] == '' and NL[k - 1] == ''):
    fail.append('there is a run of two blank lines, which canon.sh should have taken')

# THE SHAPE OF THE FILE.  Nothing here is a command, an option or a directive, and the
# check says so rather than assuming it.
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
d = [l for l in NL if l.startswith('#')]
if len(d) != 11 or any(not l.startswith('#include <') for l in d) or NL[:11] != d:
    fail.append('the output does not have exactly the eleven `#include` directives '
                'phase 21 left, on its first eleven lines.  This phase adds a '
                'DECLARATION, and MOVING THE INCLUDES IS A LATER PHASE')

if fail:
    for line in fail:
        print('  %-12s %s' % (TAG, line))
    sys.exit(1)
print('  %-12s `vim_host_exit` 3 -> 0 and `vim_host_message` 10 -> 0; `host_exit` 2 -> '
      '3 and `host_message` 2 -> 10; `exit_fn` and `message_fn` 2 -> 0.  Two objects, '
      'two parameters, two assignments and two arguments gone, TWO PROTOTYPES arrived, '
      'and every count is computed FROM THE INPUT' % TAG)
print('  %-12s the two prototypes are what the definitions say they must be, byte for '
      'byte -- %s -- and they are the two lines below phase 20\'s last `musl_` '
      'prototype, so the core -> host boundary is ONE block of eleven'
      % ('', ' / '.join(protos)))
print('  %-12s %d -> %d lines, five fewer; cmdnames[] 98 and options[] 107 unmoved; '
      'ELEVEN #includes on the first eleven lines' % ('', before_lines, len(NL) - 1))
PY

# --- 2. declaration before use, and the control that says the declaration is needed -----
wait $pid_c1
python3 - "$f" "$tmp/e.c1" <<'PY'
import re
import sys

TAG = 'hostcall'
new = open(sys.argv[1], errors='surrogateescape').read()
NL = new.split('\n')
err = open(sys.argv[2], errors='surrogateescape').read()

out = []
for name in ('host_exit', 'host_message'):
    proto = [i for i, l in enumerate(NL)
             if re.match(r'^static \w+ %s\(.*\);$' % name, l)]
    defn = [i for i, l in enumerate(NL)
            if l.startswith(name + '(') and i + 1 < len(NL) and NL[i + 1] == '{']
    uses = [i for i, l in enumerate(NL) if re.search(r'(?<!\w)%s\(' % name, l)
            and i not in proto and i not in defn]
    if len(proto) != 1 or len(defn) != 1 or not uses:
        sys.exit('  %-12s `%s` has %d prototypes, %d definitions and %d call sites in '
                 'the output' % (TAG, name, len(proto), len(defn), len(uses)))
    if not (proto[0] < min(uses) and max(uses) < defn[0]):
        sys.exit('  %-12s `%s`: prototype at %d, calls at %d..%d, definition at %d -- '
                 'the prototype must be ABOVE every call and the definition BELOW every '
                 'one, which is what makes the declaration load-bearing'
                 % (TAG, name, proto[0] + 1, min(uses) + 1, max(uses) + 1, defn[0] + 1))
    out.append((name, proto[0] + 1, len(uses), min(uses) + 1, max(uses) + 1,
                defn[0] + 1))
# The control: with the two prototype lines gone the file must NOT compile, and the
# errors must name both.  A declaration nothing needs is one this phase should not have
# added.
if not re.search(r'\berror\b', err):
    sys.exit('  %-12s THE CONTROL c1 DID NOT SHOW: with the two prototype lines DELETED '
             'the file still compiles, so the declarations this phase adds are not what '
             'lets the core name the host and the ordering above proves nothing' % TAG)
for name in ('host_exit', 'host_message'):
    if name not in err:
        sys.exit('  %-12s the control c1 failed without naming `%s`, so it is not the '
                 'control it claims to be' % (TAG, name))
n = len(re.findall(r'error:', err))
for name, p, k, lo, hi, dfn in out:
    print('  %-12s `%s`: prototype line %d, %d call site%s at %d%s, definition line %d '
          '-- DECLARED ABOVE EVERY USE AND DEFINED BELOW EVERY ONE.  A later phase moves '
          'the definitions further down and this stays true, which is the whole job of a '
          'forward declaration'
          % (TAG, name, p, k, '' if k == 1 else 's', lo,
             '' if k == 1 else '..%d' % hi, dfn))
    TAG = ''
print('  %-12s AND THE DECLARATIONS ARE LOAD-BEARING: this phase\'s own output with the '
      'two prototype lines DELETED gives %d errors naming both `host_exit` and '
      '`host_message`.  Without that control the two lines above are a statement about '
      'line numbers and not about the program' % ('', n))
PY

# --- 3. linkage, WHICH IS THE ASSERTION THAT MATTERS MOST ---------------------------------
# One external symbol has been the invariant since phase 0, and this is the phase that
# could break it quietly: the core now NAMES the host's two functions, and a `static`
# missing from a declaration and its definition is a silently correct build with two more
# symbols in it.  tools/phasecheck.sh asserts `main` alone below; here are the two
# alternatives, measured.
wait $pid_c2
wait $pid_c3
if ! grep -q "static declaration of 'host_exit' follows non-static declaration" "$tmp/e.c2"; then
    echo "  hostcall     THE CONTROL c2 DID NOT SHOW.  With \`static\` off the two PROTOTYPES"
    echo "               and left on the definitions, gcc must refuse:"
    sed 's/^/               /' "$tmp/e.c2" | head -4
    exit 1
fi
if [ -s "$tmp/e.c3" ] || [ ! -f "$tmp/c3.o" ]; then
    echo "  hostcall     the control c3 did not build, and the point of it is that it DOES:"
    sed 's/^/               /' "$tmp/e.c3" | head -4
    exit 1
fi
c3_ext=$(nm --extern-only --defined-only "$tmp/c3.o" | awk '{print $NF}' | sort | tr '\n' ' ')
if [ "$c3_ext" != "host_exit host_message main " ]; then
    echo "  hostcall     THE CONTROL c3 DID NOT SHOW.  With \`static\` off the prototypes AND"
    echo "               the definitions the object must define host_exit, host_message and"
    echo "               main; it defines: $c3_ext"
    exit 1
fi
echo "  hostcall     THE \`static\` TRAP, BOTH HALVES, MEASURED ON THIS PHASE'S OWN OUTPUT: with the keyword off the two PROTOTYPES gcc REFUSES -- \"static declaration of 'host_exit' follows non-static declaration\" -- and with it off the prototypes AND the definitions the build is SILENT and the object defines $c3_ext.  The second is the mistake this phase could have made without anything else noticing, and tools/phasecheck.sh below is what catches it"

# --- 4. the compile, the linkage and the libc surface ---------------------------------------
# NOTHING IS FREED AND NOTHING ARRIVES, and this phase says so as an equality.  `exit`
# does not come back: the host's host_exit() still records a status and jumps, and phase
# 19's __builtin_longjmp launcher is untouched by this phase.
cp "$state/symbols/undefined" "$tmp/before.u"
tools/phasecheck.sh "$work" "$f" "$state/symbols"
if ! cmp -s "$tmp/before.u" .cache/symbols/last/undefined; then
    echo "  hostcall     the libc surface moved, and TURNING AN INDIRECT CALL INTO A DIRECT ONE"
    echo "               CANNOT MOVE IT -- both name a function defined in this file:"
    echo "               gone: $(comm -23 "$tmp/before.u" .cache/symbols/last/undefined | tr '\n' ' ')"
    echo "               came: $(comm -13 "$tmp/before.u" .cache/symbols/last/undefined | tr '\n' ' ')"
    exit 1
fi
echo "  hostcall     symbols $(cat .cache/symbols/last/before) -> $(cat .cache/symbols/last/after), and the set is IDENTICAL as a cmp -- nothing left and nothing arrived.  \`exit\` does NOT come back: the host still records a status and jumps, phase 19's __builtin_longjmp launcher being untouched here.  main is still the only external symbol"

# --- 5. the binary: the same size, and NOT the same bytes ------------------------------------
wait $pid_canon
if ! cmp -s "$tmp/canon.c" "$f"; then
    echo "  hostcall     tools/canon.sh CHANGED THE OUTPUT, and it must be a no-op:"
    diff "$f" "$tmp/canon.c" | head -6 | sed 's/^/               /'
    exit 1
fi
echo "  hostcall     tools/canon.sh is a NO-OP on the output ($(sed -n 's/.*canon *//p' "$tmp/canon.log" | head -1))"

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

wait $pid_new || { echo "  hostcall     the reproducible build of the output failed"; exit 1; }
old_size=$(stat -c%s "$state/old")
new_size=$(stat -c%s "$tmp/new")
if [ "$new_size" -lt 500000 ] || [ "$old_size" -lt 500000 ]; then
    echo "  hostcall     one of the two binaries is $old_size / $new_size bytes, which is not an editor"
    exit 1
fi
if [ "$new_size" != "$(stat -c%s "$bin")" ]; then
    echo "  hostcall     the reproducible build is $new_size bytes and make produced $(stat -c%s "$bin"): the two differ by more than a timestamp, so nothing below would be about this boundary"
    exit 1
fi
if [ "$old_size" != "$new_size" ]; then
    echo "  hostcall     the binary is $old_size bytes in and $new_size out.  Nine call sites"
    echo "               change instruction and two file-scope pointers go, and the whole"
    echo "               of that was MEASURED to leave the image exactly the same length."
    echo "               A different length is a different phase and wants reading."
    exit 1
fi
if cmp -s "$state/old" "$tmp/new"; then
    echo "  hostcall     THE BINARY IS BYTE-IDENTICAL, and it must not be.  An indirect call"
    echo "               loads a pointer and calls a register; a direct call is a relative"
    echo "               call to a known address.  Identical bytes would mean the nine call"
    echo "               sites did not change at all."
    exit 1
fi
echo "  hostcall     THE BINARY IS THE SAME SIZE AND NOT THE SAME BYTES: $new_size either side, $(cmp -l "$state/old" "$tmp/new" | wc -l) of them differing.  That is stated as a MEASUREMENT and not aimed for -- an indirect call through a pointer and a direct call are different instructions at -O0, and removing two file-scope objects moves what follows.  So this phase cannot use tier 1 of CLAUDE.md's verification table and does not pretend to; the evidence is the recording below"

# --- 6. THE EVIDENCE: two recordings, and one control per name -------------------------------
# The four run at once.  Each control is this phase's own output with ONE statement
# changed, in ONE of the two functions the core now calls directly -- which is what keeps
# `diff -r` finding nothing from being a harness that records nothing.
rec() {
    tools/zrecord.sh "$2" "$3" "$tmp/REC-$1" >/dev/null 2>&1 &
    eval "pid_rec_$1=$!"
}
wait $pid_c4 || { echo "  hostcall     the control c4 did not build:"; head -5 "$tmp/e.c4" | sed 's/^/               /'; exit 1; }
wait $pid_c5 || { echo "  hostcall     the control c5 did not build:"; head -5 "$tmp/e.c5" | sed 's/^/               /'; exit 1; }
rec old "$state/old" "$state/old.c"
rec new "$tmp/new" "$f"
rec c4 "$tmp/c4" "$tmp/c4.c"
rec c5 "$tmp/c5" "$tmp/c5.c"
for p in $pid_rec_old $pid_rec_new $pid_rec_c4 $pid_rec_c5; do
    wait "$p" || { echo "  hostcall     a recording failed"; exit 1; }
done
python3 - "$tmp" <<'PY'
import filecmp
import os
import sys

TAG = 'hostcall'
tmp = sys.argv[1]


def files(d):
    out = []
    for root, _, names in os.walk(d):
        for n in names:
            out.append(os.path.relpath(os.path.join(root, n), d))
    return sorted(out)


base = files('%s/REC-new' % tmp)
if len(base) < 100:
    sys.exit('  %-12s a recording holds %d records, and a zero recording is 106 -- 102 '
             'screen cases and four sweeps.  A comparison of two things nothing wrote '
             'passes' % (TAG, len(base)))


def moved(which):
    d = '%s/REC-%s' % (tmp, which)
    if files(d) != base:
        sys.exit('  %-12s the recording of %s holds different records from the output\'s'
                 % (TAG, which))
    return [n for n in base
            if not filecmp.cmp('%s/REC-new/%s' % (tmp, n), '%s/%s' % (d, n), shallow=False)]


same = moved('old')
if same:
    print('  %-12s THE RECORDING MOVED, in %d of %d records: %s'
          % (TAG, len(same), len(base), ' '.join(same[:8])))
    print('  %-12s This phase declares NOTHING.  Two objects became two prototypes and '
          'nine indirect calls became direct ones; the editor does the same thing or '
          'the phase is wrong.' % '')
    sys.exit(1)
m4 = moved('c4')
m5 = moved('c5')
still = sorted(set(base) - set(m4))
if still != ['ref-term.txt']:
    sys.exit('  %-12s THE CONTROL c4 DID NOT SHOW AS MEASURED: host_exit recording '
             '`r + 1` instead of `r` moves %d of %d records and leaves %s unmoved, '
             'where it was measured to leave ref-term.txt alone and move everything '
             'else -- the terminal table is the one sweep that records no exit status'
             % (TAG, len(m4), len(base), ' '.join(still) or 'nothing'))
if m5 != ['ref-argv.txt']:
    sys.exit('  %-12s THE CONTROL c5 DID NOT SHOW AS MEASURED: host_message with its two '
             'streams swapped moves %s, and it was measured to move ref-argv.txt and '
             'nothing else -- everything that reaches host_message is a message printed '
             'before there is a screen (phase 21)' % (TAG, ' '.join(m5) or 'nothing'))
print('  %-12s THE RECORDING IS BYTE-IDENTICAL, all %d records -- 102 screen cases, '
      'every Ex command typed at `:`, every command line the parser may see, the four '
      'pty scenarios and the terminal table.  That is this phase\'s whole evidence, and '
      'it is the shape every zero phase before 23 used: the binary cannot be `cmp`-ed '
      'here, so what the editor DRAWS is what is compared' % (TAG, len(base)))
print('  %-12s AND IT CAN FAIL, ONCE FOR EACH NAME THIS PHASE MAKES DIRECT.  host_exit '
      'with `host_code = r + 1;` moves %d of the %d -- every record but the terminal '
      'table, which does not record an exit status.  host_message with its two streams '
      'swapped moves ref-argv.txt AND NOTHING ELSE, which is phase 21\'s own finding '
      'read back: everything reaching host_message is printed before there is a screen'
      % ('', len(m4), len(base)))
PY

# --- 7. phase 20's structural check, which a phase that renames host calls owes ------------
python3 tools/zhostonly.py "$f"
echo "  hostcall     and that is phase 20's check, undisturbed: its vocabulary is libc's terminal, signal and descriptor names, and \`host_exit\`/\`host_message\` are not in it -- so renaming nine call sites adds no host WORD to the core.  Running it here rather than assuming it is the point"

# tools/phaserun.sh runs tools/zerodelta.sh --phase 25 after this check, and this phase
# declares NOTHING: the corpus must not move at all.
