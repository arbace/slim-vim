#!/bin/sh
# Zero phase 29, the check -- THE CASE TABLES BECOME ONE, AND IT IS THE UNION.
# See pipes/zero29-edit.sh, and ZERO-GOAL.md.
#
# Usage: pipes/zero29-check.sh <work-dir> <state-dir>    (run from the repository root)
#
# Runs after pipes/zero29-edit.sh and the sweep tools/phaserun.sh runs between them,
# and reads nothing from the edit's shell -- only the work tree and the state
# directory.  What the edit left there is `old.c`, the source this phase was HANDED,
# and `old`, that source built with the boundary's own flags.
#
# WHAT IS CLAIMED, in five parts:
#
#   THE UNION     THE STRONGEST THING THIS CHECK SAYS, and it is not a row count.  The
#                 produced `toUpper[]`/`toLower[]` are expanded over all 1,114,112
#                 codepoints and required to be EXACTLY the union of the two tables the
#                 phase was handed, in all three directions: they agree with the INPUT's
#                 vim table wherever it mapped, with the INPUT's musl table wherever IT
#                 mapped, and they map nothing that neither did.  A row count cannot say
#                 any of that, and a merge that dropped Vithkuqi would pass one.
#                 Perturbing one produced row must break it, so it is proven able to
#                 fail.
#   THE AUTHORITY the musl half is re-derived from THIS MACHINE'S libc through ctypes
#                 (tools/muslcase.py's `libc()`), not read out of the table the phase
#                 deleted.  So the check does not trust the bytes phase 15 shipped
#                 either.
#   THE RULE      nothing this phase changes on the DEFAULT arm may go un-probed, and
#                 nothing it stops mapping may go un-probed either.  Both sets are
#                 COMPUTED from the two input tables -- the first is what the union adds
#                 to vim's own table, the second is what it takes away -- and every
#                 member of both must appear in the probe text.  That stays true of an
#                 input this check has never seen, where the number 1 would not.
#   THE SOURCE    musl_toUpper and musl_toLower at 0 mentions with the input at 3 each,
#                 so the assertion is one that can fail; the two wrappers still there at
#                 4 mentions and reading vim's tables; utf_convert at the same six
#                 calls; the boundary still the first of eleven #includes, and the cut
#                 compiling silently with the SAME thirteen names, read at run time.
#   SYMBOLS       `nm -u` is THE SAME SET, as a `comm` empty in both directions, and
#                 `main` is still the only external symbol.  Changing data frees no libc
#                 symbol and needs none; the eleven phase 15 freed stay freed.
#
# THE DELTA RUNS ON BOTH ARMS, and getting that wrong is the easiest mistake here.
# `utf_toupper()`/`utf_tolower()` read musl's table whenever `internal` is NOT in
# `'casemap'`, and that arm now reads the union -- so the 96 upper and 96 lower
# codepoints vim knows and musl did not ARRIVE there, and the sharp s KEEPS the mapping
# it had.  The DEFAULT arm reads vim's own table, and the one row the union adds arrives
# there: `:s/.*/\U&/` on `ß` draws `ẞ` where it drew `ß`.  Six probe sessions move and
# six do not.
#
# TWO TRAPS THE PROBES HAD TO GET RIGHT, both measured rather than reasoned.
# `gU`, `g~` and `~` CANNOT show the sharp s at all: `swapchar()` hard-codes
# U+00DF -> U+1E9E before it consults any table, so `gUU` draws `ẞ` under every
# `'casemap'` on both binaries and a probe built on it would have reported nothing.  The
# row is reachable only through `\u`/`\U` in a substitution, which goes `do_upper` ->
# `vim_toupper` -> `utf_toupper` and hits the table directly -- and THAT IS ALSO THE
# ARGUMENT FOR THE ROW: today `swapchar()` and `toUpper[]` give different answers for
# the same character, and after this phase they agree.  And the chartab the 892 startup
# calls of `towupper`/`towlower` build does NOT move, although those calls run with
# `cmp_flags` still 0 and therefore take the non-internal arm: the union equals musl's
# table at every one of 128..255, the two having disagreed below U+0100 at U+00DF alone
# and the union taking musl's answer there.
#
# AND THE RECORDED CORPUS CANNOT SEE ANY OF IT, so `pipes/zero.delta` gains no line.
# All 102 screen cases seed themselves by typing ASCII and none of them touches
# `'casemap'`; two full recordings are byte-identical.  That is zero phase 2's
# situation -- a blind harness rather than a static phase -- and a phase in it owes
# probes of its own.  These are they.
set -eu

work=${1:?usage: zero29-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero29-check.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"
before_lines=$(cat "$state/input-lines")

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")

# The probe text, in ONE place: the check's Python reads it to assert that every
# codepoint this phase changes on the default arm, and every one it stops mapping, is
# probed -- and the probe block below types it.
PROBE_TEXT='ⓐ ⱟ 𐖗 𐵰 ß'
PROBE_UP='Ⓐ Ⱟ 𐕰 𐵐 ẞ'

# --- 1. the union, the authority, the rule and the source ----------------------------
python3 - "$f" "$state/old.c" "$tmp" "$PROBE_TEXT$PROBE_UP" <<'PY'
import re
import sys

sys.path.insert(0, 'tools')
import create_cmdidxs
import muslcase                      # tools/muslcase.py -- for libc() and nothing else

TAG = 'casemap'
new = open(sys.argv[1], errors='surrogateescape').read()
old = open(sys.argv[2], errors='surrogateescape').read()
out = sys.argv[3]
probed = set(ord(c) for c in sys.argv[4])
fail = []


def words(text, name):
    return len(re.findall(r'\b%s\b' % name, text))


def calls(text, name):
    return len(re.findall(r'(?<![\w])%s\s*\(' % name, text))


ROW = re.compile(r'^        \{(0x[0-9a-f]+),(0x[0-9a-f]+),(-?\d+),(-?\d+)\},?$', re.M)


def rows_of(text, name):
    m = re.search(r'^static convertStruct %s\[\] =\n\{\n(.*?)\n\};\n' % name,
                  text, re.M | re.S)
    if not m:
        return None
    return [tuple(int(x, 0) for x in r) for r in ROW.findall(m.group(1))]


def expand(rows):
    """{codepoint: target}, exactly as utf_convert() reads the row."""
    o = {}
    for lo, hi, step, off in rows:
        if step < 0:
            o[lo] = lo + off
        else:
            for c in range(lo, hi + 1, step):
                o[c] = c + off
    return o


tables = {}
for text, tag in ((old, 'old'), (new, 'new')):
    for name in ('toUpper', 'toLower', 'musl_toUpper', 'musl_toLower'):
        tables[tag, name] = rows_of(text, name)
for name in ('toUpper', 'toLower'):
    if tables['old', name] is None or tables['new', name] is None:
        fail.append('%s[] is missing from one of the two sources' % name)
    if tables['old', 'musl_' + name] is None:
        fail.append('musl_%s[] was not in the input, so this phase merges nothing and '
                    'the check below proves nothing' % name)
    if tables['new', 'musl_' + name] is not None:
        fail.append('musl_%s[] survives in the output' % name)

if not fail:
    up, low = muslcase.libc()
    summary = []
    for name, libcf in (('toUpper', up), ('toLower', low)):
        ev = expand(tables['old', name])
        em = expand(tables['old', 'musl_' + name])
        en = expand(tables['new', name])
        union = dict(ev)
        union.update(em)
        # (a) everything the INPUT's vim table mapped, mapped the same way.  This is
        #     the half a careless merge loses silently -- all of Vithkuqi and Garay.
        lost_vim = sorted(c for c in ev if en.get(c, c) != ev[c])
        # (b) everything the INPUT's musl table mapped, mapped the same way.
        lost_musl = sorted(c for c in em if en.get(c, c) != em[c])
        # (c) nothing neither had.
        invented = sorted(c for c in en if c not in union or en[c] != union[c])
        for what, s in (("is no longer mapped as the input's %s[] mapped it" % name, lost_vim),
                        ("is no longer mapped as the input's musl_%s[] mapped it" % name, lost_musl),
                        ('is mapped by neither table the phase was handed', invented)):
            if s:
                fail.append('%d codepoints, U+%04X among them, %s -- the output is not '
                            'the union' % (len(s), s[0], what))
        # (d) THE AUTHORITY.  The musl half again, from this machine's libc rather than
        #     from the table the phase deleted.
        bad = []
        for c in range(muslcase.PLANES):
            want = libcf(c)
            if want != c and en.get(c, c) != want:
                bad.append(c)
                if len(bad) > 4:
                    break
        if bad:
            fail.append('%s[] disagrees with THIS MACHINE\'S libc at U+%04X (the table '
                        'says %04X, libc says %04X) and %d more'
                        % (name, bad[0], en.get(bad[0], bad[0]), libcf(bad[0]),
                           len(bad) - 1))

        # (e) THE RULE, and it is a rule rather than a number.  What this phase changes
        #     on the DEFAULT arm is what the union adds to vim's own table; what it
        #     takes away is what the union drops from musl's.  EVERY member of both must
        #     be in the probe text, so a phase handed a different input cannot change
        #     something no probe looks at.
        default_changes = sorted(c for c in en if en[c] != ev.get(c, c))
        stops = sorted(c for c in em if c not in en)
        unprobed = [c for c in default_changes + stops if c not in probed]
        if unprobed:
            fail.append('%d codepoint(s) this phase changes on the default arm or stops '
                        'mapping are not in the probe text, U+%04X among them -- nothing '
                        'it moves there may go un-probed'
                        % (len(unprobed), unprobed[0]))
        # and the non-internal arm, where 96 arrive and no probe text could hold them
        # all: at least one must be looked at.
        arm_changes = sorted(c for c in set(en) | set(em) if en.get(c, c) != em.get(c, c))
        if arm_changes and not (set(arm_changes) & probed):
            fail.append('not one of the %d codepoints that move on the non-internal arm '
                        'is in the probe text' % len(arm_changes))
        if not arm_changes:
            fail.append('%s[] and musl_%s[] agreed everywhere, so there was no union to '
                        'take and this phase proves nothing' % (name, name))
        summary.append((name, len(tables['old', name]), len(tables['new', name]),
                        len(ev), len(en), len(arm_changes), len(default_changes),
                        ' '.join('U+%04X' % c for c in default_changes) or 'none',
                        len(stops)))

    # PROVEN ABLE TO FAIL: perturbing one row of the produced table must break (a), (b)
    # or (d).  It is done here, on text, so it costs nothing.
    for name in ('toUpper', 'toLower'):
        rows = tables['new', name]
        broken = [rows[0][:3] + (rows[0][3] + 1,)] + rows[1:]
        eb = expand(broken)
        ev = expand(tables['old', name])
        if not [c for c in ev if eb.get(c, c) != ev[c]]:
            fail.append('perturbing the first row of the produced %s[] changes no '
                        'codepoint, so the union check cannot fail' % name)

if fail:
    for line in fail:
        print('  %-12s %s' % (TAG, line))
    sys.exit(1)
for name, r0, r1, ncp, nn, arm, ndef, defs, nstop in summary:
    print('  %-12s %s[] %d rows -> %d, %d codepoints -> %d: it maps everything the '
          'input\'s %s[] mapped AND everything the input\'s musl_%s[] mapped AND NOTHING '
          'NEITHER HAD, over all 1,114,112 codepoints, with the musl half re-derived '
          'from THIS MACHINE\'S libc through ctypes rather than from the table this '
          'phase deleted.  %d codepoints move on the NON-INTERNAL arm and %d on the '
          'DEFAULT one (%s), %d stop mapping anywhere -- and every one of the last two '
          'kinds is in the probe text'
          % (TAG, name, r0, r1, ncp, nn, name, name, arm, ndef, defs, nstop))

# --- the source, as rules -----------------------------------------------------------
src = []
for name in ('musl_toUpper', 'musl_toLower'):
    if words(new, name):
        src.append('%s is still named %d times' % (name, words(new, name)))
    if words(old, name) != 3:
        src.append('the input names %s %d times, not the 3 this phase was written '
                   'against -- its definition and the two in its wrapper\'s '
                   'utf_convert call' % (name, words(old, name)))
for name in ('musl_towupper', 'musl_towlower'):
    if words(new, name) != words(old, name) or words(new, name) != 4:
        src.append('%s has %d mentions and the input had %d; both must be 4 -- its '
                   'prototype, its definition, the live call in utf_to*() and the dead '
                   'one in vim_to*().  THE TWO WRAPPERS STAY'
                   % (name, words(new, name), words(old, name)))
for name in ('toUpper', 'toLower'):
    if words(new, name) != words(old, name) + 2:
        src.append('%s is named %d times and the input named it %d; the repointed '
                   'wrapper adds exactly two' % (name, words(new, name), words(old, name)))
if calls(new, 'utf_convert') != calls(old, 'utf_convert'):
    src.append('utf_convert is called %d times and the input called it %d -- this '
               'phase moves no call, it changes what two of them read'
               % (calls(new, 'utf_convert'), calls(old, 'utf_convert')))
# The two things this phase does NOT touch, and both are load-bearing for its argument.
# swapchar()'s hard-coded sharp s is why gU cannot show the row -- and, now that the row
# is in, it is what the table has been made to AGREE with.  utf_islower()'s
# `|| a == 0xdf` becomes redundant here and is deliberately left: removing it is a
# different idea.
for text, tag in ((new, 'output'), (old, 'input')):
    if 'ins_char(0x1E9E);' not in text:
        src.append("swapchar()'s hard-coded sharp s is not in the %s, and it is both why "
                   "gU cannot show this phase's row and what the row makes the table "
                   "agree with" % tag)
    if '(utf_toupper(a) != a) || a == 0xdf' not in text:
        src.append("utf_islower()'s `|| a == 0xdf` is not in the %s" % tag)
L = new.split('\n')
d = [i for i, l in enumerate(L) if l.lstrip().startswith('#')]
if len(d) != 11 or any(not re.match(r'^ *# *include ', L[i]) for i in d):
    src.append('the directives are not the eleven #includes phase 21 left')
elif d != list(range(d[0], d[0] + 11)):
    src.append('the eleven #includes are no longer eleven consecutive lines')


# The two tables this phase must not touch, stated against the INPUT rather than as
# remembered numbers: a later phase that removes a command or an option row would
# otherwise fail here for a reason that is not this phase's.
def rowcount(text):
    i = text.find('static struct vimoption options[]')
    j = text.index('\n};', i)
    return len(re.findall(r'^[ \t]*\{"([a-z]+)",', text[i:j], re.M))


cmds = len(re.findall(r'^    \[CMD_\w+\] = \{.*$', new, re.M))
was = len(re.findall(r'^    \[CMD_\w+\] = \{.*$', old, re.M))
got = create_cmdidxs.names(sys.argv[1])
if cmds != was or len(got) != was:
    src.append('cmdnames[] has %d rows and names() reads %d; the input had %d and this '
               'phase touches no row' % (cmds, len(got), was))
if rowcount(new) != rowcount(old):
    src.append('options[] has %d rows and the input had %d; this phase retires no option'
               % (rowcount(new), rowcount(old)))
if not re.search(r'\{"casemap"', new):
    src.append("the 'casemap' option row is gone, and retiring it is not this phase's")
if src:
    for line in src:
        print('  %-12s %s' % (TAG, line))
    sys.exit(1)
print('  %-12s musl_toUpper and musl_toLower at 0 mentions where the input had 3 each, '
      'so the assertion is one that can fail; musl_towupper and musl_towlower STILL AT '
      '4 each and now reading vim\'s tables; utf_convert at the same %d calls; '
      'swapchar()\'s hard-coded sharp s present in BOTH sources -- it is why gU cannot '
      'show the row, and it is what the row makes the table agree with -- and '
      'utf_islower()\'s `|| a == 0xdf`, now redundant, deliberately left; eleven '
      'consecutive #includes and nothing else; cmdnames[] %d and options[] %d, both the '
      'input\'s, with \'casemap\' still among them'
      % (TAG, calls(new, 'utf_convert'), cmds, rowcount(new)))

# The two controls the shell builds below, computed from the two sources rather than
# spelled out.
#   vimonly  the output with musl's contribution taken back out -- the shape that
#            deletes musl's tables and adds no row.  The DEFAULT-arm probe must then
#            record what the INPUT recorded, and the sharp s must go from the
#            non-internal arm: that is the loss the user declined, demonstrated.
#   vimless  vim's toUpper[] replaced by the input's musl_toUpper[].  The MUST-NOT-DIFFER
#            probes for the internal arm must then move, which is what says the
#            ninety-six are really being looked at.
def retable(text, name, rows):
    head = re.search(r'^static convertStruct %s\[\] =\n\{\n.*?\n\};\n' % name,
                     text, re.M | re.S)
    body = ',\n'.join('        {0x%x,0x%x,%d,%d}' % r for r in rows)
    return text.replace(head.group(0),
                        'static convertStruct %s[] =\n{\n%s\n};\n' % (name, body))


vimonly = new
for name in ('toUpper', 'toLower'):
    ev = expand(tables['old', name])
    em = expand(tables['old', 'musl_' + name])
    keep = [r for r in tables['new', name]
            if not (r[0] == r[1] and r[0] in em and r[0] not in ev)]
    if len(keep) != len(tables['old', name]):
        sys.exit('  %-12s taking musl\'s contribution back out of %s[] leaves %d rows '
                 'where the input had %d, so the `vimonly` control is not the input\'s '
                 'table' % (TAG, name, len(keep), len(tables['old', name])))
    vimonly = retable(vimonly, name, keep)
if vimonly == new:
    sys.exit('  %-12s the `vimonly` control is the output unchanged, so the union added '
             'nothing and the default-arm probe proves nothing' % TAG)
open(out + '/vimonly.c', 'w', errors='surrogateescape').write(vimonly)
open(out + '/vimless.c', 'w', errors='surrogateescape').write(
    retable(new, 'toUpper', tables['old', 'musl_toUpper']))
print('  %-12s two controls written: `vimonly`, the output with musl\'s contribution '
      'taken back out -- the union NOT taken -- and `vimless`, the output with toUpper[] '
      'replaced by the input\'s musl_toUpper[] -- the merge done the careless way round.  '
      'One for each half of the union, because "it kept both" is the claim a careless '
      'phase breaks in silence' % TAG)
PY

# --- 2. the compile, the linkage and the libc surface -------------------------------
gcc -c -O0 -fno-stack-protector -o "$tmp/old.o" "$state/old.c"
gcc -c -O0 -fno-stack-protector -o "$tmp/new.o" "$f"
nm -u "$tmp/old.o" | awk '{print $2}' | sort > "$tmp/u.old"
nm -u "$tmp/new.o" | awk '{print $2}' | sort > "$tmp/u.new"
gone=$(comm -23 "$tmp/u.old" "$tmp/u.new" | tr '\n' ' ')
came=$(comm -13 "$tmp/u.old" "$tmp/u.new" | tr '\n' ' ')
if [ -n "$gone$came" ]; then
    echo "  casemap      \`nm -u\` moved: gone [$gone] arrived [$came].  CHANGING DATA FREES NO LIBC SYMBOL AND NEEDS NONE -- the eleven phase 15 freed were freed by the two wrappers, which this phase keeps"
    exit 1
fi
ext=$(nm --extern-only --defined-only "$tmp/new.o" | awk '{print $3}' | sort | tr '\n' ' ')
if [ "$ext" != "main " ]; then
    echo "  casemap      the output defines external symbols other than main: $ext"
    exit 1
fi
for absent in towupper towlower toupper tolower open stat fopen; do
    if grep -qx "$absent" "$tmp/u.new"; then
        echo "  casemap      $absent is undefined again, and phase 15 freed it"; exit 1
    fi
done
echo "  casemap      \`nm -u\` is THE SAME SET, $(wc -l <"$tmp/u.new") names, as a \`comm\` empty in BOTH directions, and \`main\` is still the only external symbol.  towupper and towlower stay freed: what this phase changes is DATA, and the two wrappers that replaced the calls are still there"

# --- 3. the enumerators -------------------------------------------------------------
tools/enumvals.sh "$state/old.c" "$tmp/ev.old" &
pid_ev=$!
tools/enumvals.sh "$f" "$tmp/ev.new"
wait $pid_ev
python3 - "$tmp/ev.old" "$tmp/ev.new" <<'PY'
import sys
TAG = 'casemap'
o = dict(l.rsplit('=', 1) for l in open(sys.argv[1]).read().splitlines())
n = dict(l.rsplit('=', 1) for l in open(sys.argv[2]).read().splitlines())
gone, came = sorted(set(o) - set(n)), sorted(set(n) - set(o))
moved = sorted(k for k in set(o) & set(n) if o[k] != n[k])
if gone or came or moved:
    for what, s in (('went', gone), ('arrived', came), ('renumbered', moved)):
        if s:
            print('  %-12s enumerators %s: %s' % (TAG, what, ' '.join(s)))
    sys.exit(1)
print('  %-12s enumerators %d -> %d: not one went, arrived or renumbered -- this phase '
      'edits two array initialisers and touches no enum' % (TAG, len(o), len(n)))
PY

# --- 4. the structural tools, and the boundary as a compile --------------------------
tools/st.sh nvidx "$f"
tools/st.sh orphanopts "$f"
for src in "$f" "$state/old.c"; do
    awk '/^ *# *include / { exit } { a[NR] = $0; if (NF) last = NR } \
         END { for (i = 1; i <= last; i++) print a[i] }' "$src" > "$tmp/cut.c"
    if grep -q '^ *#' "$tmp/cut.c"; then
        echo "  casemap      the cut of $src holds a directive"; exit 1
    fi
    gcc -O0 -fno-stack-protector -Wall -Wextra -Wno-unused-parameter \
        -fsyntax-only "$tmp/cut.c" 2>"$tmp/w.txt" || true
    if grep -q ': error:' "$tmp/w.txt"; then
        echo "  casemap      the cut of $src does not compile on its own:"
        grep ': error:' "$tmp/w.txt" | head -3 | sed 's/^/               /'
        exit 1
    fi
    if grep ': warning: ' "$tmp/w.txt" | grep -qv 'used but never defined'; then
        echo "  casemap      the cut of $src has a warning that is not a boundary name:"
        grep ': warning: ' "$tmp/w.txt" | grep -v 'used but never defined' | head -3 \
            | sed 's/^/               /'
        exit 1
    fi
    grep -o "'[A-Za-z_][A-Za-z0-9_]*' used but never defined" "$tmp/w.txt" \
        | sort -u > "$tmp/boundary.$(basename "$src")"
    echo "$(grep -c '' "$tmp/cut.c")" > "$tmp/cutlines.$(basename "$src")"
done
if ! cmp -s "$tmp/boundary.zero-vim.c" "$tmp/boundary.old.c"; then
    echo "  casemap      the core -> host interface moved:"
    diff "$tmp/boundary.old.c" "$tmp/boundary.zero-vim.c" | head -6 | sed 's/^/               /'
    exit 1
fi
echo "  casemap      cut at the first #include, $(cat "$tmp/cutlines.old.c") lines -> $(cat "$tmp/cutlines.zero-vim.c"), 0 directives, 0 errors and no warning that is not a boundary name -- and THE SAME $(grep -c '' "$tmp/boundary.zero-vim.c") NAMES either side, read at run time, so the core -> host interface phase 27 drew did not move"

# --- 5. the binary, and the two controls --------------------------------------------
make -C "$work" clean >/dev/null 2>&1 || true
if ! make -C "$work" >/dev/null 2>&1; then
    echo "  build        FAILED -- rerun by hand: make -C $work"
    exit 1
fi
bin="$work/zero-vim"
if ! readelf -h "$bin" | grep -q 'Type:.*EXEC'; then
    echo "  casemap      the binary is no longer EXEC"; exit 1
fi
if readelf -l "$bin" | grep -q INTERP; then
    echo "  casemap      the binary grew an INTERP"; exit 1
fi
if readelf -d "$bin" 2>/dev/null | grep -q 'Dynamic section'; then
    echo "  casemap      the binary grew a dynamic section"; exit 1
fi
# shellcheck disable=SC2086
( gcc $cflags $ldflags -o "$tmp/vimonly" "$tmp/vimonly.c" ) &
pid_o=$!
# shellcheck disable=SC2086
( gcc $cflags $ldflags -o "$tmp/vimless" "$tmp/vimless.c" ) &
pid_v=$!
wait $pid_o || { echo "  casemap      the vimonly control did not build"; exit 1; }
wait $pid_v || { echo "  casemap      the vimless control did not build"; exit 1; }
echo "  build        ok, $before_lines -> $(grep -c '' "$f") lines, $(stat -c%s "$bin") bytes against the input's $(stat -c%s "$state/old") -- and it SHRINKS, because two tables of 16-byte rows leave and one row arrives"

# --- 6. twelve probes on both binaries, and the two controls -------------------------
python3 - "$state/old" "$bin" "$tmp/vimonly" "$tmp/vimless" "$PROBE_TEXT" "$PROBE_UP" <<'PY'
import concurrent.futures
import hashlib
import os
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, 'tools')
import zrec
import zscreen
import zstream

TAG = 'casemap'
ESC, CR = b'\x1b', b'\r'
QUIT = ESC + b':q!' + CR
old_bin, new_bin, vimonly_bin, vimless_bin = (os.path.abspath(a) for a in sys.argv[1:5])

# THE PROBE TEXT IS THE SHELL'S, so that part 1 can assert against the SAME string that
# every codepoint this phase changes on the default arm is probed.
#   U+24D0 CIRCLED LATIN SMALL LETTER A, U+2C5F GLAGOLITIC SMALL LETTER CAUDATE CHRIVI,
#   U+10597 VITHKUQI SMALL LETTER BE and U+10D70 GARAY SMALL LETTER CA are four of the
#   ninety-six VIM knows and musl did not -- Vithkuqi is Unicode 14 and Garay is Unicode
#   16, and musl's casemap.h predates both -- and they ARRIVE on the non-internal arm.
#   U+00DF LATIN SMALL LETTER SHARP S is the ONE musl knew and vim did not, and it
#   arrives on the DEFAULT one.  A probe text with only the first group would miss the
#   row entirely, and one with only the sharp s would pass a phase that lost Vithkuqi.
LOW = sys.argv[5].encode()
UP = sys.argv[6].encode()
SS = 'ß'.encode()


def record(binary, args, keys, timeout=10):
    vim = zstream.stage(binary)     # argv[0], and the copy race: tools/zstream.py
    home = tempfile.mkdtemp(prefix='zero29-home-')
    env = dict(os.environ)
    env.update(TERM='xterm', HOME=home, VIM=os.path.join(home, 'novim'),
               VIMRUNTIME=os.path.join(home, 'novim'),
               XDG_CONFIG_HOME=os.path.join(home, 'xdg'))
    for k in ('LINES', 'COLUMNS', 'VIMINIT', 'EXINIT', 'MYVIMRC'):
        env.pop(k, None)
    d = tempfile.mkdtemp(prefix='zero29-run-')
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
    return zrec.scrub(text)


def typed(seed, *keys):
    return (['+set paste'],
            [b'i' + seed + ESC, b':set nopaste' + CR] + list(keys) + [QUIT])


def line(rec):
    """The first line of the last screen the editor drew -- the edited text."""
    snaps = [b for h, b in zrec.split(rec) if h.startswith('snap')]
    return snaps[-1].split('\n')[0].strip() if snaps else '<no screen>'


SUBST = br':s/.*/\U&/' + CR

# name, session, must-differ, what the NEW record must SHOW.  A record that is equal
# because both binaries did nothing is two failures agreeing, so every row says what it
# expects to see; a record that differs for a reason other than the phase's is caught by
# the same string.
PROBES = [
    # THE FOUR THAT MOVE ON THE NON-INTERNAL ARM -- 'casemap' WITHOUT `internal`, which
    # read musl's table and now reads the union.  The ninety-six arrive.
    ('empty_gUU', typed(LOW, b':set casemap=' + CR, b'gUU'), True, 'Ⓐ Ⱟ 𐕰 𐵐 ẞ'),
    ('empty_guu', typed(UP, b':set casemap=' + CR, b'guu'), True, 'ⓐ ⱟ 𐖗 𐵰 ß'),
    ('keepascii_gUU', typed(LOW, b':set casemap=keepascii' + CR, b'gUU'), True,
     'Ⓐ Ⱟ 𐕰 𐵐 ẞ'),
    ('empty_subst_U', typed(LOW, b':set casemap=' + CR, SUBST), True, 'Ⓐ Ⱟ 𐕰 𐵐 ẞ'),
    # AND THE TWO THAT MOVE ON THE DEFAULT ARM, which is the one row.  `gU` cannot show
    # it -- swapchar() hard-codes U+00DF before any table is read -- so it is reached
    # through `\U` in a substitution.
    ('default_subst_U', typed(LOW, SUBST), True, 'Ⓐ Ⱟ 𐕰 𐵐 ẞ'),
    ('default_subst_ss', typed(SS, SUBST), True, 'ẞ'),
    # THE SIX THAT MUST NOT MOVE.  The ninety-six PROVING THEY DID NOT REGRESS on the
    # arm that always had them, the sharp s KEEPING the mapping it had on the arm that
    # always had it, swapchar()'s hard-coded answer, and the chartab.
    ('default_gUU', typed(LOW, b'gUU'), False, 'Ⓐ Ⱟ 𐕰 𐵐 ẞ'),
    ('default_guu', typed(UP, b'guu'), False, 'ⓐ ⱟ 𐖗 𐵰 ß'),
    ('internal_gUU', typed(LOW, b':set casemap=internal' + CR, b'gUU'), False,
     'Ⓐ Ⱟ 𐕰 𐵐 ẞ'),
    ('empty_subst_ss', typed(SS, b':set casemap=' + CR, SUBST), False, 'ẞ'),
    ('tilde_ss', typed(SS, b'0', b'g~g~'), False, 'ẞ'),
    # the chartab the 892 startup calls of towupper/towlower build: they run with
    # cmp_flags still 0 and so take the NON-INTERNAL arm, and they still do not move,
    # because the union equals musl's table at every one of 128..255.
    ('isk_at', typed('café naïve'.encode(), b':set isk=@' + CR, b'0', b'dw'), False,
     'naïve'),
]

#   vimonly  the union NOT taken -- musl's contribution removed again.  The default-arm
#            probe then records what the INPUT recorded, and the sharp s goes from the
#            non-internal arm too: that is what the row buys, demonstrated.
#   vimless  vim's toUpper[] replaced by the input's musl_toUpper[]: default_gUU then
#            loses the ninety-six, which is the regression no record could report.
CONTROLS = [('vimonly', vimonly_bin, 'default_subst_ss'),
            ('vimonly', vimonly_bin, 'empty_subst_ss'),
            ('vimless', vimless_bin, 'default_gUU')]


def one(job):
    kind, name, binary, session = job
    return kind, name, binary, record(binary, *session)


SESSION = dict((n, s) for n, s, _, _ in PROBES)
jobs = [('probe', n, b, s) for n, s, _, _ in PROBES for b in (old_bin, new_bin)]
jobs += [('control', probe, binary, SESSION[probe]) for _, binary, probe in CONTROLS]
with concurrent.futures.ThreadPoolExecutor(max_workers=len(jobs)) as ex:
    done = list(ex.map(one, jobs))
rec = {(name, binary): text for kind, name, binary, text in done}

fail, moved, still = [], [], []
for name, session, must_differ, want in PROBES:
    o, n = rec[name, old_bin], rec[name, new_bin]
    if want not in n:
        fail.append('%s: the new binary shows %r and not %r, so the comparison below '
                    'is two failures agreeing' % (name, line(n), want))
    if must_differ and o == n:
        fail.append('%s DID NOT MOVE, and this phase claims it does: %r'
                    % (name, line(n)))
    if not must_differ and o != n:
        fail.append('%s MOVED, and this phase claims it does not: %r -> %r'
                    % (name, line(o), line(n)))
    if must_differ:
        moved.append('%s %r -> %r' % (name, line(o), line(n)))
    else:
        still.append('%s == %r' % (name, line(n)))

for cname, binary, probe in CONTROLS:
    c = rec[probe, binary]
    if c == rec[probe, new_bin]:
        fail.append('the `%s` control records the same %s as this phase\'s own binary, '
                    'so that probe is not being tested' % (cname, probe))
    if cname == 'vimonly' and probe == 'default_subst_ss' and c != rec[probe, old_bin]:
        fail.append('the `vimonly` control does not record %s as the INPUT did, so what '
                    'it removes is not exactly what the union adds' % probe)
if 'Ⓐ' in line(rec['default_gUU', vimless_bin]):
    fail.append('the `vimless` control still uppercases the circled letter, so it is '
                'not the careless merge it is meant to be: %r'
                % line(rec['default_gUU', vimless_bin]))

if fail:
    for l in fail:
        print('  %-12s %s' % (TAG, l))
    sys.exit(1)
print('  %-12s SIX PROBES MOVE, and they are the union arriving on BOTH arms -- four on '
      '\'casemap\' without `internal`, which read musl\'s table and now read the union, '
      'and two on the DEFAULT one, which is the single row: %s'
      % (TAG, '; '.join(moved)))
print('  %-12s SIX DO NOT: the ninety-six PROVING THEY DID NOT REGRESS on the arm that '
      'always had them, the sharp s KEEPING what it had on the arm that always had it, '
      'swapchar()\'s hard-coded answer, and the chartab the 892 startup calls build -- %s'
      % (TAG, '; '.join(still)))
print('  %-12s AND THE TWO CONTROLS FAIL AS THEY MUST.  With musl\'s one row taken back '
      'out -- the union NOT taken -- default_subst_ss records exactly what the INPUT '
      'recorded and empty_subst_ss draws %r where this phase draws %r, which is what the '
      'row buys.  With toUpper[] replaced by the input\'s musl_toUpper[] -- the merge '
      'done the careless way round -- default_gUU draws %r and the circled letter is '
      'gone, which is the regression no record could report'
      % (TAG, line(rec['empty_subst_ss', vimonly_bin]),
         line(rec['empty_subst_ss', new_bin]),
         line(rec['default_gUU', vimless_bin])))
PY

# --- 7. the recording did not move --------------------------------------------------
tools/zrecord.sh "$state/old" "$state/old.c" "$tmp/REC.old" >/dev/null 2>&1 &
pid_ro=$!
tools/zrecord.sh "$bin" "$f" "$tmp/REC.new" >/dev/null 2>&1 &
pid_rn=$!
wait $pid_ro
wait $pid_rn
if ! diff -rq "$tmp/REC.old" "$tmp/REC.new" >"$tmp/rec.diff" 2>&1; then
    echo "  casemap      the declared delta is NOTHING AT ALL and the two recordings differ:"
    sed -n '1,12p' "$tmp/rec.diff"
    exit 1
fi
echo "  casemap      the declared delta is NOTHING AT ALL and TWO FULL RECORDINGS ARE BYTE-IDENTICAL -- and here that is the HARNESS and not the phase.  The six probes above prove both arms of 'casemap' moved; the corpus cannot see it, because all 102 screen cases seed themselves by typing ASCII and none of them touches 'casemap'"

# tools/phaserun.sh runs tools/zerodelta.sh --phase 29 after this check, and that is the
# second opinion on the same claim -- against .reference/zero-baselines rather than
# against the binary this phase was handed.
