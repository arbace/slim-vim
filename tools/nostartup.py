#!/usr/bin/env python3
"""Nothing is read at startup that was not named on the command line.

Usage:
    python3 tools/nostartup.py <file>

An editor that goes looking for its own configuration has a filesystem layout
in its head.  `source_startup_scripts()` tries, in order: `$VIMRUNTIME/evim.vim`,
`$VIMRUNTIME/defaults.vim`, `$VIM/vimrc`, `$VIMINIT`, `$HOME/.vimrc`,
`$HOME/.exrc`, and -- if `'exrc'` is on -- `./.vimrc` and `./.exrc` in whatever
directory it happens to have been started in, each guarded by an ownership
check because reading a config file out of the current directory is a way to be
handed someone else's commands.

All of it goes.  **`-u <file>` stays**, and so does `:source`: a file the user
names is not the editor going looking, and Phase 12 already decided `:source`
stays.  What is left of the function is the one branch that reads a file it was
told to read.

`NONE`, `NORC` and `DEFAULTS` are still recognised as `-u` arguments and still
mean "read nothing", which they now do by agreeing with everything else.

Two more that read the environment for the same purpose go with it:
`set_init_xdg_rtp()`, which builds a `'runtimepath'` out of `$XDG_CONFIG_HOME`
-- Phase 1 emptied that option and this was still filling it back in -- and
`process_env()`, which ran `$VIMINIT` or `$EXINIT` as Ex commands.

THE DELTA: none, and that is the point rather than a surprise.  Every harness
already passes `-u NONE`, so none of these paths was ever taken in a recorded
run.  What changes is that the editor no longer needs to be told.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cutil

BODY = '''    // Only a file the user named.  Everything this used to search for -- the
    // runtime's defaults, $VIM/vimrc, $VIMINIT, ~/.vimrc, ~/.exrc, and .vimrc
    // or .exrc in the current directory -- is a place the editor went looking,
    // which is what an embedded editor must not do.
    if (parmp->use_vimrc == NULL)
    {
        return;
    }
    if ( strcmp((char *)(parmp->use_vimrc), (char *)("NONE"))  == 0
            ||  strcmp((char *)(parmp->use_vimrc), (char *)("NORC"))  == 0
            ||  strcmp((char *)(parmp->use_vimrc), (char *)("DEFAULTS"))  == 0)
    {
        return;
    }
    if (do_source(parmp->use_vimrc, FALSE, DOSO_NONE, NULL) != OK)
    {
        semsg(_(e_cannot_read_from_str_2), parmp->use_vimrc);
    }'''


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    text = path.read_text(errors='surrogateescape')
    blanked = cutil.blank(text)

    m = re.search(r'^source_startup_scripts\([^\n]*\n', text, re.M)
    if not m:
        sys.exit('nostartup: source_startup_scripts is not defined at file scope')
    o = blanked.index('{', m.end())
    c = cutil.match(text, o, blanked)
    if c < 0:
        sys.exit('nostartup: source_startup_scripts is unbalanced')
    was = text.count('\n', o, c)
    text = text[:o] + '{\n' + BODY + '\n}' + text[c + 1:]
    print('  nostartup    source_startup_scripts was %d lines; it now reads the '
          'file it was told to and nothing else' % was)

    text, n = re.subn(r'^[ \t]*set_init_xdg_rtp\(\);\n', '', text, flags=re.M)
    if n != 1:
        sys.exit('nostartup: expected one set_init_xdg_rtp call, matched %d' % n)
    print("  nostartup    'runtimepath' stops being rebuilt from $XDG_CONFIG_HOME")

    path.write_text(text, errors='surrogateescape')
    print('  nostartup    %d process_env mentions left for the sweep'
          % text.count('process_env'))


if __name__ == '__main__':
    main()
