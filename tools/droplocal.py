#!/usr/bin/env python3
"""Remove a buffer-local option's field, and the plumbing that maintains it.

Usage:
    python3 tools/droplocal.py <file> <buffer-field> ...

It takes the FIELD name -- b_p_path, b_p_tc -- and not the option name, because
by the time it runs the option's row is already gone and there is nothing left
to look the field up from.  That ordering is forced: see below.

`tools/dropoptions.py` refuses a row whose `indir` is not `PV_NONE`, because the
row is also what initialises the global -- Phase 14 learned that from `'tagcase'`
by segfaulting before the first keystroke.  This is the other half: it removes
the buffer-local *field* and everything that keeps it alive, so that the row
becomes ordinary and `dropoptions.py` will take it.

An option reaches its buffer through five places, and all five are one line or
two.  Every one is a fixed idiom, which is why this can be a tool at all:

    buf_T                 char_u *b_p_xx;           the field
    buf_copy_options()    buf->b_p_xx = ...;        a new buffer gets one
    check_buf_options()   check_string_option(&buf->b_p_xx);
    free_buf_options()    clear_string_option(&buf->b_p_xx);
    get_varp()            case PV_XX: return ...;   one line, or the two-line
                                                    "local if set" form

What this does NOT do is decide whether the option is dead.  That is the
caller's judgement, and `dropoptions.py --strict` is what checks it afterwards:
if a real reader survives, the global still has one and the drop is refused.
This tool only removes the plumbing that would make that check answer wrongly --
plumbing is not a reader, it is the option existing.
"""

import re
import sys
from pathlib import Path


def drop_field(text, var, name):
    """Every site of buf->VAR that is plumbing rather than a read."""
    n = 0
    pats = [
        # the field in buf_T
        r'^[ \t]*(?:char_u[ \t]*\*|int[ \t]+|long[ \t]+)%s;\n' % re.escape(var),
        # buf_copy_options(), free_buf_options(), buf_clear_file()
        # `buf->` only.  buf_copy_options(), free_buf_options() and
        # buf_clear_file() all take the buffer as a parameter; a `curbuf->`
        # assignment is somebody deciding something, and belongs to the phase.
        r'^[ \t]*buf->%s = [^\n]*;\n' % re.escape(var),
        # One exception, and it is an initialiser rather than a decision:
        # set_init_1() seeds the current buffer's copy with the -1 sentinel
        # that means "this buffer has no opinion, follow the global".
        r'^[ \t]*curbuf->%s = -1;\n' % re.escape(var),
        # check_buf_options(), free_buf_options()
        r'^[ \t]*(?:check|clear)_string_option\(&buf->%s\);\n' % re.escape(var),
        # get_varp(): the plain form, then the "local if set" form
        r'^[ \t]*case[^\n]*\n[ \t]*return \(char_u \*\)&\(curbuf->%s\);\n' % re.escape(var),
        r'^[ \t]*case[^\n]*\n[ \t]*return [^\n]*curbuf->%s[^\n]*\n'
        r'[ \t]*\? \(char_u \*\)&\(curbuf->%s\) : p->var;\n' % (re.escape(var), re.escape(var)),
    ]
    for pat in pats:
        text, k = re.subn(pat, '', text, flags=re.M)
        n += k
    return text, n


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    text = path.read_text(errors='surrogateescape')

    for bvar in sys.argv[2:]:
        if bvar not in text:
            sys.exit('droplocal: there is no %s here' % bvar)
        name = bvar
        text, n = drop_field(text, bvar, name)
        if n < 3:
            sys.exit('droplocal: %s: only %d plumbing sites, expected at least '
                     'the field, an initialiser and a get_varp case -- the shape '
                     'has moved' % (bvar, n))
        left = text.count(bvar)
        if left:
            sys.exit('droplocal: %s still has %d mentions after the plumbing '
                     'went -- those are readers, and the phase has to deal with '
                     'them before the field can go' % (bvar, left))
        print('  droplocal    %-10s %d plumbing sites' % (bvar, n))

    path.write_text(text, errors='surrogateescape')


if __name__ == '__main__':
    main()
