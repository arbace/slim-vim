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
