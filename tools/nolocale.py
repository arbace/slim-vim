#!/usr/bin/env python3
"""Stop asking the environment what language this is.

Usage:
    python3 tools/nolocale.py <file>

An embedded editor has no locale.  `setlocale(LC_ALL, "")` reads `$LANG`,
`$LC_ALL` and `$LC_CTYPE` at startup and changes how the process compares
strings, classifies characters and formats a time; `:language` lets the user
change it again; and `enc_locale()` derives `'encoding'` from
`nl_langinfo(CODESET)`.  All of it is the process taking instruction from the
environment, which is the thing this fork is narrowing.

**One edit here is load-bearing and is not a removal.** `'encoding'`'s compiled
default is `latin1`.  It is only ever `utf-8` because `set_init_default_encoding()`
asks the locale at startup and overwrites the default with the answer.  Delete
that call on its own and the editor silently becomes a latin1 editor -- every
multibyte motion, every `:s` over non-ASCII, every file read.  So the default
becomes `utf-8` in the same edit that removes the derivation.

That is not a behaviour change on this target, and it was checked rather than
assumed: musl's `nl_langinfo(CODESET)` answers UTF-8 unconditionally, so the
derived value was already `utf-8` -- with `$LANG` set, and with `$LANG` unset.
The change makes it a property of the build instead of a property of the
machine, which is the point.

Seven edits, each fatal if it does not apply:

  * `init_locale()` goes from `common_init_2` -- no `setlocale` at startup.
  * `set_init_default_encoding()` goes from `set_init_1`, and `'encoding'`
    defaults to `utf-8`.
  * `string_compare()` stops offering `strcoll`; `:sort l` sorts like `:sort`.
  * `:messages` stops printing a maintainer line gated on `$LANG`.
  * the `CMD_language` completion case, and the two locale rows of the
    completion dispatch table, which would otherwise keep `find_locales` alive
    -- it shells out to `locale -a`, and there is no shell.
  * `-complete=locale` stops being a name `:command` accepts.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, __file__.rsplit('/', 1)[0])

EDITS = [
    # (what, pattern, replacement, count)
    ('the setlocale at startup',
     r'^[ \t]*init_locale\(\);\n\n?', '', 1),
    # NOT a deletion.  set_init_default_encoding() did three things: ask the
    # locale, re-initialise the multibyte layer for whatever it answered, and
    # write that back as the option's default.  Only the first is locale.  The
    # second is load-bearing and invisible: `p_enc` is set from the option
    # table's default, and nothing acts on it until mb_init() runs.  Delete the
    # call outright and `'encoding'` reports utf-8 while `enc_utf8` is still
    # FALSE -- the editor says UTF-8 and behaves like latin1, which is worse
    # than either, and which five multibyte behaviour cases caught.
    ("deriving 'encoding' from the locale, keeping the mbyte init it also did",
     r'^([ \t]*)set_init_default_encoding\(\);$', r'\1(void)mb_init();', 1),
    ("'encoding' defaults to utf-8 instead of latin1",
     r'(\{"encoding",[^\n]*\n[^\n]*\n[ \t]*\{\(char_u \*\) )"latin1"', r'\1"utf-8"', 1),
    ('locale-aware collation in :sort',
     r'[ \t]*if \(sort_lc\)\n[ \t]*\{\n[ \t]*return strcoll\([^\n]*\n[ \t]*\}\n\n?', '', 1),
    ('the $LANG-gated maintainer line in :messages',
     r'[ \t]*s =  \(char_u \*\)getenv\(\(char \*\)\(\(char_u \*\)"LANG"\)\) ;\n'
     r'[ \t]*if \(s != NULL && \*s != NUL\)\n[ \t]*\{\n[ \t]*msg_attr\([^\n]*\n[ \t]*\}\n', '', 1),
    ('the :language completion case',
     r'[ \t]*case CMD_language:\n[ \t]*return set_context_in_lang_cmd\(xp, arg\);\n', '', 1),
    ('the two locale rows of the completion dispatch table',
     r'[ \t]*\{EXPAND_LANGUAGE, get_lang_arg, TRUE, FALSE\},\n'
     r'[ \t]*\{EXPAND_LOCALES, get_locales, TRUE, FALSE\},\n', '', 1),
    ('-complete=locale as a name :command accepts',
     r'[ \t]*\{\(EXPAND_LOCALES\), \{\(\(char_u \*\)"locale"\),[^\n]*\n', '', 1),
]

# The one that kept `setlocale` alive after everything else had gone, and the
# one that cannot be done with a regex.  mb_init() asks the locale what a DBCS
# terminal is speaking so it can convert messages into it; the block is guarded
# by `if (enc_dbcs)`, which made it easy to miss and impossible to reach for any
# encoding this build has.
#
# A lazy `(?:[^\n]*\n)*?\}` stops at the FIRST line that is just a brace, which
# here is the inner `if (p == NULL || ...)`'s -- leaving `vim_free(p);` and a
# stray `}` at file scope.  gcc reports that four hundred lines away as "data
# definition has no type or storage class", which is the same symptom
# funcreach.py's two regex bugs produced.  Match braces.
def drop_dbcs_conversion(text):
    import cutil
    i = text.find('    vimconv.vc_type = CONV_NONE;\n')
    if i < 0:
        sys.exit('nolocale: mb_init no longer sets up a conversion here')
    blanked = cutil.blank(text)
    opening = blanked.index('{', text.index('if (enc_dbcs)', i))
    close = cutil.match(text, opening, blanked)
    if close < 0:
        sys.exit('nolocale: the enc_dbcs block is unbalanced')
    end = close + 1
    while end < len(text) and text[end] in ' \t\n':
        end += 1
    # Only the block.  `vimconv` and its CONV_NONE initialiser STAY: mb_init
    # tests vimconv.vc_type again two hundred lines further down, and taking
    # the declaration on the strength of one visible use is how a phase turns
    # into a compile error four hundred lines from the edit.
    start = text.index('    if (enc_dbcs)', i)
    return text[:start] + text[end:]


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    text = path.read_text(errors='surrogateescape')

    for what, pat, repl, want in EDITS:
        text, n = re.subn(pat, repl, text, flags=re.M)
        if n != want:
            sys.exit('nolocale: %s -- expected %d, matched %d' % (what, want, n))
        print('  nolocale     %s' % what)

    text = drop_dbcs_conversion(text)
    print('  nolocale     the DBCS locale conversion in mb_init, and its local')

    if '"latin1"' in text.split('{"encoding"')[1][:400]:
        sys.exit("nolocale: 'encoding' still defaults to latin1, which would "
                 "make this a latin1 editor the moment the locale stops being "
                 "asked")

    path.write_text(text, errors='surrogateescape')
    print('  nolocale     %d setlocale calls left for the sweep'
          % text.count('setlocale('))


if __name__ == '__main__':
    main()
