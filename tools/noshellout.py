#!/usr/bin/env python3
"""Keep the shell-out interface; remove the process behind it.

Usage:
    python3 tools/noshellout.py <file>

`:!cmd`, `:[range]!cmd`, `:r !cmd`, `:w !cmd` and `:shell` keep their names,
their ranges and their parsing.  What goes is everything under them: the fork,
the exec, the pipe, the wait -- and the temporary file, which is not interface
but implementation, and exists only because a Unix shell needs a file to read
a range out of.

**The cut is above the temp file, not below it**, and that placement is the
whole point of the phase.  `do_filter()` calls `vim_tempname()` before it ever
reaches `mch_call_shell()`, so stubbing the shell alone leaves the entire
temporary-directory layer alive -- `mkdtemp`, `opendir`, `readdir`, `closedir`,
`rmdir`, `flock`, `dirfd` -- building a file for a command that will never run.
Measured: cutting at `mch_call_shell` removes 6 libc symbols, cutting here
removes 16.

Three entry points, and one call that outlives them:

  * `do_filter()` and `do_shell()` report, in the words `ex_ni` uses for a
    command that is not in this build.  They are the two user-facing paths, and
    they are where a host-provided filter would attach if this editor is ever
    embedded in something that can run one.
  * `get_cmd_output()` returns NULL and says NOTHING.  It is an internal
    helper, its one caller is `find_locales()` -- which shells out to `locale
    -a` to complete `:language` -- and that caller already handles NULL.  An
    emsg here would fire on a Tab press rather than on a command.
  * `ml_close_all()` calls `vim_deltempdir()` on the way out.  Nothing creates
    a temp directory any more, but the teardown is unconditional, and it is the
    last thing holding `opendir` and `readdir`.  Deleting nothing is not worth
    three syscalls.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cutil

NOT_HERE = '    emsg(_(e_sorry_command_is_not_available_in_this_version));'

STUBS = [
    ('do_filter',      NOT_HERE),
    ('do_shell',       NOT_HERE),
    ('get_cmd_output', '    return NULL;'),
]


def replace_body(text, name, body):
    """Swap a file-scope function's body, matching braces rather than scanning.

    A depth count that believes every brace is a brace runs off the end of the
    file: these bodies hold string literals like "*?[{" and shell fragments
    full of them.
    """
    blanked = cutil.blank(text)
    m = re.search(r'^%s\([^\n]*\n' % re.escape(name), text, re.M)
    if not m:
        sys.exit('noshellout: %s is not defined at file scope any more' % name)
    opening = blanked.index('{', m.end())
    close = cutil.match(text, opening, blanked)
    if close < 0:
        sys.exit('noshellout: %s is unbalanced' % name)
    was = text.count('\n', opening, close)
    return text[:opening] + '{\n' + body + '\n}' + text[close + 1:], was


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    text = path.read_text(errors='surrogateescape')

    total = 0
    for name, body in STUBS:
        text, was = replace_body(text, name, body)
        total += was
        print('  noshellout   %-16s was %4d lines, is now one' % (name, was))

    # The teardown that outlives what it tore down.
    before = text
    text = re.sub(r'^[ \t]*vim_deltempdir\(\);[ \t]*\n\n?', '', text, flags=re.M)
    if text == before:
        sys.exit('noshellout: nothing calls vim_deltempdir any more, so this '
                 'phase has already run or the exit path has moved')

    path.write_text(text, errors='surrogateescape')
    print('  noshellout   %d lines of implementation gone; the temp directory '
          'has nothing left to make it' % total)


if __name__ == '__main__':
    main()
