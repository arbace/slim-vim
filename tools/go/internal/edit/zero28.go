package edit

import (
	"bytes"
	"io"
	"regexp"
	"strconv"
	"strings"
)

func init() { register("zero28", Zero28) }

var (
	zero28Inc   = regexp.MustCompile(`^#include <([A-Za-z0-9_/.]+)>$`)
	zero28Timev = regexp.MustCompile(`struct timeval\b`)
	zero28Names = regexp.MustCompile(`\b(?:elapsed_T|elapsed|now_tv|start_tv|musl_gettimeofday` +
		`|gettimeofday|musl_now_ms)\b|struct timeval\b`)
)

const zero28HostMark = "static volatile sig_atomic_t host_winch_pending"

// zero28Once replaces text that must occur exactly once, with this phase's own
// refusal: the anchor truncated to seventy characters with its newlines shown.
func zero28Once(p ph, text []byte, old, new, why string) ([]byte, error) {
	if k := bytes.Count(text, []byte(old)); k != 1 {
		shown := strings.ReplaceAll(old, "\n", `\n`)
		if len(shown) > 70 {
			shown = shown[:70]
		}
		return nil, p.die("`%s` is not in the file exactly once (%s)", shown, why)
	}
	return bytes.Replace(text, []byte(old), []byte(new), 1), nil
}

// Zero28 makes the clock a scalar: `long musl_now_ms(void)` replaces
// `void musl_gettimeofday(long *, long *)` and takes elapsed_T, elapsed() and
// the out-parameter pair with it.
//
// THE POINT IS THE SIGNATURE AND NOT THE SAVING: after this phase no core ->
// host call's shape is decided by a type the core cannot name.  Phase 26 had
// to invent a tagless `struct timeval` mirror for the core to hold; this
// deletes it.
func Zero28(text []byte, w io.Writer) ([]byte, error) {
	p := ph{"clock", w}
	lines := bytes.Split(text, []byte{'\n'})
	runsBefore := p.blankRuns(text)
	var err error

	// ---- 0. the file this edit was written against -----------------------
	// ELEVEN DIRECTIVES, contiguous, and NOTHING ABOVE THEM.  Phase 27 made
	// the first of them the boundary; this phase edits both sides of that
	// line and must know exactly where it is.
	var directives []int
	for i, l := range lines {
		if bytes.HasPrefix(bytes.TrimLeft(l, " \t"), []byte("#")) {
			directives = append(directives, i)
		}
	}
	if len(directives) != 11 {
		return nil, p.die("the file has %d preprocessor directives and this phase was written against 11",
			len(directives))
	}
	for k, i := range directives {
		if i != directives[0]+k {
			var at []string
			for _, d := range directives {
				at = append(at, strconv.Itoa(d+1))
			}
			return nil, p.die("the eleven directives are not contiguous: %s", strings.Join(at, " "))
		}
	}
	for _, i := range directives {
		if !zero28Inc.Match(lines[i]) {
			return nil, p.die("a directive is not an `#include <...>` of a system header, and no phase may " +
				"add one")
		}
	}
	cut := directives[0]
	core := bytes.Join(lines[:cut], []byte{'\n'})
	below := bytes.Join(lines[cut:], []byte{'\n'})
	p.sayf("eleven `#include`s, contiguous, at lines %d-%d, and NOTHING above the first of "+
		"them -- so the core is the %d lines above the boundary and the host is the %d "+
		"below it", cut+1, cut+11, cut, len(lines)-cut-1)

	// ---- 1. the host region, which is where the new definition has to land
	// `zhostonly` reads the host as the lines from `host_winch_pending` to
	// musl_suspend()'s last brace, and requires every mention of its
	// vocabulary -- `struct timeval` among them -- to be inside it.
	hb := 0
	for _, l := range lines {
		if bytes.HasPrefix(l, []byte(zero28HostMark)) {
			hb++
		}
	}
	if hb != 1 {
		return nil, p.die("the host block does not begin exactly once with %s -- found %d",
			"'"+zero28HostMark+"'", hb)
	}

	// ---- 2. the inventory, counted here rather than remembered -----------
	for _, inv := range []struct {
		name          string
		ncore, nbelow int
	}{
		{"elapsed_T", 8, 0}, {"elapsed", 6, 0}, {"elapsed_time", 3, 0},
		{"now_tv", 5, 0}, {"start_tv", 20, 0}, {"musl_gettimeofday", 6, 1},
		{"gettimeofday", 0, 1}, {"musl_now_ms", 0, 0},
	} {
		gc := p.mentions(core, inv.name)
		gb := p.mentions(below, inv.name)
		if gc != inv.ncore || gb != inv.nbelow {
			return nil, p.die("`%s` occurs %d times above the boundary and %d below it, where this phase "+
				"was written against %d and %d", inv.name, gc, gb, inv.ncore, inv.nbelow)
		}
	}
	tvCore := len(zero28Timev.FindAll(core, -1))
	tvBelow := len(zero28Timev.FindAll(below, -1))
	if tvCore != 0 || tvBelow != 3 {
		return nil, p.die("`struct timeval` occurs %d times above the boundary and %d below, where this "+
			"phase was written against 0 and 3", tvCore, tvBelow)
	}
	p.say("the core's clock is elapsed_T 8, elapsed 6, musl_gettimeofday 6 and `struct " +
		"timeval` 0 -- phase 26 took the last of those; the host has musl_gettimeofday's " +
		"definition, its one real `gettimeofday` call and three `struct timeval`")

	// ---- 3. the literals -------------------------------------------------
	// Phase 23 was caught out by three string literals holding `NULL`, and
	// phase 26 applied the lesson rather than assuming it.  So does this one.
	spans, err := literalSpans(p, text)
	if err != nil {
		return nil, err
	}
	var bad []string
	for _, s := range spans {
		if zero28Names.Match(text[s[0]:s[1]]) {
			bad = append(bad, string(text[s[0]:s[1]]))
		}
	}
	if len(bad) > 0 {
		return nil, p.die("a literal holds a name this phase substitutes: %s", strings.Join(bad, " / "))
	}
	p.sayf("%d string and character literals, NONE holding any of the seven names -- so every "+
		"substitution below is over code", len(spans))

	// ---- 4. the type and the function leave the core ---------------------
	// The typedef, the prototype and ONE of the two blank lines around them.
	// Deleting the five lines alone would leave a run of two blank lines,
	// which no verification tier can see and which the arithmetic at the end
	// refuses.
	text, err = zero28Once(p, text, `
typedef struct {
    long        tv_sec;
    long        tv_usec;
} elapsed_T;
static long elapsed(elapsed_T *start_tv);
`, "", "the tagless struct and the prototype, which phase 26 wrote")
	if err != nil {
		return nil, err
	}
	text, err = zero28Once(p, text, `
    static long
elapsed(elapsed_T *start_tv)
{
    elapsed_T       now_tv;

    musl_gettimeofday(&now_tv.tv_sec, &now_tv.tv_usec);
    return (now_tv.tv_sec - start_tv->tv_sec) * 1000L
         + (now_tv.tv_usec - start_tv->tv_usec) / 1000L;
}
`, "", "elapsed(), whose entire body is one clock read and one subtraction")
	if err != nil {
		return nil, err
	}
	p.say("`elapsed_T` and `elapsed()` leave the core: 5 lines of declaration and 9 of " +
		"definition, with one blank line of each pair, so no run of two blank lines is left " +
		"behind")

	// ---- 5. the four objects become `long` -------------------------------
	// The declarator column is kept: this file aligns a declaration block and
	// `long` is five characters shorter than `elapsed_T`.
	for _, s := range []struct{ old, new, who string }{
		{"    elapsed_T   start_tv;\n\n     musl_gettimeofday(&start_tv.tv_sec, " +
			"&start_tv.tv_usec) ;\n\n    if (hide_cursor)",
			"    long        start_tv;\n\n    start_tv = musl_now_ms();\n\n" +
				"    if (hide_cursor)", "do_sleep"},
		{"        static elapsed_T        start_tv;",
			"        static long             start_tv;", "vim_beep"},
		{"    elapsed_T       start_tv;\n} oscstate_T;",
			"    long            start_tv;\n} oscstate_T;", "oscstate_T"},
		{"    elapsed_T   start_tv;\n\n     musl_gettimeofday(&start_tv.tv_sec, " +
			"&start_tv.tv_usec) ;\n\n    for (;;)",
			"    long        start_tv;\n\n    start_tv = musl_now_ms();\n\n" +
				"    for (;;)", "inchar_loop"},
	} {
		text, err = zero28Once(p, text, s.old, s.new, "the clock object in "+s.who)
		if err != nil {
			return nil, err
		}
	}

	// ---- 6. the remaining stamps and every difference --------------------
	// A stamp is `X = musl_now_ms();` and a reading is `musl_now_ms() - X`.
	// The leading space and the space before the semicolon at these sites are
	// what macro expansion left behind, three pipelines ago.
	for _, s := range []struct{ old, new, who string }{
		{"             musl_gettimeofday(&start_tv.tv_sec, &start_tv.tv_usec) ;",
			"            start_tv = musl_now_ms();", "vim_beep's stamp"},
		{"         musl_gettimeofday(&osc_state.start_tv.tv_sec, " +
			"&osc_state.start_tv.tv_usec) ;",
			"        osc_state.start_tv = musl_now_ms();", "handle_osc's stamp"},
		{"        done =  elapsed(&(start_tv)) ;",
			"        done = musl_now_ms() - start_tv;", "do_sleep's reading"},
		{"        if (!did_init ||  elapsed(&(start_tv))  > 500)",
			"        if (!did_init || musl_now_ms() - start_tv > 500)",
			"vim_beep's 500 ms rate limit"},
		{"    if ( elapsed(&(osc_state.start_tv))  >= p_ost)",
			"    if (musl_now_ms() - osc_state.start_tv >= p_ost)",
			"handle_osc's p_ost timeout"},
		{"            elapsed_time =  elapsed(&(start_tv)) ;",
			"            elapsed_time = musl_now_ms() - start_tv;",
			"inchar_loop's deadline"},
	} {
		text, err = zero28Once(p, text, s.old, s.new, s.who)
		if err != nil {
			return nil, err
		}
	}
	p.say("four stamps -- do_sleep, vim_beep, handle_osc, inchar_loop -- are `X = " +
		"musl_now_ms();`, and the four readings are `musl_now_ms() - X`.  `-` binds tighter " +
		"than `>` and `>=`, so the two comparisons need no parenthesis they did not have")

	// ---- 7. the host call ------------------------------------------------
	text, err = zero28Once(p, text, "static void musl_gettimeofday(long *sec, long *usec);\n",
		"static long musl_now_ms(void);\n", "the host call's prototype")
	if err != nil {
		return nil, err
	}
	text, err = zero28Once(p, text, "static int host_tty_raw = FALSE;\n",
		"static int host_tty_raw = FALSE;\n"+
			"static long host_now_base = 0;\n"+
			"static int host_now_based = FALSE;\n",
		"the host's own state, beside the terminal's")
	if err != nil {
		return nil, err
	}
	text, err = zero28Once(p, text, `    static void
musl_gettimeofday(long *sec, long *usec)
{
    struct timeval tv;

    gettimeofday(&tv, nullptr);
    *sec = tv.tv_sec;
    *usec = tv.tv_usec;
}
`, `    static long
musl_now_ms(void)
{
    struct timeval tv;

    gettimeofday(&tv, nullptr);
    if (!host_now_based)
    {
        host_now_based = TRUE;
        host_now_base = tv.tv_sec;
    }
    return (tv.tv_sec - host_now_base) * 1000L + tv.tv_usec / 1000L;
}
`, "the host call's definition, above musl_delay and inside zhostonly's region")
	if err != nil {
		return nil, err
	}
	p.say("`long musl_now_ms(void)` replaces `void musl_gettimeofday(long *, long *)`: " +
		"milliseconds since the WHOLE SECOND of its first call, which makes a difference of " +
		"two readings identical to what an epoch-millisecond clock would give and keeps " +
		"(tv_sec - base) * 1000 inside a 32-bit `long` for 24.86 days")

	// ---- 8. what the file is now -----------------------------------------
	L := bytes.Split(text, []byte{'\n'})
	const coreDelta = -6 - 10
	const belowDelta = 4 + 2
	if d := len(L) - len(lines); d != coreDelta+belowDelta {
		return nil, p.die("the file moved by %d lines where %d was expected: -6 for the typedef and the "+
			"prototype with a blank, -10 for elapsed() with a blank, +4 for musl_now_ms's "+
			"longer body and +2 for the host's two statics", d, coreDelta+belowDelta)
	}
	var ndir []int
	for i, l := range L {
		if bytes.HasPrefix(bytes.TrimLeft(l, " \t"), []byte("#")) {
			ndir = append(ndir, i)
		}
	}
	// THE BOUNDARY MOVES UP BY WHAT THE CORE LOST, and by exactly that: the
	// core is the lines above the first `#include`, so the directive's index
	// IS the core's line count.  The two halves are checked separately -- a
	// line removed from the host and one removed from the core sum the same
	// and mean different things.
	okDir := len(ndir) == 11
	for k, i := range ndir {
		if i != directives[0]+coreDelta+k {
			okDir = false
		}
	}
	if !okDir {
		var at []string
		for _, i := range ndir {
			if len(at) < 3 {
				at = append(at, strconv.Itoa(i+1))
			}
		}
		return nil, p.die("the eleven directives are not the eleven contiguous lines at %d: they are at "+
			"%s.  The first one IS the boundary, and it moves up by exactly what the core "+
			"lost", directives[0]+coreDelta+1, strings.Join(at, " "))
	}
	for _, i := range ndir {
		if !zero28Inc.Match(L[i]) {
			return nil, p.die("a directive is no longer an `#include <...>` of a system header")
		}
	}
	ncore := bytes.Join(L[:ndir[0]], []byte{'\n'})
	nbelow := bytes.Join(L[ndir[0]:], []byte{'\n'})
	for _, name := range []string{"elapsed_T", "elapsed", "now_tv", "musl_gettimeofday"} {
		if n := p.mentions(text, name); n != 0 {
			return nil, p.die("`%s` still occurs %d times in the file", name, n)
		}
	}
	if zero28Timev.Match(ncore) {
		return nil, p.die("`struct timeval` is back above the boundary")
	}
	if n := len(zero28Timev.FindAll(nbelow, -1)); n != 3 {
		return nil, p.die("the host should still have its three `struct timeval` and has %d", n)
	}
	if n := p.mentions(text, "gettimeofday"); n != 1 {
		return nil, p.die("the bare name `gettimeofday` occurs %d times and must occur exactly once -- "+
			"the one call musl_now_ms makes", n)
	}
	if p.mentions(ncore, "gettimeofday") > 0 {
		return nil, p.die("the core calls `gettimeofday` directly")
	}
	if n := p.mentions(ncore, "musl_now_ms"); n != 9 {
		return nil, p.die("`musl_now_ms` occurs %d times above the boundary where 9 were expected -- the "+
			"prototype, four stamps and four readings", n)
	}
	if n := p.mentions(nbelow, "musl_now_ms"); n != 1 {
		return nil, p.die("`musl_now_ms` occurs %d times below the boundary where 1 was expected -- its "+
			"definition", n)
	}
	if n := p.mentions(text, "elapsed_time"); n != 3 {
		return nil, p.die("`elapsed_time`, which is inchar_loop's own `long` and not this phase's, is at "+
			"%d and was at 3", n)
	}
	if r := p.blankRuns(text); r != runsBefore {
		return nil, p.die("the edit left %d runs of two blank lines where there were %d", r, runsBefore)
	}
	p.sayf("the core has NO clock type and NO clock call of its own: elapsed_T, elapsed, "+
		"now_tv, musl_gettimeofday and `struct timeval` are all at 0 above the boundary, "+
		"musl_now_ms is 9 there and 1 below, and the file is %d lines against %d",
		len(L)-1, len(lines)-1)
	return text, nil
}
