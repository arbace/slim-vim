#!/usr/bin/env python3
"""No command that does nothing, and none of three that do something unwanted.

Usage:
    python3 tools/noinert.py <file>

tools/retire.py points the rows at ex_ni; this removes what a row cannot:

  :browse AND :confirm ARE MODIFIERS, matched by name in parse_command_modifiers()
  before the table is consulted.  Their flags went with the file browser and the
  dialogs, so both branches only skipped the word and ran the rest.  Without the
  branch the name reaches the table, and the table says not implemented.

  TERMINAL-JOB MAPPINGS.  :tmap and its family stored mappings for a mode the
  editor never enters -- nothing assigns MODE_TERMINAL to State.  get_map_mode()
  loses its 't', and map_mode_to_chars() the letter it printed for it.  The
  MODE_TERMINAL enumerator and the tests that mask it stay: they are constants,
  and a mask with a bit nothing sets costs nothing.

  COMPLETION ARMS for the retired names, and :behave's argument list, so that the
  sweep takes get_behave_arg().

:behave, :mode, :open and :winpos are rows and nothing else; the sweep takes
their handlers.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cutil


def literal(seg, old, new, what, count=1):
    n = seg.count(old)
    if n != count:
        sys.exit('noinert: %s -- occurs %d times, expected %d' % (what, n, count))
    print('  noinert      %s' % what)
    return seg.replace(old, new)


def in_function(text, name, edit):
    span = cutil.find_definition(text, name)
    if not span:
        sys.exit('noinert: %s is not defined at file scope' % name)
    a, z = span
    return text[:a] + edit(text[a:z]) + text[z:]


def sub_once(seg, pattern, what):
    seg, n = re.subn(pattern, '', seg, flags=re.M)
    if n != 1:
        sys.exit('noinert: %s -- matched %d times, expected 1' % (what, n))
    print('  noinert      %s' % what)
    return seg


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    t = path.read_text(errors='surrogateescape')

    # --- the two modifiers ----------------------------------------------------
    def mods(seg):
        seg = cutil.drop_if(seg, r'^[ \t]*if \(checkforcmd_opt\(&eap->cmd, "browse", 3, TRUE\)\)$', flags=re.M)
        print('  noinert      the :browse modifier')
        seg = sub_once(seg, r"^[ \t]*case 'c':\n"
                            r'[ \t]*if \(!checkforcmd_opt\(&eap->cmd, "confirm", 4, TRUE\)\)\n'
                            r'[ \t]*\{\n[ \t]*break;\n[ \t]*\}\n[ \t]*continue;\n\n',
                       'the :confirm modifier')
        return seg
    t = in_function(t, 'parse_command_modifiers', mods)

    # --- terminal-job mappings ------------------------------------------------
    t = in_function(t, 'get_map_mode', lambda s: sub_once(
        s, r"^[ \t]*else if \(modec == 't'\)\n[ \t]*\{\n[ \t]*mode = MODE_TERMINAL;\n[ \t]*\}\n",
        "get_map_mode's 't'"))
    t = in_function(t, 'map_mode_to_chars', lambda s: sub_once(
        s, r"^[ \t]*if \(mode & MODE_TERMINAL\)\n[ \t]*\{\n[ \t]*ga_append\(&mapmode, 't'\);\n[ \t]*\}\n",
        "map_mode_to_chars printing 't'"))

    # --- completion -----------------------------------------------------------
    def complete(seg):
        for name in ('browse', 'confirm', 'tmap', 'tnoremap', 'tunmap', 'tmapclear'):
            seg = sub_once(seg, r'^[ \t]*case CMD_%s:\n' % name, 'completion for :%s' % name)
        seg = sub_once(seg, r'^[ \t]*case CMD_behave:\n[ \t]*xp->xp_context = EXPAND_BEHAVE;\n'
                            r'[ \t]*xp->xp_pattern = arg;\n[ \t]*break;\n\n',
                       'completion for :behave')
        return seg
    t = in_function(t, 'set_context_by_cmdname', complete)
    t = literal(t, '        {EXPAND_BEHAVE, get_behave_arg, TRUE, TRUE},\n', '', ":behave's argument list")

    left = re.findall(r'"(browse|confirm)", \d, TRUE|modec == \'t\'|CMD_behave:', t)
    if left:
        sys.exit('noinert: still present after the cut: %s' % ', '.join(left))

    path.write_text(t, errors='surrogateescape')
    print('  noinert      no modifier, mapping mode or argument list that does nothing')


if __name__ == '__main__':
    main()
