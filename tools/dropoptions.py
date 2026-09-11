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


def drop_row(text, name, strict=False, local=False):
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
    # The next two checks are SWEEP-DEPENDENT and only meaningful to a caller
    # that has already swept: before the sweep, the readers they complain about
    # are the ones the sweep is about to remove.  Phase 2 ('spell') and Phase 6
    # ('regexpengine') both trip them and are both correct.
    #
    # AND A ROW LOOKED UP BY NAME CANNOT GO EITHER.  Options are usually
    # reached through their `p_xx` variable, but a handful are reached with
    # findoption() or set_string_option_direct() on the spelled-out name, and
    # that lookup returns -1 for a row that is not there -- E685, then a
    # segfault before the first keystroke.
    #
    # 'fileencodings' is the one that taught this: mb_init() installs a default
    # for it with set_string_option_direct((char_u *)"fencs", ...).  The PV_
    # guard below did not fire, because the row is PV_NONE; nothing about the
    # row says it is spoken for.  So look for the name instead, anywhere but
    # the table itself.
    for spelling in ([] if not strict else re.findall(r'"([^"]+)"', text[m.start():m.start() + 60])[:2]):
        for hit in re.finditer(r'"%s"' % re.escape(spelling), text):
            if abs(hit.start() - m.start()) < 400:
                continue
            line = text[text.rfind('\n', 0, hit.start()) + 1:
                        text.index('\n', hit.start())]
            if re.match(r'[ \t]*\{"', line):
                continue
            sys.exit("dropoptions: '%s' is reached by name as \"%s\" here, not "
                     "only through its variable:\n    %s\nA lookup of a row "
                     "that is not there returns -1, and the caller does not "
                     "check. Remove the caller first."
                     % (name, spelling, line.strip()[:100]))

    # AND THE REAL INVARIANT, of which the two above are special cases: a
    # row is also what INITIALISES its global, so the row can only go if
    # nothing reads that global any more.  'fileencodings' is PV_NONE and is
    # not reached by name once mb_init() stops installing a default -- and
    # dropping it still segfaults, because readfile() dereferences p_fencs.
    #
    # An option whose feature has really gone has an unread global, and the
    # dead-code sweep will delete it a moment later.  One that is still read is
    # not inert; it is live code with its initialiser removed.
    var = re.search(r'\(char_u \*\)&(\w+)', text[m.start():m.start() + 400])
    if var and strict:
        name_of_var = var.group(1)
        others = [h.start() for h in re.finditer(r'\b%s\b' % name_of_var, text)
                  if abs(h.start() - m.start()) >= 400]
        # Mentions inside options[] itself are other rows' business, not a read.
        reads = []
        for o in others:
            line = text[text.rfind('\n', 0, o) + 1:text.index('\n', o)]
            # Not reads: another row of options[], the row's own var field,
            # and -- the one that made this guard cry wolf the first time it
            # was actually wired up -- the variable's OWN DECLARATION.  A
            # declaration is what the row initialises, not something that
            # reads it.
            if (re.match(r'[ \t]*\{"', line)
                    or re.match(r'[ \t]*\(char_u \*\)&', line)
                    or re.match(r'static\b[^=]*\b%s;$' % re.escape(name_of_var), line)):
                continue
            reads.append(line.strip()[:90])
        if reads:
            sys.exit("dropoptions: '%s' still has readers of %s, so its row is "
                     "not inert -- it is what initialises a variable live code "
                     "dereferences:\n    %s\nRemove the readers first."
                     % (name, name_of_var, '\n    '.join(reads[:3])))

    # --local says the caller is removing the buffer-local field in the same
    # phase, with tools/droplocal.py.  It suspends the PV_ guard and nothing
    # else: the name test and the global-read test above still apply, and the
    # phase still has to run the binary afterwards.  Without the pairing this
    # is the flag that reintroduces Phase 14's segfault.
    indir = re.search(r'PV_\w+', text[m.start():m.start() + 400])
    if local:
        indir = None
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
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    strict = '--strict' in sys.argv
    local = '--local' in sys.argv
    if len(args) < 2:
        sys.exit(__doc__)
    path = Path(args[0])
    names = args[1:]
    text = path.read_text(errors='surrogateescape')

    dropped = []
    for name in names:
        text, ok = drop_row(text, name, strict, local)
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
