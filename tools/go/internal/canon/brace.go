package canon

import (
	"bytes"

	"slimvim.local/tools/internal/cutil"
)

// isSkippable is brace.py's: blank, a directive, or a // comment.  A body is
// none of those, so the scan steps over them to find the statement a head
// governs -- `if (x)` followed by `#ifdef` followed by `y();` governs y().
func isSkippable(line []byte) bool {
	s := trim(line)
	return len(s) == 0 || s[0] == '#' || bytes.HasPrefix(s, []byte("//"))
}

func nextCode(lines [][]byte, i int) int {
	for i < len(lines) && isSkippable(lines[i]) {
		i++
	}
	return i
}

// skipCloseBrace consumes an optional `}` and the whitespace after it, which
// is the `(?:\}\s*)?` several of brace.py's patterns open with.
func skipCloseBrace(s []byte) []byte {
	if len(s) > 0 && s[0] == '}' {
		s = s[1:]
		for len(s) > 0 && isSpace(s[0]) {
			s = s[1:]
		}
	}
	return s
}

// wordThenParen matches one of the keywords, optional space, then '(' .
func wordThenParen(s []byte, kws ...string) (string, bool) {
	for _, kw := range kws {
		if !bytes.HasPrefix(s, []byte(kw)) {
			continue
		}
		r := s[len(kw):]
		if len(r) > 0 && isWord(r[0]) {
			continue
		}
		for len(r) > 0 && isSpace(r[0]) {
			r = r[1:]
		}
		if len(r) > 0 && r[0] == '(' {
			return kw, true
		}
	}
	return "", false
}

// onlyWord matches `^(\s*)kw\s*$`.
func onlyWord(s []byte, kw string) bool {
	r := ltrim(s)
	if !bytes.HasPrefix(r, []byte(kw)) {
		return false
	}
	return len(trim(r[len(kw):])) == 0
}

// elseIfHead matches `^(\s*)else\s+if\s*\(` -- note the REQUIRED whitespace
// between else and if, which is why it is not wordThenParen("else", "if").
func elseIfHead(s []byte) bool {
	r := ltrim(s)
	if !bytes.HasPrefix(r, []byte("else")) {
		return false
	}
	r = r[len("else"):]
	if len(r) == 0 || !isSpace(r[0]) {
		return false
	}
	r = ltrim(r)
	_, ok := wordThenParen(r, "if")
	return ok
}

// startsWithCloseThenWord matches `^\s*(\}\s*)?kw\b`.
func startsWithCloseThenWord(s []byte, kw string) bool {
	return startsWithWord(skipCloseBrace(ltrim(s)), kw)
}

type head struct {
	indent []byte
	kind   string // "do", "else", "if" or "loop"
}

// headOf returns the head this line is, or ok=false.
//
// A `while` that terminates a do-while is not a head.  Usually it says so by
// ending in ';', but it can also be written with the semicolon on a line of
// its own, and then it cannot be told from a real while-head by looking at the
// line alone.  Those are found in a first pass and passed in as doTerms.
func headOf(line []byte, index int, doTerms map[int]bool) (head, bool) {
	s := rtrim(line)
	if isSkippable(s) {
		return head{}, false
	}
	if index >= 0 && doTerms[index] {
		return head{}, false
	}
	if bytes.HasSuffix(trim(s), []byte(";")) {
		return head{}, false // `while (cond);` closing a do
	}
	indent := indentOf(s)
	if onlyWord(s, "do") {
		return head{indent, "do"}, true
	}
	if onlyWord(s, "else") {
		return head{indent, "else"}, true
	}
	if elseIfHead(s) && bytes.HasSuffix(s, []byte(")")) {
		return head{indent, "if"}, true
	}
	if kw, ok := wordThenParen(skipCloseBrace(ltrim(s)), "if", "for", "while", "switch"); ok &&
		bytes.HasSuffix(s, []byte(")")) {
		// Only an `if` may swallow a following `else`.  A for/while/switch
		// that happens to be an if's body must not: doing so would put the
		// closing brace on the far side of the else and move the else's body
		// inside the loop.
		if kw == "if" {
			return head{indent, "if"}, true
		}
		return head{indent, "loop"}, true
	}
	return head{}, false
}

// stmtEnd returns the index of the last line of the statement starting at i.
func stmtEnd(lines [][]byte, i int, doTerms map[int]bool) int {
	i = nextCode(lines, i)
	if i >= len(lines) {
		return i
	}
	if h, ok := headOf(lines[i], i, doTerms); ok {
		j := nextCode(lines, i+1)
		e := stmtEnd(lines, j, doTerms)
		switch h.kind {
		case "do":
			k := nextCode(lines, e+1)
			if k < len(lines) && startsWithCloseThenWord(lines[k], "while") {
				// The do-while ends at its semicolon, which is not always on
				// the same line as the `while`.
				for k < len(lines) && !bytes.HasSuffix(rtrim(lines[k]), []byte(";")) {
					k++
				}
				return k
			}
			return e
		case "if":
			k := nextCode(lines, e+1)
			if k < len(lines) && startsWithCloseThenWord(lines[k], "else") {
				return stmtEnd(lines, k, doTerms)
			}
		}
		return e
	}

	// A plain statement, or a brace block.  The end is "brace depth back to
	// zero and the line ends in ';'", not "the next ';'", because a statement
	// can span lines when it contains an initialiser list.
	depth := 0
	started := false
	for j := i; j < len(lines); j++ {
		if isSkippable(lines[j]) {
			continue
		}
		b := cutil.Blank(lines[j])
		depth += bytes.Count(b, []byte("{")) - bytes.Count(b, []byte("}"))
		if bytes.IndexByte(b, '{') >= 0 {
			started = true
		}
		s := rtrim(lines[j])
		if depth <= 0 && (bytes.HasSuffix(s, []byte(";")) ||
			(started && bytes.HasSuffix(s, []byte("}")))) {
			return j
		}
		if depth <= 0 && bytes.HasSuffix(s, []byte(":")) {
			return j
		}
	}
	return len(lines) - 1
}

// Brace gives every if/else/for/while/do body a brace block.
//
// The point is not style.  Everything after this needs to know where a body
// begins and ends: make it syntactic and the tools stop parsing C, leave it
// implicit and every later pass is a fresh chance to get an extent wrong.
//
// It runs after JoinParens and SplitHeads, so a head is a whole line ending in
// ')' -- or the word `else` or `do` -- and a body starts on the next line.
//
// It returns the do-terminating count as well, because brace.py prints TWO
// lines where every other tool prints one, and tools/sweep.sh reads only the
// last.  Both are printed here: matching a drop-in means matching what it
// writes, not only what its caller happens to read.
func Brace(src []byte) (out []byte, doTermCount, braced, nIn, nOut int) {
	lines := split(src)
	nIn = len(lines)

	// The do-terminating `while` lines, to a fixpoint: identifying one can
	// change the extent of an enclosing statement, which can reveal another.
	doTerms := map[int]bool{}
	for round := 0; round < 5; round++ {
		found := map[int]bool{}
		for i, line := range lines {
			h, ok := headOf(line, i, doTerms)
			if !ok || h.kind != "do" {
				continue
			}
			j := nextCode(lines, i+1)
			e := stmtEnd(lines, j, doTerms)
			k := nextCode(lines, e+1)
			if k < len(lines) && startsWithCloseThenWord(lines[k], "while") {
				found[k] = true
			}
		}
		if sameSet(found, doTerms) {
			break
		}
		for k := range found {
			doTerms[k] = true
		}
	}
	doTermCount = len(doTerms)

	opens := map[int][][]byte{}
	closes := map[int][][]byte{}
	for i, line := range lines {
		h, ok := headOf(line, i, doTerms)
		if !ok {
			continue
		}
		j := nextCode(lines, i+1)
		if j >= len(lines) {
			continue
		}
		if bytes.HasPrefix(trim(lines[j]), []byte("{")) {
			continue
		}
		e := stmtEnd(lines, j, doTerms)
		opens[i] = append(opens[i], h.indent)
		closes[e] = append(closes[e], h.indent)
		braced++
	}

	kept := make([][]byte, 0, len(lines)+2*braced)
	for i, line := range lines {
		kept = append(kept, line)
		for _, indent := range opens[i] {
			kept = append(kept, concat(indent, []byte("{")))
		}
		// A close for line e and an open for line e cannot both be right; the
		// opens are emitted first, which is the order they nest in.
		cl := closes[i]
		for k := len(cl) - 1; k >= 0; k-- {
			kept = append(kept, concat(cl[k], []byte("}")))
		}
	}

	nOut = len(kept)
	return joinWithFinalNewline(kept), doTermCount, braced, nIn, nOut
}

func sameSet(a, b map[int]bool) bool {
	if len(a) != len(b) {
		return false
	}
	for k := range a {
		if !b[k] {
			return false
		}
	}
	return true
}
