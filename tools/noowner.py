r"""Nobody owns a file.

Usage:
    python3 tools/noowner.py <file>

An embedded editor runs where there are no users to tell apart, so asking who
you are is asking a question with no answer -- and three places in `buf_write()`
and one in the option table were still asking it.

  * `:w!` on a read-only file makes it writable first, but only **if you own
    it**: `st_old.st_uid == getuid()`.  The ownership test goes and the `chmod`
    stays.  Nothing widens in practice -- where the test used to say no, the
    `chmod` now says no instead, and the same error comes back by a different
    route.
  * When a write fails and `!` makes it retry, the mode carried onto the new
    file is masked to `0777` -- dropping setuid, setgid and sticky -- but again
    only if `st_old.st_uid != getuid() || st_old.st_gid != getgid()`.  The test
    goes and **the masking stays**, which is the safe direction: a file this
    editor writes never carries a setuid bit.
  * `'modeline'` is forced off when `getuid() == ROOT_UID`, a protection against
    a modeline running as root.  There is no root here and no `+eval` for a
    modeline to reach; the option keeps its compiled default.
  * `get_user_name()` was stubbed to `return FAIL;` in Phase 22, when the
    password database went, and its two callers were left writing the answer
    into the swap file's block zero.  There are no swap files and no users, so
    the callers go and the stub with them.  The second is an `if (…FAIL || …)`
    whose condition was already always true, so its `else` -- the arm that
    spliced a user name into the recorded file name -- has been dead since
    Phase 22 and goes now.

WHAT STAYS: `chmod` and `fchmod`, through `mch_setperm()` and `mch_fsetperm()`.
**Permissions are not ownership.**  A file still has a mode, `:w!` still has to
clear the read-only bit to write, and the mode of the file that was there is
still put back on the file that replaces it.  Removing those would take `:w!` on
a read-only file with it, which is a capability and not a concept.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cutil


def cut(text, pattern, what, count=1, flags=re.M):
    text, n = re.subn(pattern, '', text, count=count, flags=flags)
    if n != count:
        sys.exit('noowner: %s -- expected %d, matched %d' % (what, count, n))
    return text


def sub(text, old, new, what):
    if old not in text:
        sys.exit('noowner: %s is not where this expects' % what)
    return text.replace(old, new, 1)


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    text = path.read_text(errors='surrogateescape')

    text = sub(text,
               'if (forceit && perm >= 0 && !(perm & 0200) && st_old.st_uid == getuid() '
               '&& vim_strchr(p_cpo, CPO_FWRITE) == NULL)',
               'if (forceit && perm >= 0 && !(perm & 0200) '
               '&& vim_strchr(p_cpo, CPO_FWRITE) == NULL)',
               "the `do you own this read-only file` test")
    print('  noowner      :w! clears the read-only bit without asking whose it is')

    # The mode masking stays; only the test that guarded it goes.
    blanked = cutil.blank(text)
    k = text.index('                            if (st_old.st_uid != getuid() || st_old.st_gid != getgid())')
    o = blanked.index('{', k)
    c = cutil.match(text, o, blanked)
    body = text[text.index('\n', o) + 1:text.rfind('\n', 0, c) + 1]
    body = ''.join(l[4:] if l.startswith('    ') else l
                   for l in body.splitlines(keepends=True))
    end = text.index('\n', c) + 1
    if 'perm &= 0777;' not in body:
        sys.exit('noowner: the mode masking is not where this expects')
    text = text[:text.rfind('\n', 0, k) + 1] + body + text[end:]
    print('  noowner      a written file never carries a setuid bit, whoever '
          'wrote it')

    # 'modeline' off for root.
    text = cutil.drop_if(
        text,
        r'^[ \t]*if \(options\[opt_idx\]\.indir ==   \(idopt_T\)\(PV_BUF \+ \(int\)\(BV_ML\)\)   '
        r'&& getuid\(\) == ROOT_UID\)$', flags=re.M)
    text = cut(text, r'^enum \{ ROOT_UID = 0 \};\n', 'the ROOT_UID enumerator')
    print("  noowner      'modeline' stops asking whether this is root")

    # --- who wrote the swap file, which Phase 22 left behind ----------------
    text = cut(text,
               r'^[ \t]*\(void\)get_user_name\(b0p->b0_uname, B0_UNAME_SIZE\);\n'
               r'[ \t]*b0p->b0_uname\[B0_UNAME_SIZE - 1\] = NUL;\n',
               "block zero's user name")

    # The other caller's `if` was already always true -- get_user_name() has
    # returned FAIL since Phase 22 -- so its `else` has been dead that long.
    blanked = cutil.blank(text)
    k = text.index('            if (get_user_name(uname, B0_UNAME_SIZE) == FAIL')
    o = blanked.index('{', text.index('\n', k))
    c = cutil.match(text, o, blanked)
    m = re.match(r'\n[ \t]*else\n', text[c + 1:])
    if not m:
        sys.exit('noowner: the get_user_name arm has no else')
    o2 = blanked.index('{', c + 1 + m.end())
    c2 = cutil.match(text, o2, blanked)
    body = text[text.index('\n', o) + 1:text.rfind('\n', 0, c) + 1]
    body = ''.join(l[4:] if l.startswith('    ') else l
                   for l in body.splitlines(keepends=True))
    end = text.index('\n', c2) + 1
    text = text[:text.rfind('\n', 0, k) + 1] + body + text[end:]

    # `flen` was the length the user name would have been spliced in front of.
    # -Wunused-but-set-variable is not a shape deadsweep.py deletes, so the
    # assignment becomes a plain call and the declaration is named here.
    text = sub(text,
               'flen = home_replace(NULL, buf->b_ffname, b0p->b0_fname, B0_FNAME_SIZE_CRYPT, TRUE);',
               '(void)home_replace(NULL, buf->b_ffname, b0p->b0_fname, B0_FNAME_SIZE_CRYPT, TRUE);',
               "set_b0_fname's home_replace")
    text = cut(text, r'^[ \t]*size_t  flen;\n', "set_b0_fname's flen")

    # And the field it wrote into.  A STRUCT FIELD IS NOT A VARIABLE: no warning
    # names one that nothing reads, and the dead-code sweep cannot see it.  The
    # layout of block zero does not matter -- nothing writes it to a disk and
    # nothing reads one back -- and there is no assertion on its size.
    text = cut(text, r'^[ \t]*char_u      b0_uname\[B0_UNAME_SIZE\];\n',
               "block zero's b0_uname field")
    text = cut(text, r'^enum \{ B0_UNAME_SIZE = 40 \};\n', 'B0_UNAME_SIZE')

    text, ok = cutil.delete_definition(text, 'get_user_name')
    if not ok:
        sys.exit('noowner: get_user_name is not defined at file scope')
    print('  noowner      who wrote the swap file, a stub since Phase 22')

    path.write_text(text, errors='surrogateescape')
    print('  noowner      %d identity mentions left for the sweep'
          % len(re.findall(r'\bgetuid\b|\bgetgid\b|\bget_user_name\b', text)))


if __name__ == '__main__':
    main()
