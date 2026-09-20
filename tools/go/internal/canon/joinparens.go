package canon

import (
	"bytes"

	"slimvim.local/tools/internal/cutil"
)

// parenBalance counts unclosed ( and [ on one line, ignoring what is inside a
// literal or a comment.
//
// The line is blanked ON ITS OWN, not as part of the whole file, which is what
// the Python does and what makes this a line-local question.  Braces are NOT
// counted, deliberately: a line ending in a comma inside braces is a table row
// rather than a wrapped argument list, and counting them would put a
// 600-entry table on one line.
func parenBalance(line []byte) int {
	b := cutil.Blank(line)
	return bytes.Count(b, []byte("(")) - bytes.Count(b, []byte(")")) +
		bytes.Count(b, []byte("[")) - bytes.Count(b, []byte("]"))
}

// JoinParens joins every parenthesised group onto one line -- the conditions
// of if/while/for/switch and the argument lists of calls, declarations and
// definitions -- and reports how many lines it pulled up and the line count
// before and after.
//
// One linear scan.  Find-one-fix-it-rescan is quadratic and does not finish on
// a file this size: carry the current line, pull in following lines while its
// parens are unbalanced, and re-examine the joined line.
//
// On whim and zero this joins nothing at all, measured over 97 inputs
// including 25 real phase-edit outputs -- the invariant slim phase 7
// establishes still holds, and the loop below is never entered.  It is ported
// whole anyway because it is thirty lines, and a tool that can only check an
// invariant cannot restore it.
func JoinParens(src []byte) (out []byte, joined, nIn, nOut int) {
	lines := split(src)
	nIn = len(lines)
	kept := make([][]byte, 0, len(lines))

	for i := 0; i < len(lines); {
		cur := lines[i]
		i++
		if hasPrefixAfterSpace(cur, "#") || hasPrefixAfterSpace(cur, "//") {
			kept = append(kept, cur)
			continue
		}
		depth := parenBalance(cur)
		for depth > 0 && i < len(lines) {
			next := lines[i]
			// A group may not be joined ACROSS a directive.  Dead for
			// whim and zero, whose only directive is #include and whose
			// groups do not span lines at all; live for slim, 5,653 times.
			if hasPrefixAfterSpace(next, "#") {
				break
			}
			i++
			joined++
			sep := []byte(" ")
			if bytes.HasSuffix(cur, []byte("(")) || bytes.HasSuffix(cur, []byte("[")) ||
				len(trim(cur)) == 0 {
				sep = nil
			}
			if hasPrefixAfterSpace(next, ")") || hasPrefixAfterSpace(next, ",") {
				sep = nil
			}
			joinedLine := make([]byte, 0, len(cur)+len(sep)+len(next))
			joinedLine = append(joinedLine, rtrim(cur)...)
			joinedLine = append(joinedLine, sep...)
			joinedLine = append(joinedLine, trim(next)...)
			cur = joinedLine
			depth = parenBalance(cur)
		}
		kept = append(kept, cur)
	}

	nOut = len(kept)
	return joinWithFinalNewline(kept), joined, nIn, nOut
}
