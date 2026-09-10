#!/bin/sh
# Phase 8 -- internal linkage, then dead code to a fixpoint.  See GOAL.md.
#
# Usage: tools/phase8.sh <work-dir>       (run from the repository root)
#
# Before the macro work, not after: every macro deleted here is one that does
# not have to be converted in Phase 9.
#
# The order is forced.  Split declarations are joined first, because the dead
# sweep deletes by line and half a declaration left behind surfaces as an
# unrelated undeclared symbol.  Then everything but main() becomes static,
# which is what turns `-Wall -Wextra` into a real dead-code detector: with
# internal linkage the compiler can see that nothing uses a thing.  Only then
# does the sweep run, and it runs to a JOINT fixpoint with the type sweep,
# because deleting a function orphans its callees and deleting a type orphans
# the functions that took it.
set -eu

work=${1:?usage: phase8.sh <work-dir>}
f="$work/vim.c"
export SOURCE_DATE_EPOCH=1700000000

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

before_lines=$(grep -c '' "$f")

# --- join, then make it all internal --------------------------------------
python3 tools/joindecls.py "$f"

# EXTERN is what makes the globals external, and it becomes static TEXTUALLY.
# Expanding it as a macro instead pads all 1,055 sites with a space on each
# side and leaves ` static  int p_ai;`.
n_ext=$(grep -c '^EXTERN\b' "$f" || true)
sed -i 's/^EXTERN\b/static/' "$f"
echo "  EXTERN       $n_ext sites became static, textually"

# PLURAL_MSG is the same shape one level down: its body emits a bare
# `char var[]`, which leaves two error strings external however the call sites
# are written.  The macro body is what has to change.
sed -i 's/^\(# define PLURAL_MSG(.*)\)\( *\)char \(var1\[\] = msg1;\) *char \(var2\[\] = msg2;\)/\1\2static char \3     static char \4/' "$f"

# --- until nm says only main ----------------------------------------------
# nm the OBJECT, not a linked binary: a static musl binary defines 1,400-odd
# symbols of its own and buries the answer.
round=0
while :; do
    round=$((round + 1))
    gcc -c -O0 -o "$tmp/o.o" "$f" 2>/dev/null || {
        echo "  static       build failed in round $round"
        gcc -c -O0 -o /dev/null "$f" 2>&1 | grep -E 'error' | head -5 | sed 's/^/               /'
        exit 1
    }
    ext=$(nm --extern-only --defined-only "$tmp/o.o" | awk '{print $NF}' | grep -v '^main$' || true)
    [ -z "$ext" ] && break
    if [ "$round" -ge 20 ]; then
        echo "  static       not converging; still external:$(echo $ext | head -c 200)"
        exit 1
    fi
    for sym in $ext; do
        # The definition is at column 0 and is not already static.  A prototype
        # whose name is a function-like macro is a declaration of the expansion,
        # not of itself -- mch_rename is one, and making it static declares
        # libc's rename static -- so a name that has a #define is left alone.
        if grep -q "^# *define  *$sym(" "$f"; then
            echo "  static       $sym is a macro name, left alone"
            continue
        fi
        python3 - "$f" "$sym" <<'PY'
import re, sys
path, sym = sys.argv[1], sys.argv[2]
lines = open(path, errors='surrogateescape').read().split('\n')

# A declaration at file scope: starts at column 0 with a type or a storage
# class, names the symbol, and ends the way a declaration or a definition
# does.  `extern` is REPLACED rather than prefixed -- two storage classes in
# one declaration is an error, and the globals block is written that way.
# The terminator is deliberately not required.  Two prototypes carry their
# attribute on a CONTINUATION line -- `int vim_vsnprintf(...)` then
# `        ATTRIBUTE_FORMAT_PRINTF(3, 0);` -- so the declaration's own line
# ends in `)`.  Anchoring at column 0 is enough on its own here: every
# statement in this file is indented, so a call cannot match.
decl = re.compile(r'^(?!static\b)[A-Za-z_][A-Za-z0-9_ \t*()\[\]]*\b%s\s*[(\[;=,)]'
                  % re.escape(sym))
TYPELINE = re.compile(r'^[ \t]*[A-Za-z_][A-Za-z0-9_ \t*]*$')
# EVERY file-scope occurrence, not the first.  Objects do not inherit internal
# linkage: a definition with no storage class is external whatever a prior
# static declaration said, and gcc rejects the pair outright with "non-static
# declaration follows static declaration".  The twelve in pathdef.c's region
# need the keyword on both the declaration and the definition.
def start_of(i):
    """Where the declaration containing line i begins.

    A function definition here is written with its return type on the line
    above, indented, and the name at column 0.  Prefixing the name's line
    gives `static empty_curbuf(...)` under a line that already says
    `static int`, which gcc reports as a duplicate storage class.  The keyword
    belongs at the START of the declaration.
    """
    j = i - 1
    while j >= 0 and lines[j].strip() == '':
        j -= 1
    # Only a line that LOOKS like a return type counts -- an identifier and
    # qualifiers, nothing else.  Testing "does not end in a semicolon" instead
    # walks back onto whatever happens to precede, and a #define acquires a
    # `static` in front of its `#`.
    if j >= 0 and TYPELINE.match(lines[j]):
        return j
    return i

hits = 0
for i, l in enumerate(lines):
    if not decl.match(l):
        continue
    k = start_of(i)
    if lines[k].lstrip().startswith('static'):
        continue
    if lines[k].startswith('extern '):
        lines[k] = 'static ' + lines[k][len('extern '):]
    else:
        indent = len(lines[k]) - len(lines[k].lstrip())
        lines[k] = lines[k][:indent] + 'static ' + lines[k][indent:]
    hits += 1
if not hits:
    sys.exit('phase8: no file-scope declaration of %s to make static' % sym)
open(path, 'w', errors='surrogateescape').write('\n'.join(lines))
PY
    done
done
echo "  static       nm on the object prints exactly main, after $round round(s)"

# --- dead code, to a joint fixpoint ---------------------------------------
# Functions and variables from -Wall -Wextra; types by reachability, for which
# no warning exists.  Alternating, because each orphans the other.
# The fixpoint is the FILE, not any tool's report.  Keying on a count means
# parsing three tools' prose, and reading only the first number of
# "prototypes 0, functions 1, variables 2" stops the loop with work left to do
# -- which it did, leaving three unused functions and a failed warning gate.
sweep=0
while :; do
    sweep=$((sweep + 1))
    before=$(sha256sum "$f" | cut -d' ' -f1)

    a=$(python3 tools/deadsweep.py "$f" | tail -1)
    # Prototypes for functions that no longer exist say nothing to gcc, and
    # each one is a ROOT for the type sweep -- proftime_T and getoption_T
    # survived an entire type pass on the strength of one dead declaration
    # apiece.  So this belongs inside the loop, between the two.
    c=$(python3 tools/deadprotos.py "$f" | tail -1)
    b=$(python3 tools/typereach.py "$f" --delete | tail -1)
    echo "  sweep $sweep      $a; $c; $b"

    [ "$(sha256sum "$f" | cut -d' ' -f1)" = "$before" ] && break
    if [ "$sweep" -ge 15 ]; then
        echo "  sweep        not converging after $sweep rounds"
        exit 1
    fi
done

# --- the two warnings that are findings, not dead code --------------------
# GOAL.md predicts both, and both were there.  They are the reason the sweep is
# not a delete-everything-it-names loop: a warning can be the compiler noticing
# a bug rather than noticing something unused.
#
#   :winpos parsed two numbers nothing reads any more.  getdigits() advances
#   the pointer, so the CALLS have to stay and only the variables go -- delete
#   the calls and the second number is parsed from the first one's text.
#
#   The swap-file age check compared st.st_mtime against time(NULL) minus
#   sinfo.uptime, and uptime is unsigned, which makes the whole subtraction
#   unsigned and liable to wrap.  A cast to time_t is the fix; deleting
#   anything here would have been wrong.
python3 tools/findings8.py "$f"

# --- and the only warnings left must be the fall-throughs -----------------
# 37 of them, deliberate, and Phase 9 is where they are marked as such with
# __attribute__((fallthrough)).  Anything else means the sweep is unfinished --
# and the requirement is nothing else AT ALL, never "the usual two", because a
# new warning cannot hide behind a remembered count.
gcc -c -O0 -Wall -Wextra -Wno-unused-parameter -o /dev/null "$f" 2>&1 \
    | grep 'warning:' > "$tmp/warn" || true
other=$(grep -cv 'implicit-fallthrough' "$tmp/warn" || true)
ft=$(grep -c 'implicit-fallthrough' "$tmp/warn" || true)
if [ "$other" != 0 ]; then
    echo "  warnings     $other besides the fall-throughs -- the sweep is not finished"
    grep -v 'implicit-fallthrough' "$tmp/warn" | head -5 | sed 's/^/               /'
    exit 1
fi
echo "  warnings     $ft fall-throughs and nothing else"

make -C "$work" clean >/dev/null 2>&1 || true
if make -C "$work" >/dev/null 2>&1; then
    echo "  build        ok, $before_lines -> $(grep -c '' "$f") lines"
else
    echo "  build        FAILED -- rerun by hand: make -C $work"
    exit 1
fi
