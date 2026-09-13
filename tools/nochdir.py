r"""The working directory is where it started.

Usage:
    python3 tools/nochdir.py <file>

`:cd`, `:lcd` and `:tcd` are `ex_ni`, `:!` no longer forks, and nothing else in
this editor moves the process.  So **the directory it starts in is the one it
dies in** -- and three pieces of machinery that exist because that was not true
stop being needed.

  * `mch_FullName()` chdir'd into the leading directory of a relative name, asked
    `getcwd()` where that had landed, and chdir'd back -- via `fchdir()` on a
    descriptor it held open, falling back to `chdir()`.  That is what resolved
    `..` and a symlinked directory on the way to a full name.  **`fchdir`.**
  * `win_fix_current_dir()` restores a window's or tab's local directory, and
    runs only when `w_localdir`, `tp_localdir` or `globaldir` is set.  The first
    two come only from `:lcd` and `:tcd`; `globaldir` is assigned only inside
    this function.  Unreachable.
  * `edit_buffers()` takes a `cwd` to return to between `-o` windows.  It is
    passed `start_dir`, which is `static char_u *start_dir = NULL;` and which
    nothing assigns -- the `-o` local-directory handling that set it is already
    gone.  So the call never ran.  **`chdir`**, once `mch_chdir()` has no
    callers left.

WHAT IT COSTS, and it is the reason to say it rather than to call this a
cleanup: a full name is now the working directory with the name appended, so
`../x/y` becomes `/cwd/../x/y` instead of `/real/x/y`.  It opens the same file;
what it loses is that two spellings of one path no longer compare equal, so
`:e ../x/y` and `:e /real/x/y` are two buffers rather than one.

`getcwd` STAYS, and is now asked once.  It has five callers through
`mch_dirname()` -- `shorten_fnames()` shortens every displayed name against it,
and `mch_FullName()` is how a relative name becomes absolute at all.  Dropping
it would mean `b_ffname` could not be a full path, which is a capability cut
rather than plumbing.  But since nothing can move the process any more, the
answer cannot change: it is read into a static on the first call, and every
later call is a copy.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cutil

FULLNAME = '''    int         buflen = 0;

    // The dance that used to be here chdir'd into the leading directory of a
    // relative name, asked getcwd() where that landed, and chdir'd back -- so
    // that `..` and a symlinked directory were resolved on the way.  Nothing
    // moves this process any more, so a full name is the working directory
    // with the name appended, and a `..` in it survives into the answer.
    //
    // `force` asked for that re-resolution even when the name was already
    // absolute.  There is nothing left to re-resolve, so an absolute name is
    // its own answer -- and prepending the cwd to one was the whole of the
    // first attempt at this, which moved :read, :write and :wq.
    if (!mch_isFullName(fname))
    {
        if (mch_dirname(buf, len) == FAIL)
        {
            *buf = NUL;
            return FAIL;
        }
        buflen = (int) strlen((char *)(buf)) ;
        if (buflen >= len - 1)
        {
            return FAIL;
        }
        if (buflen > 0 && buf[buflen - 1] !=  ((char_u)'/')  && *fname != NUL &&  strcmp((char *)(fname), (char *)("."))  != 0)
        {
             strcpy((char *)(buf + buflen), (char *)( "/" )) ;
            buflen += sizeof( ((char_u)'/') );
        }
    }
    else
    {
        *buf = NUL;
    }

    if ((int)(buflen +  strlen((char *)(fname)) ) >= len)
    {
        return FAIL;
    }

    if ( strcmp((char *)(fname), (char *)("."))  != 0)
    {
         strcpy((char *)(buf + buflen), (char *)(fname)) ;
    }

    return OK;'''

DIRNAME = '''    // Asked once.  Nothing can move this process -- :cd, :lcd and :tcd are
    // ex_ni, :! does not fork, and mch_FullName() no longer chdirs -- so every
    // later call is asking the kernel a question whose answer cannot have
    // changed since the first one.
    static char_u   cwd[ PATH_MAX ];
    static int      cwd_len = -1;

    if (cwd_len < 0)
    {
        if (getcwd((char *)cwd, sizeof(cwd)) == NULL)
        {
             strcpy((char *)(buf), (char *)(strerror(errno))) ;
            return FAIL;
        }
        cwd_len = (int) strlen((char *)(cwd)) ;
    }
    if (cwd_len >= len)
    {
        return FAIL;
    }
     strcpy((char *)(buf), (char *)(cwd)) ;
    return OK;'''


def body(text, name, replacement, tag):
    blanked = cutil.blank(text)
    m = re.search(r'^%s\([^\n]*\n' % re.escape(name), text, re.M)
    if not m:
        sys.exit('nochdir: %s is not defined at file scope' % name)
    o = blanked.index('{', m.end())
    c = cutil.match(text, o, blanked)
    print('  nochdir      %-14s was %3d lines -- %s' % (name, text.count('\n', o, c), tag))
    return text[:o] + '{\n' + replacement + '\n}' + text[c + 1:]


def cut(text, pattern, what, count=1, flags=re.M):
    text, n = re.subn(pattern, '', text, count=count, flags=flags)
    if n != count:
        sys.exit('nochdir: %s -- expected %d, matched %d' % (what, count, n))
    return text


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    text = path.read_text(errors='surrogateescape')

    text = body(text, 'mch_FullName', FULLNAME, 'nothing moves this process')
    text = body(text, 'mch_dirname', DIRNAME, 'the answer cannot change')

    # The window- and tab-local directory restore.  Its guard can never be
    # true: w_localdir and tp_localdir come only from :lcd and :tcd, and
    # globaldir is assigned only inside this function.
    text, ok = cutil.delete_definition(text, 'win_fix_current_dir')
    if not ok:
        sys.exit('nochdir: win_fix_current_dir is not defined at file scope')
    text = cutil.drop_if(text, r'^[ \t]*if \(awp->w_localdir != NULL\)$', flags=re.M)
    text = cut(text, r'^[ \t]*win_fix_current_dir\(\);\n\n?', 'its unconditional call')
    print('  nochdir      win_fix_current_dir, whose guard cannot be true')

    # `globaldir` remembers the directory to come back to when a window-local
    # one is in force.  win_fix_current_dir() was the only thing that ever set
    # it, so what is left is aucmd_prepbuf()/aucmd_restbuf() saving and
    # restoring a pointer that is always NULL.  A STRUCT FIELD IS NOT A
    # VARIABLE -- no warning would report this one -- so it is named here.
    for pattern, what in (
            (r'^[ \t]*aco->globaldir = globaldir;\n[ \t]*globaldir = NULL;\n', 'the save'),
            (r'^[ \t]*vim_free\(globaldir\);\n[ \t]*globaldir = aco->globaldir;\n', 'the restore'),
            (r'^[ \t]*char_u      \*globaldir;\n', 'the field'),
            (r'^static char_u   \*globaldir  = NULL ;\n', 'the global')):
        text = cut(text, pattern, 'globaldir -- %s' % what)
    print('  nochdir      globaldir, saved and restored and always NULL')

    # edit_buffers() returns to `cwd` between -o windows.  It is passed
    # start_dir, which nothing assigns.
    text = cutil.drop_if(text, r'^[ \t]*if \(cwd != NULL\)$', flags=re.M)
    for pattern, what in (
            (r'^static char_u \*start_dir = NULL;\n\n?', 'start_dir itself'),
            (r'^[ \t]*vim_free\(start_dir\);\n', 'the free of it')):
        text = cut(text, pattern, 'start_dir -- %s' % what)
    text = text.replace('edit_buffers(&params, start_dir);',
                        'edit_buffers(&params);', 1)
    text = text.replace('static void edit_buffers(mparm_T *parmp, char_u *cwd);',
                        'static void edit_buffers(mparm_T *parmp);', 1)
    text = text.replace('edit_buffers(mparm_T     *parmp, char_u      *cwd)',
                        'edit_buffers(mparm_T     *parmp)', 1)
    print('  nochdir      the -o window walk stops returning to a directory it '
          'was never given')

    path.write_text(text, errors='surrogateescape')
    for g in ('mch_chdir', 'fchdir', 'getcwd'):
        print('  nochdir      %-10s %d mentions left for the sweep'
              % (g, len(re.findall(r'\b%s\b' % g, text))))


if __name__ == '__main__':
    main()
