"""The shape of a zero recording, and the two things that have to be scrubbed.

Every zero harness writes the same sectioned text, so that one comparator can be
told to ignore a whole dimension of it -- which is what `pipes/zero.delta`'s
`stderr-moved` and `screen-moved` tokens mean:

    --- exit 0
    --- bells 1
    --- stream 2371 sha=dc2753fe11c84d69
    --- stderr
    Vim: Warning: Output is not to a terminal
    --- snap 0 cursor=23,79 bells=0
    <24 screen lines, right-stripped>
    --- snap 1 cursor=0,0 bells=0
    ...

**Two things in a recording are not the editor's behaviour.**  Undo says how long
ago a change was made ("1 second ago", from `time()`), and `mainerr()` prints the
version banner, which carries `__DATE__` and `__TIME__` and so moves on every
rebuild.  Both are replaced -- **padded to the width they replace**, because the
screen is columns: a shorter token moved the ruler into a different one, and
three runs in eight disagreed until the padding went in (ZERO-PLAN.md 2e).
"""
import re

AGO = re.compile(r'\b\d+ (seconds?|minutes?|hours?|days?) ago')
# What the editor DREW, as opposed to what it returned: the screen dimension.
SCREEN = ('snap', 'stream', 'text', 'msgs')
BANNER = re.compile(r'compiled [A-Z][a-z]{2} [ \d]\d \d{4} \d\d:\d\d:\d\d')


def _pad(m, token):
    return token.ljust(len(m.group(0)))[:len(m.group(0))]


def scrub(s):
    s = AGO.sub(lambda m: _pad(m, '<ago>'), s)
    return BANNER.sub(lambda m: _pad(m, '<compiled>'), s)


def section(name, body=None):
    """One section of a record: a header line, and an optional block after it."""
    if body is None:
        return '--- %s\n' % name
    return '--- %s\n%s\n' % (name, body)


def split(text):
    """[(header, body)] in order, as `section()` wrote them."""
    out, head, body = [], None, []
    for line in text.split('\n'):
        if line.startswith('--- '):
            if head is not None:
                out.append((head, '\n'.join(body)))
            head, body = line[4:], []
        elif head is not None:
            body.append(line)
    if head is not None:
        out.append((head, '\n'.join(body)))
    return out


def without(text, dimensions):
    """The record with whole dimensions dropped, for a declared token.

    `stderr` drops the stderr block; `screen` drops everything the editor DREW --
    the snapshots, the text and message lines the command sweep keeps, and the
    stream's length and digest, since a changed redraw moves the digest by
    construction.  `exit` and `bells` are never dropped: a phase that changes
    what the editor draws has not licensed it to change what it returns.
    """
    keep = []
    for head, body in split(text):
        kind = head.split()[0] if head else head
        if kind == 'stderr' and 'stderr' in dimensions:
            continue
        if kind in SCREEN and 'screen' in dimensions:
            continue
        keep.append(section(head, body))
    return ''.join(keep)


def only(text, dimension):
    """Just one dimension of a record, for asking whether IT moved.

    `without()` answers "is the difference explained by these tokens"; this
    answers "did this token's dimension really move", which a declaration that
    names a dimension nothing touched would otherwise pass.
    """
    kinds = SCREEN if dimension == 'screen' else (dimension,)
    return ''.join(section(h, b) for h, b in split(text)
                   if (h.split()[0] if h else h) in kinds)


def blocks(text, marker='=== '):
    """{name: block} for a record that holds many, as the command sweep does."""
    out, name, body = {}, None, []
    for line in text.split('\n'):
        if line.startswith(marker):
            if name is not None:
                out[name] = '\n'.join(body)
            name, body = line[len(marker):].strip(), []
        elif name is not None:
            body.append(line)
    if name is not None:
        out[name] = '\n'.join(body)
    return out
