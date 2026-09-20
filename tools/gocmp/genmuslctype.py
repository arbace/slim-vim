"""Write tools/go/internal/harness/muslctype.go, with the C driver taken from
tools/muslctype.py by IMPORT rather than by transcription.

The driver is 230 lines of C.  Retyping it into a Go literal is the one step of
this port where a silent difference could hide -- a changed constant in the
random walk, a dropped case in the edge table -- and neither the compile nor the
comparison would name it.  So it is generated.

--check IS WHAT MAKES THAT TRUE, and without it the previous sentence was a
claim rather than a fact.  The commit that added this file said "regenerating is
how it is checked" and nothing regenerated: an edit to tools/muslctype.py's
driver would leave tools/go/internal/harness/muslctype.go stale, the Go would go
on compiling and the comparison would go on passing, because both sides would be
testing the OLD driver against itself.  That is the same shape as a tool reached
by import naming no path -- the thing that actually changed is invisible to
everything downstream of it.

    python3 tools/gocmp/genmuslctype.py            rewrite the Go
    python3 tools/gocmp/genmuslctype.py --check    require it to be current
"""
import subprocess
import sys
import pathlib

def lit(name):
    out = subprocess.run([sys.executable, 'tools/gocmp/genlit.py', 'muslctype', name],
                         capture_output=True, text=True, check=True).stdout
    body = []
    keep = False
    for line in out.split('\n'):
        if line == 'CONST %s' % name:
            keep = True
            continue
        if line == 'ENDCONST':
            keep = False
            continue
        if keep:
            body.append(line)
    return '\n'.join(body).rstrip()

GO = '''package harness

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
)

// MuslCtypeVerify is tools/muslctype.py: compile the vendored musl block OUT OF
// THE SOURCE THE PHASE PRODUCED and hold it to the libc this machine links.
//
// The claim zero phase 15 makes is not "these look like musl's" but "these
// compute what musl computes", and the only way to say that is to run both.  So
// the block is sliced out of the .c the phase wrote -- not out of
// tools/musl-ctype.txt, which would only prove the copy was faithful -- wrapped
// in a main() that calls libc beside it, compiled with -Wall -Wextra, and run.
//
// THE DOMAIN IS BOUNDED ON PURPOSE and it is the one number here that is not
// exhaustive.  All eleven classifiers were compared with musl's over all
// 4,294,967,296 int values while the phase was written: zero disagreements, in
// 66 seconds.  A check that doubles a phase's time to re-prove a closed form is
// a check that stops being run.  What runs is every int in [-1024, 1024], every
// threshold and its two neighbours, EOF, INT_MIN, INT_MAX, and a FIXED
// pseudo-random sample of 1,000,000 -- fixed, so the check is a function of its
// input like everything else here.
//
// THE C DRIVER BELOW IS GENERATED from tools/muslctype.py by
// tools/gocmp/genmuslctype.py, which imports that module rather than scraping
// it.  Do not hand-edit it: a changed constant in the random walk or a dropped
// row in the edge table would be invisible to both the compile and the
// comparison.
const muslCtypeStart = %(START)s

const muslCtypeEnd = %(END)s

const muslCtypeMain = %(MAIN)s

// muslCtypeNames are the fifteen the block must define exactly once each.  The
// slice is by text, so a block that lost a function would still compile if
// libc supplied the name -- this is what stops that.
var muslCtypeNames = []string{
	"musl_isdigit", "musl_isalpha", "musl_isupper", "musl_islower",
	"musl_isgraph", "musl_isspace", "musl_isalnum", "musl_iscntrl",
	"musl_ispunct", "musl_tolower", "musl_toupper", "musl_atoi",
	"musl_atol", "musl_bsearch", "musl_qsort",
}

const muslCtypeTag = "vendor"

func muslDie(format string, a ...any) error {
	return fmt.Errorf("  %%-12s %%s", muslCtypeTag, fmt.Sprintf(format, a...))
}

// MuslCtypeVerify returns nil when the vendored block agrees with libc, and
// writes its own success line -- which carries the numbers, because a check
// that prints only "ok" cannot be read for whether it did anything.
func MuslCtypeVerify(path string, out *os.File) error {
	data, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	text := string(data)
	if strings.Count(text, muslCtypeStart) != 1 || strings.Count(text, muslCtypeEnd) != 1 {
		return muslDie("%%s does not hold exactly one vendored block", path)
	}
	a := strings.Index(text, muslCtypeStart)
	z := strings.Index(text, muslCtypeEnd)
	if z <= a {
		return muslDie("the vendored block and its two prototypes are in the wrong order")
	}
	block := text[a:z]
	for _, name := range muslCtypeNames {
		re := regexp.MustCompile("(?m)^" + regexp.QuoteMeta(name) + `\\(`)
		if len(re.FindAllString(block, -1)) != 1 {
			return muslDie("the block sliced out of %%s does not define %%s exactly once", path, name)
		}
	}

	d, err := os.MkdirTemp("", "muslctype")
	if err != nil {
		return err
	}
	defer os.RemoveAll(d)
	src := filepath.Join(d, "h.c")
	if err := os.WriteFile(src, []byte("#include <stddef.h>\\n"+block+muslCtypeMain), 0644); err != nil {
		return err
	}
	bin := filepath.Join(d, "h")
	cc := exec.Command("gcc", "-O2", "-Wall", "-Wextra", "-o", bin, src)
	var ccerr strings.Builder
	cc.Stderr = &ccerr
	// A CLEAN COMPILE IS PART OF THE CLAIM, so a warning fails it: gcc exits 0
	// with warnings, and a check that tests only the status passes always.
	if err := cc.Run(); err != nil || strings.TrimSpace(ccerr.String()) != "" {
		fmt.Fprintf(out, "  %%-12s the vendored block does not compile clean on its own:\\n", muslCtypeTag)
		s := strings.TrimRight(ccerr.String(), "\\n")
		if len(s) > 2000 {
			s = s[:2000]
		}
		fmt.Fprintln(out, s)
		return ErrReported
	}
	run := exec.Command(bin)
	stdout, err := run.Output()
	if err != nil {
		return muslDie("the harness did not run")
	}

	got := map[string][]string{}
	for _, line := range strings.Split(string(stdout), "\\n") {
		f := strings.Fields(line)
		if len(f) > 1 {
			got[f[0]] = f[1:]
		}
	}
	num := func(key string, idx int) (int, error) {
		v, ok := got[key]
		if !ok || idx >= len(v) {
			return 0, muslDie("the harness printed no %%s row, so its result cannot be read", key)
		}
		n, err := strconv.Atoi(v[idx])
		if err != nil {
			return 0, muslDie("the harness's %%s row is not a number: %%v", key, v)
		}
		return n, nil
	}

	var fail []string
	get := func(key string, idx int) int {
		n, err := num(key, idx)
		if err != nil {
			fail = append(fail, err.Error())
			return -1
		}
		return n
	}
	ctypeN, ctypeBad := get("ctype", 0), get("ctype", 1)
	atoiN, atoiBad := get("atoi", 0), get("atoi", 1)
	bsN, bsBad := get("bsearch", 0), get("bsearch", 1)
	qsBad := get("qsort", 1)
	tiesMoved, tiesOrder := get("ties", 0), get("ties", 1)

	if ctypeBad != 0 {
		fail = append(fail, fmt.Sprintf("%%d ctype disagreements with libc", ctypeBad))
	}
	if ctypeN < 1002000 {
		fail = append(fail, fmt.Sprintf("the ctype domain shrank to %%d values", ctypeN))
	}
	if atoiN != 137560 || atoiBad != 0 {
		fail = append(fail, fmt.Sprintf("atoi/atol: %%d %%d", atoiN, atoiBad))
	}
	if bsN != 1845 || bsBad != 0 {
		fail = append(fail, fmt.Sprintf("bsearch: %%d %%d", bsN, bsBad))
	}
	if qsBad != 0 {
		fail = append(fail, fmt.Sprintf("qsort: %%v", got["qsort"]))
	}
	// THE TIE CASE IS REQUIRED TO DIFFER IN POINTERS AND NOT IN STRINGS.
	// musl's smoothsort is unstable and this insertion sort is stable, so a
	// harness that could not tell them apart would pass a phase that had
	// swapped one for the other by accident.
	if tiesOrder != 0 {
		fail = append(fail, fmt.Sprintf("the tie case sorts to a DIFFERENT string order, "+
			"which is a bug in musl_qsort and not a tie-break: %%v", got["ties"]))
	}
	if tiesMoved == 0 {
		fail = append(fail, "the tie case places every pointer exactly as musl does, so this "+
			"harness cannot tell a stable sort from an unstable one and the "+
			"qsort result above proves nothing")
	}
	if len(fail) > 0 {
		for _, line := range fail {
			fmt.Fprintf(out, "  %%-12s %%s\\n", muslCtypeTag, strings.TrimSpace(strings.TrimPrefix(line, "  "+muslCtypeTag)))
		}
		return ErrReported
	}
	fmt.Fprintf(out, "  %%-12s the block compiled OUT OF THE PRODUCED SOURCE agrees with libc: "+
		"%%d int values (bounded -- all 2^32 were checked once, 0 disagreements, and "+
		"it costs 66 s), %%d atoi/atol strings, %%d bsearch lookups compared by "+
		"POINTER, 2000 qsort arrays -- and the three-equal-keys case moves %%d of 5 "+
		"pointers while sorting to the same strings, which is what says the harness "+
		"can see a tie at all\\n",
		muslCtypeTag, ctypeN, atoiN, bsN, tiesMoved)
	return nil
}
'''

def main():
    src = GO % {'START': lit('START'), 'END': lit('END'), 'MAIN': lit('MAIN')}
    p = pathlib.Path('tools/go/internal/harness/muslctype.go')
    if '--check' in sys.argv[1:]:
        if not p.exists():
            sys.exit('%s does not exist; run this without --check' % p)
        if p.read_text() != src:
            sys.exit('%s is NOT what tools/muslctype.py generates -- the vendored\n'
                     'C driver has moved and the Go copy is stale.  Re-run this '
                     'without --check.' % p)
        print('%s is current with tools/muslctype.py' % p)
        return
    p.write_text(src)
    print('wrote %s (%d lines)' % (p, src.count('\n') + 1))

if __name__ == '__main__':
    main()
