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

func init() { register("zero26", Zero26) }

const z26Host = "static volatile sig_atomic_t host_winch_pending"

var (
	z26CFlags  = regexp.MustCompile(`(?m)^CFLAGS  *= *(.*)$`)
	z26LDFlags = regexp.MustCompile(`(?m)^LDFLAGS  *= *(.*)$`)
	// THE SECOND BACKREFERENCE IN THIS FILE, and unlike the MIN/MAX one it
	// does not need a scanner.  The heredoc writes
	// `musl_gettimeofday\(&([\w.]+)\.tv_sec, &\1\.tv_usec\)`, where `\1`
	// requires the two names to be the same expression.  RE2 has no
	// backreference and rejects `\1` at COMPILE time -- which in a package
	// -level MustCompile is a panic at init, taking down every check in the
	// package and not only this one.  Measured: `tools/st.sh check` panicked
	// before printing its usage.
	//
	// So both names are captured and compared instead.  That is exact here
	// rather than merely close: `[\w.]+` is greedy on both sides and the text
	// it matches is `&start_tv.tv_sec, &start_tv.tv_usec`, so the two groups
	// take the same extent whenever Python's backtracking would have made them
	// equal.  A pair that differ are skipped, which is what Python's failure
	// to match does.
	z26Call    = regexp.MustCompile(`musl_gettimeofday\(&([\w.]+)\.tv_sec, &([\w.]+)\.tv_usec\)`)
	z26MinMax  = regexp.MustCompile(`\b(MIN|MAX)\(`)
	z26TV      = regexp.MustCompile(`struct timeval\b`)
	z26ScrName = regexp.MustCompile(`.*screen/([A-Za-z0-9_]*) .*`)
)

// z26Protos are the nine the core declares, and NOT ONE of them may be
// `static`: gcc would give libc's own declaration internal linkage to match,
// warn `'malloc' declared 'static' but never defined`, link anyway, and the
// sweep's rule that the build print NOTHING is what stands between the core
// and that.
var z26Protos = []string{
	"void *malloc(usize n);", "void *realloc(void *p, usize n);",
	"void free(void *p);", "long time(long *tp);", "int getpid(void);",
	"int kill(int pid, int sig);", "long write(int fd, const void *buf, usize n);",
	"long labs(long n);", "int abs(int n);",
}

// ---- the template matcher, which is this port's one piece of new machinery --
//
// The heredoc counts the MIN/MAX expansion with a Python BACKREFERENCE:
//
//	pat = re.escape(tmpl).replace('ZZA', '(?P<a>.+?)', 1)...
//	pat = pat.replace('ZZA', '(?P=a)')...
//
// so the repeated argument must really repeat -- which is what a macro does
// and what a hand-written "expansion" gets wrong.  RE2 has no backreference,
// and this is one of the twenty uses tools/README.md counted.  So it is a
// scanner, and it reproduces Python's semantics exactly rather than
// approximating them: `.+?` is one or more characters, NOT newline, minimal
// first with backtracking, and `re.findall` takes the leftmost match and
// resumes after it.

type z26Seg struct{ lit, ph string }

func z26Parse(tmpl string) []z26Seg {
	var segs []z26Seg
	cur := ""
	for i := 0; i < len(tmpl); {
		if strings.HasPrefix(tmpl[i:], "ZZA") || strings.HasPrefix(tmpl[i:], "ZZB") {
			if cur != "" {
				segs = append(segs, z26Seg{lit: cur})
				cur = ""
			}
			segs = append(segs, z26Seg{ph: tmpl[i : i+3]})
			i += 3
			continue
		}
		cur += string(tmpl[i])
		i++
	}
	if cur != "" {
		segs = append(segs, z26Seg{lit: cur})
	}
	return segs
}

func z26MatchAt(text string, pos int, segs []z26Seg, bound map[string]string) int {
	if len(segs) == 0 {
		return pos
	}
	s := segs[0]
	if s.ph == "" {
		if !strings.HasPrefix(text[pos:], s.lit) {
			return -1
		}
		return z26MatchAt(text, pos+len(s.lit), segs[1:], bound)
	}
	if v, ok := bound[s.ph]; ok {
		if !strings.HasPrefix(text[pos:], v) {
			return -1
		}
		return z26MatchAt(text, pos+len(v), segs[1:], bound)
	}
	for n := 1; pos+n <= len(text); n++ {
		if text[pos+n-1] == '\n' { // `.` does not match a newline
			break
		}
		bound[s.ph] = text[pos : pos+n]
		if e := z26MatchAt(text, pos+n, segs[1:], bound); e >= 0 {
			return e
		}
	}
	delete(bound, s.ph)
	return -1
}

func z26Count(text, tmpl string) int {
	segs := z26Parse(tmpl)
	n, i := 0, 0
	for i < len(text) {
		if e := z26MatchAt(text, i, segs, map[string]string{}); e > i {
			n++
			i = e
		} else {
			i++
		}
	}
	return n
}

// Zero26 is phase 26's check: the header types and macros the core can own,
// asserted WHILE THE HEADERS ARE STILL ABOVE THEM to be cross-checked against.
func Zero26(w io.Writer, args []string) error {
	if len(args) != 2 {
		return fmt.Errorf("usage: check zero26 <work-dir> <state-dir>")
	}
	work, state := args[0], args[1]
	f := filepath.Join(work, "zero-vim.c")
	r := &rep{tag: "headers", w: w}
	stop := func(format string, a ...any) error {
		r.say(format, a...)
		return harness.ErrReported
	}
	fatal := func(head string, logPath string, n int) error {
		r.say("%s", head)
		lines := strings.Split(readFile(logPath), "\n")
		for i, l := range lines {
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
	tmp, err := os.MkdirTemp("", "zero26-")
	if err != nil {
		return err
	}
	defer os.RemoveAll(tmp)

	mk := readFile(filepath.Join(work, "Makefile"))
	cflags := strings.Fields(z26CFlags.FindStringSubmatch(mk)[1])
	ldflags := strings.Fields(z26LDFlags.FindStringSubmatch(mk)[1])
	link := func(src, out string) *exec.Cmd {
		a := append(append([]string{}, cflags...), ldflags...)
		a = append(a, "-o", out, src)
		c := exec.Command("gcc", a...)
		c.Env = append(os.Environ(), "SOURCE_DATE_EPOCH=0")
		return c
	}

	var wg sync.WaitGroup
	var errNew error
	wg.Add(1)
	go func() { defer wg.Done(); errNew = link(f, filepath.Join(tmp, "new")).Run() }()

	t := readFile(f)

	// ---- the eight controls ----------------------------------------------
	// r0 -- THE CLOCK ALONE REVERTED.  If its binary is the binary the phase
	// was handed, the six renames, the macro expansions and the nine
	// prototypes generate not one different instruction.
	r0 := t
	const z26Struct = "typedef struct {\n    long        tv_sec;\n    long        tv_usec;\n} elapsed_T;"
	if strings.Count(r0, z26Struct) != 1 {
		return stop("the tagless elapsed_T is not in the output exactly once")
	}
	r0 = strings.Replace(r0, z26Struct, "typedef struct timeval elapsed_T;", 1)
	for _, ab := range [][2]string{
		{"static long elapsed(elapsed_T *start_tv);", "static long elapsed(struct timeval *start_tv);"},
		{"elapsed(elapsed_T *start_tv)\n{", "elapsed(struct timeval *start_tv)\n{"},
		{"    elapsed_T       now_tv;", "    struct timeval  now_tv;"},
		{"static void musl_gettimeofday(long *sec, long *usec);\n", ""},
		{`    static void
musl_gettimeofday(long *sec, long *usec)
{
    struct timeval tv;

    gettimeofday(&tv, nullptr);
    *sec = tv.tv_sec;
    *usec = tv.tv_usec;
}

`, ""},
	} {
		if strings.Count(r0, ab[0]) != 1 {
			shown := strings.ReplaceAll(ab[0], "\n", "\\n")
			if len(shown) > 60 {
				shown = shown[:60]
			}
			return stop("`%s` is not in the output exactly once, so the clock cannot be "+
				"reverted and the equality below would not be one", shown)
		}
		r0 = strings.Replace(r0, ab[0], ab[1], 1)
	}
	nRev := 0
	r0 = z26Call.ReplaceAllStringFunc(r0, func(m string) string {
		g := z26Call.FindStringSubmatch(m)
		if g[1] != g[2] { // what the backreference refused
			return m
		}
		nRev++
		return "gettimeofday(&(" + g[1] + "), nullptr)"
	})
	if nRev != 5 {
		return stop("%d musl_gettimeofday call sites were reverted where 5 were expected", nRev)
	}

	// x0 -- THE POSITIVE CROSS-CHECK, and the thing the move destroys.
	const z26Asserts = `
static_assert(sizeof(elapsed_T) == sizeof(struct timeval), "elapsed_T size");
static_assert(__builtin_offsetof(elapsed_T, tv_sec) == __builtin_offsetof(struct timeval, tv_sec), "tv_sec");
static_assert(__builtin_offsetof(elapsed_T, tv_usec) == __builtin_offsetof(struct timeval, tv_usec), "tv_usec");
static_assert(sizeof(((elapsed_T *)0)->tv_sec) == sizeof(((struct timeval *)0)->tv_sec), "tv_sec width");
static_assert(sizeof(((elapsed_T *)0)->tv_usec) == sizeof(((struct timeval *)0)->tv_usec), "tv_usec width");
static_assert(_Generic((usize)0, uintptr_t: 1, default: 0), "uintptr_t");
static_assert(_Generic((usize)0, size_t: 1, default: 0), "size_t");
static_assert(_Generic((time_T)0, time_t: 1, default: 0), "time_T");
static_assert(_Generic((int)0, sig_atomic_t: 1, default: 0), "sig_atomic_t");
static_assert(_Generic(time, long (*)(long *): 1, default: 0), "time");
static_assert(__builtin_offsetof(buffblock_T, b_str) == offsetof(buffblock_T, b_str), "buffblock_T");
static_assert(__builtin_offsetof(hlname_T, hn_key) == offsetof(hlname_T, hn_key), "hlname_T");
static_assert(__builtin_offsetof(DATA_BL, db_index) == offsetof(DATA_BL, db_index), "DATA_BL");
static_assert(__builtin_offsetof(PTR_BL, pb_pointer) == offsetof(PTR_BL, pb_pointer), "PTR_BL");
static_assert(__builtin_offsetof(msgchunk_T, sb_text) == offsetof(msgchunk_T, sb_text), "msgchunk_T");
static_assert(__builtin_offsetof(bt_regprog_T, program) == offsetof(bt_regprog_T, program), "bt_regprog_T");
`
	x0 := t + z26Asserts
	x0bad := t + strings.Replace(z26Asserts,
		"__builtin_offsetof(elapsed_T, tv_usec) == __builtin_offsetof(struct timeval, tv_usec)",
		"__builtin_offsetof(elapsed_T, tv_usec) == __builtin_offsetof(struct timeval, tv_sec)", 1)

	// m1..m4 -- THE NEGATIVE HALF.  Each is one declaration this phase writes,
	// written wrong, and each is caught by the header still above it.
	mis := []struct{ name, old, new, want, what string }{
		{"m1", "long time(long *tp);", "int time(int *tp);",
			"conflicting types for 'time'", "long time(long *tp) written int time(int *tp)"},
		{"m2", "void *malloc(usize n);", "void *malloc(int n);",
			"conflicting types for 'malloc'", "void *malloc(usize n) written void *malloc(int n)"},
		{"m3", "int getpid(void);", "long getpid(void);",
			"conflicting types for 'getpid'", "int getpid(void) written long getpid(void)"},
		{"m4", "void *malloc(usize n);", "static void *malloc(usize n);",
			"static declaration of 'malloc' follows non-static declaration",
			"the malloc prototype made static -- THE TRAP"},
	}
	files := map[string]string{"r0": r0, "x0": x0, "x0bad": x0bad}
	for _, m := range mis {
		if strings.Count(t, m.old) != 1 {
			return stop("`%s` is not in the output exactly once, so %s would not be a "+
				"control", m.old, m.name)
		}
		files[m.name] = strings.Replace(t, m.old, m.new, 1)
	}
	const sw = "    *sec = tv.tv_sec;\n    *usec = tv.tv_usec;"
	if strings.Count(t, sw) != 1 {
		return stop("musl_gettimeofday does not assign its two outputs exactly once")
	}
	files["swap"] = strings.Replace(t, sw, "    *sec = tv.tv_usec;\n    *usec = tv.tv_sec;", 1)

	// Written in a FIXED order: ranging a Go map would vary it, and a control
	// that failed to be written would be reported about a different name each
	// run.
	names := make([]string, 0, len(files))
	for k := range files {
		names = append(names, k)
	}
	sort.Strings(names)
	for _, name := range names {
		if files[name] == t {
			return stop("%s changed nothing", name)
		}
		if err := os.WriteFile(filepath.Join(tmp, name+".c"), []byte(files[name]), 0o644); err != nil {
			return err
		}
	}
	// tag -- the eleven includes and nothing else.  A probe and not a whole
	// file, because the point is the dialect and the whole file does not
	// compile under -std=c11 (phase 23's `typeof`).
	inc := strings.Join(strings.Split(t, "\n")[:11], "\n")
	os.WriteFile(filepath.Join(tmp, "tag.c"),
		[]byte(inc+"\ntypedef struct timeval { long tv_sec; long tv_usec; } elapsed_T;\n"), 0o644)
	r.say("eight controls written: r0 the clock alone reverted, x0 sixteen " +
		"static_asserts against the headers, x0bad one of them wrong, m1 m2 m3 m4 the " +
		"four mismatched declarations, swap musl_gettimeofday writing its two fields " +
		"the wrong way round, tag the struct with a tag")

	// r0 and swap are full static links and the slowest; the rest are warning
	// runs.  The ones EXPECTED to fail have their status discarded, which is
	// the measurement and not an oversight.
	var errR0, errSwap error
	wg.Add(2)
	go func() { defer wg.Done(); errR0 = link(filepath.Join(tmp, "r0.c"), filepath.Join(tmp, "r0")).Run() }()
	go func() {
		defer wg.Done()
		errSwap = link(filepath.Join(tmp, "swap.c"), filepath.Join(tmp, "swap")).Run()
	}()
	// x0's STATUS is kept and the rest are discarded, and the difference is
	// in the report: the shell says "did not compile" when `wait $pid_x0`
	// fails and "compiled but were not silent" when the log is non-empty.
	// Collapsing the two loses a distinction a reader needs -- a control that
	// cannot build is a different fault from one that builds and warns.
	var errX0 error
	syn := func(name string, extra ...string) {
		wg.Add(1)
		go func() {
			defer wg.Done()
			a := append([]string{"-O0", "-fno-stack-protector"}, extra...)
			a = append(a, "-fsyntax-only", filepath.Join(tmp, name+".c"))
			c := exec.Command("gcc", a...)
			b, e := c.CombinedOutput()
			if name == "x0" {
				errX0 = e
			}
			os.WriteFile(filepath.Join(tmp, "w."+name), b, 0o644)
		}()
	}
	syn("x0", "-Wall", "-Wextra", "-Wno-unused-parameter")
	syn("x0bad")
	for _, m := range mis {
		syn(m.name)
	}
	tagRun := func(out string, std ...string) {
		wg.Add(1)
		go func() {
			defer wg.Done()
			a := append(append([]string{}, std...), "-fsyntax-only", filepath.Join(tmp, "tag.c"))
			c := exec.Command("gcc", a...)
			b, _ := c.CombinedOutput()
			os.WriteFile(filepath.Join(tmp, out), b, 0o644)
		}()
	}
	tagRun("w.tag23")
	tagRun("w.tagc11", "-std=c11")
	tagRun("w.tagc17", "-std=c17")
	canonC := filepath.Join(tmp, "canon.c")
	os.WriteFile(canonC, []byte(t), 0o644)
	var errCanon error
	wg.Add(1)
	go func() {
		defer wg.Done()
		c := exec.Command("sh", "tools/canon.sh", canonC)
		b, e := c.CombinedOutput()
		errCanon = e
		os.WriteFile(filepath.Join(tmp, "canon.log"), b, 0o644)
	}()

	// ---- 1. the source, as arithmetic on the input -----------------------
	old := readFile(filepath.Join(state, "old.c"))
	split := func(text string) (string, string, []string, error) {
		lines := strings.Split(text, "\n")
		var hb []int
		for i, l := range lines {
			if strings.HasPrefix(l, z26Host) {
				hb = append(hb, i)
			}
		}
		if len(hb) != 1 {
			return "", "", nil, stop("the host block does not begin exactly once with "+
				"%s -- found %d.  Every count below distinguishes the core from the "+
				"host and without the line there is nothing to distinguish",
				pyRepr26(z26Host), len(hb))
		}
		return strings.Join(lines[11:hb[0]], "\n"), strings.Join(lines[hb[0]:], "\n"), lines, nil
	}
	ocore, ohost, olines, e := split(old)
	if e != nil {
		return e
	}
	ncore, nhost, nlines, e := split(t)
	if e != nil {
		return e
	}
	count := func(s, pat string) int {
		return len(regexp.MustCompile(pat).FindAllString(s, -1))
	}

	if len(olines)-1 != beforeLines {
		r.bad("the state directory says the edit was handed %d lines and old.c has %d",
			beforeLines, len(olines)-1)
	}
	for _, x := range []struct {
		name   string
		inHost int
	}{
		{"time_t", 0}, {"sig_atomic_t", 3}, {"uintptr_t", 0},
		{"size_t", 0}, {"MIN", 0}, {"MAX", 0}, {"offsetof", 0},
	} {
		p := `\b` + x.name + `\b`
		was, now := count(ocore, p), count(ncore, p)
		if now != 0 {
			r.bad("`%s` was %d in the core and is still %d -- the phase's whole product "+
				"is that it is 0", x.name, was, now)
		}
		if h := count(nhost, p); h != x.inHost {
			r.bad("`%s` is %d in the host block and was expected at %d -- the host is "+
				"below the boundary and keeps its own headers", x.name, h, x.inHost)
		}
	}
	if tvc := len(z26TV.FindAllString(ncore, -1)); tvc != 0 {
		r.bad("`struct timeval` is still %d in the core", tvc)
	}
	tvh := len(z26TV.FindAllString(nhost, -1))
	if oh := len(z26TV.FindAllString(ohost, -1)); tvh != oh+1 {
		r.bad("`struct timeval` is %d in the host block and the input had %d there: "+
			"musl_gettimeofday adds exactly one", tvh, oh)
	}

	oldTimeT := count(old, `\btime_t\b`)
	oldTimeTT := count(old, `\btime_T\b`)
	oldOffset := count(old, `\boffsetof\b`)
	for _, x := range []struct {
		pat  string
		want int
		why  string
	}{
		{`\btime_T\b`, oldTimeTT + oldTimeT - 1,
			fmt.Sprintf("the input's %d `time_T` plus its %d `time_t`, less the one in "+
				"`typedef time_t time_T;`, which becomes `long`", oldTimeTT, oldTimeT)},
		{`\b__builtin_offsetof\b`, oldOffset, "every `offsetof` in the input"},
		{`\bmusl_gettimeofday\b`, 5 + 2, "the five call sites, the prototype and the definition"},
	} {
		if n := count(t, x.pat); n != x.want {
			r.bad("`%s` occurs %d times in the output where %d were expected -- %s",
				strings.Trim(x.pat, `\b`), n, x.want, x.why)
		}
	}
	if bare := count(t, `\bgettimeofday\b`); bare != 1 {
		r.bad("the bare name `gettimeofday` occurs %d times in the output and must "+
			"occur exactly once -- the call inside musl_gettimeofday, in the host "+
			"block", bare)
	}
	if count(ncore, `\bgettimeofday\b`) > 0 {
		r.bad("the core still calls `gettimeofday` directly, which is the one libc " +
			"call this phase could not leave as it was: its argument is a struct")
	}

	// THE MACRO EXPANSION, checked against the header rather than against this
	// file, with the repeated argument really repeated.
	var mm []string
	for _, l := range strings.Split(readFile(filepath.Join(state, "minmax.txt")), "\n") {
		if s := strings.TrimSpace(l); s != "" {
			mm = append(mm, s)
		}
	}
	for _, tmpl := range mm {
		was, now := z26Count(old, tmpl), z26Count(t, tmpl)
		want := 16
		if strings.Contains(tmpl, "<") {
			want = 7
		}
		if now-was != want {
			r.bad("the shape %s occurs %d times in the output and %d in the input, a "+
				"difference of %d where %d was expected",
				pyRepr26(tmpl), now, was, now-was, want)
		}
	}
	if z26MinMax.MatchString(t) {
		r.bad("a `MIN(` or `MAX(` survives in the output")
	}

	added := 10 + 3 + 1 + 10
	if len(nlines)-len(olines) != added {
		r.bad("the output is %d lines and the input was %d, a difference of %d where %d "+
			"was expected -- 10 for the prototype block, 3 for the tagless struct, 1 "+
			"for musl_gettimeofday's prototype and 10 for its definition",
			len(nlines)-1, len(olines)-1, len(nlines)-len(olines), added)
	}
	var dIdx []int
	for i, l := range nlines {
		if strings.HasPrefix(l, "#") {
			dIdx = append(dIdx, i)
		}
	}
	okD := len(dIdx) == 11
	for k, i := range dIdx {
		if okD && i != k {
			okD = false
		}
	}
	if !okD {
		var at []string
		for _, i := range dIdx {
			at = append(at, strconv.Itoa(i))
		}
		r.bad("the output does not have exactly eleven directives on its first eleven "+
			"lines: %d at %s", len(dIdx), strings.Join(at, " "))
	}

	for _, p := range z26Protos {
		if strings.Count(t, "\n"+p+"\n") != 1 {
			r.bad("the prototype `%s` is not on a line of its own exactly once", p)
		}
		if strings.Contains(t, "static "+p) {
			r.bad("the prototype `%s` is `static`, which gives the core an internal "+
				"function that is never defined", p)
		}
	}
	if rn, ro := blankRuns26(t), blankRuns26(old); rn != ro {
		r.bad("the edit left %d runs of two blank lines where there were %d", rn, ro)
	}

	if err := r.done(); err != nil {
		return err
	}
	r.say("the core takes NOTHING from a header but the twelve constants phase 27 " +
		"moves: size_t time_t sig_atomic_t uintptr_t `struct timeval` MIN MAX offsetof " +
		"are all 0 above the host block, which keeps its own 3 sig_atomic_t and 3 " +
		"`struct timeval`")
	r.say("the substitutions are the input's own counts arriving: %d time_t -> time_T, "+
		"%d offsetof -> __builtin_offsetof, 7 MIN and 16 MAX expanded to the shapes the "+
		"preprocessor gives for <sys/param.h> (%s), and 5 gettimeofday call sites "+
		"through musl_gettimeofday", oldTimeT, oldOffset, strings.Join(mm, " and "))
	var pnames []string
	for _, p := range z26Protos {
		fs := strings.Fields(strings.SplitN(p, "(", 2)[0])
		pnames = append(pnames, strings.TrimLeft(fs[len(fs)-1], "*"))
	}
	r.say("nine plain prototypes, each on a line of its own and NOT ONE of them "+
		"`static`: %s", strings.Join(pnames, " "))
	r.say("%d lines -> %d, exactly the %d the edit adds, eleven directives on the first "+
		"eleven lines, and the blank-line runs unmoved at %d",
		len(olines)-1, len(nlines)-1, added, blankRuns26(t))

	// ---- 2. the headers verify the core ----------------------------------
	wg.Wait()
	if errX0 != nil {
		return fatal("the sixteen static_asserts against the headers did not compile:",
			filepath.Join(tmp, "w.x0"), 12)
	}
	wx0 := readFile(filepath.Join(tmp, "w.x0"))
	if wx0 != "" {
		return fatal("the sixteen static_asserts compiled but were not silent:",
			filepath.Join(tmp, "w.x0"), 12)
	}
	if !strings.Contains(readFile(filepath.Join(tmp, "w.x0bad")), "static assertion failed") {
		return fatal("x0bad -- one static_assert deliberately comparing elapsed_T's "+
			"tv_usec against struct timeval's tv_sec -- did NOT fail, so the sixteen "+
			"above prove nothing:", filepath.Join(tmp, "w.x0bad"), 8)
	}
	r.say("SIXTEEN static_asserts, silent: sizeof and both field offsets of the tagless " +
		"elapsed_T against <sys/time.h>'s struct timeval, _Generic saying usize IS " +
		"uintptr_t and IS size_t, time_T IS time_t, int IS sig_atomic_t and time IS " +
		"long(long *), and __builtin_offsetof == <stddef.h>'s offsetof at all six " +
		"types.  EVERY ONE NAMES A HEADER TYPE, so not one of them can be written after " +
		"phase 27 moves the includes -- which is the whole argument for doing this " +
		"first.  The control with one comparison wrong fails, so they are compiled and " +
		"not merely present")

	for _, m := range mis {
		if !strings.Contains(readFile(filepath.Join(tmp, "w."+m.name)), m.want) {
			return fatal(fmt.Sprintf("%s (%s) did not give `%s`, so the header above it "+
				"is not checking this declaration:", m.name, m.what, m.want),
				filepath.Join(tmp, "w."+m.name), 6)
		}
	}
	r.say("and the negative half: four wrong declarations, four errors from the headers " +
		"that are still above them -- conflicting types for time, for malloc and for " +
		"getpid, and `static declaration of 'malloc' follows non-static declaration` " +
		"for the trap the brief names.  AFTER THE MOVE the last of those becomes a link " +
		"failure and the other three become nothing at all")

	// ---- 3. the tag, and the claim that is no longer true ----------------
	if readFile(filepath.Join(tmp, "w.tag23")) != "" {
		return fatal("the tagged struct was expected to be SILENT under this file's own "+
			"dialect and was not:", filepath.Join(tmp, "w.tag23"), 6)
	}
	for _, s := range []string{"c11", "c17"} {
		if !strings.Contains(readFile(filepath.Join(tmp, "w.tag"+s)),
			"redefinition of 'struct timeval'") {
			return fatal(fmt.Sprintf("the tagged struct did not give `error: "+
				"redefinition of 'struct timeval'` under -std=%s:", s),
				filepath.Join(tmp, "w.tag"+s), 6)
		}
	}
	r.say("THE TAG IS FORBIDDEN FOR A BETTER REASON THAN THE BRIEF GIVES.  `typedef " +
		"struct timeval { long tv_sec; long tv_usec; } elapsed_T;` after the eleven " +
		"includes is SILENT under gcc's default dialect -- C23 permits a struct to be " +
		"redeclared with the same members -- and is `error: redefinition of 'struct " +
		"timeval'` under -std=c11 and -std=c17.  So the diagnostic the brief relied on " +
		"does not exist here, the core must simply not define a libc TAG, and the " +
		"layout equality is asserted in section 2 instead")

	// ---- 4. canon.sh ------------------------------------------------------
	if errCanon != nil {
		return fatal("tools/canon.sh failed on the output:",
			filepath.Join(tmp, "canon.log"), 10)
	}
	if readFile(canonC) != t {
		r.say("tools/canon.sh is not a no-op on the output -- the new text is not " +
			"written the way this file writes everything else:")
		return harness.ErrReported
	}
	r.say("tools/canon.sh is a NO-OP on the output: the tagless struct, the nine " +
		"prototypes and musl_gettimeofday are written the way this file writes " +
		"everything else")

	// ---- 5. the host's vocabulary is still the host's --------------------
	zh := exec.Command("sh", "tools/st.sh", "zhostonly", f)
	zh.Stdout, zh.Stderr = w, w
	if err := zh.Run(); err != nil {
		return harness.ErrReported
	}

	// ---- 6. the symbols, and the binary ----------------------------------
	if errNew != nil {
		return stop("the output did not build with '%s' '%s'",
			strings.Join(cflags, " "), strings.Join(ldflags, " "))
	}
	if errR0 != nil {
		return stop("the clock-reverted control did not build")
	}
	if errSwap != nil {
		return stop("the swapped-clock control did not build")
	}
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
	gone := minus26(uOld, uNew)
	came := minus26(uNew, uOld)
	if len(gone)+len(came) > 0 {
		return stop("`nm -u` moved: gone [%s] arrived [%s].  A rename and a wrapper "+
			"inside ONE translation unit can free nothing and can need nothing",
			strings.Join(gone, " ")+" ", strings.Join(came, " ")+" ")
	}
	ext := nmField26(filepath.Join(tmp, "new.o"), []string{"--extern-only", "--defined-only"}, 2)
	if s := strings.Join(ext, " ") + " "; s != "main " {
		return stop("the output defines external symbols other than main: %s", s)
	}
	r.say("`nm -u` is THE SAME SET, %d names, as a `comm` empty in BOTH directions, and "+
		"`main` is still the only external symbol", len(uNew))

	oldBin := readFile(filepath.Join(state, "old"))
	if readFile(filepath.Join(tmp, "r0")) != oldBin {
		r.say("THE CLOCK IS NOT THE ONLY THING THAT MOVED: with the clock alone " +
			"reverted the binary is not the one this phase was handed")
		return harness.ErrReported
	}
	newBin := readFile(filepath.Join(tmp, "new"))
	if newBin == oldBin {
		return stop("the output binary is byte-identical to the input's, which cannot " +
			"be: musl_gettimeofday adds a call and two stores at five sites, so the " +
			"clock control in section 7 would not be a control")
	}
	if readFile(filepath.Join(tmp, "swap")) == newBin {
		return stop("the swapped-clock control produced the same binary as the output, " +
			"so it is not a control")
	}
	r.say("THE CLOCK IS THE ONLY THING THAT CHANGES CODE, as an equality: with it ALONE "+
		"reverted the binary is `cmp`-IDENTICAL to the %d-byte one this phase was "+
		"handed.  So the six renames, the 23 macro expansions and the nine prototypes "+
		"are tier 1 of CLAUDE.md's table -- literally the same program -- and only the "+
		"clock has anything left to answer for.  The output is %d bytes",
		sizeOf(filepath.Join(state, "old")), sizeOf(filepath.Join(tmp, "new")))

	// ---- 7. the recording did not move -----------------------------------
	// THE CONTROL IS THE 102 SCREEN CASES AND NOT A WHOLE RECORDING: a binary
	// whose clock runs backwards is one whose timeouts do not expire, and
	// zpty.py duly waits out its deadline and exits 1.  That is the harness
	// behaving correctly on a deliberately broken editor.
	var wgR sync.WaitGroup
	wgR.Add(3)
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
	go func() {
		defer wgR.Done()
		exec.Command("sh", "tools/st.sh", "zcases", filepath.Join(tmp, "swap"),
			filepath.Join(tmp, "SCR.swap")).Run()
	}()
	wgR.Wait()

	diffOut, _ := exec.Command("diff", "-rq", filepath.Join(tmp, "REC.old"),
		filepath.Join(tmp, "REC.new")).CombinedOutput()
	if len(diffOut) > 0 {
		r.say("the declared delta is NOTHING AT ALL and the two recordings differ:")
		return harness.ErrReported
	}
	scr, _ := exec.Command("diff", "-rq", filepath.Join(tmp, "REC.new", "screen"),
		filepath.Join(tmp, "SCR.swap")).CombinedOutput()
	movedLines := strings.Split(strings.TrimRight(string(scr), "\n"), "\n")
	moved := len(movedLines)
	if len(scr) == 0 {
		moved = 0
	}
	if moved < 1 {
		return stop("the swapped-clock control moves NOTHING in the 102 screen cases, " +
			"so the byte-identical recording above is two numbers agreeing")
	}
	var nm []string
	for _, l := range movedLines {
		if m := z26ScrName.FindStringSubmatch(l); m != nil {
			nm = append(nm, m[1])
		}
	}
	r.say("the declared delta is NOTHING AT ALL and TWO FULL RECORDINGS ARE "+
		"BYTE-IDENTICAL -- 102 screen cases, every Ex command, every command line, the "+
		"pty scenarios and the terminal table.  And the recording is NOT blind to what "+
		"moved: the control whose musl_gettimeofday writes its two fields the wrong way "+
		"round moves %d of the 102 screen cases (%s)",
		moved, strings.Join(nm, " ")+" ")
	return nil
}

func blankRuns26(text string) int {
	L := strings.Split(text, "\n")
	n := 0
	for i := 1; i < len(L); i++ {
		if L[i] == "" && L[i-1] == "" {
			n++
		}
	}
	return n
}

// nmField26 is `nm <flags> f | awk '{print $N}' | sort`.  The FIELD INDEX is
// the shell's and differs between the two calls here -- `$2` for `nm -u` and
// `$3` for `--extern-only --defined-only` -- because an undefined symbol has
// no address column and a defined one does.
func nmField26(path string, flags []string, field int) []string {
	out, _ := exec.Command("nm", append(flags, path)...).Output()
	var got []string
	for _, l := range strings.Split(strings.TrimRight(string(out), "\n"), "\n") {
		fs := strings.Fields(l)
		if len(fs) > field {
			got = append(got, fs[field])
		} else {
			got = append(got, "")
		}
	}
	sort.Strings(got)
	return got
}

func minus26(a, b []string) []string {
	in := map[string]bool{}
	for _, x := range b {
		in[x] = true
	}
	var out []string
	for _, x := range a {
		if x != "" && !in[x] {
			out = append(out, x)
		}
	}
	return out
}

// pyRepr26 is Python's `%r` for a plain string: single quotes unless the text
// holds one.
func pyRepr26(s string) string {
	if strings.Contains(s, "'") && !strings.Contains(s, `"`) {
		return `"` + s + `"`
	}
	return "'" + strings.ReplaceAll(s, "'", `\'`) + "'"
}
