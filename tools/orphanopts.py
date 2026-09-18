r"""No option global is left without the row that initialises it.

Usage:
    python3 tools/orphanopts.py <file>

**A row is what initialises its global.**  `set_init_1()` walks `options[]` and
writes each row's default into the variable the row points at, so removing a row
does not merely remove an option -- it removes the only assignment a `p_xx`
global ever gets.  A `long` then stays 0, which is usually harmless.  A
`char_u *` stays NULL for ever, and the first `*p_xx` that runs is a segfault.

`dropoptions.py --strict` refuses to drop a row while anything still reads its
global, which is the guard for this.  It was written after the fact, though, and
Phase 11 dropped `'directory'`, `'updatecount'` and `'swapsync'` before it
existed -- leaving `p_dir` and `p_sws` NULL and dereferenced.  `p_sws` sat behind
`if (mfp->mf_fd < 0) return FAIL;` and could not be reached; `p_dir` could:

    :w! <an existing other file>      ->      Segmentation fault

Nothing found it for twelve phases.  The build is clean, the sweep is silent --
an orphaned global is *used*, so no unused-variable warning names it -- the
linkage and symbol checks pass, and neither the Ex sweep nor the 67 behaviour
cases write over an existing file under a different name with `!`.

So this is the check that catches it by construction rather than by luck, and it
is cheap enough to run in every phase: parse `options[]`, collect every `&p_xx`
it names, and compare that against every `p_xx` declared at file scope.  A
survivor with no row and no initialiser of its own is an orphan; an orphan that
is a pointer is a crash waiting for the right command.

Exit 1 names them.  A non-pointer orphan is reported and tolerated -- the
`p_ai_nopaste` and `p_tw_nobin` save slots are exactly that shape on purpose,
and `int` and `long` orphans read as 0 rather than trapping.

THE ROW FLOOR IS 80, AND IT WAS 100.  The parse below is a regex over options[],
and a regex that stops matching after an edit to the table's shape returns an
empty set -- from which every global looks orphaned, or none does, depending on
which way the comparison falls.  So the floor is a deliberate number rather than
a guard against zero, and it is the same number and the same argument as
tools/create_cmdidxs.py's, so that the two floors stay one idea.  It was 100
while the smallest table in play was slim's and whim's 116 distinct option
globals.  The zero pipeline deletes rows: its phase 12 drops `'fsync'`,
`'prompt'`, `'readonly'`, `'undoreload'`, `'write'` and `'writeany'`, taking the
count 102 -> 96, which the old floor refused with `only 96 rows parsed`.
tools/zerodelta.sh runs this beside its harnesses, so crossing the floor does not
fail that phase -- it fails the delta check of EVERY zero phase after it, with a
message about a table that moved.  Lowered here, in that phase's own commit, per
ZERO-PLAN.md decision 8's argument and never silently; 80 leaves 16 globals of
margin below zero's 96, and the plan removes no further rows.
"""

import re
import sys
from pathlib import Path


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    s = Path(sys.argv[1]).read_text(errors='surrogateescape')

    i = s.find('static struct vimoption options[]')
    if i < 0:
        sys.exit('orphanopts: options[] is not in this file')
    j = s.index('\n};', i)
    rows = set(re.findall(r'&(p_[a-z0-9_]+)\b', s[i:j]))
    if len(rows) < 80:
        sys.exit('orphanopts: only %d rows parsed -- the table has moved and '
                 'this would pass for the wrong reason' % len(rows))

    bad = []
    for m in re.finditer(
            r'^static\s+(char_u\s*\*|long|int)\s*(p_[a-z0-9_]+)\s*(=[^;]*)?;$', s, re.M):
        typ, name, init = m.group(1), m.group(2), m.group(3)
        if name in rows or init:
            continue
        if len(re.findall(r'\b%s\b' % name, s)) <= 1:
            continue          # declared and unread; the sweep takes it
        # ANY MENTION AT ALL, not just a `*p_x` dereference.  This counted
        # only explicit dereferences at first and missed `'completeopt'` in
        # Phase 32: `opt_strings_flags(p_cot, p_cot_values, &cot_flags, TRUE)`
        # passes the NULL pointer to something that dereferences it, and the
        # editor segfaulted before the first keystroke.
        #
        # A pointer nothing mentions is harmless -- the sweep takes it.  One
        # that is mentioned at all, having no row to initialise it, is a NULL
        # going somewhere, and the shape of the somewhere is not this tool's
        # business to judge.
        sites = [h.group(0).strip() for h in re.finditer(r'^.*\b%s\b.*$' % name, s, re.M)
                 if not re.match(r'static\b[^=]*\b%s\s*;' % name, h.group(0).strip())]
        bad.append((name, '*' in typ, sites))

    fatal = [b for b in bad if b[1]]
    quiet = sorted(b[0] for b in bad if not b[1])
    if quiet:
        print('  orphanopts   %d non-pointer orphans read as 0: %s'
              % (len(quiet), ' '.join(quiet)))
    for name, ptr, sites in fatal:
        print('  orphanopts   %s has no row and is a pointer -- NULL for ever, '
              '%d dereference%s' % (name, len(sites), '' if len(sites) == 1 else 's'))
        for line in sites:
            print('               %s' % line[:96])
    if fatal:
        sys.exit(1)
    print('  orphanopts   every option pointer still has the row that sets it')


if __name__ == '__main__':
    main()
