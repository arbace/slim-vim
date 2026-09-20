package cut

import (
	"fmt"
	"io"
	"regexp"
	"sort"
	"strings"

	"slimvim.local/tools/internal/cutil"
)

// pyList renders a []string the way Python prints a list of str.
func pyList(items []string) string {
	parts := make([]string, len(items))
	for i, s := range items {
		parts[i] = cutil.PyRepr(s)
	}
	return "[" + strings.Join(parts, ", ") + "]"
}

// cCaseArm is `-c` in the option switch, and it is the one place in this port
// where Go cannot spell the Python's pattern.
//
// The Python ends with a LOOKAHEAD, `(?=[ \t]*case 'T':\n)` -- and RE2 has no
// lookahead at all, by design.  The equivalent without one is to match the
// trailing context and put it back: capture the `case 'T':` line and replace
// the whole match with just that.  The two agree exactly while the count is
// one, which this asserts.
var (
	cCaseArm = regexp.MustCompile(`(?sm)^[ \t]*case 'c':\n[ \t]*if \(argv\[0\]\[argv_idx\] != NUL\)\n` +
		`.*?^[ \t]*__attribute__\(\(fallthrough\)\);\n([ \t]*case 'T':\n)`)
	mCaseArm = regexp.MustCompile(`(?m)^[ \t]*case 'M':\n[ \t]*reset_modifiable\(\);\n\n` +
		`[ \t]*__attribute__\(\(fallthrough\)\);\n` +
		`[ \t]*case 'm':\n[ \t]*p_write = FALSE;\n[ \t]*break;\n\n`)
	preCommands = regexp.MustCompile(`(?m)^[ \t]*exe_pre_commands\(&params\);\n`)
	leftCase    = regexp.MustCompile(`(?m)^[ \t]*case '[cRmMw]':$`)
	leftCmd     = regexp.MustCompile(`\("cmd"\)`)
)

func setEqual(got map[string]bool, want ...string) bool {
	if len(got) != len(want) {
		return false
	}
	for _, w := range want {
		if !got[w] {
			return false
		}
	}
	return true
}

func sortedKeys(m map[string]bool) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}

// NoCmdArgs removes -c, --cmd, -R, -m, -M and -w.
func NoCmdArgs(text []byte, w io.Writer) ([]byte, error) {
	blanked := cutil.Blank(text)
	a, z, ok := cutil.FindDefinition(text, blanked, "command_line_scan")
	if !ok {
		return nil, fmt.Errorf("nocmdargs: command_line_scan is not defined at file scope")
	}
	fn := text[a:z]

	if n := len(cCaseArm.FindAll(fn, -1)); n != 1 {
		return nil, fmt.Errorf("nocmdargs: -c in the option switch -- matched %d times, "+
			"expected 1", n)
	}
	fn = cCaseArm.ReplaceAll(fn, []byte("${1}"))
	fmt.Fprintln(w, "  nocmdargs    -c in the option switch")

	if n := len(mCaseArm.FindAll(fn, -1)); n != 1 {
		return nil, fmt.Errorf("nocmdargs: -M and -m -- matched %d times, expected 1", n)
	}
	fn = mCaseArm.ReplaceAll(fn, nil)
	fmt.Fprintln(w, "  nocmdargs    -M and -m")

	fn, held, err := DropShort(fn, 0, map[string]bool{"R": true, "w": true})
	if err != nil {
		return nil, err
	}
	if !setEqual(held, "R", "w") {
		return nil, fmt.Errorf("nocmdargs: -R and -w are not both labels in the option "+
			"switch: %s", pyList(sortedKeys(held)))
	}
	fmt.Fprintln(w, "  nocmdargs    -R and -w")

	fn, inArgs, err := DropShort(fn, 1, map[string]bool{"c": true, "-": true})
	if err != nil {
		return nil, err
	}
	if !setEqual(inArgs, "c", "-") {
		return nil, fmt.Errorf("nocmdargs: -c and -- are not both in the argument "+
			"switch: %s", pyList(sortedKeys(inArgs)))
	}
	fmt.Fprintln(w, "  nocmdargs    -c and --cmd in the argument switch")

	if fn, err = DropLong(fn, "cmd"); err != nil {
		return nil, err
	}
	fmt.Fprintln(w, "  nocmdargs    --cmd in the option switch")

	fn, err = cutil.FoldAlways(fn, `(?m)^[ \t]*if \(!want_argument\)$`, 1)
	if err != nil {
		return nil, fmt.Errorf("nocmdargs: -- asking whether it wants an argument -- %v", err)
	}
	fmt.Fprintln(w, "  nocmdargs    -- no longer asks whether it wants an argument")

	var buf []byte
	buf = append(buf, text[:a]...)
	buf = append(buf, fn...)
	text = append(buf, text[z:]...)

	if n := len(preCommands.FindAll(text, -1)); n != 1 {
		return nil, fmt.Errorf("nocmdargs: startup running the --cmd commands -- matched "+
			"%d times, expected 1", n)
	}
	text = preCommands.ReplaceAll(text, nil)
	fmt.Fprintln(w, "  nocmdargs    startup running the --cmd commands")

	var left []string
	for _, c := range []struct {
		what string
		re   *regexp.Regexp
	}{
		{"a case for -c, -R, -m, -M or -w", leftCase},
		{"--cmd in the parser", leftCmd},
	} {
		if n := len(c.re.FindAll(fn, -1)); n != 0 {
			left = append(left, fmt.Sprintf("(%s, %d)", cutil.PyRepr(c.what), n))
		}
	}
	if len(left) > 0 {
		return nil, fmt.Errorf("nocmdargs: still present: [%s]", strings.Join(left, ", "))
	}

	fmt.Fprintln(w, "  nocmdargs    -c, --cmd, -R, -m, -M and -w are unknown options")
	return text, nil
}
