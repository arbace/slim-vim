#!/bin/sh
# Zero phase 22 -- the variadic collapse: the seven wrappers that walk a va_list are
# expanded at their 129 call sites.  See ZERO-PLAN.md 4c and ZERO-GOAL.md.
#
# Usage: pipes/zero22-edit.sh <work-dir> <state-dir>     (run from the repository root)
#
# ZERO-PLAN.md 4c settled the variadic question on 2026-09-18: the formatter goes to the
# host rather than `__builtin_va_list` going into `editor.c`.  It also said the move
# splits in two and that ONLY THE SECOND NEEDS TWO FILES.  This is the first: everything
# that can be done about `va_start` inside one translation unit, done here, where the
# declared delta can be nothing at all and a byte-identical recording can say so.
#
# WHAT IT DOES.  C cannot forward `...` -- which is why `vsnprintf` exists beside
# `snprintf` -- so a wrapper that takes `...`, opens a `va_list` and hands it to
# `vim_vsnprintf` cannot survive a split unless the formatter goes with it.  There are
# eight such functions.  Seven of them are wrappers over the eighth, and every one of
# their call sites is rewritten here into `vim_snprintf(...)` plus the tail the wrapper
# ran afterwards.  `va_start` goes from EIGHT functions to ONE.
#
# THE PHASE'S WHOLE PRODUCT IS THAT `va_start` APPEARS ONCE.  It frees no libc symbol,
# removes no Ex command, removes no option and changes no message -- and the binary gets
# BIGGER, because 129 call sites now carry a format call and a tail call where they
# carried one call, which at -O0 is the expected sign.  `nm -u` is required to be THE
# SAME SET both ways, asserted as a `comm` that is empty in both directions rather than
# as a count: a reader meeting a 129-site phase expects a symbol to fall, and none can.
# A PURE RESTRUCTURE INSIDE ONE TRANSLATION UNIT FREES NOTHING.  `vim_vsnprintf_typval`
# still does every conversion, in the same file, and `<stdarg.h>`'s three names are
# macros and a compiler builtin type, which contribute no symbol at all.  The symbols
# and the header go when `vim_snprintf`, `vim_vsnprintf`, `vim_vsnprintf_typval` and
# `skip_to_arg` LEAVE THE FILE, and that is the split.  What this phase moves is not
# code across a boundary but the POSSIBILITY of drawing one: eight functions calling
# `va_start` cannot be split, one can.
#
# ------------------------------------------------------------------------------------
# THE INVENTORY -- 129 SITES, AND THE COUNT IS THE PHASE'S FIRST ASSERTION
#
#   wrapper                 mentions  protos  own def  CALL SITES
#   smsg                          12       1        1          10
#   smsg_attr                      4       1        1           2
#   smsg_attr_keep                 2       0        1           1
#   semsg                         96       1        1          94
#   siemsg                        12       1        1          10
#   vim_snprintf_add               3       1        1           1
#   vim_snprintf_safelen          13       1        1          11
#                                                             129
#
# `vim_snprintf`'s own 73 mentions are NOT touched: it is the survivor, the one function
# left calling `va_start`, and its rename to `musl_snprintf` belongs to the split.
#
# ------------------------------------------------------------------------------------
# THE TAILS ALREADY EXIST, WHICH IS WHAT MAKES THIS SMALL
#
# Read each wrapper beside its non-variadic twin and the wrapper is the twin with a
# format in front of it:
#
#   semsg(s, ...)                        emsg(s)
#     if (emsg_not_now()) return TRUE;     if (emsg_not_now()) return TRUE;
#     if (IObuff == NULL) return emsg_core(s);
#     format into IObuff
#     return emsg_core((char *)IObuff);    return emsg_core(s);
#
# `semsg`'s tail IS `emsg()`.  `siemsg`'s IS `iemsg()`.  `smsg`'s is `msg()`,
# `smsg_attr`'s `msg_attr()`, `smsg_attr_keep`'s `msg_attr_keep(..., TRUE)`.  All five
# already exist and all five are already called from elsewhere, so THIS PHASE WRITES NO
# MESSAGE LOGIC AT ALL.  What is left over is the two guards, and those become helpers.
#
# THE SIZE-ZERO TRICK IS WHAT MAKES THE EXPANSION EXACTLY FAITHFUL, and it was measured
# rather than assumed.  `vim_vsnprintf_typval` guards every write with
# `if (str_l < str_m)` and terminates with `if (str_m > 0)`, so `vim_snprintf(buf, 0,
# ...)` writes nothing and does not fault -- measured with a build whose first act is
# `vim_snprintf(canary, 0, "%s %d %ld %c %x", ...)`, `vim_snprintf(NULL, 0, ...)` and
# `vim_snprintf(NULL, 0, "%s", (char *)NULL)`: all eight canary bytes untouched, no
# fault on the NULL destination.  So a helper returning 0 reproduces BOTH of the
# wrapper's guards -- `emsg_off > 0` and `IObuff == NULL` -- with no conditional at the
# site.  That is why there are five helpers and not an `if`/`else` written out 117
# times.
#
# THE FIVE HELPERS, against SEVEN deleted definitions: two fewer, 1,758 -> 1,756.
#
#   iobuff_room()        0 if IObuff is NULL, else IOSIZE
#   emsg_iobuff_room()   0 if IObuff is NULL OR emsg_not_now(), else IOSIZE
#   iobuff_or(s)         IObuff, or s when IObuff is NULL -- what the wrapper handed
#                        emsg_core() in that arm
#   safelen_result()     vim_snprintf_safelen()'s arithmetic, lifted out unchanged
#   append_room()        vim_snprintf_add()'s, likewise
#
# Trace `semsg`'s three cases against the original and nothing is lost.  `emsg_off > 0`:
# room 0, nothing written, `emsg()` returns TRUE having consulted `emsg_not_now()`
# itself.  `IObuff == NULL`: room 0, nothing written, `iobuff_or` hands `emsg()` the
# unformatted format, exactly as the wrapper handed it to `emsg_core`.  Otherwise:
# formatted, and `emsg()` calls `emsg_core((char *)IObuff)`.  `siemsg` against `iemsg`
# is the same three cases.
#
# TWO MICRO-DIVERGENCES, STATED RATHER THAN HIDDEN.  (i) `vim_snprintf` is CALLED in the
# two suppressed cases where the wrapper called nothing; with `str_m == 0` it writes
# nothing but does run `parse_fmt_types`, which mallocs and frees an `ap_types` array.
# (ii) `vim_snprintf_safelen`'s `str_m == 0` early return now happens AFTER the
# formatter has been entered rather than before, with the same result.  Neither is
# observable -- 263 probes and two full recordings say so -- and both are the price of
# not putting a conditional at 129 sites.
#
# THE `emsg_not_now()` HALF OF `emsg_iobuff_room()` IS KEPT ALTHOUGH IT IS MEASURED
# UNOBSERVABLE.  A build of this phase's own output with that half of the guard removed
# moves 0 of 263 probes and 0 recording files: with `emsg_off > 0` the formatter would
# write into `IObuff`, and nothing anywhere reads `IObuff` before the next thing writes
# it.  It is kept because the phase claims THE SAME COMPUTATION and not merely the same
# output, and a phase whose declaration is "nothing at all" should not knowingly compute
# something new.  The user's decision, and it is recorded here rather than dropped
# quietly.
#
# `safelen_result`'s CLAMP IS UNTESTABLE BY ANYTHING AVAILABLE, and that is said plainly
# rather than papered over with a probe that cannot fail.  A build with
# `return ((size_t)str_l >= str_m) ? str_m - 1 : (size_t)str_l;` reduced to
# `return (size_t)str_l;` moves 0 of 263 probes and 0 recording files -- the clamp never
# fires in anything this pipeline can drive, because reaching it means overflowing
# `fileinfo`'s 1,025-byte line.  The clamp is copied verbatim from the wrapper, so the
# risk is nil; the evidence simply does not reach it, and the check says so instead of
# claiming otherwise.
#
# ------------------------------------------------------------------------------------
# THE THING A READER EXPECTS TO BE A PROBLEM AND IS NOT: NON-LITERAL FORMATS
#
# MEASURED, and it is the opposite of the expected answer.  EVERY ONE of `semsg`'s 94
# formats is `_(e_name)` or `(const char *)(_(e_name))`, where `e_name` is a
# `static char e_name[] = "E123: ...";` array -- whim's constant fold turned upstream's
# string macros into arrays, so THERE IS NO LITERAL AT A `semsg` SITE ANYWHERE IN THE
# FILE.  It changes nothing, because the expansion does not need to know the format: it
# copies the format EXPRESSION verbatim into `vim_snprintf`'s third argument, and
# `vim_snprintf` is itself variadic and reads the format at run time.
#
# The two things that could have gone wrong were both measured.
#
#   -Wformat COVERAGE DOES NOT DISAPPEAR, IT MOVES.  The wrappers carry
#   `__attribute__((format(printf, 1, 2)))` / `(2, 3)` / `(3, 4)`, and `vim_snprintf`
#   carries `format(printf, 3, 4)` -- and every expansion puts the format expression at
#   `vim_snprintf`'s third parameter, so gcc checks exactly what it checked before.
#   `-Wformat=2` gives 115 `-Wformat-nonliteral` warnings in 53 functions before this
#   phase and THE IDENTICAL 115 IN THE IDENTICAL 53 after it.  `_()` and `NGETTEXT()`
#   are `static inline __attribute__((format_arg(1)))`, so gcc sees through them either
#   side.  That equality is the check a mis-expanded argument list would fail and the
#   build would not, and pipes/zero22-check.sh makes it.
#
#   DOUBLE EVALUATION OF THE FORMAT EXPRESSION.  The expansion mentions the format twice
#   -- once in `vim_snprintf`, once in the tail's `iobuff_or(F)`.  MEASURED over all 129
#   sites: every format expression is side-effect-free.  118 are `_(e_name)` / a bare
#   `e_name` / a literal, 8 are `NGETTEXT(a, b, n)` (a pure inline `return`), 2 are a
#   `? :` over two `_()`s, 1 is a parameter.  None contains an assignment, an increment,
#   or a call to anything but `_` and `NGETTEXT`.
#
# ------------------------------------------------------------------------------------
# THE TRAPS, ALL MEASURED, AND EACH ONE CAN PRODUCE A WRONG PHASE SILENTLY
#
#   1. `emsg(` IS A SUBSTRING OF `semsg(` AND OF `siemsg(`.  A textual replace of
#      `emsg(` corrupts 106 lines.  Every search here is by word boundary --
#      `(?<![A-Za-z0-9_])NAME(?![A-Za-z0-9_])\s*\(` -- and the same applies to `smsg` as
#      a prefix of `smsg_attr` and `smsg_attr_keep`, and `vim_snprintf` of
#      `vim_snprintf_add` and `vim_snprintf_safelen`.  `grep -c vim_snprintf` counts all
#      three; `grep -ow` counts one.
#   2. SIX SITE TEXTS ARE DUPLICATED ACROSS 13 SITES, so an exact-text anchor with
#      `count == 1` FAILS ON A CORRECT PHASE.  The remedy is not to count anchors: THIS
#      PHASE IS A RULE.  It finds every call by word boundary, splits its arguments by
#      balanced parens with string and character literals honoured, and rewrites.  The
#      residue is 0 and the program does not care what upstream renamed.
#   3. THE SITES COME IN THREE SHAPES AND AN EDIT THAT EMITS TWO STATEMENTS
#      UNCONDITIONALLY GETS TWO OF THEM WRONG.  92 are a plain statement alone on its
#      line, and become two lines at the same indentation.  7 are a WHOLE BLOCK ON ONE
#      LINE -- `{   semsg(...);         goto error;     }   ;` inside `parse_fmt_types`
#      -- where two lines would put a statement in front of the closing brace, so the
#      expansion goes inline on the same line.  30 are in VALUE POSITION: 18 `semsg`es
#      inside `return (..., rc_did_emsg = TRUE, (void *)NULL) ;` comma expressions in
#      the regexp engine, all eleven `vim_snprintf_safelen`s (whose value is consumed at
#      every site, five of them `+=`), and `vim_snprintf_add`'s one.  A statement is
#      told from an operand by the character after the closing paren.  THE COMMA SHAPE
#      ALREADY EXISTS IN THE FILE -- `return (iemsg((e_internal_error_in_regexp)),
#      rc_did_emsg = TRUE, (void *)NULL) ;` -- so the expansion invents no idiom.
#   4. ONE NEW PROTOTYPE IS REQUIRED and it is not one of the five helpers'.
#      `emsg_iobuff_room()` calls `emsg_not_now()`, which is defined 130 lines below the
#      place the helpers go and had no forward declaration.  Without
#      `static int emsg_not_now(void);` the build fails with *"static declaration of
#      'emsg_not_now' follows non-static declaration"* -- loud, not silent -- and
#      `deadprotos.py` does not take it away once added.
#   5. `smsg_attr_keep` HAS NO PROTOTYPE AND `vim_snprintf` HAS TWO.  A phase that
#      deletes "the prototype and the definition" for each of seven names fails on the
#      first and leaves one behind on the second.  Measured: 1, 1, 0, 1, 1, 1, 1.
#   6. NO SITE PASSES ZERO VARIADIC ARGUMENTS, so the question "does
#      `vim_snprintf(buf, n, s)` differ from a plain copy when there is nothing to
#      substitute" never arises.  It would if a future edit added such a site, because
#      `vim_snprintf` interprets `%` in the format and a copy does not.
#
# `vim_snprintf`'s SECOND PROTOTYPE GOES WITH THE WRAPPERS.  Line 35776,
# `static int vim_snprintf(char *str, size_t str_m, const char *fmt, ...);`, exists only
# because the five message wrappers are defined above `vim_snprintf` and needed to call
# it.  All five are leaving, the declaration block at the top already has the same
# prototype, and the sweep does not take a redundant one -- so it is removed here by
# name.  It is this phase's own residue and not a tidy smuggled in.
#
# NO `need 22 swept`, AND IT WAS CHECKED RATHER THAN ASSUMED: the edit finds its sites
# by word boundary and balanced parens over the whole file, not by counted anchors, so
# it gives the same answer on swept and unswept text.  The only counts it asserts are
# the seven wrappers' whole-file mention totals, which no sweep moves.
set -eu

work=${1:?usage: zero22-edit.sh <work-dir> <state-dir>}
state=${2:?usage: zero22-edit.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"

# The flags are read out of the boundary's makefile rather than written here a second
# time: zero's compile line is the boundary's (ZERO-GOAL.md rule 8).
cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")
cp "$f" "$state/old.c"
# shellcheck disable=SC2086
( cd "$state" && gcc $cflags $ldflags -o old old.c ) &
pid_old=$!

python3 - "$f" <<'PY'
import re
import sys

TAG = 'format'
path = sys.argv[1]
t = open(path, errors='surrogateescape').read()


def die(msg):
    sys.exit('  %-12s %s' % (TAG, msg))


def say(what):
    print('  %-12s %s' % (TAG, what))


def mentions(text, name):
    return len(re.findall(r'\b%s\b' % name, text))


def sub(old, new, n=1, tag=''):
    global t
    c = t.count(old)
    if c != n:
        die('%s: `%s` occurs %d times, expected %d'
            % (tag, old.strip().split('\n')[0][:70], c, n))
    t = t.replace(old, new)


def delfunc(sigline, tag=''):
    """Delete a whole definition by brace matching from its name line."""
    global t
    if t.count(sigline) != 1:
        die('%s: the definition line `%s` occurs %d times, expected 1'
            % (tag, sigline.strip()[:60], t.count(sigline)))
    i = t.index(sigline)
    k = t.index('{', i)
    d = 0
    while True:
        if t[k] == '{':
            d += 1
        elif t[k] == '}':
            d -= 1
            if d == 0:
                break
        k += 1
    st = t.rindex('\n', 0, t.rindex('\n', 0, i)) + 1
    t = t[:st] + t[t.index('\n', k) + 1:]


lines_before = len(t.split('\n'))

# ---- 0. this is the file the phase was written against -------------------------------
# The seven whole-file mention totals, which no sweep moves and which every count below
# is derived from.  `vim_snprintf`'s OWN count is deliberately NOT asserted here: phase
# 21 formats its host message with it, so the number before the edit is the message
# layer's business and not this phase's.  It is asserted afterwards, as this
# transformer's own arithmetic.
WRAP = (('smsg', 12), ('smsg_attr', 4), ('smsg_attr_keep', 2), ('semsg', 96),
        ('siemsg', 12), ('vim_snprintf_add', 3), ('vim_snprintf_safelen', 13))
for name, want in WRAP:
    if mentions(t, name) != want:
        die('the input has %d mentions of `%s`, expected %d -- this is not the tree '
            'this phase was written against' % (mentions(t, name), name, want))
for name, want in (('va_start', 8), ('va_list', 15), ('va_end', 10)):
    if mentions(t, name) != want:
        die('the input has %d mentions of `%s`, expected %d' % (mentions(t, name), name, want))
vs_before = mentions(t, 'vim_snprintf')
say('the input is r21: eight functions call `va_start`, seven of them wrappers over the '
    'eighth, and their mention totals are 12 4 2 96 12 3 13')

# ---- 1. the seven definitions --------------------------------------------------------
for sig in ('smsg(const char *s, ...)', 'smsg_attr(int attr, const char *s, ...)',
            'smsg_attr_keep(int attr, const char *s, ...)', 'semsg(const char *s, ...)',
            'siemsg(const char *s, ...)',
            'vim_snprintf_add(char *str, size_t str_m, const char *fmt, ...)',
            'vim_snprintf_safelen(char *str, size_t str_m, const char *fmt, ...)'):
    delfunc('\n' + sig + '\n', 'D')

# ---- 2. the prototypes ---------------------------------------------------------------
# Six, not seven: `smsg_attr_keep` never had one.  And `vim_snprintf`'s SECOND
# prototype, which existed only because the wrappers sit above its definition.
sub('static int vim_snprintf(char *str, size_t str_m, const char *fmt, ...);\n\n', '',
    1, 'P0')
for p in (
        'static int smsg(const char *, ...)  __attribute__((cold))   '
        '__attribute__((format(printf, 1, 2))) ;\n',
        'static int smsg_attr(int, const char *, ...)  '
        '__attribute__((format(printf, 2, 3))) ;\n',
        'static int semsg(const char *, ...)  __attribute__((cold))   '
        '__attribute__((format(printf, 1, 2))) ;\n',
        'static void siemsg(const char *, ...)  __attribute__((cold))   '
        '__attribute__((format(printf, 1, 2))) ;\n',
        'static int vim_snprintf_add(char *, size_t, const char *, ...)  '
        '__attribute__((format(printf, 3, 4))) ;\n',
        'static size_t vim_snprintf_safelen(char *, size_t, const char *, ...)  '
        '__attribute__((format(printf, 3, 4))) ;\n'):
    sub(p, '', 1, 'P')
# The five helpers are called from line 4307 onwards and defined at 35777, so they need
# declarations; `emsg_not_now` needs one because emsg_iobuff_room() is above it.
sub('static int vim_snprintf(char *, size_t, const char *, ...)  '
    '__attribute__((format(printf, 3, 4))) ;\n',
    'static int vim_snprintf(char *, size_t, const char *, ...)  '
    '__attribute__((format(printf, 3, 4))) ;\n'
    'static int emsg_not_now(void);\n'
    'static size_t iobuff_room(void);\n'
    'static size_t emsg_iobuff_room(void);\n'
    'static char *iobuff_or(const char *s);\n'
    'static size_t safelen_result(char *str, size_t str_m, int str_l);\n'
    'static size_t append_room(char *str, size_t str_m);\n', 1, 'P1')

# ---- 3. the five helpers, where the message wrappers were ----------------------------
HELPERS = '''    static size_t
iobuff_room(void)
{
    if (IObuff == NULL)
    {
        return 0;
    }
    return  (1024+1) ;
}

    static size_t
emsg_iobuff_room(void)
{
    if (IObuff == NULL || emsg_not_now())
    {
        return 0;
    }
    return  (1024+1) ;
}

    static char *
iobuff_or(const char *s)
{
    if (IObuff == NULL)
    {
        return (char *)s;
    }
    return (char *)IObuff;
}

    static size_t
safelen_result(char *str, size_t str_m, int str_l)
{
    if (str_m == 0)
    {
        return 0;
    }
    if (str_l < 0)
    {
        *str = NUL;
        return 0;
    }
    return ((size_t)str_l >= str_m) ? str_m - 1 : (size_t)str_l;
}

    static size_t
append_room(char *str, size_t str_m)
{
    size_t      len =  musl_strlen((char *)(str)) ;

    if (str_m <= len)
    {
        return 0;
    }
    return str_m - len;
}

'''
ANCHOR = 'static int      last_sourcing_lnum = 0;\n'
sub(ANCHOR, HELPERS + ANCHOR, 1, 'H')

# ---- 4. the 129 call sites -----------------------------------------------------------
NAMES = [n for n, _ in WRAP]
CALL = re.compile(r'(?<![A-Za-z0-9_])(%s)(?![A-Za-z0-9_])\s*\(' % '|'.join(NAMES))


def close_paren(s, i):
    """i indexes an opening paren; returns the index of its match.

    String and character literals are skipped, because a format holds `(` and `)`
    and a `'('` would otherwise end the scan in the wrong place.
    """
    d = 0
    while i < len(s):
        c = s[i]
        if c == '"' or c == "'":
            q = c
            i += 1
            while s[i] != q:
                i += 2 if s[i] == '\\' else 1
        elif c == '(':
            d += 1
        elif c == ')':
            d -= 1
            if d == 0:
                return i
        i += 1
    die('unbalanced parentheses')


def split_args(s):
    """Top-level commas only: parens, brackets, braces and literals are opaque."""
    args, d, cur, i = [], 0, [], 0
    while i < len(s):
        c = s[i]
        if c == '"' or c == "'":
            q = c
            j = i + 1
            while s[j] != q:
                j += 2 if s[j] == '\\' else 1
            cur.append(s[i:j + 1])
            i = j + 1
            continue
        if c in '([{':
            d += 1
        elif c in ')]}':
            d -= 1
        if c == ',' and d == 0:
            args.append(''.join(cur).strip())
            cur = []
        else:
            cur.append(c)
        i += 1
    args.append(''.join(cur).strip())
    return args


ROOM = {'smsg': 'iobuff_room()', 'smsg_attr': 'iobuff_room()',
        'smsg_attr_keep': 'iobuff_room()', 'semsg': 'emsg_iobuff_room()',
        'siemsg': 'emsg_iobuff_room()'}
NLEAD = {'smsg': 0, 'smsg_attr': 1, 'smsg_attr_keep': 1, 'semsg': 0, 'siemsg': 0}
shapes = {'plain': 0, 'inline': 0, 'value': 0}
counts = dict((n, 0) for n in NAMES)

pos = 0
while True:
    m = CALL.search(t, pos)
    if m is None:
        break
    name = m.group(1)
    op = m.end() - 1
    cp = close_paren(t, op)
    args = split_args(t[op + 1:cp])
    counts[name] += 1

    if name == 'vim_snprintf_safelen':
        # ALWAYS AN EXPRESSION: the value is consumed at every one of the eleven sites,
        # five of them `+=`, so two statements cannot say this.
        if len(args) < 4:
            die('vim_snprintf_safelen with %d arguments' % len(args))
        rep = ('safelen_result(%s, %s, vim_snprintf(%s))'
               % (args[0], args[1], ', '.join(args)))
        shapes['value'] += 1
    elif name == 'vim_snprintf_add':
        if len(args) < 4:
            die('vim_snprintf_add with %d arguments' % len(args))
        rep = ('vim_snprintf(%s +  musl_strlen((char *)(%s)) , append_room(%s, %s), %s)'
               % (args[0], args[0], args[0], args[1], ', '.join(args[2:])))
        shapes['value'] += 1
    else:
        nl = NLEAD[name]
        if len(args) < nl + 2:
            die('`%s` with %d arguments -- no site passes zero variadic arguments'
                % (name, len(args)))
        fmt = args[nl]
        a = ('vim_snprintf((char *)IObuff, %s, %s)'
             % (ROOM[name], ', '.join([fmt] + args[nl + 1:])))
        if name == 'smsg':
            b = 'msg(iobuff_or(%s))' % fmt
        elif name == 'smsg_attr':
            b = 'msg_attr(iobuff_or(%s), %s)' % (fmt, args[0])
        elif name == 'smsg_attr_keep':
            b = 'msg_attr_keep(iobuff_or(%s), %s, TRUE)' % (fmt, args[0])
        elif name == 'semsg':
            b = 'emsg(iobuff_or(%s))' % fmt
        else:
            b = 'iemsg(iobuff_or(%s))' % fmt
        if t[cp + 1:cp + 2] == ';':
            bol = t.rindex('\n', 0, m.start()) + 1
            eol = t.index('\n', cp)
            if t[bol:m.start()].strip() == '' and t[cp + 2:eol].strip() == '':
                rep = a + ';\n' + t[bol:m.start()] + b + ';'
                shapes['plain'] += 1
            else:
                # A WHOLE BLOCK ON ONE LINE.  Two lines here would leave a statement in
                # front of the closing brace.
                rep = a + '; ' + b + ';'
                shapes['inline'] += 1
            t = t[:m.start()] + rep + t[cp + 2:]
            pos = m.start() + len(rep)
            continue
        # VALUE POSITION: the comma shape the regexp engine already uses.
        rep = '(%s, %s)' % (a, b)
        shapes['value'] += 1
    t = t[:m.start()] + rep + t[cp + 1:]
    pos = m.start() + len(rep)

total = sum(counts.values())
if total != 129:
    die('%d call sites, expected 129 -- %s'
        % (total, ' '.join('%s %d' % (n, counts[n]) for n in NAMES)))
for name, _ in WRAP:
    if mentions(t, name):
        die('`%s` still has %d mentions after the expansion' % (name, mentions(t, name)))
for name, want in (('va_start', 1), ('va_list', 8), ('va_end', 3)):
    if mentions(t, name) != want:
        die('`%s` has %d mentions after the expansion, expected %d'
            % (name, mentions(t, name), want))
if mentions(t, 'vim_snprintf') != vs_before - 1 + total:
    die('`vim_snprintf` went from %d to %d, expected %d -- one prototype away and one '
        'mention at each of the %d sites'
        % (vs_before, mentions(t, 'vim_snprintf'), vs_before - 1 + total, total))

say('129 call sites expanded: %s'
    % ', '.join('%s %d' % (n, counts[n]) for n in NAMES))
say('%d plain statements (two lines), %d whole blocks on one line (inline), %d in value '
    'position -- the 18 `return (semsg(...), rc_did_emsg = TRUE, NULL)` comma '
    'expressions, the 11 safelens whose value is consumed, and the one append'
    % (shapes['plain'], shapes['inline'], shapes['value']))
say('`va_start` 8 -> 1, `va_list` 15 -> 8, `va_end` 10 -> 3; `vim_snprintf` %d -> %d; '
    'seven definitions and six prototypes gone, five helpers and six declarations in; '
    'lines %d -> %d'
    % (vs_before, mentions(t, 'vim_snprintf'), lines_before, len(t.split('\n'))))
open(path, 'w', errors='surrogateescape').write(t)
PY

wait $pid_old || { echo "  format       the input source did not build"; exit 1; }
echo "  format       the input binary is built and kept, and the check needs it: every"
echo "               number below is a PAIR, and the recording this phase declares"
echo "               nothing against is a recording of both"
