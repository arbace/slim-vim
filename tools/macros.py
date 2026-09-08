"""Inventory the #define directives.

Count them with `^[[:space:]]*#[[:space:]]*define`, never `^#define`.
Whitespace between `#` and the keyword is insignificant to C, and this file has
plenty of `# define` -- what the conditional-resolution pass left when it
dedented `#  define` by one level and stopped.

Importing does nothing.
"""
import re

DEFINE = re.compile(r'^[ \t]*#[ \t]*define[ \t]+(\w+)(\()?')
INT = re.compile(r'^[+-]?(0[xX][0-9a-fA-F]+|0[bB][01]+|\d+)[uUlL]*$')
STR = re.compile(r'^"([^"\\]|\\.)*"$')
CHAR = re.compile(r"^'([^'\\]|\\.)*'$")


def parse(path):
    """[(lineno, name, params or None, body)]"""
    out = []
    for i, line in enumerate(open(path, encoding='utf-8', errors='surrogateescape'), 1):
        m = DEFINE.match(line)
        if not m:
            continue
        name = m.group(1)
        rest = line[m.end(1):].rstrip('\n')
        params = None
        if rest.startswith('('):
            depth = 0
            for j, c in enumerate(rest):
                if c == '(':
                    depth += 1
                elif c == ')':
                    depth -= 1
                    if depth == 0:
                        params = [p.strip() for p in rest[1:j].split(',') if p.strip()]
                        rest = rest[j + 1:]
                        break
        out.append((i, name, params, rest.strip()))
    return out


def classify(body):
    b = body.strip()
    if b == '':
        return 'empty'
    if INT.match(b):
        return 'int'
    if STR.match(b):
        return 'string'
    if CHAR.match(b):
        return 'char'
    return 'expr'
