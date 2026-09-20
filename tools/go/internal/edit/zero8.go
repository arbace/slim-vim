package edit

import (
	"io"
	"regexp"
	"strings"

	"slimvim.local/tools/internal/cutil"
	"slimvim.local/tools/internal/harness"
)

func init() { register("zero8", Zero8) }

const (
	z8RowsBefore = 104
	z8RowsAfter  = 99
	z8Floor      = 80
)

// z8Going are the five Ex commands that name another file to edit.  They are
// ONE handler; `gf gF [f ]f` are arms inside two surviving handlers and not
// nv_cmds[] rows, which is why anchors 4 and 5 are text and not table edits.
var z8Going = []string{"CMD_edit", "CMD_enew", "CMD_ex", "CMD_visual", "CMD_view"}

var z8Before = map[string]int{
	"CMD_edit": 3, "CMD_enew": 4, "CMD_ex": 2, "CMD_view": 3, "CMD_visual": 2,
	"ex_edit": 6, "do_exedit": 3, "nv_gotofile": 3,
	"EX_ARGOPT": 6, "getargopt": 3, "read_edit": 2,
	"readfile": 5, "open_buffer": 6, "p_ur": 4,
}

// Zero8 takes every way to name another file to edit.
func Zero8(text []byte, w io.Writer) ([]byte, error) {
	p := ph{"noedit", w}
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

	// ---- 0. the shape the anchors below were counted on -----------------------
	if n := len(zRows(text)); n != z8RowsBefore {
		return nil, p.die("cmdnames[] has %d rows, expected %d -- the anchors below were counted "+
			"against a different table", n, z8RowsBefore)
	}
	names, err := harness.CommandNamesIn(text, "zero-vim.c")
	if err != nil || len(names) != z8RowsBefore {
		return nil, p.die("create_cmdidxs names() does not read %d rows out of this table", z8RowsBefore)
	}
	for _, name := range sortedKeys(z8Before) {
		if k := mentions(text, name); k != z8Before[name] {
			return nil, p.die("%s has %d mentions, expected %d -- the anchors below were counted "+
				"against a different file", name, k, z8Before[name])
		}
	}
	// EX_ARGOPT's five rows are what anchor 6 rests on: four here and `:read`'s,
	// which phase 7 took.  Counted, so that a row arriving would refuse rather
	// than leave a reachable block with no way in.
	argopt := 0
	for _, r := range zRows(text) {
		if strings.Contains(string(r), "EX_ARGOPT") {
			argopt++
		}
	}
	if argopt != 4 {
		return nil, p.die("EX_ARGOPT is on %d cmdnames[] rows, expected the 4 this phase removes", argopt)
	}
	p.sayf("cmdnames[] %d rows, ex_edit on 5 of them, EX_ARGOPT on 4, readfile 5 and "+
		"open_buffer 6 -- the line against the byte-reader phase", z8RowsBefore)

	// ---- 1. the five enumerators ----------------------------------------------
	for _, e := range z8Going {
		line := "    " + e + ",\n"
		if strings.Count(string(text), line) != 1 {
			return nil, p.die("the %s enumerator is not one line of its own", e)
		}
		text = []byte(strings.ReplaceAll(string(text), line, ""))
	}
	p.sayf("five enumerators of enum CMD_index: %s", strings.Join(z8Going, " "))

	// ---- 2. the five cmdnames[] rows ------------------------------------------
	for _, e := range z8Going {
		m := regexp.MustCompile(`(?m)^    \[` + e + `\] = \{.*\n`).FindIndex(text)
		if m == nil {
			return nil, p.die("cmdnames[] has no [%s] row", e)
		}
		text = append(append([]byte{}, text[:m[0]]...), text[m[1]:]...)
	}
	if n := len(zRows(text)); n != z8RowsAfter {
		return nil, p.die("cmdnames[] has %d rows after the cut, expected %d", n, z8RowsAfter)
	}
	p.sayf("the five cmdnames[] rows; %d -> %d, which is under the floor create_cmdidxs "+
		"names() had -- lowered to %d in this phase's own commit (ZERO-PLAN.md "+
		"decision 8), so the margin is %d rows",
		z8RowsBefore, z8RowsAfter, z8Floor, z8RowsAfter-z8Floor)

	// ---- 3. do_one_cmd's curbuf_locked() exemption ----------------------------
	if text, err = within(text, "do_one_cmd", "ea.cmdidx != CMD_edit && ", "",
		"do_one_cmd no longer exempts :edit from the curbuf_locked() refusal, "+
			"and :file still is", 1); err != nil {
		return nil, err
	}
	// ---- 4. nv_g_cmd's gf and gF ----------------------------------------------
	if text, err = within(text, "nv_g_cmd", z8lit1, "", "nv_g_cmd's `gf` and `gF` arm", 1); err != nil {
		return nil, err
	}
	// ---- 5. nv_brackets's [f and ]f -------------------------------------------
	// Deleted as counted text and not folded, because the else body is already
	// at the function's own indentation.  The closer is found by brace matching
	// and required to be a line of its own, so a differently shaped else refuses
	// instead of eating the wrong block.
	if text, err = inFunction(text, "nv_brackets", func(s []byte) ([]byte, error) {
		str := string(s)
		k := strings.Count(str, z8Head)
		if k != 1 {
			return nil, p.die("nv_brackets: the `[f` head occurs %d times, expected 1", k)
		}
		i := strings.Index(str, z8Head)
		o := i + len(z8Head) - 2 // the else's `{`
		if str[o] != '{' {
			return nil, p.die("nv_brackets: the else does not open where this phase expects it")
		}
		c := cutil.Match(cutil.Blank(s), o)
		if c < 0 {
			return nil, p.die("nv_brackets: the else's block does not close")
		}
		a := strings.LastIndex(str[:c], "\n") + 1
		z := strings.Index(str[c:], "\n") + c + 1
		if str[a:z] != z8lit4 {
			return nil, p.die("nv_brackets: the else closes with %s, not a line of its own",
				cutil.PyRepr(str[a:z]))
		}
		return []byte(str[:i] + str[i+len(z8Head):a] + str[z:]), nil
	}); err != nil {
		return nil, err
	}
	p.say("nv_brackets's `[f` and `]f` arm, keeping the else that is the rest of the " +
		"function at the indentation it already had")

	// ---- 6. do_one_cmd's ++opt parse ------------------------------------------
	if text, err = within(text, "do_one_cmd", z8lit2, "",
		"do_one_cmd no longer parses `++opt`: EX_ARGOPT is on no row, so "+
			"getargopt() is unreachable and read_edit is written by nothing", 1); err != nil {
		return nil, err
	}

	// ---- 7. what is left, and why it does not compile yet ---------------------
	left, holders, found, err := zResidue(p, text, z8Going)
	if err != nil {
		return nil, err
	}
	s := "s"
	if left == 1 {
		s = ""
	}
	p.sayf("%d mention%s of %s left, inside %s, and no surviving row names it: the text "+
		"does not compile until the sweep has run, and tools/phasecheck.sh is where "+
		"that is asserted", left, s, strings.Join(found, " and "), strings.Join(holders, ", "))
	return text, nil
}
