package cutil

import (
	"bytes"
	"fmt"
	"regexp"
	"strings"
)

// PyRepr renders a plain string the way Python's %r does: single quotes, with
// a backslash and a single quote escaped.  Go's %q would print DOUBLE quotes,
// and these strings land in refusal messages that are compared against the
// Python's byte for byte.
func PyRepr(v string) string {
	v = strings.ReplaceAll(v, `\`, `\\`)
	v = strings.ReplaceAll(v, `'`, `\'`)
	return "'" + v + "'"
}

// pyPattern is PyRepr for a pattern, and drops a leading (?m).
//
// Go needs the multiline flag INSIDE the pattern where Python passes re.M as
// an argument, so the two spell the same regex differently -- and both
// implementations echo the pattern in their refusal.  Without this the
// messages would differ on every refusal while the behaviour was identical,
// which is a difference in the harness rather than in the tool.
func pyPattern(p string) string {
	return PyRepr(strings.TrimPrefix(p, "(?m)"))
}

// DropIf deletes an `if (...)` and the block it guards, BY MATCHING BRACES.
//
// Every phase tool that needed this wrote its own, and four of them wrote the
// same bug: a lazy `(?:[^\n]*\n)*?\}` to find the end of the block.  That
// stops at the FIRST line which is only a brace, which is an inner block's
// whenever there is one -- so the cut takes the header and half the body and
// leaves the rest at file scope.  gcc then reports it hundreds of lines away
// as "expected identifier before 'else'", or a duplicate case value in an
// unrelated function.  It kept coming back because the helper lived in
// whichever tool met it last.
//
// It refuses a block followed by `else`, because deleting the `if` alone would
// orphan it and change which branch runs.
func DropIf(s []byte, pattern string, count int) ([]byte, error) {
	re, err := regexp.Compile(pattern)
	if err != nil {
		return nil, err
	}
	for i := 0; i < count; i++ {
		b := Blank(s)
		m := re.FindIndex(s)
		if m == nil {
			return nil, fmt.Errorf("drop_if: no match for %s", pyPattern(pattern))
		}
		lp := m[0] + bytes.IndexByte(s[m[0]:], '(')
		rp := Match(b, lp)
		if rp < 0 {
			return nil, fmt.Errorf("drop_if: unbalanced condition")
		}
		j := rp + 1
		for j < len(s) && (s[j] == ' ' || s[j] == '\t' || s[j] == '\n') {
			j++
		}
		if j >= len(s) || s[j] != '{' {
			return nil, fmt.Errorf("drop_if: the condition does not open a block")
		}
		closeAt := Match(b, j)
		if closeAt < 0 {
			return nil, fmt.Errorf("drop_if: unbalanced block")
		}
		tail := s[closeAt+1:]
		if len(tail) > 40 {
			tail = tail[:40]
		}
		if regexp.MustCompile(`^[ \t]*\n[ \t]*else\b`).Match(tail) {
			return nil, fmt.Errorf("drop_if: block has an else; deleting the if alone " +
				"would orphan it")
		}
		end := closeAt + 1
		for end < len(s) && (s[end] == ' ' || s[end] == '\t') {
			end++
		}
		if end < len(s) && s[end] == '\n' {
			end++
		}
		if end < len(s) && s[end] == '\n' {
			end++
		}
		out := make([]byte, 0, len(s))
		out = append(out, s[:m[0]]...)
		out = append(out, s[end:]...)
		s = out
	}
	return s, nil
}

// Dedent4 strips one four-space level, line by line.
func Dedent4(body []byte) []byte {
	var out []byte
	for _, line := range splitKeepEnds(body) {
		if bytes.HasPrefix(line, []byte("    ")) {
			out = append(out, line[4:]...)
		} else {
			out = append(out, line...)
		}
	}
	return out
}

func splitKeepEnds(b []byte) [][]byte {
	var out [][]byte
	start := 0
	for i := 0; i < len(b); i++ {
		if b[i] == '\n' {
			out = append(out, b[start:i+1])
			start = i + 1
		}
	}
	if start < len(b) {
		out = append(out, b[start:])
	}
	return out
}

// guarded returns the line start, the opening brace, the closing brace, and
// the head text of the block the `if` at m guards.
// Guarded is exported for the cutters that walk an if-chain themselves.
func Guarded(s, b []byte, m []int) (k, o, c int, head string, err error) {
	k = bytes.LastIndexByte(s[:m[0]], '\n') + 1
	lp := m[0] + bytes.IndexByte(s[m[0]:], '(')
	rp := Match(b, lp)
	if rp < 0 {
		return 0, 0, 0, "", fmt.Errorf("unbalanced condition")
	}
	o = rp + 1
	for o < len(s) && (s[o] == ' ' || s[o] == '\t' || s[o] == '\n') {
		o++
	}
	if o >= len(s) || s[o] != '{' {
		return 0, 0, 0, "", fmt.Errorf("the condition does not open a block")
	}
	c = Match(b, o)
	if c < 0 {
		return 0, 0, 0, "", fmt.Errorf("unbalanced block")
	}
	return k, o, c, strings.TrimSpace(string(s[k:lp])), nil
}

// fold is the counted driver: A FOLD THAT IS NOT COUNTED IS A GUESS.  A fold
// applied to "the first one" of several is the cut that took the wrong block.
func fold(s []byte, pattern string, count int, what string,
	one func(s, b []byte, m []int) ([]byte, error)) ([]byte, error) {

	re, err := regexp.Compile(pattern)
	if err != nil {
		return nil, err
	}
	n := len(re.FindAllIndex(s, -1))
	if n != count {
		return nil, fmt.Errorf("%s: %s matches %d times, expected %d -- a fold that is "+
			"not counted is a guess", what, pyPattern(pattern), n, count)
	}
	for i := 0; i < count; i++ {
		b := Blank(s)
		m := re.FindIndex(s)
		if m == nil {
			return nil, fmt.Errorf("%s: the match vanished between passes", what)
		}
		s, err = one(s, b, m)
		if err != nil {
			return nil, err
		}
	}
	return s, nil
}

// FoldAlways folds an `if` whose condition is now always true: keep the body,
// lose the test.  Only a plain `if` with no `else`, which is the only shape
// that has needed it.
func FoldAlways(s []byte, pattern string, count int) ([]byte, error) {
	return fold(s, pattern, count, "fold_always",
		func(s, b []byte, m []int) ([]byte, error) {
			k, o, c, head, err := Guarded(s, b, m)
			if err != nil {
				return nil, err
			}
			if head != "if" {
				return nil, fmt.Errorf("fold_always: only a plain if, not %s", PyRepr(head))
			}
			end := c + bytes.IndexByte(s[c:], '\n') + 1
			if regexp.MustCompile(`^[ \t]*else\b`).Match(s[end:]) {
				return nil, fmt.Errorf("fold_always: the block has an else")
			}
			bodyStart := o + bytes.IndexByte(s[o:], '\n') + 1
			bodyEnd := bytes.LastIndexByte(s[:c], '\n') + 1
			body := Dedent4(s[bodyStart:bodyEnd])
			out := make([]byte, 0, len(s))
			out = append(out, s[:k]...)
			out = append(out, body...)
			out = append(out, s[end:]...)
			return out, nil
		})
}

var elseHead = regexp.MustCompile(`^([ \t]*)else\b([ \t]+if\b)?`)

// FoldNever folds an `if` whose condition is now always false: lose it, keep
// what it chose between.  Every shape of chain, because the condition can sit
// anywhere in one:
//
//	if (F) { A }                     -> nothing
//	if (F) { A } else { C }          -> C
//	if (F) { A } else if (X) { B }   -> if (X) { B }
//	... else if (F) { A } ...        -> ... ...
func FoldNever(s []byte, pattern string, count int) ([]byte, error) {
	tidy := func(before, after []byte) []byte {
		if bytes.HasSuffix(before, []byte("\n\n")) && bytes.HasPrefix(after, []byte("\n")) {
			after = after[1:]
		}
		out := make([]byte, 0, len(before)+len(after))
		out = append(out, before...)
		return append(out, after...)
	}
	return fold(s, pattern, count, "fold_never",
		func(s, b []byte, m []int) ([]byte, error) {
			k, o, c, head, err := Guarded(s, b, m)
			if err != nil {
				return nil, err
			}
			_ = o
			end := c + bytes.IndexByte(s[c:], '\n') + 1
			rest := s[end:]
			if head == "else if" {
				out := make([]byte, 0, len(s))
				out = append(out, s[:k]...)
				return append(out, rest...), nil
			}
			if head != "if" {
				return nil, fmt.Errorf("fold_never: not an if: %s", PyRepr(head))
			}
			nxt := elseHead.FindSubmatchIndex(rest)
			if nxt == nil {
				return tidy(s[:k], rest), nil
			}
			if nxt[4] >= 0 { // `else if`
				out := make([]byte, 0, len(s))
				out = append(out, s[:k]...)
				out = append(out, rest[nxt[2]:nxt[3]]...)
				out = append(out, "if"...)
				return append(out, rest[nxt[1]:]...), nil
			}
			o2 := end + nxt[1] + bytes.IndexByte(b[end+nxt[1]:], '{')
			c2 := Match(b, o2)
			if c2 < 0 {
				return nil, fmt.Errorf("fold_never: the else block is unbalanced")
			}
			bodyStart := o2 + bytes.IndexByte(s[o2:], '\n') + 1
			bodyEnd := bytes.LastIndexByte(s[:c2], '\n') + 1
			body := Dedent4(s[bodyStart:bodyEnd])
			after := c2 + bytes.IndexByte(s[c2:], '\n') + 1
			out := make([]byte, 0, len(s))
			out = append(out, s[:k]...)
			out = append(out, body...)
			return append(out, s[after:]...), nil
		})
}
