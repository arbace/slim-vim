#!/usr/bin/env python3
"""Every tools/ module a phase IMPORTS must also be named as a path.

Usage:
    python3 tools/importpaths.py [--fix]      (from the repository root)

tools/implhash.sh greps a phase program for `tools/...` PATHS, and a Python
`import` names a MODULE.  So a heredoc that does `import cutil` depends on
tools/cutil.py and the memoize cannot see it: an edit to that module changes
what the phase produces, moves no key, and lets a warm repass replay the old
boundary and report success.  CLAUDE.md records this for cutil.py and macros.py
and its fix -- name the path in a comment beside the import -- was applied to
the six importers in tools/ and to none of the 118 in pipes/.

MEASURED when this was written: editing tools/cutil.py moved 2 of 59 whim and
zero unit keys, and 52 phase files import it.

This is the rule as a program rather than as a habit, because the habit failed
twice in one hour: swapping a tool to Go, the prose cleanup that correctly stops
naming a tool the phase no longer RUNS also stopped naming one it still
IMPORTS -- create_cmdidxs first, then termcheck.  A rule you have to remember at
the moment you are doing something else is not a rule.

It is named by no phase program, so it enters no implementation key and can be
changed freely.
"""
import os, re, sys, glob

NOTE = ["# tools/%s.py -- named as a PATH so tools/implhash.sh hashes it into this",
        "# phase's key.  implhash greps for paths and an `import` names a module, so",
        "# without this line an edit to it changes what this phase produces and moves",
        "# no key at all.  See CLAUDE.md on cutil.py and macros.py.  Do not delete it."]


def holes(path):
    src = open(path).read()
    mods = set(re.findall(r'^\s*import\s+([a-z0-9_]+)\s*$', src, re.M))
    mods |= set(re.findall(r'^\s*from\s+([a-z0-9_]+)\s+import', src, re.M))
    return sorted(m for m in mods
                  if os.path.exists('tools/%s.py' % m) and ('tools/%s.py' % m) not in src)


def fix(path, need):
    out, done = [], set()
    for line in open(path).read().split('\n'):
        m = re.match(r'^(\s*)(?:import\s+([a-z0-9_]+)\s*$|from\s+([a-z0-9_]+)\s+import)', line)
        if m:
            mod = m.group(2) or m.group(3)
            if mod in need and mod not in done:
                ind = m.group(1)
                out.extend(ind + l % mod if '%s' in l else ind + l for l in NOTE)
                done.add(mod)
        out.append(line)
    open(path, 'w').write('\n'.join(out))
    return len(done)


def main():
    fixing = '--fix' in sys.argv
    files = sorted(glob.glob('pipes/*.sh'))
    if not files:
        sys.exit('importpaths: no pipes/*.sh -- run me from the repository root')
    bad = 0
    for f in files:
        need = holes(f)
        if not need:
            continue
        if fixing:
            bad += fix(f, set(need))
        else:
            bad += len(need)
            print('  %-28s imports %s without naming its path' % (f, ', '.join(need)))
    if fixing:
        print('  importpaths  named %d modules as paths' % bad)
        return
    if bad:
        print('  importpaths  %d module(s) a phase imports are in no key -- run --fix' % bad)
        sys.exit(1)
    print('  importpaths  every tools/ module a phase imports is named as a path')


if __name__ == '__main__':
    main()
