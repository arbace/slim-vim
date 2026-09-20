package edit

import (
	"bytes"
	"fmt"
	"io"
	"regexp"
	"strings"
)

var (
	blankRun3  = regexp.MustCompile(`\n\n\n+`)
	braceBlank = regexp.MustCompile(`\{\n\n`)
)

// commentSpans returns the start and end of every comment, found by a SCANNER
// THAT KNOWS STRING AND CHARACTER LITERALS -- a `//` inside "pack/*/start/*" or
// "://" is not one.  CLAUDE.md records 295 such occurrences on 16 lines of the
// product, every one inside a literal, which is why this cannot be a regex.
func commentSpans(s []byte) [][2]int {
	var out [][2]int
	i, n := 0, len(s)
	for i < n {
		c := s[i]
		switch {
		case c == '"' || c == '\'':
			i++
			for i < n && s[i] != c {
				if s[i] == '\\' {
					i += 2
				} else {
					i++
				}
			}
			i++
		case bytes.HasPrefix(s[i:], []byte("//")):
			j := bytes.IndexByte(s[i:], '\n')
			if j < 0 {
				out = append(out, [2]int{i, n})
				i = n
			} else {
				out = append(out, [2]int{i, i + j})
				i += j
			}
		case bytes.HasPrefix(s[i:], []byte("/*")):
			j := bytes.Index(s[i+2:], []byte("*/"))
			if j < 0 {
				out = append(out, [2]int{i, n})
				i = n
			} else {
				out = append(out, [2]int{i, i + 2 + j + 2})
				i += 2 + j + 2
			}
		default:
			i++
		}
	}
	return out
}

// Whim82 strips every comment, and asserts the paragraphing it must not change.
//
// THE BLANK-LINE ASSERTIONS ARE THE POINT.  A comment on a line of its own
// becomes nothing, and two such lines either side of a blank one would leave a
// run of three newlines where there was one -- which no verification tier can
// see, since blank lines change neither the binary nor the token stream.  So
// the runs are counted before and after, and a brace followed by a blank line
// is collapsed ONLY if there were none to begin with.
func Whim82(text []byte, w io.Writer) ([]byte, error) {
	found := commentSpans(text)
	for _, s := range found {
		if bytes.HasPrefix(text[s[0]:s[1]], []byte("/*")) {
			return nil, fmt.Errorf("  %-12s a block comment -- this program only knows line comments", "nocomments")
		}
	}
	runsBefore := len(regexp.MustCompile(`\n\n\n`).FindAll(text, -1))
	afterBraceBefore := len(braceBlank.FindAll(text, -1))

	lines := strings.Split(string(text), "\n")
	starts := map[int]int{}
	for _, s := range found {
		ln := bytes.Count(text[:s[0]], []byte("\n"))
		col := s[0] - (bytes.LastIndex(text[:s[0]], []byte("\n")) + 1)
		starts[ln] = col
	}
	var out []string
	gone, trimmed := 0, 0
	for ln, line := range lines {
		if col, ok := starts[ln]; ok {
			code := strings.TrimRight(line[:col], " \t\r\n\v\f")
			if code == "" {
				gone++
				continue
			}
			out = append(out, code)
			trimmed++
			continue
		}
		out = append(out, line)
	}
	t := []byte(strings.Join(out, "\n"))
	t = bytes.TrimLeft(t, "\n")
	t = blankRun3.ReplaceAll(t, []byte("\n\n"))
	if afterBraceBefore == 0 {
		t = braceBlank.ReplaceAll(t, []byte("{\n"))
	}
	if n := len(commentSpans(t)); n > 0 {
		return nil, fmt.Errorf("  %-12s %d comments survive", "nocomments", n)
	}
	if len(regexp.MustCompile(`\n\n\n`).FindAll(t, -1)) > runsBefore {
		return nil, fmt.Errorf("  %-12s stripping made a run of blank lines", "nocomments")
	}
	fmt.Fprintf(w, "  %-12s %d comment lines deleted, %d comments cut from the end of a line\n",
		"nocomments", gone, trimmed)
	return t, nil
}

func init() { register("whim82", Whim82) }
