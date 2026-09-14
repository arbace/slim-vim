#!/usr/bin/env python3
"""What the options Phase 3 drops used to set, and the code that read it.

Usage:
    python3 tools/optreaders.py <file>

tools/dropopts.py removes an option's `case` or its `else if`.  This removes what
only that option could ever make true.  A field nothing sets is still READ, so
no warning names it and no sweep can take it: the reader goes on answering the
same thing for ever.  An answer that cannot change is removed by removing the
question.

  -nb           early_arg_scan() existed to refuse it before anything else ran;
                its only other test was for `--`, which ended the scan.  The
                call goes and the sweep takes the function.
  --clean       set `params.clean` twice: in a pre-scan of argv at the top of
                main(), because set_init_1() needs it before options exist, and
                again in the parser.  set_init_1() used it for one thing, to call
                set_init_clean_rtp() and empty 'runtimepath' and 'packpath'.  The
                pre-scan, the parameter and that test all go, and the sweep takes
                set_init_clean_rtp().  A parameter that can only be FALSE is a
                field nothing sets, one call deep.
  --not-a-term  `params.not_a_term`, read through is_not_a_term() and
                is_not_a_term_or_gui() at eight places.  Each now takes the
                branch it always took when the option was not given.
  -n            `params.no_swap_file`, whose one reader set 'updatecount' to 0.
  -p            `WIN_TABS`, tested seven times in create_windows() and
                edit_buffers() to lay the files out as tab pages rather than
                windows, and `p_shm_save`, which kept those tab pages quiet while
                they were filled.  make_tabpages() is then unreachable and the
                sweep takes it.  The :tab commands do not use any of it.
  -h            mainerr() ended every usage error with `More info with: "vim -h"`,
                a pointer to an option that no longer exists, naming a binary
                this one is not.

-C, -N, -l, -V, --noplugin, --startuptime, --log, -d and -U set nothing that
cannot be set some other way, or nothing at all, so there is nothing here for
them.  -C's `has_dash_c_arg` is still read, by the vimrc search that Phase 18
replaces whole, and it goes then.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cutil

CLEAN_PRESCAN = '''    for (i = 1; i < argc; ++i)
    {
        if ( strcasecmp((char *)(argv[i]), (char *)("--clean"))  == 0)
        {
            params.clean = TRUE;
            break;
        }
    }

'''

# (what, old, new) -- each must occur exactly once.
LITERAL = [
    ('-nb: the scan that existed to refuse it',
     '    early_arg_scan(paramp);\n\n', ''),
    ('--clean: the pre-scan of argv at the top of main',
     CLEAN_PRESCAN, ''),
    ('--clean: main passing set_init_1 what only --clean could set',
     'set_init_1(paramp->clean);', 'set_init_1();'),
    ('--clean: set_init_1 taking it',
     'set_init_1(int clean_arg)', 'set_init_1(void)'),
    ('--not-a-term: whether a filter\'s output counts as redirected',
     '!stdout_isatty && !is_not_a_term_or_gui();', '!stdout_isatty;'),
    ('--not-a-term: clearing the command line on exit',
     'else if (!is_not_a_term())', 'else'),
    ('--not-a-term: check_tty\'s warning',
     ' && !parmp->not_a_term)', ')'),
    ('--not-a-term: "N files to edit"',
     ' && !is_not_a_term())', ')'),
    ('-p: equalising the windows it did not make',
     ' && parmp->window_layout != WIN_TABS)', ')'),
    ('-h: the pointer to it at the end of every usage error',
     '     fprintf(stderr, "%s", (_("\\nMore info with: \\"vim -h\\"\\n"))) ;\n', ''),
]

# (what, fold, pattern, count)
FOLDS = [
    ('--not-a-term: "Reading from stdin" and restoring the title',
     cutil.fold_always, r'^[ \t]*if \(!is_not_a_term\(\)\)$', 2),
    ('--not-a-term: the cursor to the last line on exit',
     cutil.fold_always, r'^[ \t]*if \(!is_not_a_term_or_gui\(\)\)$', 2),
    ("--clean: emptying 'runtimepath' and 'packpath'",
     cutil.fold_never, r'^[ \t]*if \(clean_arg\)$', 1),
    ("-n: 'updatecount' set to 0",
     cutil.fold_never, r'^[ \t]*if \(params\.no_swap_file\)$', 1),
    ('-p: tab pages instead of windows',
     cutil.fold_never, r'^[ \t]*if \(parmp->window_layout == WIN_TABS\)$', 5),
    ('-p: moving to the next tab page',
     cutil.fold_never, r'^[ \t]*else if \(parmp->window_layout == WIN_TABS\)$', 1),
    ("-p: restoring 'shortmess' after filling the tab pages",
     cutil.fold_never, r'^[ \t]*if \(p_shm_save != NULL\)$', 1),
]

# (what, pattern, count) -- regex deletions, each counted.
DELETIONS = [
    ('-p: the p_shm_save local', r'^[ \t]*char_u[ \t]+\*p_shm_save = NULL;\n', 1),
    ('--not-a-term: the two prototypes', r'^static int is_not_a_term(?:_or_gui)?\(void\);\n', 2),
]

# (what, pattern, count) -- what must be left, counted after every edit.
AFTER = [
    ('is_not_a_term', r'\bis_not_a_term', 0),
    ('p_shm_save', r'\bp_shm_save\b', 0),
    ('the clean field outside its declaration', r'(?:\.|->)clean\b', 0),
    ('clean_arg', r'\bclean_arg\b', 0),
    ('not_a_term outside its declaration', r'\bnot_a_term\b', 1),
    ('no_swap_file outside its declaration', r'\bno_swap_file\b', 1),
    ('WIN_TABS outside its enumerator', r'\bWIN_TABS\b', 1),
    ('early_arg_scan outside its definition and prototype', r'\bearly_arg_scan\(paramp\)', 0),
]


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    text = path.read_text(errors='surrogateescape')

    for what, old, new in LITERAL:
        n = text.count(old)
        if n != 1:
            sys.exit('optreaders: %s -- occurs %d times, not once' % (what, n))
        text = text.replace(old, new)
        print('  optreaders   %s' % what)

    for what, fold, pattern, count in FOLDS:
        try:
            text = fold(text, pattern, count, re.M)
        except ValueError as e:
            sys.exit('optreaders: %s -- %s' % (what, e))
        print('  optreaders   %s%s' % (what, ', %d places' % count if count > 1 else ''))

    for name in ('is_not_a_term', 'is_not_a_term_or_gui'):
        text, ok = cutil.delete_definition(text, name)
        if not ok:
            sys.exit('optreaders: %s is not defined at file scope' % name)
    for what, pattern, count in DELETIONS:
        text, n = re.subn(pattern, '', text, flags=re.M)
        if n != count:
            sys.exit('optreaders: %s -- expected %d, matched %d' % (what, count, n))
        print('  optreaders   %s' % what)

    for what, pattern, want in AFTER:
        n = len(re.findall(pattern, text))
        if n != want:
            sys.exit('optreaders: %s -- %d left, expected %d' % (what, n, want))

    path.write_text(text, errors='surrogateescape')
    print('  optreaders   nothing reads what a dropped option set')


if __name__ == '__main__':
    main()
