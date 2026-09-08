"""Concatenate the tree into one translation unit.

Headers are inlined where they were included, once each, so the whole-file
include guards become inert.  ex_cmds.h is the exception: it is read twice on
purpose, with DO_DECLARE_EXCMD toggled, to expand one list into enum CMD_index
and into cmdnames[].  System includes are collected and hoisted to the top.

Three macros that individual sources used to define *before* including vim.h
change what the headers produce, so they move to the preamble:
  EXTERN            main.c    -- makes globals.h define rather than declare
  IN_OPTION_C       option.c  -- same, for the handful of options option.h
                                 defines outright
  USING_FLOAT_STUFF eval.c, fuzzy.c, strings.c

Each former file keeps a banner, which are the only comments in the result.
They are the only navigation in a file this size, and they keep
`git log --follow` working back through the merge.

Usage: merge.py <output> <first.c> ... <main.c>
"""
import os
import re
import sys

INCL = re.compile(r'^[ \t]*#[ \t]*include[ \t]*([<"])([^>"]+)[>"]')
PREAMBLE_MACROS = ('EXTERN', 'IN_OPTION_C', 'USING_FLOAT_STUFF')
TWICE = ('ex_cmds.h',)


class Merger:
    def __init__(self):
        self.out = []
        self.sysincludes = []
        self.seen = set()
        self.counts = {}

    def sys_include(self, name):
        if name not in self.sysincludes:
            self.sysincludes.append(name)

    def banner(self, path, opening):
        base = os.path.basename(path)
        if path.endswith('.c') and opening:
            self.out.append('// ==================== %s ====================' % base)
        elif path.endswith('.c'):
            pass
        else:
            self.out.append('// ---------------- %s %s ----------------'
                            % ('begin' if opening else 'end', base))

    def inline(self, path, top=False):
        n = self.counts.get(path, 0)
        self.counts[path] = n + 1
        self.banner(path, True)
        for line in open(path, encoding='utf-8', errors='surrogateescape').read().split('\n'):
            m = INCL.match(line)
            if m:
                kind, name = m.group(1), m.group(2)
                if kind == '<':
                    self.sys_include(name)
                    continue
                target = name if os.path.exists(name) else os.path.basename(name)
                if not os.path.exists(target):
                    raise SystemExit('cannot find included file %r' % name)
                if target in self.seen and os.path.basename(target) not in TWICE:
                    continue
                self.seen.add(target)
                self.inline(target)
                continue
            if not top and re.match(r'^[ \t]*#[ \t]*define[ \t]+(%s)\b'
                                    % '|'.join(PREAMBLE_MACROS), line):
                continue
            self.out.append(line)
        self.banner(path, False)


def main():
    outpath, sources = sys.argv[1], sys.argv[2:]
    m = Merger()
    body = Merger()
    for src in sources:
        body.seen = m.seen
        body.sysincludes = m.sysincludes
        body.counts = m.counts
        body.out = m.out
        m.seen.add(src)
        body.inline(src)
    head = []
    head.append('// One translation unit.  What were %d .c files, their headers and'
                % len(sources))
    head.append('// the forward declarations that used to be proto/*.pro, in the order')
    head.append('// the preprocessor used to paste them.  main() is last.')
    head.append('')
    for name in m.sysincludes:
        head.append('#include <%s>' % name)
    head.append('')
    head.append('// Set before the headers because they change what the headers')
    head.append('// produce: EXTERN makes globals.h define rather than declare, and')
    head.append('// IN_OPTION_C does the same for a few options.')
    for name in PREAMBLE_MACROS:
        head.append('#define %s' % name)
    head.append('')
    text = '\n'.join(head + m.out)
    text = re.sub(r'\n{3,}', '\n\n', text)
    if not text.endswith('\n'):
        text += '\n'
    open(outpath, 'w', encoding='utf-8', errors='surrogateescape').write(text)
    print('%d system includes, %d files inlined, %d lines'
          % (len(m.sysincludes), len(m.counts), text.count('\n')))


if __name__ == '__main__':
    main()
