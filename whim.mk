# The whim pipeline: whim-vim.c = G(slim-vim.c).
#
# Included by the root Makefile, and the same construct as slim.mk -- phases as
# targets, boundaries as content digests, results memoized in three tiers.  The
# driver, the oracle and the synthesiser are shared and take the pipeline as an
# argument; tools/pipeline.sh is the whole of the difference between the two.
#
# What differs is what the phases DO.  SLIM-GOAL.md removes files and
# preprocessor and changes nothing about the editor; WHIM-GOAL.md removes
# capability on purpose, so every phase there has to state its delta in advance
# and the harness has to show exactly that set and no more.
#
# The input is the COMMITTED slim-vim.c, not a phase boundary of the other
# pipeline.  That decoupling is deliberate: `make whim-vim` needs no clone, no
# network and no agent, and the memoize key is slim-vim.c's digest and the
# implementation's -- exactly as the other pipeline keys on upstream's sha.

WHIMWORK   = whim
WHIMBUILD  = .build-whim
WHIMORACLE = .reference/whim-phases
WHIMPHASES = 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60 61 62 63 64 65 66 67 68 69 70 71 72 73 74 75 76 77 78 79 80 81 82

# --- the chain ------------------------------------------------------------
# The chain is of STAGES, read from pipes/whim.stages by tools/stages.sh: a stage
# is a run of phases whose edits share one sweep, and only a stage's end is a
# boundary -- q41 is the boundary of stage 13-41, and nothing between q12 and q41
# exists.  Each boundary depends on the one before it, as each phase's did.
WHIMSTAGES := $(shell tools/stages.sh whim)
ifeq ($(WHIMSTAGES),)
$(error pipes/whim.stages does not hold -- tools/stages.sh whim --check says why)
endif
WHIMENDS   := $(foreach u,$(WHIMSTAGES),$(lastword $(subst -, ,$(u))))
WHIMSTARTS := input.sha256 $(patsubst %,q%.sha256,$(filter-out $(lastword $(WHIMENDS)),$(WHIMENDS)))
WHIMLAST   := $(lastword $(WHIMENDS))
$(foreach i,$(shell seq 1 $(words $(WHIMENDS))),$(eval \
    $(WHIMBUILD)/q$(word $(i),$(WHIMENDS)).sha256: $(WHIMBUILD)/$(word $(i),$(WHIMSTARTS))))

$(WHIMBUILD)/q%.sha256:
	@tools/restore.sh $(patsubst %.sha256,%.tar,$<) $(WHIMWORK)
	@tools/memo.sh $$(tools/stages.sh whim --of $*) $(WHIMWORK) $(WHIMBUILD) whim
	@tools/oracle.sh $* $(WHIMBUILD) $(WHIMORACLE) whim | sed 's/^  /      /'

# --- the input ------------------------------------------------------------
# A directory holding one file and a makefile, so the boundary machinery -- a
# tar and a digest over a tree -- applies unchanged.
$(WHIMBUILD)/input.sha256: slim-vim.c tools/templates/whim.mk
	@rm -rf $(WHIMWORK)
	@mkdir -p $(WHIMWORK) $(WHIMBUILD)
	@cp slim-vim.c $(WHIMWORK)/whim-vim.c
	@cp tools/templates/whim.mk $(WHIMWORK)/Makefile
	@date +%s > $(WHIMBUILD)/pass-start
	@printf '\n\033[1m  whim-vim\033[0m  from slim-vim.c: an editor with no runtime\n'
	@tools/snapshot.sh $(WHIMWORK) $(WHIMBUILD)/input.tar $(WHIMBUILD)/input.sha256

# --- the product ----------------------------------------------------------
# The same content-keyed dependency the other pipeline uses, for the same
# reason: whim-vim.c and slim-vim.c are both tracked, and a fresh clone writes
# them at checkout time in arbitrary order, so an mtime dependency would run a
# whim pass on a tree that is exactly right.  slim.sha records the slim-vim.c
# this whim-vim.c was produced from.
whim-vim: whim-vim.c
	@printf '  %-12s %s\n' "compiling" "$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $<"
	@t0=`date +%s`; $(CC) $(CFLAGS) $(LDFLAGS) -o $@ $<; \
	 printf '  %-12s %s bytes, static-PIE, %ss\n' "$@" \
	     "`stat -c%s $@ | sed -e :a -e 's/\(.*[0-9]\)\([0-9]\{3\}\)/\1,\2/;ta'`" \
	     "$$((`date +%s` - t0))"

whim-vim.c: force
	@set -e; \
	live=`sha256sum slim-vim.c | cut -c1-64`; \
	if [ -f $@ ] && [ "$$live" = "`cat slim.sha 2>/dev/null`" ]; then \
	    printf '  %-12s %s unchanged -- whim-vim.c is current\n' "slim-vim.c" "`echo $$live | cut -c1-12`"; \
	    exit 0; \
	fi; \
	printf '  %-12s %s -- whim-vim.c must be produced\n' "slim-vim.c" "`echo $$live | cut -c1-12`"; \
	$(MAKE) --no-print-directory whim-pass; \
	echo "$$live" > slim.sha

# --- what a whim pass is --------------------------------------------------
.PHONY: whim-pass
whim-pass: $(WHIMBUILD)/q$(WHIMLAST).sha256
	@cp $(WHIMWORK)/whim-vim.c whim-vim.c
	@echo
	@printf '  %-12s %s lines, from slim-vim.c\n' "whim-vim.c" \
	    "`grep -c '' whim-vim.c | sed -e :a -e 's/\(.*[0-9]\)\([0-9]\{3\}\)/\1,\2/;ta'`"

# The same per-phase handles slim.mk has, and one semantic change: a phase is run
# by running THE STAGE THAT CONTAINS IT, because only a stage's end is a boundary
# and nothing else has an input to start from.  `make whim-phase-50` re-runs stage
# 42-63; within it, the edits before 50 come from the edit cache when nothing they
# read has changed (tools/phaserun.sh).
.PHONY: $(WHIMPHASES:%=whim-phase-%)
$(WHIMPHASES:%=whim-phase-%): whim-phase-%:
	@u=$$(tools/stages.sh whim --of $*) && last=$${u#*-} && \
	 rm -f $(WHIMBUILD)/q$$last.sha256 && \
	 $(MAKE) --no-print-directory $(WHIMBUILD)/q$$last.sha256

# Only a stage's end can be replayed: nothing else was ever a tree on disk.
.PHONY: $(WHIMPHASES:%=whim-replay-%)
$(WHIMPHASES:%=whim-replay-%): whim-replay-%:
	@if [ ! -f $(WHIMBUILD)/q$*.tar ]; then \
	     echo "  replay       q$* is not a boundary: phase $* is inside stage $$(tools/stages.sh whim --of $*)," \
	          "and only a stage's end is kept"; exit 1; fi
	@tools/restore.sh $(WHIMBUILD)/q$*.tar $(WHIMWORK)
	@echo "  replay       $(WHIMWORK)/ is the tree after whim phase $*"

.PHONY: whim-times
whim-times:
	@total=0; for u in $(WHIMSTAGES); do q=$${u#*-}; \
	    [ -f $(WHIMBUILD)/q$$q.seconds ] || continue; \
	    s=$$(cat $(WHIMBUILD)/q$$q.seconds); total=$$((total + s)); \
	    printf '  whim %-6s %4s s  by %s\n' "$$u" "$$s" "$$(cat $(WHIMBUILD)/q$$q.kind)"; \
	done; \
	printf '  %-12s %4s s\n' "total" "$$total"

# Force one when the recorded input digest already matches -- slim-repass's twin.
.PHONY: whim-repass
whim-repass:
	@rm -rf $(WHIMBUILD)
	@$(MAKE) --no-print-directory whim-pass

# Both phases are programs and this pipeline has no agent in it, so a boundary
# it produced is reproducible by construction -- there is no advisory stage to
# pass through.  Recorded only after a run that built, swept to silence and
# showed exactly the declared delta.
# ADDING A PHASE DOES NOT COST A PASS, and this target is the proof rather than
# a promise.  tools/implhash.sh reads a phase's own program and the tools that
# program NAMES -- not whim.mk, not pipeline.sh -- so putting a new phase on the
# end invalidates nothing before it.  A cached phase replays in 0.6 s and a warm
# pass in one.
#
# So the loop while you are trying ideas out is: write pipes/whimN-edit.sh and
# pipes/whimN-check.sh, declare its delta in pipes/whim.delta, add N here and in
# tools/pipeline.sh, put it in the last stage or a new one in pipes/whim.stages
# (WHIM-GOAL.md, "Adding a phase"), and `make whim-tip`.  Only the last stage runs,
# and its earlier edits come from the edit cache.
#
# WHAT THIS DOES NOT DO, and must not be mistaken for: falsify the boundaries
# before it.  A tier 3 replay COPIES the recorded digest rather than recomputing
# it, so a warm pass agrees with the oracle whatever the oracle says -- which is
# how a wrong boundary went unnoticed for eleven phases once.  Only a run that
# recomputes every digest can do that: `make whim-verify`, every phase at once on
# the recorded boundary before it, or `make whim-repass` after `make clean-cache`,
# which is sequential and is the one that records.  Do it before a push, and
# whenever a SHARED tool changes (sweep.sh, canon.sh, deadsweep.py, typereach.py,
# funcreach.py, deadfields.py, deadenums.py, phasecheck.sh, whimdelta.sh,
# cutil.py) -- those are in every phase's implhash, so everything re-runs then
# anyway.
.PHONY: whim-tip
whim-tip:
	@$(MAKE) --no-print-directory whim-phase-$(WHIMLAST) && \
	 $(MAKE) --no-print-directory whim-record | tail -1

# Every recorded boundary, checked at once.  Each stage is run on the recorded
# boundary before it, in a scratch root of its own, and must reproduce the one it
# recorded -- by induction the same proof as a repass from an empty cache, in the
# wall time of the slowest stage instead of the sum of them all.
.PHONY: whim-verify
whim-verify:
	@tools/verifypass.sh whim

# A repass that waits only where it has to.  Every stage first runs at once on
# the previous pass's boundary before it, and its result goes into the tier 3
# cache under the key memo.sh will look up; then the ordinary sequential pass
# runs, and is a cache hit wherever that guess about its input was right.  A
# change to a tool rather than to what a phase produces costs the wall time of
# the slowest phase; a change to phase K's output still runs K onwards in
# sequence.  See tools/specpass.sh.  The previous .build-whim is its input, so
# this target reads it before whim-repass removes it.
.PHONY: whim-specpass
whim-specpass:
	@tools/specpass.sh whim
	@$(MAKE) --no-print-directory whim-repass

.PHONY: whim-record
whim-record:
	@mkdir -p $(WHIMORACLE)
	@for q in $(WHIMENDS); do \
	    [ -f $(WHIMBUILD)/q$$q.sha256 ] || continue; \
	    cp $(WHIMBUILD)/q$$q.sha256 $(WHIMORACLE)/q$$q.sha256; \
	    cp $(WHIMBUILD)/q$$q.sha256.files $(WHIMORACLE)/q$$q.sha256.files; \
	    echo "  record       q$$q: $$(cut -c1-12 $(WHIMORACLE)/q$$q.sha256)"; \
	done

.PHONY: whim-clean
whim-clean:
	rm -rf $(WHIMBUILD) $(WHIMWORK) whim-vim

# How much of each phase is still a recorded diff rather than a rule.  The twin
# of slim-residue; the scoreboard is the same question either side.
.PHONY: whim-residue
whim-residue:
	@tools/residue.sh whim
