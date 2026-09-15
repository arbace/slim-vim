#!/usr/bin/env python3
"""No -c, --cmd, -R, -m, -M or -w{N}: each becomes the error any unknown option is.

Usage:
    python3 tools/nocmdargs.py <file>

tools/dropopts.py removes a short option whose body ends in `break` and a long
option that is a link in the `--` chain, and it is used here for -R, -w and
--cmd.  Two of the six it refuses, rightly:

  -c HAS A BODY OF ITS OWN THAT FALLS THROUGH into -T and -u.  `-c{command}`
  takes its command from the same argument and breaks; `-c {command}` falls
  through to ask for the next argument.  The label and its body go by hand, and
  the argument switch's `case 'c':` goes with dropopts.

  -M FALLS THROUGH INTO -m, so the pair goes together.

--cmd was the only long option that took an argument, so the argument switch's
`case '-':` goes too, and the one `if (!want_argument)` left in the option
switch's `case '-':` can no longer be false.  The commands --cmd collected ran
in exe_pre_commands(); its call goes, and the sweep takes it and the fields.

+{command} stays, and fills the same list -c did.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cutil
import dropopts


def subn(seg, pattern, new, what, count=1, flags=re.M):
    seg, n = re.subn(pattern, new, seg, flags=flags)
    if n != count:
        sys.exit('nocmdargs: %s -- matched %d times, expected %d' % (what, n, count))
    print('  nocmdargs    %s' % what)
    return seg


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    t = path.read_text(errors='surrogateescape')

    span = cutil.find_definition(t, 'command_line_scan')
    if not span:
        sys.exit('nocmdargs: command_line_scan is not defined at file scope')
    a, z = span
    fn = t[a:z]

    fn = subn(fn, r"^[ \t]*case 'c':\n[ \t]*if \(argv\[0\]\[argv_idx\] != NUL\)\n.*?"
                  r"^[ \t]*__attribute__\(\(fallthrough\)\);\n(?=[ \t]*case 'T':\n)",
              '', '-c in the option switch', flags=re.M | re.S)
    fn = subn(fn, r"^[ \t]*case 'M':\n[ \t]*reset_modifiable\(\);\n\n[ \t]*__attribute__\(\(fallthrough\)\);\n"
                  r"[ \t]*case 'm':\n[ \t]*p_write = FALSE;\n[ \t]*break;\n\n",
              '', '-M and -m')
    fn, held = dropopts.drop_short(fn, 0, {'R', 'w'})
    if held != {'R', 'w'}:
        sys.exit('nocmdargs: -R and -w are not both labels in the option switch: %s' % sorted(held))
    print('  nocmdargs    -R and -w')
    fn, held = dropopts.drop_short(fn, 1, {'c', '-'})
    if held != {'c', '-'}:
        sys.exit("nocmdargs: -c and -- are not both in the argument switch: %s" % sorted(held))
    print('  nocmdargs    -c and --cmd in the argument switch')
    fn = dropopts.drop_long(fn, 'cmd')
    print('  nocmdargs    --cmd in the option switch')
    try:
        fn = cutil.fold_always(fn, r'^[ \t]*if \(!want_argument\)$', 1, re.M)
    except ValueError as e:
        sys.exit('nocmdargs: -- asking whether it wants an argument -- %s' % e)
    print('  nocmdargs    -- no longer asks whether it wants an argument')
    t = t[:a] + fn + t[z:]

    t = subn(t, r'^[ \t]*exe_pre_commands\(&params\);\n', '', 'startup running the --cmd commands')

    left = [(what, n) for what, pattern, want in (
                ("a case for -c, -R, -m, -M or -w", r"^[ \t]*case '[cRmMw]':$", 0),
                ('--cmd in the parser', r'\("cmd"\)', 0))
            for n in [len(re.findall(pattern, fn, re.M))] if n != want]
    if left:
        sys.exit('nocmdargs: still present: %s' % left)

    path.write_text(t, errors='surrogateescape')
    print('  nocmdargs    -c, --cmd, -R, -m, -M and -w are unknown options')


if __name__ == '__main__':
    main()
