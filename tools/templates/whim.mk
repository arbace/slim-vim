# whim-vim, from the one source in this directory.
#
# The same compile line as slim-vim: -O0 because this tree is rebuilt far more
# often than the editor is run, -static -s for a binary with nothing to resolve.
# WHIM-GOAL.md says optimisation comes last, deliberately -- a shipped embedded
# binary wants different flags, and choosing them before the shape has settled
# optimises the wrong thing.

CC      = gcc
CFLAGS  = -O0
LDFLAGS = -static -s

whim-vim: whim-vim.c
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ whim-vim.c

clean:
	rm -f whim-vim

.PHONY: clean
