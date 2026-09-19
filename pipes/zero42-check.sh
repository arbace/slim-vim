#!/bin/sh
# Zero phase 42's proof -- the swap file's residue.  See pipes/zero42-edit.sh.
#
# Usage: pipes/zero42-check.sh <work-dir> <state-dir>    (run from the repository root)
#
# THE DECLARED DELTA IS NOTHING AT ALL, AND IT IS TWO DIFFERENT KINDS AT ONCE.  Four
# zero phases have declared nothing before, for four different reasons (CLAUDE.md,
# *Verification tiers*), and this one phase is two of them in the same edit:
#
#   THE NEGATIVE-BLOCK HALF IS PHASE 9'S KIND -- code that COULD NOT RUN.  The chain the
#   edit computes says `negative` is FALSE at every call, so mf_trans_add() returns
#   before it does anything and ml_find_line()'s `bnum < 0` arm is unreachable.  A
#   recording cannot show that, because there is nothing to show; what shows it is an
#   INSTRUMENTED PAIR, and this check builds it rather than citing one.  Four markers, on
#   the four places a negative block number would be made, translated or followed, and a
#   control OF IDENTICAL SHAPE in ml_new_data(), which every buffer reaches.  Measured on
#   the input, over the 102 screen cases, the Ex sweep, the argv sweep and eight stress
#   sessions: the four fire in NONE and the control fires in nearly all.
#
#   THE BLOCK-ZERO HALF IS PHASE 12'S KIND -- code that RUNS and the instrument cannot
#   see.  ml_open() fills the header for every buffer in every session, and nothing ever
#   reads it back, so the corpus executes this code everywhere and is blind to it.  The
#   same instrumented build says so with its other three markers, which fire in almost
#   every record -- and the two full recordings are byte-identical anyway.  An empty
#   declaration means something different in each half, and the check says which is
#   which rather than letting one number stand for both.
#
# THE BINARY IS NOT BYTE-IDENTICAL and this phase does not pretend otherwise: code goes,
# a memline's block numbers move down by one, and a pointer-block entry gets smaller.  So
# tier 1 of CLAUDE.md's table is out of reach and the evidence is arranged in the shape
# that table's second half describes -- a byte-identical RECORDING with controls that
# move it.
#
# THE FANOUT CHANGES, AND THAT IS WHAT PHASE 40 IS FOR.  `pe_old_lnum` is a member of
# PTR_EN, so taking it makes each pointer-block entry smaller and MORE OF THEM FIT IN A
# PAGE.  The tree is therefore shaped differently after this phase and the root pointer
# block overflows LATER.  Not one of the 102 screen cases can see that: measured, a
# binary with ml_append_int()'s root test left at the OLD block number -- a real bug, the
# root not kept where ml_find_line() starts -- draws all 102 of them IDENTICALLY, and all
# four of the survey's own deep cases with them.
#
# THIS IS THE FIRST MEMLINE CHANGE SINCE ZERO PHASE 40, which added a corpus of buffers
# big enough to have a tree for exactly this reason, and that corpus is the only recorded
# thing that tells the two apart: section 7b.  It also NARROWS what phase 40 reaches, and
# the check asserts that as an inequality rather than as a count -- phase 40 sized its
# buffers from `sizeof(PTR_EN)`, and a phase that makes a pointer block hold MORE children
# can only move cases out of the root-splitting set, never into it.  Section 8 is then the
# direct proof, at sixty thousand lines, with an instrument on the branch itself.
set -eu

work=${1:?usage: zero42-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero42-check.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
TAG=swapres
say() { printf '  %-12s %s\n' "$TAG" "$1"; }
die() { printf '  %-12s %s\n' "$TAG" "$1"; exit 1; }

[ -f "$state/old.c" ] || die "the edit left no \$state/old.c"
[ -f "$state/edit.c" ] || die "the edit left no \$state/edit.c, so what the EDIT removed and what the SWEEP removed cannot be told apart"
[ -f "$state/old" ] || die "the edit left no input binary"

cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")

# The output binary, and every variant, built at once.
cp "$f" "$tmp/new.c"
# shellcheck disable=SC2086
( SOURCE_DATE_EPOCH=0 gcc $cflags $ldflags -o "$tmp/new" "$tmp/new.c" 2>"$tmp/e.new" ) &
pid_new=$!

python3 - "$state/old.c" "$f" "$tmp" <<'PY'
import sys
TAG = 'swapres'
old, new, tmp = (open(sys.argv[1], errors='surrogateescape').read(),
                 open(sys.argv[2], errors='surrogateescape').read(), sys.argv[3])


def one(text, s, what):
    if text.count(s) != 1:
        sys.exit('  %-12s `%s` is not in that source exactly once, so a control built '
                 'from it would not be one' % (TAG, what))
    return s


# THE INSTRUMENT, on the INPUT, because only the input still has both halves of this
# phase in it.  Eleven counters and a line to stderr from host_exit(), which every
# session reaches.  Four are the negative-block half, three are the block zero half,
# three are the controls -- ml_new_data(), which every buffer reaches; the root split,
# which almost nothing reaches; and ml_find_line()'s descent into a pointer block.
# NOTHING above the boundary calls libc here: the counters are plain increments and the
# printing is done below the boundary, where <unistd.h> is (zero phase 30's lesson).
NAMES = ['neg_new', 'neg_add', 'neg_del', 'neg_find', 'ctl_data',
         'b0_open', 'b0_flags', 'b0_fname', 'split_seen', 'split_root', 'find_ptr']
DECLS = 'static long ' + ', '.join('probe_' + n for n in NAMES) + ';\n\n'
BODY = '''
    static void
probe_num(long v)
{
    char b[24];
    int i = 24;

    if (v == 0)
    {
        b[--i] = '0';
    }
    while (v > 0)
    {
        b[--i] = (char)('0' + v %% 10);
        v /= 10;
    }
    write(2, b + i, (usize)(24 - i));
}

    static void
probe_dump(void)
{
    write(2, "PROBE", 5);
%s
    write(2, "\\n", 1);
}

''' % '\n'.join('    write(2, " %s=", %d);\n    probe_num(probe_%s);'
                % (n, len(n) + 2, n) for n in NAMES)
EXIT = one(old, '    static void\nhost_exit(int r)\n{\n', 'host_exit()')
if 'probe_neg_new' in old:
    sys.exit('  %-12s the input already says `probe_neg_new`' % TAG)

# EACH MARKER'S PLACE IS WRITTEN OUT AND NOT COMPUTED FROM THE ANCHOR'S INDENT.  Two of
# these anchors OPEN a block -- `if (negative) {` and `if (bnum < 0) {` -- so a counter
# put in front of them counts every call rather than the arm, and the instrument would
# then report the unreachable island as reachable.  Measured: an earlier draft of this
# check computed the indent and refused with `neg_new neg_find fired in a recorded
# session`, which is this check failing correctly on itself.  So each anchor and the text
# that replaces it are both written out.
MARKS = [
    # the four the phase claims cannot run
    ('neg_new', '''        if (negative)
        {
            hp-> bh_hashitem.mhi_key  = mfp->mf_blocknr_min--;''',
     '''        if (negative)
        {
            probe_neg_new++;
            hp-> bh_hashitem.mhi_key  = mfp->mf_blocknr_min--;''',
     "mf_new()'s negative branch"),
    ('neg_add', '''    if (hp-> bh_hashitem.mhi_key  >= 0)
    {
        return OK;
    }
''', '''    if (hp-> bh_hashitem.mhi_key  >= 0)
    {
        return OK;
    }
    probe_neg_add++;
''', 'mf_trans_add() past its early return'),
    ('neg_del', '''    if (np == nullptr)
    {
        return old_nr;
    }
''', '''    if (np == nullptr)
    {
        return old_nr;
    }
    probe_neg_del++;
''', 'mf_trans_del() past its early return'),
    ('neg_find', '''                if (bnum < 0)
                {
                    bnum2 = mf_trans_del(mfp, bnum);''',
     '''                if (bnum < 0)
                {
                    probe_neg_find++;
                    bnum2 = mf_trans_del(mfp, bnum);''',
     "ml_find_line()'s negative-block arm"),
    # the control of identical shape, in a function every buffer reaches
    ('ctl_data', '''ml_new_data(memfile_T *mfp, int negative, int page_count)
{''', '''ml_new_data(memfile_T *mfp, int negative, int page_count)
{
    probe_ctl_data++;''', 'ml_new_data()'),
    # the block-zero half, which RUNS
    ('b0_open', '    b0p->b0_id[0] = BLOCK0_ID0;',
     '    probe_b0_open++;\n    b0p->b0_id[0] = BLOCK0_ID0;',
     "ml_open()'s first header write"),
    ('b0_flags', '''            b0p = (ZERO_BL *)(hp->bh_data);
            b0p-> b0_fname[B0_FNAME_SIZE_ORG - 1]  = buf->b_changed ? B0_DIRTY : 0;''',
     '''            b0p = (ZERO_BL *)(hp->bh_data);
            probe_b0_flags++;
            b0p-> b0_fname[B0_FNAME_SIZE_ORG - 1]  = buf->b_changed ? B0_DIRTY : 0;''',
     "ml_setflags()'s header write"),
    ('b0_fname', '''set_b0_fname(ZERO_BL *b0p, buf_T *buf)
{
''', '''set_b0_fname(ZERO_BL *b0p, buf_T *buf)
{
    probe_b0_fname++;
''', 'set_b0_fname()'),
    # the depth controls
    ('split_seen', '                hp_new = ml_new_ptr(mfp);',
     '                probe_split_seen++;\n                hp_new = ml_new_ptr(mfp);',
     "ml_append_int()'s split loop"),
    ('split_root', '''                 musl_memmove((char *)(pp_new), (char *)(pp), (usize)page_size) ;
                pp->pb_count = 1;''', '''                probe_split_root++;
                 musl_memmove((char *)(pp_new), (char *)(pp), (usize)page_size) ;
                pp->pb_count = 1;''', "ml_append_int()'s root-preserving branch"),
    ('find_ptr', '        if ((top = ml_add_stack(buf)) < 0)',
     '        probe_find_ptr++;\n        if ((top = ml_add_stack(buf)) < 0)',
     "ml_find_line()'s descent into a pointer block"),
]
p = old.replace('    static bhdr_T *\nmf_new(', DECLS + '    static bhdr_T *\nmf_new(', 1)
if p == old:
    sys.exit('  %-12s mf_new() is not defined in this tree\'s shape, so the counters '
             'have nowhere to go above their first use' % TAG)
for name, anchor, marked, what in MARKS:
    one(p, anchor, what)
    p = p.replace(anchor, marked, 1)
    if p.count('probe_%s++' % name) != 1:
        sys.exit('  %-12s the marker for %s was not planted exactly once' % (TAG, what))
p = p.replace(EXIT, BODY + EXIT + '    probe_dump();\n', 1)
open('%s/probe.c' % tmp, 'w', errors='surrogateescape').write(p)

# THE MUST-DIFFER CONTROLS.  Two are on the INPUT'S block zero, because the output has
# none; two are on the OUTPUT'S renumbering, because that is what only this phase can
# get wrong.
ctl = {}
ctl['c_open'] = old.replace('    b0p->b0_id[0] = BLOCK0_ID0;',
                            '    return FAIL;\n    b0p->b0_id[0] = BLOCK0_ID0;', 1)
ctl['c_bnum'] = new.replace('    pp->pb_pointer[0].pe_bnum = 1;',
                            '    pp->pb_pointer[0].pe_bnum = 2;', 1)
ctl['c_root'] = new.replace('                if (hp-> bh_hashitem.mhi_key  != 0)\n',
                            '                if (hp-> bh_hashitem.mhi_key  != 1)\n', 1)
for k, v in sorted(ctl.items()):
    base = old if k == 'c_open' else new
    if v == base:
        sys.exit('  %-12s the control %s changed nothing, so it would not be a control'
                 % (TAG, k))
    open('%s/%s.c' % (tmp, k), 'w', errors='surrogateescape').write(v)

# THE DEPTH INSTRUMENT: the root-preserving branch and the overflow that follows when it
# is not taken, on the OUTPUT and on c_root, which are the two sources section 8 drives.
DEP = 'static long pr_pres, pr_over;\n\n'
DBODY = BODY.replace('probe_num', 'pr_num').split('    static void\nprobe_dump')[0]
for side, text in (('wkp', new), ('rootp', ctl['c_root'])):
    q = text.replace('    static bhdr_T *\nmf_new(', DEP + '    static bhdr_T *\nmf_new(', 1)
    q = q.replace('''                 musl_memmove((char *)(pp_new), (char *)(pp), (usize)page_size) ;
                pp->pb_count = 1;''', '''                pr_pres++;
                 musl_memmove((char *)(pp_new), (char *)(pp), (usize)page_size) ;
                pp->pb_count = 1;''', 1)
    q = q.replace('            iemsg(e_updated_too_many_blocks);',
                  '            pr_over++;\n            iemsg(e_updated_too_many_blocks);', 1)
    q = q.replace(EXIT, DBODY + EXIT + '    write(2, "ROOTPROBE pres=", 15);\n'
                  '    pr_num(pr_pres);\n    write(2, " over=", 6);\n    pr_num(pr_over);\n'
                  '    write(2, "\\n", 1);\n', 1)
    if q.count('pr_pres++') != 1 or q.count('pr_over++') != 1 or 'ROOTPROBE' not in q:
        sys.exit('  %-12s the depth instrument did not plant on %s' % (TAG, side))
    open('%s/%s.c' % (tmp, side), 'w', errors='surrogateescape').write(q)
print('  %-12s six variants written: probe, the INPUT with eleven counters -- four on '
      'the negative-block island, three on block zero, and ml_new_data(), the root split '
      'and the pointer-block descent as controls; c_open, the input with its first '
      'header write replaced by `return FAIL;`; c_bnum and c_root, the output with each '
      'of the two block numbers this phase moved put back; and wkp and rootp, the output '
      'and c_root with a counter on the root-preserving branch and on the overflow that '
      'follows when it is not taken' % TAG)
PY

for v in probe c_open c_bnum c_root wkp rootp; do
    # shellcheck disable=SC2086
    ( SOURCE_DATE_EPOCH=0 gcc $cflags $ldflags -o "$tmp/$v" "$tmp/$v.c" 2>"$tmp/e.$v" ) &
    eval "pid_$v=\$!"
done
# tools/canon.sh must be a NO-OP on the output.
cp "$f" "$tmp/canon.c"
( tools/canon.sh "$tmp/canon.c" >"$tmp/canon.log" 2>&1 ) &
pid_canon=$!

# --- 1. the source: what the EDIT took and what the SWEEP took, separately ---------------
python3 - "$state/old.c" "$state/edit.c" "$f" "$(cat "$state/input-lines")" <<'PY'
import re
import sys
TAG = 'swapres'
old, mid, new = (open(p, errors='surrogateescape').read() for p in sys.argv[1:4])
declared_in = int(sys.argv[4])


def die(msg):
    sys.exit('  %-12s %s' % (TAG, msg))


def say(what):
    print('  %-12s %s' % (TAG, what))


def n(text):
    return text.count('\n')


def words(text):
    return set(re.findall(r'[A-Za-z_]\w*', text))


if n(old) != declared_in:
    die('the text the edit was handed is %d lines and the driver recorded %d'
        % (n(old), declared_in))
say('%d -> %d -> %d lines: the EDIT took %d and the SWEEP took %d more, %d altogether'
    % (n(old), n(mid), n(new), n(old) - n(mid), n(mid) - n(new), n(old) - n(new)))

# EVERY NAME THAT LEAVES, IN THREE SETS, AND THE THREE SETS ARE A PARTITION OF THE
# DIFFERENCE.  Nothing may leave that this phase does not account for, and nothing may
# ARRIVE at all: the edit adds no name to the file.
EDIT = {
    'mf_dirty': 'the write-only dirtiness field',
    'mfdirty_T': 'its type',
    'MF_DIRTY_NO': 'its three values',
    'MF_DIRTY_YES': 'its three values',
    'MF_DIRTY_YES_NOSYNC': 'its three values',
    'mf_sync': 'a function whose whole body wrote that field',
    'mf_trans': 'the translation table for negative blocks',
    'mf_trans_add': 'the function that filled it, which returned before it did anything',
    'mf_trans_del': 'the function that read it',
    'mf_blocknr_min': 'the lowest negative block number',
    'mf_neg_count': 'the count of negative blocks',
    'newfile': "ml_append()'s parameter, FALSE at every call site",
    'infile': "mf_put()'s parameter, the one that called the no-op",
    'pe_old_lnum': 'a write-only pointer-block field',
    'lnum_left': 'a local written only to feed it',
    'lnum_right': 'a local written only to feed it',
    'bnum2': "ml_find_line()'s local for a translated block number",
    'mf_dont_release': 'a file-scope int read twice and assigned nowhere',
    'new_bnum': 'a local of mf_trans_add()',
    'old_nr': 'a parameter of mf_trans_del()',
    'dirty': "mf_put()'s parameter and ml_find_line()'s local",
    'VIM': 'the four bytes copied into the header\'s version field',
}
SWEEP = {
    'ZERO_BL': 'a type nothing reaches',
    'block0': 'its struct tag',
    'b0p': 'the only pointer to it',
    'b0_id': 'a header field',
    'b0_version': 'a header field',
    'b0_page_size': 'a header field',
    'b0_fname': 'a header field',
    'b0_magic_long': 'a header field',
    'b0_magic_int': 'a header field',
    'b0_magic_short': 'a header field',
    'b0_magic_char': 'a header field',
    'BLOCK0_ID0': 'an enumerator nothing mentions',
    'BLOCK0_ID1': 'an enumerator nothing mentions',
    'B0_FNAME_SIZE_ORG': 'an enumerator nothing mentions',
    'B0_MAGIC_LONG': 'an enumerator nothing mentions',
    'B0_MAGIC_INT': 'an enumerator nothing mentions',
    'B0_MAGIC_SHORT': 'an enumerator nothing mentions',
    'B0_MAGIC_CHAR': 'an enumerator nothing mentions',
    'B0_DIRTY': 'an enumerator nothing mentions',
    'BH_DIRTY': 'an enumerator nothing mentions',
    'MFS_ZERO': 'an enumerator nothing mentions',
    'ML_APPEND_NEW': 'an enumerator nothing mentions',
    'ML_LOCKED_DIRTY': 'an enumerator nothing mentions',
    'ML_LOCKED_POS': 'an enumerator nothing mentions',
    'NR_TRANS': 'a type nothing reaches',
    'nr_trans': 'its struct tag',
    'nt_hashitem': 'its fields',
    'nt_new_bnum': 'its fields',
    'set_b0_fname': 'a static function with no caller',
    'long_to_char': 'a static function with no caller',
    'ml_setflags': 'a static function with no caller',
    'mf_hash_free_all': 'a static function with no caller',
    'Version': 'a static object nothing reads',
    'VIM_VERSION_SHORT': 'the only thing it held',
    'e_didnt_get_block_nr_two': 'a static object nothing reads',
}
LITERAL = {'x10111213L', 'x20212223L', 'x30313233L', 'x55'}
wo, wm, wn = words(old), words(mid), words(new)
if wn - wo:
    die('the phase introduces %d names the input did not have (%s), and it must '
        'introduce none' % (len(wn - wo), ' '.join(sorted(wn - wo))))
gone_edit, gone_sweep = wo - wm, wm - wn
for what, got, want in (('EDIT', gone_edit, set(EDIT)), ('SWEEP', gone_sweep, set(SWEEP))):
    extra, missing = got - want - LITERAL, want - got
    if extra or missing:
        die('the %s removes %s and this phase accounts for %s -- unaccounted: %s; '
            'accounted but still here: %s'
            % (what, len(got), len(want), ' '.join(sorted(extra)) or 'none',
               ' '.join(sorted(missing)) or 'none'))
say('%d names leave in the EDIT and %d more in the SWEEP, and every one is accounted '
    'for.  THE DIVISION IS THE PHASE\'S WHOLE ARGUMENT: nothing that is WRITTEN is in '
    'the sweep\'s set, because no tool in tools/ can see a write -- the edit\'s set is '
    'four write-only fields, a write-only state machine, two unreachable functions, four '
    'parameters and four locals; the sweep\'s is what those left behind, %d of them '
    'enumerators and %d functions with no caller'
    % (len(gone_edit), len(gone_sweep),
       sum(1 for k, v in SWEEP.items() if 'enumerator' in v),
       sum(1 for k, v in SWEEP.items() if 'function' in v)))

# THE SIGNATURES, which are what a later reader will see of this phase.
for sig, what in (
        ('mf_new(memfile_T *mfp, int page_count)', 'mf_new() takes no `negative`'),
        ('mf_put(bhdr_T *hp)', 'mf_put() takes neither a memfile nor a state'),
        ('ml_new_data(memfile_T *mfp, int page_count)', 'ml_new_data() takes no `negative`'),
        ('ml_append(linenr_T    lnum, char_u      *line, colnr_T     len)',
         'ml_append() takes no `newfile`')):
    if new.count(sig) != 1:
        die('%s -- `%s` is in the output %d times' % (what, sig, new.count(sig)))
say('the four signatures this phase narrows are each in the output exactly once: '
    'mf_new and ml_new_data without `negative`, ml_append without `newfile`, and mf_put '
    'as `mf_put(bhdr_T *hp)`')

# THE FIVE BLOCK NUMBERS, stated as a property of the output rather than as a diff.
if new.count('    bnum = 0;\n') != 1:
    die('ml_find_line() does not start its descent at block nr 0 exactly once')
tests = re.findall(r'^( *)if \(hp-> bh_hashitem\.mhi_key  != (\d)\)$', new, re.M)
shallow = [v for ind, v in tests if len(ind) == 4]
deep = [v for ind, v in tests if len(ind) > 4]
if shallow != ['0', '1'] or deep != ['0']:
    die('the output tests a block number in %d places -- %s -- and after this phase '
        'ml_open() tests 0 then 1 and ml_append_int() tests 0'
        % (len(tests), ' '.join('%d:%s' % (len(i), v) for i, v in tests)))
if new.count('    pp->pb_pointer[0].pe_bnum = 1;') != 1:
    die("ml_open()'s root does not point at block nr 1")
say('the two surviving blocks are numbered from 0: ml_find_line() descends from block '
    'nr 0, ml_open() takes block nr 0 for the root and block nr 1 for the data, and its '
    'root points at 1')

# The directives, and the one line that is the boundary.
d_old = [i for i, l in enumerate(old.split('\n')) if re.match(r'^ *# *', l)]
d_new = [i for i, l in enumerate(new.split('\n')) if re.match(r'^ *# *', l)]
if len(d_old) != len(d_new) or d_new != list(range(d_new[0], d_new[0] + len(d_new))):
    die('the output holds %d directives where the input held %d, or they are not '
        'contiguous' % (len(d_new), len(d_old)))
say('the %d `#include`s are untouched and contiguous, at line %d where they were at %d, '
    'and this phase adds no preprocessor line and removes none'
    % (len(d_new), d_new[0] + 1, d_old[0] + 1))
PY

# --- 2. the cut: the core is still plain C and the boundary has not moved ---------------
# `make editor.c`'s rule, one clause and no judgement (CLAUDE.md, *The core and the host
# are one file with a line in it*).  Both sides are cut, because what matters is that the
# interface is UNCHANGED: this phase deletes core code and must widen no core -> host
# call.
for side in old new; do
    src=$state/old.c
    [ "$side" = new ] && src=$f
    awk '/^ *# *include / { exit } { print }' "$src" > "$tmp/cut-$side.c"
    lines=$(grep -c '' "$tmp/cut-$side.c")
    [ "$lines" -gt 1000 ] || die "the $side cut is $lines lines, so the boundary is not where this check thinks"
    hashes=$(grep -c '^ *#' "$tmp/cut-$side.c" || true)
    [ "$hashes" = 0 ] || die "the $side cut holds $hashes preprocessor directives and the core may hold none"
    gcc -O0 -fno-stack-protector -fsyntax-only "$tmp/cut-$side.c" 2>"$tmp/syn-$side" || die "the $side cut does not compile on its own"
    grep -q 'error:' "$tmp/syn-$side" && die "the $side cut draws an error under -fsyntax-only"
    gcc -c -O0 -fno-stack-protector -o "$tmp/cut-$side.o" "$tmp/cut-$side.c" 2>&1 |
        sed -n "s/.*warning: '\([A-Za-z_0-9]*\)' used but never defined.*/\1/p" |
        sort -u > "$tmp/iface-$side"
    eval "cut_$side=\$lines"
done
cmp -s "$tmp/iface-old" "$tmp/iface-new" ||
    die "the core -> host interface moved: $(comm -3 "$tmp/iface-old" "$tmp/iface-new" | tr -d '\t' | tr '\n' ' ')"
say "the cut is $cut_old -> $cut_new lines, every line this phase removes is ABOVE the boundary, 0 of them begin with \`#\`, both draw 0 errors under -fsyntax-only, and the core -> host interface is the same $(grep -c '' "$tmp/iface-new") names either side: $(tr '\n' ' ' < "$tmp/iface-new")"

# --- 3. the tools that assert a place, a floor and a linkage ----------------------------
wait $pid_new || { die "the output did not build: $(head -3 "$tmp/e.new")"; }
new_size=$(stat -c%s "$tmp/new")
old_size=$(stat -c%s "$state/old")
python3 tools/zhostonly.py "$f"
python3 tools/orphanopts.py "$f"
tools/phasecheck.sh "$work" "$f" "$state/symbols"
wait $pid_canon || die "tools/canon.sh failed on the output"
cmp -s "$tmp/canon.c" "$f" || die "tools/canon.sh is not a no-op on the output: $(tail -1 "$tmp/canon.log")"
say "tools/canon.sh is a no-op on the output, so the file the sweep left is canonical"

# THIS PHASE FREES NO LIBC SYMBOL AND SAYS SO AS AN EQUALITY.  It removes core code and
# moves no call across the boundary, so the undefined set cannot move -- and an equality
# is a stronger statement than a count, because it names what would have had to change.
gcc -c -O0 -fno-stack-protector -o "$tmp/old.o" "$state/old.c" 2>/dev/null
nm -u "$tmp/old.o" | awk '{print $2}' | sort > "$tmp/u-old"
gcc -c -O0 -fno-stack-protector -o "$tmp/new.o" "$f" 2>/dev/null
nm -u "$tmp/new.o" | awk '{print $2}' | sort > "$tmp/u-new"
cmp -s "$tmp/u-old" "$tmp/u-new" ||
    die "the undefined set moved by $(comm -3 "$tmp/u-old" "$tmp/u-new" | tr -d '\t' | tr '\n' ' ') and this phase frees none"
ext=$(nm --extern-only --defined-only "$tmp/new.o" | awk '{print $3}' | tr '\n' ' ')
[ "$ext" = "main " ] || die "the object defines \`$ext\` where it must define exactly main"
say "the undefined set is UNCHANGED, $(grep -c '' "$tmp/u-new") names either side -- $(tr '\n' ' ' < "$tmp/u-new")-- and \`nm --extern-only --defined-only\` prints exactly main.  A phase that deletes core code and crosses no boundary frees no symbol, and this is that stated as an equality rather than as a count"
say "the binary is $old_size bytes in and $new_size out, $((old_size - new_size)) fewer"

# --- 4. the two recordings, and they are byte-identical ---------------------------------
# tools/zrecord.sh is the instrument zero has (ZERO-PLAN.md 2): 102 keystroke cases, the
# Ex sweep, the argv sweep, four pty scenarios and the terminal table.  This phase
# declares NOTHING, so the two recordings must be the same bytes, and tools/zerodelta.sh
# says the same thing against the baselines when tools/phaserun.sh runs it after this
# check.  Both are here because they answer different questions: this one is old against
# new, that one is new against whim.
tools/zrecord.sh "$state/old" "$state/old.c" "$tmp/REC-old" >/dev/null &
pid_rold=$!
tools/zrecord.sh "$tmp/new" "$tmp/new.c" "$tmp/REC-new" >/dev/null &
pid_rnew=$!
wait $pid_rold || die "the input binary could not be recorded"
wait $pid_rnew || die "the output binary could not be recorded"
diff -r "$tmp/REC-old" "$tmp/REC-new" > "$tmp/recdiff" 2>&1 ||
    die "the recordings differ, and this phase declares nothing: $(head -4 "$tmp/recdiff")"
say "TWO FULL RECORDINGS, BYTE-IDENTICAL: $(ls "$tmp/REC-new/screen" | grep -c '') screen cases, $(ls "$tmp/REC-new/memline" | grep -c '') memline cases, the Ex sweep, the argv sweep, the pty scenarios and the terminal table, from the binary the edit was handed and from the one it produced"

# --- 5. the probes, both halves, and they are invisible for OPPOSITE reasons -------------
wait $pid_probe || { die "the instrumented build failed: $(head -3 "$tmp/e.probe")"; }
python3 tools/zcases.py "$tmp/probe" "$tmp/SC-probe" >/dev/null 2>&1 &
pid_sc=$!
python3 tools/zexcmds.py "$tmp/probe" "$tmp/probe.c" "$tmp/ex-probe.txt" >/dev/null 2>&1 &
pid_ex=$!
python3 tools/zargv.py "$tmp/probe" "$tmp/argv-probe.txt" >/dev/null 2>&1 &
pid_av=$!
# PHASE 40'S SIXTEEN CASES ARE PART OF A RECORDING NOW, and they are the part that
# works the text layer hardest -- which is exactly where a negative block number would
# appear if anywhere in this pipeline could make one.  So they are instrumented with the
# rest rather than only in 7b, and the tally below counts their records with the others.
python3 tools/zmemline.py "$tmp/probe" "$tmp/ML-in" >/dev/null 2>&1 &
pid_ml=$!
# The eight stress sessions the corpus has no room for: they are what reaches the
# pointer-block machinery at all, and the instrument is asked about them too.
python3 - "$tmp/probe" "$tmp/stress-probe.txt" <<'PY' &
import sys
sys.path.insert(0, 'tools')
import zstream
E = b'\x1b'


def L(n, f):
    return [b'i'] + [f(i) for i in range(n)] + [E]


CASES = {
    '4k lines': L(4000, lambda i: b'line %d of the buffer here\n' % i) + [b'G', b':q!\r'],
    '25k lines': [b'i'] + [b'x' * 19 + b'\n'] * 25000 + [E, b'G', b':q!\r'],
    '25k dGG+undo': [b'i'] + [b'y' * 19 + b'\n'] * 25000 + [E, b'ggdG', b'u', b'G', b':q!\r'],
    '25k mid-delete': [b'i'] + [b'z%d\n' % i for i in range(25000)] + [E, b'12000G']
                      + [b'dd'] * 2000 + [b'G', b':q!\r'],
    '25k sort': [b'i'] + [b'%d\n' % (7919 * i % 99991) for i in range(25000)]
                + [E, b':sort\r', b'G', b':q!\r'],
    'mid churn': L(2000, lambda i: b'abcdefghij%d\n' % i) + [b'1000Gdd'] * 300 + [b'G', b':q!\r'],
    'sort big': L(3000, lambda i: b's%d\n' % (7919 * i % 10000)) + [b':sort\r', b'G', b':q!\r'],
    'join all': L(2000, lambda i: b'j%d\n' % i) + [b'gg', b'2000J', b':q!\r'],
}
out = []
for name, keys in CASES.items():
    r = zstream.session(sys.argv[1], keys, timeout=600)
    out.append('%s rc=%s\n%s\n' % (name, r[3], r[2].decode('utf-8', 'replace')))
open(sys.argv[2], 'w').write(''.join(out))
PY
pid_st=$!
wait $pid_sc || die "the screen corpus failed on the instrumented build"
wait $pid_ex || die "the Ex sweep failed on the instrumented build"
wait $pid_av || die "the argv sweep failed on the instrumented build"
wait $pid_ml || die "phase 40's memline corpus failed on the instrumented build"
wait $pid_st || die "the stress sessions failed on the instrumented build"

python3 - "$tmp" <<'PY'
import collections
import os
import re
import sys
TAG, tmp = 'swapres', sys.argv[1]
NAMES = ['neg_new', 'neg_add', 'neg_del', 'neg_find', 'ctl_data',
         'b0_open', 'b0_flags', 'b0_fname', 'split_seen', 'split_root', 'find_ptr']
RX = re.compile(r'PROBE ' + ' '.join(r'%s=(\d+)' % n for n in NAMES))
tot, hit, nrec = collections.Counter(), collections.Counter(), 0


def scan(text):
    global nrec
    got = 0
    for m in RX.finditer(text):
        nrec += 1
        got += 1
        for k, v in zip(NAMES, m.groups()):
            v = int(v)
            tot[k] += v
            if v:
                hit[k] += 1
    return got


d = '%s/SC-probe' % tmp
files = sorted(os.listdir(d))
marked = sum(1 for n in files
             if scan(open(os.path.join(d, n), errors='surrogateescape').read()))
if marked != len(files) or not files:
    sys.exit('  %-12s the instrumented build marked %d of %d screen cases, and it must '
             'mark every one -- the counters are printed from host_exit(), which every '
             'case reaches' % (TAG, marked, len(files)))
for extra in ('ex-probe.txt', 'argv-probe.txt', 'stress-probe.txt'):
    scan(open('%s/%s' % (tmp, extra), errors='surrogateescape').read())
d2 = '%s/ML-in' % tmp
mem = sorted(os.listdir(d2))
memmarked = sum(1 for n in mem
                if scan(open(os.path.join(d2, n), errors='surrogateescape').read()))
if memmarked != len(mem) or not mem:
    sys.exit('  %-12s the instrumented build marked %d of %d memline cases, and it must '
             'mark every one' % (TAG, memmarked, len(mem)))
NEG = ['neg_new', 'neg_add', 'neg_del', 'neg_find']
B0 = ['b0_open', 'b0_flags', 'b0_fname']
bad = [k for k in NEG if hit[k]]
if bad:
    sys.exit('  %-12s %s fired in a recorded session, so the negative-block island is '
             'NOT unreachable and this phase must not remove it' % (TAG, ' '.join(bad)))
if hit['ctl_data'] < nrec // 2:
    sys.exit('  %-12s the control fired in %d of %d records, and an instrument that '
             'marks almost nothing proves nothing about the four that mark none'
             % (TAG, hit['ctl_data'], nrec))
if min(hit[k] for k in B0) < nrec // 2:
    sys.exit('  %-12s the block-zero markers fired in %s of %d records, and this half of '
             'the phase is code that RUNS -- an instrument that does not see it running '
             'is not measuring what the check claims'
             % (TAG, '/'.join(str(hit[k]) for k in B0), nrec))
print('  %-12s THE NEGATIVE-BLOCK HALF IS PHASE 9\'S KIND -- CODE THAT COULD NOT RUN: '
      'the four markers on mf_new()\'s negative branch, mf_trans_add() past its early '
      'return, mf_trans_del() past its own and ml_find_line()\'s `bnum < 0` arm fired in '
      '0 of %d records -- %d screen, %d memline, %d from the two sweeps and %d stress '
      'sessions -- against a control of identical shape in ml_new_data() that fired '
      'in %d of them, %d times'
      % (TAG, nrec, len(files), len(mem), nrec - len(files) - len(mem) - 8, 8,
         hit['ctl_data'], tot['ctl_data']))
print('  %-12s THE BLOCK-ZERO HALF IS PHASE 12\'S KIND -- CODE THAT RUNS AND THE '
      'INSTRUMENT CANNOT SEE: the three markers on the header writes fired in %s of %d '
      'records, %s times, and the two full recordings above are the same bytes.  An '
      'empty declaration is a different statement in each half, and only the second one '
      'is about the harness'
      % (TAG, '/'.join(str(hit[k]) for k in B0), nrec,
         '/'.join(str(tot[k]) for k in B0)))
print('  %-12s AND THE CORPUS CANNOT SEE THE ROOT AT ALL: ml_find_line() descended into '
      'a pointer block in %d of %d records and %d times, but ml_append_int()\'s split '
      'loop was reached in %d and its root-preserving branch in %d.  That is why '
      'sections 7b and 8 exist: phase 40\'s memline corpus, and sixty thousand lines '
      'driven by hand'
      % (TAG, hit['find_ptr'], nrec, tot['find_ptr'], hit['split_seen'], hit['split_root']))
PY

# --- 6. the controls that MUST move the recording ----------------------------------------
# Section 4's diff is worth something only if the corpus can see this part of the editor
# at all, and two of the three controls say it can.  The third says something else and
# the check states it rather than hiding it.
wait $pid_c_open || die "c_open did not build"
wait $pid_c_bnum || die "c_bnum did not build"
wait $pid_c_root || die "c_root did not build"
for v in c_open c_bnum c_root; do
    python3 tools/zcases.py "$tmp/$v" "$tmp/SC-$v" >/dev/null 2>&1 &
    eval "pid_sc_$v=\$!"
done
for v in c_open c_bnum c_root; do
    eval "wait \$pid_sc_$v" || die "the screen corpus failed on $v"
    eval "d_$v=\$(diff -rq \"\$tmp/REC-new/screen\" \"\$tmp/SC-$v\" | grep -c '' || true)"
done
total=$(ls "$tmp/REC-new/screen" | grep -c '')
[ "$d_c_open" = "$total" ] || die "c_open -- the input's first header write replaced by \`return FAIL;\` -- moves $d_c_open of $total screen cases, and it must move every one"
[ "$d_c_bnum" = "$total" ] || die "c_bnum -- ml_open()'s root pointing at the old block number -- moves $d_c_bnum of $total screen cases, and it must move every one"
[ "$d_c_root" = 0 ] || die "c_root moves $d_c_root screen cases, and the measurement this check is built on is that it moves none"
say "the controls: c_open moves $d_c_open of $total screen cases and c_bnum moves $d_c_bnum, so the corpus can see both ml_open() and the block numbering -- and c_root moves $d_c_root, which is the finding sections 7b and 8 are for: the ONE line of this phase that every one of the 102 screen cases is blind to"

# --- 7. BH_LOCKED is NOT BH_DIRTY's twin, surveyed and not taken --------------------------
# It looks like one: a bit of the same word, set in mf_get() and cleared in mf_put().  It
# is read, by mf_put()'s own `e_block_was_not_locked` test, and this phase leaves it
# alone.  What makes that worth stating is that the corpus cannot tell: the only reader
# is an internal-error test, so a binary that never clears the bit simply never fires it.
# Unreachable EVIDENCE is not unreachable code, and the difference is the whole of why
# BH_DIRTY goes and BH_LOCKED stays.
grep -q 'BH_LOCKED' "$f" || die "BH_LOCKED has gone, and this phase does not remove it"
say "BH_LOCKED stays: it is read by mf_put()'s \`e_block_was_not_locked\` test, which is the one thing bh_flags is asked, and $(grep -c 'BH_LOCKED' "$f") mentions of it survive"

# --- 7b. phase 40's memline corpus, the instrument that CAN see this phase ---------------
# Zero phase 40 exists because the 102 screen cases each allocate exactly ONE data block,
# so the text layer is a tree with one entry and forty phases had been verified by an
# instrument that could not see a corrupted one.  THIS IS THE FIRST MEMLINE CHANGE SINCE
# THAT CORPUS EXISTS, and the corpus is part of tools/zrecord.sh, so section 4's
# byte-identical recording already includes its sixteen cases.  What is measured here is
# the other half: that the corpus can TELL, and how this phase changes what it reaches.
python3 tools/zmemline.py "$tmp/c_root" "$tmp/ML-croot" >/dev/null 2>&1 ||
    die "phase 40's corpus failed on the c_root control"
python3 tools/zmemline.py "$tmp/wkp" "$tmp/ML-out" >/dev/null 2>&1 ||
    die "phase 40's corpus failed on the instrumented output"
[ -d "$tmp/ML-in" ] || die "section 5 left no instrumented memline record"
[ -d "$tmp/REC-new/memline" ] ||
    die "tools/zrecord.sh recorded no memline/, so phase 40's corpus is not in the recording this check compares"
moved=$(diff -rq "$tmp/REC-new/memline" "$tmp/ML-croot" | sed 's/.*memline\/\([a-z_]*\) .*/\1/' | tr '\n' ' ' | sed 's/ *$//')
[ -n "$moved" ] ||
    die "the c_root control moves NONE of phase 40's cases, so nothing in this pipeline can see ml_append_int()'s root test"
case " $moved " in
    *" mem_deep_jumps "*) ;;
    *) die "the c_root control moves $moved, and mem_deep_jumps is the case measured to reach the root split on THIS phase's output" ;;
esac
ml_in=$(grep -l 'split_root=[1-9]' "$tmp"/ML-in/* | wc -l)
ml_out=$(grep -l 'ROOTPROBE pres=[1-9]' "$tmp"/ML-out/* | wc -l)
[ "$ml_out" -ge 1 ] || die "no case of phase 40's corpus reaches the root split on this phase's output"
[ "$ml_in" -gt "$ml_out" ] ||
    die "phase 40's corpus reaches the root split in $ml_in cases on the input and $ml_out on the output, and this phase can only make a pointer block hold MORE children, never fewer"
say "PHASE 40'S CORPUS SEES THIS PHASE, and it is the only recorded thing that does: the c_root control -- ml_append_int()'s root test left at the old block number, which all 102 screen cases are blind to -- moves $moved of its sixteen cases.  AND THIS PHASE NARROWS WHAT THAT CORPUS REACHES: $ml_in of the sixteen split the root on the input and $ml_out on the output, because phase 40 derived its buffer sizes from sizeof(PTR_EN) and pe_old_lnum has left PTR_EN.  A case named for the root split is a case sized for a fanout, and this phase changes the fanout"

# --- 8. the root split, which only sixty thousand lines reach ------------------------------
wait $pid_wkp || die "the depth instrument on the output did not build"
wait $pid_rootp || die "the depth instrument on c_root did not build"
python3 - "$tmp" "$state/old" "$tmp/new" <<'PY'
import hashlib
import re
import sys
sys.path.insert(0, 'tools')
import zstream
TAG, tmp, old, new = 'swapres', sys.argv[1], sys.argv[2], sys.argv[3]
E = b'\x1b'


def die(msg):
    sys.exit('  %-12s %s' % (TAG, msg))


def keys(n):
    return [b'i'] + [b'x' * 19 + b'\n'] * n + [E, b'G', b'%dG' % (n // 2), b':q!\r']


def reads(n):
    k = [b'i'] + [b'L%07d\n' % i for i in range(n)] + [E]
    return k + [b'%dG' % j for j in (1, 1000, n // 2, n - 1)] + [b'gg', b'G', b':q!\r']


# UNDO'S MESSAGE CARRIES A WALL CLOCK -- `1 change; before #1  0 seconds ago` -- and at
# this size building the buffer takes long enough for that number to move between runs.
# Measured on the binary the edit was HANDED, five runs of the undo case below: four said
# `0 seconds ago` and one said `1 second ago`, which is a difference between a binary and
# ITSELF.  So the comparison reads the stream with that phrase folded to a constant, and
# the case that needs the folding is required to contain it -- a normalisation nothing
# matches would be a normalisation hiding something.
CLOCK = re.compile(rb'\d+ seconds? ago')


def run(binary, k, timeout=900):
    r = zstream.session(binary, k, timeout=timeout)
    return r[3], hashlib.sha256(CLOCK.sub(b'<CLOCK>', r[1])).hexdigest()[:16], r[2], r[1]


# FIRST: the instrument says the root really is split at this size, on the OUTPUT, and
# that the control instead runs off the top of the tree.  Without this the comparison
# below would be two binaries agreeing about a branch neither of them took.
RX = re.compile(rb'ROOTPROBE pres=(\d+) over=(\d+)')
got = {}
for side in ('wkp', 'rootp'):
    rc, sha, err, raw = run('%s/%s' % (tmp, side), keys(60000))
    m = RX.search(err)
    if not m:
        die('the depth instrument on %s printed no ROOTPROBE line' % side)
    got[side] = (int(m.group(1)), int(m.group(2)), sha)
if got['wkp'][0] < 1 or got['wkp'][1]:
    die('at sixty thousand lines the OUTPUT preserved the root %d times and overflowed '
        '%d -- it must preserve it at least once and never overflow, or this case is not '
        'reaching the line the phase moves' % got['wkp'][:2])
if got['rootp'][0] or got['rootp'][1] < 1:
    die('the control with the old block number preserved the root %d times and '
        'overflowed %d -- it must do the opposite, or it is not a control' % got['rootp'][:2])
if got['wkp'][2] == got['rootp'][2]:
    die('the output and the wrong-number control draw the same screen even at sixty '
        'thousand lines, so nothing in this check can see the root test at all')
print('  %-12s AT SIXTY THOUSAND LINES THE ROOT REALLY SPLITS, and the one line the '
      'corpus is blind to becomes visible: the OUTPUT preserves the root %d time(s) and '
      'never overflows, the control with ml_append_int()\'s test left at the OLD block '
      'number preserves it %d times and reaches e_updated_too_many_blocks %d time(s), and the '
      'two draw DIFFERENT screens (%s against %s).  That is the check that `!= 0` is '
      'right, said directly; 7b is the same fact said by the pipeline\'s own corpus'
      % (TAG, got['wkp'][0], got['rootp'][0], got['rootp'][1],
         got['wkp'][2], got['rootp'][2]))

# THEN: the input and the output agree at that size, in four ways.
CASES = {
    '60k + a jump to the middle': keys(60000),
    '60k with reads all over it': reads(60000),
    '60k deleted and undone': [b'i'] + [b'y' * 19 + b'\n'] * 60000
                              + [E, b'ggdG', b'u', b'G', b':q!\r'],
    '100k with five hundred deletions': [b'i'] + [b'z%07d\n' % i for i in range(100000)]
                                        + [E, b'50000G'] + [b'dd'] * 500
                                        + [b'G', b'25000G', b':q!\r'],
}
bad = []
clocks = 0
for name, k in CASES.items():
    a, b = run(old, k), run(new, k)
    clocks += bool(CLOCK.search(a[3])) + bool(CLOCK.search(b[3]))
    if a[:3] != b[:3]:
        bad.append('%s: %s against %s' % (name, a[:2], b[:2]))
if bad:
    die('the input and the output differ on %s' % '; '.join(bad))
if not clocks:
    die('none of the %d sessions drew undo\'s `N seconds ago`, so the clock this '
        'comparison folds out is not in them and the folding is hiding something else'
        % len(CASES))
print('  %-12s and the two binaries AGREE at that size: %d sessions of sixty thousand '
      'lines and more -- built, jumped about in, read all over, deleted and undone, and '
      'churned -- each drawing the same stream and exiting the same way, with undo\'s '
      'wall clock folded out of %d of the %d streams.  The pointer '
      'block holds MORE entries after this phase, because pe_old_lnum left PTR_EN, so '
      'the tree is a different shape and the screen is the same'
      % (TAG, len(CASES), clocks, 2 * len(CASES)))
PY

# --- 9. what this phase declares -----------------------------------------------------------
# tools/phaserun.sh runs tools/zerodelta.sh --phase 42 after this check, and this phase
# declares nothing, so what it requires is the recording of the phase before it.
[ "$(tools/zerodelta.sh --declared 42 | tr -d '[:space:]')" = "" ] ||
    die "pipes/zero.delta declares something for phase 42, and this phase declares nothing at all"
say "pipes/zero.delta declares NOTHING for this phase, and that is two statements and not one: the negative-block island could not run, and block zero ran everywhere and was never read"
