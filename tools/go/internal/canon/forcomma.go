package canon

import (
	"bytes"
	"regexp"

	"slimvim.local/tools/internal/cutil"
)

// typeWord is forcomma.py's TYPEWORD.  Unlike onedecl.py's KEYWORD_START, this
// alternation is NOT subsumed by a catch-all -- it really is a fixed list of
// type keywords, and it means what it says.
var typeWord = regexp.MustCompile(`^(static|const|volatile|unsigned|signed|struct|union|enum|register|auto|extern|short|long|int|char|float|double|void)\b`)

// forHead matches `^(\s*)for\s*\(` and returns the offset of that '(' , or -1.
func forHead(line []byte) int {
	end := keywordHead(line, "for")
	if end < 0 {
		return -1
	}
	j := end
	for j < len(line) && isSpace(line[j]) {
		j++
	}
	if j < len(line) && line[j] == '(' {
		return j
	}
	return -1
}

// initClause returns the open paren, its closer, and the half-open range of
// the init clause of the `for` head on line, or ok=false.
func initClause(line []byte) (open, closeI, a, z int, ok bool) {
	o := forHead(line)
	if o < 0 {
		return 0, 0, 0, 0, false
	}
	b := cutil.Blank(line)
	c := cutil.Match(b, o)
	if c < 0 {
		return 0, 0, 0, 0, false
	}
	inner := line[o+1 : c]
	ib := cutil.Blank(inner)
	d := cutil.Depths(ib)
	semi := -1
	for j := 0; j < len(ib); j++ {
		if ib[j] == ';' && d[j] == 0 {
			semi = j
			break
		}
	}
	if semi < 0 {
		return 0, 0, 0, 0, false
	}
	return o, c, o + 1, o + 1 + semi, true
}

// hoist rewrites a `for` head whose init clause holds a comma operator,
// returning the replacement lines, or nil when it declines.
//
// It declines two ways, and both are refusals rather than failures: an init
// clause that DECLARES -- `for (int i = n, j = m; ...)` scopes i and j to the
// loop, and hoisting would widen that to the enclosing block, which is a
// change in meaning and not in formatting -- and an init clause containing a
// call or a cast, which is what a '(' inside it means here.
//
// Measured, it declines every one it finds on whim and zero: 132 init clauses
// with a top-level comma across the boundary corpus, 0 hoisted.
func hoist(line []byte) [][]byte {
	_, _, a, z, ok := initClause(line)
	if !ok {
		return nil
	}
	init := line[a:z]
	if len(trim(init)) == 0 {
		return nil
	}
	ib := cutil.Blank(init)
	parts := cutil.SplitTop(init, ib, ",")
	if len(parts) < 2 {
		return nil
	}
	if bytes.IndexByte(ib, '(') >= 0 {
		return nil // a call or a cast: decline
	}
	head := trim(parts[0])
	hb := cutil.Blank(head)
	eq := cutil.FindTop(head, hb, '=')
	core := head
	if eq >= 0 {
		core = head[:eq]
	}
	if typeWord.Match(trim(core)) || len(ident.FindAllIndex(core, -1)) > 1 {
		return nil // declares: hoisting would widen scope
	}

	indent := indentOf(line)
	var out [][]byte
	for _, p := range parts[:len(parts)-1] {
		stmt := concat(indent, trim(p))
		out = append(out, append(stmt, ';'))
	}
	last := make([]byte, 0, len(line))
	last = append(last, line[:a]...)
	last = append(last, trim(parts[len(parts)-1])...)
	last = append(last, line[z:]...)
	return append(out, last)
}

// ForComma hoists comma operators out of `for` init clauses, so that
// `for (n1 = 0, n2 = 0; ...)` becomes `n1 = 0;` on its own line and
// `for (n2 = 0; ...)`.  Every initialiser but the last is hoisted; the last
// stays so the head keeps an init clause.
//
// Safe only after bracing: every body is a brace block, so a statement
// inserted before the `for` lands inside the same block the `for` is in.
// Increment clauses are left alone -- they run on `continue` too.
//
// check suppresses the write, which is forcomma.py's --check.  Nothing in
// tools/ or pipes/ passes it; it is kept so the CLI is a drop-in.
func ForComma(src []byte, check bool) (out []byte, found, hoisted, declined, nIn, nOut int) {
	lines := split(src)
	nIn = len(lines)
	kept := make([][]byte, 0, len(lines))
	for _, line := range lines {
		if _, _, a, z, ok := initClause(line); ok {
			init := line[a:z]
			if len(cutil.SplitTop(init, cutil.Blank(init), ",")) > 1 {
				if got := hoist(line); got == nil {
					declined++
				} else {
					hoisted++
					if !check {
						kept = append(kept, got...)
						continue
					}
				}
			}
		}
		kept = append(kept, line)
	}
	nOut = len(kept)
	return joinWithFinalNewline(kept), hoisted + declined, hoisted, declined, nIn, nOut
}
