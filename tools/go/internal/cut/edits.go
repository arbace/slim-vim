package cut

import (
	"bytes"
	"fmt"
	"io"
	"regexp"

	"slimvim.local/tools/internal/cutil"
)

// ed is the shape most cutters share: a tool name, a writer, and four counted
// edits that refuse in that tool's words.
//
// The report column is the same in every tool -- two spaces, the name padded
// to thirteen -- so it is written once here rather than per message.
type ed struct {
	tool string
	w    io.Writer
}

func (e ed) say(what string) { fmt.Fprintf(e.w, "  %-13s%s\n", e.tool, what) }

// literal replaces exact text, counted.
func (e ed) literal(seg []byte, old, new, what string, count int) ([]byte, error) {
	n := bytes.Count(seg, []byte(old))
	if n != count {
		return nil, fmt.Errorf("%s: %s -- occurs %d times, expected %d",
			e.tool, what, n, count)
	}
	e.say(what)
	return bytes.ReplaceAll(seg, []byte(old), []byte(new)), nil
}

// subOnce deletes a pattern that must match exactly once.
func (e ed) subOnce(seg []byte, pattern, what string) ([]byte, error) {
	re := regexp.MustCompile("(?m)" + pattern)
	n := len(re.FindAll(seg, -1))
	if n != 1 {
		return nil, fmt.Errorf("%s: %s -- matched %d times, expected 1", e.tool, what, n)
	}
	e.say(what)
	return re.ReplaceAll(seg, nil), nil
}

// foldNever folds a condition that is now always false.
func (e ed) foldNever(seg []byte, pattern, what string) ([]byte, error) {
	out, err := cutil.FoldNever(seg, "(?m)"+pattern, 1)
	if err != nil {
		return nil, fmt.Errorf("%s: %s -- %v", e.tool, what, err)
	}
	e.say(what)
	return out, nil
}

// inFunction applies an edit to ONE function's text and splices it back, so a
// pattern that would match elsewhere in the file cannot.
func (e ed) inFunction(text []byte, name string, edit func([]byte) ([]byte, error)) ([]byte, error) {
	a, z, ok := cutil.FindDefinition(text, cutil.Blank(text), name)
	if !ok {
		return nil, fmt.Errorf("%s: %s is not defined at file scope", e.tool, name)
	}
	seg, err := edit(text[a:z])
	if err != nil {
		return nil, err
	}
	out := make([]byte, 0, len(text))
	out = append(out, text[:a]...)
	out = append(out, seg...)
	return append(out, text[z:]...), nil
}

// linesMatchingUnless is RE2's answer to a negative lookahead at line start.
//
// Go's regexp has no lookahead of either sign, by design, so a Python pattern
// like `^(?![ \t]*\[?CMD_)[^\n]*\bCMD_x\b` cannot be transcribed.  What it
// means is "a line that names CMD_x and is not itself a table row", and that
// is two tests over the lines rather than one pattern.
func linesMatchingUnless(text []byte, want, unless *regexp.Regexp) []string {
	var out []string
	for _, line := range bytes.Split(text, []byte{'\n'}) {
		if want.Match(line) && !unless.Match(line) {
			out = append(out, string(line))
		}
	}
	return out
}
