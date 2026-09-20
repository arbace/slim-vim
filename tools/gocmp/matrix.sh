#!/bin/sh
# Every ported tool against every corpus.
set -eu
cd /root/slim-vim/.claude/worktrees/go-tools
bin=$(sh tools/gobuild.sh)
for t in deadsweep deadprotos typereach funcreach deadfields deadenums \
         blankruns joinparens splitheads brace onestmt onedecl forcomma canon; do
    for c in gc/wz gc/unswept corpus-slim; do
        r=$("./$bin" difftest "$t" ${GOCMP:-tools/gocmp}/$c/*.c 2>&1 | head -1 | sed 's/.*: //')
        printf '%-11s %-9s %s\n' "$t" "$(basename $c)" "$r"
    done
done
