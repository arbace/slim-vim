#!/usr/bin/env python3
"""Find functions nothing reaches, including ones that only reach each other.

Usage:
    python3 tools/funcreach.py <file> [--delete]

`-Wall` reports a static function that nothing *mentions*, which is reference
counting, and reference counting cannot see a group that mentions itself.  Two
kinds of that are everywhere in this file and both survived the dead-code sweep
to a fixpoint:

  * a recursive-descent parser -- nfa_reg calls nfa_regbranch calls
    nfa_regconcat calls nfa_regpiece calls nfa_regatom, which calls nfa_reg
    again.  Delete the one caller above it and all five still name each other.
  * a matcher and its helper -- nfa_regmatch and addstate call each other.

Six thousand lines of NFA engine sat there after its only entry point was cut,
because every one of its functions was mentioned by another one of them.

This is `typereach.py`'s argument applied to functions: **reachability, not
reference counting.**  Take roots, close over what they reach, and whatever is
left over is unreachable however often it is named.

The roots are:

  * `main`, the program's own entry point;
  * every function whose name appears OUTSIDE all function bodies -- a static
    table of handlers like `cmdnames[]`, a struct of callbacks like
    `bt_regengine`, an initialiser.  That is how a function reached only
    through a pointer stays alive, and getting this wrong would delete every Ex
    command handler in the file.

**A prototype is not a use**, and this is the whole difficulty.  Nearly two
thousand `static` declarations sit at the top of the file, outside every body,
naming every function there is; count those as roots and everything is
reachable, which is exactly what the first attempt reported.  They are stripped
before roots are taken -- a declaration is a line that names a function and ends
in a semicolon, with any attribute continuation that follows it.

It is deliberately conservative in one direction: a name that merely *appears*
in a live function's body counts as reached, even in a comment-free file where
it might be a variable of the same name.  Over-keeping is recoverable; the
other error deletes something that runs.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cutil

IDENT = re.compile(r'\b[A-Za-z_]\w*\b')
# A definition at file scope: the name at column 0, a parameter list, and a
# body that opens on the next line.  Phase 7 of the slim pipeline guarantees
# this shape -- one statement per line, every brace where it belongs.
# Two things in this pattern are load-bearing and both were wrong first time,
# with the same symptom: a span that ended at the wrong brace, so the deletion
# took a function's header and left its body as a file-scope fragment.
#
#   `[^;\n]*`, never `[^;]*` -- a negated class matches newlines too, so a
#   greedy parameter list runs into the body and stops at some later `)` that
#   happens to end a line.  Phase 7 guarantees the whole list is on one line.
#   `[ \t]*$`, never `\s*$` -- \s matches a newline, with the same effect.
DEFN = re.compile(r'^([A-Za-z_]\w*)\([^;\n]*\)[ \t]*$', re.M)


def definitions(text, blanked):
    """{name: (start, end)} for every function defined at file scope."""
    out = {}
    for m in DEFN.finditer(blanked):
        i = m.end()
        while i < len(blanked) and blanked[i] in ' \t\n':
            i += 1
        if i >= len(blanked) or blanked[i] != '{':
            continue
        end = cutil.match(text, i, blanked)
        if end < 0:
            continue

        # The return type sits on the line above; take it with the function.
        start = text.rfind('\n', 0, m.start())
        start = text.rfind('\n', 0, start) + 1 if start > 0 else 0
        out[m.group(1)] = (start, end + 1)
    return out


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    delete = '--delete' in sys.argv
    if not args:
        sys.exit(__doc__)
    path = Path(args[0])
    text = path.read_text(errors='surrogateescape')
    blanked = cutil.blank(text)

    defs = definitions(text, blanked)
    if len(defs) < 100:
        sys.exit('funcreach: only %d definitions found, which cannot be right '
                 'for this file -- the shape it matches has changed, and acting '
                 'on the answer would delete most of the program' % len(defs))

    # What each body mentions.
    mentions = {}
    for name, (a, b) in defs.items():
        mentions[name] = set(IDENT.findall(text[a:b])) & set(defs)

    # Outside every body: tables, initialisers, prototypes.  A handler reached
    # only through cmdnames[] lives here and nowhere else.
    spans = sorted(defs.values())
    outside, prev = [], 0
    for a, b in spans:
        outside.append(text[prev:a])
        prev = b
    outside.append(text[prev:])

    # Strip the declarations.  A prototype names a function and does not use
    # it, and this file has nearly two thousand of them in one block.
    PROTO = re.compile(r'^[A-Za-z_][A-Za-z0-9_ \t*]*\b\w+\([^;]*\)\s*;\s*$', re.M)
    ATTR = re.compile(r'^\s+__attribute__.*;\s*$', re.M)
    cleaned = PROTO.sub('', '\n'.join(outside))
    cleaned = ATTR.sub('', cleaned)
    # Two-line prototypes: the declaration ends on a continuation carrying an
    # attribute, so the first line has no semicolon.  Take those too.
    cleaned = re.sub(r'^[A-Za-z_][A-Za-z0-9_ \t*]*\b\w+\([^;]*\)\s*$\n\s*$',
                     '', cleaned, flags=re.M)
    roots = (set(IDENT.findall(cleaned)) & set(defs)) | {'main'}

    seen, stack = set(), [r for r in roots if r in defs]
    while stack:
        f = stack.pop()
        if f in seen:
            continue
        seen.add(f)
        stack.extend(mentions.get(f, ()))

    dead = sorted(set(defs) - seen)
    lines = sum(text.count('\n', *defs[f]) for f in dead)
    print('  funcreach    %d definitions, %d reachable, %d not (%d lines)'
          % (len(defs), len(seen), len(dead), lines))

    if dead and delete:
        for f in sorted(dead, key=lambda f: -defs[f][0]):
            a, b = defs[f]
            while b < len(text) and text[b] == '\n':
                b += 1
            text = text[:a] + text[b:]
        path.write_text(text, errors='surrogateescape')
        print('  funcreach    deleted: %s%s'
              % (', '.join(dead[:6]), '...' if len(dead) > 6 else ''))


if __name__ == '__main__':
    main()
