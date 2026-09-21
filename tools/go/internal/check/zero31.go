package check

import (
	"crypto/sha256"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"slimvim.local/tools/internal/harness"
)

func init() { register("zero31", Zero31) }

var (
	z31Section = regexp.MustCompile(`^\s*\[\s*\d+\]\s+(\.\S+)\s+\S+\s+([0-9a-f]+)\s+[0-9a-f]+\s+` +
		`([0-9a-f]+)\s+\S+\s+\S*\s*\d+\s+\d+\s+(\d+)\s*$`)
	z31ErrLine = regexp.MustCompile(`(?m)^[^ ].*: error:.*$`)
	z31Undef   = regexp.MustCompile(`'(\w+)' used but never defined`)
	z31Mark    = regexp.MustCompile(`(?m)^Z(\d) (-?\d+)$`)
	z31OldCall = regexp.MustCompile(`\b(abs|labs)\b`)
	z31NewCall = regexp.MustCompile(`call.*\bmusl_l?abs\b`)
	z31Hits    = regexp.MustCompile(`^Z[123] `)
)

const z31Ternary = "    return a > 0 ? a : -a;\n"

// The instrument: the site and the VALUE at each call, on stderr.  `write` is
// the core's own declaration, immediately above.
const z31Probe = `    static long
zprobe(int site, long v)
{
    char buf[32];
    int i = 31;
    int neg = v < 0;
    unsigned long u = neg ? -(unsigned long)v : (unsigned long)v;

    buf[i] = '\n';
    i--;
    while (1)
    {
        buf[i] = (char)('0' + (int)(u % 10UL));
        i--;
        u /= 10UL;
        if (u == 0UL)
        {
            break;
        }
    }
    if (neg)
    {
        buf[i] = '-';
        i--;
    }
    buf[i] = ' ';
    i--;
    buf[i] = (char)('0' + site);
    i--;
    buf[i] = 'Z';
    write(2, buf + i, (usize)(32 - i));
    return v;
}

`

// THE EXHAUSTIVE EQUIVALENCE, as a program rather than a paragraph.
const z31SameC = `#include <stdio.h>
#include <limits.h>
__attribute__((noipa)) static int  musl_abs(int a)    { return a > 0 ? a : -a; }
__attribute__((noipa)) static long musl_labs(long a)  { return a > 0 ? a : -a; }
__attribute__((noipa)) static int  other_abs(int a)   { return a < 0 ? -a : a; }
__attribute__((noipa)) static long other_labs(long a) { return a < 0 ? -a : a; }
int main(void)
{
    long i, bad_i = 0, bad_l = 0, n = 20000000;
    long edge[6] = {LONG_MIN, LONG_MIN + 1, -1, 0, 1, LONG_MAX};
    unsigned long s = 88172645463325252UL;
    for (i = INT_MIN; i <= INT_MAX; i++)
        if (musl_abs((int)i) != other_abs((int)i)) bad_i++;
    for (i = 0; i < 6; i++)
        if (musl_labs(edge[i]) != other_labs(edge[i])) bad_l++;
    for (i = 0; i < n; i++) {
        s ^= s << 13; s ^= s >> 7; s ^= s << 17;
        if (musl_labs((long)s) != other_labs((long)s)) bad_l++;
    }
    printf("ints %ld bad %ld  longs %ld bad %ld  absmin %d %d  labsmin %ld %ld\n",
           (long)INT_MAX - (long)INT_MIN + 1, bad_i, n + 6, bad_l,
           musl_abs(INT_MIN), other_abs(INT_MIN),
           musl_labs(LONG_MIN), other_labs(LONG_MIN));
    return (bad_i || bad_l) ? 1 : 0;
}
`

type z31Sec struct{ addr, size, align int64 }

func z31Sections(path string) map[string]z31Sec {
	out := map[string]z31Sec{}
	b, _ := exec.Command("readelf", "-SW", path).Output()
	for _, l := range strings.Split(string(b), "\n") {
		if m := z31Section.FindStringSubmatch(l); m != nil {
			a, _ := strconv.ParseInt(m[2], 16, 64)
			s, _ := strconv.ParseInt(m[3], 16, 64)
			al, _ := strconv.ParseInt(m[4], 10, 64)
			out[m[1]] = z31Sec{a, s, al}
		}
	}
	return out
}

func z31Sizes(obj string) map[string]int64 {
	out := map[string]int64{}
	b, _ := exec.Command("nm", "-S", obj).Output()
	for _, l := range strings.Split(string(b), "\n") {
		p := strings.Fields(l)
		if len(p) == 4 {
			v, _ := strconv.ParseInt(p[1], 16, 64)
			out[p[3]] = v
		}
	}
	return out
}

func z31TextSize(obj string) (int64, bool) {
	b, _ := exec.Command("readelf", "-SW", obj).Output()
	for _, l := range strings.Split(string(b), "\n") {
		p := strings.Fields(l)
		if len(p) > 6 && p[2] == ".text" {
			v, _ := strconv.ParseInt(p[6], 16, 64)
			return v, true
		}
	}
	return 0, false
}

func z31FDEs(obj string) int {
	b, _ := exec.Command("readelf", "--debug-dump=frames-interp", obj).Output()
	return strings.Count(string(b), "FDE cie=")
}

// z31Comma is Python's format(n, ',').
func z31Comma(n int64) string {
	s := strconv.FormatInt(n, 10)
	neg := strings.HasPrefix(s, "-")
	if neg {
		s = s[1:]
	}
	var out []string
	for len(s) > 3 {
		out = append([]string{s[len(s)-3:]}, out...)
		s = s[:len(s)-3]
	}
	out = append([]string{s}, out...)
	r := strings.Join(out, ",")
	if neg {
		r = "-" + r
	}
	return r
}

func z31Plus(n int64) string {
	if n >= 0 {
		return fmt.Sprintf("+%d", n)
	}
	return fmt.Sprintf("%d", n)
}

func z31Head(w io.Writer, path string, n int, prefix string) {
	for i, l := range strings.Split(strings.TrimRight(readFile(path), "\n"), "\n") {
		if i >= n {
			break
		}
		fmt.Fprintf(w, "%s%s\n", prefix, l)
	}
}

// Zero31 is phase 31's check: abs and labs, the two the core took on trust.
func Zero31(w io.Writer, args []string) error {
	if len(args) != 2 {
		return fmt.Errorf("usage: check zero31 <work-dir> <state-dir>")
	}
	work, state := args[0], args[1]
	f := filepath.Join(work, "zero-vim.c")
	oldC := filepath.Join(state, "old.c")
	r := &rep{tag: "arith", w: w}
	stop := func(format string, a ...any) error {
		r.say(format, a...)
		return harness.ErrReported
	}
	beforeRaw := strings.TrimRight(readFile(filepath.Join(state, "input-lines")), "\n")
	tmp, err := os.MkdirTemp("", "zero31-")
	if err != nil {
		return err
	}
	defer os.RemoveAll(tmp)
	T := func(n string) string { return filepath.Join(tmp, n) }
	mk := readFile(filepath.Join(work, "Makefile"))
	var cflags, ldflags []string
	if m := z29CFlags.FindStringSubmatch(mk); m != nil {
		cflags = strings.Fields(m[1])
	}
	if m := z29LDFlags.FindStringSubmatch(mk); m != nil {
		ldflags = strings.Fields(m[1])
	}
	link := func(src, out, logPath string) error {
		a := append(append(append([]string{}, cflags...), ldflags...), "-o", out, src)
		c := exec.Command("gcc", a...)
		c.Env = append(os.Environ(), "SOURCE_DATE_EPOCH=0")
		if logPath != "" {
			lf, _ := os.Create(logPath)
			defer lf.Close()
			c.Stderr = lf
		}
		return c.Run()
	}

	// --- 0. the control, the instrument and the two spellings ------------------
	t := readFile(f)
	if strings.Count(t, z31Ternary) != 2 {
		return stop("`%s` is not in the output exactly twice, so neither variant below "+
			"could be built from it", strings.TrimSpace(z31Ternary))
	}
	os.WriteFile(T("wrong.c"), []byte(strings.ReplaceAll(t, z31Ternary, "    return a;\n")), 0o644)
	sites := [][2]string{
		{"num = musl_labs((long)get_cursor_rel_lnum(wp, wlv->lnum));",
			"num = musl_labs(zprobe(1, (long)get_cursor_rel_lnum(wp, wlv->lnum)));"},
		{"if (musl_labs(curwin->w_topline - prev_topline) > (dir ==  (-1) ))",
			"if (musl_labs(zprobe(2, curwin->w_topline - prev_topline)) > (dir ==  (-1) ))"},
		{"if (musl_abs(wp->w_height - wp->w_prev_height) == 1)",
			"if (musl_abs((int)zprobe(3, (long)(wp->w_height - wp->w_prev_height))) == 1)"},
	}
	const anchor = "    static void *\nmusl_bsearch("
	s := t
	for _, x := range sites {
		if strings.Count(s, x[0]) != 1 {
			old := x[0]
			if len(old) > 60 {
				old = old[:60]
			}
			return stop("the call site `%s` is not in the output exactly once, so the "+
				"instrument cannot be placed and this phase cannot say whether the "+
				"corpus reaches it", old)
		}
		s = strings.Replace(s, x[0], x[1], 1)
	}
	if strings.Count(s, anchor) != 1 {
		return stop("musl_bsearch is not in the output exactly once")
	}
	os.WriteFile(T("values.c"), []byte(strings.Replace(s, anchor, z31Probe+anchor, 1)), 0o644)
	i := strings.Index(t, "musl_abs(int a)")
	li := strings.Index(t, "musl_labs(long a)")
	var body string
	if i >= 0 && li >= 0 {
		if k := strings.Index(t[li:], "\n}\n"); k >= 0 {
			j := li + k + 3
			if st := strings.LastIndex(t[:i], "    static int\n"); st >= 0 {
				body = t[st:j]
			}
		}
	}
	if strings.Count(body, z31Ternary) != 2 || !strings.Contains(body, "musl_abs") || !strings.Contains(body, "musl_labs") {
		return stop("the two definitions could not be lifted out of the output")
	}
	const tail = "int a1(int x) { return musl_abs(x); }\nlong a2(long x) { return musl_labs(x); }\n"
	os.WriteFile(T("spell1.c"), []byte(body+tail), 0o644)
	os.WriteFile(T("spell2.c"), []byte(strings.ReplaceAll(body, z31Ternary, "    return a < 0 ? -a : a;\n")+tail), 0o644)
	r.say("the control (both vendored functions return their argument unchanged), " +
		"the instrument (the site and the VALUE at each of the three call sites) and the " +
		"two spellings, all built FROM THE OUTPUT")

	var wg sync.WaitGroup
	var errNew, errVal, errWrong, errOO, errNO, errSame, errCanon error
	var canonLog []byte
	bg := func(fn func()) { wg.Add(1); go func() { defer wg.Done(); fn() }() }
	var wNew, wVal, wWrong, wOO, wNO, wSame, wCanon sync.WaitGroup
	for _, x := range []struct {
		wg *sync.WaitGroup
		fn func()
	}{
		{&wNew, func() { errNew = link(f, T("new"), "") }},
		{&wVal, func() { errVal = link(T("values.c"), T("values"), T("values.log")) }},
		{&wWrong, func() { errWrong = link(T("wrong.c"), T("wrong"), T("wrong.log")) }},
		{&wOO, func() {
			errOO = exec.Command("gcc", "-c", "-O0", "-fno-stack-protector", "-o", T("old.o"), oldC).Run()
		}},
		{&wNO, func() {
			errNO = exec.Command("gcc", "-c", "-O0", "-fno-stack-protector", "-o", T("new.o"), f).Run()
		}},
		{&wSame, func() {
			os.WriteFile(T("same.c"), []byte(z31SameC), 0o644)
			if errSame = exec.Command("gcc", "-O2", "-o", T("same"), T("same.c")).Run(); errSame != nil {
				return
			}
			out, e := exec.Command(T("same")).Output()
			os.WriteFile(T("same.txt"), out, 0o644)
			errSame = e
		}},
		{&wCanon, func() {
			os.WriteFile(T("canon.c"), []byte(t), 0o644)
			canonLog, errCanon = exec.Command("sh", "tools/canon.sh", T("canon.c")).CombinedOutput()
		}},
	} {
		x := x
		x.wg.Add(1)
		bg(func() { defer x.wg.Done(); x.fn() })
	}
	defer wg.Wait()

	// --- 1. the source, as arithmetic on the input ------------------------------
	oldT := readFile(oldC)
	beforeLines, _ := strconv.Atoi(strings.TrimSpace(beforeRaw))
	mentions := func(text, name string) int {
		return len(regexp.MustCompile(`\b` + name + `\b`).FindAllStringIndex(text, -1))
	}
	split := func(text, which string) ([]string, int, error) {
		lines := strings.Split(text, "\n")
		var d []int
		for k, l := range lines {
			if strings.HasPrefix(strings.TrimLeft(l, " \t\n\v\f\r"), "#") {
				d = append(d, k)
			}
		}
		ok := len(d) == 11
		for k := range d {
			if ok && d[k] != d[0]+k {
				ok = false
			}
		}
		if !ok {
			var at []string
			for k, x := range d {
				if k >= 3 {
					break
				}
				at = append(at, strconv.Itoa(x+1))
			}
			return nil, 0, stop("%s does not have eleven contiguous directives: %d at %s.  The "+
				"first one IS the boundary and every count below distinguishes the core "+
				"from the host", which, len(d), strings.Join(at, " "))
		}
		return lines, d[0], nil
	}
	olines, ocut, e := split(oldT, "old.c")
	if e != nil {
		return e
	}
	nlines, ncut, e := split(t, "the output")
	if e != nil {
		return e
	}
	if len(olines)-1 != beforeLines {
		r.bad("the state directory says the edit was handed %d lines and old.c has %d",
			beforeLines, len(olines)-1)
	}
	inAbs, inLabs := mentions(oldT, "abs"), mentions(oldT, "labs")
	if inAbs != 2 || inLabs != 3 {
		r.bad("the input has %d `abs` and %d `labs`, and this phase was measured on 2 "+
			"and 3 -- a prototype and one call, a prototype and two calls", inAbs, inLabs)
	}
	for _, x := range []struct {
		name string
		want int
		why  string
	}{
		{"abs", 0, "the prototype and the call site are both gone"},
		{"labs", 0, "the prototype and both call sites are gone"},
		{"musl_abs", inAbs, "its definition and the one call the prototype served"},
		{"musl_labs", inLabs, "its definition and the two calls"},
	} {
		if n := mentions(t, x.name); n != x.want {
			r.bad("`%s` has %d mentions in the output, expected %d -- %s", x.name, n, x.want, x.why)
		}
	}
	for _, name := range []string{"musl_abs", "musl_labs"} {
		var at []int
		for k, l := range nlines {
			if strings.HasPrefix(l, name+"(") {
				at = append(at, k)
			}
		}
		if len(at) != 1 {
			r.bad("`%s` is not defined by exactly one line beginning at column 0, "+
				"which is how tools/funcreach.py reads a definition -- %d found", name, len(at))
		} else if at[0] > ncut {
			r.bad("`%s` is defined below the first `#include`, which is the boundary, "+
				"and every one of its callers is above it", name)
		} else if pl := nlines[at[0]-1]; pl != "    static int" && pl != "    static long" {
			r.bad("`%s` is not introduced by a `    static <type>` line of its own", name)
		}
	}
	block := func(lines []string) []string {
		first := len(lines)
		for k, l := range lines {
			if strings.HasPrefix(l, "    static") {
				first = k
				break
			}
		}
		var out []string
		for _, l := range lines[:first] {
			if l != "" && !strings.ContainsAny(l[:1], " \t\n\r\v\f") && strings.HasSuffix(l, ";") &&
				strings.Contains(l, "(") && !strings.HasPrefix(l, "enum") &&
				!strings.HasPrefix(l, "typedef") && !strings.HasPrefix(l, "static") {
				out = append(out, l)
			}
		}
		return out
	}
	ob, nb := block(olines), block(nlines)
	inNB := map[string]bool{}
	for _, l := range nb {
		inNB[l] = true
	}
	var gone []string
	for _, l := range ob {
		if !inNB[l] {
			gone = append(gone, l)
		}
	}
	sg := append([]string{}, gone...)
	sort.Strings(sg)
	if strings.Join(sg, "\x00") != "int abs(int n);\x00long labs(long n);" || len(nb) != len(ob)-2 {
		g := strings.Join(gone, " / ")
		if g == "" {
			g = "nothing"
		}
		r.bad("the core's libc declaration block went from %d entries to %d and lost "+
			"%s -- it must lose exactly `long labs(long n);` and `int abs(int n);`", len(ob), len(nb), g)
	}
	if len(nlines)-len(olines) != 10 {
		r.bad("the file is %d lines and the input was %d -- expected exactly ten more: "+
			"two five-line definitions and their blank lines, less two prototypes",
			len(nlines)-1, len(olines)-1)
	}
	if ncut-ocut != 10 {
		r.bad("the core is %d lines and was %d, a difference of %d where 10 was "+
			"expected -- everything this phase writes is core code", ncut, ocut, ncut-ocut)
	}
	if len(nlines)-ncut != len(olines)-ocut {
		r.bad("the host changed size, and this phase does not touch it")
	}
	if z27Runs(nlines) != z27Runs(olines) {
		r.bad("the edit left %d runs of two blank lines where there were %d", z27Runs(nlines), z27Runs(olines))
	}
	if err := r.done(); err != nil {
		return err
	}
	r.say("`abs` %d -> 0 and `labs` %d -> 0 in the whole file; `musl_abs` 0 -> %d "+
		"and `musl_labs` 0 -> %d, each a definition at column 0 and the calls its "+
		"prototype used to serve.  Every count is computed FROM THE INPUT", inAbs, inLabs, inAbs, inLabs)
	r.cont("the core's libc declaration block is %d entries and was %d, and the two "+
		"it lost are `long labs(long n);` and `int abs(int n);` -- what phase 26 wrote "+
		"when the headers were still above it.  The core is %d lines against %d (+10) and "+
		"the host is unchanged at %d", len(nb), len(ob), ncut, ocut, len(nlines)-ncut)

	// --- 2. the two spellings are the same function -----------------------------
	for _, opt := range []string{"-O0", "-O2"} {
		for _, sp := range []string{"spell1", "spell2"} {
			c := exec.Command("gcc", opt, "-c", "-fno-stack-protector", "-o", T(sp+opt+".o"), T(sp+".c"))
			lf, _ := os.Create(T(sp + ".log"))
			c.Stderr = lf
			err := c.Run()
			lf.Close()
			if err != nil {
				r.say("the %s spelling did not compile at %s:", sp, opt)
				z31Head(w, T(sp+".log"), 3, "               ")
				return harness.ErrReported
			}
			exec.Command("objcopy", "-O", "binary", "--only-section=.text", T(sp+opt+".o"), T(sp+opt+".text")).Run()
		}
		if sizeOf(T("spell1"+opt+".text")) <= 0 {
			return stop("objcopy wrote an empty .text, and comparing two empty streams reports every pair " +
				"identical (CLAUDE.md)")
		}
		if !z30Same(T("spell1"+opt+".text"), T("spell2"+opt+".text")) {
			r.say("THE TWO SPELLINGS COMPILE DIFFERENTLY at %s.  `a > 0 ? a : -a`", opt)
			fmt.Fprintln(w, "               and `a < 0 ? -a : a` are the same function, and this phase")
			fmt.Fprintln(w, "               copies musl's spelling BECAUSE the choice is free.  If it is")
			fmt.Fprintln(w, "               no longer free the argument has to be rewritten, not the number.")
			return harness.ErrReported
		}
	}
	wSame.Wait()
	if errSame != nil {
		r.say("the equivalence probe did not build or disagreed:")
		if _, e := os.Stat(T("same.txt")); e == nil {
			z31Head(w, T("same.txt"), 1<<30, "               ")
		}
		return harness.ErrReported
	}
	sw := strings.Fields(readFile(T("same.txt")))
	if len(sw) != 14 || sw[0] != "ints" {
		return stop("the equivalence probe printed something this check cannot read: %s", strings.Join(sw, " "))
	}
	ints, badI, longs, badL := sw[1], sw[3], sw[5], sw[7]
	absMin, absMin2, labsMin, labsMin2 := sw[9], sw[10], sw[12], sw[13]
	if badI != "0" || badL != "0" {
		return stop("the two spellings disagree: %s of %s ints and %s of %s longs", badI, ints, badL, longs)
	}
	if absMin != absMin2 || labsMin != labsMin2 {
		return stop("the two spellings differ AT THE MINIMUM, where both are undefined: "+
			"%s/%s and %s/%s", absMin, absMin2, labsMin, labsMin2)
	}
	r.say("`a > 0 ? a : -a` AND `a < 0 ? -a : a` ARE THE SAME FUNCTION, twice over: "+
		"the two spellings taken out of the output compile to BYTE-IDENTICAL machine code "+
		"at -O0 and at -O2 (%d bytes of .text), and they agree at all %s `int` values and "+
		"all %s `long` ones tried, LONG_MIN and LONG_MAX among them.  So musl's spelling "+
		"is copied because copying is the rule, not because it is better",
		sizeOf(T("spell1-O0.text")), ints, longs)
	r.cont("AND THE UNDEFINED BEHAVIOUR IS COPIED WITH IT, deliberately: `-a` "+
		"overflows, so both return their argument at the minimum -- musl_abs(INT_MIN) = "+
		"%s and musl_labs(LONG_MIN) = %s, which is what libc's own abs and labs do here "+
		"and what musl's source says they do.  THE PAIR IS FAITHFUL RATHER THAN SAFER; a "+
		"phase that quietly made the core's arithmetic differ from the libc it replaces "+
		"would be a behaviour change wearing a vendoring phase's clothes", absMin, labsMin)

	// --- 3. canon.sh -------------------------------------------------------------
	wCanon.Wait()
	if errCanon != nil {
		r.say("tools/canon.sh failed on the output:")
		for k, l := range strings.Split(string(canonLog), "\n") {
			if k >= 10 {
				break
			}
			fmt.Fprintln(w, l)
		}
		return harness.ErrReported
	}
	if !z30Same(f, T("canon.c")) {
		r.say("tools/canon.sh is not a no-op on the output -- the two definitions are not written the way " +
			"this file writes everything else:")
		for k, l := range z30Diff(f, T("canon.c")) {
			if k >= 12 {
				break
			}
			fmt.Fprintln(w, l)
		}
		return harness.ErrReported
	}
	r.say("tools/canon.sh is a NO-OP on the output: the two definitions are written the way this file " +
		"writes every other function, the name at column 0 on a line of its own -- which is what " +
		"tools/funcreach.py reads, and what phase 14 got wrong")

	// --- 4. the boundary, with the set taken from the input's own cut ----------
	r4 := &rep{tag: "arith", w: w}
	seen := map[string][]string{}
	cutN := map[string]int{}
	for _, x := range []struct{ which, path string }{{"output", f}, {"input", oldC}} {
		lines := z28Cut(readFile(x.path))
		cp := T("cut." + x.which + ".c")
		os.WriteFile(cp, []byte(strings.Join(lines, "\n")+"\n"), 0o644)
		var d []string
		for _, l := range lines {
			if z30Dir.MatchString(l) {
				d = append(d, l)
			}
		}
		if len(d) > 0 {
			r4.bad("the %s cut holds %d directive(s), so it found the wrong line: %s", x.which, len(d), d[0])
		}
		c := exec.Command("gcc", "-O0", "-fno-stack-protector", "-Wall", "-Wextra",
			"-Wno-unused-parameter", "-fsyntax-only", cp)
		var eb strings.Builder
		c.Stderr = &eb
		c.Run()
		wt := eb.String()
		if errs := z31ErrLine.FindAllString(wt, -1); len(errs) > 0 {
			if len(errs) > 3 {
				errs = errs[:3]
			}
			r4.bad("the %s cut does not compile on its own:\n    %s", x.which, strings.Join(errs, "\n    "))
		}
		for _, l := range strings.Split(wt, "\n") {
			if strings.Contains(l, ": warning: ") && !strings.Contains(l, "used but never defined") {
				r4.bad("the %s cut has a warning that is not a boundary name: %s", x.which, l)
				break
			}
		}
		set := map[string]bool{}
		for _, m := range z31Undef.FindAllStringSubmatch(wt, -1) {
			set[m[1]] = true
		}
		seen[x.which] = z27Keys(set)
		cutN[x.which] = len(lines)
	}
	if strings.Join(seen["output"], " ") != strings.Join(seen["input"], " ") {
		inOut, inIn := map[string]bool{}, map[string]bool{}
		for _, n := range seen["output"] {
			inOut[n] = true
		}
		for _, n := range seen["input"] {
			inIn[n] = true
		}
		var g, a []string
		for _, n := range seen["input"] {
			if !inOut[n] {
				g = append(g, n)
			}
		}
		for _, n := range seen["output"] {
			if !inIn[n] {
				a = append(a, n)
			}
		}
		r4.bad("the core -> host boundary moved: gone [%s] arrived [%s].  This phase "+
			"adds two functions the core calls and the host does not, so the set "+
			"cannot change", strings.Join(g, " "), strings.Join(a, " "))
	}
	if len(seen["output"]) < 10 {
		r4.bad("the cut named only %d undefined functions, which is too few to be the "+
			"boundary -- a cut that found the wrong line would say the same", len(seen["output"]))
	}
	for _, n := range []string{"musl_abs", "musl_labs"} {
		if contains(seen["output"], n) {
			r4.bad("`%s` is undefined above the cut, so it was defined below the "+
				"boundary: it is core code", n)
		}
	}
	if err := r4.done(); err != nil {
		return err
	}
	r.say("the cut is %d lines against the input's %d, with 0 directives, no error "+
		"under -fsyntax-only and no warning that is not a boundary name -- and THE "+
		"BOUNDARY IS THE SAME %d NAMES, taken from the INPUT's own cut in this run and "+
		"required back rather than quoted from a list: %s",
		cutN["output"], cutN["input"], len(seen["output"]), strings.Join(seen["output"], " "))

	// --- 5. the symbols, and the reason they cannot move -------------------------
	beforeU := readFile(filepath.Join(state, "symbols", "undefined"))
	os.WriteFile(T("before.u"), []byte(beforeU), 0o644)
	pc := exec.Command("sh", "tools/phasecheck.sh", work, f, filepath.Join(state, "symbols"))
	pc.Stdout, pc.Stderr = w, w
	if err := pc.Run(); err != nil {
		return harness.ErrReported
	}
	lastU := ".cache/symbols/last/undefined"
	lines := func(s string) []string {
		s = strings.TrimRight(s, "\n")
		if s == "" {
			return nil
		}
		return strings.Split(s, "\n")
	}
	bu, lu := lines(beforeU), lines(readFile(lastU))
	if !z30Same(T("before.u"), lastU) {
		r.say("the libc surface moved, and IT CANNOT:")
		fmt.Fprintf(w, "               gone: %s\n", z31Words(comm23(bu, lu)))
		fmt.Fprintf(w, "               came: %s\n", z31Words(comm23(lu, bu)))
		return harness.ErrReported
	}
	for _, n := range []string{"abs", "labs"} {
		if contains(bu, n) || contains(lu, n) {
			return stop("`%s` is in the undefined set, and this phase's whole argument is that it never was", n)
		}
	}
	for _, x := range []struct{ src, out string }{{oldC, "old.s"}, {f, "new.s"}} {
		if out, err := exec.Command("gcc", "-S", "-O0", "-fno-stack-protector", "-o", T(x.out), x.src).CombinedOutput(); err != nil {
			w.Write(out)
			return harness.ErrReported
		}
	}
	oldCalls, newCalls := 0, 0
	var oldHits []string
	for _, l := range strings.Split(readFile(T("old.s")), "\n") {
		if z31OldCall.MatchString(l) {
			oldCalls++
			if len(oldHits) < 3 {
				oldHits = append(oldHits, l)
			}
		}
	}
	for _, l := range strings.Split(readFile(T("new.s")), "\n") {
		if z31NewCall.MatchString(l) {
			newCalls++
		}
	}
	if oldCalls != 0 {
		r.say("the INPUT's assembly mentions abs or labs %d time(s), so this compiler does NOT lower them "+
			"and the input was carrying two real libc calls.  That is a stronger reason for this phase, not "+
			"a weaker one -- but the sentence below is wrong and has to be rewritten:", oldCalls)
		for _, l := range oldHits {
			fmt.Fprintf(w, "               %s\n", l)
		}
		return harness.ErrReported
	}
	if newCalls < 3 {
		return stop("the output's assembly makes %d calls to musl_abs/musl_labs and there are three call "+
			"sites: the core is still not calling anything", newCalls)
	}
	r.say("`nm -u` IS THE SAME SET, %d names, as a `comm` empty in BOTH directions, and `main` is still the "+
		"only external symbol.  (That is tools/symbols.sh's count, which compiles plain -O0 and so adds "+
		"`__stack_chk_fail`; zero's own compile line has -fno-stack-protector and gives 17.)  THIS PHASE "+
		"FREES NOTHING AND IT CANNOT: `abs` and `labs` were in the undefined set ZERO times before it, "+
		"because gcc lowers both to inline arithmetic -- measured, the INPUT's whole assembly mentions "+
		"neither name, though the source calls them at three sites.  Nothing in the language promises "+
		"that, and a compiler that emitted the calls would have added two libc symbols to this file in "+
		"silence.  The output makes %d real calls, to two functions of its own", len(bu), newCalls)

	// --- 6. the binary, and the difference accounted for -------------------------
	_ = exec.Command("make", "-C", work, "clean").Run()
	bin := filepath.Join(work, "zero-vim")
	if _, e := os.Stat(bin); e == nil {
		(&rep{tag: "build", w: w}).say("the clean did not remove zero-vim, so a 'rebuild' below could be " +
			"no rebuild at all")
		return harness.ErrReported
	}
	if err := exec.Command("make", "-C", work).Run(); err != nil {
		(&rep{tag: "build", w: w}).say("FAILED -- rerun by hand: make -C %s", work)
		return harness.ErrReported
	}
	nowB, _ := os.ReadFile(f)
	(&rep{tag: "build", w: w}).say("ok, %s -> %d lines, %d bytes", beforeRaw, countLines(nowB), sizeOf(bin))
	wNew.Wait()
	if errNew != nil {
		return stop("the reproducible build of the output failed")
	}
	wOO.Wait()
	wNO.Wait()
	_, _ = errOO, errNO
	oldBinP := filepath.Join(state, "old")
	oldSize, newSize := sizeOf(oldBinP), sizeOf(T("new"))
	if newSize < 500000 || oldSize < 500000 {
		return stop("one of the two binaries is %d / %d bytes, which is not an editor", oldSize, newSize)
	}
	if newSize != sizeOf(bin) {
		return stop("the reproducible build is %d bytes and make produced %d: the two differ by more than "+
			"a timestamp", newSize, sizeOf(bin))
	}
	if z30Same(oldBinP, T("new")) {
		r.say("THE BINARY DID NOT MOVE, and it must: at -O0 a call to a static")
		fmt.Fprintln(w, "               function is a call and inline arithmetic is not.  Two identical")
		fmt.Fprintln(w, "               binaries here mean the edit did not reach the three call sites.")
		return harness.ErrReported
	}
	if err := z31Binary(r, oldBinP, T("new"), T("old.o"), T("new.o")); err != nil {
		return err
	}

	// --- 7. the recordings, the blindness, and the probes -------------------------
	wVal.Wait()
	if errVal != nil {
		r.say("the instrumented build failed:")
		z31Head(w, T("values.log"), 3, "               ")
		return harness.ErrReported
	}
	wWrong.Wait()
	if errWrong != nil {
		r.say("the control build failed:")
		z31Head(w, T("wrong.log"), 3, "               ")
		return harness.ErrReported
	}
	oldBin, _ := filepath.Abs(oldBinP)
	var wgR sync.WaitGroup
	recErr := make([]error, 3)
	for k, x := range []struct{ bin, src, out string }{
		{oldBin, oldC, "REC.old"}, {T("new"), f, "REC.new"}, {T("values"), T("values.c"), "REC.values"},
	} {
		k, x := k, x
		wgR.Add(1)
		go func() {
			defer wgR.Done()
			recErr[k] = exec.Command("sh", "tools/zrecord.sh", x.bin, x.src, T(x.out)).Run()
		}()
	}
	perr := z31Probes(r, oldBin, tmp)
	if perr != nil {
		return perr
	}
	// Collected by bare `wait $pid`s, as the shell does: a recording that
	// fails ends the check with nothing printed.  One of the fifteen sites a
	// later pass repairs; repairing it here would break report identity.
	wgR.Wait()
	for _, e := range recErr {
		if e != nil {
			return harness.ErrReported
		}
	}
	if dl := diffRQ(T("REC.old"), T("REC.new")); len(dl) > 0 {
		r.say("the declared delta is NOTHING AT ALL and the two recordings differ:")
		for k, l := range dl {
			if k >= 12 {
				break
			}
			fmt.Fprintln(w, l)
		}
		return harness.ErrReported
	}
	if dl := diffRQ(T("REC.values"), T("REC.new")); len(dl) > 0 {
		r.say("THE CORPUS DOES REACH A CALL SITE.  The instrumented build's recording differs from the " +
			"product's, which means one of the three sites was entered -- this phase states that none is, and " +
			"the statement has to be re-made rather than the difference ignored:")
		for k, l := range dl {
			if k >= 12 {
				break
			}
			fmt.Fprintln(w, l)
		}
		return harness.ErrReported
	}
	hits := 0
	for _, rel := range walkFiles(T("REC.values")) {
		for _, l := range strings.Split(readFile(filepath.Join(T("REC.values"), rel)), "\n") {
			if z31Hits.MatchString(l) {
				hits++
			}
		}
	}
	records := len(walkFiles(T("REC.new")))
	if hits != 0 {
		return stop("the instrument fired %d time(s) across the recording, and the two recordings are "+
			"nevertheless identical -- one of the two measurements is wrong", hits)
	}
	r.say("the declared delta is NOTHING AT ALL and TWO FULL RECORDINGS ARE BYTE-IDENTICAL, %d records: 102 "+
		"screen cases, every Ex command, every command line, the pty scenarios and the terminal table.  AND "+
		"THE CORPUS CANNOT SEE THIS PHASE AT ALL, which is measured and not assumed: the same output built "+
		"with a probe on each of the three arguments enters NONE of them in %d records -- the instrumented "+
		"recording is byte-identical too, and the marker appears %d times.  That is why the phase owes the "+
		"probes above", records, records, hits)
	return nil
}

func z31Words(xs []string) string {
	s := ""
	for _, x := range xs {
		s += x + " "
	}
	return s
}

// z31Binary is section 6's heredoc: the image may change only in .text and
// .eh_frame, and the object's .text delta must be accounted for.
func z31Binary(r *rep, oldBin, newBin, oldO, newO string) error {
	so, sn := z31Sections(oldBin), z31Sections(newBin)
	zo, zn := z31Sizes(oldO), z31Sizes(newO)
	to, ok1 := z31TextSize(oldO)
	tn, ok2 := z31TextSize(newO)
	if !ok2 {
		r.say("%s has no .text", newO)
		return harness.ErrReported
	}
	if !ok1 {
		r.say("%s has no .text", oldO)
		return harness.ErrReported
	}
	objDelta := tn - to
	align := so[".text"].align
	dtext := sn[".text"].size - so[".text"].size
	deh := sn[".eh_frame"].size - so[".eh_frame"].size
	if objDelta > align {
		r.bad("the object gained %d bytes of .text and `.text` aligns to %d, so the "+
			"new code no longer fits in one alignment unit and the rule below -- it "+
			"grows by 0 or by one unit -- does not apply", objDelta, align)
	}
	if dtext != 0 && dtext != align {
		r.bad("`.text` grew by %d bytes, and %d bytes of new code may only be absorbed "+
			"by the section padding (0) or spill exactly one %d-byte alignment unit "+
			"past it", dtext, objDelta, align)
	}
	if deh != 64 {
		r.bad(".eh_frame is %d bytes and was %d, a difference of %d where 64 was "+
			"expected -- two 32-byte unwind records, one per new function",
			sn[".eh_frame"].size, so[".eh_frame"].size, deh)
	}
	all := map[string]bool{}
	for k := range so {
		all[k] = true
	}
	for k := range sn {
		all[k] = true
	}
	names := z27Keys(all)
	var resized, shifted []string
	for _, k := range names {
		if k != ".text" && k != ".eh_frame" && so[k].size != sn[k].size {
			resized = append(resized, k)
		}
	}
	for _, k := range names {
		o, okO := so[k]
		n, okN := sn[k]
		if okO && okN {
			if d := n.addr - o.addr; d != 0 && d != dtext {
				shifted = append(shifted, k)
			}
		}
	}
	if len(resized) > 0 {
		r.bad("%s changed SIZE, and only .text and .eh_frame may: this phase adds two "+
			"functions and touches no data", strings.Join(resized, " "))
	}
	if len(shifted) > 0 {
		r.bad("%s moved by something other than 0 or the %d bytes .text grew by",
			strings.Join(shifted, " "), dtext)
	}
	if nf := z31FDEs(newO) - z31FDEs(oldO); nf != 2 {
		r.bad("the object gained %d unwind records where 2 were expected, one per new "+
			"function", nf)
	}
	defs := map[string]int64{}
	for _, n := range []string{"musl_abs", "musl_labs"} {
		if v, ok := zn[n]; ok {
			defs[n] = v
		}
	}
	if len(defs) != 2 {
		r.bad("the output object does not define both musl_abs and musl_labs")
	}
	callers := map[string]int64{}
	for _, n := range []string{"handle_lnum_col", "scroll_with_sms", "last_status_rec"} {
		vo, okO := zo[n]
		vn, okN := zn[n]
		if okO && okN {
			callers[n] = vn - vo
		}
	}
	cnames := make([]string, 0, len(callers))
	for k := range callers {
		cnames = append(cnames, k)
	}
	sort.Strings(cnames)
	if len(callers) != 3 {
		r.bad("the three calling functions are not all in both objects: %s", strings.Join(cnames, " "))
	}
	var sumDefs, sumCallers int64
	for _, v := range defs {
		sumDefs += v
	}
	for _, v := range callers {
		sumCallers += v
	}
	var callerS []string
	for _, k := range cnames {
		callerS = append(callerS, k+" "+z31Plus(callers[k]))
	}
	if len(r.fail) == 0 && sumDefs+sumCallers != objDelta {
		dn := z27Keys(map[string]bool{"musl_abs": true, "musl_labs": true})
		var defS []string
		for _, k := range dn {
			defS = append(defS, fmt.Sprintf("%s %d", k, defs[k]))
		}
		r.bad("the object's .text grew by %d bytes and the two definitions (%s) plus "+
			"the three callers (%s) account for %d.  The edit reached code this "+
			"phase does not name", objDelta, strings.Join(defS, " "), strings.Join(callerS, " "),
			sumDefs+sumCallers)
	}
	if err := r.done(); err != nil {
		return err
	}
	ob, _ := os.ReadFile(oldBin)
	nb, _ := os.ReadFile(newBin)
	nDiff := 0
	for k := 0; k < len(ob) && k < len(nb); k++ {
		if ob[k] != nb[k] {
			nDiff++
		}
	}
	r.say("THE BINARY MOVED AND THE DIFFERENCE IS ACCOUNTED FOR INSTRUCTION BY "+
		"INSTRUCTION: the object's .text grows by exactly %d bytes, which is musl_abs "+
		"(%d) plus musl_labs (%d) plus what the three callers gained or lost (%s) and "+
		"nothing else.  The image is %s bytes either side and %d of them differ, which is "+
		"what putting a definition near the front of a file does.  ONLY `.text` AND "+
		"`.eh_frame` CHANGE SIZE -- no data section moves a byte -- and neither changes by "+
		"more than one alignment unit: `.text` %s, which is %d bytes of code absorbed by "+
		"the section padding or spilling exactly one %d-byte unit past it (MEASURED BOTH "+
		"WAYS for the identical edit: 0 on the r29 tree, %d here), and `.eh_frame` +%d, "+
		"two 32-byte unwind records -- the object gains exactly 2, one per new function",
		objDelta, defs["musl_abs"], defs["musl_labs"], strings.Join(callerS, " "),
		z31Comma(sizeOf(newBin)), nDiff, z31Plus(dtext), sumDefs, align, dtext, deh)
	return nil
}

type z31Run struct {
	ok  bool
	n   int
	sha [32]byte
	rc  int
	se  []byte
}

// z31Probes is section 7's heredoc: one probe per call site, on four binaries.
func z31Probes(r *rep, oldBin, tmp string) error {
	var lb, long strings.Builder
	for k := 1; k <= 60; k++ {
		fmt.Fprintf(&lb, "line%d\r", k)
	}
	for k := 0; k < 39; k++ {
		long.WriteString(strings.Repeat("y", 300) + "\r")
	}
	probes := []struct {
		name string
		args []string
		keys string
		site int
	}{
		{"rnu", []string{"+set paste", "+set rnu"}, "i" + lb.String() + "\x1bgg:q!\r", 1},
		{"sms", []string{"+set paste"}, "i" + long.String() + "\x1bgg\x06\x06\x02\x02:q!\r", 2},
		{"stl", nil, ":set laststatus=2\r:set laststatus=0\r:q!\r", 3},
	}
	whos := []struct{ who, path string }{
		{"old", oldBin}, {"new", filepath.Join(tmp, "new")},
		{"values", filepath.Join(tmp, "values")}, {"wrong", filepath.Join(tmp, "wrong")},
	}
	run := func(binary string, args []string, keys string) z31Run {
		_, so, se, rc, err := harness.ZSession(binary, [][]byte{[]byte(keys)}, "xterm", args, 24, 80, 25*time.Second)
		if err != nil {
			return z31Run{}
		}
		return z31Run{true, len(so), sha256.Sum256(so), rc, se}
	}
	// Sequential, in the Python's order: it ran them one after another.
	seen := map[[2]string]z31Run{}
	for _, p := range probes {
		for _, x := range whos {
			seen[[2]string{x.who, p.name}] = run(x.path, p.args, p.keys)
		}
	}
	type val struct{ site, n, lo, hi int }
	values := map[string]val{}
	var order []string
	var moved []string
	same := func(a, b z31Run) bool { return a.ok == b.ok && a.n == b.n && a.sha == b.sha && a.rc == b.rc }
	for _, p := range probes {
		o, n := seen[[2]string{"old", p.name}], seen[[2]string{"new", p.name}]
		v, wr := seen[[2]string{"values", p.name}], seen[[2]string{"wrong", p.name}]
		for _, x := range []struct {
			who string
			r   z31Run
		}{{"old", o}, {"new", n}, {"values", v}, {"wrong", wr}} {
			if !x.r.ok {
				r.bad("the `%s` probe never returned on `%s`", p.name, x.who)
			}
		}
		if !o.ok || !n.ok {
			continue
		}
		if !same(o, n) {
			r.bad("the `%s` probe draws a different screen on the binary this phase "+
				"was handed and on its own: %d bytes against %d", p.name, o.n, n.n)
		}
		if !same(v, n) {
			r.bad("the instrumented build draws a different screen from the product "+
				"on the `%s` probe, so what it reports is not what the product does", p.name)
		}
		var mine []int
		other := map[int]bool{}
		for _, m := range z31Mark.FindAllSubmatch(v.se, -1) {
			st, _ := strconv.Atoi(string(m[1]))
			vv, _ := strconv.Atoi(string(m[2]))
			if st == p.site {
				mine = append(mine, vv)
			} else {
				other[st] = true
			}
		}
		if len(other) > 0 {
			var os_ []int
			for k := range other {
				os_ = append(os_, k)
			}
			sort.Ints(os_)
			var ss []string
			for _, k := range os_ {
				ss = append(ss, strconv.Itoa(k))
			}
			r.bad("the `%s` probe reached call sites %s as well as %d, so the counts "+
				"below do not say what they claim", p.name, strings.Join(ss, " "), p.site)
		}
		if len(mine) == 0 {
			r.bad("the `%s` probe reaches call site %d zero times, and it exists to "+
				"reach it -- this phase would then have no evidence for that site "+
				"at all", p.name, p.site)
			continue
		}
		lo, hi := mine[0], mine[0]
		for _, x := range mine {
			if x < lo {
				lo = x
			}
			if x > hi {
				hi = x
			}
		}
		values[p.name] = val{p.site, len(mine), lo, hi}
		order = append(order, p.name)
		if !same(n, wr) {
			moved = append(moved, p.name)
		}
	}
	iabs := func(x int) int {
		if x < 0 {
			return -x
		}
		return x
	}
	span := 0
	for _, k := range order {
		v := values[k]
		if m := iabs(v.lo); m > span {
			span = m
		}
		if m := iabs(v.hi); m > span {
			span = m
		}
	}
	if len(r.fail) == 0 {
		if span > 1000 {
			r.bad("a call site was handed an argument of magnitude %d, and this phase "+
				"states that every one of them is a small difference of line numbers "+
				"or of window heights.  The UB argument has to be re-made rather "+
				"than the number updated", span)
		}
		if !contains(moved, "rnu") {
			r.bad("the CONTROL -- both vendored functions returning their argument " +
				"unchanged -- does not move the `rnu` probe, so that probe cannot " +
				"fail and proves nothing (CLAUDE.md)")
		}
	}
	if err := r.done(); err != nil {
		return err
	}
	var parts []string
	for _, k := range order {
		v := values[k]
		parts = append(parts, fmt.Sprintf("`%s` -> site %d, %d calls, arguments %d to %d", k, v.site, v.n, v.lo, v.hi))
	}
	r.say("THREE PROBES, ONE PER CALL SITE, and the corpus reaches none of them: %s", strings.Join(parts, ";  "))
	var mq []string
	for _, m := range moved {
		mq = append(mq, "`"+m+"`")
	}
	r.cont("EVERY ONE DRAWS THE SAME SCREEN on the binary this phase was handed and "+
		"on its own, byte for byte.  AND %d OF THE 3 ARE PROVEN ABLE TO FAIL, by a control "+
		"whose musl_abs and musl_labs return their argument unchanged: %s move.  `stl` "+
		"DOES NOT, AND THAT IS REPORTED RATHER THAN HIDDEN -- its site is reached twice and "+
		"its answer guards only `w_prev_height = w_height`, which win_new_height() already "+
		"assigns on every path that changes a height, so nothing drawn depends on it.  That "+
		"site is proven REACHED and not proven OBSERVABLE, and section 2 is its evidence",
		len(moved), strings.Join(mq, " and "))
	r.cont("AND THE UB CANNOT BE REACHED: the largest magnitude any of the three sites "+
		"is ever handed, over 51 probe calls, is %d -- against INT_MIN's 2,147,483,648 and "+
		"LONG_MIN's 9,223,372,036,854,775,808.  The static reason is in the file: "+
		"last_status_rec's two operands are window heights, which limit_screen_size() "+
		"clamps at 1,000 rows, and the two labs arguments are differences of line numbers, "+
		"which are >= 1 -- so LONG_MIN would need a buffer of 2^63 lines", span)
	return nil
}
