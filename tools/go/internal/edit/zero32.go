package edit

import (
	"bytes"
	"fmt"
	"io"
	"regexp"
	"strings"
)

func init() { register("zero32", Zero32) }

var (
	z32Inc      = regexp.MustCompile(`^#include <([A-Za-z0-9_/.]+)>$`)
	z32Proto    = regexp.MustCompile(`^[A-Za-z_].*\);$`)
	z32Names    = regexp.MustCompile(`\b(?:vim_time|host_time|time_T|time_t)\b`)
	z32Word     = regexp.MustCompile(`\btime\b`)
	z32TimeCall = regexp.MustCompile(`\btime\s*\(`)
	z32VimTime  = regexp.MustCompile(`\bvim_time\b`)
	z32HostTime = regexp.MustCompile(`\bhost_time\b`)
	z32TimeT    = regexp.MustCompile(`\btime_t\b`)
	z32TimeTT   = regexp.MustCompile(`\btime_T\b`)
)

// z32Strip blanks string and character literals in ONE line.  It is
// zhostonly's, and for the same reason: this file says "%ld line %sed %d time"
// in two NGETTEXT strings, and a count that read those as calls would be
// counting English.
//
// It is NOT cutil.Blank -- it collapses a literal to a single space rather
// than preserving its offsets, because nothing here indexes back into it.
func z32Strip(line []byte) []byte {
	out := make([]byte, 0, len(line))
	i, n := 0, len(line)
	for i < n {
		c := line[i]
		if c == '"' || c == '\'' {
			q := c
			out = append(out, ' ')
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
		out = append(out, c)
		i++
	}
	return out
}

func z32Code(lines [][]byte) []byte {
	out := make([][]byte, len(lines))
	for i, l := range lines {
		out[i] = z32Strip(l)
	}
	return bytes.Join(out, []byte{'\n'})
}

// Zero32 sends the wall clock across the boundary: vim_time() becomes
// host_time() below the line, `long time(long *tp);` leaves the core's
// prototype block and a static_assert stronger than it replaces it.
func Zero32(text []byte, w io.Writer) ([]byte, error) {
	p := ph{"wallclock", w}
	t := text

	once := func(text []byte, old, new, why string) ([]byte, error) {
		if k := bytes.Count(text, []byte(old)); k != 1 {
			shown := strings.ReplaceAll(old, "\n", "\\n")
			if len(shown) > 70 {
				shown = shown[:70]
			}
			return nil, p.die("`%s` is not in the file exactly once (%s)", shown, why)
		}
		return bytes.Replace(text, []byte(old), []byte(new), 1), nil
	}

	lines := bytes.Split(t, []byte{'\n'})
	runsBefore := p.blankRuns(t)

	// ---- 0. the file this edit was written against ----------------------
	// ELEVEN DIRECTIVES, every one an `#include <...>`, CONTIGUOUS, and
	// NOTHING ABOVE THEM.  Phase 27 made the first of them the boundary
	// between the core and the host (ZERO-PLAN.md 4c); this phase edits both
	// sides of that line and must know where it is.
	var directives []int
	for i, l := range lines {
		if bytes.HasPrefix(bytes.TrimLeft(l, " \t\n\v\f\r"), []byte("#")) {
			directives = append(directives, i)
		}
	}
	if len(directives) != 11 {
		return nil, p.die("the file has %d preprocessor directives and this phase was written "+
			"against 11", len(directives))
	}
	for k, i := range directives {
		if i != directives[0]+k {
			var at []string
			for _, j := range directives {
				at = append(at, fmt.Sprint(j+1))
			}
			return nil, p.die("the eleven directives are not contiguous: %s", strings.Join(at, " "))
		}
	}
	var incNames []string
	for _, i := range directives {
		if !z32Inc.Match(lines[i]) {
			return nil, p.die("a directive is not an `#include <...>` of a system header, and no " +
				"phase may add one")
		}
		incNames = append(incNames, string(lines[i]))
	}
	if !containsStr(incNames, "#include <time.h>") {
		return nil, p.die("<time.h> is not among the eleven includes.  It is what will declare " +
			"`time()` for the host once the core stops declaring it, and what the " +
			"static_assert this phase adds compares `time_T` against")
	}
	cut := directives[0]
	core := z32Code(lines[:cut])
	below := z32Code(lines[cut:])
	p.sayf("eleven `#include`s, contiguous, at lines %d-%d, <time.h> among them, and "+
		"NOTHING above the first of them -- so the core is the %d lines above the "+
		"boundary and the host is the %d below it",
		cut+1, cut+11, cut, len(lines)-cut-1)

	// ---- 1. the inventory, counted here rather than remembered -----------
	// Every number is what this edit is about to act on, taken on the
	// literal-stripped text.
	want := []struct {
		name          string
		nCore, nBelow int
	}{
		{"time", 4, 1}, {"vim_time", 7, 0}, {"host_time", 0, 0},
		{"time_T", 10, 0}, {"time_t", 0, 0}, {"musl_now_ms", 9, 1},
	}
	for _, x := range want {
		re := regexp.MustCompile(`\b` + x.name + `\b`)
		gc := len(re.FindAll(core, -1))
		gb := len(re.FindAll(below, -1))
		if gc != x.nCore || gb != x.nBelow {
			return nil, p.die("`%s` occurs %d times above the boundary and %d below it, where this "+
				"phase was written against %d and %d", x.name, gc, gb, x.nCore, x.nBelow)
		}
	}
	p.say("the core says `time` FOUR times -- the libc prototype, vim_time's own call, " +
		"and ui_focus_change's TWO, which bypass the wrapper -- and `vim_time` seven: a " +
		"prototype, a definition and five call sites.  Below the boundary `time` is the " +
		"one `#include <time.h>`, and musl_now_ms, the clock that has already crossed, " +
		"is 9 above and 1 below")

	// ---- 2. the core's own libc prototype block, computed ----------------
	// The block is the run of non-blank lines around `long time(long *tp);`,
	// not a line number and not a count this file states: another phase in
	// flight removes two of its entries, and a written size would already be
	// stale.
	const tp = "long time(long *tp);"
	var at []int
	for i, l := range lines {
		if string(l) == tp {
			at = append(at, i)
		}
	}
	if len(at) != 1 {
		return nil, p.die("`%s` is not on a line of its own exactly once above the boundary -- it "+
			"is phase 26's, and it is what this phase removes", tp)
	}
	a, b := at[0], at[0]
	for len(bytes.TrimSpace(lines[a-1])) > 0 {
		a--
	}
	for len(bytes.TrimSpace(lines[b+1])) > 0 {
		b++
	}
	if b >= cut {
		return nil, p.die("the prototype block runs past the boundary, so it is not the block " +
			"phase 26 wrote")
	}
	var notProto []string
	for _, l := range lines[a : b+1] {
		if !z32Proto.Match(l) {
			notProto = append(notProto, string(l))
		}
	}
	if len(notProto) > 0 {
		return nil, p.die("the block around `%s` is not all prototypes: %s",
			tp, strings.Join(notProto, " / "))
	}
	for _, l := range lines[a : b+1] {
		if bytes.HasPrefix(l, []byte("static ")) {
			return nil, p.die("a prototype in the block is `static`, which phase 26 forbade: it " +
				"would give the core an internal function that is never defined")
		}
	}
	var protoNames []string
	for _, l := range lines[a : b+1] {
		f := strings.Fields(strings.SplitN(string(l), "(", 2)[0])
		protoNames = append(protoNames, strings.TrimLeft(f[len(f)-1], "*"))
	}
	p.sayf("the core's libc prototype block is %d lines (%d-%d), every one a plain "+
		"non-`static` prototype: %s.  This phase takes `time` out of it and leaves %d",
		b-a+1, a+1, b+1, strings.Join(protoNames, " "), b-a)

	// ---- 3. the literals -------------------------------------------------
	// Phase 23 was caught out by three string literals holding `NULL`; 26 and
	// 28 applied the lesson rather than assuming it.  So does this one.
	spans, err := literalSpans(p, t)
	if err != nil {
		return nil, err
	}
	var bad, english []string
	for _, s := range spans {
		lit := t[s[0]:s[1]]
		if z32Names.Match(lit) {
			bad = append(bad, string(lit))
		}
		if z32Word.Match(lit) {
			english = append(english, string(lit))
		}
	}
	if len(bad) > 0 {
		return nil, p.die("a literal holds a name this phase substitutes: %s", strings.Join(bad, " / "))
	}
	var shortened []string
	for _, x := range english {
		if len(x) > 34 {
			x = x[:34]
		}
		shortened = append(shortened, x)
	}
	p.sayf("%d string and character literals, NONE holding `vim_time`, `host_time`, "+
		"`time_T` or `time_t` -- and %d holding the English word `time` (%s), which is "+
		"why no substitution below is a bare name",
		len(spans), len(english), strings.Join(shortened, " / "))

	// ---- 4. STEP ONE: ui_focus_change stops bypassing the wrapper --------
	// TWO READS BEFORE AND TWO READS AFTER.  The condition reads the clock
	// and the body reads it again; nothing is hoisted into a local, because
	// that would be a different program -- the two reads could always fall
	// either side of a second tick and they still can, exactly as often.  The
	// check instruments both binaries and requires the same count, with a
	// control that DOES hoist and moves it.
	t, err = once(t, `    if (in_focus && last_time + 2 < time(nullptr))
    {
        last_time = time(nullptr);
    }
`, `    if (in_focus && last_time + 2 < vim_time())
    {
        last_time = vim_time();
    }
`, "ui_focus_change's two standalone clock reads, which are the whole of step one")
	if err != nil {
		return nil, err
	}
	mid := z32Code(bytes.Split(t, []byte{'\n'})[:cut])
	if k := len(z32TimeCall.FindAll(mid, -1)); k != 2 {
		return nil, p.die("`time(` occurs %d times above the boundary after step one, where 2 were "+
			"expected -- the prototype and the one call inside the wrapper", k)
	}
	p.say("STEP ONE: ui_focus_change's two direct `time(nullptr)` are `vim_time()`.  " +
		"STILL TWO READS, in the same two statements, in the same order -- and `time(` " +
		"above the boundary is now the prototype and ONE call site, the wrapper's own")

	// ---- 5. STEP TWO: the wrapper becomes the host's ---------------------
	nRen := len(z32VimTime.FindAll(t, -1))
	t = z32VimTime.ReplaceAll(t, []byte("host_time"))
	if nRen != 9 {
		return nil, p.die("%d `vim_time` were renamed where 9 were counted -- the prototype, the "+
			"definition, five call sites and the two step one just made", nRen)
	}
	t, err = once(t, "static time_T host_time(void);\n", "",
		"the core's own forward declaration, in the block of them")
	if err != nil {
		return nil, err
	}
	t, err = once(t, "static void host_message(const char *msg, int len, int err);\n",
		"static void host_message(const char *msg, int len, int err);\n"+
			"static long host_time(void);\n",
		"the core's HOST BLOCK, where host_exit, host_message and the nine musl_ "+
			"names are declared")
	if err != nil {
		return nil, err
	}
	// The definition leaves with one of the two blank lines around it, so no
	// run of two is left behind -- which no verification tier can see
	// (CLAUDE.md).
	t, err = once(t, `
    static time_T
host_time(void)
{
    return time(nullptr);
}
`, "", "the definition, which is one clock read and nothing else")
	if err != nil {
		return nil, err
	}
	// It lands between musl_now_ms and musl_delay: beside the clock that
	// crossed at phase 28, and INSIDE the region `zhostonly` reads as the
	// host.
	t, err = once(t, `    static void
musl_delay(long ms, int interruptible)
`, `    static long
host_time(void)
{
    return time(nullptr);
}

    static void
musl_delay(long ms, int interruptible)
`, "the host block, immediately below musl_now_ms -- the clock's other half")
	if err != nil {
		return nil, err
	}
	p.sayf("STEP TWO: `vim_time` is `host_time` at all %d mentions; its declaration moves "+
		"from the forward-declaration block to the host block, as `static long "+
		"host_time(void);` -- `long` and not `time_T`, because the DEFINITION is below "+
		"the boundary and the host cannot name a core typedef once the file is cut; and "+
		"the definition lands between musl_now_ms and musl_delay", nRen)

	// ---- 6. the prototype the core no longer needs, and what replaces it --
	t, err = once(t, tp+"\n", "",
		"phase 26's prototype for time(): nothing above the boundary calls it now")
	if err != nil {
		return nil, err
	}
	t, err = once(t, "static_assert(15 == SIGTERM, \"SIGTERM\");\n",
		"static_assert(15 == SIGTERM, \"SIGTERM\");\n"+
			"static_assert(_Generic((time_T)0, time_t: 1, default: 0), \"time_T is time_t\");\n",
		"the twelve constants phase 27 put below the includes, which is the only place "+
			"in the file where a core name and a header name are both in scope")
	if err != nil {
		return nil, err
	}
	p.sayf("`%s` leaves the core -- the block goes %d lines to %d -- and "+
		"`static_assert(_Generic((time_T)0, time_t: 1, default: 0), \"time_T is "+
		"time_t\");` joins the twelve below the includes.  THE PROTOTYPE WAS THE "+
		"GUARANTEE: gcc compared it with <time.h>'s and would have said `conflicting "+
		"types for 'time'`.  The assertion says the same thing about the same two "+
		"types, and the check proves it can fail", tp, b-a+1, b-a)

	// ---- 7. what the file is now -----------------------------------------
	L := bytes.Split(t, []byte{'\n'})
	const coreDelta = -1 + 1 - 6 - 1
	const belowDelta = 6 + 1
	if len(L)-len(lines) != coreDelta+belowDelta {
		return nil, p.die("the file moved by %d lines where %d was expected",
			len(L)-len(lines), coreDelta+belowDelta)
	}
	var ndir []int
	for i, l := range L {
		if bytes.HasPrefix(bytes.TrimLeft(l, " \t\n\v\f\r"), []byte("#")) {
			ndir = append(ndir, i)
		}
	}
	// THE BOUNDARY MOVES UP BY WHAT THE CORE LOST, and by exactly that: the
	// core is the lines above the first `#include`, so the directive's index
	// IS the core's line count.
	okDir := len(ndir) == 11
	for k, i := range ndir {
		if okDir && i != cut+coreDelta+k {
			okDir = false
		}
	}
	if !okDir {
		var at3 []string
		for _, i := range ndir {
			if len(at3) < 3 {
				at3 = append(at3, fmt.Sprint(i+1))
			}
		}
		return nil, p.die("the eleven directives are not the eleven contiguous lines at %d: they "+
			"are at %s.  The first one IS the boundary, and it moves up by exactly what "+
			"the core lost", cut+coreDelta+1, strings.Join(at3, " "))
	}
	for _, i := range ndir {
		if !z32Inc.Match(L[i]) {
			return nil, p.die("a directive is no longer an `#include <...>` of a system header")
		}
	}
	ncore := z32Code(L[:ndir[0]])
	nbelow := z32Code(L[ndir[0]:])
	if z32Word.Match(ncore) {
		return nil, p.die("`time` is still named %d times above the boundary, and the whole "+
			"product of this phase is that the core does not name it at all",
			len(z32Word.FindAll(ncore, -1)))
	}
	if len(z32VimTime.FindAll(t, -1)) > 0 {
		return nil, p.die("`vim_time` survives somewhere in the file")
	}
	if k := len(z32HostTime.FindAll(ncore, -1)); k != 8 {
		return nil, p.die("`host_time` occurs %d times above the boundary where 8 were expected "+
			"-- the declaration and seven call sites", k)
	}
	if k := len(z32HostTime.FindAll(nbelow, -1)); k != 1 {
		return nil, p.die("`host_time` occurs %d times below the boundary where 1 was expected "+
			"-- its definition", k)
	}
	if k := len(z32Word.FindAll(nbelow, -1)); k != 2 {
		return nil, p.die("`time` occurs %d times below the boundary where 2 were expected -- "+
			"`#include <time.h>` and host_time's call.  `time_t` is not one of them: `_` "+
			"is a word character, so `\\btime\\b` does not match inside it", k)
	}
	if k := len(z32TimeT.FindAll(nbelow, -1)); k != 1 {
		return nil, p.die("`time_t` occurs %d times below the boundary where 1 was expected -- "+
			"the static_assert", k)
	}
	if k := len(z32TimeTT.FindAll(ncore, -1)); k != 8 {
		return nil, p.die("`time_T` occurs %d times above the boundary where 8 were expected -- "+
			"the input had 10 and the two that go are the prototype's and the "+
			"definition's", k)
	}
	if !bytes.Contains(ncore, []byte("typedef long        time_T;")) {
		return nil, p.die("`typedef long        time_T;` is not in the core.  host_time returns " +
			"`long`, so the core's clock type being `long` is what makes every call site " +
			"an assignment and not a conversion")
	}
	if k := p.blankRuns(t); k != runsBefore {
		return nil, p.die("the edit left %d runs of two blank lines where there were %d",
			k, runsBefore)
	}
	p.sayf("THE CORE DOES NOT NAME `time` AT ALL -- four mentions to none -- `host_time` "+
		"is 8 above the boundary and 1 below, `time_t` is named once in the whole file "+
		"and it is the static_assert, and the file is %d lines against %d",
		len(L)-1, len(lines)-1)
	return t, nil
}
