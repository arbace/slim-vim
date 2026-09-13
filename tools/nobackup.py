r"""A write is a write.

Usage:
    python3 tools/nobackup.py <file>

Writing a file in vim is not one operation.  Before the new contents go
anywhere, the old file may be renamed or copied aside, its permissions, owner,
group, ACL and timestamps carried over, the write attempted, and the whole thing
rolled back if it fails -- and afterwards the copy is kept, or deleted, or
renamed again for `'patchmode'`.  That is what `'backup'`, `'writebackup'`,
`'backupcopy'`, `'backupdir'`, `'backupext'`, `'backupskip'` and `'patchmode'`
are between them, and it is 370 lines of `buf_write()`.

An embedded editor writes the file it was asked to write.

**`dobackup` is the hinge.**  It is `(p_wb || p_bk || *p_pm != NUL)`, so with the
options gone it is FALSE, `backup` stays NULL and `backup_copy` stays FALSE --
and thirteen tests spread through the rest of the function each collapse to the
branch they were already going to take when `:set nobackup nowritebackup` was
in force, which is a configuration vim has always supported.

Three things fall out that are worth naming separately:

  * `vim_rename()` has **five callers and all five are in here** -- make the
    backup, put it back when the write fails, put it back when the write is
    abandoned, and move it aside for `'patchmode'`.  So `vim_copyfile()` goes
    with it, and that is `readlink`, `symlink` and `rename`.
  * `set_file_time()` carried the old file's timestamps onto the backup.  That
    is `utime`, and it had exactly one caller.
  * `mch_get_acl()` and `mch_set_acl()` are already stubs -- this build has no
    ACL support, so one returns NULL and the other does nothing with it.  They
    went unnoticed because a stub compiles.  The `vim_acl_T` that threaded
    through `buf_write` to reach them goes too.

WHAT STAYS: the write itself, `'fsync'`, the check that the file did not change
underneath you, and the restore-on-failure path for the file being written --
none of which needs a copy.  `'backupcopy'` is `PV_BOTH` and buffer-local, so it
needs `droplocal.py` and `dropoptions.py --local`, which is the pairing Phase 14
records.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cutil


def cut(text, pattern, what, count=1, flags=re.M):
    text, n = re.subn(pattern, '', text, count=count, flags=flags)
    if n != count:
        sys.exit('nobackup: %s -- expected %d, matched %d' % (what, count, n))
    return text


def sub(text, old, new, what, count=1):
    text, n = re.subn(re.escape(old), new.replace('\\', '\\\\'), text, count=count)
    if n != count:
        sys.exit('nobackup: %s -- expected %d, matched %d' % (what, count, n))
    return text


def block(text, anchor, what, keep_body=False):
    """Delete the `if` block whose line is `anchor` (a literal)."""
    blanked = cutil.blank(text)
    k = text.index(anchor)
    o = blanked.index('{', k + len(anchor) - 2)
    c = cutil.match(text, o, blanked)
    if c < 0:
        sys.exit('nobackup: %s -- unbalanced' % what)
    end = text.index('\n', c) + 1
    if re.match(r'[ \t]*\n[ \t]*else\b', text[c + 1:c + 40]):
        sys.exit('nobackup: %s -- has an else' % what)
    if text[end:end + 1] == '\n':
        end += 1
    n = text.count('\n', k, end)
    k = text.rfind('\n', 0, k) + 1
    if keep_body:
        body = text[text.index('\n', o) + 1:text.rfind('\n', 0, c) + 1]
        body = ''.join(l[4:] if l.startswith('    ') else l
                       for l in body.splitlines(keepends=True))
        return text[:k] + body + text[end:], n
    return text[:k] + text[end:], n


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    text = path.read_text(errors='surrogateescape')

    total = 0
    for anchor, what in (
            ('    if (!(append && *p_pm == NUL) && !filtering && perm >= 0 && dobackup)',
             'the backup itself'),
            ('    if (*p_pm && dobackup)', "'patchmode'"),
            ('        if (backup != NULL)', 'the backup kept or removed after the write'),
            ('    if (!p_bk && backup != NULL && !write_info.bw_conv_error && ',
             'the backup deleted when \'backup\' is off')):
        text, n = block(text, anchor, what)
        total += n
        print('  nobackup     %-46s %4d lines' % (what, n))

    # The owner carried onto the written file when the backup was a rename.
    # Its `else if` is the branch that now always runs, so the pair collapses
    # to that rather than going -- buf_setino() still has to happen.
    text = cut(text,
               r'^[ \t]*if \(backup != NULL && !backup_copy\)\n[ \t]*\{\n'
               r'(?:[^\n]*\n)*?[ \t]*buf_setino\(buf\);\n[ \t]*\}\n'
               r'[ \t]*else (if \(!buf->b_dev_valid\))',
               'the owner carried to the backup')
    text = sub(text, 'if (!buf->b_dev_valid)\n', 'if (!buf->b_dev_valid)\n',
               'the surviving arm', count=0) if False else text
    print('  nobackup     %-46s %4d lines' % ('the owner carried to the backup', 13))

    # The restore-on-failure arm for a backup that was never made.
    text, n = block(text, '                    if (backup != NULL && wfname == fname)',
                    'the roll-back to a backup')
    total += n
    print('  nobackup     %-46s %4d lines' % ('the roll-back to a backup', n))

    # And the tests that were only ever asking whether a backup happened.
    text = sub(text, 'if (reset_changed && !newfile && overwriting && !(exiting && backup != NULL))',
               'if (reset_changed && !newfile && overwriting)',
               "the `written a backup while exiting` test")
    text = sub(text, 'if (!converted || dobackup)', 'if (!converted)',
               'the conversion test')
    text = sub(text,
               'if (overwriting && (!dobackup || backup_copy) && fname == wfname && perm >= 0 && ',
               'if (overwriting && fname == wfname && perm >= 0 && ',
               'the permissions test')
    text, n = block(text, '        if (!backup_copy)', 'the ACL put back', keep_body=True)
    print('  nobackup     thirteen tests that asked whether a backup happened')

    # --- the helpers, each with no caller left ------------------------------
    for name in ('vim_rename', 'vim_copyfile', 'set_file_time', 'get_bkc_flags'):
        text, ok = cutil.delete_definition(text, name)
        if not ok:
            sys.exit('nobackup: %s is not defined at file scope' % name)
    print('  nobackup     vim_rename and vim_copyfile: readlink, symlink, rename')
    print('  nobackup     set_file_time: utime')

    # --- the ACL that this build never had ----------------------------------
    for name in ('mch_get_acl', 'mch_set_acl'):
        text, ok = cutil.delete_definition(text, name)
        if not ok:
            sys.exit('nobackup: %s is not defined at file scope' % name)
    text = cut(text, r'^[ \t]*vim_acl_T[ \t]+acl = NULL;\n', "buf_write's acl")
    text = cut(text, r'^[ \t]*\{\n[ \t]*acl = mch_get_acl\(fname\);\n[ \t]*\}\n',
               "buf_write's mch_get_acl")
    text = cut(text, r'^[ \t]*mch_set_acl\(wfname, acl\);\n', 'the ACL put back')
    text, ok = cutil.delete_definition(text, 'mch_free_acl')
    if not ok:
        sys.exit('nobackup: mch_free_acl is not defined at file scope')
    text = cut(text, r'^[ \t]*mch_free_acl\(acl\);\n', "buf_write's mch_free_acl")
    # Their forward declarations go here rather than in the sweep: the sweep
    # has to compile the file first, and a prototype that names a type this
    # removes is an error, not a warning.
    text = cut(text, r'^static vim_acl_T mch_get_acl\(char_u \*fname\);\n'
               r'static void mch_set_acl\(char_u \*fname, vim_acl_T aclent\);\n'
               r'static void mch_free_acl\(vim_acl_T aclent\);\n',
               'the three ACL declarations')
    text = cut(text, r'^typedef void        \*vim_acl_T;\n', 'the vim_acl_T type')
    print('  nobackup     the ACL calls, which were stubs in this build')

    # set_init_default_backupskip() builds 'backupskip' from /tmp at startup and
    # looks the row up BY NAME -- the lookup that returns -1 for a row that is
    # not there, is not checked, and indexes options[-1].  Phase 22 had already
    # reduced it to one pass over one directory.
    text, ok = cutil.delete_definition(text, 'set_init_default_backupskip')
    if not ok:
        sys.exit('nobackup: set_init_default_backupskip is not defined')
    text = cut(text, r'^[ \t]*set_init_default_backupskip\(\);\n', 'its call')
    print("  nobackup     the 'backupskip' default, built at startup by name")

    # --- the callback its own row keeps reachable ---------------------------
    # An option row is a ROOT for reachability, so did_set_backupcopy() survives
    # the sweep and reads p_bkc, and --strict then refuses to drop the row that
    # is the only thing keeping the reader alive.  Phase 26 met this circle
    # three times; the answer is the same, and it is to point the row at NULL
    # first.  The row goes a moment later.
    for handler, rows in (('did_set_backupcopy', 1),
                          ('expand_set_backupcopy', 1),
                          ('did_set_backupext_or_patchmode', 2)):
        text, n = re.subn(r'(?<=[ ,])%s(?=,)' % handler, 'NULL', text)
        # Only the table rows match: a forward declaration has `(` after the
        # name, not `,`, so it is left alone for deadprotos to take.
        if n != rows:
            sys.exit('nobackup: %s is named in %d rows, expected %d'
                     % (handler, n, rows))
        text, ok = cutil.delete_definition(text, handler)
        if not ok:
            sys.exit('nobackup: %s is not defined at file scope' % handler)
    print('  nobackup     the three handlers the rows kept reachable')

    # didset_string_options() dereferences every string option's global once at
    # startup -- the trap Phase 20 records, and the one Phase 26 met again.  A
    # row can be inert to every other reader and still be read there.
    text = cut(text,
               r'^[ \t]*\(void\)opt_strings_flags\(p_bkc, p_bkc_values, '
               r'&bkc_flags, TRUE\);\n',
               "didset_string_options' p_bkc line")
    print("  nobackup     didset_string_options stops reading 'backupcopy'")

    # And the two places that compare an option's ADDRESS against p_bdir, which
    # is how Phase 23 left `:set dir>`: neither reads the value, so neither was
    # a crash, but with the row gone `varp` can never equal &p_bdir and both
    # say something that is no longer true.
    text = cutil.drop_if(
        text, r"^[ \t]*else if \(\*arg == '>' && varp == \(char_u \*\)&p_bdir\)$",
        flags=re.M)
    text = sub(text, 'if (p == (char_u *)&p_bdir || p == (char_u *)&p_pp',
               'if (p == (char_u *)&p_pp', 'the directory-list test')
    print("  nobackup     the two `is this option a directory?` tests")

    # --- the locals nothing sets any more -----------------------------------
    for pat, what in (
            (r'^[ \t]*char_u          \*backup = NULL;\n', 'backup'),
            (r'^[ \t]*int             backup_copy = FALSE;\n', 'backup_copy'),
            (r'^[ \t]*int             dobackup;\n', 'dobackup'),
            (r'^[ \t]*char_u          \*backup_ext;\n', 'backup_ext'),
            (r'^[ \t]*unsigned int    bkc = get_bkc_flags\(buf\);\n', 'bkc'),
            (r'^[ \t]*dobackup = \(p_wb \|\| p_bk \|\| \*p_pm != NUL\);\n', 'its one assignment'),
            (r'^[ \t]*vim_free\(backup\);\n', 'the free of backup')):
        text = cut(text, pat, what)
    text = cutil.drop_if(
        text, r'^[ \t]*if \(dobackup && \*p_bsk != NUL && match_file_list\(p_bsk, sfname, ffname\)\)$',
        flags=re.M)
    print('  nobackup     six locals and the assignment that drove them')

    path.write_text(text, errors='surrogateescape')
    print('  nobackup     %d lines of backup machinery; %d mentions left for '
          'the sweep' % (total, len(re.findall(r'\bbackup\b', text))))


if __name__ == '__main__':
    main()
