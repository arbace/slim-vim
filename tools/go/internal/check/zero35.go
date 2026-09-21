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

func init() { register("zero35", Zero35) }

var (
	z35Dir     = regexp.MustCompile(`^ *# *`)
	z35Include = regexp.MustCompile(`^#include <[A-Za-z0-9_/.]+>$`)
	z35DeclRe  = regexp.MustCompile(`^[A-Za-z_][\w *]*\**\w+\([^;]*\);$`)
	z35FnName  = regexp.MustCompile(`^.*?\**(\w+)\(.*$`)
	z35CanonLn = regexp.MustCompile(`^.*canon *`)
	z35Warn    = regexp.MustCompile(`warning: '([A-Za-z_][A-Za-z0-9_]*)' used but never defined`)
	z35CmdRow  = regexp.MustCompile(`(?m)^    \[CMD_\w+\] = \{.*$`)
	z35Probe   = regexp.MustCompile(`PROBE alloc=(\d+) amax=(\d+) free=(\d+) fnull=(\d+) write=(\d+) wmax=(\d+) wshort=(\d+)`)
	z35Probe4  = regexp.MustCompile(`PROBE alloc=(\d+) amax=(\d+) free=(\d+) fnull=(\d+)`)
)

// z35Decl is the heredoc's DECL: an ordinary declaration, which RE2 cannot
// say with the Python's `(?!static |typedef |static_assert)` lookahead, so the
// three prefixes are refused by hand.
func z35Decl(l string) bool {
	if strings.HasPrefix(l, "static ") || strings.HasPrefix(l, "typedef ") || strings.HasPrefix(l, "static_assert") {
		return false
	}
	return z35DeclRe.MatchString(l)
}

// z35CallShaped is `(?<!\w)NAME\(`, counted.
func z35CallShaped(text, name string) int {
	n := 0
	pat := name + "("
	for i := 0; ; {
		k := strings.Index(text[i:], pat)
		if k < 0 {
			return n
		}
		k += i
		if k == 0 || !z35Word(text[k-1]) {
			n++
		}
		i = k + 1
	}
}

func z35Word(b byte) bool {
	return b == '_' || (b >= '0' && b <= '9') || (b >= 'a' && b <= 'z') || (b >= 'A' && b <= 'Z') || b >= 0x80
}

const z35Instr = `static long probe_a, probe_f, probe_fnull, probe_w, probe_amax, probe_wmax, probe_wshort;

    static void
probe_num(long v)
{
    char b[24];
    int i = 24;

    if (v == 0)
    {
        b[--i] = '0';
    }
    while (v > 0)
    {
        b[--i] = (char)('0' + v % 10);
        v /= 10;
    }
    write(2, b + i, (usize)(24 - i));
}

    static void
probe_dump(void)
{
    write(2, "PROBE alloc=", 12);
    probe_num(probe_a);
    write(2, " amax=", 6);
    probe_num(probe_amax);
    write(2, " free=", 6);
    probe_num(probe_f);
    write(2, " fnull=", 7);
    probe_num(probe_fnull);
    write(2, " write=", 7);
    probe_num(probe_w);
    write(2, " wmax=", 6);
    probe_num(probe_wmax);
    write(2, " wshort=", 8);
    probe_num(probe_wshort);
    write(2, "\n", 1);
}

`

// Zero35 is phase 35's check: the core calls nothing but the host.
func Zero35(w io.Writer, args []string) error {
	if len(args) != 2 {
		return fmt.Errorf("usage: check zero35 <work-dir> <state-dir>")
	}
	work, state := args[0], args[1]
	f := filepath.Join(work, "zero-vim.c")
	oldC := filepath.Join(state, "old.c")
	const TAG = "hostcall"
	r := &rep{tag: TAG, w: w}
	stop := func(format string, a ...any) error {
		r.say(format, a...)
		return harness.ErrReported
	}
	raw := func(format string, a ...any) { fmt.Fprintf(w, format+"\n", a...) }
	head := func(ls []string, n int, prefix string) {
		for i, l := range ls {
			if i >= n {
				break
			}
			fmt.Fprintf(w, "%s%s\n", prefix, l)
		}
	}
	fileLines := func(p string) []string {
		s := strings.TrimRight(readFile(p), "\n")
		if s == "" {
			return nil
		}
		return strings.Split(s, "\n")
	}
	beforeRaw := strings.TrimRight(readFile(filepath.Join(state, "input-lines")), "\n")
	tmp, err := os.MkdirTemp("", "zero35-")
	if err != nil {
		return err
	}
	defer os.RemoveAll(tmp)
	T := func(n string) string { return filepath.Join(tmp, n) }
	mk := readFile(filepath.Join(work, "Makefile"))
	cflagsS, ldflagsS := "", ""
	if m := z29CFlags.FindStringSubmatch(mk); m != nil {
		cflagsS = m[1]
	}
	if m := z29LDFlags.FindStringSubmatch(mk); m != nil {
		ldflagsS = m[1]
	}
	link := func(src, out, logPath string) error {
		a := append(append(strings.Fields(cflagsS), strings.Fields(ldflagsS)...), "-o", out, src)
		c := exec.Command("gcc", a...)
		c.Env = append(os.Environ(), "SOURCE_DATE_EPOCH=0")
		if logPath != "" {
			lf, _ := os.Create(logPath)
			defer lf.Close()
			c.Stderr = lf
		}
		return c.Run()
	}
	var wgAll sync.WaitGroup
	defer wgAll.Wait()
	type job struct {
		wg  sync.WaitGroup
		err error
	}
	start := func(fn func() error) *job {
		j := &job{}
		j.wg.Add(1)
		wgAll.Add(1)
		go func() { defer wgAll.Done(); defer j.wg.Done(); j.err = fn() }()
		return j
	}
	jNew := start(func() error { return link(f, T("new"), "") })

	// --- 0. the nine variants ----------------------------------------------------
	t := readFile(f)
	protos := []string{"static void *host_alloc(usize n);", "static void host_free(void *p);",
		"static int host_write(const char *s, int len);"}
	var missing []string
	for _, p := range protos {
		if strings.Count(t, p+"\n") != 1 {
			missing = append(missing, p)
		}
	}
	if len(missing) > 0 {
		return stop("the output does not hold each of this phase's three prototypes "+
			"exactly once: %s", strings.Join(missing, " / "))
	}
	c1 := t
	for _, p := range protos {
		c1 = strings.Replace(c1, p+"\n", "", 1)
	}
	c2 := t
	for _, p := range protos {
		c2 = strings.Replace(c2, p+"\n", p[len("static "):]+"\n", 1)
	}
	c3 := c2
	for _, name := range []string{"host_alloc", "host_free", "host_write"} {
		re := regexp.MustCompile(`(?m)^    static ([\w *]+)\n(` + name + `\()`)
		m := re.FindStringSubmatchIndex(c3)
		if m == nil {
			return stop("`%s` is not defined in the `    static <type>` shape, so c3 "+
				"would not be a control", name)
		}
		c3 = c3[:m[0]] + "    " + c3[m[2]:m[3]] + "\n" + c3[m[4]:m[5]] + c3[m[1]:]
	}
	one := func(old, what string) (string, error) {
		if strings.Count(t, old) != 1 {
			return "", stop("`%s` is not in the output exactly once, so the control built "+
				"from it would not be one", what)
		}
		return old, nil
	}
	ALLOC, e := one("    return malloc(n);\n", "return malloc(n);")
	if e != nil {
		return e
	}
	FREE, e := one("    free(p);\n", "free(p);")
	if e != nil {
		return e
	}
	WRITE, e := one("    return (int)write(1, s, (usize)len);\n", "return (int)write(1, s, (usize)len);")
	if e != nil {
		return e
	}
	MCHW, e := one("    vim_ignored = host_write((char *)s, len);\n", "mch_write()'s call")
	if e != nil {
		return e
	}
	ctl := map[string]string{
		"ca":    strings.Replace(t, ALLOC, "    return nullptr;\n", 1),
		"cbig":  strings.Replace(t, ALLOC, "    return n > 200000 ? nullptr : malloc(n);\n", 1),
		"cf":    strings.Replace(t, FREE, "    (void)p;\n", 1),
		"cw":    strings.Replace(t, WRITE, "    return (int)write(1, s, (usize)len) / 2;\n", 1),
		"cw2":   strings.Replace(t, WRITE, "    return (int)write(1, s, (usize)len / 2);\n", 1),
		"cnull": strings.Replace(t, MCHW, "    host_free(nullptr);\n"+MCHW, 1),
	}
	EXIT, e := one("    static void\nhost_exit(int r)\n{\n", "host_exit()")
	if e != nil {
		return e
	}
	p := strings.Replace(t, EXIT, z35Instr+EXIT+"    probe_dump();\n", 1)
	p = strings.Replace(p, ALLOC, `    probe_a++;
    if ((long)n > probe_amax)
    {
        probe_amax = (long)n;
    }
    return malloc(n);
`, 1)
	p = strings.Replace(p, FREE, `    probe_f++;
    if (p == nullptr)
    {
        probe_fnull++;
    }
    free(p);
`, 1)
	p = strings.Replace(p, WRITE, `    int w;

    probe_w++;
    if (len > probe_wmax)
    {
        probe_wmax = len;
    }
    w = (int)write(1, s, (usize)len);
    if (w >= 0 && w < len)
    {
        probe_wshort++;
    }
    return w;
`, 1)
	ctl["probe"] = p
	names := []string{"ca", "cbig", "cf", "cnull", "cw", "cw2", "probe"}
	type named struct{ name, text string }
	all := []named{{"c1", c1}, {"c2", c2}, {"c3", c3}}
	for _, n := range names {
		all = append(all, named{n, ctl[n]})
	}
	for _, v := range all {
		if v.text == t {
			return stop("%s changed nothing", v.name)
		}
		os.WriteFile(T(v.name+".c"), []byte(v.text), 0o644)
	}
	r.say("nine variants written: c1 the three prototypes DELETED, c2 `static` off " +
		"them, c3 `static` off them AND the definitions; ca host_alloc always nullptr, " +
		"cbig it fails only above 200,000 bytes, cf host_free does nothing, cw host_write " +
		"writes everything and REPORTS half, cw2 it writes half, cnull host_free(nullptr) " +
		"on every draw; and probe, the output with a counter on each of the three")

	stderrTo := func(c *exec.Cmd, path string) error {
		lf, _ := os.Create(path)
		defer lf.Close()
		c.Stderr = lf
		return c.Run()
	}
	jC1 := start(func() error {
		stderrTo(exec.Command("gcc", "-O0", "-fno-stack-protector", "-fsyntax-only", T("c1.c")), T("e.c1"))
		return nil
	})
	jC2 := start(func() error {
		stderrTo(exec.Command("gcc", "-O0", "-fno-stack-protector", "-fsyntax-only", T("c2.c")), T("e.c2"))
		return nil
	})
	jC3 := start(func() error {
		stderrTo(exec.Command("gcc", "-c", "-O0", "-fno-stack-protector", "-o", T("c3.o"), T("c3.c")), T("e.c3"))
		return nil
	})
	jobs := map[string]*job{}
	for _, v := range names {
		v := v
		jobs[v] = start(func() error { return link(T(v+".c"), T(v), T("e."+v)) })
	}
	os.WriteFile(T("canon.c"), []byte(t), 0o644)
	var canonLog []byte
	jCanon := start(func() error {
		var e error
		canonLog, e = exec.Command("sh", "tools/canon.sh", T("canon.c")).CombinedOutput()
		return e
	})

	// --- 1. the source, as arithmetic on the input ------------------------------
	oldT := readFile(oldC)
	beforeLines, _ := strconv.Atoi(strings.TrimSpace(beforeRaw))
	NL, OL := strings.Split(t, "\n"), strings.Split(oldT, "\n")
	GO := []string{"void *malloc(usize n);", "void free(void *p);", "long write(int fd, const void *buf, usize n);"}
	mentions := func(text, name string) int {
		return len(regexp.MustCompile(`\b` + name + `\b`).FindAllStringIndex(text, -1))
	}
	halves := func(lines []string) (string, string, int, bool) {
		var d []int
		for i, l := range lines {
			if z35Dir.MatchString(l) {
				d = append(d, i)
			}
		}
		if len(d) != 11 {
			return "", "", 0, false
		}
		for k, i := range d {
			if i != d[0]+k || !z35Include.MatchString(lines[i]) {
				return "", "", 0, false
			}
		}
		return strings.Join(lines[:d[0]], "\n"), strings.Join(lines[d[0]:], "\n"), d[0], true
	}
	ocore, ohost, obound, okO := halves(OL)
	ncore, nhost, nbound, okN := halves(NL)
	if !okO || !okN {
		which := "output"
		if !okO {
			which = "input"
		}
		return stop("the eleven `#include` directives are not eleven consecutive lines "+
			"in the %s -- the first `#include` IS the boundary and nothing else marks "+
			"it", which)
	}
	ncalls := map[string]int{}
	known := map[string]bool{}
	for _, x := range []struct {
		name string
		hcnt int
		why  string
	}{
		{"malloc", 0, "lalloc(), and phase 34's two"},
		{"free", 1, "vim_free(), update_wincolor() and phase 34's two; and " +
			"format_overflow_error() below the boundary already did"},
		{"write", 1, "mch_write(); and host_message() below the boundary already did"},
	} {
		occ := mentions(ocore, x.name)
		paren := z35CallShaped(ocore, x.name)
		if occ != paren || paren < 2 {
			r.bad("the INPUT has %d mentions of `%s` above the boundary of which %d "+
				"are call-shaped, and this phase needs every one to be the "+
				"declaration or a call, with at least one call -- %s", occ, x.name, paren, x.why)
			continue
		}
		ncalls[x.name] = paren - 1
		known[x.name] = true
		if mentions(ohost, x.name) != x.hcnt {
			r.bad("the INPUT says `%s` %d times below the boundary, expected %d -- %s",
				x.name, mentions(ohost, x.name), x.hcnt, x.why)
		} else if mentions(ncore, x.name) != 0 || mentions(nhost, x.name) != x.hcnt+1 {
			r.bad("`%s` ends at %d mentions above the boundary and %d below, expected "+
				"0 and %d -- the phase MOVES the call, it does not remove it",
				x.name, mentions(ncore, x.name), mentions(nhost, x.name), x.hcnt+1)
		}
	}
	if known["write"] && ncalls["write"] > 0 {
		fd1 := 0
		for i := 0; ; {
			k := strings.Index(ocore[i:], "write(1, ")
			if k < 0 {
				break
			}
			k += i
			if k == 0 || !z35Word(ocore[k-1]) {
				fd1++
			}
			i = k + 1
		}
		if fd1 != ncalls["write"] {
			r.bad("%d of the INPUT's %d core write() calls are to fd 1, and "+
				"host_write() can only stand in for a write to the screen", fd1, ncalls["write"])
		}
	}
	for _, x := range []struct{ name, was string }{{"host_alloc", "malloc"}, {"host_free", "free"}, {"host_write", "write"}} {
		if mentions(oldT, x.name) > 0 {
			r.bad("the INPUT already says `%s`", x.name)
		} else if known[x.was] {
			want := ncalls[x.was] + 2
			if got := mentions(t, x.name); got != want {
				s := "s"
				if ncalls[x.was] == 1 {
					s = ""
				}
				r.bad("`%s` has %d mentions, expected %d -- its prototype, the %d call "+
					"site%s it took over from `%s` and its definition", x.name, got, want, ncalls[x.was], s, x.was)
			}
		}
	}
	var blockBefore, blockAfter []string
	var seed []int
	for i, l := range OL[:obound] {
		if l == GO[0] {
			seed = append(seed, i)
		}
	}
	if len(seed) != 1 {
		r.bad("the input does not declare `%s` exactly once above the boundary", GO[0])
	} else {
		lo, hi := seed[0], seed[0]
		for lo > 0 && z35Decl(OL[lo-1]) {
			lo--
		}
		for hi+1 < obound && z35Decl(OL[hi+1]) {
			hi++
		}
		blockBefore = OL[lo : hi+1]
		for _, l := range blockBefore {
			if !contains(GO, l) {
				blockAfter = append(blockAfter, l)
			}
		}
		if len(blockBefore)-len(blockAfter) != 3 {
			r.bad("the input's block of ordinary declarations does not hold all "+
				"three of this phase's lines: %s", strings.Join(blockBefore, " / "))
		}
		var have []string
		for i, l := range NL[:nbound] {
			prev := ""
			if i > 0 {
				prev = NL[i-1]
			} else {
				prev = NL[len(NL)-1]
			}
			if z35Decl(l) && (prev == "" || z35Decl(prev)) {
				have = append(have, l)
			}
		}
		if strings.Join(have, "\x00") != strings.Join(blockAfter, "\x00") {
			hs, bs := strings.Join(have, " / "), strings.Join(blockAfter, " / ")
			if hs == "" {
				hs = "none"
			}
			if bs == "" {
				bs = "none"
			}
			r.bad("the ordinary declarations above the boundary are %s and the "+
				"input's block minus the three is %s", hs, bs)
		}
	}
	dropped := 3
	if len(blockAfter) == 0 {
		dropped = len(blockBefore) + 1
	}
	if len(NL)-1 != beforeLines+21-dropped || len(OL)-1 != beforeLines {
		r.bad("the file is %d lines and the input was %d (%d recorded) -- expected %d "+
			"more", len(NL)-1, len(OL)-1, beforeLines, 21-dropped)
	}
	if z27Runs(NL) > 0 {
		r.bad("there is a run of two blank lines, which canon.sh should have taken")
	}
	// tools/create_cmdidxs.py -- named as a PATH so tools/implhash.sh hashes
	// it into this phase's key.  Do not delete it.
	nOld := len(z35CmdRow.FindAllString(oldT, -1))
	nNew := len(z35CmdRow.FindAllString(t, -1))
	cn, _ := harness.CommandNames(f)
	if nNew != nOld || len(cn) != nOld {
		r.bad("cmdnames[] is %d rows and the input had %d -- this phase touches no Ex "+
			"command", nNew, nOld)
	}
	if z29RowCount(t) != z29RowCount(oldT) {
		r.bad("options[] has %d rows and the input had %d -- this phase removes no "+
			"option", z29RowCount(t), z29RowCount(oldT))
	}
	if nbound != obound {
		r.bad("the boundary moved from line %d to line %d, and it must not: three "+
			"declarations leave the core's block and three arrive at the end of "+
			"the core -> host block, which is the same number of lines above the "+
			"first `#include`", obound+1, nbound+1)
	}
	if err := r.done(); err != nil {
		return err
	}
	pl := func(n int) string {
		if n == 1 {
			return ""
		}
		return "s"
	}
	r.say("ABOVE THE BOUNDARY every mention of the three goes: `malloc` %d -> 0 "+
		"(its declaration and %d call%s), `free` %d -> 0 (%d) and `write` %d -> 0 (%d, all "+
		"to fd 1).  BELOW IT 0 -> 1, 1 -> 2 and 1 -> 2, so the phase MOVES three libc calls "+
		"and removes none; `host_alloc` 0 -> %d, `host_free` 0 -> %d, `host_write` 0 -> %d.  "+
		"Not one of those numbers is written down: each is the INPUT partitioned into a "+
		"declaration and its calls",
		ncalls["malloc"]+1, ncalls["malloc"], pl(ncalls["malloc"]), ncalls["free"]+1, ncalls["free"],
		ncalls["write"]+1, ncalls["write"], ncalls["malloc"]+2, ncalls["free"]+2, ncalls["write"]+2)
	var tail string
	if len(blockAfter) > 0 {
		var fn []string
		for _, l := range blockAfter {
			fn = append(fn, z35FnName.ReplaceAllString(l, "$1"))
		}
		tail = strings.Join(fn, " ") + " remain, and each belongs to a phase of its own"
	} else {
		tail = "IT IS EMPTY.  The core names no libc function at all, and every outward call " +
			"it makes is a `musl_` or a `host_`"
	}
	r.cont("THE CORE'S BLOCK OF ORDINARY DECLARATIONS -- the libc it names, the one "+
		"run above the boundary that is not `static` -- is %d lines and was %d: %s",
		len(blockAfter), len(blockBefore), tail)
	r.cont("%d -> %d lines, %d more; cmdnames[] %d and options[] %d unmoved; the "+
		"eleven #includes still eleven consecutive lines at %d",
		beforeLines, len(NL)-1, len(NL)-1-beforeLines, nNew, z29RowCount(t), nbound+1)

	// --- 2. declaration before use ------------------------------------------------
	jC1.wg.Wait()
	errC1 := readFile(T("e.c1"))
	bound := -1
	for i, l := range NL {
		if z35Dir.MatchString(l) {
			bound = i
			break
		}
	}
	type pos struct {
		name              string
		pr, k, lo, hi, df int
	}
	var out []pos
	for _, name := range []string{"host_alloc", "host_free", "host_write"} {
		reP := regexp.MustCompile(`^static [\w *]*` + name + `\(.*\);$`)
		var proto, defn, uses []int
		for i, l := range NL {
			if reP.MatchString(l) {
				proto = append(proto, i)
			}
		}
		for i, l := range NL {
			if strings.HasPrefix(l, name+"(") && i+1 < len(NL) && NL[i+1] == "{" {
				defn = append(defn, i)
			}
		}
		for i, l := range NL {
			if z35CallShaped(l, name) > 0 && !containsInt(proto, i) && !containsInt(defn, i) {
				uses = append(uses, i)
			}
		}
		if len(proto) != 1 || len(defn) != 1 || len(uses) == 0 {
			return stop("`%s` has %d prototypes, %d definitions and %d call sites in "+
				"the output", name, len(proto), len(defn), len(uses))
		}
		lo, hi := uses[0], uses[len(uses)-1]
		if !(proto[0] < lo && hi < defn[0] && bound < defn[0]) {
			return stop("`%s`: prototype at %d, calls at %d..%d, definition at %d, "+
				"boundary at %d -- the prototype must be ABOVE every call, the "+
				"definition BELOW every one of them and BELOW the boundary, which is "+
				"what makes it the host's and not the core's",
				name, proto[0]+1, lo+1, hi+1, defn[0]+1, bound+1)
		}
		out = append(out, pos{name, proto[0] + 1, len(uses), lo + 1, hi + 1, defn[0] + 1})
	}
	if !regexp.MustCompile(`\berror\b`).MatchString(errC1) {
		return stop("THE CONTROL c1 DID NOT SHOW: with the three prototype lines " +
			"DELETED the file still compiles, so the declarations this phase adds are " +
			"not what lets the core name the host and the ordering above proves " +
			"nothing")
	}
	for _, name := range []string{"host_alloc", "host_free", "host_write"} {
		if !strings.Contains(errC1, name) {
			return stop("the control c1 failed without naming `%s`, so it is not the "+
				"control it claims to be", name)
		}
	}
	nerr := strings.Count(errC1, "error:")
	tag := TAG
	for _, o := range out {
		rng := ""
		if o.k != 1 {
			rng = fmt.Sprintf("..%d", o.hi)
		}
		raw("  %-12s `%s`: prototype line %d, %d call site%s at %d%s, definition line %d, "+
			"below the boundary at %d", tag, o.name, o.pr, o.k, pl(o.k), o.lo, rng, o.df, bound+1)
		tag = ""
	}
	r.cont("AND THE DECLARATIONS ARE LOAD-BEARING: this phase's own output with the "+
		"three prototype lines DELETED gives %d errors naming all three.  Without that "+
		"control the three lines above are a statement about line numbers and not about "+
		"the program", nerr)

	// --- 3. linkage ------------------------------------------------------------------
	jC2.wg.Wait()
	jC3.wg.Wait()
	if !strings.Contains(readFile(T("e.c2")), "static declaration of 'host_alloc' follows non-static declaration") {
		r.say("THE CONTROL c2 DID NOT SHOW.  With `static` off the three PROTOTYPES")
		raw("               and left on the definitions, gcc must refuse:")
		head(fileLines(T("e.c2")), 4, "               ")
		return harness.ErrReported
	}
	if _, e := os.Stat(T("c3.o")); sizeOf(T("e.c3")) > 0 || e != nil {
		r.say("the control c3 did not build, and the point of it is that it DOES:")
		head(fileLines(T("e.c3")), 4, "               ")
		return harness.ErrReported
	}
	extOut, _ := exec.Command("nm", "--extern-only", "--defined-only", T("c3.o")).Output()
	var c3ext []string
	for _, l := range strings.Split(strings.TrimRight(string(extOut), "\n"), "\n") {
		fs := strings.Fields(l)
		if len(fs) > 0 {
			c3ext = append(c3ext, fs[len(fs)-1])
		} else {
			c3ext = append(c3ext, "")
		}
	}
	sort.Strings(c3ext)
	c3s := z31Words(c3ext)
	if c3s != "host_alloc host_free host_write main " {
		r.say("THE CONTROL c3 DID NOT SHOW.  With `static` off the prototypes AND")
		raw("               the definitions the object must define host_alloc, host_free,")
		raw("               host_write and main; it defines: %s", c3s)
		return harness.ErrReported
	}
	r.say("THE `static` TRAP, BOTH HALVES, MEASURED ON THIS PHASE'S OWN OUTPUT: with the keyword off the three "+
		"PROTOTYPES gcc REFUSES -- \"static declaration of 'host_alloc' follows non-static declaration\" -- and "+
		"with it off the prototypes AND the definitions the build is SILENT and the object defines %s.  The "+
		"second is the mistake this phase could have made without anything else noticing, and "+
		"tools/phasecheck.sh below is what catches it", c3s)

	// --- 4. the libc surface ------------------------------------------------------------
	beforeU := readFile(filepath.Join(state, "symbols", "undefined"))
	os.WriteFile(T("before.u"), []byte(beforeU), 0o644)
	pc := exec.Command("sh", "tools/phasecheck.sh", work, f, filepath.Join(state, "symbols"))
	pc.Stdout, pc.Stderr = w, w
	if err := pc.Run(); err != nil {
		return harness.ErrReported
	}
	lastU := ".cache/symbols/last/undefined"
	if !z30Same(T("before.u"), lastU) {
		bu, lu := fileLines(T("before.u")), fileLines(lastU)
		r.say("the libc surface moved, and MOVING A CALL ACROSS THE BOUNDARY CANNOT")
		raw("               MOVE IT -- the host calls all three where the core did:")
		raw("               gone: %s", z31Words(comm23(bu, lu)))
		raw("               came: %s", z31Words(comm23(lu, bu)))
		return harness.ErrReported
	}
	for _, s := range []string{"malloc", "free", "write"} {
		if !contains(fileLines(lastU), s) {
			r.say("`%s` is no longer an undefined symbol, and it must still be one:", s)
			raw("               this phase moves the call into the host, it does not remove it.")
			return harness.ErrReported
		}
	}
	r.say("symbols %s -> %s, and the set is IDENTICAL as a cmp -- nothing left and nothing arrived.  `malloc`, "+
		"`free` and `write` are all three still there, which is the point: the phase MOVES them out of the core "+
		"and the host calls them, and an undefined symbol leaves only when its last caller leaves the FILE.  "+
		"main is still the only external symbol",
		strings.TrimRight(readFile(".cache/symbols/last/before"), "\n"),
		strings.TrimRight(readFile(".cache/symbols/last/after"), "\n"))

	// --- 5. the cut, and the core -> host interface it prints ---------------------------
	type cut struct {
		lines int
		errs  int
		warns int
		names []string
		log   string
	}
	editorcut := func(src, dst string) (cut, error) {
		lines := z28Cut(readFile(src))
		text := ""
		for _, l := range lines {
			text += l + "\n"
		}
		os.WriteFile(dst, []byte(text), 0o644)
		for _, l := range lines {
			if z30Dir.MatchString(l) {
				return cut{}, stop("the cut of %s holds a directive, so it found the wrong line", src)
			}
		}
		if len(lines) <= 70000 {
			return cut{}, stop("the cut of %s is %d lines, and zero.mk's floor is 70,000 -- a cut that found "+
				"line 1 would be empty and every check below would pass on nothing", src, len(lines))
		}
		c := exec.Command("gcc", "-O0", "-fno-stack-protector", "-fsyntax-only", dst)
		var eb strings.Builder
		c.Stderr = &eb
		c.Run()
		lg := eb.String()
		var cu cut
		cu.lines, cu.log = len(lines), lg
		for _, l := range strings.Split(lg, "\n") {
			if strings.Contains(l, "error:") {
				cu.errs++
			}
			if strings.Contains(l, "warning:") {
				cu.warns++
			}
			if m := z35Warn.FindStringSubmatch(l); m != nil {
				cu.names = append(cu.names, m[1])
			}
		}
		sort.Strings(cu.names)
		return cu, nil
	}
	co, e := editorcut(oldC, T("cut-old.c"))
	if e != nil {
		return e
	}
	cnw, e := editorcut(f, T("cut-new.c"))
	if e != nil {
		return e
	}
	for _, x := range []struct {
		w string
		c cut
	}{{"old", co}, {"new", cnw}} {
		if x.c.errs != 0 {
			r.say("the %s cut does not parse: %d errors", x.w, x.c.errs)
			var el []string
			for _, l := range strings.Split(x.c.log, "\n") {
				if strings.Contains(l, "error:") {
					el = append(el, l)
				}
			}
			head(el, 3, "               ")
			return harness.ErrReported
		}
		if x.c.warns != len(x.c.names) {
			r.say("the %s cut has a warning that is not a 'used but never defined':", x.w)
			var wl []string
			for _, l := range strings.Split(x.c.log, "\n") {
				if strings.Contains(l, "warning:") && !strings.Contains(l, "used but never defined") {
					wl = append(wl, l)
				}
			}
			head(wl, 3, "               ")
			return harness.ErrReported
		}
	}
	cutBytes, _ := os.ReadFile(T("cut-new.c"))
	fb, _ := os.ReadFile(f)
	if len(fb) < len(cutBytes) || string(fb[:len(cutBytes)]) != string(cutBytes) {
		return stop("the cut is not a byte prefix of zero-vim.c")
	}
	arrived := z31Words(comm23(cnw.names, co.names))
	left := z31Words(comm23(co.names, cnw.names))
	if arrived != "host_alloc host_free host_write " || left != "" {
		a, l := arrived, left
		if a == "" {
			a = "nothing"
		}
		if l == "" {
			l = "nothing"
		}
		r.say("THE CUT'S BOUNDARY SET DID NOT MOVE AS THIS PHASE CLAIMS.")
		raw("               arrived: %s", a)
		raw("               left:    %s", l)
		return harness.ErrReported
	}
	r.say("THE CUT -- `make editor.c`'s own rule, and a byte prefix of the file -- is %d lines either side, 0 "+
		"errors either side, and its warning set, which IS the core -> host interface, goes from %d names to %d: "+
		"host_alloc, host_free and host_write ARRIVE and nothing leaves.  A libc dependency that was implicit in "+
		"a bare declaration is now an explicit named call, and the interface growing by three is what that "+
		"looks like.  The input's set is computed here and never written down", cnw.lines, len(co.names), len(cnw.names))

	// --- 6. the binary ---------------------------------------------------------------------
	jCanon.wg.Wait()
	if !z30Same(T("canon.c"), f) {
		r.say("tools/canon.sh CHANGED THE OUTPUT, and it must be a no-op:")
		head(z30Diff(f, T("canon.c")), 6, "               ")
		return harness.ErrReported
	}
	canonWord := ""
	for _, l := range strings.Split(string(canonLog), "\n") {
		if z35CanonLn.MatchString(l) {
			canonWord = z35CanonLn.ReplaceAllString(l, "")
			break
		}
	}
	r.say("tools/canon.sh is a NO-OP on the output (%s)", canonWord)
	_ = exec.Command("make", "-C", work, "clean").Run()
	bin := filepath.Join(work, "zero-vim")
	if _, e := os.Stat(bin); e == nil {
		(&rep{tag: "build", w: w}).say("the clean did not remove zero-vim, so a 'rebuild' below could be no rebuild at all")
		return harness.ErrReported
	}
	if err := exec.Command("make", "-C", work).Run(); err != nil {
		(&rep{tag: "build", w: w}).say("FAILED -- rerun by hand: make -C %s", work)
		return harness.ErrReported
	}
	(&rep{tag: "build", w: w}).say("ok, %s -> %d lines, %d bytes", beforeRaw, countLines(fb), sizeOf(bin))
	jNew.wg.Wait()
	if jNew.err != nil {
		return stop("the reproducible build of the output failed")
	}
	oldBinP := filepath.Join(state, "old")
	oldSize, newSize := sizeOf(oldBinP), sizeOf(T("new"))
	if newSize < 500000 || oldSize < 500000 {
		return stop("one of the two binaries is %d / %d bytes, which is not an editor", oldSize, newSize)
	}
	if newSize != sizeOf(bin) {
		return stop("the reproducible build is %d bytes and make produced %d: the two differ by more than a "+
			"timestamp, so nothing below would be about this boundary", newSize, sizeOf(bin))
	}
	if z30Same(oldBinP, T("new")) {
		r.say("THE BINARY IS BYTE-IDENTICAL, and it must not be: four call sites go")
		raw("               from a direct libc call to a call into a function of this file, and")
		raw("               three definitions arrive at the bottom of it.")
		return harness.ErrReported
	}
	ob, _ := os.ReadFile(oldBinP)
	nb, _ := os.ReadFile(T("new"))
	nDiff := 0
	for k := 0; k < len(ob) && k < len(nb); k++ {
		if ob[k] != nb[k] {
			nDiff++
		}
	}
	r.say("the binary is %d bytes in and %d out, %d of them differing.  Both are MEASUREMENTS and neither is "+
		"aimed for: at -O0 a call to a static function in the same file is not the same instruction stream as a "+
		"call to a libc symbol, and three definitions arrive.  So this phase cannot use tier 1 of CLAUDE.md's "+
		"verification table and does not pretend to; the evidence is the recording and the probes below",
		oldSize, newSize, nDiff)

	// --- 7. THE EVIDENCE: two recordings, and a control that moves all of them -------------
	jobs["ca"].wg.Wait()
	if jobs["ca"].err != nil {
		r.say("the control ca did not build:")
		head(fileLines(T("e.ca")), 5, "               ")
		return harness.ErrReported
	}
	oldBin, _ := filepath.Abs(oldBinP)
	var wgR sync.WaitGroup
	recErr := make([]error, 3)
	for k, x := range []struct{ name, bin, src string }{
		{"old", oldBin, oldC}, {"new", T("new"), f}, {"ca", T("ca"), T("ca.c")},
	} {
		k, x := k, x
		wgR.Add(1)
		go func() {
			defer wgR.Done()
			recErr[k] = exec.Command("sh", "tools/zrecord.sh", x.bin, x.src, T("REC-"+x.name)).Run()
		}()
	}
	wgR.Wait()
	for _, e := range recErr {
		if e != nil {
			return stop("a recording failed")
		}
	}
	base := walkFiles(T("REC-new"))
	if len(base) < 100 {
		return stop("a recording holds %d records, and a zero recording is 106 -- 102 "+
			"screen cases and four sweeps.  A comparison of two things nothing wrote "+
			"passes", len(base))
	}
	movedRec := func(which string) ([]string, error) {
		d := T("REC-" + which)
		if strings.Join(walkFiles(d), "\x00") != strings.Join(base, "\x00") {
			return nil, stop("the recording of %s holds different records from the output's", which)
		}
		var m []string
		for _, n := range base {
			if !z30Same(filepath.Join(T("REC-new"), n), filepath.Join(d, n)) {
				m = append(m, n)
			}
		}
		return m, nil
	}
	same, e := movedRec("old")
	if e != nil {
		return e
	}
	if len(same) > 0 {
		show := same
		if len(show) > 8 {
			show = show[:8]
		}
		r.say("THE RECORDING MOVED, in %d of %d records: %s", len(same), len(base), strings.Join(show, " "))
		r.cont("This phase declares NOTHING.  Three libc calls became three calls " +
			"into the host, each forwarding to the same libc function with the same " +
			"arguments; the editor does the same thing or the phase is wrong.")
		return harness.ErrReported
	}
	mca, e := movedRec("ca")
	if e != nil {
		return e
	}
	if len(mca) != len(base) {
		return stop("THE CONTROL ca DID NOT SHOW: with host_alloc returning nullptr "+
			"always, %d of %d records move and every one must -- an editor that cannot "+
			"allocate cannot draw", len(mca), len(base))
	}
	r.say("THE RECORDING IS BYTE-IDENTICAL, all %d records -- 102 screen cases, "+
		"every Ex command typed at `:`, every command line the parser may see, the four "+
		"pty scenarios and the terminal table.  lalloc() and vim_free() are on the path "+
		"of essentially everything the editor does and mch_write() is every byte it "+
		"draws, so the corpus HAMMERS all three of this phase's subjects: an empty `diff "+
		"-r` is strong evidence here, where for a phase whose subject the corpus cannot "+
		"reach it would be weak", len(base))
	r.cont("AND IT CAN FAIL: host_alloc returning nullptr always moves %d of %d -- "+
		"every record there is", len(mca), len(base))

	// --- 8. THE PROBES ------------------------------------------------------------------------
	jobs["probe"].wg.Wait()
	if jobs["probe"].err != nil {
		r.say("the instrumented build failed:")
		head(fileLines(T("e.probe")), 5, "               ")
		return harness.ErrReported
	}
	for _, v := range []string{"cbig", "cf", "cw", "cw2", "cnull"} {
		jobs[v].wg.Wait()
		if jobs[v].err != nil {
			r.say("the control %s did not build:", v)
			head(fileLines(T("e."+v)), 5, "               ")
			return harness.ErrReported
		}
	}
	scV := []string{"probe", "cbig", "cf", "cw", "cw2", "cnull"}
	scErr := map[string]error{}
	var mu sync.Mutex
	var wgS sync.WaitGroup
	for _, v := range scV {
		v := v
		wgS.Add(1)
		go func() {
			defer wgS.Done()
			e := exec.Command("sh", "tools/st.sh", "zcases", T(v), T("SC-"+v)).Run()
			mu.Lock()
			scErr[v] = e
			mu.Unlock()
		}()
	}
	os.WriteFile(T("keys-q"), []byte(":q!\r"), 0o644)
	os.WriteFile(T("keys-i"), []byte("ihello world\x1b:q!\r"), 0o644)
	session := func(binName, arg, keys, errFile string) {
		in, _ := os.Open(T(keys))
		defer in.Close()
		ef, _ := os.Create(T(errFile))
		defer ef.Close()
		c := exec.Command("./"+binName, arg)
		c.Dir = tmp
		var env []string
		for _, kv := range os.Environ() {
			k := kv[:strings.IndexByte(kv+"=", '=')]
			switch k {
			case "VIMINIT", "EXINIT", "HOME", "VIM", "VIMRUNTIME", "XDG_CONFIG_HOME", "TERM":
				continue
			}
			env = append(env, kv)
		}
		c.Env = append(env, "HOME=", "VIM=", "VIMRUNTIME=", "XDG_CONFIG_HOME=", "TERM=xterm")
		c.Stdin, c.Stdout, c.Stderr = in, nil, ef
		c.Run()
	}
	session("probe", "+normal 200000ax", "keys-q", "big.err")
	session("probe", "+set paste", "keys-i", "small.err")
	session("cnull", "+set paste", "keys-i", "null.err")
	wgS.Wait()
	for _, v := range scV {
		if scErr[v] != nil {
			return stop("the screen corpus failed on %s", v)
		}
	}
	ents, _ := os.ReadDir(T("REC-new") + "/screen")
	var sbase []string
	for _, en := range ents {
		sbase = append(sbase, en.Name())
	}
	sort.Strings(sbase)
	if len(sbase) != 102 {
		return stop("the screen corpus is %d cases and it is 102", len(sbase))
	}
	movedSC := func(which string) ([]string, error) {
		d := T("SC-" + which)
		es, _ := os.ReadDir(d)
		var got []string
		for _, en := range es {
			got = append(got, en.Name())
		}
		sort.Strings(got)
		if strings.Join(got, "\x00") != strings.Join(sbase, "\x00") {
			return nil, stop("the %s corpus holds different cases", which)
		}
		var m []string
		for _, n := range sbase {
			if !z30Same(filepath.Join(T("REC-new"), "screen", n), filepath.Join(d, n)) {
				m = append(m, n)
			}
		}
		return m, nil
	}
	fields := []string{"alloc", "amax", "free", "fnull", "write", "wmax", "wshort"}
	tot := map[string]int{}
	var totOrder []string
	seen := 0
	for _, n := range sbase {
		m := z35Probe.FindStringSubmatch(readFile(filepath.Join(T("SC-probe"), n)))
		if m == nil {
			continue
		}
		seen++
		for k, name := range fields {
			v, _ := strconv.Atoi(m[k+1])
			if _, ok := tot[name]; !ok {
				totOrder = append(totOrder, name)
			}
			if name == "amax" || name == "wmax" {
				if v > tot[name] {
					tot[name] = v
				}
			} else {
				tot[name] += v
			}
		}
	}
	if seen != 102 {
		return stop("the instrumented build marked %d of 102 cases, and it must mark "+
			"every one: the counter is printed from host_exit(), which every case "+
			"reaches", seen)
	}
	if !(tot["alloc"] > 10000 && tot["free"] > 5000 && tot["write"] > 500) {
		var kv []string
		for _, k := range totOrder {
			kv = append(kv, fmt.Sprintf("'%s': %d", k, tot[k]))
		}
		return stop("the instrument counts {%s}, and a corpus that hammers lalloc() and "+
			"mch_write() cannot give numbers that small -- the counters are not on the "+
			"path", strings.Join(kv, ", "))
	}
	if tot["fnull"] > 0 {
		return stop("host_free was handed a null pointer %d times, and the input's two "+
			"call sites both guard against it -- vim_free() tests `x != nullptr` and "+
			"update_wincolor() frees only the arm it allocated.  A null arriving means "+
			"one of the two guards has gone", tot["fnull"])
	}
	if tot["wshort"] > 0 {
		return stop("host_write came up short %d times in the corpus, which is the one "+
			"thing mch_write() has never coped with: it assigns the count to "+
			"vim_ignored and writes no more.  A short write here would mean the "+
			"recording above is comparing truncated screens", tot["wshort"])
	}
	r.say("THE INSTRUMENT, over all 102 screen cases and marking every one of them: "+
		"host_alloc %d calls, the largest %d bytes; host_free %d calls, %d of them null; "+
		"host_write %d calls, the largest %d bytes, %d of them short.  That is what the "+
		"byte-identical recording above was carried by",
		tot["alloc"], tot["amax"], tot["free"], tot["fnull"], tot["write"], tot["wmax"], tot["wshort"])
	big, small, null := readFile(T("big.err")), readFile(T("small.err")), readFile(T("null.err"))
	mb, ms := z35Probe4.FindStringSubmatch(big), z35Probe4.FindStringSubmatch(small)
	if mb == nil || ms == nil {
		return stop("a by-hand probe session printed no counter line")
	}
	bigA, _ := strconv.Atoi(mb[1])
	bigMax, _ := strconv.Atoi(mb[2])
	bigF, _ := strconv.Atoi(mb[3])
	smA, _ := strconv.Atoi(ms[1])
	if bigA < 100000 || bigA <= smA*10 {
		return stop("`+normal 200000ax` made %d allocations against a bare session's "+
			"%d, and a 200,000-character insert must make far more -- the probe is not "+
			"driving lalloc()", bigA, smA)
	}
	if bigMax < 100000 {
		return stop("the largest allocation in that session is %d bytes, and this "+
			"probe is meant to drive a LARGE one through lalloc()", bigMax)
	}
	r.cont("THE ALLOCATION PROBE: `+normal 200000ax` -- a 200,000-character insert -- "+
		"makes %d host_alloc calls against %d for `ihello world<Esc>`, frees %d of them, "+
		"and the largest single allocation is %d bytes.  EVERY allocation the editor makes "+
		"goes through lalloc(), which is the one place the core said `malloc`", bigA, smA, bigF, bigMax)
	if !strings.Contains(small, "PROBE") {
		return stop("the small session printed no counter line")
	}
	if strings.TrimSpace(null) != "" {
		nn := null
		if len(nn) > 80 {
			nn = nn[:80]
		}
		return stop("the cnull binary -- host_free(nullptr) on EVERY draw -- wrote to "+
			"stderr: %s.  A null free must be silent and harmless", pyRepr26(nn))
	}
	mv := map[string][]string{}
	for _, k := range []string{"cbig", "cf", "cw", "cw2", "cnull"} {
		m, e := movedSC(k)
		if e != nil {
			return e
		}
		mv[k] = m
	}
	if len(mv["cbig"]) < 90 {
		return stop("THE CONTROL cbig DID NOT SHOW: refusing the ONE allocation larger "+
			"than 200,000 bytes moves %d of 102 screen cases, and it was measured to "+
			"move 100", len(mv["cbig"]))
	}
	if len(mv["cw2"]) != 102 {
		return stop("THE CONTROL cw2 DID NOT SHOW: host_write writing HALF the bytes "+
			"moves %d of 102 screen cases and must move every one -- those bytes ARE "+
			"the screen the corpus records", len(mv["cw2"]))
	}
	if len(mv["cf"])+len(mv["cw"])+len(mv["cnull"]) > 0 {
		return stop("a control that was MEASURED to move nothing moved something: cf %d, "+
			"cw %d, cnull %d of 102.  Each is reported here as a finding and not hidden, "+
			"so a change in one is a fact to read rather than a failure to explain",
			len(mv["cf"]), len(mv["cw"]), len(mv["cnull"]))
	}
	r.say("THE CONTROLS, ONE PER FUNCTION AND TWO OF THEM MOVE NOTHING, WHICH IS " +
		"REPORTED AND NOT HIDDEN:")
	r.cont("  host_alloc  refusing only the allocations above 200,000 bytes -- in "+
		"this editor exactly ONE, the screen -- moves %d of 102, and the two that survive "+
		"are ctrl_c_clean and ctrl_c_changed, which exit before a key is looked up "+
		"(ZERO-PLAN.md 2g)", len(mv["cbig"]))
	r.cont("  host_free   doing NOTHING AT ALL moves 0 of 102.  A leak is invisible "+
		"to a 106-record corpus, so the recording is NOT what says host_free is called; "+
		"the instrument above is, at %d calls across the same 102 cases.  A control that "+
		"moves nothing is REPORTED here and not quietly dropped", tot["free"])
	r.cont("  host_write  writing every byte and REPORTING HALF moves 0 of 102, and " +
		"writing HALF THE BYTES moves 102 of 102.  That pair is the phase's claim about " +
		"the wrapper stated as a measurement: mch_write() ignores the count -- it assigns " +
		"it to vim_ignored and writes no more -- so the return value is inert and the " +
		"BYTES are everything.  A wrapper that LOOPED on a short write would be a " +
		"behaviour change no recording could see, and host_write does not loop")
	r.cont("  host_free(nullptr) called on EVERY draw moves 0 of 102 and writes " +
		"nothing to stderr, which is `free(nullptr) is defined and does nothing` measured " +
		"on the wrapper rather than assumed from the standard.  The core does not rely on " +
		"it -- 0 of the corpus's frees are null -- but the wrapper inherits it")

	// --- 9. phase 20's structural check -----------------------------------------------------
	zh := exec.Command("sh", "tools/st.sh", "zhostonly", f)
	zh.Stdout, zh.Stderr = w, w
	if err := zh.Run(); err != nil {
		return harness.ErrReported
	}
	r.say("and that is phase 20's check, undisturbed.  Its vocabulary is libc's terminal, signal and descriptor " +
		"names and `write` is deliberately NOT in it -- its own comment says so, naming mch_write as a later " +
		"phase's.  THIS is that phase, and the assertion it owes is made directly above instead: `write` is 0 " +
		"mentions above the boundary, computed from the input, which is stronger than a word list")
	return nil
}

func containsInt(xs []int, v int) bool {
	for _, x := range xs {
		if x == v {
			return true
		}
	}
	return false
}
