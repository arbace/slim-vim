"""Regenerate ex_cmdidxs.h and require it byte-identical.

Upstream generates this with create_cmdidxs.vim, which needs a vim with +eval;
this build has none, so the generator is here.  Its value is as a canary: it
parses the command table and reproduces a checked-in file exactly, so a pass
that quietly reshapes the table -- or merely re-indents a line of it -- shows
up as a diff instead of as a wrong answer months later.

Importing does nothing.  Call names_from() then generate().
"""
import re
import sys

LETTERS = 'abcdefghijklmnopqrstuvwxyz'


def names(path):
    """Command names in table order, whichever shape the table is in.

    The table has been an X-macro (EXCMD rows) and a written-out cmdnames[]
    with designated initialisers.  Try both and take whichever parses; asking
    by file name stopped working when there was only one file.

    The 600 EXCMD rows appear twice in the merged file, once per reading of
    what was ex_cmds.h, so take the first run of them.
    """
    for fn in (names_from_cmdnames, names_from_ex_cmds_h):
        got = fn(path, check=False)
        if len(got) >= 100:
            if fn is names_from_ex_cmds_h and len(got) > 600:
                got = got[:len(got) // 2]
            return got
    raise SystemExit('%s: no command table found in either shape' % path)


def names_from_ex_cmds_h(path, check=True):
    """Command names, in table order, from EXCMD rows."""
    text = open(path, errors='surrogateescape').read()
    names = re.findall(r'^EXCMD\(\s*CMD_\w+\s*,\s*"((?:[^"\\]|\\.)*)"',
                       text, re.M)
    if check:
        _check(names, path)
    return names


def names_from_cmdnames(path, check=True):
    """Command names from a written-out cmdnames[] with designated rows."""
    text = open(path, errors='surrogateescape').read()
    names = re.findall(r'\[CMD_\w+\] = \{\(char_u \*\)"((?:[^"\\]|\\.)*)"', text)
    if check:
        _check(names, path)
    return names


def _check(names, path):
    # A regex that stops matching after an edit to the table's shape yields an
    # empty list, and from it a plausible-looking all-zero index.  Refuse.
    if len(names) < 100:
        raise SystemExit('%s: parsed only %d command names; the table does '
                         'not have the expected shape' % (path, len(names)))


def generate(names):
    idx1 = []
    for c in LETTERS:
        idx1.append(next((i for i, n in enumerate(names)
                          if n.startswith(c)), 0))
    idx2 = []
    for a, c1 in enumerate(LETTERS):
        row = []
        for c2 in LETTERS:
            first = next((i for i, n in enumerate(names)
                          if n.startswith(c1 + c2)), None)
            row.append(0 if first is None else first - idx1[a])
        idx2.append(row)

    # The tree carries no comments, so neither does what is written into it:
    # both tables are indexed by letter, a first and z last.  The banner and
    # the per-letter labels this file used to carry went with every other
    # comment; if they ever come back, re-validate against the checked-in file.
    o = []
    o.append('static const unsigned short cmdidxs1[26] =\n{\n')
    for i in range(26):
        o.append('    %d%s\n' % (idx1[i], ',' if i < 25 else ''))
    o.append('};\n')
    o.append('\n')
    o.append('static const unsigned char cmdidxs2[26][26] =\n{\n')
    for i in range(26):
        vals = ', '.join('%2d' % v for v in idx2[i])
        o.append('    { %s }%s\n' % (vals, ',' if i < 25 else ''))
    o.append('};\n')
    o.append('\n')
    o.append('static const int command_count = %d;\n' % len(names))
    return ''.join(o)


BEGIN = '// ---------------- begin ex_cmdidxs.h ----------------'
END = '// ---------------- end ex_cmdidxs.h ----------------'


def block_of(path):
    """The generated block as it currently stands in the file."""
    lines = open(path, encoding='utf-8', errors='surrogateescape').read().split('\n')
    i, j = lines.index(BEGIN), lines.index(END)
    return '\n'.join(lines[i + 1:j]) + '\n'


def update(path):
    lines = open(path, encoding='utf-8', errors='surrogateescape').read().split('\n')
    i, j = lines.index(BEGIN), lines.index(END)
    lines[i + 1:j] = generate(names(path)).split('\n')[:-1]
    open(path, 'w', encoding='utf-8', errors='surrogateescape').write('\n'.join(lines))


if __name__ == '__main__':
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    src = args[0] if args else 'vim.c'
    if '--update' in sys.argv[1:]:
        update(src)
    elif '--check' in sys.argv[1:]:
        want = generate(names(src))
        got = block_of(src)
        if want != got:
            sys.stderr.write('%s: the generated table does not match the source\n' % src)
            raise SystemExit(1)
        print('%s: ex_cmdidxs block reproduces byte for byte' % src)
    else:
        sys.stdout.write(generate(names(src)))
