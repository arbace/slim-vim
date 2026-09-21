#!/bin/sh
# Does the repository reproduce itself from a clone of the remote?
#
# Usage: sh tools/gocmp/clonecheck.sh <scratch-dir> [step...]
#        steps: clone pass fix settle cross   (default: all, in that order)
#
# WHAT THIS IS FOR.  Every verify recorded in this repository -- and there have
# been many -- has run against a tree somebody assembled.  A verify needs
# recorded boundaries, and boundaries carried into a clone from a working tree
# would reintroduce exactly the assumption being tested.  So this clones the
# remote, repasses all three pipelines cold in it, and then compares.
#
# WHAT IT ESTABLISHES, AND AT WHAT STRENGTH.  Four values, and they are not the
# same claim:
#
#   THE PRODUCTS are the externally grounded part, because they are TRACKED:
#   git holds one side and the pass writes the other.  And the three are a
#   CHAIN, not three results -- `whim-repass` reads whatever `slim-repass`
#   left.  Only slim's left-hand side is externally fixed unconditionally: it
#   is the upstream REMOTE.  If slim comes back dirty, a dirty whim is that
#   finding propagating and not a second one.
#
#   THE VERIFIES establish determinism and internal consistency: each stage
#   reproduces from the boundary before it, in a scratch root of its own.  In a
#   clone they check against records the same pass wrote, so they are not
#   correctness against an independent record.
#
#   THE CROSS-TREE COMPARISON is what supplies that: the same boundary digests,
#   produced separately in another tree.  It retires "the clone only agrees
#   with itself" and does NOT touch "both could be wrong the same way if a
#   phase program is wrong", which no number of trees running the same programs
#   can retire.  Both halves belong in one sentence.
#
#   AND BEFORE COUNTING ANY AGREEMENT, ASK BY WHAT ROUTE THE TWO SIDES CAME TO
#   EXIST.  Tracked, copied, or separately produced -- only the third is
#   corroboration, and the same question has opposite answers two steps apart
#   in this very measurement:
#     .reference/<pipe>-phases   NOT tracked (.gitignore line 13, `git ls-files`
#                                empty, mtime after the clone) -- so the clone
#                                produced them and the agreement is real
#     `whim-record`              literally `cp .build-whim/q*.sha256` into
#                                .reference/whim-phases (whim.mk:189-196) -- so
#                                its thirteen are the SAME measurement seen
#                                twice and must not be added to the count
#   `cross` below reads .build-<pipe>/ on both sides, which is the separately
#   produced object; it deliberately does not read .reference/, which on one
#   side is a copy of it.
#
#   THE BEHAVIOURAL HARNESSES are four-valued in a clone and this surprised
#   both sessions that measured it:
#     slim   do not run and cannot fail -- pipes/slim1.sh exits 0 when
#            .reference/baselines is absent, saying "Record them from this
#            binary before Phase 2", and NOTHING performs that instruction
#     whim   half runs; tools/whimdelta.sh prints "no slim baselines to compare
#            against", still runs orphanopts, and exits $fail so it CAN refuse
#     zero   runs IN FULL, because zero phase 0 records .reference/zero-baselines
#            from whim-vim.c -- a TRACKED input, so the input to the
#            self-recording is external even though the recording is internal
#     all    boundary and product comparisons are real throughout
#
# THREE STEPS THE OBVIOUS SEQUENCE OMITS, each of which cost a run to find.
#
#   `whim-record` and `zero-record`.  `slim-repass` records its own boundaries
#   (as ADVISORY, because slim can still fall through to an agent); whim and
#   zero deliberately do not, whim.mk saying a boundary is "recorded only after
#   a run that built, swept to silence and showed exactly the declared delta".
#   Without them `whim-verify` and `zero-verify` refuse -- every stage
#   UNRECORDED, exit 1, one second.  That is a correct refusal of a real
#   mistake and it is why they are here.
#
#   NO_AGENT=1.  zero.mk sets it per unit and slim is unguarded, so a slim
#   phase whose program refused would fall through to tier 1 and spend a
#   `claude -p` run -- and an agent firing inside a measurement makes the
#   measurement partly about the agent.
#
#   `produced()`.  A product the pass never wrote is "clean" in every sense git
#   can see, and that is indistinguishable from produced-and-matched.  Found by
#   dry-running the report mid-pass, where it said `zero-vim.c clean` about a
#   file nothing had touched.  The evidence is that the product must be at
#   least as new as the last boundary its pipeline recorded, because
#   `<pipe>-pass` extracts it from that boundary's tar.
#
# `command grep` throughout, never bare `grep`: in an interactive Claude Code
# shell `grep` is a function dispatching to ugrep, and the two differ on
# metacharacter-heavy patterns.  A count is a fact about a BINARY as much as
# about a file.
#
# Nothing here is part of the build.  tools/gocmp/ is named by no makefile and
# no phase program, so it enters no implementation key.
set -u

d=${1:?usage: sh tools/gocmp/clonecheck.sh <scratch-dir> [clone|pass|fix|settle|cross...]}
shift
steps=${*:-clone pass fix settle cross}
here=$PWD
clone=$d/clone
REMOTE=https://github.com/arbace/slim-vim.git

run_clone() {
    rm -rf "$clone"
    git clone -q "$REMOTE" "$clone" || return 1
    printf '  clone        %s at %s\n' "$clone" \
        "$(git -C "$clone" rev-parse --short HEAD)"
    printf '  starting     .reference: %s   .build-*: %s\n' \
        "$(ls -a "$clone" | command grep -c '^\.reference$')" \
        "$(ls -a "$clone" | command grep -c '^\.build-')"
}

run_pass() {
    ( cd "$clone" && NO_AGENT=1 make slim-repass && NO_AGENT=1 make whim-repass \
        && NO_AGENT=1 make zero-repass ) 2>&1 | tail -4
}

# The two record steps, then the verifies they enable.
run_fix() {
    for t in whim-record whim-verify zero-record zero-verify; do
        printf '\n  === %s ===\n' "$t"
        ( cd "$clone" && NO_AGENT=1 make "$t" ) 2>&1 | tail -6
    done
}

produced() {   # produced <file> <build-dir> <tag>
    last=$(ls "$clone/$2"/$3*.sha256 2>/dev/null |
           sed "s|.*/$3||;s|\.sha256||" | sort -n | tail -1)
    [ -n "$last" ] || { echo "no boundary recorded"; return; }
    b=$clone/$2/$3$last.sha256
    if [ "$clone/$1" -nt "$b" ] || [ ! "$b" -nt "$clone/$1" ]; then
        echo "written $(stat -c%y "$clone/$1" | cut -d. -f1), boundary $3$last $(stat -c%y "$b" | cut -d. -f1)"
    else
        echo "NOT PRODUCED -- older than $3$last, so the pass never copied it out"
    fi
}

run_settle() {
    echo "  === git status --porcelain (empty = every product is what was shipped) ==="
    ( cd "$clone" && git status --porcelain ) | sed 's/^/    /'
    echo "  === the chain, in order ==="
    for f in slim-vim.c whim-vim.c zero-vim.c; do
        if ( cd "$clone" && git diff --quiet -- "$f" ); then
            printf '    %-12s clean\n' "$f"
        else
            printf '    %-12s DIFFERS %s\n' "$f" \
                "$( cd "$clone" && git diff --numstat -- "$f" | awk '{printf "+%s -%s", $1, $2}')"
        fi
    done
    echo "  === was each actually WRITTEN, or merely untouched? ==="
    printf '    %-12s %s\n' slim-vim.c "$(produced slim-vim.c .build-slim p)"
    printf '    %-12s %s\n' whim-vim.c "$(produced whim-vim.c .build-whim q)"
    printf '    %-12s %s\n' zero-vim.c "$(produced zero-vim.c .build-zero r)"
}

# The independent record: the same boundary digests produced separately here.
run_cross() {
    for pipe in slim whim zero; do
        case $pipe in slim) t=p;; whim) t=q;; zero) t=r;; esac
        same=0; diffr=0; only=0
        for f in "$clone/.build-$pipe"/$t*.sha256; do
            [ -f "$f" ] || continue
            n=$(basename "$f")
            if [ ! -f "$here/.build-$pipe/$n" ]; then only=$((only + 1)); continue; fi
            if cmp -s "$f" "$here/.build-$pipe/$n"; then same=$((same + 1))
            else
                diffr=$((diffr + 1))
                printf '      %-14s clone %s   here %s\n' "${n%.sha256}" \
                    "$(cut -c1-12 < "$f")" "$(cut -c1-12 < "$here/.build-$pipe/$n")"
            fi
        done
        printf '    %-5s %s identical, %s DIFFER, %s not here\n' "$pipe" "$same" "$diffr" "$only"
    done
}

for s in $steps; do
    printf '\n=== %s ===\n' "$s"
    start=$(date +%s)
    "run_$s" || echo "  $s FAILED"
    printf '    [%ss]\n' "$(( $(date +%s) - start ))"
done
