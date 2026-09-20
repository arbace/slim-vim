#!/bin/sh
# tools/dropopts.py against the Go, on the THREE real invocations the phase
# programs make, over every corpus file.
#
# The argument lists are not invented: they are whim phase 3's eighteen, whim's
# `-y -Z -u` and whim's `-b`, copied out of pipes/.  A tool driven by arguments
# has to be compared on the arguments it is actually given, because the
# refusals it owes are about THOSE letters.
#
# Two deliberately wrong invocations are included as controls, so the run
# cannot pass by refusing everything identically for an uninteresting reason.
set -eu
cd /root/slim-vim/.claude/worktrees/go-tools
bin=$(sh tools/gobuild.sh)
same=0; diff=0; cut=0; refused=0

run() {   # run <label> <args...>
    label=$1; shift
    for src in ${GOCMP_CORPUS:-.cache/gocorpus}/*/*.c; do
        a=$(mktemp); b=$(mktemp)
        cp "$src" "$a"; cp "$src" "$b"
        pa=$(python3 tools/dropopts.py "$a" "$@" 2>&1 || echo "EXIT$?")
        pb=$(./"$bin" dropopts "$b" "$@" 2>&1 || echo "EXIT$?")
        case "$pa" in *EXIT*) refused=$((refused + 1)) ;; *) cut=$((cut + 1)) ;; esac
        if [ "$pa" = "$pb" ] && cmp -s "$a" "$b"; then
            same=$((same + 1))
        else
            diff=$((diff + 1))
            printf '%-10s %-22s DIFFER\npy: %s\ngo: %s\n' \
                "$label" "$(basename "$src")" "$pa" "$pb"
            cmp -s "$a" "$b" || echo "  (output files differ)"
        fi
        rm -f "$a" "$b"
    done
}

run whim3 -h '-?' -A -F -H -g -f -X -Y -d -U -l -C -N -n -p -V \
    --help --version --clean --literal --nofork --noplugin --not-a-term \
    --gui-dialog-file --startuptime --log
run yZu -y -Z -u
run b -b
run control-missing -Q           # no such case: must refuse, with the letter named
run control-bad '+x'             # not an option this can remove: must refuse

echo "dropopts: $same same, $diff differ ($cut cut, $refused refused)"
[ "$cut" -gt 0 ] || { echo "VACUOUS: nothing was actually cut"; exit 1; }
[ "$diff" -eq 0 ]
