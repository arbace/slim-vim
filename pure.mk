# The pure pipeline: pure-vim.c = G(slim-vim.c).
#
# Included by the root Makefile, and the same construct as slim.mk -- phases as
# targets, boundaries as content digests, results memoized in three tiers.  The
# driver, the oracle and the synthesiser are shared and take the pipeline as an
# argument; tools/pipeline.sh is the whole of the difference between the two.
#
# What differs is what the phases DO.  SLIM-GOAL.md removes files and
# preprocessor and changes nothing about the editor; PURE-GOAL.md removes
# capability on purpose, so every phase there has to state its delta in advance
# and the harness has to show exactly that set and no more.
#
# The input is the COMMITTED slim-vim.c, not a phase boundary of the other
# pipeline.  That decoupling is deliberate: `make pure-vim` needs no clone, no
# network and no agent, and the memoize key is slim-vim.c's digest and the
# implementation's -- exactly as the other pipeline keys on upstream's sha.

PUREWORK   = pure
PUREBUILD  = .build-pure
PUREORACLE = .reference/pure-phases
PUREPHASES = 0 1 2

# --- the chain ------------------------------------------------------------
$(PUREBUILD)/q0.sha256: $(PUREBUILD)/input.sha256
$(PUREBUILD)/q1.sha256: $(PUREBUILD)/q0.sha256
$(PUREBUILD)/q2.sha256: $(PUREBUILD)/q1.sha256

$(PUREBUILD)/q%.sha256:
	@tools/restore.sh $(patsubst %.sha256,%.tar,$<) $(PUREWORK)
	@tools/memo.sh $* $(PUREWORK) $(PUREBUILD) pure
	@tools/oracle.sh $* $(PUREBUILD) $(PUREORACLE) pure | sed 's/^  /      /'

# --- the input ------------------------------------------------------------
# A directory holding one file and a makefile, so the boundary machinery -- a
# tar and a digest over a tree -- applies unchanged.
$(PUREBUILD)/input.sha256: slim-vim.c tools/templates/pure.mk
	@rm -rf $(PUREWORK)
	@mkdir -p $(PUREWORK) $(PUREBUILD)
	@cp slim-vim.c $(PUREWORK)/pure-vim.c
	@cp tools/templates/pure.mk $(PUREWORK)/Makefile
	@date +%s > $(PUREBUILD)/pass-start
	@printf '\n\033[1m  pure-vim\033[0m  from slim-vim.c: an editor with no runtime\n'
	@tools/snapshot.sh $(PUREWORK) $(PUREBUILD)/input.tar $(PUREBUILD)/input.sha256

# --- the product ----------------------------------------------------------
# The same content-keyed dependency the other pipeline uses, for the same
# reason: pure-vim.c and slim-vim.c are both tracked, and a fresh clone writes
# them at checkout time in arbitrary order, so an mtime dependency would run a
# pure pass on a tree that is exactly right.  slim.sha records the slim-vim.c
# this pure-vim.c was produced from.
pure-vim: pure-vim.c
	@printf '  %-12s %s\n' "compiling" "$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $<"
	@t0=`date +%s`; $(CC) $(CFLAGS) $(LDFLAGS) -o $@ $<; \
	 printf '  %-12s %s bytes, static-PIE, %ss\n' "$@" \
	     "`stat -c%s $@ | sed -e :a -e 's/\(.*[0-9]\)\([0-9]\{3\}\)/\1,\2/;ta'`" \
	     "$$((`date +%s` - t0))"

pure-vim.c: force
	@set -e; \
	live=`sha256sum slim-vim.c | cut -c1-64`; \
	if [ -f $@ ] && [ "$$live" = "`cat slim.sha 2>/dev/null`" ]; then \
	    printf '  %-12s %s unchanged -- pure-vim.c is current\n' "slim-vim.c" "`echo $$live | cut -c1-12`"; \
	    exit 0; \
	fi; \
	printf '  %-12s %s -- pure-vim.c must be produced\n' "slim-vim.c" "`echo $$live | cut -c1-12`"; \
	$(MAKE) --no-print-directory pure-pass; \
	echo "$$live" > slim.sha

# --- what a pure pass is --------------------------------------------------
.PHONY: pure-pass
pure-pass: $(PUREBUILD)/q2.sha256
	@cp $(PUREWORK)/pure-vim.c pure-vim.c
	@echo
	@printf '  %-12s %s lines, from slim-vim.c\n' "pure-vim.c" \
	    "`grep -c '' pure-vim.c | sed -e :a -e 's/\(.*[0-9]\)\([0-9]\{3\}\)/\1,\2/;ta'`"

# The same per-phase handles slim.mk has: re-run one, or put the work directory
# back to what a phase receives.  Their absence was an asymmetry rather than a
# decision -- the boundaries were always there, with nothing to reach them by.
.PHONY: $(PUREPHASES:%=pure-phase-%)
$(PUREPHASES:%=pure-phase-%): pure-phase-%:
	@rm -f $(PUREBUILD)/q$*.sha256
	@$(MAKE) --no-print-directory $(PUREBUILD)/q$*.sha256

.PHONY: $(PUREPHASES:%=pure-replay-%)
$(PUREPHASES:%=pure-replay-%): pure-replay-%:
	@tools/restore.sh $(PUREBUILD)/q$*.tar $(PUREWORK)
	@echo "  replay       $(PUREWORK)/ is the tree after pure phase $*"

.PHONY: pure-times
pure-times:
	@total=0; for q in $(PUREPHASES); do \
	    [ -f $(PUREBUILD)/q$$q.seconds ] || continue; \
	    s=$$(cat $(PUREBUILD)/q$$q.seconds); total=$$((total + s)); \
	    printf '  pure %-6s %4s s  by %s\n' "$$q" "$$s" "$$(cat $(PUREBUILD)/q$$q.kind)"; \
	done; \
	printf '  %-12s %4s s\n' "total" "$$total"

# Force one when the recorded input digest already matches.
.PHONY: repure
repure:
	@rm -rf $(PUREBUILD)
	@$(MAKE) --no-print-directory pure-pass

# Both phases are programs and this pipeline has no agent in it, so a boundary
# it produced is reproducible by construction -- there is no advisory stage to
# pass through.  Recorded only after a run that built, swept to silence and
# showed exactly the declared delta.
.PHONY: pure-record
pure-record:
	@mkdir -p $(PUREORACLE)
	@for q in $(PUREPHASES); do \
	    [ -f $(PUREBUILD)/q$$q.sha256 ] || continue; \
	    cp $(PUREBUILD)/q$$q.sha256 $(PUREORACLE)/q$$q.sha256; \
	    cp $(PUREBUILD)/q$$q.sha256.files $(PUREORACLE)/q$$q.sha256.files; \
	    echo "  record       q$$q: $$(cut -c1-12 $(PUREORACLE)/q$$q.sha256)"; \
	done

.PHONY: pure-clean
pure-clean:
	rm -rf $(PUREBUILD) $(PUREWORK) pure-vim

# --- the score ------------------------------------------------------------
# Binary size and external surface, together.  The symbol set is the one that
# matters: an embedded target is defined by what it must supply, not by what it
# costs, and a phase that shrinks the binary while adding a syscall has gone
# backwards.  Both go the same way or the phase is wrong.
.PHONY: pure-score
pure-score:
	@tools/purescore.sh
