r"""No floating-point library, and no floating-point conversion.

Usage:
    python3 tools/nofloat.py <file>

Three calls are the whole of libm here, and they turn out to be two different
questions.

**`ceil()` and `floor()`** appear once, in the fuzzy matcher, as the two halves
of rounding half away from zero:

    (fzy_score < 0) ? (int)ceil(fzy_score * SCORE_SCALE - 0.5)
                    : (int)floor(fzy_score * SCORE_SCALE + 0.5)

C's double-to-int conversion truncates **toward zero**, which is `ceil` for a
negative value and `floor` for a positive one -- so biasing by half in the sign's
own direction and then converting gives the same answer for every input, and the
two arms collapse into one expression.  `tools/nolibm_check.c` sweeps a million
values through both forms and requires them to agree.

**`log10()`** is not translated, because it cannot be.  It appears once, as
`max_prec -= (size_t)log10(abs_f)`, and the obvious integer equivalent --
dividing by ten until the value drops below ten -- **is not the same function**:
just below a power of ten, `log10()` returns a double that rounds up to the
integer, so `(size_t)log10(99.999999999999986)` is 2 where counting digits gives
1.  The equivalence check found 79 such values in a million and that is what
turned this phase from a translation into a removal.

So the whole floating-point branch of `vim_vsnprintf()` goes instead, and the
justification is that **nothing can reach it**: there is not one `%f`, `%F`,
`%e`, `%E`, `%g` or `%G` conversion in any format string in the file, and the
single `vim_snprintf()` call whose format is not a literal takes a local
`char *fmt` that is one of two constants, `"%*ld "` and `"%-*ld "`.  Without
`+eval` there is no `printf()` to supply one at run time either.

That removes the conversion case (137 lines), `TYPE_FLOAT` and its three arms,
`infinity_str()`, and the six labels in the argument walker -- and with them
`log10`, `isinf` and `isnan`.

`<math.h>` STAYS: `INFINITY` is the fuzzy matcher's score sentinel, in thirteen
places.  Under musl libm is part of libc, so the link line does not change
either -- what changes is that `nm -u` stops naming a floating-point function.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cutil

ROUND = ('''                score = (fzy_score ==  INFINITY ) ? INT_MAX
                    : (int)(fzy_score * SCORE_SCALE + ((fzy_score < 0) ? -0.5 : 0.5));''')

FLOAT_LABELS = ("            case 'f':\n            case 'F':\n"
                "            case 'e':\n            case 'E':\n"
                "            case 'g':\n            case 'G':\n")


# A printf conversion: % then flags, width, precision, then the letter.
FLOAT_CONV = re.compile(r'%[-+ #0\']*[0-9*]*(?:\.[0-9*]*)?[fFeEgG]')
# A C string literal, escapes included.
LITERAL = re.compile(r'"(?:[^"\\\n]|\\.)*"')
# Terminfo capability strings use % as an operator language of their own --
# %p1 pushes a parameter, %{1} a constant, %? %t %e %; are its conditional.
# `\033[?1006;1000%?%p1%{1}%=%th%el%;` is not a printf format and its %e is an
# `else`.  Raw text is worse still: `indent % get_sw_value(curbuf)` is C.
TERMINFO = re.compile(r'%[p{?;]|%t[^a-zA-Z]')


def check_no_float_formats(text):
    """Refuse to cut unless nothing can reach the branch being cut."""
    bad = []
    for m in LITERAL.finditer(text):
        lit = m.group(0)
        if TERMINFO.search(lit):
            continue
        if FLOAT_CONV.search(lit):
            line = text.count('\n', 0, m.start()) + 1
            bad.append('%d: %s' % (line, lit[:70]))
    if bad:
        sys.exit('nofloat: %d string literals carry a float conversion, so the '
                 '%%f branch IS reachable and must not be removed:\n    %s'
                 % (len(bad), '\n    '.join(bad[:5])))
    # SCANNING EVERY LITERAL IS THE COMPLETE CHECK, and that is worth saying
    # because twelve call sites pass a format that is not a literal.  None of
    # them CONSTRUCTS one: smsg() and semsg() forward the format parameter they
    # were given, vim_snprintf() forwards to vim_vsnprintf(), and the three
    # remaining locals (`msg`, `fmt`) are assigned from literals a few lines
    # above.  So every format that can reach the branch originates as a literal
    # in this file, and every literal in this file has just been read.
    loose = len(re.findall(
        r'vim_v?snprintf[_a-z]*\([^,]*,[^,]*, *[A-Za-z_][\w>.\-]*[,)]', text))
    print('  nofloat      no float conversion in any of %d string literals; the '
          '%d forwarded formats all originate in one'
          % (len(LITERAL.findall(text)), loose))


def cut(text, pattern, what, count=1, flags=re.M):
    text, n = re.subn(pattern, '', text, count=count, flags=flags)
    if n != count:
        sys.exit('nofloat: %s -- expected %d, matched %d' % (what, count, n))
    return text


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    text = path.read_text(errors='surrogateescape')

    check_no_float_formats(text)

    # --- the fuzzy matcher's rounding --------------------------------------
    old = ('''                score = (fzy_score ==  INFINITY ) ? INT_MAX\n'''
           '''                    : (fzy_score < 0) ? (int)ceil(fzy_score * SCORE_SCALE - 0.5)\n'''
           '''                    : (int)floor(fzy_score * SCORE_SCALE + 0.5);''')
    if old not in text:
        sys.exit("nofloat: the fuzzy matcher's rounding is not where this expects")
    text = text.replace(old, ROUND, 1)
    print('  nofloat      ceil and floor: a conversion truncates toward zero, '
          'which is both of them')

    # --- vim_vsnprintf's float conversion, which nothing can reach ----------
    blanked = cutil.blank(text)
    k = text.index(FLOAT_LABELS + '                {\n')
    o = blanked.index('{', k + len(FLOAT_LABELS))
    c = cutil.match(text, o, blanked)
    if 'log10' not in text[k:c]:
        sys.exit('nofloat: the float conversion case is not where this expects')
    end = text.index('\n', c) + 1
    if text[end:end + 1] == '\n':
        end += 1
    print('  nofloat      the %%f conversion, %d lines nothing can reach'
          % text.count('\n', k, end))
    text = text[:k] + text[end:]

    # The three tables that describe an argument's type.
    text = cut(text,
               r"^    case 'f':\n    case 'F':\n    case 'e':\n    case 'E':\n"
               r"    case 'g':\n    case 'G':\n        return TYPE_FLOAT;\n\n?",
               "format_typeof's float arm")
    text = cut(text,
               r"^[ \t]*case 'f':\n[ \t]*case 'F':\n[ \t]*case 'e':\n"
               r"[ \t]*case 'E':\n[ \t]*case 'g':\n[ \t]*case 'G':\n",
               "the argument walker's six labels")
    text = cut(text,
               r'^[ \t]*case TYPE_FLOAT:\n[ \t]*return typename_float;\n',
               "format_typename's float arm")
    text = cut(text,
               r'^[ \t]*case TYPE_FLOAT:\n[ \t]*va_arg\(\*ap, double\);\n[ \t]*break;\n\n?',
               "the va_arg walker's float arm")
    # TYPE_FLOAT is the LAST enumerator, so removing it renumbers nothing --
    # checked, because several enums in this file index a parallel table.
    text, n = re.subn(r',\n    TYPE_FLOAT\n\};', '\n};', text, count=1)
    if n != 1:
        sys.exit('nofloat: TYPE_FLOAT is not the last enumerator any more')
    print('  nofloat      TYPE_FLOAT and its three arms')

    path.write_text(text, errors='surrogateescape')
    n = len(re.findall(r'\b(?:ceil|floor|log10)\s*\(', text))
    print('  nofloat      %d libm calls left' % n)


if __name__ == '__main__':
    main()
