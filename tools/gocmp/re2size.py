"""Size the RE2 problem in pipes/, split by COST and by EDIT-vs-CHECK.

Usage: python3 tools/gocmp/re2size.py       (run from the repository root)

Go's regexp has no lookaround of either kind and no back-reference inside a
pattern, by design -- it is what buys the linear-time guarantee.  A raw count
of the heredocs that use one is not a size, because the constructs differ in
cost by an order of magnitude, and because a cost landing in a CHECK part is
not a cost of the port at all if check parts stay shell.

Three classes, named for what the six already-ported cutters needed:

  local   a lookaround whose body is ONE character class or one short literal:
          (?<!_)\\bX\\b, (?<![\\w.>])X\\s*\\(, (?=[,)]).  It becomes "test the
          bytes either side", which is what nobackup and noconv already do.
          Five of the six were this.
  other   a lookaround whose body is longer -- an alternation of literal
          prefixes, a marker in a split.  Anchored ones become a HasPrefix
          test over the line, which is what noarglist and nowindows already do.
  pback   a back-reference INSIDE a pattern, (?P=name) or \\1.  This is the one
          RE2 genuinely cannot express.  A \\1 in a REPLACEMENT is not this --
          Go spells it $1 and it is a transliteration, not a rewrite -- so the
          two are counted apart, which a grep for backslash-one does not do.

WHAT THIS DOES NOT MEASURE: whether a rewrite is correct.  Expressible is not
free, and every ported heredoc still owes its per-phase boundary gate.  The
claim here is only about which ones need a hand-written scanner, which is the
question that has to be answered before anyone commits to the work rather than
discovered partway through it.
"""
import collections
import pathlib
import re
import sys

ROOT = pathlib.Path('pipes')

LOCAL = re.compile(r'\(\?<?[!=](\[[^\]]*\]|\\?[A-Za-z0-9_=!<>.*]|[A-Za-z0-9_]{1,3})\)')
ANY = re.compile(r'\(\?<[!=]|\(\?[!=]')
PBACK = re.compile(r'\(\?P=')


def kindof(name):
    if name.endswith('-edit.sh'):
        return 'edit'
    if name.endswith('-check.sh'):
        return 'check'
    return 'whole'


def heredocs(path):
    """Yield the body of each PY heredoc in a phase program."""
    lines = path.read_text(errors='surrogateescape').split('\n')
    i = 0
    while i < len(lines):
        m = re.search(r"<<'(PY|ZPY|PYEOF)'\s*$", lines[i])
        if m:
            tag, j, body = m.group(1), i + 1, []
            while j < len(lines) and lines[j] != tag:
                body.append(lines[j])
                j += 1
            yield body
            i = j
        i += 1


def main():
    if not ROOT.is_dir():
        sys.exit('re2size: run me from the repository root')
    rows = collections.defaultdict(collections.Counter)
    hard = collections.defaultdict(set)
    seen = collections.Counter()

    for f in sorted(ROOT.glob('*.sh')):
        k = kindof(f.name)
        for body in heredocs(f):
            seen[k] += 1
            text = '\n'.join(body)
            total, local = len(ANY.findall(text)), len(LOCAL.findall(text))
            pb = len(PBACK.findall(text))
            rows[k]['heredocs-with-any'] += 1 if (total or pb) else 0
            rows[k]['lookaround'] += total
            rows[k]['local'] += local
            rows[k]['other'] += total - local
            rows[k]['pback'] += pb
            if total - local or pb:
                hard[k].add(f.name)

    print('%-7s %8s %11s %7s %7s %7s' %
          ('', 'heredocs', 'lookaround', 'local', 'other', 'pback'))
    for k in ('edit', 'check', 'whole'):
        r = rows[k]
        print('%-7s %8d %11d %7d %7d %7d' %
              (k, seen[k], r['lookaround'], r['local'], r['other'], r['pback']))
    print()
    for k in ('edit', 'check', 'whole'):
        if hard[k]:
            print('%s parts needing more than a byte test:' % k)
            for n in sorted(hard[k]):
                print('    ' + n)
    if not any(rows[k]['lookaround'] for k in rows):
        sys.exit('re2size: found no lookaround at all -- the scan is broken, not the tree')


if __name__ == '__main__':
    main()
