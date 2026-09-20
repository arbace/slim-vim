package cutil

import "bytes"

// SplitTop splits s on top-level occurrences of the literal operator op.
//
// Top level means outside every (), [], {} and outside every literal.  The
// parts are substrings of s and are NOT trimmed, and there is always at least
// one -- a trailing separator yields a final empty part, which callers rely on
// when they take parts[len-1].
//
// b is Blank(s).  It is taken rather than computed because the callers that
// matter already have it, and blanking is the expensive half.
func SplitTop(s, b []byte, op string) [][]byte {
	d := Depths(b)
	var parts [][]byte
	start, i, n, l := 0, 0, len(s), len(op)
	for i <= n-l {
		if d[i] == 0 && bytes.HasPrefix(b[i:], []byte(op)) {
			parts = append(parts, s[start:i])
			i += l
			start = i
			continue
		}
		i++
	}
	return append(parts, s[start:])
}

// FindTop returns the index of the first top-level occurrence of ch, or -1.
func FindTop(s, b []byte, ch byte) int {
	d := Depths(b)
	for i := 0; i < len(s); i++ {
		if d[i] == 0 && b[i] == ch {
			return i
		}
	}
	return -1
}
