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
WHIMPHASES = 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60 61 62 63 64 65 66 67 68 69 70 71 72 73 74 75 76 77 78 79

# --- the chain ------------------------------------------------------------
$(WHIMBUILD)/q0.sha256: $(WHIMBUILD)/input.sha256
$(WHIMBUILD)/q1.sha256: $(WHIMBUILD)/q0.sha256
$(WHIMBUILD)/q2.sha256: $(WHIMBUILD)/q1.sha256
$(WHIMBUILD)/q3.sha256: $(WHIMBUILD)/q2.sha256
$(WHIMBUILD)/q4.sha256: $(WHIMBUILD)/q3.sha256
$(WHIMBUILD)/q5.sha256: $(WHIMBUILD)/q4.sha256
$(WHIMBUILD)/q6.sha256: $(WHIMBUILD)/q5.sha256
$(WHIMBUILD)/q7.sha256: $(WHIMBUILD)/q6.sha256
$(WHIMBUILD)/q8.sha256: $(WHIMBUILD)/q7.sha256
$(WHIMBUILD)/q9.sha256: $(WHIMBUILD)/q8.sha256
$(WHIMBUILD)/q10.sha256: $(WHIMBUILD)/q9.sha256
$(WHIMBUILD)/q11.sha256: $(WHIMBUILD)/q10.sha256
$(WHIMBUILD)/q12.sha256: $(WHIMBUILD)/q11.sha256
$(WHIMBUILD)/q13.sha256: $(WHIMBUILD)/q12.sha256
$(WHIMBUILD)/q14.sha256: $(WHIMBUILD)/q13.sha256
$(WHIMBUILD)/q15.sha256: $(WHIMBUILD)/q14.sha256
$(WHIMBUILD)/q16.sha256: $(WHIMBUILD)/q15.sha256
$(WHIMBUILD)/q17.sha256: $(WHIMBUILD)/q16.sha256
$(WHIMBUILD)/q18.sha256: $(WHIMBUILD)/q17.sha256
$(WHIMBUILD)/q19.sha256: $(WHIMBUILD)/q18.sha256
$(WHIMBUILD)/q20.sha256: $(WHIMBUILD)/q19.sha256
$(WHIMBUILD)/q21.sha256: $(WHIMBUILD)/q20.sha256
$(WHIMBUILD)/q22.sha256: $(WHIMBUILD)/q21.sha256
$(WHIMBUILD)/q23.sha256: $(WHIMBUILD)/q22.sha256
$(WHIMBUILD)/q24.sha256: $(WHIMBUILD)/q23.sha256
$(WHIMBUILD)/q25.sha256: $(WHIMBUILD)/q24.sha256
$(WHIMBUILD)/q26.sha256: $(WHIMBUILD)/q25.sha256
$(WHIMBUILD)/q27.sha256: $(WHIMBUILD)/q26.sha256
$(WHIMBUILD)/q28.sha256: $(WHIMBUILD)/q27.sha256
$(WHIMBUILD)/q29.sha256: $(WHIMBUILD)/q28.sha256
$(WHIMBUILD)/q30.sha256: $(WHIMBUILD)/q29.sha256
$(WHIMBUILD)/q31.sha256: $(WHIMBUILD)/q30.sha256
$(WHIMBUILD)/q32.sha256: $(WHIMBUILD)/q31.sha256
$(WHIMBUILD)/q33.sha256: $(WHIMBUILD)/q32.sha256
$(WHIMBUILD)/q34.sha256: $(WHIMBUILD)/q33.sha256
$(WHIMBUILD)/q35.sha256: $(WHIMBUILD)/q34.sha256
$(WHIMBUILD)/q36.sha256: $(WHIMBUILD)/q35.sha256
$(WHIMBUILD)/q37.sha256: $(WHIMBUILD)/q36.sha256
$(WHIMBUILD)/q38.sha256: $(WHIMBUILD)/q37.sha256
$(WHIMBUILD)/q39.sha256: $(WHIMBUILD)/q38.sha256
$(WHIMBUILD)/q40.sha256: $(WHIMBUILD)/q39.sha256
$(WHIMBUILD)/q41.sha256: $(WHIMBUILD)/q40.sha256
$(WHIMBUILD)/q42.sha256: $(WHIMBUILD)/q41.sha256
$(WHIMBUILD)/q43.sha256: $(WHIMBUILD)/q42.sha256
$(WHIMBUILD)/q44.sha256: $(WHIMBUILD)/q43.sha256
$(WHIMBUILD)/q45.sha256: $(WHIMBUILD)/q44.sha256
$(WHIMBUILD)/q46.sha256: $(WHIMBUILD)/q45.sha256
$(WHIMBUILD)/q47.sha256: $(WHIMBUILD)/q46.sha256
$(WHIMBUILD)/q48.sha256: $(WHIMBUILD)/q47.sha256
$(WHIMBUILD)/q49.sha256: $(WHIMBUILD)/q48.sha256
$(WHIMBUILD)/q50.sha256: $(WHIMBUILD)/q49.sha256
$(WHIMBUILD)/q51.sha256: $(WHIMBUILD)/q50.sha256
$(WHIMBUILD)/q52.sha256: $(WHIMBUILD)/q51.sha256
$(WHIMBUILD)/q53.sha256: $(WHIMBUILD)/q52.sha256
$(WHIMBUILD)/q54.sha256: $(WHIMBUILD)/q53.sha256
$(WHIMBUILD)/q55.sha256: $(WHIMBUILD)/q54.sha256
$(WHIMBUILD)/q56.sha256: $(WHIMBUILD)/q55.sha256
$(WHIMBUILD)/q57.sha256: $(WHIMBUILD)/q56.sha256
$(WHIMBUILD)/q58.sha256: $(WHIMBUILD)/q57.sha256
$(WHIMBUILD)/q59.sha256: $(WHIMBUILD)/q58.sha256
$(WHIMBUILD)/q60.sha256: $(WHIMBUILD)/q59.sha256
$(WHIMBUILD)/q61.sha256: $(WHIMBUILD)/q60.sha256
$(WHIMBUILD)/q62.sha256: $(WHIMBUILD)/q61.sha256
$(WHIMBUILD)/q63.sha256: $(WHIMBUILD)/q62.sha256
$(WHIMBUILD)/q64.sha256: $(WHIMBUILD)/q63.sha256
$(WHIMBUILD)/q65.sha256: $(WHIMBUILD)/q64.sha256
$(WHIMBUILD)/q66.sha256: $(WHIMBUILD)/q65.sha256
$(WHIMBUILD)/q67.sha256: $(WHIMBUILD)/q66.sha256
$(WHIMBUILD)/q68.sha256: $(WHIMBUILD)/q67.sha256
$(WHIMBUILD)/q69.sha256: $(WHIMBUILD)/q68.sha256
$(WHIMBUILD)/q70.sha256: $(WHIMBUILD)/q69.sha256
$(WHIMBUILD)/q71.sha256: $(WHIMBUILD)/q70.sha256
$(WHIMBUILD)/q72.sha256: $(WHIMBUILD)/q71.sha256
$(WHIMBUILD)/q73.sha256: $(WHIMBUILD)/q72.sha256
$(WHIMBUILD)/q74.sha256: $(WHIMBUILD)/q73.sha256
$(WHIMBUILD)/q75.sha256: $(WHIMBUILD)/q74.sha256
$(WHIMBUILD)/q76.sha256: $(WHIMBUILD)/q75.sha256
$(WHIMBUILD)/q77.sha256: $(WHIMBUILD)/q76.sha256
$(WHIMBUILD)/q78.sha256: $(WHIMBUILD)/q77.sha256
$(WHIMBUILD)/q79.sha256: $(WHIMBUILD)/q78.sha256

$(WHIMBUILD)/q%.sha256:
	@tools/restore.sh $(patsubst %.sha256,%.tar,$<) $(WHIMWORK)
	@tools/memo.sh $* $(WHIMWORK) $(WHIMBUILD) whim
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
whim-pass: $(WHIMBUILD)/q79.sha256
	@cp $(WHIMWORK)/whim-vim.c whim-vim.c
	@echo
	@printf '  %-12s %s lines, from slim-vim.c\n' "whim-vim.c" \
	    "`grep -c '' whim-vim.c | sed -e :a -e 's/\(.*[0-9]\)\([0-9]\{3\}\)/\1,\2/;ta'`"

# The same per-phase handles slim.mk has: re-run one, or put the work directory
# back to what a phase receives.  Their absence was an asymmetry rather than a
# decision -- the boundaries were always there, with nothing to reach them by.
.PHONY: $(WHIMPHASES:%=whim-phase-%)
$(WHIMPHASES:%=whim-phase-%): whim-phase-%:
	@rm -f $(WHIMBUILD)/q$*.sha256
	@$(MAKE) --no-print-directory $(WHIMBUILD)/q$*.sha256

.PHONY: $(WHIMPHASES:%=whim-replay-%)
$(WHIMPHASES:%=whim-replay-%): whim-replay-%:
	@tools/restore.sh $(WHIMBUILD)/q$*.tar $(WHIMWORK)
	@echo "  replay       $(WHIMWORK)/ is the tree after whim phase $*"

.PHONY: whim-times
whim-times:
	@total=0; for q in $(WHIMPHASES); do \
	    [ -f $(WHIMBUILD)/q$$q.seconds ] || continue; \
	    s=$$(cat $(WHIMBUILD)/q$$q.seconds); total=$$((total + s)); \
	    printf '  whim %-6s %4s s  by %s\n' "$$q" "$$s" "$$(cat $(WHIMBUILD)/q$$q.kind)"; \
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
# So the loop while you are trying ideas out is: write tools/whimN.sh, add it
# here, and `make whim-tip`.  Only the new phase runs.
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
	@last=$$(for q in $(WHIMPHASES); do echo $$q; done | tail -1); \
	 $(MAKE) --no-print-directory whim-phase-$$last && \
	 $(MAKE) --no-print-directory whim-record | tail -1

# Every recorded boundary, checked at once.  Each phase is run on the recorded
# boundary before it, in a scratch root of its own, and must reproduce the one it
# recorded -- by induction the same proof as a repass from an empty cache, in the
# wall time of the slowest phase instead of the sum of them all.
.PHONY: whim-verify
whim-verify:
	@tools/verifypass.sh whim

# A repass that waits only where it has to.  Every phase first runs at once on
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
	@for q in $(WHIMPHASES); do \
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
