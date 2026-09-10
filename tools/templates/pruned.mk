# vim, from the sources in this directory, while the tree is being pruned.
#
# Phase 2 installs this INSTEAD of editing upstream's 3,570-line makefile, and
# Phase 3 replaces it with the final one -- so nothing here survives two
# phases.  That is the whole argument for it: the surgery it avoids is the
# fiddliest work in the pass, and none of its results outlive the phase after
# it.  Measured: p2 and p3 differ in exactly five files, and the makefile is
# one of them.
#
# What the surgery involved, and is now simply not done: five things had to go
# before upstream's makefile would run at all (the hand-written dependency
# block, TOOLS/xxd, two `include`s, $(TERM_DEPS) and $(XDIFF_INCL), $(MKDIR_P)),
# the SRC, OBJ and .pro lists needed an entry removed per dropped source, and
# sixteen rules end `cd <dir>; $(MAKE) ...` -- once the prune deletes those
# directories the `cd` fails, the `;` runs $(MAKE) in the same directory on the
# same makefile, and it recurses.  `make clean` alone reached 50,106 processes
# and a load average of 1,400.  A wildcard makefile has no lists to edit and no
# recursion to remove.
#
# -I. -Iproto -DHAVE_CONFIG_H are still needed at this point.  Phase 3 is what
# removes the need for them, by unwrapping the config block in vim.h and naming
# the .pro includes by path.

CC      = gcc
CFLAGS  = -O0 -I. -Iproto -DHAVE_CONFIG_H

# SRC is not a wildcard.  Every .c in this directory is not a source of this
# build -- the GUI, the language bindings and the other platforms are all still
# here at this point -- and the authoritative list of what IS one is the set of
# objects the previous phase's build left behind.  phase2.sh writes it out.
include srcs.mk
OBJ = $(SRC:%.c=objects/%.o)

# Compiling is what this phase measures: -MD makes each object record every
# file the compiler opened, which is the keep-set, and an object with no
# defined symbols says its source compiles to nothing.  Linking is worth doing
# once, at the end, so it is not the default target.
compile: $(OBJ)

vim: $(OBJ)
	$(CC) $(CFLAGS) -o $@ $(OBJ)

$(OBJ): objects/%.o: %.c | objdir
	$(CC) $(CFLAGS) -MD -MP -c -o $@ $<

objdir:
	@mkdir -p objects

clean:
	rm -rf objects vim

.PHONY: compile objdir clean
