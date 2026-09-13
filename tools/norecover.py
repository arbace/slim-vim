r"""There is nothing to recover.

Usage:
    python3 tools/norecover.py <file>

Phase 13 made the swap file memory-only: the block structure is still built,
still paged, still the thing every line of the buffer lives in, but it never
reaches a disk.  What it left behind is the other half of the feature -- the
code that reads someone else's swap file back, which is now code for reading a
file that this editor cannot have written.

  * `-r` and `-L` on the command line.  `-r` with no file listed what swap files
    it could find; `-r file` recovered one.  Both set `recoverymode`, which is
    the only thing that ever did, so the global folds to FALSE and its seven
    readers each collapse to the branch they were already taking -- three of
    them in `readfile()`, which had to know it was being called to fill a buffer
    from a swap file rather than from the file itself.
  * `ml_recover()` (559 lines), `recover_names()` (216) and `swapfile_info()`
    (103).
  * `mch_get_uname()`, and with it **`getpwuid`** -- the fifth of the five
    password-database symbols, and the one Phase 23 said would need a phase of
    its own.  `swapfile_info()` called it to say who owned a swap file.

`:recover` was pointed at `ex_ni` earlier and does not move: it already failed,
because it needed a swap file to read.

TIME, WHICH IS THE PART THAT IS A DECISION.  `swapfile_info()` was the only
caller of `get_ctime()`, so `vim_localtime()` is left with one user, `add_time()`
-- the timestamp in `:undolist` and in "1 change; before #3".  It is dropped
too, and the argument is not that it is unreachable but that it is wrong:
`localtime_r()` asks libc what the local zone is, and Phase 24 took away every
way this editor could be told.  Undo history does not survive the process
either, `:wundo` and `:rundo` being `ex_ni` since Phase 13 -- so every time
`add_time()` formats is within one session, and the relative form it already
used for anything under 100 seconds is the true one.  `strftime` and both format
strings go with it.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cutil

RELATIVE = '''    // How long ago, not when.  Phase 24 took away every way this editor could
    // be told what zone the clock is in, and undo history does not outlive the
    // process -- :wundo and :rundo are ex_ni -- so every time this formats is
    // within one session, which is exactly what "ago" measures.
    long seconds = (long)(vim_time() - tt);

    vim_snprintf((char *)buf, buflen, NGETTEXT("%ld second ago", "%ld seconds ago", seconds), seconds);'''


def dedent(body):
    return ''.join(l[4:] if l.startswith('    ') else l
                   for l in body.splitlines(keepends=True))


def _block(text, pattern, flags):
    """(start-of-line, open-brace, close-brace) for the `if` `pattern` matches."""
    blanked = cutil.blank(text)
    m = re.search(pattern, text, flags)
    if not m:
        sys.exit('norecover: no match for %r' % pattern)
    k = text.rfind('\n', 0, m.start()) + 1
    o = blanked.index('{', m.end())
    c = cutil.match(text, o, blanked)
    if c < 0:
        sys.exit('norecover: unbalanced block for %r' % pattern)
    return k, o, c


def unwrap_if(text, pattern, what, flags=re.M):
    """Keep the body of an `if` whose condition is now always true."""
    k, o, c = _block(text, pattern, flags)
    if re.match(r'[ \t]*\n[ \t]*else\b', text[c + 1:c + 40]):
        sys.exit('norecover: %s -- the block has an else' % what)
    body = dedent(text[text.index('\n', o) + 1:text.rfind('\n', 0, c) + 1])
    end = text.index('\n', c) + 1
    print('  norecover    %s, %d lines that always ran' % (what, text.count('\n', k, end)))
    return text[:k] + body + text[end:]


def keep_else(text, pattern, what, flags=re.M):
    """Keep the `else` body of an `if` whose condition is now always false."""
    k, o, c = _block(text, pattern, flags)
    m = re.match(r'[ \t]*\n[ \t]*else\n', text[c + 1:])
    if not m:
        sys.exit('norecover: %s -- no else to keep' % what)
    blanked = cutil.blank(text)
    o2 = blanked.index('{', c + 1 + m.end())
    c2 = cutil.match(text, o2, blanked)
    body = dedent(text[text.index('\n', o2) + 1:text.rfind('\n', 0, c2) + 1])
    end = text.index('\n', c2) + 1
    print('  norecover    %s, and the %d lines it guarded'
          % (what, text.count('\n', k, c) + 1))
    return text[:k] + body + text[end:]


def cut(text, pattern, what, count=1, flags=re.M):
    text, n = re.subn(pattern, '', text, count=count, flags=flags)
    if n != count:
        sys.exit('norecover: %s -- expected %d, matched %d' % (what, count, n))
    return text


def sub(text, pattern, repl, what, flags=re.M):
    text, n = re.subn(pattern, repl, text, count=1, flags=flags)
    if n != 1:
        sys.exit('norecover: %s is not where this expects' % what)
    return text


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    text = path.read_text(errors='surrogateescape')

    # --- the two flags that are the only thing that ever set recoverymode ---
    text = cut(text,
               r'[ \t]*case \'r\':\n[ \t]*case \'L\':\n'
               r'[ \t]*recoverymode = 1;\n[ \t]*break;\n\n?',
               '-r and -L in command_line_scan')
    print('  norecover    -r and -L, the only two things that set recoverymode')

    # --- the three functions ------------------------------------------------
    for name in ('swapfile_info', 'recover_names', 'ml_recover'):
        before = text.count('\n')
        text, ok = cutil.delete_definition(text, name)
        if not ok:
            sys.exit('norecover: %s is not defined at file scope' % name)
        print('  norecover    %s, %d lines' % (name, before - text.count('\n')))

    # --- recoverymode is FALSE, so each reader takes the branch it took -----
    # main(), before the screen is sized: -r with no file listed what it found.
    text = cutil.drop_if(
        text, r'^[ \t]*if \(recoverymode && params\.fname == NULL\)$', count=2, flags=re.M)
    print('  norecover    the two `-r with no file` arms of main and vim_main2')

    text = sub(text, r'if \(params\.edit_type == EDIT_STDIN && !recoverymode\)',
               'if (params.edit_type == EDIT_STDIN)', 'the stdin arm of vim_main2')
    print('  norecover    reading stdin stops asking whether this is a recovery')

    text = keep_else(text, r'^[ \t]*if \(recoverymode\)$',
                     'the recovery arm of create_windows')

    # readfile() had to know whether it was filling a buffer from a swap file
    # rather than from the file itself.  It never is.
    text = sub(text, r'if \(!recoverymode && !filtering && !\(flags & READ_DUMMY\)\)',
               'if (!filtering && !(flags & READ_DUMMY))',
               "readfile's `reading from stdin` message")
    text = unwrap_if(text, r'^[ \t]*if \(!recoverymode\)$',
                     "readfile's redraw and line count")
    text = unwrap_if(text, r'^[ \t]*if \(!\(recoverymode && error\)\)$',
                     "readfile's return value")

    # --- and the time it can no longer tell ---------------------------------
    blanked = cutil.blank(text)
    m = re.search(r'^add_time\([^\n]*\n', text, re.M)
    if not m:
        sys.exit('norecover: add_time is not defined at file scope')
    o = blanked.index('{', m.end())
    c = cutil.match(text, o, blanked)
    text = text[:o] + '{\n' + RELATIVE + '\n}' + text[c + 1:]
    print('  norecover    add_time says how long ago, not when; localtime_r and '
          'strftime go with it')

    path.write_text(text, errors='surrogateescape')
    print('  norecover    %d recoverymode mentions left for the sweep'
          % len(re.findall(r'\brecoverymode\b', text)))


if __name__ == '__main__':
    main()
