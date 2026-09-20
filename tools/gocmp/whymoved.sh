#!/bin/sh
# Why did a phase that names no directory re-key?  Print the dependency paths
# the old regex found and the new one finds, for the program and for each of
# its level-1 deps, and show only the differences.
set -eu
cd /root/slim-vim/.claude/worktrees/go-tools
prog=$1

old() { grep -oE '(tools|pipes)/[A-Za-z0-9_/-]+\.(py|sh|txt|mk|patch)' "$1" 2>/dev/null || true; }
new() {
    grep -oE '(tools|pipes)/[A-Za-z0-9_/-]+\.(py|sh|txt|mk|patch|go|mod|sum)' "$1" 2>/dev/null || true
    grep -oE '(tools|pipes)/[A-Za-z0-9_/-]*/([^A-Za-z0-9_/.-]|$)' "$1" 2>/dev/null |
        sed 's#[^/]$##' | sort -u |
        while read -r d; do [ -d "$d" ] && find "$d" -type f; done | LC_ALL=C sort
    true
}

for f in "$prog" $(old "$prog" | sort -u); do
    [ -f "$f" ] || continue
    a=$(old "$f" | sort -u)
    b=$(new "$f" | sort -u)
    if [ "$a" != "$b" ]; then
        echo "--- $f gains:"
        printf '%s\n' "$b" | comm -13 <(printf '%s\n' "$a") - | sed 's/^/      /' | head -6
    fi
done
