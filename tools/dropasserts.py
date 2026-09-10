#!/usr/bin/env python3
"""Delete the assert() calls, and the <assert.h> that declares them.

Usage:
    python3 tools/dropasserts.py <work-dir>            # find, delete, report
    python3 tools/dropasserts.py <work-dir> --list     # find and report only

Why this exists at all: assert() embeds __LINE__, and __LINE__ is what makes
verification tier 1 -- "the binary is byte-identical" -- impossible, because a
blank line inserted anywhere then moves the binary although no token did.  So
the asserts go before any formatting pass runs.  <assert.h> goes with them:
static_assert is a C23 keyword and needs no header.

Two traps, both paid for:

  * There are EIGHT, not four.  Four is the count in a finished vim.c; the
    unpruned tree compiles eight.  About 180 more live in files this
    configuration does not compile, and deleting those is Phase 2's job by
    deletion of the whole file.
  * A loose grep for "assert" matches vim's own `in_assert_fails` global and
    gives the wrong answer.  The objects are the authority: an object that
    references __assert_fail contains a compiled assert, and nothing else does.
    We use them to decide WHICH FILES to edit, and a word-anchored pattern to
    decide which lines.

The call is removed whole, by paren matching rather than by line, and its line
goes with it -- the surrounding blank lines are left exactly as they were, so
the paragraphing this tree cares about is untouched.
"""

import re
import subprocess
import sys
from pathlib import Path

CALL = re.compile(r'(?<![0-9A-Za-z_])assert\s*\(')


def objects_with_asserts(src: Path):
    """The source files whose objects reference __assert_fail."""
    hits = []
    for obj in sorted((src / 'objects').glob('*.o')):
        out = subprocess.run(['nm', '-u', str(obj)],
                             capture_output=True, text=True).stdout
        if re.search(r'^ *U __assert_fail$', out, re.M):
            hits.append(src / (obj.stem + '.c'))
    return [h for h in hits if h.exists()]


def strip_calls(text: str):
    """Remove every assert(...) statement, returning (text, count)."""
    count = 0
    while True:
        m = CALL.search(text)
        if not m:
            break
        depth, i = 0, m.end() - 1
        while i < len(text):
            if text[i] == '(':
                depth += 1
            elif text[i] == ')':
                depth -= 1
                if depth == 0:
                    break
            i += 1
        end = i + 1
        while end < len(text) and text[end] in ' \t':
            end += 1
        if end < len(text) and text[end] == ';':
            end += 1
        # Take the whole line when nothing but whitespace is left of it.
        line_start = text.rfind('\n', 0, m.start()) + 1
        line_end = text.find('\n', end)
        line_end = len(text) if line_end < 0 else line_end + 1
        head, tail = text[line_start:m.start()], text[end:line_end]
        if head.strip() == '' and tail.strip() == '':
            text = text[:line_start] + text[line_end:]
        else:
            text = text[:m.start()] + text[end:]
        count += 1
    return text, count


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    listing = '--list' in sys.argv
    if not args:
        sys.exit(__doc__)
    work = Path(args[0])
    src = work / 'src'
    if not (src / 'objects').is_dir():
        sys.exit('dropasserts: no %s -- build first, the objects are the authority'
                 % (src / 'objects'))

    files = objects_with_asserts(src)
    total = 0
    for f in files:
        text = f.read_text()
        new, n = strip_calls(text)
        total += n
        if not listing and n:
            f.write_text(new)
    print('  asserts      %d call%s in %d file%s: %s'
          % (total, '' if total == 1 else 's',
             len(files), '' if len(files) == 1 else 's',
             ', '.join(f.name for f in files)))

    # <assert.h> is included by vim.h alone in the files this build compiles.
    # The four in the *_test.c files go with those files in Phase 2.
    if not listing:
        headers = 0
        for h in [src / 'vim.h']:
            text = h.read_text()
            new = re.sub(r'^# *include *<assert\.h>\n', '', text, flags=re.M)
            if new != text:
                h.write_text(new)
                headers += 1
        print('  assert.h     removed from %d header%s'
              % (headers, '' if headers == 1 else 's'))

    if total != 8:
        print('  asserts      NOTE: expected 8, found %d -- upstream may have '
              'moved; check before trusting the boundary' % total)


if __name__ == '__main__':
    main()
