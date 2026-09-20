#!/bin/sh
# Compare tools/implhash.sh against `slimtools implhash` for every unit and
# every edit, in all three pipelines.
set -eu
cd /root/slim-vim/.claude/worktrees/go-tools
bin=$(sh tools/gobuild.sh)
same=0; diff=0

check() {   # check <pipeline> <args...>
    p=$1; shift
    a=$(sh tools/implhash.sh "$@" "$p" 2>&1 || echo ERR)
    b=$(./"$bin" implhash "$@" "$p" 2>&1 || echo ERR)
    if [ "$a" = "$b" ]; then
        same=$((same + 1))
    else
        diff=$((diff + 1))
        echo "DIFFER $p $*: shell=$a go=$b"
    fi
}

for p in slim whim zero; do
    phases=$(./"$bin" parts "$p" 0-99 >/dev/null 2>&1 || true)
    n=99
    case $p in slim) n=11 ;; whim) n=82 ;; zero) n=45 ;; esac
    i=0
    while [ "$i" -le "$n" ]; do
        check "$p" "$i"
        if [ -f "pipes/$p$i-edit.sh" ]; then check "$p" --edit "$i"; fi
        i=$((i + 1))
    done
done

# And the real stages, which are what the driver actually runs.
for p in whim zero; do
    for u in $(awk '$1 == "stage" { print $2 }' "pipes/$p.stages"); do
        check "$p" "$u"
    done
done

echo "implhash: $same identical, $diff differ"
[ "$diff" -eq 0 ]
