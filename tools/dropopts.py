#!/usr/bin/env python3
"""Delete command-line options, so that each reaches the error an unknown one does.

Usage:
    python3 tools/dropopts.py <file> -X -Y --name ...

An option the editor accepts and ignores is a lie, and an option whose whole
body is an error message is a branch that exists only to say no.  Both are
better expressed by the option not existing -- which this build already has a
path for, `mainerr(ME_UNKNOWN_OPTION)`, reached by anything the parser does not
recognise.  WHIM-GOAL.md's Phase 3 says which options, and why each.

A SHORT OPTION has up to two `case` labels, one in each of command_line_scan()'s
two switches: the one that reads the option, and the one that reads its argument
when it takes one.  A label that shares its body with other options (`case 'S':
case 'd': case 'T':`) goes alone and the body stays for the rest; a label that is
the last of its group goes with the body.  A whole group is refused if the case
before it falls through into it, because the body would vanish from under an
option that is staying.

A LONG OPTION is a link in an `if ... else if` chain, removed by brace matching.
THE CHAIN MUST STAY A CHAIN, and the first version of this tool did not keep it.
It asked whether the text before the removed link ended in `else` -- which it
never does, because the match had already consumed that `else` -- so removing
ANY link turned the next `else if` into a bare `if`.  `--clean`, `--noplugin` and
`--not-a-term` then each matched their own branch, failed every test of the
split chain after it, and reached `mainerr` anyway: three options broken for
thirty phases, because no harness passed them.  The removed link's own `else`
decides now, and tools/clicheck.py runs every option the parser has left.

Everything is bounded by command_line_scan()'s own text.  `case 'X':` occurs in
several switches in this file -- the normal-mode tables and get_c_indent() have
their own -- and a scan over the whole file finds the wrong one.  Everything
refuses a shape it does not recognise, because a partial removal here leaves an
option that parses and then runs something else's body.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cutil

LABEL = re.compile(r"^[ \t]*case '(.)':[ \t]*$")
DEFAULT = re.compile(r'^[ \t]*default:[ \t]*$')


def switches(fn):
    """The option switch and the argument switch, as (open, close) offsets in `fn`."""
    b = cutil.blank(fn)
    found = []
    for m in re.finditer(r'\bswitch \(c\)', b):
        o = b.index('{', m.end())
        found.append((o, cutil.match(fn, o, b)))
    if len(found) != 2:
        sys.exit('dropopts: expected the option switch and the argument switch, '
                 'found %d switches on c' % len(found))
    return found, b


def groups(lines, blines):
    """Each group of adjacent labels at the switch's own depth: (labels, body start, body end)."""
    depth, depths = 0, []
    for bl in blines:
        depths.append(depth)
        depth += bl.count('{') - bl.count('}')

    def is_label(k):
        return depths[k] == 0 and LABEL.match(lines[k])

    out, i = [], 0
    while i < len(lines):
        if not is_label(i):
            i += 1
            continue
        labels = []
        while i < len(lines) and is_label(i):
            labels.append(i)
            i += 1
        j = i
        while j < len(lines) and not (is_label(j) or
                                      (depths[j] == 0 and DEFAULT.match(lines[j]))):
            j += 1
        out.append((labels, i, j))
        i = j
    return out


def drop_short(fn, which, letters):
    """Remove `letters` from one switch; return (fn, the letters it held)."""
    sw, b = switches(fn)
    o, c = sw[which]
    lines = fn[o + 1:c].split('\n')
    gs = groups(lines, b[o + 1:c].split('\n'))
    remove, held = set(), set()
    for n, (labels, bs, be) in enumerate(gs):
        names = [LABEL.match(lines[k]).group(1) for k in labels]
        gone = [k for k, name in zip(labels, names) if name in letters]
        if not gone:
            continue
        held.update(LABEL.match(lines[k]).group(1) for k in gone)
        if len(gone) < len(labels):
            remove.update(gone)
            continue
        if n > 0:
            prev = [l.strip() for l in lines[gs[n - 1][1]:gs[n - 1][2]] if l.strip()]
            if prev and prev[-1] != 'break;':
                sys.exit("dropopts: -%s -- the case before it falls through into it, "
                         "so removing its body would change what that option runs"
                         % '/-'.join(names))
        tail = [l.strip() for l in lines[bs:be] if l.strip()]
        if not tail or tail[-1] != 'break;':
            sys.exit("dropopts: -%s -- its body does not end in break" % '/-'.join(names))
        remove.update(range(labels[0], be))
    kept = [l for k, l in enumerate(lines) if k not in remove]
    return fn[:o + 1] + '\n'.join(kept) + fn[c:], held


def drop_long(fn, name):
    """Remove the chain link comparing against "name", keeping the chain a chain."""
    sw, _ = switches(fn)
    o, c = sw[0]
    seg = fn[o + 1:c]
    pat = re.compile(r'^[ \t]*(else )?if \([^\n]*\("%s"\)[^\n]*\)\n[ \t]*\{'
                     % re.escape(name), re.M)
    ms = list(pat.finditer(seg))
    if len(ms) != 1:
        sys.exit('dropopts: --%s -- expected one branch in the option switch, found %d'
                 % (name, len(ms)))
    m = ms[0]
    b = cutil.blank(seg)
    ob = b.index('{', m.end() - 1)
    cb = cutil.match(seg, ob, b)
    end = cb + 1
    if seg[end:end + 1] == '\n':
        end += 1
    head, tail = seg[:m.start()], seg[end:]
    if not m.group(1):
        # The FIRST link: whatever followed it has to stop being an `else`.
        nxt = re.match(r'([ \t]*)else if\b', tail)
        if nxt:
            tail = nxt.group(1) + 'if' + tail[nxt.end():]
        elif re.match(r'[ \t]*else\b', tail):
            sys.exit('dropopts: --%s is the only test before a bare else' % name)
    return fn[:o + 1] + head + tail + fn[c:]


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    text = path.read_text(errors='surrogateescape')

    shorts, longs = [], []
    for a in sys.argv[2:]:
        if re.fullmatch(r'-[A-Za-z?]', a):
            shorts.append(a[1])
        elif re.fullmatch(r'--[a-z][a-z-]*', a):
            longs.append(a[2:])
        else:
            sys.exit('dropopts: not an option this can remove: %r' % a)

    span = cutil.find_definition(text, 'command_line_scan')
    if not span:
        sys.exit('dropopts: command_line_scan is not defined at file scope')
    a, z = span
    fn = text[a:z]

    fn, held = drop_short(fn, 0, set(shorts))
    missing = sorted(set(shorts) - held)
    if missing:
        sys.exit('dropopts: no `case` in the option switch for %s -- it has gone '
                 'already, or the switch has moved' % ' '.join('-' + c for c in missing))
    fn, in_args = drop_short(fn, 1, set(shorts))

    for n in longs:
        fn = drop_long(fn, n)

    # A long option that took an argument had a test in the argument switch,
    # and once its branch is gone that test compares against a name nothing
    # can produce.  An EMPTY one is dead whatever it names -- the one left
    # behind by --gui-dialog-file had been empty since the GUI went.
    sw, _ = switches(fn)
    o, c = sw[1]
    seg, empty = re.subn(r'^[ \t]*if \(argv\[-1\]\[2\] == \'.\'\)\n[ \t]*\{\n[ \t]*\}\n',
                         '', fn[o + 1:c], flags=re.M)
    fn = fn[:o + 1] + seg + fn[c:]

    path.write_text(text[:a] + fn + text[z:], errors='surrogateescape')
    print('  dropopts     %d short (%s), %d of them also in the argument switch; '
          '%d long (%s); %d empty argument test%s'
          % (len(shorts), ' '.join('-' + c for c in shorts), len(in_args),
             len(longs), ' '.join('--' + n for n in longs),
             empty, '' if empty == 1 else 's'))


if __name__ == '__main__':
    main()
