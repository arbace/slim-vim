package check

import (
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"

	"slimvim.local/tools/internal/harness"
)

func init() { register("whim80", Whim80) }

var w80Lines = []string{"%d", ".d", "$d", "2;3d", "1,2d", "3,1d", "d 2", "2d 2", "'<,'>d", "*d", "-1d", "+1d",
	"2q", "%q", "$q", ".q", "0q", "1,2q", "%undo", "2undo", "0undo", "%messages", "3messages",
	"%normal Ax", "2,3>", "%<", "g/a/d", "v/a/d", "2k a", "ka", "2mark b", "%s/a/X/g", "%&&",
	"2,3m0", "1t$", "1co$", "2,3j", "%p", "%#", "%l", "=", "1z", ".=", "2,3y", "0put", "$put",
	"2,3w! w.txt", "2,$w >> f.txt", "r f.txt", "0r f.txt", "2cq", "%cq", "1,2~", "%@a",
	"2*", "wq!", "2,3x", "up", "sav s.txt", "e!", "ene", "vi", "vie", "ex", "f n.txt",
	"set ts=3|%s/a/X/|w", "ma b|2d|w", "nmap|%s/a/X/|w", "dl", "dp", "2dl 2", "Print", "2P",
	"++", "--", "{", "}", "!", "!ls", "#", "&", "1,2&", "k", "ke", "sg", "si", "sI", "sr", "sc",
	"buffer|%s/a/X/|w", "if 1|%s/a/X/|w", "lua|%s/a/X/|w", "n|%s/a/X/|w", "h|%s/a/X/|w"}

// Whim80 is phase 80's check: the Ex command table, cut to the commands that
// exist.
func Whim80(w io.Writer, args []string) error {
	if len(args) < 2 {
		return fmt.Errorf("usage: check whim80 <work-dir> <state-dir>")
	}
	work, state := args[0], args[1]
	r := &rep{tag: "cmdtable", w: w}
	f := filepath.Join(work, "whim-vim.c")
	beforeLines := strings.TrimSpace(readFile(filepath.Join(state, "input-lines")))
	declared, err := exec.Command("sh", "tools/whimdelta.sh", "--declared", "80").Output()
	if err != nil {
		return harness.ErrReported
	}
	src := []byte(readFile(f))
	for _, g := range strings.Fields("cmd_namelen cmdidxs1 cmdidxs2 command_count e_command_table_needs_to_be_updated_run_make_cmdidxs " +
		"if_level ex_ni ex_script_ni get_wincmd_addr_type " +
		"ADDR_ARGUMENTS ADDR_BUFFERS ADDR_LOADED_BUFFERS ADDR_QUICKFIX ADDR_QUICKFIX_VALID ADDR_TABS ADDR_TABS_RELATIVE") {
		if n := countWord(src, g); n != 0 {
			r.say("%s still has %d mentions", g, n)
			return harness.ErrReported
		}
	}
	alnum := regexp.MustCompile(`^[A-Za-z0-9]*$`)
	for _, c := range strings.Fields(string(declared)) {
		if !alnum.MatchString(c) {
			continue
		}
		if regexp.MustCompile(`\bCMD_` + c + `\b`).Match(src) {
			r.say("CMD_%s survives", c)
			return harness.ErrReported
		}
	}
	if n := len(regexp.MustCompile(`(?m)^    \[CMD_\w+\] = \{\(char_u \*\)".*$`).FindAll(src, -1)); n != 111 {
		r.say("%d rows, expected 111", n)
		return harness.ErrReported
	}
	if regexp.MustCompile(`(?m)^    \[CMD_\w+\] = .*sizeof\(".*$`).Match(src) {
		r.say("a row still carries its name length")
		return harness.ErrReported
	}
	r.say("111 rows, no index, nothing names a removed command or address type")
	if err := run(w, "sh", "tools/phasecheck.sh", work, f, filepath.Join(state, "symbols")); err != nil {
		return harness.ErrReported
	}
	if err := run(w, "sh", "tools/phasebuild.sh", work, beforeLines); err != nil {
		return harness.ErrReported
	}

	d, err := os.MkdirTemp("", "whim80")
	if err != nil {
		return err
	}
	defer os.RemoveAll(d)
	home, _ := os.MkdirTemp(d, "cmdtable-home-")
	env := whimEnv(home)
	oldV, e1 := harness.Stage(filepath.Join(state, "old"))
	newV, e2 := harness.Stage(filepath.Join(work, "whim-vim"))
	if e1 != nil || e2 != nil {
		return fmt.Errorf("staging the two binaries failed")
	}
	var words []string
	for _, line := range strings.Split(strings.TrimRight(readFile(filepath.Join(state, "words")), "\n"), "\n") {
		wd, old, _ := strings.Cut(line, "\t")
		if old != "stop" && old != "suspend" {
			words = append(words, wd)
		}
	}
	set := map[string]bool{}
	for _, x := range words {
		set[x] = true
	}
	for _, x := range w80Lines {
		set[x] = true
	}
	var todo []string
	for k := range set {
		todo = append(todo, k)
	}
	sort.Strings(todo)
	oldR, newR := make([]whimRes, len(todo)), make([]whimRes, len(todo))
	whimPool(len(todo), func(i int) { oldR[i] = whimRun(oldV, d, env, []string{"+" + todo[i], "+q!"}, "f.txt") })
	whimPool(len(todo), func(i int) { newR[i] = whimRun(newV, d, env, []string{"+" + todo[i], "+q!"}, "f.txt") })
	const bar = "a stub no longer splits its line at the bar"
	differ := map[string]string{"if": "accepted, now an error", "if 1|%s/a/X/|w": "accepted, now an error",
		"buffer|%s/a/X/|w": bar, "n|%s/a/X/|w": bar}
	var dk []string
	for k := range differ {
		dk = append(dk, k)
	}
	sort.Strings(dk)
	idx := map[string]int{}
	var got []string
	for i, c := range todo {
		idx[c] = i
		if !oldR[i].eq(newR[i], true) {
			got = append(got, c)
		}
	}
	if strings.Join(got, "\x00") != strings.Join(dk, "\x00") {
		fmt.Fprintf(w, "  cmdtable     old and new binaries differ on %d command lines:\n", len(got))
		for _, c := range head(got, 20) {
			o, n := oldR[idx[c]], newR[idx[c]]
			fmt.Fprintf(w, "                 %-18s old (%s, %q)\n", pyRepr(c), o.rc, o.stderr)
			fmt.Fprintf(w, "                 %-18s new (%s, %q)\n", "", n.rc, n.stderr)
		}
		q := make([]string, len(dk))
		for i, k := range dk {
			q[i] = pyRepr(k)
		}
		fmt.Fprintf(w, "                 expected exactly: [%s]\n", strings.Join(q, ", "))
		return harness.ErrReported
	}
	if o, n := oldR[idx["if"]], newR[idx["if"]]; o.rc != "0" || n.rc != "1" {
		fmt.Fprintf(w, "  cmdtable     :if was expected to go from exit 0 to 1: (%s,) -> (%s,)\n", o.rc, n.rc)
		return harness.ErrReported
	}
	for _, c := range []string{"buffer|%s/a/X/|w", "n|%s/a/X/|w"} {
		o, n := oldR[idx[c]], newR[idx[c]]
		if o.body == nil || *o.body != "X\nbX\ncX\n" || n.body == nil || *n.body != "a\nba\nca\n" {
			fmt.Fprintf(w, "  cmdtable     %s: expected the old binary to substitute and write, the new not to: %s -> %s\n", pyRepr(c), optRepr(o.body), optRepr(n.body))
			return harness.ErrReported
		}
	}
	var kv []string
	for _, k := range dk {
		kv = append(kv, fmt.Sprintf("%s (%s)", k, differ[k]))
	}
	r.say("%d words and %d command lines through both binaries: identical but for %s", len(words), len(w80Lines), strings.Join(kv, ", "))
	return nil
}

// optRepr is repr() of a file's contents, or None when there was no file.
func optRepr(b *string) string {
	if b == nil {
		return "None"
	}
	return pyRepr(*b)
}
