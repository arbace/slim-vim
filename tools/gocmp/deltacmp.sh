#!/bin/sh
# The delta parser: whimdelta.sh's awk against `slimtools declared`, for every
# phase and every field it computes.
set -eu
cd /root/slim-vim/.claude/worktrees/go-tools
bin=$(sh tools/gobuild.sh)
same=0; diff=0

delta_awk='
    /^[ \t]*#/ || NF == 0 { next }
    {
        i = 1
        if ($0 ~ /^[0-9]/) { phase = $1 + 0; i = 2 }
        if (phase > N) next
        for (; i <= NF; i++) {
            w = $i
            if (phase == N && w !~ /^(case:|drop:|term-moved$)/) own[++nown] = w
            if (w == "term-moved") term = 1
            else if (w ~ /^drop:case:/) delete cases[substr(w, 11)]
            else if (w ~ /^drop:/) delete cmds[substr(w, 6)]
            else if (w ~ /^case:/) cases[substr(w, 6)] = 1
            else cmds[w] = 1
        }
    }
    END {
        if (WHAT == "term") print (term ? "yes" : "no")
        else if (WHAT == "cases") for (c in cases) print c
        else if (WHAT == "cmds") for (c in cmds) print c
        else if (WHAT == "own") for (k = 1; k <= nown; k++) print own[k]
    }'

one() {   # one <deltafile> <maxphase> <label>
    f=$1; max=$2; lab=$3
    n=0
    while [ "$n" -le "$max" ]; do
        t=$(awk -v N="$n" -v WHAT=term "$delta_awk" "$f")
        c=$(awk -v N="$n" -v WHAT=cmds "$delta_awk" "$f" | sort | tr '\n' ' ')
        k=$(awk -v N="$n" -v WHAT=cases "$delta_awk" "$f" | sort | tr '\n' ' ')
        o=$(awk -v N="$n" -v WHAT=own "$delta_awk" "$f" | tr '\n' ' ')
        [ "$t" = yes ] && tb=true || tb=false
        a="term $tb|cmds $(echo $c)|cases $(echo $k)|own $(echo $o)"
        g=$(./"$bin" declared "$f" "$n")
        gt=$(echo "$g" | sed -n 's/^term //p')
        gc=$(echo "$g" | sed -n 's/^cmds //p')
        gk=$(echo "$g" | sed -n 's/^cases //p')
        go=$(echo "$g" | sed -n 's/^own //p')
        b="term $gt|cmds $gc|cases $gk|own $go"
        if [ "$a" = "$b" ]; then same=$((same + 1)); else
            diff=$((diff + 1)); printf '  %s %s\n    awk: %s\n    go : %s\n' "$lab" "$n" "$a" "$b"
        fi
        n=$((n + 1))
    done
}

one pipes/whim.delta 82 whim
one pipes/zero.delta 45 zero
echo "delta parse: $same same, $diff differ"
[ "$diff" -eq 0 ]
