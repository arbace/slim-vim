#!/bin/sh
# Whim phase 80 -- the Ex command table, cut to the commands that exist.
# See WHIM-GOAL.md.
#
# Usage: tools/whim80.sh <work-dir>      (run from the repository root)
#
# 600 rows in `enum CMD_index` and `cmdnames[]`, and 489 of them are ex_ni or
# ex_script_ni: every phase that removed a command pointed its row at the stub and
# left the row, because the row still did one job -- it held the command's NAME, and
# a name in the table decides what every abbreviation of every other name means.
# Delete `buffer` and `:b` means something else.  So the rows stayed, and with them
# the two-level prefix index generated from them.
#
# THIS PHASE DELETES THE ROWS AND KEEPS WHAT THEY WERE FOR.  The lookup used to be
# "the first row, in table order, whose name starts with what was typed", so a
# name's shortest abbreviation was implied by every row above it.  Measured on q79:
# removing the 489 rows in place would have handed 15 prefixes that used to hit a
# stub to a live command -- :n to nmap, :o to omap, :h to highlight, :sa to saveas,
# :la to later, :en to enew, :ve to verbose.  No live command would have lost an
# abbreviation or gained another's, but an error becoming a mapping listing is not
# a thing to do to anyone.
#
# So each surviving row CARRIES its shortest abbreviation, computed here from the
# 600-row table before a row is touched, in the field that held the name's length
# (whose one reader was the Vim9 whole-name check, dead since phase 79).  A typed
# word names a command when it is a prefix of the name and at least that long.
# That makes a match unique, which makes row order irrelevant, which makes the
# index pointless: cmdidxs1, cmdidxs2, command_count and E943 go, and the lookup is
# a scan of 111 rows.  Every typed word resolves exactly as it did.  That is PROVED
# in step 1 rather than argued: the old lookup, index and all, and the new one are
# both modelled over every prefix of every one of the 600 names, and they must
# agree wherever the old answer survives and find nothing wherever it did not.
# Then step 9 runs every one of those words through both BINARIES.
#
# WHAT GOES WITH THE ROWS, each proved dead by the rows going:
#
#   26 CMD_ tests of commands that no longer exist (wincmd, if/endif, try, the
#       filename-escaping exceptions for grep/make/terminal, new/split/sview in
#       do_exedit, the Vim9 final/horizontal/mode quirks, and the index's two start
#       points CMD_Next and CMD_bang);
#   the `ni` flag in do_one_cmd, which exempted stub commands from range, bang,
#       count and argument checks, and can no longer be true;
#   the user-command test `(int)cmdidx < 0` -- nothing assigns a negative index;
#   the py3 and vim9 digit rules in find_ex_command -- no row starts with py or vim;
#   seven address types that only stub rows used -- argument list, buffers, loaded
#       buffers, tab pages twice, quickfix twice -- and their arms in five switches;
#   :if.  It was an ex_ni row that do_one_cmd special-cased to raise if_level, and
#       if_level is reset at the end of every do_cmdline while :if swallows the rest
#       of its line.  No command could ever run with it raised, so `ea.skip` was
#       already constantly FALSE, and its nineteen readers fold here.
#
# THE DELTA, declared.  Each removed name now gives E492 "Not an editor command"
# instead of E319 "not available in this version".  Both are errors with the same
# exit status, and the sweep cannot see the text.  Two things can see a difference,
# and both were agreed before this was written:
#   :if    was silently accepted (exit 0) and is now an error (exit 1);
#   `stub|cmd`  ran `cmd` after the stub's error, because a stub row with EX_TRLBAR
#       split its line at the bar; an unknown name takes the whole line, so `cmd`
#       no longer runs.  Probed below in both directions.
# And every removed name leaves the command sweep, which dispatches the names in
# the table: 489 rows, listed in REMOVED and required to be exactly the stub rows.
set -eu

work=${1:?usage: whim80.sh <work-dir>}
f="$work/whim-vim.c"

REMOVED='
    abbreviate abclear aboveleft abstract all amenu anoremenu args argadd argdelete
    argdo argdedupe argedit argglobal arglocal argument autocmd augroup aunmenu buffer
    bNext ball badd balt bdelete behave belowright bfirst blast bmodified bnext botright
    bprevious brewind break breakadd breakdel breaklist browse buffers bufdo bunload
    bwipeout cNext cNfile cabbrev cabclear cabove caddbuffer caddexpr caddfile cafter
    call catch cbuffer cbefore cbelow cbottom cc cclose cd cdo center cexpr cfile cfdo
    cfirst cgetfile cgetbuffer cgetexpr chdir checkpath checktime chistory clist
    clipreset clast class close clearjumps cmenu cnext cnewer cnfile cnoreabbrev
    cnoremenu colder colorscheme command comclear compiler continue confirm const copen
    cprevious cpfile crewind cscope cstag cunabbrev cunmenu cwindow debug debuggreedy
    def defcompile defer delcommand delfunction diffupdate diffget diffoff diffpatch
    diffput diffsplit diffthis digraphs disassemble djump dlist doautocmd doautoall drop
    dsearch dsplit echo echoerr echohl echomsg echoconsole echon echowindow else elseif
    emenu endif endinterface endclass enddef endenum endfunction endfor endtry endwhile
    enum eval execute export exusage files filetype find final finally finish first fold
    foldclose folddoopen folddoclosed foldopen for function goto grep grepadd gui gvim
    help helpclose helpfind helpgrep helptags hardcopy hide horizontal iabbrev iabclear
    if ijump ilist imenu import inoreabbrev inoremenu intro interface isearch isplit
    iunabbrev iunmenu jumps keepalt lNext lNfile last labove language laddexpr
    laddbuffer laddfile lafter lbuffer lbefore lbelow lbottom lcd lchdir lclose lcscope
    ldo left leftabove let lexpr legacy lfile lfdo lfirst lgetfile lgetbuffer lgetexpr
    lgrep lgrepadd lhelpgrep lhistory ll llast llist lmap lmapclear lmake lnoremap lnext
    lnewer lnfile loadview loadkeymap lockvar lolder lopen lprevious lpfile lrewind ltag
    lunmap lua luado luafile lvimgrep lvimgrepadd lwindow ls make menu menutranslate
    mkexrc mksession mkspell mkvimrc mkview mode mzscheme mzfile next nbkey nbclose
    nbstart new nmenu nnoremenu noautocmd noreabbrev noremenu noswapfile nunmenu open
    oldfiles omenu only onoremenu options ounmenu ownsyntax packadd packloadall pbuffer
    pclose perl perldo pedit pop popup ppop preserve previous promptfind promptrepl
    profile profdel psearch ptag ptNext ptfirst ptjump ptlast ptnext ptprevious ptrewind
    ptselect public pwd python pydo pyfile py3 py3do python3 py3file pyx pyxdo pythonx
    pyxfile quitall qall recover redir redrawtabline redrawtabpanel resize retab return
    rewind right rightbelow runtime ruby rubydo rubyfile rundo rviminfo sNext sargument
    sall sandbox sbuffer sbNext sball sbfirst sblast sbmodified sbnext sbprevious
    sbrewind scriptnames scriptencoding scriptversion scscope setfiletype setglobal
    setlocal sfind sfirst shell simalt sign sleep slast smenu snext snoremenu source
    sort split spellgood spelldump spellinfo spellrepall spellrare spellundo spellwrong
    sprevious srewind stag startinsert startgreplace startreplace static stopinsert
    stjump stselect sunhide sunmenu sview swapname syntax syntime syncbind smile tNext
    tag tags tab tabclose tabdo tabedit tabfind tabfirst tabmove tablast tabnext tabnew
    tabonly tabprevious tabNext tabrewind tabs tcd tchdir tcl tcldo tclfile tearoff
    terminal tfirst throw this tjump tlast tlmenu tlnoremenu tlunmenu tmenu tmap
    tmapclear tnext tnoremap topleft tprevious trewind try tselect tunmenu tunmap type
    unabbreviate unhide uniq unlet unlockvar unmenu var version vertical vimgrep
    vimgrepadd vim9cmd vim9script viusage vmenu vnew vnoremenu vsplit vunmenu wNext wall
    while wincmd windo winpos wlrestore wnext wprevious wqall wundo wviminfo xall xmenu
    xnoremenu xrestore xunmenu ! { } Next X ++ --
'
export REMOVED

d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT

# The binary this phase is compared against, built from its input before a byte
# of it moves.  In the background: the edits below do not wait for it.
cp "$f" "$d/old.c"
(cd "$d" && gcc -O0 -static -s -w -o old old.c) &
pid_old=$!

before_lines=$(grep -c '' "$f")
tools/symbols.sh "$f" .cache/symbols/before

python3 - "$f" "$d/words" <<'PY'
TAG = 'cmdtable'
import os, re, sys
sys.path.insert(0, 'tools')
import cutil
path, words_out = sys.argv[1], sys.argv[2]
t = open(path, errors='surrogateescape').read()

def die(msg):
    sys.exit('  %-12s %s' % (TAG, msg))

def say(what):
    print('  %-12s %s' % (TAG, what))

def fold_never(text, pattern, what, n=1):
    try:
        out = cutil.fold_never(text, pattern, n, re.M)
    except ValueError as e:
        die('%s -- %s' % (what, e))
    say(what)
    return out

def fold_always(text, pattern, what, n=1):
    try:
        out = cutil.fold_always(text, pattern, n, re.M)
    except ValueError as e:
        die('%s -- %s' % (what, e))
    say(what)
    return out

def drop_if(text, pattern, what, n=1):
    try:
        out = cutil.drop_if(text, pattern, n, re.M)
    except ValueError as e:
        die('%s -- %s' % (what, e))
    say(what)
    return out

def term(text, frag, repl, what, n=1):
    """A literal fragment, replaced.  Counted, never 'the first one'."""
    k = text.count(frag)
    if k != n:
        die('%s -- the fragment occurs %d times, expected %d' % (what, k, n))
    say(what)
    return text.replace(frag, repl)

def lines(text, pattern, what, n=1):
    rx = re.compile(r'^[ \t]*' + pattern + r'[ \t]*\n', re.M)
    k = len(rx.findall(text))
    if k != n:
        die('%s -- %d lines match, expected %d' % (what, k, n))
    say(what)
    return rx.sub('', text)

def fold_always_else(text, pattern, what):
    """`if (TRUE) { A } else { B }` -> A.  cutil.fold_always refuses an else."""
    ms = list(re.finditer(pattern, text, re.M))
    if len(ms) != 1:
        die('%s -- %d matches, expected 1' % (what, len(ms)))
    b = cutil.blank(text)
    k, o, c, head = cutil._guarded(text, ms[0], b)
    if head != 'if':
        die('%s -- not a plain if: %r' % (what, head))
    end = text.index('\n', c) + 1
    m = re.match(r'[ \t]*else[ \t]*\n', text[end:])
    if not m:
        die('%s -- expected an else' % what)
    o2 = b.index('{', end + m.end())
    c2 = cutil.match(text, o2, b)
    if re.match(r'[ \t]*else\b', text[text.index('\n', c2) + 1:]):
        die('%s -- the else is followed by another else' % what)
    body = cutil._dedent4(text[text.index('\n', o) + 1:text.rfind('\n', 0, c) + 1])
    say(what)
    return text[:k] + body + text[text.index('\n', c2) + 1:]

# ---- 1: the table, the index, and the proof ----------------------------------------
m = re.search(r'^static struct cmdname cmdnames\[\] =\n\{\n(.*?)^\};\n', t, re.M | re.S)
if not m:
    die('cmdnames[] definition not found')
tab_start, tab_end = m.start(1), m.end(1)
ROW = re.compile(r'^    \[CMD_(\w+)\] = \{\(char_u \*\)"([^"]*)", sizeof\("([^"]*)"\) - 1, *(\w+) *, '
                 r'\(long_u\)\(.*\), ADDR_\w+\},$')
rows = {}
row_order = []
for line in m.group(1).split('\n'):
    if line == '':
        continue
    r = ROW.match(line)
    if not r or r.group(2) != r.group(3):
        die('a cmdnames[] row does not have the expected shape: %r' % line[:90])
    rows[r.group(1)] = (r.group(2), r.group(4), line)
    row_order.append(r.group(1))

m = re.search(r'^enum CMD_index\n\{\n(.*?)^    CMD_SIZE\};\n', t, re.M | re.S)
if not m:
    die('enum CMD_index not found')
enum_start, enum_end = m.start(1), m.end(1)
ids = re.findall(r'^    CMD_(\w+),$', m.group(1), re.M)
if len(ids) != 600 or sorted(ids) != sorted(rows):
    die('enum CMD_index has %d names, and they are not the %d rows' % (len(ids), len(rows)))
if ids != row_order:
    die('the rows are not written in enumerator order')

# THE LOOKUP SCANS BY INDEX, so the model uses enumerator order.
names = [rows[i][0] for i in ids]
handler = {rows[i][0]: rows[i][1] for i in ids}
cmdid = {rows[i][0]: i for i in ids}
dead = [n for n in names if handler[n] in ('ex_ni', 'ex_script_ni')]
live = [n for n in names if n not in dead]
if sorted(dead) != sorted(os.environ['REMOVED'].split()):
    die('the stub rows are not REMOVED: extra %s, missing %s'
        % (sorted(set(dead) - set(os.environ['REMOVED'].split())),
           sorted(set(os.environ['REMOVED'].split()) - set(dead))))
say('confirmed: %d rows, %d of them stubs -- exactly REMOVED -- and %d live'
    % (len(names), len(dead), len(live)))

# The old index, read out of the file rather than regenerated.
def ints(s):
    return [int(x) for x in re.findall(r'\d+', s)]
m1 = re.search(r'static const unsigned short cmdidxs1\[26\] =\n\{\n(.*?)\};', t, re.S)
m2 = re.search(r'static const unsigned char cmdidxs2\[26\]\[26\] =\n\{\n(.*?)\n\};', t, re.S)
mc = re.search(r'static const int command_count = (\d+);', t)
if not (m1 and m2 and mc):
    die('the ex_cmdidxs block is not where it was')
idx1, idx2 = ints(m1.group(1)), ints(m2.group(1))
if len(idx1) != 26 or len(idx2) != 676 or int(mc.group(1)) != 600:
    die('the ex_cmdidxs block has an unexpected shape')

OLD_CHARS = '@*!=><&~#}'
m = re.search(r'vim_strchr\(\(char_u \*\)"([^"]*)", \*p\) != NULL\)\n', t)
if not m or m.group(1) != OLD_CHARS:
    die('the one-character command set is not %r' % OLD_CHARS)
NEW_CHARS = ''.join(c for c in OLD_CHARS if c in live)

def lower(c):
    return 'a' <= c <= 'z'

def upper(c):
    return 'A' <= c <= 'Z'

def old_lookup(w):
    """find_ex_command as it stands on q79, index included."""
    if lower(w[0]) or upper(w[0]):
        if not all(lower(c) or upper(c) or c.isdigit() for c in w):
            return None
        if lower(w[0]):
            start = idx1[ord(w[0]) - 97]
            if len(w) > 1 and lower(w[1]):
                start += idx2[(ord(w[0]) - 97) * 26 + ord(w[1]) - 97]
        else:
            start = ids.index('Next')
    elif w[0] in OLD_CHARS:
        if len(w) != 1:
            return None
        start = ids.index('bang')
    else:
        return None
    for n in names[start:]:
        if n.startswith(w):
            return n
    return None

minlen = {}
for n in live:
    if old_lookup(n) != n:
        die('%r does not resolve to itself in the old table' % n)
    minlen[n] = next(i for i in range(1, len(n) + 1) if old_lookup(n[:i]) == n)

def new_lookup(w):
    """The lookup this phase writes: a prefix at least as long as the row says.

    A name is letters only now -- the py3 and vim9 digit rules go with every row
    that needed them -- so the word stops at the first character that is not one.
    """
    if not (lower(w[0]) or upper(w[0])):
        if w[0] not in NEW_CHARS or len(w) != 1:
            return None
    else:
        w = re.match(r'[A-Za-z]+', w).group(0)
    for n in live:
        if len(w) >= minlen[n] and n.startswith(w):
            return n
    return None

words = sorted({n[:i] for n in names for i in range(1, len(n) + 1)} | set(OLD_CHARS + '{+-'))
moved = []
for w in words:
    o = old_lookup(w)
    want = o if o in minlen else None
    got = new_lookup(w)
    if got != want:
        moved.append((w, o, got))
if moved:
    die('the new lookup disagrees with the old one on %d words: %s' % (len(moved), moved[:8]))
unique = [w for w in words if sum(1 for n in live if len(w) >= minlen[n] and n.startswith(w)) > 1]
if unique:
    die('a word matches more than one row: %s' % unique[:8])
say('proved: all %d prefixes of the 600 names resolve as before, each to at most one row' % len(words))

# What step 9 dispatches, with what the old table made of each word.
with open(words_out, 'w') as fh:
    for w in words:
        fh.write('%s\t%s\n' % (w, old_lookup(w) or '-'))

# ---- 2: rewrite the two lists ------------------------------------------------------
def tidy_blank_runs(s):
    return re.sub(r'\n\n+', '\n\n', s)

# Keep the blank lines between groups, where the input had them.
body = []
for line in t[tab_start:tab_end].split('\n'):
    if line == '':
        body.append('')
        continue
    r = ROW.match(line)
    name = r.group(2)
    if name in minlen:
        body.append(line.replace('sizeof("%s") - 1' % name, str(minlen[name]), 1))
tab_body = tidy_blank_runs('\n'.join(body))
enum_body = []
for line in t[enum_start:enum_end].split('\n'):
    r = re.match(r'^    CMD_(\w+),$', line)
    if r and rows[r.group(1)][0] not in minlen:
        continue
    enum_body.append(line)
enum_body = tidy_blank_runs('\n'.join(enum_body))
# the table is after the enum in the file
if not enum_end < tab_start:
    die('the enum is not above the table')
t = t[:enum_start] + enum_body + t[enum_end:tab_start] + tab_body + t[tab_end:]
say('%d rows and %d enumerators kept, each row with its shortest abbreviation' % (len(minlen), len(minlen)))

t = term(t, '    size_t      cmd_namelen;\n', '    int         cmd_minlen;\n',
         'the row field that held the name length holds the shortest abbreviation')
m = re.search(r'^// -+ begin ex_cmdidxs\.h -+\n.*?^// -+ end ex_cmdidxs\.h -+\n', t, re.M | re.S)
if not m:
    die('the ex_cmdidxs banners are gone')
t = t[:m.start()] + t[m.end():]
say('the prefix index, its banners and its count')
t = term(t, 'zeroed hole, which the 600-command sweep catches.',
         'zeroed hole, which the command sweep catches.', 'the note on the two lists')
t = term(t, '    // ex_ni, :! does not fork,', '    // not commands, :! does not fork,',
         'the note in mch_dirname, which named the stub')
t = term(t, ':wundo and :rundo are ex_ni --', ':wundo and :rundo are not commands --',
         'and the note in add_time')

# ---- 3: find_ex_command ------------------------------------------------------------
t = lines(t, r'int         vim9 = FALSE;', 'the Vim9 flag nothing sets')
t = fold_never(t, r'^[ \t]*if \(vim9 && eap->cmdidx != CMD_SIZE\)$',
               'the Vim9 whole-name check, the one reader of the name length')
t = term(t, "if (!vim9 && *eap->cmd == 'd' && ", "if (*eap->cmd == 'd' && ",
         ':dl and :dp outside Vim9, which is everywhere')
t = fold_never(t, r'^[ \t]*if \(eap->cmdidx == CMD_final && p - eap->cmd == 4 && !vim9\)$',
               ':final is not a command')
t = fold_never(t, r'^[ \t]*if \(eap->cmdidx == CMD_horizontal && p - eap->cmd == 2\)$',
               ':horizontal is not a command')
if [n for n in live if n.startswith('py') or n.startswith('vim')]:
    die('a live command starts with py or vim, and its name may need a digit')
t = fold_never(t, r"^[ \t]*if \(eap->cmd\[0\] == 'p' && eap->cmd\[1\] == 'y'\)$",
               'no command left is spelled with a digit: not :py3')
t = fold_never(t, r"^[ \t]*if \(\*p == '9' &&  strncmp\(\(char \*\)\(\"vim9\"\), \(char \*\)\(eap->cmd\), \(4\)\)  == 0\)$",
               'and not :vim9cmd')
if re.search(r'\bvim9\b', t[t.index('\nfind_ex_command('):t.index('\nfind_ex_command(') + 6000]):
    die('vim9 survives in find_ex_command')

HEAD = "        if ( ((unsigned)(eap->cmd[0]) - 'a' < 26) )\n"
if t.count(HEAD) != 1:
    die('the index lookup head occurs %d times' % t.count(HEAD))
a = t.index(HEAD)
loop = t.index('        for ( ; (int)eap->cmdidx < (int)CMD_SIZE;', a)
b = cutil.blank(t)
lb = b.index('{', loop)
z = t.index('\n', cutil.match(t, lb, b)) + 1
old_span = t[a:z]
for need in ('cmdidxs1', 'cmdidxs2', 'command_count', 'CMD_Next', 'CMD_bang', 'strncmp'):
    if need not in old_span:
        die('the lookup span does not contain %s -- it is not the block it was' % need)
if old_span.count('\n') != 33:
    die('the lookup span is %d lines, expected 33' % old_span.count('\n'))
t = t[:a] + '''        for (eap->cmdidx = (cmdidx_T)0; (int)eap->cmdidx < (int)CMD_SIZE; eap->cmdidx = (cmdidx_T)((int)eap->cmdidx + 1))
        {
            if (len >= cmdnames[(int)eap->cmdidx].cmd_minlen &&  strncmp((char *)(cmdnames[(int)eap->cmdidx].cmd_name), (char *)((char *)eap->cmd), ((size_t)len))  == 0)
            {
                break;
            }
        }
''' + t[z:]
say('the lookup: a prefix at least as long as the row says, over %d rows' % len(minlen))
t = term(t, 'vim_strchr((char_u *)"%s", *p)' % OLD_CHARS, 'vim_strchr((char_u *)"%s", *p)' % NEW_CHARS,
         'the one-character commands that exist: %s' % NEW_CHARS)

# ---- 4: do_one_cmd -----------------------------------------------------------------
t = fold_never(t, r'^[ \t]*if \(ea\.cmdidx == CMD_wincmd && p != NULL\)$', ':wincmd has no address type to find')
t = fold_always(t, r'^[ \t]*if \(! \(\(int\)\(ea\.cmdidx\) < 0\) \)$', 'a command index is never a user command', 3)
t = term(t, 'ea.cmd[0] == 78 && ! ((int)(ea.cmdidx) < 0) )', 'ea.cmd[0] == 78)', 'nor in the Ni! test')
t = term(t, 'ea.cmdidx != CMD_checktime && ea.cmdidx != CMD_edit && ea.cmdidx != CMD_file && ! ((int)(ea.cmdidx) < 0)  && curbuf_locked()',
         'ea.cmdidx != CMD_edit && ea.cmdidx != CMD_file && curbuf_locked()',
         'nor in the locked-buffer exemptions, which lose :checktime')
t = term(t, "*ea.arg != NUL && (! ((int)(ea.cmdidx) < 0)  || *ea.arg != '=') && !((ea.argt",
         "*ea.arg != NUL && !((ea.argt", 'nor in the register argument test')
t = term(t, '(! ((int)(ea.cmdidx) < 0)  && ea.cmdidx != CMD_put && ea.cmdidx != CMD_iput)',
         '(ea.cmdidx != CMD_put && ea.cmdidx != CMD_iput)', 'nor in which registers may be written')
t = fold_never(t, r'^[ \t]*if \( \(\(int\)\(eap->cmdidx\) < 0\) \)$', 'nor in a % range over windows')

t = lines(t, r'ni = \(! \(\(int\)\(ea\.cmdidx\) < 0\)  && \(cmdnames\[ea\.cmdidx\]\.cmd_func == ex_ni \|\| cmdnames\[ea\.cmdidx\]\.cmd_func == ex_script_ni\)\);',
          'the stub flag, which no row can raise')
t = lines(t, r'int         ni;', 'and its declaration')
t = term(t, '(!ni && ', '(', 'range, bang, extra-argument and required-argument checks apply to every command', 4)
t = term(t, '&& !ni && ', '&& ', 'and the range and count checks', 2)
t = term(t, 'getargopt(&ea) == FAIL && !ni)', 'getargopt(&ea) == FAIL)', 'and ++opt parsing')

t = drop_if(t, r'^    if \(ea\.cmdidx == CMD_if\)$', ':if and the level it raised')
t = fold_never(t, r'^    if \(if_level\)$', 'the level is never raised')
t = lines(t, r'ea\.skip = \(if_level > 0\);', 'so nothing is skipped')
t = lines(t, r'if_level = 0;', 'the reset')
t = term(t, 'static int      if_level = 0;\n', '', 'and the level')

t = fold_never(t, r'^[ \t]*if \(ea\.cmdidx == CMD_bang\)$', ':! keeps no leading space')
t = term(t, 'else if (ea.cmdidx == CMD_bang || ea.cmdidx == CMD_terminal || ea.cmdidx == CMD_global',
         'else if (ea.cmdidx == CMD_global', 'the commands that take the whole line are :g and :v')
t = term(t, "else if (*p == '\\n' && !(ea.argt & EX_EXPR_ARG))", "else if (*p == '\\n')",
         'and none takes an expression')
t = term(t, "  && (!(ea.argt & EX_BUFNAME) || *(p = skipdigits(ea.arg + 1)) == NUL ||  ((*p) == ' ' || (*p) == '\\t') ))",
         ')', 'a count is never a buffer name')
t = fold_never(t, r'^[ \t]*if \(ea\.cmdidx == CMD_try && cmdmod\.cmod_did_esilent > 0\)$', ':try is not a command')

# ---- 5: ea.skip, which only :if ever raised ----------------------------------------
for fn in ('ex_ni', 'ex_script_ni'):
    sp = cutil.find_definition(t, fn)
    if not sp:
        die('%s is not defined' % fn)
    a, z = sp
    if t[a - 2:a] == '\n\n' and t[z:z + 1] == '\n':
        z += 1
    t = t[:a] + t[z:]
say('ex_ni and ex_script_ni, which no row names')
t = fold_never(t, r'^[ \t]*if \(ea\.skip\)$', 'an empty command line is never skipped')
t = fold_always(t, r'^[ \t]*if \(!ea\.skip\)$', 'do_one_cmd: nothing is skipped', 3)
t = term(t, 'if (!ea.skip && (ea.argt & EX_RANGE))', 'if (ea.argt & EX_RANGE)', 'nor a range check')
t = term(t, 'eap->addr_type, eap->skip, silent,', 'eap->addr_type, FALSE, silent,', 'nor an address')
t = fold_never(t, r'^[ \t]*if \(eap->skip\)$', ':substitute is never skipped', 2)
t = fold_always(t, r'^[ \t]*if \(!eap->skip\)$', 'nor its pattern, a range, or :match', 6)
t = term(t, '    else if (!eap->skip)\n', '    else\n', "nor :substitute's previous pattern")
t = term(t, 'i <= 0 && !eap->skip && subflags.do_error', 'i <= 0 && subflags.do_error', 'nor its count')
if re.search(r'\b(ea\.|eap->)skip\b', t):
    die('a read of skip survives')

# ---- 6: the filename and bar parsers -----------------------------------------------
t = term(t, ' && eap->cmdidx != CMD_bang && eap->cmdidx != CMD_grep && eap->cmdidx != CMD_grepadd && eap->cmdidx != CMD_hardcopy && eap->cmdidx != CMD_lgrep && eap->cmdidx != CMD_lgrepadd && eap->cmdidx != CMD_lmake && eap->cmdidx != CMD_make && eap->cmdidx != CMD_terminal)',
         ')', 'expanded filenames are escaped for every command left')
t = term(t, '(eap->usefilter || eap->cmdidx == CMD_bang || eap->cmdidx == CMD_terminal) &&',
         'eap->usefilter &&', "and '!' only for a filter")
t = term(t, " && (eap->cmdidx != CMD_redir || p != eap->arg + 1 || p[-1] != '@'))", ')',
         'a double quote after :redir @ is a comment like any other')

# ---- 7: do_exedit ------------------------------------------------------------------
for e in ('ERROR_IF_POPUP_WINDOW', 'ERROR_IF_TERM_POPUP_WINDOW'):
    if not re.search(r'^enum \{ %s = 0 \};$' % e, t, re.M):
        die('%s is not the constant 0' % e)
t = fold_never(t, r'^[ \t]*if \(\(eap->cmdidx != CMD_pedit && ERROR_IF_POPUP_WINDOW\) \|\| ERROR_IF_TERM_POPUP_WINDOW\)$',
               'no popup window refuses an edit')
t = fold_never(t, r'^[ \t]*if \(\(eap->cmdidx == CMD_new \|\| eap->cmdidx == CMD_vnew\) && \*eap->arg == NUL\)$',
               ':new and :vnew are not commands')
t = fold_always_else(t, r'^[ \t]*if \(\(eap->cmdidx != CMD_split && eap->cmdidx != CMD_vsplit\) \|\| \*eap->arg != NUL\)$',
                     'and neither are :split and :vsplit, so every edit edits')
t = term(t, 'if (eap->cmdidx == CMD_view || eap->cmdidx == CMD_sview)', 'if (eap->cmdidx == CMD_view)',
         ':view is read-only and :sview is gone')

# ---- 8: the address types only stub rows had ---------------------------------------
t = fold_never(t, r'^[ \t]*if \(addr_type == ADDR_TABS_RELATIVE\)$', 'no relative tab page offset')
t = fold_never(t, r'^[ \t]*if \(addr_type == ADDR_LOADED_BUFFERS \|\| addr_type == ADDR_BUFFERS\)$',
               'no buffer-number offset')
DEAD_ADDR = {'ADDR_ARGUMENTS', 'ADDR_BUFFERS', 'ADDR_LOADED_BUFFERS', 'ADDR_QUICKFIX',
             'ADDR_QUICKFIX_VALID', 'ADDR_TABS', 'ADDR_TABS_RELATIVE'}
live_addr = set(re.findall(r'ADDR_\w+', t[tab_start:t.index('\n};\n', tab_start)]))
if live_addr & DEAD_ADDR:
    die('a live row has one of the address types being removed: %s' % sorted(live_addr & DEAD_ADDR))
L = t.split('\n')
out = []
i = 0
groups_gone = labels_gone = 0
LABEL = re.compile(r'^([ \t]*)(case \w+:|default:)$')
while i < len(L):
    mm = LABEL.match(L[i])
    if not mm:
        out.append(L[i])
        i += 1
        continue
    ind = mm.group(1)
    j = i
    labels = []
    while j < len(L) and LABEL.match(L[j]) and LABEL.match(L[j]).group(1) == ind:
        labels.append(L[j])
        j += 1
    k = j
    while k < len(L) and (L[k] == '' or (L[k].startswith(ind + ' ') and not LABEL.match(L[k]))):
        k += 1
    names_here = [re.match(r'^[ \t]*case (\w+):$', x).group(1) if x.strip() != 'default:' else 'default'
                  for x in labels]
    keep = [x for x, n in zip(labels, names_here) if n not in DEAD_ADDR]
    if len(keep) == len(labels):
        out.extend(L[i:k])
    elif keep:
        out.extend(keep)
        out.extend(L[j:k])
        labels_gone += len(labels) - len(keep)
    else:
        prev = next(x for x in reversed(out) if x.strip())
        if not re.match(r'^[ \t]*(break;|goto \w+;|return\b.*;|\{)$', prev):
            die('a removed case group can be fallen into from %r' % prev.strip())
        labels_gone += len(labels)
        groups_gone += 1
    i = k
t = '\n'.join(out)
t = term(t, '"Cannot use EX_DFLALL with ADDR_NONE, ADDR_UNSIGNED or ADDR_QUICKFIX"',
         '"Cannot use EX_DFLALL with ADDR_NONE or ADDR_UNSIGNED"',
         'the internal error that named the quickfix address type')
left = [a for a in DEAD_ADDR if re.search(r'\bcase %s:' % a, t)]
if left:
    die('case labels survive: %s' % left)
say('%d case labels for the seven address types, %d whole arms' % (labels_gone, groups_gone))

open(path, 'w', errors='surrogateescape').write(t)
PY

tools/sweep.sh "$f"

# Nothing the rows took with them may be named any more.
for g in cmd_namelen cmdidxs1 cmdidxs2 command_count e_command_table_needs_to_be_updated_run_make_cmdidxs \
         if_level ex_ni ex_script_ni get_wincmd_addr_type \
         ADDR_ARGUMENTS ADDR_BUFFERS ADDR_LOADED_BUFFERS ADDR_QUICKFIX ADDR_QUICKFIX_VALID ADDR_TABS ADDR_TABS_RELATIVE; do
    n=$(grep -cE -- "\\b$g\\b" "$f" || true)
    [ "$n" = 0 ] || { echo "  cmdtable     $g still has $n mentions"; exit 1; }
done
for c in $REMOVED; do
    case $c in *[!A-Za-z0-9]*) continue ;; esac
    if grep -qE "\\bCMD_$c\\b" "$f"; then
        echo "  cmdtable     CMD_$c survives"; exit 1
    fi
done
n=$(grep -cE '^    \[CMD_\w+\] = \{\(char_u \*\)"' "$f")
[ "$n" = 111 ] || { echo "  cmdtable     $n rows, expected 111"; exit 1; }
grep -qE '^    \[CMD_\w+\] = .*sizeof\("' "$f" && { echo "  cmdtable     a row still carries its name length"; exit 1; }
echo "  cmdtable     111 rows, no index, nothing names a removed command or address type"

tools/phasecheck.sh "$work" "$f" .cache/symbols/before

tools/phasebuild.sh "$work" "$before_lines"

wait $pid_old

# --- 9: every prefix of every name, through both binaries --------------------------
# Step 1 proved the lookup tables agree.  This proves the editors do: each word
# goes in as `+word`, alone, on a three-line file, and the exit status, what it
# wrote to stderr, the file afterwards and anything left in the directory must be
# the same.  The one word allowed to differ is `if`.  Words the old table resolved
# to :stop or :suspend are left out, as the sweep leaves those commands out.
cp "$work/whim-vim" "$d/new"
python3 - "$d" <<'PY'
import concurrent.futures, os, shutil, subprocess, sys, tempfile
d = sys.argv[1]
home = tempfile.mkdtemp(prefix='cmdtable-home-', dir=d)
env = dict(os.environ, HOME=home, VIM=home + '/novim', VIMRUNTIME=home + '/novim',
           XDG_CONFIG_HOME=home + '/xdg')
for k in ('VIMINIT', 'EXINIT', 'MYVIMRC'):
    env.pop(k, None)
stage = {}
for b in ('old', 'new'):
    os.makedirs('%s/%s.bin' % (d, b))
    shutil.copy2('%s/%s' % (d, b), '%s/%s.bin/vim' % (d, b))
    stage[b] = '%s/%s.bin/vim' % (d, b)

words = []
for line in open(d + '/words'):
    w, old = line.rstrip('\n').split('\t')
    if old not in ('stop', 'suspend'):
        words.append(w)

# Command lines, not words: the address parser lost five switches' worth of arms,
# and these reach every address form on the commands that kept one.
LINES = ['%d', '.d', '$d', '2;3d', '1,2d', '3,1d', 'd 2', '2d 2', "'<,'>d", '*d', '-1d', '+1d',
         '2q', '%q', '$q', '.q', '0q', '1,2q', '%undo', '2undo', '0undo', '%messages', '3messages',
         '%normal Ax', '2,3>', '%<', 'g/a/d', 'v/a/d', '2k a', 'ka', "2mark b", '%s/a/X/g', '%&&',
         '2,3m0', '1t$', '1co$', '2,3j', '%p', '%#', '%l', '=', '1z', '.=', '2,3y', '0put', '$put',
         '2,3w! w.txt', '2,$w >> f.txt', 'r f.txt', '0r f.txt', '2cq', '%cq', '1,2~', '%@a',
         '2*', 'wq!', '2,3x', 'up', 'sav s.txt', 'e!', 'ene', 'vi', 'vie', 'ex', 'f n.txt',
         'set ts=3|%s/a/X/|w', 'ma b|2d|w', 'nmap|%s/a/X/|w', "dl", "dp", "2dl 2", 'Print', '2P',
         '++', '--', '{', '}', '!', '!ls', '#', '&', '1,2&', 'k', 'ke', 'sg', 'si', 'sI', 'sr', 'sc',
         'buffer|%s/a/X/|w', 'if 1|%s/a/X/|w', 'lua|%s/a/X/|w', 'n|%s/a/X/|w', 'h|%s/a/X/|w']
BAR = 'a stub no longer splits its line at the bar'
DIFFER = {'if': 'accepted, now an error', 'if 1|%s/a/X/|w': 'accepted, now an error',
          'buffer|%s/a/X/|w': BAR, 'n|%s/a/X/|w': BAR}
# h| is the control: :help's row never had EX_TRLBAR, so its bar was never a
# separator, and it must come out the same.

def run(b, cmd):
    w = tempfile.mkdtemp(prefix='c-', dir=d)
    try:
        open(w + '/f.txt', 'w').write('a\nba\nca\n')
        r = subprocess.run([stage[b], '-e', '-s', '+' + cmd, '+q!', 'f.txt'], cwd=w, env=env,
                           stdin=subprocess.DEVNULL, capture_output=True, timeout=20,
                           start_new_session=True)
        left = sorted(os.listdir(w))
        body = open(w + '/f.txt', errors='replace').read() if os.path.exists(w + '/f.txt') else None
        return (r.returncode, r.stderr, left, body)
    except subprocess.TimeoutExpired:
        return ('TIMEOUT',)
    finally:
        shutil.rmtree(w, ignore_errors=True)

todo = sorted(set(words) | set(LINES))
with concurrent.futures.ThreadPoolExecutor(max_workers=os.cpu_count() or 1) as ex:
    old = dict(zip(todo, ex.map(lambda c: run('old', c), todo)))
    new = dict(zip(todo, ex.map(lambda c: run('new', c), todo)))
got = sorted(c for c in todo if old[c] != new[c])
if got != sorted(DIFFER):
    print('  cmdtable     old and new binaries differ on %d command lines:' % len(got))
    for c in got[:20]:
        print('                 %-18r old %r' % (c, old[c][:2]))
        print('                 %-18s new %r' % ('', new[c][:2]))
    print('                 expected exactly: %s' % sorted(DIFFER))
    sys.exit(1)
if old['if'][0] != 0 or new['if'][0] != 1:
    sys.exit('  cmdtable     :if was expected to go from exit 0 to 1: %r -> %r' % (old['if'][:1], new['if'][:1]))
for c in ('buffer|%s/a/X/|w', 'n|%s/a/X/|w'):
    if old[c][3] != 'X\nbX\ncX\n' or new[c][3] != 'a\nba\nca\n':
        sys.exit('  cmdtable     %r: expected the old binary to substitute and write, the new not to: %r -> %r'
                 % (c, old[c][3], new[c][3]))
print('  cmdtable     %d words and %d command lines through both binaries: identical but for %s'
      % (len(words), len(LINES), ', '.join('%s (%s)' % kv for kv in sorted(DIFFER.items()))))
PY

# --- the delta, cumulative --------------------------------------------------
# Phase 79's list, and every removed row: the sweep dispatches the names in the
# table, so a row that goes is a row whose result goes.
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
    jumps clearjumps \
    $REMOVED
