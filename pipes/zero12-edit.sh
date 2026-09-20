#!/bin/sh
# Zero phase 12 -- the options nothing reads.  See ZERO-GOAL.md.
#
# Usage: pipes/zero12-edit.sh <work-dir> <state-dir>     (run from the repository root)
#
# Phases 6 to 11 took every way to reach a file and then the refusal that guarded
# the text.  What they left behind is a set of SETTINGS: `options[]` rows whose
# global nothing reads any more, so that `:set fsync?` answers a question about
# machinery that is not there.  An option that cannot do anything is a lie, and the
# same argument that removed `:write` removes `'write'`.
#
# WHICH ROWS GO IS COMPUTED, NOT LISTED.  The edit walks `options[]`, finds each
# row's `(char_u *)&p_xx` and counts readers of that global outside the row, with
# `dropoptions --strict`'s own exclusions -- another row, the row's `var`
# field, the variable's own declaration, and taking the address, which is an
# identity test and not a dereference.  Exactly SEVEN of the 114 rows have no
# reader, and the program requires that set rather than naming six of them:
#
#   fsync       p_fs       PV_BOTH   goes, but needs droplocal.py b_p_fs first
#   modified    p_mod      PV_BUF    STAYS -- see below
#   prompt      p_prompt   PV_NONE   goes
#   readonly    p_ro       PV_BUF    goes, by ZERO-PLAN.md decision 5
#   undoreload  p_ur       PV_NONE   goes
#   write       p_write    PV_NONE   goes
#   writeany    p_wa       PV_NONE   goes
#
# `'modified'` HAS NO READER OF `p_mod` EITHER AND MUST NOT GO.  ZERO-PLAN.md
# decision 5 keeps it: the state it reports lives in `b_changed`, not in `p_mod`, so
# `:set modified?` answers correctly and the row is not a lie.  A computation that
# took "no reader" as the criterion would delete it, which is why the seven are
# computed and the six are chosen.  `dropoptions` refuses it anyway, on the
# PV_ guard.
#
# `'paste'` IS EXEMPT FOR EVER, and this is the comment that says so -- ZERO-PLAN.md
# 2d and decision 8, the user's standing promise.  `p_paste` has 12 mentions here and
# has them afterwards, and its five save slots `p_ai_nopaste p_et_nopaste
# p_sts_nopaste p_tw_nopaste p_wm_nopaste` are the non-pointer orphans
# tools/orphanopts.py reports and tolerates, before and after, identically.  THE NEXT
# PERSON TO RUN THE COMPUTATION MUST NOT "FIX" THEM.  `+{command}` is likewise
# untouched, for the same promise.
#
# FOUR PARTS.  A and B are the tools' work; C is the only live code here.
#
#   A  the four clean rows, `dropoptions --strict prompt undoreload write
#      writeany`.  The sweep then takes the four globals as -Wunused-variable.
#   B  `'fsync'`, which --strict alone REFUSES -- not on a reader but on the PV_
#      guard, because the row is what initialises the global ('tagcase' taught that
#      by segfaulting before the first keystroke).  `droplocal.py b_p_fs` is the
#      other half and goes first: six plumbing sites, including get_varp()'s two-line
#      "local if set" form.  Then `--strict --local fsync`.
#   C  `'readonly'`, which is LIVE CODE and not an inert row.  `p_ro` the global has
#      had no reader since whim; what survives is the buffer-local `b_p_ro`, and
#      since phase 6 nothing but `:set ro` can set it -- decision 5's premise.  Five
#      edits, in this order and for this reason:
#        1  the W10 warning.  `change_warning()` and its six call sites, each one
#           statement on a line of its own.  There is NO PROTOTYPE -- it is defined
#           above its first call -- so a program that removes one fails loudly.  This
#           also takes the `ui_delay(1002L, TRUE)` that ZERO-GOAL.md phase 2 named as
#           one of the eight other pauses.
#        2  the `[RO]` in `fileinfo()`.  THE FORMAT STRING AND THE ARGUMENT MOVE
#           TOGETHER -- `%s%s%s%s%s%s` to `%s%s%s%s%s` -- and nothing in the build
#           checks a vim_snprintf_safelen count.
#        3  the `[RO]` on the status line, in `win_redr_status()`: the name-padding
#           disjunct and the block that appends it.
#        4  `did_set_readonly()`, BY NAME and with the reason: it is the row's
#           callback and the row is its only other reference, but droplocal.py runs
#           in the same edit and would otherwise find it still reading `b_p_ro`.
#           Measured without it: `droplocal: b_p_ro still has 1 mentions after the
#           plumbing went`, which is the tool working.  The alternative is an inner
#           sweep; this is cheaper and honest.
#        5  the row, then `droplocal.py b_p_ro` -- three plumbing sites.
#
# WHAT THE SWEEP THEN FINDS: `SHM_RO`, `BV_FS`, `BV_RO`, the static string
# `w_readonly` inside change_warning(), the `b_did_warn` field -- which becomes dead
# only after BOTH change_warning and did_set_readonly have gone, so removing one and
# not the other leaves a field with one reader and one writer that no tool reports --
# and the six globals.
#
# THE FLAG LETTERS ARE NOT TOUCHED, AND THAT IS A DECISION.  `'cpoptions'` and
# `'shortmess'` each have a validity list that is a separate string literal from the
# value, so removing a letter from a list cannot move `:set cpo?` or `:set shm?`.
# But `:set shm=F` is accepted silently and `:set shm=y` answers E539, and dropping a
# letter from the list turns the first into the second -- a behaviour change no
# corpus case, Ex row, argv row or pty scenario can see, which is exactly what
# ZERO-GOAL.md rule 2 exists to prevent.  Accepting a letter that does nothing is
# what upstream does for every feature a build lacks.  Measured: 23 of 'cpoptions'
# 60 letters and 14 of 'shortmess' 23 are inert here, and THIS PHASE MAKES EXACTLY
# ONE MORE SO -- `'shortmess'`'s `r`, whose SHM_RO the sweep takes with the `[RO]`
# indicator.  The check asserts both literals character for character.
#
# THE INPUT BINARY IS BUILT HERE, before the edit, from the boundary's own makefile
# flags, as every zero edit since phase 2 does, and the source goes with it as
# $state/old.c.  The check needs both, and needs them more than any phase so far:
# THIS PHASE DECLARES NOTHING, because `:set` is the one thing zero's instrument
# cannot read, and the probes are the whole evidence.
set -eu

work=${1:?usage: zero12-edit.sh <work-dir> <state-dir>}
state=${2:?usage: zero12-edit.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"

# The flags are read out of the boundary's makefile rather than written here a
# second time: zero's compile line is the boundary's (ZERO-GOAL.md rule 8).
cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")
cp "$f" "$state/old.c"
# shellcheck disable=SC2086
( cd "$state" && gcc $cflags $ldflags -o old old.c ) &
pid_old=$!

python3 - "$f" <<'PY'
TAG = 'noopts'
import re, sys
sys.path.insert(0, 'tools')
import cutil
path = sys.argv[1]
t = open(path, errors='surrogateescape').read()


def die(msg):
    sys.exit('  %-12s %s' % (TAG, msg))


def say(what):
    print('  %-12s %s' % (TAG, what))


def mentions(text, name):
    return len(re.findall(r'\b%s\b' % name, text))


def text_edit(text, old, new, what, n=1):
    """An exact-text replacement, counted file-wide.  Never 'the first one'."""
    k = text.count(old)
    if k != n:
        die('%s -- the text occurs %d times, expected %d: %r'
            % (what, k, n, old[:70]))
    say(what)
    return text.replace(old, new)


# ---- 0. the shape every anchor below was counted against --------------------------
BEFORE = {'change_warning': 7,      # the definition and six calls; NO prototype
          'did_set_readonly': 3,    # prototype, the row's callback, definition
          'b_p_ro': 10, 'b_p_fs': 7, 'b_did_warn': 4,
          'p_ro': 2, 'p_fs': 2, 'p_ur': 2, 'p_write': 2, 'p_wa': 2, 'p_prompt': 2,
          'p_mod': 2, 'did_set_modified': 3,       # 'modified' STAYS: decision 5
          'SHM_RO': 2, 'BV_RO': 3, 'BV_FS': 4, 'w_readonly': 2,
          'p_paste': 12,            # the exemption, before and after
          'read_cmd_fd': 12,        # the terminal's
          'vim_fsync': 3, 'scriptin': 8, 'redir_fd': 6}   # the FILE* phase's
for name in ('p_ai_nopaste', 'p_et_nopaste', 'p_sts_nopaste', 'p_tw_nopaste',
             'p_wm_nopaste'):
    BEFORE[name] = 4
for name, want in sorted(BEFORE.items()):
    k = mentions(t, name)
    if k != want:
        die('%s has %d mentions, expected %d -- the anchors below were counted '
            'against a different file' % (name, k, want))
say('change_warning 7 (a definition and six calls, and no prototype), '
    'did_set_readonly 3, b_p_ro 10, b_p_fs 7 -- the file the five edits of part C '
    'were counted against')

# ---- 1. WHICH ROWS HAVE NO READER, COMPUTED --------------------------------------
# `dropoptions --strict`'s own test, run here over EVERY row, so that the six
# this phase drops are a chosen subset of a computed set and not a list.  The
# exclusions are that tool's and for its reasons: another row of options[] is not a
# read, nor is the row's own `var` field, nor the variable's declaration -- which is
# what the row initialises -- nor taking the address, which asks which option a
# pointer refers to and never touches the value.
i = t.find('static struct vimoption options[]')
if i < 0:
    die('options[] is not in this file')
j = t.index('\n};', i)
b = cutil.blank(t)
rows = []
for m in re.finditer(r'^[ \t]*\{"([a-z]+)",', t[i:j], re.M):
    start = i + m.start()
    end = cutil.match(t, t.index('{', start), b)
    if end < 0:
        die('the options[] row for %r is not balanced' % m.group(1))
    rows.append((m.group(1), start, end))
if len(rows) != 114:
    die('options[] has %d rows, expected 114 -- the table has moved under this '
        'phase' % len(rows))

unread = {}
for name, start, end in rows:
    var = re.search(r'\(char_u \*\)&(\w+)', t[start:end])
    if not var:
        continue                      # a row with no global of its own
    v = var.group(1)
    for h in re.finditer(r'\b%s\b' % v, t):
        o = h.start()
        if start <= o <= end:
            continue
        line = t[t.rfind('\n', 0, o) + 1:t.index('\n', o)]
        if (re.match(r'[ \t]*\{"', line) or re.match(r'[ \t]*\(char_u \*\)&', line)
                or re.match(r'static\b[^=]*\b%s;$' % re.escape(v), line)):
            continue
        bare = re.sub(r'&\s*%s\b' % re.escape(v), '', line)
        if not re.search(r'\b%s\b' % re.escape(v), bare):
            continue
        break
    else:
        unread[name] = (v, (re.search(r'PV_\w+', t[start:end]) or
                            re.match('', '')).group(0) if re.search(r'PV_\w+', t[start:end]) else 'PV_NONE')

WANT = {'fsync': 'PV_BOTH', 'modified': 'PV_BUF', 'prompt': 'PV_NONE',
        'readonly': 'PV_BUF', 'undoreload': 'PV_NONE', 'write': 'PV_NONE',
        'writeany': 'PV_NONE'}
got = {k: v[1] for k, v in unread.items()}
if got != WANT:
    die('the rows with no reader are %s, expected exactly %s -- the six this phase '
        'drops are a chosen subset of that computed set, so a different set means '
        'the choice was made against a different file'
        % (' '.join('%s(%s)' % kv for kv in sorted(got.items())),
           ' '.join('%s(%s)' % kv for kv in sorted(WANT.items()))))
say('seven of the 114 rows have no reader of their own global, computed with '
    "dropoptions --strict's own test: fsync modified prompt readonly undoreload "
    'write writeany')
say("and 'modified' is the one that STAYS -- ZERO-PLAN.md decision 5: the state it "
    'reports lives in b_changed and not in p_mod, so the row is not a lie.  A '
    'computation that took "no reader" as the criterion would delete it')

# THE EXEMPTION, ASSERTED RATHER THAN ONLY WRITTEN DOWN.  'paste' is exempt for ever
# (ZERO-PLAN.md 2d and decision 8, the user's standing promise), and so is
# `+{command}`.  p_paste has a reader, so the computation above does not offer it --
# but the next person to widen that computation must meet this line.
if 'paste' in unread or 'paste' in WANT:
    die("'paste' came out of the computation with no reader, and it is EXEMPT FOR "
        'EVER (ZERO-PLAN.md 2d): nothing in this pipeline may drop it')
say("'paste' is exempt for ever and is not in the set: p_paste 12 mentions, and its "
    'five save slots p_ai_nopaste p_et_nopaste p_sts_nopaste p_tw_nopaste '
    'p_wm_nopaste are the non-pointer orphans orphanopts.py reports and tolerates, '
    'here and afterwards, identically')

# ---- C1. the W10 warning ------------------------------------------------------------
# change_warning() is 'readonly''s only real behaviour: it prints W10 and pauses a
# second the first time a read-only buffer is changed.  Six call sites, each one
# statement on a line of its own, counted; then the definition, which takes the
# static string w_readonly and the ui_delay(1002L) with it.
calls = re.findall(r'^[ \t]*change_warning\([^;]*\);\n', t, re.M)
if len(calls) != 6:
    die('change_warning has %d call sites, expected 6' % len(calls))
t = re.sub(r'^[ \t]*change_warning\([^;]*\);\n', '', t, flags=re.M)
t, removed = cutil.delete_definition(t, 'change_warning')
if not removed:
    die('change_warning has no definition to remove')
if mentions(t, 'change_warning'):
    die('change_warning still has %d mentions; it has no prototype, so six calls '
        'and a definition is all of it' % mentions(t, 'change_warning'))
say('the W10 warning: six calls to change_warning() and the definition, which takes '
    'the static string w_readonly and the ui_delay(1002L, TRUE) with it -- ZERO-GOAL '
    "phase 2 named that as one of the eight other pauses.  It has NO prototype, so a "
    'program that removed one would fail here')

# ---- C2. the [RO] in fileinfo() -----------------------------------------------------
# THE FORMAT STRING AND THE ARGUMENT MOVE TOGETHER.  Nothing in the build checks a
# vim_snprintf_safelen argument count, so the two edits are one step and are counted
# against each other.
t = text_edit(t, '"\\"%s%s%s%s%s%s", curbufIsChanged()',
              '"\\"%s%s%s%s%s", curbufIsChanged()',
              "fileinfo's CTRL-G line loses one %s, and the argument below goes with "
              'it in the same step -- nothing in the build checks the count')
t = text_edit(t,
              'curbuf->b_p_ro ? (shortmess(SHM_RO) ? _("[RO]") : _("[readonly]")) : "", ',
              '',
              'the [RO]/[readonly] argument itself, which is SHM_RO\'s only reader')
t = text_edit(t, ' || curbuf->b_p_ro) ? " " : "");', ') ? " " : "");',
              "and the trailing-space test's `|| curbuf->b_p_ro` disjunct")

# ---- C3. the [RO] on the status line -------------------------------------------------
t = text_edit(t, ' || wp->w_buffer->b_p_ro) && plen <  PATH_MAX  - 1)',
              ') && plen <  PATH_MAX  - 1)',
              "win_redr_status: the name-padding test's `|| b_p_ro` disjunct")
t = text_edit(t,
              '        if (wp->w_buffer->b_p_ro)\n'
              '        {\n'
              '            plen += vim_snprintf((char *)p + plen,  PATH_MAX  - plen, "%s", _("[RO]"));\n'
              '        }\n',
              '',
              'and the block that appended [RO] to it -- nothing else reaches that '
              'indicator')

# ---- C4. did_set_readonly, by name and with the reason -------------------------------
# It is the row's callback and the row is its only other reference, so the sweep
# would take it -- but droplocal.py runs in this same edit and would find it still
# reading b_p_ro.  Measured without this: `droplocal: b_p_ro still has 1 mentions
# after the plumbing went`, which is the tool working.  The alternative is an inner
# sweep; this is cheaper and honest.
t = text_edit(t, 'static char *did_set_readonly(optset_T *args);\n', '',
              "did_set_readonly's prototype")
t, removed = cutil.delete_definition(t, 'did_set_readonly')
if not removed:
    die('did_set_readonly has no definition to remove')
if mentions(t, 'did_set_readonly') != 1:
    die('did_set_readonly has %d mentions, expected 1 -- the row that names it as '
        'its callback, which part C5 removes' % mentions(t, 'did_set_readonly'))
say("did_set_readonly, BY NAME: it is 'readonly''s callback and the sweep would take "
    'it, but droplocal.py runs in this same edit and would find it still reading '
    'b_p_ro -- measured, that refusal is the tool working')
if mentions(t, 'b_p_ro') != 3:
    die('b_p_ro has %d mentions, expected 3 -- the field, buf_copy_options\' write, '
        "and get_varp's case" % mentions(t, 'b_p_ro'))
say('b_p_ro 10 -> 3, and the three that are left are plumbing: the field, '
    "buf_copy_options' write and get_varp's case.  droplocal.py is what takes those")

open(path, 'w', errors='surrogateescape').write(t)
PY

# ---- A. the four clean rows ----------------------------------------------------------
# --strict is the guard: it refuses a row while anything still reads its global,
# because the row is what INITIALISES that global.  The sweep takes the four
# variables afterwards as -Wunused-variable.
tools/st.sh dropoptions "$f" --strict prompt undoreload write writeany

# ---- B. 'fsync', where --strict alone is NOT the guard --------------------------------
# The row is PV_BOTH + PV_BUF + BV_FS, so dropoptions stops on the PV_ guard before
# the reader test is ever reached, and its message talks about a segfault at startup
# rather than about readers.  droplocal.py is the other half and goes first.
tools/st.sh droplocal "$f" b_p_fs
tools/st.sh dropoptions "$f" --strict --local fsync

# ---- C5. 'readonly': the row, then the field -------------------------------------------
tools/st.sh dropoptions "$f" --strict --local readonly
tools/st.sh droplocal "$f" b_p_ro

python3 - "$f" <<'PY'
TAG = 'noopts'
import re, sys
path = sys.argv[1]
t = open(path, errors='surrogateescape').read()


def die(msg):
    sys.exit('  %-12s %s' % (TAG, msg))


def mentions(name):
    return len(re.findall(r'\b%s\b' % name, t))


# ---- what the sweep is handed, as a count rather than as trust -------------------------
# The six globals are declared and unread now, so -Wunused-variable takes them; SHM_RO,
# BV_RO and BV_FS have no reader left and deadenums takes them; b_did_warn is a field
# nothing names and deadfields takes it -- and it reaches that state only because BOTH
# change_warning and did_set_readonly have gone.
AFTER = {'b_p_ro': 0, 'b_p_fs': 0, 'change_warning': 0, 'did_set_readonly': 0,
         'p_ro': 1, 'p_fs': 1, 'p_ur': 1, 'p_write': 1, 'p_wa': 1, 'p_prompt': 1,
         'b_did_warn': 1,          # the field alone: deadfields.py's
         'p_mod': 2, 'did_set_modified': 3,        # 'modified' is untouched
         'p_paste': 12,
         'read_cmd_fd': 12, 'vim_fsync': 3, 'scriptin': 8, 'redir_fd': 6}
for name in ('p_ai_nopaste', 'p_et_nopaste', 'p_sts_nopaste', 'p_tw_nopaste',
             'p_wm_nopaste'):
    AFTER[name] = 4
for name, want in sorted(AFTER.items()):
    k = mentions(name)
    if k != want:
        die('%s has %d mentions after the cut, expected %d' % (name, k, want))

i = t.find('static struct vimoption options[]')
j = t.index('\n};', i)
rows = re.findall(r'^[ \t]*\{"([a-z]+)",', t[i:j], re.M)
globals_ = set(re.findall(r'&(p_[a-z0-9_]+)\b', t[i:j]))
if len(rows) != 108 or len(globals_) != 96:
    die('options[] has %d rows and %d distinct globals, expected 108 and 96'
        % (len(rows), len(globals_)))
for gone in ('fsync', 'prompt', 'readonly', 'undoreload', 'write', 'writeany'):
    if gone in rows:
        die("the row for '%s' is still there" % gone)
if 'modified' not in rows or 'paste' not in rows:
    die("'modified' or 'paste' lost its row, and neither may")
print('  %-12s the cut is done: options[] 114 -> 108 rows and 102 -> 96 distinct '
      "globals; 'modified' and 'paste' keep theirs, b_did_warn is a field nothing "
      'names and the six globals are declared and unread -- all of it the sweep\'s '
      'now' % TAG)
PY

# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  noopts       the input binary did not build with '$cflags' '$ldflags'"; exit 1; }
echo "  noopts       the input is $state/old, $(stat -c%s "$state/old") bytes, beside the source it was built from: this phase declares nothing, because :set is the one thing zero's instrument cannot read, and the probes are the whole evidence"

# tools/phaserun.sh sweeps next, then runs pipes/zero12-check.sh.
