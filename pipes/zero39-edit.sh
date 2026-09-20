#!/bin/sh
# Zero phase 39 -- `-T {term}` goes, and the command line is `+{command}` alone.
# See ZERO-GOAL.md.
#
# Usage: pipes/zero39-edit.sh <work-dir> <state-dir>     (run from the repository root)
#
# Zero phase 5 left argv as exactly two options: `+{command}`, which is how a host
# tells the editor what to do, and `-T {term}`, which is how a SHELL told it what it
# was attached to.  A core is told that by its host or not at all -- and `-T` has
# had a replacement inside the editor since before this pipeline began: `+set term=`
# reaches did_set_term() and does everything `-T` did, which is why zero phase 33
# rebuilt the terminal harness on it.  So this removes the option, and after it
# `+{command}` is the whole command line: every other word is what every unknown
# word already was, `mainerr(ME_UNKNOWN_OPTION)`.
#
# WHAT THE OPTION LETTER PULLS WITH IT, and every one of these is dead code a sweep
# CANNOT see -- gcc has no warning for a variable that is only ever FALSE, for a
# switch that has lost its cases, or for a statement after a `return`:
#
#   want_argument   the flag `-T` was the only setter of.  With no case left to set
#                   it the whole `if (want_argument)` block is unreachable, and that
#                   block is where ME_GARBAGE, mainerr_arg_missing() and the second
#                   switch -- `parmp->term = argv[0]` -- live.
#   the two rows    ME_GARBAGE and ME_ARG_MISSING lose their last use, and
#                   main_errors[] is INDEXED BY THEM, so the enumerator and the row
#                   are one thing.  deadenums.py would take the enumerator and leave
#                   the row, and the rows are positional; this is CLAUDE.md's
#                   deadfields lesson in a table, so the edit takes both and
#                   renumbers what is left.  mainerr_arg_missing() goes with them
#                   because it is ME_ARG_MISSING's only other mention: the
#                   enumerator cannot go while its one reader is still there.
#   mparm_T.term    the field nothing assigns now.  It goes in the EDIT for a
#                   reason phase 38's dead clause did not have: deadfields.py
#                   matches by NAME, and this file holds thirty-two mentions of
#                   another struct's `.term` member (attr_entry's `ae_u.term`), so
#                   that tool can never see this one dead.  The edit computes that
#                   partition rather than asserting it.
#   termcapinit()   it can only ever be handed what the memset left, so it takes no
#                   name at all now and the compiled default -- read out of the
#                   function, not written here -- is its initialiser.  That is
#                   pipes/zero13-edit.sh's ui_write(console) again.
#
# AND THEN set_termname()'s NO-SCREEN ARM CANNOT RUN.  set_termname() has two call
# sites, and the edit partitions them: termcapinit()'s, which reaches it before
# there is a screen, and did_set_term()'s, which is `:set term=` at run time.  The
# first can no longer fail -- the compiled default IS a row of builtin_terminals[],
# which the edit checks -- so when find_builtin_term() answers nullptr the call came
# from the second, where `starting` is NO_BUFFERS or 0 and never NO_SCREEN (the edit
# reads every assignment to `starting` and requires none of them to be NO_SCREEN).
# So `if (starting != NO_SCREEN)` is always true there, the block returns FAIL, and
# the three statements after it are unreachable: the fallback that phase 38 had to
# repair, report_default_term(), and the option write that recorded it.
# pipes/zero39-check.sh measures all of that with the same marker in the same place
# on both texts -- the input enters the fallback in exactly the two `-T` records and
# a control built from THIS phase's output enters it in none.
#
# THE MESSAGE GOES WITH THE FALLBACK, for phase 38's reason read backwards.  That
# phase retargeted `' not known, defaulting to 'xterm''` onto the name it kept
# because nothing in the build checks that a message tells the truth.  There is no
# fallback to name now, so the clause that promised one is cut -- the NAME is read
# out of the assignment this edit deletes, never written here -- and what is left is
# `'vt320' not known`, which is true, with E522 following it exactly as before.
#
# WHAT RIDES ALONG IS `requested` AND NOT THE 256-COLOUR TEST, and the difference is
# the whole of what was measured.  set_termname() keeps the name it was GIVEN in
# `requested` for one test, `musl_strstr(requested, "256color")`, and CLAUDE.md says
# why: the unknown-terminal path reassigned `term`, so testing that would have given
# `alacritty-256color` eight colours.  That path is what this phase removes, so the
# only rewrite of `term` left is the `term += 8` that strips a `builtin_` prefix --
# and a strstr cannot match inside that prefix, because the needle begins with a
# character the prefix does not contain, which the edit checks rather than asserts.
# So `requested` IS `term` for this test and the variable goes.
#
# THE TEST ITSELF DOES NOT FOLD, and this phase declines to pretend it does.  Both
# surviving terminal names disagree on it -- `xterm-256color` matches and `debug`
# does not -- and `:set term=` still names either at run time.  MEASURED, in both
# directions, and the check keeps the measurement: with the name test forced TRUE
# exactly ONE of the nineteen rows moves (`debug` gains t_Co=256) and with it forced
# FALSE EIGHTEEN move (everything the compiled default reaches drops to t_Co=8).
# A fold either way would be a behaviour change, so there is none here.
#
# THE INPUT BINARY AND ITS ENUMERATOR VALUES ARE TAKEN HERE, before the edit, as
# pipes/zero5-edit.sh takes them: the check needs the old binary to show what `-T`
# used to do, and the DWARF dump because main_errors[] is indexed by enumerators
# this phase renumbers and a build is perfectly happy to renumber a table index.
set -eu

work=${1:?usage: zero39-edit.sh <work-dir> <state-dir>}
state=${2:?usage: zero39-edit.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"

# The flags are read out of the boundary's makefile rather than written here a
# second time: zero's compile line is the boundary's (ZERO-GOAL.md rule 8).
cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")
cp "$f" "$state/old.c"
# shellcheck disable=SC2086
( cd "$state" && SOURCE_DATE_EPOCH=0 gcc $cflags $ldflags -o old old.c ) &
pid_old=$!

# The enumerator values of the text this phase is HANDED: main_errors[] is indexed
# by them and this phase moves one, so the check compares DWARF and not the build.
tools/enumvals.sh "$f" "$state/enums-before" &
pid_enums=$!

python3 - "$f" <<'PY'
TAG = 'cmdline'
import re
import sys
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


def mentions(text, name):
    """Mentions of an IDENTIFIER, with string literals excluded."""
    return len(re.findall(r'\b%s\b' % name, cutil.blank(text)))


def span(text, name):
    r = cutil.find_definition(text, name)
    if r is None:
        die('%s() is not defined in this file, and this phase is drawn against its '
            'extent' % name)
    return r


def in_function(text, name, edit):
    a, z = span(text, name)
    return text[:a] + edit(text[a:z]) + text[z:]


# ---- 0. the parser: the option letters, read out of the switch --------------------
# Nothing is written down here.  Which letters `-` accepts is the first `switch (c)`
# in command_line_scan(), and this phase removes every one of them; what is left is
# the `default:` that was always there.
def parser(s):
    b = cutil.blank(s)
    sw = [m.start() for m in re.finditer(r'\bswitch \(c\)', s)]
    if len(sw) != 2:
        die('command_line_scan() holds %d `switch (c)`, and this phase is written '
            'against the two zero phase 5 left -- the letter and its argument' % len(sw))
    o = b.index('{', sw[0])
    c = cutil.match(s, o, b)
    if c < 0:
        die('the option switch is not balanced')
    body = s[o + 1:c]
    labels = re.findall(r'^[ \t]*(case .*?|default):$', body, re.M)
    letters = [x for x in labels if x != 'default']
    if not letters:
        die('the option switch accepts no letter at all: there is nothing here to '
            'remove and every assertion below would be vacuous')
    if labels.count('default') != 1 or labels[-1] != 'default':
        die('the option switch is %r, and this phase needs one default, last' % labels)
    for lab in letters:
        pat = r'\n[ \t]*%s:\n(?:[^\n]*\n)*?[ \t]*break;\n' % re.escape(lab)
        n = len(re.findall(pat, body))
        if n != 1:
            die('%s has %d arms in the shape `case: ... break;`, and this phase '
                'removes whole arms' % (lab, n))
        body = re.sub(pat, '\n', body)
    s = s[:o + 1] + body + s[c:]
    say('the option letters are READ OUT of the switch and not written here: %s go, '
        'and the default that answered everything else stays'
        % ' '.join(x.split()[-1] for x in letters))

    # want_argument can no longer be TRUE, so its block cannot run.  What is in it
    # is stated as a partition of the block's own text, not as a list.
    m = re.search(r'^[ \t]*if \(want_argument\)$', s, re.M)
    if not m:
        die('command_line_scan() has no `if (want_argument)` to fold')
    bb = cutil.blank(s)
    ob = bb.index('{', m.end())
    cb = cutil.match(s, ob, bb)
    inside = s[ob + 1:cb]
    for name in ('parmp->term', 'ME_GARBAGE', 'mainerr_arg_missing'):
        if inside.count(name) != 1:
            die('the want_argument block names %s %d times, and this phase is '
                'written against the one' % (name, inside.count(name)))
    if 'switch (c)' not in inside:
        die("the want_argument block does not hold the argument switch, so this "
            'phase has misread what it is deleting')
    try:
        s = cutil.fold_never(s, r'^[ \t]*if \(want_argument\)$', 1, re.M)
    except ValueError as e:
        die('the want_argument block would not fold -- %s' % e)
    s = re.sub(r'\n[ \t]*int +want_argument;\n', '\n', s)
    s = re.sub(r'\n[ \t]*want_argument = FALSE;\n', '\n', s)
    if mentions(s, 'want_argument'):
        die('want_argument survives the fold')
    say('want_argument is FALSE for ever, so the block it guarded goes: the '
        'argument switch, `parmp->term`, ME_GARBAGE and mainerr_arg_missing with it')

    # The letter switch is one `default:` now, so it IS its body.  That is only a
    # rewrite because mainerr() does not return, which is read off mainerr() itself.
    bb = cutil.blank(s)
    i = s.index('switch (c)')
    o = bb.index('{', i)
    c = cutil.match(s, o, bb)
    m = re.match(r'\s*\n[ \t]*default:\n(.*)$', s[o + 1:c], re.S)
    if not m:
        die('the option switch did not reduce to one default label: %r' % s[o + 1:c])
    k = s.rfind('\n', 0, s.rfind('\n', 0, i)) + 1
    end = s.index('\n', c) + 1
    s = s[:k + 1] + cutil._dedent4(m.group(1).rstrip(' \n') + '\n') + s[end:]
    s = re.sub(r'\n[ \t]*c = argv\[0\]\[argv_idx\+\+\];\n', '\n', s)
    s = re.sub(r'\n[ \t]*int +c;\n', '\n', s)
    if mentions(s, 'c'):
        die('`c` survives in command_line_scan()')
    return s


def collapse(s):
    """The two arms do the same thing now, so the chain is one else."""
    b = cutil.blank(s)
    m = re.search(r'^[ \t]*else if \(argv\[0\]\[0\] == \'-\'\)$', s, re.M)
    if not m:
        die('command_line_scan() has no `-` arm left to collapse')
    k = s.rfind('\n', 0, m.start()) + 1
    o1 = b.index('{', m.end())
    c1 = cutil.match(s, o1, b)
    nxt = re.match(r'\s*\n[ \t]*else\n', s[c1 + 1:])
    if not nxt:
        die('the `-` arm is not followed by a plain else, so collapsing it would '
            'change which branch runs')
    o2 = b.index('{', c1 + 1 + nxt.end())
    c2 = cutil.match(s, o2, b)
    a1 = cutil.collapse_ws(s[o1 + 1:c1]).strip()
    a2 = cutil.collapse_ws(s[o2 + 1:c2]).strip()
    if a1 != a2:
        die('the `-` arm and the last arm are not the same statement -- %r against '
            '%r -- so they do not collapse' % (a1, a2))
    say('a word beginning with `-` and any other word are now the same statement, '
        '%s, so the chain is ONE else and what is kept is the else arm\'s own text: '
        'the command line is `+{command}` and nothing else' % a1)
    return s[:k + 1] + s[c1 + 2:]


text = in_function(t, 'command_line_scan', parser)
t = in_function(text, 'command_line_scan', collapse)

# mainerr() is what makes dropping `c = argv[0][argv_idx++];` a rewrite and not a
# change: it does not return.  Read off its definition rather than assumed.
a, z = span(t, 'mainerr')
if 'mch_exit(' not in t[a:z]:
    die('mainerr() does not end the process, so the option arm cannot simply be its '
        'call and the increment it dropped would have mattered')

# ---- 1. the two enumerators and the two rows -------------------------------------
# COMPUTED: an ME_* enumerator whose only mention left is its own `enum` line.
# mainerr_arg_missing() goes first because it is the one other mention of one of
# them -- the enumerator cannot go while its reader is there, and the reader has no
# caller since the fold above.
if mentions(t, 'mainerr_arg_missing') != 2:
    die('mainerr_arg_missing has %d mentions after the fold, expected its '
        'definition and its prototype' % mentions(t, 'mainerr_arg_missing'))
t, dropped = cutil.delete_definition(t, 'mainerr_arg_missing')
if not dropped:
    die('mainerr_arg_missing() is not defined in this file')
t = re.sub(r'^static void mainerr_arg_missing\([^)]*\);\n', '', t, flags=re.M)
if mentions(t, 'mainerr_arg_missing'):
    die('mainerr_arg_missing survives its own deletion')

pairs = re.findall(r'^enum \{ (ME_\w+) = (\d+) \};$', t, re.M)
if not pairs or [int(v) for _n, v in pairs] != list(range(len(pairs))):
    die('the ME_* enumerators are not 0..%d in order: %r' % (len(pairs) - 1, pairs))
names = [n for n, _v in pairs]
DEAD = [n for n in names if mentions(t, n) == 1]
if not DEAD:
    die('no ME_* enumerator lost its last use, so this phase removed nothing the '
        'table is indexed by and the renumbering below would be vacuous')
enums = re.search(r'(?:^enum \{ ME_\w+ = \d+ \};\n)+', t, re.M)
table = re.search(r'^static char \*\(main_errors\[\]\) =\n\{\n(.*?)^\};\n', t, re.M | re.S)
if not table:
    die('main_errors[] is not where it was')
rows = table.group(1).splitlines(keepends=True)
if len(rows) != len(pairs) + 1:
    die('main_errors[] has %d rows for %d enumerators; this phase only knows the '
        'shape where the one extra row is the unreachable one whim left'
        % (len(rows), len(pairs)))
drop = sorted(names.index(n) for n in DEAD)
keep = [n for n in names if n not in DEAD]
t = (t.replace(enums.group(0),
               ''.join('enum { %s = %d };\n' % (n, k) for k, n in enumerate(keep)))
      .replace(table.group(0),
               'static char *(main_errors[]) =\n{\n%s};\n'
               % ''.join(r for k, r in enumerate(rows) if k not in drop)))
say('%s lost their last use, and each takes the main_errors[] row it indexes -- %s; '
    '%s.  The enumerator and the row are ONE thing: deadenums.py would take the '
    'enumerator and leave the row, and the rows are positional'
    % (' and '.join(DEAD),
       ' / '.join(rows[i].strip().rstrip(',').strip() for i in drop),
       ', '.join('%s %d->%d' % (n, names.index(n), k)
                 for k, n in enumerate(keep) if names.index(n) != k)
       or 'nothing renumbers'))
say('main_errors[] keeps its last row, %s, which no enumerator named before this '
    'phase either -- whim\'s leftover, and pipes/zero5-edit.sh\'s sentence'
    % rows[-1].strip().rstrip(',').strip())

# ---- 2. termcapinit() takes no name ----------------------------------------------
def tci(s):
    try:
        s = cutil.fold_never(s, r'^[ \t]*if \(term != nullptr && \*term == NUL\)$',
                             1, re.M)
    except ValueError as e:
        die('termcapinit()\'s empty-name test would not fold -- %s' % e)
    d = re.search(r'^[ \t]*if \(term == nullptr \|\| \*term == NUL\)$', s, re.M)
    if not d:
        die('termcapinit() has no `given none` test, so the compiled default cannot '
            'be read out of it')
    b = cutil.blank(s)
    o = b.index('{', d.end())
    c = cutil.match(s, o, b)
    ass = re.match(r'\s*\n[ \t]*term = (.*?);\n[ \t]*$', s[o + 1:c])
    if not ass:
        die('the compiled default is not one assignment: %r' % s[o + 1:c])
    globals()['DEFAULT'] = ass.group(1)
    end = s.index('\n', c) + 1
    k = s.rfind('\n', 0, d.start()) + 1
    s = s[:k] + s[end:]
    s, n = re.subn(r'^([ \t]*char_u +\*term) = name;$', r'\1 =%s;' % DEFAULT.replace('\\', '\\\\'),
                   s, count=1, flags=re.M)
    if n != 1:
        die('termcapinit() does not open with `char_u *term = name;`')
    s = s.replace('termcapinit(char_u *name)', 'termcapinit(void)')
    return s


t = in_function(t, 'termcapinit', tci)
t = re.sub(r'^static void termcapinit\([^)]*\);$', 'static void termcapinit(void);',
           t, flags=re.M)
if t.count('termcapinit(params.term);') != 1:
    die('termcapinit() is not called with the field this phase just removed')
t = t.replace('termcapinit(params.term);', 'termcapinit();')
if mentions(t, 'name') and 'termcapinit(char_u' in t:
    die('termcapinit() still takes a name')
say('termcapinit() takes no name -- nothing could assign the field it was handed -- '
    'and the compiled default it substituted when it was given none, %s, is its '
    'initialiser now.  That is pipes/zero13-edit.sh\'s ui_write(console) again'
    % DEFAULT.strip())

# ---- 3. mparm_T loses the field nothing assigns ----------------------------------
# THE PARTITION, and it is why this is the edit's: every `.term`/`->term` in the
# file belongs either to this struct -- and those mentions have just gone -- or to
# another struct with a member of the same name, which is exactly what
# deadfields.py cannot tell apart, because it matches by NAME.
i = t.index('} mparm_T;')
o = cutil.rmatch(t, t.rindex('}', 0, i + 1))
if o < 0:
    die('mparm_T\'s definition is not balanced')
member = re.search(r'^[ \t]*char_u +\*term;\n', t[o:i], re.M)
if not member:
    die('mparm_T has no `char_u *term;` member to remove')
t = t[:o + member.start()] + t[o + member.end():]
owners = sorted(set(re.findall(r'(\w+)\s*(?:\.|->)\s*term\b', cutil.blank(t))))
if not owners:
    die('nothing in the file names a `.term` member at all, so the partition below '
        'says nothing -- read the file before removing this')
mine = [x for x in owners if x in ('params', 'parmp')]
if mine:
    die('%s still names this struct\'s `term` field' % ' '.join(mine))
say('mparm_T loses its `term` member, in the EDIT: every one of the %d `.term` '
    'mentions left belongs to another struct (%s), and deadfields.py matches by '
    'NAME, so that tool could never see this one dead'
    % (len(re.findall(r'(?:\.|->)\s*term\b', cutil.blank(t))), ' '.join(owners)))

# ---- 4. set_termname()'s no-screen arm cannot run ---------------------------------
# THE ARGUMENT, computed in three parts before a line is cut.
calls = []
for m in re.finditer(r'\bset_termname\s*\(', cutil.blank(t)):
    lo = t.rfind('\n    static ', 0, m.start())
    fn = re.search(r'\n[a-zA-Z_]\w*', t[lo:m.start()])
    calls.append((m.start(), fn.group(0).strip() if fn else '?'))
defn = span(t, 'set_termname')
sites = sorted({who for at, who in calls if not (defn[0] <= at < defn[1])
                and t[t.rfind('\n', 0, at) + 1:at].strip() != 'static int'})
if sites != ['did_set_term', 'termcapinit']:
    die('set_termname() is called from %s, and this phase is written against the '
        'two -- termcapinit(), before there is a screen, and did_set_term(), at run '
        'time' % (' '.join(sites) or 'nowhere'))
ROWS = re.findall(r'^[ \t]*\{\s*"([^"]*)"\s*,\s*\w+\s*\},$',
                  t[t.index('static builtin_tcap_T builtin_terminals[] = {'):
                    t.index('\n};', t.index('static builtin_tcap_T builtin_terminals[] = {'))],
                  re.M)
default_name = re.search(r'"([^"]*)"', DEFAULT).group(1)
if default_name not in ROWS:
    die('the compiled default %r is not a row of builtin_terminals[], so '
        'termcapinit() can still be refused and the arm below is live'
        % default_name)
assigns = sorted({m.group(1).strip() for m in
                  re.finditer(r'^[ \t]*starting = ([^;]+);$', t, re.M)})
if 'NO_SCREEN' in assigns:
    die('something assigns starting = NO_SCREEN, so `starting != NO_SCREEN` is not '
        'true wherever the arm below is reached: %s' % ' '.join(assigns))
say('set_termname() is called from %s and from nowhere else; termcapinit() now '
    'passes %r, which IS a row of builtin_terminals[]; and the only assignments to '
    '`starting` are %s -- so a refusal can only come from did_set_term(), where '
    '`starting != NO_SCREEN`' % (' and '.join(sites), default_name, ' and '.join(assigns)))


def stn(s):
    b = cutil.blank(s)
    m = re.search(r'^[ \t]*if \(termp == nullptr\)$', s, re.M)
    if not m:
        die('set_termname() has no `termp == nullptr` arm')
    o = b.index('{', m.end())
    c = cutil.match(s, o, b)
    if c < 0:
        die('the refusal arm is not balanced')
    pad = s[s.rfind('\n', 0, c) + 1:c]
    try:
        inner = cutil.fold_always(s[o + 1:c],
                                  r'^[ \t]*if \(starting != NO_SCREEN\)$', 1, re.M)
    except ValueError as e:
        die('the no-screen test would not fold -- %s' % e)
    k = inner.index('return FAIL;\n') + len('return FAIL;\n')
    globals()['TAIL'] = inner[k:]
    if not TAIL.strip():
        die('nothing follows the refusal, so this phase has already been applied or '
            'the arm is not the one it was written against')
    return s[:o + 1] + inner[:k] + pad + s[c:], TAIL


a, z = span(t, 'set_termname')
seg, TAIL = stn(t[a:z])
t = t[:a] + seg + t[z:]
say('the no-screen test folds ALWAYS, and what followed the refusal is unreachable '
    'and goes: %s' % ' '.join(TAIL.split()))

# The name the fallback promised, read out of the text that has just been deleted.
NAME = re.search(r'"([^"]*)"', TAIL)
if not NAME or NAME.group(1) not in ROWS:
    die('the deleted fallback does not name a row of builtin_terminals[], so the '
        'message below cannot be kept in step with it')
NAME = NAME.group(1)
if 'report_default_term' not in TAIL:
    die('the deleted text does not call report_default_term(), which this phase '
        'leaves for the sweep -- read the arm before removing this')


def message(s):
    out = re.sub(r",[^\"]*'%s'" % re.escape(NAME), '', s)
    if out == s:
        die('report_term_error() does not promise %r, so there is nothing here to '
            'keep in step with the fallback' % NAME)
    left = [x for x in ROWS if "'%s'" % x in out]
    if left:
        die('report_term_error() still names %s after the cut' % ' '.join(left))
    return out


t = in_function(t, 'report_term_error', message)
say('report_term_error() stops promising %r: phase 38 moved the message and the '
    'fallback together because nothing in the build checks that a message tells the '
    'truth, and this is that rule with no fallback left to name' % NAME)

# ---- 5. `requested` is `term` for the one test that reads it ----------------------
def requested(s):
    hits = [m for m in re.finditer(r'\brequested\b', cutil.blank(s))]
    if len(hits) != 2:
        die('`requested` has %d mentions in set_termname(), and this phase is '
            'written against two -- its declaration and the 256-colour test'
            % len(hits))
    rew = sorted({m.group(1).strip() for m in
                  re.finditer(r'^[ \t]*term (\+?=[^;]*);$', s, re.M)})
    if rew != ['+= 8']:
        die('`term` is rewritten as %s inside set_termname(), and `requested` can '
            'only be folded into it while the prefix strip is the only one'
            % ' / '.join(rew) or 'nothing')
    prefix = re.search(r'musl_strncmp\(\(char \*\)\(name\), \(char \*\)\("([^"]*)"\), '
                       r'\(\(usize\)(\d+)\)\)', t[slice(*span(t, 'term_is_builtin'))])
    if not prefix or len(prefix.group(1)) != int(prefix.group(2)):
        die('term_is_builtin() does not strip a counted literal prefix, so what '
            '`term += 8` skips cannot be read off the file')
    needle = re.search(r'musl_strstr\(\(char \*\)requested, "([^"]*)"\)', s)
    if not needle:
        die('the 256-colour test is not a musl_strstr on `requested`')
    if needle.group(1)[0] in prefix.group(1):
        die('%r begins with a character the stripped prefix %r contains, so a match '
            'could start inside the prefix and `requested` is NOT `term` here'
            % (needle.group(1), prefix.group(1)))
    s = s.replace('musl_strstr((char *)requested, "%s")' % needle.group(1),
                  'musl_strstr((char *)term, "%s")' % needle.group(1))
    s, n = re.subn(r'\n[ \t]*char_u +\*requested = term;\n', '\n', s)
    if n != 1:
        die('`requested` is not declared as `= term`')
    say('`requested` goes: it existed because the fallback reassigned `term`, and '
        'the only rewrite left is the %s that strips %r -- %r cannot match inside '
        'that, because it begins with a character the prefix does not hold'
        % (rew[0], prefix.group(1), needle.group(1)))
    return s


a, z = span(t, 'set_termname')
t = t[:a] + requested(t[a:z]) + t[z:]

# ---- 6. what is left, as a partition ---------------------------------------------
GONE = ('want_argument', 'mainerr_arg_missing', 'ME_GARBAGE', 'ME_ARG_MISSING',
        'requested')
for name in GONE:
    if mentions(t, name):
        die('%s still has %d mentions' % (name, mentions(t, name)))
for name in ('ME_UNKNOWN_OPTION', 'ME_EXTRA_CMD', 'MAX_ARG_CMDS', 'exe_commands',
             'p_paste', 'did_set_term', 'report_term_error'):
    if not mentions(t, name):
        die('%s went, and it is not this phase\'s' % name)
if mentions(t, 'report_default_term') != 1:
    die('report_default_term has %d mentions, and this phase leaves it at one -- '
        'its own definition, which is what the sweep takes'
        % mentions(t, 'report_default_term'))
say('0 mentions of %s; report_default_term is down to its definition and is the '
    'sweep\'s; ME_UNKNOWN_OPTION, ME_EXTRA_CMD, MAX_ARG_CMDS, exe_commands and '
    "'paste' are untouched" % ', '.join(GONE))

open(path, 'w', errors='surrogateescape').write(t)
PY

# NOT create_cmdidxs --check, for pipes/zero2-edit.sh's reason: the derived
# first-two-letters index went with the command table whim reduced, and the tool
# raises rather than reporting nothing.  Nothing here touches the command table.
#
# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  cmdline      the input binary did not build with '$cflags' '$ldflags'"; exit 1; }
wait $pid_enums || { echo "  cmdline      the input's enumerator values could not be dumped"; exit 1; }
echo "  cmdline      the input is $state/old, $(stat -c%s "$state/old") bytes, beside the source it was built from and $(grep -c '' "$state/enums-before") enumerator values: this phase moves command lines and renumbers a table index, and both need a before"

# tools/phaserun.sh sweeps next, then runs pipes/zero39-check.sh.
