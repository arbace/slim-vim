r"""`K` and the tag jumps, keeping `*` and `#`.

Usage:
    python3 tools/noident.py <file>

`nv_ident()` is not one command, it is five, and they have nothing in common but
the first step -- read the identifier under the cursor:

    *  #  g*  g#      search for that word          -- STAY
    K                 run 'keywordprg' on it        -- goes
    ]  CTRL-]  g]     jump to its tag               -- goes

`*` and `#` are among the most used keys in vim and are pure search.  Deleting
`nv_ident()` wholesale would take them, which is why this phase rewrites the
function rather than removing it.

`K` runs `'keywordprg'` through a shell, and Phase 8 took the shell.  The tag
jumps build an Ex command -- `ta `, `tj `, `ts `, `he! ` -- and hand it to
`do_cmdline_cmd()`; Phase 12 retired the tag stack, so every one of those names
is already `ex_ni`.  Both arms have been building commands that fail.

What the rewrite drops with them: `nv_K_getcmd()`, the `kp`/`kp_help`/`kp_ex`
setup, `tag_cmd` and the two escape sets it chose between, `g_tag_at_cursor`,
and the `do_cmdline_cmd()` tail.  What it keeps is the whole of the search path,
including `\<`/`\>` word anchoring, the magic-dependent escape set, the
pcmark, and the search-history entry.

FOUR ENTRY POINTS GO and three stay.  `nv_cmds[]` loses its `K` and `CTRL-]`
rows and keeps `*`, `#` and `POUND`; `nv_g_cmd()` loses `]` and `CTRL-]` from
its case list and keeps the same three; and `do_window()` loses `CTRL-W ]` and
`CTRL-W g]`, which are tag jumps that open a split first -- after which
`do_nv_ident()` has no callers at all.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cutil

BODY = '''    char_u      *ptr = NULL;
    char_u      *buf;
    size_t      bufsize;
    size_t      buflen;
    char_u      *p;
    int         n = 0;
    int         cmdchar;
    int         g_cmd;
    char_u      *aux_ptr;

    if (cap->cmdchar == 'g')
    {
        cmdchar = cap->nchar;
        g_cmd = TRUE;
    }
    else
    {
        cmdchar = cap->cmdchar;
        g_cmd = FALSE;
    }

    if (cmdchar == POUND)
    {
        cmdchar = '#';
    }

    if (ptr == NULL && (n = find_ident_under_cursor(&ptr, (cmdchar == '*' || cmdchar == '#') ? FIND_IDENT|FIND_STRING : FIND_IDENT)) == 0)
    {
        clearop(cap->oap);
        return;
    }

    bufsize = (size_t)(n * 2 + 30);
    buf = alloc(bufsize);
    if (buf == NULL)
    {
        return;
    }
    buf[0] = NUL;
    buflen = 0;

    setpcmark();
    curwin->w_cursor.col = (colnr_T) (ptr - ml_get_curline());

    if (!g_cmd && vim_iswordp(ptr))
    {
         strcpy((char *)(buf), (char *)("\\\\<")) ;
        buflen =  (sizeof("\\\\<" "") - 1) ;
    }
    no_smartcase = TRUE;

    if (cmdchar == '*')
    {
        aux_ptr = (char_u *)(magic_isset() ? "/.*~[^$\\\\" : "/^$\\\\");
    }
    else
    {
        aux_ptr = (char_u *)(magic_isset() ? "/?.*~[^$\\\\" : "/?^$\\\\");
    }

    p = buf + buflen;
    while (n-- > 0)
    {
        if (vim_strchr(aux_ptr, *ptr) != NULL)
        {
            *p++ = '\\\\';
        }

        if (has_mbyte)
        {
            int i;
            int len = (*mb_ptr2len)(ptr) - 1;

            for (i = 0; i < len && n >= 1; ++i, --n)
            {
                *p++ = *ptr++;
            }
        }
        *p++ = *ptr++;
    }
    *p = NUL;
    buflen = p - buf;

    if (!g_cmd && (has_mbyte ? vim_iswordp(mb_prevptr(ml_get_curline(), ptr)) : vim_iswordc(ptr[-1])))
    {
         strcpy((char *)(buf + buflen), (char *)("\\\\>")) ;
        buflen +=  (sizeof("\\\\>" "") - 1) ;
    }

    init_history();
    add_to_history(HIST_SEARCH, buf, buflen, TRUE, NUL);

    (void)normal_search(cap, cmdchar == '*' ? '/' : '?', buf, buflen, 0, NULL);

    vim_free(buf);'''


def cut(text, pattern, what, count=1, flags=re.M):
    text, n = re.subn(pattern, '', text, count=count, flags=flags)
    if n != count:
        sys.exit('noident: %s -- expected %d, matched %d' % (what, count, n))
    return text


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    text = path.read_text(errors='surrogateescape')

    # --- the function, rewritten to the half that is search ----------------
    blanked = cutil.blank(text)
    m = re.search(r'^nv_ident\(cmdarg_T \*cap\)\n', text, re.M)
    if not m:
        sys.exit('noident: nv_ident is not defined at file scope')
    o = blanked.index('{', m.end())
    c = cutil.match(text, o, blanked)
    was = text.count('\n', o, c)
    if 'nv_K_getcmd' not in text[o:c]:
        sys.exit('noident: nv_ident does not look like the one this expects')
    text = text[:o] + '{\n' + BODY + '\n}' + text[c + 1:]
    print('  noident      nv_ident was %d lines and is now the search half' % was)

    # --- the rows and cases that fed it the other three --------------------
    # A ROW IS NEVER DELETED FROM nv_cmds[], IT IS POINTED AT nv_error --
    # which is PURE-GOAL rule 3, and it turns out to apply to normal-mode
    # commands for exactly the reason it applies to Ex ones.  `nv_cmd_idx[]` is
    # a static const array of INDICES INTO nv_cmds[], precomputed and sorted by
    # command character, with `nv_max_linear` marking how far a direct lookup
    # works.  Deleting two rows shifts every later index and the precomputed
    # table still points at the old positions, so every normal command after
    # them dispatches to the wrong function.
    #
    # The first version of this phase deleted the rows.  It built, it swept
    # clean, it passed the linkage and symbol checks -- and 39 of the 67
    # behaviour cases moved: CTRL-A, joins, macros, marks, multibyte motions,
    # nothing to do with `K` or tags.  That is what a parallel table looks like
    # from the outside.
    #
    # nv_error() is the normal-mode ex_ni: it beeps, which is what an unbound
    # key does.
    text, n = re.subn(r'^([ \t]*\{Ctrl_RSB, )nv_ident(, NV_NCW, 0\} ,\n)',
                      r'\1nv_error\2', text, count=1, flags=re.M)
    text, n2 = re.subn(r"^([ \t]*\{'K', )nv_ident(, 0, 0\} ,\n)",
                       r'\1nv_error\2', text, count=1, flags=re.M)
    if n + n2 != 2:
        sys.exit('noident: the CTRL-] and K rows are not where this expects')
    text = cut(text,
               r'^[ \t]*case POUND:\n[ \t]*case Ctrl_RSB:\n[ \t]*case \]:\n',
               "nv_g_cmd's tag cases") if False else text
    text, n = re.subn(r"(    case '\*':\n    case '#':\n    case POUND:\n)"
                      r"    case Ctrl_RSB:\n    case \]:\n", r'\1', text, count=1)
    if n != 1:
        # the labels are spelled with the character constants
        text, n = re.subn(r"(\n[ \t]*case POUND:\n)[ \t]*case Ctrl_RSB:\n[ \t]*case '\]':\n",
                          r'\1', text, count=1)
    if n != 1:
        sys.exit("noident: nv_g_cmd's tag cases are not where this expects")
    print('  noident      K and CTRL-] answer nv_error, and g] leaves nv_g_cmd')

    # --- CTRL-W ] and CTRL-W g], which split first and then jump -----------
    text = cut(text,
               r"^    case '\]':\n[ \t]*case Ctrl_RSB:\n(?:[^\n]*\n)*?"
               r'[ \t]*do_nv_ident\(Ctrl_RSB, NUL\);\n'
               r'[ \t]*postponed_split = 0;\n[ \t]*break;\n\n?',
               "do_window's CTRL-W ]")
    text = cut(text,
               r"^[ \t]*case '\]':\n[ \t]*case Ctrl_RSB:\n(?:[^\n]*\n)*?"
               r"[ \t]*do_nv_ident\('g', xchar\);\n"
               r'[ \t]*postponed_split = 0;\n[ \t]*break;\n\n?',
               "do_window's CTRL-W g]")
    print('  noident      CTRL-W ] and CTRL-W g], which split and then jump')

    path.write_text(text, errors='surrogateescape')
    print('  noident      %d nv_K_getcmd/do_nv_ident mentions left for the sweep'
          % len(re.findall(r'\b(?:nv_K_getcmd|do_nv_ident|g_tag_at_cursor)\b', text)))


if __name__ == '__main__':
    main()
