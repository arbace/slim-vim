# One product, and the process that produces it.
#
# This makefile is not derived from upstream and is not a product of a pass --
# it is part of the seed, alongside .gitignore, README.md, CLAUDE.md, GOAL.md
# and tools/, and it is what drives a pass.  A pass must never write over it.
#
# vim.c depends on upstream, which is a remote, so the dependency is the branch
# head at github.com/arbace/vim -- consulted on every make, whether it has
# moved or not.  It cannot be a timestamp: git clone writes every file at
# checkout time in arbitrary order, so a stamp file landing a second after
# vim.c would fire a multi-hour pass on a tree that is exactly right.  What
# decides is content -- the sha recorded in upstream.sha, which is written only
# after a pass has succeeded, so a failed pass leaves the record alone and the
# next make retries.
#
# The pass itself is one claude -p invocation carrying the prompt below.  That
# is a baseline, not the destination: the process is meant to move piece by
# piece into deterministic bash and python under tools/, partitioned into
# subtasks this makefile drives, leaving the agent only where no concise
# algorithm exists yet.  PROGRESS.md is what the pass writes to inform that.
#
# The build is -O0: this tree is rebuilt far more often than the editor it
# produces is used.  _FORTIFY_SOURCE went with -O2, its checks needing sizes the
# optimiser computes, and there is no -g -- debug info records a line number for
# everything, which would make a formatting change move the binary and cost the
# cheapest verification there is.
#
# -static -s: nothing to resolve at run time and no symbol table.  gcc defaults
# to PIE here, so the result is a static-PIE and ASLR still applies -- readelf
# -l for INTERP and readelf -d for NEEDED are the check, never ldd, which
# prints a musl line for a static-PIE that is not a dependency.
#
# One gcc invocation.  vim.c includes no local header, so it depends on nothing
# but itself and the upstream it was produced from; there is no dependency
# block and no object phase, and "make clean && make" is a real from-scratch
# rebuild.

CC      = gcc
CFLAGS  = -O0
LDFLAGS = -static -s

UPSTREAM_URL    = https://github.com/arbace/vim
UPSTREAM_BRANCH = regexp-delimiter-atoms

CLAUDE       = claude
CLAUDE_FLAGS = --model opus --dangerously-skip-permissions \
               --output-format stream-json --verbose
PASS_LOG     = pass.log

define PASS_PROMPT
You are running one pass of the process in GOAL.md, in this repository,
unattended.  Nobody is watching: never ask a question, never wait for input,
and never stop to propose a plan.  Decide and proceed.

Read GOAL.md in full before starting, then CLAUDE.md.  GOAL.md is the process;
CLAUDE.md describes the tree the process produces.  The ordering of the phases
is the point.

Six things this invocation fixes, which override GOAL.md wherever they differ:

1. upstream/ is ALREADY CLONED for you, at the branch this makefile pins, with
   its .git already deleted.  Do not clone it, do not fetch, do not re-point
   it, and never write to that remote -- it is read-only input.  Do not delete
   upstream/ at the end either; the makefile removes it when you exit 0.

2. The Makefile at the repository root is the SEED THAT INVOKED YOU.  Never
   edit it, never move a file onto it, never delete it.  Phase 3 still writes a
   small makefile INSIDE upstream/ -- that one is scaffolding for phases 3
   through 8 and dies with upstream/.  Nothing from upstream/ overwrites a file
   at the root except the two products below.

3. The products a pass moves to the repository root are exactly two: vim.c and
   LICENSE.  The Makefile is no longer one of them.

4. upstream.sha at the root records the commit vim.c was produced from.  The
   makefile writes it after you exit 0.  Do not write it yourself.

5. Keep PROGRESS.md, described below.  It is the main deliverable of this run
   after vim.c itself.

6. Record wall-clock time.  Note the time you start each phase and the time it
   ends, and put the elapsed figure in PROGRESS.md.  Total elapsed time for the
   pass matters as much as any other measurement here.

Otherwise run Phases 0 through 9 as written, with the ground rules as written:
build the verification before the first change, one commit per phase with prose
saying why and how it was checked, reset and replay rather than patching a
cascade, keep a copy of the file before every pass, and re-run every Phase 7
canonicaliser at the end and require each to report zero.  Verify with
tools/verify.sh against .reference/baselines if that directory exists, with the
-Wall -Wextra sweep printing nothing at all, with tools/create_cmdidxs.py
--check, and end by running tools/refcheck.sh.  Update CLAUDE.md as you go,
phase by phase, editing the sentences your work made wrong rather than
appending -- that is GOAL.md rule 5 and it is not optional.

PROGRESS.md -- what this run is really for
==========================================

Write PROGRESS.md incrementally, appending a section as each phase ends.  Never
rewrite what you already wrote there; it is a log, not a summary.  It is
gitignored and transient: its insights get folded into GOAL.md, CLAUDE.md and
tools/ afterwards and then it is deleted.  Do not commit it.

The reader is the next iteration of this process, and that reader has one
goal: to replace as much of this pass as possible with DETERMINISTIC
ARTEFACTS -- bash and python programs in tools/, partitioned into subtasks with
explicit inputs and outputs, wired together by dependencies in this makefile --
leaving a claude -p invocation only where no concise algorithm exists yet.
Today the whole transformation is agent work over tool-use primitives.  That is
the baseline being measured, not the destination.

So for every phase record, concretely:

- Elapsed wall-clock time, and where inside the phase it actually went.  Name
  the steps that dominated.
- What was already mechanical: which tools/ program did it, run how, and was it
  a no-op or did it change something.
- What needed judgement, one entry per decision.  For each: what the decision
  was, what information it needed, and whether it could become a deterministic
  program.  If it could, say what that program would take as input and emit as
  output.  If it could not, say exactly what blocks it -- that is the more
  valuable answer.
- The smallest partition of the phase into subtasks that a makefile could drive:
  what each subtask consumes, what it produces, and which subtasks are
  independent of each other and could run in parallel.
- Anything reread or recomputed that a cached artefact would have saved.
- Dead ends, surprises, and every place GOAL.md turned out to be wrong,
  missing, or in the wrong order.  An approach that failed and why is worth
  more here than a clean account of what worked.

Be specific and quantitative.  "Phase 4 was slow" is worthless; "splice.py over
67 files took 40 s, and the 20 minutes before it went to reading each file to
decide which needed it, which a grep answers" is what this is for.

When everything is done, print a short summary: total elapsed, the per-phase
breakdown, whether refcheck.sh and verify.sh passed, and the three changes that
would most reduce the next run's wall-clock time.
endef
export PASS_PROMPT

vim: vim.c
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $<

# A phony prerequisite, so the freshness question is asked on every make; the
# answer is decided inside the recipe by content, never by a timestamp.  When
# the recipe leaves vim.c alone, make re-stats it, sees it unmoved, and does
# not relink vim either.
#
# IS_SANDBOX=1 is not decoration.  claude refuses the permission flag outright
# when it is running as root, and this tree is built in a container where root
# is the only user there is; without it the pass dies before it starts.
vim.c: force
	@set -e; set -o pipefail; \
	if [ -n "$$SLIM_VIM_PASS" ]; then \
	    echo "  upstream     not probed -- already inside a pass"; \
	    exit 0; \
	fi; \
	live=`GIT_TERMINAL_PROMPT=0 timeout 60 git ls-remote $(UPSTREAM_URL) $(UPSTREAM_BRANCH) 2>/dev/null | cut -f1` || true; \
	if [ -z "$$live" ]; then \
	    echo "  upstream     UNREACHABLE -- building the committed vim.c"; \
	    exit 0; \
	fi; \
	if [ -f $@ ] && [ "$$live" = "`cat upstream.sha 2>/dev/null`" ]; then \
	    echo "  upstream     $$live -- vim.c is current"; \
	    exit 0; \
	fi; \
	echo "  upstream     $$live -- vim.c must be produced"; \
	rm -rf upstream; \
	git clone --quiet --branch $(UPSTREAM_BRANCH) --depth 1 $(UPSTREAM_URL) upstream; \
	rm -rf upstream/.git; \
	echo "  clone        `find upstream -type f | wc -l | tr -d ' '` files, .git removed"; \
	start=`date +%s`; \
	echo "  pass         started `date -Is`, logging to $(PASS_LOG)"; \
	SLIM_VIM_PASS=$$live IS_SANDBOX=1 $(CLAUDE) -p "$$PASS_PROMPT" $(CLAUDE_FLAGS) 2>&1 | tee $(PASS_LOG); \
	now=`date +%s`; elapsed=$$((now - start)); \
	echo "  pass         finished `date -Is`, $$(($$elapsed / 3600))h $$((($$elapsed % 3600) / 60))m $$(($$elapsed % 60))s"; \
	test -f $@; \
	rm -rf upstream; \
	echo "$$live" > upstream.sha

clean:
	rm -f vim

force: ;

.PHONY: clean force
