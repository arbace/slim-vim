package edit

import (
	"fmt"
	"io"
	"regexp"
	"strings"

	"slimvim.local/tools/internal/cutil"
	"slimvim.local/tools/internal/harness"
)

func init() { register("zero6", Zero6) }

// z6Six are the six commands that put bytes on a disk, and nothing else.
var z6Six = []string{"CMD_exit", "CMD_saveas", "CMD_update", "CMD_write", "CMD_wq", "CMD_xit"}

const (
	z6RowsBefore = 111
	z6RowsAfter  = 105
	z6Floor      = 100
)

// Zero6 takes every way to write a file: the six Ex commands, ZZ and the
// `:w >>` / `:w !` parse.
//
// FOUR ANCHORS AND NOT ONE FOLD.  The row is the only reference a command
// handler has, so taking the row is what makes the handler unreachable and the
// sweep is what removes it.  The text this edit leaves DOES NOT COMPILE --
// step 5 is the honest form of that claim, computed rather than listed.
func Zero6(text []byte, w io.Writer) ([]byte, error) {
	p := ph{"nowrite", w}

	// literal is the heredoc's, and it does NOT report: step 1 and step 2 each
	// call it six times and then say one line.
	literal := func(t []byte, old, new, what string, n int) ([]byte, error) {
		k := strings.Count(string(t), old)
		if k != n {
			return nil, p.die("%s -- %s occurs %d times, expected %d", what, cutil.PyRepr(zHead(old, 50)), k, n)
		}
		return []byte(strings.ReplaceAll(string(t), old, new)), nil
	}
	// within replaces exact text inside ONE function, counted there and not
	// file-wide -- `q!` is already in nv_Zet's neighbour as ZQ's.
	within := func(t []byte, fn, old, new, what string, n int) ([]byte, error) {
		a, z, ok := cutil.FindDefinition(t, cutil.Blank(t), fn)
		if !ok {
			return nil, p.die("%s is not defined", fn)
		}
		body := string(t[a:z])
		k := strings.Count(body, old)
		if k != n {
			return nil, p.die("%s -- %s occurs %d times in %s, expected %d",
				what, cutil.PyRepr(zHead(old, 50)), k, fn, n)
		}
		return []byte(string(t[:a]) + strings.ReplaceAll(body, old, new) + string(t[z:])), nil
	}

	// ---- 0. the table this phase edits, at the shape the anchors were counted on
	if n := len(zRows(text)); n != z6RowsBefore {
		return nil, p.die("cmdnames[] has %d rows, expected %d -- the anchors below were counted "+
			"against a different table", n, z6RowsBefore)
	}
	names, err := harness.CommandNamesIn(text, "zero-vim.c")
	if err != nil || len(names) != z6RowsBefore {
		return nil, p.die("create_cmdidxs.names() does not read %d rows out of this table", z6RowsBefore)
	}

	// ---- 1. the six enumerators of enum CMD_index -----------------------------
	for _, e := range z6Six {
		if text, err = literal(text, fmt.Sprintf("    %s,\n", e), "", "the "+e+" enumerator", 1); err != nil {
			return nil, err
		}
	}
	short := make([]string, len(z6Six))
	for i, e := range z6Six {
		short[i] = e[4:]
	}
	p.sayf("six enumerators of enum CMD_index: %s", strings.Join(short, " "))

	// ---- 2. the six cmdnames[] rows -------------------------------------------
	for _, e := range z6Six {
		re := regexp.MustCompile(`(?m)^    \[` + e + `\] = \{.*\n`)
		m := re.FindIndex(text)
		if m == nil {
			return nil, p.die("cmdnames[] has no [%s] row", e)
		}
		text = append(append([]byte{}, text[:m[0]]...), text[m[1]:]...)
	}
	if n := len(zRows(text)); n != z6RowsAfter {
		return nil, p.die("cmdnames[] has %d rows after the cut, expected %d", n, z6RowsAfter)
	}
	p.sayf("six cmdnames[] rows; %d -> %d, and create_cmdidxs.names() refuses under %d, "+
		"so the margin is %d rows -- the :edit phase spends it (ZERO-PLAN.md 3a)",
		z6RowsBefore, z6RowsAfter, z6Floor, z6RowsAfter-z6Floor)

	// ---- 3. ZZ ----------------------------------------------------------------
	if text, err = within(text, "nv_Zet", `do_cmdline_cmd((char_u *)"x");`,
		`do_cmdline_cmd((char_u *)"q!");`, `ZZ is ZQ: nv_Zet runs "q!" where it ran "x"`, 1); err != nil {
		return nil, err
	}
	p.say(`ZZ is ZQ: nv_Zet runs the string "q!" where it ran "x", which is this ` +
		`phase's decision and moves case:zz_key`)

	// ---- 4. do_one_cmd's :w>> and :w! parse -----------------------------------
	if text, err = within(text, "do_one_cmd", z6lit1, "",
		"do_one_cmd no longer parses `:w >>file` or `:w !cmd`", 1); err != nil {
		return nil, err
	}
	p.say("do_one_cmd's `:w>>` and `:w!` parse, deleted as text: its condition named " +
		"two of the enumerators above")

	// ---- 5. what is left, and why it does not compile yet ---------------------
	left, holders, _, err := zResidue(p, text, z6Six)
	if err != nil {
		return nil, err
	}
	p.sayf("%d mentions of the six are left, all inside %s, and no surviving row names "+
		"any of them: the text does not compile until the sweep has run, and "+
		"tools/phasecheck.sh is where that is asserted", left, strings.Join(holders, ", "))
	return text, nil
}
