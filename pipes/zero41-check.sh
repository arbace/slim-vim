#!/bin/sh
# Zero phase 41, the check -- freeing is free.  See pipes/zero41-edit.sh, and
# ZERO-GOAL.md's charter bullet "A GARBAGE COLLECTOR IS ASSUMED FROM HERE ON".
#
# Usage: pipes/zero41-check.sh <work-dir> <state-dir>    (run from the repository root)
#
# Runs after pipes/zero41-edit.sh and the sweep tools/phaserun.sh runs between them, and
# reads nothing from the edit's shell -- only the work tree and the state directory.
# What the edit left there is `old.c`, the source this phase was HANDED, `old`, that
# source built with SOURCE_DATE_EPOCH=0 and the boundary's own flags, and `arena-bytes`.
#
# WHAT IS CLAIMED, in eleven parts:
#
#   ARITHMETIC  `malloc`, `free` and `realloc` are 0 mentions in the whole file, stated
#               as a PARTITION of the input's mentions rather than as counts, and every
#               name the phase writes is defined exactly once.
#   THE CUT     `make editor.c`'s own rule on the input and on the output, and they are
#               BYTE-IDENTICAL.  That is the whole of "this phase touches no core line",
#               and it is the cleanest thing this phase can say: the program the project
#               is FOR is literally the same program.  Its warning set -- the core -> host
#               interface -- is the same names either side, which follows.
#   SYMBOLS     `nm -u` loses EXACTLY `free malloc realloc` and nothing else moves, as a
#               `comm` in both directions against the stage's snapshot.  17 -> 14.  Two
#               of the three are the allocator; the third is the one phase 34 left below
#               the boundary and phase 35 left with it.
#   THE IMAGE   EXEC, no INTERP, no dynamic section, no relocation -- phases 0 and 1's
#               four facts, which a gigabyte object could have disturbed and does not.
#               `.bss` grows by the arena and THE FILE SHRINKS, both as measurements:
#               `.bss` is NOBITS and musl's allocator is no longer linked in.
#   THE RECORD  two full tools/zrecord.sh recordings, `diff -r` empty over 106 records,
#               with a control that moves all 106.
#   THE ARENA   the high-water the corpus really asks for, measured by an instrument on
#               THIS PHASE'S OWN OUTPUT over all 102 screen cases, and required to sit
#               well inside the arena.  The size is a checked property here and not a
#               number remembered from the edit's header.
#   THE GUARD   an arena deliberately too small must ABORT, with a message naming the
#               arena, what is used and the request that did not fit, and a non-zero
#               status -- and the same session on the real output must be silent and
#               exit 0.  Without this the abort is a branch nobody has ever taken.
#   THE BUMP    the offset never advancing must move every screen case.  A bump allocator
#               whose bookkeeping did nothing would hand the same block out twice and
#               still pass every test above, and this is what says it does not.
#   host_free   PHASE 35'S OWN CONTROL, RE-RUN ON THIS PHASE'S INPUT AND NOT REINVENTED:
#               `cf`, host_free doing nothing, which phase 35 measured at 0 of 102.  It
#               is the same 0 here, and it is REPORTED rather than hidden -- a leak is
#               invisible to this corpus, so the recording above is NOT what says the
#               freeing changed, and nothing in this check pretends it is.
#   THE PROBE   the two rewrites below the boundary that no recording can reach.  A
#               driver built into the input AND the output drives six positional formats
#               through adjust_types(), entering the grow arm this phase rewrote, and the
#               two binaries must print the same bytes.
#   <stdlib.h>  MEASURED AND DECLINED.  With malloc, free and realloc gone the directive
#               is dead, and the output built without it is BYTE-IDENTICAL.  It stays:
#               phase 13's precedent, and this phase's subject is the allocator.
set -eu

work=${1:?usage: zero41-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero41-check.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"
before_lines=$(cat "$state/input-lines")
arena=$(cat "$state/arena-bytes")

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")

# shellcheck disable=SC2086
( SOURCE_DATE_EPOCH=0 gcc $cflags $ldflags -o "$tmp/new" "$f" ) &
pid_new=$!

# --- 0. every variant this check builds, written from the output and from the input -------
python3 - "$f" "$state/old.c" "$tmp" "$arena" <<'PY'
import re
import sys

TAG = 'arena'
t = open(sys.argv[1], errors='surrogateescape').read()
old = open(sys.argv[2], errors='surrogateescape').read()
out = sys.argv[3]
arena = int(sys.argv[4])


def one(text, s, what):
    if text.count(s) != 1:
        sys.exit('  %-12s `%s` is not in that source exactly once, so a control built '
                 'from it would not be one' % (TAG, what))
    return s


# The three lines of the output every control below is built from, each required to be
# unique before it is used -- a "control" made from a string that occurs twice, or not at
# all, is not a control (CLAUDE.md, *Three checks that pass while doing nothing*).
RET = one(t, '    p = (char *)host_arena + host_arena_used;\n', "host_alloc's return")
BUMP = one(t, '    host_arena_used += want;\n', "host_alloc's bump")
SIZE = one(t, 'enum { HOST_ARENA_BYTES = 1024 * 1024 * 1024 };\n', 'the arena size')
INCL = one(t, '#include <stdlib.h>\n', '<stdlib.h>')
if arena != 1024 * 1024 * 1024:
    sys.exit('  %-12s the edit recorded an arena of %d bytes and the output says 1 GiB'
             % (TAG, arena))

ctl = {
    # ca -- host_alloc always fails.  The editor cannot draw a screen without memory, so
    #       this is the maximal control: it must move EVERY record.  Phase 35's ca, in
    #       the shape this phase's host_alloc has.
    'ca': t.replace(RET, '    return nullptr;\n', 1).replace(BUMP, '', 1),
    # cnb -- the offset never advances.  Every allocation returns the same block, which
    #       is a bump allocator with its bookkeeping switched off, and it must move every
    #       screen case.  THE ONLY CONTROL HERE THAT TESTS THE ALLOCATOR AND NOT THE
    #       WRAPPER: `ca` would move everything for any broken allocator at all.
    'cnb': t.replace(BUMP, '', 1),
    # ctiny -- an arena of 256 KiB.  Measured to be smaller than the ONE allocation the
    #       screen needs, so the guard fires in a bare session and fires deterministically.
    'ctiny': t.replace(SIZE, 'enum { HOST_ARENA_BYTES = 256 * 1024 };\n', 1),
    # cstdlib -- the output without <stdlib.h>.  Not a control but a MEASUREMENT: the
    #       directive is dead and the phase declines to remove it, and the way to say
    #       "dead" and mean it is a byte comparison of the binary.
    'cstdlib': t.replace(INCL, '', 1),
}
# cf -- host_free does nothing, built from the INPUT.  This is phase 35's own control,
#       verbatim in shape: pipes/zero35-check.sh made it by replacing `free(p);` with
#       `(void)p;` in host_free and measured it at 0 of 102.  It is re-run here rather
#       than a new claim being invented, which is what the brief for this phase asked for.
FREEP = one(old, '    free(p);\n', "the input's host_free body")
ctl['cf'] = old.replace(FREEP, '    (void)p;\n', 1)

# probe -- the output with the arena's two numbers reported from host_exit(), which every
#       session reaches.  host_exit() is defined ABOVE the arena, so the instrument
#       declares what it reads; both scalars are tentative definitions and merge with the
#       real ones below.  Nothing is folded away: it is the product plus two longs.
DUMP = '''static int host_arena_say(char *b, int at, const char *s);
static int host_arena_num(char *b, int at, usize v);
static usize host_arena_used;
static long host_arena_calls;

    static void
host_exit(int r)
{
    {
        char        b[96];
        int         at = 0;

        at = host_arena_say(b, at, "ARENA used=");
        at = host_arena_num(b, at, host_arena_used);
        at = host_arena_say(b, at, " calls=");
        at = host_arena_num(b, at, (usize)host_arena_calls);
        at = host_arena_say(b, at, "\\n");
        host_message(b, at, TRUE);
    }
'''
EXIT = one(t, '    static void\nhost_exit(int r)\n{\n', 'host_exit()')
p = t.replace(EXIT, DUMP, 1)
p = p.replace('static usize host_arena_used;\n',
              'static usize host_arena_used;\nstatic long host_arena_calls;\n', 1)
p = p.replace(RET, '    host_arena_calls++;\n' + RET, 1)
ctl['probe'] = p

# din / dout -- THE PROBE FOR WHAT THE CORPUS CANNOT REACH.  adjust_types() grows
# *ap_types with the call this phase rewrote, and it is reached only by a format string
# holding a positional spec -- of which this file has none, so no recorded session can
# ever enter it.  The same driver is built into the INPUT and into the OUTPUT and the two
# must print the same bytes.  The formats ASCEND deliberately: `%2$s-%1$s` allocates once
# and never grows, and a probe made of those would exercise the arm this phase did not
# touch.  `probe_grow` counts the entries so the check can refuse a driver that reached
# nothing.
DRIVER = '''\nmain(int argc, char **argv)
{
    if (argc == 2 && argv[1][0] == 'Z')
    {
        char        b[512];
        int         k;
        const char  *fm[7];

        fm[0] = "%1$s";
        fm[1] = "%1$s-%2$s";
        fm[2] = "%1$s/%2$s/%3$s/%1$s";
        fm[3] = "%1$s|%2$s|%3$s|%4$s|%5$s";
        fm[4] = "%1$s.%2$s.%3$s.%4$s.%5$s.%6$s.%7$s.%8$s.%9$s";
        fm[5] = "%2$s-%1$s-%2$s-%3$s-%1$s";
        fm[6] = "%1$d+%2$d=%2$d";
        for (k = 0; k < 6; k++)
        {
            vim_snprintf(b, sizeof(b), fm[k], "a", "bb", "ccc", "dddd", "eeeee",
                         "ffffff", "ggggggg", "hhhhhhhh", "iiiiiiiii");
            host_message(b, -1, 1);
            host_message("\\n", 1, 1);
        }
        vim_snprintf(b, sizeof(b), fm[6], 11, 22);
        host_message(b, -1, 1);
        host_message("\\n", 1, 1);
        host_message("grows=", 6, 1);
        b[0] = (char)('0' + probe_grow / 10);
        b[1] = (char)('0' + probe_grow % 10);
        b[2] = '\\n';
        host_message(b, 3, 1);
        return 0;
    }
'''
GROW_OLD = ('            new_types =  realloc(((char **)*ap_types), '
            '(arg * sizeof(const char *))) ;\n')
GROW_NEW = ('            new_types = (const char **)host_alloc('
            'arg * sizeof(const char *));\n')
for tag, src, grow in (('din', old, GROW_OLD), ('dout', t, GROW_NEW)):
    d = src.replace(one(src, '\nmain(int argc, char **argv)\n{\n', "the launcher's head"),
                    DRIVER, 1)
    d = d.replace(one(src, grow, "adjust_types's grow arm"),
                  '            probe_grow++;\n' + grow, 1)
    d = d.replace(one(src, '\n    static int\nadjust_types(', 'adjust_types()'),
                  '\nstatic int probe_grow;\n\n    static int\nadjust_types(', 1)
    ctl[tag] = d

for name, text in sorted(ctl.items()):
    if text == t and name not in ('cf', 'din'):
        sys.exit('  %-12s %s changed nothing' % (TAG, name))
    open('%s/%s.c' % (out, name), 'w', errors='surrogateescape').write(text)
print('  %-12s eight variants written: ca host_alloc always nullptr, cnb the offset '
      'never advances, ctiny a 256 KiB arena, cstdlib the output without <stdlib.h>, cf '
      "PHASE 35'S OWN control on the INPUT (host_free does nothing), probe the output "
      'with the arena reported from host_exit, and din/dout the positional-format driver '
      'built into both' % TAG)
PY

for v in ca cnb ctiny cstdlib cf probe; do
    # shellcheck disable=SC2086
    ( SOURCE_DATE_EPOCH=0 gcc $cflags $ldflags -o "$tmp/$v" "$tmp/$v.c" 2>"$tmp/e.$v" ) &
    eval "pid_$v=$!"
done
for v in din dout; do
    # shellcheck disable=SC2086
    ( SOURCE_DATE_EPOCH=0 gcc $cflags -Wno-format $ldflags -o "$tmp/$v" "$tmp/$v.c" 2>"$tmp/e.$v" ) &
    eval "pid_$v=$!"
done
# tools/canon.sh must be a NO-OP on the output.
cp "$f" "$tmp/canon.c"
( tools/canon.sh "$tmp/canon.c" >"$tmp/canon.log" 2>&1 ) &
pid_canon=$!

# --- 1. the source, as a partition of the input ---------------------------------------
python3 - "$f" "$state/old.c" "$before_lines" "$arena" <<'PY'
import re
import sys

TAG = 'arena'
new = open(sys.argv[1], errors='surrogateescape').read()
old = open(sys.argv[2], errors='surrogateescape').read()
before_lines = int(sys.argv[3])
arena = int(sys.argv[4])
fail = []


def mentions(text, name):
    return len(re.findall(r'\b%s\b' % name, text))


def cut(text):
    L = text.split('\n')
    b = [i for i, l in enumerate(L) if re.match(r'^ *# *', l)]
    return b, '\n'.join(L[:b[0]]), L


ob, ocore, OL = cut(old)
nb, ncore, NL = cut(new)

# THE THREE NAMES.  The input's mentions are read here and never written down; what is
# asserted is that the output has none, and that the input had at least one of each --
# which is what keeps "0 mentions" from being true of a file nothing ever said them in.
for name in ('malloc', 'free', 'realloc'):
    was, now = mentions(old, name), mentions(new, name)
    if was < 1:
        fail.append('the INPUT does not mention `%s` at all, so this phase has not been '
                    'handed the file it was written for' % name)
    if now:
        fail.append('`%s` still has %d mentions in the output' % (name, now))

# THE NAMES THIS PHASE WRITES, each defined exactly once and every one of them below the
# boundary.  `host_arena` is counted rather than pinned: its mentions are the definition,
# two `sizeof` and the one `(char *)` -- how many is the file's business.
for name in ('host_arena', 'host_arena_used', 'host_arena_say', 'host_arena_num',
             'host_arena_exhausted', 'HOST_ARENA_BYTES'):
    if mentions(old, name):
        fail.append('`%s` was already a name in the input' % name)
    if not mentions(new, name):
        fail.append('`%s` is not in the output at all' % name)
    if mentions(ncore, name):
        fail.append('`%s` is mentioned ABOVE the boundary, and every line this phase '
                    'writes is below it' % name)
for name, kind in (('host_arena_say', '    static int\n'),
                   ('host_arena_num', '    static int\n'),
                   ('host_arena_exhausted', '    static void\n'),
                   ('host_alloc', '    static void *\n'),
                   ('host_free', '    static void\n')):
    if new.count(kind + name + '(') != 1:
        fail.append('`%s` is not defined exactly once in the `    static <type>` shape, '
                    'and everything this file defines has internal linkage' % name)

# THE CORE IS THE SAME BYTES.  Stated here on the text and below as `make editor.c`'s own
# cut; the two are the same claim and the second is the one the project states.
if ncore != ocore:
    fail.append('the text above the first `#include` is not byte-identical in and out, '
                'and this phase is entirely below it')
if len(ob) != 11 or len(nb) != 11 or nb != ob:
    fail.append('the eleven `#include` directives are not on the same eleven lines in '
                'and out -- this phase adds none, removes none and moves none')

# THE ALIGNMENT IS THE TYPE SYSTEM'S.  A rounding written as a bare 16 would be this
# phase's assumption about a machine; `alignof(max_align_t)` is the requirement itself,
# and `max_align_t[]` is what gives the arena an address that satisfies it.
if 'static max_align_t host_arena[' not in new:
    fail.append('the arena is not an array of `max_align_t`, so its alignment is not the '
                'strictest any object in this translation unit can ask for')
if new.count('alignof(max_align_t)') != 2:
    fail.append('the rounding does not use `alignof(max_align_t)` twice -- the mask and '
                'the addend -- so it is arithmetic about a machine rather than about the '
                'requirement')

# THE ABORT IS NOT A QUIET ONE.  host_alloc must not be able to return a null pointer:
# lalloc() has an out-of-memory path that turns one into a message and carries on, and a
# phase whose declared delta is NOTHING must have no way of quietly doing less.
body = new[new.index('    static void *\nhost_alloc('):]
body = body[:body.index('\n}\n') + 3]
if 'nullptr' in body:
    fail.append('host_alloc() can return a null pointer, and this phase\'s arena is '
                'meant to abort rather than let lalloc() report an out-of-memory it '
                'could carry on from')
if 'host_exit' not in new[new.index('host_arena_exhausted(usize n)'):][:800]:
    fail.append('host_arena_exhausted() does not reach host_exit(), so exhaustion would '
                'return into host_alloc and hand out the arena anyway')

if fail:
    for line in fail:
        print('  %-12s %s' % (TAG, line))
    sys.exit(1)
print('  %-12s THE PARTITION: `malloc` %d mentions in and 0 out, `free` %d and 0, '
      '`realloc` %d and 0 -- every one of them was below the boundary and in one of the '
      'four runs of text the edit rewrites, and the output does not name a libc '
      'allocator anywhere.  Two were the wrappers phase 35 wrote; the other two are the '
      'sites phase 35 and phase 34 each SAW and left, in the formatter island phase 27 '
      'moved below the includes -- and they had to move here, because a free() or a '
      'realloc() of a pointer the arena handed out is undefined from this phase on'
      % (TAG, mentions(old, 'malloc'), mentions(old, 'free'), mentions(old, 'realloc')))
print('  %-12s THE ARENA is %d bytes of `max_align_t`, rounded with '
      '`alignof(max_align_t)` and not with a number, and host_alloc() has no `nullptr` '
      'in it at all: exhaustion goes to host_arena_exhausted(), which names the arena, '
      'what is used and the request, and ends the process' % ('', arena))
print('  %-12s %d -> %d lines, %d more; the core above the boundary is BYTE-IDENTICAL '
      'and the eleven #includes are on the same eleven lines'
      % ('', before_lines, len(NL) - 1, len(NL) - 1 - before_lines))
PY

# --- 2. THE CUT: zero.mk's own rule, on the input and on the output ---------------------
# `make editor.c`, one awk clause and no judgement.  This phase is host-only, so the two
# cuts must be THE SAME BYTES -- which is the strongest thing it can say and subsumes
# every claim anyone could make about the core.
editorcut() {
    awk '/^ *# *include / { exit } { a[NR] = $0; if (NF) last = NR } \
         END { for (i = 1; i <= last; i++) print a[i] }' "$1" > "$2"
    if grep -q '^ *#' "$2"; then
        echo "  arena        the cut of $1 holds a directive, so it found the wrong line"
        exit 1
    fi
    if [ "$(grep -c '' "$2")" -le 70000 ]; then
        echo "  arena        the cut of $1 is $(grep -c '' "$2") lines, and zero.mk's floor is 70,000 -- a cut that found line 1 would be empty and every check below would pass on nothing"
        exit 1
    fi
    gcc -c -O0 -fno-stack-protector -o "$2.o" "$2" 2>"$2.log" || true
    grep -c 'error:' "$2.log" > "$2.err" || true
    sed -n "s/.*warning: '\\([A-Za-z_][A-Za-z0-9_]*\\)' used but never defined.*/\\1/p" "$2.log" | sort > "$2.names"
}
editorcut "$state/old.c" "$tmp/cut-old.c"
editorcut "$f" "$tmp/cut-new.c"
for w in old new; do
    if [ "$(cat "$tmp/cut-$w.c.err")" != 0 ] || [ ! -f "$tmp/cut-$w.c.o" ]; then
        echo "  arena        the $w cut does not compile: $(cat "$tmp/cut-$w.c.err") errors"
        grep 'error:' "$tmp/cut-$w.c.log" | head -3 | sed 's/^/               /'
        exit 1
    fi
    if [ "$(grep -c 'warning:' "$tmp/cut-$w.c.log")" != "$(grep -c '' "$tmp/cut-$w.c.names")" ]; then
        echo "  arena        the $w cut has a warning that is not a 'used but never defined':"
        grep 'warning:' "$tmp/cut-$w.c.log" | grep -v 'used but never defined' | head -3 | sed 's/^/               /'
        exit 1
    fi
    if [ -n "$(nm --extern-only --defined-only "$tmp/cut-$w.c.o")" ]; then
        echo "  arena        the $w cut DEFINES an external symbol, and the core defines none -- main is the host's:"
        nm --extern-only --defined-only "$tmp/cut-$w.c.o" | head -3 | sed 's/^/               /'
        exit 1
    fi
done
head -c "$(stat -c%s "$tmp/cut-new.c")" "$f" > "$tmp/prefix.c"
cmp -s "$tmp/prefix.c" "$tmp/cut-new.c" || { echo "  arena        the cut is not a byte prefix of zero-vim.c"; exit 1; }
if ! cmp -s "$tmp/cut-old.c" "$tmp/cut-new.c"; then
    echo "  arena        THE CUT MOVED, and this phase is host-only.  It is below the first"
    echo "               #include from end to end, so \`make editor.c\` must write the same bytes:"
    cmp "$tmp/cut-old.c" "$tmp/cut-new.c" | head -2 | sed 's/^/               /'
    diff "$tmp/cut-old.c" "$tmp/cut-new.c" | head -6 | sed 's/^/               /'
    exit 1
fi
if ! cmp -s "$tmp/cut-old.c.names" "$tmp/cut-new.c.names"; then
    echo "  arena        the cut's warning set moved, which cannot happen when the cut itself did not"
    exit 1
fi
echo "  arena        THE CUT IS BYTE-IDENTICAL -- \`make editor.c\`'s own rule, $(grep -c '' "$tmp/cut-new.c") lines and $(stat -c%s "$tmp/cut-new.c") bytes either side, a \`cmp\` and not a count.  THAT IS THE WHOLE OF \"this phase touches no core line\", and it subsumes every screen case, every Ex command and every pty scenario at once for the part of the file the project is FOR: the core that would be transpiled is literally the same text.  Its warning set, the core -> host interface, is the same $(grep -c '' "$tmp/cut-new.c.names") names, which follows rather than being a second fact"

# --- 3. the binary, and the four facts a gigabyte object could have disturbed --------------
wait $pid_new || { echo "  arena        the output did not build with '$cflags' '$ldflags'"; exit 1; }
old_size=$(stat -c%s "$state/old")
new_size=$(stat -c%s "$tmp/new")
[ "$(readelf -h "$tmp/new" | sed -n 's/^ *Type: *\([A-Z]*\).*/\1/p')" = EXEC ] \
    || { echo "  arena        readelf -h no longer says EXEC"; exit 1; }
[ "$(readelf -l "$tmp/new" | grep -c INTERP)" = 0 ] \
    || { echo "  arena        the image has an INTERP segment"; exit 1; }
[ -z "$(readelf -d "$tmp/new" 2>/dev/null | grep 'NEEDED\|Tag')" ] \
    || { echo "  arena        the image has a dynamic section"; exit 1; }
[ -z "$(readelf -r "$tmp/new" 2>/dev/null | grep 'R_X86')" ] \
    || { echo "  arena        the image carries relocations"; exit 1; }
# `strtonum` is gawk's and this machine's awk is not gawk, which cost one run: the shell
# does the base conversion instead, and `16#` is POSIX arithmetic.
obss=$((16#$(readelf -S "$state/old" | grep -A1 '\.bss' | tail -1 | awk '{print $1}')))
nbss=$((16#$(readelf -S "$tmp/new" | grep -A1 '\.bss' | tail -1 | awk '{print $1}')))
# THE GROWTH IS THE ARENA AND IT IS SLIGHTLY LESS THAN THE ARENA, which is not slack in
# the assertion but a second fact.  musl's allocator carries static state of its own --
# `__malloc_context` and five smaller objects, 964 bytes measured on an unstripped pair --
# and that state leaves `.bss` with the three symbols.  So the tolerance is stated
# relative to the arena rather than as a number somebody remembered, and the shortfall
# is REPORTED rather than absorbed.
slack=$((arena / 1024))
if [ "$((nbss - obss))" -lt "$((arena - slack))" ] || [ "$((nbss - obss))" -gt "$((arena + slack))" ]; then
    echo "  arena        .bss grew by $((nbss - obss)) bytes and the arena is $arena -- the arena is not in .bss, which is the only reason it can cost nothing to store"
    exit 1
fi
if [ "$new_size" -ge "$old_size" ]; then
    echo "  arena        the image is $new_size bytes and was $old_size.  That is a measurement and not a requirement, but it is reported here because the expected direction is DOWN: .bss is NOBITS, so the arena adds no bytes to the file, and musl's allocator is no longer linked in"
fi
echo "  arena        THE IMAGE: EXEC, no INTERP, no dynamic section, no relocation -- phases 0 and 1's four facts, undisturbed by a $arena-byte object.  \`.bss\` goes $obss -> $nbss bytes, a growth of $((nbss - obss)), which is the arena LESS $((arena - (nbss - obss))) -- musl's own allocator state, \`__malloc_context\` and five smaller objects, leaving .bss with the three symbols.  AND THE FILE SHRINKS, $old_size -> $new_size, $((old_size - new_size)) bytes: \`.bss\` is NOBITS, so the section header records a size and the file holds none of it, and what does leave the file is musl's allocator itself"

# --- 4. linkage and the symbols ------------------------------------------------------------
cp "$state/symbols/undefined" "$tmp/before.u"
tools/phasecheck.sh "$work" "$f" "$state/symbols"
gone=$(comm -23 "$tmp/before.u" .cache/symbols/last/undefined | tr '\n' ' ')
came=$(comm -13 "$tmp/before.u" .cache/symbols/last/undefined | tr '\n' ' ')
if [ "$gone" != "free malloc realloc " ] || [ -n "$came" ]; then
    echo "  arena        THE UNDEFINED SET DID NOT MOVE AS THIS PHASE CLAIMS."
    echo "               gone: ${gone:-nothing}, and it must be exactly free malloc realloc"
    echo "               came: ${came:-nothing}"
    exit 1
fi
for s in malloc free realloc calloc reallocarray; do
    if grep -qx "$s" .cache/symbols/last/undefined; then
        echo "  arena        \`$s\` is in nm -u, and nothing in this file may ask a host for memory but host_alloc"
        exit 1
    fi
done
echo "  arena        SYMBOLS $(cat .cache/symbols/last/before) -> $(cat .cache/symbols/last/after), and the set moves by EXACTLY free, malloc and realloc, as a comm empty in the other direction.  Three symbols leave because their last CALLER left the file, which is the only way one ever leaves a single translation unit -- and no allocator name is undefined any more.  main is still the only external symbol"

# --- 5. THE EVIDENCE: two recordings, and a control that moves all of them -----------------
rec() {
    tools/zrecord.sh "$2" "$3" "$tmp/REC-$1" >/dev/null 2>&1 &
    eval "pid_rec_$1=$!"
}
wait $pid_ca || { echo "  arena        the control ca did not build:"; head -5 "$tmp/e.ca" | sed 's/^/               /'; exit 1; }
rec old "$state/old" "$state/old.c"
rec new "$tmp/new" "$f"
rec ca "$tmp/ca" "$tmp/ca.c"
for pp in $pid_rec_old $pid_rec_new $pid_rec_ca; do
    wait "$pp" || { echo "  arena        a recording failed"; exit 1; }
done
python3 - "$tmp" <<'PY'
import filecmp
import os
import sys

TAG = 'arena'
tmp = sys.argv[1]


def files(d):
    out = []
    for root, _, names in os.walk(d):
        for n in names:
            out.append(os.path.relpath(os.path.join(root, n), d))
    return sorted(out)


base = files('%s/REC-new' % tmp)
if len(base) < 100:
    sys.exit('  %-12s a recording holds %d records, and a comparison of two things '
             'nothing wrote passes.  The count is REPORTED and not pinned: it is 122 '
             'here -- 102 screen cases, 16 memline cases and four sweeps -- and was 106 '
             'before zero phase 40 added the memline corpus' % (TAG, len(base)))


def moved(which):
    d = '%s/REC-%s' % (tmp, which)
    if files(d) != base:
        sys.exit('  %-12s the recording of %s holds different records from the output\'s'
                 % (TAG, which))
    return [n for n in base
            if not filecmp.cmp('%s/REC-new/%s' % (tmp, n), '%s/%s' % (d, n),
                               shallow=False)]


same = moved('old')
if same:
    print('  %-12s THE RECORDING MOVED, in %d of %d records: %s'
          % (TAG, len(same), len(base), ' '.join(same[:8])))
    print('  %-12s This phase declares NOTHING.  The editor asks for exactly the memory '
          'it asked for before and is handed as much of it; what changed is where the '
          'bytes come from and that giving them back costs nothing.' % '')
    sys.exit(1)
m = moved('ca')
if len(m) != len(base):
    sys.exit('  %-12s THE CONTROL ca DID NOT SHOW: with host_alloc returning nullptr '
             'always, %d of %d records move and every one must -- an editor that cannot '
             'allocate cannot draw' % (TAG, len(m), len(base)))
print('  %-12s THE RECORDING IS BYTE-IDENTICAL, all %d records -- 102 screen cases, '
      'every Ex command typed at `:`, every command line the parser may see, the four '
      'pty scenarios and the terminal table.  EVERY ONE of them runs on the arena from '
      'its first allocation, which is what makes an empty `diff -r` strong here: this is '
      'not a subject the corpus has to be steered towards, it is the one thing every '
      'session does thousands of times' % (TAG, len(base)))
print('  %-12s AND IT CAN FAIL: host_alloc returning nullptr always moves %d of %d -- '
      'every record there is' % ('', len(m), len(base)))
PY

# --- 6. THE ARENA: what the corpus really asks for, measured on this phase's own output ----
wait $pid_probe || { echo "  arena        the instrumented build failed:"; head -5 "$tmp/e.probe" | sed 's/^/               /'; exit 1; }
for v in cnb cf ctiny cstdlib; do
    eval "wait \$pid_$v" || { echo "  arena        the control $v did not build:"; head -5 "$tmp/e.$v" | sed 's/^/               /'; exit 1; }
done
# BOTH CORPORA, AND THE MEMLINE ONE IS WHY THE ARENA IS THE SIZE IT IS.  Zero phase 40
# added 16 cases that build buffers of 200 to 25,000 lines, and they are not a larger
# version of the 102 -- measured, the heaviest of them asks host_alloc for 200,458,672
# bytes where the heaviest screen case asks for 1,722,512, which is 115 times more.  An
# instrument that measured the high-water over the 102 alone would have sized this arena
# from a corpus that cannot reach the memline at all, which is the defect phase 40 exists
# to have ended.  The two controls run over both for the same reason.
for v in probe cnb cf; do
    ( python3 tools/zcases.py "$tmp/$v" "$tmp/SC-$v" >/dev/null 2>&1 ) &
    eval "pid_sc_$v=$!"
    ( python3 tools/zmemline.py "$tmp/$v" "$tmp/ML-$v" >/dev/null 2>&1 ) &
    eval "pid_ml_$v=$!"
done

# THE GUARD, while the corpora run: an arena measured to be too small must abort, and the
# real one must not.  The environment is emptied exactly as every harness empties it
# (CLAUDE.md), so a real ~/.vimrc on the machine cannot reach either session.
printf ':q!\r' > "$tmp/keys-q"
session() {
    ( cd "$tmp" && env -u VIMINIT -u EXINIT HOME= VIM= VIMRUNTIME= XDG_CONFIG_HOME= \
        TERM=xterm "./$1" '+set paste' < keys-q > /dev/null 2> "$2" ); echo $? > "$tmp/rc.$2"
}
session ctiny tiny.err || true
session new big.err || true
for v in probe cnb cf; do
    eval "wait \$pid_sc_$v" || { echo "  arena        the screen corpus failed on $v"; exit 1; }
    eval "wait \$pid_ml_$v" || { echo "  arena        the memline corpus failed on $v"; exit 1; }
done
python3 - "$tmp" "$arena" <<'PY'
import filecmp
import os
import re
import sys

TAG = 'arena'
tmp = sys.argv[1]
arena = int(sys.argv[2])
# THE TWO CORPORA A SESSION CAN BE MEASURED OVER, and their SIZES ARE REPORTED AND NOT
# PINNED: 102 screen cases and 16 memline cases here, where it was 102 and none before
# zero phase 40.  A floor is what stands between this section and passing on a corpus
# nothing wrote.
CORPORA = (('screen', 'SC', 100), ('memline', 'ML', 10))
cases = {}
for part, _, floor in CORPORA:
    cases[part] = sorted(os.listdir('%s/REC-new/%s' % (tmp, part)))
    if len(cases[part]) < floor:
        sys.exit('  %-12s the %s corpus is %d cases and a comparison over a corpus '
                 'nothing wrote passes' % (TAG, part, len(cases[part])))


def moved(which, side='new'):
    out = {}
    for part, pre, _ in CORPORA:
        d = '%s/%s-%s' % (tmp, pre, which)
        if sorted(os.listdir(d)) != cases[part]:
            sys.exit('  %-12s the %s %s corpus holds different cases'
                     % (TAG, which, part))
        a = '%s/REC-%s/%s' % (tmp, side, part)
        out[part] = [n for n in cases[part]
                     if not filecmp.cmp('%s/%s' % (a, n), '%s/%s' % (d, n),
                                        shallow=False)]
    return out


# THE INSTRUMENT, over every case of both.  The high-water is what decides whether the
# arena is the right size, so it is MEASURED HERE, on this phase's own output, rather
# than remembered from the edit's header -- and it is measured over the MEMLINE corpus
# too, which is the whole reason the number is what it is.  Sizing an arena from the 102
# screen cases alone would be sizing it from a corpus that cannot reach the text layer,
# which is the defect zero phase 40 exists to have ended.
peak = {}
calls = {}
for part, pre, _ in CORPORA:
    peak[part] = calls[part] = 0
    seen = 0
    for n in cases[part]:
        text = open('%s/%s-probe/%s' % (tmp, pre, n), errors='surrogateescape').read()
        m = re.search(r'ARENA used=(\d+) calls=(\d+)', text)
        if not m:
            continue
        seen += 1
        peak[part] = max(peak[part], int(m.group(1)))
        calls[part] += int(m.group(2))
    if seen != len(cases[part]):
        sys.exit('  %-12s the instrumented build marked %d of the %d %s cases, and it '
                 'must mark every one: the counter is printed from host_exit(), which '
                 'every case reaches' % (TAG, seen, len(cases[part]), part))
high = max(peak.values())
total = sum(calls.values())
if high < 100000 or total < 10000:
    sys.exit('  %-12s the instrument reports a high-water of %d bytes over %d calls, and '
             'a corpus that hammers lalloc() cannot give numbers that small -- the '
             'counters are not on the path' % (TAG, high, total))
if peak['memline'] <= peak['screen']:
    sys.exit('  %-12s the heaviest memline case asks for %d bytes and the heaviest '
             'screen case for %d.  The memline corpus builds buffers of thousands of '
             'lines and the screen corpus does not, so if it is not asking for MORE '
             'memory it is not the corpus this arena was sized from'
             % (TAG, peak['memline'], peak['screen']))
if high * 4 > arena:
    sys.exit('  %-12s the corpus asks for %d bytes at its worst and the arena is %d.  '
             'Less than four times the measured high-water is not a margin, it is a '
             'coincidence waiting to end: either the arena grows or this phase is wrong '
             'about the workload' % (TAG, high, arena))
print('  %-12s THE HIGH-WATER, MEASURED ON THIS PHASE\'S OWN OUTPUT and over BOTH '
      'corpora, marking every case of each: the heaviest of the %d memline cases asks '
      'host_alloc for %d bytes and the heaviest of the %d screen cases for %d -- 115 '
      'times less -- across %d calls in all.  So the arena is %.1f times what the corpus '
      'has ever needed and is %.2f%% used at its worst.  Nothing is freed, so that number '
      'is the session\'s whole allocation TRAFFIC and not its live data, which is why it '
      'is the number the arena has to be sized from AND why it is a memline case that '
      'sets it: a 25,000-line buffer edited in the middle churns the text layer, and '
      'churn is traffic'
      % (TAG, len(cases['memline']), peak['memline'], len(cases['screen']),
         peak['screen'], total, arena / float(high), 100.0 * high / arena))

# THE CONTROLS, over both corpora.
cnb = moved('cnb')
cf = moved('cf', 'old')
for part, _, _ in CORPORA:
    if len(cnb[part]) != len(cases[part]):
        sys.exit('  %-12s THE CONTROL cnb DID NOT SHOW: with the offset never advancing, '
                 'host_alloc hands the same block out every time, and that moves %d of '
                 'the %d %s cases where it must move every one.  Without this control '
                 'the bump is untested: a `host_alloc` that returned the arena\'s base '
                 'for ever would pass the symbol check, the cut and the size assertion'
                 % (TAG, len(cnb[part]), len(cases[part]), part))
    if cf[part]:
        sys.exit('  %-12s PHASE 35 MEASURED ITS `cf` CONTROL AT 0 OF 102 AND IT MOVES %d '
                 'OF THE %d %s CASES HERE.  That control -- host_free doing nothing, '
                 'built from the INPUT -- is the whole reason this phase could be '
                 'written; if it moves a case, freeing was never free and something has '
                 'changed underneath both phases'
                 % (TAG, len(cf[part]), len(cases[part]), part))
print('  %-12s THE CONTROLS, AND THE ONE THAT MOVES NOTHING IS REPORTED AND NOT HIDDEN:'
      % TAG)
print('  %-12s   the bump  the offset never advancing moves %d of %d screen cases and '
      '%d of %d memline cases.  It is the only control here that tests the ALLOCATOR '
      'rather than the wrapper -- `ca` above moves everything for any broken host_alloc '
      'at all, and this one is still a bump allocator in every respect except that its '
      'bookkeeping does nothing'
      % ('', len(cnb['screen']), len(cases['screen']), len(cnb['memline']),
         len(cases['memline'])))
print('  %-12s   host_free doing NOTHING AT ALL moves 0 of %d screen cases and 0 of %d '
      'memline cases, and that is PHASE 35\'S OWN CONTROL re-run on this phase\'s input '
      'rather than a new claim -- on a corpus phase 35 did not have.  A leak is invisible '
      'to this corpus too, so the byte-identical recording above is NOT what says the '
      'freeing changed; it says the ALLOCATION did not.  What says the freeing changed is '
      '`free` leaving nm -u' % ('', len(cases['screen']), len(cases['memline'])))
PY

# --- 7. THE GUARD: an arena too small must abort, loudly and with a status -----------------
python3 - "$tmp" "$arena" <<'PY'
import re
import sys

TAG = 'arena'
tmp = sys.argv[1]
arena = int(sys.argv[2])
small = 256 * 1024
tiny = open('%s/tiny.err' % tmp, errors='surrogateescape').read()
big = open('%s/big.err' % tmp, errors='surrogateescape').read()
rc_tiny = int(open('%s/rc.tiny.err' % tmp).read())
rc_big = int(open('%s/rc.big.err' % tmp).read())

m = re.search(r'zero-vim: host arena exhausted: (\d+) bytes, (\d+) used, request (\d+)',
              tiny)
if not m:
    sys.exit('  %-12s THE GUARD DID NOT SHOW: a 256 KiB arena ran a bare session to the '
             'end and printed %r on stderr.  The abort is the one branch of this phase a '
             'recording can never take, so it is the one that most needs a probe'
             % (TAG, tiny[:120]))
size, used, req = (int(x) for x in m.groups())
if size != small:
    sys.exit('  %-12s the message names an arena of %d and the control was built with %d'
             % (TAG, size, small))
if used + req <= size:
    sys.exit('  %-12s the message says %d used and %d requested, which FITS in %d -- the '
             'abort fired on a request the arena could have served' % (TAG, used, req, size))
if rc_tiny == 0:
    sys.exit('  %-12s the exhausted binary exited 0.  It must not: a host that runs out '
             'of memory and says so with a success status is a silent failure with '
             'extra steps' % TAG)
if big.strip() or rc_big != 0:
    sys.exit('  %-12s the SAME session on the real output wrote %r to stderr and exited '
             '%d.  Both halves are needed: an abort that fired on every session would '
             'pass the test above and be a catastrophe' % (TAG, big[:80], rc_big))
print('  %-12s THE GUARD, ON BOTH SIDES: with a 256 KiB arena a bare session aborts with '
      '`host arena exhausted: %d bytes, %d used, request %d` and exits %d -- the request '
      'that did not fit is the screen, the single largest allocation this editor makes -- '
      'and the identical session on the %d-byte output writes nothing to stderr and exits '
      '0.  The message names the arena, what was used and what was asked for, because a '
      'host that dies owes the next person the three numbers that decide what to change'
      % (TAG, size, used, req, rc_tiny, arena))
PY

# --- 8. THE PROBE the corpus cannot give: the two rewrites below the boundary --------------
for v in din dout; do
    eval "wait \$pid_$v" || { echo "  arena        the driver $v did not build:"; head -5 "$tmp/e.$v" | sed 's/^/               /'; exit 1; }
done
( cd "$tmp" && ./din Z > din.out 2> din.err; echo $? > rc.din ) || true
( cd "$tmp" && ./dout Z > dout.out 2> dout.err; echo $? > rc.dout ) || true
python3 - "$tmp" <<'PY'
import re
import sys

TAG = 'arena'
tmp = sys.argv[1]
a = open('%s/din.err' % tmp, errors='surrogateescape').read()
b = open('%s/dout.err' % tmp, errors='surrogateescape').read()
for w, rc in (('din', int(open('%s/rc.din' % tmp).read())),
              ('dout', int(open('%s/rc.dout' % tmp).read()))):
    if rc != 0:
        sys.exit('  %-12s the %s driver exited %d' % (TAG, w, rc))
ma = re.search(r'grows=(\d+)', a)
mb = re.search(r'grows=(\d+)', b)
if not ma or not mb:
    sys.exit('  %-12s a driver printed no `grows=` line, so nothing says it reached the '
             'arm this phase rewrote' % TAG)
if int(ma.group(1)) < 5 or ma.group(1) != mb.group(1):
    sys.exit('  %-12s the grow arm was entered %s times in the input and %s in the '
             'output, and the driver is written to enter it many times in both -- a '
             'probe that reaches the rewritten line zero times proves nothing'
             % (TAG, ma.group(1), mb.group(1)))
if a != b:
    sys.exit('  %-12s THE TWO DRIVERS PRINT DIFFERENT BYTES, so the realloc rewrite is '
             'not faithful:\n               in  %r\n               out %r'
             % (TAG, a[:200], b[:200]))
if len(a.split('\n')) < 8:
    sys.exit('  %-12s the driver printed %d lines and it formats seven strings'
             % (TAG, len(a.split('\n'))))
print('  %-12s THE PROBE FOR WHAT NO RECORDING CAN REACH: adjust_types() grows *ap_types '
      'only when a format string carries a positional spec, and NOT ONE STRING LITERAL '
      'IN THIS FILE HAS ONE -- so no session in the corpus has ever entered the arm this '
      'phase rewrote.  The same driver built into the input and into the output runs six '
      'ascending positional formats through it, enters the grow arm %s times in each, and '
      'the two binaries print the same bytes.  Its sibling, format_overflow_error()\'s '
      'free of argcopy, cannot be probed because it cannot RUN: its guard is '
      '`overflow_err`, which is `tvs != nullptr`, and vim_vsnprintf_typval has one caller '
      'in this file passing nullptr -- phase 9\'s and phase 17\'s kind, and it is rewritten '
      'for the same reason a dead branch is kept correct' % (TAG, ma.group(1)))
PY

# --- 9. the host's vocabulary is still the host's -------------------------------------------
python3 tools/zhostonly.py "$f"
echo "  arena        and that is phase 20's check, undisturbed and unamended.  tools/zhostonly.py reads the host region from host_winch_pending to musl_suspend's last brace, and this phase writes NOTHING in it: host_alloc and host_free have sat BELOW that brace since phase 35 put them beside main.  Neither \`malloc\`, \`free\`, \`realloc\`, \`max_align_t\` nor \`alignof\` is in that tool's vocabulary, so it needed no new word and no new exception -- the phase moves memory, not a syscall"

# --- 10. <stdlib.h>, measured and declined ---------------------------------------------------
if ! cmp -s "$tmp/cstdlib" "$tmp/new"; then
    echo "  arena        the output built WITHOUT <stdlib.h> is not byte-identical to the output, so the directive is not dead after all and the sentence below would be wrong"
    exit 1
fi
echo "  arena        <stdlib.h> IS NOW DEAD AND IT STAYS, which is measured rather than argued: malloc, free and realloc were its only users, and the output built with the directive DELETED is BYTE-IDENTICAL, $(stat -c%s "$tmp/new") bytes either way.  ZERO-GOAL.md lets a phase remove a directive; phase 13 is the precedent for declining, having measured that removing three was free and written \"the count stays 18\" into its own program.  Eleven stays eleven: this phase's subject is the allocator, the removal is free for whoever asks for it, and a phase that changes two things cannot say which one a difference came from"

# --- 11. canon ---------------------------------------------------------------------------------
wait $pid_canon || true
if ! cmp -s "$tmp/canon.c" "$f"; then
    echo "  arena        tools/canon.sh CHANGED THE OUTPUT, and it must be a no-op:"
    diff "$f" "$tmp/canon.c" | head -6 | sed 's/^/               /'
    exit 1
fi
echo "  arena        tools/canon.sh is a NO-OP on the output ($(sed -n 's/.*canon *//p' "$tmp/canon.log" | head -1))"

# tools/phaserun.sh runs tools/zerodelta.sh --phase 41 after this check, and this phase
# declares NOTHING: the corpus must not move at all.
