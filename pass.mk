# The pass, partitioned at phase boundaries.
#
# Included by the root Makefile.  Ten phases, each a target whose prerequisite
# is the previous phase's boundary, so make -- not an agent, and not a
# document -- is what sequences them.
#
# Every phase is a pure function of its input tree.  The recipe restores the
# previous boundary into $(WORK) before running, so a phase cannot inherit
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
# The phase commits this replaces carried no tracked change at all -- $(WORK)
# is gitignored, so nine of the ten were empty commits whose whole content was
# their message.  A digest is a better record, and it is checkable.

WORK    = upstream
BUILD   = .build
ORACLE  = .reference/phases

PHASES  = 0 1 2 3 4 5 6 7 8 9

# --- the chain ------------------------------------------------------------
# p0 hangs off the clone; pN off p(N-1).  Written out rather than computed:
# ten lines that say what they mean beat a $(eval) that has to be run to be
# read.
$(BUILD)/p0.sha256: $(BUILD)/input.sha256
$(BUILD)/p1.sha256: $(BUILD)/p0.sha256
$(BUILD)/p2.sha256: $(BUILD)/p1.sha256
$(BUILD)/p3.sha256: $(BUILD)/p2.sha256
$(BUILD)/p4.sha256: $(BUILD)/p3.sha256
$(BUILD)/p5.sha256: $(BUILD)/p4.sha256
$(BUILD)/p6.sha256: $(BUILD)/p5.sha256
$(BUILD)/p7.sha256: $(BUILD)/p6.sha256
$(BUILD)/p8.sha256: $(BUILD)/p7.sha256
$(BUILD)/p9.sha256: $(BUILD)/p8.sha256

# One recipe for all ten.  $* is the phase number, and the input tar is the
# prerequisite's name with .sha256 swapped for .tar.
$(BUILD)/p%.sha256:
	@tools/restore.sh $(patsubst %.sha256,%.tar,$<) $(WORK)
	@tools/memo.sh $* $(WORK) $(BUILD)
	@tools/oracle.sh $* $(BUILD) $(ORACLE)

# --- the input ------------------------------------------------------------
# The clone, snapshotted before anything touches it.  The root Makefile makes
# $(WORK) and then asks for this.
$(BUILD)/input.sha256:
	@test -d $(WORK) || { echo "  pass         no $(WORK)/ -- the Makefile clones it"; exit 1; }
	@mkdir -p $(BUILD)
	@tools/snapshot.sh $(WORK) $(BUILD)/input.tar $(BUILD)/input.sha256

# --- the clone ------------------------------------------------------------
# Here rather than in the root makefile's recipe because two things need it:
# an ordinary pass, and `make repass`.  A second copy of these four lines is a
# second place for the .git deletion to be forgotten.
.PHONY: clone
clone:
	@rm -rf $(WORK) $(BUILD)
	@git clone --quiet --branch $(UPSTREAM_BRANCH) --depth 1 $(UPSTREAM_URL) $(WORK)
	@rm -rf $(WORK)/.git
	@echo "  clone        `find $(WORK) -type f | wc -l | tr -d ' '` files, .git removed"

# Force a pass on a tree whose upstream.sha already matches -- which is what
# every run during development is, since the point is to reproduce the same
# vim.c by different means.  It deliberately does not write upstream.sha: only
# the real dependency does that.
.PHONY: repass
repass: clone
	@start=`date +%s`; \
	$(MAKE) --no-print-directory SLIM_VIM_PASS=forced pass; \
	$(MAKE) --no-print-directory record; \
	$(MAKE) --no-print-directory times; \
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
# repository's vim.c, because having a second answer to compare against the
# committed one is the entire point.
REFWORK = upstream-ref

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
.PHONY: passorref
passorref:
	@if $(MAKE) --no-print-directory pass; then \
	    echo "  workflow     the fast path produced vim.c"; \
	else \
	    echo "  workflow     the fast path FAILED -- falling back to the agent"; \
	    $(MAKE) --no-print-directory refpass; \
	    cp $(BUILD)/ref/vim.c vim.c; \
	    cp $(BUILD)/ref/LICENSE LICENSE; \
	    echo "  workflow     the reference path produced vim.c; repairing the fast path"; \
	    tools/repair.sh; \
	fi

.PHONY: refpass
refpass:
	@rm -rf $(REFWORK) $(BUILD)/ref
	@mkdir -p $(BUILD)/ref
	@git clone --quiet --branch $(UPSTREAM_BRANCH) --depth 1 $(UPSTREAM_URL) $(REFWORK)
	@rm -rf $(REFWORK)/.git
	@echo "  clone        `find $(REFWORK) -type f | wc -l | tr -d ' '` files, .git removed"
	@start=`date +%s`; \
	 tools/agentpass.sh $(REFWORK); \
	 now=`date +%s`; echo "  refpass      $$((now - start))s"
	@cp $(REFWORK)/vim.c $(BUILD)/ref/vim.c
	@cp $(REFWORK)/LICENSE $(BUILD)/ref/LICENSE
	@rm -rf $(REFWORK)
	@$(MAKE) --no-print-directory compare

# The two answers, against each other.  A difference is a result: either the
# fast path has drifted, or upstream moved and only the agent noticed.
.PHONY: compare
compare:
	@test -f $(BUILD)/ref/vim.c || { echo "  compare      no reference answer -- run make refpass"; exit 1; }
	@if cmp -s vim.c $(BUILD)/ref/vim.c; then \
	    echo "  compare      identical -- both paths produced the same vim.c"; \
	else \
	    echo "  compare      DIFFERS -- fast path $$(grep -c '' vim.c) lines, reference $$(grep -c '' $(BUILD)/ref/vim.c)"; \
	    echo "               +$$(diff vim.c $(BUILD)/ref/vim.c | grep -c '^>') -$$(diff vim.c $(BUILD)/ref/vim.c | grep -c '^<') against the committed one"; \
	    echo "               diff vim.c $(BUILD)/ref/vim.c   -- and read $(BUILD)/ref/PROGRESS.md"; \
	fi

# --- what a pass is -------------------------------------------------------
.PHONY: pass
pass: $(BUILD)/p9.sha256
	@cp $(WORK)/vim.c vim.c
	@cp $(WORK)/LICENSE LICENSE
	@echo "  pass         vim.c and LICENSE at the root"

# The documents, and only when there is something to describe.  A pass that
# reproduced the previous vim.c byte for byte made no sentence wrong, and an
# agent rewriting them anyway costs twelve minutes to confirm that nothing
# happened.  git is what knows: vim.c is tracked, so "did this pass change the
# editor" is one command and not a judgement.
.PHONY: docs-if-changed
docs-if-changed:
	@if git diff --quiet -- vim.c 2>/dev/null; then \
	    echo "  documents    vim.c unchanged -- nothing to describe"; \
	else \
	    echo "  documents    vim.c changed -- updating"; \
	    tools/agentdocs.sh; \
	fi

# Run, or re-run, one phase: make phase-4
.PHONY: $(PHASES:%=phase-%)
$(PHASES:%=phase-%): phase-%:
	@rm -f $(BUILD)/p$*.sha256
	@$(MAKE) --no-print-directory $(BUILD)/p$*.sha256

# Put $(WORK) back to a boundary and leave it there, for looking at:
# make replay-3  gives the tree exactly as phase 4 receives it.
.PHONY: $(PHASES:%=replay-%)
$(PHASES:%=replay-%): replay-%:
	@tools/restore.sh $(BUILD)/p$*.tar $(WORK)
	@echo "  replay       $(WORK)/ is the tree after phase $*"

# Promote an agent-recorded boundary to a hard check.  Only after a pass whose
# vim.c and behaviour verified end to end: a boundary promoted from the run it
# is meant to check would agree with itself.
.PHONY: $(PHASES:%=promote-%)
$(PHASES:%=promote-%): promote-%:
	@mkdir -p $(ORACLE)
	@test -f $(BUILD)/p$*.sha256 || { echo "no $(BUILD)/p$*.sha256 to promote"; exit 1; }
	@cp $(BUILD)/p$*.sha256 $(ORACLE)/p$*.sha256
	@cp $(BUILD)/p$*.sha256.files $(ORACLE)/p$*.sha256.files
	@rm -f $(ORACLE)/p$*.sha256.advisory $(ORACLE)/p$*.sha256.advisory.files
	@echo "  promote      p$* is now a check: $$(cut -c1-12 $(ORACLE)/p$*.sha256)"

# Record every boundary this run produced, as advisory.  What an agent pass
# leaves behind for the programs that will replace it.
.PHONY: record
record:
	@mkdir -p $(ORACLE)
	@for p in $(PHASES); do \
	    [ -f $(BUILD)/p$$p.sha256 ] || continue; \
	    [ -f $(ORACLE)/p$$p.sha256 ] && continue; \
	    cp $(BUILD)/p$$p.sha256 $(ORACLE)/p$$p.sha256.advisory; \
	    cp $(BUILD)/p$$p.sha256.files $(ORACLE)/p$$p.sha256.advisory.files; \
	    echo "  record       p$$p advisory: $$(cut -c1-12 $(BUILD)/p$$p.sha256)"; \
	done

# Where the time went, from what runphase.sh recorded.
.PHONY: times
times:
	@total=0; for p in $(PHASES); do \
	    [ -f $(BUILD)/p$$p.seconds ] || continue; \
	    s=$$(cat $(BUILD)/p$$p.seconds); total=$$((total + s)); \
	    printf '  phase %-6s %4s s  by %s\n' "$$p" "$$s" "$$(cat $(BUILD)/p$$p.kind)"; \
	done; \
	printf '  %-12s %4s s  (%s m)\n' "total" "$$total" "$$((total / 60))"

# How much of each phase is still a recorded diff rather than a rule.
.PHONY: residue
residue:
	@tools/residue.sh

# What a pass would need on this machine, asked before it starts rather than
# ten minutes in.  The ordinary case -- sha matches, compile the committed
# vim.c -- reaches none of it.
.PHONY: preflight
preflight:
	@tools/preflight.sh

.PHONY: clean-pass
clean-pass:
	rm -rf $(BUILD)

# The tier-3 cache is keyed by content, so it never goes stale -- but it does
# grow, and throwing it away costs only the time to recompute.
.PHONY: clean-cache
clean-cache:
	rm -rf .cache
