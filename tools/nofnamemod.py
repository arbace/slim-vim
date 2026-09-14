r"""File-name modifiers: `%:p`, `%:h`, `%:t`, `%:r`, `%:e` and the rest.

Usage:
    python3 tools/nofnamemod.py <file>

`eval_vars()` expands `%` and `#` into the current and alternate file names, and
`<cword>`, `<afile>` and the others.  **That stays** -- `:w %` and `:e #` are
how a file name is written without typing it.

What goes is the **suffix language** that may follow: `modify_fname()`, 426
lines implementing `:p` (full path), `:h` (head), `:t` (tail), `:r` (root),
`:e` (extension), `:s/from/to/` (substitute), `:gs`, `:~` and `:.`, applied left
to right so that `%:p:h:t` means something.

It is a small programming language over path strings, and most of it answers
questions this editor can no longer ask.  `:p` made a name absolute by asking
where the working directory is -- Phase 24 fixed that to one answer; `:~`
shortened a name under `$HOME`, and Phase 22 removed the notion of a home
directory; `:s//` needs a regexp over a file name, which is the only place in
the editor a pattern is applied to something that is not buffer text.

After this, `%` is a file name and nothing more.  A modifier that follows it is
left in the command line as the literal characters it is written with, which is
what an editor that does not know the syntax does.

ONE CALLER, which is why the cut is small: `eval_vars()` reaches it once, in the
arm that runs when the next character is not `<`.  The arm goes; the `<` arm --
which strips one extension and is not part of the modifier language -- stays.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cutil


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    text = path.read_text(errors='surrogateescape')

    old = '''        else if (!skip_mod)
        {
            valid |= modify_fname(src, tilde_file, usedlen, &result, &resultbuf, &resultlen);
            if (result == NULL)
            {
                *errormsg = "";
                return NULL;
            }
        }
'''
    if old not in text:
        sys.exit("nofnamemod: eval_vars' modifier arm is not where this expects")
    text = text.replace(old, '', 1)
    print('  nofnamemod   %% is a file name and nothing more')

    # `tilde_file` and `skip_mod` existed only to be passed to it, or to
    # suppress it.  -Wunused-but-set-variable is not a shape deadsweep.py
    # deletes -- they are assigned, so nothing calls them unused -- so they are
    # named here, which is the same reason Phase 22 had to name `at_start`.
    for pat, what in (
            (r'^[ \t]*int         tilde_file = FALSE;\n', "tilde_file's declaration"),
            (r'^[ \t]*int         skip_mod = FALSE;\n', "skip_mod's declaration"),
            (r"^[ \t]*tilde_file =  strcmp\(\(char \*\)\(result\), \(char \*\)\(\"~\"\)\)  == 0;\n",
             'a tilde_file assignment'),
            (r'^[ \t]*skip_mod = TRUE;\n', "skip_mod's assignment")):
        n = 2 if 'tilde_file assignment' in what else 1
        text, got = re.subn(pat, '', text, count=n, flags=re.M)
        if got != n:
            sys.exit('nofnamemod: %s -- expected %d, matched %d' % (what, n, got))
    print('  nofnamemod   tilde_file and skip_mod, which only fed it')

    text, ok = cutil.delete_definition(text, 'modify_fname')
    if not ok:
        sys.exit('nofnamemod: modify_fname is not defined at file scope')

    path.write_text(text, errors='surrogateescape')
    print('  nofnamemod   %d modify_fname mentions left for the sweep'
          % len(re.findall(r'\bmodify_fname\b', text)))


if __name__ == '__main__':
    main()
