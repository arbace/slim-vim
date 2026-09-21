package check

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"slimvim.local/tools/internal/harness"
)

func init() { register("whim81", Whim81) }

// Whim81 is phase 81's check: one line, one command.
func Whim81(w io.Writer, args []string) error {
	if len(args) < 2 {
		return fmt.Errorf("usage: check whim81 <work-dir> <state-dir>")
	}
	work, state := args[0], args[1]
	r := &rep{tag: "onecommand", w: w}
	f := filepath.Join(work, "whim-vim.c")
	beforeLines := strings.TrimSpace(readFile(filepath.Join(state, "input-lines")))
	src := []byte(readFile(f))
	for _, g := range []string{"comment_start", "starts_with_colon"} {
		if n := countWord(src, g); n != 0 {
			r.say("%s still has %d mentions", g, n)
			return harness.ErrReported
		}
	}
	if err := run(w, "sh", "tools/phasecheck.sh", work, f, filepath.Join(state, "symbols")); err != nil {
		return harness.ErrReported
	}
	if err := run(w, "sh", "tools/phasebuild.sh", work, beforeLines); err != nil {
		return harness.ErrReported
	}

	d, err := os.MkdirTemp("", "whim81")
	if err != nil {
		return err
	}
	defer os.RemoveAll(d)
	home, _ := os.MkdirTemp(d, "onecommand-home-")
	env := whimEnv(home)
	oldV, e1 := harness.Stage(filepath.Join(state, "old"))
	newV, e2 := harness.Stage(filepath.Join(work, "whim-vim"))
	if e1 != nil || e2 != nil {
		return fmt.Errorf("staging the two binaries failed")
	}
	const (
		bar   = "a bar is argument text"
		quote = "a quote is argument text"
		esc   = "a backslash before a bar stays"
	)
	type cse struct {
		cmds []string
		why  string
	}
	differ := []cse{
		{[]string{"%s/a/X/|%s/b/Y/"}, bar}, {[]string{"set ts=3|%s/a/X/"}, bar}, {[]string{"1d|1d"}, bar},
		{[]string{"2|"}, bar}, {[]string{"|"}, bar}, {[]string{"1a|new"}, bar},
		{[]string{"map Q A|b", "normal Q"}, bar}, {[]string{"nmap Q A|b", "normal Q"}, bar},
		{[]string{"\" a comment"}, quote}, {[]string{"\""}, quote}, {[]string{"set ts=3 \" a comment"}, quote},
		{[]string{"%s/a/X/ \" a comment"}, quote}, {[]string{"1d \" a comment"}, quote},
		{[]string{"map Q A\\|b", "normal Q"}, esc},
	}
	same := [][]string{
		{"%s/a/X/"}, {"%s/a/X/", "%s/b/Y/"}, {"%s/a\\|b/Q/g"}, {"g/a\\|c/d"}, {"g/b/s/a/Z/"},
		{"%s/a/\"/"}, {"%s/\"/q/"}, {"normal! A\"x"}, {"normal! A|x"}, {"map Q AX", "normal Q"},
		{"map Q A\"b", "normal Q"}, {"map Q A\x16|b", "normal Q"}, {"set ts=3"}, {"2,3d"}, {"2d 2"},
		{"%s/a/X/\n%s/b/Y/"}, {"1d\n1d"}, {"$"}, {"2"}, {"%p"}, {"1a"}, {"%j"},
		{"map Q A\\\"b", "normal Q"}, {"let x = 1"}, {"echo \"x\""}, {"@\""}, {"2*"}, {"undo"}, {"map Q A b ", "normal Q"},
	}
	key := func(c []string) string { return strings.Join(c, "\x00") }
	all := map[string][]string{}
	isDiffer := map[string]bool{}
	for _, c := range differ {
		all[key(c.cmds)] = c.cmds
		isDiffer[key(c.cmds)] = true
	}
	for _, c := range same {
		all[key(c)] = c
	}
	// Python sorts the tuples themselves: element by element, a shorter tuple
	// first when it is a prefix.
	var todo [][]string
	for _, c := range all {
		todo = append(todo, c)
	}
	less := func(a, b []string) bool {
		for i := 0; i < len(a) && i < len(b); i++ {
			if a[i] != b[i] {
				return a[i] < b[i]
			}
		}
		return len(a) < len(b)
	}
	sort.Slice(todo, func(i, j int) bool { return less(todo[i], todo[j]) })
	argv := func(c []string) []string {
		var a []string
		for _, x := range c {
			a = append(a, "+"+x)
		}
		return append(a, "+w! out.txt", "+q!")
	}
	oldR, newR := make([]whimRes, len(todo)), make([]whimRes, len(todo))
	whimPool(len(todo), func(i int) { oldR[i] = whimRun(oldV, d, env, argv(todo[i]), "out.txt") })
	whimPool(len(todo), func(i int) { newR[i] = whimRun(newV, d, env, argv(todo[i]), "out.txt") })
	idx := map[string]int{}
	var gotSet = map[string]bool{}
	for i, c := range todo {
		idx[key(c)] = i
		if !oldR[i].eq(newR[i], false) {
			gotSet[key(c)] = true
		}
	}
	mismatch := len(gotSet) != len(isDiffer)
	for k := range gotSet {
		if !isDiffer[k] {
			mismatch = true
		}
	}
	tupleRepr := func(c []string) string {
		q := make([]string, len(c))
		for i, x := range c {
			q[i] = pyRepr(x)
		}
		if len(q) == 1 {
			return "(" + q[0] + ",)"
		}
		return "(" + strings.Join(q, ", ") + ")"
	}
	resRepr := func(x whimRes) string {
		if x.timeout {
			return "('TIMEOUT',)"
		}
		b := "None"
		if x.body != nil {
			b = pyRepr(*x.body)
		}
		return fmt.Sprintf("(%s, %q, %s)", x.rc, x.stderr, b)
	}
	if mismatch {
		fmt.Fprintf(w, "  onecommand   old and new binaries differ on %d cases, expected %d:\n", len(gotSet), len(differ))
		for i, c := range todo {
			k := key(c)
			if gotSet[k] != isDiffer[k] {
				fmt.Fprintf(w, "                 %-36s old %s\n", tupleRepr(c), resRepr(oldR[i]))
				fmt.Fprintf(w, "                 %-36s new %s\n", "", resRepr(newR[i]))
			}
		}
		return harness.ErrReported
	}
	for _, p := range []struct {
		c    []string
		body string
	}{{[]string{"map Q A|b", "normal Q"}, "a\nba\nca|b\n"}, {[]string{"map Q A\\|b", "normal Q"}, "a\nba\nca\\|b\n"}} {
		n := newR[idx[key(p.c)]]
		if n.body == nil || *n.body != p.body {
			b := "None"
			if n.body != nil {
				b = pyRepr(*n.body)
			}
			r.say("%s wrote %s, expected %s", tupleRepr(p.c), b, pyRepr(p.body))
			return harness.ErrReported
		}
	}
	bi := idx[key([]string{"%s/a/X/|%s/b/Y/"})]
	if o, n := oldR[bi], newR[bi]; o.body == nil || *o.body != "X\nYX\ncX\n" || n.body == nil || *n.body != "a\nba\nca\n" {
		fmt.Fprintf(w, "  onecommand   the bar case did not show a split before and none after: %s -> %s\n", optRepr(o.body), optRepr(n.body))
		return harness.ErrReported
	}
	r.say("%d cases through both binaries: %d differ exactly as declared, %d identical", len(todo), len(differ), len(same))
	return nil
}
