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

WHERE THINGS ARE.  This is the orientation; do not go and rediscover it.  The
first pass to run phases separately spent four to five minutes per phase on
exactly that -- ls, the first 120 lines of GOAL.md, cat pass.mk, cat
tools/README.md, reading the source of tools it was about to run -- and turned
a 47-second phase into seven minutes.

  cwd                  the repository root.  Stay in it; use paths.
  upstream/            the tree you transform.  Before phase 2 the C sources are
                       in upstream/src with proto/*.pro and objects/ beside
                       them; phase 2 flattens it, and from then on everything
                       sits directly in upstream/.
  building it          make -C upstream/src -j\$(nproc)   before phase 3
                       make -C upstream -j\$(nproc)       from phase 3 on
                       NEVER cd into it and run make: the repository root has a
                       makefile whose default target is also 'vim', so a cd
                       that does not stick rebuilds THAT and reports success
                       while the tree under test is untouched.
  tools/               run from the root, with paths into upstream/.  They take
                       file lists on the command line and do nothing at import.
  .reference/baselines what the Phase 1 binary did, recorded.  behaviour.py,
                       exsweep.py, ptycheck.py and termcheck.py compare to it.
  .build/pN.tar        the tree each earlier phase left, if you need to look.

THE TOOLS.  All of them exist.  Do not read their source before running them,
and do not write your own version of one:

  cutil.py         blank literals or comments preserving offsets, match braces
                   and parens, per-character depth, split on a top-level
                   operator, find and delete a function by name
  splice.py        backslash continuations      untab.py       tabs at 8-col stops
  decomment.py     a comment becomes one space plus the newlines it spanned
  keepset.py       what the compiler opens      dropsrc.py     a source and its mentions
  cond.py          conditional groups as a tree macros.py      parse the #defines
  plant.py         mark every branch            resolve.py     keep the ones that survive
  merge.py         67 files into one            toenum.py      #define to enumerator
  expand.py        expand a macro at its uses   reblank.py     recover paragraphing
  canon.sh         the seven canonicalisers to a joint fixpoint -- blankruns,
                   joinparens, splitheads, brace, onestmt, onedecl, forcomma
  deadsweep.py     delete what -Wall names      typereach.py   dead type definitions
  create_cmdidxs.py  the command lookup table, --check or --update
  build.sh         a reproducible build for tier 1 (pins SOURCE_DATE_EPOCH)
  tier2.py         compare two preprocessed files as token streams
  enumvals.sh      every enumerator and its value, from DWARF
  verify.sh refcheck.sh behaviour.py exsweep.py ptycheck.py termcheck.py

VERIFICATION.  Pick the cheapest that applies.  Pure formatting: the binary is
byte-identical, via build.sh, which pins the timestamp __DATE__ would otherwise
move.  Token-preserving: the token stream is identical, via tier2.py -- and
check the warnings too, since a token-neutral change can still be wrong.
Anything else: the harnesses against .reference/baselines.  Blank lines are
what no tier can see; count them when you touch paragraphing.

If you need a program that does not exist, write it into .build/newtools/ and
say so in your final output, so it can be kept.  Two tools written into /tmp by
an earlier phase were nearly lost with it.

The phase text below is complete and authoritative.  GOAL.md is 1,400 lines
describing ten phases, nine of which are not yours -- open it only if the phase
text names a section you actually need, and never read it front to back.  Its
numbers are measurements from previous passes: reproduce them where they are
stated, and say so when yours differ.

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
