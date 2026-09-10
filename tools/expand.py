"""Expand every remaining macro at its use sites, then delete the #defines.

Expansion is safe in a way a function is not: it cannot change the
preprocessed token stream, because it is what the preprocessor was going to do.
A function changes types, changes what gcc can prove about the arguments, and
can silently drop a diagnostic.

**Substitute all parameters simultaneously.**  One at a time lets an argument's
own text be rewritten by a later parameter -- that is what corrupted nv_cmds[]
in a previous run, turning NVCMD('b', nv_bck_word, 0, 0) into
{'nv_bck_word', ...} and unbinding b, c and d.

One linear scan per round, over a tokenised view that respects literals, with
every macro looked up in a dict; a pass per macro over a five-megabyte file
would be five gigabytes of scanning.  Bodies are expanded too, so the rounds
converge and the #defines can all go at the end.

Usage: expand.py [--keep=NAME,...] <file> [rounds]
"""
import re
import sys

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cutil
import macros

IDENT = re.compile(r'[A-Za-z_]\w*')


def split_args(text):
    """Top-level comma split of an argument list, keeping the text."""
    b = cutil.blank(text)
    d = cutil.depths(b)
    out, start = [], 0
    for i in range(len(b)):
        if b[i] == ',' and d[i] == 0:
            out.append(text[start:i])
            start = i + 1
    out.append(text[start:])
    return [a.strip() for a in out]


def substitute(body, params, args):
    """All parameters at once."""
    if not params:
        return body
    table = dict(zip(params, args))
    pat = re.compile(r'\b(%s)\b' % '|'.join(re.escape(p) for p in params))
    return pat.sub(lambda m: table[m.group(1)], body)


def one_round(text, table):
    b = cutil.blank(text)
    out = []
    i, n = 0, len(text)
    hits = 0
    while i < n:
        c = b[i]
        if not (c.isalpha() or c == '_'):
            out.append(text[i])
            i += 1
            continue
        m = IDENT.match(b, i)
        name = m.group()
        end = m.end()
        entry = table.get(name)
        if entry is None:
            out.append(text[i:end])
            i = end
            continue
        params, body = entry
        if params is None:
            out.append(' ' + body + ' ')
            i = end
            hits += 1
            continue
        j = end
        while j < n and b[j] in ' \t\n':
            j += 1
        if j >= n or b[j] != '(':
            out.append(text[i:end])
            i = end
            continue
        k = cutil.match(text, j, b)
        if k < 0:
            out.append(text[i:end])
            i = end
            continue
        args = split_args(text[j + 1:k])
        if len(args) == 1 and args[0] == '' and not params:
            args = []
        if len(args) != len(params):
            out.append(text[i:end])
            i = end
            continue
        out.append(' ' + substitute(body, params, args) + ' ')
        i = k + 1
        hits += 1
    return ''.join(out), hits


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--keep=')]
    # Names that must survive as names.  _() and NGETTEXT() become inline
    # functions carrying format_arg, which is what keeps -Wformat seeing
    # through them; expanding them instead builds cleanly and loses the
    # diagnostics silently.
    keep = set()
    for a in sys.argv[1:]:
        if a.startswith('--keep='):
            keep.update(a[len('--keep='):].split(','))
    path = args[0]
    rounds = int(args[1]) if len(args) > 1 else 12
    defs = macros.parse(path)
    table = {name: (params, body) for _, name, params, body in defs
             if name not in keep}
    lines = open(path, encoding='utf-8', errors='surrogateescape').read().split('\n')
    dropped = {ln for ln, _, _, _ in defs}
    text = '\n'.join(l for i, l in enumerate(lines) if (i + 1) not in dropped)
    print('%d macros, %d #define lines removed' % (len(table), len(dropped)))
    # The preprocessor rescans what an expansion produces, and so must this:
    # a macro name that arrives as an *argument* -- INIT(= MAXLNUM) -- is only
    # visible after the enclosing expansion has been done.  Keep the table
    # after the #defines are gone and iterate until nothing changes.
    for r in range(rounds):
        text, hits = one_round(text, table)
        print('round %d: %d expansions' % (r + 1, hits))
        if not hits:
            break
    open(path, 'w', encoding='utf-8', errors='surrogateescape').write(text)


if __name__ == '__main__':
    main()
