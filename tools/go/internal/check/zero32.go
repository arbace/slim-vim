package check

import (
	"bytes"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"

	"slimvim.local/tools/internal/harness"
)

func init() { register("zero32", Zero32) }

var (
	z32Time    = regexp.MustCompile(`\btime\b`)
	z32VimTime = regexp.MustCompile(`\bvim_time\b`)
	z32Host    = regexp.MustCompile(`\bhost_time\b`)
	z32HostC   = regexp.MustCompile(`\bhost_time\(\)`)
	z32VimC    = regexp.MustCompile(`\bvim_time\(\)`)
	z32Null    = regexp.MustCompile(`\btime\(nullptr\)`)
	z32TimeT   = regexp.MustCompile(`\btime_t\b`)
	z32TimeTT  = regexp.MustCompile(`\btime_T\b`)
)

// z32Strip is zhostonly's strip_strings: every string and character literal
// becomes one space, so English in an NGETTEXT is not counted as code.
func z32Strip(line string) string {
	var out strings.Builder
	i, n := 0, len(line)
	for i < n {
		c := line[i]
		if c == '"' || c == '\'' {
			q := c
			out.WriteByte(' ')
			i++
			for i < n {
				if line[i] == '\\' {
					i += 2
					continue
				}
				if line[i] == q {
					break
				}
				i++
			}
			i++
			continue
		}
		out.WriteByte(c)
		i++
	}
	return out.String()
}

type z32Res struct {
	ok      bool
	got, rc int
}

func (r z32Res) show() string {
	if !r.ok {
		return "None"
	}
	return strconv.Itoa(r.got)
}

// Zero32 is phase 32's check: the clock crosses the boundary.
func Zero32(w io.Writer, args []string) error {
	if len(args) != 2 {
		return fmt.Errorf("usage: check zero32 <work-dir> <state-dir>")
	}
	work, state := args[0], args[1]
	f := filepath.Join(work, "zero-vim.c")
	oldC := filepath.Join(state, "old.c")
	r := &rep{tag: "wallclock", w: w}
	stop := func(format string, a ...any) error {
		r.say(format, a...)
		return harness.ErrReported
	}
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
	tmp, err := os.MkdirTemp("", "zero32-")
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
	link := func(src, out string) error {
		a := append(append(strings.Fields(cflagsS), strings.Fields(ldflagsS)...), "-o", out, src)
		c := exec.Command("gcc", a...)
		c.Env = append(os.Environ(), "SOURCE_DATE_EPOCH=0")
		return c.Run()
	}

	// --- 0. the controls -------------------------------------------------------
	newT, oldT := readFile(f), readFile(oldC)
	const TD = "typedef long        time_T;"
	const AS = "static_assert(_Generic((time_T)0, time_t: 1, default: 0), \"time_T is time_t\");\n"
	const PR = "long time(long *tp);"
	for _, x := range []struct{ text, what, where string }{
		{newT, TD, "the output"}, {newT, AS, "the output"}, {oldT, TD, "the input"}, {oldT, PR, "the input"},
	} {
		if strings.Count(x.text, x.what) != 1 {
			return stop("`%s` is not in %s exactly once, so the controls below would not be controls",
				strings.TrimSpace(x.what), x.where)
		}
	}
	const INT = "typedef int         time_T;"
	const LL = "typedef long long   time_T;"
	type ctl struct{ name, text string }
	files := []ctl{
		{"m1", strings.Replace(oldT, PR, "int time(int *tp);", 1)},
		{"m2", strings.Replace(oldT, TD, INT, 1)},
		{"p1", strings.Replace(strings.Replace(newT, TD, INT, 1), AS, "", 1)},
		{"p2", strings.Replace(newT, TD, INT, 1)},
		{"p3", strings.Replace(newT, TD, LL, 1)},
	}
	const TICK = "    write(2, \"TICK\\n\", 5);\n"
	const OW = "vim_time(void)\n{\n    return time(nullptr);\n}"
	const OF = `    if (in_focus && last_time + 2 < time(nullptr))
    {
        last_time = time(nullptr);
    }
`
	const NW = "host_time(void)\n{\n    return time(nullptr);\n}"
	const NF = `    if (in_focus && last_time + 2 < host_time())
    {
        last_time = host_time();
    }
`
	for _, x := range []struct{ text, what, where string }{
		{oldT, OW, "the input"}, {oldT, OF, "the input"}, {newT, NW, "the output"}, {newT, NF, "the output"},
	} {
		if strings.Count(x.text, x.what) != 1 {
			s := strings.ReplaceAll(x.what, "\n", "\\n")
			if len(s) > 60 {
				s = s[:60]
			}
			return stop("`%s` is not in %s exactly once, so the instrument would not be at every "+
				"clock read", s, x.where)
		}
	}
	tOld := strings.Replace(strings.Replace(oldT, OW, "vim_time(void)\n{\n"+TICK+"    return time(nullptr);\n}", 1),
		OF, `    if (in_focus && last_time + 2 < (write(2, "TICK\n", 5), time(nullptr)))
    {
        last_time = (write(2, "TICK\n", 5), time(nullptr));
    }
`, 1)
	tNew := strings.Replace(newT, NW, "host_time(void)\n{\n"+TICK+"    return time(nullptr);\n}", 1)
	hoist := strings.Replace(tNew, NF, `    long        now = host_time();

    if (in_focus && last_time + 2 < now)
    {
        last_time = now;
    }
`, 1)
	files = append(files, ctl{"t_old", tOld}, ctl{"t_new", tNew}, ctl{"hoist", hoist})
	for _, c := range files {
		if c.text == newT || c.text == oldT {
			return stop("%s changed nothing, so it is not a control", c.name)
		}
		if err := os.WriteFile(T(c.name+".c"), []byte(c.text), 0o644); err != nil {
			return err
		}
	}
	r.say("eight controls written: m1 the input's `time` prototype written wrong, " +
		"m2 the input's time_T perturbed with the prototype LEFT ALONE, p1 the output " +
		"with the static_assert deleted and time_T perturbed, p2 and p3 the same " +
		"perturbations WITH the assert, t_old and t_new the instrumented pair -- five " +
		"bytes at every clock read on each side -- and hoist, which collapses " +
		"ui_focus_change's two reads into one")

	var wgNew, wgT, wgSyn, wgCanon sync.WaitGroup
	var errNew, errCanon error
	var canonLog []byte
	wgNew.Add(1)
	go func() { defer wgNew.Done(); errNew = link(f, T("new")) }()
	for _, v := range []string{"t_old", "t_new", "hoist"} {
		v := v
		wgT.Add(1)
		go func() { defer wgT.Done(); link(T(v+".c"), T(v)) }()
	}
	for _, v := range []string{"m1", "m2", "p1", "p2", "p3"} {
		v := v
		wgSyn.Add(1)
		go func() {
			defer wgSyn.Done()
			c := exec.Command("gcc", "-O0", "-fno-stack-protector", "-fsyntax-only", T(v+".c"))
			lf, _ := os.Create(T("w." + v))
			c.Stderr = lf
			c.Run()
			lf.Close()
		}()
	}
	os.WriteFile(T("canon.c"), []byte(newT), 0o644)
	wgCanon.Add(1)
	go func() {
		defer wgCanon.Done()
		canonLog, errCanon = exec.Command("sh", "tools/canon.sh", T("canon.c")).CombinedOutput()
	}()
	defer func() { wgNew.Wait(); wgT.Wait(); wgSyn.Wait(); wgCanon.Wait() }()

	// --- 1. the source, as arithmetic on the input ------------------------------
	beforeLines, _ := strconv.Atoi(strings.TrimSpace(beforeRaw))
	split := func(text, which string) (string, string, []string, int, error) {
		lines := strings.Split(text, "\n")
		var d []int
		for i, l := range lines {
			if strings.HasPrefix(strings.TrimLeft(l, " \t\n\v\f\r"), "#") {
				d = append(d, i)
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
			return "", "", nil, 0, stop("%s does not have eleven contiguous directives: %d at %s.  The "+
				"first one IS the boundary and every count below distinguishes the core "+
				"from the host", which, len(d), strings.Join(at, " "))
		}
		var c, b []string
		for _, l := range lines[:d[0]] {
			c = append(c, z32Strip(l))
		}
		for _, l := range lines[d[0]:] {
			b = append(b, z32Strip(l))
		}
		return strings.Join(c, "\n"), strings.Join(b, "\n"), lines, d[0], nil
	}
	ocore, obelow, olines, ocut, e := split(oldT, "old.c")
	if e != nil {
		return e
	}
	ncore, nbelow, nlines, ncut, e := split(newT, "the output")
	if e != nil {
		return e
	}
	cnt := func(re *regexp.Regexp, s string) int { return len(re.FindAllStringIndex(s, -1)) }
	if len(olines)-1 != beforeLines {
		r.bad("the state directory says the edit was handed %d lines and old.c has %d", beforeLines, len(olines)-1)
	}
	was, now := cnt(z32Time, ocore), cnt(z32Time, ncore)
	if was != 4 {
		r.bad("the INPUT's core names `time` %d times and this phase was written "+
			"against 4 -- the libc prototype, the wrapper's call and "+
			"ui_focus_change's two", was)
	}
	if now > 0 {
		r.bad("the output's core still names `time` %d times, and the whole product "+
			"of this phase is that it names it none", now)
	}
	if n := cnt(z32VimTime, newT); n > 0 {
		r.bad("`vim_time` survives in the output, %d times", n)
	}
	for _, x := range []struct {
		where, text string
		want        int
		why         string
	}{
		{"above the boundary", ncore, 8, "the declaration and seven call sites"},
		{"below the boundary", nbelow, 1, "its definition"},
	} {
		if n := cnt(z32Host, x.text); n != x.want {
			r.bad("`host_time` occurs %d times %s where %d were expected -- %s", n, x.where, x.want, x.why)
		}
	}
	calls := cnt(z32HostC, ncore)
	owrap := cnt(z32VimC, ocore)
	obypass := cnt(z32Null, ocore) - 1
	if calls != owrap+obypass {
		r.bad("the core makes %d calls to host_time() and the input made %d to "+
			"vim_time() and %d directly to time(nullptr) outside the wrapper", calls, owrap, obypass)
	}
	if owrap != 5 || obypass != 2 {
		r.bad("the input had %d wrapper calls and %d bypassing ones, where 5 and 2 "+
			"were counted", owrap, obypass)
	}
	if cnt(z32Time, nbelow) != cnt(z32Time, obelow)+1 {
		r.bad("`time` is %d below the boundary and the input had %d there: host_time "+
			"brings exactly one call with it, beside the `#include <time.h>`",
			cnt(z32Time, nbelow), cnt(z32Time, obelow))
	}
	if n := cnt(z32TimeT, ncore+nbelow); n != 1 {
		r.bad("`time_t` is named %d times in the file's CODE and must be named once "+
			"-- the static_assert, which is the only place a core name and a header "+
			"name are both in scope.  The assert's own message says the name again "+
			"and is a literal", n)
	}
	if cnt(z32TimeTT, ncore) != cnt(z32TimeTT, ocore)-2 {
		r.bad("`time_T` is %d in the core and the input had %d: the two that go are "+
			"the wrapper's prototype and its definition head", cnt(z32TimeTT, ncore), cnt(z32TimeTT, ocore))
	}
	const DECL = "static void host_message(const char *msg, int len, int err);\nstatic long host_time(void);\n"
	if !strings.Contains(newT, DECL) {
		r.bad("`static long host_time(void);` is not on the line after " +
			"host_message's declaration: the host block is ONE block and this is " +
			"the fourteenth name in it")
	}
	if !strings.Contains(ncore, "typedef long        time_T;") {
		r.bad("`typedef long        time_T;` is not in the core, so host_time " +
			"returning `long` would be a conversion at seven call sites rather than " +
			"an assignment")
	}
	const DEF = "    static long\nhost_time(void)\n{\n    return time(nullptr);\n}\n"
	if strings.Count(newT, DEF) != 1 {
		r.bad("host_time's definition is not below the boundary exactly once in the " +
			"shape the edit wrote")
	}
	if !strings.Contains(nbelow+"\n", DEF) {
		r.bad("host_time is defined above the boundary")
	}
	block := func(lines []string, which string) ([]string, error) {
		var at []int
		for i, l := range lines {
			if l == "void *malloc(usize n);" {
				at = append(at, i)
			}
		}
		if len(at) != 1 {
			return nil, stop("`void *malloc(usize n);` is not on a line of its own exactly "+
				"once in %s, so the prototype block cannot be found", which)
		}
		a, b := at[0], at[0]
		for a > 0 && strings.TrimSpace(lines[a-1]) != "" {
			a--
		}
		for b+1 < len(lines) && strings.TrimSpace(lines[b+1]) != "" {
			b++
		}
		return lines[a : b+1], nil
	}
	ob, e := block(olines, "old.c")
	if e != nil {
		return e
	}
	nb, e := block(nlines, "the output")
	if e != nil {
		return e
	}
	notIn := func(a, b []string) []string {
		var out []string
		for _, x := range a {
			if !contains(b, x) {
				out = append(out, x)
			}
		}
		return out
	}
	if lost := notIn(ob, nb); strings.Join(lost, "\x00") != "long time(long *tp);" {
		r.bad("the prototype block lost %s and this phase removes exactly "+
			"`long time(long *tp);`", strings.Join(lost, " / "))
	}
	if gained := notIn(nb, ob); len(gained) > 0 {
		r.bad("the prototype block gained %s", strings.Join(gained, " / "))
	}
	if len(nb) != len(ob)-1 {
		r.bad("the prototype block is %d lines and was %d", len(nb), len(ob))
	}
	if ncut-ocut != -7 {
		r.bad("the core is %d lines and was %d, a difference of %d where -7 was "+
			"expected: -1 for the forward declaration, +1 for the host-block one, "+
			"-6 for the definition with its blank and -1 for the libc prototype", ncut, ocut, ncut-ocut)
	}
	if hd := (len(nlines) - ncut) - (len(olines) - ocut); hd != 7 {
		r.bad("the host is %d lines and was %d, a difference of %d where +7 was "+
			"expected: +6 for the definition with its blank and +1 for the "+
			"static_assert", len(nlines)-ncut, len(olines)-ocut, hd)
	}
	if len(nlines) != len(olines) {
		r.bad("the file is %d lines and was %d, and the two halves were expected to "+
			"cancel exactly", len(nlines)-1, len(olines)-1)
	}
	if z27Runs(nlines) != z27Runs(olines) {
		r.bad("the edit left %d runs of two blank lines where there were %d", z27Runs(nlines), z27Runs(olines))
	}
	if err := r.done(); err != nil {
		return err
	}
	r.say("THE CORE DOES NOT NAME `time` AT ALL: %d mentions in the input's core -- "+
		"the libc prototype, the wrapper's call and ui_focus_change's TWO -- and 0 here, "+
		"counted on the literal-stripped text because two NGETTEXT strings say the English "+
		"word.  `host_time` is 8 above the boundary and 1 below, and its %d call sites are "+
		"the input's %d wrapper calls plus the %d that bypassed it", was, calls, owrap, obypass)
	r.say("the boundary crosses as `static long host_time(void);`, on the line below " +
		"host_message's, and NOT as `time_T`: the definition is below the boundary and the " +
		"host cannot name a core typedef once the file is cut, which is musl_now_ms's own " +
		"reason.  `typedef long        time_T;` is what makes every call site an assignment " +
		"and not a conversion")
	var bnames []string
	for _, l := range nb {
		fs := strings.Fields(strings.SplitN(l, "(", 2)[0])
		name := ""
		if len(fs) > 0 {
			name = strings.TrimLeft(fs[len(fs)-1], "*")
		}
		bnames = append(bnames, name)
	}
	r.say("the libc prototype block is %d lines and was %d, losing `long time(long "+
		"*tp);` and nothing else: %s", len(nb), len(ob), strings.Join(bnames, " "))
	r.say("the core is %d lines against %d (-7) and the host %d against %d (+7), so "+
		"the file is %d lines either side, and `time_t` is named ONCE in the whole file -- "+
		"the static_assert", ncut, ocut, len(nlines)-ncut, len(olines)-ocut, len(nlines)-1)

	// --- 2. THE GUARANTEE, as four compiles -------------------------------------
	wgSyn.Wait()
	wl := func(v string) string { return readFile(T("w." + v)) }
	if !strings.Contains(wl("m1"), "conflicting types for 'time'") {
		r.say("m1 -- the INPUT's `long time(long *tp);` written `int time(int *tp);` -- did not give " +
			"`conflicting types for 'time'`, so the prototype this phase removes was not a check after all and " +
			"there is nothing to replace:")
		head(fileLines(T("w.m1")), 6, "")
		return harness.ErrReported
	}
	if sizeOf(T("w.m2")) > 0 {
		r.say("m2 -- the INPUT's time_T perturbed to `int` with the prototype LEFT ALONE -- was expected to " +
			"compile SILENTLY, and did not:")
		head(fileLines(T("w.m2")), 6, "")
		return harness.ErrReported
	}
	if sizeOf(T("w.p1")) > 0 {
		r.say("p1 -- the OUTPUT with the static_assert deleted and time_T perturbed to `int` -- was expected " +
			"to compile SILENTLY, which is the hole this phase would leave, and did not:")
		head(fileLines(T("w.p1")), 6, "")
		return harness.ErrReported
	}
	for _, v := range []string{"p2", "p3"} {
		if !strings.Contains(wl(v), `static assertion failed: "time_T is time_t"`) {
			r.say("%s -- the OUTPUT with time_T perturbed and the static_assert PRESENT -- did not fail the "+
				"assertion, so the guarantee that replaces the prototype cannot be broken and is therefore not "+
				"a guarantee:", v)
			head(fileLines(T("w."+v)), 6, "")
			return harness.ErrReported
		}
	}
	r.say("THE PROTOTYPE WAS LOAD-BEARING AND WHAT REPLACES IT IS STRONGER, in four compiles.  m1: the input's " +
		"`long time(long *tp);` written `int time(int *tp);` is `conflicting types for 'time'` from <time.h> " +
		"below it -- that WAS the guarantee, and it is what phase 26 relied on when it wrote `typedef long " +
		"time_T;`.  m2: the same input with `time_T` perturbed to `int` and the prototype LEFT ALONE compiles " +
		"in SILENCE -- so the prototype pinned `long == time_t` and never `time_T == long`.  p1: the output " +
		"with the static_assert deleted and time_T perturbed compiles in silence too -- that is the regression " +
		"this phase would have shipped.  p2 and p3: with the assert present, `int` and `long long` both give " +
		"`static assertion failed: \"time_T is time_t\"`.  The one line names time_T ITSELF, which the " +
		"prototype could not")

	// --- 3. the editor.c cut, and its warning set compared WITH THE INPUT'S ------
	bset := map[string][]string{}
	cutN := map[string]int{}
	for _, x := range []struct{ side, src string }{{"old", oldC}, {"new", f}} {
		lines := z28Cut(readFile(x.src))
		var dl []string
		for i, l := range lines {
			if z30Dir.MatchString(l) {
				dl = append(dl, fmt.Sprintf("%d:%s", i+1, l))
			}
		}
		if len(dl) > 0 {
			r.say("the %s cut holds a directive, so it found the wrong line:", x.side)
			head(dl, 3, "")
			return harness.ErrReported
		}
		text := ""
		for _, l := range lines {
			text += l + "\n"
		}
		cp := T("ed." + x.side + ".c")
		os.WriteFile(cp, []byte(text), 0o644)
		c := exec.Command("gcc", "-O0", "-fno-stack-protector", "-Wall", "-Wextra", "-Wno-unused-parameter",
			"-fsyntax-only", cp)
		var eb strings.Builder
		c.Stderr = &eb
		c.Run()
		var errs, warns []string
		for _, l := range strings.Split(eb.String(), "\n") {
			if strings.Contains(l, ": error:") {
				errs = append(errs, l)
			}
			if strings.Contains(l, ": warning: ") && !strings.Contains(l, "used but never defined") {
				warns = append(warns, l)
			}
		}
		if len(errs) > 0 {
			r.say("the %s cut does not parse on its own:", x.side)
			head(errs, 4, "")
			return harness.ErrReported
		}
		set := map[string]bool{}
		for _, m := range z30Undef.FindAllStringSubmatch(eb.String(), -1) {
			set[m[1]] = true
		}
		bset[x.side] = z27Keys(set)
		if len(warns) > 0 {
			r.say("the %s cut has a warning that is not a boundary name:", x.side)
			head(warns, 3, "")
			return harness.ErrReported
		}
		cutN[x.side] = len(lines)
	}
	gone := z31Words(minus26(bset["old"], bset["new"]))
	came := z31Words(minus26(bset["new"], bset["old"]))
	if gone != "" || came != "host_time " {
		return stop("the core -> host boundary moved by something other than host_time arriving: gone [%s] "+
			"arrived [%s].  This phase adds exactly one name to it and takes none away", gone, came)
	}
	r.say("the `make editor.c` cut: %d lines -> %d, 0 directives, 0 errors under `-fsyntax-only`, and the "+
		"WHOLE warning set is the core -> host boundary -- %d names -> %d, with `host_time` ARRIVING and "+
		"NOTHING gone, compared name by name at run time and never written out here (phase 28 renamed one of "+
		"them and phase 31 renames none)", cutN["old"], cutN["new"], len(bset["old"]), len(bset["new"]))

	// --- 4. canon.sh ----------------------------------------------------------------
	wgCanon.Wait()
	if errCanon != nil {
		r.say("tools/canon.sh failed on the output:")
		head(strings.Split(string(canonLog), "\n"), 10, "")
		return harness.ErrReported
	}
	if !z30Same(f, T("canon.c")) {
		r.say("tools/canon.sh is not a no-op on the output -- the new text is not written the way this file " +
			"writes everything else:")
		head(z30Diff(f, T("canon.c")), 12, "")
		return harness.ErrReported
	}
	r.say("tools/canon.sh is a NO-OP on the output: host_time's declaration, its definition and the " +
		"static_assert are written the way this file writes everything else")

	// --- 5. the host's vocabulary is still the host's ------------------------------
	zh := exec.Command("sh", "tools/st.sh", "zhostonly", f)
	zh.Stdout, zh.Stderr = w, w
	if err := zh.Run(); err != nil {
		return harness.ErrReported
	}

	// --- 6. the symbols, and the binary ----------------------------------------------
	wgNew.Wait()
	if errNew != nil {
		return stop("the output did not build with '%s' '%s'", cflagsS, ldflagsS)
	}
	for _, x := range []struct{ src, obj string }{{oldC, "old.o"}, {f, "new.o"}} {
		if out, err := exec.Command("gcc", "-c", "-O0", "-fno-stack-protector", "-o", T(x.obj), x.src).CombinedOutput(); err != nil {
			w.Write(out)
			return harness.ErrReported
		}
	}
	uOld := nmField26(T("old.o"), []string{"-u"}, 1)
	uNew := nmField26(T("new.o"), []string{"-u"}, 1)
	if g, c := minus26(uOld, uNew), minus26(uNew, uOld); len(g)+len(c) > 0 {
		return stop("`nm -u` moved: gone [%s] arrived [%s].  MOVING A CALL FROM THE CORE INTO THE HOST INSIDE "+
			"ONE TRANSLATION UNIT FREES NOTHING AND NEEDS NOTHING", z31Words(g), z31Words(c))
	}
	if !contains(uNew, "time") {
		return stop("`time` is NOT in the undefined set, and it must be: the host still calls it to implement " +
			"host_time()")
	}
	ext := nmField26(T("new.o"), []string{"--extern-only", "--defined-only"}, 2)
	if s := z31Words(ext); s != "main " {
		return stop("the output defines external symbols other than main: %s", s)
	}
	if z30Same(T("new"), filepath.Join(state, "old")) {
		return stop("the output binary is byte-identical to the input's, which cannot be: a call replaces an " +
			"inlined read at two sites and five lines of definition move past two thousand")
	}
	r.say("`nm -u` is THE SAME SET, %d names, as a `comm` empty in BOTH directions, and `main` is still the "+
		"only external symbol.  `time` IS STILL THERE and this phase says so as an equality, exactly as phase "+
		"28 did for `gettimeofday`: the host calls it to implement host_time(), and a symbol leaves when its "+
		"last CALLER leaves the FILE, which is the split and not this phase.  The binary is %d bytes against %d "+
		"and they are NOT the same bytes", len(uNew), sizeOf(T("new")), sizeOf(filepath.Join(state, "old")))
	pc := exec.Command("sh", "tools/phasecheck.sh", work, f, filepath.Join(state, "symbols"))
	pc.Stdout, pc.Stderr = w, w
	if err := pc.Run(); err != nil {
		return harness.ErrReported
	}

	// --- 7. the reads, instrumented, and the recordings ------------------------------
	wgT.Wait()
	for _, v := range []string{"t_old", "t_new", "hoist"} {
		if _, e := os.Stat(T(v)); e != nil {
			return stop("the %s build did not finish", v)
		}
	}
	oldBin, _ := filepath.Abs(filepath.Join(state, "old"))
	var wgR, wgC sync.WaitGroup
	recErr := make([]error, 2)
	casErr := make([]error, 2)
	for k, x := range []struct{ bin, src, out string }{{oldBin, oldC, "REC.old"}, {T("new"), f, "REC.new"}} {
		k, x := k, x
		wgR.Add(1)
		go func() {
			defer wgR.Done()
			recErr[k] = exec.Command("sh", "tools/zrecord.sh", x.bin, x.src, T(x.out)).Run()
		}()
	}
	for k, x := range []struct{ bin, out string }{{T("t_old"), "SC.told"}, {T("t_new"), "SC.tnew"}} {
		k, x := k, x
		wgC.Add(1)
		go func() {
			defer wgC.Done()
			casErr[k] = exec.Command("sh", "tools/st.sh", "zcases", x.bin, T(x.out)).Run()
		}()
	}

	// `\033[I` and `\033[O` are KE_FOCUSGAINED and KE_FOCUSLOST, registered
	// unconditionally by set_termname(), so a keystroke file reaches
	// ui_focus_change() -- the one clock reader no screen case touches.
	probes := []struct {
		name string
		keys string
		want int
	}{
		{"focus", "\x1b[O\x1b[I:q!\r", 3},
		{"focus_twice", "\x1b[O\x1b[I\x1b[O\x1b[I:q!\r", 4},
		{"edit", "ihi\x1b:q!\r", 2},
		{"undo", "ihi\x1bu:q!\r", 3},
		{"plainq", ":q!\r", 1},
	}
	res := map[string]map[string]z32Res{}
	for _, who := range []string{"t_old", "t_new", "hoist"} {
		res[who] = map[string]z32Res{}
		for _, p := range probes {
			_, _, se, rc, err := harness.ZSession(T(who), [][]byte{[]byte(p.keys)}, "xterm", nil, 24, 80, 8*time.Second)
			if err != nil {
				res[who][p.name] = z32Res{}
				continue
			}
			res[who][p.name] = z32Res{true, bytes.Count(se, []byte("TICK")), rc}
		}
	}
	r7 := &rep{tag: "wallclock", w: w}
	for _, p := range probes {
		for _, who := range []string{"t_old", "t_new"} {
			g := res[who][p.name]
			if !g.ok {
				r7.bad("%s: the %s probe never returned", who, p.name)
				continue
			}
			if g.rc != 0 {
				r7.bad("%s: the %s probe exited %d", who, p.name, g.rc)
			}
			if g.got != p.want {
				r7.bad("%s: the %s probe recorded %d clock reads and %d were expected", who, p.name, g.got, p.want)
			}
		}
		o, n := res["t_old"][p.name], res["t_new"][p.name]
		if o.ok != n.ok || (o.ok && o.got != n.got) {
			r7.bad("the %s probe reads the clock %s times on the binary this phase was "+
				"handed and %s times on its own.  The phase renames a read and moves "+
				"it; it does not add or remove one", p.name, o.show(), n.show())
		}
	}
	if h := res["hoist"]["focus_twice"]; !h.ok || h.got != 5 {
		r7.bad("the `hoist` control -- ui_focus_change reading the clock ONCE into a "+
			"local -- recorded %s clock reads on `focus_twice` and 5 were expected: "+
			"one per call plus the :q!.  If collapsing the two reads does not move "+
			"the probe, the probe cannot see whether they were collapsed", h.show())
	}
	if h, n := res["hoist"]["focus"], res["t_new"]["focus"]; h.ok != n.ok || (h.ok && h.got != n.got) {
		r7.bad("the `hoist` control moved the `focus` probe, where the arithmetic says " +
			"it must not: 1 + 1 against 0 + 2, plus the :q!, is 3 either way.  If " +
			"that has changed, the reasoning behind `focus_twice` needs re-doing")
	}
	if err := r7.done(); err != nil {
		return err
	}
	tn := res["t_new"]
	r.say("THE READS ARE THE SAME READS, at every probe: `focus` %s, `focus_twice` "+
		"%s, `edit` %s, `undo` %s, `plainq` %s -- identical on the instrumented input and "+
		"the instrumented output.  ui_focus_change still reads the clock TWICE, in two "+
		"statements, in the same order: at `focus_twice` the four calls read 0, 2, 0 and 1 "+
		"times, because in_focus FALSE short-circuits and the second FocusGained finds "+
		"last_time fresh", tn["focus"].show(), tn["focus_twice"].show(), tn["edit"].show(),
		tn["undo"].show(), tn["plainq"].show())
	r.say("AND THE INSTRUMENT CAN SEE A COLLAPSED READ: `hoist`, the output with "+
		"ui_focus_change's two reads hoisted into one local, reads ONCE PER CALL and "+
		"gives `focus_twice` %s against the product's %s.  So \"can the two reads straddle "+
		"a second differently now\" is answered by measurement -- the program that would "+
		"make it true is a DIFFERENT program and the probe says so",
		res["hoist"]["focus_twice"].show(), tn["focus_twice"].show())

	// Collected by bare `wait $pid`s, as the shell does: a recording that fails
	// ends the check with nothing printed.  One of the fifteen sites a later
	// pass repairs; repairing it here would break report identity.
	wgC.Wait()
	for _, e := range casErr {
		if e != nil {
			return harness.ErrReported
		}
	}
	if dl := diffRQ(T("SC.told"), T("SC.tnew")); len(dl) > 0 {
		r.say("the two INSTRUMENTED 102-case recordings differ, so the clock is read a different number of " +
			"times or in a different order somewhere in the corpus:")
		head(dl, 12, "")
		return harness.ErrReported
	}
	marked, total := 0, 0
	ents, _ := os.ReadDir(T("SC.tnew"))
	for _, en := range ents {
		d := readFile(filepath.Join(T("SC.tnew"), en.Name()))
		n := 0
		for _, l := range strings.Split(d, "\n") {
			if strings.Contains(l, "TICK") {
				n++
			}
		}
		if n > 0 {
			marked++
		}
		total += n
	}
	if marked < 1 {
		return stop("the instrument marks NO screen case, so the byte-identical instrumented recording above " +
			"is two empty files agreeing")
	}
	r.say("THE INSTRUMENTED PAIR: the same five bytes at EVERY clock read on each side -- three sites on the "+
		"input (the wrapper and ui_focus_change's two, which bypass it) and one on the output, because after "+
		"this phase there is only one -- and the two 102-case recordings are BYTE-IDENTICAL.  The instrument is "+
		"not silent: it marks %d of 102 cases with %d reads in all, the two it does not being ctrl_c_clean and "+
		"ctrl_c_changed, which exit before a key is looked up", marked, total)
	wgR.Wait()
	for _, e := range recErr {
		if e != nil {
			return harness.ErrReported
		}
	}
	if dl := diffRQ(T("REC.old"), T("REC.new")); len(dl) > 0 {
		r.say("the declared delta is NOTHING AT ALL and the two recordings differ:")
		head(dl, 12, "")
		return harness.ErrReported
	}
	r.say("the declared delta is NOTHING AT ALL and TWO FULL RECORDINGS ARE BYTE-IDENTICAL -- 102 screen " +
		"cases, every Ex command, every command line, the pty scenarios and the terminal table.  On its own " +
		"that would say little, the corpus never reaching ui_focus_change at all; what answers for this phase " +
		"is the instrumented pair and the focus probes above")
	return nil
}
