r"""There is no home directory, and `~` is an ordinary character.

Usage:
    python3 tools/nohome.py <file>

`$HOME` is where an editor keeps the things it was told not to keep: this fork
stopped writing them in Phase 13 and stopped looking for them in Phase 20, and
what is left is the *notion* of a home directory -- `~/x` meaning a path, `~bob`
meaning someone else's, and `/home/you/x` displayed back as `~/x`.

All three go, and the last one is the reason this is not only a `getenv`
removal: `home_replace()` has thirteen callers, every one of them a place that
shows the user a file name.  It becomes a bounded copy, so the thirteen keep
working and a name is displayed as what it is.

  * `init_homedir()` -- read `$HOME`, and chdir into it and back to resolve
    symlinks -- loses its call in `common_init_2()`.
  * `expand_env_esc()` stops treating a leading `~`.  Its `$VAR` half stays;
    Phase 24 takes that.
  * the user database goes: `init_users()`, `add_user()`, `match_user()` and
    `get_users()` exist so that `~bob` can complete, and `mch_get_uname()` and
    `mch_get_user_name()` so that a swap file could say who wrote it.

**This is the phase where the symbol count finally moves.**  `getpwnam`,
`getpwuid`, `getpwent`, `setpwent`, `endpwent`, `getuid` and `getgid` are
reachable from nowhere else -- CLAUDE.md notes that `getpwnam()` working under
static musl is one of the two things that make this binary honestly standalone,
and now it does not need it.

WHAT THIS COSTS, and it was agreed before it was written: `:e ~/notes` opens a
file called `~/notes` in the current directory.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cutil

COPY = '''    size_t len;

    // A name is shown as what it is.  This was the shortening of a path under
    // $HOME to ~/..., and its thirteen callers are every place that displays a
    // file name to the user; they keep working, and see the name unchanged.
    if (src == NULL)
    {
        *dst = NUL;
        return 0;
    }
    len =  strlen((char *)(src)) ;
    if (len >= (size_t)dstlen)
    {
        len = (size_t)dstlen - 1;
    }
     memmove((char *)(dst), (char *)(src), len) ;
    dst[len] = NUL;
    return len;'''


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    text = path.read_text(errors='surrogateescape')

    # --- $HOME, read once at startup --------------------------------------
    text, n = re.subn(r'^[ \t]*init_homedir\(\);\n', '', text, count=1, flags=re.M)
    if n != 1:
        sys.exit('nohome: common_init_2 no longer calls init_homedir')
    print('  nohome       $HOME, read once at startup')

    # --- home_replace becomes a bounded copy ------------------------------
    blanked = cutil.blank(text)
    m = re.search(r'^home_replace\([^\n]*\n', text, re.M)
    if not m:
        sys.exit('nohome: home_replace is not defined at file scope')
    o = blanked.index('{', m.end())
    c = cutil.match(text, o, blanked)
    was = text.count('\n', o, c)
    text = text[:o] + '{\n' + COPY + '\n}' + text[c + 1:]
    print('  nohome       home_replace was %d lines, and now shows a name as it '
          'is' % was)

    # --- the two tilde arms of expand_env_esc -----------------------------
    # Brace-matched: the `$VAR` arm is kept and the two `~` arms go, so the
    # chain `if (*src != '~') A else if (...) B else C` becomes just A.
    blanked = cutil.blank(text)
    k = text.index("            if (*src != '~')")
    o1 = blanked.index('{', k)
    c1 = cutil.match(text, o1, blanked)
    rest = text[c1 + 1:]
    m2 = re.match(r'\n[ \t]*else if \(  src\[1\] == NUL', rest)
    if not m2:
        sys.exit("nohome: expand_env_esc's ~ arm is not where this expects")
    o2 = blanked.index('{', c1 + 1 + m2.end())
    c2 = cutil.match(text, o2, blanked)
    m3 = re.match(r'\n[ \t]*else\n', text[c2 + 1:])
    if not m3:
        sys.exit("nohome: expand_env_esc's ~user arm is not where this expects")
    o3 = blanked.index('{', c2 + 1 + m3.end())
    c3 = cutil.match(text, o3, blanked)
    body = text[text.index('\n', o1) + 1:text.rfind('\n', 0, c1) + 1]
    body = ''.join(l[4:] if l.startswith('    ') else l
                   for l in body.splitlines(keepends=True))
    text = text[:k] + body + text[c3 + 1:].lstrip('\n')
    print('  nohome       ~/ and ~user in expand_env_esc; its $VAR half stays')

    text, n = re.subn(r"\(\*src == '\$'\) \|\| \(\*src == '~' && at_start\)",
                      "*src == '$'", text, count=1)
    if n != 1:
        sys.exit('nohome: the $ / ~ trigger is not where this expects')
    print('  nohome       ~ stops starting an expansion at all')

    # --- at_start, which existed only to know whether ~ began a path ------
    # Scoped to expand_env_esc: `at_start` is also a static in the regexp
    # engine and a local in two other functions.  -Wunused-but-set-variable is
    # not a shape deadsweep.py deletes, so this is done here.
    import funcreach
    blanked = cutil.blank(text)
    defs = funcreach.definitions(text, blanked)
    a, c = defs['expand_env_esc']
    body = text[a:c]
    for pat, what in (
            (r'^[ \t]*int[ \t]*at_start = TRUE;\n', 'its declaration'),
            (r'^[ \t]*at_start = FALSE;\n', 'the reset'),
            (r'[ \t]*else if \(\(src\[0\] == \' \' \|\| src\[0\] == \',\'\) && !one\)\n'
             r'[ \t]*\{\n[ \t]*at_start = TRUE;\n[ \t]*\}\n', 'the separator arm'),
            (r'[ \t]*if \(startstr != NULL[^\n]*\n[ \t]*\{\n'
             r'[ \t]*at_start = TRUE;\n[ \t]*\}\n', 'the startstr arm'),
            # startstr_len was computed for that arm alone.  The `startstr`
            # PARAMETER stays -- callers pass it and -Wno-unused-parameter
            # means gcc will not say so -- but the length it was measured for
            # is gone.
            (r'^[ \t]*int[ \t]*startstr_len = 0;\n', "startstr_len's declaration"),
            (r'^[ \t]*if \(startstr != NULL\)\n[ \t]*\{\n'
             r'[ \t]*startstr_len = \(int\) strlen\(\(char \*\)\(startstr\)\) ;\n'
             r'[ \t]*\}\n\n?', "startstr_len's one assignment")):
        body, n = re.subn(pat, '', body, count=1, flags=re.M)
        if n != 1:
            sys.exit('nohome: at_start -- %s is not where this expects' % what)
    text = text[:a] + body + text[c:]
    print('  nohome       at_start, which existed only to know whether ~ began '
          'a path')

    # --- the user database -------------------------------------------------
    text, n = re.subn(r'[ \t]*\{EXPAND_USER, get_users, TRUE, FALSE\},\n', '', text)
    if n != 1:
        sys.exit('nohome: expected one EXPAND_USER completion row, got %d' % n)

    # And the context that reaches it.  Removing the completion row alone
    # leaves match_user() called from set_context_for_wildcard_arg(), and
    # match_user() is what walks the password database -- so the five pw
    # symbols stayed until this went too.
    text = cutil.drop_if(text, r"^[ \t]*if \(\*xp->xp_pattern == '~'\)$", flags=re.M)
    print('  nohome       ~user completion, and the context that reaches it')

    # get_user_name() answers who this is, for a swap file's block zero.  There
    # are no swap files; the block is still built in memory, and it can be
    # built without a name.  This is the last reader of getpwuid.
    blanked = cutil.blank(text)
    m = re.search(r'^get_user_name\([^\n]*\n', text, re.M)
    if not m:
        sys.exit('nohome: get_user_name is not defined at file scope')
    o = blanked.index('{', m.end())
    c = cutil.match(text, o, blanked)
    text = text[:o] + '{\n    return FAIL;\n}' + text[c + 1:]
    print('  nohome       who this is, which only a swap file wanted to know')

    path.write_text(text, errors='surrogateescape')
    print('  nohome       %d homedir mentions left for the sweep'
          % text.count('homedir'))


if __name__ == '__main__':
    main()
