#!/bin/sh
# Zero phase 25 -- the plain host calls.  See ZERO-PLAN.md 4c and ZERO-GOAL.md.
#
# Usage: pipes/zero25-edit.sh <work-dir> <state-dir>     (run from the repository root)
#
# THE CORE REACHES THE HOST THROUGH TWO FUNCTION POINTERS, AND THE ONE REASON THEY ARE
# POINTERS IS GONE.  Phase 19 wrote `static void (*vim_host_exit)(int);` and phase 21
# wrote `static void (*vim_host_message)(const char *, int, int);`, each installed
# through a parameter of `vim_main()` that `main()` passes.  pipes/zero19-edit.sh says
# why in as many words: "a pointer the launcher installs through a parameter adds no
# external symbol, where a `musl_exit(int)` the host defines would" -- the invariant
# being `nm --extern-only --defined-only` giving exactly `main`, and the design at the
# time being TWO TRANSLATION UNITS, where the host's definition of a function the core
# calls has external linkage by construction.
#
# THE DESIGN CHANGED ON 2026-09-18 AND THE INDIRECTION DID NOT FOLLOW IT.  ZERO-PLAN.md
# 4c is now one file with two parts and the first `#include` as the boundary, so the
# host's definitions sit BELOW the core in the SAME translation unit.  A `static`
# forward declaration above and a `static` definition below is all a direct call needs,
# and nothing becomes external: the global the indirection existed to avoid does not
# appear.  So this phase spends two prototypes and gets back two objects, two
# parameters, two assignments and two arguments:
#
#     static void host_exit(int r);                            beside the nine musl_
#     static void host_message(const char *, int, int);        prototypes phase 20 left
#     host_exit(r);            in mch_exit                     1 call site
#     host_message(...);       in five core functions          8 call sites
#     vim_main(int argc, char **argv)                          the signature phase 18
#                                                              wrote, back again
#
# WHERE THE DECLARATIONS GO, AND IT IS NOT "THE TOP OF THE FILE".  Phase 20 left NINE
# `musl_` prototypes in one run -- musl_host_init, musl_get_winsize, musl_term_start,
# musl_term_stop, musl_tty_keys, musl_delay, musl_wait_for_input, musl_read_input,
# musl_suspend -- and those ARE the core's declared calls to the host.  The two go at
# the end of that run, in the order their definitions appear at the bottom of the file,
# so the boundary is ELEVEN prototypes in ONE block and not nine in a block and two
# wherever an object happened to sit.  That it is above every call site is COMPUTED
# here and asserted again in the check, by line number, and not assumed; and it will
# still be above them when a later phase moves the definitions further down, because a
# forward declaration's whole job is to make definition order not matter (CLAUDE.md).
#
# THE PROTOTYPE IS BUILT OUT OF THE DEFINITION'S OWN TWO LINES, so the two cannot
# disagree.  `    static void` + `host_exit(int r)` + `;` is the text that goes in, read
# from the file rather than retyped.
#
# `static` ON BOTH, AND IT IS THE TRAP THIS PHASE CAN FALL INTO.  A prototype that
# forgets it is either a hard error -- MEASURED, `static declaration of 'host_exit'
# follows non-static declaration` -- or, if the definition forgets it too, a SILENTLY
# CORRECT BUILD with two more external symbols.  MEASURED: `nm --extern-only
# --defined-only` on that variant prints `host_exit`, `host_message` and `main` where
# it must print `main` alone.  pipes/zero25-check.sh builds both variants.
#
# THE ASYMMETRY, AND IT IS WHY THIS PHASE COSTS TWO DECLARATIONS AND NOT FOUR.  In one
# translation unit everything above the cut is visible below it for free, so only the
# core -> host direction ever needs a name declared.  MEASURED on this file: the four
# functions that still hold a `va_list` -- `vim_snprintf`, `vim_vsnprintf`,
# `vim_vsnprintf_typval` and `skip_to_arg`, the ones a later phase moves below the
# boundary -- call TWENTY distinct core functions at FORTY-ONE sites, `emsg`, `iemsg`,
# `iobuff_or` and `emsg_iobuff_room` among them, and read `IObuff` once.  A two-file
# split would have had to answer for every one of those; phase 22's survey flagged
# exactly that and called it a genuine boundary question with three unattractive
# answers.  UNDER ONE FILE THERE IS NO QUESTION, and it is recorded here so that the
# earlier note does not send the next reader looking for a problem that the design
# dissolved rather than solved.
#
# THE BINARY WILL NOT BE BYTE-IDENTICAL AND THIS PHASE DOES NOT AIM FOR IT.  At -O0 a
# call through a pointer loads the pointer and calls the register; a direct call is a
# relative call to a known address.  Different instructions, and removing two file-scope
# objects moves everything after them.  MEASURED: the same 788,488 bytes, and 347,279 of
# them differ.  So the evidence is the RECORDING -- two full tools/zrecord.sh runs,
# byte-identical -- which is how every zero phase before 23 was checked, with a control
# for each of the two names this phase makes direct.
#
# THE INPUT BINARY IS BUILT HERE with SOURCE_DATE_EPOCH=0, and the check records from it.
set -eu

work=${1:?usage: zero25-edit.sh <work-dir> <state-dir>}
state=${2:?usage: zero25-edit.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"

# The flags are read out of the boundary's makefile rather than written here a second
# time: zero's compile line is the boundary's (ZERO-GOAL.md rule 8).
cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")
cp "$f" "$state/old.c"
# shellcheck disable=SC2086
( cd "$state" && SOURCE_DATE_EPOCH=0 gcc $cflags $ldflags -o old old.c ) &
pid_old=$!

python3 - "$f" <<'PY'
import re
import sys

TAG = 'hostcall'
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


def once(text, what, why):
    if t.count(text) != 1:
        die('%s occurs %d times, expected 1 -- %s' % (what, t.count(text), why))


def swap(old, new, what, why):
    global t
    once(old, what, why)
    t = t.replace(old, new, 1)


lines_before = len(t.split('\n')) - 1
runs_before = blank_runs(t)

# ---- 0. the file this edit was written against --------------------------------------
# ELEVEN DIRECTIVES on the first eleven lines, every one an `#include` of a system
# header (ZERO-GOAL.md's charter, phase 21's count).  This phase adds a declaration and
# not a directive, so it must leave that exactly where it found it.
lines = t.split('\n')
directives = [(i, l) for i, l in enumerate(lines) if l.startswith('#')]
if len(directives) != 11 or [i for i, _ in directives] != list(range(11)):
    die('the file does not have exactly eleven preprocessor directives on its first '
        'eleven lines: %d directives at lines %s'
        % (len(directives), ' '.join(str(i) for i, _ in directives)))
if any(not re.match(r'^#include <[A-Za-z0-9_/.]+>$', l) for _, l in directives):
    die('a directive is not an `#include <...>` of a system header, and no phase may '
        'add one')

# ---- 1. the two pointers, and every mention of each ----------------------------------
# A PARTITION AND NOT A COUNT.  `vim_host_exit` is three words -- its declaration, the
# one installation and the one call -- and `vim_host_message` is ten, the same three
# shapes with eight calls.  Each is taken out below, so anything this arithmetic does
# not account for would survive into a file where the object no longer exists, and the
# compile would stop.
for name, want, why in (
        ('vim_host_exit', 3, 'its declaration, the assignment in vim_main and the one '
                             'call in mch_exit'),
        ('vim_host_message', 10, 'its declaration, the assignment in vim_main and '
                                 'EIGHT calls'),
        ('exit_fn', 2, "vim_main's third parameter and the assignment that reads it"),
        ('message_fn', 2, "vim_main's fourth parameter and its assignment"),
        ('host_exit', 2, "the launcher's definition and the argument main() passes"),
        ('host_message', 2, 'the same two, for the message call'),
        ('vim_main', 2, 'its definition and the one call from the launcher'),
        ('main', 1, "the launcher's head, still the only bare `main` in the file")):
    if mentions(t, name) != want:
        die('`%s` has %d mentions, expected %d -- %s'
            % (name, mentions(t, name), want, why))
n_exit_calls = len(re.findall(r'(?<!\w)vim_host_exit\(', t))
n_msg_calls = len(re.findall(r'(?<!\w)vim_host_message\(', t))
if n_exit_calls != 1 or n_msg_calls != 8:
    die('%d calls through vim_host_exit and %d through vim_host_message, expected 1 '
        'and 8 -- the other two mentions of each are its declaration and its one '
        'assignment' % (n_exit_calls, n_msg_calls))
say('`vim_host_exit` is THREE mentions and `vim_host_message` is TEN, and each '
    'partitions into a declaration, one assignment in vim_main and its calls -- ONE '
    'and EIGHT.  Nothing else in the file names either')

# ---- 2. the prototypes, built out of the definitions' own lines ----------------------
# The two cannot disagree with what they declare, because the text that goes in is read
# from the text it declares.  BOTH ARE `static`: a prototype that forgot the keyword is
# either a hard error against the static definition or, with the definition changed too,
# a silently correct build with two more external symbols -- which is the one thing this
# whole pipeline has asserted since phase 0.
protos = []
for name in ('host_exit', 'host_message'):
    m = re.search(r'^    (static \w+)\n(%s\([^\n]*\))\n\{\n' % name, t, re.M)
    if not m:
        die('`%s` is not defined in this file\'s shape -- `    static <type>` on one '
            'line, the declarator on the next and `{` on the third -- so the prototype '
            'cannot be built out of it' % name)
    if not m.group(1).startswith('static '):
        die('`%s` is not defined `static`, and a non-static definition is an external '
            'symbol' % name)
    protos.append('%s %s;' % (m.group(1), m.group(2)))
say('the two prototypes are BUILT OUT OF THE DEFINITIONS\' OWN LINES and not retyped, '
    'so they cannot disagree with what they declare: %s' % '  /  '.join(protos))

# ---- 3. the nine prototypes phase 20 left, and the two that join them ----------------
# The boundary is one block.  `musl_suspend` is the last of phase 20's nine, and the
# order the two are added in is the order their definitions appear at the bottom.
swap('static void musl_suspend(void);\n',
     'static void musl_suspend(void);\n%s\n' % '\n'.join(protos),
     "the last of phase 20's nine musl_ prototypes",
     'the core -> host boundary is ONE run of declarations, and these two belong in it '
     'rather than wherever an object happened to sit')

# ---- 4. the two objects go ------------------------------------------------------------
swap('static int musl_towlower(int a);\n'
     '\n'
     'static void (*vim_host_message)(const char *msg, int len, int err);\n'
     '\n',
     'static int musl_towlower(int a);\n\n',
     "the vim_host_message object, where phase 21 put it",
     'it and the blank line that separated it from what follows go together, so the '
     'paragraphing either side of it is what it was')
swap('}\n'
     '\n'
     'static void (*vim_host_exit)(int);\n'
     '\n'
     '    static void\n'
     'mch_exit(int r)\n'
     '{\n',
     '}\n\n    static void\nmch_exit(int r)\n{\n',
     'the vim_host_exit object, where phase 19 put it -- immediately above mch_exit',
     'the same: the object and its blank line, leaving mch_exit separated from the '
     'function above it exactly as every other function in this file is')

# ---- 5. vim_main takes argc and argv, and nothing else -------------------------------
swap('    static int\n'
     'vim_main(int argc, char **argv, void (*exit_fn)(int), void (*message_fn)(const char *, int, int))\n'
     '{\n'
     '\n'
     '    vim_host_exit = exit_fn;\n'
     '    vim_host_message = message_fn;\n'
     '\n',
     '    static int\nvim_main(int argc, char **argv)\n{\n\n',
     "vim_main()'s head and the two installations",
     'the signature goes back to the one phase 18 wrote, and the two assignments and '
     'the blank line that followed them go with the parameters they read')
swap('    return vim_main(argc, argv, host_exit, host_message);\n',
     '    return vim_main(argc, argv);\n',
     "main()'s one statement",
     'the launcher no longer hands the core anything but its command line')

# ---- 6. the nine call sites ------------------------------------------------------------
t, a = re.subn(r'(?<!\w)vim_host_exit\(', 'host_exit(', t)
t, b = re.subn(r'(?<!\w)vim_host_message\(', 'host_message(', t)
if a != n_exit_calls or b != n_msg_calls:
    die('the renames took %d and %d where %d and %d were counted'
        % (a, b, n_exit_calls, n_msg_calls))
say('%d call site renamed to `host_exit` and %d to `host_message`, and vim_main is '
    '`vim_main(int argc, char **argv)` again -- two objects, two parameters, two '
    'assignments and two arguments gone, two prototypes arrived' % (a, b))

# ---- 7. what the file is now -----------------------------------------------------------
L = t.split('\n')
if mentions(t, 'vim_host_exit') or mentions(t, 'vim_host_message'):
    die('a `vim_host_*` name survives')
if mentions(t, 'exit_fn') or mentions(t, 'message_fn'):
    die('a parameter name survives the signature it was written for')
for name, want, why in (
        ('host_exit', 3, 'the prototype, the one call in mch_exit and the definition'),
        ('host_message', 10, 'the prototype, EIGHT calls and the definition'),
        ('vim_main', 2, 'its definition and the one call from the launcher'),
        ('main', 1, 'still the only bare `main` in the file')):
    if mentions(t, name) != want:
        die('`%s` has %d mentions after the edit, expected %d -- %s'
            % (name, mentions(t, name), want, why))

# DECLARATION BEFORE USE, COMPUTED.  The prototype must be above every call and the
# definition below every one of them; a later phase moves the definitions further down
# and this stays true, which is the whole point of a forward declaration.
for name in ('host_exit', 'host_message'):
    proto = [i for i, l in enumerate(L) if l in protos and name + '(' in l]
    defn = [i for i, l in enumerate(L) if l.startswith(name + '(') and L[i + 1] == '{']
    uses = [i for i, l in enumerate(L)
            if re.search(r'(?<!\w)%s\(' % name, l) and i not in proto and i not in defn]
    if len(proto) != 1 or len(defn) != 1 or not uses:
        die('`%s` has %d prototypes, %d definitions and %d call sites, and this phase '
            'needs exactly one, one and at least one'
            % (name, len(proto), len(defn), len(uses)))
    if proto[0] >= min(uses):
        die('`%s`\'s prototype is at line %d and its first call at line %d -- a call '
            'above its declaration' % (name, proto[0] + 1, min(uses) + 1))
    if defn[0] <= max(uses):
        die('`%s`\'s definition is at line %d and its last call at line %d -- the '
            'definition must be below every call, which is what makes the prototype '
            'load-bearing' % (name, defn[0] + 1, max(uses) + 1))
    say('`%s`: prototype at line %d, %d call site%s at %s, definition at line %d -- '
        'declared above every use and defined below every one of them'
        % (name, proto[0] + 1, len(uses), '' if len(uses) == 1 else 's',
           ' '.join(str(u + 1) for u in uses), defn[0] + 1))

block = [i for i, l in enumerate(L) if l == 'static void musl_suspend(void);']
if len(block) != 1 or L[block[0] + 1] != protos[0] or L[block[0] + 2] != protos[1]:
    die('the two prototypes are not the two lines below `static void '
        'musl_suspend(void);` -- the core -> host boundary is one block')
n_boundary = 0
i = block[0]
while i >= 0 and re.match(r'^static [\w ]+\**(musl_|host_)\w+\([^\n]*\);$', L[i]):
    n_boundary += 1
    i -= 1
n_boundary += 2
say('the core -> host boundary is now ONE run of %d prototypes ending at line %d: '
    "phase 20's nine `musl_` and these two" % (n_boundary, block[0] + 3))

if len(L) - 1 != lines_before - 5:
    die('the file is %d lines and the input was %d -- expected exactly 5 fewer: two '
        'objects with their blank lines is four, two prototypes back is two, and the '
        'two assignments with their blank line is three'
        % (len(L) - 1, lines_before))
if blank_runs(t) != runs_before:
    die('the edit left %d runs of two blank lines where there were %d'
        % (blank_runs(t), runs_before))
d = [l for l in L if l.startswith('#')]
if len(d) != 11 or any(not l.startswith('#include <') for l in d) or L[:11] != d:
    die('the output does not have exactly the eleven `#include` directives phase 21 '
        'left, on its first eleven lines -- this phase adds a DECLARATION and not a '
        'directive')
say('%d -> %d lines, the eleven #includes untouched, and no run of two blank lines'
    % (lines_before, len(L) - 1))

open(path, 'w', errors='surrogateescape').write(t)
PY

# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  hostcall     the input binary did not build with '$cflags' '$ldflags'"; exit 1; }
echo "  hostcall     the input is $state/old, $(stat -c%s "$state/old") bytes, built with SOURCE_DATE_EPOCH=0 beside the source it came from -- an indirect call and a direct one are different instructions at -O0, so the binary is NOT byte-identical and the evidence is a RECORDING of each"

# tools/phaserun.sh sweeps next, then runs pipes/zero25-check.sh.
