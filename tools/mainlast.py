#!/usr/bin/env python3
"""Move main() to the end of its file.

Usage:
    python3 tools/mainlast.py <main.c>

main.c has functions after main(), and the finished vim.c ends with main()'s
closing brace -- which is a property worth having deliberately rather than by
accident: it is the one place a reader can be certain they have reached the
end of the program rather than the end of a file that happened to be last.

The extent is found by brace matching, not by a regex.  cutil.find_definition
returns the whole definition including its return type and any preceding
attributes, so what moves is the function and nothing else.
"""

import sys
from pathlib import Path

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cutil


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    text = path.read_text(errors='surrogateescape')

    span = cutil.find_definition(text, 'main')
    if span is None:
        sys.exit('mainlast: no definition of main() in %s' % path)
    start, end = span

    body = text[start:end]
    rest = text[:start] + text[end:]
    rest = rest.rstrip('\n') + '\n'
    out = rest + '\n' + body.strip('\n') + '\n'
    path.write_text(out, errors='surrogateescape')

    moved = text[end:].count('\n')
    print('  main last    moved past %d lines; the file now ends with its brace'
          % moved)


if __name__ == '__main__':
    main()
