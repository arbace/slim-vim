#!/bin/sh
# An argument-taking cutter, Go against Python, on the invocations the phase
# programs actually make -- in parallel.
#
# Usage: pargcmp.sh <tool>   (the invocations are listed below, per tool)
#
# A tool driven by arguments has to be compared on the arguments it is given,
# because the refusals it owes are about THOSE letters.  Each list here is
# copied out of pipes/, and two deliberately wrong invocations are added as
# controls so the run cannot pass by refusing everything for a dull reason.
set -eu
cd /root/slim-vim/.claude/worktrees/go-tools
TOOL=${1:?usage: pargcmp.sh <tool>}
BIN=$PWD/$(sh tools/gobuild.sh)
OUT=$(mktemp -d)
export TOOL BIN OUT
trap 'rm -rf "$OUT"' EXIT

case $TOOL in
dropopts)
    set -- \
      "whim3|-h -? -A -F -H -g -f -X -Y -d -U -l -C -N -n -p -V --help --version --clean --literal --nofork --noplugin --not-a-term --gui-dialog-file --startuptime --log" \
      "yZu|-y -Z -u" \
      "b|-b" \
      "ctl-missing|-Q" \
      "ctl-bad|+x"
    ;;
*) echo "pargcmp: no invocation list for $TOOL" >&2; exit 2 ;;
esac

for inv in "$@"; do
    label=${inv%%|*}; args=${inv#*|}
    for src in ${GOCMP_CORPUS:-.cache/gocorpus}/*/*.c; do
        printf '%s|%s|%s\n' "$label" "$src" "$args"
    done
done | xargs -d '\n' -P "$(nproc)" -n 1 sh ${GOCMP:-tools/gocmp}/pargone.sh

count() { grep -l "$1" "$OUT"/* 2>/dev/null | wc -l; }
same=$(count '^same'); diff=$(count '^differ')
cut=$(count '^same cut'); refused=$(count '^same refused')
[ "$diff" -eq 0 ] || grep -h -A3 '^differ' "$OUT"/* | head -60
echo "pargcmp [$TOOL]: $same same, $diff differ ($cut cut, $refused refused)"
[ "$cut" -gt 0 ] || { echo "VACUOUS: nothing was actually cut"; exit 1; }
[ "$diff" -eq 0 ]
