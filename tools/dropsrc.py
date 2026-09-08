"""Remove a .c file from the build: the file, its .pro, and every mention.

A source appears in more places than is obvious -- the SRC list, the OBJ list,
the .pro list, its build rule and its proto rule.  Missing one leaves either a
dangling prerequisite or a silently-still-linked object.

Usage: dropsrc.py <srcdir> <name-without-.c> ...
"""
import os
import re
import sys


def drop(srcdir, name):
    mk = os.path.join(srcdir, 'Makefile')
    s = open(mk).read()
    n = 0
    # List entries: a whole line naming the file, continuation backslash and all.
    for pat in (r'^[ \t]*%s\.c[ \t]*\\?\n' % re.escape(name),
                r'^[ \t]*objects/%s\.o[ \t]*\\?\n' % re.escape(name),
                r'^[ \t]*proto/%s\.pro[ \t]*\\?\n' % re.escape(name)):
        s, k = re.subn(pat, '', s, flags=re.M)
        n += k
    # Rules with their recipes.
    for pat in (r'^objects/%s\.o:[^\n]*\n(?:\t[^\n]*\n)*\n?' % re.escape(name),
                r'^proto/%s\.pro:[^\n]*\n(?:\t[^\n]*\n)*\n?' % re.escape(name)):
        s, k = re.subn(pat, '', s, flags=re.M)
        n += k
    open(mk, 'w').write(s)
    for p in (os.path.join(srcdir, name + '.c'),
              os.path.join(srcdir, 'proto', name + '.pro')):
        if os.path.exists(p):
            os.remove(p)
            n += 1
    return n


def main():
    srcdir = sys.argv[1]
    total = 0
    for name in sys.argv[2:]:
        k = drop(srcdir, name)
        total += k
        print('  %-22s %d mentions removed' % (name, k))
    print('%d sources dropped' % (len(sys.argv) - 2))


if __name__ == '__main__':
    main()
