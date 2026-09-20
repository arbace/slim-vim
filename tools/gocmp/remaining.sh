#!/bin/sh
# What is left: the tools whim/zero name that have no Go subcommand yet.
set -eu
cd /root/slim-vim/.claude/worktrees/go-tools
bin=$(sh tools/gobuild.sh)
done_list=$(./"$bin" 2>&1 | sed -n 's/^    \([a-z0-9]*\) .*/\1/p' | sort -u)

used=$(grep -ohE 'tools/[a-z0-9_]+\.py' pipes/whim*.sh pipes/zero*.sh | sed 's|tools/||; s|\.py||' | sort -u)

total=0; left=0; leftlines=0
for t in $used; do
    total=$((total + 1))
    if echo "$done_list" | grep -qx "$t"; then continue; fi
    # a few are named under a different subcommand
    case $t in
        create_cmdidxs) continue ;;
        nvidxcheck) continue ;;
        cutil|zstream|zrec|zscreen|ptyrun) continue ;;
    esac
    n=$(wc -l < "tools/$t.py")
    left=$((left + 1)); leftlines=$((leftlines + n))
    printf '%5d  %s\n' "$n" "$t"
done | sort -rn
echo "---"
echo "distinct tools whim/zero name: $(echo "$used" | wc -l)"
