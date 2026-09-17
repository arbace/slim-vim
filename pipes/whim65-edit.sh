#!/bin/sh
# Whim phase 65 -- no rot13, no operator function, no empty key handler.
# See WHIM-GOAL.md.
#
# Usage: pipes/whim65-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# Three cuts, and only the first changes what the editor can do:
#
#   ROT13  g?, the one operator here that encodes rather than edits.  It goes
#       whole: nv_g_cmd()'s case, the OP_ROT13 dispatch label, nv_search()'s
#       redirect -- which is how `g?` reaches the operator when a search is
#       pending -- and swapchar()'s three arms, after which swapchar() is the
#       case-changing function it always really was.
#   THE OPERATOR FUNCTION  g@, which has had nothing to call since the eval
#       feature went: op_function() is one emsg(), and 'operatorfunc' does not
#       exist to name a function anyway.  The dispatch, the OP_FUNCTION term in
#       the motion_force test, and op_function() itself all go.
#   AN EMPTY CALL  ins_ctrl_x() has an empty body -- CTRL-X in Insert mode began
#       a completion, and completion went in phase 6.  The key stays inert, but
#       it no longer calls a function to do nothing.
#
# WHAT IS DELIBERATELY KEPT, because "does nothing" and "should be deleted" are
# different claims:
#
#   CTRL-P and CTRL-N in Insert mode are `break;` -- they do nothing on purpose.
#       Deleting the labels would drop them into `normalchar`, which INSERTS the
#       control character, so removing dead-looking code would add behaviour.
#   zy, zp and zP are live.  It looks as though `zy` must reach
#       internal_error("get_op_type()"), since opchars[] has no {'z','y'} row --
#       but get_op_type() special-cases 'z'+'y' to OP_YANK before it consults the
#       table.  Measured on the q64 binary: no error, no message.
#   The opchars[] rows for g? and g@ stay.  The table is positional -- a row's
#       index IS its OP_* value -- so removing one renumbers every operator after
#       it.  Nothing reaches them once nv_g_cmd() has no case.
#
# THE DELTA: no Ex command, and no behaviour case -- the harness never rot13s.
# The probes check g?g? no longer encodes, that g?? and ?-with-operator-pending
# do not either, that g@g@ is refused, and that gu/gU/g~ still work, since they
# share swapchar() with the arms that go.
set -eu

work=${1:?usage: whim65-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

python3 - "$f" <<'PY'
TAG = 'norot13'
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

# ---- rot13 ---------------------------------------------------------------------
# The case labels are scoped to nv_g_cmd: another switch entirely has '?' and '@'
# next to each other, and an unscoped edit would have two places to choose from.
t = in_function(t, 'nv_g_cmd', lambda s: sub(
    s, r"^([ \t]*case 'U':\n)[ \t]*case '\?':\n[ \t]*case '@':\n", r'\1', 'g? and g@ as operators'))
t = in_function(t, 'nv_search', lambda s: drop_if(
    s, r"^[ \t]*if \(cap->cmdchar == '\?' && cap->oap->op_type == OP_ROT13\)$", 'g? reaching the operator with a search pending'))
t = in_function(t, 'do_pending_operator', lambda s: lines(s, r'case OP_ROT13:', 'rot13 sharing the case-change dispatch'))

def swap(s):
    s = drop_if(s, r'^[ \t]*if \(c >= 0x80 && op_type == OP_ROT13\)$', 'rot13 refusing a multibyte character')
    s = fold_never(s, r'^[ \t]*if \(op_type == OP_ROT13\)$', 'rot13 rotating a letter', 2)
    return s
t = in_function(t, 'swapchar', swap)

# ---- the operator function -----------------------------------------------------
OLD_FUNC = '''        case OP_FUNCTION:
            {
                redo_VIsual_T   save_redo_VIsual = redo_VIsual;

                op_function(oap);

                redo_VIsual = save_redo_VIsual;
                break;
            }

'''
t = in_function(t, 'do_pending_operator', lambda s: literal(s, OLD_FUNC, '', 'g@ reaching the operator function'))
t = in_function(t, 'do_pending_operator', lambda s: literal(
    s, ' || oap->op_type == OP_FUNCTION', '', 'the operator function deciding whether the motion is inclusive'))
t, gone = cutil.delete_definition(t, 'op_function')
if not gone:
    die('op_function is not defined')
say('op_function, which only said the eval feature is not available')

# ---- an empty call --------------------------------------------------------------
t = in_function(t, 'edit', lambda s: sub(
    s, r'^([ \t]*case Ctrl_X:\n)[ \t]*ins_ctrl_x\(\);\n', r'\1', 'CTRL-X calling an empty function'))
t, gone = cutil.delete_definition(t, 'ins_ctrl_x')
if not gone:
    die('ins_ctrl_x is not defined')
say('ins_ctrl_x, whose body has been empty since completion went')

open(path, 'w', errors='surrogateescape').write(t)
PY

# tools/phaserun.sh sweeps next, then runs pipes/whim65-check.sh.
