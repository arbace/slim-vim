#!/bin/sh
# Teach the fast path what the reference path just learned.
#
# Usage: tools/repair.sh          (run from the repository root)
#
# Called when the phase programs failed, the whole-pass agent succeeded, and
# there is now a correct slim-vim.c that the programs could not produce.  That gap
# is the most informative thing this process ever produces: something in
# upstream moved under a patch, a pattern or a count, and the agent worked out
# what to do about it.  Absorbing that silently would mean paying the same
# seventy minutes the next time.
#
# It is a narrow job on purpose.  The answer already exists -- in the failing
# phase's own error, in .build-slim/ref/PROGRESS.md, and in the boundary that the
# fast path did reach before it stopped.
set -eu
set -o pipefail

[ -f .build-slim/ref/vim.c ] || { echo "repair: no reference answer to learn from"; exit 1; }
mkdir -p .build-slim/repairs

PROMPT=$(cat <<'PREAMBLE'
The fast path failed and the reference path succeeded, and your job is to make
the fast path able to produce that same answer.  Unattended: decide and
proceed, never ask.

What is in front of you:

- slim.mk runs ten phases.  A phase is a program if tools/<pipeline><N>.sh exists
  and an agent otherwise.  One of the programs failed; its output says which
  and why.
- .build-slim/p*.sha256 are the boundaries the fast path reached before it stopped.
  The last one that exists is the last phase that worked.
- .build-slim/ref/vim.c is the correct answer, produced by the agent, and
  .build-slim/ref/PROGRESS.md is its account of what upstream changed and what it
  did about it.  Read that first; it is written for you.
- The repository's slim-vim.c is now that answer, already copied into place.

What to do:

1. Find the phase that failed and read its program.  The failure is nearly
   always one of three things: a hunk in tools/patches/ that no longer applies
   because upstream edited those lines; a pattern or count that upstream's
   change invalidated (a rename table missing a new collision, a number that is
   no longer 97 or 61 or 8); or a new construct the program has no rule for.
2. Fix the PROGRAM, not the symptom.  A hard-coded count that moved should
   become a computed one where that is possible, and a patch hunk that moved
   should be regenerated from the boundary diff -- restore the previous
   boundary with `make replay-<N-1>`, apply what the reference answer implies,
   and diff.  Prefer a rule the compiler or the tree can state over a constant.
3. If the change genuinely cannot be expressed as a program, say so plainly and
   leave that phase's tools/<pipeline><N>.sh deleted, so slim.mk falls back to an
   agent for that phase alone.  A phase that honestly needs judgement is a
   better outcome than a program that guesses.
4. Re-run the phase you fixed -- `make phase-<N>` -- and then the ones after
   it, and require the final slim-vim.c to match .build-slim/ref/vim.c byte for byte.
   `cmp slim-vim.c .build-slim/ref/vim.c` is the test.
5. Update SLIM-GOAL.md where the process description is now wrong, and write a note
   into .build-slim/repairs/ saying what upstream changed, what you changed, and how
   you verified it.

Do not edit slim-vim.c by hand, and do not weaken a check to make a phase pass.  A
check that was removed to get green is worse than the failure it hid.
PREAMBLE
)

export PROMPT
IS_SANDBOX=1 SLIM_VIM_PASS=repair \
    claude -p "$PROMPT" \
        --model opus \
        --dangerously-skip-permissions \
        --output-format stream-json --verbose \
    2>&1 | tee .build-slim/repairs/repair.log
