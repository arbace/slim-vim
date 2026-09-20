package canon

import (
	"bytes"

	"slimvim.local/tools/internal/cutil"
)

// labelHead is `^\s*(case\b|default\b|[A-Za-z_]\w*\s*:)`.
func labelHead(s []byte) bool {
	i := len(indentOf(s))
	rest := s[i:]
	if startsWithWord(rest, "case") || startsWithWord(rest, "default") {
		return true
	}
	// An identifier, optional whitespace, then a colon.
	j := 0
	if j < len(rest) && (rest[j] == '_' || isAlpha(rest[j])) {
		j++
		for j < len(rest) && isWord(rest[j]) {
			j++
		}
		for j < len(rest) && isSpace(rest[j]) {
			j++
		}
		return j < len(rest) && rest[j] == ':'
	}
	return false
}

func isAlpha(c byte) bool {
	return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}

// splitLine is onestmt.py's split_line: one statement per line, splitting on
// TOP-LEVEL semicolons only.  A `for (a; b; c)` header keeps its semicolons
// because they are inside parens, and an initialiser table keeps its rows
// because the split is on ';' and not ','.  A label goes on its own line.
func splitLine(line []byte) [][]byte {
	s := rtrim(line)
	st := trim(s)
	if len(st) == 0 || st[0] == '#' || bytes.HasPrefix(st, []byte("//")) {
		return [][]byte{line}
	}
	indent := indentOf(s)
	b := cutil.Blank(s)
	d := cutil.Depths(b)
	var out [][]byte

	// The label's colon is found in the BLANKED text: `case ':':` has two
	// colons inside a character constant, and splitting on the first of those
	// produces `case ':` and a syntax error.
	if labelHead(s) {
		colon := -1
		for j := 0; j < len(b); j++ {
			if b[j] != ':' || d[j] != 0 {
				continue
			}
			// Skip either half of a `::`.  The Python tests this twice, once
			// as b[j:j+2] == '::' and once as b[j+1:j+2] == ':'; they are the
			// same condition, so it is written once here.
			if (j > 0 && b[j-1] == ':') || (j+1 < len(b) && b[j+1] == ':') {
				continue
			}
			colon = j
			break
		}
		if colon >= 0 && len(trim(s[colon+1:])) > 0 {
			out = append(out, concat(indent, trim(s[:colon+1])))
			indent = concat(indent, []byte("    "))
			s = concat(indent, trim(s[colon+1:]))
			b = cutil.Blank(s)
			d = cutil.Depths(b)
		}
	}

	var pieces [][]byte
	start := 0
	for j := 0; j < len(b); j++ {
		if b[j] == ';' && d[j] == 0 {
			pieces = append(pieces, s[start:j+1])
			start = j + 1
		}
	}
	if tail := s[start:]; len(trim(tail)) > 0 {
		pieces = append(pieces, tail)
	}
	if len(pieces) <= 1 && len(out) == 0 {
		return [][]byte{line}
	}
	for _, p := range pieces {
		if t := trim(p); len(t) > 0 {
			out = append(out, concat(indent, t))
		}
	}
	if len(out) == 0 {
		return [][]byte{line}
	}
	return out
}

func concat(a, b []byte) []byte {
	out := make([]byte, 0, len(a)+len(b))
	out = append(out, a...)
	return append(out, b...)
}

// OneStmt puts one statement on each line.
//
// On whim and zero it splits nothing, measured over 150 inputs including 53
// real phase-edit outputs; on slim's sources it splits thousands.  Note the
// counter: a line that becomes three lines counts ONCE, because the Python
// counts lines that changed and not pieces produced.
func OneStmt(src []byte) (out []byte, changed, nIn, nOut int) {
	lines := split(src)
	nIn = len(lines)
	kept := make([][]byte, 0, len(lines))
	for _, line := range lines {
		got := splitLine(line)
		if len(got) > 1 {
			changed++
		}
		kept = append(kept, got...)
	}
	nOut = len(kept)
	return joinWithFinalNewline(kept), changed, nIn, nOut
}
