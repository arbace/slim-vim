#!/bin/sh
# Whim phase 71 -- one buffer, structurally.  See WHIM-GOAL.md.
#
# Usage: tools/whim71.sh <work-dir>      (run from the repository root)
#
# THE INVARIANT IS ALREADY TRUE; this phase removes the machinery that pretended
# otherwise.  Phase 69 allowed at most one file argument, phase 70 made :e reuse the
# one buffer, and every buffer Ex command was retired long before that: all 24 rows
# -- :buffer :buffers :ls :files :bnext :bprevious :bNext :bfirst :blast :brewind
# :bmodified :bdelete :bunload :bwipeout :bufdo :ball :badd :balt -- already read
# ex_ni, and do_buffer, do_bufdel, ex_buffer, ex_bufdo and ex_listdo do not exist.
# So NOTHING can create a second buffer:
#
#   * win_alloc_first() at startup makes the one buffer, BEFORE command_line_scan;
#   * buflist_add() then names it through BLN_CURBUF, reusing that same buffer;
#   * do_ecmd() no longer calls buflist_new() at all (phase 70).
#
# THREE THINGS NAMED b_next ARE NOT THE BUFFER LIST, and a regex over the name would
# gut the editor:
#
#   * buffblock_T.b_next       -- the typeahead/redo chain: bh_first, redobuff,
#                                 old_redobuff, readbuf1, readbuf2.  ~30 sites.
#   * free_buffer()            -- buf->b_next = au_pending_free_buf, a free list.
#   * buf_T.b_next / b_prev    -- THIS is the buffer list, and only this.
#
# Every edit below is scoped with in_function() for exactly that reason.
#
# TWO SITES ARE NOT SIMPLE FOLDS:
#
#   * check_map_keycodes()'s walk is `for (bp = firstbuf; ; bp = bp->b_next)` with NO
#     termination test -- it runs once per buffer and then ONCE MORE with bp == NULL,
#     which is how the global (non buffer-local) maps get scanned, and breaks on that
#     pass.  It becomes `for (bp = curbuf; ; bp = NULL)`: still exactly two
#     iterations.  Folding it to a single pass would stop scanning half the maps.
#
#     This walk feeds add_termcap_entry(), NOT mapping lookup: a mapping is found
#     through curbuf->b_maphash[] directly, which never touches the buffer list and
#     was never at risk here.  Worth stating because the first version of this file
#     claimed otherwise.
#   * close_buffer()'s wipe branch is guarded by (b_prev != NULL || b_next != NULL),
#     which with a single buffer is ALREADY false.  The splice it guards is dead
#     today, not merely dead afterwards, so the guard folds to its else.
#
# WHAT IS LOST: nothing reachable.  buf_valid() becomes `buf == curbuf`, which makes
# set_curbuf()'s `enter_buffer(lastbuf)` fallback unreachable and takes the rest of
# set_curbuf's other-buffer handling with it.
#
# WHAT STAYS: buf_hashtab and buflist_findnr(), because five live callers still look
# a buffer up by number -- eval_vars, setmark_pos, check_changed_any, buflist_nr2name
# and buflist_getfile.  Collapsing that to a curbuf test is a separate step.
#
# THE DELTA: none expected.  The buffer commands are already ex_ni, so no exsweep row
# can move; declared empty and left for whimdelta.sh to correct.
set -eu

work=${1:?usage: whim71.sh <work-dir>}
f="$work/whim-vim.c"

before_lines=$(grep -c '' "$f")
tools/symbols.sh "$f" .cache/symbols/before

python3 - "$f" <<'PY'
TAG = 'onebuf'
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

def drop_def(text, name, what):
    out, ok = cutil.delete_definition(text, name)
    if not ok:
        die('%s -- %s is not defined' % (what, name))
    say(what)
    return out

def body_of(text, name):
    span = cutil.find_definition(text, name)
    if not span:
        die('%s is not defined' % name)
    return text[span[0]:span[1]]

def replace_body(text, name, new_body, what):
    """Replace a definition's body, keeping its signature lines."""
    def edit(s):
        head = s[:s.index('{\n') + 2]
        say(what)
        return head + new_body + '}\n'
    return in_function(text, name, edit)

# A buffer-list walk is one macro-expanded line.  Folding one means deleting the
# `for` line and its braces and dedenting what was inside, with `buf` set to curbuf.
def fold_walk(text, fn, var, head, what, n=1):
    """Turn `for ((v) = firstbuf; ...)` + block into `v = curbuf;` + the block body.

    REFUSES a body with a `break` or `continue` at the loop's own level.  Deleting
    the `for` header rebinds such a statement to whatever encloses it, or to nothing
    at all -- getout()'s walk did exactly that here and produced "break statement not
    within loop or switch".  It is the same hazard CLAUDE.md records for unwrapping
    do { } while (0), and it must be a refusal rather than a silent miscompile.
    """
    def edit(s):
        pat = re.compile(r'^([ \t]*)' + re.escape(head) + r'[ \t]*\n([ \t]*)\{\n', re.M)
        found = pat.findall(s)
        if len(found) != n:
            die('%s -- the walk matches %d times, expected %d' % (what, len(found), n))
        out = s
        for _ in range(n):
            m = pat.search(out)
            b = cutil.blank(out)
            o = out.index('{', m.start())
            c = cutil.match(out, o, b)
            raw = out[out.index('\n', o) + 1:out.rfind('\n', 0, c) + 1]
            # C binds break/continue to the nearest enclosing loop or switch, and
            # brace depth has nothing to do with it: getout()'s break sits two ifs
            # deep and still bound to the `for` this fold removes.  So the test is
            # "is there an enclosing loop/switch INSIDE the body", not "is it at
            # depth 0" -- an earlier version tested depth and would have passed it.
            rb = cutil.blank(raw)
            spans = []
            for mm in re.finditer(r'\b(for|while|switch|do)\b', rb):
                j = rb.find('{', mm.end())
                if j >= 0:
                    k2 = cutil.match(raw, j, rb)
                    if k2 > 0:
                        spans.append((j, k2))
            for kw in ('break', 'continue'):
                for mm in re.finditer(r'\b%s\b[ \t]*;' % kw, rb):
                    if not any(a < mm.start() < z for a, z in spans):
                        die('%s -- the body has a `%s;` that binds to the walk being '
                            'removed, not to anything inside it' % (what, kw))
            body = cutil._dedent4(raw)
            end = out.index('\n', c) + 1
            out = out[:m.start()] + m.group(1) + var + ' = curbuf;\n' + body + out[end:]
        say(what)
        return out
    return in_function(text, fn, edit)

def drop_walk(text, fn, head, repl, what, n=1):
    """Replace `for (<head>)` and the block it runs with `repl`.

    The head is matched as a REGEX, never as a literal, and that is deliberate:
    these walk lines are macro-expanded and carry a trailing space after the
    closing paren.  A literal written out in a shell heredoc is a bad place to
    depend on invisible whitespace, and one written that way already failed here.
    """
    def edit(s):
        pat = re.compile(r'^[ \t]*' + re.escape(head) + r'[ \t]*\n[ \t]*\{\n', re.M)
        k = len(pat.findall(s))
        if k != n:
            die('%s -- the walk matches %d times, expected %d' % (what, k, n))
        out = s
        for _ in range(n):
            m = pat.search(out)
            b = cutil.blank(out)
            o = out.index('{', m.start())
            c = cutil.match(out, o, b)
            end = out.index('\n', c) + 1
            out = out[:m.start()] + repl + out[end:]
        say(what)
        return out
    return in_function(text, fn, edit)


# ---- 1. the keystone: a buffer is valid exactly when it is THE buffer ------------
t = replace_body(t, 'buf_valid', '    return buf == curbuf;\n',
                 'buf_valid, which walked the list to find the buffer it was given')

# ---- 2. the walks, one function at a time ---------------------------------------
FWD = 'for ((buf) = firstbuf; (buf) != NULL; (buf) = (buf)->b_next)'
BWD = 'for ((buf) = lastbuf; (buf) != NULL; (buf) = (buf)->b_prev)'

t = replace_body(t, 'anyBufIsChanged', '    return bufIsChanged(curbuf);\n',
                 'anyBufIsChanged, which asked every buffer')
t = replace_body(t, 'buflist_findname_stat', '''    if ((curbuf->b_flags & BF_DUMMY) == 0 && !otherfile_buf(curbuf, ffname, stp))
    {
        return curbuf;
    }
    return NULL;
''', 'buflist_findname_stat, which searched the list by name')

t = fold_walk(t, 'ml_close_all', 'buf', FWD, 'ml_close_all closing every buffer')
t = fold_walk(t, 'ml_close_notmod', 'buf', FWD, 'ml_close_notmod closing every buffer')
t = fold_walk(t, 'shorten_fnames', 'buf', FWD, 'shorten_fnames shortening every name')
t = fold_walk(t, 'did_set_paste', 'buf', FWD, "'paste' saving and restoring every buffer", 3)
t = fold_walk(t, 'set_termname', 'buf', FWD, 'a new terminal notifying every buffer')
# getout's walk cannot be folded: its body breaks out of the walk itself, two ifs
# deep, so removing the `for` header orphans the break.  The body becomes a plain
# `if`, and the break becomes the end of it -- the bufref_valid test existed only to
# stop walking, and with nothing left to walk it has no work to do.
t = drop_walk(t, 'getout', FWD, '''        if (curbuf->b_ml.ml_mfp != NULL)
        {
            bufref_T bufref;

            set_bufref(&bufref, curbuf);
            apply_autocmds(EVENT_BUFUNLOAD, curbuf->b_fname, curbuf->b_fname, FALSE, curbuf);
        }
''', 'quitting unloading every buffer, whose break bound to the walk')
# buflist_findpat is REPLACED, not folded, and the guard above is why: its walk body
# carries a `break` and a `continue` that bind to the walk itself, two ifs deep.  An
# earlier version folded it and rebound both to the enclosing `for (;;)` retry loop
# -- a behaviour change no compiler can report, which sat through three dry runs.
#
# With one buffer the retry machinery has nothing to retry: there is exactly one
# candidate, so `attempt`, `find_listed`, the unlisted second pass and the
# "more than one match" (-2) arm are all unreachable.  What is left is: does the
# pattern match THE buffer.  The curtab_only window walk goes with it -- the one
# buffer is in the one window.
t = replace_body(t, 'buflist_findpat', '''    int         match = -1;
    char_u      *pat;
    char_u      *patend;
    int         attempt;
    char_u      *p;
    int         toggledollar;

    if ((pattern_end == pattern + 1 && (*pattern == '%' || *pattern == '#')) || (in_vim9script() && pattern_end == pattern + 2 && pattern[0] == '%' && pattern[1] == '%'))
    {
        if (*pattern == '#' || pattern_end == pattern + 2)
        {
            match = 0;
        }
        else
        {
            match = curbuf->b_fnum;
        }
    }

    else
    {
        pat = file_pat_to_reg_pat(pattern, pattern_end, NULL, FALSE);
        if (pat == NULL)
        {
            return -1;
        }
        patend = pat +  strlen((char *)(pat))  - 1;
        toggledollar = (patend > pat && *patend == '$');

        for (attempt = 0; attempt <= 3; ++attempt)
        {
            regmatch_T      regmatch;

            if (toggledollar)
            {
                *patend = (attempt < 2) ? NUL : '$';
            }
            p = pat;
            if (*p == '^' && !(attempt & 1))
            {
                ++p;
            }
            regmatch.regprog = vim_regcomp(p, magic_isset() ? RE_MAGIC : 0);
            if (regmatch.regprog == NULL)
            {
                vim_free(pat);
                return -1;
            }
            if (buflist_match(&regmatch, curbuf, FALSE) != NULL)
            {
                match = curbuf->b_fnum;
            }
            vim_regfree(regmatch.regprog);
            if (match >= 0)
            {
                break;
            }
        }

        vim_free(pat);
    }

    if (match < 0)
    {
        semsg(_(e_no_matching_buffer_for_str), pattern);
    }
    return match;
''', 'buflist_findpat matching against every buffer')

# check_changed_any: bufnrs[] is already seeded with curbuf->b_fnum, so the count is
# one and the second walk only re-adds the same number.
t = drop_walk(t, 'check_changed_any', FWD, '    bufcount = 1;\n',
              'counting the buffers to check, and re-adding the one already seeded', 2)

# ---- 3. open_buffer has no other buffer to fall back to -------------------------
t = drop_walk(t, 'open_buffer', FWD.replace('(buf)', '(curbuf)'), '',
              'open_buffer looking for another loaded buffer')
# what is left is `if (curbuf == NULL)` guarding the exit -- a plain if, no else, and
# with no other buffer to find it is now always taken.
t = in_function(t, 'open_buffer', lambda s: cutil.fold_always(
    s, r'^[ \t]*if \(curbuf == NULL\)$', 1, re.M))
say('open_buffer testing whether it found one')
t = in_function(t, 'open_buffer', lambda s: literal(s, '''
        emsg(_(e_cannot_allocate_buffer_using_other_one));
        enter_buffer(curbuf);
        return FAIL;
''', '', 'open_buffer carrying on in another buffer instead'))

# ---- 3b. the Ex address arms: every buffer address is now THE buffer -------------
# compute_buffer_local_count walked the list by fnum offset; with one buffer every
# offset lands on it.
t = replace_body(t, 'compute_buffer_local_count', '    return curbuf->b_fnum;\n',
                 'computing a buffer address by walking to an offset')

ADDR_PAIR_1 = '''                    case ADDR_LOADED_BUFFERS:
                        {
                            buf_T       *buf = firstbuf;

                            while (buf->b_next != NULL && buf->b_ml.ml_mfp == NULL)
                            {
                                buf = buf->b_next;
                            }
                            eap->line1 = buf->b_fnum;
                            buf = lastbuf;
                            while (buf->b_prev != NULL && buf->b_ml.ml_mfp == NULL)
                            {
                                buf = buf->b_prev;
                            }
                            eap->line2 = buf->b_fnum;
                            break;
                        }
                    case ADDR_BUFFERS:
                        eap->line1 = firstbuf->b_fnum;
                        eap->line2 = lastbuf->b_fnum;
                        break;
'''
NEW_PAIR_1 = '''                    case ADDR_LOADED_BUFFERS:
                    case ADDR_BUFFERS:
                        eap->line1 = curbuf->b_fnum;
                        eap->line2 = curbuf->b_fnum;
                        break;
'''
t = in_function(t, 'parse_cmd_address',
                lambda s: literal(s, ADDR_PAIR_1, NEW_PAIR_1, 'the default buffer range'))

ADDR_PAIR_2 = '''        case ADDR_LOADED_BUFFERS:
            {
                buf_T *buf = firstbuf;

                while (buf->b_next != NULL && buf->b_ml.ml_mfp == NULL)
                {
                    buf = buf->b_next;
                }
                eap->line1 = buf->b_fnum;
                buf = lastbuf;
                while (buf->b_prev != NULL && buf->b_ml.ml_mfp == NULL)
                {
                    buf = buf->b_prev;
                }
                eap->line2 = buf->b_fnum;
            }
            break;
        case ADDR_BUFFERS:
            eap->line1 = firstbuf->b_fnum;
            eap->line2 = lastbuf->b_fnum;
            break;
'''
NEW_PAIR_2 = '''        case ADDR_LOADED_BUFFERS:
        case ADDR_BUFFERS:
            eap->line1 = curbuf->b_fnum;
            eap->line2 = curbuf->b_fnum;
            break;
'''
t = in_function(t, 'address_default_all',
                lambda s: literal(s, ADDR_PAIR_2, NEW_PAIR_2, 'the :% buffer range'))

ADDR_PAIR_3 = '''                    case ADDR_LOADED_BUFFERS:
                        buf = lastbuf;
                        while (buf->b_ml.ml_mfp == NULL)
                        {
                            if (buf->b_prev == NULL)
                            {
                                break;
                            }
                            buf = buf->b_prev;
                        }
                        lnum = buf->b_fnum;
                        break;
                    case ADDR_BUFFERS:
                        lnum = lastbuf->b_fnum;
                        break;
'''
NEW_PAIR_3 = '''                    case ADDR_LOADED_BUFFERS:
                    case ADDR_BUFFERS:
                        lnum = curbuf->b_fnum;
                        break;
'''
t = in_function(t, 'get_address',
                lambda s: literal(s, ADDR_PAIR_3, NEW_PAIR_3, "the $ of a buffer range"))

ADDR_PAIR_4 = '''            case ADDR_LOADED_BUFFERS:
                buf = firstbuf;
                while (buf->b_ml.ml_mfp == NULL)
                {
                    if (buf->b_next == NULL)
                    {
                        return _(e_invalid_range);
                    }
                    buf = buf->b_next;
                }
                if (eap->line1 < buf->b_fnum)
                {
                    return _(e_invalid_range);
                }
                buf = lastbuf;
                while (buf->b_ml.ml_mfp == NULL)
                {
                    if (buf->b_prev == NULL)
                    {
                        return _(e_invalid_range);
                    }
                    buf = buf->b_prev;
                }
                if (eap->line2 > buf->b_fnum)
                {
                    return _(e_invalid_range);
                }
                break;
'''
NEW_PAIR_4 = '''            case ADDR_LOADED_BUFFERS:
                if (curbuf->b_ml.ml_mfp == NULL || eap->line1 < curbuf->b_fnum || eap->line2 > curbuf->b_fnum)
                {
                    return _(e_invalid_range);
                }
                break;
'''
t = in_function(t, 'invalid_range',
                lambda s: literal(s, ADDR_PAIR_4, NEW_PAIR_4, 'validating a buffer range'))

# ---- 3c. free_buffer deferred onto a chain nothing ever drained ------------------
# au_pending_free_buf is WRITTEN in two places and read in none: the deferred branch
# leaked the buffer, and always did.  It goes with the field it linked through.
t = in_function(t, 'free_buffer', lambda s: literal(s, '''    if (autocmd_busy)
    {
        buf->b_next = au_pending_free_buf;
        au_pending_free_buf = buf;
    }
    else
    {
        vim_free(buf);
        if (curbuf == buf)
        {
            curbuf = NULL;
        }
    }
''', '''    vim_free(buf);
    if (curbuf == buf)
    {
        curbuf = NULL;
    }
''', 'free_buffer deferring onto a chain nothing ever drained'))
t = lines(t, r'static buf_T[ \t]+\*au_pending_free_buf[ \t]*=[ \t]*NULL[ \t]*;', 'that chain')

# ---- 4. the mappings walk keeps BOTH passes -------------------------------------
t = literal(t, 'for (bp = firstbuf; ; bp = bp->b_next)\n', 'for (bp = curbuf; ; bp = NULL)\n',
            'the mapping scan walking the list, still twice: curbuf then the globals')

# ---- 5. set_curbuf has nowhere else to go ---------------------------------------
t = in_function(t, 'set_curbuf', lambda s: literal(s, '''    valid = buf_valid(buf);
    if ((valid && buf != curbuf) || curwin->w_buffer == NULL)
    {
        if (!valid)
        {
            enter_buffer(lastbuf);
        }
        else
        {
            enter_buffer(buf);
        }
    }
''', '''    if (curwin->w_buffer == NULL)
    {
        enter_buffer(buf);
    }
''', 'set_curbuf entering a different buffer'))
t = in_function(t, 'set_curbuf', lambda s: lines(s, r'int[ \t]+valid;', 'its validity flag'))

# ---- 6. close_buffer's splice was already unreachable ---------------------------
t = in_function(t, 'close_buffer', lambda s: cutil.fold_never(
    s, r'^[ \t]*if \(wipe_buf && buf->b_nwindows <= 0 && \(buf->b_prev != NULL \|\| buf->b_next != NULL\)\)$',
    1, re.M))
say('close_buffer unlinking a buffer that was never linked to another')

# ---- 7. buflist_new keeps making THE buffer, but links it to nothing -------------
t = in_function(t, 'buflist_new', lambda s: literal(s, '''        buf->b_next = NULL;
        if (firstbuf == NULL)
        {
            buf->b_prev = NULL;
            firstbuf = buf;
        }
        else
        {
            lastbuf->b_next = buf;
            buf->b_prev = lastbuf;
        }
        lastbuf = buf;

''', '', 'buflist_new appending to the list'))

OLD_REUSE_START = '''        if ((flags & BLN_REUSE) && buf_reuse.ga_len > 0)
        {
            --buf_reuse.ga_len;
            buf->b_fnum = ((int *)buf_reuse.ga_data)[buf_reuse.ga_len];
'''
OLD_REUSE_END = '        else\n        {\n            buf->b_fnum = top_file_num++;\n        }\n'
if t.count(OLD_REUSE_START) != 1:
    die('the wiped-fnum branch -- its head occurs %d times, expected 1' % t.count(OLD_REUSE_START))
i = t.index(OLD_REUSE_START)
j = t.find(OLD_REUSE_END, i)
if j < 0:
    die('the wiped-fnum branch -- no plain `b_fnum = top_file_num++` else after it')
t = t[:i] + '        buf->b_fnum = top_file_num++;\n' + t[j + len(OLD_REUSE_END):]
say('buflist_new reusing a wiped fnum and re-sorting the list for it')

# ---- 8. what is left of the list itself -----------------------------------------
t = lines(t, r'static buf_T[ \t]+\*firstbuf[ \t]*=[ \t]*NULL[ \t]*;', 'firstbuf')
t = lines(t, r'static buf_T[ \t]+\*lastbuf[ \t]*=[ \t]*NULL[ \t]*;', 'lastbuf')
t = lines(t, r'static garray_T buf_reuse[ \t]*=[ \t]*\{0, 0, 0, 0, NULL\}[ \t]*;', 'the wiped-fnum pool')

# The buf_T fields, and ONLY the buf_T fields.  buffblock_T's b_next is ten lines
# away and must survive; it is matched by its own type, not by the name.
t = literal(t, '''    buf_T       *b_next;
    buf_T       *b_prev;

''', '', 'the buffer list pointers in buf_T')

open(path, 'w', errors='surrogateescape').write(t)
PY

python3 tools/create_cmdidxs.py "$f" --check >/dev/null

tools/sweep.sh "$f"

# The three things named b_next that are NOT the buffer list must all survive.
grep -qE '^[ \t]*buffblock_T \*b_next;' "$f" || { echo "  onebuf       buffblock_T lost its b_next -- the redo buffer is gone"; exit 1; }
for g in bh_first redobuff readbuf1 readbuf2; do
    grep -qE "\\b$g\\b" "$f" || { echo "  onebuf       $g went -- that was never the buffer list"; exit 1; }
done
# and the list itself must be gone
for g in firstbuf lastbuf buf_reuse BLN_REUSE au_pending_free_buf; do
    n=$(grep -cE -- "\\b$g\\b" "$f" || true)
    [ "$n" = 0 ] || { echo "  onebuf       $g still has $n mentions"; exit 1; }
done
# DOBUF_WIPE_REUSE keeps its enum and the two tests that name it; what must be gone
# is any CALLER passing it, which is what made the wipe branch reachable.
grep -nE '\b(close_buffer|set_curbuf)\([^;]*DOBUF_WIPE_REUSE' "$f" && { echo "  onebuf       something still asks for a reusable wipe"; exit 1; }
# a buf_T may no longer point at another buf_T
awk '/^struct file_buffer$/,/^\};$/' "$f" | grep -qE 'buf_T[ \t]+\*b_(next|prev);' && { echo "  onebuf       buf_T still links to another buffer"; exit 1; }
# the one buffer still has to be MADE, and looked up by number
for g in buflist_new buflist_add buflist_findnr buf_hashtab win_alloc_firstwin; do
    grep -qE "\\b$g\\b" "$f" || { echo "  onebuf       $g went too -- the one buffer still needs it"; exit 1; }
done
# the mapping scan must still make two passes
grep -qE 'for \(bp = curbuf; ; bp = NULL\)' "$f" || { echo "  onebuf       the mapping scan no longer runs its global pass"; exit 1; }
echo "  onebuf       one buffer, structurally; the redo chain and the free list untouched"

tools/phasecheck.sh "$work" "$f" .cache/symbols/before

tools/phasebuild.sh "$work" "$before_lines"

d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT
cp "$work/whim-vim" "$d/vim"

# LOAD FIRST, as always: prove the buffer holds the file before testing anything else.
printf 'a\nb\nc\n' > "$d/t.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+$' '+s/^/LAST /' '+wq' t.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/t.txt")" = 'a|b|LAST c|' ] || { echo "  onebuf       the file did not load: '$(tr '\n' '|' < "$d/t.txt")'"; exit 1; }

# :e still switches files, and the write follows it (phase 70's behaviour, unchanged)
printf 'h1\n' > "$d/h1.txt"; printf 'h2\n' > "$d/h2.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+e h2.txt' '+normal! iE' '+wq' h1.txt </dev/null >/dev/null 2>&1) || true
[ "$(cat "$d/h1.txt")" = 'h1' ] || { echo "  onebuf       :e wrote over the first file: $(cat "$d/h1.txt")"; exit 1; }
[ "$(cat "$d/h2.txt")" = 'Eh2' ] || { echo "  onebuf       :e did not load the second file: $(cat "$d/h2.txt")"; exit 1; }

# plain editing
printf 'one\ntwo\nthree\n' > "$d/e.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+2' '+normal! dd' '+wq' e.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/e.txt")" = 'one|three|' ] || { echo "  onebuf       editing broke: '$(tr '\n' '|' < "$d/e.txt")'"; exit 1; }

# BUFFER-LOCAL MAPPINGS still work.  NOTE THE MISSING BANG, and do not put it back:
# `normal!` suppresses mappings by definition, so a mapping probe written with it
# cannot fire on ANY build and measures nothing.  Calibrated against q70, which gives
# x with the bang and x! without it -- the same answer this phase gives, which is how
# the invalid probe was caught.  It is the <LeftMouse> mistake in another costume.
printf 'x\n' > "$d/m.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+map <buffer> Q A!' '+normal Q' '+wq' m.txt </dev/null >/dev/null 2>&1) || true
[ "$(cat "$d/m.txt")" = 'x!' ] || { echo "  onebuf       a buffer-local mapping stopped working: $(cat "$d/m.txt")"; exit 1; }

# a global mapping too, which is the second pass of check_map_keycodes' walk
printf 'y\n' > "$d/g.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+map Z A?' '+normal Z' '+wq' g.txt </dev/null >/dev/null 2>&1) || true
[ "$(cat "$d/g.txt")" = 'y?' ] || { echo "  onebuf       a global mapping stopped working: $(cat "$d/g.txt")"; exit 1; }

# '#' has no alternate file to name, and must say so rather than crash
printf 'z\n' > "$d/alt.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+normal! A1' '+wq' alt.txt </dev/null >/dev/null 2>&1) || true
[ "$(cat "$d/alt.txt")" = 'z1' ] || { echo "  onebuf       editing after the alternate-file cut broke: $(cat "$d/alt.txt")"; exit 1; }
echo "  onebuf       loads, edits, :e switches, and both mapping passes still fire"

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
