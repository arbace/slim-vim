#!/bin/sh
# The whole pass, by one agent, from SLIM-GOAL.md.  The reference path.
#
# Usage: tools/agentpass.sh <work-dir>      (run from the repository root)
#
# This is where this process was before it was partitioned, and it is kept
# deliberately.  The phase programs are faster by a factor of twenty and they
# are also BRITTLE IN A WAY AN AGENT IS NOT: each was written against one
# upstream, and a patch that no longer applies, a pattern that stops matching
# or a count that comes out wrong will stop them.  When upstream moves, this
# path is the one that can still think -- it reads the error, understands what
# changed, and carries the intent forward.
#
# So the two are a pair, and the comparison is the point:
#
#   make          the fast path.  Ten phases, seven of them programs.
#   make refpass  this one.  One agent, no phase boundaries, ~70 minutes.
#   make compare  the two slim-vim.c files against each other.
#
# When the fast path fails and this one succeeds, the difference between the
# two answers is the specification for repairing the fast path.  When both
# succeed and the answers differ, one of them is wrong and the boundary digests
# say where to look.
#
# It writes into the work directory only.  In particular it does NOT put slim-vim.c
# at the repository root: the whole value here is having a second answer to
# compare against the committed one, and an agent that overwrote it would
# destroy the comparison it was run for.
set -eu
set -o pipefail

work=${1:?usage: agentpass.sh <work-dir>}
mkdir -p .build/ref

PROMPT=$(cat <<PREAMBLE
You are running one whole pass of the process in SLIM-GOAL.md, unattended.  Nobody
is watching: never ask a question, never wait for input, never stop to propose
a plan.  Decide and proceed.

Read SLIM-GOAL.md in full before starting, then CLAUDE.md.  SLIM-GOAL.md is the process;
CLAUDE.md describes the tree it produces.  The ordering of the phases is the
point.

You are the REFERENCE PATH.  Most of this process now exists as programs in
tools/ -- tools/phase0.sh, phase1.sh and so on -- and a makefile runs them.
You are not running those and you are not bound by them.  You are here because
they cannot think: they were written against one upstream, and when upstream
moves, a patch stops applying or a count comes out wrong and they stop.  You
work the phases out from SLIM-GOAL.md as written and carry their intent forward onto
whatever upstream now is.  If you find that a phase's intent no longer matches
what SLIM-GOAL.md literally says, follow the intent and say so clearly at the end --
that difference is the most valuable thing you will produce.

You may READ tools/ freely; the harnesses are yours to use and the phase
programs are worth reading when you want to know what the fast path believes.
Run whichever tools help.

Five things this invocation fixes:

1. $work/ is ALREADY CLONED for you, at the branch the makefile pins, with its
   .git already deleted.  Do not clone it, do not fetch, do not re-point it,
   and never write to that remote -- it is read-only input.  Do not delete
   $work/ either; the makefile does that when you exit 0.

2. Write ONLY inside $work/.  Not the root Makefile, not slim.mk, not tools/,
   not SLIM-GOAL.md, not CLAUDE.md, not .reference/, not .build/ -- and above all
   NOT the slim-vim.c at the repository root.  That file is the fast path's answer
   and this run exists to be compared against it; overwriting it destroys the
   comparison.  Leave your slim-vim.c and LICENSE in $work/ and the makefile will
   collect them.

3. Do not commit, and do not run git outside $work/.

4. Keep .build/ref/PROGRESS.md as you work -- one section per phase, appended,
   never rewritten.  Record elapsed time per phase, what you did, every place
   SLIM-GOAL.md turned out to be wrong or incomplete, and -- most valuable of all --
   anything upstream has changed that a program written against the previous
   upstream would have got wrong.  Be specific and quantitative.

5. At the end, print: total elapsed, the per-phase breakdown, whether the
   verification passed, and a plain statement of anything that differed from
   what SLIM-GOAL.md predicts.

Verify as SLIM-GOAL.md says: tools/verify.sh against .reference/baselines if that
directory exists, the -Wall -Wextra sweep printing nothing at all,
tools/create_cmdidxs.py --check, and every Phase 7 canonicaliser reporting zero
at the end.  Do not run tools/refcheck.sh -- it compares against the repository
root's slim-vim.c, which is not yours to be judged against here; the makefile does
that comparison afterwards.
PREAMBLE
)

export PROMPT
IS_SANDBOX=1 SLIM_VIM_PASS=refpass \
    claude -p "$PROMPT" \
        --model opus \
        --dangerously-skip-permissions \
        --output-format stream-json --verbose \
    2>&1 | tee .build/ref/pass.log
