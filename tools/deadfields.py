r"""Struct and union fields nothing outside a type definition ever names.

Usage:
    python3 tools/deadfields.py <file> [--delete]

**A struct field is not a variable.**  gcc has no warning for one that nothing
reads, `deadsweep.py` never sees it, and `typereach.py` works on whole types --
so a field whose only reader went ten phases ago sits there for ever, costing
bytes in every instance of the struct.  This pipeline met that twice by hand:
`b0_uname` in the swap file's block zero, and eight fields of `memfile_T`, both
of which had to be named in a phase tool because nothing would find them.

The rule is the same one the type and function sweeps use, one level down: a
field is live if its name appears **outside every type definition**.  A mention
inside another struct is not a use -- it is another field with the same name --
so reference counting over the whole file would keep half of these alive.

WHAT IT WILL NOT TOUCH, because being wrong here is silent:

  * a field of a type this file does not define.  Only fields declared inside a
    definition `typereach.py` found are candidates, so nothing belonging to
    libc's `struct stat` or `struct tm` is reachable from here at all.
  * a bitfield, a flexible array member, or an anonymous union member -- the
    shapes where a declaration's text does not say plainly what it declares.
  * the last field of a struct that would otherwise become empty, which is not
    C.  An empty struct is left to `typereach.py`, which removes whole types.

ON LAYOUT: removing a field moves the ones after it, and that is only safe
because no struct this file defines describes anything outside the process any
more -- there are no swap files to read, no session files to write, and no
structure is passed to a library.  Phase 11 and phase 21 are what make that
true; before them this tool would have been wrong about block zero.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cutil
import typereach as T

# `type name;` or `type name[...];` -- one declarator, which is this file's
# shape everywhere.  A bitfield (`int x : 1;`), a function pointer and an
# anonymous member all fail to match, which is the intent.
FIELD = re.compile(r'^([A-Za-z_][\w \t]*?[ \t\*])([A-Za-z_]\w*)[ \t]*(\[[^;]*\])?[ \t]*;$')


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    text = path.read_text(errors='surrogateescape')
    # NOT WHILE A STRUCT CAN STILL DESCRIBE A FILE.  Removing a field moves the
    # ones after it, and until the editor can no longer read a swap file, block
    # zero and the memfile's pages are a disk format -- a field nothing in the
    # code reads is still a field another vim wrote.  ml_recover() is what reads
    # them, so its presence is the question, asked of the file rather than of a
    # phase number: slim-vim.c always has it, and whim-vim.c has it until the
    # phase that removes recovery.
    if cutil.find_definition(text, 'ml_recover'):
        print('  deadfields   not while ml_recover() can read a swap file: a struct '
              'layout is still a disk format')
        return 0
    b = cutil.blank(text)
    defs = T.definitions(text, b)

    inside = bytearray(len(text))
    for a, z, _, _ in defs:
        for i in range(a, z):
            inside[i] = 1
    outside = set()
    for m in T.IDENT.finditer(b):
        if not inside[m.start()]:
            outside.add(m.group())

    # candidate declarations, with the definition they belong to
    cand = []                       # (line_start, line_end, name, def_index)
    for idx, (a, z, _, _) in enumerate(defs):
        body = text[a:z]
        if not re.match(r'^\s*(typedef\s+)?(static\s+)?(struct|union)\b', body):
            continue
        pos = a
        for line in body.split('\n'):
            ls, le = pos, pos + len(line)
            pos = le + 1
            t = line.strip()
            if not t or '(' in t or t.startswith('//'):
                continue
            m = FIELD.match(t)
            if not m or m.group(2) in T.KEYWORDS:
                continue
            if m.group(2) in outside:
                continue
            cand.append((ls, le + 1, m.group(2), idx))

    # A POSITIONAL INITIALISER NAMES NO FIELD AT ALL.
    # `static termrequest_T crv_status = {STATUS_GET, -1};` fills two fields and
    # mentions neither, so the second one looks dead by the rule above and
    # removing it leaves "excess elements in struct initializer" -- a warning,
    # not an error, which means a sweep keyed on errors would have shipped it.
    # So a type that is ever initialised WITHOUT designators keeps all its
    # fields.  A designated initialiser is fine: it names what it sets, and the
    # rule above already counted those names.
    # ONE PASS, not one per type.  The first version searched the whole file
    # for every type name it knew -- about 1,500 scans of six megabytes, which
    # took five and a half minutes and made this phase longer than the other
    # twenty-eight together.  Find the initialisers once and look their type up
    # instead.
    positional_names = set()
    # ON THE BLANKED TEXT: a `{` inside a string literal is not an initialiser,
    # and cutil.match would refuse it.
    for m in re.finditer(r'\b([A-Za-z_]\w*)\s+\w+\s*(?:\[[^\]]*\])?\s*=\s*\{', b):
        o = b.index('{', m.end() - 1)
        c = cutil.match(text, o, b)
        if c > 0 and not re.search(r'\.\s*\w+\s*=', text[o:c]):
            positional_names.add(m.group(1))
    positional = set()
    for idx, (_, _, names, _) in enumerate(defs):
        if names & positional_names:
            positional.add(idx)
    cand = [c for c in cand if c[3] not in positional]

    # never empty a struct out: that is not C, and typereach owns whole types
    per_def = {}
    for _, _, _, idx in cand:
        per_def[idx] = per_def.get(idx, 0) + 1
    total_fields = {}
    for idx, (a, z, _, _) in enumerate(defs):
        if idx not in per_def:
            continue
        n = 0
        for line in text[a:z].split('\n'):
            t = line.strip()
            if t and '(' not in t and FIELD.match(t):
                n += 1
        total_fields[idx] = n
    cand = [c for c in cand if total_fields.get(c[3], 0) > per_def[c[3]]]

    if '--delete' in sys.argv and cand:
        for ls, le, _, _ in sorted(cand, reverse=True):
            text = text[:ls] + text[le:]
        path.write_text(text, errors='surrogateescape')
    print('  deadfields   %d fields nothing outside a type names' % len(cand))
    return len(cand)


if __name__ == '__main__':
    sys.exit(0 if main() == 0 else 1)
