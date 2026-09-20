#!/bin/sh
# Whim phase 70 -- :e reloads in place, and there is no swap file.  See WHIM-GOAL.md.
#
# Usage: pipes/whim70-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# THIS INVARIANT IS IMPOSED, NOT PROVED, and that is the difference between it and
# phase 68.  One window fell out of the two places a window could be created.  A
# second BUFFER is genuinely reachable: curbuf_reusable() wants an unnamed, empty
# buffer, so once the first file is named, `:e other` allocates a new buf_T and
# switches to it.  Measured on q69: `:e h2.txt` then `+wq h1.txt` writes h2.
#
# So do_ecmd() is made to reuse the one buffer:
#
#   * the other_file branch renames curbuf with setfname() instead of calling
#     buflist_new(), sets oldbuf = FALSE, and falls through;
#   * the reload path below it -- u_sync(), u_savecommon(), buf_freeall(curbuf,
#     BFA_KEEP_UNDO), then open_buffer(... READ_KEEP_UNDO) -- ALREADY IS "wipe and
#     re-read in place".  Its gate widens from `!other_file && !oldbuf` to `!oldbuf`;
#   * the whole `if (buf != curbuf)` block goes: BufLeave, buf_copy_options, u_sync,
#     close_buffer(DOBUF_WIPE), the auto_buf dance, the curwin->w_buffer swap and
#     get_winopts.  It is removed by brace matching, not by matching its body.
#
# ORDER: fname2fnum() FIRST.  It calls buflist_new(name, p, 1, 0) to give a file
# mark's file a buffer, and once reuse is unconditional that call would wipe the
# buffer being edited.  Folded to nothing; getmark_buf_fnum() already treats a zero
# fnum as "not in a buffer".
#
# NO SWAP FILE, EVER -- not even one left from another age.  Swap files are already
# never WRITTEN here: findswapname, p_swf, swapfile_info, swapfile_unchanged,
# ml_recover and ml_sync_all are gone, mf_open() is the in-memory memfile, and
# ml_open_file() had been reduced to a single `b_may_swap = FALSE`.  What survived
# was the DETECTION prompt, and it was already unreachable: measured on q69, a .swp
# sitting beside the file produces no prompt at all, and the edit and the write go
# through in silence.  So swap_exists_action, the three SEA_* actions,
# handle_swap_exists(), check_swap_exists_action(), check_need_swap(), ml_open_file()
# and the b_may_swap field all go together -- vestigial scaffolding, the can_cindent
# shape again: a flag written in three places and never true.
#
# The one test that was not obviously dead is in changed(), not buf_write -- the
# first change to a buffer used to open its swap file there.  It is folded away.
#
# WHAT IS LOST: the state of the file you leave -- its undo history and its marks.
# `:e` and `:wq` keep working, on one buffer.  What stays: the load path, the
# argument-free reload (`:e` with no name), and :e! discarding changes.
#
# THE DELTA: none expected.  :e prints nothing to stderr, and an exsweep row is
# `exit= left= err=` -- the same reason :next did not move in phase 69.  Declared
# empty and left for whimdelta.sh to correct.
set -eu

work=${1:?usage: whim70-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

python3 - "$f" <<'PY'
TAG = 'onebuffer'
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

def drop_def(text, name, what):
    out, ok = cutil.delete_definition(text, name)
    if not ok:
        die('%s -- %s is not defined' % (what, name))
    say(what)
    return out

def drop_block(text, fn, pattern, what):
    # Brace-matched: the body may be any length, which is the point.
    def edit(s):
        try:
            out = cutil.drop_if(s, pattern, 1, re.M)
        except ValueError as e:
            die('%s -- %s' % (what, e))
        say(what)
        return out
    return in_function(text, fn, edit)

# ---- 1. nothing may create a buffer for a file mark -----------------------------
def f2f(s):
    head = s[:s.index('{\n') + 2]
    say('fname2fnum giving a file mark its own buffer')
    return head + '}\n'
t = in_function(t, 'fname2fnum', f2f)

# ---- 2. :e reuses the one buffer ------------------------------------------------
OLD_OPEN = '''        if (fnum)
        {
            buf = buflist_findnr(fnum);
        }
        else
        {
            buf = buflist_new(ffname, sfname, 0L, BLN_CURBUF | ((flags & ECMD_SET_HELP) ? 0 : BLN_LISTED));

            if (oldwin != NULL)
            {
                oldwin = curwin;
            }
            set_bufref(&old_curbuf, curbuf);
        }
        if (buf == NULL)
        {
            goto theend;
        }
'''
NEW_OPEN = '''        if (ffname != NULL && setfname(curbuf, ffname, sfname, FALSE) == FAIL)
        {
            goto theend;
        }
        if (oldwin != NULL)
        {
            oldwin = curwin;
        }
        set_bufref(&old_curbuf, curbuf);
        buf = curbuf;
'''
t = in_function(t, 'do_ecmd', lambda s: literal(s, OLD_OPEN, NEW_OPEN, ':edit opening a second buffer'))

# The buffer is the one already loaded, so it is never an "old" one to enter: the
# reload path below must run.
OLD_OLDBUF = '''        if (buf->b_ml.ml_mfp == NULL)
        {
            oldbuf = FALSE;
        }
        else
        {
            oldbuf = TRUE;
            set_bufref(&bufref, buf);
            if (!bufref_valid(&bufref) || curbuf != old_curbuf.br_buf)
            {
                goto theend;
            }
        }
'''
t = in_function(t, 'do_ecmd', lambda s: literal(s, OLD_OLDBUF, '        oldbuf = FALSE;\n',
                                                ':edit deciding the buffer was already loaded'))

# and the whole switch-to-another-buffer block
t = drop_block(t, 'do_ecmd', r'^[ \t]*if \(buf != curbuf\)\n[ \t]*\{\n[ \t]*bufref_T[ \t]+save_au_new_curbuf;$',
               ':edit leaving one buffer for another')

# the reload path was gated on this being the SAME file; now it is always the same
# buffer, so only "not already loaded" remains
t = in_function(t, 'do_ecmd', lambda s: literal(s, '    if (!other_file && !oldbuf)\n', '    if (!oldbuf)\n',
                                                'the reload path asking whether the file changed'))

# ---- 3. no swap file, ever, not even one left from another age -----------------
# Swap files are already never WRITTEN: findswapname, p_swf, swapfile_info,
# swapfile_unchanged, ml_recover and ml_sync_all are all gone, mf_open() is the
# in-memory memfile, and ml_open_file() has been reduced to `b_may_swap = FALSE`.
# What survived is the DETECTION prompt -- and it is already unreachable: measured
# on q69 with a .swp sitting beside the file, the editor edits and writes it without
# a word.  So this is vestigial scaffolding, the can_cindent shape again.
t = drop_def(t, 'handle_swap_exists', 'handle_swap_exists, which swapped in a buffer on "quit"')
t = drop_def(t, 'check_swap_exists_action', 'check_swap_exists_action, which quit for it')

t = in_function(t, 'do_ecmd', lambda s: literal(s, '''            swap_exists_action = SEA_DIALOG;
            curbuf->b_flags |= BF_CHECK_RO;
''', '''            curbuf->b_flags |= BF_CHECK_RO;
''', ':edit arming the swap-file dialog'))
t = in_function(t, 'do_ecmd', lambda s: literal(s, '''
            if (swap_exists_action == SEA_QUIT)
            {
                retval = FAIL;
            }
            handle_swap_exists(&old_curbuf);
''', '', ':edit answering it'))

t = in_function(t, 'readfile', lambda s: literal(s, '''    if (swap_exists_action == SEA_QUIT)
    {
        if (!read_buffer && !read_stdin)
        {
            close(fd);
        }
        goto theend;
    }

''', '', 'reading a file abandoning it for a swap file'))

t = in_function(t, 'create_windows', lambda s: literal(s, '''            swap_exists_action = SEA_DIALOG;

            (void)open_buffer(FALSE, NULL, 0);

            if (swap_exists_action == SEA_QUIT)
            {
                if (TRUE)
                {
                    did_emsg = FALSE;
                    getout(1);
                }
                setfname(curbuf, NULL, NULL, FALSE);
                swap_exists_action = SEA_NONE;
            }
            else
            {
                handle_swap_exists(NULL);
            }
''', '''            (void)open_buffer(FALSE, NULL, 0);
''', 'the startup open arming and answering the dialog'))

t = in_function(t, 'read_stdin', lambda s: literal(s, '    swap_exists_action = SEA_DIALOG;\n\n', '',
                                                  'reading stdin arming the dialog'))
t = in_function(t, 'read_stdin', lambda s: literal(s, '    check_swap_exists_action();\n\n', '',
                                                  'reading stdin answering it'))
t = lines(t, r'static int[ \t]+swap_exists_action[ \t]*=[ \t]*SEA_NONE[ \t]*;', 'the swap-file action itself')
# three anonymous single-enumerator enums, each with an explicit value, so removing
# them cannot renumber anything else.
t = lines(t, r'enum \{ SEA_(?:NONE|DIALOG|QUIT) = [0-9]+ \};', 'the SEA_* actions', 3)

# b_may_swap: set false in ml_open(), set false again in ml_open_file(), and tested
# in two places that can therefore never fire.  The test lives in changed(), NOT in
# buf_write -- line 8756 is changed(void), which is worth stating because I had it
# wrong from memory.
t = in_function(t, 'ml_open', lambda s: lines(s, r'buf->b_may_swap = false;', 'ml_open clearing b_may_swap'))
t = in_function(t, 'changed', lambda s: cutil.fold_never(
    s, r'^[ \t]*if \(curbuf->b_may_swap\)$', 1, re.M))
say('the first change to a buffer opening a swap file')
t = lines(t, r'check_need_swap\(newfile\);', 'the two calls that asked for a swap file', 2)
t = drop_def(t, 'check_need_swap', 'check_need_swap, which only reached ml_open_file')
t = drop_def(t, 'ml_open_file', 'ml_open_file, whose body was one assignment')
t = lines(t, r'bool[ \t]+b_may_swap;', 'the b_may_swap field')

open(path, 'w', errors='surrogateescape').write(t)
PY

tools/st.sh cmdidxs "$f" --check >/dev/null

# tools/phaserun.sh sweeps next, then runs pipes/whim70-check.sh.
