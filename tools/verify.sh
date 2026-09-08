#!/bin/sh
# Everything a phase boundary needs, run concurrently, with one verdict.
#
# Usage: tools/verify.sh <baselines-dir> [--enums]
#
# The harnesses are independent and mostly wait, so they run together; the
# build has to come first because they all need the binary.  --enums adds the
# DWARF enumerator dump, which rebuilds with -g and is only wanted around a
# change that could renumber something.
set -e
base=${1:?usage: verify.sh <baselines-dir> [--enums]}
tmp=$(mktemp -d)
fail=0

# A build failure is the commonest failure and must be reported, not fall
# through `set -e` and leave the script dying with no output at all.
if ! make clean >/dev/null 2>&1 || ! make >"$tmp/build.log" 2>&1; then
    echo "  build        FAILED"
    grep -E 'error|Error' "$tmp/build.log" | head -10 | sed 's/^/      /'
    rm -rf "$tmp"
    exit 1
fi

run() {
    name=$1; shift
    if "$@" >"$tmp/$name.log" 2>&1; then
        printf '  %-12s ok\n' "$name"
    else
        printf '  %-12s FAILED\n' "$name"
        sed 's/^/      /' "$tmp/$name.log" | head -20
        fail=1
    fi
}

check_behaviour() {
    python3 tools/behaviour.py ./vim "$tmp/t" >/dev/null && diff -rq "$base/behaviour" "$tmp/t"
}
check_exsweep() {
    python3 tools/exsweep.py ./vim vim.c "$tmp/s" >/dev/null && diff "$base/ref-exsweep.txt" "$tmp/s"
}
check_pty() {
    python3 tools/ptycheck.py ./vim "$tmp/y" >/dev/null && diff "$base/ref-pty.txt" "$tmp/y"
}
check_term() {
    python3 tools/termcheck.py ./vim "$tmp/m" >/dev/null && diff "$base/ref-term.txt" "$tmp/m"
}
check_enums() {
    # Enumerators legitimately disappear when a dead type goes, so the set is
    # not the invariant.  The invariant is that every name present in both
    # dumps has the same value: deleting an enumerator renumbers the ones after
    # it, and several enums index a parallel table.
    ./tools/enumvals.sh vim.c "$tmp/e" || return 1
    python3 - "$base/enumerators.txt" "$tmp/e" <<'PY'
import sys
def load(p):
    return dict(l.rsplit('=', 1) for l in open(p).read().split())
b, a = load(sys.argv[1]), load(sys.argv[2])
bad = [k for k in a if k in b and a[k] != b[k]]
if bad:
    print('renumbered: ' + ', '.join('%s %s->%s' % (k, b[k], a[k]) for k in bad[:10]))
    sys.exit(1)
print('%d enumerators, %d shared with the baseline, none renumbered'
      % (len(a), len(set(a) & set(b))))
PY
}

check_behaviour >"$tmp/o.behaviour" 2>&1 & p1=$!
check_exsweep >"$tmp/o.exsweep" 2>&1 & p2=$!
check_pty     >"$tmp/o.pty"     2>&1 & p3=$!
check_term    >"$tmp/o.term"    2>&1 & p4=$!
python3 tools/create_cmdidxs.py vim.c --check >"$tmp/o.cmdidxs" 2>&1 & p5=$!
# gcc exits 0 with warnings, so exit status is no check at all here: the
# requirement is that it says *nothing*.
( gcc -c -O0 -Wall -Wextra -Wno-unused-parameter -o /dev/null vim.c 2>&1 \
    | tee "$tmp/o.warnings" | grep -q . && exit 1 || exit 0 ) & p6=$!
if [ "$2" = --enums ] || [ "$1" = --enums ]; then
    check_enums >"$tmp/o.enums" 2>&1 & p7=$!
fi

report() {
    if wait "$2" 2>/dev/null; then
        printf '  %-12s ok\n' "$1"
    else
        printf '  %-12s FAILED\n' "$1"
        sed 's/^/      /' "$tmp/o.$1" | head -20
        fail=1
    fi
}
report behaviour $p1
report exsweep  $p2
report pty      $p3
report term     $p4
report cmdidxs  $p5
report warnings $p6
[ -n "${p7-}" ] && report enums $p7

rm -rf "$tmp"
[ "$fail" = 0 ] && echo "  all clear" || echo "  SOMETHING FAILED"
exit "$fail"
