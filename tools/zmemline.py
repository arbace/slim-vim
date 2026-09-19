"""Zero's memline corpus: buffers big enough that the text layer has a TREE.

Usage: python3 tools/zmemline.py <binary> <outdir>

`tools/zcases.py` is the model and this is its second half rather than its
replacement: the same keystrokes-in/screens-out session (`tools/zstream.py`), the
same sectioned record (`tools/zrec.py`), one file per case.  What differs is the
SIZE of the buffer, and that is the whole point.

WHY IT EXISTS.  Measured with an instrumented build on the boundary zero phase 40
was handed: every one of `tools/zcases.py`'s 102 cases allocates **exactly one
data block**, so the root pointer block holds exactly one entry for the whole
session.  `ml_find_line()` then never chooses AMONG entries -- `idx` is 0 every
time, and a pointer entry's `pe_line_count` is never the number that decides
which child block a line is in.  So a `zero-vim` with
`pp->pb_pointer[idx].pe_line_count--` deleted from `ml_find_line()`'s ML_DELETE
arm records all 102 cases BYTE-IDENTICALLY, and forty phases had been verified by
an instrument that could not see a corrupted text layer at all.

WHAT A CASE HAS TO DO to be able to see it, all three:

  * **build a buffer of more than one data block.**  A page is 4,096 bytes and a
    line costs `sizeof(unsigned)` for its index entry plus its text and a NUL, so
    a block holds `(page - offsetof(DATA_BL, db_index)) / (len + 5)` lines -- 78
    of the 47-byte lines below -- and a pointer block holds
    `(page - offsetof(PTR_BL, pb_pointer)) / sizeof(PTR_EN)` children, which is
    127.  `pipes/zero40.sh` derives all of that from the struct definitions in
    the source rather than trusting this paragraph, and then requires an
    instrumented build to show each path actually reached;
  * **be self-labelling.**  Every line begins with its own line number, so a
    screen drawn with `'number'` shows the tree's answer beside the question: a
    descent that lands in the wrong block puts a line's label against somebody
    else's number;
  * **read the whole buffer back.**  `observe()` ends a case with a
    substitute-count over every line -- which walks all of them through
    `ml_get()` and prints the total -- then jumps into the middle and to both
    ends.

HOW A BUFFER IS BUILT, given that zero-vim has no file argument (phase 5), no
`:edit` (phase 8) and no `:read` (phase 7).  `build()` types ONE line under
`'paste'` and replays a three-key macro -- yank the line, put it, CTRL-A the
number -- with a count.  25,000 lines cost five keystrokes and about two seconds,
and `'lazyredraw'` (a compiled-in default) keeps the whole replay off the stream.
`'nrformats='` is set first because this build's default includes `octal`, under
which line 000008 is followed by 000010.
"""
import concurrent.futures
import os
import shutil
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import zrec
import zstream

ESC = b'\x1b'
CR = b'\r'
CA = b'\x01'
CR_R = b'\x12'
CG = b'\x07'
QUIT = ESC + b':q!' + CR

# A case here drives one editor through a session of tens of thousands of lines;
# `zstream.session`'s default of 20 s is the 102 small cases'.  The longest build
# below takes about two seconds, so this is a stall detector and not a budget --
# and a session that reaches it is recorded as `blocked` AND makes the run exit
# non-zero, rather than returning a short capture silently.
TIMEOUT = 180

PAD = 40
# What a line of this corpus costs the text layer, so that a phase program can
# check the sizes below against the block arithmetic it reads out of the source
# instead of against a number written here: six digits, a space and PAD letters.
LINE_BYTES = len('%06d ' % 1) + PAD
# Every size build() was asked for, in the order the cases ask.  It is filled by
# building CASES below, so it is the corpus itself and not a second list.
SIZES = []


def build(n, pad=PAD):
    """Keys that leave the buffer holding exactly `n` self-labelled lines.

    Line k is `%06d ` % k followed by `pad` letters, so every line is the same
    length and its text names its own line number.  CTRL-A keeps the six-digit
    zero padding, which is what holds the length constant.
    """
    SIZES.append(n)
    seed = b'%06d ' % 1 + b'a' * pad
    keys = [b'i' + seed + ESC, b':set nopaste' + CR, b':set nrformats=' + CR]
    if n > 2:
        # RECORDING the macro runs it, so `qqyyp^Aq` has already made the second
        # line and the replay count is n - 2.  `n` is exact, not approximate.
        keys += [b'qqyyp' + CA + b'q', b'%d@q' % (n - 2)]
    return keys


def observe(*lnums):
    """Read the whole buffer back, then look at named lines and at both ends.

    `:%s/^/&/n` counts without changing anything: the empty match at the start of
    every line makes the reported total the buffer's line count, whatever the
    case did to the text, and getting it requires walking every line through
    `ml_get()`.  `:%s/\\d/&/n` is the same walk asked a question about CONTENT,
    and a case that has no digits left answers E486, which is a record too.  The
    jumps then draw screens whose `'number'` column sits beside each line's own
    label.
    """
    keys = [b':set number' + CR, br':%s/^/&/n' + CR, br':%s/\d/&/n' + CR]
    for l in lnums:
        keys += [b':%d' % l + CR, CG]
    return keys + [b'gg', CG, b'G', CG]


def case(name, opts, keys):
    return (name, ['+set ' + o for o in opts] + ['+set paste'], list(keys) + [QUIT])


# --- the cases -------------------------------------------------------------
# The sizes are chosen against the derived block arithmetic above and not against
# a wish: with 47-byte lines a data block holds 78 of them, so 200 lines is a
# handful of blocks, 4,000 is about 52, and 12,000 is past the 127 a pointer
# block can point at -- so the root splits and the tree gains a third level.
# pipes/zero40.sh recomputes that from the source and then MEASURES which case
# reaches which path with an instrumented build, because a corpus that intends to
# reach a split and does not is exactly the failure this phase exists to end.
CASES = [
    # --- more than one data block, which nothing in zcases.py has -------------
    case('mem_two_blocks', [], build(200) + [b':100' + CR, b'dd', b'Oinserted' + ESC] +
         observe(1, 100, 150)),
    case('mem_many_blocks', [], build(4000) + [b':2000' + CR, b'dd'] +
         observe(1, 1000, 2000, 3000)),

    # --- past pb_count_max: the ROOT pointer block splits ---------------------
    case('mem_root_split', [], build(12000) + observe(1, 6000, 11999)),
    case('mem_deep_jumps', [], build(25000) +
         [b':%d' % l + CR for l in (24000, 1, 12345, 300, 19999, 7, 22222)] +
         observe(1, 12500, 24999)),

    # --- churn in the MIDDLE of a large buffer, never at its ends -------------
    case('mem_mid_insert', [], build(4000) +
         [b':2000' + CR, b'400oinserted line here' + ESC] + observe(1900, 2100, 2500)),
    case('mem_mid_delete', [], build(4000) + [b':1500' + CR, b'1000dd'] +
         observe(1, 1400, 1600)),
    case('mem_mid_replace', [], build(4000) + [b':1000,2000s/a/B/g' + CR] +
         observe(999, 1500, 2001)),
    case('mem_split_root_mid', [], build(12000) +
         [b':6000' + CR, b'200oxxxx' + ESC, b'500dd'] + observe(5900, 6100, 11000)),

    # --- a line longer than a page, and a buffer of mixed lengths -------------
    case('mem_long_line', [], build(200) + [b':100' + CR, b'4200ix' + ESC] +
         observe(99, 100, 101)),
    case('mem_mixed_len', [], build(1000) +
         [b':200' + CR, b'2000iy' + ESC, b':400' + CR, b'6000iz' + ESC,
          b':600' + CR, b'80iw' + ESC] + observe(200, 400, 600)),

    # --- whole-buffer commands over a tree ------------------------------------
    case('mem_global_del', [], build(4000) + [b':g/3 a/d' + CR] + observe(1, 1000, 3000)),
    case('mem_global_sub', [], build(4000) + [b':g/7 a/s/a/Q/' + CR] +
         observe(1, 2000, 3500)),
    case('mem_sort', [], build(3000) + [b':sort!' + CR, b':sort' + CR] +
         observe(1, 1500, 2999)),
    case('mem_join_split', [], build(2000) + [b':1000,1400j' + CR, br':%s/ a/\r/' + CR] +
         observe(1, 990, 1100)),

    # --- undo and redo storms over a tree -------------------------------------
    case('mem_undo_storm', [], build(4000) +
         [b':2000' + CR] + [b'dd'] * 30 + [b'30u', b'30' + CR_R, b'30u'] +
         observe(1, 1990, 2010)),
    case('mem_undo_big', [], build(12000) +
         [b':6000' + CR, b'2000dd', b'u', CR_R, b'u'] + observe(1, 6000, 11999)),
]


def redraws(out):
    """How many times the editor finished a redraw -- and NOT the stream's digest.

    `tools/zcases.py` records `stream <bytes> sha=<digest>` as a tripwire under
    its screens (ZERO-PLAN.md 5.1).  That cannot be done here, and the reason is
    MEASURED rather than assumed: an undo in this corpus reports its age, and the
    editor writes the message and then positions the cursor to clear the rest of
    the line -- so `0 seconds ago` gives `\x1b[24;40H\x1b[K` and `1 second ago`
    gives `\x1b[24;39H\x1b[K`, a COLUMN NUMBER derived from the width of a
    timestamp.  `tools/zrec.py`'s scrub cannot reach it: it rewrites the text of
    the age, and this is arithmetic on its length.  Caught as a one-byte stream
    difference in `mem_undo_big`, once in 48 whole recordings of one binary, with
    every screen identical; and forced deliberately with a build whose `add_time`
    reports one second more than it should, which is exactly the variation the
    machine's load produces.

    The 102 screen cases keep their digest and are right to: their undos are
    sub-second, so the age is always `0 seconds ago`.  A corpus that undoes 2,000
    lines of a 12,000-line buffer straddles the second.

    What is kept instead is the count of `\x1b[?25h` -- show cursor, where a
    redraw ENDS and where tools/zscreen.py snapshots -- which is the same number
    as the snapshots below and is clock-free.  The screens are the record; the
    phase program asserts the whole thing by building a control whose clock
    advances by a second per call and requiring every record to be identical.
    """
    return out.count(b'\x1b[?25h')


def record(binary, name, args, keys):
    try:
        scr, out, err, rc = zstream.session(binary, keys, args=args, timeout=TIMEOUT)
    except zstream.Blocked:
        return zrec.section('blocked') + zrec.section(
            'why', 'the editor took the input over and did not return'), True
    text = zrec.section('exit %s' % rc)
    text += zrec.section('bells %d' % scr.bells)
    text += zrec.section('stream %d redraws' % redraws(out))
    text += zrec.section('stderr', err.decode('utf-8', 'replace').rstrip('\n'))
    for i, (dump, y, x, bells) in enumerate(scr.snaps):
        text += zrec.section('snap %d cursor=%d,%d bells=%d' % (i, y, x, bells), dump)
    return zrec.scrub(text), False


def main():
    binary, outdir = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])
    # Every artifact deleted before the run: a harness that diffs an output it
    # did not first delete keeps passing on the previous run's file.
    shutil.rmtree(outdir, ignore_errors=True)
    os.makedirs(outdir)
    t = time.time()
    blocked = []

    def one(c):
        name, args, keys = c
        text, stalled = record(binary, name, args, keys)
        open(os.path.join(outdir, name), 'w').write(text)
        if stalled:
            blocked.append(name)

    with concurrent.futures.ThreadPoolExecutor(
            max_workers=min(len(CASES), (os.cpu_count() or 4) * 2)) as ex:
        list(ex.map(one, CASES))
    print('%d memline cases -> %s in %.1fs' % (len(CASES), outdir, time.time() - t))
    if blocked:
        print('%d case(s) stalled and did not return: %s'
              % (len(blocked), ' '.join(sorted(blocked))), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
