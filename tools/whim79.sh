#!/bin/sh
# Whim phase 79 -- the constant-return predicates.  See WHIM-GOAL.md.
#
# Usage: tools/whim79.sh <work-dir>      (run from the repository root)
#
# Twenty-eight functions whose whole body is `return <constant>;`.  Each was emptied
# by an earlier phase and left with its callers in place, so the editor still asks
# "is the popup menu visible", "are we in a Vim9 script", "is there more than one
# window" -- and still branches on an answer that cannot change.  The compiler cannot
# help: at -O0 each is a real call and a real branch, and every sweep this pipeline
# runs reports the code as live because it is reachable.  Unuseful, not unused.
#
# THE INVARIANT, AND IT IS ASSERTED RATHER THAN TRUSTED.  Step 1 reads every one of
# the 28 definitions and requires the body to be exactly `return <expected>;`, with
# the expected token written out here.  If an upstream ever gives one a real body,
# the phase fails instead of folding a live predicate.  That is the phase 77 pattern
# ("all EX_BUFNAME commands are ex_ni") and it is the only thing standing between a
# fold and a wrong answer.
#
# FOUR SIMILAR-LOOKING FUNCTIONS ARE NOT TOUCHED, and the distinction is the whole
# reason this phase was surveyed twice.  A scan for `return <single token>;` reports
# 32, but four of those tokens are VARIABLES, not constants:
#
#     get_hislen           -> hislen
#     is_maphash_valid     -> maphash_valid
#     get_search_pat       -> mr_pattern
#     get_text_locked_msg  -> e_not_allowed_to_change_text_or_change_window
#
# My first classifier said thirteen of the 32 returned a variable; it had matched the
# bare tokens 0, 1 and NULL against unrelated declarations elsewhere in the file.
# Reading the DEFINITIONS gives four.  Supplying the expected constant per name, as
# step 1 does, is what makes that mistake impossible to repeat silently.
#
# did_set_number_relativenumber IS A CONSTANT AND IS STILL NOT TOUCHED.  Its only two
# mentions are option-table rows, where it appears as a FUNCTION POINTER with no call
# parentheses.  Folding is meaningless and deleting it would leave two rows pointing
# at nothing.  It stays, and an assertion at the end requires both rows intact.
#
# `binds_out` IS A VETO FOR fold_always, NOT FOR fold_never.  The block at
# parse_command_modifiers' `if (vim9script)` contains a `break` that binds to the
# enclosing `for (;;)`, which is exactly the shape that made buflist_findpat change
# behaviour silently in phase 71 -- but that phase FOLDED A WALK, keeping the body
# while removing the loop around it, so the break rebound.  fold_never DELETES the
# body, break and all, and the condition was false, so the break never fired.  Every
# fold_always site in this phase was audited and none contains an escaping break.
#
# THE SECOND-ORDER CUTS, both proved in the phase rather than assumed:
#
#   skip_for_popup  is not a constant stub on entry -- it has three returns.  Once
#       pum_under_menu and pum_visible fold, both of its guards go and it becomes
#       `return FALSE;`.  Step 5 asserts that with the same const_of() check before
#       step 6 uses it, so the collapse is proved, not hoped for.  Nine more sites.
#
#   may_have_range  is a local of do_one_cmd with two writes.  One is inside the
#       `if (vim9script && ...)` block this phase folds away; the other is that
#       block's else arm, `may_have_range = TRUE;`.  So after the fold it has one
#       write and is constantly true, and its two readers fold too.
#
#   wc  in option_value2string is `long wc = 0;` whose only "write" is `&wc` passed
#       to wc_use_keyname -- which never dereferences wcp.  So BOTH arms of that
#       if/else-if chain are dead, not just the first, and it collapses to the
#       sprintf.  Checked by reading wc_use_keyname's body, not by assuming.
#
#   need_check_timestamps, need_redraw, bom_count  each become write-only once the
#       stub feeding them is gone, so their tests fold and the variables sweep.
#
# ORDERING IS THE MAIN HAZARD AND THE STEPS ARE NUMBERED FOR IT.  Specific literals
# run before blanket regexes, EXCEPT where a blanket edit creates the specific one's
# target.  Three places depend on it: the may_have_range cascade (step 3) only exists
# after step 2a folds the block holding its other write; skip_for_popup's nine sites
# (step 6) only collapse after step 5 empties it; and the two-line ternary at
# do_one_cmd (step 10a) must be replaced BEFORE the blanket current_win_nr pass, or
# that pass eats one of its two halves and leaves a syntax error.  Every anchor in
# this file was counted against the q78 tree before it was written.
#
# NO TERM EDIT ENDS IN WHITESPACE.  `only_one_window() && check_changed_any` becomes
# `check_changed_any` rather than stripping `only_one_window() && `, because a
# literal with a trailing space lost it passing through an editor in phase 71 and the
# match then failed for reasons invisible in the diff.
#
# THE DELTA: none expected.  Every fold removes a branch whose condition cannot hold,
# and every term edit removes a conjunct that is constantly true or a disjunct that
# is constantly false.  The quit path is the one place where getting this wrong is
# silent rather than fatal -- check_more() feeds the four ex_quit/ex_exit conditions
# that decide whether getout(0) runs -- so five quit probes, calibrated on q78, guard
# it directly.  Declared empty, left for whimdelta.sh to correct.
set -eu

work=${1:?usage: whim79.sh <work-dir>}
f="$work/whim-vim.c"

before_lines=$(grep -c '' "$f")
tools/symbols.sh "$f" .cache/symbols/before

python3 - "$f" <<'PY'
TAG = 'noconstfn'
import re, sys
sys.path.insert(0, 'tools')
import cutil
path = sys.argv[1]
t = open(path, errors='surrogateescape').read()

def die(msg):
    sys.exit('  %-12s %s' % (TAG, msg))

def say(what):
    print('  %-12s %s' % (TAG, what))

def body_of(text, name):
    sp = cutil.find_definition(text, name)
    if not sp:
        die('%s is not defined' % name)
    s = text[sp[0]:sp[1]]
    return s[s.index('{\n') + 2:s.rindex('}')]

def const_of(text, name, expect):
    """Require `name`'s whole body to be `return <expect>;` -- nothing else."""
    inner = body_of(text, name).strip()
    m = re.fullmatch(r'return\s+(.+);', inner)
    if not m:
        die('%s is no longer a one-line stub: %r' % (name, inner[:70]))
    if m.group(1).strip() != expect:
        die('%s returns %r, not %r -- folding it would change behaviour'
            % (name, m.group(1).strip(), expect))

def fold_never(text, pattern, what, n=1):
    try:
        out = cutil.fold_never(text, pattern, n, re.M)
    except ValueError as e:
        die('%s -- %s' % (what, e))
    say(what)
    return out

def fold_always(text, pattern, what, n=1):
    try:
        out = cutil.fold_always(text, pattern, n, re.M)
    except ValueError as e:
        die('%s -- %s' % (what, e))
    say(what)
    return out

def drop_if(text, pattern, what, n=1):
    try:
        out = cutil.drop_if(text, pattern, n, re.M)
    except ValueError as e:
        die('%s -- %s' % (what, e))
    say(what)
    return out

def term(text, frag, repl, what, n=1):
    """A literal fragment of a condition, replaced.  Counted, never 'the first one'."""
    k = text.count(frag)
    if k != n:
        die('%s -- the fragment occurs %d times, expected %d' % (what, k, n))
    say(what)
    return text.replace(frag, repl)

def lines(text, pattern, what, n=1):
    rx = re.compile(r'^[ \t]*' + pattern + r'[ \t]*\n', re.M)
    k = len(rx.findall(text))
    if k != n:
        die('%s -- %d lines match, expected %d' % (what, k, n))
    say(what)
    return rx.sub('', text)

# ---- 1: the invariant --------------------------------------------------------------
# The expected constant is written out per name.  A stub that acquires a real body,
# or returns something else, fails here rather than being folded.
CONSTANTS = {
    'in_vim9script': 'FALSE',        'tabline_height': '0',
    'pum_visible': 'FALSE',          'current_win_nr': '1',
    'current_tab_nr': '1',           'check_more': 'OK',
    'only_one_window': 'TRUE',       'check_timestamps': '0',
    'stl_connected': 'FALSE',        'pum_under_menu': 'FALSE',
    'ins_compl_win_active': 'FALSE', 'ins_compl_lnum_in_range': 'FALSE',
    'ins_compl_active': 'FALSE',     'has_cursormoved': 'FALSE',
    'wc_use_keyname': 'FALSE',       'script_get': 'NULL',
    'pum_redraw_in_same_position': 'FALSE',
    'has_textchanged': 'FALSE',      'has_insertcharpre': 'FALSE',
    'get_cellwidth': '0',            'check_can_set_curbuf_forceit': 'TRUE',
    'check_can_set_curbuf_disabled': 'TRUE',
    'bt_terminal': 'FALSE',          'bt_quickfix': 'FALSE',
    'bomb_size': '0',                'at_ins_compl_key': 'FALSE',
    'append_arg_number': '0',        'did_set_number_relativenumber': 'NULL',
}
for name, val in sorted(CONSTANTS.items()):
    const_of(t, name, val)
say('confirmed: %d functions whose whole body is `return <constant>;`' % len(CONSTANTS))

# The four that are NOT constants must still be variable-returning.  If one ever
# becomes a constant it belongs in the list above -- and if one is silently already
# there, this phase was surveyed wrong.
VARIABLE = {'get_hislen': 'hislen', 'is_maphash_valid': 'maphash_valid',
            'get_search_pat': 'mr_pattern',
            'get_text_locked_msg': 'e_not_allowed_to_change_text_or_change_window'}
for name, val in sorted(VARIABLE.items()):
    const_of(t, name, val)
say('confirmed: %d more return a VARIABLE and are left alone' % len(VARIABLE))

# wc_use_keyname must not write through its out-parameter, or folding its `if` would
# leave `wc` unset.  Its body is `return FALSE;`, checked above -- state the reason.
if 'wcp' in body_of(t, 'wc_use_keyname'):
    die('wc_use_keyname now mentions wcp -- it may write through the out-parameter')
say('confirmed: wc_use_keyname never dereferences its out-parameter')

# ---- 2: the Vim9 script layer ------------------------------------------------------
# The three locals `int vim9script = in_vim9script();` and their six readers.  A
# whole-file grep finds exactly nine mentions of the identifier: three declarations
# and these six.  2a must run first -- it is what makes may_have_range constant.
t = fold_never(t, r'^[ \t]*if \(vim9script && \(flags & DOCMD_RANGEOK\) == 0\)$',
               'scanning backwards for a colon to decide whether a range is allowed')
t = fold_never(t, r'^[ \t]*if \(vim9script && !may_have_range\)$',
               'the Vim9 path through find_ex_command')
t = fold_never(t, r'^[ \t]*if \(vim9script\)$',
               'two Vim9 checks in parse_command_modifiers', 2)
t = fold_never(t, r'^[ \t]*if \(vim9script && has_cmdmod\(cmod, FALSE\)\)$',
               'a command modifier without a command')
t = term(t, "(*p == '\"' && !vim9script && !(eap->argt & EX_NOTRLCOM)",
            "(*p == '\"' && !(eap->argt & EX_NOTRLCOM)",
            'a double quote always starts a comment outside Vim9 script')
t = term(t, "(*p == '#' && vim9script && !(eap->argt & EX_NOTRLCOM) && p > eap->cmd "
            "&&  ((p[-1]) == ' ' || (p[-1]) == '\\t') ) || (*p == '|' "
            "&& eap->cmdidx != CMD_append",
            "(*p == '|' && eap->cmdidx != CMD_append",
            'and a hash never does')
for indent in ('', '    ', '        '):
    t = lines(t, r'int %svim9script = in_vim9script\(\);' % indent,
              'the local that recorded it')

# ---- 3: may_have_range, which step 2a made constant --------------------------------
# Its other write lived inside the block 2a folded; what survives is that block's
# else arm, `may_have_range = TRUE;`.  One write, constantly true.
t = fold_always(t, r'^[ \t]*if \(may_have_range\)$', 'skipping a range that is always allowed')
t = fold_never(t, r'^[ \t]*if \(!may_have_range\)$', 'the default address for a range that cannot be absent')
t = lines(t, r'may_have_range = TRUE;', 'the flag nothing decides any more')
t = lines(t, r'int         may_have_range;', 'and its declaration')

# ---- 4: the remaining in_vim9script sites ------------------------------------------
t = fold_never(t, r"^[ \t]*if \(in_vim9script\(\) && \*p == '\\'' &&  \(\(unsigned\)\(p\[1\]\) - '0' < 10\) \)$",
               "a digit separator in a Vim9 number literal")
t = fold_never(t, r"^[ \t]*if \(in_vim9script\(\) && \*p == '#'\)$",
               'a hash comment ending a Vim9 command')
t = fold_never(t, r'^[ \t]*if \(in_vim9script\(\) && arg > arg_start && vim_strchr\(\(char_u \*\)"!&<", \*arg\) != NULL\)$',
               'the Vim9 spacing rule for an unknown option')
t = fold_never(t, r'^[ \t]*if \(in_vim9script\(\)\)$',
               'eight more Vim9 script branches', 8)
t = term(t, 'in_vim9script() ? GETLINE_CONCAT_CONTBAR : GETLINE_CONCAT_CONT',
            'GETLINE_CONCAT_CONT',
            'how a continuation line is joined')

# ---- 5: the popup menu, which never appears ----------------------------------------
t = fold_never(t, r'^[ \t]*if \(pum_under_menu\(row, col, TRUE\)\)$',
               'skipping a cell the popup menu covers')
t = fold_never(t, r'^[ \t]*if \(pum_visible\(\) && \(State & MODE_CMDLINE\) == 0 && pum_under_menu\(row, col, FALSE\)\)$',
               'and the same test on the command line')
# PROVE the collapse rather than assume it: skip_for_popup is only now a stub.
const_of(t, 'skip_for_popup', 'FALSE')
say('confirmed: skip_for_popup has collapsed to `return FALSE;`')

t = term(t, 'may_trigger_safestate(ready && !ins_compl_active() && !pum_visible());',
            'may_trigger_safestate(ready);',
            'whether a state is safe no longer asks about completion')
t = fold_never(t, r'^[ \t]*if \(pum_visible\(\)\)$', 'two redraws deferred for the popup menu', 2)
t = fold_never(t, r'^[ \t]*if \(!ignore_pum && pum_visible\(\)\)$', 'the ruler deferred for it')
t = fold_never(t, r'^[ \t]*if \(pum_redraw_in_same_position\(\)\)$', 'redrawing it in place')
t = term(t, ' || (!ignore_pum && pum_visible())', '',
            'the status line deferred for it')
t = term(t, ' && !pum_visible())', ')',
            "'relativenumber' redrawing around it")
t = term(t, ' && !ins_compl_active())', ')',
            "'showmatch' suppressed during completion")
t = fold_never(t, r'^[ \t]*if \(\(State & MODE_INSERT\) && ins_compl_win_active\(wp\) && \(in_curline \|\| ins_compl_lnum_in_range\(lnum\)\)\)$',
               'two completion highlights in the line drawer', 2)
t = term(t, ' && !at_ins_compl_key())', ')',
            'a mapping suppressed by a completion key')

# ---- 6: skip_for_popup's nine sites, unlocked by step 5 ----------------------------
t = fold_never(t, r'^[ \t]*if \(redraw_this && char_cells == 2 && skip_for_popup\(row, col \+ coloff \+ 1\)\)$',
               'a double-width cell under the menu')
t = fold_never(t, r'^[ \t]*if \(redraw_this && skip_for_popup\(row, col \+ coloff\)\)$',
               'and a single-width one')
t = term(t, ' && !skip_for_popup(row, col + coloff))', ')',
            'clearing the next cell')
t = fold_always(t, r'^[ \t]*if \(!skip_for_popup\(row, col \+ coloff\)\)$',
                'drawing a screen line cell')
t = fold_always(t, r'^[ \t]*if \(!skip_for_popup\(row, col - 1\)\)$',
                'redrawing the cell to the left')
t = term(t, ' && !skip_for_popup(row, col))', ')',
            'three more cells that are never covered', 3)
t = fold_always(t, r'^[ \t]*if \(!skip_for_popup\(r, c\)\)$',
                'and filling a screen region')

# ---- 7: quitting ------------------------------------------------------------------
# THE MOST BEHAVIOUR-SENSITIVE EDIT IN THE PHASE.  check_more() returns OK, so
# `check_more(...) == OK` is true and `check_more(TRUE, ...) == FAIL` is false.  What
# is left deciding whether getout(0) runs is check_changed() and check_changed_any(),
# which is what the five quit probes below exercise.  Getting this wrong does not
# fail to compile: it makes the editor refuse to quit, or quit without saving.
t = fold_always(t, r'^[ \t]*if \(quit_all \|\| \(check_more\(FALSE, forceit\) == OK\)\)$',
                'the autocommand check before quitting')
t = fold_always(t, r'^[ \t]*if \(check_more\(FALSE, eap->forceit\) == OK && only_one_window\(\)\)$',
                'deciding to exit in :quit and :exit', 2)
t = term(t, ' || check_more(TRUE, eap->forceit) == FAIL', '',
            'refusing to quit with more files to edit', 2)
t = term(t, 'only_one_window() && check_changed_any', 'check_changed_any',
            'and asking whether this is the last window', 2)

# ---- 8: the scattered remainder ----------------------------------------------------
t = fold_never(t, r'^[ \t]*if \(stl_connected\(wp\)\)$',
               'a status line joined to the one beside it', 2)
t = fold_never(t, r'^[ \t]*if \(get_cellwidth\(ScreenLinesUC\[off\]\) > 1\)$',
               "a character widened by 'setcellwidths'")
# wc is `long wc = 0;` and wc_use_keyname never writes through wcp, so BOTH arms of
# this chain are dead.  The first fold turns the `else if` into an `if`.
t = fold_never(t, r'^[ \t]*if \(wc_use_keyname\(varp, &wc\)\)$',
               'showing a numeric option as a key name')
t = fold_never(t, r'^[ \t]*if \(wc != 0\)$',
               'and showing it as a character')
t = fold_never(t, r'^[ \t]*if \(!check_can_set_curbuf_disabled\(\)\)$',
               'refusing to change buffer in gf')
t = fold_never(t, r'^[ \t]*if \(\(is_other_file\(0, ffname\) && !check_can_set_curbuf_forceit\(eap->forceit\)\)\)$',
               'and refusing in :edit')
t = term(t, ' && !bt_terminal(wp->w_buffer)', '',
            'the [+] flag suppressed for a terminal buffer')
t = term(t, ' && !bt_quickfix(curbuf)', '',
            'a quickfix buffer never being reusable')
t = term(t, ' && !has_insertcharpre()', '',
            'the InsertCharPre fast path')
t = fold_never(t, r'^[ \t]*if \(!finish_op && \(has_cursormoved\(\)\) && ! ',
               'tracking the cursor for CursorMoved')
t = fold_never(t, r'^[ \t]*if \(!finish_op && has_textchanged\(\) && ',
               'and the change tick for TextChanged')

# ---- 9: the calls made only for a result nobody uses -------------------------------
t = drop_if(t, r'^[ \t]*if \(need_check_timestamps\)$',
            'three checks for a file changed outside the editor', 3)
t = lines(t, r'need_check_timestamps = TRUE;', 'asking for one')
t = lines(t, r'static int      need_check_timestamps  = FALSE ;', 'and the flag itself')
t = lines(t, r'need_redraw = check_timestamps\(FALSE\);', 'the timestamp check on focus')
t = fold_never(t, r'^[ \t]*if \(need_redraw\)$', 'and the redraw it asked for')
t = lines(t, r'\(void\)append_arg_number\(curwin, \(char_u \*\)buffer \+ bufferlen,  \(1024\+1\)  - bufferlen, !shortmess\(SHM_FILE\)\);',
          'appending the argument-list position to the file message')
t = term(t, '''    if (!eap->skip)
    {
        ex_ni(eap);
    }
    else
    {
        vim_free(script_get(eap, eap->arg));
    }
''', '''    if (!eap->skip)
    {
        ex_ni(eap);
    }
''', 'reading a here-document for a command that cannot run')
t = lines(t, r'bom_count = bomb_size\(\);', 'counting the byte order mark')
t = fold_never(t, r'^[ \t]*if \(dict == NULL && bom_count > 0\)$', 'and reporting it')

# ---- 10: the arithmetic ------------------------------------------------------------
# 10a IS SPECIFIC AND MUST PRECEDE 10b.  The ternary spans a line break -- the one
# construct in this tree that may -- so the blanket pass below would rewrite half of
# it and leave `eap->line2 = eap->addr_type == ADDR_WINDOWS` dangling.
t = term(t, '''                            eap->line2 = eap->addr_type == ADDR_WINDOWS
                                                  ?  current_win_nr(NULL)  :  current_tab_nr(NULL) ;
''', '''                            eap->line2 = 1;
''', 'the window-or-tab count for a bare range')
for fn, arg, n in (('current_win_nr', 'curwin', 3), ('current_win_nr', 'NULL', 3),
                   ('current_tab_nr', 'curtab', 3), ('current_tab_nr', 'NULL', 3)):
    t = term(t, '%s(%s)' % (fn, arg), '1',
             'there is one window and one tabpage (%s(%s))' % (fn, arg), n)

# 10c is specific for the same reason: this return spans a line break.
t = term(t, '''    return frame_minheight(curtab->tp_topframe, NULL) + tabline_height()
        + MIN_CMDHEIGHT;
''', '''    return frame_minheight(curtab->tp_topframe, NULL) + MIN_CMDHEIGHT;
''', 'the minimum rows needed, without a tab line')
t = lines(t, r'total \+= tabline_height\(\);', 'the tab line in the all-tabpages minimum')
t = term(t, 'int         row = tabline_height();', 'int         row = 0;',
            'window layout starting at the top row')
t = term(t, '(Rows - p_ch - tabline_height())', '(Rows - p_ch)',
            'five window heights with no tab line to subtract', 5)
t = term(t, 'tabline_height() + topframe->fr_height', 'topframe->fr_height',
            "and the 'cmdheight' consistency check")

open(path, 'w', errors='surrogateescape').write(t)
PY

python3 tools/create_cmdidxs.py "$f" --check >/dev/null

tools/sweep.sh "$f"

# Every constant-return predicate, and the second-order stub, must be gone.
for g in in_vim9script tabline_height pum_visible current_win_nr current_tab_nr \
         check_more only_one_window check_timestamps stl_connected pum_under_menu \
         ins_compl_win_active ins_compl_lnum_in_range ins_compl_active \
         has_cursormoved wc_use_keyname script_get pum_redraw_in_same_position \
         has_textchanged has_insertcharpre get_cellwidth \
         check_can_set_curbuf_forceit check_can_set_curbuf_disabled \
         bt_terminal bt_quickfix bomb_size at_ins_compl_key append_arg_number \
         skip_for_popup may_have_range need_check_timestamps; do
    n=$(grep -cE -- "\\b$g\\b" "$f" || true)
    [ "$n" = 0 ] || { echo "  noconstfn    $g still has $n mentions"; exit 1; }
done

# vim9script IS DELIBERATELY NOT IN THAT LOOP.  Four mentions survive and none is the
# identifier: three former-file banner comments (vim9script.pro twice, vim9script.c)
# and the [CMD_vim9script] row, where it is the command NAME -- a string literal.  A
# bare word count cannot tell an identifier from a comment or a string, and asserting
# zero here fails on a phase that did exactly the right thing.  Phase 78 made this
# mistake twice in one script, both times an assertion contradicting a correct edit.
if grep -E '\bvim9script\b' "$f" | grep -qvE '^(// |    \[CMD_vim9script\] = )'; then
    echo "  noconstfn    the vim9script identifier survives outside the banners and the command row"
    grep -nE '\bvim9script\b' "$f" | grep -vE ':(// |    \[CMD_vim9script\] = )'
    exit 1
fi

# The four that return a VARIABLE must all survive untouched.  This is the assertion
# that would have caught the classifier error described in the header.
for g in get_hislen is_maphash_valid get_search_pat get_text_locked_msg; do
    grep -qE "\\b$g\\b" "$f" || { echo "  noconstfn    $g went -- it returns a variable and must stay"; exit 1; }
done

# did_set_number_relativenumber is a constant AND stays: it is a function pointer in
# two option-table rows, where folding means nothing and deleting breaks the rows.
n=$(grep -cE '^[ \t]*did_set_number_relativenumber, NULL,$' "$f" || true)
[ "$n" = 2 ] || { echo "  noconstfn    the two did_set_number_relativenumber option rows are $n, expected 2"; exit 1; }
grep -qE '\bdid_set_number_relativenumber\(optset_T' "$f" || { echo "  noconstfn    did_set_number_relativenumber lost its definition"; exit 1; }

# The quit path must still have the guards that actually refuse.
for g in getout ex_quit ex_exit check_changed check_changed_any before_quit_autocmds \
         not_exiting do_write curbufIsChanged; do
    grep -qE "\\b$g\\b" "$f" || { echo "  noconstfn    $g went -- :q and :wq still need it"; exit 1; }
done
# and both branches of the exit decision must survive in each of the two commands
for fn in ex_quit ex_exit; do
    n=$(awk "/^$fn\\(exarg_T/,/^\\}\$/" "$f" | grep -cE 'getout\(0\);' || true)
    [ "$n" = 1 ] || { echo "  noconstfn    $fn has $n getout(0) calls, expected 1"; exit 1; }
    n=$(awk "/^$fn\\(exarg_T/,/^\\}\$/" "$f" | grep -cE 'not_exiting\(save_exiting\);' || true)
    [ "$n" = 2 ] || { echo "  noconstfn    $fn has $n not_exiting calls, expected 2"; exit 1; }
done
echo "  noconstfn    28 constants folded, 4 variable-returning stubs intact, quit guards intact"

tools/phasecheck.sh "$work" "$f" .cache/symbols/before

tools/phasebuild.sh "$work" "$before_lines"

d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT
cp "$work/whim-vim" "$d/vim"

# --- the quit probes.  All five calibrated against q78 before this phase was written,
# --- because check_more() feeds every condition that decides whether getout(0) runs.
# --- An editor that refuses to quit, or quits without writing, fails here and not in
# --- the compiler.
# EVERY ONE OF THESE CAPTURES THE STATUS AS `rc=0; cmd || rc=$?`, NOT `cmd; rc=$?`.
# Under `set -e` a command whose status is not tested aborts the script, and the
# second probe runs :q on a MODIFIED file, which exits 1 on purpose -- so the plain
# form killed the phase on exactly the behaviour it exists to check, after the build
# and before a single probe had run.  `cmd || rc=$?` is a tested context and is safe.
printf 'a\nb\n' > "$d/q1.txt"
rc=0
(cd "$d" && HOME="$d" ./vim -e -s '+q' q1.txt </dev/null >/dev/null 2>&1) || rc=$?
[ "$rc" = 0 ] || { echo "  noconstfn    :q on an unmodified file exited $rc, expected 0"; exit 1; }
[ "$(tr '\n' '|' < "$d/q1.txt")" = 'a|b|' ] || { echo "  noconstfn    :q changed the file"; exit 1; }

printf 'a\nb\n' > "$d/q2.txt"
rc=0
(cd "$d" && HOME="$d" ./vim -e -s '+normal! A-mod' '+q' q2.txt </dev/null >/dev/null 2>&1) || rc=$?
[ "$rc" = 1 ] || { echo "  noconstfn    :q on a MODIFIED file exited $rc, expected 1 -- it must refuse"; exit 1; }
[ "$(tr '\n' '|' < "$d/q2.txt")" = 'a|b|' ] || { echo "  noconstfn    :q wrote a modified file it should have refused"; exit 1; }

printf 'a\nb\n' > "$d/q3.txt"
rc=0
(cd "$d" && HOME="$d" ./vim -e -s '+normal! A-mod' '+q!' q3.txt </dev/null >/dev/null 2>&1) || rc=$?
[ "$rc" = 0 ] || { echo "  noconstfn    :q! exited $rc, expected 0"; exit 1; }
[ "$(tr '\n' '|' < "$d/q3.txt")" = 'a|b|' ] || { echo "  noconstfn    :q! wrote the file"; exit 1; }

printf 'a\nb\n' > "$d/q4.txt"
rc=0
(cd "$d" && HOME="$d" ./vim -e -s '+1' '+normal! A-wq' '+wq' q4.txt </dev/null >/dev/null 2>&1) || rc=$?
[ "$rc" = 0 ] || { echo "  noconstfn    :wq exited $rc, expected 0"; exit 1; }
[ "$(tr '\n' '|' < "$d/q4.txt")" = 'a-wq|b|' ] || { echo "  noconstfn    :wq did not write: '$(tr '\n' '|' < "$d/q4.txt")'"; exit 1; }

printf 'a\nb\n' > "$d/q5.txt"
rc=0
(cd "$d" && HOME="$d" ./vim -e -s '+1' '+normal! A-x' '+x' q5.txt </dev/null >/dev/null 2>&1) || rc=$?
[ "$rc" = 0 ] || { echo "  noconstfn    :x exited $rc, expected 0"; exit 1; }
[ "$(tr '\n' '|' < "$d/q5.txt")" = 'a-x|b|' ] || { echo "  noconstfn    :x did not write: '$(tr '\n' '|' < "$d/q5.txt")'"; exit 1; }
echo "  noconstfn    :q refuses a modified file, :q! discards, :wq and :x write and exit"

# --- six general probes, all calibrated against q78.  The substitution and :g cases
# --- cover do_one_cmd's range parsing, which steps 2, 3 and 10 all edit.
printf 'a\nb\nc\n' > "$d/t.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+$' '+s/^/LAST /' '+wq' t.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/t.txt")" = 'a|b|LAST c|' ] || { echo "  noconstfn    a range and a substitution broke: '$(tr '\n' '|' < "$d/t.txt")'"; exit 1; }

printf 'k1\ndrop\nk2\n' > "$d/g.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+g/drop/d' '+wq' g.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/g.txt")" = 'k1|k2|' ] || { echo "  noconstfn    :g broke: '$(tr '\n' '|' < "$d/g.txt")'"; exit 1; }

printf 'o1\n' > "$d/sw.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+set shiftwidth=8' '+normal! >>' '+wq' sw.txt </dev/null >/dev/null 2>&1) || true
[ "$(cat "$d/sw.txt")" = '        o1' ] || { echo "  noconstfn    :set and >> broke: '$(cat "$d/sw.txt")'"; exit 1; }

printf 'q1\nq2\n' > "$d/w.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+1' '+normal! A-e' '+wq' w.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/w.txt")" = 'q1-e|q2|' ] || { echo "  noconstfn    writing broke: '$(tr '\n' '|' < "$d/w.txt")'"; exit 1; }

printf 'z1\nz2\n' > "$d/m.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+1' '+normal! ma' '+2' "+normal! 'aA-mk" '+wq' m.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/m.txt")" = 'z1-mk|z2|' ] || { echo "  noconstfn    marks broke: '$(tr '\n' '|' < "$d/m.txt")'"; exit 1; }

printf 'r1\nr2\nr3\n' > "$d/u.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+2' '+normal! dd' '+normal! u' '+wq' u.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/u.txt")" = 'r1|r2|r3|' ] || { echo "  noconstfn    undo broke: '$(tr '\n' '|' < "$d/u.txt")'"; exit 1; }
echo "  noconstfn    ranges, :g, :set, writing, marks and undo all work"
python3 tools/arrowcheck.py "$work/whim-vim"

# --- the delta, cumulative --------------------------------------------------
tools/whimdelta.sh "$work/whim-vim" "$f" --term-moved --cases bomb_on,filter,read_cmd,retab,sort_u,sort_n,ff_dos,binary_mode,format_gq,format_comment,open_comment \
    helpclose intro version cd chdir lcd lchdir tcd tchdir pwd '!' language \
    tags preserve swapname mkvimrc mkexrc checktime command comclear colorscheme \
    abbreviate noreabbrev abclear iabbrev inoreabbrev iabclear cabbrev cnoreabbrev cabclear \
    sleep smile vim9script autocmd augroup doautocmd doautoall noautocmd sandbox filetype \
    tab tabedit tabfirst tabmove tablast tabnext tabnew tabonly tabprevious tabNext tabrewind tabs redrawtabline \
    browse confirm mode open tmap tmapclear tnoremap \
    all args argadd argdelete argdedupe argglobal arglocal argument first last rewind \
    sargument sall sfirst slast srewind \
    aboveleft ball belowright botright horizontal leftabove new only resize rightbelow \
    sbuffer sbNext sball sbfirst sblast sbnext sbprevious sbrewind split sunhide sview \
    syncbind topleft unhide vertical vnew vsplit \
    buffer bNext bdelete bfirst blast brewind buffers bwipeout files ls \
    bnext bprevious keepalt \
    center left retab right sort uniq \
    qall quitall wall wqall xall \
    startinsert startreplace startgreplace stopinsert \
    noswapfile \
    setlocal setglobal \
    lmap lnoremap lmapclear \
    jumps clearjumps
