"""The set of files the build actually reads.  Measured, not guessed.

**Use `from_depfiles()` alone.**  The .d files record what the compiler opened,
which is the question being asked.  `from_make()` is kept for comparison and
must NOT be unioned with it: make's rule database answers a different question
and drags in rules for the GUI, perl, wayland and libvterm this build never
reaches -- 133 extra entries against 254 real ones in the last run.  And
xdiff.h, the classic example of a prerequisite the compiler never opens, is in
fact opened, by vim.h, for mmfile_t.

The makefile's own needs are three named files (Makefile, config.mk,
create_cmdidxs.py), not a set to compute.

Usage: keepset.py <srcdir> <objdir>
"""
import os
import re
import subprocess
import sys


def from_depfiles(objdir, srcdir):
    keep = set()
    for name in os.listdir(objdir):
        if not name.endswith('.d'):
            continue
        text = open(os.path.join(objdir, name)).read()
        text = text.replace('\\\n', ' ')
        text = text.split(':', 1)[1] if ':' in text else ''
        for tok in text.split():
            p = os.path.normpath(os.path.join(srcdir, tok)) if not \
                os.path.isabs(tok) else os.path.normpath(tok)
            if p.startswith(os.path.abspath(srcdir)) or not os.path.isabs(p):
                keep.add(os.path.relpath(p, srcdir))
    return {k for k in keep if not k.startswith('..')}


def from_make(srcdir):
    """Every prerequisite make would consider, from a dry run of the database."""
    out = subprocess.run(['make', '-C', srcdir, '-p', '-n', 'vim'],
                         capture_output=True, text=True).stdout
    keep = set()
    for line in out.splitlines():
        m = re.match(r'^([^\s#=:]+)\s*:\s*([^=].*)?$', line)
        if not m:
            continue
        for tok in (m.group(2) or '').split():
            if tok.endswith(('.c', '.h', '.pro', '.in', '.mk', '.py')):
                keep.add(tok)
    return keep


def main():
    srcdir, objdir = sys.argv[1], sys.argv[2]
    a = from_depfiles(objdir, srcdir)
    b = from_make(srcdir)
    keep = a | b
    for p in sorted(keep):
        print(p)
    print('# %d from .d files, %d from make, %d together'
          % (len(a), len(b), len(keep)), file=sys.stderr)


if __name__ == '__main__':
    main()
