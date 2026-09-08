"""Remove every comment, preserving the line structure exactly.

The standard says a comment becomes one space, which collapses a multi-line
comment onto a single line.  Doing that is what lost this tree's paragraphing
once: deciding afterwards whether a now-empty line *had been* blank needs the
two texts walked together, and a resync heuristic gets it wrong at scale --
26,476 blank lines down to 3,884, with both verification tiers passing, because
neither can see a blank line.

Preserving the newlines inside a comment avoids the question entirely: line i
of the output is line i of the input, so a line that became empty held only a
comment and a line that was blank stays blank.

That is only equivalent to the standard's rule when **no multi-line comment has
code on both sides of it** -- otherwise two statements that shared a logical
line would be split.  The tool checks, and refuses if any does.  In this tree
the count is zero.

Usage: decomment.py <file> ...
"""
import sys

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cutil


def unsafe_sites(s):
    """Multi-line comments with code before the `/*` and after the `*/`."""
    out = []
    i = 0
    while True:
        j = s.find('/*', i)
        if j < 0:
            return out
        if cutil.blank(s[:j + 2])[j:j + 2] != '/*':
            i = j + 2
            continue
        k = s.find('*/', j + 2)
        if k < 0:
            return out
        if '\n' in s[j:k]:
            before = s[s.rfind('\n', 0, j) + 1:j].strip()
            nl = s.find('\n', k)
            after = s[k + 2:nl if nl >= 0 else len(s)].strip()
            if before and after:
                out.append(s[:j].count('\n') + 1)
        i = k + 2


def collapse(s):
    """Each comment becomes one space, plus the newlines it spanned.

    The space is what the standard asks for; keeping the newlines is what keeps
    line i of the output line i of the input.  Blanking a comment to its full
    width instead leaves the indentation of what follows it wrong -- which the
    command-table canary notices immediately, since its rows are written
    `  /* a */ 0,`.
    """
    out = []
    i, n = 0, len(s)
    while i < n:
        c = s[i]
        if c == '"' or c == "'":
            q = c
            j = i + 1
            while j < n:
                if s[j] == '\\' and j + 1 < n:
                    j += 2
                    continue
                if s[j] == q:
                    j += 1
                    break
                j += 1
            out.append(s[i:j])
            i = j
            continue
        if c == '/' and i + 1 < n and s[i + 1] in '*/':
            if s[i + 1] == '*':
                j = s.find('*/', i + 2)
                j = n if j < 0 else j + 2
            else:
                j = s.find('\n', i)
                j = n if j < 0 else j
            out.append(' ' + '\n' * s.count('\n', i, j))
            i = j
            continue
        out.append(c)
        i += 1
    return ''.join(out)


def main():
    files = comments = dropped = 0
    for p in sys.argv[1:]:
        s = open(p, encoding='utf-8', errors='surrogateescape').read()
        bad = unsafe_sites(s)
        if bad:
            raise SystemExit('%s: multi-line comment with code on both sides at '
                             'line %d; this pass would split a logical line'
                             % (p, bad[0]))
        blanked = collapse(s)
        out = []
        for orig, b in zip(s.split('\n'), blanked.split('\n')):
            keep = b.rstrip()
            if not keep.strip() and orig.strip():
                dropped += 1
                continue
            out.append(keep)
        if out != s.split('\n'):
            files += 1
        comments += s.count('/*') + s.count('//')
        open(p, 'w', encoding='utf-8', errors='surrogateescape').write('\n'.join(out))
    print('comments removed from %d files, %d comment-only lines dropped'
          % (files, dropped))


if __name__ == '__main__':
    main()
