package edit

import (
	"bytes"
	"fmt"
	"io"
	"regexp"

	"slimvim.local/tools/internal/cutil"
)

// ph is the driver every zero edit heredoc writes for itself at the top.
//
// Each of those blocks opens with the same six helpers -- die, say, and some
// subset of in_function, fold_never, fold_always and literal -- around a TAG
// that is the phase's word in the report column.  That is not an idiom worth
// factoring out of the PYTHON, where each copy is eight lines and lives beside
// the edit it serves; it is worth writing once here, because a Go file per
// phase would otherwise repeat it forty-two times.
//
// It is deliberately a near-copy of internal/cut's `ed` rather than a shared
// version of it: `ed` is reached by all 57 cutters, and hoisting it into a
// third package to save this file would edit every one of them to save
// forty lines.  If the two ever need to agree on something, agreeing by
// copy is cheaper here than agreeing by dependency.
//
// THE REPORT COLUMN IS THE PYTHON'S, exactly: `'  %-12s %s'`.  That is two
// spaces, the tag padded to twelve, one space, the message -- which is the
// same fifteen columns `ed` writes as `"  %-13s%s"`, and it is written the
// Python's way here so the two can be compared by eye against the heredoc
// they replace.
//
// ORDER IS OUTPUT.  Every helper prints as it succeeds, so the sequence of
// calls IS the sequence of lines.  A phase log is read by a human comparing
// two phase commits, and grouping edits of the same shape into a loop gives
// byte-identical trees and a differently-ordered report -- measured twice in
// the cutters, on oneoptset and onebuffer.  Follow the heredoc's order even
// where it looks arbitrary.
type ph struct {
	tag string
	w   io.Writer
}

func (p ph) say(what string) { fmt.Fprintf(p.w, "  %-12s %s\n", p.tag, what) }

// die is the heredoc's `die()`: the phase refuses and writes nothing.
func (p ph) die(format string, a ...any) error {
	return fmt.Errorf("  %-12s %s", p.tag, fmt.Sprintf(format, a...))
}

// literal replaces exact text, counted, and refuses on any other count.
//
// The count is the assertion.  These edits run on a tree every earlier phase
// has touched, so an anchor that has stopped matching means the phase is about
// to cut something other than what it was written to cut -- which is worth a
// refusal rather than a silent smaller cut.
func (p ph) literal(text []byte, old, new, what string, n int) ([]byte, error) {
	k := bytes.Count(text, []byte(old))
	if k != n {
		return nil, p.die("%s -- occurs %d times, expected %d", what, k, n)
	}
	p.say(what)
	return bytes.ReplaceAll(text, []byte(old), []byte(new)), nil
}

// inFunction applies an edit to ONE function's text and splices it back, so a
// pattern that would match elsewhere in the file cannot.
func (p ph) inFunction(text []byte, name string, edit func([]byte) ([]byte, error)) ([]byte, error) {
	a, z, ok := cutil.FindDefinition(text, cutil.Blank(text), name)
	if !ok {
		return nil, p.die("%s is not defined", name)
	}
	seg, err := edit(text[a:z])
	if err != nil {
		return nil, err
	}
	out := make([]byte, 0, len(text)-(z-a)+len(seg))
	out = append(out, text[:a]...)
	out = append(out, seg...)
	return append(out, text[z:]...), nil
}

// foldNever folds a condition that can no longer be true, inside one function.
func (p ph) foldNever(text []byte, fn, pattern, what string, n int) ([]byte, error) {
	out, err := p.inFunction(text, fn, func(seg []byte) ([]byte, error) {
		got, err := cutil.FoldNever(seg, "(?m)"+pattern, n)
		if err != nil {
			return nil, p.die("%s -- %v", what, err)
		}
		return got, nil
	})
	if err != nil {
		return nil, err
	}
	p.say(what)
	return out, nil
}

// foldAlways folds a condition that is now always true, inside one function.
func (p ph) foldAlways(text []byte, fn, pattern, what string, n int) ([]byte, error) {
	out, err := p.inFunction(text, fn, func(seg []byte) ([]byte, error) {
		got, err := cutil.FoldAlways(seg, "(?m)"+pattern, n)
		if err != nil {
			return nil, p.die("%s -- %v", what, err)
		}
		return got, nil
	})
	if err != nil {
		return nil, err
	}
	p.say(what)
	return out, nil
}

// count is how the heredocs state an invariant before cutting: a name that
// must appear exactly so many times, asserted rather than trusted from the
// survey, so that an upstream which gave it another reader fails loudly
// instead of letting the phase take a decision that is no longer the one
// written down.
func (p ph) count(text []byte, pattern string, want int, what string) error {
	k := len(regexp.MustCompile(pattern).FindAll(text, -1))
	if k != want {
		return p.die("%s appears %d times, expected %d", what, k, want)
	}
	return nil
}

// gone requires each name to have left the text, which is the last act of
// most of these blocks: the cut is stated as a partition over the vocabulary
// and not as a diff.
func (p ph) gone(text []byte, names ...string) error {
	for _, n := range names {
		if bytes.Contains(text, []byte(n)) {
			return p.die("%s survives the edit", cutil.PyRepr(n))
		}
	}
	return nil
}
