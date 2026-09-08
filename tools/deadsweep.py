"""Delete what -Wall -Wextra says is dead, once.

Three kinds are handled mechanically:
  * "declared 'static' but never defined"  -> delete the prototype line
  * "'X' defined but not used"             -> delete the whole definition
  * "unused variable 'X'"                  -> delete the declaration line

Everything else is left for a human to look at.  Deletions are applied from the
bottom of the file up, so earlier line numbers stay valid.

Deleting a function orphans its callees, so run this to a fixpoint.

Usage: deadsweep.py <file>
"""
import re
import subprocess
import sys

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cutil

W = re.compile(r'^[^:]+:(\d+):\d+: warning: (.*)$')
# The *text* is the same for a function and a variable -- "'X' defined but not
# used" -- and only the option in brackets says which.  Matching on the text
# alone treats an unused error string as a function definition and deletes 500
# lines: the extent scan runs from the string to the closing brace of the next
# function it finds.
NEVER_DEFINED = re.compile(r"'(\w+)' declared 'static' but never defined")
DEAD_FUNCTION = re.compile(r"'(\w+)' defined but not used \[-Wunused-function\]")
DEAD_VARIABLE = re.compile(
    r"(?:'(\w+)' defined but not used|unused variable '(\w+)')"
    r" \[-Wunused(?:-const)?-variable=?\]")


def warnings(path):
    r = subprocess.run(['gcc', '-c', '-O0', '-Wall', '-Wextra',
                        '-Wno-unused-parameter', '-o', '/dev/null', path],
                       capture_output=True, text=True)
    out = []
    for line in r.stderr.splitlines():
        m = W.match(line)
        if m:
            out.append((int(m.group(1)), m.group(2)))
    return out


def function_extent(lines, lineno):
    """(first, last) line indices of the definition reported at lineno."""
    i = lineno - 1
    # walk back over the return type, which vim puts on its own line
    start = i
    while start > 0:
        prev = lines[start - 1].rstrip()
        if not prev.strip():
            break
        if prev.endswith((';', '{', '}', ':')) or prev.lstrip().startswith(('#', '//')):
            break
        start -= 1
    j = i
    while j < len(lines) and '{' not in cutil.blank(lines[j]):
        j += 1
    if j >= len(lines):
        return None
    depth = 0
    started = False
    while j < len(lines):
        b = cutil.blank(lines[j])
        depth += b.count('{') - b.count('}')
        if '{' in b:
            started = True
        if started and depth <= 0:
            return (start, j)
        j += 1
    return None


def main():
    path = sys.argv[1]
    lines = open(path, encoding='utf-8', errors='surrogateescape').read().split('\n')
    kill = set()
    counts = {'proto': 0, 'func': 0, 'var': 0, 'other': 0}
    for lineno, text in warnings(path):
        if NEVER_DEFINED.search(text):
            kill.add(lineno - 1)
            counts['proto'] += 1
        elif DEAD_FUNCTION.search(text):
            e = function_extent(lines, lineno)
            if e:
                kill.update(range(e[0], e[1] + 1))
                counts['func'] += 1
            else:
                counts['other'] += 1
        elif DEAD_VARIABLE.search(text):
            kill.add(lineno - 1)
            counts['var'] += 1
        else:
            counts['other'] += 1
    out = [l for i, l in enumerate(lines) if i not in kill]
    text = '\n'.join(out)
    if not text.endswith('\n'):
        text += '\n'
    open(path, 'w', encoding='utf-8', errors='surrogateescape').write(text)
    print('prototypes %(proto)d, functions %(func)d, variables %(var)d, '
          'left alone %(other)d' % counts, '-- %d lines removed' % len(kill))
    return counts['proto'] + counts['func'] + counts['var']


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
