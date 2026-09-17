#!/bin/sh
# Whim phase 69 -- one file argument, and no argument list.  See WHIM-GOAL.md.
#
# Usage: pipes/whim69-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# THE ORDER MATTERS, and it is the opposite of the obvious one.  An earlier
# attempt at "one buffer" imposed reuse inside buflist_new() and deleted the
# argument-list call that reaches it -- and that call is THE ONLY THING THAT NAMES
# THE FIRST BUFFER.  open_buffer() reads through `readfile(curbuf->b_ffname, ...)`,
# so with no name it read nothing: the buffer came up empty, every edit was a
# silent no-op, and :wq wrote the original bytes back.  It built and it passed two
# of three probes.
#
# So this phase limits the command line FIRST and keeps the naming path exactly as
# it is:
#
#   ONE FILE ARGUMENT.  A second non-option argument is mainerr(ME_TOO_MANY_ARGS),
#       which is what vim already answers for a second `-`.  One file means one
#       entry, which is what makes the list pointless rather than merely unused.
#   THE NAME STILL GOES THROUGH buflist_add().  curbuf exists and is unnamed and
#       empty when command_line_scan() runs -- main() calls common_init_2(), which
#       calls win_alloc_first(), before the scan -- so buflist_new() reuses it and
#       sets b_ffname, exactly as today.  Only the LIST around that call goes.
#   THE ARGUMENT LIST.  :next and :previous point at ex_ni; the other 21 argument
#       commands already do.  ex_next(), ex_previous(), do_argfile(), do_arglist(),
#       arglist_del_files(), alist_set(), alist_clear(), alist_add(), alist_name(),
#       editing_arg_idx(), check_arglist_locked(), arg_had_last, global_alist,
#       alist_T, aentry_T, w_alist, w_arg_idx, w_arg_idx_invalid and mparm_T.fname
#       go with them, by fold or by sweep.
#
# WHAT FOLDS BECAUSE THE COUNT IS ALWAYS ONE: check_more(), whose "N more files to
# edit" refusal can never fire; append_arg_number(), the "(N of M)" suffix in
# :file; and the four ADDR_ARGUMENTS arms of Ex range parsing.
#
# THE DELTA: NONE, which was measured rather than assumed.  :next and :previous
# were declared as moving and did not: an exsweep row is `exit= left= err=`, and
# with one file argument do_argfile() already answered "there is only one file to
# edit" -- so pointing the rows at ex_ni changes the message text, which the sweep
# does not record, while the exit status, the files touched and stderr all stay the
# same.  The declaration is narrowed to match the measurement; widening one to fit
# is what whimdelta.sh exists to refuse.
#
# The probes are LOAD-FIRST -- the first one proves the buffer holds the file's
# lines, because that is the check the earlier attempt did not have and needed.
set -eu

work=${1:?usage: whim69-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

python3 - "$f" <<'PY'
TAG = 'onearg'
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

def body(text, name, new, what):
    def edit(s):
        head = s[:s.index('{\n') + 2]
        say(what)
        return head + new + '}\n'
    return in_function(text, name, edit)

# ---- 1. one file argument, and the name still reaching curbuf -------------------
OLD_ARG = '''            if (parmp->edit_type != EDIT_NONE && parmp->edit_type != EDIT_FILE)
            {
                mainerr(ME_TOO_MANY_ARGS, (char_u *)argv[0]);
            }
            parmp->edit_type = EDIT_FILE;

            if (ga_grow(&global_alist.al_ga, 1) == FAIL || (p = vim_strsave((char_u *)argv[0])) == NULL)
            {
                mch_exit(2);
            }

            alist_add(&global_alist, p, 2);

'''
NEW_ARG = '''            if (parmp->edit_type != EDIT_NONE)
            {
                mainerr(ME_TOO_MANY_ARGS, (char_u *)argv[0]);
            }
            parmp->edit_type = EDIT_FILE;

            if ((p = vim_strsave((char_u *)argv[0])) == NULL)
            {
                mch_exit(2);
            }

            (void)buflist_add(p, BLN_CURBUF | BLN_LISTED);

'''
t = in_function(t, 'command_line_scan', lambda s: literal(s, OLD_ARG, NEW_ARG, 'a second file argument, and the list that held them'))

# ---- 2. :next and :previous ------------------------------------------------------
for c, h in (('next', 'ex_next'), ('previous', 'ex_previous')):
    t = sub(t, r'^([ \t]*\[CMD_%s\] = \{\(char_u \*\)"%s", sizeof\("%s"\) - 1, )%s,' % (c, c, c, h), r'\1ex_ni,',
            ':%s points at ex_ni' % c)

# ---- 3. the readers that can only ever see one --------------------------------
t = body(t, 'check_more', '    return OK;\n', 'check_more refusing to quit with files left to edit')
t = body(t, 'append_arg_number', '    return 0;\n', 'the (N of M) suffix on the file message')

# EVERY command that uses ADDR_ARGUMENTS -- argadd, argdelete, argdo, argedit,
# argument, sargument -- is already ex_ni, so no live command reaches these arms.
# But the LABELS MUST STAY: these switches enumerate ADDR_* exhaustively, and
# deleting one only earns "enumeration value 'ADDR_ARGUMENTS' not handled in
# switch" -- seven of them, which is what the sweep kept reporting as "left alone"
# and could never converge on.  So each arm gets a constant body instead.
def arm(text, fn, old, new, what, n=1):
    return in_function(text, fn, lambda s: literal(s, old, new, what, n))

t = arm(t, 'parse_cmd_address',
        '''                    case ADDR_ARGUMENTS:
                        if ( ( (curwin)->w_alist ->al_ga.ga_len)  == 0)
                        {
                            eap->line1 = eap->line2 = 0;
                        }
                        else
                        {
                            eap->line1 = 1;
                            eap->line2 =  ( (curwin)->w_alist ->al_ga.ga_len) ;
                        }
                        break;
''',
        '''                    case ADDR_ARGUMENTS:
                        eap->line1 = eap->line2 = 0;
                        break;
''', 'an argument range in a command line')

t = arm(t, 'address_default_all',
        '''        case ADDR_ARGUMENTS:
            if ( ( (curwin)->w_alist ->al_ga.ga_len)  == 0)
            {
                eap->line1 = eap->line2 = 0;
            }
            else
            {
                eap->line2 =  ( (curwin)->w_alist ->al_ga.ga_len) ;
            }
            break;
''',
        '''        case ADDR_ARGUMENTS:
            eap->line1 = eap->line2 = 0;
            break;
''', 'an argument range with no range given')

t = arm(t, 'default_address',
        '''        case ADDR_ARGUMENTS:
            lnum = curwin->w_arg_idx + 1;
            if (lnum >  ( (curwin)->w_alist ->al_ga.ga_len) )
            {
                lnum =  ( (curwin)->w_alist ->al_ga.ga_len) ;
            }
            break;
''',
        '''        case ADDR_ARGUMENTS:
            lnum = 0;
            break;
''', 'the default line for an argument range')

t = arm(t, 'get_address',
        '''                    case ADDR_ARGUMENTS:
                        lnum = curwin->w_arg_idx + 1;
                        break;
''',
        '''                    case ADDR_ARGUMENTS:
                        lnum = 0;
                        break;
''', 'an argument range parsed from an address', 2)
t = arm(t, 'get_address',
        '''                    case ADDR_ARGUMENTS:
                        lnum =  ( (curwin)->w_alist ->al_ga.ga_len) ;
                        break;
''',
        '''                    case ADDR_ARGUMENTS:
                        lnum = 0;
                        break;
''', 'the last line of an argument range')

t = arm(t, 'invalid_range',
        '''            case ADDR_ARGUMENTS:
                if (eap->line2 >  ( (curwin)->w_alist ->al_ga.ga_len)  + (! ( (curwin)->w_alist ->al_ga.ga_len) ))
                {
                    return _(e_invalid_range);
                }
                break;
''',
        '''            case ADDR_ARGUMENTS:
                break;
''', 'an argument range checked for validity')

# ---- 3b. the readers with live callers -----------------------------------------
# check_arg_idx() is called from six live functions, so its BODY folds and the calls
# go; editing_arg_idx() is reached only from it.  arg_all() builds the ## expansion
# from every entry, and now has none to build from.
t = lines(t, r'check_arg_idx\((?:win|curwin)\);', 'the six calls that revalidated the argument index', 6)
t = in_function(t, 'eval_vars', lambda s: literal(
    s, '                    result = arg_all();\n                    resultbuf = result;\n',
    '                    result = (char_u *)"";\n                    resultbuf = NULL;\n',
    '## expanding to every file in the argument list'))

# the window fields, and the one place that still set an index
t = in_function(t, 'win_init_some', lambda s: sub(
    s, r'^[ \t]*newp->w_alist = oldp->w_alist;\n[ \t]*\+\+newp->w_alist->al_refcount;\n[ \t]*newp->w_arg_idx = oldp->w_arg_idx;\n\n?',
    '', 'a new window inheriting the argument list'))
t = lines(t, r'curwin->w_arg_idx = -1;', 'the index a swap-file quit invalidated')
t = sub(t, r'^[ \t]*alist_T[ \t]+\*w_alist;\n[ \t]*int[ \t]+w_arg_idx;\n[ \t]*bool[ \t]+w_arg_idx_invalid;\n', '',
        "the window's argument-list fields")
# main() takes the first entry's name into params.fname and never reads it: the
# whole guarded assignment goes, not just the line, or alist_name outlives the list.
t = sub(t, r'^[ \t]*if \( \(global_alist\.al_ga\.ga_len\)  > 0\)\n[ \t]*\{\n'
           r'[ \t]*params\.fname = alist_name\(& \(\(aentry_T \*\)global_alist\.al_ga\.ga_data\) \[0\]\);\n[ \t]*\}\n', '',
        'main taking the first argument as the file name')
t = sub(t, r'^[ \t]*char_u[ \t]+\*fname;\n\n', '', "mparm_T's unread fname")
# The list itself: initialised at startup and pointed at by the one window.  These
# are the last two mentions, and without them alist_init, global_alist, alist_T and
# aentry_T all lose their readers and the sweep takes them.
t = in_function(t, 'common_init_2', lambda s: sub(
    s, r'^[ \t]*alist_init\(&global_alist\);\n[ \t]*global_alist\.id = 0;\n\n?', '', 'the argument list set up at startup'))
t = in_function(t, 'win_alloc_firstwin', lambda s: lines(
    s, r'curwin->w_alist = &global_alist;', 'the one window pointing at it'))
# The two types, matched in their INPUT shape.  An earlier version patterned against
# `typedef struct arglist { int id; } alist_T;` -- which is what the file looks like
# AFTER a sweep has stripped the fields, not before one -- and matched nothing.  Both
# are removed here rather than left to typereach.py, which takes roots from mentions
# outside every type definition and still leaves the typedef standing.
t = sub(t, r'^typedef struct arglist\n\{\n[ \t]*garray_T[ \t]+al_ga;\n[ \t]*int[ \t]+al_refcount;\n[ \t]*int[ \t]+id;\n\} alist_T;\n\n?',
        '', 'the argument list type itself')
t = sub(t, r'^typedef struct argentry\n\{\n[ \t]*char_u[ \t]+\*ae_fname;\n[ \t]*int[ \t]+ae_fnum;\n\} aentry_T;\n\n?',
        '', 'the argument entry type')
# and the count message, which one file argument can never satisfy
t = sub(t, r'^[ \t]*if \( \(global_alist\.al_ga\.ga_len\)  > 1 && !silent_mode\)\n[ \t]*\{\n'
           r'[ \t]*printf\(_\("%d files to edit\\n"\),  \(global_alist\.al_ga\.ga_len\) \);\n[ \t]*\}\n\n?', '',
        'the "N files to edit" message at startup')

open(path, 'w', errors='surrogateescape').write(t)
PY

python3 tools/create_cmdidxs.py "$f" --check >/dev/null

# tools/phaserun.sh sweeps next, then runs pipes/whim69-check.sh.
