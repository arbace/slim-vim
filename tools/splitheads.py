"""Put the body of a control statement on its own line.

`if (x) return;` becomes two lines.  Bracing is much simpler once every body
starts on a line of its own, and "one statement per line" wants this anyway.

Two things must not be split:
  * `} while (cond);` -- the tail of a do-while, not a head with a body;
  * `else if (...)`   -- one statement, not an else with an if body.

Usage: splitheads.py <file>
"""
import re
import sys

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cutil

HEAD = re.compile(r'^(\s*)(if|for|while|switch)\s*\(')
ELSE = re.compile(r'^(\s*)else\b')
DO = re.compile(r'^(\s*)do\b')


def main():
    path = sys.argv[1]
    lines = open(path, encoding='utf-8', errors='surrogateescape').read().split('\n')
    out = []
    split = 0
    for line in lines:
        stripped = line.strip()
        if stripped.startswith('#') or stripped.startswith('//') or not stripped:
            out.append(line)
            continue
        m = HEAD.match(line)
        if m and not line.lstrip().startswith('}'):
            b = cutil.blank(line)
            open_i = b.index('(', m.end(2) - 1 if False else len(m.group(1)) + len(m.group(2)))
            close_i = cutil.match(line, open_i, b)
            if close_i < 0:
                out.append(line)
                continue
            tail = line[close_i + 1:].strip()
            if tail and tail != '{':
                out.append(line[:close_i + 1])
                out.append(m.group(1) + '    ' + tail)
                split += 1
                continue
            out.append(line)
            continue
        m = ELSE.match(line)
        if m:
            tail = line[m.end():].strip()
            if tail and tail != '{' and not re.match(r'^if\b', tail):
                out.append(m.group(1) + 'else')
                out.append(m.group(1) + '    ' + tail)
                split += 1
                continue
            out.append(line)
            continue
        m = DO.match(line)
        if m:
            tail = line[m.end():].strip()
            if tail and tail != '{':
                out.append(m.group(1) + 'do')
                out.append(m.group(1) + '    ' + tail)
                split += 1
                continue
        out.append(line)
    text = '\n'.join(out)
    if not text.endswith('\n'):
        text += '\n'
    open(path, 'w', encoding='utf-8', errors='surrogateescape').write(text)
    print('%d bodies moved onto their own line; %d lines -> %d'
          % (split, len(lines), len(out)))


if __name__ == '__main__':
    main()
