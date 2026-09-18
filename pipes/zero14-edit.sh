#!/bin/sh
# Zero phase 14 -- the strings are the editor's own.  See ZERO-GOAL.md.
#
# Usage: pipes/zero14-edit.sh <work-dir> <state-dir>     (run from the repository root)
#
# Seventeen libc symbols are string and memory work, and every one of them is pure
# computation: no descriptor, no clock, no signal, nothing the host owns.  This phase
# brings sixteen of them into `zero-vim.c` as `static musl_*` functions written from
# /root/musl/src/string/, and moves the seventeenth -- `sprintf` -- onto the printf
# this editor already carries.  `nm -u` goes 61 -> 44 and the recording does not move.
#
# THE MEASUREMENT THAT MADE THIS PHASE POSSIBLE, and it was the open question:
# gcc emits calls to `memcpy` and `memset` FOR ITSELF, for aggregate assignments and
# large zero initialisers, whatever the source calls -- so renaming every call site
# might have left both symbols undefined and forced a definition under the REAL name,
# which is external linkage and would break "nothing is global but main()".  Measured
# on this file and it does not happen: after the rename, `gcc -S` contains NOT ONE
# call to any of the seventeen, and `nm -u` loses all seventeen.  Two things bound it
# rather than luck -- gcc's -O0 inline-copy threshold is between 8 KiB and 16 KiB (a
# 8192-byte struct assignment is inlined, a 16384-byte one calls memcpy), and
# `-Wlarger-than=8192` on zero-vim.c reports exactly ONE object above 8 KiB,
# `options[]` at 13,536 bytes, which is a table nothing assigns whole, while
# `-Wframe-larger-than=8192` reports none.  The check asserts the absence from `nm -u`,
# so a later phase that adds a big aggregate and assigns it whole fails loudly.
#
# (Measured and NOT taken: `-fno-builtin` and `-ffreestanding` each ADD `abs fprintf
# labs` and remove `fputc fputs fwrite putchar`.  A different set, not a smaller
# problem, and none of it is this phase's.  ZEROCFLAGS is untouched, so this phase
# edits no makefile and zero.mk needs no change.)
#
# `sprintf` IS TWO POPULATIONS AND THE SPLIT IS THE WHOLE STORY.  Of its 22
# occurrences, THIRTEEN are ordinary call sites that become `vim_snprintf(dest, size,
# ...)`, and NINE are inside `vim_vsnprintf_typval` ITSELF -- which is what
# vim_snprintf calls.  Using the in-house printf for those nine would be circular.
# What they actually do is narrow: `f` is built twenty lines above the call and is
# `%`, an optional `h`/`l`/`ll`, and one of `p d o u x X`, with NO flags, NO width and
# NO precision -- vim does all of those itself, in `tmp[]`, before and after.  So the
# nine are "write this integer in this base", and they become `musl_fmtnum()` and
# `musl_fmtptr()`, which have no format string and are not a printf.  The `char f[6]`
# block goes with them: leaving it would draw -Wunused-but-set-variable, which is in
# -Wall and which the sweep acts on.
#
# EVERY SIZE ARGUMENT IS KNOWABLE AND NONE IS INVENTED.  Eight are `sizeof()` of a
# visible array or the constant the buffer was allocated with -- `IObuff` is
# `alloc((1024+1))` and `NameBuff` is `alloc(PATH_MAX)` -- three repeat the `alloc()`
# expression from three lines above, and ONE, `highlight_arg_to_string`'s, is a
# pointer PARAMETER where `sizeof(buf)` would be 8 and wrong.  Its bound is
# `MAX_ATTR_LEN`, and that is sound ONLY because the function has exactly one caller,
# `highlight_list_arg`, whose local is `char_u buf[MAX_ATTR_LEN]`.  Both the edit and
# the check assert that caller count: a second caller appearing later would silently
# invalidate the bound, and the assertion is what catches it.
#
# `musl_strcasecmp` AND `musl_strncasecmp` DO NOT CALL `tolower`.  musl's do, and
# musl's `tolower` in the C locale is `(unsigned)c - 'A' < 26 ? c | 32 : c` and
# nothing else, so the arithmetic is inlined here.  That is not a shortcut: `tolower`
# belongs to the character-class phase, which counts its mentions, and four new ones
# here would trip it.  The check asserts `tolower` at exactly 2 mentions after this
# phase, which is what it had before.
#
# THE INPUT BINARY IS BUILT HERE, before the edit, from the boundary's own makefile
# flags, and the source goes with it as $state/old.c.  The check needs the binary for
# its one MUST-DIFFER probe: `t_CF` is a user-settable option used as a FORMAT STRING
# into `char buf[20]`, `sprintf` has no bound, and the binary this phase is handed
# SEGFAULTS on it.  vim_snprintf truncates instead.  That is a bug fix and it is the
# only reachable input on which this phase changes what the editor does.
set -eu

work=${1:?usage: zero14-edit.sh <work-dir> <state-dir>}
state=${2:?usage: zero14-edit.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"

# The flags are read out of the boundary's makefile rather than written here a
# second time: zero's compile line is the boundary's (ZERO-GOAL.md rule 8).
cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")
cp "$f" "$state/old.c"
# shellcheck disable=SC2086
( cd "$state" && gcc $cflags $ldflags -o old old.c ) &
pid_old=$!

python3 - "$f" <<'PY'
TAG = 'strings'
import re, sys
path = sys.argv[1]
t = open(path, errors='surrogateescape').read()


def die(msg):
    sys.exit('  %-12s %s' % (TAG, msg))


def say(what):
    print('  %-12s %s' % (TAG, what))


def mentions(text, name):
    """OCCURRENCES, not lines.  `grep -c` counts lines and gives 125 for strlen
    where there are 127, 65 for strncmp where there are 82 and 7 for strncasecmp
    where there are 13 -- a check written against `grep -c` refuses a correct
    phase."""
    return len(re.findall(r'\b%s\b' % name, text))


def text_edit(text, old, new, what, n=1):
    """An exact-text replacement, counted file-wide.  Never 'the first one'."""
    k = text.count(old)
    if k != n:
        die('%s -- the text occurs %d times, expected %d: %r'
            % (what, k, n, old[:70]))
    return text.replace(old, new)


# ---- 0. the shape every anchor below was counted against ---------------------------
# The seventeen, as OCCURRENCES.  Nothing here is approximate: a rename is only safe
# if the count of what is about to be renamed is known first.
BEFORE = {'memmove': 159, 'strlen': 127, 'memset': 79, 'strncmp': 82, 'strcmp': 62,
          'strcpy': 51, 'sprintf': 22, 'memcpy': 7, 'strncasecmp': 13, 'strcat': 6,
          'strcasecmp': 6, 'strncpy': 4, 'strstr': 3, 'strchr': 2, 'memcmp': 2,
          'memchr': 1, 'strpbrk': 2,
          'vim_snprintf': 55, 'vim_vsnprintf_typval': 4,
          'tolower': 2,               # the character-class phase's, and untouched
          'highlight_arg_to_string': 2, 'MAX_ATTR_LEN': 2}
for name, want in sorted(BEFORE.items()):
    k = mentions(t, name)
    if k != want:
        die('%s has %d mentions, expected %d -- the anchors below were counted '
            'against a different file' % (name, k, want))
say('the seventeen at 606 + 22 occurrences, tolower at 2, vim_snprintf at 55 -- the '
    'file the anchors below were counted against')

# ---- THE SINGLE CALLER, COUNTED BEFORE THE BOUND IS CHOSEN ---------------------------
# `highlight_arg_to_string(..., char_u *buf)` takes a POINTER, so sizeof(buf) is 8 and
# the bound has to come from outside the call.  It is sound only while there is
# exactly one caller and that caller's local is char_u buf[MAX_ATTR_LEN].
if mentions(t, 'highlight_arg_to_string') != 2:
    die('highlight_arg_to_string has %d mentions and not the definition plus ONE '
        'call: MAX_ATTR_LEN is only its buffer size while highlight_list_arg is its '
        'only caller' % mentions(t, 'highlight_arg_to_string'))
if t.count('    char_u      buf[MAX_ATTR_LEN];\n') != 1:
    die("highlight_list_arg's `char_u buf[MAX_ATTR_LEN];` is not there exactly once, "
        'and it is where the bound for site 25443 comes from')
if t.count('enum { MAX_ATTR_LEN = 120 };\n') != 1:
    die('MAX_ATTR_LEN is not the one enumerator this phase reads')
say('highlight_arg_to_string has ONE caller, highlight_list_arg, whose local is '
    'char_u buf[MAX_ATTR_LEN] with MAX_ATTR_LEN = 120 -- that, and nothing weaker, '
    'is why the size argument at site 25443 may be a constant from another function')

# ---- A. the thirteen external sprintf sites -------------------------------------------
# Exact whole-line text, one occurrence each.  Every one is a STATEMENT whose return
# value is discarded, so vim_snprintf is a drop-in; vim_snprintf is declared at the
# top of the file, above all thirteen.  The size is the second argument and nothing
# else about the line changes.
SITES = [
    ('        sprintf((char *)buf, "%d", iarg - 1);',
     '        vim_snprintf((char *)buf, MAX_ATTR_LEN, "%d", iarg - 1);',
     'highlight_arg_to_string: a pointer parameter, bounded by its one caller'),
    ('        sprintf((char *)str, "!(:%s", opt);',
     '        vim_snprintf((char *)str, sizeof("!(:") +  strlen((char *)(opt)) , "!(:%s", opt);',
     "update_wincolor: the alloc() expression from four lines above, which fits exactly"),
    ('                sprintf((char *)IObuff, " %c %6ld %4d ", c, p->lnum, p->col);',
     '                vim_snprintf((char *)IObuff,  (1024+1) , " %c %6ld %4d ", c, p->lnum, p->col);',
     'show_one_mark: IObuff, which is alloc((1024+1))'),
    ('            sprintf((char *)IObuff, "%c %3d %5ld %4d ", i == curwin->w_changelistidx ? \'>\' : \' \', i > curwin->w_changelistidx ? i - curwin->w_changelistidx : curwin->w_changelistidx - i, (long)curbuf->b_changelist[i].lnum, curbuf->b_changelist[i].col);',
     '            vim_snprintf((char *)IObuff,  (1024+1) , "%c %3d %5ld %4d ", i == curwin->w_changelistidx ? \'>\' : \' \', i > curwin->w_changelistidx ? i - curwin->w_changelistidx : curwin->w_changelistidx - i, (long)curbuf->b_changelist[i].lnum, curbuf->b_changelist[i].col);',
     'ex_changes: the same buffer'),
    ('        sprintf((char *)IObuff + rlen, "%02x ", (line[i] == NL) ? NUL : line[i]);',
     '        vim_snprintf((char *)IObuff + rlen, (size_t)( (1024+1)  - rlen), "%02x ", (line[i] == NL) ? NUL : line[i]);',
     "do_ascii: IObuff at an offset, and the loop's own guard bounds rlen"),
    ('            sprintf((char *)Buf, (char *)p, sname);',
     '            vim_snprintf((char *)Buf,  strlen((char *)(sname))  +  strlen((char *)(p)) , (char *)p, sname);',
     'get_emsg_source: a RUNTIME format, and the alloc() expression repeated'),
    ('            sprintf((char *)Buf, (char *)p, (long) (((estack_T *)exestack.ga_data)[exestack.ga_len - 1].es_lnum) );',
     '            vim_snprintf((char *)Buf,  strlen((char *)(p))  + 20, (char *)p, (long) (((estack_T *)exestack.ga_data)[exestack.ga_len - 1].es_lnum) );',
     'get_emsg_lnum: the same shape'),
    ('        sprintf((char *)NameBuff, "%ld", *(long *)varp);',
     '        vim_snprintf((char *)NameBuff, PATH_MAX, "%ld", *(long *)varp);',
     'option_value2string: NameBuff, which is alloc(PATH_MAX)'),
    ('    sprintf((char *)IObuff, "Vim: Caught deadly signal %s\\r\\n", signal_info[i].name);',
     '    vim_snprintf((char *)IObuff,  (1024+1) , "Vim: Caught deadly signal %s\\r\\n", signal_info[i].name);',
     'deadly_signal: IObuff again'),
    ('    sprintf(s, " @%c", reg_recording);',
     '    vim_snprintf(s, sizeof(s), " @%c", reg_recording);',
     'recording_mode: char s[4], which the four bytes fill exactly'),
    ('        sprintf((char *)nr_colors, "%d", t_colors);',
     '        vim_snprintf((char *)nr_colors, sizeof(nr_colors), "%d", t_colors);',
     'set_color_count: char_u nr_colors[20]'),
    ('        sprintf(buf, (char *) ( term_strings[(int)(KS_CF)] ) , 9 + n);',
     '        vim_snprintf(buf, sizeof(buf), (char *) ( term_strings[(int)(KS_CF)] ) , 9 + n);',
     'term_font: char buf[20] and t_CF, THE ONE SITE THAT CAN OVERFLOW TODAY'),
    ('        sprintf(buf, format, lead, tail);',
     '        vim_snprintf(buf, sizeof(buf), format, lead, tail);',
     'term_color: char buf[20] and a local format that is "%s%s%%dm"'),
]
for old, new, what in SITES:
    t = text_edit(t, old, new, what)
say('thirteen external sprintf call sites are vim_snprintf now, each with the size '
    'its destination really has -- eight a sizeof() or the constant the buffer was '
    'allocated with, three the alloc() expression repeated, one MAX_ATTR_LEN from '
    'the single caller above, and term_font the one that could overflow')

# ---- B. the nine inside vim_vsnprintf_typval, and the format string they shared -------
# `f` is `%`, an optional length modifier and the spec, and NOTHING ELSE -- vim has
# already put the sign, the alternate form's `0x` and the padding into tmp[] by hand,
# and puts the width and precision there afterwards.  So these nine are an integer
# conversion, and they become one.  THE BLOCK GOES FIRST: removing the calls and
# leaving `f` would draw -Wunused-but-set-variable, which is in -Wall.
t = text_edit(t,
              "                        char    f[6];\n"
              "                        int     f_l = 0;\n"
              "\n"
              "                        f[f_l++] = '%';\n"
              "                        if (!length_modifier)\n"
              "                        {\n"
              "                            ;\n"
              "                        }\n"
              "                        else if (length_modifier == 'L')\n"
              "                        {\n"
              "                            f[f_l++] = 'l';\n"
              "                            f[f_l++] = 'l';\n"
              "                        }\n"
              "                        else\n"
              "                        {\n"
              "                            f[f_l++] = length_modifier;\n"
              "                        }\n"
              "                        f[f_l++] = fmt_spec;\n"
              "                        f[f_l++] = '\\0';\n"
              "\n", '',
              "vim_vsnprintf_typval's `char f[6]`, the two-to-five character format "
              'string it built for the nine calls below')
t = text_edit(t,
              "                        if (fmt_spec == 'p')\n"
              "                        {\n"
              "                            str_arg_l += sprintf(tmp + str_arg_l, f, ptr_arg);\n"
              "                        }\n",
              "                        if (fmt_spec == 'p')\n"
              "                        {\n"
              "                            str_arg_l += musl_fmtptr(tmp + str_arg_l, ptr_arg);\n"
              "                        }\n",
              "%p, which musl's own printf renders as `0x` and sixteen zero-padded "
              'hex digits -- musl vfprintf does `p = MAX(p, 2*sizeof(void*)); t = '
              "'x'; fl |= ALT_FORM`, so musl_fmtptr reproduces that and not glibc's "
              '`(nil)`')
# The eight integer arms.  They differ in their argument and in their trailing
# indentation, which is why these are eight one-count patterns and not one pattern
# with a count of eight.
ARMS = [
    ('int_arg);', '(unsigned long long)(long long)int_arg, 10, 0, int_arg < 0);'),
    ('(short)int_arg);',
     '(unsigned long long)(long long)(short)int_arg, 10, 0, (short)int_arg < 0);'),
    ('long_arg);', '(unsigned long long)(long long)long_arg, 10, 0, long_arg < 0);'),
    ('llong_arg);', '(unsigned long long)llong_arg, 10, 0, llong_arg < 0);'),
    ('uint_arg);',
     "(unsigned long long)uint_arg, musl_fmtbase(fmt_spec), fmt_spec == 'X', 0);"),
    ('(unsigned short)uint_arg);',
     "(unsigned long long)(unsigned short)uint_arg, musl_fmtbase(fmt_spec), fmt_spec == 'X', 0);"),
    ('ulong_arg);',
     "(unsigned long long)ulong_arg, musl_fmtbase(fmt_spec), fmt_spec == 'X', 0);"),
    ('ullong_arg);',
     "(unsigned long long)ullong_arg, musl_fmtbase(fmt_spec), fmt_spec == 'X', 0);"),
]
PAD = ' ' * 32
for arg, call in ARMS:
    t = text_edit(t,
                  PAD + 'str_arg_l += sprintf(tmp + str_arg_l, f, ' + arg,
                  PAD + 'str_arg_l += musl_fmtnum(tmp + str_arg_l, ' + call,
                  'the %s arm' % arg[:-2])
if mentions(t, 'sprintf') or mentions(t, 'f_l'):
    die('sprintf has %d mentions and f_l %d after the nine went, and both must be 0'
        % (mentions(t, 'sprintf'), mentions(t, 'f_l')))
say('the nine calls inside vim_vsnprintf_typval are musl_fmtnum() and musl_fmtptr() '
    'now, and the char f[6] that fed them is gone -- sprintf at 0 mentions and f_l '
    'at 0')

# ---- C. the rename, outside string and character literals ------------------------------
# zero-vim.c has NO comments and no preprocessor directive but its eighteen
# #includes, so a scanner that knows about '...' and "..." with backslash escapes
# knows everything there is to know about where an identifier is not an identifier.
# MEASURED: not one literal in this file mentions any of the sixteen, so the literal
# awareness is belt and braces -- but a rename that did not have it would be a guess.
NAMES = ['memmove', 'strlen', 'memset', 'strncmp', 'strcmp', 'strcpy', 'memcpy',
         'strncasecmp', 'strcat', 'strcasecmp', 'strncpy', 'strstr', 'strchr',
         'memcmp', 'memchr', 'strpbrk']


def runs(text):
    """(is_literal, text) pairs."""
    out, i, n, start = [], 0, len(text), 0
    while i < n:
        c = text[i]
        if c == '"' or c == "'":
            out.append((False, text[start:i]))
            j = i + 1
            while j < n:
                if text[j] == '\\':
                    j += 2
                    continue
                if text[j] == c or text[j] == '\n':
                    j += 1 if text[j] == c else 0
                    break
                j += 1
            out.append((True, text[i:j]))
            i = start = j
        else:
            i += 1
    out.append((False, text[start:]))
    return out


pat = re.compile(r'\b(%s)\b' % '|'.join(NAMES))
pieces, renamed = [], 0
for is_lit, s in runs(t):
    if is_lit:
        if pat.search(s):
            die('a string literal mentions one of the sixteen and the rename would '
                'change what the editor PRINTS: %r' % s[:60])
        pieces.append(s)
    else:
        s, k = pat.subn(lambda m: 'musl_' + m.group(1), s)
        renamed += k
        pieces.append(s)
t = ''.join(pieces)
# 606 in the input + 4 that section A's size expressions introduced (two strlen in
# get_emsg_source, one in get_emsg_lnum, one in update_wincolor).  THE ORDER MATTERS:
# a phase that renamed first and edited sprintf afterwards would leave four bare
# strlen behind, which would compile and would keep the symbol.
if renamed != 610:
    die('%d identifiers were renamed, expected 610 -- 606 in the input plus the four '
        'strlen the size expressions above introduce' % renamed)
say('610 identifiers renamed to musl_*, none of them inside a literal -- 606 of the '
    'input and the four strlen the size arguments added')

# ---- D. the definitions, after the eighteen #includes -----------------------------------
# DEFINED BEFORE FIRST USE, so no prototype is needed and no prototype block is
# touched -- one fewer anchor and one fewer thing for a later phase to keep in step.
# Everything they name is already available: size_t and NULL from <stddef.h>,
# uintptr_t from <stdint.h>.  `tolower` is NOT used; see the header of this file.
DEFS = r'''
    static void *
musl_memcpy(void *dest, const void *src, size_t n)
{
    unsigned char *d = dest;
    const unsigned char *s = src;
    for (; n; n--)
    {
        *d++ = *s++;
    }
    return dest;
}

    static void *
musl_memmove(void *dest, const void *src, size_t n)
{
    unsigned char *d = dest;
    const unsigned char *s = src;
    if (d == s)
    {
        return dest;
    }
    if (d < s)
    {
        for (; n; n--)
        {
            *d++ = *s++;
        }
    }
    else
    {
        while (n)
        {
            n--;
            d[n] = s[n];
        }
    }
    return dest;
}

    static void *
musl_memset(void *dest, int c, size_t n)
{
    unsigned char *s = dest;
    for (; n; n--)
    {
        *s++ = (unsigned char)c;
    }
    return dest;
}

    static int
musl_memcmp(const void *vl, const void *vr, size_t n)
{
    const unsigned char *l = vl;
    const unsigned char *r = vr;
    for (; n && *l == *r; n--, l++, r++)
    {
    }
    return n ? *l - *r : 0;
}

    static void *
musl_memchr(const void *src, int c, size_t n)
{
    const unsigned char *s = src;
    unsigned char ch = (unsigned char)c;
    for (; n && *s != ch; s++, n--)
    {
    }
    return n ? (void *)s : NULL;
}

    static size_t
musl_strlen(const char *s)
{
    const char *a = s;
    for (; *s; s++)
    {
    }
    return (size_t)(s - a);
}

    static char *
musl_strcpy(char *dest, const char *src)
{
    char *d = dest;
    while ((*d = *src) != 0)
    {
        d++;
        src++;
    }
    return dest;
}

    static char *
musl_strncpy(char *dest, const char *src, size_t n)
{
    char *d = dest;
    for (; n && *src; n--)
    {
        *d++ = *src++;
    }
    for (; n; n--)
    {
        *d++ = 0;
    }
    return dest;
}

    static char *
musl_strcat(char *dest, const char *src)
{
    musl_strcpy(dest + musl_strlen(dest), src);
    return dest;
}

    static int
musl_strcmp(const char *l, const char *r)
{
    for (; *l == *r && *l; l++, r++)
    {
    }
    return *(const unsigned char *)l - *(const unsigned char *)r;
}

    static int
musl_strncmp(const char *ls, const char *rs, size_t n)
{
    const unsigned char *l = (const unsigned char *)ls;
    const unsigned char *r = (const unsigned char *)rs;
    if (!n--)
    {
        return 0;
    }
    for (; *l && *r && n && *l == *r; l++, r++, n--)
    {
    }
    return *l - *r;
}

    static int
musl_strcasecmp(const char *ls, const char *rs)
{
    const unsigned char *l = (const unsigned char *)ls;
    const unsigned char *r = (const unsigned char *)rs;
    for (; *l && *r && ((unsigned)*l - 'A' < 26 ? *l | 32 : *l) == ((unsigned)*r - 'A' < 26 ? *r | 32 : *r); l++, r++)
    {
    }
    return ((unsigned)*l - 'A' < 26 ? *l | 32 : *l) - ((unsigned)*r - 'A' < 26 ? *r | 32 : *r);
}

    static int
musl_strncasecmp(const char *ls, const char *rs, size_t n)
{
    const unsigned char *l = (const unsigned char *)ls;
    const unsigned char *r = (const unsigned char *)rs;
    if (!n--)
    {
        return 0;
    }
    for (; *l && *r && n && ((unsigned)*l - 'A' < 26 ? *l | 32 : *l) == ((unsigned)*r - 'A' < 26 ? *r | 32 : *r); l++, r++, n--)
    {
    }
    return ((unsigned)*l - 'A' < 26 ? *l | 32 : *l) - ((unsigned)*r - 'A' < 26 ? *r | 32 : *r);
}

    static char *
musl_strchr(const char *s, int c)
{
    unsigned char ch = (unsigned char)c;
    for (; *s && *(const unsigned char *)s != ch; s++)
    {
    }
    if (*(const unsigned char *)s == ch)
    {
        return (char *)s;
    }
    return NULL;
}

    static char *
musl_strstr(const char *h, const char *n)
{
    size_t i;
    if (!n[0])
    {
        return (char *)h;
    }
    for (; *h; h++)
    {
        for (i = 0; n[i] && h[i] == n[i]; i++)
        {
        }
        if (!n[i])
        {
            return (char *)h;
        }
    }
    return NULL;
}

    static char *
musl_strpbrk(const char *s, const char *b)
{
    const char *c;
    for (; *s; s++)
    {
        for (c = b; *c; c++)
        {
            if (*s == *c)
            {
                return (char *)s;
            }
        }
    }
    return NULL;
}

    static int
musl_fmtbase(char spec)
{
    if (spec == 'o')
    {
        return 8;
    }
    if (spec == 'x' || spec == 'X')
    {
        return 16;
    }
    return 10;
}

    static int
musl_fmtnum(char *dest, unsigned long long v, int base, int upper, int isneg)
{
    char digits[24];
    int n = 0;
    int out = 0;
    int i;
    int d;

    if (isneg)
    {
        v = ~v + 1ULL;
    }
    do
    {
        d = (int)(v % (unsigned long long)base);
        if (d < 10)
        {
            digits[n++] = (char)('0' + d);
        }
        else if (upper)
        {
            digits[n++] = (char)('A' + d - 10);
        }
        else
        {
            digits[n++] = (char)('a' + d - 10);
        }
        v /= (unsigned long long)base;
    }
    while (v != 0)
        ;
    if (isneg)
    {
        dest[out++] = '-';
    }
    for (i = 0; i < n; i++)
    {
        dest[out++] = digits[n - 1 - i];
    }
    dest[out] = '\0';
    return out;
}

    static int
musl_fmtptr(char *dest, void *p)
{
    unsigned long long v = (unsigned long long)(uintptr_t)p;
    int i;
    int d;

    dest[0] = '0';
    dest[1] = 'x';
    for (i = 0; i < 16; i++)
    {
        d = (int)((v >> (60 - 4 * i)) & 0xf);
        if (d < 10)
        {
            dest[2 + i] = (char)('0' + d);
        }
        else
        {
            dest[2 + i] = (char)('a' + d - 10);
        }
    }
    dest[18] = '\0';
    return 18;
}
'''
ANCHOR = '#include <termios.h>\n\n'
t = text_edit(t, ANCHOR, ANCHOR + DEFS.lstrip('\n') + '\n',
              'the eighteen definitions go after the eighteenth and last #include, '
              'before the first enum -- defined ahead of every use, so no prototype '
              'is added and the prototype block is not touched')

# ---- E. what the sweep is handed, as counts rather than as trust -------------------------
AFTER = {'sprintf': 0, 'f_l': 0, 'tolower': 2, 'vim_snprintf': 68,
         'musl_memmove': 160, 'musl_strlen': 133, 'musl_memset': 80,
         'musl_strncmp': 83, 'musl_strcmp': 63, 'musl_strcpy': 53, 'musl_memcpy': 8,
         'musl_strncasecmp': 14, 'musl_strcat': 7, 'musl_strcasecmp': 7,
         'musl_strncpy': 5, 'musl_strstr': 4, 'musl_strchr': 3, 'musl_memcmp': 3,
         'musl_memchr': 2, 'musl_strpbrk': 3,
         'musl_fmtnum': 9, 'musl_fmtptr': 2, 'musl_fmtbase': 5}
for name, want in sorted(AFTER.items()):
    k = mentions(t, name)
    if k != want:
        die('%s has %d mentions after the cut, expected %d' % (name, k, want))
for name in NAMES + ['sprintf']:
    if re.search(r'(?<!_)\b%s\b' % name, t):
        die('%s survives as a bare name somewhere' % name)
directives = [l for l in t.split('\n') if l.startswith('#')]
if len(directives) != 18 or any(not l.startswith('#include <') for l in directives):
    die('the file has %d lines starting with # and they must be the same eighteen '
        '#includes: this phase adds no preprocessor syntax' % len(directives))
say('the cut is done: sprintf and f_l at 0, tolower still at 2 -- the '
    'character-class phase\'s and untouched -- vim_snprintf 55 -> 68, the sixteen '
    'musl_* at their source counts plus their own definitions, musl_fmtnum at 9 and '
    'musl_fmtptr at 2, and eighteen #include lines and no other directive')

open(path, 'w', errors='surrogateescape').write(t)
PY

# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  strings      the input binary did not build with '$cflags' '$ldflags'"; exit 1; }
echo "  strings      the input is $state/old, $(stat -c%s "$state/old") bytes, beside the source it was built from: the check needs it for the one MUST-DIFFER probe this phase has, where t_CF overflows char buf[20] and the old binary dies of it"

# tools/phaserun.sh sweeps next, then runs pipes/zero14-check.sh.
