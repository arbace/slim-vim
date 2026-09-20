"""Render a Python cutter's big string constants as Go string literals.

Imports the module rather than scraping its source, because the constants are
non-raw triple-quoted strings: `\\\\` in the source is `\\` in the value, and a
regex over the text would carry the wrong one into the Go.

Go raw strings cannot hold a backtick and two of these do, so the output is an
interpreted string, one source line per Go line joined with `+`.
"""
import sys


def golit(s):
    out = []
    for line in s.split('\n'):
        esc = (line.replace('\\', '\\\\').replace('"', '\\"')
                   .replace('\t', '\\t'))
        out.append('\t"%s\\n" +' % esc)
    # the value has no trailing newline; drop the last \n and the trailing +
    last = out[-1]
    out[-1] = last[:-len('\\n" +')] + '"'
    return '\n'.join(out).lstrip('\t')


if __name__ == '__main__':
    sys.path.insert(0, 'tools')
    mod = __import__(sys.argv[1])
    for name in sys.argv[2:]:
        print('CONST %s' % name)
        print(golit(getattr(mod, name)))
        print('ENDCONST')
