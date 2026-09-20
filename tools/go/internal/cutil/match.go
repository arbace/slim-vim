package cutil

// Match returns the index of the closer matching the opener at b[i], or -1 if
// the text is unbalanced.
//
// b is blanked text -- Blank's output -- because the whole point is that a
// parenthesis inside a string literal must not count.  The Python takes the
// original too and indexes only the blanked copy; this takes the one it uses.
//
// A non-opener at i is a caller bug and not an unbalanced text, so it panics
// rather than returning -1, which is what cutil.py's ValueError does.  Telling
// the two apart matters: -1 means "this program's input is not balanced", and
// the callers act on that.
func Match(b []byte, i int) int {
	o := b[i]
	var c byte
	switch o {
	case '(':
		c = ')'
	case '[':
		c = ']'
	case '{':
		c = '}'
	default:
		panic("cutil.Match: not an opener at the given index")
	}
	depth := 0
	for ; i < len(b); i++ {
		switch b[i] {
		case o:
			depth++
		case c:
			depth--
			if depth == 0 {
				return i
			}
		}
	}
	return -1
}
