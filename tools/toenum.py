"""Turn literal-valued object-like macros into enumerators.

Four things must be checked first, and each one has cost a broken build
somewhere:

  * **sizeof(NAME)**.  An enumerator is an int, so sizeof on it is 4.  A pure
    literal body is already int -- sizeof('a') is 4 in C -- so this class is
    safe, but the check is cheap and the failure is silent.
  * **stringification**.  `VIM_TOSTR(VIM_VERSION_MAJOR)` produces "9" only
    while VIM_VERSION_MAJOR is a macro; as an enumerator the name is
    stringified literally and mediumVersion becomes the 35-character string
    "VIM_VERSION_MAJOR.VIM_VERSION_MINOR", which is then STRCPY'd into a
    20-byte buffer.  Nothing but the preprocessor can build a string from a
    constant, so any name reachable by a stringifying macro stays a macro.
  * **width**.  A value that does not fit in int needs `enum : long`.
  * **duplicates and collisions**.  Identical macro redefinition is legal;
    identical enumerator redefinition is not, and ex_cmds.h is inlined twice.
    A macro may also shadow an existing enumerator that nothing references any
    more -- legal for a macro, an error for an enumerator.

Usage: toenum.py <file>
"""
import re
import sys

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cutil
import macros

IDENT = re.compile(r'\b[A-Za-z_]\w*\b')


def stringified_names(path, defs):
    """Identifiers that reach a `#` operator, and so must stay macros."""
    text = open(path, encoding='utf-8', errors='surrogateescape').read()
    stringifiers = set()
    for _, name, params, body in defs:
        if params and any(re.search(r'#\s*%s\b' % re.escape(p), body) for p in params):
            stringifiers.add(name)
    # a macro that passes a parameter to a stringifier is one too
    changed = True
    while changed:
        changed = False
        for _, name, params, body in defs:
            if name in stringifiers or not params:
                continue
            for s in stringifiers:
                if re.search(r'\b%s\s*\(\s*%s\s*\)' % (re.escape(s),
                                                       re.escape(params[0])), body):
                    stringifiers.add(name)
                    changed = True
                    break
    out = set()
    for s in stringifiers:
        for m in re.finditer(r'\b%s\s*\(\s*([A-Za-z_]\w*)\s*\)' % re.escape(s), text):
            out.add(m.group(1))
    # and transitively: a macro whose body is only such a name
    for _, name, params, body in defs:
        if params is None and body.strip() in out:
            out.add(name)
    return out, stringifiers


def main():
    path = sys.argv[1]
    lines = open(path, encoding='utf-8', errors='surrogateescape').read().split('\n')
    text = '\n'.join(lines)
    defs = macros.parse(path)

    keep, stringifiers = stringified_names(path, defs)
    print('stringifying macros: %s' % sorted(stringifiers))
    print('names that must stay macros because they are stringified: %s' % sorted(keep))

    sizeofs = {m.group(1) for m in
               re.finditer(r'\bsizeof\s*\(\s*([A-Za-z_]\w*)\s*\)', text)}

    depth_at = []
    depth = 0
    for line in lines:
        depth_at.append(depth)
        seg = cutil.blank(line)
        depth += seg.count('{') - seg.count('}')

    seen = {}
    hoist = []
    converted = dropped = 0
    for lineno, name, params, body in defs:
        if params is not None or macros.classify(body) not in ('int', 'char'):
            continue
        if name in keep or name in sizeofs:
            continue
        i = lineno - 1
        if name in seen:
            if seen[name] == body:
                lines[i] = None       # ex_cmds.h is inlined twice
                dropped += 1
                continue
            raise SystemExit('%s defined twice with different values' % name)
        seen[name] = body
        indent = lines[i][:len(lines[i]) - len(lines[i].lstrip())]
        kind = 'enum'
        if not body.startswith("'"):
            try:
                v = int(body.rstrip('uUlL'), 0)
                if not (-2**31 <= v < 2**31):
                    kind = 'enum : long'
            except ValueError:
                pass
        decl = '%s { %s = %s };' % (kind, name, body)
        if depth_at[i] > 0:
            hoist.append(decl)
            lines[i] = None
        else:
            lines[i] = indent + decl
        converted += 1
    lines = [l for l in lines if l is not None]
    anchor = max(i for i, l in enumerate(lines) if l.startswith('#include <'))
    lines[anchor + 1:anchor + 1] = [
        '',
        '// Constants that were #defines inside a struct body, where a bare enum',
        '// declaration declares nothing.  They are plain integers with no',
        '// dependencies, so they sit together here.'] + hoist + ['']
    open(path, 'w', encoding='utf-8', errors='surrogateescape').write('\n'.join(lines))
    print('%d macros became enumerators, %d hoisted out of a struct, '
          '%d duplicates dropped' % (converted, len(hoist), dropped))


if __name__ == '__main__':
    main()
