#!/usr/bin/env python3
"""Command-line options that no longer decide anything.

Usage:
    python3 tools/nocmdopts.py <file>

Four options outlived what they controlled, and each in a different way:

  -y   evim mode.  `parmp->evim_mode` is assigned here and read nowhere: its
       one reader was the line in source_startup_scripts() that sourced
       $VIMRUNTIME/evim.vim, and Phase 20 removed it.
  -Z   restricted mode.  Its whole purpose is to refuse shell commands, and
       check_restricted() has exactly two callers left -- do_bang(), stubbed in
       Phase 10, and ex_stop().  No live command carries EX_RESTRICT either;
       the ten that do are all ex_script_ni.  It guards nothing.
  -t   jump to a tag at startup, by running `:ta <tag>`.  Phase 12 retired
       :tag, so the option's whole effect is to run a command that reports it
       is not implemented.
  -i   the viminfo file.  `'viminfo'` and `'viminfofile'` are wired to
       (char_u *)NULL -- accepted and stored nowhere -- in BOTH editors: the
       tiny configuration has no viminfo at all.  `-i NONE` has been a no-op
       for as long as this fork has existed, which is why the harnesses passed
       it without anyone noticing it did nothing.

`-u <file>` STAYS.  Phase 20 removed every path the editor searched on its own;
a file the user names is not the editor going looking, and `:source` stays for
the same reason.

`--clean` keeps its other effects and loses its `'viminfofile'` line, because
that reached the option BY NAME -- set_option_value_give_err((char_u *)"vif") --
and a name lookup of a row that is not there answers -1 without the caller
checking.  That is the trap Phases 17 and 19 both met.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cutil
import funcreach

# SCOPED TO THE PARSER.  `case 't':` occurs in get_c_indent() as well, three
# thousand lines away and about 'cinoptions', and a substitution with count=1
# takes whichever comes first in the FILE.  It did: the first attempt cut a
# branch out of the C indenter and gcc reported a duplicate case value in a
# function this phase never meant to touch.  Everything that edits the option
# parser is applied to command_line_scan()'s body alone.
IN_PARSER = [
    ("-t, which ran a :tag that is not implemented",
     r'[ \t]*case \'t\':\n(?:[^\n]*\n)*?[ \t]*break;\n\n', ''),
    ("-t's argument",
     r'[ \t]*case \'t\':\n[ \t]*parmp->tagname = \(char_u \*\)argv\[0\];\n[ \t]*break;\n\n', ''),
    ("-i's argument, which set an option wired to NULL",
     r'[ \t]*case \'i\':\n'
     r'[ \t]*set_option_value_give_err\(\(char_u \*\)"vif", 0L, \(char_u \*\)argv\[0\], 0\);\n'
     r'[ \t]*break;\n\n', ''),
    ("-i and -t from the list of options that take one",
     r'([ \t]*case \'S\':\n)[ \t]*case \'i\':\n[ \t]*case \'d\':\n[ \t]*case \'T\':\n',
     r"\1            case 'd':\n            case 'T':\n"),
    ("--clean setting a viminfo file",
     r'[ \t]*set_option_value_give_err\(\(char_u \*\)"vif", 0L, \(char_u \*\)"NONE", 0\);\n', ''),
]

ELSEWHERE = [
    # The fields the four options set, and their now-unreachable readers.  A
    # struct field is not a variable, so no warning reports it and the sweep
    # cannot see it -- the same shape Phase 19 met with b_start_fenc.
    # SCOPED BY THEIR NEIGHBOUR.  `char_u *tagname;` is also a field of
    # taggy_T, seventeen hundred lines earlier, and an unanchored pattern takes
    # the first -- which removed the tag stack's field and broke five lines in
    # two functions this phase never meant to touch.  `int edit_type;` sits
    # immediately above mparm_T's and nowhere else.
    ("mparm_T's evim_mode field",
     r'^[ \t]*int[ \t]*evim_mode;\n', ''),
    ("the startup tag jump, which nothing can now ask for",
     r'[ \t]*if \(params\.tagname != NULL\)\n[ \t]*\{\n(?:[^\n]*\n)*?'
     r'[ \t]*do_cmdline_cmd\(IObuff\);\n(?:[^\n]*\n)*?^[ \t]{4}\}\n\n?', ''),
    ("exe_pre_commands testing for one",
     r'[ \t]*if \(parmp->tagname == NULL && curwin->w_cursor\.lnum <= 1\)\n'
     r'([ \t]*\{\n[ \t]*curwin->w_cursor\.lnum = 0;\n[ \t]*\}\n)',
     '    if (curwin->w_cursor.lnum <= 1)\n\\1'),
    ("mparm_T's tagname field",
     r'(^[ \t]*int[ \t]*edit_type;\n)[ \t]*char_u[ \t]*\*tagname;\n', r'\1'),
    # And the flag itself, out of the twenty-four rows that carry it.  With the
    # gate gone it is a bit nothing reads; leaving it is leaving a concept in
    # the table that the code no longer has.
    ("EX_RESTRICT out of the command table", r'\|EX_RESTRICT\)', ')', 24),
    # The other way in, and a small find of its own: set_init_restricted_mode()
    # reads $SHELL at startup and turns the mode on when it is nologin or
    # false.  An environment read, deciding a mode that now restricts nothing.
    ("$SHELL deciding restricted mode at startup",
     r'^[ \t]*set_init_restricted_mode\(\);\n', ''),
    ("restricted mode in do_bang and ex_stop",
     r'check_restricted\(\) \|\| check_secure\(\)', 'check_secure()'),
    ("ex_stop's restricted check",
     r'[ \t]*if \(check_restricted\(\)\)\n[ \t]*\{\n[ \t]*return;\n[ \t]*\}\n\n?', ''),
    ("the EX_RESTRICT gate, which no live command reaches",
     r'[ \t]*if \(restricted != 0 && \(ea\.argt & EX_RESTRICT\)\)\n'
     r'[ \t]*\{\n(?:[^\n]*\n)*?[ \t]*\}\n', ''),
    ("restricted deciding whether SIGTSTP is ignored",
     r'ignore_sigtstp = restricted \|\| SIG_IGN', 'ignore_sigtstp = SIG_IGN'),
]


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    text = path.read_text(errors='surrogateescape')
    blanked = cutil.blank(text)
    defs = funcreach.definitions(text, blanked)
    if 'command_line_scan' not in defs:
        sys.exit('nocmdopts: command_line_scan is not defined at file scope')
    a, c = defs['command_line_scan']
    body = text[a:c]
    for what, pat, repl in IN_PARSER:
        body, n = re.subn(pat, repl, body, count=1, flags=re.M)
        if n != 1:
            sys.exit('nocmdopts: %s -- not found in the option parser' % what)
        print('  nocmdopts    %s' % what)
    text = text[:a] + body + text[c:]

    for edit in ELSEWHERE:
        what, pat, repl = edit[0], edit[1], edit[2]
        want = edit[3] if len(edit) > 3 else 1
        text, n = re.subn(pat, repl, text, count=0 if want > 1 else 1, flags=re.M)
        if n != want:
            sys.exit('nocmdopts: %s -- expected %d, matched %d' % (what, want, n))
        print('  nocmdopts    %s' % what)
    path.write_text(text, errors='surrogateescape')


if __name__ == '__main__':
    main()
