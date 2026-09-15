#!/usr/bin/env python3
"""No scripts, no session, no autocommands: the questions they leave behind.

Usage:
    python3 tools/nosession.py <file>

tools/retire.py points the rows at ex_ni -- :source, :redir, :sleep, :smile,
:scriptencoding, :scriptversion, :vim9script, :legacy, :autocmd, :augroup,
:doautocmd, :doautoall, :noautocmd, :sandbox, :filetype and :setfiletype.  This
removes what a row cannot:

  THE MODIFIERS ARE PARSED BY NAME.  parse_command_modifiers() matches
  `legacy`, `noautocmd`, `sandbox` and `vim9cmd` before the table is ever
  consulted, so retiring a row changes nothing about `:noautocmd w`.  Those four
  blocks go, and with them the save and restore of 'eventignore' that
  :noautocmd did around its command.

  THE AUTOCOMMAND ENGINE IS ANSWERED AT ITS DOORS.  Nothing can define an
  autocommand any more, so every event fires into an empty table:
  apply_autocmds_group() returns FALSE, has_autocmd() and the per-event has_*()
  say no, and the trigger_*() helpers do nothing -- which is what each of them
  already did with no autocommand defined, so no behaviour moves.  The sweep then
  takes the engine behind the doors.  The 130 calls that fire events stay: each
  is now a call to a constant, and removing them is a phase of its own.

  VIM9 SCRIPT IS GONE WITH ITS COMMANDS.  in_vim9script() could only be true
  after :vim9script or under the vim9cmd modifier, and both are gone.

  SUSPEND STAYS.  CTRL-Z, :stop and :suspend still hand the terminal back to the
  shell.  They were cut once and put back on request: suspending is a job-control
  habit, not a script or a session.

  THE COMMAND LINE LOSES ITS SCRIPTS.  `-S file` sourced a session, `-s file`
  read keystrokes from a file and `-w`/`-W file` recorded them to one.  `-s`
  keeps its other meaning, silent Ex mode, and `-wN` still sets 'window'.

`-u file` stays: it is the only startup file there is, and every harness passes
`-u NONE`.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cutil
import dropopts

UNKNOWN = 'mainerr(ME_UNKNOWN_OPTION, (char_u *)argv[0]);'

# (name, the whole new body)
STUBS = [
    ('apply_autocmds_group', '    return FALSE;\n'),
    ('has_autocmd', '    return FALSE;\n'),
    ('has_cursorhold', '    return FALSE;\n'),
    ('has_winresized', '    return FALSE;\n'),
    ('has_winscrolled', '    return FALSE;\n'),
    ('has_cursormoved', '    return FALSE;\n'),
    ('has_textchanged', '    return FALSE;\n'),
    ('has_insertcharpre', '    return FALSE;\n'),
    ('has_cmdundefined', '    return FALSE;\n'),
    ('has_tabclosedpre', '    return FALSE;\n'),
    ('trigger_cursorhold', '    return FALSE;\n'),
    ('trigger_undo_ftplugin', ''),
    ('trigger_cmd_autocmd', ''),
    ('trigger_winnewpre', ''),
    ('trigger_winclosed', ''),
    ('trigger_tabclosedpre', ''),
    # It scans every window for WinScrolled and WinResized, and leaves at once
    # when neither event has an autocommand -- which neither can now.
    ('may_trigger_win_scrolled_resized', ''),
    ('in_vim9script', '    return FALSE;\n'),
]

# (what, pattern of the `if` line) -- each must occur exactly once, block dropped.
DROPS = [
    ('the legacy modifier', r'^[ \t]*if \(checkforcmd_noparen\(&eap->cmd, "legacy", 3\)\)$'),
    ('the noautocmd modifier', r'^[ \t]*if \(checkforcmd_noparen\(&eap->cmd, "noautocmd", 3\)\)$'),
    ('the sandbox modifier', r'^[ \t]*if \(checkforcmd_noparen\(&eap->cmd, "sandbox", 3\)\)$'),
    ('the vim9cmd modifier', r'^[ \t]*if \(checkforcmd_noparen\(&eap->cmd, "vim9cmd", 4\)\)$'),
    ("noautocmd saving 'eventignore'",
     r'^[ \t]*if \(\(cmod->cmod_flags & CMOD_NOAUTOCMD\) && cmod->cmod_save_ei == NULL\)$'),
    ("noautocmd restoring 'eventignore'", r'^[ \t]*if \(cmod->cmod_save_ei != NULL\)$'),
    ("'loadplugins' switched off by -u NONE, for plugins that are never loaded",
     r'^[ \t]*if \(params\.use_vimrc != NULL && \( strcmp\(\(char \*\)\(params\.use_vimrc\), \(char \*\)\("NONE"\)\)  == 0'),
]

LITERAL = [
    # 'eventignorewin' is window-local, and tools/droplocal.py knows only buffer
    # fields, so its window field and the four places that keep it go here.  Its
    # row goes in the phase, with --local, before the sweep.
    ("the window's 'eventignorewin' field", '    char_u      *wo_eiw;\n', ''),
    ("get_varp() handing out 'eventignorewin'",
     '''        case   (idopt_T)(PV_WIN + (int)(WV_EIW))  :
            return (char_u *)&(curwin-> w_onebuf_opt.wo_eiw );
''', ''),
    ("copy_winopt() copying 'eventignorewin'", '    to->wo_eiw = copy_option_val(from->wo_eiw);\n', ''),
    ("check_winopt() checking 'eventignorewin'", '    check_string_option(&wop->wo_eiw);\n', ''),
    ("clear_winopt() freeing 'eventignorewin'", '    clear_string_option(&wop->wo_eiw);\n', ''),
]

# Inside command_line_scan() only.
PARSER = [
    ("-s outside Ex mode taking a keystroke file",
     '''            case 's':
                if (exmode_active)
                {
                    silent_mode = TRUE;
                }
                else
                {
                    want_argument = TRUE;
                }
                break;
''', '''            case 's':
                if (exmode_active)
                {
                    silent_mode = TRUE;
                }
                else
                {
                    %s
                }
                break;
''' % UNKNOWN),
    ("-w taking a file to record keystrokes to",
     '''                    set_option_value_give_err((char_u *)"window", n, NULL, 0);
                    break;
                }
                want_argument = TRUE;
                break;
''', '''                    set_option_value_give_err((char_u *)"window", n, NULL, 0);
                    break;
                }
                %s
                break;
''' % UNKNOWN),
    ("-w and -W opening the keystroke record",
     '''                case 'w':
                    if (vim_isdigit(*((char_u *)argv[0])))
                    {
                        argv_idx = 0;
                        n = get_number_arg((char_u *)argv[0], &argv_idx, 10);
                        set_option_value_give_err((char_u *)"window", n, NULL, 0);
                        argv_idx = -1;
                        break;
                    }
                __attribute__((fallthrough));
                case 'W':
                    if (scriptout != NULL)
                    {
                        goto scripterror;
                    }
                    if ((scriptout =  fopen((argv[0]), (c == 'w' ?  "a"  :  "w" )) ) == NULL)
                    {
                         fprintf(stderr, "%s", (_("Cannot open for script output: \\""))) ;
                         fprintf(stderr, "%s", (argv[0])) ;
                         fprintf(stderr, "%s", ("\\"\\n")) ;
                        mch_exit(2);
                    }
                    break;
''', ''),
    ("-S being the one option allowed no argument", "argc < 1 && c != 'S'", 'argc < 1'),
]


def replace_body(text, name, new_body):
    span = cutil.find_definition(text, name)
    if not span:
        sys.exit('nosession: %s is not defined at file scope' % name)
    a, z = span
    seg = text[a:z]
    b = cutil.blank(seg)
    o = b.index('{')
    c = cutil.match(seg, o, b)
    return text[:a] + seg[:o] + '{\n' + new_body + '}' + seg[c + 1:] + text[z:]


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    text = path.read_text(errors='surrogateescape')

    for name, new_body in STUBS:
        text = replace_body(text, name, new_body)
    print('  nosession    %d doors of the autocommand engine and Vim9 answer without it' % len(STUBS))

    for what, pattern in DROPS:
        n = len(re.findall(pattern, text, re.M))
        if n != 1:
            sys.exit('nosession: %s -- matches %d times, not once' % (what, n))
        text = cutil.drop_if(text, pattern, flags=re.M)
        print('  nosession    %s' % what)

    for what, old, new in LITERAL:
        n = text.count(old)
        if n != 1:
            sys.exit('nosession: %s -- occurs %d times, not once' % (what, n))
        text = text.replace(old, new)
        print('  nosession    %s' % what)

    # :write and :file to a new name re-run filetype detection when the
    # `filetypedetect` group exists -- a group only :augroup or :autocmd made.
    # The test is known now, and with it goes the last caller of do_doautocmd().
    try:
        text = cutil.fold_never(text, r'^[ \t]*if \(au_has_group\(\(char_u \*\)"filetypedetect"\)\)$', 2, re.M)
    except ValueError as e:
        sys.exit('nosession: filetype detection after a rename -- %s' % e)
    print('  nosession    :write and :file no longer re-detect a filetype no group can detect')

    span = cutil.find_definition(text, 'command_line_scan')
    if not span:
        sys.exit('nosession: command_line_scan is not defined at file scope')
    a, z = span
    fn = text[a:z]
    for what, old, new in PARSER:
        n = fn.count(old)
        if n != 1:
            sys.exit('nosession: %s -- occurs %d times in the parser, not once' % (what, n))
        fn = fn.replace(old, new)
        print('  nosession    %s' % what)
    fn, held = dropopts.drop_short(fn, 0, {'S', 'W'})
    if held != {'S', 'W'}:
        sys.exit('nosession: -S and -W are not both labels in the option switch: %s' % sorted(held))
    fn, held = dropopts.drop_short(fn, 1, {'S', 's'})
    if held != {'S', 's'}:
        sys.exit('nosession: -S and -s are not both in the argument switch: %s' % sorted(held))
    try:
        fn = cutil.fold_never(fn, r"^[ \t]*if \(c == 'S'\)$", 1, re.M)
    except ValueError as e:
        sys.exit('nosession: the session file becoming a :source -- %s' % e)
    print('  nosession    -S, -s file, -w file and -W are unknown options')
    text = text[:a] + fn + text[z:]

    left = [('the four modifiers in the modifier parser',
             r'checkforcmd_noparen\([^,]+, "(legacy|noautocmd|sandbox|vim9cmd)"', 0),
            ('cmod_save_ei outside its declaration', r'\bcmod_save_ei\b', 1),
            ('scriptout opened by the parser', r'\bscripterror\b', 0),
            ('p_lpl outside its declaration and row', r'\bp_lpl\b', 2)]
    for what, pattern, want in left:
        n = len(re.findall(pattern, text))
        if n != want:
            sys.exit('nosession: %s -- %d left, expected %d' % (what, n, want))

    path.write_text(text, errors='surrogateescape')
    print('  nosession    nothing parses a script modifier, suspends from a key, or reads a script file')


if __name__ == '__main__':
    main()
