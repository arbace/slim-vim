package cutil

// The part of cutil.py the SWEEP does not reach, added as a phase program
// needs it.  The package docstring says these are "left out until something
// needs them"; zero39 needs both.

// RMatch returns the index of the OPENER matching the closer at b[i], or -1 if
// the text is unbalanced.
//
// It is Match read backwards and it exists for one shape: finding the start of
// a struct definition from its `} name;`, where the name is what a phase can
// search for and the opening brace is what it needs.
//
// b is blanked text, for Match's reason -- a brace inside a string literal
// must not count.  A non-closer at i is a caller bug and not an unbalanced
// text, so it panics rather than returning -1, which is Match's rule and
// cutil.py's ValueError.
func RMatch(b []byte, i int) int {
	c := b[i]
	var o byte
	switch c {
	case ')':
		o = '('
	case ']':
		o = '['
	case '}':
		o = '{'
	default:
		panic("cutil.RMatch: not a closer")
	}
	depth := 0
	for i >= 0 {
		switch b[i] {
		case c:
			depth++
		case o:
			depth--
			if depth == 0 {
				return i
			}
		}
		i--
	}
	return -1
}

// CollapseWS collapses runs of whitespace to one space, OUTSIDE literals only.
//
// It walks the real string and copies literals through untouched, and that is
// the whole of why it cannot be done on blanked text: every character inside
// `"a  b"` looks like whitespace there, so deciding from the blanked copy
// would delete literal contents.
//
// Its use is comparing two statements for sameness when only their layout
// differs -- zero39 asks whether a `-` arm and the final `else` arm are the
// same statement before collapsing the chain, and they are written with
// different indentation.
func CollapseWS(s []byte) []byte {
	out := make([]byte, 0, len(s))
	i, n := 0, len(s)
	prevWS := false
	for i < n {
		c := s[i]
		if c == '"' || c == '\'' {
			q := c
			j := i + 1
			for j < n {
				if s[j] == '\\' && j+1 < n {
					j += 2
					continue
				}
				if s[j] == q {
					j++
					break
				}
				j++
			}
			out = append(out, s[i:j]...)
			prevWS = false
			i = j
			continue
		}
		if c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f' || c == '\v' {
			if !prevWS {
				out = append(out, ' ')
			}
			prevWS = true
			i++
			continue
		}
		out = append(out, c)
		prevWS = false
		i++
	}
	return out
}
