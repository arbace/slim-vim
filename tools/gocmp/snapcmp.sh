#!/bin/sh
# snapshot.sh vs `slimtools snapshot`: the digest IS the boundary, so it must
# match, and so must the manifest it is taken over.
set -eu
cd /root/slim-vim/.claude/worktrees/go-tools
bin=$(sh tools/gobuild.sh)
same=0; diff=0
for t in .build-whim/q41.tar .build-whim/q82.tar .build-zero/r45.tar .build-zero/r0.tar .build-zero/r20.tar; do
    [ -f "$t" ] || continue
    w=$(mktemp -d); o=$(mktemp -d)
    tar xf "$t" -C "$w"
    sh tools/snapshot.sh "$w" "$o/sh.tar" "$o/sh.sha" >/dev/null
    ./"$bin" snapshot "$w" "$o/go.tar" "$o/go.sha" >/dev/null
    if cmp -s "$o/sh.sha" "$o/go.sha" && cmp -s "$o/sh.sha.files" "$o/go.sha.files"; then
        same=$((same + 1))
        rec=$(cat "${t%.tar}.sha256" 2>/dev/null | cut -c1-12 || echo '?')
        printf '  %-16s same  %s   (recorded %s)\n' "$(basename "$t")" \
            "$(cut -c1-12 "$o/sh.sha")" "$rec"
    else
        diff=$((diff + 1))
        printf '  %-16s DIFFER\n' "$(basename "$t")"
        diff "$o/sh.sha.files" "$o/go.sha.files" | head -5 || true
    fi
    rm -rf "$w" "$o"
done
echo "snapshot: $same same, $diff differ"
[ "$diff" -eq 0 ]
