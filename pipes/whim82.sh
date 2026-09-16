#!/bin/sh
# Whim phase 82 -- the system headers nothing needs, and every comment.
# See WHIM-GOAL.md.
#
# Usage: pipes/whim82.sh <work-dir>      (run from the repository root)
#
# whim-vim.c opens with the 41 #includes slim-vim.c has, and eighty-one phases have
# taken away most of what they were for: the directory walker, the locale,
# the password file, dlopen, setjmp, the maths library, utime, uname.  The object
# now leaves 80 symbols for libc to supply, and a header that supplies none of them
# -- no function, no type, no constant -- is a dependency on the host that buys
# nothing.
#
# THE SET IS COMPUTED, NOT LISTED.  A header's name says what it is for, not what
# this file uses from it: <sys/types.h> may be the only thing declaring a type the
# code names, and musl's headers include one another, so one that looks dead can be
# carrying another.  So each #include is tried: delete it and require the compile
# to stay SILENT under the sweep's flags.  gcc 15 compiles C23, where a call to an
# undeclared function is an error and an unknown type is an error, so "silent" is
# "nothing this header provided was used".  The candidates are tried one at a time
# and in parallel, then all together; if the set fails together -- two headers each
# covering for the other -- it falls back to removing them one by one, keeping each
# removal only while the build stays silent.  ONE BY ONE FROM THE BOTTOM: tried top
# down, the first dry run dropped <string.h> and <stdlib.h>, whose declarations also
# arrive through headers further down, and kept <wchar.h>.  The general headers come
# first in the file, so walking up from the end drops the specific ones and keeps
# the ones everything else leans on.
#
# THE PROOF IS THE BINARY, BYTE FOR BYTE.  A declaration that no longer exists cannot
# change what is compiled -- but a header can also define a function-like macro that
# shadows the function (musl's <ctype.h> does, for isalpha and friends), and losing
# one of those would change code without a word from the compiler if the prototype
# still came from somewhere.  So the input and the output are both built with
# SOURCE_DATE_EPOCH pinned, from the same file name, and must be identical.  That is
# tier 1 of the verification tiers, and it makes the delta "none" a measurement.
#
# EVERY COMMENT GOES TOO: the former-file banners, the notes, and the lines earlier
# phases wrote to explain themselves.  Reasoning lives in the phase programs,
# WHIM-GOAL.md and the commit messages; whim-vim.c carries code and nothing else, and
# no phase after this one writes a comment into it.  Comments do not reach the
# binary -- nothing uses __LINE__ -- so the byte-for-byte check covers this cut too.
# A comment is found by a scanner that knows string and character literals, since
# "pack/*/start/*" and "://" are data.  A line that was only a comment is deleted; a
# comment after code is cut with the whitespace before it; a blank run the deletions
# create is collapsed.
set -eu

work=${1:?usage: whim82.sh <work-dir>}
f="$work/whim-vim.c"
CC_CHECK='gcc -fsyntax-only -O0 -Wall -Wextra -Wno-unused-parameter'

d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT

before_lines=$(grep -c '' "$f")
tools/symbols.sh "$f" .cache/symbols/before

# The input, for the binary comparison at the end.  Same file name both sides, or
# __FILE__ differs.  Built there, not here in the background: the header trials
# below end in a bare `wait`, which reaps every child, and a later `wait $pid` on a
# reaped child is status 127 -- which is how the first dry run died.
mkdir "$d/old"
cp "$f" "$d/old/whim-vim.c"

silent() {
    out=$($CC_CHECK "$1" 2>&1) || return 1
    [ -z "$out" ]
}

if ! silent "$f"; then
    echo "  includes     the input does not compile silently -- nothing to measure against"
    exit 1
fi

# The block: every #include, and they are the first directives in the file.
grep -nE '^#include <[^>]+>$' "$f" | cut -d: -f1 > "$d/lines"
total=$(wc -l < "$d/lines")
[ "$total" -gt 0 ] || { echo "  includes     no #include lines found"; exit 1; }
if grep -vE '^#include <[^>]+>$' "$f" | grep -qE '^[ \t]*#'; then
    echo "  includes     a directive other than #include is in the file"
    exit 1
fi

# One at a time, all at once.
while read -r n; do
    (sed "${n}d" "$f" > "$d/t$n.c" && if silent "$d/t$n.c"; then echo "$n"; fi; rm -f "$d/t$n.c") &
done < "$d/lines" > "$d/cand.unsorted"
wait
sort -n "$d/cand.unsorted" > "$d/cand"
echo "  includes     $(wc -l < "$d/cand") of $total can go on their own"

# All together, and if not, one by one from the bottom.
drop() {
    sed "$(sed 's/$/d/' "$1" | tr '\n' ';')" "$f" > "$2"
}
drop "$d/cand" "$d/all.c"
if silent "$d/all.c"; then
    cp "$d/cand" "$d/keep"
    echo "  includes     and all of them together"
else
    : > "$d/keep"
    while read -r n; do
        cat "$d/keep" > "$d/try"
        echo "$n" >> "$d/try"
        drop "$d/try" "$d/t.c"
        if silent "$d/t.c"; then cp "$d/try" "$d/keep"; fi
    done <<EOF
$(sort -rn "$d/cand")
EOF
    sort -n "$d/keep" -o "$d/keep"
    echo "  includes     together they do not build; $(wc -l < "$d/keep") removed one by one, from the bottom"
fi
[ -s "$d/keep" ] || { echo "  includes     nothing to remove"; exit 1; }
removed=$(while read -r n; do sed -n "${n}s/^#include <\(.*\)>$/\1/p" "$f"; done < "$d/keep" | tr '\n' ' ')
drop "$d/keep" "$d/new.c"
cp "$d/new.c" "$f"
echo "  includes     removed: $removed"

# --- every comment ---------------------------------------------------------
python3 - "$f" <<'PY'
import re, sys
path = sys.argv[1]
t = open(path, errors='surrogateescape').read()

def comments(s):
    """(start, end) of every comment, found by a scanner that knows string and
    character literals -- a `//` inside "pack/*/start/*" or "://" is not one."""
    out, i, n = [], 0, len(s)
    while i < n:
        c = s[i]
        if c in '"\'':
            i += 1
            while i < n and s[i] != c:
                i += 2 if s[i] == '\\' else 1
            i += 1
        elif s.startswith('//', i):
            j = s.find('\n', i)
            out.append((i, n if j < 0 else j))
            i = n if j < 0 else j
        elif s.startswith('/*', i):
            j = s.find('*/', i + 2)
            out.append((i, n if j < 0 else j + 2))
            i = n if j < 0 else j + 2
        else:
            i += 1
    return out

def die(msg):
    sys.exit('  %-12s %s' % ('nocomments', msg))

found = comments(t)
if any(t[a:b].startswith('/*') for a, b in found):
    die('a block comment -- this program only knows line comments')
runs_before = len(re.findall(r'\n\n\n', t))
after_brace_before = len(re.findall(r'\{\n\n', t))
lines = t.split('\n')
starts = {}
for a, b in found:
    ln = t.count('\n', 0, a)
    col = a - (t.rfind('\n', 0, a) + 1)
    starts[ln] = col
out = []
gone = trimmed = 0
for ln, line in enumerate(lines):
    if ln in starts:
        code = line[:starts[ln]].rstrip()
        if code == '':
            gone += 1
            continue
        out.append(code)
        trimmed += 1
    else:
        out.append(line)
t = '\n'.join(out)
t = t.lstrip('\n')
t = re.sub(r'\n\n\n+', '\n\n', t)
t = re.sub(r'\{\n\n', '{\n', t) if after_brace_before == 0 else t
if comments(t):
    die('%d comments survive' % len(comments(t)))
if len(re.findall(r'\n\n\n', t)) > runs_before:
    die('stripping made a run of blank lines')
open(path, 'w', errors='surrogateescape').write(t)
print('  %-12s %d comment lines deleted, %d comments cut from the end of a line' % ('nocomments', gone, trimmed))
PY

tools/sweep.sh "$f"

left=$(grep -cE '^#include <' "$f")
[ "$left" = $((total - $(wc -l < "$d/keep"))) ] || { echo "  includes     $left includes left, expected $((total - $(wc -l < "$d/keep")))"; exit 1; }
silent "$f" || { echo "  includes     the result does not compile silently"; exit 1; }

tools/phasecheck.sh "$work" "$f" .cache/symbols/before

tools/phasebuild.sh "$work" "$before_lines"

# --- tier 1: the binary is the same bytes -----------------------------------
(cd "$d/old" && SOURCE_DATE_EPOCH=0 gcc -O0 -static -s -o vim whim-vim.c)
mkdir "$d/new"
cp "$f" "$d/new/whim-vim.c"
(cd "$d/new" && SOURCE_DATE_EPOCH=0 gcc -O0 -static -s -o vim whim-vim.c)
if ! cmp -s "$d/old/vim" "$d/new/vim"; then
    echo "  includes     the binary changed -- a header was doing more than declaring"
    exit 1
fi
echo "  includes     $left includes left; the binary is byte-identical ($(wc -c < "$d/new/vim") bytes)"

# --- the delta, cumulative: phase 81's, unchanged ---------------------------
REMOVED=$(sed -n "/^REMOVED='$/,/^'$/p" pipes/whim80.sh | sed '1d;$d')
tools/whimdelta.sh "$work/whim-vim" "$f" --term-moved --cases bomb_on,filter,read_cmd,retab,sort_u,sort_n,ff_dos,binary_mode,format_gq,format_comment,open_comment \
    helpclose intro version cd chdir lcd lchdir tcd tchdir pwd '!' language \
    tags preserve swapname mkvimrc mkexrc checktime command comclear colorscheme \
    abbreviate noreabbrev abclear iabbrev inoreabbrev iabclear cabbrev cnoreabbrev cabclear \
    sleep smile vim9script autocmd augroup doautocmd doautoall noautocmd sandbox filetype \
    tab tabedit tabfirst tabmove tablast tabnext tabnew tabonly tabprevious tabNext tabrewind tabs redrawtabline \
    browse confirm mode open tmap tmapclear tnoremap \
    all args argadd argdelete argdedupe argglobal arglocal argument first last rewind \
    sargument sall sfirst slast srewind \
    aboveleft ball belowright botright horizontal leftabove new only resize rightbelow \
    sbuffer sbNext sball sbfirst sblast sbnext sbprevious sbrewind split sunhide sview \
    syncbind topleft unhide vertical vnew vsplit \
    buffer bNext bdelete bfirst blast brewind buffers bwipeout files ls \
    bnext bprevious keepalt \
    center left retab right sort uniq \
    qall quitall wall wqall xall \
    startinsert startreplace startgreplace stopinsert \
    noswapfile \
    setlocal setglobal \
    lmap lnoremap lmapclear \
    jumps clearjumps \
    $REMOVED
