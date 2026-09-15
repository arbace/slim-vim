#!/usr/bin/env python3
"""UTF-8 is not a question: fold every test of the encoding flags.

Usage:
    python3 tools/utf8only.py <file>

Phase 12 made 'encoding' accept only utf-8, and mb_init() then sets five globals
to the same values every time: enc_utf8, has_mbyte and enc_latin1like TRUE,
enc_dbcs and enc_unicode 0.  About four hundred and fifty places still ask them,
in every shape C allows -- a bare `if`, a chain of && and ||, a ternary, a
comparison with a DBCS code page, an argument -- and each one is a branch for an
encoding this editor cannot have.

This is constant folding, done on the source, and it is careful in one way that
matters: it NEVER DROPS A SIDE EFFECT.

  1. The five globals lose their declarations and their assignments in
     mb_init(), and every other mention becomes a marker: __T__ for the three
     that are TRUE, __Z__ for the two that are 0.  A marker is an identifier, so
     the text still parses, and it is unambiguous -- a TRUE already in the
     source is never mistaken for one this tool introduced.

  2. Every expression holding a marker is simplified, innermost first, to a
     fixpoint: a ternary on a constant condition becomes its branch; in an ||
     list a false operand goes and a true one ends the list, in an && list the
     reverse; ! of a constant flips it; parentheses around a constant collapse;
     `__Z__ == DBCS_x` is false.  An operand is dropped only where C would not
     have evaluated it (after the deciding one), or where it is PURE -- no call,
     no assignment, no ++ or --.  Otherwise it stays and the expression is left
     partly unsimplified, which is correct and merely untidy.

  3. Every if, else if and while whose condition is now a constant marker folds,
     with its else chain, by brace matching.

  4. What is left -- a marker compared with something that is not a constant,
     or assigned -- becomes TRUE, FALSE or 0 again.

The sweep then takes what no longer has a caller: the DBCS and latin1 paths.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cutil

T, F, Z = '__T__', '__F__', '__Z__'
FLAGS = {'enc_utf8': T, 'has_mbyte': T, 'enc_latin1like': T, 'enc_dbcs': Z, 'enc_unicode': Z}
MARK = re.compile(r'\b(?:__T__|__F__|__Z__)\b')


def outer(s):
    """True if s is one parenthesised group, parentheses included."""
    if not s.startswith('(') or not s.endswith(')'):
        return False
    return cutil.match(s, 0, cutil.blank(s)) == len(s) - 1


def const_of(e):
    s = e.strip()
    while outer(s):
        s = s[1:-1].strip()
    if s == T:
        return True
    if s in (F, Z):
        return False
    return None


ASSIGN = re.compile(r'(?<![=!<>+\-*/%&|^])=(?!=)|\+\+|--|[+\-*/%&|^]=|<<=|>>=')
CALL = re.compile(r'[\w\]\)]\s*\(')


def pure(e):
    b = cutil.blank(e)
    return not ASSIGN.search(b) and not CALL.search(b)


def simplify(e):
    """Return e with every constant marker expression folded; spacing outside is kept."""
    lead = e[:len(e) - len(e.lstrip())]
    trail = e[len(e.rstrip()):]
    s = e.strip()
    if not s or not MARK.search(s):
        return e
    b = cutil.blank(s)
    if cutil.find_top(s, ',', 0, b) >= 0:
        return e
    # An assignment at the top of the expression is left to the statement code.
    if ASSIGN.search(''.join(ch if d == 0 else ' ' for ch, d in zip(b, cutil.depths(b)))):
        return e

    q = cutil.find_top(s, '?', 0, b)
    if q >= 0:
        cond, rest = s[:q], s[q + 1:]
        rb = cutil.blank(rest)
        colon = cutil.find_top(rest, ':', 0, rb)
        if colon < 0 or cutil.find_top(rest[:colon], '?') >= 0:
            return e
        yes, no = rest[:colon], rest[colon + 1:]
        c2 = simplify(cond)
        k = const_of(c2)
        if k is True:
            return lead + simplify(yes).strip() + trail
        if k is False:
            return lead + simplify(no).strip() + trail
        new = '%s ? %s : %s' % (c2.strip(), simplify(yes).strip(), simplify(no).strip())
        return lead + new + trail if new != s else e

    for op, stop in (('||', True), ('&&', False)):
        parts = cutil.split_top(s, op, b)
        if len(parts) > 1:
            out = []
            for p in parts:
                p2 = simplify(p).strip()
                k = const_of(p2)
                if k is (not stop):
                    continue                        # the neutral operand goes
                if k is stop:
                    if all(pure(x) for x in out):
                        return lead + (T if stop else F) + trail
                    out.append(T if stop else F)    # an impure prefix stays
                    break
                out.append(p2)
            if not out:
                return lead + (F if stop else T) + trail
            new = (' %s ' % op).join(out)
            return lead + new + trail if new != s else e

    if s.startswith('!') and not s.startswith('!='):
        inner = simplify(s[1:])
        k = const_of(inner)
        if k is True:
            return lead + F + trail
        if k is False:
            return lead + T + trail
        return lead + '!' + inner.strip() + trail if inner.strip() != s[1:].strip() else e

    if outer(s):
        inner = simplify(s[1:-1])
        k = const_of(inner)
        if k is not None:
            return lead + (T if k else F) + trail
        return lead + '(' + inner.strip() + ')' + trail if inner != s[1:-1] else e

    m = re.fullmatch(r'(__Z__|0)\s*(==|!=)\s*(__Z__|0|DBCS_\w+)', s) or \
        re.fullmatch(r'(DBCS_\w+|0)\s*(==|!=)\s*(__Z__)', s)
    if m:
        equal = (m.group(1) in (Z, '0')) and (m.group(3) in (Z, '0'))
        if m.group(2) == '==':
            return lead + (T if equal else F) + trail
        return lead + (F if equal else T) + trail
    return e


def enclosing_group(text, b, dep, pos):
    """(open, close) of the innermost parenthesis group around pos, or None."""
    d = dep[pos]
    i = pos
    while i > 0:
        i -= 1
        if b[i] == '(' and dep[i] < d:
            c = cutil.match(text, i, b)
            if c > pos:
                return i, c
            d = dep[i]
        elif b[i] in '{;}' and dep[i] < d:
            return None
    return None


def statement_bounds(text, b, dep, pos):
    """The statement around pos at brace depth: from after ; { } to its ;."""
    d = dep[pos]
    i = pos
    while i > 0 and not (b[i - 1] in ';{}' and dep[i - 1] <= d):
        i -= 1
    j = pos
    while j < len(text) and not (b[j] == ';' and dep[j] <= d):
        j += 1
    return i, j


def simplify_function(body):
    """Fold every marker expression in one function body; return (body, changes)."""
    changes = 0
    for _ in range(200):
        b = cutil.blank(body)
        dep = cutil.depths(b)
        progressed = False
        for m in MARK.finditer(body):
            pos = m.start()
            g = enclosing_group(body, b, dep, pos)
            if g:
                o, c = g
                before = body[:o].rstrip()
                control = re.search(r'\b(?:if|while|switch|for)\s*$', before) is not None
                call = (not control) and bool(before) and (before[-1].isalnum() or before[-1] in '_)]')
                inner = body[o + 1:c]
                pieces = cutil.split_top(inner, ',')
                if len(pieces) > 1 or call or re.search(r'\bfor\s*$', before):
                    seps = ';' if re.search(r'\bfor\s*$', before) else ','
                    pieces = cutil.split_top(inner, seps)
                    new_pieces = [simplify(p) for p in pieces]
                    new_inner = seps.join(new_pieces)
                    if new_inner != inner:
                        body = body[:o + 1] + new_inner + body[c:]
                        progressed = True
                        break
                    continue
                new_inner = simplify(inner)
                k = const_of(new_inner)
                if not control and k is not None and new_inner.strip() in (T, F, Z):
                    body = body[:o] + new_inner.strip() + body[c + 1:]
                    progressed = True
                    break
                if new_inner != inner:
                    body = body[:o + 1] + new_inner + body[c:]
                    progressed = True
                    break
                continue
            i, j = statement_bounds(body, b, dep, pos)
            stmt = body[i:j]
            sb = cutil.blank(stmt)
            ma = re.match(r'(\s*return\s+)', stmt)
            if ma:
                head, rhs = stmt[:ma.end()], stmt[ma.end():]
            else:
                a = re.search(r'(?<![=!<>])(?:[+\-*/%&|^]|<<|>>)?=(?!=)', sb)
                if not a:
                    continue
                head, rhs = stmt[:a.end()], stmt[a.end():]
            new_rhs = simplify(rhs)
            if new_rhs != rhs:
                body = body[:i] + head + new_rhs + body[j:]
                progressed = True
                break
        if not progressed:
            break
        changes += 1
    return body, changes


def fold_controls(body):
    """Fold if / else if / while on a constant marker; return (body, count)."""
    n = 0
    while True:
        m = re.search(r'^([ \t]*)(else if|if|while) \((__T__|__F__|__Z__)\)$', body, re.M)
        if not m:
            return body, n
        head, val = m.group(2), m.group(3)
        truth = val == T
        pat = r'^[ \t]*%s \(%s\)$' % (re.escape(head), val)
        if truth and head == 'while':
            sys.exit('utf8only: while (TRUE) from a marker -- not expected')
        if not truth:
            # A function can hold the same false condition more than once, one
            # nested inside another's block.  Folding the outer one first makes
            # the inner vanish, so fold from the LAST occurrence: its block and
            # its else chain lie after it, and nothing before it moves.
            last = list(re.finditer(pat, body, re.M))[-1]
            start = body.rfind('\n', 0, last.start()) + 1
            body = body[:start] + cutil.fold_never(body[start:], pat, 1, re.M)
            n += 1
            continue
        else:
            b = cutil.blank(body)
            mm = re.search(pat, body, re.M)
            k, o, c, _ = cutil._guarded(body, mm, b)
            end = body.index('\n', c) + 1
            tail_start = end
            while True:
                nxt = re.match(r'[ \t]*else\b', body[end:])
                if not nxt:
                    break
                o2 = b.index('{', end + nxt.end())
                c2 = cutil.match(body, o2, b)
                end = body.index('\n', c2) + 1
            if head == 'if':
                kept = cutil._dedent4(body[body.index('\n', o) + 1:body.rfind('\n', 0, c) + 1])
                body = body[:k] + kept + body[end:]
            else:
                line_end = body.index('\n', mm.start())
                body = body[:mm.start()] + m.group(1) + 'else' + body[line_end:tail_start] + body[end:]
        n += 1


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    t = path.read_text(errors='surrogateescape')

    t, n = re.subn(r'^static int\s+(?:enc_utf8|has_mbyte|enc_dbcs|enc_unicode|enc_latin1like)\s+=\s*[^;\n]*;\n', '', t, flags=re.M)
    if n != 5:
        sys.exit('utf8only: expected five flag declarations, found %d' % n)
    a, z = cutil.find_definition(t, 'mb_init')
    seg, n = re.subn(r'^[ \t]*(?:enc_unicode|enc_utf8|enc_dbcs|has_mbyte|enc_latin1like) = [^;\n]*;\n', '', t[a:z], flags=re.M)
    if n != 5:
        sys.exit('utf8only: expected five assignments in mb_init, found %d' % n)
    t = t[:a] + seg + t[z:]
    print('  utf8only     the five flags lose their declarations and mb_init() its assignments')

    marks = 0
    for name, tok in FLAGS.items():
        t, k = re.subn(r'\b%s\b' % name, tok, t)
        marks += k
    print('  utf8only     %d mentions become constant markers' % marks)

    import bisect
    heads = [(m.start(), m.group(1)) for m in re.finditer(r'^(\w+)\([^;\n]*\)[ \t]*\n\{', t, re.M)]
    starts = [s0 for s0, _ in heads]
    names = []
    for mk in MARK.finditer(t):
        k = bisect.bisect_right(starts, mk.start()) - 1
        if k >= 0 and heads[k][1] not in names:
            names.append(heads[k][1])
    exprs = folds = 0
    for name in names:
        span = cutil.find_definition(t, name)
        if not span:
            sys.exit('utf8only: %s holds a marker and is not a function at file scope' % name)
        a, z = span
        body, c1 = simplify_function(t[a:z])
        body, c2 = fold_controls(body)
        body, c3 = simplify_function(body)
        body, c4 = fold_controls(body)
        exprs += c1 + c3
        folds += c2 + c4
        t = t[:a] + body + t[z:]
    print('  utf8only     %d expression simplifications and %d statement folds in %d functions'
          % (exprs, folds, len(names)))

    left = MARK.findall(t)
    t = t.replace(T, 'TRUE').replace(F, 'FALSE')
    t = re.sub(r'\b__Z__\b', '0', t)
    print('  utf8only     %d constants left where they are an operand or a value, written as TRUE, FALSE or 0'
          % len(left))
    for name in FLAGS:
        if re.search(r'\b%s\b' % name, t):
            sys.exit('utf8only: %s is still named' % name)
    path.write_text(t, errors='surrogateescape')
    print('  utf8only     no test of the encoding is left to answer')


if __name__ == '__main__':
    main()
