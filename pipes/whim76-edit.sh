#!/bin/sh
# Whim phase 76 -- one regexp engine, so no retry.  See WHIM-GOAL.md.
#
# Usage: pipes/whim76-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# PROVED BY A SINGLE ASSIGNMENT.  `prog->re_engine = BACKTRACKING_ENGINE` is the only
# place re_engine is ever written, so the field can hold no other value -- and both
#
#     if (rmp->regprog->re_engine == AUTOMATIC_ENGINE && result == -1)
#
# blocks, one in vim_regexec_string and one in vim_regexec_multi, are unreachable.
# They exist to recompile a pattern with the backtracking engine when the automatic
# choice failed; with one engine there is nothing to fall back to.  nfa_regengine and
# regexp_engine are already at zero mentions -- the NFA engine went in an earlier
# phase and these two blocks are what was left pointing at its corpse.
#
# WHAT GOES WITH THEM:
#   * p_re entirely.  It is an ORPHAN OPTION -- no row in the option table, so it can
#     never be set and reads as 0 -- and its only uses are the `< 0 || > 2`
#     validation, which can therefore never fire, and the save/restore inside the two
#     dead blocks.
#   * AUTOMATIC_ENGINE, which has no other reader.
#   * nfa_regprog_T and nfa_state_T, by cascade: their only non-type mentions are the
#     two `((nfa_regprog_T *)rmp->regprog)->pattern` casts INSIDE the dead blocks.
#     A husk kept alive purely by unreachable code.
#
# Audited before writing: both blocks are 25 lines, carry no break or continue that
# would rebind, contain no label, and are followed by no else -- so fold_never takes
# them without the hazards phases 71, 72 and 75 each ran into.
#
# THE DELTA: none expected.  The blocks never ran, so removing them cannot change a
# match.  Declared empty and left for whimdelta.sh to correct.
set -eu

work=${1:?usage: whim76-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

python3 - "$f" <<'PY'
TAG = 'oneengine'
import re, sys
sys.path.insert(0, 'tools')
# tools/cutil.py -- named as a PATH so tools/implhash.sh hashes it into this
# phase's key.  implhash greps for paths and an `import` names a module, so
# without this line an edit to it changes what this phase produces and moves
# no key at all.  See CLAUDE.md on cutil.py and macros.py.  Do not delete it.
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

def literal(s, old, new, what, n=1):
    k = s.count(old)
    if k != n:
        die('%s -- occurs %d times, expected %d' % (what, k, n))
    say(what)
    return s.replace(old, new)

def lines(text, pattern, what, n=1):
    rx = re.compile(r'^[ \t]*' + pattern + r'[ \t]*\n', re.M)
    k = len(rx.findall(text))
    if k != n:
        die('%s -- %d lines match, expected %d' % (what, k, n))
    say(what)
    return rx.sub('', text)

def fold_never(text, fn, pattern, what, n=1):
    def edit(s):
        try:
            return cutil.fold_never(s, pattern, n, re.M)
        except ValueError as e:
            die('%s -- %s' % (what, e))
    out = in_function(text, fn, edit)
    say(what)
    return out

def assigns_to(text, name):
    """Assignments TO `name` or to a `->name` field, skipping any subscript.

    Written the careful way after phase 75, where a first guard matched
    `name[^\\n;]*=` and reported the `!=` of three predicates as writes.  An
    assertion that cries wolf invites being loosened until it passes.
    """
    out = []
    for m in re.finditer(r'\b%s\b' % re.escape(name), text):
        s = text[m.end():m.end() + 80].lstrip()
        if s.startswith('['):
            depth = 0
            for i, ch in enumerate(s):
                if ch == '[':
                    depth += 1
                elif ch == ']':
                    depth -= 1
                    if depth == 0:
                        s = s[i + 1:]
                        break
            s = s.lstrip()
        if s.startswith('=') and not s.startswith('=='):
            out.append(text[:m.start()].count('\n') + 1)
    return out

# THE INVARIANT, asserted here rather than trusted from the survey.  If an upstream
# ever restores a second engine this fails loudly instead of deleting a retry path
# that had become live again.
w = assigns_to(t, 're_engine')
if len(w) != 1:
    die('re_engine is assigned in %d place(s) (lines %s), not once -- a second engine '
        'may exist and both retry blocks may be reachable'
        % (len(w), ' '.join(str(n) for n in w)))
if not re.search(r'^[ \t]*prog->re_engine = BACKTRACKING_ENGINE;[ \t]*$', t, re.M):
    die('the one assignment to re_engine is not to BACKTRACKING_ENGINE')
for gone in ('nfa_regengine', 'regexp_engine'):
    if re.search(r'\b%s\b' % gone, t):
        die('%s still exists -- the NFA engine is back and this phase is wrong' % gone)
say('confirmed: re_engine is written once, to BACKTRACKING_ENGINE, and only there')

# ---- 1. the two retry blocks ------------------------------------------------------
RETRY = r'^[ \t]*if \(rmp->regprog->re_engine == AUTOMATIC_ENGINE && result ==  \(-1\) \)$'
t = fold_never(t, 'vim_regexec_string', RETRY,
               'a failed match recompiling with the other engine')
t = fold_never(t, 'vim_regexec_multi', RETRY,
               'and the multi-line variant of the same')

# ---- 2. the option that chose between engines -------------------------------------
# p_re is an orphan: no row in the option table sets it, so it reads as 0 for ever and
# the range check below can never fire.
t = in_function(t, 'check_num_option_bounds', lambda s: literal(s, '''    if (p_re < 0 || p_re > 2)
    {
        errmsg = e_invalid_argument;
        p_re = 0;
    }
''', '', "validating an option nothing can set"))
t = lines(t, r'static long[ \t]+p_re;', "'regexpengine', which had no row to set it")
t = lines(t, r'enum \{ AUTOMATIC_ENGINE = 0 \};', 'the engine it chose between')

open(path, 'w', errors='surrogateescape').write(t)
PY

tools/st.sh cmdidxs "$f" --check >/dev/null

# tools/phaserun.sh sweeps next, then runs pipes/whim76-check.sh.
