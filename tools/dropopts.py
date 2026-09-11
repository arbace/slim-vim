#!/usr/bin/env python3
"""Delete command-line options that accept and do nothing, or only refuse.

Usage:
    python3 tools/dropopts.py <file> -X -Y --name ...

Three kinds end up here, and the argument for removing them is the one that
removed `'spelllang'` in phase 2: an option the editor accepts and ignores is a
lie, and an option whose whole body is an error message is a branch that exists
only to say no.  Both are better expressed by the option not existing -- which
this build already has a path for, `mainerr(ME_UNKNOWN_OPTION)`, reached by
anything the parser does not recognise.

  inert     `-f`, `-X`, `-Y`, `--nofork`, `--literal`, `--gui-dialog-file` --
            accepted, with an empty body or an argument that goes nowhere.
  refusing  `-A`, `-F`, `-H`, `-g` -- print "not enabled at compile time" and
            exit, which is what an unknown option does anyway, one message less
            specifically.
  vestigial `--help`, `--version` -- cut in phase 3, but left as string
            comparisons that matched and then called mainerr.  A branch that
            exists only to reach the default is worse than no branch.

A short option is removed by deleting its `case` label and body up to and
including the `break;`, so it falls to `default:`.  A long one is removed with
its `else if` block, by brace matching.  Both refuse if what they find does not
have the expected shape, because a partial removal here leaves an option that
parses and then falls through to something else's body.
"""

import re
import sys
from pathlib import Path


def parser_region(lines):
    """The argument switch, and nothing else.

    `case 'X':` occurs in several switches in this file -- the normal-mode
    tables have their own -- and a scan over the whole file finds the wrong one
    and then reports something confusing about a shared body.  The argument
    parser is the switch that ends in mainerr(ME_UNKNOWN_OPTION).
    """
    end = max(i for i, l in enumerate(lines)
              if 'mainerr(ME_UNKNOWN_OPTION, (char_u *)argv[0]);' in l)
    for i in range(end, 0, -1):
        if re.match(r'^\s*switch \(', lines[i]):
            return i, end
    sys.exit('dropopts: cannot find the argument switch')


def drop_short(lines, letter):
    """Delete `case 'x':` and its body, up to and including its break."""
    lo, hi = parser_region(lines)
    for i, line in enumerate(lines):
        if not (lo <= i <= hi):
            continue
        if re.match(r"^\s*case '%s':\s*$" % re.escape(letter), line):
            j = i + 1
            while j < len(lines) and lines[j].strip() != 'break;':
                if re.match(r"^\s*case '", lines[j]):
                    sys.exit("dropopts: -%s shares its body with the next case; "
                             "removing it would take that one too" % letter)
                if j - i > 8:
                    sys.exit("dropopts: -%s has no break within eight lines" % letter)
                j += 1
            if j >= len(lines):
                sys.exit("dropopts: -%s has no break at all" % letter)
            j += 1
            while j < len(lines) and lines[j].strip() == '':
                j += 1
            return lines[:i] + lines[j:], True
    return lines, False


def drop_long(text, name):
    """Delete the `else if (...("name")...) { ... }` block, by brace matching."""
    m = re.search(r'\n[ \t]*(?:else )?if \([^\n]*\("%s"\)[^\n]*\)\n[ \t]*\{'
                  % re.escape(name), text)
    if not m:
        return text, False
    open_brace = text.index('{', m.end() - 1)
    depth, k = 0, open_brace
    while k < len(text):
        if text[k] == '{':
            depth += 1
        elif text[k] == '}':
            depth -= 1
            if depth == 0:
                break
        k += 1
    end = k + 1
    if text[end:end + 1] == '\n':
        end += 1
    head = text[:m.start()]
    tail = text[end:]
    # The chain must stay a chain: if what followed was an `else if`, and what
    # preceded was too, removing the middle is safe; if this was the FIRST
    # link, the next one has to stop being an `else`.
    if not re.search(r'\belse\s*$', head.rstrip()[-8:]) and \
       re.match(r'\s*else if', tail):
        tail = re.sub(r'^(\s*)else if', r'\1if', tail, count=1)
    return head + tail, True


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    text = path.read_text(errors='surrogateescape')

    shorts = [a[1:] for a in sys.argv[2:] if re.fullmatch(r'-[A-Za-z?]', a)]
    longs = [a[2:] for a in sys.argv[2:] if a.startswith('--')]

    lines = text.split('\n')
    done_s = []
    for c in shorts:
        lines, ok = drop_short(lines, c)
        if not ok:
            sys.exit('dropopts: no `case %r:` in the parser -- it has gone '
                     'already, or the switch has moved' % c)
        done_s.append(c)
    text = '\n'.join(lines)

    done_l = []
    for n in longs:
        text, ok = drop_long(text, n)
        if not ok:
            sys.exit('dropopts: no branch for --%s' % n)
        done_l.append(n)

    path.write_text(text, errors='surrogateescape')
    print('  dropopts     %d short (%s), %d long (%s)'
          % (len(done_s), ' '.join('-' + c for c in done_s),
             len(done_l), ' '.join('--' + n for n in done_l)))


if __name__ == '__main__':
    main()
