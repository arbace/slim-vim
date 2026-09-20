#!/bin/sh
# zscreen.py vs `slimtools zscreen`, on real escape streams captured from a
# real zero binary.  The recordings keep only a digest of the stream, so the
# streams are produced here.
set -eu
cd /root/slim-vim/.claude/worktrees/go-tools
bin=$(sh tools/gobuild.sh)
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
tar xf .build-zero/r45.tar -C "$w"
v=$(find "$w" -maxdepth 1 -name 'zero-vim' -type f | head -1)
[ -n "$v" ] || { echo "no zero binary in r45.tar"; exit 1; }
cp "$v" "$w/vim"; chmod +x "$w/vim"

same=0; diff=0
i=0
# A few keystroke programs, each exercising a different part of the screen
# model: plain text, a scroll, a message line, an undo, a wrapped line.
for keys in \
    'ihello world\x1bZZ' \
    'i\x1b:set nu\rihello\x1bZZ' \
    'ione\rtwo\rthree\x1bggdd:q!\r' \
    'iabc\x1buZZ' \
    'i0123456789\x1b:q!\r' \
    ':q!\r'
do
    i=$((i + 1))
    printf "$keys" > "$w/keys"
    ( cd "$w" && ./vim < keys > "stream$i" 2>/dev/null ) || true
    [ -s "$w/stream$i" ] || { echo "  case $i: empty stream, skipped"; continue; }
    python3 -c "
import sys
sys.path.insert(0, 'tools')
import zscreen
data = open(sys.argv[1], 'rb').read()
s = zscreen.Screen(24, 80)
s.feed(data)
for n, (text, y, x, b) in enumerate(s.snaps):
    print('--- snap %d cursor=%d,%d bells=%d' % (n, y, x, b))
    print(text)
print('--- final cursor=%d,%d bells=%d snaps=%d' % (s.y, s.x, s.bells, len(s.snaps)))
" "$w/stream$i" > "$w/py$i.txt"
    ./"$bin" zscreen "$w/stream$i" > "$w/go$i.txt"
    if cmp -s "$w/py$i.txt" "$w/go$i.txt"; then
        same=$((same + 1))
        printf '  case %d  same  (%s bytes of stream, %s snaps)\n' "$i" \
            "$(wc -c < "$w/stream$i")" "$(grep -c '^--- snap' "$w/py$i.txt" || true)"
    else
        diff=$((diff + 1))
        printf '  case %d  DIFFER\n' "$i"
        diff "$w/py$i.txt" "$w/go$i.txt" | head -10 || true
    fi
done
echo "zscreen: $same same, $diff differ"
[ "$diff" -eq 0 ]
