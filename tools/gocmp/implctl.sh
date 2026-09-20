#!/bin/sh
# Control: distinct units give distinct digests, and a changed dependency
# moves BOTH implementations' answers together.
set -eu
cd /root/slim-vim/.claude/worktrees/go-tools
bin=$(sh tools/gobuild.sh)

echo "=== distinct units, distinct digests ==="
for u in 13-41 42-63 72; do
    printf '  whim %-7s shell=%s  go=%s\n' "$u" \
        "$(sh tools/implhash.sh "$u" whim)" "$(./"$bin" implhash "$u" whim)"
done

echo "=== a changed dependency must move both ==="
cp tools/canon.sh ${GOCMP:-tools/gocmp}/canon.sh.orig
echo '# probe' >> tools/canon.sh
printf '  after probe    shell=%s  go=%s\n' \
    "$(sh tools/implhash.sh 13-41 whim)" "$(./"$bin" implhash 13-41 whim)"
cp ${GOCMP:-tools/gocmp}/canon.sh.orig tools/canon.sh
printf '  reverted       shell=%s  go=%s\n' \
    "$(sh tools/implhash.sh 13-41 whim)" "$(./"$bin" implhash 13-41 whim)"
