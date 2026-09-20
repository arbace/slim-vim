package canon

import "bytes"

// Python's str.strip() family, spelled out.
//
// These tools are ported against CPython's whitespace, not Go's: str.isspace()
// is true for 0x1c to 0x1f and unicode.IsSpace is not.  No product contains
// one -- measured, all three are pure ASCII with no control byte but TAB and
// LF -- so this cannot change an answer today.  It is written out so that it
// cannot start to, and so that nobody has to re-derive which of the two
// definitions a given line of Python meant.
func isSpace(c byte) bool {
	switch c {
	case '\t', '\n', '\v', '\f', '\r', 0x1c, 0x1d, 0x1e, 0x1f, ' ':
		return true
	}
	return false
}

func ltrim(s []byte) []byte {
	i := 0
	for i < len(s) && isSpace(s[i]) {
		i++
	}
	return s[i:]
}

func rtrim(s []byte) []byte {
	j := len(s)
	for j > 0 && isSpace(s[j-1]) {
		j--
	}
	return s[:j]
}

func trim(s []byte) []byte { return ltrim(rtrim(s)) }

// hasPrefixAfterSpace is `s.lstrip().startswith(p)`.
func hasPrefixAfterSpace(s []byte, p string) bool {
	return bytes.HasPrefix(ltrim(s), []byte(p))
}

// split splits on '\n' exactly as Python's str.split('\n') does, so a text
// ending in a newline yields a final empty field and the counts these tools
// print are of fields rather than of lines a reader would count.
func split(s []byte) [][]byte { return bytes.Split(s, nl) }

// join is '\n'.join(parts), with the trailing newline the tools add when the
// result does not already end in one.  Eight of the thirteen normalise this
// way and five do not, so it is a helper rather than something done centrally.
func joinWithFinalNewline(parts [][]byte) []byte {
	out := bytes.Join(parts, nl)
	if len(out) == 0 || out[len(out)-1] != '\n' {
		out = append(out, '\n')
	}
	return out
}
