package edit

import (
	"bytes"
	"io"
	"regexp"
	"strconv"
	"strings"

	"slimvim.local/tools/internal/cutil"
)

func init() { phases["zero30"] = Zero30 }

var zero30Directive = regexp.MustCompile(`^ *#`)
var zero30Include = regexp.MustCompile(`^#include <([A-Za-z0-9_/.]+)>$`)

// zero30Old is the four-line block at msg_puts_attr_len().
//
// THE ONE-LINE FORM IS NOT AN ANCHOR: `    if (msg_use_printf())` at four
// spaces is a substring of the same line at eight, so it counts 3 where the
// block counts 1.
const zero30Old = `    if (msg_use_printf())
    {
        msg_puts_printf((char_u *)str, maxlen);
    }
`

const zero30New = `    if (msg_use_printf())
    {
        host_message((char *)str, maxlen, !info_message);
        msg_didout = TRUE;
    }
`

// Zero30 folds msg_puts_attr_len()'s never-taken arm into one host_message()
// call.
func Zero30(text []byte, w io.Writer) ([]byte, error) {
	p := ph{"msgfold", w}
	linesBefore := p.lines(text)
	runsBefore := p.blankRuns(text)

	// ---- 0. the file this edit was written against -----------------------
	// ELEVEN DIRECTIVES AND NONE ABOVE THE BOUNDARY.  Phase 27 made the first
	// `#include` the core -> host boundary; this phase adds no directive,
	// removes none and moves none.
	lines := bytes.Split(text, []byte{'\n'})
	var directives []int
	for i, l := range lines {
		if zero30Directive.Match(l) {
			directives = append(directives, i)
		}
	}
	consecutive := len(directives) > 0
	for k, i := range directives {
		if i != directives[0]+k {
			consecutive = false
		}
	}
	if len(directives) != 11 || !consecutive {
		var first []string
		for _, i := range directives {
			if len(first) < 4 {
				first = append(first, strconv.Itoa(i+1))
			}
		}
		return nil, p.die("the file does not have exactly eleven preprocessor directives on eleven "+
			"consecutive lines: %d at %s", len(directives), strings.Join(first, " "))
	}
	for _, i := range directives {
		if !zero30Include.Match(lines[i]) {
			return nil, p.die("a directive is not an `#include <...>` of a system header, and no phase may " +
				"add one")
		}
	}
	p.sayf("eleven directives, every one an `#include <...>`, on lines %d-%d -- the first of "+
		"them is the boundary and this phase writes nothing above it but C",
		directives[0]+1, directives[len(directives)-1]+1)

	// ---- 1. the inventory, counted here rather than remembered -----------
	for _, inv := range []struct {
		name string
		want int
		why  string
	}{
		{"msg_use_printf", 6, "a prototype, a definition and FOUR call sites -- this " +
			"phase leaves all six"},
		{"msg_puts_printf", 3, "a prototype, a definition and the one call this phase " +
			"folds away"},
		{"vim_strlen_maxlen", 3, "a prototype, a definition and its ONLY call, which " +
			"is inside msg_puts_printf"},
		{"msg_puts_display", 4, "a prototype, a definition and two calls -- the false " +
			"arm this phase keeps, and one recursive"},
		{"host_message", 10, "a prototype, a definition and eight calls, four of them " +
			"inside msg_puts_printf"},
		{"info_message", 9, "a declaration, its setters and the four reads inside " +
			"msg_puts_printf"},
		{"msg_didout", 29, "one of them msg_puts_printf's last statement, which the " +
			"replacement keeps"},
	} {
		if got := p.mentions(text, inv.name); got != inv.want {
			return nil, p.die("`%s` has %d mentions and this phase was written against %d -- %s",
				inv.name, got, inv.want, inv.why)
		}
	}
	p.say("the inventory, and the FOUR call sites are four: msg_use_printf 6, " +
		"msg_puts_printf 3, vim_strlen_maxlen 3, msg_puts_display 4, host_message 10, " +
		"info_message 9, msg_didout 29")

	// ---- 2. the three sites this phase does NOT touch, asserted VERBATIM -
	// Two of them are folds that were measured to be WRONG and one is a live
	// guard.  They are named so a later edit cannot quietly widen this phase
	// into them.
	keep := []struct {
		who, s string
		want   int
		why    string
	}{
		{"hit_return_msg", "    if (!msg_use_printf())\n", 1,
			"the live guard -- and it is written with a `!`, which is why an edit that " +
				"greps for the positive spelling finds three sites and not four"},
		{"msg_clr_eos_force", "msg_clr_eos_force(void)\n{\n    if (msg_use_printf())\n", 1,
			"CANNOT BE FOLDED SAFELY: the false arm calls screen_fill() with no valid " +
				"screen, which the corpus cannot see and two probes can"},
		{"exit_scroll", "        if (msg_use_printf())\n", 1,
			"ALIVE: its printf arm fires in three of the 32 stream probes and three of " +
				"the four signal probes, with no signal needed for the first three"},
	}
	for _, k := range keep {
		if got := bytes.Count(text, []byte(k.s)); got != k.want {
			return nil, p.die("the %s site is %d occurrences of %s and must be %d -- %s",
				k.who, got, cutil.PyRepr(k.s), k.want, k.why)
		}
	}
	p.say("and the THREE sites this phase leaves alone, each asserted verbatim: " +
		"hit_return_msg's `!msg_use_printf()` guard, msg_clr_eos_force's test (folding " +
		"it moves t_ti_stopterm 2,266 -> 2,280 and hup_clean 2,124 -> 2,142) and " +
		"exit_scroll's (its printf arm is ALIVE, and phase 21 named it dead)")

	// ---- 3. the fold, at the one anchor whose count is 1 -----------------
	if got := bytes.Count(text, []byte(zero30Old)); got != 1 {
		return nil, p.die("the four-line block at msg_puts_attr_len() occurs %d times and must occur "+
			"exactly once.  THE ONE-LINE FORM IS NOT AN ANCHOR: `    if "+
			"(msg_use_printf())` at four spaces is a substring of the same line at eight, "+
			"so it counts 3 where the block counts 1", got)
	}
	text = bytes.Replace(text, []byte(zero30Old), []byte(zero30New), 1)
	p.say("the fold: msg_puts_attr_len()'s true arm becomes `host_message((char *)str, " +
		"maxlen, !info_message); msg_didout = TRUE;`.  host_message() takes len < 0 as " +
		"strlen and len >= 0 as an exact count, which IS msg_puts_printf's maxlen " +
		"contract -- and the arm is never executed, so equivalence is not claimed: what " +
		"the two lines do not reproduce is the CR-before-NL insertion and the msg_col " +
		"bookkeeping, which no recording or probe can reach")

	// ---- 4. what the file is now -----------------------------------------
	if n := p.lines(text); n != linesBefore+1 {
		return nil, p.die("the file is %d lines and the input was %d -- this edit adds exactly one",
			n-1, linesBefore-1)
	}
	if got := p.mentions(text, "msg_use_printf"); got != 6 {
		return nil, p.die("`msg_use_printf` is %d mentions after the edit and must still be 6: the test "+
			"stays, and only the arm behind it goes", got)
	}
	if got := p.mentions(text, "msg_puts_printf"); got != 2 {
		return nil, p.die("`msg_puts_printf` is %d mentions after the edit and must be 2 -- the "+
			"prototype and the definition, which the SWEEP removes and this edit does not", got)
	}
	for _, k := range keep {
		if bytes.Count(text, []byte(k.s)) != k.want {
			return nil, p.die("the %s site moved, and this edit touches exactly one site", k.who)
		}
	}
	if r := p.blankRuns(text); r != runsBefore {
		return nil, p.die("the edit left %d runs of two blank lines where there were %d", r, runsBefore)
	}
	n := 0
	for _, l := range bytes.Split(text, []byte{'\n'}) {
		if zero30Directive.Match(l) {
			n++
		}
	}
	if n != 11 {
		return nil, p.die("the file no longer has exactly eleven directives")
	}
	p.sayf("one line added, msg_use_printf still 6, msg_puts_printf down to 2 -- the "+
		"prototype and the definition, which are the SWEEP's to take along with "+
		"vim_strlen_maxlen and its prototype; eleven directives unmoved and the "+
		"blank-line runs at %d", runsBefore)
	return text, nil
}
