#!/bin/sh
# Whim phase 64 -- no formatting, comment or nroff-macro options.  See WHIM-GOAL.md.
#
# Usage: pipes/whim64-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# Five options, and the machinery that only they gave a meaning to:
#
#   'comments'       no comment leader is recognised any more.  get_leader_len()
#       and get_last_leader_offset() would return 0 and -1, so everything built
#       on a leader goes: open_line() copying, replacing and aligning one,
#       insertchar() completing a comment's end, J removing leaders, the leader
#       a formatted or wrapped line keeps, same_leader(), skip_comment(), the
#       declaration search skipping comment lines, and % skipping a // comment
#       in a buffer whose 'comments' looked like C.
#   'formatoptions'  fixed at its default, "tcq".  With no leader, 'c' and 'q'
#       have nothing to act on, so what is left is 't': text still wraps at
#       'textwidth' while typing, and gq still formats.  Every other flag was
#       off, so its code goes: 'a' (auto_format(), check_auto_format() and the
#       18 calls), 'w', 'n', '2', 'b', 'l', 'v', 'm', 'M', 'B', '1', 'p', ']',
#       'j', 'r', 'o' and '/'.  'paste' still stops the wrapping, as it did.
#   'formatlistpat'  only 'n' read it, through get_number_indent().
#   'paragraphs', 'sections'  no nroff macro starts a paragraph or section: {, },
#       [[, ]], ( and ) and the ip/ap text objects stop at blank lines, form
#       feeds and braces, and inmacro() goes.
#
# And the two mechanisms that were left reading what those options described:
#
#   THE FORMAT OPERATOR  gq and gw, their doubled gqq/gqgq/gww/gwgw, op_format(),
#       format_lines() and fmt_check_par().  A paragraph is only a paragraph to
#       decide where a format stops, and nothing formats now.  What stays is the
#       wrap while typing: 'textwidth' and 'wrapmargin' still break a line
#       through insertchar() and internal_format(), and 'paste' still stops it.
#       With no gq, INSCHAR_FORMAT is never set and comp_textwidth() loses the
#       flag that chose the screen width for it.
#   GO TO LOCAL DECLARATION  gd and gD, nv_gd() and find_decl(), which searched
#       from the start of the block the cursor was in.  gd was the only caller.
#   THE = OPERATOR  ==, =G and the rest.  op_reindent() re-applied get_indent(),
#       which is the indent the line already has: 'equalprg' went in phase 60 and
#       C-indenting is off, so = could not compute an indent to apply.
#   THE ! OPERATOR  !{motion}, which was ALREADY dead -- its nv_cmds row has been
#       nv_error for phases, and get_op_type() is reached only from nv_operator()
#       -- so OP_FILTER could no longer be set at all.  What goes is the dispatch
#       nothing reached: the OP_FILTER case, the `!` op_colon() typed after a
#       range, and do_bang()'s bangredo block, which only that case set.
#       :w !cmd and :r !cmd still reach do_bang(), and do_filter() still says the
#       command is not available in this version.
#   WHAT C-INDENTING LEFT BEHIND  the engine went phases ago -- no get_c_indent(),
#       no cin_* anything, no 'cindent', 'cinoptions', 'cinkeys', 'cinwords',
#       'indentexpr' or 'indentkeys'.  What stayed was a switch wired to FALSE and
#       its plumbing: cindent_on(), which is `return FALSE`, and can_cindent,
#       WRITTEN IN TEN PLACES AND READ IN NONE -- gcc does not warn, because a
#       static that is assigned counts as used.  set_can_cindent() goes with it.
#       'smartindent' STAYS: may_do_si(), did_si/can_si/can_si_back/no_si and
#       open_line()'s {, }, # and ) rules are a different mechanism, and this
#       build switches it on by default.
#
# THE DELTA: three behaviour cases -- format_gq (gqq now beeps and changes
# nothing) and the two that set the options, format_comment and open_comment.
# The probes check the five options are unknown, that typing still wraps at
# 'textwidth', that gqq and gd do nothing, and that } no longer stops at .PP.
set -eu

work=${1:?usage: whim64-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

python3 - "$f" <<'PY'
TAG = 'noformatopts'
import re, sys
sys.path.insert(0, 'tools')
import cutil
path = sys.argv[1]
t = open(path, errors='surrogateescape').read()

def die(msg):
    sys.exit('  %-12s %s' % (TAG, msg))

def say(what):
    print('  %-12s %s' % (TAG, what))

def in_function(text, name, edit):
    span = cutil.find_definition(text, name)
    if not span:
        die('%s is not defined' % name)
    a, z = span
    return text[:a] + edit(text[a:z]) + text[z:]

def count(s, pattern, n, what):
    k = len(re.findall(pattern, s, re.M))
    if k != n:
        die('%s -- matched %d times, expected %d' % (what, k, n))

def _last(s, pattern, f):
    m = list(re.finditer(pattern, s, re.M))[-1]
    start = s.rfind('\n', 0, m.start()) + 1
    return s[:start] + f(s[start:], pattern, 1, re.M)

def repeat(s, pattern, what, n, f):
    count(s, pattern, n, what)
    for _ in range(n):
        try:
            s = _last(s, pattern, f)
        except ValueError as e:
            die('%s -- %s' % (what, e))
    say(what if n == 1 else '%s (%d)' % (what, n))
    return s

def drop_if(s, pattern, what, n=1):
    return repeat(s, pattern, what, n, lambda x, p, c, fl: cutil.drop_if(x, p, c, fl))

def fold_never(s, pattern, what, n=1):
    return repeat(s, pattern, what, n, cutil.fold_never)

def fold_always(s, pattern, what, n=1):
    return repeat(s, pattern, what, n, cutil.fold_always)

def sub(s, pattern, new, what, n=1):
    s, k = re.subn(pattern, new, s, flags=re.M)
    if k != n:
        die('%s -- matched %d times, expected %d' % (what, k, n))
    say(what)
    return s

def literal(s, old, new, what, n=1):
    k = s.count(old)
    if k != n:
        die('%s -- occurs %d times, expected %d' % (what, k, n))
    say(what)
    return s.replace(old, new)

def lines(s, pattern, what, n=1):
    return sub(s, r'^[ \t]*' + pattern + r'\n', '', what, n)

# ---- open_line: no leader to find, copy or align -------------------------------
def openline(s):
    s = sub(s, r'^[ \t]*if \(flags & OPENLINE_DO_COM\)\n[ \t]*\{\n[ \t]*lead_len = get_leader_len\(ptr, NULL, FALSE, TRUE\);\n'
               r'[ \t]*\}\n[ \t]*else\n[ \t]*\{\n[ \t]*lead_len = 0;\n[ \t]*\}\n', '', 'smartindent looking for a comment leader', 2)
    s = sub(s, r"\( ?lead_len == 0 && ptr\[0\] == '#'\)", "(ptr[0] == '#')", 'smartindent after a # line not asking about a leader', 2)
    # The leader block first: it holds lead_len = 0 statements and an if (lead_len > 0)
    # of its own, which would throw every count after it.
    s = drop_if(s, r'^[ \t]*if \(lead_len > 0\)\n[ \t]*\{\n[ \t]*char_u[ \t]+\*lead_repl = NULL;$', 'copying, replacing and aligning a comment leader')
    s = fold_never(s, r'^[ \t]*if \(flags & OPENLINE_DO_COM\)$', 'a new line finding the leader to repeat')
    s = lines(s, r'lead_len = 0;', 'a new line with no leader')
    s = fold_never(s, r'^[ \t]*if \(lead_len > 0\)$', 'smartindent treating a comment line specially')
    s = fold_never(s, r'^[ \t]*if \(lead_len\)$', 'the new line starting with its leader')
    s = lines(s, r'end_comment_pending = NUL;', 'a new line clearing the pending comment end', 2)
    s = literal(s, 'if (trunc_line && !(flags & OPENLINE_KEEPTRAIL))', 'if (trunc_line)', "a broken line always losing its trailing blanks ('w')")
    s = drop_if(s, r'^[ \t]*if \( \(\(\(State\) & REPLACE_FLAG\) && !\(\(State\) & VREPLACE_FLAG\)\) \)$\n[ \t]*\{\n[ \t]*while \(lead_len-- > 0\)',
                'Replace mode pushing a NUL per leader byte')
    s = literal(s, 'if (newindent == 0 && !(flags & OPENLINE_COM_LIST))', 'if (newindent == 0)', 'the second-line indent no longer for a comment list')
    s = lines(s, r'vim_free\(allocated\);', 'freeing the leader')
    # extra_len sized the leader's allocation and nothing else
    s = lines(s, r'extra_len = \(int\) strlen\(\(char \*\)\(p_extra\)\) ;', 'measuring the text after the cursor for the leader')
    for d in (r'int[ \t]+extra_len = 0;', r'int[ \t]+lead_len;', r'int[ \t]+comment_start = 0;', r'char_u[ \t]+\*lead_flags;',
              r'char_u[ \t]+\*leader = NULL;', r'char_u[ \t]+\*allocated = NULL;'):
        s = lines(s, d, 'open_line declaring ' + d.split('\\*')[-1].split(' ')[-1].rstrip(';').replace('[ \\t]+', ''))
    return s
t = in_function(t, 'open_line', openline)
t = literal(t, 'has_format_option(FO_RET_COMS) ? OPENLINE_DO_COM : 0', '0', "Enter in Insert mode repeating a leader ('r')")
t = literal(t, 'has_format_option(FO_OPEN_COMS) ? OPENLINE_DO_COM : 0', '0', "o and O repeating a leader ('o')")

# ---- insertchar: 'b' and 'l' off, no comment end to complete --------------------
def insch(s):
    s = lines(s, r'int[ \t]+fo_ins_blank;', 'insertchar declaring fo_ins_blank')
    s = lines(s, r'fo_ins_blank = has_format_option\(FO_INS_BLANK\);', "insertchar asking for 'b'")
    s = literal(s, ' && (curwin->w_cursor.lnum != Insstart.lnum || ((!has_format_option(FO_INS_LONG) || Insstart_textlen <= (colnr_T)textwidth) && (!fo_ins_blank || Insstart_blank_vcol <= (colnr_T)textwidth)))',
                '', "wrapping a line that was already long when Insert began ('l', 'b')")
    s = drop_if(s, r'^[ \t]*if \(did_ai && c == end_comment_pending\)$', 'typing the last character of a comment end')
    s = lines(s, r'end_comment_pending = NUL;', 'insertchar clearing the pending comment end')
    return s
t = in_function(t, 'insertchar', insch)
t = lines(t, r'static colnr_T[ \t]+Insstart_textlen;', 'the length of the line Insert began on', 1)
t = lines(t, r'static colnr_T[ \t]+Insstart_blank_vcol;', 'the column of the first blank typed', 1)
t = lines(t, r'Insstart_textlen = \(colnr_T\)linetabsize_str\(ml_get_curline\(\)\);', 'measuring the line Insert began on', 3)
t = lines(t, r'Insstart_blank_vcol = MAXCOL;', 'resetting the first blank typed', 1)
t = drop_if(t, r'^[ \t]*if \(Insstart_blank_vcol == MAXCOL && curwin->w_cursor\.lnum == Insstart\.lnum\)$', 'remembering the first blank typed', 2)
t = lines(t, r'end_comment_pending = NUL;', 'ins_bs clearing the pending comment end')
t = lines(t, r'static int[ \t]+end_comment_pending[ \t]*=[ \t]*NUL[ \t]*;', 'the pending comment end')

# ---- 'a' and 'w': no auto-formatting ------------------------------------------
t = in_function(t, 'stop_insert', lambda s: drop_if(s, r'^[ \t]*if \(!ins_need_undo && has_format_option\(FO_AUTO\)\)$', 'leaving Insert mode auto-formatting'))
t = in_function(t, 'stop_insert', lambda s: lines(s, r'check_auto_format\(TRUE\);', 'leaving Insert mode removing an auto-format space'))
t = in_function(t, 'ins_bs', lambda s: drop_if(s, r'^[ \t]*if \(has_format_option\(FO_AUTO\) && has_format_option\(FO_WHITE_PAR\)\)$', 'backspacing over a line break dropping a trailing space'))
t = in_function(t, 'do_pending_operator', lambda s: drop_if(s, r'^[ \t]*if \(oap->motion_type == MLINE && has_format_option\(FO_AUTO\) && u_save_cursor\(\) == OK\)$', 'a linewise delete auto-formatting'))
t = in_function(t, 'op_delete', lambda s: sub(s, r'^[ \t]*if \(oap->op_type == OP_DELETE\)\n[ \t]*\{\n[ \t]*auto_format\(FALSE, TRUE\);\n[ \t]*\}\n', '', 'a characterwise delete auto-formatting'))
t = lines(t, r'auto_format\((?:FALSE|TRUE), (?:FALSE|TRUE)\);', 'the other calls to auto_format', 15)
for name in ('auto_format', 'check_auto_format', 'paragraph_start'):
    t, gone = cutil.delete_definition(t, name)
    if not gone:
        die('%s is not defined' % name)
    say('%s, which only a flag that is off reached' % name)

# ---- J: 'j', 'M' and 'B' off -------------------------------------------------
def join(s):
    s = sub(s, r'^[ \t]*int[ \t]+remove_comments = \(use_formatoptions == TRUE\)\n[ \t]*&& has_format_option\(FO_REMOVE_COMS\);\n', '', "J asking for 'j'")
    s = lines(s, r'int[ \t]+\*comments = NULL;', 'J declaring the leader offsets')
    s = lines(s, r'int[ \t]+prev_was_comment;', 'J declaring prev_was_comment')
    s = drop_if(s, r'^[ \t]*if \(remove_comments\)$', 'J removing comment leaders', 4)
    s = literal(s, ' && (!has_format_option(FO_MBYTE_JOIN) || (utf_ptr2char(curr) < 0x100 && endcurr1 < 0x100)) && (!has_format_option(FO_MBYTE_JOIN2) || (utf_ptr2char(curr) < 0x100 && !(utf_eat_space(endcurr1))) || (endcurr1 < 0x100 && !(utf_eat_space(utf_ptr2char(curr)))))',
                '', "J inserting no space between multibyte characters ('M', 'B')")
    return s
t = in_function(t, 'do_join', join)

# ---- internal_format: 't' alone, no leader --------------------------------------
def ifmt(s):
    for d in (r'int[ \t]+fo_ins_blank = has_format_option\(FO_INS_BLANK\);', r'int[ \t]+fo_multibyte = has_format_option\(FO_MBYTE_BREAK\);',
              r'int[ \t]+fo_rigor_tw  = has_format_option\(FO_RIGOROUS_TW\);', r'int[ \t]+fo_white_par = has_format_option\(FO_WHITE_PAR\);',
              r'colnr_T[ \t]+leader_len;', r'int[ \t]+no_leader = FALSE;', r'int[ \t]+do_comments = \(flags & INSCHAR_DO_COM\);',
              r'int[ \t]+did_do_comment = FALSE;', r'int[ \t]+first_line = TRUE;', r'int[ \t]+skip_pos;', r'skip_pos = 0;',
              r'int[ \t]+wcc;', r'wcc = 0;'):
        s = lines(s, d, 'internal_format: ' + re.sub(r'\\|\[ \\t\]\+', ' ', d).replace('  ', ' '))
    m = re.search(r'^[ \t]*if \(no_leader\)\n', s, re.M)
    end = '        if (leader_len == 0)\n        {\n            no_leader = TRUE;\n        }\n'
    z = s.find(end)
    if not m or z < 0 or s.count(end) != 1:
        die('internal_format -- the leader lookup was not found once')
    s = s[:m.start()] + s[z + len(end):]
    say("wrapping a line looking up its leader ('c')")
    s = literal(s, 'if (!(flags & INSCHAR_FORMAT) && leader_len == 0 && !has_format_option(FO_WRAP))', 'if (!(flags & INSCHAR_FORMAT) && p_paste)',
                "wrapping only with 't', which 'paste' turns off")
    s = literal(s, 'while ((!fo_ins_blank && !has_format_option(FO_INS_VI)) || (flags & INSCHAR_FORMAT) || curwin->w_cursor.lnum != Insstart.lnum || curwin->w_cursor.col >= Insstart.col)',
                'for (;;)', "breaking only at blanks typed in this Insert ('v', 'b')")
    s = drop_if(s, r'^[ \t]*if \(wcc < 2\)$', 'counting the blanks before a break')
    s = drop_if(s, r"^[ \t]*if \(has_format_option\(FO_PERIOD_ABBR\) && cc == '\.' && wcc < 2\)$", "not breaking after a period ('p')")
    s = fold_never(s, r'^[ \t]*else if \(\(cc >= 0x100 \|\| !utf_allow_break_before\(cc\)\) && fo_multibyte\)$', "breaking between multibyte characters ('m', ']')")
    s = drop_if(s, r'^[ \t]*if \(has_format_option\(FO_ONE_LETTER\)\)$', "not breaking after a one-letter word ('1')")
    s = sub(s, r'^[ \t]*if \(curwin->w_cursor\.col < leader_len\)\n[ \t]*\{\n[ \t]*break;\n[ \t]*\}\n\n?', '', 'not breaking inside the leader')
    s = literal(s, ' && (!fo_white_par || curwin->w_cursor.col < startcol)', '', "keeping a trailing blank ('w')")
    s = fold_always(s, r'^[ \t]*if \(!fo_white_par\)$', "removing the blanks at the break ('w')", 2)
    s = literal(s, 'open_line(FORWARD, OPENLINE_DELSPACES + OPENLINE_MARKFIX + (fo_white_par ? OPENLINE_KEEPTRAIL : 0) + (do_comments ? OPENLINE_DO_COM : 0) + OPENLINE_FORMAT + ((flags & INSCHAR_COM_LIST) ? OPENLINE_COM_LIST : 0), ((flags & INSCHAR_COM_LIST) ? second_indent : old_indent), &did_do_comment);',
                'open_line(FORWARD, OPENLINE_DELSPACES + OPENLINE_MARKFIX, old_indent, NULL);', 'the break opening a line with no leader')
    s = drop_if(s, r'^[ \t]*if \(did_do_comment\)$', 'a leader found by the new line')
    # second_indent is -1: ins_char() is the only caller left once the operator goes
    s = drop_if(s, r'^[ \t]*if \(first_line\)$', "the first broken line's second-line indent ('2', 'n')")
    s = fold_always(s, r'^[ \t]*if \(!\(flags & INSCHAR_COM_LIST\)\)$', 'a comment list keeping its indent')
    return s
t = in_function(t, 'internal_format', ifmt)

# format_lines() and fmt_check_par() are NOT folded for the options: the operator
# section below deletes both outright, and folding a function that is about to go
# is work this phase would throw away.  same_leader(), ends_in_white() and
# get_number_indent() go with them, by the sweep.

# ---- the rest of 'comments' ----------------------------------------------------
t = in_function(t, 'find_decl', lambda s: drop_if(s, r'^[ \t]*if \(get_leader_len\(ml_get_curline\(\), NULL, FALSE, TRUE\) > 0\)$', 'gd skipping comment lines'))
t = in_function(t, 'nv_percent', lambda s: fold_never(s, r'^[ \t]*if \(vim_strchr\(p_cpo, CPO_MATCH\) == NULL && buf_has_cstyle_comments\(\)\)$', '% skipping a // comment'))

# ---- 'paragraphs' and 'sections' ------------------------------------------------
t = in_function(t, 'startPS', lambda s: drop_if(s, r"^[ \t]*if \(\*s == '\.' && \(inmacro\(p_sections, s \+ 1\) \|\| \(!para && inmacro\(p_para, s \+ 1\)\)\)\)$", 'an nroff macro starting a paragraph or section'))

# ---- the format operator: gq, gw, and gqq/gwgw --------------------------------
t = in_function(t, 'nv_g_cmd', lambda s: sub(
    s, r"^[ \t]*case 'q':\n[ \t]*case 'w':\n[ \t]*oap->cursor_start = curwin->w_cursor;\n[ \t]*__attribute__\(\(fallthrough\)\);\n", '',
    'gq and gw as operators'))
t = in_function(t, 'nv_record', lambda s: drop_if(
    s, r'^[ \t]*if \(cap->oap->op_type == OP_FORMAT\)$', 'gqq and gqgq doubling the operator'))
t = in_function(t, 'do_pending_operator', lambda s: sub(
    s, r'^[ \t]*case OP_FORMAT:\n[ \t]*\{\n[ \t]*op_format\(oap, FALSE\);\n[ \t]*\}\n[ \t]*break;\n'
       r'[ \t]*case OP_FORMAT2:\n[ \t]*op_format\(oap, TRUE\);\n[ \t]*break;\n', '', 'the operator reaching the formatter'))

# ---- gd and gD ----------------------------------------------------------------
t = in_function(t, 'nv_g_cmd', lambda s: sub(
    s, r"^[ \t]*case 'd':\n[ \t]*case 'D':\n[ \t]*nv_gd\(oap, cap->nchar, \(int\)cap->count0\);\n[ \t]*break;\n\n?", '',
    'gd and gD'))

# The three go by hand rather than by sweep: comp_textwidth() loses its argument
# below, and format_lines() would still be calling it with one when the sweep
# compiles.
for name in ('op_format', 'format_lines', 'fmt_check_par'):
    t, gone = cutil.delete_definition(t, name)
    if not gone:
        die('%s is not defined' % name)
    say('%s, which only gq and gw reached' % name)

# ---- what only the formatter set: INSCHAR_FORMAT ------------------------------
def insch2(s):
    s = lines(s, r'int[ \t]+force_format = flags & INSCHAR_FORMAT;', 'insertchar asking whether this is a whole-line format')
    s = literal(s, 'textwidth = comp_textwidth(force_format);', 'textwidth = comp_textwidth();', 'the width to wrap at')
    s = literal(s, "if (textwidth > 0 && (force_format || (! ((c) == ' ' || (c) == '\\t')  && !((State & REPLACE_FLAG) && !(State & VREPLACE_FLAG) && *ml_get_cursor() != NUL))))",
                "if (textwidth > 0 && ! ((c) == ' ' || (c) == '\\t')  && !((State & REPLACE_FLAG) && !(State & VREPLACE_FLAG) && *ml_get_cursor() != NUL))",
                'wrapping only a character that was typed')
    s = literal(s, 'internal_format(textwidth, second_indent, flags, c == NUL, c);', 'internal_format(textwidth, second_indent, flags, FALSE, c);',
                'the wrap never being a whole-line format')
    s = drop_if(s, r'^[ \t]*if \(c == NUL\)$', 'insertchar called with no character to insert')
    return s
t = in_function(t, 'insertchar', insch2)

def ctw(s):
    s = drop_if(s, r'^[ \t]*if \(ff && textwidth == 0\)$', "the width gq used when 'textwidth' is 0")
    s = literal(s, 'comp_textwidth(int         ff)', 'comp_textwidth(void)', 'comp_textwidth without its gq flag')
    return s
t = in_function(t, 'comp_textwidth', ctw)
t = literal(t, 'static int comp_textwidth(int ff);', 'static int comp_textwidth(void);', "comp_textwidth's prototype")
t = literal(t, 'cols = comp_textwidth(FALSE);', 'cols = comp_textwidth();', 'the change list asking for the width')
t = in_function(t, 'internal_format', lambda s: literal(s, 'if (!(flags & INSCHAR_FORMAT) && p_paste)', 'if (p_paste)', "wrapping stopped only by 'paste'"))
t = in_function(t, 'internal_format', lambda s: literal(s, 'if (!format_only && haveto_redraw)', 'if (haveto_redraw)', 'the wrap always redrawing'))

# oparg_T's cursor_start was gq's alone, and goes by hand.  deadfields.py keeps
# every field of a type that is ever initialised WITHOUT designators, because a
# positional initialiser names no field and removing one silently shifts what the
# rest fill -- and `oparg_T oa = { 0 };` in pagescroll() is exactly that.
# `{ 0 }` fills only the first field, so removing a later one is safe here.
t = lines(t, r'pos_T[ \t]+cursor_start;', "the cursor gw returned to")

# ---- the = operator, and what only the unreachable ! operator left behind ------
t = sub(t, r"^([ \t]*\{'=', )nv_operator(, 0, 0\} ,)$", r'\1nv_error\2', '= in Normal and Visual mode points at nv_error')

OLD_DISPATCH = r'''        case OP_FILTER:
            if (vim_strchr(p_cpo, CPO_FILTER) != NULL)
            {
                AppendToRedobuff((char_u *)"!\r");
            }
            else
            {
                bangredo = TRUE;
            }

        __attribute__((fallthrough));
        case OP_INDENT:
        case OP_COLON:

            if (oap->op_type == OP_INDENT)
            {
                op_reindent(oap, get_indent);
                break;
            }

            op_colon(oap);
            break;
'''
NEW_DISPATCH = '''        case OP_COLON:
            op_colon(oap);
            break;
'''
t = in_function(t, 'do_pending_operator', lambda s: literal(s, OLD_DISPATCH, NEW_DISPATCH, 'the filter and indent operators being dispatched'))
t = in_function(t, 'do_pending_operator', lambda s: literal(s, ' || oap->op_type == OP_FILTER', '', 'a filter deciding whether the motion is inclusive'))
t = in_function(t, 'op_colon', lambda s: drop_if(s, r'^[ \t]*if \(oap->op_type != OP_COLON\)$', 'the ! typed after an operator range'))
t = in_function(t, 'do_bang', lambda s: drop_if(s, r'^[ \t]*if \(bangredo\)$', 'the ! operator putting its command in the redo buffer'))
# That block held the only `goto theend`, and a label with nothing jumping to it
# is a warning.  The free below it runs either way, so only the marker goes.
t = in_function(t, 'do_bang', lambda s: lines(s, r'theend:', 'do_bang\'s label, which only the redo block jumped to'))

# ---- what C-indenting left behind ---------------------------------------------
# Three of the ten writes are the whole body of an `if`, so the test goes with
# them rather than leaving an empty block.  Each is scoped to its function:
# `if (inindent(0))` also guards do_pending_operator's `oap->motion_type = MLINE`,
# which stays, and an unscoped drop would have had two matches to choose between.
t = in_function(t, 'edit', lambda s: drop_if(s, r'^[ \t]*if \(inindent\(0\)\)$', 'a space typed in the indent forbidding a reindent'))
t = in_function(t, 'ins_bs', lambda s: drop_if(s, r'^[ \t]*if \(in_indent\)$', 'a backspace in the indent forbidding a reindent'))
t = in_function(t, 'ins_tab', lambda s: drop_if(s, r'^[ \t]*if \(ind\)$', 'a Tab in the indent forbidding a reindent'))
t = lines(t, r'can_cindent = (?:TRUE|FALSE);', 'the other places that armed or disarmed a reindent', 7)
t = in_function(t, 'internal_format', lambda s: lines(s, r'set_can_cindent\(TRUE\);', 'a wrapped line arming a reindent'))
t, gone = cutil.delete_definition(t, 'set_can_cindent')
if not gone:
    die('set_can_cindent is not defined')
say('set_can_cindent, which only wrote a flag nothing read')
t = lines(t, r'static int[ \t]+can_cindent;', 'can_cindent itself, written ten times and read none')

# cindent_on() is `return FALSE`; its two callers fold and the sweep takes it.
t = in_function(t, 'ins_bs', lambda s: literal(
    s, 'if (mode == BACKSPACE_LINE && (curbuf->b_p_ai || cindent_on()))', 'if (mode == BACKSPACE_LINE && curbuf->b_p_ai)',
    "CTRL-U keeping the indent for 'autoindent' alone"))
t = in_function(t, 'insertchar', lambda s: literal(
    s, ' && !cindent_on()', '', 'the multi-character insert asking whether C-indenting is on'))

open(path, 'w', errors='surrogateescape').write(t)
PY

python3 tools/dropoptions.py "$f" paragraphs sections
python3 tools/dropoptions.py "$f" --local formatoptions formatlistpat comments

tools/sweep.sh "$f"
for v in b_p_fo b_p_flp b_p_com; do
    python3 tools/droplocal.py "$f" $v
done

# tools/phaserun.sh sweeps next, then runs pipes/whim64-check.sh.
