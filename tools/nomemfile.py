r"""The memfile is memory, and only memory.

Usage:
    python3 tools/nomemfile.py <file>

Phase 13 stopped the editor creating a swap file and Phase 25 stopped it reading
one back.  What is left is a **file back-end with no file**: `memfile_T` still
carries a descriptor, still knows how to page a block out and read it in, and
still sizes an LRU cache against how much memory the machine has -- all of it
behind `if (mfp->mf_fd >= 0)`, and `mf_fd` can no longer be anything but -1.

The proof is short.  `mf_open()` has exactly two callers: `ml_open()` passes
`(NULL, 0)`, and `ml_recover()` passed a name -- and Phase 25 deleted
`ml_recover()`.  Phase 13 stubbed `ml_open_file()` to `b_may_swap = FALSE`.  So
nothing can hand the memfile a name, `mf_do_open()` is unreachable, `mf_write()`
returns FAIL on its first line, and `mf_read()` on its first line too.

Which makes **`'maxmem'` and `'maxmemtot'` options that decide nothing**:

    need_release = (mfp->mf_used_count >= mfp->mf_used_count_max
                    || (total_mem_used >> 10) >= (long_u)p_mmt);
    ...
    if (mfp->mf_fd < 0 || !need_release) { return NULL; }

`need_release` is where both are read, and the test in front of it is always
true, so the answer is computed and thrown away.  They go, and with them
`set_init_default_maxmemtot()` and `mch_total_mem()` -- **`sysinfo` and
`getrlimit`**, whose only purpose was to size a cache that never evicts.

Three more things fall out:

  * `mch_get_host_name()`, which wrote the machine's name into block zero so a
    recovering vim could say the swap file came from elsewhere.  **`uname`.**
  * `check_overwrite()`'s "swap file exists" warning, which asks whether ANOTHER
    vim is editing the file you are about to overwrite.  It is the last reader
    of `p_dir`, so **`'directory'` can finally go** -- Phase 13 dropped its row
    while this still read it, and `:w!` over an existing other file segfaulted
    for twelve phases as a result.  See tools/orphanopts.py.
  * `lalloc()`'s retry loop, whose whole point was that `mf_release_all()` might
    have paged blocks out to disk and freed some memory.  It cannot.

WHAT DOES NOT CHANGE: the block structure.  Lines still live in blocks, blocks
still have numbers, `mf_trans` still maps them.  This removes the ability to
*evict* a block, which was already impossible, not the ability to have one.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cutil

MF_OPEN = '''    memfile_T           *mfp;

    // No caller can name a file: ml_open() passes nothing and ml_recover(),
    // which passed a name, went in Phase 25.  So there is no descriptor, no
    // block is ever in a file, and the page size is ours to choose.
    if ((mfp =  (memfile_T *)alloc(sizeof(memfile_T)) ) == NULL)
    {
        return NULL;
    }

    mfp->mf_free_first = NULL;
    mfp->mf_used_first = NULL;
    mfp->mf_used_last = NULL;
    mfp->mf_dirty = MF_DIRTY_NO;
    mf_hash_init(&mfp->mf_hash);
    mf_hash_init(&mfp->mf_trans);
    mfp->mf_page_size = MEMFILE_PAGE_SIZE;
    mfp->mf_blocknr_max = 0;
    mfp->mf_blocknr_min = -1;
    mfp->mf_neg_count = 0;

    return mfp;'''

MF_SYNC = '''    // Nothing to sync to.  Reporting the buffer clean is what the fd-less arm
    // of this always did; it is now the whole function.
    mfp->mf_dirty = MF_DIRTY_NO;
    return FAIL;'''

MF_GET_MISS = '''            // A block that is not in the hash is not anywhere: it could only
            // ever have come back from the file, and there is no file.
            return NULL;'''

LALLOC = '''    p = malloc(size);
    if (p == NULL && !releasing)
    {
        // The scrollback is the only memory left to reclaim.  This used to be
        // a retry loop, because mf_release_all() could page buffer blocks out
        // to the swap file and free them; it cannot, so there is nothing to
        // retry with.  `releasing` stays, because clear_sb_text() allocates.
        releasing = TRUE;
        clear_sb_text(TRUE);
        releasing = FALSE;
    }'''


def body(text, name, replacement, tag):
    blanked = cutil.blank(text)
    m = re.search(r'^%s\([^\n]*\n' % re.escape(name), text, re.M)
    if not m:
        sys.exit('nomemfile: %s is not defined at file scope' % name)
    o = blanked.index('{', m.end())
    c = cutil.match(text, o, blanked)
    was = text.count('\n', o, c)
    print('  nomemfile    %-16s was %3d lines -- %s' % (name, was, tag))
    return text[:o] + '{\n' + (replacement + '\n' if replacement else '') + '}' + text[c + 1:]


def cut(text, pattern, what, count=1, flags=re.M):
    text, n = re.subn(pattern, '', text, count=count, flags=flags)
    if n != count:
        sys.exit('nomemfile: %s -- expected %d, matched %d' % (what, count, n))
    return text


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    text = path.read_text(errors='surrogateescape')

    # --- the descriptor, and everything that only existed to use it ---------
    text = text.replace('static memfile_T *mf_open(char_u *fname, int flags);',
                        'static memfile_T *mf_open(void);', 1)
    text = text.replace('mf_open(char_u *fname, int flags)', 'mf_open(void)', 1)
    text = text.replace('mfp = mf_open(NULL, 0);', 'mfp = mf_open();', 1)
    text = body(text, 'mf_open', MF_OPEN, 'no caller can name a file')
    text = body(text, 'mf_sync', MF_SYNC, 'nothing to sync to')

    for name in ('mf_do_open', 'mf_set_ffname', 'mf_fullname', 'mf_read',
                 'mf_write_block', 'mf_write', 'mf_release_all', 'mf_release'):
        text, ok = cutil.delete_definition(text, name)
        if not ok:
            sys.exit('nomemfile: %s is not defined at file scope' % name)
    print('  nomemfile    the file back-end: open, read, write, release')

    text = cut(text, r'^[ \t]*mf_fullname\(buf->b_ml\.ml_mfp\);\n', "mf_fullname's caller")

    # mf_close's descriptor, the unlink of a file that was never created, and
    # the two names it freed.
    text = cut(text,
               r'^[ \t]*if \(mfp->mf_fd >= 0\)\n[ \t]*\{\n'
               r'[ \t]*if \(close\(mfp->mf_fd\) < 0\)\n[ \t]*\{\n'
               r'[ \t]*emsg\(_\(e_close_error_on_swap_file\)\);\n'
               r'[ \t]*\}\n[ \t]*\}\n'
               r'[ \t]*if \(del_file && mfp->mf_fname != NULL\)\n[ \t]*\{\n'
               r'[ \t]* unlink\(\(char \*\)\(mfp->mf_fname\)\) ;\n[ \t]*\}\n',
               "mf_close's descriptor and unlink")
    text = cut(text,
               r'^[ \t]*vim_free\(mfp->mf_fname\);\n[ \t]*vim_free\(mfp->mf_ffname\);\n',
               "mf_close's two names")

    # buf_write matched the swap file's permissions and group to the file's.
    # `mf_fname` is NULL for ever, so the block never ran; it is the last
    # mention of mf_fd, and swap_mode exists only for it.
    text = cutil.drop_if(
        text,
        r'^[ \t]*if \(swap_mode > 0 && curbuf->b_ml\.ml_mfp != NULL '
        r'&& curbuf->b_ml\.ml_mfp->mf_fname != NULL\)$', flags=re.M)
    text = cut(text, r'^[ \t]*int[ \t]+swap_mode = -1;\n', "swap_mode's declaration")
    text = cut(text, r'^[ \t]*swap_mode = \(st\.st_mode & 0644\) \| 0600;\n',
               "swap_mode's one assignment")
    print("  nomemfile    buf_write stops matching a swap file's permissions")
    text = text.replace('    hp = mf_release(mfp, page_count);\n',
                        '    hp = NULL;\n', 1)

    # mf_get's cache miss: the block could only have come back from the file.
    blanked = cutil.blank(text)
    k = text.index('        if (nr < 0 || nr >= mfp->mf_infile_count)')
    o = blanked.index('{', text.index('if (hp == NULL)', k - 400))
    c = cutil.match(text, o, blanked)
    text = text[:o] + '{\n' + MF_GET_MISS + '\n        }' + text[c + 1:]
    print('  nomemfile    mf_get stops trying to read a block back')

    # --- lalloc's retry loop ------------------------------------------------
    blanked = cutil.blank(text)
    k = text.index('    for (;;)\n    {\n        if ((p = malloc(size)) != NULL)')
    o = blanked.index('{', k + 12)
    c = cutil.match(text, o, blanked)
    end = text.index('\n', c) + 1
    text = text[:k] + LALLOC + '\n' + text[end:]
    text = cut(text, r'^[ \t]*int[ \t]+try_again;\n', "lalloc's try_again")
    # The label was the loop's only exit; -Wunused-label is not a shape the
    # dead-code sweep deletes, so it is named here.
    text = cut(text, r'^theend:\n', "lalloc's theend label")
    print('  nomemfile    lalloc stops retrying: there is nothing to page out')

    # --- the two options that sized a cache that never evicts ---------------
    text = cut(text,
               r'^[ \t]*mfp->mf_used_count \+= hp->bh_page_count;\n'
               r'[ \t]*total_mem_used \+= \(long_u\)hp->bh_page_count \* mfp->mf_page_size;\n',
               "mf_ins_used's accounting")
    text = cut(text,
               r'^[ \t]*mfp->mf_used_count -= hp->bh_page_count;\n'
               r'[ \t]*total_mem_used -= \(long_u\)hp->bh_page_count \* mfp->mf_page_size;\n',
               "mf_rem_used's accounting")
    text = cut(text,
               r'^[ \t]*total_mem_used -= \(long_u\)hp->bh_page_count \* mfp->mf_page_size;\n',
               "mf_close's accounting")
    text = cut(text, r'^static long_u   total_mem_used = 0;\n', 'total_mem_used')

    text, ok = cutil.delete_definition(text, 'mch_total_mem')
    if not ok:
        sys.exit('nomemfile: mch_total_mem is not defined at file scope')
    text, ok = cutil.delete_definition(text, 'set_init_default_maxmemtot')
    if not ok:
        sys.exit('nomemfile: set_init_default_maxmemtot is not defined')
    text = cut(text, r'^[ \t]*set_init_default_maxmemtot\(\);\n', 'its call')
    print("  nomemfile    'maxmem' and 'maxmemtot' sized a cache that never "
          'evicts; sysinfo and getrlimit go with them')

    # --- what block zero said about the machine it was written on -----------
    text, ok = cutil.delete_definition(text, 'mch_get_host_name')
    if not ok:
        sys.exit('nomemfile: mch_get_host_name is not defined at file scope')
    text = cut(text,
               r'^[ \t]*mch_get_host_name\(b0p->b0_hname, B0_HNAME_SIZE\);\n'
               r'[ \t]*b0p->b0_hname\[B0_HNAME_SIZE - 1\] = NUL;\n',
               "block zero's host name")
    print('  nomemfile    the machine name in block zero; uname goes with it')

    # --- and the last reader of p_dir ---------------------------------------
    text = cutil.drop_if(text, r"^[ \t]*if \(other && !emsg_silent\)$", flags=re.M)
    print("  nomemfile    check_overwrite's `is another vim editing this` "
          "warning, the last reader of p_dir")

    # set_b0_dir_flag() records in block zero whether the swap file sits beside
    # the file it belongs to.  Neither exists.  Stubbed rather than deleted, so
    # ml_upd_block0()'s UB_SAME_DIR arm keeps its shape.
    text = body(text, 'set_b0_dir_flag', '',
                'the swap file is nowhere, let alone beside the file')

    # preserve_exit() announces "Vim: preserving files..." on a deathtrap and
    # flushes each buffer to its swap file.  The test is mf_fname != NULL.
    # SCOPED TO THE FUNCTION: `for ((buf) = firstbuf; ...)` is the expansion of
    # FOR_ALL_BUFFERS and appears dozens of times, so an unanchored cut takes
    # the first one in the file -- which is somebody else's loop entirely.
    import funcreach
    blanked = cutil.blank(text)
    a, c = funcreach.definitions(text, blanked)['preserve_exit']
    fn = text[a:c]
    k = fn.index(' for ((buf) = firstbuf;')
    k = fn.rfind('\n', 0, k) + 1
    o = cutil.blank(fn).index('{', k)
    close = cutil.match(fn, o, cutil.blank(fn))
    end = fn.index('\n', close) + 1
    if 'mf_fname' not in fn[k:end]:
        sys.exit('nomemfile: preserve_exit loop is not the mf_fname one')
    text = text[:a] + fn[:k] + fn[end:].lstrip('\n') + text[c:]
    print('  nomemfile    preserve_exit stops announcing what it cannot preserve')

    # And the two places that compare an option's ADDRESS against p_dir to ask
    # "is this option a list of directories?".  Neither reads the value, so
    # neither was a crash; but with the row gone `varp` can never equal &p_dir,
    # so both arms are unreachable and say something that is no longer true.
    text = text.replace(
        "else if (*arg == '>' && (varp == (char_u *)&p_dir || varp == (char_u *)&p_bdir))",
        "else if (*arg == '>' && varp == (char_u *)&p_bdir)", 1)
    text = text.replace(
        "if (p == (char_u *)&p_bdir || p == (char_u *)&p_dir || p == (char_u *)&p_pp",
        "if (p == (char_u *)&p_bdir || p == (char_u *)&p_pp", 1)
    print("  nomemfile    the two `is this option a directory list?` tests")

    # --- the fields nothing reads any more ----------------------------------
    # A STRUCT FIELD IS NOT A VARIABLE: no warning reports one that is never
    # read, and the dead-code sweep cannot see it.  So they are named here.
    for field in ('char_u      \\*mf_fname;', 'char_u      \\*mf_ffname;',
                  'int         mf_fd;', 'int         mf_flags;',
                  'int         mf_reopen;', 'unsigned    mf_used_count;',
                  'unsigned    mf_used_count_max;',
                  'blocknr_T   mf_infile_count;'):
        text = cut(text, r'^[ \t]*%s\n' % field, 'the %s field' % field.split()[-1])
    print('  nomemfile    eight fields of memfile_T that nothing reads')

    path.write_text(text, errors='surrogateescape')
    for g in ('mf_fd', 'total_mem_used', 'p_mmt'):
        print('  nomemfile    %-14s %d mentions left for the sweep'
              % (g, len(re.findall(r'\b%s\b' % g, text))))


if __name__ == '__main__':
    main()
