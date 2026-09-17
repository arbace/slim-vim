"""Shared C-text helpers.  Importing this module must do nothing.

A previous run lost a whole pass because a helper module's top level read
sys.argv and rewrote the source; the pass imported it, the import crashed, and
the pass reported "0 changed" instead of failing.  So: no argv, no I/O, no
prints at import time.  Everything here is a pure function -- blank() and
depths() remember their last large answers, which changes when they compute and
never what they return.

The rule these exist to enforce: never parse C with a regex over the whole
file.  Extract the construct by brace or paren matching, operate on it, write
it back.
"""

# ---------------------------------------------------------------- literals

# THE LAST FEW LARGE ANSWERS ARE REMEMBERED.  A phase program finds, folds and
# finds again in one text, and every find_definition, drop_if and fold blanked
# the whole file from scratch -- a third of a second each on a large file, for
# a string it had blanked a moment before.  The key is the string itself,
# compared by content: an id() is reused as soon as its string is freed, so a
# cache keyed on one hands an old text's answer to a new text.  Holding the key
# keeps it alive, so an identity match is a content match, and anything else is
# compared the ordinary way.  Small strings -- a line, a condition -- are not
# kept: they are cheap to blank and would push the file out.
_KEEP_FROM = 1 << 16
_blanked = []
_depths = []


def _remember(cache, key, compute, size):
    for i, (k, v) in enumerate(cache):
        if k is key or k == key:
            if i:
                cache.insert(0, cache.pop(i))
            return v
    v = compute(key)
    cache.insert(0, (key, v))
    del cache[size:]
    return v


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
    if len(s) >= _KEEP_FROM:
        return _remember(_blanked, s, _blank, 2)
    return _blank(s)


def _blank(s):
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

    A large answer is remembered like blank()'s and returned again, so it must
    be read and never modified.
    """
    if len(b) >= _KEEP_FROM:
        return _remember(_depths, b, _depths_of, 1)
    return _depths_of(b)


def _depths_of(b):
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


def drop_if(s, pattern, count=1, flags=0):
    r"""Delete an `if (...)` and the block it guards, by matching braces.

    Every phase tool that has needed this wrote its own, and four of them wrote
    the same bug: a lazy `(?:[^\n]*\n)*?\}` to find the end of the block.  That
    stops at the FIRST line which is only a brace, which is an inner block's
    whenever there is one -- so the cut takes the header and half the body and
    leaves the rest at file scope.  gcc then reports it hundreds of lines away
    as "expected identifier before 'else'", "data definition has no type or
    storage class", or a duplicate case value in an unrelated function.

    It is the same mistake as funcreach.py's two regexes and it kept coming
    back because the helper lived in whichever tool met it last.  It lives here
    now.

    `pattern` matches the `if` line; the block is found from the condition's
    parentheses onward.  Refuses a block followed by `else`, because deleting
    the `if` alone would orphan it and change which branch runs.
    """
    import re as _re
    for _ in range(count):
        b = blank(s)
        m = _re.search(pattern, s, flags)
        if not m:
            raise ValueError('drop_if: no match for %r' % pattern)
        lp = s.index('(', m.start())
        rp = match(s, lp, b)
        if rp < 0:
            raise ValueError('drop_if: unbalanced condition')
        i = rp + 1
        while i < len(s) and s[i] in ' \t\n':
            i += 1
        if s[i] != '{':
            raise ValueError('drop_if: the condition does not open a block')
        close = match(s, i, b)
        if close < 0:
            raise ValueError('drop_if: unbalanced block')
        if _re.match(r'[ \t]*\n[ \t]*else\b', s[close + 1:close + 40]):
            raise ValueError('drop_if: block has an else; deleting the if '
                             'alone would orphan it')
        end = close + 1
        while end < len(s) and s[end] in ' \t':
            end += 1
        if end < len(s) and s[end] == '\n':
            end += 1
        if s[end:end + 1] == '\n':
            end += 1
        s = s[:m.start()] + s[end:]
    return s


def _dedent4(body):
    return ''.join(l[4:] if l.startswith('    ') else l
                   for l in body.splitlines(keepends=True))


def _guarded(s, m, b):
    """(line start, open brace, close brace) of the block the `if` at `m` guards."""
    k = s.rfind('\n', 0, m.start()) + 1
    lp = s.index('(', m.start())
    rp = match(s, lp, b)
    if rp < 0:
        raise ValueError('unbalanced condition')
    o = rp + 1
    while o < len(s) and s[o] in ' \t\n':
        o += 1
    if o >= len(s) or s[o] != '{':
        raise ValueError('the condition does not open a block')
    c = match(s, o, b)
    if c < 0:
        raise ValueError('unbalanced block')
    return k, o, c, s[k:lp].strip()


def _fold(s, pattern, count, flags, one, what):
    import re as _re
    n = len(list(_re.finditer(pattern, s, flags)))
    if n != count:
        raise ValueError('%s: %r matches %d times, expected %d -- a fold that is '
                         'not counted is a guess' % (what, pattern, n, count))
    for _ in range(count):
        b = blank(s)
        s = one(s, _re.search(pattern, s, flags), b)
    return s


def fold_always(s, pattern, count=1, flags=0):
    r"""An `if` whose condition is now always true: keep its body, lose the test.

    For a plain `if` with no `else`, which is the only shape that has needed it.
    `pattern` matches the `if` line, and must match exactly `count` times: a
    fold applied to "the first one" of several is the cut that took the wrong
    block in Phase 35, so the number is stated rather than found.

    norecover.py, nowildmenu.py and noenc.py each carry a private version of
    this from before it lived here.
    """
    import re as _re

    def one(s, m, b):
        k, o, c, head = _guarded(s, m, b)
        if head != 'if':
            raise ValueError('fold_always: only a plain if, not %r' % head)
        end = s.index('\n', c) + 1
        if _re.match(r'[ \t]*else\b', s[end:]):
            raise ValueError('fold_always: the block has an else')
        body = _dedent4(s[s.index('\n', o) + 1:s.rfind('\n', 0, c) + 1])
        return s[:k] + body + s[end:]
    return _fold(s, pattern, count, flags, one, 'fold_always')


def fold_never(s, pattern, count=1, flags=0):
    r"""An `if` whose condition is now always false: lose it, keep what it chose between.

    Every shape of chain, because the condition can sit anywhere in one:

        if (F) { A }                     -> nothing
        if (F) { A } else { C }          -> C
        if (F) { A } else if (X) { B }   -> if (X) { B }
        ... else if (F) { A } ...        -> ... ...

    `pattern` matches the `if` or `else if` line, exactly `count` times.
    """
    import re as _re

    def tidy(before, after):
        if before.endswith('\n\n') and after.startswith('\n'):
            after = after[1:]
        return before + after

    def one(s, m, b):
        k, o, c, head = _guarded(s, m, b)
        end = s.index('\n', c) + 1
        rest = s[end:]
        if head == 'else if':
            return s[:k] + rest
        if head != 'if':
            raise ValueError('fold_never: not an if: %r' % head)
        nxt = _re.match(r'([ \t]*)else\b([ \t]+if\b)?', rest)
        if not nxt:
            return tidy(s[:k], rest)
        if nxt.group(2):
            return s[:k] + nxt.group(1) + 'if' + rest[nxt.end():]
        o2 = b.index('{', end + nxt.end())
        c2 = match(s, o2, b)
        body = _dedent4(s[s.index('\n', o2) + 1:s.rfind('\n', 0, c2) + 1])
        return s[:k] + body + s[s.index('\n', c2) + 1:]
    return _fold(s, pattern, count, flags, one, 'fold_never')
