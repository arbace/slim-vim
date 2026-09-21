package check

import (
	"bytes"
	"io/fs"
	"os"
	"os/exec"
	"regexp"
	"strings"
)

// The small shell verbs a check reaches for, once each.  They are here rather
// than in each port because a check is mostly the SAME half-dozen shell idioms
// over different anchors, and thirty private copies would be thirty chances to
// spell `tr '\n' '|'` differently.

// readFile is `cat`, and an unreadable file is the empty string: every caller
// here is asserting about content, and a missing file fails that assertion on
// its own terms rather than by panicking somewhere else.
func readFile(p string) string {
	b, err := os.ReadFile(p)
	if err != nil {
		return ""
	}
	return string(b)
}

// sizeOf is `stat -c%s`.
func sizeOf(p string) int64 {
	fi, err := os.Stat(p)
	if err != nil {
		return -1
	}
	return fi.Size()
}

// copyExec is `cp` of a binary, and the mode matters: a staged editor that is
// not executable fails with a message about the shell rather than the phase.
func copyExec(src, dst string) error {
	b, err := os.ReadFile(src)
	if err != nil {
		return err
	}
	return os.WriteFile(dst, b, fs.FileMode(0o755))
}

// pipeJoin is `tr '\n' '|'`, which is how every check here compares a small
// file's contents on one line.
func pipeJoin(s string) string { return strings.ReplaceAll(s, "\n", "|") }

// exitCode is `$?` for a command that ran and refused.  A signal or a failure
// to start is -1, which no check expects, so it refuses rather than passing as
// some other status.
func exitCode(err error) int {
	var ee *exec.ExitError
	if errorsAs(err, &ee) {
		return ee.ExitCode()
	}
	return -1
}

func errorsAs(err error, target **exec.ExitError) bool {
	if ee, ok := err.(*exec.ExitError); ok {
		*target = ee
		return true
	}
	return false
}

// awkRange is `awk '/from/,/to/'`: every line from the first match of from
// through the first following match of to, inclusive, and nothing if from is
// never seen.  It is awk's range and not a brace match -- the checks that use
// it are reading a function body whose closing `}` is in column 1, which is
// what the tree's own formatting guarantees.
func awkRange(src []byte, from, to string) string {
	f := regexp.MustCompile("(?m)" + from)
	t := regexp.MustCompile("(?m)" + to)
	var out []string
	in := false
	for _, line := range strings.Split(string(bytes.TrimRight(src, "\n")), "\n") {
		if !in {
			if f.MatchString(line) {
				in = true
				out = append(out, line)
			}
			continue
		}
		out = append(out, line)
		if t.MatchString(line) {
			break
		}
	}
	return strings.Join(out, "\n")
}

// hasLine is `grep -qxF`: one whole line, matched literally.  It exists
// because a shell check writes `grep -q '^check_tty(void)$'`, where basic
// regular expressions leave the parentheses alone -- compiled as an RE2
// pattern the same string is a group and matches something else entirely.
func hasLine(src []byte, line string) bool {
	for _, l := range strings.Split(string(src), "\n") {
		if l == line {
			return true
		}
	}
	return false
}

// countWord is `grep -cw`: lines holding the name as a whole word.
func countWord(src []byte, name string) int {
	return len(regexp.MustCompile(`(?m)^.*\b`+regexp.QuoteMeta(name)+`\b.*$`).FindAll(src, -1))
}

// countLinesWith is `grep -cF`: lines holding the text literally.
func countLinesWith(src []byte, text string) int {
	n := 0
	for _, l := range strings.Split(string(src), "\n") {
		if strings.Contains(l, text) {
			n++
		}
	}
	return n
}

// countLines is `grep -c ''`, which counts LINES and not newlines: a file whose
// last line has no newline still has that line.
func countLines(src []byte) int {
	s := string(src)
	if s == "" {
		return 0
	}
	n := strings.Count(s, "\n")
	if !strings.HasSuffix(s, "\n") {
		n++
	}
	return n
}

// hasLinePrefix is `grep -q '^literal'` where the literal holds regex
// metacharacters -- `^getexline(` is an unclosed group to RE2 and an ordinary
// prefix to grep.
func hasLinePrefix(src []byte, prefix string) bool {
	for _, l := range strings.Split(string(src), "\n") {
		if strings.HasPrefix(l, prefix) {
			return true
		}
	}
	return false
}

// comm23 is `comm -23`: what is in a and not in b, both already sorted.
func comm23(a, b []string) []string {
	in := map[string]bool{}
	for _, v := range b {
		in[v] = true
	}
	var out []string
	for _, v := range a {
		if !in[v] {
			out = append(out, v)
		}
	}
	return out
}

func contains(ss []string, v string) bool {
	for _, s := range ss {
		if s == v {
			return true
		}
	}
	return false
}

// diffLines is `diff a b` reduced to the `<` and `>` lines the checks print.
// It is a plain set difference in file order, not an LCS: every caller here is
// reporting "these went and those arrived" about two sorted symbol lists or two
// recordings, and the shape of the edit script is not what they say.
func diffLines(a, b string) []string {
	as, bs := strings.Split(a, "\n"), strings.Split(b, "\n")
	inB := map[string]bool{}
	for _, l := range bs {
		inB[l] = true
	}
	inA := map[string]bool{}
	for _, l := range as {
		inA[l] = true
	}
	var out []string
	for _, l := range as {
		if l != "" && !inB[l] {
			out = append(out, "< "+l)
		}
	}
	for _, l := range bs {
		if l != "" && !inA[l] {
			out = append(out, "> "+l)
		}
	}
	return out
}

// cutilRepr is Python's %r of a short string, for a refusal message that
// quotes a needle.
func cutilRepr(s string) string { return "'" + s + "'" }
