"""Shared C-text helpers.  Importing this module must do nothing.

A previous run lost a whole pass because a helper module's top level read
sys.argv and rewrote the source; the pass imported it, the import crashed, and
the pass reported "0 changed" instead of failing.  So: no argv, no I/O, no
prints at import time.  Everything here is a pure function.

The rule these exist to enforce: never parse C with a regex over the whole
file.  Extract the construct by brace or paren matching, operate on it, write
it back.
"""

# ---------------------------------------------------------------- literals

def blank(s):
    """Return a string of the same length with the *contents* of string
    literals, character constants and comments replaced by spaces.

    Offsets are preserved exactly, so an index into the result is an index
    into the input.  The delimiters themselves survive, so a caller can still
    see where a literal was.  Newlines survive too, so line numbers hold.

    This is for *locating* things -- parens, braces, operators -- not for
    reading them.  What is inside a literal is gone here; a pass that needs the
    real characters must walk the original string.  Deciding whitespace from
    blanked text is what turned '\\n' into '' and produced 630 compile errors.
    """
    out = []
    i, n = 0, len(s)
    while i < n:
        c = s[i]
        if c == '"' or c == "'":
            q = c
            out.append(c)
            i += 1
            while i < n:
                if s[i] == '\\' and i + 1 < n:
                    out.append('  ' if s[i + 1] != '\n' else ' \n')
                    i += 2
                    continue
                if s[i] == q:
                    out.append(q)
                    i += 1
                    break
                out.append('\n' if s[i] == '\n' else ' ')
                i += 1
            continue
        if c == '/' and i + 1 < n and s[i + 1] == '*':
            j = s.find('*/', i + 2)
            j = n if j < 0 else j + 2
            out.append(''.join('\n' if ch == '\n' else ' ' for ch in s[i:j]))
            i = j
            continue
        if c == '/' and i + 1 < n and s[i + 1] == '/':
            j = i
            while j < n and s[j] != '\n':
                # a // comment continues across a spliced line break
                if s[j] == '\\' and j + 1 < n and s[j + 1] == '\n':
                    j += 2
                    continue
                j += 1
            out.append(''.join('\n' if ch == '\n' else ' ' for ch in s[i:j]))
            i = j
            continue
        out.append(c)
        i += 1
    r = ''.join(out)
    assert len(r) == len(s), (len(r), len(s))
    return r


def strip_comments_only(s):
    """Blank comments but leave literals alone.  Same length."""
    out = []
    i, n = 0, len(s)
    while i < n:
        c = s[i]
        if c == '"' or c == "'":
            q = c
            out.append(c)
            i += 1
            while i < n:
                if s[i] == '\\' and i + 1 < n:
                    out.append(s[i:i + 2])
                    i += 2
                    continue
                out.append(s[i])
                if s[i] == q:
                    i += 1
                    break
                i += 1
            continue
        if c == '/' and i + 1 < n and s[i + 1] in '*/':
            if s[i + 1] == '*':
                j = s.find('*/', i + 2)
                j = n if j < 0 else j + 2
            else:
                j = s.find('\n', i)
                j = n if j < 0 else j
            out.append(''.join('\n' if ch == '\n' else ' ' for ch in s[i:j]))
            i = j
            continue
        out.append(c)
        i += 1
    return ''.join(out)


# ---------------------------------------------------------------- matching

_PAIR = {'(': ')', '[': ']', '{': '}'}


def match(s, i, b=None):
    """Index of the closer matching the opener at s[i].  -1 if unbalanced.

    `b` is blank(s); pass it in when matching repeatedly over one file, since
    blanking is the expensive part.
    """
    if b is None:
        b = blank(s)
    o = b[i]
    if o not in _PAIR:
        raise ValueError('not an opener: %r at %d' % (o, i))
    c = _PAIR[o]
    depth = 0
    n = len(b)
    while i < n:
        ch = b[i]
        if ch == o:
            depth += 1
        elif ch == c:
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return -1


def rmatch(s, i, b=None):
    """Index of the opener matching the closer at s[i].  -1 if unbalanced."""
    if b is None:
        b = blank(s)
    c = b[i]
    o = {v: k for k, v in _PAIR.items()}.get(c)
    if o is None:
        raise ValueError('not a closer: %r at %d' % (c, i))
    depth = 0
    while i >= 0:
        ch = b[i]
        if ch == c:
            depth += 1
        elif ch == o:
            depth -= 1
            if depth == 0:
                return i
        i -= 1
    return -1


def depths(b):
    """Per-character nesting depth of () [] {} over blanked text `b`.

    depth[i] is the depth *before* consuming b[i], so an opener sits at the
    depth of its enclosing context and its closer sits one deeper.
    """
    out = []
    d = 0
    for ch in b:
        out.append(d)
        if ch in '([{':
            d += 1
        elif ch in ')]}':
            d -= 1
    return out


def split_top(s, op, b=None):
    """Split `s` on top-level occurrences of the operator string `op`.

    Top level means outside every (), [], {} and outside every literal.
    Returns a list of substrings of `s` (not stripped).  `op` is matched
    literally, so pass '||', '&&', ',' or ';'.
    """
    if b is None:
        b = blank(s)
    d = depths(b)
    parts, start, i, n = [], 0, 0, len(s)
    L = len(op)
    while i <= n - L:
        if d[i] == 0 and b[i:i + L] == op:
            parts.append(s[start:i])
            i += L
            start = i
            continue
        i += 1
    parts.append(s[start:])
    return parts


def find_top(s, ch, start=0, b=None):
    """Index of the first top-level occurrence of single character `ch`."""
    if b is None:
        b = blank(s)
    d = depths(b)
    for i in range(start, len(s)):
        if d[i] == 0 and b[i] == ch:
            return i
    return -1


# ---------------------------------------------------------------- whitespace

def collapse_ws(s):
    """Collapse runs of whitespace to one space, *outside* literals only.

    Walks the real string and copies literals through untouched.  Deciding
    whitespace from blanked text deletes literal contents, because every
    character inside "a  b" looks like whitespace there.
    """
    out = []
    i, n = 0, len(s)
    prev_ws = False
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
            prev_ws = False
            i = j
            continue
        if c in ' \t\n\r\f\v':
            if not prev_ws:
                out.append(' ')
            prev_ws = True
            i += 1
            continue
        out.append(c)
        prev_ws = False
        i += 1
    return ''.join(out)


# ---------------------------------------------------------------- functions

def _ident_start(s, i):
    return i > 0 and (s[i - 1].isalnum() or s[i - 1] == '_')


def find_definition(s, name, b=None):
    """Locate a top-level function definition `name`.

    Returns (start, end) covering the whole definition including its closing
    brace and the newline after it, or None.  A definition is: the identifier
    at brace depth 0, followed by '(' ... ')' and then '{' with only type
    tokens between.  A declaration ends in ';' and is not matched.
    """
    if b is None:
        b = blank(s)
    d = depths(b)
    n = len(s)
    pos = 0
    while True:
        i = b.find(name, pos)
        if i < 0:
            return None
        pos = i + 1
        if d[i] != 0:
            continue
        if _ident_start(s, i) or (i + len(name) < n and
                                  (s[i + len(name)].isalnum() or s[i + len(name)] == '_')):
            continue
        j = i + len(name)
        while j < n and b[j] in ' \t\n':
            j += 1
        if j >= n or b[j] != '(':
            continue
        k = match(s, j, b)
        if k < 0:
            continue
        k += 1
        while k < n and b[k] in ' \t\n':
            k += 1
        if k >= n or b[k] != '{':
            continue
        end = match(s, k, b)
        if end < 0:
            continue
        # walk back over the return type to the start of the line
        st = s.rfind('\n', 0, i)
        st = 0 if st < 0 else st + 1
        # a return type on its own preceding line belongs to the definition
        while True:
            p = s.rfind('\n', 0, st - 1)
            p = 0 if p < 0 else p + 1
            line = s[p:st].strip()
            if not line or line.endswith((';', '}', '{', ':')) or line.startswith('#'):
                break
            if line.startswith('//') or line.startswith('/*') or line.endswith('*/'):
                break
            st = p
        end += 1
        if end < n and s[end] == '\n':
            end += 1
        return (st, end)


def delete_definition(s, name):
    """Remove a function definition by name.  Returns (text, removed?)."""
    r = find_definition(s, name)
    if r is None:
        return s, False
    a, z = r
    return s[:a] + s[z:], True


# ---------------------------------------------------------------- line passes

def linear_pass(text, step):
    """Run a whole-file pass as ONE forward scan.

    `step(line, pull)` is called with the current logical line; `pull()` yields
    the next physical line or None.  It returns the text to emit.  The scan
    never restarts, which is the point: `find one, fix it, rescan from the top`
    is O(n^2) and does not finish on a 168,000-line file.
    """
    lines = text.split('\n')
    out = []
    i = 0

    def make_pull(state):
        def pull():
            if state[0] + 1 < len(lines):
                state[0] += 1
                return lines[state[0]]
            return None
        return pull

    state = [0]
    pull = make_pull(state)
    while state[0] < len(lines):
        i = state[0]
        emitted = step(lines[i], pull)
        if emitted is not None:
            out.append(emitted)
        if state[0] == i:
            state[0] += 1
        else:
            state[0] += 1
    return '\n'.join(out)


def balanced(s):
    """True if (), [] and {} all balance in `s`, literals ignored."""
    b = blank(s)
    st = []
    for ch in b:
        if ch in '([{':
            st.append(ch)
        elif ch in ')]}':
            if not st or _PAIR[st.pop()] != ch:
                return False
    return not st
