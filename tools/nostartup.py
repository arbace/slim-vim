#!/usr/bin/env python3
"""Nothing is read at startup, not even a file named on the command line.

Usage:
    python3 tools/nostartup.py <file>

An editor that goes looking for its own configuration has a filesystem layout
in its head.  `source_startup_scripts()` tries, in order: `$VIMRUNTIME/evim.vim`,
`$VIMRUNTIME/defaults.vim`, `$VIM/vimrc`, `$VIMINIT`, `$HOME/.vimrc`,
`$HOME/.exrc`, and -- if `'exrc'` is on -- `./.vimrc` and `./.exrc` in whatever
directory it happens to have been started in, each guarded by an ownership
check because reading a config file out of the current directory is a way to be
handed someone else's commands.

All of it goes, and so does `-u <file>`, the one branch that read a file it was
told to read: whim18.sh drops the option with tools/dropopts.py.  With no path
left to search and no name to be given, the function has no body, its call goes,
and the sweep takes it.  The `-u NONE` test in main() that switched
'loadplugins' off goes with the option it asked about.

It went in this phase, not later, so that no tool has to pass `-u NONE`: every
harness isolates the editor through its environment instead -- an empty $HOME,
$VIM and $VIMRUNTIME -- which is what `-u NONE` was for, and which works as well
against slim-vim, which still searches.

Two more that read the environment for the same purpose go with it:
`set_init_xdg_rtp()`, which builds a `'runtimepath'` out of `$XDG_CONFIG_HOME`
-- Phase 1 emptied that option and this was still filling it back in -- and
`process_env()`, which ran `$VIMINIT` or `$EXINIT` as Ex commands.

THE DELTA: none.  No harness passes `-u`, and none of these paths is taken
under an empty environment.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cutil

BODY = ''


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
    text = text[:o] + '{\n}' + text[c + 1:]
    print('  nostartup    source_startup_scripts was %d lines; it now has no body' % was)

    text, n = re.subn(r'^[ \t]*source_startup_scripts\(&params\);\n', '', text, flags=re.M)
    if n != 1:
        sys.exit('nostartup: expected one source_startup_scripts call, matched %d' % n)
    print('  nostartup    startup reads nothing, so it does not call the function that read')

    pat = r'^[ \t]*if \(params\.use_vimrc != NULL && \( strcmp\(\(char \*\)\(params\.use_vimrc\), \(char \*\)\("NONE"\)\)  == 0'
    if len(re.findall(pat, text, re.M)) != 1:
        sys.exit('nostartup: the -u NONE test in main() is not where this expects')
    text = cutil.drop_if(text, pat, flags=re.M)
    print("  nostartup    -u NONE no longer switches 'loadplugins' off")

    text, n = re.subn(r'^[ \t]*set_init_xdg_rtp\(\);\n', '', text, flags=re.M)
    if n != 1:
        sys.exit('nostartup: expected one set_init_xdg_rtp call, matched %d' % n)
    print("  nostartup    'runtimepath' stops being rebuilt from $XDG_CONFIG_HOME")

    path.write_text(text, errors='surrogateescape')
    print('  nostartup    %d process_env mentions left for the sweep'
          % text.count('process_env'))


if __name__ == '__main__':
    main()
