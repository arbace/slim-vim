#!/bin/sh
# Bring the documents back in line with a tree that actually changed.
#
# Usage: tools/agentdocs.sh
#
# Run only when there is something to describe.  A pass that reproduced the
# previous slim-vim.c byte for byte has, by definition, made no statement in
# CLAUDE.md or SLIM-GOAL.md wrong, and the twelve minutes an agent spends rewriting
# them are twelve minutes spent confirming that nothing happened.  The caller
# decides; this script assumes the decision was yes.
set -eu
set -o pipefail

PROMPT=$(cat <<'PREAMBLE'
A pass has just produced a slim-vim.c that differs from the one committed here, and
you are updating the documents to match.  Unattended: never ask a question,
decide and proceed.

What is in front of you:

- `git diff -- slim-vim.c` is what changed, and `upstream.sha` against its committed
  value is why.  Establish what upstream patch caused it before writing a word;
  a difference is a result, not a failure, and the commit has to name its
  cause.
- `.build/p*.sha256` are this pass's phase boundaries and `.reference/phases/`
  holds what the last one recorded.  The first boundary that differs is where
  the change entered, and that is worth stating.
- `tools/verify.sh .reference/baselines --enums` and `tools/refcheck.sh` are the
  checks.  Run them.  If a behaviour baseline moved, say which case and why,
  and do not re-record it unless the move was intended -- a re-recorded
  baseline agrees with whatever produced it.

What to do:

1. Edit CLAUDE.md so it describes the tree as it now is.  Edit the sentences
   this change made wrong; do not append a section that disagrees with an
   earlier one.  Its figures are measurements -- re-measure them, and say what
   you measured.  The patch level comes from version.c, not from memory.
2. Edit SLIM-GOAL.md only where the process itself turned out to be wrong, missing
   or misordered.  It is the process, not a changelog.
3. Leave README.md alone unless something in it is now false.  It carries no
   figures on purpose.
4. Commit, with a `type: summary` subject and prose saying why the change
   happened, what was measured, how it was verified, and what was deliberately
   left out.

Do not touch the Makefile, pass.mk or tools/.  They are the harness that
invoked you.
PREAMBLE
)

export PROMPT
IS_SANDBOX=1 SLIM_VIM_PASS=docs \
    claude -p "$PROMPT" \
        --model opus \
        --dangerously-skip-permissions \
        --output-format stream-json --verbose \
    2>&1 | tee .build/docs.log
