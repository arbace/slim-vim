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
# relocation, where whim-vim is a static-PIE.  Phase 1 adds -fno-stack-protector,
# so the line is now gcc -O0 -fno-stack-protector -static -no-pie -s.
#
# THE FLAGS ARE THE BOUNDARY'S.  A phase changes them by editing zero/Makefile, the
# makefile the last phase leaves -- never tools/templates/zero.mk, which is the
# pipeline's input and whose every byte is in r0's input digest.  The product rule
# below cannot read zero/, which does not exist in a checkout that only builds the
# committed zero-vim.c, so it states them once, as ZEROCFLAGS and ZEROLDFLAGS, and
# zero-pass refuses to copy zero-vim.c out when they differ from that makefile's
# CFLAGS and LDFLAGS.  The two statements cannot drift without a pass saying so.
#
# Zero's behaviour is measured against its own baselines, .reference/zero-baselines,
# which zero phase 0 records from whim-vim.c built with whim's compile line.  So
# pipes/zero.delta starts empty, and each zero phase declares only what it changes
# relative to whim (tools/zerodelta.sh).

ZEROWORK    = zero
ZEROBUILD   = .build-zero
ZEROORACLE  = .reference/zero-phases
ZEROCFLAGS  = -O0 -fno-stack-protector
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
	@NO_AGENT=1 tools/memo.sh $$(tools/stages.sh zero --of $*) $(ZEROWORK) $(ZEROBUILD) zero
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
	@printf '  %-12s %s\n' "compiling" "$(CC) $(ZEROCFLAGS) $(ZEROLDFLAGS) -o $@ $<"
	@t0=`date +%s`; $(CC) $(ZEROCFLAGS) $(ZEROLDFLAGS) -o $@ $<; \
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

# --- editor.c, the upper part on its own ----------------------------------
# What this pipeline is for.  zero-vim.c is one translation unit with two parts:
# above, the core editor, with no preprocessor syntax at all; below, the host,
# beginning with the #includes -- and that first directive IS the boundary, marked
# by nothing else (ZERO-PLAN.md 4c).  The product of the whole project is the upper
# part, and this is the rule that takes it.
#
# The cut is `stop at the first #include`, which is one awk clause and no judgement.
# The rest of the awk drops trailing blank lines, so the file ends on its last line
# of code rather than on whatever blank separated the core from the host.
#
# THE PATTERN IS `^ *# *include `, NEVER `^#include`, and tools/macros.py already
# carries the reason: whitespace between `#` and the keyword is insignificant to C,
# and this tree has had plenty of `# define` -- what the conditional-resolution pass
# left when it dedented `#  define` by one level and stopped.  A cut that missed
# ` # include` would not fail, it would run PAST the boundary and take the host with
# it.  So the rule also refuses if the file it wrote holds a DIRECTIVE -- a line whose
# first non-blank character is `#`: the defining property of the upper part is that it
# has no directive, and a cut that produced one has found the wrong line.
#
# THE GUARD SAID `grep -q '#'` UNTIL ZERO PHASE 27, AND IT COULD ONLY EVER HAVE BEEN
# WRITTEN AGAINST AN EMPTY FILE.  A `#` is also an ordinary character, and the editor is
# full of them: measured on the first cut this rule ever produced, 63 lines hold one --
# `enum { CPO_HASH = '#' };`, `if (ptr[0] == '#')`, the two latin1 case tables, the
# `"E1281: Atom '\%%#=%c'"` message.  None is a directive and the rule refused all the
# same.  `^ *#` is what the paragraph above already says it means, and it is measured
# at 0 on the cut and at 11 on the whole file, which is the eleven `#include`s.
#
# IT DOES NOT COMPILE ON ITS OWN, AND THAT IS CORRECT, not a defect to fix: the core
# calls the musl_ functions the host defines below, so the upper part declares them
# and defines none.  What it must do is PARSE -- `gcc -fsyntax-only` with no errors
# and a warning set equal to the declared boundary -- and that is the reorganisation
# phase's check, not this rule's.
#
# Until the includes move down, the first line of zero-vim.c is one, so this rule
# writes an EMPTY FILE.  That is the honest answer for the tree as it stands and it
# is why the rule exists now: the target is here before the phase that fills it, so
# the phase changes the source and not the makefile.
.PHONY: editor.c
editor.c: zero-vim.c
	@awk '/^ *# *include / { exit } { a[NR] = $$0; if (NF) last = NR } \
	      END { for (i = 1; i <= last; i++) print a[i] }' $< > $@
	@if grep -q '^ *#' $@; then \
	    echo "  editor.c     REFUSED -- the cut holds a directive, so it found the wrong line:"; \
	    grep -n '^ *#' $@ | head -3 | sed 's/^/               /'; \
	    rm -f $@; exit 1; \
	 fi
	@printf '  %-12s %s lines, cut at the first #include of %s\n' "$@" \
	    "`grep -c '' $@ | sed -e :a -e 's/\(.*[0-9]\)\([0-9]\{3\}\)/\1,\2/;ta'`" \
	    "`grep -c '' $< | sed -e :a -e 's/\(.*[0-9]\)\([0-9]\{3\}\)/\1,\2/;ta'`"

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
	 if [ -d $$b/screen ] && [ -n "$$(ls -A $$b/screen 2>/dev/null)" ] \
	    && [ -s $$b/ref-excmds.txt ] && [ -s $$b/ref-argv.txt ] \
	    && [ -s $$b/ref-pty.txt ] && [ -s $$b/ref-term.txt ]; then exit 0; fi; \
	 echo; \
	 echo "  baselines    MISSING or of the old shape: $$b does not hold screen/,"; \
	 echo "               ref-excmds.txt, ref-argv.txt, ref-pty.txt and ref-term.txt"; \
	 echo "               (tools/zrecord.sh).  Zero phase 0 records them only when it"; \
	 echo "               runs, and r0 came from the tier 3 cache.  Every later zero"; \
	 echo "               delta compares with them.  Fix:"; \
	 echo "                 rm -rf .cache/r0 && make zero-phase-0"; \
	 exit 1

# --- what a zero pass is --------------------------------------------------
.PHONY: zero-pass
zero-pass: $(ZEROBUILD)/r$(ZEROLAST).sha256
	@$(MAKE) --no-print-directory zero-baselines-check
	@m=$$(tar -xOf $(ZEROBUILD)/r$(ZEROLAST).tar ./Makefile 2>/dev/null \
	      || tar -xOf $(ZEROBUILD)/r$(ZEROLAST).tar Makefile); \
	 c=$$(printf '%s\n' "$$m" | sed -n 's/^CFLAGS  *= *//p'); \
	 l=$$(printf '%s\n' "$$m" | sed -n 's/^LDFLAGS  *= *//p'); \
	 if [ "$$c" != "$(ZEROCFLAGS)" ] || [ "$$l" != "$(ZEROLDFLAGS)" ]; then \
	     echo "  flags        zero.mk builds zero-vim with '$(ZEROCFLAGS)' '$(ZEROLDFLAGS)',"; \
	     echo "               but the last boundary's makefile says '$$c' '$$l'."; \
	     echo "               ZEROCFLAGS and ZEROLDFLAGS must state the boundary's flags."; \
	     exit 1; \
	 fi
	@tar -xOf $(ZEROBUILD)/r$(ZEROLAST).tar ./zero-vim.c > zero-vim.c 2>/dev/null \
	 || tar -xOf $(ZEROBUILD)/r$(ZEROLAST).tar zero-vim.c > zero-vim.c
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
	rm -rf $(ZEROBUILD) $(ZEROWORK) zero-vim editor.c

.PHONY: zero-residue
zero-residue:
	@tools/residue.sh zero
