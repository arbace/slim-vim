#!/bin/sh
# Run ONE phase of GOAL.md with an agent, and nothing else.
#
# Usage: tools/agentphase.sh <phase> <workdir>
#
# This is the fallback for a phase that has no tools/phase<N>.sh yet.  Every
# phase that grows one stops coming through here, and the day none of them does
# is the day the pass is deterministic.
#
# The prompt is assembled invariant-part-first, phase-part-last, deliberately.
# The prompt cache is content-addressed on a prefix: ten phase agents whose
# first N tokens are byte-identical share that prefix, the first paying to
# write it and the rest reading it at a tenth of the price.  Putting the phase
# text at the front would make ten unrelated prefixes out of what is really one.
set -eu
set -o pipefail         # or the tee below reports its own success as claude's

phase=${1:?usage: agentphase.sh <phase> <workdir>}
work=${2:?}

goal=GOAL.md
[ -f "$goal" ] || { echo "agentphase: no $goal here"; exit 1; }

# The phase's own section: from its heading to the next top-level heading.
section=$(awk -v p="^## Phase $phase " '
    $0 ~ p        { inside = 1 }
    inside && /^## / && $0 !~ p { exit }
    inside        { print }
' "$goal")

[ -n "$section" ] || { echo "agentphase: no '## Phase $phase' in $goal"; exit 1; }

PROMPT=$(cat <<PREAMBLE
You are running exactly one phase of the process in GOAL.md, unattended.
Nobody is watching: never ask a question, never wait for input, never stop to
propose a plan.  Decide and proceed.

The repository root is the working directory.  The tree being transformed is
in $work/ and is the only thing you may modify.

Rules, all of them absolute:

- Do THIS PHASE ONLY.  Do not start the next one, do not finish the previous
  one, and do not "while I am here" anything.  A harness runs the phases; you
  are one step of it.
- Do not modify anything outside $work/.  Not the root Makefile, not tools/,
  not GOAL.md, not CLAUDE.md, not .reference/, not .build/.  They are the
  harness that invoked you.
- Do not commit, and do not run git at all outside $work/.  The harness records
  this phase's boundary as a content digest, which is a better record than an
  empty commit and is what the next run is checked against.
- Do not delete $work/ or clone anything.  It is handed to you at exactly the
  state this phase's input should be.
- If the phase cannot be completed, stop and say precisely what blocked it.  Do
  not work around it and do not leave the tree half-transformed on purpose --
  the harness can restore the input and retry, and a clean failure is worth
  more than a partial success it cannot tell apart from a whole one.

Read GOAL.md's ground rules and verification tiers if you need them; the phase
text below is authoritative for what to do, and the rest of that file is
context.  Its numbers are measurements from previous passes: reproduce them
where they are stated, and say so when yours differ.

When you are done, print one line per thing you changed and the measurements
the phase text asks for.  Nothing else.

===================== THE PHASE YOU ARE RUNNING =====================

$section
PREAMBLE
)

export PROMPT
IS_SANDBOX=1 SLIM_VIM_PASS=phase$phase \
    claude -p "$PROMPT" \
        --model opus \
        --dangerously-skip-permissions \
        --output-format stream-json --verbose \
    2>&1 | tee ".build/phase$phase.log"
