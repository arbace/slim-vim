# vim, from the sources in this directory.  Two targets: vim and clean.
#
# This replaces 3,570 lines of autoconf output and its config.mk.  Everything
# it dropped was either a configuration this build does not have -- GUI, perl,
# python, ruby, tcl, lua, wayland, libvterm, the terminal library -- or a
# generation rule for a file that is now a checked-in source: config.h,
# osdef.h, pathdef.c, ex_cmdidxs.h and nv_cmdidxs.h are frozen, so there is no
# configure, no shell script and nothing generated at build time.
#
# There is no -I and no -D on the compile line, and getting them off took three
# source edits rather than a relocation.  -DHAVE_CONFIG_H guards a fifty-line
# block in vim.h, which is unwrapped -- by matching its #endif, not by deleting
# its first line, which would leave that #endif to close #ifndef VIM__H three
# thousand lines early.  -Iproto was two things: proto.h now names its 97 .pro
# includes by path, and xdiff.h's "../vim.h", which only ever resolved because
# -Iproto made proto/../vim.h mean this directory, names it directly.  No
# LDLIBS either -- musl's libm is part of libc, so even -lm is unnecessary, and
# -lintl went with it.  Another libc would want both back.
#
# -O0, and no -g: this tree is rebuilt far more often than the editor it
# produces is used, and debug info records a line number for everything, which
# would make a formatting change move the binary and destroy the cheapest
# verification there is.  _FORTIFY_SOURCE went with -O2, its checks needing
# object sizes the optimiser computes.
#
# -static -s is the whole of the standalone binary.  gcc defaults to PIE here,
# so the result is a static-PIE: readelf -h still says DYN and ASLR still
# applies.  readelf -l for INTERP and readelf -d for NEEDED are the check,
# never ldd, which prints a musl line for a static-PIE that is not a
# dependency.  -s also breaks nm, so build `make LDFLAGS=-static` when you need
# symbols and `make CFLAGS=-g LDFLAGS=-static` for a DWARF dump; the .text of
# either is identical to the shipped one.
#
# The object phase stays until there is one file to compile.  Measured here,
# one gcc -O0 invocation over the 67 translation units takes 13.4 s and
# per-file objects with make -j64 and a link take 1.1 s, and the phases after
# this one rebuild constantly.
#
# Every object depends on every header and every prototype, in one line.  It is
# deliberately coarse: a full rebuild is a second, and a rule that cannot be
# stale is worth more than a precise one that can.
#
# regexp_bt.c and regexp_nfa.c are #included by regexp.c, so they are sources
# but not translation units.

CC      = gcc
CFLAGS  = -O0
LDFLAGS = -static -s

SRC = $(filter-out regexp_bt.c regexp_nfa.c,$(wildcard *.c))
OBJ = $(SRC:%.c=objects/%.o)

vim: $(OBJ)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $(OBJ)

$(OBJ): objects/%.o: %.c $(wildcard *.h proto/*.pro) | objects
	$(CC) $(CFLAGS) -c -o $@ $<

objects:
	mkdir -p objects

clean:
	rm -rf objects vim

.PHONY: clean
