package check

import (
	"bytes"
	"fmt"
	"io"
	"math"
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

func init() { register("zero28", Zero28) }

var (
	z28CFlags  = regexp.MustCompile(`(?m)^CFLAGS  *= *(.*)$`)
	z28LDFlags = regexp.MustCompile(`(?m)^LDFLAGS  *= *(.*)$`)
	z28Inc     = regexp.MustCompile(`^ *# *include `)
	z28Hash    = regexp.MustCompile(`^ *#`)
	z28Stamp   = regexp.MustCompile(`(?m)^\s*(?:\w+\.)?start_tv = musl_now_ms\(\);$`)
	z28Read    = regexp.MustCompile(`musl_now_ms\(\) - (?:\w+\.)?start_tv\b`)
	z28TV      = regexp.MustCompile(`struct timeval\b`)
	z28ErrLine = regexp.MustCompile(`(?m)^[^ ].*: error:.*$`)
	z28Undef   = regexp.MustCompile(`'(\w+)' used but never defined`)
	z28Scalar  = regexp.MustCompile(`^(?:const +)?(?:void|int|long|char|usize) *\**$`)
	z28ParmNm  = regexp.MustCompile(`\b[A-Za-z_]\w* *$`)
	z28WS      = regexp.MustCompile(`\s+`)
)

var z28Declared = strings.Fields("host_exit host_message musl_delay musl_get_winsize " +
	"musl_host_init musl_now_ms musl_read_input musl_suspend musl_term_start " +
	"musl_term_stop musl_tty_keys musl_wait_for_input vim_snprintf")

const z28Gone = "musl_gettimeofday"

// z28RoundC is the rounding probe, written and run here so that the claim in
// the edit's header is a measurement at every boundary and not a memory.
// `srandom(12345)`, so its output is the same every run and the report line it
// feeds is stable where the timing probes are not.
const z28RoundC = `#include <stdio.h>
#include <stdlib.h>
static long old_f(long s1, long u1, long s2, long u2)
{ return (s2 - s1) * 1000L + (u2 - u1) / 1000L; }
static long now_ms(long s, long u, long b)
{ return (s - b) * 1000L + u / 1000L; }
int main(void)
{
    long b = 1000000, n = 20000000, i, worst = 0, d[3] = {0, 0, 0};
    double miss_old = 0, miss_new = 0;
    srandom(12345);
    for (i = 0; i < n; i++) {
        long s1 = b + random() % 100, u1 = random() % 1000000;
        long gap = random() % 5000000;
        long t1 = s1 * 1000000L + u1, t2 = t1 + gap;
        long s2 = t2 / 1000000L, u2 = t2 % 1000000L;
        long o = old_f(s1, u1, s2, u2);
        long w = now_ms(s2, u2, b) - now_ms(s1, u1, b);
        long delta = w - o;
        if (delta < -1 || delta > 1) { printf("RANGE %ld\n", delta); return 1; }
        d[delta + 1]++;
        if (labs(delta) > worst) worst = labs(delta);
        miss_old += (double)(o - gap / 1000);
        miss_new += (double)(w - gap / 1000);
    }
    printf("pairs %ld  minus1 %ld  same %ld  plus1 %ld  worst %ld  mean_old %+.4f  mean_new %+.4f\n",
           n, d[0], d[1], d[2], worst, miss_old / n, miss_new / n);
    return 0;
}
`

// z28Cut is `make editor.c`'s rule character for character: stop at the first
// `#include`, drop the trailing blank lines -- where BLANK means `strip()` is
// empty, so a line of spaces counts.  zero27's cut tests `== ""` instead; the
// two are different rules and each port keeps its own heredoc's.
func z28Cut(text string) []string {
	var keep []string
	last := 0
	for _, line := range strings.Split(text, "\n") {
		if z28Inc.MatchString(line) {
			break
		}
		keep = append(keep, line)
		if strings.TrimSpace(line) != "" {
			last = len(keep)
		}
	}
	return keep[:last]
}

// z28Args is the heredoc's `argsof`: the parameter list by BRACE MATCHING and
// not by a split on the first `(`.  `__attribute__((format(printf, 3, 4)))`
// carries parentheses and commas of its own, and a naive split reads them as
// parameters -- measured, three of them.
func z28Args(decl, name string) (string, []string) {
	i := strings.Index(decl, name) + len(name)
	for i < len(decl) && (decl[i] == ' ' || decl[i] == '\t') {
		i++
	}
	d, j := 0, i
	for j < len(decl) {
		if decl[j] == '(' {
			d++
		} else if decl[j] == ')' {
			d--
			if d == 0 {
				break
			}
		}
		j++
	}
	inner := decl[i+1 : j]
	var out []string
	d, last := 0, 0
	for x := 0; x < len(inner); x++ {
		switch inner[x] {
		case '(':
			d++
		case ')':
			d--
		case ',':
			if d == 0 {
				out = append(out, inner[last:x])
				last = x + 1
			}
		}
	}
	out = append(out, inner[last:])
	for k := range out {
		out[k] = strings.TrimSpace(out[k])
	}
	return decl[len("static"):strings.Index(decl, name)], out
}

type z28Probe struct {
	name  string
	keys  []byte
	bells int
}

// `gs` IS nv_g_cmd's `s` arm and it is do_sleep(count * 1000): the one call
// site a keystroke file can drive, and the only way real time passes inside
// the editor.
var z28Probes = []z28Probe{
	{"1gs", []byte("gs:q!\r"), 0},
	{"2gs", []byte("2gs:q!\r"), 0},
	{"hgshh", []byte("hgshh:q!\r"), 2},
}

type z28Res struct {
	ms, bells, rc int
	ok            bool // false is Python's (None, None, None): the probe blocked
}

// Zero28 is phase 28's check: the scalar clock.
func Zero28(w io.Writer, args []string) error {
	if len(args) != 2 {
		return fmt.Errorf("usage: check zero28 <work-dir> <state-dir>")
	}
	work, state := args[0], args[1]
	f := filepath.Join(work, "zero-vim.c")
	r := &rep{tag: "clock", w: w}
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
	tmp, err := os.MkdirTemp("", "zero28-")
	if err != nil {
		return err
	}
	defer os.RemoveAll(tmp)

	mk := readFile(filepath.Join(work, "Makefile"))
	cflags := strings.Fields(z28CFlags.FindStringSubmatch(mk)[1])
	ldflags := strings.Fields(z28LDFlags.FindStringSubmatch(mk)[1])
	link := func(src, out string) *exec.Cmd {
		a := append(append([]string{}, cflags...), ldflags...)
		a = append(a, "-o", out, src)
		c := exec.Command("gcc", a...)
		c.Env = append(os.Environ(), "SOURCE_DATE_EPOCH=0")
		return c
	}

	t := readFile(f)

	// ---- the six variants ------------------------------------------------
	const ret = "    return (tv.tv_sec - host_now_base) * 1000L + tv.tv_usec / 1000L;"
	const beep = "        if (!did_init || musl_now_ms() - start_tv > 500)"
	if strings.Count(t, ret) != 1 {
		return stop("musl_now_ms does not compute its answer in exactly one line, so not " +
			"one of the variants below could be built from it")
	}
	variants := []struct{ name, old, line string }{
		{"ceil", ret, "    return (tv.tv_sec - host_now_base) * 1000L + (tv.tv_usec + 999) / 1000L;"},
		{"epoch", ret, "    return tv.tv_sec * 1000L + tv.tv_usec / 1000L;"},
		{"fast", ret, "    return (tv.tv_sec - host_now_base) * 1000000L + tv.tv_usec;"},
		{"froze", ret, "    return (tv.tv_sec - host_now_base) * 0L + tv.tv_usec * 0L;"},
		// THE BELL PROBE NEEDS CONTROLS OF ITS OWN, and they move vim_beep's
		// THRESHOLD rather than the clock: a clock control that breaks the rate
		// limit breaks do_sleep first, and `hgshh` then never returns at all.
		{"nobell", beep, strings.Replace(beep, "> 500", "> 500000", 1)},
		{"allbell", beep, strings.Replace(beep, "> 500", "> -1", 1)},
	}
	for _, v := range variants {
		if strings.Count(t, v.old) != 1 {
			return stop("the line the %s variant rewrites is not in the output exactly "+
				"once, so it could not be a control", v.name)
		}
		nv := strings.Replace(t, v.old, v.line, 1)
		if nv == t {
			return stop("the %s variant changed nothing, so it is not a control", v.name)
		}
		if err := os.WriteFile(filepath.Join(tmp, v.name+".c"), []byte(nv), 0o644); err != nil {
			return err
		}
	}
	r.say("six variants written: ceil (every reading rounded UP), epoch (milliseconds " +
		"since 1970), fast (microseconds, so 1000x), froze (a clock that never " +
		"advances), and nobell/allbell, which move vim_beep's 500 to 500000 and to -1")

	var wg sync.WaitGroup
	var errNew error
	wg.Add(1)
	go func() { defer wg.Done(); errNew = link(f, filepath.Join(tmp, "new")).Run() }()
	for _, v := range variants {
		name := v.name
		wg.Add(1)
		go func() {
			defer wg.Done()
			link(filepath.Join(tmp, name+".c"), filepath.Join(tmp, name)).Run()
		}()
	}
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
	var errRound error
	wg.Add(1)
	go func() {
		defer wg.Done()
		rc := filepath.Join(tmp, "round.c")
		os.WriteFile(rc, []byte(z28RoundC), 0o644)
		if e := exec.Command("gcc", "-O2", "-o", filepath.Join(tmp, "round"), rc).Run(); e != nil {
			errRound = e
			return
		}
		out, e := exec.Command(filepath.Join(tmp, "round")).Output()
		errRound = e
		os.WriteFile(filepath.Join(tmp, "round.txt"), out, 0o644)
	}()

	// ---- 1. the source, as arithmetic on the input -----------------------
	old := readFile(filepath.Join(state, "old.c"))
	split := func(text, which string) (string, string, []string, int, error) {
		lines := strings.Split(text, "\n")
		var d []int
		for i, l := range lines {
			if strings.HasPrefix(strings.TrimLeft(l, " \t\n\v\f\r"), "#") {
				d = append(d, i)
			}
		}
		ok := len(d) == 11
		for k, i := range d {
			if ok && i != d[0]+k {
				ok = false
			}
		}
		if !ok {
			var at []string
			for i, x := range d {
				if i >= 3 {
					break
				}
				at = append(at, strconv.Itoa(x+1))
			}
			return "", "", nil, 0, stop("%s does not have eleven contiguous directives: %d "+
				"at %s.  The first one IS the boundary and every count below "+
				"distinguishes the core from the host", which, len(d), strings.Join(at, " "))
		}
		return strings.Join(lines[:d[0]], "\n"), strings.Join(lines[d[0]:], "\n"), lines, d[0], nil
	}
	_, obelow, olines, ocut, e := split(old, "old.c")
	if e != nil {
		return e
	}
	ncore, nbelow, nlines, ncut, e := split(t, "the output")
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
	for _, name := range []string{"elapsed_T", "elapsed", "now_tv", "musl_gettimeofday"} {
		was, now := count(old, `\b`+name+`\b`), count(t, `\b`+name+`\b`)
		if now != 0 {
			r.bad("`%s` was %d in the input and is still %d in the output -- this phase's "+
				"whole product is that it is 0 everywhere", name, was, now)
		}
	}
	if n := len(z28TV.FindAllString(ncore, -1)); n > 0 {
		r.bad("`struct timeval` is back above the boundary, %d times", n)
	}
	tvh := len(z28TV.FindAllString(nbelow, -1))
	if oh := len(z28TV.FindAllString(obelow, -1)); tvh != oh {
		r.bad("`struct timeval` is %d below the boundary and the input had %d there: "+
			"musl_now_ms keeps musl_gettimeofday's one and adds none", tvh, oh)
	}
	if bare := count(t, `\bgettimeofday\b`); bare != 1 {
		r.bad("the bare name `gettimeofday` occurs %d times in the output and must occur "+
			"exactly once -- the call inside musl_now_ms", bare)
	}
	if count(ncore, `\bgettimeofday\b`) > 0 {
		r.bad("the core calls `gettimeofday` directly, which is the whole thing the host " +
			"call exists to prevent")
	}
	for _, x := range []struct {
		where, text string
		want        int
		why         string
	}{
		{"above the boundary", ncore, 9, "the prototype, four stamps and four readings"},
		{"below the boundary", nbelow, 1, "its definition"},
	} {
		if n := count(x.text, `\bmusl_now_ms\b`); n != x.want {
			r.bad("`musl_now_ms` occurs %d times %s where %d were expected -- %s",
				n, x.where, x.want, x.why)
		}
	}
	stamps := len(z28Stamp.FindAllString(ncore, -1))
	reads := len(z28Read.FindAllString(ncore, -1))
	if stamps != 4 || reads != 4 {
		r.bad("the core has %d stamps of the shape `X = musl_now_ms();` and %d readings "+
			"of the shape `musl_now_ms() - X`, where 4 and 4 were expected", stamps, reads)
	}
	if on, nn := count(old, `\belapsed_time\b`), count(t, `\belapsed_time\b`); on != nn {
		r.bad("`elapsed_time` is inchar_loop's own `long` and not this phase's, and it "+
			"moved from %d to %d", on, nn)
	}
	if ncut-ocut != -16 {
		r.bad("the core is %d lines and was %d, a difference of %d where -16 was "+
			"expected: -6 for the typedef and the prototype with a blank and -10 for "+
			"elapsed() with a blank", ncut, ocut, ncut-ocut)
	}
	hostN, hostO := len(nlines)-ncut, len(olines)-ocut
	if hostN-hostO != 6 {
		r.bad("the host is %d lines and was %d, a difference of %d where +6 was "+
			"expected: +4 for musl_now_ms's longer body and +2 for its two statics",
			hostN, hostO, hostN-hostO)
	}
	for _, line := range []string{"static long host_now_base = 0;", "static int host_now_based = FALSE;"} {
		if strings.Count(t, "\n"+line+"\n") != 1 {
			r.bad("`%s` is not on a line of its own exactly once below the boundary", line)
		}
	}
	if !strings.Contains(nbelow, "if (!host_now_based)") {
		r.bad("musl_now_ms does not take its base LAZILY.  Setting it in " +
			"musl_host_init() instead would be an ordering dependency a host rewrite " +
			"breaks silently, and the symptom would be base 0, epoch milliseconds and a " +
			"32-bit overflow on every call")
	}
	if rn, ro := z27Runs(nlines), z27Runs(olines); rn != ro {
		r.bad("the edit left %d runs of two blank lines where there were %d", rn, ro)
	}
	if err := r.done(); err != nil {
		return err
	}
	r.say("the core has NO clock of its own: elapsed_T (%d in the input), elapsed (%d), "+
		"now_tv (%d) and musl_gettimeofday (%d) are all 0 in the whole file, `struct "+
		"timeval` is 0 above the boundary and %d below, and the one bare `gettimeofday` "+
		"left is the call musl_now_ms makes",
		count(old, `\belapsed_T\b`), count(old, `\belapsed\b`), count(old, `\bnow_tv\b`),
		count(old, `\bmusl_gettimeofday\b`), tvh)
	r.say("four stamps `X = musl_now_ms();` and four readings `musl_now_ms() - X`, the "+
		"prototype above and the definition below: the core is %d lines against %d "+
		"(-16) and the host %d against %d (+6)", ncut, ocut, hostN, hostO)

	// ---- 2 and 3. the boundary: the cut, and the shape of what crosses it --
	r2 := &rep{tag: "clock", w: w}
	for _, x := range []struct{ which, path string }{
		{"output", f}, {"input", filepath.Join(state, "old.c")},
	} {
		lines := z28Cut(readFile(x.path))
		text := strings.Join(lines, "\n") + "\n"
		cp := filepath.Join(tmp, "cut."+x.which+".c")
		os.WriteFile(cp, []byte(text), 0o644)
		for _, l := range lines {
			if z28Hash.MatchString(l) {
				var dcount int
				for _, l2 := range lines {
					if z28Hash.MatchString(l2) {
						dcount++
					}
				}
				r2.bad("the %s cut holds %d directive(s), so it found the wrong line: %s",
					x.which, dcount, l)
				break
			}
		}
		wb, _ := exec.Command("gcc", "-O0", "-fno-stack-protector", "-Wall", "-Wextra",
			"-Wno-unused-parameter", "-fsyntax-only", cp).CombinedOutput()
		wtxt := string(wb)
		if errs := z28ErrLine.FindAllString(wtxt, -1); len(errs) > 0 {
			if len(errs) > 3 {
				errs = errs[:3]
			}
			r2.bad("the %s cut does not compile on its own:\n    %s",
				x.which, strings.Join(errs, "\n    "))
		}
		for _, l := range strings.Split(wtxt, "\n") {
			if strings.Contains(l, ": warning: ") && !strings.Contains(l, "used but never defined") {
				r2.bad("the %s cut has a warning that is not a boundary name: %s", x.which, l)
				break
			}
		}
		seenSet := map[string]bool{}
		for _, m := range z28Undef.FindAllStringSubmatch(wtxt, -1) {
			seenSet[m[1]] = true
		}
		seen := z27Keys(seenSet)
		var want []string
		if x.which == "output" {
			want = append(want, z28Declared...)
		} else {
			for _, n := range z28Declared {
				if n != "musl_now_ms" {
					want = append(want, n)
				}
			}
			want = append(want, z28Gone)
		}
		sort.Strings(want)
		if strings.Join(seen, "\x00") != strings.Join(want, "\x00") {
			r2.bad("the %s boundary is %s and this phase declares %s.  A phase that "+
				"widens the core -> host interface changes this set and nothing else in "+
				"the pipeline would say so", x.which, strings.Join(seen, " "), strings.Join(want, " "))
		}
		for _, name := range seen {
			reD := regexp.MustCompile(`^static\s.*\b` + regexp.QuoteMeta(name) + `\s*\(`)
			var decl []string
			for _, l := range lines {
				if reD.MatchString(l) && strings.HasSuffix(strings.TrimRight(l, " \t"), ";") {
					decl = append(decl, l)
				}
			}
			if len(decl) != 1 {
				r2.bad("the %s boundary name `%s` has %d declarations above the cut and "+
					"must have exactly one", x.which, name, len(decl))
				continue
			}
			retT, params := z28Args(decl[0], name)
			for _, a := range append([]string{retT}, params...) {
				a = strings.TrimSpace(z28WS.ReplaceAllString(a, " "))
				if a == "..." {
					if !strings.Contains(decl[0], "format(printf") {
						r2.bad("the %s boundary name `%s` is VARIADIC and carries no "+
							"`format(printf, ...)` attribute, so nothing constrains what "+
							"crosses in its argument list", x.which, name)
					}
					continue
				}
				bare := strings.TrimSpace(z28ParmNm.ReplaceAllString(a, ""))
				if !(z28Scalar.MatchString(a) || z28Scalar.MatchString(bare)) {
					r2.bad("the %s boundary name `%s` takes or returns `%s`, which is not "+
						"a scalar or a byte buffer", x.which, name, a)
				}
			}
		}
	}
	if err := r2.done(); err != nil {
		return err
	}
	decl := append([]string{}, z28Declared...)
	sort.Strings(decl)
	r.say("THE BOUNDARY IS THIRTEEN NAMES, stated as a SET: %s.  `musl_gettimeofday` is "+
		"REPLACED by `musl_now_ms` and not added to, and the cut is %d lines with 0 "+
		"directives, no error and no warning that is not one of the thirteen",
		strings.Join(decl, " "), len(z28Cut(t)))
	r.say("and EVERY ONE OF THE THIRTEEN TAKES SCALARS AND BYTE BUFFERS ONLY -- void, " +
		"int, long, usize, char * and int *, with vim_snprintf's `...` held to printf " +
		"arguments by `format(printf, 3, 4)` on a build that is -Wall -Wextra clean.  IT " +
		"IS TRUE OF THE INPUT TOO, and this phase does not claim to have made it so: " +
		"phase 26 wrote `musl_gettimeofday(long *, long *)` precisely so that `struct " +
		"timeval` would not cross.  WHAT THIS PHASE EARNS is that the workaround is gone " +
		"-- no host call's shape is decided any more by a type the core cannot name, and " +
		"the core declares nothing shaped like a libc struct")

	// ---- 4. the rounding, measured ---------------------------------------
	wg.Wait()
	if errRound != nil {
		return stop("the rounding probe did not build or did not run")
	}
	fields := strings.Fields(readFile(filepath.Join(tmp, "round.txt")))
	v := map[string]string{}
	for k := 0; k+1 < len(fields); k += 2 {
		v[fields[k]] = fields[k+1]
	}
	worst, _ := strconv.Atoi(v["worst"])
	if worst != 1 {
		return stop("the rounding probe found a worst-case disagreement of %d ms, where "+
			"the whole claim of this phase is that it is exactly 1", worst)
	}
	m1, _ := strconv.Atoi(v["minus1"])
	p1, _ := strconv.Atoi(v["plus1"])
	if m1 == 0 || p1 == 0 {
		return stop("the rounding probe found the disagreement in only one direction (%s "+
			"below, %s above), which would make the new formula systematically biased "+
			"rather than differently rounded", v["minus1"], v["plus1"])
	}
	mo, _ := strconv.ParseFloat(v["mean_old"], 64)
	mn, _ := strconv.ParseFloat(v["mean_new"], 64)
	if math.Abs(mo-mn) > 0.01 {
		return stop("the two formulas are %s and %s ms from the true elapsed time on "+
			"average, and the claim is that neither is better", v["mean_old"], v["mean_new"])
	}
	r.say("PRECISION IS NOT LOST AND THE ROUNDING POINT MOVES, measured over %s random "+
		"pairs: elapsed() subtracted and THEN divided, musl_now_ms divides at each "+
		"reading and the caller subtracts, and the two differ by EXACTLY +-1 ms and "+
		"never more -- %s pairs 1 ms lower, %s the same, %s 1 ms higher.  Microseconds "+
		"were already discarded either way, and neither formula is closer to the truth: "+
		"%s ms against %s ms on average.  Whether a CALLER can see 1 ms is section 8's "+
		"`ceil` control", v["pairs"], v["minus1"], v["same"], v["plus1"],
		v["mean_old"], v["mean_new"])

	// ---- 5. canon.sh ------------------------------------------------------
	if errCanon != nil {
		return fatal("tools/canon.sh failed on the output:", filepath.Join(tmp, "canon.log"), 10)
	}
	if readFile(canonC) != t {
		r.say("tools/canon.sh is not a no-op on the output -- the new text is not written " +
			"the way this file writes everything else:")
		return harness.ErrReported
	}
	r.say("tools/canon.sh is a NO-OP on the output: the four `long` declarations, the " +
		"four stamps, the four readings and musl_now_ms are written the way this file " +
		"writes everything else")

	// ---- 6. the host's vocabulary, which this phase extends --------------
	zh := exec.Command("sh", "tools/st.sh", "zhostonly", f)
	zh.Stdout, zh.Stderr = w, w
	if err := zh.Run(); err != nil {
		return harness.ErrReported
	}

	// ---- 7. the symbols ---------------------------------------------------
	if errNew != nil {
		return stop("the output did not build with '%s' '%s'",
			strings.Join(cflags, " "), strings.Join(ldflags, " "))
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
	if g, c := minus26(uOld, uNew), minus26(uNew, uOld); len(g)+len(c) > 0 {
		return stop("`nm -u` moved: gone [%s] arrived [%s].  THIS PHASE FREES NOTHING AND "+
			"NEEDS NOTHING", strings.Join(g, " ")+" ", strings.Join(c, " ")+" ")
	}
	hasGTOD := false
	for _, s := range uNew {
		if s == "gettimeofday" {
			hasGTOD = true
		}
	}
	if !hasGTOD {
		return stop("`gettimeofday` is NOT in the undefined set, and it must be: the host " +
			"still calls it to implement musl_now_ms")
	}
	ext := nmField26(filepath.Join(tmp, "new.o"), []string{"--extern-only", "--defined-only"}, 2)
	if s := strings.Join(ext, " ") + " "; s != "main " {
		return stop("the output defines external symbols other than main: %s", s)
	}
	r.say("`nm -u` is THE SAME SET, %d names, as a `comm` empty in BOTH directions, and "+
		"`main` is still the only external symbol.  `gettimeofday` IS STILL THERE and "+
		"this phase says so as an equality: a reader expects a clock phase to free a "+
		"clock symbol, and it cannot -- the host calls it to implement musl_now_ms, and "+
		"a symbol leaves when its last CALLER leaves the FILE, which is the split and not "+
		"this phase.  The output is %d bytes against %d", len(uNew),
		sizeOf(filepath.Join(tmp, "new")), sizeOf(filepath.Join(state, "old")))

	// ---- 8. the probes, and the recordings -------------------------------
	for _, vv := range variants {
		if sizeOf(filepath.Join(tmp, vv.name)) < 0 {
			return stop("the %s control did not build", vv.name)
		}
	}
	var wgR sync.WaitGroup
	for _, x := range []struct{ bin, src, out string }{
		{filepath.Join(state, "old"), filepath.Join(state, "old.c"), "REC.old"},
		{filepath.Join(tmp, "new"), f, "REC.new"},
		{filepath.Join(tmp, "ceil"), filepath.Join(tmp, "ceil.c"), "REC.ceil"},
		{filepath.Join(tmp, "epoch"), filepath.Join(tmp, "epoch.c"), "REC.epoch"},
	} {
		x := x
		wgR.Add(1)
		go func() {
			defer wgR.Done()
			exec.Command("sh", "tools/zrecord.sh", x.bin, x.src, filepath.Join(tmp, x.out)).Run()
		}()
	}

	run := func(bin string, keys []byte) (z28Res, error) {
		t0 := time.Now()
		_, stdout, _, rc, err := harness.ZSession(bin, [][]byte{keys}, "xterm", nil, 24, 80, 8*time.Second)
		if err == harness.ErrBlocked {
			return z28Res{}, nil
		}
		if err != nil {
			return z28Res{}, err
		}
		return z28Res{int(time.Since(t0) / time.Millisecond), bytes.Count(stdout, []byte{7}), rc, true}, nil
	}
	// SEQUENTIAL and in the Python's order, because the measurement is wall
	// time and running them at once would make each one's load the others'.
	type who struct{ name, path, which string }
	whos := []who{
		{"old", filepath.Join(state, "old"), "all"}, {"new", filepath.Join(tmp, "new"), "all"},
		{"ceil", filepath.Join(tmp, "ceil"), "all"}, {"epoch", filepath.Join(tmp, "epoch"), "all"},
		{"fast", filepath.Join(tmp, "fast"), "sleep"}, {"froze", filepath.Join(tmp, "froze"), "one"},
		{"nobell", filepath.Join(tmp, "nobell"), "bell"}, {"allbell", filepath.Join(tmp, "allbell"), "bell"},
	}
	wantBy := map[string][]string{
		"all": {"1gs", "2gs", "hgshh"}, "sleep": {"1gs", "2gs"},
		"one": {"1gs"}, "bell": {"hgshh"},
	}
	res := map[string]map[string]z28Res{}
	for _, x := range whos {
		res[x.name] = map[string]z28Res{}
		for _, p := range z28Probes {
			if !containsStr28(wantBy[x.which], p.name) {
				continue
			}
			got, err := run(x.path, p.keys)
			if err != nil {
				return err
			}
			res[x.name][p.name] = got
		}
	}

	r3 := &rep{tag: "clock", w: w}
	for _, who := range []string{"old", "new", "ceil", "epoch"} {
		for _, p := range z28Probes {
			g := res[who][p.name]
			if !g.ok {
				r3.bad("%s: the %s probe never returned", who, p.name)
				continue
			}
			if g.rc != 0 {
				r3.bad("%s: the %s probe exited %d", who, p.name, g.rc)
			}
			if g.bells != p.bells {
				r3.bad("%s: the %s probe rang %d bell(s) and %d were expected",
					who, p.name, g.bells, p.bells)
			}
		}
		one, two := res[who]["1gs"], res[who]["2gs"]
		if !one.ok || !two.ok {
			continue
		}
		if one.ms < 950 {
			r3.bad("%s: `1gs` returned after %d ms and do_sleep(1000) cannot be shorter "+
				"than 1,000", who, one.ms)
		}
		// A LOWER BOUND ON A SLEEP, NEVER A DIFFERENCE BETWEEN TWO RUNS: each run
		// carries its own startup jitter, and a sleep takes at least as long as it
		// asks for while load can only make it longer.
		if two.ms < 1900 {
			r3.bad("%s: `2gs` took %d ms, where two capped 1,000 ms waits were expected "+
				"-- do_sleep's loop is not measuring time", who, two.ms)
		}
	}
	fone, ftwo := res["fast"]["1gs"], res["fast"]["2gs"]
	if !fone.ok || !ftwo.ok {
		r3.bad("the `fast` control did not return, and it was chosen because it does")
	} else if ftwo.ms >= 1900 {
		r3.bad("the `fast` control -- a clock running 1000x -- gave `2gs` %d ms, which is "+
			"over the bound the assertion above uses.  It should return after ONE wait, "+
			"and if it does not that assertion proves nothing", ftwo.ms)
	}
	if fr := res["froze"]["1gs"]; fr.ok {
		r3.bad("the `froze` control -- a clock that never advances -- returned from `1gs` "+
			"after %d ms.  do_sleep's `done` can never reach 1,000 with a clock that does "+
			"not move, so the probe is not measuring do_sleep", fr.ms)
	}
	nob, allb := res["nobell"]["hgshh"], res["allbell"]["hgshh"]
	if nob.bells != 1 {
		r3.bad("the `nobell` control -- vim_beep's 500 written 500000 -- rang %s bells on "+
			"`hgshh` and 1 was expected.  The second h rings BECAUSE more than 500 ms have "+
			"passed, and if moving the threshold does not stop it the probe is measuring "+
			"something else", z28Opt(nob))
	}
	if allb.bells != 3 {
		r3.bad("the `allbell` control -- vim_beep's 500 written -1 -- rang %s bells on "+
			"`hgshh` and 3 were expected.  The THIRD h is suppressed because fewer than "+
			"500 ms have passed, and if making the test always true does not let it ring, "+
			"that half of the probe measures nothing", z28Opt(allb))
	}
	if err := r3.done(); err != nil {
		return err
	}
	r.say("THE PROBES: `1gs` %d ms and `2gs` %d on the binary this phase was HANDED, %d "+
		"and %d on its own -- do_sleep's loop, at one wait and at two.  `hgshh` rings 2 "+
		"bells on both, which is vim_beep's threshold in BOTH directions in one probe: h "+
		"at column 0 rings, gs lets a second pass, the next h rings because more than 500 "+
		"ms have gone and the third is suppressed because fewer than 500 have",
		res["old"]["1gs"].ms, res["old"]["2gs"].ms, res["new"]["1gs"].ms, res["new"]["2gs"].ms)
	r.say("AND EACH HALF FAILS ON A CONTROL AIMED AT IT.  The timing: with the clock "+
		"running 1000x fast `2gs` is %d ms against `1gs` %d -- one wait instead of two, "+
		"the difference gone -- and with a clock that never advances `1gs` NEVER "+
		"RETURNS.  The bells: a clock control cannot answer for those, because one that "+
		"breaks the rate limit breaks do_sleep first and `hgshh` then blocks, so the two "+
		"bell controls move vim_beep's 500 instead -- to 500000, and `hgshh` rings %d; "+
		"to -1, and it rings %d", ftwo.ms, fone.ms, nob.bells, allb.bells)
	r.say("`ceil` -- every reading rounded UP instead of down, which perturbs each one "+
		"by up to a full millisecond, TWICE what section 4 measured -- gives `1gs` %d "+
		"ms, `2gs` %d and 2 bells, exactly the product.  `epoch` -- milliseconds since "+
		"1970 rather than since the whole second of the first call -- gives %d, %d and "+
		"2.  So no caller can see one millisecond, and the origin is a free choice",
		res["ceil"]["1gs"].ms, res["ceil"]["2gs"].ms,
		res["epoch"]["1gs"].ms, res["epoch"]["2gs"].ms)

	wgR.Wait()
	for _, vv := range []string{"old", "ceil", "epoch"} {
		dq, _ := exec.Command("diff", "-rq", filepath.Join(tmp, "REC."+vv),
			filepath.Join(tmp, "REC.new")).CombinedOutput()
		if len(dq) > 0 {
			r.say("the declared delta is NOTHING AT ALL and the recording of `%s` differs "+
				"from the output's:", vv)
			return harness.ErrReported
		}
	}
	// THE CORPUS IS BLIND TO THE CLOCK, and this is that measurement rather than
	// a claim: no case rings the bell twice, so vim_beep's rate limit is never
	// asked to suppress anything.
	scr := filepath.Join(tmp, "REC.new", "screen")
	ents, _ := os.ReadDir(scr)
	var names []string
	for _, en := range ents {
		names = append(names, en.Name())
	}
	sort.Strings(names)
	var bells []int
	for _, n := range names {
		for _, line := range strings.Split(readFile(filepath.Join(scr, n)), "\n") {
			if strings.HasPrefix(line, "--- bells ") {
				if fs := strings.Fields(line); len(fs) > 2 {
					b, _ := strconv.Atoi(fs[2])
					bells = append(bells, b)
				}
				break
			}
		}
	}
	one, zero, maxb := 0, 0, 0
	for _, b := range bells {
		if b > maxb {
			maxb = b
		}
		if b == 1 {
			one++
		}
		if b == 0 {
			zero++
		}
	}
	if maxb > 1 {
		many := 0
		for _, b := range bells {
			if b > 1 {
				many++
			}
		}
		return stop("%d of the %d screen cases now ring the bell more than once, so the "+
			"corpus CAN see vim_beep's rate limit and this phase's empty declaration needs "+
			"re-arguing rather than asserting", many, len(bells))
	}
	r.say("the declared delta is NOTHING AT ALL and FOUR FULL RECORDINGS ARE "+
		"BYTE-IDENTICAL -- the binary this phase was handed, its own, `ceil` and `epoch` "+
		"-- across 102 screen cases, every Ex command, every command line, the pty "+
		"scenarios and the terminal table.  AND THE CORPUS IS BLIND TO THE CLOCK, "+
		"measured: %d of the %d cases ring the bell once and %d not at all, and NOT ONE "+
		"rings it twice, so vim_beep's 500 ms limit -- the only reading a screen case "+
		"could see -- is never asked to suppress anything.  That is why this phase owes "+
		"the probes above, and they are what answer for it", one, len(bells), zero)
	return nil
}

// z28Opt is Python's `%s` of a value that may be None: a probe that blocked
// printed `None` there, and the Go must too or the refusal reads differently.
func z28Opt(x z28Res) string {
	if !x.ok {
		return "None"
	}
	return strconv.Itoa(x.bells)
}

func containsStr28(xs []string, x string) bool {
	for _, v := range xs {
		if v == x {
			return true
		}
	}
	return false
}
