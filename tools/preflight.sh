#!/bin/sh
# Fail before a pass starts, not ten minutes into one.
#
# Usage: tools/preflight.sh
#
# Run only when a pass is actually needed -- upstream has moved, or vim.c is
# missing.  The ordinary case, where the sha matches and make just compiles the
# committed vim.c, reaches none of this and needs none of it.
#
# What it checks is exactly what a pass will reach for, in the order it will
# reach for it:
#
#   * the GNU userland the phase programs assume.  `sed -i` without an
#     argument, `mv -t`, and binutils' `nm --defined-only` are not portable to
#     BSD or macOS, and the failures they produce are a long way from the cause
#     -- phase 2 silently moving nothing, phase 8 finding no symbols.
#   * a compiler, python3, and patch.
#   * an agent, but ONLY if some phase still needs one.  This is the check
#     worth having: a machine with Claude Code installed but never started has
#     no credentials, and without this the pass dies in phase 9 with an
#     authentication error, having spent ten minutes getting there.
#
# Everything here is a question with a yes-or-no answer.  Nothing is repaired.
set -eu

fail=0
note() { printf '  %-12s %s\n' "$1" "$2"; }

# --- the userland ---------------------------------------------------------
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo x > "$tmp/f"
if ! sed -i 's/x/y/' "$tmp/f" 2>/dev/null || [ "$(cat "$tmp/f")" != y ]; then
    note sed "NOT GNU -- \`sed -i\` here wants an argument; phases 2 and 8 edit in place"
    fail=1
fi

mkdir -p "$tmp/d"
if ! mv -t "$tmp/d" "$tmp/f" 2>/dev/null; then
    note mv "no \`mv -t\` -- phase 2's flatten needs it"
    fail=1
fi

if ! nm --help 2>&1 | grep -q -- --defined-only; then
    note nm "no \`--defined-only\` -- phases 2, 6 and 8 ask the objects what they define"
    fail=1
fi

for t in gcc python3 patch tar git; do
    command -v "$t" >/dev/null 2>&1 || { note "$t" "not on PATH"; fail=1; }
done

# --- an agent, only if a phase still needs one ----------------------------
missing=
for p in 0 1 2 3 4 5 6 7 8 9; do
    [ -x "tools/phase$p.sh" ] || missing="$missing $p"
done

if [ -z "$missing" ]; then
    note phases "all ten have programs; a pass needs no agent unless one fails"
else
    note phases "no program for:$missing -- these will run as agents"
    if ! command -v claude >/dev/null 2>&1; then
        note claude "not on PATH, and a phase needs it"
        fail=1
    elif ! IS_SANDBOX=1 timeout 120 claude -p 'Reply with exactly: OK' \
            >/dev/null 2>&1; then
        note claude "present but cannot run -- not signed in, or no ANTHROPIC_API_KEY"
        note "" "a fresh install has neither; run \`claude\` once, or set the key"
        fail=1
    else
        note claude "available and authenticated"
    fi
fi

if [ "$fail" != 0 ]; then
    echo "  preflight    STOPPING -- a pass would fail on the above, later and less clearly"
    exit 1
fi
note preflight "ok"
