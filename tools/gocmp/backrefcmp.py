"""Can capture-and-compare replace the one construct RE2 cannot express?

Usage: python3 tools/gocmp/backrefcmp.py       (run from the repository root)

pipes/whim72-edit.sh is the only EDIT part in the tree with a back-reference
inside a pattern.  It matches expanded FOR_ALL_* macros, where the same
identifier recurs four or five times in one `for` header:

    for \\(\\((?P<v>\\w+)\\) = firstwin; \\((?P=v)\\) != NULL; ...

RE2 has no back-reference, so the substitute is to capture each occurrence
separately and require them equal in the caller.  THAT SUBSTITUTE IS NOT VALID
IN GENERAL -- a capturing rewrite consumes its delimiters, so two matches
sharing one would lose the second, which is why tools/README.md records that
nobackup and noconv test bytes instead of capturing.  Here the matches are
whole `for` headers and non-overlapping by construction, which is why it should
hold; this measures that it does.

TWO HALVES, AND THE SECOND IS THE ONE THAT MATTERS.  On the real tree the
equality constraint rejects NOTHING -- every raw RE2 match already has equal
groups -- so agreement there shows only that the rewrite loses no match, not
that the constraint does anything.  A synthetic header whose variables differ
is what shows the constraint discriminates.  Without it this would be a
comparison that agrees because it compared nothing, which is the defect
tools/gocmp/CUTTERS.md found in ten cutters at once.
"""
import pathlib
import re
import subprocess
import sys
import tempfile

PY = {
    'NESTED': (r'for \(\((?P<v>\w+)\) = \(\((?P<tv>\w+)\) == (?:NULL \|\| \((?P=tv)\) == )?curtab\)'
               r' *\? firstwin : \((?P=tv)\)->tp_firstwin; \((?P=v)\); \((?P=v)\) = \((?P=v)\)->w_next\)'),
    'TABS': (r'for \(\((?P<v>\w+)\) = first_tabpage; \((?P=v)\) != NULL;'
             r' \((?P=v)\) = \((?P=v)\)->tp_next\)'),
    'WINS': (r'for \(\((?P<v>\w+)\) = firstwin; \((?P=v)\) != NULL;'
             r' \((?P=v)\) = \((?P=v)\)->w_next\)'),
}

RE2 = {
    'NESTED': (r'for \(\((\w+)\) = \(\((\w+)\) == (?:NULL \|\| \((\w+)\) == )?curtab\)'
               r' *\? firstwin : \((\w+)\)->tp_firstwin; \((\w+)\); \((\w+)\) = \((\w+)\)->w_next\)'),
    'TABS': (r'for \(\((\w+)\) = first_tabpage; \((\w+)\) != NULL;'
             r' \((\w+)\) = \((\w+)\)->tp_next\)'),
    'WINS': (r'for \(\((\w+)\) = firstwin; \((\w+)\) != NULL;'
             r' \((\w+)\) = \((\w+)\)->w_next\)'),
}


def keep(name, m):
    g = m.groups()
    if name in ('TABS', 'WINS'):
        return len(set(g)) == 1
    vs = [g[0], g[4], g[5], g[6]]
    tvs = [x for x in (g[1], g[2], g[3]) if x is not None]
    return len(set(vs)) == 1 and len(set(tvs)) == 1


def main():
    tar = pathlib.Path('.build-whim/q71.tar')
    if not tar.is_file():
        sys.exit('backrefcmp: %s is not here -- whim phase 72 runs on stage 66-71\'s\n'
                 'output, so that boundary is the tree this measures against.' % tar)
    with tempfile.TemporaryDirectory() as d:
        subprocess.run(['tar', 'xf', str(tar), '-C', d], check=True)
        src = pathlib.Path(d, 'whim-vim.c').read_text(errors='surrogateescape')

    bad = 0
    fired = 0
    for name in ('NESTED', 'TABS', 'WINS'):
        py = [(m.start(), m.end()) for m in re.finditer(PY[name], src)]
        raw = list(re.finditer(RE2[name], src))
        kept = [(m.start(), m.end()) for m in raw if keep(name, m)]
        fired += len(raw) - len(kept)
        ok = py == kept
        bad += 0 if ok else 1
        print('%-7s backref %3d   capture-and-compare %3d   (raw RE2 %3d)  %s'
              % (name, len(py), len(kept), len(raw), 'SAME' if ok else 'DIFFER'))

    print('the equality rejected %d of the tree\'s matches' % fired)

    # The control: on the real tree the constraint may reject nothing, so prove
    # separately that it CAN.
    good = "for ((wp) = firstwin; (wp) != NULL; (wp) = (wp)->w_next)\n"
    bad_s = "for ((wp) = firstwin; (zz) != NULL; (wp) = (wp)->w_next)\n"
    for label, s, want in (('matching vars', good, 1), ('mismatched vars', bad_s, 0)):
        p = len(re.findall(PY['WINS'], s))
        raw = list(re.finditer(RE2['WINS'], s))
        k = [m for m in raw if keep('WINS', m)]
        agree = (p == len(k) == want)
        print('control %-16s backref=%d raw-RE2=%d capture-and-compare=%d  %s'
              % (label, p, len(raw), len(k), 'AGREE' if agree else 'DISAGREE'))
        if not agree:
            bad += 1
    sys.exit(1 if bad else 0)


if __name__ == '__main__':
    main()
