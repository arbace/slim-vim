#!/usr/bin/env python3
"""The host's vocabulary is the host's: every mention of it is inside the host block.

Usage: python3 tools/zhostonly.py <file.c> [--quiet]

Zero phase 20 moves the signal handlers, the window size, the terminal mode, the
delay and the wait out of the editor and into a block of `host_*`/`musl_*` functions
at the bottom of the same file -- the launcher region zero phase 18 created.  Inside
ONE translation unit that frees no `nm -u` symbol: a symbol leaves when its last
CALLER leaves the file, and that is the split.  So the phase's central claim is not a
count, it is a structural fact -- *the core names none of this* -- and without this
tool the strongest form of it available is `sigaction` at 2 mentions, which says
nothing about WHERE.

This is that claim as an assertion, and it is the check that survives into the file
split: when `editor.c` and `zero-vim.c` become two files, the host block becomes the
second file and this tool becomes `grep` over the first.

WHAT IT READS.  The file is split into function definitions by the shape every
definition in this tree has -- a name at column 0 followed by `{` at column 0 and
closed by `}` at column 0 -- plus a HOST REGION, the lines from the host block's first
declaration to the last brace of its last function.  Every occurrence of the
vocabulary below must be inside that region, or be one of the EXCEPTIONS, which are
named one by one with the reason and the exact count.  A new one fails.

WHAT IT IGNORES, and both are measured rather than assumed.  **String literals**: the
file contains `hash_remove(&buf_hashtab, hi, "close buffer")`, and a tool that read
that as a `close()` would report the buffer layer as filesystem code.  **Preprocessor
lines**: `#include <errno.h>` and `#include <sys/ioctl.h>` name two of the words, and
the twelve includes are the host's business in a file that is on its way to being
split.

IT IS PROVEN NOT TO PASS VACUOUSLY.  A pattern that stopped matching, or a host
region that failed to parse, would make the whole check succeed by finding nothing --
the same failure `tools/create_cmdidxs.py` and `tools/orphanopts.py` each carry a
floor against.  So the tool REQUIRES the host region to be found, to define every
function in HOST_FUNCS, and to contain at least one mention of each word in
HOST_MUST -- the six that are the whole point: the signal installer, the window size,
the terminal mode, the sleep, the wait and the stop.

IT IS ZERO-ONLY.  Nothing whim or slim runs names it (CLAUDE.md's rule for a shared
tool), so adding it re-keys zero's phases and nothing else.
"""
import re
import sys

# The words that belong to the host.  `read` and `write` are NOT here: the core's
# `mch_write` still writes to fd 1 and `fill_input_buf` still asks the host for bytes,
# which is ZERO-PLAN.md 4c's next step and not this phase's.
VOCAB = re.compile(
    r'\b(?:sigaction|sigemptyset|sigaddset|sigismember|sigprocmask|sighandler_T'
    r'|raise|kill|ioctl|TIOCGWINSZ|SIG_?[A-Z][A-Z0-9_]*'
    r'|tcgetattr|tcsetattr|nanosleep|select|isatty|close|dup'
    r'|FD_SET|FD_ZERO|FD_ISSET|fd_set|TCSANOW'
    r'|ICANON|ECHO|ISIG|ECHOE|IEXTEN|ICRNL|IXON|ONLCR|XTABS'
    r'|VMIN|VTIME|VERASE|VINTR|EINTR|errno)\b'
    r'|\bstruct[ \t]+(?:winsize|termios|timespec|timeval)\b')

HOST_BEGIN = 'static volatile sig_atomic_t host_winch_pending'
HOST_LAST = 'musl_suspend'

HOST_FUNCS = ('host_catch', 'host_on_winch', 'host_on_tstp', 'host_on_int',
              'host_tty_set',
              'musl_host_init', 'musl_get_winsize', 'musl_term_start',
              'musl_term_stop', 'musl_tty_keys', 'musl_delay',
              'musl_wait_for_input', 'musl_read_input', 'musl_suspend')

HOST_MUST = ('sigaction', 'ioctl', 'tcsetattr', 'nanosleep', 'select', 'kill')

# (function, word, count, why).  `<file scope>` is anything outside a definition.
# Every one of these is a place the CORE still says one of these words, and each is
# here because it was read and kept, not because the pattern was loosened.
EXCEPTIONS = (
    ('signal_info[]', 'SIGHUP', 1,
     'the deadly-signal table: the two signals whose NAME the editor reports.  The '
     'host installs the handler; the core still owns the message'),
    ('signal_info[]', 'SIGTERM', 1, 'the same row of the same table'),
    ('deathtrap', 'SIGHUP', 1,
     "deathtrap's own test for the two signals it may defer.  The core keeps this "
     'function on purpose: it is what restores the terminal and writes `Vim: Caught '
     'deadly signal` before the editor ends, and the host installs it rather than '
     'replacing it'),
    ('deathtrap', 'SIGTERM', 1, 'the same test'),
    ('vim_handle_signal', 'kill', 1,
     're-raising a deadly signal that arrived while the editor was not reading.  '
     'This is the ONLY core mention of any of these words that is not a message, and '
     'it is kept because deleting it would make a deadly signal act in the middle of '
     'a screen update -- a behaviour change no recording can see'),
    ('<file scope>', 'struct timeval', 2,
     "`elapsed_T`, the clock's, and not this phase's: zero-vim measures elapsed time "
     'with `gettimeofday`, which is somebody else\'s later phase'),
    ('elapsed', 'struct timeval', 2, 'the same clock, in the one function that reads it'),
)


def strip_strings(line):
    """Blank out string and character literals.  See the docstring."""
    out = []
    i = 0
    n = len(line)
    while i < n:
        c = line[i]
        if c in '"\'':
            q = c
            out.append(' ')
            i += 1
            while i < n:
                if line[i] == '\\':
                    i += 2
                    continue
                if line[i] == q:
                    break
                i += 1
            i += 1
            continue
        out.append(c)
        i += 1
    return ''.join(out)


def owners(lines):
    """For every line, the function definition that contains it, or None."""
    cur = None
    out = []
    for i, line in enumerate(lines):
        m = re.match(r'^([A-Za-z_]\w*)\s*\(', line)
        if m and i + 1 < len(lines) and lines[i + 1].startswith('{'):
            cur = m.group(1)
        out.append(cur)
        if line == '}':
            cur = None
    return out


def main(argv):
    path = argv[1]
    quiet = '--quiet' in argv
    lines = open(path, errors='surrogateescape').read().split('\n')
    own = owners(lines)
    fail = []

    begin = [i for i, l in enumerate(lines) if l.startswith(HOST_BEGIN)]
    if len(begin) != 1:
        sys.exit('zhostonly: the host block does not begin exactly once with %r -- '
                 'found %d.  A region this tool cannot find would make every check '
                 'below pass by finding nothing' % (HOST_BEGIN, len(begin)))
    last = [i for i, l in enumerate(lines) if l.startswith(HOST_LAST + '(')]
    if len(last) != 1:
        sys.exit('zhostonly: %s() is not defined exactly once, so the host region has '
                 'no end' % HOST_LAST)
    end = last[0]
    while end < len(lines) and lines[end] != '}':
        end += 1
    if end >= len(lines):
        sys.exit('zhostonly: %s() does not close at column 0' % HOST_LAST)

    inhost = set(range(begin[0], end + 1))
    defined = {own[i] for i in inhost if own[i]}
    missing = [f for f in HOST_FUNCS if f not in defined]
    if missing:
        fail.append('the host region does not define %s -- the region is %d lines and '
                    'this check is only as strong as what is in it'
                    % (' '.join(missing), len(inhost)))

    # Every hit, bucketed.
    hits = {}
    for n, raw in enumerate(lines):
        if raw.startswith('#'):
            continue
        for m in VOCAB.finditer(strip_strings(raw)):
            word = re.sub(r'[ \t]+', ' ', m.group(0))
            if n in inhost:
                hits.setdefault(('<host>', word), []).append(n + 1)
            else:
                who = own[n] or '<file scope>'
                if who == '<file scope>' and 'signal_info[]' in ''.join(
                        lines[max(0, n - 12):n + 1]):
                    who = 'signal_info[]'
                hits.setdefault((who, word), []).append(n + 1)

    for w in HOST_MUST:
        if ('<host>', w) not in hits:
            fail.append('the host region does not mention `%s` at all.  This tool '
                        'would then be asserting that the core does not say a word '
                        'nobody says' % w)

    want = {(f, w): c for f, w, c, _ in EXCEPTIONS}
    for (who, word), ls in sorted(hits.items()):
        if who == '<host>':
            continue
        n = len(ls)
        if want.get((who, word)) != n:
            fail.append('%s says `%s` %d time%s (line%s %s)%s'
                        % (who, word, n, '' if n == 1 else 's',
                           '' if n == 1 else 's',
                           ' '.join(str(x) for x in ls[:6]),
                           '' if (who, word) not in want else
                           ', where %d was expected' % want[(who, word)]))
    for (f, w), c in want.items():
        if len(hits.get((f, w), [])) != c:
            fail.append('the named exception `%s` in %s is gone or has moved -- it was '
                        '%d.  An exception that stops being true is a fact this tool '
                        'is meant to notice' % (w, f, c))

    if fail:
        for line in fail:
            print('  zhostonly    %s' % line)
        return 1
    if not quiet:
        n = sum(len(v) for (who, _), v in hits.items() if who == '<host>')
        words = sorted({w for (who, w) in hits if who == '<host>'})
        print('  zhostonly    %d mentions of %d host words, ALL of them inside the '
              '%d-line host block (%s)' % (n, len(words), len(inhost), ' '.join(words)))
        print('  %-12s and %d named exceptions in the core, every one of them the '
              'deadly-signal message or the clock: %s' %
              ('', len(EXCEPTIONS),
               ', '.join('%s:%s' % (f, w) for f, w, _, _ in EXCEPTIONS)))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
