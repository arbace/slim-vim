#!/bin/sh
# phasecheck's FAILURE paths must agree too: a cut that does not leave valid
# C, and a cut that leaves a warning.
set -eu
cd /root/slim-vim/.claude/worktrees/go-tools
bin=$(sh tools/gobuild.sh)
src=${GOCMP_CORPUS:-.cache/gocorpus}/wz/zero-r45.c

run() {   # run <mutation> <side>
    w=$(mktemp -d); b=$(mktemp -d)
    cp "$src" "$w/src.c"
    case $1 in
        broken)  printf 'this is not C;\n' >> "$w/src.c" ;;
        warning) printf 'static int probe_unused_variable;\n' >> "$w/src.c" ;;
    esac
    rm -rf .cache/compile .cache/symbols
    if [ "$2" = sh ]; then
        sh tools/phasecheck.sh "$w" "$w/src.c" "$b" 2>&1 || true
    else
        ./"$bin" phasecheck "$w" "$w/src.c" "$b" 2>&1 || true
    fi
    rm -rf "$w" "$b"
}

for m in broken warning; do
    a=$(run "$m" sh | sed "s|/tmp/tmp\.[A-Za-z0-9]*|TMP|g"); c=$(run "$m" go | sed "s|/tmp/tmp\.[A-Za-z0-9]*|TMP|g")
    if [ "$a" = "$c" ]; then
        printf '=== %-8s SAME ===\n%s\n' "$m" "$a"
    else
        printf '=== %-8s DIFFER ===\nshell:\n%s\ngo:\n%s\n' "$m" "$a" "$c"
    fi
done
