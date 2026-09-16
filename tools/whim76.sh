#!/bin/sh
# Whim phase 76 -- one regexp engine, so no retry.  See WHIM-GOAL.md.
#
# Usage: tools/whim76.sh <work-dir>      (run from the repository root)
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

work=${1:?usage: whim76.sh <work-dir>}
f="$work/whim-vim.c"

before_lines=$(grep -c '' "$f")
tools/symbols.sh "$f" .cache/symbols/before

python3 - "$f" <<'PY'
TAG = 'oneengine'
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

python3 tools/create_cmdidxs.py "$f" --check >/dev/null

tools/sweep.sh "$f"

# The retry, the option and the husk it kept alive are gone.
for g in AUTOMATIC_ENGINE p_re nfa_regprog_T nfa_state_T nfa_regengine regexp_engine; do
    n=$(grep -cE -- "\\b$g\\b" "$f" || true)
    [ "$n" = 0 ] || { echo "  oneengine    $g still has $n mentions"; exit 1; }
done
# The one engine and everything matching depends on must survive.
for g in BACKTRACKING_ENGINE re_engine bt_regengine bt_regprog_T regprog_T regengine_T \
         vim_regcomp vim_regfree vim_regexec_string vim_regexec_multi re_in_use re_flags; do
    grep -qE "\\b$g\\b" "$f" || { echo "  oneengine    $g went -- matching still needs it"; exit 1; }
done
grep -qE 'prog->re_engine = BACKTRACKING_ENGINE;' "$f" || { echo "  oneengine    the engine is no longer recorded on the program"; exit 1; }
echo "  oneengine    one engine, no retry; the matcher and its program types intact"

tools/phasecheck.sh "$work" "$f" .cache/symbols/before

tools/phasebuild.sh "$work" "$before_lines"

d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT
cp "$work/whim-vim" "$d/vim"

# EVERY PROBE CALIBRATED AGAINST q75 FIRST.  This phase touches vim_regexec_string and
# vim_regexec_multi, so the probes exercise MATCHING rather than plain editing -- a
# load-and-edit probe would pass whatever happened to the regexp layer.
printf 'a\nb\nc\n' > "$d/t.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+$' '+s/^/LAST /' '+wq' t.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/t.txt")" = 'a|b|LAST c|' ] || { echo "  oneengine    the file did not load: '$(tr '\n' '|' < "$d/t.txt")'"; exit 1; }

# a quantified pattern, matched many times on one line -- vim_regexec_string
printf 'alpha\nbeta\ngamma\n' > "$d/s.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+%s/a\+/X/g' '+wq' s.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/s.txt")" = 'XlphX|betX|gXmmX|' ] || { echo "  oneengine    a quantified match broke: '$(tr '\n' '|' < "$d/s.txt")'"; exit 1; }

# :g drives vim_regexec_multi over every line
printf 'one1\ntwo2\nthree3\n' > "$d/d.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+g/[0-9]$/s/[0-9]$/N/' '+wq' d.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/d.txt")" = 'oneN|twoN|threeN|' ] || { echo "  oneengine    :g over a pattern broke: '$(tr '\n' '|' < "$d/d.txt")'"; exit 1; }

# capture groups and back-references, which the backtracking engine implements
printf 'foo\nbar\nfoobar\n' > "$d/r.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+%s/\(foo\)\(bar\)/\2\1/' '+wq' r.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/r.txt")" = 'foo|bar|barfoo|' ] || { echo "  oneengine    back-references broke: '$(tr '\n' '|' < "$d/r.txt")'"; exit 1; }

# a non-capturing group with a count -- the shape the NFA engine used to be chosen for
printf 'aaa\nbbb\n' > "$d/c.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+%s/\%(a\|b\)\{2}/Z/' '+wq' c.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/c.txt")" = 'Za|Zb|' ] || { echo "  oneengine    a counted group broke: '$(tr '\n' '|' < "$d/c.txt")'"; exit 1; }

# and a plain search, which reaches the matcher by a different path again
printf 'x\ny\n' > "$d/n.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+/y' '+normal! A-found' '+wq' n.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/n.txt")" = 'x|y-found|' ] || { echo "  oneengine    search broke: '$(tr '\n' '|' < "$d/n.txt")'"; exit 1; }
echo "  oneengine    quantifiers, :g, back-references, counted groups and search all match"
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
