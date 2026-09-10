"""Collapse runs of more than one blank line to a single one.

A blank line is one with nothing but whitespace on it; the collapsed survivor
is written empty, which is what the rest of the file already is.

Usage: blankruns.py <file>
"""
import sys


def main():
    path = sys.argv[1]
    text = open(path, encoding='utf-8', errors='surrogateescape').read()
    lines = text.split('\n')
    out = []
    runs = 0
    dropped = 0
    prev_blank = False
    for line in lines:
        if not line.strip():
            if prev_blank:
                dropped += 1
                continue
            prev_blank = True
            out.append('')
            continue
        prev_blank = False
        out.append(line)
    # count runs for the report
    n, i = 0, 0
    while i < len(lines):
        if not lines[i].strip():
            j = i
            while j < len(lines) and not lines[j].strip():
                j += 1
            if j - i > 1:
                n += 1
            i = j
            continue
        i += 1
    runs = n
    res = '\n'.join(out)
    if not res.endswith('\n'):
        res += '\n'
    open(path, 'w', encoding='utf-8', errors='surrogateescape').write(res)
    print('%d runs of >1 blank line collapsed, %d lines dropped; %d lines -> %d'
          % (runs, dropped, len(lines), len(out)))


if __name__ == '__main__':
    main()
