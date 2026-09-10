# One product, and the process that produces it.
#
# This makefile is not derived from upstream and is not a product of a pass --
# it is part of the seed, alongside .gitignore, README.md, CLAUDE.md, GOAL.md
# and tools/, and it is what drives a pass.  A pass must never write over it.
#
# slim-vim.c depends on upstream, which is a remote, so the dependency is the branch
# head at github.com/arbace/vim -- consulted on every make, whether it has
# moved or not.  It cannot be a timestamp: git clone writes every file at
# checkout time in arbitrary order, so a stamp file landing a second after
# slim-vim.c would fire a whole pass on a tree that is exactly right.  What decides
# is content -- the sha recorded in upstream.sha, which is written only after a
# pass has succeeded, so a failed pass leaves the record alone and the next
# make retries.
#
# The pass itself is in pass.mk: ten phases, each a make target whose
# prerequisite is the previous phase's boundary.  A phase is run by a program
# if tools/phase<N>.sh exists and by an agent if it does not, so converting a
# phase to a deterministic one is adding a file rather than editing anything
# here.  That conversion is the direction of travel; GOAL.md measures where the
# hour goes and what each phase is worth.
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
# One gcc invocation.  slim-vim.c includes no local header, so it depends on nothing
# but itself and the upstream it was produced from; there is no dependency
# block and no object phase, and "make clean && make" is a real from-scratch
# rebuild.

CC      = gcc
CFLAGS  = -O0
LDFLAGS = -static -s

UPSTREAM_URL    = https://github.com/arbace/vim
UPSTREAM_BRANCH = regexp-delimiter-atoms

include pass.mk

# The default goal is the first target make sees, and `include` is where make
# sees pass.mk's -- so without this line a bare `make` builds the first phase
# boundary instead of the editor, and says "no upstream/" on a tree that needs
# nothing.  Naming it is also just true: `make` here has always meant `make
# slim-vim`.
.DEFAULT_GOAL := slim-vim

# Announced rather than echoed.  make's own echo prints the command and nothing
# else; what is worth knowing is that it finished, how big the result is, and
# that it really is standalone -- readelf, never ldd, which prints a musl line
# for a static-PIE that is not a dependency.
slim-vim: slim-vim.c
	@printf '  %-12s %s\n' "compiling" "$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $<"
	@t0=`date +%s`; $(CC) $(CFLAGS) $(LDFLAGS) -o $@ $<; \
	 printf '  %-12s %s bytes, static-PIE, %ss\n' "$@" \
	     "`stat -c%s $@ | sed -e :a -e 's/\(.*[0-9]\)\([0-9]\{3\}\)/\1,\2/;ta'`" \
	     "$$((`date +%s` - t0))"

# A phony prerequisite, so the freshness question is asked on every make; the
# answer is decided inside the recipe by content, never by a timestamp.  When
# the recipe leaves slim-vim.c alone, make re-stats it, sees it unmoved, and does
# not relink vim either.
#
# The recursive make is what runs the pass.  SLIM_VIM_PASS is passed down for
# the same reason it is tested at the top: the phases build the editor
# constantly, and a `make` from inside one must not come back here and ask
# github what the branch head is.
slim-vim.c: force
	@set -e; set -o pipefail; \
	if [ -n "$$SLIM_VIM_PASS" ]; then \
	    echo "  upstream     not probed -- already inside a pass"; \
	    exit 0; \
	fi; \
	live=`GIT_TERMINAL_PROMPT=0 timeout 60 git ls-remote $(UPSTREAM_URL) $(UPSTREAM_BRANCH) 2>/dev/null | cut -f1` || true; \
	if [ -z "$$live" ]; then \
	    echo "  upstream     UNREACHABLE -- building the committed slim-vim.c"; \
	    exit 0; \
	fi; \
	if [ -f $@ ] && [ "$$live" = "`cat upstream.sha 2>/dev/null`" ]; then \
	    printf '  %-12s %s unchanged -- slim-vim.c is current\n' "upstream" "`echo $$live | cut -c1-12`"; \
	    exit 0; \
	fi; \
	printf '  %-12s %s -- moved; slim-vim.c must be produced\n' "upstream" "`echo $$live | cut -c1-12`"; \
	tools/preflight.sh; \
	$(MAKE) --no-print-directory clone; \
	start=`date +%s`; \
	echo "  pass         started `date -Is`"; \
	$(MAKE) --no-print-directory SLIM_VIM_PASS=$$live passorref; \
	$(MAKE) --no-print-directory record; \
	$(MAKE) --no-print-directory times; \
	$(MAKE) --no-print-directory SLIM_VIM_PASS=$$live docs-if-changed; \
	now=`date +%s`; elapsed=$$((now - start)); \
	echo "  pass         finished `date -Is`, $$(($$elapsed / 3600))h $$((($$elapsed % 3600) / 60))m $$(($$elapsed % 60))s"; \
	test -f $@; \
	rm -rf $(WORK); \
	echo "$$live" > upstream.sha

clean:
	rm -f slim-vim

force: ;

.PHONY: clean force
