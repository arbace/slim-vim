#!/bin/sh
# Whim phase 77 -- no buffer-name argument matching.  See WHIM-GOAL.md.
#
# Usage: tools/whim77.sh <work-dir>      (run from the repository root)
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

work=${1:?usage: whim77.sh <work-dir>}
f="$work/whim-vim.c"

before_lines=$(grep -c '' "$f")
tools/symbols.sh "$f" .cache/symbols/before

python3 - "$f" <<'PY'
TAG = 'nobufpat'
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

python3 tools/create_cmdidxs.py "$f" --check >/dev/null

tools/sweep.sh "$f"

# The matching and everything that existed only to serve it are gone.
for g in buflist_findpat file_pat_to_reg_pat buflist_match; do
    n=$(grep -cE -- "\\b$g\\b" "$f" || true)
    [ "$n" = 0 ] || { echo "  nobufpat     $g still has $n mentions"; exit 1; }
done
# EX_BUFNAME itself stays: the rows still carry the flag, and the count check at the
# top of do_one_cmd still reads it.  Removing a flag from cmdnames[] rows would be a
# table edit, which is a different and riskier thing.
grep -qE '\bEX_BUFNAME\b' "$f" || { echo "  nobufpat     EX_BUFNAME went -- the rows and the count check still name it"; exit 1; }
# `ni` and the seven checks that consult it must be untouched.
grep -qE '^[ \t]*ni = \(! \(\(int\)\(ea\.cmdidx\) < 0\)' "$f" || { echo "  nobufpat     do_one_cmd no longer computes ni"; exit 1; }
n=$(grep -cE '!ni\b' "$f" || true)
[ "$n" -ge 7 ] || { echo "  nobufpat     only $n checks still consult ni, expected at least 7"; exit 1; }
# doend is a shared label: the goto inside the block went, the label must not have.
awk '/^do_one_cmd\(/,/^\}$/' "$f" | grep -qE '^doend:$' || { echo "  nobufpat     do_one_cmd lost its shared exit label"; exit 1; }
g=$(awk '/^do_one_cmd\(/,/^\}$/' "$f" | grep -cE 'goto doend;' || true)
[ "$g" -ge 5 ] || { echo "  nobufpat     only $g gotos target doend, expected many -- the label may have been orphaned"; exit 1; }
# and the Ex dispatcher itself must still work
for g in do_one_cmd find_ex_command ex_ni cmdnames; do
    grep -qE "\\b$g\\b" "$f" || { echo "  nobufpat     $g went -- the Ex dispatcher still needs it"; exit 1; }
done
echo "  nobufpat     no buffer-name matching; ni, EX_BUFNAME and the doend label intact"

tools/phasecheck.sh "$work" "$f" .cache/symbols/before

tools/phasebuild.sh "$work" "$before_lines"

d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT
cp "$work/whim-vim" "$d/vim"

# `:buffer nosuchname` is NOT a discriminator and is not used as one: measured on q76
# it exits 1 with nothing on stderr and the file written either way, because ex_ni
# sets eap->errmsg rather than printing.  A probe on it would prove nothing.  These
# exercise what SURVIVES, and all three were calibrated against q76 first.
printf 'a\nb\nc\n' > "$d/t.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+$' '+s/^/LAST /' '+wq' t.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/t.txt")" = 'a|b|LAST c|' ] || { echo "  nobufpat     the file did not load: '$(tr '\n' '|' < "$d/t.txt")'"; exit 1; }

printf 'p1\np2\n' > "$d/w.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+1' '+normal! A-w' '+wq' w.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/w.txt")" = 'p1-w|p2|' ] || { echo "  nobufpat     writing broke: '$(tr '\n' '|' < "$d/w.txt")'"; exit 1; }

# :e still names a file -- the path that DOES take a file argument, next to the one removed
printf 'e1\n' > "$d/e1.txt"; printf 'e2\n' > "$d/e2.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+e e2.txt' '+normal! A-E' '+wq' e1.txt </dev/null >/dev/null 2>&1) || true
[ "$(cat "$d/e1.txt")" = 'e1' ] || { echo "  nobufpat     :e wrote over the first file: $(cat "$d/e1.txt")"; exit 1; }
[ "$(cat "$d/e2.txt")" = 'e2-E' ] || { echo "  nobufpat     :e did not load the second file: $(cat "$d/e2.txt")"; exit 1; }

# a command with a range and an argument, so the argument parsing around the removed
# block still works
printf 'k1\ndrop\nk2\n' > "$d/g.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+g/drop/d' '+wq' g.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/g.txt")" = 'k1|k2|' ] || { echo "  nobufpat     :g broke: '$(tr '\n' '|' < "$d/g.txt")'"; exit 1; }

# and a retired EX_BUFNAME command must still be refused rather than crash
printf 'z\n' > "$d/z.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+buffer nosuchname' '+normal! A-ok' '+wq' z.txt </dev/null >/dev/null 2>&1) || true
[ "$(cat "$d/z.txt")" = 'z-ok' ] || { echo "  nobufpat     :buffer with a name broke the session: $(cat "$d/z.txt")"; exit 1; }
echo "  nobufpat     loads, writes, :e names a file, :g takes a pattern, :buffer still refused"

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
