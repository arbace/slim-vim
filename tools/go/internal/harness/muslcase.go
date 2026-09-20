package harness

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
)

// muslCase is tools/muslcase.py: musl's Unicode case mapping, as a table
// zero-vim.c can carry itself.
//
// zero-vim.c called towupper()/towlower() from utf_toupper()/utf_tolower(),
// and zero phase 15 vendors them.  musl implements both with a two-level
// base-6 packed table and forty lines of bit arithmetic, which is exactly what
// this repository's "obvious, simple, idiomatic C" rule is not -- but the SAME
// MAPPING fits the shape zero-vim.c already has: convertStruct rows of
// {rangeStart, rangeEnd, step, offset}, searched by utf_convert(), which is how
// vim carries its own case tables.
//
// THE TABLE IS DATA THE TREE CANNOT DERIVE, and --verify is what keeps it from
// being a remembered constant: it compares the shipped rows against THE LIBC
// THIS MACHINE LINKS, over every one of the 1,114,112 codepoints.  The phase's
// check does not trust the bytes it shipped; it re-derives the answer from the
// only authority there is.  A musl upgrade that moved one codepoint fails the
// phase rather than passing quietly.
//
// HOW THIS ASKS LIBC, AND WHY IT IS NOT cgo.  The Python calls towupper and
// towlower through ctypes.  The Go generates a small C program, compiles it
// with gcc and reads what it prints -- the route tools/muslctype.py already
// takes and that several zero checks take, so it adds no dependency beyond the
// gcc this tree cannot build without.  cgo would be the first thing in the
// build that is not "gcc plus one static binary".
//
// MEASURED EQUIVALENT before this was written, which is the premise the whole
// approach rests on: over all 1,114,112 codepoints the C driver and the
// Python's ctypes report the same 1,382 upper and 1,364 lower mappings, and
// agree on towupper(0x61)=0x41, towupper(0x3b1)=0x391 and the one that
// identifies the libc, towupper(0xdf)=0x1e9e -- ß to ẞ, which musl knows and
// glibc's C locale does not.

const muslCasePlanes = 0x110000

// muslCaseDumper prints one line per codepoint whose mapping is not itself.
// It takes no locale call, deliberately: ctypes calls into the process's libc
// with whatever locale Python started in, which is "C", and a C program that
// called setlocale would be asking a different question.
const muslCaseDumper = `#include <stdio.h>
#include <wctype.h>

int main(void)
{
    long c;

    for (c = 0; c < 0x110000L; c++)
    {
        long u = (long)towupper((wint_t)c);
        long l = (long)towlower((wint_t)c);

        if (u != c)
        {
            printf("u %ld %ld\n", c, u - c);
        }
        if (l != c)
        {
            printf("l %ld %ld\n", c, l - c);
        }
    }
    return 0;
}
`

// muslCaseLibc returns the two {codepoint: offset} maps this machine's libc
// implements.
func muslCaseLibc() (map[int]int, map[int]int, error) {
	d, err := os.MkdirTemp("", "muslcase")
	if err != nil {
		return nil, nil, err
	}
	defer os.RemoveAll(d)
	src := filepath.Join(d, "d.c")
	bin := filepath.Join(d, "d")
	if err := os.WriteFile(src, []byte(muslCaseDumper), 0644); err != nil {
		return nil, nil, err
	}
	cc := exec.Command("gcc", "-O2", "-o", bin, src)
	var ccerr strings.Builder
	cc.Stderr = &ccerr
	if err := cc.Run(); err != nil {
		return nil, nil, fmt.Errorf("muslcase: the libc probe does not compile: %s", ccerr.String())
	}
	out, err := exec.Command(bin).Output()
	if err != nil {
		return nil, nil, fmt.Errorf("muslcase: the libc probe did not run: %v", err)
	}
	up, low := map[int]int{}, map[int]int{}
	s := bufio.NewScanner(strings.NewReader(string(out)))
	s.Buffer(make([]byte, 0, 64*1024), 1<<20)
	for s.Scan() {
		f := strings.Fields(s.Text())
		if len(f) != 3 {
			continue
		}
		c, e1 := strconv.Atoi(f[1])
		off, e2 := strconv.Atoi(f[2])
		if e1 != nil || e2 != nil {
			continue
		}
		switch f[0] {
		case "u":
			up[c] = off
		case "l":
			low[c] = off
		}
	}
	if len(up) == 0 || len(low) == 0 {
		return nil, nil, fmt.Errorf("muslcase: the libc probe reported no mappings at all")
	}
	return up, low, nil
}

type convRow struct{ start, end, step, off int }

// muslCaseCompress turns {codepoint: offset} into convertStruct rows, greedily.
//
// A row is {start, end, step, offset}: the same offset applied to every
// step-th codepoint in [start, end].  utf_convert() binary-searches on
// rangeEnd, so the rows must come out ascending and non-overlapping, which a
// single forward pass over sorted codepoints gives for free.
func muslCaseCompress(delta map[int]int) []convRow {
	keys := make([]int, 0, len(delta))
	for c := range delta {
		keys = append(keys, c)
	}
	sort.Ints(keys)
	var out []convRow
	for _, c := range keys {
		d := delta[c]
		if n := len(out); n > 0 {
			r := out[n-1]
			if r.off == d {
				if r.step == 1 && c == r.end+1 {
					out[n-1].end = c
					continue
				}
				if r.start == r.end && c-r.end >= 2 {
					out[n-1].end, out[n-1].step = c, c-r.end
					continue
				}
				if r.step > 1 && c-r.end == r.step {
					out[n-1].end = c
					continue
				}
			}
		}
		out = append(out, convRow{c, c, 1, d})
	}
	return out
}

func muslCaseExpand(rows []convRow) map[int]int {
	m := map[int]int{}
	for _, r := range rows {
		for c := r.start; c <= r.end; c += r.step {
			m[c] = r.off
		}
	}
	return m
}

func muslCaseEmit(name string, rows []convRow) string {
	parts := make([]string, len(rows))
	for i, r := range rows {
		parts[i] = fmt.Sprintf("        {0x%x,0x%x,%d,%d}", r.start, r.end, r.step, r.off)
	}
	return fmt.Sprintf("static convertStruct %s[] =\n{\n%s\n};\n", name, strings.Join(parts, ",\n"))
}

const muslCaseWrappers = `
    static int
musl_towupper(int a)
{
    return utf_convert(a, musl_toUpper, (int)sizeof(musl_toUpper));
}

    static int
musl_towlower(int a)
{
    return utf_convert(a, musl_toLower, (int)sizeof(musl_toLower));
}
`

// MuslCaseGenerate writes the table text.
func MuslCaseGenerate() (string, error) {
	u, l, err := muslCaseLibc()
	if err != nil {
		return "", err
	}
	up, low := muslCaseCompress(u), muslCaseCompress(l)
	// THE COMPRESSION IS CHECKED, NOT ASSUMED: a greedy pass that merged one
	// row too eagerly would emit a table that is wrong at a codepoint nobody
	// tests, so it is expanded again and required to equal what went in.
	for _, pair := range []struct {
		rows []convRow
		want map[int]int
	}{{up, u}, {low, l}} {
		got := muslCaseExpand(pair.rows)
		if len(got) != len(pair.want) {
			return "", fmt.Errorf("muslcase: the compression is not exact")
		}
		for c, off := range pair.want {
			if got[c] != off {
				return "", fmt.Errorf("muslcase: the compression is not exact")
			}
		}
	}
	return "\n" + muslCaseEmit("musl_toUpper", up) + "\n" + muslCaseEmit("musl_toLower", low) + muslCaseWrappers, nil
}

var muslCaseRow = regexp.MustCompile(`\{(0x[0-9a-f]+),(0x[0-9a-f]+),(-?\d+),(-?\d+)\}`)

func muslCaseRowsOf(text, name string) []convRow {
	re := regexp.MustCompile(`(?ms)^static convertStruct ` + regexp.QuoteMeta(name) + `\[\] =\n\{\n(.*?)\n\};$`)
	m := re.FindStringSubmatch(text)
	if m == nil {
		return nil
	}
	var rows []convRow
	for _, f := range muslCaseRow.FindAllStringSubmatch(m[1], -1) {
		s, _ := strconv.ParseInt(f[1], 0, 64)
		e, _ := strconv.ParseInt(f[2], 0, 64)
		st, _ := strconv.Atoi(f[3])
		off, _ := strconv.Atoi(f[4])
		rows = append(rows, convRow{int(s), int(e), st, off})
	}
	return rows
}

// MuslCaseVerify holds a source's shipped tables to this machine's libc.
func MuslCaseVerify(path string, out *os.File) error {
	data, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	text := string(data)
	up := muslCaseRowsOf(text, "musl_toUpper")
	low := muslCaseRowsOf(text, "musl_toLower")
	if up == nil || low == nil {
		return fmt.Errorf("muslcase: %s has no musl_toUpper[]/musl_toLower[]", path)
	}
	fu, fl := muslCaseExpand(up), muslCaseExpand(low)
	cu, cl, err := muslCaseLibc()
	if err != nil {
		return err
	}
	type badRow struct {
		kind      string
		c         int
		got, want int
	}
	var bad []badRow
	for c := 0; c < muslCasePlanes; c++ {
		if c+fu[c] != c+cu[c] {
			bad = append(bad, badRow{"upper", c, c + fu[c], c + cu[c]})
		}
		if c+fl[c] != c+cl[c] {
			bad = append(bad, badRow{"lower", c, c + fl[c], c + cl[c]})
		}
		if len(bad) > 8 {
			break
		}
	}
	if len(bad) > 0 {
		for _, b := range bad {
			fmt.Fprintf(out, "  muslcase     %s U+%04X: the table says %04X, this libc says %04X\n",
				b.kind, b.c, b.got, b.want)
		}
		return ErrReported
	}
	fmt.Fprintf(out, "  muslcase     %d + %d convertStruct rows, and every one of the %d codepoints "+
		"maps as THIS MACHINE'S libc maps it -- the table is re-derived from the only "+
		"authority there is, not trusted\n", len(up), len(low), muslCasePlanes)
	return nil
}
