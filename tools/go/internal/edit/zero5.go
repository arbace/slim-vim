package edit

import (
	"fmt"
	"io"
	"regexp"
	"sort"
	"strconv"
	"strings"

	"slimvim.local/tools/internal/cutil"
)

func init() { register("zero5", Zero5) }

var (
	z5EnumRun  = regexp.MustCompile(`(?m)(?:^enum \{ ME_\w+ = \d+ \};\n)+`)
	z5EnumLine = regexp.MustCompile(`(?m)^enum \{ (ME_\w+) = (\d+) \};$`)
	z5Table    = regexp.MustCompile(`(?ms)^static char \*\(main_errors\[\]\) =\n\{\n(.*?)^\};\n`)
)

// z5Before is every identifier this phase removes at the mentions it has before
// it, plus the ones it must NOT move -- `read_stdin` as a parameter (23 of its
// 26 mentions belong to the phase that stops reading bytes) and the five kept
// ME_* / MAX_ARG_CMDS.
var z5Before = map[string]int{
	"had_minmin": 4, "edit_type": 7, "EDIT_NONE": 3, "EDIT_FILE": 2,
	"EDIT_STDIN": 4, "ME_TOO_MANY_ARGS": 3, "buflist_add": 3,
	"read_stdin": 26, "read_cmd_fd": 13, "ME_UNKNOWN_OPTION": 3,
	"ME_ARG_MISSING": 2, "ME_GARBAGE": 2, "ME_EXTRA_CMD": 2,
	"MAX_ARG_CMDS": 4, "want_argument": 4, "mainerr_arg_missing": 3,
	"exe_commands": 3,
}

// z5After is the same names once the cut has run: each removed name is down to
// its definition, and each definition is a kind tools/sweep.sh deletes.  Stated
// as a number per name, so a use that survived shows up HERE and not as a
// warning five minutes later.
var z5After = map[string]int{
	"had_minmin": 0, "edit_type": 1, "EDIT_NONE": 1, "EDIT_FILE": 1,
	"EDIT_STDIN": 1, "ME_TOO_MANY_ARGS": 0, "buflist_add": 2,
	"read_stdin": 25, "read_cmd_fd": 12, "ME_UNKNOWN_OPTION": 3,
	"ME_ARG_MISSING": 2, "ME_GARBAGE": 2, "ME_EXTRA_CMD": 2,
	"MAX_ARG_CMDS": 4, "want_argument": 4, "mainerr_arg_missing": 3,
	"exe_commands": 3,
}

// Zero5 leaves the command line as `+{command}` and `-T {term}`: the file
// argument, the bare `-` and `--` all become mainerr(ME_UNKNOWN_OPTION).
func Zero5(text []byte, w io.Writer) ([]byte, error) {
	p := ph{"noargv", w}
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
	// within reports only when the caller gives it a `what`: three of the calls
	// below are the second half of an act the line before has already named.
	within := func(t []byte, fn, old, new, what string, n int) ([]byte, error) {
		out, err := inFunction(t, fn, func(s []byte) ([]byte, error) {
			k := strings.Count(string(s), old)
			if k != n {
				w := what
				if w == "" {
					w = "in " + fn
				}
				return nil, p.die("%s -- %s occurs %d times in %s, expected %d",
					w, cutil.PyRepr(old), k, fn, n)
			}
			return []byte(strings.ReplaceAll(string(s), old, new)), nil
		})
		if err != nil {
			return nil, err
		}
		if what != "" {
			p.say(what)
		}
		return out, nil
	}
	// line is a whole line by its trimmed text: the anchor is exact and countable.
	line := func(body string) string { return `(?m)^[ \t]*` + regexp.QuoteMeta(body) + `$` }

	// ---- 0. the invariants the cut rests on -----------------------------------
	for _, name := range sortedKeys2(z5Before) {
		if k := mentions(text, name); k != z5Before[name] {
			return nil, p.die("%s has %d mentions, expected %d -- the anchors below were counted "+
				"against a different file", name, k, z5Before[name])
		}
	}
	p.say("17 identifiers at their counted mentions: had_minmin 4, edit_type 7, " +
		"read_stdin 26 (23 of them a parameter)")

	// ---- 1. the parser: three ways to name a file or a stream -----------------
	if text, err = within(text, "command_line_scan", z5lit1, z5lit2,
		"a file argument is an unknown option: buflist_add loses its only caller", 1); err != nil {
		return nil, err
	}
	if text, err = within(text, "command_line_scan", z5lit3, "\n",
		"and `p`, which only that arm used", 1); err != nil {
		return nil, err
	}
	if text, err = within(text, "command_line_scan", z5lit5, "",
		"a bare `-` is an unknown option: EDIT_STDIN and read_cmd_fd = 2 go", 1); err != nil {
		return nil, err
	}
	if text, err = within(text, "command_line_scan", z5lit6, "",
		"`--` no longer ends the options", 1); err != nil {
		return nil, err
	}
	if text, err = within(text, "command_line_scan", z5lit7, "\n",
		"and had_minmin, the flag it set", 1); err != nil {
		return nil, err
	}
	if text, err = within(text, "command_line_scan", `if (argv[0][0] == '+' && !had_minmin)`,
		`if (argv[0][0] == '+')`, "so +cmd is +cmd wherever it appears", 1); err != nil {
		return nil, err
	}
	if text, err = within(text, "command_line_scan", `else if (argv[0][0] == '-' && !had_minmin)`,
		`else if (argv[0][0] == '-')`, "and an option is an option", 1); err != nil {
		return nil, err
	}

	// ---- 2. ME_TOO_MANY_ARGS, and the row it indexes --------------------------
	// ONE PARSE OF BOTH LISTS, and the edit is computed from it: the enumerators
	// are main_errors[]'s indices, so the two cannot be edited separately without
	// the numbering being a guess.
	const gone = "ME_TOO_MANY_ARGS"
	enums := z5EnumRun.FindString(string(text))
	if enums == "" {
		return nil, p.die("the ME_* enumerators are not a run of `enum { NAME = N };` lines")
	}
	pairs := z5EnumLine.FindAllStringSubmatch(enums, -1)
	var repr []string
	for i, pr := range pairs {
		if v, _ := strconv.Atoi(pr[2]); v != i {
			for _, q := range pairs {
				repr = append(repr, "("+cutil.PyRepr(q[1])+", "+cutil.PyRepr(q[2])+")")
			}
			return nil, p.die("the ME_* enumerators are not 0..%d in order: [%s]",
				len(pairs)-1, strings.Join(repr, ", "))
		}
	}
	tm := z5Table.FindStringSubmatchIndex(string(text))
	if tm == nil {
		return nil, p.die("main_errors[] is not where it was")
	}
	whole := string(text[tm[0]:tm[1]])
	rows := z5Lines(string(text[tm[2]:tm[3]]))
	if len(rows) != len(pairs)+1 {
		return nil, p.die("main_errors[] has %d rows for %d enumerators; this phase only knows the "+
			"shape where the one extra row is the unreachable one whim left", len(rows), len(pairs))
	}
	names := make([]string, len(pairs))
	for i, pr := range pairs {
		names[i] = pr[1]
	}
	i := indexOf(names, gone)
	if i < 0 {
		return nil, p.die("%s is not among the ME_* enumerators", gone)
	}
	if !strings.Contains(rows[i], "Too many edit arguments") {
		return nil, p.die("main_errors[%d] is %s, which is not %s's row",
			i, cutil.PyRepr(strings.TrimSpace(rows[i])), gone)
	}
	var kept []string
	for _, n := range names {
		if n != gone {
			kept = append(kept, n)
		}
	}
	var newEnums, newRows strings.Builder
	for k, n := range kept {
		fmt.Fprintf(&newEnums, "enum { %s = %d };\n", n, k)
	}
	for k, r := range rows {
		if k != i {
			newRows.WriteString(r)
		}
	}
	text = []byte(strings.ReplaceAll(
		strings.ReplaceAll(string(text), enums, newEnums.String()),
		whole, "static char *(main_errors[]) =\n{\n"+newRows.String()+"};\n"))
	var moved []string
	for k, n := range kept {
		if o := indexOf(names, n); o != k {
			moved = append(moved, fmt.Sprintf("%s %d->%d", n, o, k))
		}
	}
	p.sayf("%s and its row go; %s", gone, strings.Join(moved, ", "))
	p.sayf("main_errors[] keeps its sixth row, %s, which no enumerator named before this "+
		"phase either", strings.TrimSpace(strings.TrimRight(strings.TrimSpace(rows[len(rows)-1]), ",")))

	// ---- 3. what params.edit_type is once nothing assigns it ------------------
	if text, err = inFunction(text, "vim_main2", func(s []byte) ([]byte, error) {
		return cutil.FoldNever(s, line("if (params.edit_type == EDIT_STDIN)"), 1)
	}); err != nil {
		return nil, err
	}
	p.say("vim_main2 no longer reads a buffer from stdin: read_stdin loses its call")
	if text, err = within(text, "vim_main2", " && params.edit_type != EDIT_STDIN)", ")",
		"and sets newline_on_exit on the two conditions that are left", 1); err != nil {
		return nil, err
	}

	// ---- 4. what is left is exactly what the sweep can take -------------------
	for _, name := range sortedKeys2(z5After) {
		k := mentions(text, name)
		if k != z5After[name] {
			why := "more went than was meant to"
			if k > z5After[name] {
				why = "a use survived"
			}
			return nil, p.die("%s has %d mentions after the cut, expected %d -- %s",
				name, k, z5After[name], why)
		}
	}
	if strings.Contains(string(text), "Too many edit arguments") {
		return nil, p.die("'Too many edit arguments' survives the edit")
	}
	p.say("every use of the six is gone; the field, three enumerators, read_stdin and " +
		"buflist_add are what the sweep takes")
	return text, nil
}

// z5Lines is Python's splitlines(keepends=True): each line with its newline.
func z5Lines(s string) []string {
	var out []string
	for len(s) > 0 {
		i := strings.IndexByte(s, '\n')
		if i < 0 {
			out = append(out, s)
			break
		}
		out = append(out, s[:i+1])
		s = s[i+1:]
	}
	return out
}

func sortedKeys2(m map[string]int) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}
