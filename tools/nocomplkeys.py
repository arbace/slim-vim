r"""The completion keys stop being keys.

Usage:
    python3 tools/nocomplkeys.py <file>

tools/nocompl.py stubbed the five predicates completion is *entered* through, so
completion produces nothing.  It deliberately stopped there, and said so: the
`docomplete:` label and its sixteen `goto`s were left alone because unpicking
them out of a 900-line switch was a larger change than that phase was making.

This is that change.  Afterwards the island is not merely inert, it is gone.

WHY IT COULD NOT BE SWEPT.  Seventy functions survived those stubs -- reachable, so
`funcreach.py` could not touch them, and never entered, because `ins_complete()`
returns FAIL before any of them runs.  `edit()` does not reach completion
through one door: it calls `ins_compl_addleader()`, `ins_compl_bs()`,
`ins_compl_accept_char()` and twenty-five more directly, and the redraw layer
asks `pum_visible()` on its own account.  A stub answers a question; it does not
remove the caller that asks it.

WHAT THIS CUTS, all of it inside `edit()`:

  * the CTRL-X submode.  `ins_ctrl_x()` set `ctrl_x_mode` and printed a submode
    message; it is now empty, so `ctrl_x_mode` never leaves CTRL_X_NORMAL and
    every `ctrl_x_mode_*()` test is decided.  The five keys that only meant
    something inside it -- CTRL-], CTRL-F, CTRL-S, and CTRL-L when it is not
    whole-line -- become ordinary characters.
  * the per-key completion arm: forty lines testing `ins_compl_active()` and
    then feeding the keystroke to the match list.
  * `'autocomplete'`, which armed a timer after every printable character.  Six
    sites, three of them the one-line blobs macro expansion left behind.
  * the four `if (pum_visible()) goto docomplete;` arms on the arrow and page
    keys, which is what made Up and Down move a menu selection.
  * the `docomplete:` label itself.

WHAT STAYS, and it is the same answer the stubs gave: CTRL-N and CTRL-P are still
insert-mode keys.  They now do nothing, which is what an unbound key does.

Nine more predicates become constants, for the callers outside insert mode that
ask on their own account -- the redraw layer, `do_put()`, `win_line()`.
`funcreach.py` then takes the interior.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cutil


def drop_unique(text, cond, what):
    """`cutil.drop_if`, but only when the condition occurs exactly once.

    The first version of this phase dropped
    `if (c != KE_CURSORHOLD && c != KE_COMPLETE_DELAY)` by pattern.  That
    condition appears three times inside edit(), and the one it took was
    `{ lastc = c; }` -- the last-character save, which has nothing to do with
    completion.  It compiled, it swept clean, and the island still shrank by
    2,400 lines, so nothing downstream objected.

    A cut that is not unique is not a cut, it is a guess.  Anything genuinely
    ambiguous is spelled out in full below or anchored with `drop_if_in`.
    """
    n = text.count(cond)
    if n != 1:
        sys.exit('nocomplkeys: %s -- the condition occurs %d times, not once' % (what, n))
    return cutil.drop_if(text, r'^[ \t]*' + re.escape(cond), flags=re.M)


def drop_if_in(text, func, pattern, what):
    """`cutil.drop_if`, restricted to one function.

    The pattern that names do_put's cleanup also matches four copies inside the
    completion code itself, and a bare search takes the first.  That edits the
    island instead of the caller keeping it alive -- and the island then does
    not die, because the reachable call is still there.
    """
    r = cutil.find_definition(text, func)
    if r is None:
        sys.exit('nocomplkeys: %s is not defined' % func)
    a, z = r
    inner = cutil.drop_if(text[a:z], pattern, flags=re.M)
    if inner == text[a:z]:
        sys.exit('nocomplkeys: %s -- nothing dropped in %s' % (what, func))
    return text[:a] + inner + text[z:]


def stub(text, name, ret):
    r"""Replace a definition's body with a constant answer.

    TWO SHAPES, and only looking for one of them cost this phase a pass.  Most
    definitions here put the return type on its own line and the name at column
    zero, so `^name\(` finds them.  The `ctrl_x_mode_*()` predicates are
    one-liners -- `static int ctrl_x_mode_scroll(void)` with the body on the
    next line -- and the anchored search does not see them at all.  The tool
    exited, tier 2 failed, and the agent ran for three minutes to produce a
    2,876-line residue patch of what a working program does for free.

    So find the name, and let the C decide: a definition is the occurrence whose
    matching `)` is followed by `{`.  A prototype ends in `;` and is skipped.
    """
    blanked = cutil.blank(text)
    pos = 0
    while True:
        m = re.search(r'\b%s\s*\(' % re.escape(name), blanked[pos:])
        if not m:
            sys.exit('nocomplkeys: %s is not defined' % name)
        lp = pos + m.end() - 1
        rp = cutil.match(text, lp, blanked)
        rest = blanked[rp + 1:rp + 40].lstrip()
        pos = rp + 1
        if rest.startswith('{'):
            o = blanked.index('{', rp)
            c = cutil.match(text, o, blanked)
            return text[:o] + '{\n' + (ret + '\n' if ret else '') + '}' + text[c + 1:]


def sub(text, old, new, what, count=1):
    n = text.count(old)
    if n != count:
        sys.exit('nocomplkeys: %s -- expected %d, found %d' % (what, count, n))
    return text.replace(old, new, count)


# Predicates the rest of the editor asks on its own account.  Each already had
# only one honest answer; saying it in the body is what lets the sweep reach
# everything behind it.
STUBS = (
    ('ins_compl_win_active', '    return FALSE;'),
    ('ins_compl_lnum_in_range', '    return FALSE;'),
    ('ins_compl_col_range_attr', '    return -1;'),
    ('ins_compl_preinsert_effect', '    return FALSE;'),
    ('ins_compl_autocomplete_pending', '    return FALSE;'),
    ('ins_compl_autocomplete_elapsed', '    return 0;'),
    ('pum_under_menu', '    return FALSE;'),
    ('pum_get_height', '    return 0;'),
    ('vim_is_ctrl_x_key', '    return FALSE;'),
    # With ins_ctrl_x() empty, `ctrl_x_mode` is never assigned and stays
    # CTRL_X_NORMAL, so these two are decided.  ins_ctrl_ey() then takes its
    # else branch, which is CTRL-Y and CTRL-E's ordinary meaning: copy the
    # character above or below.
    ('ctrl_x_mode_scroll', '    return FALSE;'),
    ('at_ins_compl_key', '    return FALSE;'),
)


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    text = path.read_text(errors='surrogateescape')

    # ---- 1. CTRL-X no longer opens a submode ------------------------------
    text = stub(text, 'ins_ctrl_x', '')
    print('  complkeys    CTRL-X opens no submode; ctrl_x_mode stays normal')

    # ---- 2. edit() ---------------------------------------------------------
    text = sub(text,
        '    if (textlock != 0 || ins_compl_active() || compl_busy || pum_visible())',
        '    if (textlock != 0)',
        "edit()'s entry guard")
    text = sub(text, '    ins_compl_clear();\n', '', "edit()'s ins_compl_clear")
    text = sub(text,
        '        if (stop_insert_mode && !ins_compl_active())',
        '        if (stop_insert_mode)',
        'the stop_insert_mode guard')

    # 'autocomplete' arming, in its six shapes.
    text = drop_unique(text, 'if (ins_compl_has_autocomplete() && !char_avail() && curwin->w_cursor.col > 0)', 'the ins_just_started autocomplete arm')
    text = sub(text, '                    ins_compl_prep(ESC);\n', '',
               'the ESC hook')
    disarm = """        if (c !=   (-((KS_EXTRA) + ((int)(KE_CURSORHOLD) << 8)))   && c !=   (-((KS_EXTRA) + ((int)(KE_COMPLETE_DELAY) << 8)))  )
        {
            ins_compl_clear_autocomplete_delay();
            ins_compl_disarm_autostart();
            if (!ins_compl_active())
            {
                ins_compl_disable_autocomplete();
            }
        }

"""
    text = sub(text, disarm, '', 'the per-key autocomplete disarm')
    text = drop_unique(text, 'if (ins_compl_active() && curwin->w_cursor.col >= ins_compl_col() && ins_compl_has_shown_match() && pum_wanted())', 'a completion arm')
    text = sub(text, '        ins_compl_init_get_longest();\n', '',
               "edit()'s init_get_longest")
    text = drop_unique(text, 'if (ins_compl_prep(c))', 'the per-key prep hook')
    text = drop_unique(text, 'if ((c == Ctrl_V || c == Ctrl_Q) && ctrl_x_mode_cmdline())', 'CTRL-V in cmdline completion')
    text = sub(text, 'doESCkey:\n            ins_compl_clear_autocomplete_delay();\n',
               'doESCkey:\n', 'the doESCkey disarm')
    text = drop_unique(text, 'if (ctrl_x_mode_register() && !ins_compl_active())', 'a completion arm')

    # The three one-line blobs macro expansion left behind, each inside an
    # `if (did_backspace)` that is then empty.
    blob = re.compile(
        r'[ \t]*if \(did_backspace\)\n[ \t]*\{\n'
        r'[ \t]*if \(ins_compl_has_autocomplete\(\)[^\n]*\n[ \t]*\{[^\n]*\n'
        r'[ \t]*\}\n', re.M)
    text, n = blob.subn('', text)
    if n != 3:
        sys.exit('nocomplkeys: the backspace autocomplete blobs -- expected 3, matched %d' % n)
    print('  complkeys    autocomplete disarmed at %d sites' % (n + 3))

    # The KE_COMPLETE_DELAY key exists only to fire the timer.
    old = """            ins_compl_clear_autocomplete_delay();
            if (!ins_compl_has_autocomplete() || char_avail() || curwin->w_cursor.col == 0)
            {
                break;
            }
            c = char_before_cursor();
            if (!vim_isprintc(c))
            {
                break;
            }
            ins_compl_enable_autocomplete();
            ins_compl_arm_autostart();
            goto docomplete;
"""
    text = sub(text, old, '            break;\n', 'the KE_COMPLETE_DELAY arm')

    # Up, Down, PageUp, PageDown moved a menu selection.
    text, n = re.subn(r'[ \t]*if \(pum_visible\(\)\)\n[ \t]*\{\n[ \t]*goto docomplete;\n[ \t]*\}\n\n?',
                      '', text)
    if n != 4:
        sys.exit('nocomplkeys: the arrow-key pum arms -- expected 4, matched %d' % n)
    print('  complkeys    Up, Down, PageUp and PageDown no longer move a selection')

    # Keys that only meant something inside CTRL-X mode.
    for key, mode in (('Ctrl_RSB', 'ctrl_x_mode_tags'),
                      ('Ctrl_F', 'ctrl_x_mode_files'),
                      ('Ctrl_S', 'ctrl_x_mode_spell')):
        old = """            if (!%s())
            {
                goto normalchar;
            }
            goto docomplete;
""" % mode
        text = sub(text, old, '            goto normalchar;\n', 'the %s arm' % key)

    old = """            if (!ctrl_x_mode_whole_line())
            {
                if (p_im)
                {
                    if (echeck_abbr(Ctrl_L + ABBR_OFF))
                    {
                        break;
                    }
                    goto doESCkey;
                }
                goto normalchar;
            }

        __attribute__((fallthrough));
        case Ctrl_P:
        case Ctrl_N:
docomplete:
            ins_compl_clear_autocomplete_delay();
            compl_busy = TRUE;
            if (ins_complete(c, TRUE) == FAIL)
            {
                compl_status_clear();
            }
            compl_busy = FALSE;
            can_si = may_do_si();
            break;
"""
    new = """            if (p_im)
            {
                if (echeck_abbr(Ctrl_L + ABBR_OFF))
                {
                    break;
                }
                goto doESCkey;
            }
            goto normalchar;

        case Ctrl_P:
        case Ctrl_N:
            break;
"""
    text = sub(text, old, new, 'the docomplete label')
    print('  complkeys    docomplete is gone; CTRL-N and CTRL-P do nothing')

    # The last arming site, and the cancel at the bottom of the loop.
    text = drop_unique(text, 'if (ins_compl_has_autocomplete() && !char_avail() && vim_isprintc(c))', 'the printable-character autocomplete arm')
    text = drop_unique(text, 'if (ins_compl_active() && !ins_compl_win_active(curwin))', 'the end-of-loop cancel')

    # ---- 3. do_put ---------------------------------------------------------
    text = drop_if_in(text, 'do_put', r'^[ \t]*' + re.escape('if (ins_compl_preinsert_effect())'),
                      "do_put's preinsert cleanup")

    # ---- 4. the predicates everyone else asks -----------------------------
    for name, ret in STUBS:
        text = stub(text, name, ret)
    print('  complkeys    %d predicates answer without the machinery' % len(STUBS))

    path.write_text(text, errors='surrogateescape')


main()
