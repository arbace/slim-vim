package edit

import (
	"bytes"
	"io"
	"os"
	"regexp"
	"strconv"
	"strings"

	"slimvim.local/tools/internal/cutil"
)

func init() { registerArgs("zero26", Zero26) }

var (
	z26Inc   = regexp.MustCompile(`^#include <([A-Za-z0-9_/.]+)>$`)
	z26Names = regexp.MustCompile(`\b(?:time_t|sig_atomic_t|uintptr_t|MIN|MAX|offsetof|gettimeofday)\b|struct timeval\b`)
	z26TV    = regexp.MustCompile(`struct timeval\b`)
	z26TimeT = regexp.MustCompile(`\btime_t\b`)
	z26Off   = regexp.MustCompile(`\boffsetof\b`)
	z26GT    = regexp.MustCompile(`gettimeofday\(&(\(?[A-Za-z_][\w.]*(?:->[\w.]+)?\)?), nullptr\)`)
	z26MM    = regexp.MustCompile(`\b(MIN|MAX)\(`)
)

// Zero26 gives the core the header types and macros it can own: time_t,
// sig_atomic_t, uintptr_t, struct timeval, MIN, MAX and offsetof become the
// core's own and nine libc prototypes are written out, WHILE THE HEADERS ARE
// STILL ABOVE THEM to be cross-checked against.
func Zero26(text []byte, w io.Writer, args []string) ([]byte, error) {
	p := ph{"headers", w}
	if len(args) != 1 {
		return nil, p.die("usage: edit zero26 <file> <minmax.txt>")
	}
	t := text

	lines := bytes.Split(t, []byte{'\n'})
	runsBefore := p.blankRuns(t)

	// ---- 0. the file this edit was written against ----------------------
	// ELEVEN DIRECTIVES, every one an `#include` of a system header, on the
	// first eleven lines -- ZERO-GOAL.md's charter.  This phase adds no
	// directive and moves none: the move is phase 27's, and a phase that
	// quietly did it here would make every cross-check below impossible
	// rather than merely wrong.
	var dIdx []int
	var dLine [][]byte
	for i, l := range lines {
		if bytes.HasPrefix(l, []byte("#")) {
			dIdx = append(dIdx, i)
			dLine = append(dLine, l)
		}
	}
	okFirst := len(dIdx) == 11
	for k, i := range dIdx {
		if okFirst && i != k {
			okFirst = false
		}
	}
	if !okFirst {
		var at []string
		for _, i := range dIdx {
			at = append(at, strconv.Itoa(i))
		}
		return nil, p.die("the file does not have exactly eleven preprocessor directives on its "+
			"first eleven lines: %d directives at lines %s", len(dIdx), strings.Join(at, " "))
	}
	var headers []string
	for _, l := range dLine {
		m := z26Inc.FindSubmatch(l)
		if m == nil {
			return nil, p.die("a directive is not an `#include <...>` of a system header, and no " +
				"phase may add one")
		}
		headers = append(headers, string(m[1]))
	}
	for _, want := range []string{"stdlib.h", "unistd.h", "sys/param.h", "time.h",
		"signal.h", "stdint.h", "stddef.h"} {
		if !containsStr(headers, want) {
			return nil, p.die("<%s> is not among the eleven includes, and it is one of the headers "+
				"this phase replaces: the cross-check it depends on would not happen", want)
		}
	}
	var shown []string
	for _, h := range headers {
		shown = append(shown, "<"+h+">")
	}
	p.sayf("eleven directives, every one an `#include <...>` on the first eleven lines, "+
		"and the seven headers this phase takes from are all among them: %s",
		strings.Join(shown, " "))

	// ---- 1. the host block, which is the other side of the boundary ------
	// The core is everything above it.  Phase 27 puts the eleven includes
	// here; today the line is already exactly where the host block begins,
	// and the counts below are the counts that matter -- a `sig_atomic_t` in
	// the host is not this phase's business and a `sig_atomic_t` in the core
	// is.
	const host = "static volatile sig_atomic_t host_winch_pending"
	var hb []int
	for i, l := range lines {
		if bytes.HasPrefix(l, []byte(host)) {
			hb = append(hb, i)
		}
	}
	if len(hb) != 1 {
		return nil, p.die("the host block does not begin exactly once with %s -- found %d.  "+
			"Without it this phase cannot tell a core mention from a host one",
			cutil.PyRepr(host), len(hb))
	}
	hostAt := hb[0]
	coreT := bytes.Join(lines[11:hostAt], []byte{'\n'})
	hostT := bytes.Join(lines[hostAt:], []byte{'\n'})

	// ---- 2. the inventory, as a partition and not a list -----------------
	// What the core still takes from a header, counted here rather than
	// remembered.  Each number is checked against what the substitution below
	// actually does, so a count that has moved under this phase stops it
	// instead of letting it cut something else.
	for _, x := range []struct {
		name         string
		nCore, nHost int
	}{
		{"time_t", 6, 0}, {"sig_atomic_t", 2, 3}, {"uintptr_t", 1, 0},
		{"size_t", 0, 0}, {"MIN", 7, 0}, {"MAX", 16, 0}, {"offsetof", 9, 0},
	} {
		re := regexp.MustCompile(`\b` + x.name + `\b`)
		gc := len(re.FindAll(coreT, -1))
		gh := len(re.FindAll(hostT, -1))
		if gc != x.nCore || gh != x.nHost {
			return nil, p.die("`%s` occurs %d times in the core and %d in the host block, where "+
				"this phase was written against %d and %d", x.name, gc, gh, x.nCore, x.nHost)
		}
	}
	tvCore := len(z26TV.FindAll(coreT, -1))
	tvHost := len(z26TV.FindAll(hostT, -1))
	if tvCore != 4 || tvHost != 2 {
		return nil, p.die("`struct timeval` occurs %d times in the core and %d in the host block, "+
			"where this phase was written against 4 and 2", tvCore, tvHost)
	}
	p.say("the core takes eight things from a header: time_t 6, sig_atomic_t 2, " +
		"uintptr_t 1, struct timeval 4, MIN 7, MAX 16, offsetof 9 -- and size_t 0, " +
		"phase 23 having taken it.  The host block keeps its own sig_atomic_t 3 and " +
		"struct timeval 2")

	// ---- 3. the literals -------------------------------------------------
	// Phase 23 was caught out by three string literals holding `NULL`.  The
	// lesson is applied rather than assumed: no literal may hold any name
	// this phase substitutes.
	spans, err := literalSpans(p, t)
	if err != nil {
		return nil, err
	}
	var bad []string
	for _, s := range spans {
		if z26Names.Match(t[s[0]:s[1]]) {
			bad = append(bad, string(t[s[0]:s[1]]))
		}
	}
	if len(bad) > 0 {
		return nil, p.die("a literal holds a name this phase substitutes, and no substitution "+
			"below may reach inside a string: %s", strings.Join(bad, " / "))
	}
	p.sayf("%d string and character literals, NONE holding any of the eight names or "+
		"`gettimeofday` -- so every substitution below is over code", len(spans))

	// ---- 4. the nine libc prototypes -------------------------------------
	// PLAIN, NEVER `static`.  A `static` prototype gives the core an internal
	// function that is never defined; here that is `error: static declaration
	// of 'malloc' follows non-static declaration` and after the move it is a
	// link failure.  The check breaks it both ways.
	//
	// Their types are the core's statement of the ABI, and <stdlib.h>,
	// <unistd.h> and <time.h> above them are what makes it a statement that
	// can be wrong out loud.
	const anchor = "typedef typeof(sizeof(0)) usize;\n"
	const block = `
void *malloc(usize n);
void *realloc(void *p, usize n);
void free(void *p);
long time(long *tp);
int getpid(void);
int kill(int pid, int sig);
long write(int fd, const void *buf, usize n);
long labs(long n);
int abs(int n);
`
	if bytes.Count(t, []byte(anchor)) != 1 {
		return nil, p.die("`%s` is not in the file exactly once -- phase 23 put it directly below "+
			"the last `#include` and this phase declares the libc calls beneath it",
			strings.TrimSpace(anchor))
	}
	t = bytes.Replace(t, []byte(anchor), []byte(anchor+block), 1)
	p.say("nine plain prototypes below the usize typedef -- malloc realloc free time " +
		"getpid kill write labs abs -- and NOT ONE of them `static`.  gettimeofday is " +
		"the tenth and is the one that cannot stay: its argument is a struct")

	// ---- 5. time_t -> time_T, and the core owns the width ----------------
	const td = "typedef time_t      time_T;"
	if bytes.Count(t, []byte(td)) != 1 {
		return nil, p.die("`%s` is not in the file exactly once", td)
	}
	t = bytes.Replace(t, []byte(td), []byte("typedef long        time_T;"), 1)
	nTime := len(z26TimeT.FindAll(t, -1))
	t = z26TimeT.ReplaceAll(t, []byte("time_T"))
	if nTime != 5 {
		return nil, p.die("%d further `time_t` were rewritten where 5 were counted", nTime)
	}
	p.sayf("`typedef time_t time_T;` -> `typedef long time_T;` and %d further `time_t` "+
		"-> `time_T`.  `long time(long *)` above is what pins the width against "+
		"<time.h>", nTime)

	// ---- 6. sig_atomic_t -> volatile int, in the core only ---------------
	for _, x := range [][2]string{
		{"static volatile sig_atomic_t full_screen ", "static volatile int full_screen "},
		{"static volatile sig_atomic_t got_int ", "static volatile int got_int "},
	} {
		if bytes.Count(t, []byte(x[0])) != 1 {
			return nil, p.die("`%s` is not in the file exactly once", strings.TrimSpace(x[0]))
		}
		t = bytes.Replace(t, []byte(x[0]), []byte(x[1]), 1)
	}
	p.say("the core's two `volatile sig_atomic_t` objects -- full_screen and got_int " +
		"-- are spelled `volatile int`, and the host block's three are left alone")

	// ---- 7. uintptr_t -> usize -------------------------------------------
	const up = "(unsigned long long)(uintptr_t)p"
	if bytes.Count(t, []byte(up)) != 1 {
		return nil, p.die("`%s` is not in the file exactly once -- it is the one cast that names "+
			"uintptr_t", up)
	}
	t = bytes.Replace(t, []byte(up), []byte("(unsigned long long)(usize)p"), 1)
	p.say("the one `(uintptr_t)` cast, in musl_fmtptr, is `(usize)` -- the same type, " +
		"and the check asserts that with _Generic against <stdint.h>")

	// ---- 8. struct timeval -> a TAGLESS core struct ----------------------
	// TAGLESS IS MANDATORY.  A tag would be the core defining a libc name,
	// and C23 would not even complain about it (measured; see the header of
	// this file), so the layout equality has to be asserted instead -- which
	// the check does, against the header that is still above.
	const tv = "typedef struct timeval elapsed_T;"
	if bytes.Count(t, []byte(tv)) != 1 {
		return nil, p.die("`%s` is not in the file exactly once", tv)
	}
	t = bytes.Replace(t, []byte(tv),
		[]byte("typedef struct {\n    long        tv_sec;\n    long        tv_usec;\n} elapsed_T;"), 1)
	for _, x := range [][2]string{
		{"static long elapsed(struct timeval *start_tv);",
			"static long elapsed(elapsed_T *start_tv);"},
		{"elapsed(struct timeval *start_tv)\n{", "elapsed(elapsed_T *start_tv)\n{"},
		{"    struct timeval  now_tv;", "    elapsed_T       now_tv;"},
	} {
		if bytes.Count(t, []byte(x[0])) != 1 {
			return nil, p.die("`%s` is not in the file exactly once",
				strings.ReplaceAll(x[0], "\n", "\\n"))
		}
		t = bytes.Replace(t, []byte(x[0]), []byte(x[1]), 1)
	}

	locs := z26GT.FindAllSubmatchIndex(t, -1)
	nGt := len(locs)
	if nGt != 5 {
		return nil, p.die("%d `gettimeofday(&X, nullptr)` calls were rewritten where 5 were "+
			"counted", nGt)
	}
	var out []byte
	last := 0
	for _, m := range locs {
		e := string(t[m[2]:m[3]])
		if strings.HasPrefix(e, "(") && strings.HasSuffix(e, ")") {
			e = e[1 : len(e)-1]
		}
		out = append(out, t[last:m[0]]...)
		out = append(out, "musl_gettimeofday(&"+e+".tv_sec, &"+e+".tv_usec)"...)
		last = m[1]
	}
	t = append(out, t[last:]...)

	const proto = "static void musl_delay(long ms, int interruptible);\n"
	if bytes.Count(t, []byte(proto)) != 1 {
		return nil, p.die("musl_delay's prototype is not in the file exactly once, so the new one " +
			"has nowhere it belongs")
	}
	t = bytes.Replace(t, []byte(proto),
		[]byte("static void musl_gettimeofday(long *sec, long *usec);\n"+proto), 1)
	const def = "    static void\nmusl_delay(long ms, int interruptible)\n"
	if bytes.Count(t, []byte(def)) != 1 {
		return nil, p.die("musl_delay's definition is not in the file exactly once")
	}
	t = bytes.Replace(t, []byte(def), []byte(`    static void
musl_gettimeofday(long *sec, long *usec)
{
    struct timeval tv;

    gettimeofday(&tv, nullptr);
    *sec = tv.tv_sec;
    *usec = tv.tv_usec;
}

`+def), 1)
	p.sayf("`elapsed_T` is the core's own TAGLESS `struct { long tv_sec; long tv_usec; "+
		"}`, the three other `struct timeval` in the core are it, and the %d "+
		"`gettimeofday(&X, nullptr)` calls go through `musl_gettimeofday(long *, long "+
		"*)` -- defined in the host block above musl_delay, which is inside the region "+
		"zhostonly reads", nGt)

	// ---- 9. offsetof -> __builtin_offsetof -------------------------------
	// ZERO-PLAN.md 4c settled this.  The plain-C alternative
	// `(usize)&(((T *)0)->m)` was measured to compile, to run, and to
	// static_assert equal to libc's offsetof -- but `-Wpedantic` says it is
	// not an integer constant expression, so it could never be an enumerator.
	// None of these nine needs to be one, so it stays a real option and not a
	// reason to change: one gcc extension in one construct is cheaper to
	// explain than a UB-by-the-letter idiom in nine places.
	nOff := len(z26Off.FindAll(t, -1))
	t = z26Off.ReplaceAll(t, []byte("__builtin_offsetof"))
	if nOff != 9 {
		return nil, p.die("%d `offsetof` were rewritten where 9 were counted", nOff)
	}
	p.sayf("%d `offsetof` -> `__builtin_offsetof`, which is what <stddef.h> expands it "+
		"to here.  The check asserts the two are equal at all six types", nOff)

	// ---- 10. MIN and MAX, expanded to the text the header gives ----------
	probe, err := os.ReadFile(args[0])
	if err != nil {
		return nil, p.die("the preprocessed probe could not be read: %v", err)
	}
	tmpl := map[string]string{}
	for _, raw := range strings.Split(string(probe), "\n") {
		line := strings.TrimSpace(raw)
		if line == "" {
			continue
		}
		if !strings.Contains(line, "ZZA") || !strings.Contains(line, "ZZB") {
			return nil, p.die("the preprocessed probe line %s does not mention both arguments -- "+
				"the expansion could not be turned into a template", cutil.PyRepr(line))
		}
		if strings.Contains(line, "<") {
			tmpl["MIN"] = line
		} else {
			tmpl["MAX"] = line
		}
	}
	if len(tmpl) != 2 || tmpl["MIN"] == "" || tmpl["MAX"] == "" {
		return nil, p.die("the preprocessed probe gave %d templates and not one for MIN and one "+
			"for MAX", len(tmpl))
	}

	// minmax_lines is counted BEFORE the expansion, because expanding moves
	// every offset after the first act.
	seen := map[int]bool{}
	for _, m := range z26MM.FindAllIndex(t, -1) {
		seen[bytes.Count(t[:m[0]], []byte{'\n'})] = true
	}
	minmaxLines := len(seen)

	nMin, nMax := 0, 0
	for {
		m := z26MM.FindSubmatchIndex(t)
		if m == nil {
			break
		}
		which := string(t[m[2]:m[3]])
		lineNo := bytes.Count(t[:m[0]], []byte{'\n'}) + 1
		i := m[1] - 1
		d, j := 0, i
		found := false
		for j < len(t) {
			if t[j] == '(' {
				d++
			} else if t[j] == ')' {
				d--
				if d == 0 {
					found = true
					break
				}
			}
			j++
		}
		if !found {
			return nil, p.die("an unbalanced `%s(` at line %d", which, lineNo)
		}
		inner := string(t[i+1 : j])
		d, k := 0, -1
		for x := 0; x < len(inner); x++ {
			switch inner[x] {
			case '(':
				d++
			case ')':
				d--
			case ',':
				if d == 0 {
					k = x
				}
			}
			if k >= 0 {
				break
			}
		}
		if k < 0 {
			return nil, p.die("`%s(%s)` at line %d has no top-level comma, so it is not the "+
				"two-argument macro this phase expands", which, inner, lineNo)
		}
		a := strings.TrimSpace(inner[:k])
		b := strings.TrimSpace(inner[k+1:])
		if strings.Contains(inner, "\n") {
			return nil, p.die("a `%s(` at line %d spans a line break, which this file does not do "+
				"(CLAUDE.md) and this expansion could not keep", which, lineNo)
		}
		rep := strings.ReplaceAll(strings.ReplaceAll(tmpl[which], "ZZA", a), "ZZB", b)
		nt := append([]byte(nil), t[:m[0]]...)
		nt = append(nt, rep...)
		t = append(nt, t[j+1:]...)
		if which == "MIN" {
			nMin++
		} else {
			nMax++
		}
	}
	if nMin != 7 || nMax != 16 {
		return nil, p.die("%d MIN and %d MAX were expanded where 7 and 16 were counted", nMin, nMax)
	}
	p.sayf("%d MIN and %d MAX on %d lines expanded to the header's own text -- %s and "+
		"%s, read back through the preprocessor and not written into this program",
		nMin, nMax, minmaxLines, tmpl["MIN"], tmpl["MAX"])

	// ---- 11. what the file is now ----------------------------------------
	L := bytes.Split(t, []byte{'\n'})
	const added = 10 + 3 + 1 + 10
	if len(L) != len(lines)+added {
		return nil, p.die("the file is %d lines and the input was %d -- this phase adds exactly "+
			"%d: 10 for the prototype block, 3 for the tagless struct, 1 for "+
			"musl_gettimeofday's prototype and 10 for its definition",
			len(L)-1, len(lines)-1, added)
	}
	var host2 []int
	for i, l := range L {
		if bytes.HasPrefix(l, []byte(host)) {
			host2 = append(host2, i)
		}
	}
	if len(host2) != 1 {
		return nil, p.die("the host block no longer begins exactly once with %s", cutil.PyRepr(host))
	}
	ncore := bytes.Join(L[11:host2[0]], []byte{'\n'})
	nhost := bytes.Join(L[host2[0]:], []byte{'\n'})
	for _, name := range []string{"time_t", "sig_atomic_t", "uintptr_t", "size_t",
		"MIN", "MAX", "offsetof"} {
		n := len(regexp.MustCompile(`\b`+name+`\b`).FindAll(ncore, -1))
		if n > 0 {
			return nil, p.die("`%s` still occurs %d times in the core", name, n)
		}
	}
	if z26TV.Match(ncore) {
		return nil, p.die("`struct timeval` still occurs in the core")
	}
	if len(regexp.MustCompile(`\bsig_atomic_t\b`).FindAll(nhost, -1)) != 3 {
		return nil, p.die("the host block no longer has its three `sig_atomic_t`")
	}
	if k := len(z26TV.FindAll(nhost, -1)); k != 3 {
		return nil, p.die("the host block should have three `struct timeval` -- its two and "+
			"musl_gettimeofday's -- and has %d", k)
	}
	nd := 0
	for _, l := range L {
		if bytes.HasPrefix(l, []byte("#")) {
			nd++
		}
	}
	if nd != 11 {
		return nil, p.die("the file no longer has exactly eleven directives")
	}
	if k := p.blankRuns(t); k != runsBefore {
		return nil, p.die("the edit left %d runs of two blank lines where there were %d",
			k, runsBefore)
	}
	p.say("the core is clean: size_t, time_t, sig_atomic_t, uintptr_t, struct timeval, " +
		"MIN, MAX and offsetof are ALL at 0 above the host block, the eleven directives " +
		"are where they were, and the only header-supplied names left are the twelve " +
		"constants phase 27 takes with the move")
	return t, nil
}
