#!/bin/sh
# Whim phase 77 -- no buffer-name argument matching.  See WHIM-GOAL.md.
#
# Usage: pipes/whim77-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# do_one_cmd() computes, at 20635,
#
#     ni = (!(cmdidx < 0) && (cmd_func == ex_ni || cmd_func == ex_script_ni))
#
# -- "this command is not implemented" -- and SEVEN later checks consult it before
# doing work.  One does not: the EX_BUFNAME pre-dispatch block, guarded only by
# `!(cmdidx < 0)`, which compiles a regexp and matches it against the buffer to turn
# `:buffer foo` into a line number.
#
# Every command carrying EX_BUFNAME is ex_ni: :buffer, :bdelete, :bunload, :bwipeout,
# :checktime, :sbuffer.  So that block does real pattern-matching work for commands
# that cannot succeed, and its result is discarded when the handler errors.
#
# THE EDIT IS A FOLD, NOT A GUARD.  Adding `&& !ni` would leave a block that can
# still never run -- dead weight wearing a condition.  The condition is false for
# every command that reaches it, so fold_never removes it outright, and
# buflist_findpat loses its only caller.
#
# WHAT GOES BY CASCADE: buflist_findpat (71 lines), file_pat_to_reg_pat (167) and
# buflist_match (13) -- 251 lines whose whole purpose was naming a buffer by pattern.
# Nothing here deletes them by name; removing the one call site orphans them and the
# sweep takes them.
#
# THE BLOCK CONTAINS `goto doend;` AND THAT IS SAFE.  doend is do_one_cmd's shared
# exit label, targeted from many other places, so this removes a goto STATEMENT, not
# a label -- the distinction that mattered for readfile's `theend` in phase 75 and
# for close_buffer's `aucmd_abort`, where the label itself was inside the fold.
#
# THE DELTA: none expected.  `:buffer foo` already exits 1 with nothing on stderr --
# ex_ni sets eap->errmsg rather than printing, and an exsweep row is
# `exit= left= err=`.  Measured on q76: exit=1, stderr empty, file written.  So the
# gain here is code, not behaviour.  Declared empty, left for whimdelta.sh.
set -eu

work=${1:?usage: whim77-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

python3 - "$f" <<'PY'
TAG = 'nobufpat'
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

def fold_never(text, fn, pattern, what, n=1):
    def edit(s):
        try:
            return cutil.fold_never(s, pattern, n, re.M)
        except ValueError as e:
            die('%s -- %s' % (what, e))
    out = in_function(text, fn, edit)
    say(what)
    return out

# THE INVARIANT: every command that can reach this block is not-implemented.  If an
# upstream ever gives a LIVE handler to a command carrying EX_BUFNAME, the block
# becomes reachable again and this phase would be deleting a working feature.  Assert
# it rather than trust the survey.
rows = re.findall(r'\[CMD_[a-zA-Z]+\] = \{\(char_u \*\)"([a-zA-Z]+)", [^,]+, *([a-z_]+)[^}]*EX_BUFNAME', t)
if not rows:
    die('no command carries EX_BUFNAME -- the block this phase removes is already gone')
live = [name for name, fn in rows if fn not in ('ex_ni', 'ex_script_ni')]
if live:
    die('these EX_BUFNAME commands have a LIVE handler and still need the pattern '
        'matching: %s' % ' '.join(live))
say('confirmed: all %d EX_BUFNAME commands are ex_ni' % len(rows))

# and the block really is the one check that does not consult `ni`
if not re.search(r'^[ \t]*ni = \(! \(\(int\)\(ea\.cmdidx\) < 0\)  && \(cmdnames\[ea\.cmdidx\]\.cmd_func == ex_ni', t, re.M):
    die('`ni` is no longer computed as "the handler is ex_ni"')

# ---- the pre-dispatch matching ----------------------------------------------------
t = fold_never(t, 'do_one_cmd',
               r'^[ \t]*if \(\(ea\.argt & EX_BUFNAME\) && \*ea\.arg != NUL && ea\.addr_count == 0 && ! \(\(int\)\(ea\.cmdidx\) < 0\) \)$',
               'naming a buffer by pattern for commands that cannot run')

open(path, 'w', errors='surrogateescape').write(t)
PY

tools/st.sh cmdidxs "$f" --check >/dev/null

# tools/phaserun.sh sweeps next, then runs pipes/whim77-check.sh.
