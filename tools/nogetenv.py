r"""Nothing is read from the environment.

Usage:
    python3 tools/nogetenv.py <file>

Phase 20 stopped reading configuration files and Phase 22 stopped believing in a
home directory; this is the last of the three, and the one that makes the claim
checkable.  `getenv`, `setenv`, `unsetenv` and `environ` leave `nm -u`, and after
that no answer this editor gives can depend on how it was invoked.

`vim_getenv()` is where nearly all of it went through, and it is worth saying
what it already was: Phase 1 folded its `vimruntime` flag to FALSE, so
`vim_getenv("VIMRUNTIME")` had already been returning NULL unconditionally, and
"VIM" was the only name that could still reach the `$VIM`/`p_hf` fallback chain
-- which nothing asks for any more.  So **the function can only ever answer "not
set"**, and every caller collapses to the branch it already took:

  * `expand_env_esc()` -- `$VAR` in a file name never expanded, so the whole
    `if (*src == '$')` arm was dead weight.  What is left is `skipwhite`, the
    backslash escape and the bound on `dstlen`: the name arrives intact.  Its
    `~` half went in Phase 22 and this is the same shape of answer.
  * `expand_shellcmd()` -- `$PATH` was the list of directories to complete a
    command name from; without it the search is the pattern's own directory.
  * `fix_help_buffer()` -- `rt` was `vim_getenv("VIMRUNTIME")` and therefore
    NULL, so the `*local-additions*` scan of `'runtimepath'` could never add a
    line.  The block goes rather than being left to look like it does something.
  * `set_init_default_shell()` (`$SHELL`), `set_init_default_cdpath()`
    (`$CDPATH`) and the `$VIM_POSIX` arm of `set_init_1()` -- each existed to
    let the environment choose a default.  The compiled-in defaults stand.
  * `set_init_default_backupskip()` -- `$TMPDIR`, `$TEMP`, `$TMP` and, always,
    `/tmp`.  Only the last can contribute now, so the table of four names goes
    and the loop runs its one pass.
  * `vimrc_found()` -- already unreachable: every `do_source()` call in the file
    passes `DOSO_NONE`, so the two arms that called it were dead from Phase 20.
    Removing them takes `vim_setenv`, `export_myvimdir` and `$MYVIMDIR` with it.
  * `did_set_helpfile()` -- unset `$VIM` and `$VIMRUNTIME` so a later read would
    recompute them from the new `'helpfile'`.  There is no later read.
  * `get_env_name()` walks `environ` to complete `$VAR` on the command line, and
    is the only thing in the file that names `environ` at all.  The completion
    row and the `$`-prefix context that selects it go together -- exactly as the
    `~user` row and its context did in Phase 22.
  * `term_bg_default()` -- `$COLORFGBG` is a terminal telling the editor its own
    background.  Phase 21 already decided what terminal this is.

WHAT STAYS, and the distinction is worth stating: `vim_localtime()` no longer
reads `$TZ` to decide whether to call `tzset()`, but it still calls
`localtime_r()`, and musl reads `$TZ` inside that.  The rule this phase enforces
is that *this source* asks the environment nothing; making a file's timestamp
display in UTC instead would be a different decision, and not this one.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cutil

# expand_env_esc, with the $ arm gone.  Written out rather than cut, because
# what survives is the loop's tail and it reads better as its own function than
# as a `copy_char` flag that is now always true.
COPY = '''    char_u      *src;
    char_u      *dst_start = dst;

    // $VAR is part of a name, not a place to look one up.  There is no
    // environment to ask, so what is left of this is the escape handling and
    // the bound on dstlen: a name reaches its caller as it was written.
    src = skipwhite(srcp);
    --dstlen;
    while (*src && dstlen > 0)
    {
        if (src[0] == '\\\\' && src[1] != NUL)
        {
            *dst++ = *src++;
            --dstlen;
        }
        if (dstlen > 0)
        {
            *dst++ = *src++;
            --dstlen;
        }
    }
    *dst = NUL;

    return (size_t)(dst - dst_start);'''


def body(text, name, replacement):
    """Replace the body of the file-scope definition of `name`."""
    blanked = cutil.blank(text)
    m = re.search(r'^%s\([^\n]*\n' % re.escape(name), text, re.M)
    if not m:
        sys.exit('nogetenv: %s is not defined at file scope' % name)
    o = blanked.index('{', m.end())
    c = cutil.match(text, o, blanked)
    return text[:o] + '{\n' + replacement + '\n}' + text[c + 1:], text.count('\n', o, c)


def cut(text, pattern, what, count=1, flags=re.M):
    text, n = re.subn(pattern, '', text, count=count, flags=flags)
    if n != count:
        sys.exit('nogetenv: %s -- expected %d, matched %d' % (what, count, n))
    return text


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    text = path.read_text(errors='surrogateescape')

    # --- $VAR in a file name ----------------------------------------------
    text, was = body(text, 'expand_env_esc', COPY)
    print('  nogetenv     expand_env_esc was %d lines, and now copies a name' % was)

    # --- $PATH, the directories a command name completes from -------------
    text = cut(text,
               r'^[ \t]*if \(!mch_isFullName\(pat\)\)\n[ \t]*\{\n'
               r'[ \t]*path = vim_getenv\(\(char_u \*\)"PATH", &mustfree\);\n[ \t]*\}\n',
               '$PATH in expand_shellcmd')
    print('  nogetenv     $PATH, which was where a command name was looked for')

    # --- the *local-additions* scan, whose $VIMRUNTIME is always NULL ------
    # Phase 1 folded `vimruntime` to FALSE inside vim_getenv, so `rt` here has
    # been NULL since then and the block has added nothing.  It goes rather
    # than staying to look like it might.
    blanked = cutil.blank(text)
    k = text.index('    fname = gettail(curbuf->b_fname);\n'
                   '    if ( vim_fnamecmp((char_u *)(fname), (char_u *)("help.txt"))  == 0)')
    o = blanked.index('{', k + 40)
    c = cutil.match(text, o, blanked)
    end = text.index('\n', c) + 1
    print('  nogetenv     the local-additions scan, %d lines that $VIMRUNTIME '
          'being unset had already made a no-op' % text.count('\n', k, end))
    text = text[:k] + text[end:]

    # --- the defaults the environment used to choose ----------------------
    for name, call in (('set_init_default_shell', '$SHELL for \'shell\''),
                       ('set_init_default_cdpath', '$CDPATH for \'cdpath\'')):
        text, ok = cutil.delete_definition(text, name)
        if not ok:
            sys.exit('nogetenv: %s is not defined at file scope' % name)
        text = cut(text, r'^[ \t]*%s\(\);\n' % name, 'the call to ' + name)
        print('  nogetenv     %s' % call)

    text = cutil.drop_if(
        text, r'^[ \t]*if \( \(char_u \*\)getenv\(\(char \*\)\(\(char_u \*\)"VIM_POSIX"\)\)  != NULL\)$', flags=re.M)
    print("  nogetenv     $VIM_POSIX, which chose a stricter 'cpoptions'")

    # 'backupskip' was $TMPDIR, $TEMP, $TMP and always /tmp.  Three of the four
    # cannot contribute now, so the table goes and the loop runs its one pass;
    # `i` is left for the sweep.
    text = cut(text, r'^[ \t]*static char \*\(names\[4\]\) = \{"", "TMPDIR", "TEMP", "TMP"\};\n',
               "backupskip's table of environment names")
    # The loop's one surviving pass keeps its braces and its `mustfree`, which
    # the tail of the body still frees: the substitution keeps those two groups
    # rather than deleting the whole match.
    text, n = re.subn(
        r'[ \t]*for \(i = 0; i < \(int\) \(sizeof\(names\) / sizeof\(\(names\)\[0\]\)\) ; \+\+i\)\n'
        r'([ \t]*\{\n[ \t]*int[ \t]+mustfree = FALSE;\n)'
        r'[ \t]*if \(\*names\[i\] == NUL\)\n[ \t]*\{\n'
        r'([ \t]*p = \(char_u \*\)"/tmp";\n[ \t]*plen = \(int\) \(sizeof\("/tmp" ""\) - 1\) ;\n)'
        r'[ \t]*\}\n[ \t]*else\n[ \t]*\{\n'
        r'[ \t]*p = vim_getenv\(\(char_u \*\)names\[i\], &mustfree\);\n'
        r'[ \t]*plen = 0;\n[ \t]*\}\n',
        r'\1\2', text, count=1, flags=re.M)
    if n != 1:
        sys.exit("nogetenv: backupskip's loop over them is not where this expects")
    print("  nogetenv     $TMPDIR, $TEMP and $TMP; 'backupskip' keeps /tmp")

    # --- $VIM and $VIMRUNTIME, which this used to publish ------------------
    # vimrc_found() is reached only from do_source_ext(), and every do_source()
    # call in the file passes DOSO_NONE -- so these two arms have been dead
    # since Phase 20 stopped sourcing a vimrc.  They are what keep vim_setenv,
    # export_myvimdir and $MYVIMDIR alive.
    text = cut(text,
               r'[ \t]*if \(is_vimrc == DOSO_VIMRC\)\n[ \t]*\{\n'
               r'[ \t]*vimrc_found\(fname_exp, \(char_u \*\)"MYVIMRC"\);\n[ \t]*\}\n'
               r'[ \t]*else if \(is_vimrc == DOSO_GVIMRC\)\n[ \t]*\{\n'
               r'[ \t]*vimrc_found\(fname_exp, \(char_u \*\)"MYGVIMRC"\);\n[ \t]*\}\n\n?',
               'the two DOSO_VIMRC arms of do_source_ext')
    text = cutil.drop_if(text, r'^[ \t]*if \(varp == &p_rtp\)$', flags=re.M)
    print('  nogetenv     $VIM, $VIMRUNTIME and $MYVIMDIR stop being published')

    text, _ = body(text, 'did_set_helpfile', '    return NULL;')
    print("  nogetenv     'helpfile' stops unsetting what it can no longer set")

    # --- $VAR completion, and the only mention of environ ------------------
    text = cut(text, r'[ \t]*\{EXPAND_ENV_VARS, get_env_name, TRUE, TRUE\},\n',
               'the EXPAND_ENV_VARS completion row')
    text = cutil.drop_if(text, r"^[ \t]*if \(\*xp->xp_pattern == '\$'\)$", flags=re.M)
    text = cut(text, r'[ \t]*\{\(EXPAND_ENV_VARS\), \{\(\(char_u \*\)"environment"\)[^\n]*\n',
               "`:command -complete=environment`")
    print('  nogetenv     $VAR completion, and the one mention of environ')

    # --- $COLORFGBG, a terminal describing itself --------------------------
    text = cut(text,
               r' \|\| \(\(p =  \(char_u \*\)getenv\(\(char \*\)\(\(char_u \*\)"COLORFGBG"\)\) \) != NULL'
               r' && \(p = vim_strrchr\(p, \';\'\)\) != NULL'
               r" && \(\(p\[1\] >= '0' && p\[1\] <= '6'\) \|\| p\[1\] == '8'\) && p\[2\] == NUL\)",
               '$COLORFGBG in term_bg_default', flags=0)
    print("  nogetenv     $COLORFGBG; 'background' is what the table says")

    # --- $TZ ---------------------------------------------------------------
    # The cache existed to avoid calling tzset() on every timestamp.  musl's
    # localtime_r does the zone setup itself, so the call was the cache's only
    # purpose and both go.  libc still reads $TZ in there; this source does not.
    text, _ = body(text, 'vim_localtime', '    return localtime_r(timep, result);')
    print('  nogetenv     $TZ, and the tzset cache that existed to avoid it')

    path.write_text(text, errors='surrogateescape')
    n = len(re.findall(r'\bgetenv\b|\bsetenv\b|\benviron\b', text))
    print('  nogetenv     %d environment mentions left for the sweep' % n)


if __name__ == '__main__':
    main()
