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
import hashlib
import os
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


def warnings(path, keep=None):
    """Ask gcc what it warned about, and optionally keep what it produced.

    THE LAST ROUND OF A SWEEP COMPILES A FILE IT THEN DOES NOT CHANGE -- that is
    what "no round changed anything" means -- and phasecheck.sh used to compile
    exactly that file again, for exactly the same two answers: the warnings, and
    the object to run `nm` over.  Five compiles of a 145,000-line file per phase,
    and two of them were the same compile.

    So when `keep` is given the object is written there instead of thrown away,
    beside the stderr and the sha256 of the source it came from.  phasecheck.sh
    uses them only if that sha still matches, which is the same content key as
    the tier-3 cache: a different file has a different key, so nothing goes
    stale.  It costs one 5 MB write per round and saves a whole compile.

    It goes in .cache/ and NOT in the work tree.  A file left in the work tree
    is a file the boundary digest counts -- the mistake that changed twenty-one
    boundaries when the symbol cache first landed.
    """
    obj = '/dev/null'
    if keep:
        os.makedirs(keep, exist_ok=True)
        obj = os.path.join(keep, 'last.o')
    r = subprocess.run(['gcc', '-c', '-O0', '-Wall', '-Wextra',
                        '-Wno-unused-parameter', '-o', obj, path],
                       capture_output=True, text=True)
    if keep:
        with open(os.path.join(keep, 'last.txt'), 'w') as fh:
            fh.write(r.stderr)
        with open(path, 'rb') as fh:
            digest = hashlib.sha256(fh.read()).hexdigest()
        with open(os.path.join(keep, 'last.sha'), 'w') as fh:
            fh.write(digest + '\n')
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


def declaration_extent(lines, lineno):
    """(first, last) line indices of the declaration reported at lineno.

    "Delete the line" is wrong for the 39 file-scope tables whose initialiser
    starts on the *next* line -- `static char *(features[]) =` followed by a
    brace block, or base64_table followed by its string.  Deleting only the
    first line leaves the initialiser behind as a bare expression, and the
    error surfaces as "expected identifier or '(' before string constant".
    Run to where the declaration actually ends: depth back to zero and a
    terminating semicolon.
    """
    i = lineno - 1
    depth = 0
    j = i
    while j < len(lines):
        b = cutil.blank(lines[j])
        depth += b.count('{') - b.count('}') + b.count('(') - b.count(')')
        if depth <= 0 and b.rstrip().endswith(';'):
            break
        j += 1
        if j - i > 4000:            # runaway: decline rather than guess
            return None
    else:
        return None

    # AND BACKWARDS, when the declarator closes a type definition.  There are
    # five of these:
    #
    #     static struct mousetable
    #     {
    #         int     pseudo_code;
    #         ...
    #     } mouse_table[] =
    #     {
    #         ...
    #     };
    #
    # gcc reports the unused variable at `} mouse_table[] =`, and running
    # forward from there takes the initialiser and leaves the struct body open.
    # The next declaration then lands inside it and gcc says
    # "expected specifier-qualifier-list before 'static'" a hundred lines later
    # -- which is how this was found, in the phase that removed the mouse.
    #
    # It is the same class of mistake as keying on the warning's sentence
    # instead of its option: the extent of a thing is not "the line it was
    # reported on".
    if lines[i].lstrip().startswith('}'):
        depth = 1
        k = i - 1
        while k >= 0:
            b = cutil.blank(lines[k])
            depth += b.count('}') - b.count('{')
            if depth == 0:
                break
            k -= 1
        if k < 0:
            return None             # unbalanced: decline rather than guess
        # and the type's head, on the lines above its opening brace
        while k > 0:
            prev = lines[k - 1].strip()
            if (not prev or prev.endswith((';', '}', '{', ':'))
                    or prev.startswith(('//', '#'))):
                break
            k -= 1
        i = k

    return (i, j)


def main():
    path = sys.argv[1]
    keep = None
    if '--keep' in sys.argv:
        keep = sys.argv[sys.argv.index('--keep') + 1]
    lines = open(path, encoding='utf-8', errors='surrogateescape').read().split('\n')
    kill = set()
    counts = {'proto': 0, 'func': 0, 'var': 0, 'other': 0}
    for lineno, text in warnings(path, keep):
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
            e = declaration_extent(lines, lineno)
            if e:
                kill.update(range(e[0], e[1] + 1))
                counts['var'] += 1
            else:
                counts['other'] += 1
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
