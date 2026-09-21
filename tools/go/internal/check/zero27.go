package check

import (
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

	"slimvim.local/tools/internal/harness"
)

func init() { register("zero27", Zero27) }

var (
	z27Inc     = regexp.MustCompile(`^ *# *include `)
	z27Hash    = regexp.MustCompile(`^ *#`)
	z27EnumP   = regexp.MustCompile(`^enum \{ ([A-Z][A-Z0-9_]*) = (.+) \};$`)
	z27EnumT   = regexp.MustCompile(`^    (?:int|long|long long|unsigned long long|usize) \{ ([A-Z][A-Z0-9_]*) = (.+) \};$`)
	z27Defn    = regexp.MustCompile(`^([A-Za-z_]\w*)\s*\(`)
	z27Word    = regexp.MustCompile(`\b[A-Za-z_]\w*\b`)
	z27Err     = regexp.MustCompile(`(?m)^[^ ].*:\d+:\d+: error:.*$`)
	z27Undef   = regexp.MustCompile(`'(\w+)' used but never defined`)
	z27CFlags  = regexp.MustCompile(`(?m)^CFLAGS  *= *(.*)$`)
	z27LDFlags = regexp.MustCompile(`(?m)^LDFLAGS  *= *(.*)$`)
	// THE THIRD BACKREFERENCE IN THIS HALF, and it is the capture-and-compare
	// kind rather than the scanner kind.  The heredoc writes
	// `^static_assert\((.+) == ([A-Z][A-Z0-9_]*), "\2"\);$`, where `\2`
	// requires the quoted name to be the name compared against.  RE2 has none,
	// so the quoted name is captured too and the two are compared.  Exact for
	// these lines, which the edit generates: `(.+)` is greedy and backtracks to
	// the LAST ` == `, and the name that follows it is the name in quotes.
	z27Assert = regexp.MustCompile(`(?m)^static_assert\((.+) == ([A-Z][A-Z0-9_]*), "([A-Z][A-Z0-9_]*)"\);$`)
)

// z27Want is the twelve, in the order the report prints them.
var z27Want = strings.Fields("INT_MAX INT_MIN LONG_MAX LONG_MIN LLONG_MAX LLONG_MIN " +
	"ULLONG_MAX SIZE_MAX PATH_MAX EXIT_FAILURE SIGHUP SIGTERM")

// z27Declared is the boundary this phase declares: thirteen names, every one
// `used but never defined` in the cut.
var z27Declared = strings.Fields("host_exit host_message musl_delay musl_get_winsize " +
	"musl_gettimeofday musl_host_init musl_read_input musl_suspend musl_term_start " +
	"musl_term_stop musl_tty_keys musl_wait_for_input vim_snprintf")

var z27Protos = []string{
	"void *malloc(usize n);", "void *realloc(void *p, usize n);",
	"void free(void *p);", "long time(long *tp);", "int getpid(void);",
	"int kill(int pid, int sig);", "long write(int fd, const void *buf, usize n);",
	"long labs(long n);", "int abs(int n);",
}

// z27Cut is the deliverable's own rule: every line up to the first `#include`,
// with trailing blanks dropped.  QUOTE IT ENTIRE OR NOT AT ALL -- the naive
// prefix gives one line more on the same text, and a figure that differs by one
// from its neighbour's is an off-by-one in neither phase.
func z27Cut(lines []string) []string {
	var o []string
	for _, l := range lines {
		if z27Inc.MatchString(l) {
			break
		}
		o = append(o, l)
	}
	for len(o) > 0 && o[len(o)-1] == "" {
		o = o[:len(o)-1]
	}
	return o
}

type z27Const struct{ init, line string }

// z27ReadConstants reads the enumerators and the asserts OUT OF THE TEXT.
// Neither list is written down: the phase's claim is that each assert's
// left-hand side IS its enumerator's initialiser, and that equality is the one
// thing no compiler here can check -- under the includes `INT_MAX` is
// <limits.h>'s MACRO, so an assert can compare the derivation against the
// header and can never name the enumerator the core uses.
func z27ReadConstants(text string) (map[string]z27Const, map[string]string) {
	lines := strings.Split(text, "\n")
	e := map[string]z27Const{}
	a := map[string]string{}
	for i, l := range lines {
		var m []string
		if strings.HasPrefix(l, "enum { ") {
			m = z27EnumP.FindStringSubmatch(l)
		} else if i > 0 && lines[i-1] == "enum :" {
			m = z27EnumT.FindStringSubmatch(l)
		}
		if m != nil {
			if _, ok := e[m[1]]; !ok {
				e[m[1]] = z27Const{m[2], l}
			}
		}
	}
	for _, m := range z27Assert.FindAllStringSubmatch(text, -1) {
		if m[2] == m[3] { // what the `\2` backreference required
			a[m[2]] = m[1]
		}
	}
	return e, a
}

type z27Counter map[string]int

func z27Count(lines []string) z27Counter {
	c := z27Counter{}
	for _, l := range lines {
		c[l]++
	}
	return c
}

// z27Sub is Counter subtraction: only positive counts survive, which is
// Python's `co - cn`.
func z27Sub(a, b z27Counter) z27Counter {
	out := z27Counter{}
	for k, v := range a {
		if d := v - b[k]; d > 0 {
			out[k] = d
		}
	}
	return out
}

func z27Total(c z27Counter) int {
	n := 0
	for _, v := range c {
		n += v
	}
	return n
}

// Zero27 is phase 27's check: the move, the cut and the boundary.
func Zero27(w io.Writer, args []string) error {
	if len(args) != 2 {
		return fmt.Errorf("usage: check zero27 <work-dir> <state-dir>")
	}
	work, state := args[0], args[1]
	f := filepath.Join(work, "zero-vim.c")
	r := &rep{tag: "boundary", w: w}
	stop := func(format string, a ...any) error {
		r.say(format, a...)
		return harness.ErrReported
	}
	fatal := func(head, logPath string, n int) error {
		r.say("%s", head)
		for i, l := range strings.Split(readFile(logPath), "\n") {
			if i >= n {
				break
			}
			fmt.Fprintln(w, l)
		}
		return harness.ErrReported
	}

	beforeLines, err := strconv.Atoi(strings.TrimSpace(readFile(filepath.Join(state, "input-lines"))))
	if err != nil {
		return stop("the state directory holds no usable input-lines")
	}
	tmp, err := os.MkdirTemp("", "zero27-")
	if err != nil {
		return err
	}
	defer os.RemoveAll(tmp)

	mk := readFile(filepath.Join(work, "Makefile"))
	cflags := strings.Fields(z27CFlags.FindStringSubmatch(mk)[1])
	ldflags := strings.Fields(z27LDFlags.FindStringSubmatch(mk)[1])

	var wg sync.WaitGroup
	var errNew error
	wg.Add(1)
	go func() {
		defer wg.Done()
		a := append(append([]string{}, cflags...), ldflags...)
		a = append(a, "-o", filepath.Join(tmp, "new"), f)
		c := exec.Command("gcc", a...)
		c.Env = append(os.Environ(), "SOURCE_DATE_EPOCH=0")
		errNew = c.Run()
	}()

	t := readFile(f)
	L := strings.Split(t, "\n")

	// ---- the seven controls ---------------------------------------------
	var incIdx []int
	for i, l := range L {
		if z27Inc.MatchString(l) {
			incIdx = append(incIdx, i)
		}
	}
	if len(incIdx) == 0 {
		return stop("the output has no `#include` at all, so there is no boundary to cut at")
	}
	first := incIdx[0]

	const td = "typedef typeof(sizeof(0)) usize;"
	if strings.Count(t, td) != 1 {
		return stop("`%s` is not in the output exactly once, so the `#define` control "+
			"has nowhere it belongs", td)
	}

	// A SLICE AND NOT A MAP.  Python's dict keeps insertion order, and these
	// are written in it; ranging a Go map would report a different control
	// each run for the same failure.
	type ctl struct{ name, text string }
	ctls := []ctl{
		// hash -- a `#define` ABOVE THE CUT.  The ordinary build is silent;
		// the cut holds a directive.
		{"hash", strings.Replace(t, td, td+"\n#define ZZ_A_DIRECTIVE 1", 1)},
		// top -- one `#include` back at line 1.  <stddef.h> defines NONE of
		// the twelve, which is what makes the build silent.
		{"top", "#include <stddef.h>\n" + t},
		// limits -- the SAME break with a header that does: the constraint
		// that made this phase and phase 26 separate, measured.
		{"limits", "#include <limits.h>\n" + t},
	}

	// elapsed -- ONE CORE FUNCTION MOVED BELOW THE CUT.  The boundary AS AN
	// ASSERTION: a phase that quietly widened the core -> host interface would
	// move this set and nothing else in the pipeline would say so.
	var dIdx []int
	for i, l := range L {
		if strings.HasPrefix(l, "elapsed(") {
			dIdx = append(dIdx, i)
		}
	}
	if len(dIdx) != 1 || !strings.HasPrefix(L[dIdx[0]-1], "    static ") || dIdx[0] > first {
		return stop("`elapsed` is not defined exactly once above the boundary, so the " +
			"control that moves one core function below it would not be a control")
	}
	s := dIdx[0] - 1
	e := dIdx[0]
	for L[e] != "}" {
		e++
	}
	if L[e+1] != "" {
		return stop("`elapsed` is not followed by a blank line")
	}
	body := append([]string{}, L[s:e+1]...)
	moved := append(append([]string{}, L[:s]...), L[e+2:]...)
	at := -1
	for i, l := range moved {
		if z27Inc.MatchString(l) {
			at = i
		}
	}
	var movedTxt []string
	movedTxt = append(movedTxt, moved[:at+1]...)
	movedTxt = append(movedTxt, "")
	movedTxt = append(movedTxt, body...)
	movedTxt = append(movedTxt, moved[at+1:]...)
	ctls = append(ctls, ctl{"elapsed", strings.Join(movedTxt, "\n")})

	// wrong / vacuous -- A WRONG DERIVATION IS WRONG IN BOTH PLACES, because
	// the edit emits the enumerator and the assert's left-hand side from ONE
	// text.  `vacuous` is the same mistake with the assert written the way a
	// reader would first reach for, where the name below the includes is the
	// MACRO and the comparison is a tautology about the header.
	const eLine = "    int { INT_MAX = (int)(~0u >> 1) };"
	const aLine = `static_assert((int)(~0u >> 1) == INT_MAX, "INT_MAX");`
	for _, x := range []string{eLine, aLine} {
		if strings.Count(t, x) != 1 {
			return stop("`%s` is not in the output exactly once -- the enumerator and "+
				"the assert that checks it are what this phase writes", x)
		}
	}
	wrongT := strings.Replace(t, eLine, "    int { INT_MAX = (int)(~0u >> 2) };", 1)
	ctls = append(ctls,
		ctl{"wrong", strings.Replace(wrongT, aLine,
			`static_assert((int)(~0u >> 2) == INT_MAX, "INT_MAX");`, 1)},
		ctl{"vacuous", strings.Replace(wrongT, aLine,
			`static_assert(INT_MAX == INT_MAX, "INT_MAX");`, 1)})

	// stat -- THE TRAP IN ITS NEW SHAPE.  With the headers below, a `static`
	// prototype for a libc function is no longer an error at the declaration.
	const pMalloc = "void *malloc(usize n);"
	if strings.Count(t, "\n"+pMalloc+"\n") != 1 {
		return stop("the plain prototype `%s` is not on a line of its own exactly once", pMalloc)
	}
	ctls = append(ctls, ctl{"stat",
		strings.Replace(t, "\n"+pMalloc+"\n", "\nstatic "+pMalloc+"\n", 1)})

	for _, c := range ctls {
		if c.text == t {
			return stop("the control %s changed nothing", c.name)
		}
		if err := os.WriteFile(filepath.Join(tmp, c.name+".c"), []byte(c.text), 0o644); err != nil {
			return err
		}
	}
	r.say("seven controls written: hash a `#define` above the cut, top an `#include " +
		"<stddef.h>` back at line 1, limits the same with `<limits.h>`, elapsed one " +
		"core function moved below the cut, wrong one derivation broken, vacuous the " +
		"same break with the assert naming the macro instead of restating the " +
		"derivation, stat the malloc prototype made `static`")

	// The one that must LINK is the slowest; the rest are warning runs.  Those
	// expected to fail have their status discarded, which is the measurement.
	warn := func(name, src string, wall bool) {
		wg.Add(1)
		go func() {
			defer wg.Done()
			a := []string{"-c", "-O0", "-fno-stack-protector"}
			if wall {
				a = append(a, "-Wall", "-Wextra", "-Wno-unused-parameter")
			}
			a = append(a, "-o", "/dev/null", src)
			b, _ := exec.Command("gcc", a...).CombinedOutput()
			os.WriteFile(filepath.Join(tmp, "w."+name), b, 0o644)
		}()
	}
	wg.Add(1)
	go func() {
		defer wg.Done()
		a := append(append([]string{}, cflags...), ldflags...)
		a = append(a, "-o", filepath.Join(tmp, "stat"), filepath.Join(tmp, "stat.c"))
		c := exec.Command("gcc", a...)
		c.Env = append(os.Environ(), "SOURCE_DATE_EPOCH=0")
		b, _ := c.CombinedOutput()
		os.WriteFile(filepath.Join(tmp, "w.stat"), b, 0o644)
	}()
	warn("statw", filepath.Join(tmp, "stat.c"), true)
	warn("hash", filepath.Join(tmp, "hash.c"), true)
	warn("top", filepath.Join(tmp, "top.c"), true)
	warn("elapsed", filepath.Join(tmp, "elapsed.c"), true)
	warn("vacuous", filepath.Join(tmp, "vacuous.c"), true)
	warn("limits", filepath.Join(tmp, "limits.c"), false)
	warn("wrong", filepath.Join(tmp, "wrong.c"), false)
	warn("new", f, true)
	canonC := filepath.Join(tmp, "canon.c")
	os.WriteFile(canonC, []byte(t), 0o644)
	var errCanon error
	wg.Add(1)
	go func() {
		defer wg.Done()
		b, e := exec.Command("sh", "tools/canon.sh", canonC).CombinedOutput()
		errCanon = e
		os.WriteFile(filepath.Join(tmp, "canon.log"), b, 0o644)
	}()

	// ---- 1. the move, the cut and the boundary ---------------------------
	old := readFile(filepath.Join(state, "old.c"))
	N, O := L, strings.Split(old, "\n")
	enums, asserts := z27ReadConstants(t)

	for _, n := range z27Want {
		en, okE := enums[n]
		as, okA := asserts[n]
		switch {
		case !okE:
			r.bad("`%s` has no enumerator of its own in the output, and it is one of "+
				"the twelve the core must declare once the headers are below it", n)
		case !okA:
			r.bad("`%s` has an enumerator and no static_assert, so nothing checks the "+
				"core's number against the header", n)
		case as != en.init:
			r.bad("`%s`'s assert compares `%s` where its enumerator is `%s` -- the two "+
				"must be the SAME TEXT, or the assert is checking something other than "+
				"what the core uses", n, as, en.init)
		}
	}
	want := map[string]bool{}
	for _, n := range z27Want {
		want[n] = true
	}
	var extra []string
	for k := range asserts {
		if !want[k] {
			extra = append(extra, k)
		}
	}
	sort.Strings(extra)
	if len(extra) > 0 {
		r.bad("the output holds static_asserts for %s, which are not among the twelve",
			strings.Join(extra, " "))
	}
	// And that reading is PROVEN ABLE TO FAIL, on the one thing no compiler
	// here can see: the enumerator moved and the assert left behind.
	if en, ok := enums["INT_MAX"]; ok {
		broken := strings.Replace(t, en.line,
			strings.Replace(en.line, "~0u >> 1", "~0u >> 2", 1), 1)
		de, da := z27ReadConstants(broken)
		if da["INT_MAX"] == de["INT_MAX"].init {
			r.bad("with INT_MAX's ENUMERATOR alone changed the reading above still says " +
				"the two texts agree, so it is not checking anything")
		}
	}

	// THE MOVE IS A MOVE.  Every line of the output is a line of the input
	// except the 32 this phase writes, and not one line of the input is
	// missing.  A phase that moved code and altered a character of it on the
	// way could not state this.
	cn, co := z27Count(N), z27Count(O)
	gone := z27Sub(co, cn)
	came := z27Sub(cn, co)
	written := z27Counter{"enum :": 8}
	for _, n := range z27Want {
		en, okE := enums[n]
		as, okA := asserts[n]
		if okE && okA {
			written[fmt.Sprintf("static_assert(%s == %s, %q);", as, n, n)] = 1
			written[en.line] = written[en.line] + 1
		}
	}
	blanks := came[""]
	delete(came, "")
	if len(gone) > 0 {
		r.bad("%d line(s) of the input are not in the output at all, so this is not a "+
			"move: %s", z27Total(gone), z27Show(gone, 3))
	}
	unexpected := z27Counter{}
	for k, v := range came {
		if written[k] != v {
			unexpected[k] = v
		}
	}
	var missing []string
	for k, v := range written {
		if came[k] != v {
			missing = append(missing, k)
		}
	}
	sort.Strings(missing)
	if len(unexpected) > 0 {
		r.bad("the output holds %d line(s) this phase does not write: %s",
			z27Total(unexpected), z27Show(unexpected, 3))
	}
	if len(missing) > 0 {
		var shown []string
		for i, k := range missing {
			if i >= 3 {
				break
			}
			shown = append(shown, z27Repr(k))
		}
		r.bad("%d line(s) this phase writes are not in the output: %s",
			len(missing), strings.Join(shown, " / "))
	}

	if len(O)-1 != beforeLines {
		r.bad("the state directory says the edit was handed %d lines and old.c has %d",
			beforeLines, len(O)-1)
	}
	added := z27Total(written)
	if len(N)-len(O) != added+blanks {
		r.bad("the output is %d lines and the input was %d, a difference of %d where %d "+
			"was expected -- %d written lines and %d blank",
			len(N)-1, len(O)-1, len(N)-len(O), added+blanks, added, blanks)
	}
	if rN, rO := z27Runs(N), z27Runs(O); rN != 0 || rO != 0 {
		r.bad("runs of two blank lines: %d in the input and %d in the output, and "+
			"CLAUDE.md allows none", rO, rN)
	}

	var od, nd []int
	for i, l := range O {
		if z27Hash.MatchString(l) {
			od = append(od, i)
		}
	}
	for i, l := range N {
		if z27Hash.MatchString(l) {
			nd = append(nd, i)
		}
	}
	okOd := len(od) == 11
	for k, i := range od {
		if okOd && i != k {
			okOd = false
		}
	}
	if !okOd {
		r.bad("the input did not have its eleven directives on its first eleven lines")
	}
	okNd := len(nd) == 11
	for k, i := range nd {
		if okNd && i != nd[0]+k {
			okNd = false
		}
	}
	if !okNd {
		var at4 []string
		for i, x := range nd {
			if i >= 4 {
				break
			}
			at4 = append(at4, strconv.Itoa(x+1))
		}
		r.bad("the output does not have eleven directives on eleven consecutive lines: "+
			"%d at %s", len(nd), strings.Join(at4, " "))
	} else {
		ns, os_ := map[string]bool{}, map[string]bool{}
		for _, i := range nd {
			ns[N[i]] = true
		}
		for _, i := range od {
			os_[O[i]] = true
		}
		same := len(ns) == len(os_)
		for k := range ns {
			if !os_[k] {
				same = false
			}
		}
		if !same {
			r.bad("the eleven directives are not the eleven the input had")
		}
	}

	// ---- THE CUT ---------------------------------------------------------
	cutLines := z27CutRaw(N)
	last := len(cutLines)
	for last > 0 && cutLines[last-1] == "" {
		last--
	}
	cut := strings.Join(cutLines[:last], "\n") + "\n"
	os.WriteFile(filepath.Join(tmp, "cut.c"), []byte(cut), 0o644)
	if cut != strings.Join(N[:last], "\n")+"\n" {
		r.bad("the cut is not a PREFIX of the file, which is what makes it extractable " +
			"by `head -n N`")
	}
	if strings.Join(N[:len(cutLines)], "\n")+"\n"+strings.Join(N[len(cutLines):], "\n") != t {
		r.bad("the cut plus the remainder is not the file byte for byte")
	}
	var hashes []int
	for i, l := range strings.Split(cut, "\n") {
		if z27Hash.MatchString(l) {
			hashes = append(hashes, i)
		}
	}
	if len(hashes) > 0 {
		var at4 []string
		for i, x := range hashes {
			if i >= 4 {
				break
			}
			at4 = append(at4, strconv.Itoa(x+1))
		}
		r.bad("PART 1: %d line(s) of the cut begin with a `#`, at %s",
			len(hashes), strings.Join(at4, " "))
	}
	// PART 2, the floor -- the same shape and the same sentence as
	// create_cmdidxs's 80 and orphanopts's 80, to be lowered only in the phase
	// that crosses it.
	const floor = 70000
	if last < floor {
		r.bad("PART 2: the cut is %d lines, below the floor of %d.  A cut that found "+
			"the wrong line would be short rather than wrong, and the floor is what "+
			"says so", last, floor)
	}

	wb, _ := exec.Command("gcc", "-O0", "-fno-stack-protector", "-Wall", "-Wextra",
		"-Wno-unused-parameter", "-fsyntax-only", filepath.Join(tmp, "cut.c")).CombinedOutput()
	wtxt := string(wb)
	if errs := z27Err.FindAllString(wtxt, -1); len(errs) > 0 {
		if len(errs) > 4 {
			errs = errs[:4]
		}
		r.bad("PART 3: the cut does not compile on its own:\n    %s",
			strings.Join(errs, "\n    "))
	}
	seenSet := map[string]bool{}
	for _, m := range z27Undef.FindAllStringSubmatch(wtxt, -1) {
		seenSet[m[1]] = true
	}
	seen := z27Keys(seenSet)
	var other []string
	for _, l := range strings.Split(wtxt, "\n") {
		if strings.Contains(l, ": warning: ") && !strings.Contains(l, "used but never defined") {
			other = append(other, l)
		}
	}
	if len(other) > 0 {
		r.bad("PART 4: the cut has a warning that is not a boundary name: %s", other[0])
	}

	// THE BOUNDARY, COMPUTED A SECOND WAY.  A name defined below the cut and
	// mentioned above it is a core -> host call, which is what the boundary IS.
	below := map[string]bool{}
	rest := N[len(cutLines):]
	for i := 0; i+1 < len(rest); i++ {
		if m := z27Defn.FindStringSubmatch(rest[i]); m != nil && strings.HasPrefix(rest[i+1], "{") {
			below[m[1]] = true
		}
	}
	aboveWords := map[string]int{}
	for _, x := range z27Word.FindAllString(cut, -1) {
		aboveWords[x]++
	}
	var textual []string
	for n := range below {
		if aboveWords[n] > 0 {
			textual = append(textual, n)
		}
	}
	sort.Strings(textual)
	if strings.Join(seen, "\x00") != strings.Join(textual, "\x00") {
		r.bad("PART 4: gcc says the boundary is %s and the text says it is %s",
			strings.Join(seen, " "), strings.Join(textual, " "))
	}
	decl := append([]string{}, z27Declared...)
	sort.Strings(decl)
	if strings.Join(seen, "\x00") != strings.Join(decl, "\x00") {
		r.bad("PART 4: the boundary is %d names and this phase declares %d.  Now: %s.  "+
			"Declared: %s.  A phase that widens the core -> host interface changes this "+
			"set and nothing else in the pipeline would say so",
			len(seen), len(decl), strings.Join(seen, " "), strings.Join(decl, " "))
	}

	for _, p := range z27Protos {
		if strings.Count(t, "\n"+p+"\n") != 1 {
			r.bad("the prototype `%s` is not on a line of its own exactly once", p)
		}
		if strings.Contains(t, "static "+p) {
			r.bad("the prototype `%s` is `static`, which after the move is a LINK "+
				"failure and not a diagnostic at the line", p)
		}
	}

	if err := r.done(); err != nil {
		return err
	}
	os.WriteFile(filepath.Join(tmp, "boundary.txt"), []byte(strings.Join(seen, "\n")+"\n"), 0o644)
	r.say("THE MOVE IS A MOVE: not one of the input's %d lines is missing from the "+
		"output, and the only lines the output adds are the %d this phase writes -- %d "+
		"enumerator lines for the twelve constants and 12 static_asserts -- plus %d "+
		"blank where an emptied paragraph left two.  %d lines -> %d",
		len(O)-1, added, added-12, blanks, len(O)-1, len(N)-1)
	var shown []string
	for _, n := range z27Want {
		shown = append(shown, fmt.Sprintf("%s = %s", n, enums[n].init))
	}
	r.say("the twelve constants, each an ENUMERATOR above the boundary and a "+
		"static_assert below it whose left-hand side is that enumerator's own "+
		"initialiser, read back out of the output and required equal: %s",
		strings.Join(shown, "  "))
	r.say("PATH_MAX is an ARRAY BOUND, which is why all twelve are enumerators: a " +
		"`static const int` cannot appear in an array bound, a case label or an " +
		"enumerator initialiser")
	r.say("the eleven `#include`s were lines 1-11 and are lines %d-%d, and the cut "+
		"above them is %d lines with 0 directives -- the boundary is the first one and "+
		"nothing else marks it", nd[0]+1, nd[len(nd)-1]+1, last)
	r.say("THE CUT IS A PREFIX (`head -n %d` exactly) and the cut plus the remainder IS "+
		"the file, byte for byte.  It compiles ALONE with `-fsyntax-only`, 0 errors, "+
		"above a floor of %d lines", last, floor)
	r.say("and its WHOLE warning set is the boundary: %d names, every one `used but "+
		"never defined`, and gcc's list is identical to the names DEFINED below the cut "+
		"and MENTIONED above it -- %s", len(seen), strings.Join(seen, " "))

	// ---- 2. the three breaks the ordinary build cannot see ---------------
	wg.Wait()
	if !strings.Contains(readFile(filepath.Join(tmp, "w.limits")),
		"expected identifier before numeric constant") {
		return fatal("with <limits.h> put back at line 1 the enumerator `INT_MAX = "+
			"(int)(~0u >> 1)` should become `0x7fffffff = ...` and the compiler should "+
			"say `expected identifier before numeric constant`.  It did not, so the "+
			"constraint that separates this phase from phase 26 is not what "+
			"ZERO-PLAN.md 4c says it is:", filepath.Join(tmp, "w.limits"), 6)
	}
	r.say("AND THE CONSTRAINT THAT MADE THIS PHASE AND PHASE 26 SEPARATE, MEASURED ON " +
		"THE PRODUCT: with `#include <limits.h>` put back at line 1 the twelve " +
		"enumerators become their own values -- `enum : int { 0x7fffffff = ... };` -- " +
		"and the build stops at that line with `expected identifier before numeric " +
		"constant`.  The constants could not have been written before the move, which " +
		"is why phase 26 left them and this phase has them")
	for _, c := range []string{"hash", "top", "elapsed"} {
		if readFile(filepath.Join(tmp, "w."+c)) != "" {
			return fatal(fmt.Sprintf("the %s control was expected to build in SILENCE "+
				"-- that is the whole point of it -- and did not:", c),
				filepath.Join(tmp, "w."+c), 6)
		}
	}
	if readFile(filepath.Join(tmp, "w.new")) != "" {
		return fatal("the output does not compile silently with -Wall -Wextra:",
			filepath.Join(tmp, "w.new"), 8)
	}

	cutOf := func(path string) []string {
		return z27Cut(strings.Split(readFile(path), "\n"))
	}
	h := []string{}
	for _, l := range cutOf(filepath.Join(tmp, "hash.c")) {
		if z27Hash.MatchString(l) {
			h = append(h, l)
		}
	}
	if len(h) != 1 || !strings.Contains(h[0], "ZZ_A_DIRECTIVE") {
		shown := h
		if len(shown) > 2 {
			shown = shown[:2]
		}
		return stop("the `#define` control did not put exactly one directive above the "+
			"cut, so PART 1 is not proven able to fail: %s", z27ReprList(shown))
	}
	if tp := cutOf(filepath.Join(tmp, "top.c")); len(tp) != 0 {
		return stop("with one `#include` back at line 1 the cut should be EMPTY and is "+
			"%d lines, so PART 2 is not proven able to fail", len(tp))
	}
	os.WriteFile(filepath.Join(tmp, "ecut.c"),
		[]byte(strings.Join(cutOf(filepath.Join(tmp, "elapsed.c")), "\n")+"\n"), 0o644)
	eb, _ := exec.Command("gcc", "-O0", "-fno-stack-protector", "-Wall", "-Wextra",
		"-Wno-unused-parameter", "-fsyntax-only", filepath.Join(tmp, "ecut.c")).CombinedOutput()
	gotSet := map[string]bool{}
	for _, m := range z27Undef.FindAllStringSubmatch(string(eb), -1) {
		gotSet[m[1]] = true
	}
	got := z27Keys(gotSet)
	base := z27Keys(seenSet)
	wantE := append(append([]string{}, base...), "elapsed")
	sort.Strings(wantE)
	if strings.Join(got, "\x00") != strings.Join(wantE, "\x00") {
		return stop("moving ONE core function below the cut should add exactly its name "+
			"to the warning set; it gave %s against %s",
			strings.Join(got, " "), strings.Join(base, " "))
	}
	r.say("THE THREE BREAKS THE ORDINARY BUILD CANNOT SEE, each built both ways and "+
		"each SILENT under -Wall -Wextra: a `#define` above the cut (PART 1 fails, 1 "+
		"directive where the cut allows 0); an `#include` back at line 1 (PART 2 fails, "+
		"the cut is 0 lines); and ONE core function, `elapsed`, moved below the cut, "+
		"which changes the warning set by EXACTLY that name -- %d -> %d.  That last is "+
		"the boundary as an assertion", len(base), len(got))

	// ---- 3. the constants are compiled -----------------------------------
	if !strings.Contains(readFile(filepath.Join(tmp, "w.wrong")), "static assertion failed") {
		return fatal("with INT_MAX's derivation changed to (int)(~0u >> 2) the build "+
			"was expected to fail on the static_assert and did not, so the twelve prove "+
			"nothing:", filepath.Join(tmp, "w.wrong"), 6)
	}
	if readFile(filepath.Join(tmp, "w.vacuous")) != "" {
		return fatal("the vacuous control was expected to be SILENT and was not:",
			filepath.Join(tmp, "w.vacuous"), 6)
	}
	r.say("THE TWELVE ARE IN THE PRODUCT AND THEY ARE COMPILED: INT_MAX's derivation " +
		"changed to `(int)(~0u >> 2)` -- in the enumerator AND in the assert, which is " +
		"what a mistake in the table would really look like -- is `static assertion " +
		"failed` against <limits.h>.  AND THE SHAPE OF THE ASSERT IS MEASURED RATHER " +
		"THAN ARGUED: the SAME wrong enumerator with the assert written " +
		"`static_assert(INT_MAX == INT_MAX, ...)` builds in SILENCE, because below the " +
		"includes that name is <limits.h>'s MACRO and the comparison is a tautology " +
		"about the header.  That is why each assert restates the deriving expression " +
		"-- and why the equality of the two TEXTS is read out of the source in section " +
		"1, which is the only thing that can catch the enumerator drifting away from " +
		"the assert")

	// ---- 4. the `static` trap, in the shape the move gives it ------------
	if errNew != nil {
		return stop("the output did not build with '%s' '%s'",
			strings.Join(cflags, " "), strings.Join(ldflags, " "))
	}
	wStat := readFile(filepath.Join(tmp, "w.stat"))
	if strings.Contains(wStat, "static declaration of 'malloc' follows non-static declaration") {
		return stop("the `static` malloc prototype still gives phase 26's error, which " +
			"means a declaration of malloc is still ABOVE it and the includes did not move")
	}
	if !strings.Contains(wStat, "'malloc' used but never defined") {
		return fatal("the `static` malloc prototype was expected to warn `'malloc' used "+
			"but never defined` and did not:", filepath.Join(tmp, "w.stat"), 6)
	}
	if !strings.Contains(readFile(filepath.Join(tmp, "w.statw")),
		"declared 'static' but never defined [-Wunused-function]") {
		return fatal("under -Wall the `static` malloc prototype was expected to give "+
			"`'malloc' declared 'static' but never defined [-Wunused-function]`, which "+
			"is what the sweep's zero-warning rule catches, and did not:",
			filepath.Join(tmp, "w.statw"), 6)
	}
	if sizeOf(filepath.Join(tmp, "stat")) < 0 {
		return stop("the `static` malloc prototype did not link, which is what the " +
			"brief predicted -- the measurement this check records is that it DOES, so " +
			"either gcc or the brief has changed and the sentence below is wrong")
	}
	if readFile(filepath.Join(tmp, "stat")) != readFile(filepath.Join(tmp, "new")) {
		return stop("the `static` malloc prototype produced a DIFFERENT binary, where " +
			"the measurement is that it produces the same one -- the keyword changes " +
			"the diagnostic and not the code")
	}
	r.say("THE TRAP HAS CHANGED SHAPE AND IT IS WEAKER, WHICH THE BRIEF DID NOT " +
		"PREDICT.  Phase 26 measured a `static` libc prototype as `error: static " +
		"declaration of 'malloc' follows non-static declaration`, which needed " +
		"<stdlib.h> ABOVE it; the brief expected it to become a link failure here.  " +
		"MEASURED: it is neither.  gcc gives <stdlib.h>'s own declaration internal " +
		"linkage as well, warns on THAT line -- `'malloc' declared 'static' but never " +
		"defined [-Wunused-function]` -- links against libc regardless, and produces a " +
		"binary `cmp`-IDENTICAL to the product's.  So the keyword changes the " +
		"diagnostic and not one instruction, and what stands between the core and it is " +
		"the sweep's rule that the build print NOTHING, plus the assertion in section 1 " +
		"that none of the nine is `static`")

	// ---- 5. canon, and the host's vocabulary -----------------------------
	if errCanon != nil {
		return fatal("tools/canon.sh failed on the output:", filepath.Join(tmp, "canon.log"), 10)
	}
	if readFile(canonC) != t {
		r.say("tools/canon.sh is not a no-op on the output -- the twenty enumerator " +
			"lines and the twelve asserts are not written the way this file writes " +
			"everything else:")
		return harness.ErrReported
	}
	r.say("tools/canon.sh is a NO-OP on the output: the eight `enum : T` are on two " +
		"lines, as the file already writes its one existing `enum : long`")
	zh := exec.Command("sh", "tools/st.sh", "zhostonly", f)
	zh.Stdout, zh.Stderr = w, w
	if err := zh.Run(); err != nil {
		return harness.ErrReported
	}

	// ---- 6. the symbols, and the binary ----------------------------------
	obj := func(src, out string) error {
		return exec.Command("gcc", "-c", "-O0", "-fno-stack-protector", "-o", out, src).Run()
	}
	if err := obj(filepath.Join(state, "old.c"), filepath.Join(tmp, "old.o")); err != nil {
		return err
	}
	if err := obj(f, filepath.Join(tmp, "new.o")); err != nil {
		return err
	}
	uOld := nmField26(filepath.Join(tmp, "old.o"), []string{"-u"}, 1)
	uNew := nmField26(filepath.Join(tmp, "new.o"), []string{"-u"}, 1)
	gone2 := minus26(uOld, uNew)
	came2 := minus26(uNew, uOld)
	if len(gone2)+len(came2) > 0 {
		return stop("`nm -u` moved: gone [%s] arrived [%s].  MOVING DEFINITIONS INSIDE "+
			"ONE TRANSLATION UNIT CAN FREE NOTHING AND CAN NEED NOTHING -- a symbol "+
			"leaves when its last caller leaves the FILE, and this phase moves no code "+
			"out of it", strings.Join(gone2, " ")+" ", strings.Join(came2, " ")+" ")
	}
	ext := nmField26(filepath.Join(tmp, "new.o"), []string{"--extern-only", "--defined-only"}, 2)
	if s := strings.Join(ext, " ") + " "; s != "main " {
		return stop("the output defines external symbols other than main: %s", s)
	}
	if readFile(filepath.Join(tmp, "new")) == readFile(filepath.Join(state, "old")) {
		return stop("the output binary is byte-identical to the input's, which cannot " +
			"be: 1,800 lines of definitions moved past the rest, so every address below " +
			"the first of them moves")
	}
	r.say("`nm -u` is THE SAME SET, %d names, as a `comm` empty in BOTH directions, and "+
		"`main` is still the only external symbol.  THE CLAIM OF THIS PHASE IS "+
		"STRUCTURAL AND NOT A SYMBOL COUNT: it moves code inside one translation unit, "+
		"which frees nothing.  The binary is %d bytes against the input's %d, and is "+
		"NOT the same bytes -- there is no `cmp` to be had here and the recording is "+
		"what answers", len(uNew), sizeOf(filepath.Join(tmp, "new")),
		sizeOf(filepath.Join(state, "old")))

	// ---- 7. the recording did not move -----------------------------------
	var wgR sync.WaitGroup
	wgR.Add(2)
	go func() {
		defer wgR.Done()
		exec.Command("sh", "tools/zrecord.sh", filepath.Join(state, "old"),
			filepath.Join(state, "old.c"), filepath.Join(tmp, "REC.old")).Run()
	}()
	go func() {
		defer wgR.Done()
		exec.Command("sh", "tools/zrecord.sh", filepath.Join(tmp, "new"), f,
			filepath.Join(tmp, "REC.new")).Run()
	}()
	wgR.Wait()
	dq, _ := exec.Command("diff", "-rq", filepath.Join(tmp, "REC.old"),
		filepath.Join(tmp, "REC.new")).CombinedOutput()
	if len(dq) > 0 {
		r.say("the declared delta is NOTHING AT ALL and the two recordings differ:")
		return harness.ErrReported
	}
	r.say("the declared delta is NOTHING AT ALL and TWO FULL RECORDINGS ARE " +
		"BYTE-IDENTICAL -- 102 screen cases, every Ex command, every command line, the " +
		"pty scenarios and the terminal table")
	return nil
}

func z27CutRaw(lines []string) []string {
	var o []string
	for _, l := range lines {
		if z27Inc.MatchString(l) {
			break
		}
		o = append(o, l)
	}
	return o
}

func z27Runs(lines []string) int {
	n := 0
	for i := 1; i < len(lines); i++ {
		if lines[i] == "" && lines[i-1] == "" {
			n++
		}
	}
	return n
}

func z27Keys(m map[string]bool) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}

// z27Repr is Python's `repr(k[:60])`.
func z27Repr(k string) string {
	if len(k) > 60 {
		k = k[:60]
	}
	if strings.Contains(k, "'") && !strings.Contains(k, `"`) {
		return `"` + k + `"`
	}
	return "'" + strings.ReplaceAll(k, "'", `\'`) + "'"
}

func z27ReprList(xs []string) string {
	var out []string
	for _, x := range xs {
		out = append(out, z27Repr(x))
	}
	return "[" + strings.Join(out, ", ") + "]"
}

// z27Show lists the first n keys of a counter, in the order a Python dict
// would yield them -- which is INSERTION order and therefore not reproducible
// from a Go map.  Sorted instead, and the difference is stated rather than
// hidden: the set is what the assertion is about and the order is only how it
// is printed.
func z27Show(c z27Counter, n int) string {
	keys := make([]string, 0, len(c))
	for k := range c {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	if len(keys) > n {
		keys = keys[:n]
	}
	var out []string
	for _, k := range keys {
		out = append(out, z27Repr(k))
	}
	return strings.Join(out, " / ")
}
