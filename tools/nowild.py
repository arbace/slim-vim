#!/usr/bin/env python3
"""Stop expanding wildcards by building shell scripts.

Usage:
    python3 tools/nowild.py <file>

Two expanders sit behind `expand_wildcards()` and only one of them is the
editor's own.  `gen_expand_wildcards()` walks directories itself -- opendir,
readdir, `unix_expandpath()` -- and handles `*`, `?`, `[...]`, `~` and `$VAR`
without leaving the process.  Everything it cannot do it hands to
`mch_expand_wildcards()`, which is a different animal entirely: it sniffs
`'shell'` for csh, zsh or bash, picks one of five quoting styles, writes a
shell function into a temporary file, runs the shell, and parses back a
NUL-separated list.

That second expander is the editor doing the shell's job, badly and in 250
lines.  It goes.  What reaches it -- a backtick, a `{a,b}` brace, a quoted
run, a `$VAR` that survived expansion -- is now passed through literally, which
is what `save_patterns()` already does for a pattern with no wildcard in it at
all.  A shell is still the right tool for those; it is just not this process's
job to write one.

THE DELTA: `:e {a,b}.txt` and `:e `ls`` stop expanding and name a file
literally.  `:e *.c`, `:e ~/x`, `:e $HOME/x` and file-name completion are the
native path and do not move.  Shell-out itself stays: `:!`, `:%!`, `:r !` and
the `` `= `` form are untouched.

The definition is not deleted here.  Cut the three calls, and the sweep finds
`mch_expand_wildcards` unreferenced along with `have_wildcard()`, the shell
function strings and whatever else only it named.  That is PURE-GOAL.md's first
rule: remove the entry point, let the compiler find the rest.
"""

import re
import sys
from pathlib import Path

CALL = re.compile(r'\bmch_expand_wildcards\((num_pat, pat, num_file, file)[^)]*\)')
PROTO = re.compile(r'^static int mch_expand_wildcards\([^;\n]*\);$', re.M)


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    text = path.read_text(errors='surrogateescape')

    text, calls = CALL.subn(r'save_patterns(\1)', text)
    if calls != 3:
        sys.exit('nowild: expected 3 delegations to the shell expander, found %d '
                 '-- gen_expand_wildcards has been reshaped and rewriting it by '
                 'guesswork is how an editor stops opening files' % calls)

    # The forward declaration moves with the call.  `save_patterns` is defined
    # in what was os_unix.c, sixty thousand lines below its new caller, and the
    # only reason it needed no prototype before was that nothing used it early.
    # Reusing the slot the old expander's declaration held keeps `static` on it,
    # which is the difference between a file-local function and a new external
    # symbol.
    text, n = PROTO.subn(
        'static int save_patterns(int num_pat, char_u **pat, int *num_file, '
        'char_u ***file);', text)
    if n != 1:
        sys.exit('nowild: expected one declaration of the shell expander to '
                 'reuse, found %d' % n)

    path.write_text(text, errors='surrogateescape')
    left = text.count('mch_expand_wildcards')
    print('  nowild       %d delegations now return the pattern unexpanded; '
          '%d mch_expand_wildcards mentions left for the sweep' % (calls, left))


if __name__ == '__main__':
    main()
