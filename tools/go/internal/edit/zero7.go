package edit

import (
	"io"
	"regexp"
	"strings"

	"slimvim.local/tools/internal/cutil"
	"slimvim.local/tools/internal/harness"
)

func init() { register("zero7", Zero7) }

const (
	z7RowsBefore = 105
	z7RowsAfter  = 104
	z7Floor      = 100
)

// z7Dying are the names whose survivors are the reason the text does not
// compile yet.
var z7Dying = []string{"CMD_read", "usefilter"}

var z7Assign = regexp.MustCompile(`\busefilter\s*=`)

// Zero7 takes the way to read a file: `:read`, its `:r !cmd` arm, and the
// exarg_T.usefilter field that nothing writes once both `:w !` and `:r !` are
// gone.
//
// STEP 4 IS THE JUDGEMENT OF THIS PHASE and the one thing here no tool could
// have found: a struct member that is READ and never written draws no warning,
// and deadfields.py removes only a member nothing names.  do_one_cmd memsets
// `ea`, so every test folded there is constantly FALSE.
func Zero7(text []byte, w io.Writer) ([]byte, error) {
	p := ph{"noread", w}
	var err error

	mentions := func(t []byte, name string) int {
		return len(regexp.MustCompile(`\b`+name+`\b`).FindAll(t, -1))
	}
	inFunction := func(t []byte, name string, edit func([]byte) ([]byte, error)) ([]byte, error) {
		a, z, ok := cutil.FindDefinition(t, cutil.Blank(t), name)
		if !ok {
			return nil, p.die("%s is not defined", name)
		}
		body, err := edit(t[a:z])
		if err != nil {
			return nil, err
		}
		return []byte(string(t[:a]) + string(body) + string(t[z:])), nil
	}
	// within replaces exact text inside one function, counted THERE and not
	// file-wide, and reports -- zero6's namesake does not report, which is the
	// phase's own spelling and not a shared helper's.
	within := func(t []byte, fn, old, new, what string, n int) ([]byte, error) {
		out, err := inFunction(t, fn, func(s []byte) ([]byte, error) {
			k := strings.Count(string(s), old)
			if k != n {
				return nil, p.die("%s -- %s occurs %d times in %s, expected %d",
					what, cutil.PyRepr(zHead(old, 60)), k, fn, n)
			}
			return []byte(strings.ReplaceAll(string(s), old, new)), nil
		})
		if err != nil {
			return nil, err
		}
		p.say(what)
		return out, nil
	}
	// withinStruct is the same inside one struct body: cutil.FindDefinition is
	// functions only.
	withinStruct := func(t []byte, tag, old, new, what string, n int) ([]byte, error) {
		m := regexp.MustCompile(`(?m)^struct ` + regexp.QuoteMeta(tag) + `\n\{\n`).FindIndex(t)
		if m == nil {
			return nil, p.die("struct %s is not defined where this phase expects it", tag)
		}
		o := strings.Index(string(t[m[0]:]), "{") + m[0]
		c := cutil.Match(cutil.Blank(t), o)
		if c < 0 {
			return nil, p.die("struct %s does not close", tag)
		}
		body := string(t[o : c+1])
		k := strings.Count(body, old)
		if k != n {
			return nil, p.die("%s -- %s occurs %d times in struct %s, expected %d",
				what, cutil.PyRepr(zHead(old, 60)), k, tag, n)
		}
		p.say(what)
		return []byte(string(t[:o]) + strings.ReplaceAll(body, old, new) + string(t[c+1:])), nil
	}

	// ---- 0. the table and the field, at the shape the anchors were counted on
	if n := len(zRows(text)); n != z7RowsBefore {
		return nil, p.die("cmdnames[] has %d rows, expected %d -- the anchors below were counted "+
			"against a different table", n, z7RowsBefore)
	}
	names, err := harness.CommandNamesIn(text, "zero-vim.c")
	if err != nil || len(names) != z7RowsBefore {
		return nil, p.die("create_cmdidxs names() does not read %d rows out of this table", z7RowsBefore)
	}
	for _, b := range []struct {
		name string
		want int
	}{{"CMD_read", 3}, {"ex_read", 2}, {"open_buffer", 6}, {"read_buffer", 17},
		{"readfile", 7}, {"usefilter", 10}} {
		if k := mentions(text, b.name); k != b.want {
			return nil, p.die("%s has %d mentions, expected %d -- the anchors below were counted "+
				"against a different file", b.name, k, b.want)
		}
	}
	if writes := len(z7Assign.FindAll(text, -1)); writes != 2 {
		return nil, p.die("usefilter is assigned %d times, expected the 2 that anchor 3 removes -- "+
			"phase 6 took the other two with `:w >>` and `:w !cmd`", writes)
	}
	p.say("cmdnames[] 105 rows, CMD_read 3 mentions, usefilter 10 -- the field, the two " +
		"writes anchor 3 removes and seven reads")

	// ---- 1. the CMD_read enumerator -------------------------------------------
	if strings.Count(string(text), "    CMD_read,\n") != 1 {
		return nil, p.die("the CMD_read enumerator is not one line of its own")
	}
	text = []byte(strings.ReplaceAll(string(text), "    CMD_read,\n", ""))
	p.say("the CMD_read enumerator of enum CMD_index")

	// ---- 2. the cmdnames[] row -------------------------------------------------
	m := regexp.MustCompile(`(?m)^    \[CMD_read\] = \{.*\n`).FindIndex(text)
	if m == nil {
		return nil, p.die("cmdnames[] has no [CMD_read] row")
	}
	text = append(append([]byte{}, text[:m[0]]...), text[m[1]:]...)
	if n := len(zRows(text)); n != z7RowsAfter {
		return nil, p.die("cmdnames[] has %d rows after the cut, expected %d", n, z7RowsAfter)
	}
	p.sayf("the cmdnames[] row; %d -> %d, and create_cmdidxs names() refuses under %d, so "+
		"the margin is %d rows -- the :edit phase spends it (ZERO-PLAN.md 3a)",
		z7RowsBefore, z7RowsAfter, z7Floor, z7RowsAfter-z7Floor)

	// ---- 3. do_one_cmd's `:r!` and `:r !cmd` parse -----------------------------
	if text, err = within(text, "do_one_cmd", z7lit2, "",
		"do_one_cmd no longer parses `:r!` or `:r !cmd`: usefilter loses its last "+
			"two writes", 1); err != nil {
		return nil, err
	}

	// ---- 4. the field nothing writes any more, and its seven readers -----------
	if z7Assign.Match(text) {
		return nil, p.die("usefilter is still assigned after anchor 3, so the fold below would be wrong")
	}
	for _, a := range []struct{ old, new, what string }{
		{"(ea.argt & EX_CMDARG) && !ea.usefilter", "ea.argt & EX_CMDARG",
			"EX_CMDARG takes its argument command whatever the (dead) filter flag said"},
		{"(ea.argt & EX_TRLBAR) && !ea.usefilter", "ea.argt & EX_TRLBAR",
			"and EX_TRLBAR separates a trailing command"},
		{" || ea.usefilter)", ")",
			"and only :global and :vglobal keep a backslash-newline in their argument"},
	} {
		if text, err = within(text, "do_one_cmd", a.old, a.new, a.what, 1); err != nil {
			return nil, err
		}
	}
	if text, err = within(text, "expand_filename", "if (!eap->usefilter && !escaped)", "if (!escaped)",
		"expand_filename escapes a replacement unless it was escaped already", 1); err != nil {
		return nil, err
	}
	if text, err = inFunction(text, "expand_filename", func(s []byte) ([]byte, error) {
		return cutil.FoldNever(s, `(?m)^[ \t]*if \(eap->usefilter &&.*\)$`, 1)
	}); err != nil {
		return nil, err
	}
	p.say("and no longer escapes `!` for a shell, which only a filter needed")
	if text, err = within(text, "expand_filename", "(eap->argt & EX_NOSPC) && !eap->usefilter",
		"eap->argt & EX_NOSPC", "and EX_NOSPC refuses a second file name whatever it said", 1); err != nil {
		return nil, err
	}
	if text, err = withinStruct(text, "exarg", "    int         usefilter;\n", "",
		"the exarg field itself, written by nothing since anchor 3", 1); err != nil {
		return nil, err
	}

	// ---- 5. what is left, and why it does not compile yet ----------------------
	left, holders, _, err := zResidue(p, text, z7Dying)
	if err != nil {
		return nil, err
	}
	s := "s"
	if left == 1 {
		s = ""
	}
	p.sayf("%d mention%s of %s left, inside %s, and no surviving row names it: the text "+
		"does not compile until the sweep has run, and tools/phasecheck.sh is where "+
		"that is asserted", left, s, strings.Join(z7Dying, " and "), strings.Join(holders, ", "))
	return text, nil
}

// zHead is the heredocs' `old[:n]` in a refusal.
func zHead(s string, n int) string {
	if len(s) > n {
		return s[:n]
	}
	return s
}
