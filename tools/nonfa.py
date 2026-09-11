#!/usr/bin/env python3
"""Leave one regexp engine, not two.

Usage:
    python3 tools/nonfa.py <file>

vim carries two regexp engines: the backtracking one it always had, and an NFA
engine added later.  `'regexpengine'` chooses between them and `\\%#=N` at the
start of a pattern overrides it per-pattern.  That is a *migration path* -- the
NFA engine was new, and the option existed so a user could go back when it
misbehaved -- and an embedded fork inherits the machinery without inheriting the
reason.

Measured before removing it: `'regexpengine'` is compiled in as 1, the
backtracking engine, so nothing this editor does by default enters the NFA code
at all, and a coverage run over the whole harness never reaches a line of it.
That makes it the largest single entry on the "reachable and never run" list --
`nfa_emit_equi_class` alone is 4,122 lines.

It is NOT unused, which is why this is a decision and not a sweep: `:set re=2`
and `\\%#=2` reach it, and both go here.

The custom delimiter atoms this tree's upstream branch exists for are
implemented in BOTH engines -- `delimiter_atom` appears in the bt region and
again in the nfa region -- so the backtracking engine keeps them and the feature
survives intact.  That was checked before anything was cut.

Three entry points; the ~6,000 lines behind them are found by the sweep:

  * vim_regcomp() stops choosing.  The `\\%#=` prefix, the AUTOMATIC retry and
    the call into nfa_regengine all go with it.
  * prog_magic_wrong() stops asking whether the program came from the NFA
    engine -- with one engine the answer is always no, and the check would
    otherwise keep `nfa_regengine` alive by naming it.
  * `'regexpengine'` is dropped separately, by tools/dropoptions.py.

And one more, which the first attempt at this phase needed and did not have.
Cutting the three entry points removed only 48 lines, because what is left is a
MUTUALLY REFERENCING ISLAND: `nfa_regengine` is a struct naming `nfa_regcomp`
and three others, and `nfa_regcomp` assigns `&nfa_regengine` back.  Each keeps
the other looking used, `-Wall` says nothing, and six thousand lines sit there
being reachable from nothing at all.  CLAUDE.md records this trap for *types* --
"two types naming each other keep each other alive for ever" -- and it is the
same shape for functions, where no tool here computes reachability.

So the island's two halves go together, in one edit, because either alone does
not compile: the `nfa_regengine` definition, and the assignment inside
`nfa_regcomp` that points back at it.  With both gone the four functions it
named are unreferenced, `-Wall` finally says so, and the sweep takes the rest.
"""

import re
import sys
from pathlib import Path

OLD_COMPILE = '''    regexp_engine = p_re;

    if ( strncmp((char *)(expr), (char *)("\\\\%#="), (4))  == 0)
'''

NEW_COMPILE = '''    rex.reg_buf = curbuf;

    prog = bt_regengine.regcomp(expr, re_flags);

    if (prog != NULL)
    {
        prog->re_engine = BACKTRACKING_ENGINE;
        prog->re_flags  = re_flags;
    }

    return prog;
}
'''

ISLAND = """static regengine_T nfa_regengine =
{
    nfa_regcomp,
    nfa_regfree,
    nfa_regexec_nl,
    nfa_regexec_multi
};

"""

BACKREF = '    prog->engine = &nfa_regengine;\n'

MAGIC = '''    if (prog->engine == &nfa_regengine)
    {
        return FALSE;
    }

'''


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    text = path.read_text(errors='surrogateescape')

    # The whole body of vim_regcomp from the engine choice to its closing brace.
    start = text.find(OLD_COMPILE)
    if start < 0:
        sys.exit('nonfa: vim_regcomp does not begin the way this expects -- it '
                 'has moved, and replacing a body by guesswork is how an editor '
                 'ends up with no regexp engine at all')
    end = text.index('\n    return prog;\n}\n', start) + len('\n    return prog;\n}\n')
    text = text[:start] + NEW_COMPILE + text[end:]

    if MAGIC not in text:
        sys.exit('nonfa: prog_magic_wrong no longer tests for the NFA engine')
    text = text.replace(MAGIC, '', 1)

    # The island: both halves or neither.  Removing the struct alone leaves
    # nfa_regcomp assigning the address of something that no longer exists.
    for part, what in ((ISLAND, 'the nfa_regengine definition'),
                       (BACKREF, "nfa_regcomp's back-reference to it")):
        if part not in text:
            sys.exit('nonfa: cannot find %s, and cutting one half without the '
                     'other does not compile' % what)
        text = text.replace(part, '', 1)

    # Whatever is left naming it would keep six thousand lines alive.
    path.write_text(text, errors='surrogateescape')
    rest = text.count('nfa_regengine')
    print('  nonfa        vim_regcomp compiles with bt only; prog_magic_wrong '
          'stops asking; %d nfa_regengine mentions left for the sweep' % rest)


if __name__ == '__main__':
    main()
