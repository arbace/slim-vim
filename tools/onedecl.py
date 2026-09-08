"""One declarator per declaration.

`int a, b;` becomes two lines, so the unused-variable sweep deletes a line
instead of having to rewrite one.

Deliberately conservative.  A line is a candidate only if it ends in `;`, has a
top-level comma, has **no** top-level parenthesis (which rules out prototypes,
calls and function-pointer declarators), and every declarator after the type
looks like one.  Commas inside braces are not top-level, so an initialiser list
and an enum body are untouched.

The type prefix ends where the first declarator's name begins: find the last
identifier before any `[` or `=`, then back up over the `*`s that bind to it --
`char *a, b;` really does declare a pointer and a char.

Usage: onedecl.py <file>
"""
import re
import sys

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cutil

DECLARATOR = re.compile(r'^\**\s*[A-Za-z_]\w*(\s*\[[^\]]*\])*(\s*=\s*.+)?$', re.S)
IDENT = re.compile(r'[A-Za-z_]\w*')
KEYWORD_START = re.compile(
    r'^(static|const|volatile|unsigned|signed|struct|union|enum|register|'
    r'extern|short|long|int|char|float|double|void|size_t|[A-Za-z_]\w*)\b')


def split_decl(line):
    s = line.rstrip()
    body = s.strip()
    if not body.endswith(';') or body.startswith('#') or body.startswith('//'):
        return None
    if not KEYWORD_START.match(body):
        return None
    indent = s[:len(s) - len(s.lstrip())]
    inner = body[:-1]
    b = cutil.blank(inner)
    d = cutil.depths(b)
    if any(b[j] in '()' for j in range(len(b))):
        return None
    commas = [j for j in range(len(b)) if b[j] == ',' and d[j] == 0]
    if not commas:
        return None
    parts, start = [], 0
    for j in commas:
        parts.append(inner[start:j])
        start = j + 1
    parts.append(inner[start:])
    first = parts[0]
    fb = cutil.blank(first)
    fd = cutil.depths(fb)
    cut = len(first)
    for j in range(len(fb)):
        if fd[j] == 0 and fb[j] in '[=':
            cut = j
            break
    core = first[:cut]
    ids = list(IDENT.finditer(core))
    if len(ids) < 2:
        return None                 # a type and a name, at least
    k = ids[-1].start()
    while k > 0 and core[k - 1] in ' \t*':
        k -= 1
    type_prefix = first[:k].rstrip()
    if not type_prefix or not IDENT.search(type_prefix):
        return None
    for p in parts[1:]:
        if not DECLARATOR.match(p.strip()):
            return None
    out = [indent + type_prefix + ' ' + first[k:].strip() + ';']
    for p in parts[1:]:
        out.append(indent + type_prefix + ' ' + p.strip() + ';')
    return out


def main():
    path = sys.argv[1]
    lines = open(path, encoding='utf-8', errors='surrogateescape').read().split('\n')
    out, changed = [], 0
    for line in lines:
        got = split_decl(line)
        if got:
            out.extend(got)
            changed += 1
        else:
            out.append(line)
    text = '\n'.join(out)
    if not text.endswith('\n'):
        text += '\n'
    open(path, 'w', encoding='utf-8', errors='surrogateescape').write(text)
    print('%d declarations split; %d lines -> %d' % (changed, len(lines), len(out)))


if __name__ == '__main__':
    main()
