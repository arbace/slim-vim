#!/usr/bin/env python3
"""Cut every entry point that presumes an installed runtime directory.

Usage:
    python3 tools/noruntime.py <file>

This does not delete the help machinery.  It cuts the four ways in and lets the
dead-code sweep find what is unreachable behind them -- which is PURE-GOAL.md's
first rule, and not merely tidier: a list of 900 functions to delete is a
restatement of what the compiler already knows, and it is wrong the first time
upstream moves one of them.

The four:

  * Six command rows point at `ex_ni`.  Never deleted -- enum CMD_index,
    cmdnames[] and the derived ex_cmdidxs block keep their shape, nothing
    renumbers, and the trap SLIM-GOAL.md records cannot fire: deleting :help
    makes the name resolve to :helpclose, silently.
  * 'helpfile' and 'runtimepath' default to "" in both halves of the
    {vi, vim} pair.
  * The runtimepath builders -- the functions that assemble
    $VIM/vimfiles,$VIMRUNTIME,... at startup, including the XDG variant --
    stop assembling anything.
  * The VIMRUNTIME branches of vim_getenv() and vim_setenv().  That layer
    DERIVES a runtime directory from the executable's own path when the
    variable is unset, which is exactly the behaviour an embedded binary must
    not have: it would find whatever happens to sit beside it.

Every edit is an exact-text replacement and the script fails if one does not
apply.  A phase that silently skipped an entry point would leave an editor that
still goes looking for a file it will never find, and the harness would not
necessarily say so.
"""

import re
import sys
from pathlib import Path

COMMANDS = ('help', 'helpclose', 'helptags', 'runtime', 'exusage', 'viusage')

# The path strings the runtime layer assembles or defaults to.  Each becomes
# empty; none is deleted, so the options still exist and still report.
RUNTIME_PATHS = (
    '"$VIMRUNTIME/doc/help.txt"',
    '"~/.vim,$VIM/vimfiles,$VIMRUNTIME,$VIM/vimfiles/after,~/.vim/after"',
    '"$VIM/vimfiles,$VIMRUNTIME,$VIM/vimfiles/after"',
    '"$XDG_CONFIG_HOME/vim,$VIM/vimfiles,$VIMRUNTIME,$VIM/vimfiles/after,'
    '$XDG_CONFIG_HOME/vim/after"',
    '"~/.config/vim,$VIM/vimfiles,$VIMRUNTIME,$VIM/vimfiles/after,'
    '~/.config/vim/after"',
)


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    text = path.read_text(errors='surrogateescape')

    # --- the commands -----------------------------------------------------
    n_cmd = 0
    for name in COMMANDS:
        pat = re.compile(r'(\[CMD_%s\] = \{\(char_u \*\)"%s", sizeof\("%s"\) - 1, )'
                         r'(\w+)' % (name, name, name))
        text, k = pat.subn(lambda m: m.group(1) + 'ex_ni', text)
        if k != 1:
            sys.exit('noruntime: expected one row for :%s, matched %d' % (name, k))
        n_cmd += k

    # --- the paths --------------------------------------------------------
    n_path = 0
    for s in RUNTIME_PATHS:
        if s not in text:
            sys.exit('noruntime: this runtime path is not here any more, so the '
                     'file has moved under this phase: %s' % s)
        n_path += text.count(s)
        text = text.replace(s, '""')

    # --- the environment layer -------------------------------------------
    # vim_getenv() derives a runtime directory from argv[0]'s directory when
    # VIMRUNTIME is unset.  Making the test never fire is enough: the code
    # behind it becomes unreachable and the sweep takes it.
    before = text
    text = text.replace(
        'vimruntime = ( strcmp((char *)(name), (char *)("VIMRUNTIME"))  == 0);',
        'vimruntime = FALSE;')
    if text == before:
        sys.exit('noruntime: vim_getenv no longer tests for VIMRUNTIME')

    path.write_text(text, errors='surrogateescape')
    print('  noruntime    %d commands to ex_ni, %d runtime paths emptied, '
          'vim_getenv no longer derives one' % (n_cmd, n_path))


if __name__ == '__main__':
    main()
