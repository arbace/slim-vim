# vim, from the one source in this directory.  Two targets: vim and clean.
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
# -lintl went with it.  Another libc would want both back.  The four files
# named above are inside vim.c now, under their own banners, and so are the
# frozen sources: the merge absorbed all 162 of them.
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
# The object phase is gone with the merge: there is one file to compile, so a
# separate compile and link would write an object nothing else ever reads.  One
# gcc invocation turns vim.c straight into vim in about 8 s, which is also the
# whole of what `clean` has to remove, and `make clean && make` is a real
# from-scratch rebuild in one command.  -j has nothing left to parallelise.
#
# The dependency is one file and cannot be stale, so there is no dependency
# block and nothing to generate one from.

CC      = gcc
CFLAGS  = -O0
LDFLAGS = -static -s

vim: vim.c
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ vim.c

clean:
	rm -f vim

.PHONY: clean
