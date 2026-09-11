#!/usr/bin/env python3
"""Delete option rows whose feature is not in this build.

Usage:
    python3 tools/dropoptions.py <file> <option-name> ...

An option that cannot do anything is a lie, and the same argument that removes
`:help` from an editor with no runtime removes `'spelllang'` from one with no
spell checker: reporting a setting that nothing reads is worse than reporting
that the setting does not exist.

Two places name an option and both are handled, because leaving either behind
is a different kind of wrong:

  * the options[] table itself -- the row, which may run to several lines and
    ends at the brace that closes its initialiser, so the extent is found by
    matching braces rather than by counting lines;
  * modeline_whitelist[], the options a modeline is allowed to set.  A name
    left there outlives the option it names.

It refuses on a name it cannot find, because a silent miss leaves the row in
place and the report would say the work was done.

What it deliberately does NOT do is decide what becomes unreachable next.  That
is the dead-code sweep's job, and PURE-GOAL.md's first rule: cut the entry
point, let the compiler find the rest.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cutil


def drop_row(text, name):
    """Remove options[]'s row for `name`, found by brace matching."""
    m = re.search(r'^[ \t]*\{"%s",' % re.escape(name), text, re.M)
    if not m:
        return text, False
    start = m.start()

    # A BUFFER-LOCAL OR WINDOW-LOCAL ROW CANNOT SIMPLY GO, and the failure is
    # silent until the editor runs.  A row whose `indir` is anything but
    # PV_NONE owns two things: the global `p_xx`, and a `b_p_xx` or `w_p_xx`
    # field that set_init_1() initialises BY WALKING THIS TABLE.  Remove the
    # row and the global is never set, so it stays NULL -- and any reader the
    # dead-code sweep does not reach dereferences it at startup.
    #
    # 'tagcase' is the one that taught this.  Dropping it built cleanly, swept
    # to silence, passed the linkage and symbol checks, and segfaulted before
    # the first keystroke; the harness reported it as every behaviour case and
    # every Ex command moving at once, which is what a crash looks like from
    # the outside.  Every option any phase had dropped until then was PV_NONE,
    # so nothing had ever exercised this path.
    #
    # Refusing is the right answer rather than handling it: removing the
    # buffer-local field, its initialiser, its copy, its free and its readers
    # is real surgery, and it should be a phase that says so, not a side effect
    # of a call that looks like the six beside it.
    indir = re.search(r'PV_\w+', text[m.start():m.start() + 400])
    if indir and indir.group(0) != 'PV_NONE':
        sys.exit("dropoptions: '%s' is %s -- a buffer- or window-local option "
                 "whose row also initialises its global.  Removing the row "
                 "leaves that global NULL and the editor segfaults at startup. "
                 "Remove the local field first, in a phase that says it is "
                 "doing that." % (name, indir.group(0)))
    # The row is one brace group: from its `{` to the matching `}`, plus the
    # comma and the newline that follow it.
    blanked = cutil.blank(text)
    end = cutil.match(text, text.index('{', start), blanked)
    if end < 0:
        sys.exit('dropoptions: the row for %s is not balanced' % name)
    end += 1
    while end < len(text) and text[end] in ' \t,':
        end += 1
    if end < len(text) and text[end] == '\n':
        end += 1
    return text[:start] + text[end:], True


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    names = sys.argv[2:]
    text = path.read_text(errors='surrogateescape')

    dropped = []
    for name in names:
        text, ok = drop_row(text, name)
        if not ok:
            sys.exit('dropoptions: no options[] row for %r -- it has already '
                     'gone, or the table has moved under this phase' % name)
        dropped.append(name)

    # modeline_whitelist[] outlives the options it names unless it is told.
    whitelisted = 0
    for name in names:
        pat = re.compile(r'^[ \t]*"%s",\n' % re.escape(name), re.M)
        text, k = pat.subn('', text)
        whitelisted += k

    path.write_text(text, errors='surrogateescape')
    print('  options      %d rows dropped (%s), %d modeline entries with them'
          % (len(dropped), ', '.join(dropped), whitelisted))


if __name__ == '__main__':
    main()
