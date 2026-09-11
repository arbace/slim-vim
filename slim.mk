# The pass, partitioned at phase boundaries.
#
# Included by the root Makefile.  Ten phases, each a target whose prerequisite
# is the previous phase's boundary, so make -- not an agent, and not a
# document -- is what sequences them.
#
# Every phase is a pure function of its input tree.  The recipe restores the
# previous boundary into $(SLIMWORK) before running, so a phase cannot inherit
# anything from a run that went wrong, and re-running one phase means exactly
# that rather than "re-running one phase and whatever the last attempt left".
#
# A boundary is a content digest -- a sha256 over a sorted listing of every
# file's own sha256 -- and the tar beside it is a restore point.  Three things
# fall out of that and each is worth more than it costs:
#
#   * Restartable.  A failure in phase 9 costs phase 9, not the hour before it.
#   * Cheap to develop against.  Converting phase 4 from agent work to a
#     program means restoring p3, running the program, and comparing p4.  That
#     is seconds, and it needs no agent and no full pass.
#   * Attributable.  The end-to-end check says the editor changed; a boundary
#     digest says where.
#
# The phase commits this replaces carried no tracked change at all -- $(SLIMWORK)
# is gitignored, so nine of the ten were empty commits whose whole content was
# their message.  A digest is a better record, and it is checkable.

SLIMWORK    = upstream
SLIMBUILD   = .build-slim
SLIMORACLE  = .reference/slim-phases

SLIMPHASES  = 0 1 2 3 4 5 6 7 8 9

# --- the chain ------------------------------------------------------------
# p0 hangs off the clone; pN off p(N-1).  Written out rather than computed:
# ten lines that say what they mean beat a $(eval) that has to be run to be
# read.
$(SLIMBUILD)/p0.sha256: $(SLIMBUILD)/input.sha256
$(SLIMBUILD)/p1.sha256: $(SLIMBUILD)/p0.sha256
$(SLIMBUILD)/p2.sha256: $(SLIMBUILD)/p1.sha256
$(SLIMBUILD)/p3.sha256: $(SLIMBUILD)/p2.sha256
$(SLIMBUILD)/p4.sha256: $(SLIMBUILD)/p3.sha256
$(SLIMBUILD)/p5.sha256: $(SLIMBUILD)/p4.sha256
$(SLIMBUILD)/p6.sha256: $(SLIMBUILD)/p5.sha256
$(SLIMBUILD)/p7.sha256: $(SLIMBUILD)/p6.sha256
$(SLIMBUILD)/p8.sha256: $(SLIMBUILD)/p7.sha256
$(SLIMBUILD)/p9.sha256: $(SLIMBUILD)/p8.sha256

# One recipe for all ten.  $* is the phase number, and the input tar is the
# prerequisite's name with .sha256 swapped for .tar.
$(SLIMBUILD)/p%.sha256:
	@tools/restore.sh $(patsubst %.sha256,%.tar,$<) $(SLIMWORK)
	@tools/memo.sh $* $(SLIMWORK) $(SLIMBUILD)
	@tools/oracle.sh $* $(SLIMBUILD) $(SLIMORACLE) | sed 's/^  /      /'

# --- the input ------------------------------------------------------------
# The clone, snapshotted before anything touches it.  The root Makefile makes
# $(SLIMWORK) and then asks for this.
$(SLIMBUILD)/input.sha256:
	@test -d $(SLIMWORK) || { echo "  pass         no $(SLIMWORK)/ -- the Makefile clones it"; exit 1; }
	@mkdir -p $(SLIMBUILD)
	@tools/snapshot.sh $(SLIMWORK) $(SLIMBUILD)/input.tar $(SLIMBUILD)/input.sha256

# --- the clone ------------------------------------------------------------
# Here rather than in the root makefile's recipe because two things need it:
# an ordinary pass, and `make slim-repass`.  A second copy of these four lines is a
# second place for the .git deletion to be forgotten.
.PHONY: slim-clone
slim-clone:
	@rm -rf $(SLIMWORK) $(SLIMBUILD)
	@mkdir -p $(SLIMBUILD)
	@date +%s > $(SLIMBUILD)/pass-start
	@printf '\n\033[1m  slim-vim\033[0m  a pass: ten phases, upstream to slim-vim.c\n'
	@printf '  %-12s %s\n' "started" "`date -Is`"
	@git clone --quiet --branch $(UPSTREAM_BRANCH) --depth 1 $(UPSTREAM_URL) $(SLIMWORK)
	@rm -rf $(SLIMWORK)/.git
	@echo "  clone        `find $(SLIMWORK) -type f | wc -l | tr -d ' '` files, .git removed"

# Force a pass on a tree whose upstream.sha already matches -- which is what
# every run during development is, since the point is to reproduce the same
# slim-vim.c by different means.  It deliberately does not write upstream.sha: only
# the real dependency does that.
.PHONY: slim-repass
slim-repass: slim-clone
	@start=`date +%s`; \
	$(MAKE) --no-print-directory SLIM_VIM_PASS=forced slim-pass; \
	$(MAKE) --no-print-directory slim-record; \
	$(MAKE) --no-print-directory slim-times; \
	now=`date +%s`; echo "  repass       $$((now - start))s total"

# --- the reference path ---------------------------------------------------
# Where this process was before it was partitioned, kept on purpose.  The phase
# programs are twenty times faster and brittle in a way an agent is not: each
# was written against one upstream, and a patch that stops applying or a count
# that comes out wrong will stop it.  When upstream moves, this is the path
# that can still think.
#
# It uses a work directory and an output directory of its own, so it never
# touches the fast path's boundaries -- and it is forbidden to write the
# repository's slim-vim.c, because having a second answer to compare against the
# committed one is the entire point.
SLIMREFWORK = upstream-ref

# The whole workflow, when upstream has actually moved: try the fast path, and
# if it fails, fall back to the one that can think -- then have it repair the
# fast path, so the next move costs less than this one did.
#
# The order is the point.  The programs are what you want to succeed, because
# they are twenty times faster and their answer is checkable at every phase
# boundary.  The agent is what you want when they fail, because a patch that no
# longer applies is a question about upstream, not about this repository.  And
# a failure that is merely absorbed teaches nothing: the repair step is what
# turns one upstream change into a permanent improvement.
.PHONY: slim-passorref
slim-passorref:
	@if $(MAKE) --no-print-directory slim-pass; then \
	    echo "  workflow     the fast path produced slim-vim.c"; \
	else \
	    echo "  workflow     the fast path FAILED -- falling back to the agent"; \
	    $(MAKE) --no-print-directory slim-refpass; \
	    cp $(SLIMBUILD)/ref/vim.c slim-vim.c; \
	    cp $(SLIMBUILD)/ref/LICENSE LICENSE; \
	    echo "  workflow     the reference path produced slim-vim.c; repairing the fast path"; \
	    tools/repair.sh; \
	fi

.PHONY: slim-refpass
slim-refpass:
	@rm -rf $(SLIMREFWORK) $(SLIMBUILD)/ref
	@mkdir -p $(SLIMBUILD)/ref
	@git clone --quiet --branch $(UPSTREAM_BRANCH) --depth 1 $(UPSTREAM_URL) $(SLIMREFWORK)
	@rm -rf $(SLIMREFWORK)/.git
	@echo "  clone        `find $(SLIMREFWORK) -type f | wc -l | tr -d ' '` files, .git removed"
	@start=`date +%s`; \
	 tools/agentpass.sh $(SLIMREFWORK); \
	 now=`date +%s`; echo "  refpass      $$((now - start))s"
	@cp $(SLIMREFWORK)/vim.c $(SLIMBUILD)/ref/vim.c
	@cp $(SLIMREFWORK)/LICENSE $(SLIMBUILD)/ref/LICENSE
	@rm -rf $(SLIMREFWORK)
	@$(MAKE) --no-print-directory slim-compare

# The two answers, against each other.  A difference is a result: either the
# fast path has drifted, or upstream moved and only the agent noticed.
.PHONY: slim-compare
slim-compare:
	@test -f $(SLIMBUILD)/ref/vim.c || { echo "  compare      no reference answer -- run make slim-refpass"; exit 1; }
	@if cmp -s slim-vim.c $(SLIMBUILD)/ref/vim.c; then \
	    echo "  compare      identical -- both paths produced the same slim-vim.c"; \
	else \
	    echo "  compare      DIFFERS -- fast path $$(grep -c '' slim-vim.c) lines, reference $$(grep -c '' $(SLIMBUILD)/ref/vim.c)"; \
	    echo "               +$$(diff slim-vim.c $(SLIMBUILD)/ref/vim.c | grep -c '^>') -$$(diff slim-vim.c $(SLIMBUILD)/ref/vim.c | grep -c '^<') against the committed one"; \
	    echo "               diff slim-vim.c $(SLIMBUILD)/ref/vim.c   -- and read $(SLIMBUILD)/ref/PROGRESS.md"; \
	fi

# --- what a pass is -------------------------------------------------------
.PHONY: slim-pass
slim-pass: $(SLIMBUILD)/p9.sha256
	@cp $(SLIMWORK)/vim.c slim-vim.c
	@cp $(SLIMWORK)/LICENSE LICENSE
	@echo
	@printf '  %-12s %s lines, and LICENSE beside it\n' "slim-vim.c" \
	    "`grep -c '' slim-vim.c | sed -e :a -e 's/\(.*[0-9]\)\([0-9]\{3\}\)/\1,\2/;ta'`"
	@if [ -f $(SLIMBUILD)/pass-start ]; then 	    t=$$((`date +%s` - `cat $(SLIMBUILD)/pass-start`)); 	    printf '  %-12s %d phases in %dm%02ds -- make slim-times, make slim-residue\n' 	        "pass" 10 "$$((t / 60))" "$$((t % 60))"; 	 else 	    printf '  %-12s ten phases -- make slim-times, make slim-residue\n' "pass"; 	 fi

# The documents, and only when there is something to describe.  A pass that
# reproduced the previous slim-vim.c byte for byte made no sentence wrong, and an
# agent rewriting them anyway costs twelve minutes to confirm that nothing
# happened.  git is what knows: slim-vim.c is tracked, so "did this pass change the
# editor" is one command and not a judgement.
.PHONY: slim-docs
slim-docs:
	@if git diff --quiet -- slim-vim.c 2>/dev/null; then \
	    echo "  documents    slim-vim.c unchanged -- nothing to describe"; \
	else \
	    echo "  documents    slim-vim.c changed -- updating"; \
	    tools/agentdocs.sh; \
	fi

# Run, or re-run, one phase: make slim-phase-4
.PHONY: $(SLIMPHASES:%=slim-phase-%)
$(SLIMPHASES:%=slim-phase-%): slim-phase-%:
	@rm -f $(SLIMBUILD)/p$*.sha256
	@$(MAKE) --no-print-directory $(SLIMBUILD)/p$*.sha256

# Put $(SLIMWORK) back to a boundary and leave it there, for looking at:
# make slim-replay-3  gives the tree exactly as phase 4 receives it.
.PHONY: $(SLIMPHASES:%=slim-replay-%)
$(SLIMPHASES:%=slim-replay-%): slim-replay-%:
	@tools/restore.sh $(SLIMBUILD)/p$*.tar $(SLIMWORK)
	@echo "  replay       $(SLIMWORK)/ is the tree after phase $*"

# Promote an agent-recorded boundary to a hard check.  Only after a pass whose
# slim-vim.c and behaviour verified end to end: a boundary promoted from the run it
# is meant to check would agree with itself.
.PHONY: $(SLIMPHASES:%=slim-promote-%)
$(SLIMPHASES:%=slim-promote-%): slim-promote-%:
	@mkdir -p $(SLIMORACLE)
	@test -f $(SLIMBUILD)/p$*.sha256 || { echo "no $(SLIMBUILD)/p$*.sha256 to promote"; exit 1; }
	@cp $(SLIMBUILD)/p$*.sha256 $(SLIMORACLE)/p$*.sha256
	@cp $(SLIMBUILD)/p$*.sha256.files $(SLIMORACLE)/p$*.sha256.files
	@rm -f $(SLIMORACLE)/p$*.sha256.advisory $(SLIMORACLE)/p$*.sha256.advisory.files
	@echo "  promote      p$* is now a check: $$(cut -c1-12 $(SLIMORACLE)/p$*.sha256)"

# Record every boundary this run produced, as advisory.  What an agent pass
# leaves behind for the programs that will replace it.
.PHONY: slim-record
slim-record:
	@mkdir -p $(SLIMORACLE)
	@for p in $(SLIMPHASES); do \
	    [ -f $(SLIMBUILD)/p$$p.sha256 ] || continue; \
	    [ -f $(SLIMORACLE)/p$$p.sha256 ] && continue; \
	    cp $(SLIMBUILD)/p$$p.sha256 $(SLIMORACLE)/p$$p.sha256.advisory; \
	    cp $(SLIMBUILD)/p$$p.sha256.files $(SLIMORACLE)/p$$p.sha256.advisory.files; \
	    echo "  record       p$$p advisory: $$(cut -c1-12 $(SLIMBUILD)/p$$p.sha256)"; \
	done

# Where the time went, from what memo.sh recorded.
.PHONY: slim-times
slim-times:
	@total=0; for p in $(SLIMPHASES); do \
	    [ -f $(SLIMBUILD)/p$$p.seconds ] || continue; \
	    s=$$(cat $(SLIMBUILD)/p$$p.seconds); total=$$((total + s)); \
	    printf '  phase %-6s %4s s  by %s\n' "$$p" "$$s" "$$(cat $(SLIMBUILD)/p$$p.kind)"; \
	done; \
	printf '  %-12s %4s s  (%s m)\n' "total" "$$total" "$$((total / 60))"

# How much of each phase is still a recorded diff rather than a rule.
.PHONY: slim-residue
slim-residue:
	@tools/residue.sh slim

# What a pass would need on this machine, asked before it starts rather than
# ten minutes in.  The ordinary case -- sha matches, compile the committed
# slim-vim.c -- reaches none of it.
.PHONY: slim-preflight
slim-preflight:
	@tools/preflight.sh

.PHONY: slim-clean
slim-clean:
	rm -rf $(SLIMBUILD)

# The tier-3 cache is keyed by content, so it never goes stale -- but it does
# grow, and throwing it away costs only the time to recompute.
.PHONY: clean-cache
clean-cache:
	rm -rf .cache
