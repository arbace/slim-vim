"""Find type definitions nothing outside a type definition mentions.

gcc has no warning for an unused type, so this is the only sweep for them.

**Reachability, not reference counting.**  A type named only from inside
another type definition is not in use, and if two name each other, counting
references says both are live for ever.  Take as roots only the mentions that
are outside *every* type definition -- a prototype, a variable, a cast, a
sizeof -- and close over what those reach.

**An enum's constants are referenced without its tag**, so they decide whether
the definition is live.  Leave them out of the count and the whole enum looks
dead.

Usage: typereach.py <file> [--delete]
"""
import re
import sys

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cutil

IDENT = re.compile(r'\b[A-Za-z_]\w*\b')
START = re.compile(r'^(typedef\b|struct\s+\w+\s*\{|union\s+\w+\s*\{|'
                   r'enum\s+\w*\s*\{|struct\s+\w+\s*;|union\s+\w+\s*;)')

# AND THE SAME HEADS WITH THE BRACE ON THE NEXT LINE.  111 of this file's
# definitions are written that way -- `struct jobvar_S` on one line and `{` on
# the next -- and START did not match them, so they were not definitions at all
# and EVERY FIELD IN THEM COUNTED AS A ROOT.
#
# That is how a whole dead island stayed: `channel_T` is mentioned twice in the
# file outside its own definitions, and both mentions are fields -- `jv_channel`
# in jobvar_S and `ch_next` in channel_S.  jobvar_S was invisible, so
# `jv_channel` was a root, so channel_S was live, so job_T was live, and the
# +channel and +job types sat there with every function that used them long
# gone.  Recognising this form exposes 53 unreachable definitions, 343 lines.
#
# The lookahead is required rather than optional: a bare `struct foo` line with
# no brace after it is a variable declaration, not a definition.
HEAD_ONLY = re.compile(r'^(?:static\s+)?(?:struct|union|enum)\s+\w+$')
KEYWORDS = {
    'typedef', 'struct', 'union', 'enum', 'const', 'volatile', 'unsigned',
    'signed', 'short', 'long', 'int', 'char', 'float', 'double', 'void',
    'static', 'extern', 'register', 'inline', 'sizeof', 'return', 'if', 'else',
    'for', 'while', 'do', 'switch', 'case', 'default', 'break', 'continue',
    'goto',
}


def definitions(text, b):
    """[(start, end, names)] for every top-level type definition."""
    d = cutil.depths(b)
    out = []
    i = 0
    n = len(text)
    while i < n:
        j = text.find('\n', i)
        j = n if j < 0 else j
        line = text[i:j]
        brace_next = False
        if d[i] == 0 and HEAD_ONLY.match(line.strip()):
            nxt = text[j + 1:text.find('\n', j + 1)] if j < n else ''
            brace_next = nxt.strip() == '{'
        if d[i] == 0 and line.strip() and (START.match(line.strip()) or brace_next):
            # the definition ends at the first top-level ';' from here
            k = i
            depth = 0
            while k < n:
                c = b[k]
                if c in '{[(':
                    depth += 1
                elif c in '}])':
                    depth -= 1
                elif c == ';' and depth == 0:
                    break
                k += 1
            if k >= n:
                break
            body = text[i:k + 1]
            names = set()
            head = body.split('{', 1)[0]
            m = re.search(r'\b(?:struct|union|enum)\s+(\w+)', head)
            if m:
                names.add(m.group(1))
            tail = body.rsplit('}', 1)[-1] if '}' in body else body
            for mm in IDENT.finditer(tail):
                if mm.group() not in KEYWORDS:
                    names.add(mm.group())
            if re.match(r'^\s*(typedef\s+)?enum\b', body):
                inner = body[body.find('{') + 1:body.rfind('}')] if '{' in body else ''
                ib = cutil.blank(inner)
                for part in cutil.split_top(inner, ',', ib):
                    mm = IDENT.search(part)
                    if mm and mm.group() not in KEYWORDS:
                        names.add(mm.group())
            # DOES IT ALSO DECLARE A VARIABLE?  `static struct modmasktable
            # { ... } mod_mask_table[] = { ... };` is a type definition and a
            # variable in one construct, and the declarator sits between the
            # STRUCT's closing brace and the `=` -- not after the last `}`,
            # which is the initialiser's.  So `tail` above never saw it, and the
            # first version of the brace-on-the-next-line fix deleted the whole
            # thing because the TAG was unreachable, taking a live table with
            # it and leaving `mod_mask_table[i]` undeclared 40,000 lines away.
            #
            # A construct that declares a variable is not a type definition to
            # delete: it is a variable, and deadsweep.py owns those.  It is
            # still recorded, so that the mentions INSIDE it stop counting as
            # roots -- which is the whole point of recognising the form.
            # ... and `typedef struct { ... } chanpart_T;` does NOT declare a
            # variable: there the declarator names the TYPE.  Only a
            # non-typedef construct can have one.
            deletable = True
            ob = -1 if re.match(r'^\s*typedef\b', body) else body.find('{')
            if ob >= 0:
                cb = cutil.match(body, ob, cutil.blank(body))
                if cb > 0:
                    decl = body[cb + 1:].rstrip()[:-1]      # drop the ';'
                    if IDENT.search(decl):
                        deletable = False
                        for mm in IDENT.finditer(decl):
                            if mm.group() not in KEYWORDS:
                                names.add(mm.group())
            out.append((i, k + 1, names, deletable))
            i = k + 1
            continue
        i = j + 1
    return out


def main():
    path = sys.argv[1]
    text = open(path, encoding='utf-8', errors='surrogateescape').read()
    b = cutil.blank(text)
    defs = definitions(text, b)
    spans = [(a, z) for a, z, _, _ in defs]
    owner = {}
    for idx, (a, z, names, _) in enumerate(defs):
        for nm in names:
            owner.setdefault(nm, set()).add(idx)

    def inside(pos):
        for a, z in spans:
            if a <= pos < z:
                return True
        return False

    live = set()
    # roots: an identifier mentioned outside every type definition
    pos = 0
    spans_sorted = sorted(spans)
    si = 0
    for m in IDENT.finditer(b):
        p = m.start()
        while si < len(spans_sorted) and spans_sorted[si][1] <= p:
            si += 1
        if si < len(spans_sorted) and spans_sorted[si][0] <= p < spans_sorted[si][1]:
            continue
        live |= owner.get(m.group(), set())

    # close over what the live ones reach
    frontier = set(live)
    while frontier:
        nxt = set()
        for idx in frontier:
            a, z, _, _ = defs[idx]
            for m in IDENT.finditer(b[a:z]):
                for o in owner.get(m.group(), ()):
                    if o not in live:
                        live.add(o)
                        nxt.add(o)
        frontier = nxt

    dead = [i for i in range(len(defs)) if i not in live and defs[i][3]]
    print('%d type definitions, %d unreachable' % (len(defs), len(dead)))
    for i in dead[:20]:
        a, z, names, _ = defs[i]
        print('   %-40s %d lines' % (','.join(sorted(names))[:40],
                                     text.count('\n', a, z) + 1))
    if '--delete' in sys.argv and dead:
        keep = []
        last = 0
        for i in sorted(dead):
            a, z, _, _ = defs[i]
            keep.append(text[last:a])
            last = z
            while last < len(text) and text[last] == '\n':
                last += 1
        keep.append(text[last:])
        open(path, 'w', encoding='utf-8', errors='surrogateescape').write(''.join(keep))
        print('deleted %d definitions' % len(dead))


if __name__ == '__main__':
    main()
