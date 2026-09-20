#!/bin/sh
# Build the input ONE CUTTER is handed, for tools that run partway through a
# phase's edit script.
#
# Usage: toolinput.sh <tool>...
#
# phasecorpus.sh saves the tree before each PHASE's edit, which is the right
# input only for the first tool that edit runs.  whim3-edit.sh runs dropopts
# and then optreaders, so optreaders' input is phase 3's input with dropopts
# already applied -- and comparing optreaders against the phase input cuts
# nothing, which the comparison reports as VACUOUS rather than passing.
#
# This truncates the edit script at the tool's own invocation and runs what
# comes before it.  Truncating is safe because what is wanted is everything
# BEFORE the tool, and a multi-line invocation only ever extends further down.
set -eu
cd /root/slim-vim/.claude/worktrees/go-tools
out=${GOCMP_CORPUS:-.gocorpus}/phases
mkdir -p "$out"

for tool in "$@"; do
    # A TOOL IS NAMED TWO WAYS NOW and this must match both, or it goes quiet.
    # The cutover to `tools/st.sh <tool>` replaces the literal `tools/<tool>.py`
    # at every swapped call site, so a locator that greps only for the Python
    # path finds NO edit script for a swapped tool, prints one line, and
    # continues -- after which that tool has no per-tool corpus and every
    # comparison of it reports VACUOUS.  The harness would go quiet exactly
    # where the porting work had already succeeded, which is the worst possible
    # place for it to.
    script=$(grep -rlE "tools/$tool\.py|tools/st\.sh +$tool\b" pipes/whim*-edit.sh pipes/zero*-edit.sh 2>/dev/null | head -1)
    [ -n "$script" ] || { echo "toolinput: no edit script runs $tool"; continue; }
    base=$(basename "$script" -edit.sh)          # e.g. whim3
    n=${base#whim}; n=${n#zero}
    src=$out/$base-in.c
    [ -f "$src" ] || { echo "toolinput: no phase input for $base ($src)"; continue; }

    # The INVOCATION, not the first mention.  whim32-edit.sh names
    # tools/nocomplkeys.py in a comment at line 25 and runs it at line 48, so
    # `grep | head -1` truncated the edit 23 lines early -- and the tool was
    # then handed a tree that nocompl.py had not cut, where its docomplete
    # literal does not match.  Both implementations refused identically, which
    # is how it showed up as VACUOUS rather than as a difference.
    line=$(grep -nE "^[^#]*(python3 +tools/$tool\.py|tools/st\.sh +$tool\b)" "$script" | head -1 | cut -d: -f1)
    [ -n "$line" ] || line=$(grep -nE "tools/$tool\.py|tools/st\.sh +$tool\b" "$script" | head -1 | cut -d: -f1)
    work=$(mktemp -d); state=$(mktemp -d); trunc=$(mktemp)
    head -n $((line - 1)) "$script" > "$trunc"
    cp "$src" "$work/${base%%[0-9]*}-vim.c" 2>/dev/null || true
    case $base in whim*) cp "$src" "$work/whim-vim.c" ;; zero*) cp "$src" "$work/zero-vim.c" ;; esac
    grep -c '' "$src" > "$state/input-lines"
    if sh "$trunc" "$work" "$state" >/dev/null 2>&1; then
        case $base in
            whim*) cp "$work/whim-vim.c" "$out/tool-$tool.c" ;;
            zero*) cp "$work/zero-vim.c" "$out/tool-$tool.c" ;;
        esac
        echo "toolinput: $tool <- $base, after $((line - 1)) lines of its edit"
    else
        echo "toolinput: $tool -- the truncated $base edit failed"
    fi
    rm -rf "$work" "$state" "$trunc"
done
