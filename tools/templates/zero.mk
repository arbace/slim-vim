# zero-vim, from the one source in this directory.
#
# Whim's compile line with one flag added, and the flag is the whole of what zero's
# seed introduces: -no-pie.  gcc defaults to PIE here, so whim-vim is a static-PIE
# -- readelf -h says DYN, and it carries a dynamic section and 1,986 relative
# relocations that its own startup code applies to itself.  -no-pie makes an
# ordinary static executable: readelf -h says EXEC, there is no dynamic section and
# no relocation at all, and the image is 894,088 bytes against 955,976.  A binary
# with nothing left to relocate is one a host can place without a loader, which is
# what an embeddable core wants.  ASLR of the image is what it gives up.
#
# -O0 and -s stay whim's, for whim's reasons.  Nothing else changes here until a
# phase says so: -fno-stack-protector and the like are phases, not the seed.

CC      = gcc
CFLAGS  = -O0
LDFLAGS = -static -no-pie -s

zero-vim: zero-vim.c
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ zero-vim.c

clean:
	rm -f zero-vim

.PHONY: clean
