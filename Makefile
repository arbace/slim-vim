# One product, two targets.  There is no configure, nothing is generated, and
# no shell script runs.
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
# but itself, which the one rule already says; there is no dependency block and
# no object phase, and "make clean && make" is a real from-scratch rebuild.

CC      = gcc
CFLAGS  = -O0
LDFLAGS = -static -s

vim: vim.c
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $<

clean:
	rm -f vim

.PHONY: clean
