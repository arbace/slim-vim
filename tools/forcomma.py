"""Hoist comma operators out of `for` init clauses.

`for (n1 = 0, n2 = 0; ...)` becomes `n1 = 0;` on its own line and
`for (n2 = 0; ...)`.  Every initialiser but the last is hoisted; the last stays
so the head keeps an init clause.

Declined, and the line then put back byte for byte:
  * an init clause that *declares* -- `for (int i = n, j = m; ...)` scopes i and
    j to the loop, and hoisting widens that to the enclosing block, which is a
    change in meaning and not a formatting one;
  * an init clause containing a call or a cast, which is what a `(` inside it
    means here.

Safe only after bracing: every body is a brace block, so a statement inserted
before the `for` lands inside the same block the `for` is in.

Increment clauses are left alone -- they run on `continue` too.

Usage: forcomma.py <file> [--check]
"""
import re
import sys

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cutil

FOR = re.compile(r'^(\s*)for\s*\(')
IDENT = re.compile(r'[A-Za-z_]\w*')
TYPEWORD = re.compile(
    r'^(static|const|volatile|unsigned|signed|struct|union|enum|register|'
    r'auto|extern|short|long|int|char|float|double|void)\b')


def init_clause(line):
    """(open, close, init_start, init_end) for the `for` head on `line`."""
    m = FOR.match(line)
    if not m:
        return None
    b = cutil.blank(line)
    o = b.index('(', m.end() - 1)
    c = cutil.match(line, o, b)
    if c < 0:
        return None
    inner = line[o + 1:c]
    ib = cutil.blank(inner)
    d = cutil.depths(ib)
    semi = -1
    for j in range(len(ib)):
        if ib[j] == ';' and d[j] == 0:
            semi = j
            break
    if semi < 0:
        return None
    return (o, c, o + 1, o + 1 + semi)


def hoist(line):
    """[lines] if the head was rewritten, else None (line left untouched)."""
    r = init_clause(line)
    if r is None:
        return None
    o, c, a, z = r
    init = line[a:z]
    if not init.strip():
        return None
    ib = cutil.blank(init)
    parts = cutil.split_top(init, ',', ib)
    if len(parts) < 2:
        return None
    if '(' in ib:
        return None                      # a call or a cast: decline
    head = parts[0].strip()
    eq = cutil.find_top(head, '=')
    core = head[:eq] if eq >= 0 else head
    if TYPEWORD.match(core.strip()) or len(IDENT.findall(core)) > 1:
        return None                      # declares: hoisting would widen scope
    indent = FOR.match(line).group(1)
    out = [indent + p.strip() + ';' for p in parts[:-1]]
    out.append(line[:a] + parts[-1].strip() + line[z:])
    return out


def main():
    path = sys.argv[1]
    check = '--check' in sys.argv[2:]
    lines = open(path, encoding='utf-8', errors='surrogateescape').read().split('\n')
    out, hoisted, declined = [], 0, 0
    for line in lines:
        r = init_clause(line)
        if r is not None:
            init = line[r[2]:r[3]]
            if len(cutil.split_top(init, ',')) > 1:
                got = hoist(line)
                if got is None:
                    declined += 1
                else:
                    hoisted += 1
                    if not check:
                        out.extend(got)
                        continue
        out.append(line)
    text = '\n'.join(out)
    if not text.endswith('\n'):
        text += '\n'
    if not check:
        open(path, 'w', encoding='utf-8', errors='surrogateescape').write(text)
    print('%d init clauses with a comma: %d hoisted, %d declined; %d lines -> %d'
          % (hoisted + declined, hoisted, declined, len(lines), len(out)))


if __name__ == '__main__':
    main()
