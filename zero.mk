# The zero pipeline: zero-vim.c = H(whim-vim.c).
#
# Included by the root Makefile, and the same construct as slim.mk and whim.mk --
# phases as targets, boundaries as content digests, results memoized in three tiers.
# The driver, the oracle and the synthesiser are shared and take the pipeline as an
# argument; tools/pipeline.sh is the whole of the difference, and ZERO-GOAL.md is
# what the phases do.
#
# The input is the COMMITTED whim-vim.c, immutable, exactly as whim's is the
# committed slim-vim.c: `make zero-vim` needs no clone, no network and no agent, and
# the memoize key is whim-vim.c's digest and the implementation's.
#
# The one difference the seed introduces is the compile line: gcc -O0 -static
# -no-pie -s, where whim and slim keep -O0 -static -s.  The result is an ordinary
# static executable -- readelf -h says EXEC -- with no dynamic section and not one
# relocation, where whim-vim is a static-PIE.
#
# Zero's behaviour is measured against its own baselines, .reference/zero-baselines,
# which zero phase 0 records from whim-vim.c built with whim's compile line.  So
# pipes/zero.delta starts empty, and each zero phase declares only what it changes
# relative to whim (tools/zerodelta.sh).

ZEROWORK    = zero
ZEROBUILD   = .build-zero
ZEROORACLE  = .reference/zero-phases
ZEROLDFLAGS = -static -no-pie -s

# The phase list is the `phases` line of pipes/zero.stages, read through
# tools/pipeline.sh -- not written out here and not in tools/pipeline.sh, whose every
# byte is in every whim stage's key.  One list, so it cannot disagree with itself.
ZEROPHASES := $(shell . tools/pipeline.sh zero && echo $$PHASE_LIST)

# --- the chain ------------------------------------------------------------
# Stages, from pipes/zero.stages by tools/stages.sh, exactly as whim.mk reads its own.
ZEROSTAGES := $(shell tools/stages.sh zero)
ifeq ($(ZEROSTAGES),)
$(error pipes/zero.stages does not hold -- tools/stages.sh zero --check says why)
endif
ZEROENDS   := $(foreach u,$(ZEROSTAGES),$(lastword $(subst -, ,$(u))))
ZEROSTARTS := input.sha256 $(patsubst %,r%.sha256,$(filter-out $(lastword $(ZEROENDS)),$(ZEROENDS)))
ZEROLAST   := $(lastword $(ZEROENDS))
$(foreach i,$(shell seq 1 $(words $(ZEROENDS))),$(eval \
    $(ZEROBUILD)/r$(word $(i),$(ZEROENDS)).sha256: $(ZEROBUILD)/$(word $(i),$(ZEROSTARTS))))

$(ZEROBUILD)/r%.sha256:
	@tools/restore.sh $(patsubst %.sha256,%.tar,$<) $(ZEROWORK)
	@tools/memo.sh $$(tools/stages.sh zero --of $*) $(ZEROWORK) $(ZEROBUILD) zero
	@tools/oracle.sh $* $(ZEROBUILD) $(ZEROORACLE) zero | sed 's/^  /      /'

# --- the input ------------------------------------------------------------
# A directory holding one file and a makefile, as whim's is.
$(ZEROBUILD)/input.sha256: whim-vim.c tools/templates/zero.mk
	@rm -rf $(ZEROWORK)
	@mkdir -p $(ZEROWORK) $(ZEROBUILD)
	@cp whim-vim.c $(ZEROWORK)/zero-vim.c
	@cp tools/templates/zero.mk $(ZEROWORK)/Makefile
	@date +%s > $(ZEROBUILD)/pass-start
	@printf '\n\033[1m  zero-vim\033[0m  from whim-vim.c: an embeddable editor core\n'
	@tools/snapshot.sh $(ZEROWORK) $(ZEROBUILD)/input.tar $(ZEROBUILD)/input.sha256

# --- the product ----------------------------------------------------------
# Content-keyed, as whim-vim.c is on slim.sha: whim.sha records the whim-vim.c this
# zero-vim.c was produced from, and a fresh clone's arbitrary checkout order can
# never fire a pass on a tree that is exactly right.
zero-vim: zero-vim.c
	@printf '  %-12s %s\n' "compiling" "$(CC) $(CFLAGS) $(ZEROLDFLAGS) -o $@ $<"
	@t0=`date +%s`; $(CC) $(CFLAGS) $(ZEROLDFLAGS) -o $@ $<; \
	 printf '  %-12s %s bytes, static, not PIE, %ss\n' "$@" \
	     "`stat -c%s $@ | sed -e :a -e 's/\(.*[0-9]\)\([0-9]\{3\}\)/\1,\2/;ta'`" \
	     "$$((`date +%s` - t0))"

zero-vim.c: force
	@set -e; \
	live=`sha256sum whim-vim.c | cut -c1-64`; \
	if [ -f $@ ] && [ "$$live" = "`cat whim.sha 2>/dev/null`" ]; then \
	    printf '  %-12s %s unchanged -- zero-vim.c is current\n' "whim-vim.c" "`echo $$live | cut -c1-12`"; \
	    exit 0; \
	fi; \
	printf '  %-12s %s -- zero-vim.c must be produced\n' "whim-vim.c" "`echo $$live | cut -c1-12`"; \
	$(MAKE) --no-print-directory zero-pass; \
	echo "$$live" > whim.sha

# --- the baselines, which a tier 3 hit does not record ---------------------
# Zero phase 0 records .reference/zero-baselines as a side effect of running, so a
# pass that replays r0 from the cache records nothing -- and a tree with a warm
# cache and no baselines would end its pass looking fine, leaving every later zero
# phase's delta with nothing to compare against.  So every target that can end a
# pass on a cached r0 asks afterwards, and refuses with the fix.  It is here, in a
# makefile no implementation digest reads, so it moves no key.
ZEROBASELINES = .reference/zero-baselines

.PHONY: zero-baselines-check
zero-baselines-check:
	@b=$(ZEROBASELINES); \
	 if [ -d $$b/behaviour ] && [ -n "$$(ls -A $$b/behaviour 2>/dev/null)" ] \
	    && [ -s $$b/ref-exsweep.txt ] && [ -s $$b/ref-term.txt ]; then exit 0; fi; \
	 echo; \
	 echo "  baselines    MISSING: $$b does not hold behaviour/, ref-exsweep.txt and ref-term.txt"; \
	 echo "               zero phase 0 records them only when it runs, and r0 came from the"; \
	 echo "               tier 3 cache.  Every later zero delta compares with them.  Fix:"; \
	 echo "                 rm -rf .cache/r0 && make zero-phase-0"; \
	 exit 1

# --- what a zero pass is --------------------------------------------------
.PHONY: zero-pass
zero-pass: $(ZEROBUILD)/r$(ZEROLAST).sha256
	@$(MAKE) --no-print-directory zero-baselines-check
	@cp $(ZEROWORK)/zero-vim.c zero-vim.c
	@echo
	@printf '  %-12s %s lines, from whim-vim.c\n' "zero-vim.c" \
	    "`grep -c '' zero-vim.c | sed -e :a -e 's/\(.*[0-9]\)\([0-9]\{3\}\)/\1,\2/;ta'`"

# A phase is run by running the stage that contains it (whim.mk says why).
.PHONY: $(ZEROPHASES:%=zero-phase-%)
$(ZEROPHASES:%=zero-phase-%): zero-phase-%:
	@u=$$(tools/stages.sh zero --of $*) && last=$${u#*-} && \
	 rm -f $(ZEROBUILD)/r$$last.sha256 && \
	 $(MAKE) --no-print-directory $(ZEROBUILD)/r$$last.sha256 && \
	 $(MAKE) --no-print-directory zero-baselines-check

# Only a stage's end can be replayed: nothing else was ever a tree on disk.
.PHONY: $(ZEROPHASES:%=zero-replay-%)
$(ZEROPHASES:%=zero-replay-%): zero-replay-%:
	@if [ ! -f $(ZEROBUILD)/r$*.tar ]; then \
	     echo "  replay       r$* is not a boundary: phase $* is inside stage $$(tools/stages.sh zero --of $*)," \
	          "and only a stage's end is kept"; exit 1; fi
	@tools/restore.sh $(ZEROBUILD)/r$*.tar $(ZEROWORK)
	@echo "  replay       $(ZEROWORK)/ is the tree after zero phase $*"

.PHONY: zero-times
zero-times:
	@total=0; for u in $(ZEROSTAGES); do r=$${u#*-}; \
	    [ -f $(ZEROBUILD)/r$$r.seconds ] || continue; \
	    s=$$(cat $(ZEROBUILD)/r$$r.seconds); total=$$((total + s)); \
	    printf '  zero %-6s %4s s  by %s\n' "$$u" "$$s" "$$(cat $(ZEROBUILD)/r$$r.kind)"; \
	done; \
	printf '  %-12s %4s s\n' "total" "$$total"

# Force one when the recorded input digest already matches.
.PHONY: zero-repass
zero-repass:
	@rm -rf $(ZEROBUILD)
	@$(MAKE) --no-print-directory zero-pass

# The loop while a phase is being tried out: write it, declare its delta in
# pipes/zero.delta, add it to the `phases` line of pipes/zero.stages and place it in
# a stage and a package there (ZERO-GOAL.md), and `make zero-tip`.  Only the last
# stage runs.
#
# WHAT THIS DOES NOT DO: falsify the boundaries before it.  A tier 3 replay copies
# the recorded digest rather than recomputing it; `make zero-verify` recomputes.
#
# Both zero-tip and zero-verify first run tools/packages.sh zero --check, from here,
# which no implementation digest reads.
.PHONY: zero-tip
zero-tip:
	@tools/packages.sh zero --check && \
	 $(MAKE) --no-print-directory zero-phase-$(ZEROLAST) && \
	 $(MAKE) --no-print-directory zero-record | tail -1

# Every recorded boundary, checked at once, each stage on the recorded boundary
# before it in a scratch root of its own (tools/verifypass.sh).
.PHONY: zero-verify
zero-verify:
	@tools/packages.sh zero --check && \
	 tools/verifypass.sh zero

# Every stage at once on the previous pass's boundaries into the tier 3 cache, then
# the ordinary repass (tools/specpass.sh).
.PHONY: zero-specpass
zero-specpass:
	@tools/specpass.sh zero
	@$(MAKE) --no-print-directory zero-repass

.PHONY: zero-record
zero-record:
	@mkdir -p $(ZEROORACLE)
	@for r in $(ZEROENDS); do \
	    [ -f $(ZEROBUILD)/r$$r.sha256 ] || continue; \
	    cp $(ZEROBUILD)/r$$r.sha256 $(ZEROORACLE)/r$$r.sha256; \
	    cp $(ZEROBUILD)/r$$r.sha256.files $(ZEROORACLE)/r$$r.sha256.files; \
	    echo "  record       r$$r: $$(cut -c1-12 $(ZEROORACLE)/r$$r.sha256)"; \
	done

.PHONY: zero-clean
zero-clean:
	rm -rf $(ZEROBUILD) $(ZEROWORK) zero-vim

.PHONY: zero-residue
zero-residue:
	@tools/residue.sh zero
