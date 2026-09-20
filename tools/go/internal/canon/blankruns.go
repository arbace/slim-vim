// Package canon holds the canonicalisers tools/canon.sh runs, in its order.
//
// Every one of them is a pure text transform over bytes.  That is not a
// simplification of the Python, it is what the Python is: canon.sh runs as the
// seventh member of a sweep round, after six tools have deleted from the text
// and with no compile since the round began, so the text a canonicaliser sees
// need not be valid C and a parser would fail on it.  See tools/sweep.sh.
//
// Bytes, not strings, throughout.  The Python reads and writes with
// errors='surrogateescape', which is a way of carrying bytes that are not
// valid UTF-8 through a str unchanged; operating on []byte is the same thing
// without the round trip.  Measured: slim-vim.c, whim-vim.c and zero-vim.c
// contain no byte >= 0x80 and no tab at all, so the two agree here regardless.
package canon

import "bytes"

var nl = []byte{'\n'}

// blank reports whether a line is whitespace only.
//
// The set is Python's ASCII whitespace -- what str.isspace() answers true for
// -- and not Go's unicode.IsSpace, which differs: 0x1c to 0x1f are whitespace
// to Python and not to Go.  Measured, no product contains one, so this cannot
// change an answer today; it is spelled out so that it cannot start to.
func blank(line []byte) bool {
	for _, c := range line {
		switch c {
		case '\t', '\n', '\v', '\f', '\r', 0x1c, 0x1d, 0x1e, 0x1f, ' ':
		default:
			return false
		}
	}
	return true
}

// BlankRuns collapses every run of more than one blank line to a single empty
// line, and reports what it did: the number of runs collapsed, the number of
// lines dropped, and the line count before and after.
//
// The survivor is written EMPTY rather than kept as it was, because a blank
// line in this tree carries no whitespace.  A run at the very end of the file
// collapses the same way, which is how a file ending in several newlines comes
// back ending in one.
//
// The line count is of '\n'-separated fields, so a file ending in a newline
// counts a final empty field -- exactly Python's text.split('\n').  That field
// is blank, and it is why the counts this prints are one higher than the
// number of lines a reader would say the file has.
func BlankRuns(src []byte) (out []byte, runs, dropped, nIn, nOut int) {
	lines := bytes.Split(src, nl)
	nIn = len(lines)

	kept := make([][]byte, 0, len(lines))
	prevBlank := false
	for _, line := range lines {
		if blank(line) {
			if prevBlank {
				dropped++
				continue
			}
			prevBlank = true
			kept = append(kept, nil)
			continue
		}
		prevBlank = false
		kept = append(kept, line)
	}
	nOut = len(kept)

	// Counted in a second pass over the ORIGINAL lines, because a run is a
	// property of the input: the loop above has already collapsed them.
	for i := 0; i < len(lines); {
		if !blank(lines[i]) {
			i++
			continue
		}
		j := i
		for j < len(lines) && blank(lines[j]) {
			j++
		}
		if j-i > 1 {
			runs++
		}
		i = j
	}

	out = bytes.Join(kept, nl)
	if len(out) == 0 || out[len(out)-1] != '\n' {
		out = append(out, '\n')
	}
	return out, runs, dropped, nIn, nOut
}
