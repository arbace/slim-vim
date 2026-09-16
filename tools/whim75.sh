#!/bin/sh
# Whim phase 75 -- no autocommands.  See WHIM-GOAL.md.
#
# Usage: tools/whim75.sh <work-dir>      (run from the repository root)
#
# PROVED BY ABSENCE, not inferred from the command table.  `first_autopat[NUM_EVENTS]
# = { NULL }` is the ONLY write to that array in the whole file -- every other mention
# reads it.  No autocommand pattern can ever be registered, so:
#
#   * apply_autocmds_group() is already `return FALSE;`
#   * apply_autocmds(), apply_autocmds_exarg() and apply_autocmds_retval() are
#     one-line wrappers onto it, so ALL ~74 dispatch sites are no-ops;
#   * has_cursormovedI/has_textchangedI/has_textchangedP each return
#     `first_autopat[...] != NULL`, i.e. always FALSE;
#   * au_cleanup, au_remove_pat, au_del_cmd and aubuflocal_remove walk a permanently
#     empty list.
#
# :autocmd, :augroup, :doautocmd, :doautoall and :noautocmd were already ex_ni, but
# that is the weaker argument; the array being write-once-to-NULL is the strong one.
#
# TWO SITES ARE REWRITTEN, NOT FOLDED, and both would have been silent damage:
#
#   * close_buffer() -- the label `aucmd_abort:` sits INSIDE the block guarded by
#     apply_autocmds(EVENT_BUFWINLEAVE, ...), and THREE gotos target it, two of them
#     from outside that block under `if (abort_if_last)`.  fold_never would delete
#     the label and orphan them.  This is the phase-71 break-rebinding hazard wearing
#     a label instead of a loop.  The abort arm is hoisted out and kept reachable.
#   * open_buffer() -- the aco block mixes the autocommand call with REAL work:
#     `curbuf->b_flags &= ~(BF_CHECK_RO | BF_NEVERLOADED)`.  Deleting it wholesale
#     would change behaviour.
#
# THE CLASSIFICATION WAS DONE BY HAND because a scan got two sites BACKWARDS.
# 7712 and 7741 read `if (!(did_cmd = apply_autocmds_exarg(...)))` -- negated with an
# embedded assignment -- so they are ALWAYS TRUE (fold_always), not always false.
# A `startswith("if (!apply_autocmds")` test misses the `!(var = ...)` shape, and
# folding them the other way would have deleted the branch that actually runs.
#
#   fold_never (condition always FALSE)   6327 6344 6416 6423 6768 27758 27768
#   fold_always (condition always TRUE)   6531 7712 7741
#   dies with its guard                   15497 15512 (has_textchanged*), 21638
#                                         (has_cmdundefined)
#   value consumed                        7725 (did_cmd), 18098 (ins_apply_autocmds
#                                         -> return FALSE), 86559 (drop the |= term)
#   bare statements                       60 lines, deleted
#
# WHAT GOES BY CASCADE: the EVENT_ enum (123 enumerators, 127 lines), event_tab
# (127 rows), event_nr2name, auto_next_pat, AutoPat, AutoCmd, AutoPatCmd_T,
# active_apc_list, first_autopat, last_autopat, au_need_clean, autocmd_blocked,
# aucmd_prepbuf, aucmd_restbuf and aco_save_T.  Nothing here deletes those by name.
#
# SCOPE NOTE: trigger_cmd_autocmd() comes out HERE rather than with the other empty
# functions, because its call sites pass EVENT_* constants that this phase removes.
# may_trigger_modechanged() takes no argument and waits for the combined phase.
#
# THE DELTA: none expected.  Nothing could fire an autocommand, so removing the
# dispatch cannot change what the editor does.  Declared empty, left for whimdelta.sh.
set -eu

work=${1:?usage: whim75.sh <work-dir>}
f="$work/whim-vim.c"

before_lines=$(grep -c '' "$f")
tools/symbols.sh "$f" .cache/symbols/before

python3 - "$f" <<'PY'
TAG = 'noautocmd'
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

def replace_body(text, name, new_body, what):
    def edit(s):
        return s[:s.index('{\n') + 2] + new_body + '}\n'
    out = in_function(text, name, edit)
    say(what)
    return out

def drop_def(text, name, what):
    out, ok = cutil.delete_definition(text, name)
    if not ok:
        die('%s -- %s is not defined' % (what, name))
    say(what)
    return out

def fold_never(text, fn, pattern, what, n=1):
    def edit(s):
        try:
            return cutil.fold_never(s, pattern, n, re.M)
        except ValueError as e:
            die('%s -- %s' % (what, e))
    out = in_function(text, fn, edit)
    say(what)
    return out

def fold_always(text, fn, pattern, what, n=1):
    def edit(s):
        try:
            return cutil.fold_always(s, pattern, n, re.M)
        except ValueError as e:
            die('%s -- %s' % (what, e))
    out = in_function(text, fn, edit)
    say(what)
    return out

def drop_block(text, fn, anchor_re, what, n=1):
    """Delete a brace-matched block anchored on the line that opens it."""
    def edit(s):
        rx = re.compile(anchor_re, re.M)
        k = len(rx.findall(s))
        if k != n:
            die('%s -- the anchor matches %d times, expected %d' % (what, k, n))
        out = s
        for _ in range(n):
            m = rx.search(out)
            b = cutil.blank(out)
            k0 = out.rfind('\n', 0, m.start()) + 1
            o = out.index('{', m.start())
            c = cutil.match(out, o, b)
            if c < 0:
                die('%s -- unbalanced block' % what)
            out = out[:k0] + out[out.index('\n', c) + 1:]
        say(what)
        return out
    return in_function(text, fn, edit)

# THE INVARIANT, asserted in the phase rather than trusted from the survey.  If an
# upstream ever registers a pattern again this fails loudly instead of silently
# deleting a working feature.
def writes_to(text, name):
    """Assignments TO `name` (or to an element of it), skipping the subscript.

    A first version of this matched `name[^\\n;]*=` and reported three writes that
    were the `!=` of the has_* predicates -- it spanned the subscript and landed on
    the comparison.  An assertion that cries wolf is worse than none, because the
    temptation is to loosen it until it passes.  This one steps over a balanced
    subscript and then looks at the operator that actually follows.
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

w = writes_to(t, 'first_autopat')
decl = len(re.findall(r'^static AutoPat \*first_autopat\[NUM_EVENTS\] = \{ NULL \};$', t, re.M))
if decl != 1:
    die('the first_autopat declaration is not where this phase expects it')
if len(w) != 1:
    die('first_autopat is assigned in %d place(s), not just its all-NULL initialiser '
        '(lines %s) -- an autocommand CAN be registered and this whole phase is wrong'
        % (len(w), ' '.join(str(n) for n in w)))
say('confirmed: first_autopat is only ever the all-NULL initialiser')

# ---- 1. close_buffer: hoist the abort arm, then fold both conditions -------------
# The label must outlive the block it sits in.
OLD_CB = '''    if ((win_valid || closed_popup) && win->w_buffer == buf && buf->b_nwindows == 1)
    {
        ++buf->b_locked;
        ++buf->b_locked_split;
        if (apply_autocmds(EVENT_BUFWINLEAVE, buf->b_fname, buf->b_fname, FALSE, buf) && !bufref_valid(&bufref))
        {
aucmd_abort:
            emsg(_(e_autocommands_caused_command_to_abort));
            return FALSE;
        }
        --buf->b_locked;
        --buf->b_locked_split;
        if (abort_if_last)
        {
            goto aucmd_abort;
        }

        if (!unload_buf)
        {
            ++buf->b_locked;
            ++buf->b_locked_split;
            if (apply_autocmds(EVENT_BUFHIDDEN, buf->b_fname, buf->b_fname, FALSE, buf) && !bufref_valid(&bufref))
            {
                goto aucmd_abort;
            }
            --buf->b_locked;
            --buf->b_locked_split;
            if (abort_if_last)
            {
                goto aucmd_abort;
            }
        }
        win_valid = win_valid && win_valid_any_tab(win);
    }
'''
NEW_CB = '''    if ((win_valid || closed_popup) && win->w_buffer == buf && buf->b_nwindows == 1)
    {
        if (abort_if_last)
        {
            emsg(_(e_autocommands_caused_command_to_abort));
            return FALSE;
        }
        win_valid = win_valid && win_valid_any_tab(win);
    }
'''
t = in_function(t, 'close_buffer', lambda s: literal(
    s, OLD_CB, NEW_CB, 'close_buffer, whose abort label three gotos still target'))

# ---- 2. the conditions that can never be true ------------------------------------
t = fold_never(t, 'buf_freeall', r'^[ \t]*if \(apply_autocmds\(EVENT_BUFUNLOAD,',
               'unloading a buffer asking the autocommands first')
t = fold_never(t, 'buf_freeall', r'^[ \t]*if \(apply_autocmds\(EVENT_BUFWIPEOUT,',
               'wiping a buffer asking them')
t = fold_never(t, 'buflist_new', r'^[ \t]*if \(apply_autocmds\(EVENT_BUFNEW,',
               'a new buffer announcing itself')
t = fold_never(t, 'readfile', r'^[ \t]*if \(apply_autocmds_exarg\(EVENT_BUFREADCMD,',
               'a read being handled by an autocommand instead')
t = fold_never(t, 'readfile', r'^[ \t]*else if \(apply_autocmds_exarg\(EVENT_FILEREADCMD,',
               'and the file-read variant of the same')

# ---- 3. the conditions that can never be false -----------------------------------
t = fold_always(t, 'set_curbuf', r'^[ \t]*if \(!apply_autocmds\(EVENT_BUFLEAVE,',
                'leaving a buffer asking permission')
# `if (!(did_cmd = apply_autocmds_exarg(...)))` -- ALWAYS TRUE.  A scan put these two
# in the fold_never bucket; folding them that way deletes the branch that runs.
t = fold_always(t, 'buf_write', r'^[ \t]*if \(!\(did_cmd = apply_autocmds_exarg\(EVENT_FILEAPPENDCMD,',
                'an autocommand taking over an append')
t = fold_always(t, 'buf_write', r'^[ \t]*if \(!\(did_cmd = apply_autocmds_exarg\(EVENT_FILEWRITECMD,',
                'an autocommand taking over a write')

# ---- 4. blocks that die with an always-FALSE guard --------------------------------
t = fold_never(t, 'ins_redraw', r'^[ \t]*if \(ready && has_textchangedI\(\)',
               'insert mode reporting a change')
t = fold_never(t, 'ins_redraw', r'^[ \t]*if \(ready && has_textchangedP\(\)',
               'and the popup-menu variant')
t = fold_never(t, 'do_one_cmd', r'^[ \t]*if \(p != NULL && ea\.cmdidx == CMD_SIZE && !ea\.skip && [^\n]*has_cmdundefined\(\)\)$',
               'an unknown command being defined by an autocommand')

# ---- 5. the values nobody can act on ----------------------------------------------
t = in_function(t, 'buf_write', lambda s: literal(s, '''            int was_changed = curbufIsChanged();

            did_cmd = apply_autocmds_exarg(EVENT_BUFWRITECMD, sfname, sfname, FALSE, curbuf, eap);
            if (did_cmd)
            {
                if (was_changed && !curbufIsChanged())
                {
                    u_unchanged(curbuf);
                    u_update_save_nr(curbuf);
                }
            }
            else
            {
                apply_autocmds_exarg(EVENT_BUFWRITEPRE, sfname, sfname, FALSE, curbuf, eap);
            }
''', '', 'an autocommand taking over the whole write'))
t = replace_body(t, 'ins_apply_autocmds', '    return FALSE;\n',
                 'ins_apply_autocmds, which dispatched and watched the tick')
t = in_function(t, 'ui_focus_change', lambda s: literal(
    s, '    need_redraw |= apply_autocmds(in_focus ? EVENT_FOCUSGAINED : EVENT_FOCUSLOST, NULL, NULL, FALSE, curbuf);\n\n',
    '', 'a focus change telling the autocommands'))

# ---- 6. the aco blocks: three die whole, one keeps its real work ------------------
t = in_function(t, 'open_buffer', lambda s: literal(s, '''    if (bufref_valid(&old_curbuf) && old_curbuf.br_buf->b_ml.ml_mfp != NULL)
    {
        aco_save_T      aco;

        aucmd_prepbuf(&aco, old_curbuf.br_buf);
        if (curbuf == old_curbuf.br_buf)
        {
            curbuf->b_flags &= ~(BF_CHECK_RO | BF_NEVERLOADED);

            if ((flags & READ_NOWINENTER) == 0)
            {
            apply_autocmds(EVENT_BUFWINENTER, NULL, NULL, FALSE, curbuf);
            }

            aucmd_restbuf(&aco);
        }
    }
''', '''    if (bufref_valid(&old_curbuf) && old_curbuf.br_buf->b_ml.ml_mfp != NULL)
    {
        curbuf->b_flags &= ~(BF_CHECK_RO | BF_NEVERLOADED);
    }
''', 'open_buffer, keeping the flag clearing the autocmd call was wrapped around'))

t = drop_block(t, 'buf_write', r'^[ \t]*if \(!got_int\)$',
               'the post-write announcements')

# The OTHER buf_write block is handled at the very END of this script, after the
# blanket dispatch removal -- see step 9.  Its shape depends on that removal having
# already run, which is the opposite of the ordering rule the rest of the file obeys.
t = drop_block(t, 'set_termname', r'^[ \t]*if \(curbuf->b_ml\.ml_mfp != NULL\)$',
               'a new terminal telling every buffer')

# ---- 7. the call sites the bare-dispatch regex could not see ----------------------
# SPECIFIC, LITERAL-ANCHORED EDITS RUN FIRST; the blanket regex runs last.  Getting
# that order wrong costs a run three ways, all of which this script did on a first
# reading: the blanket `apply_autocmds\w*\(` also matches apply_autocmds_retval, so
# it ate do_ecmd's two lines before they were counted; it deleted the
# apply_autocmds line out of the MIDDLE of getout's two literal blocks, so neither
# matched; and the has_cursormovedI block CONTAINS one of the six
# ins_apply_autocmds calls, so folding it first left five.
# CALL SITES ONLY.  A first version of this step deleted twenty DEFINITIONS and let
# the callers dangle -- gcc reported four implicit declarations and six "used but
# never defined", and deadenums crashed because the file no longer compiled.  The
# method that works, and that phases 71-74 used, is the other way round: remove what
# calls a thing, and let sweep.sh's funcreach/deadprotos delete the orphan.

# ins_apply_autocmds is invisible to the bare-dispatch regex: that anchors on a line
# STARTING with apply_autocmds, and these start with `ins_`.  COUNTED BEFORE the
# has_cursormovedI fold below, because that block contains one of the six.
t = lines(t, r'ins_apply_autocmds\(EVENT_[A-Z]+\);', 'the insert-mode dispatches', 6)

# the has_cursormovedI block -- the one has_* guard missed on the first pass, which
# is what left a live caller behind after the definitions had been deleted.
t = fold_never(t, 'ins_redraw', r'^[ \t]*if \(ready && \(has_cursormovedI\(\)\)',
               'insert mode reporting the cursor moved')

t = in_function(t, 'free_buffer', lambda s: lines(
    s, r'aubuflocal_remove\(buf\);', 'a freed buffer detaching its buffer-local patterns'))

# getout blocks autocommands around its two exit events.  Only THESE two pairs go:
# block_autocmds/unblock_autocmds keep four other callers -- set_string_option_direct_in_win,
# u_undoredo and win_alloc -- that have nothing to do with autocommands, so both
# functions survive this phase.
for ev in ('VIMLEAVEPRE', 'VIMLEAVE'):
    t = in_function(t, 'getout', lambda s, e=ev: literal(s, '''        if (is_autocmd_blocked())
        {
            unblock_autocmds();
            ++unblock;
        }
        apply_autocmds(EVENT_%s, NULL, NULL, FALSE, curbuf);
        if (unblock)
        {
            block_autocmds();
        }
''' % e, '', 'quitting unblocking autocommands to announce EVENT_%s' % e))

# do_one_cmd asks whether the line source IS the autocommand reader.  This is a
# FUNCTION-POINTER COMPARISON, not a call, so deleting a line would be wrong: with no
# autocommands getline_equal(..., getnextac) is always false, so `!it` is always true.
t = in_function(t, 'do_one_cmd', lambda s: literal(
    s, '    if (quitmore && !getline_equal(fgetline, cookie, getnextac))\n',
    '    if (quitmore)\n', 'asking whether the command came from an autocommand'))

# What the removals leave set-but-never-read.  gcc reports these as
# -Wunused-but-set-variable, which deadsweep.py does not handle -- it knows
# unused-variable and unused-function and nothing else -- so they are removed here.
t = in_function(t, 'getcmdline_int', lambda s: lines(s, r'int[ \t]+cmdline_type;', 'the command-line type'))
t = in_function(t, 'getcmdline_int', lambda s: lines(
    s, r"cmdline_type = firstc == NUL \? '-' : firstc;", 'and the line that set it'))
# set_termname's husk is handled in step 9 for the same reason as buf_write's
# scaffold: it only takes that shape once step 8 has deleted the apply_autocmds line
# from inside it.

# ---- 8. every remaining bare dispatch, last of all --------------------------------
# This also sweeps up do_ecmd's two apply_autocmds_retval lines: `apply_autocmds\w*`
# matches the _retval suffix too, which is why they are not handled separately above.
n = len(re.findall(r'^[ \t]*(?:\(void\))?apply_autocmds\w*\([^\n]*\);[ \t]*\n', t, re.M))
t = re.sub(r'^[ \t]*(?:\(void\))?apply_autocmds\w*\([^\n]*\);[ \t]*\n', '', t, flags=re.M)
say('every remaining bare dispatch (%d)' % n)
n = len(re.findall(r'^[ \t]*trigger_cmd_autocmd\([^\n]*\);[ \t]*\n', t, re.M))
t = re.sub(r'^[ \t]*trigger_cmd_autocmd\([^\n]*\);[ \t]*\n', '', t, flags=re.M)
say('the command-line triggers (%d)' % n)

# ---- 9. the buf_write scaffold, which only now has the shape to match -------------
# THE ONE EDIT THAT MUST COME AFTER THE BLANKET REGEX, and the one place in this
# phase where deleting the obvious thing would have been silent damage.
#
# The block LOOKS like pure autocommand scaffolding -- aco_save_T, aucmd_prepbuf and
# aucmd_restbuf, set_bufref, did_cmd -- but buf_ffname, buf_sfname, buf_fname_f and
# buf_fname_s are computed inside it and READ a hundred lines later to restore
# ffname/sfname/fname from the buffer.  Deleting the 132-line block wholesale would
# break `:w` on a buffer whose name changed.  The scaffolding goes; the flags stay.
#
# And its four `if (append) { } else if (filtering) { } ...` arms are only EMPTY once
# step 8 has deleted the bare apply_autocmds_exarg lines inside them -- so this
# literal cannot match any earlier.  A pre-flight against an already-swept tree
# confirms the shape while saying nothing about when it becomes valid.
t = in_function(t, 'buf_write', lambda s: literal(s, '''        aucmd_prepbuf(&aco, buf);
        if (curbuf != buf)
        {
            return FAIL;
        }

        set_bufref(&bufref, buf);

        if (append)
        {
        }
        else if (filtering)
        {
        }
        else if (reset_changed && whole)
        {
        }
        else
        {
        }

        aucmd_restbuf(&aco);

        if (!bufref_valid(&bufref))
        {
            buf = NULL;
        }
''', '', 'buf_write bracketing the write with an autocommand buffer swap'))
t = in_function(t, 'buf_write', lambda s: lines(s, r'aco_save_T[ \t]+aco;', 'its saved window'))
t = in_function(t, 'buf_write', lambda s: lines(s, r'bufref_T[ \t]+bufref;', 'its buffer reference'))

# did_cmd HAS TWO READERS OUTSIDE THE SCAFFOLD, and they must be folded BEFORE the
# declaration goes -- removing the declaration first leaves them undeclared, which is
# exactly the compile error a first version of this produced.  The flag is now
# permanently FALSE: nothing can set it once the autocommand takeover arms are gone.
t = in_function(t, 'buf_write', lambda s: literal(
    s, '        if (buf == NULL || (buf->b_ml.ml_mfp == NULL && !empty_memline) || did_cmd)\n',
    '        if (buf == NULL || (buf->b_ml.ml_mfp == NULL && !empty_memline))\n',
    'the write asking whether an autocommand had taken over'))
t = fold_never(t, 'buf_write', r'^[ \t]*if \(did_cmd\)$',
               'and the arm only an autocommand-driven write could reach')
t = in_function(t, 'buf_write', lambda s: lines(s, r'int[ \t]+did_cmd = FALSE;', 'and the flag no autocommand can set'))

# Same dependency, same place: this husk is only empty once step 8 removed the
# apply_autocmds line from inside the block step 6 had already stripped.
#
# BRACE-MATCHED, NOT A LITERAL.  A literal was tried and failed twice, because it was
# transcribed from a POST-SWEEP tree where deadsweep had already dropped the
# now-unused `aco_save_T aco;`.  The python here runs BEFORE sweep.sh, so that
# declaration is still present -- and the next phase that leaves a different
# declaration behind would break the literal again.  Keying on the one statement that
# is certainly there survives all of that.
def drop_bare_block(text, fn, stmt, what):
    def edit(s):
        b = cutil.blank(s)
        i = s.find(stmt)
        if i < 0:
            die('%s -- %r is not in %s' % (what, stmt, fn))
        # walk back to the innermost enclosing '{'
        depth = 0
        j = i
        while j >= 0:
            if b[j] == '}':
                depth += 1
            elif b[j] == '{':
                if depth == 0:
                    break
                depth -= 1
            j -= 1
        if j < 0:
            die('%s -- no enclosing block' % what)
        c = cutil.match(s, j, b)
        if c < 0:
            die('%s -- unbalanced block' % what)
        body = s[s.index('\n', j) + 1:s.rfind('\n', 0, c) + 1]
        for line in body.split('\n'):
            line = line.strip()
            if not line:
                continue
            if line == stmt:
                continue
            if re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*[ \t]+\*?[A-Za-z_][A-Za-z0-9_]*;', line):
                continue
            die('%s -- the block still does real work: %r' % (what, line[:60]))
        k = s.rfind('\n', 0, j) + 1
        say(what)
        return s[:k] + s[s.index('\n', c) + 1:]
    return in_function(text, fn, edit)

t = drop_bare_block(t, 'set_termname', 'buf = curbuf;',
                    'the husk the terminal notification left behind')

open(path, 'w', errors='surrogateescape').write(t)
PY

python3 tools/create_cmdidxs.py "$f" --check >/dev/null

tools/sweep.sh "$f"

# The dispatch layer is gone, root and branch.
for g in apply_autocmds apply_autocmds_exarg apply_autocmds_retval apply_autocmds_group \
         aucmd_prepbuf aucmd_restbuf aco_save_T aubuflocal_remove au_cleanup \
         au_remove_pat au_del_cmd event_nr2name auto_next_pat getnextac first_autopat \
         last_autopat AutoPat AutoCmd AutoPatCmd_T active_apc_list au_need_clean \
         is_autocmd_blocked \
         has_cursormovedI has_textchangedI has_textchangedP trigger_cmd_autocmd \
         ins_apply_autocmds event_tab EVENT_BUFENTER NUM_EVENTS; do
    n=$(grep -cE -- "\\b$g\\b" "$f" || true)
    [ "$n" = 0 ] || { echo "  noautocmd    $g still has $n mentions"; exit 1; }
done
# block_autocmds/unblock_autocmds SURVIVE: four caller pairs outside getout --
# set_string_option_direct_in_win, u_undoredo and win_alloc -- are not autocommand
# code.  Asserting they reach zero would fail the phase on its own terms.
for g in block_autocmds unblock_autocmds; do
    grep -qE "\\b$g\\b" "$f" || { echo "  noautocmd    $g went -- it has callers that are not autocommand code"; exit 1; }
done
# ...and so `autocmd_blocked` survives with them, now WRITE-ONLY: ++ in one, -- in the
# other, and is_autocmd_blocked (its only reader) gone.  That is the can_cindent shape
# again, and it belongs to the combined write-only-counter phase, not here.  Listing
# it among the must-reach-zero names would contradict the decision above.
n=$(grep -cE -- '\bautocmd_blocked\b' "$f" || true)
[ "$n" = 3 ] || { echo "  noautocmd    autocmd_blocked has $n mentions, expected 3 (declaration and the ++/-- pair)"; exit 1; }
grep -qE '\bis_autocmd_blocked\b' "$f" && { echo "  noautocmd    autocmd_blocked still has a reader"; exit 1; }
# close_buffer's abort ARM survives; the LABEL does not, and that is deliberate.
# All three `goto aucmd_abort` sat in conditions that fold away, so keeping the label
# would leave it unused -- gcc says "label defined but not used", which the sweep
# does not remove.  The abort is now reached directly by `if (abort_if_last)`.
awk '/^close_buffer\(/,/^\}$/' "$f" | grep -qE 'aucmd_abort' && { echo "  noautocmd    close_buffer still has an orphaned abort label"; exit 1; }
awk '/^close_buffer\(/,/^\}$/' "$f" | grep -qE 'e_autocommands_caused_command_to_abort' || { echo "  noautocmd    close_buffer lost its abort_if_last arm"; exit 1; }
# the write path keeps the four flags the scaffolding was wrapped around
awk '/^buf_write\(/,/^\}$/' "$f" | grep -qE '\bbuf_ffname\b' || { echo "  noautocmd    buf_write lost buf_ffname -- :w on a renamed buffer would break"; exit 1; }
awk '/^buf_write\(/,/^\}$/' "$f" | grep -qE '\bbuf_fname_s\b' || { echo "  noautocmd    buf_write lost buf_fname_s"; exit 1; }
# What must survive: the real work the autocmd calls were wrapped around.
awk '/^open_buffer\(/,/^\}$/' "$f" | grep -qE 'BF_CHECK_RO \| BF_NEVERLOADED' || { echo "  noautocmd    open_buffer lost its flag clearing"; exit 1; }
for g in close_buffer buf_freeall buf_write readfile set_curbuf buflist_new open_buffer \
         ins_redraw getout do_one_cmd set_termname u_save curbufIsChanged; do
    grep -qE "\\b$g\\b" "$f" || { echo "  noautocmd    $g went -- that was never the autocommand layer"; exit 1; }
done
echo "  noautocmd    no autocommands; the work they were wrapped around is intact"

tools/phasecheck.sh "$work" "$f" .cache/symbols/before

tools/phasebuild.sh "$work" "$before_lines"

d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT
cp "$work/whim-vim" "$d/vim"

# EVERY PROBE BELOW WAS CALIBRATED AGAINST q74 AND PASSES THERE.  A :%!sort probe was
# written first and DISCARDED: `!` was retired in phase 64, so it fails on the
# baseline too and would have measured nothing.  That is the fourth probe in this run
# that could not do what it looked like it did.
printf 'a\nb\nc\n' > "$d/t.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+$' '+s/^/LAST /' '+wq' t.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/t.txt")" = 'a|b|LAST c|' ] || { echo "  noautocmd    the file did not load: '$(tr '\n' '|' < "$d/t.txt")'"; exit 1; }

printf 'w1\nw2\n' > "$d/w.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+1' '+normal! A-w' '+wq' w.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/w.txt")" = 'w1-w|w2|' ] || { echo "  noautocmd    writing broke: '$(tr '\n' '|' < "$d/w.txt")'"; exit 1; }

# :w to another name -- the buf_write path whose whole announcement block was removed
printf 'x1\n' > "$d/src.txt"; rm -f "$d/dst.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+w dst.txt' '+q!' src.txt </dev/null >/dev/null 2>&1) || true
[ "$(cat "$d/dst.txt" 2>/dev/null)" = 'x1' ] || { echo "  noautocmd    :w to another name broke: $(cat "$d/dst.txt" 2>/dev/null)"; exit 1; }

printf 'e1\n' > "$d/e1.txt"; printf 'e2\n' > "$d/e2.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+e e2.txt' '+normal! A-E' '+wq' e1.txt </dev/null >/dev/null 2>&1) || true
[ "$(cat "$d/e1.txt")" = 'e1' ] || { echo "  noautocmd    :e wrote over the first file: $(cat "$d/e1.txt")"; exit 1; }
[ "$(cat "$d/e2.txt")" = 'e2-E' ] || { echo "  noautocmd    :e did not load the second file: $(cat "$d/e2.txt")"; exit 1; }

printf 'keep1\ndrop\nkeep2\n' > "$d/g.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+g/drop/d' '+wq' g.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/g.txt")" = 'keep1|keep2|' ] || { echo "  noautocmd    :g broke: '$(tr '\n' '|' < "$d/g.txt")'"; exit 1; }

printf 's1\ns2\n' > "$d/s.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+%s/^s/S/' '+wq' s.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/s.txt")" = 'S1|S2|' ] || { echo "  noautocmd    :s broke: '$(tr '\n' '|' < "$d/s.txt")'"; exit 1; }

printf 'm1\nm2\nm3\n' > "$d/m.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+1m$' '+wq' m.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/m.txt")" = 'm2|m3|m1|' ] || { echo "  noautocmd    :m broke: '$(tr '\n' '|' < "$d/m.txt")'"; exit 1; }

# undo -- the ins_redraw blocks that folded away carried u_save calls
printf 'u1\nu2\n' > "$d/u.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+1' '+normal! dd' '+normal! u' '+wq' u.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/u.txt")" = 'u1|u2|' ] || { echo "  noautocmd    undo broke: '$(tr '\n' '|' < "$d/u.txt")'"; exit 1; }

# insert-mode editing, which ran through ins_apply_autocmds on every change
printf 'i1\n' > "$d/i.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+normal! A-ins' '+wq' i.txt </dev/null >/dev/null 2>&1) || true
[ "$(cat "$d/i.txt")" = 'i1-ins' ] || { echo "  noautocmd    insert-mode editing broke: $(cat "$d/i.txt")"; exit 1; }
echo "  noautocmd    loads, writes, :w name, :e, :g, :s, :m, undo and insert all work"
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
