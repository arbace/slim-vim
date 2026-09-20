package edit

import (
	"io"
	"regexp"
	"strconv"
	"strings"
)

func init() { register("zero31", Zero31) }

var (
	z31Inc  = regexp.MustCompile(`^#include <[A-Za-z0-9_/.]+>$`)
	z31Word = regexp.MustCompile(`\b(labs|abs)\b`)
	z31Any  = regexp.MustCompile(`\b(abs|labs)\b`)
)

// z31Defs is /root/musl/src/stdlib/abs.c and labs.c, whole, WRITTEN THE WAY THIS
// FILE WRITES A FUNCTION -- the name at column 0 on a line of its own, which is
// what funcreach.py reads a definition by.  MUSL'S TERNARY IS COPIED AND NOT
// TURNED ROUND: `a < 0 ? -a : a` is the same function, so there is nothing to
// gain and one more difference from the source of record to explain.
const z31Defs = `    static int
musl_abs(int a)
{
    return a > 0 ? a : -a;
}

    static long
musl_labs(long a)
{
    return a > 0 ? a : -a;
}

`

const z31Anchor = "    static void *\nmusl_bsearch("

// Zero31 vendors abs and labs -- called by the core, never in `nm -u` because
// gcc lowers both to inline arithmetic, so the phase's whole value is that the
// core stops depending on behaviour nothing states.
func Zero31(text []byte, w io.Writer) ([]byte, error) {
	p := ph{"arith", w}

	mentions := func(t []byte, name string) int {
		return len(regexp.MustCompile(`\b`+name+`\b`).FindAll(t, -1))
	}
	blankRuns := func(t []byte) int {
		L := strings.Split(string(t), "\n")
		n := 0
		for i := 1; i < len(L); i++ {
			if L[i] == "" && L[i-1] == "" {
				n++
			}
		}
		return n
	}
	directives := func(t []byte) ([]int, []string) {
		lines := strings.Split(string(t), "\n")
		var d []int
		for i, l := range lines {
			if strings.HasPrefix(strings.TrimLeft(l, " \t"), "#") {
				d = append(d, i)
			}
		}
		return d, lines
	}
	contiguous := func(d []int) bool {
		for i := range d {
			if d[i] != d[0]+i {
				return false
			}
		}
		return len(d) > 0
	}
	at := func(d []int, n int) string {
		out := make([]string, 0, n)
		for i := 0; i < len(d) && i < n; i++ {
			out = append(out, strconv.Itoa(d[i]+1))
		}
		return strings.Join(out, " ")
	}

	beforeLines := strings.Count(string(text), "\n")
	runsBefore := blankRuns(text)

	// ---- 0. the file this edit was written against ----------------------------
	// ELEVEN DIRECTIVES, contiguous, every one an `#include` of a system header --
	// and since zero phase 27 THEY ARE NOT AT THE TOP.  The first of them is the
	// boundary between the core and the host, so everything this phase writes
	// must land ABOVE it.
	d, lines := directives(text)
	if len(d) != 11 || !contiguous(d) {
		return nil, p.die("the file does not have exactly eleven contiguous preprocessor directives: "+
			"%d at %s", len(d), at(d, 4))
	}
	for _, i := range d {
		if !z31Inc.MatchString(lines[i]) {
			return nil, p.die("a directive is not an `#include <...>` of a system header, and no phase may " +
				"add one")
		}
	}
	cut := d[0]
	for _, name := range []string{"musl_abs", "musl_labs"} {
		if k := mentions(text, name); k != 0 {
			return nil, p.die("`%s` already occurs %d times -- this phase introduces it, so an existing "+
				"mention means the phase has already run or the name is taken", name, k)
		}
	}
	p.sayf("eleven contiguous `#include <...>` directives, the first at line %d and the "+
		"boundary between the core and the host; `musl_abs` and `musl_labs` at zero", cut+1)

	// ---- 1. the two prototypes, found as a BLOCK rather than by line number ---
	firstStatic := -1
	for i, l := range lines {
		if strings.HasPrefix(l, "    static") {
			firstStatic = i
			break
		}
	}
	if firstStatic < 0 {
		return nil, p.die("there is no `    static` line, so the declaration block has no end")
	}
	var proto []int
	for i, l := range lines[:firstStatic] {
		if l == "" || l[0] == ' ' || l[0] == '\t' {
			continue
		}
		if !strings.HasSuffix(l, ";") || !strings.Contains(l, "(") {
			continue
		}
		if strings.HasPrefix(l, "enum") || strings.HasPrefix(l, "typedef") || strings.HasPrefix(l, "static") {
			continue
		}
		proto = append(proto, i)
	}
	if len(proto) == 0 || !contiguous(proto) {
		return nil, p.die("the core's libc declarations are not one contiguous block above the first "+
			"`static`: %d lines at %s", len(proto), at(proto, 4))
	}
	block := make([]string, len(proto))
	for i, j := range proto {
		block[i] = lines[j]
	}
	for _, line := range []string{"long labs(long n);", "int abs(int n);"} {
		if z31Count(block, line) != 1 {
			return nil, p.die("`%s` is not in the core's libc declaration block exactly once -- the "+
				"block is: %s", line, strings.Join(block, " | "))
		}
		if strings.Count(string(text), line+"\n") != 1 {
			return nil, p.die("`%s` is not a line of its own exactly once in the whole file", line)
		}
		text = []byte(strings.Replace(string(text), line+"\n", "", 1))
	}
	p.sayf("the core declares %d libc functions above the first `static` and will declare "+
		"%d: `long labs(long n);` and `int abs(int n);` go, and they are the two the "+
		"core asked libc for and never got", len(block), len(block)-2)

	// ---- 2. the three call sites, by a literal-aware single pass --------------
	// CLAUDE.md, *Rename a name across the whole file*: literal-aware, because a
	// name in a string is DATA, and single-pass, because a literal span is an
	// OFFSET and every offset after the first replacement is wrong.
	// `\babs\b` does not match inside `musl_abs`: `_` is a word character.
	spans, err := literalSpans(p, text)
	if err != nil {
		return nil, err
	}
	var holding []string
	for _, s := range spans {
		if z31Any.Match(text[s[0]:s[1]]) {
			holding = append(holding, string(text[s[0]:s[1]]))
		}
	}
	if len(holding) > 0 {
		return nil, p.die("a string or character literal mentions `abs` or `labs`, so a rename would "+
			"change what the editor PRINTS: %s", strings.Join(first(holding, 3), " / "))
	}
	inSpan := func(off int) bool {
		lo, hi := 0, len(spans)
		for lo < hi {
			mid := (lo + hi) / 2
			if spans[mid][0] <= off {
				lo = mid + 1
			} else {
				hi = mid
			}
		}
		k := lo - 1
		return k >= 0 && spans[k][0] <= off && off < spans[k][1]
	}
	var out strings.Builder
	last := 0
	count := map[string]int{}
	for _, m := range z31Word.FindAllSubmatchIndex(text, -1) {
		if inSpan(m[0]) {
			continue
		}
		name := string(text[m[2]:m[3]])
		out.Write(text[last:m[0]])
		out.WriteString("musl_" + name)
		last = m[1]
		count[name]++
	}
	out.Write(text[last:])
	text = []byte(out.String())
	if count["labs"] != 2 || count["abs"] != 1 {
		return nil, p.die("the rename reached %d `labs` and %d `abs`, and this phase was measured on 2 "+
			"and 1 -- the two prototypes are already gone, so what is left is exactly the "+
			"call sites", count["labs"], count["abs"])
	}
	p.sayf("the three call sites are the core's own now: two `labs` -- the number column's "+
		"relative line number and scroll_with_sms's topline difference -- and one `abs`, "+
		"last_status_rec's window-height difference.  One pass, outside every literal, "+
		"and %d literals were scanned and none mentions either name", len(spans))

	// ---- 3. the two definitions, copied from musl -----------------------------
	if strings.Count(string(text), z31Anchor) != 1 {
		return nil, p.die("`musl_bsearch`'s definition is not in the file exactly once, so there is no " +
			"unambiguous place for these two: they belong with musl_atoi and musl_atol, " +
			"the other <stdlib.h> functions the core owns")
	}
	text = []byte(strings.Replace(string(text), z31Anchor, z31Defs+z31Anchor, 1))

	// ---- 4. what the file is now ----------------------------------------------
	d, lines = directives(text)
	if len(d) != 11 || !contiguous(d) {
		return nil, p.die("the eleven directives are no longer eleven contiguous lines")
	}
	for _, nw := range []struct {
		name string
		want int
	}{{"abs", 0}, {"labs", 0}, {"musl_abs", 2}, {"musl_labs", 3}} {
		if k := mentions(text, nw.name); k != nw.want {
			return nil, p.die("`%s` has %d mentions after the cut, expected %d", nw.name, k, nw.want)
		}
	}
	for _, name := range []string{"musl_abs", "musl_labs"} {
		var where []int
		for i, l := range lines {
			if strings.HasPrefix(l, name+"(") {
				where = append(where, i)
			}
		}
		if len(where) != 1 {
			return nil, p.die("`%s` is not defined by exactly one line beginning at column 0, which is "+
				"how tools/funcreach.py reads a definition", name)
		}
		if where[0] > d[0] {
			return nil, p.die("`%s` is defined BELOW the first `#include`, which is the boundary: it is "+
				"core code and every one of its callers is above the line", name)
		}
	}
	if n := strings.Count(string(text), "\n"); n != beforeLines+10 {
		return nil, p.die("the file is %d lines and the input was %d -- expected exactly ten more, the "+
			"two five-line definitions and their two blank lines less the two prototypes",
			n, beforeLines)
	}
	if r := blankRuns(text); r != runsBefore {
		return nil, p.die("the edit left %d runs of two blank lines where there were %d", r, runsBefore)
	}
	p.sayf("`abs` and `labs` are at 0 mentions in the whole file, `musl_abs` at 2 and "+
		"`musl_labs` at 3 -- a definition and its calls -- both defined at column 0 above "+
		"the boundary, %d -> %d lines and the blank-line runs exactly as before",
		beforeLines, strings.Count(string(text), "\n"))
	return text, nil
}

func z31Count(ss []string, v string) int {
	n := 0
	for _, s := range ss {
		if s == v {
			n++
		}
	}
	return n
}
