r"""There is no mouse.

Usage:
    python3 tools/nomouse.py <file>

A terminal mouse is a protocol, not a device: the terminal is asked to report
clicks, it sends escape sequences, and the editor decodes them into key codes
that the normal, insert and command-line loops dispatch like any other key.  All
four layers are here, and an embedded editor driven from a keyboard needs none
of them.

**The island is bounded**, which is what makes this a cut rather than a rewrite.
Thirty-five functions mention the mouse and all but two are reached only from
each other; `tools/funcreach.py` deletes the interior once the roots are gone,
so this tool removes only the roots:

  * **the tables.**  Twenty-two rows of `nv_cmds[]` pointing at `nv_mouse()` and
    `nv_mousescroll()`, and the `<LeftMouse>`, `<ScrollWheelUp>`, `<MouseMove>`
    … rows of the key-name table, so that `:map <LeftMouse>` no longer names
    anything.
  * **the dispatch.**  The mouse `case` runs in `edit()`'s insert loop and in
    `getcmdline_int()`'s command-line loop, the two `do_mouse()` calls in
    `nv_brackets()` and `nv_g_cmd()` (`]<LeftMouse>` and `g<LeftMouse>`), and
    the `jump_to_mouse()` in `wait_return()`.
  * **the decoder.**  `check_termcode_mouse()`'s call, and the three places in
    `set_termname()` and `did_set_ttymouse()` that install or remove a mouse
    termcode.
  * **`setmouse()`**, whose 31 calls are every one of them a bare statement --
    it exists to tell the terminal whether to report, and there is nothing to
    tell.  `mch_setmouse()`'s three calls outside the island go with it.
  * **`mouse_has()`** answers whether `'mouse'` covers the current mode.  Three
    callers are outside the island and each becomes the answer it now always
    gets: FALSE.

TWO NAMES THAT ARE NOT ABOUT THE MOUSE, and both were checked rather than
assumed.  `get_mouse_class()`, `find_start_of_word()` and `find_end_of_word()`
classify characters for double-click word selection and are reached only from
`do_mouse()`, so they go with it.  `WaitForCharOrMouse()` has no mouse in it at
all -- the name is left over from the GUI -- so it is folded into
`WaitForChar()`, its only caller, rather than left telling a lie.

The eight options -- `'mouse'`, `'mousefocus'`, `'mousehide'`, `'mousemodel'`,
`'mousemoveevent'`, `'mouseshape'`, `'mousetime'` and `'ttymouse'` -- are
dropped by the phase AFTER the sweep, under `--strict`, which is what proves
nothing reads their globals any more.

THE KE_* AND KS_* ENUMERATORS STAY.  They are constants, they cost nothing, and
several enums in this file index a parallel table -- deleting an enumerator
renumbers every one after it, which is a different kind of change and does not
belong in a phase about capability.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cutil


def KE(name):
    return r'[ \t]*case   \(-\(\(KS_EXTRA\) \+ \(\(int\)\(%s\) << 8\)\)\)  :\n' % name


def cut(text, pattern, what, count=1, flags=re.M):
    text, n = re.subn(pattern, '', text, count=count, flags=flags)
    if n != count:
        sys.exit('nomouse: %s -- expected %d, matched %d' % (what, count, n))
    return text


INS_KEYS = ['KE_LEFTMOUSE', 'KE_LEFTMOUSE_NM', 'KE_LEFTDRAG', 'KE_LEFTRELEASE',
            'KE_LEFTRELEASE_NM', 'KE_MOUSEMOVE', 'KE_MIDDLEMOUSE',
            'KE_MIDDLEDRAG', 'KE_MIDDLERELEASE', 'KE_RIGHTMOUSE',
            'KE_RIGHTDRAG', 'KE_RIGHTRELEASE', 'KE_X1MOUSE', 'KE_X1DRAG',
            'KE_X1RELEASE', 'KE_X2MOUSE', 'KE_X2DRAG', 'KE_X2RELEASE']


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    text = path.read_text(errors='surrogateescape')

    # --- the tables ---------------------------------------------------------
    text, n = re.subn(r'^[ \t]*\{[^\n]*, nv_mouse(?:scroll)?, [^\n]*\} ,\n', '',
                      text, flags=re.M)
    if n != 22:
        sys.exit('nomouse: expected 22 nv_cmds mouse rows, matched %d' % n)
    print('  nomouse      %d rows of nv_cmds' % n)

    # The key-name table, so that <LeftMouse> and friends stop naming a key.
    names = ('LeftDrag|LeftMouse|LeftRelease|LeftReleaseNM|MiddleMouse|'
             'MouseMove|RightMouse|ScrollWheelDown|ScrollWheelLeft|'
             'ScrollWheelRight|ScrollWheelUp|X1Mouse|X2Mouse|Mouse')
    text, n = re.subn(
        r'^[ \t]*\{TRUE,[^\n]*\{\(char_u \*\)\("(?:%s)"\),[^\n]*\},\n' % names,
        '', text, flags=re.M)
    if n != 14:
        sys.exit('nomouse: expected 14 key-name rows, matched %d' % n)
    print('  nomouse      %d rows of the key-name table' % n)

    # --- the insert-mode dispatch -------------------------------------------
    text = cut(text,
               ''.join(KE(k) for k in INS_KEYS)
               + r'[ \t]*ins_mouse\(c\);\n[ \t]*break;\n\n?',
               "edit()'s mouse cases")
    text, n = re.subn(
        r'[ \t]*case   \(-\(\(KS_EXTRA\) \+ \(\(int\)\(KE_MOUSE(?:DOWN|UP|LEFT|RIGHT)\) << 8\)\)\)  :\n'
        r'[ \t]*ins_mousescroll\([^;]*\);\n[ \t]*break;\n\n?', '', text, flags=re.M)
    if n != 4:
        sys.exit('nomouse: expected 4 ins_mousescroll cases, matched %d' % n)
    print("  nomouse      edit()'s mouse and scroll cases")

    # --- the command-line dispatch ------------------------------------------
    text = cut(text, KE('KE_MIDDLEDRAG') + KE('KE_MIDDLERELEASE')
               + r'[ \t]*goto cmdline_not_changed;\n\n?',
               "getcmdline_int()'s middle drag and release")
    text = cut(text, KE('KE_MIDDLEMOUSE')
               + r'[ \t]*if \(!mouse_has\(MOUSE_COMMAND\)\)\n[ \t]*\{\n'
               r'[ \t]*goto cmdline_not_changed;\n[ \t]*\}\n'
               r'[ \t]*cmdline_paste\(0, TRUE, TRUE\);\n'
               r'[ \t]*redrawcmd\(\);\n[ \t]*goto cmdline_changed;\n\n?',
               "getcmdline_int()'s middle-click paste")
    text = cut(text,
               KE('KE_LEFTDRAG') + KE('KE_LEFTRELEASE')
               + KE('KE_RIGHTDRAG') + KE('KE_RIGHTRELEASE')
               + r'[ \t]*if \(ignore_drag_release\)\n[ \t]*\{\n'
               r'[ \t]*goto cmdline_not_changed;\n[ \t]*\}\n'
               r'[ \t]*__attribute__\(\(fallthrough\)\);\n'
               + KE('KE_LEFTMOUSE') + KE('KE_RIGHTMOUSE')
               + r'[ \t]*cmdline_left_right_mouse\(c, &ignore_drag_release\);\n'
               r'[ \t]*goto cmdline_not_changed;\n\n?',
               "getcmdline_int()'s click and drag")
    text = cut(text,
               KE('KE_MOUSEDOWN') + KE('KE_MOUSEUP') + KE('KE_MOUSELEFT')
               + KE('KE_MOUSERIGHT') + r'[ \t]*goto cmdline_not_changed;\n\n?',
               "getcmdline_int()'s scroll cases")
    text = cut(text,
               KE('KE_X1MOUSE') + KE('KE_X1DRAG') + KE('KE_X1RELEASE')
               + KE('KE_X2MOUSE') + KE('KE_X2DRAG') + KE('KE_X2RELEASE')
               + KE('KE_MOUSEMOVE') + r'[ \t]*goto cmdline_not_changed;\n\n?',
               "getcmdline_int()'s side-button cases")
    text = cut(text, r'^[ \t]*int[ \t]+ignore_drag_release = TRUE;\n',
               'ignore_drag_release')
    text = cut(text, r'^[ \t]*ignore_drag_release = TRUE;\n',
               "ignore_drag_release's other assignment")
    print("  nomouse      getcmdline_int()'s six mouse case runs")

    # --- the two normal-mode commands that take a click ---------------------
    text = cut(text,
               r'[ \t]*\(void\)do_mouse\(cap->oap, cap->nchar, \(cap->cmdchar == \'\]\'\) \? FORWARD :  \(-1\) , cap->count1, PUT_FIXINDENT\);\n',
               "nv_brackets()'s ]<LeftMouse>")
    text = cut(text,
               r'[ \t]*\(void\)do_mouse\(oap, cap->nchar,  \(-1\) , cap->count1, 0\);\n',
               "nv_g_cmd()'s g<LeftMouse>")
    print('  nomouse      ]<LeftMouse> and g<LeftMouse>')

    # --- wait_return's click-to-dismiss -------------------------------------
    text = cut(text, r'[ \t]*\(void\)jump_to_mouse\(MOUSE_SETPOS, NULL, 0\);\n',
               "wait_return()'s jump_to_mouse")
    text = cut(text,
               r' \|\| \(!mouse_has\(MOUSE_RETURN\) && mouse_row < msg_row && '
               r'\(c ==[^;]*KE_X2MOUSE\) << 8\)\)\)  \)\)',
               "wait_return()'s mouse_has term", flags=0)
    print('  nomouse      the click that dismissed a `Press ENTER` prompt')

    # --- the decoder --------------------------------------------------------
    text = cutil.drop_if(
        text,
        r'^[ \t]*if \(check_termcode_mouse\(tp, &slen, key_name, modifiers_start, idx, &modifiers\) == -1\)$',
        flags=re.M)
    # set_termname() decides which mouse protocol the terminal speaks -- reading
    # the 1006 capability, setting 'ttymouse' from it, and installing the
    # termcodes.  Forty lines, from `did_set_ttym` to the end of the block that
    # calls check_mouse_termcode().
    blanked = cutil.blank(text)
    k = text.index('    int did_set_ttym = FALSE;\n')
    o = blanked.index('{', text.index('char_u  *p = (char_u *)"";', k) - 40)
    c = cutil.match(text, o, blanked)
    end = text.index('\n', c) + 1
    if text[end:end + 1] == '\n':
        end += 1
    if 'check_mouse_termcode' not in text[k:end]:
        sys.exit("nomouse: set_termname()'s mouse block is not where this expects")
    print("  nomouse      set_termname()'s %d lines of protocol negotiation"
          % text.count('\n', k, end))
    text = text[:k] + text[end:]
    print('  nomouse      the escape sequences that carried a click')

    # --- telling the terminal to report -------------------------------------
    text, n = re.subn(r'^[ \t]*setmouse\(\);\n', '', text, flags=re.M)
    if n != 31:
        sys.exit('nomouse: expected 31 setmouse() calls, matched %d' % n)
    # Every mch_setmouse() call is a bare statement too.  The count is not
    # hardcoded: what is asserted is that afterwards only the definition and
    # its forward declaration are left, which the sweep then takes.
    text = re.sub(r'^[ \t]*mch_setmouse\((?:TRUE|FALSE)\);\n', '', text, flags=re.M)
    left = len(re.findall(r'\bmch_setmouse\b', text))
    if left != 2:
        sys.exit('nomouse: mch_setmouse has %d mentions left, expected the '
                 'definition and its declaration' % left)
    print('  nomouse      %d setmouse() calls, every one a bare statement' % 31)

    # --- mouse_has, which now always answers no -----------------------------
    text = cut(text, r'[ \t]*if \(tabcount > 1 && mouse_has_any\(\)\)\n[ \t]*\{\n'
               r'[ \t]*screen_putchar\(\'X\', 0, \(int\)Columns - 1, attr_nosel\);\n'
               r'[ \t]*TabPageIdxs\[Columns - 1\] = -999;\n[ \t]*\}\n',
               "draw_tabline()'s close button")
    print('  nomouse      the tabline stops drawing a button to click')

    # --- `:behave`, which sets four options and one of them is the mouse ----
    # The command is about selection, not the mouse, so it keeps working; it
    # just stops setting an option that no longer exists.  Reached BY NAME,
    # which is the lookup that returns -1 for a row that is not there and then
    # is not checked -- E685 and a segfault before the first keystroke.
    text, n = re.subn(
        r'^[ \t]*set_option_value_give_err\(\(char_u \*\)"mousemodel", 0L, '
        r'\(char_u \*\)"\w+", 0\);\n', '', text, count=2, flags=re.M)
    if n != 2:
        sys.exit("nomouse: ex_behave's two mousemodel lines -- matched %d" % n)
    print("  nomouse      :behave stops setting 'mousemodel'")

    # --- the two readers the option rows keep alive -------------------------
    # An option row is a ROOT for reachability, so `did_set_ttymouse` -- and
    # through it `check_mouse_termcode()` -- survives the sweep, and
    # `did_set_string_option()` still asks whether the option being set was
    # 'mouse'.  Both read p_mouse, so `--strict` refuses to drop the row; and
    # the row is what keeps them reachable.  The circle is broken here, by
    # hand, which is the honest place for it.
    text = cutil.drop_if(text, r'^[ \t]*if \(varp == &p_mouse\)$', flags=re.M)
    text = cut(text, r'^[ \t]*check_mouse_termcode\(\);\n',
               "did_set_ttymouse's call to check_mouse_termcode")
    text, ok = cutil.delete_definition(text, 'check_mouse_termcode')
    if not ok:
        sys.exit('nomouse: check_mouse_termcode is not defined at file scope')
    print("  nomouse      the two p_mouse readers an option row kept reachable")

    # The terminal reports which mouse protocol it speaks, and this sets
    # 'ttymouse' from the answer.  Reached by name, like :behave's.
    text = cutil.drop_if(
        text,
        r'^[ \t]*if \(!option_was_set\(\(char_u \*\)"ttym"\) && \(term_props\[TPR_MOUSE\]',
        flags=re.M)
    print("  nomouse      the terminal's mouse-protocol reply stops setting "
          "'ttymouse'")

    # didset_string_options() dereferences every string option's global once at
    # startup, which is the trap Phase 18 records: a row can be inert to every
    # other reader and still be read here.
    text = cut(text,
               r'^[ \t]*\(void\)opt_strings_flags\(p_ttym, p_ttym_values, '
               r'&ttym_flags, FALSE\);\n',
               "didset_string_options' p_ttym line")
    print("  nomouse      didset_string_options stops reading 'ttymouse'")

    # --- the option callbacks, which their own rows keep reachable ----------
    # An option row names its did_set_ and expand_set_ handlers, and a row is a
    # ROOT for reachability -- so the handlers survive the sweep, and
    # did_set_mousemodel() reads p_mousem, and --strict then refuses to drop
    # the row that is the only thing keeping the reader alive.  The circle is
    # broken by pointing the rows at NULL first; the rows go a moment later.
    for name in ('mouse', 'mousemodel', 'ttymouse'):
        text, n = re.subn(r'(\(char_u \*\)&p_\w+, PV_NONE, )did_set_%s, expand_set_%s,'
                          % (name, name), r'\1NULL, NULL,', text, count=1)
        if n != 1:
            sys.exit("nomouse: '%s' does not name its two handlers" % name)
    for name in ('did_set_mouse', 'expand_set_mouse', 'did_set_mousemodel',
                 'expand_set_mousemodel', 'did_set_ttymouse',
                 'expand_set_ttymouse'):
        text, ok = cutil.delete_definition(text, name)
        if not ok:
            sys.exit('nomouse: %s is not defined at file scope' % name)
    print('  nomouse      the six option handlers their own rows kept reachable')

    # --- a name that was never about the mouse ------------------------------
    # WaitForCharOrMouse() has no mouse in it: the name is left over from the
    # GUI build, where it also polled for motion events.  Checked rather than
    # assumed, and folded into WaitForChar(), its only caller, rather than left
    # telling a lie.
    blanked = cutil.blank(text)
    m = re.search(r'^WaitForCharOrMouse\([^\n]*\n', text, re.M)
    if not m:
        sys.exit('nomouse: WaitForCharOrMouse is not defined at file scope')
    o = blanked.index('{', m.end())
    c = cutil.match(text, o, blanked)
    inner = text[text.index('\n', o) + 1:text.rfind('\n', 0, c) + 1]
    if 'mouse' in inner.lower():
        sys.exit('nomouse: WaitForCharOrMouse does mention the mouse after all')
    text, ok = cutil.delete_definition(text, 'WaitForCharOrMouse')
    if not ok:
        sys.exit('nomouse: WaitForCharOrMouse would not delete')

    blanked = cutil.blank(text)
    m = re.search(r'^WaitForChar\([^\n]*\n', text, re.M)
    if not m:
        sys.exit('nomouse: WaitForChar is not defined at file scope')
    o = blanked.index('{', m.end())
    c = cutil.match(text, o, blanked)
    if 'WaitForCharOrMouse' not in text[o:c]:
        sys.exit('nomouse: WaitForChar does not forward to WaitForCharOrMouse')
    text = text[:o] + '{\n' + inner + '}' + text[c + 1:]
    print('  nomouse      WaitForCharOrMouse has no mouse in it; folded into '
          'its one caller')

    path.write_text(text, errors='surrogateescape')
    print('  nomouse      %d mouse mentions left for the sweep'
          % len(re.findall(r'(?i)mouse', text)))


if __name__ == '__main__':
    main()
