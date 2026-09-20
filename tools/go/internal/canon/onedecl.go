package canon

import (
	"bytes"
	"regexp"

	"slimvim.local/tools/internal/cutil"
)

// declarator is onedecl.py's DECLARATOR.  Go's \w is ASCII and Python's is
// Unicode, and Go's \s lacks \v; on this corpus, measured pure ASCII with no
// control byte but TAB and LF, the two agree.  (?s) is Python's re.S.
var declarator = regexp.MustCompile(`(?s)^\**\s*[A-Za-z_]\w*(\s*\[[^\]]*\])*(\s*=\s*.+)?$`)

var ident = regexp.MustCompile(`[A-Za-z_]\w*`)

// startsDeclaration is onedecl.py's KEYWORD_START.
//
// That pattern lists eighteen type keywords and then ends with the
// alternative [A-Za-z_]\w*, which matches everything the other eighteen do --
// so the whole alternation says no more than "begins with an identifier", and
// the list is a fossil of the path that found it.  Written here as what it
// means.  (The \b that follows cannot fail: \w* is greedy to the end of the
// identifier, so a word boundary always holds there.)
func startsDeclaration(body []byte) bool {
	return len(body) > 0 && (body[0] == '_' || isAlpha(body[0]))
}

// splitDecl is onedecl.py's split_decl: one declarator per declaration, so
// that `int a, b;` becomes two lines and the unused-variable sweep deletes a
// line instead of rewriting one.  It returns nil when the line is not a
// candidate.
//
// Deliberately conservative.  A line qualifies only if it ends in ';', has a
// top-level comma, has NO parenthesis at all -- which rules out prototypes,
// calls and function-pointer declarators -- and every declarator after the
// type looks like one.  Commas inside braces are not top level, so an
// initialiser list and an enum body are untouched.
func splitDecl(line []byte) [][]byte {
	s := rtrim(line)
	body := trim(s)
	if !bytes.HasSuffix(body, []byte(";")) || bytes.HasPrefix(body, []byte("#")) ||
		bytes.HasPrefix(body, []byte("//")) {
		return nil
	}
	if !startsDeclaration(body) {
		return nil
	}
	indent := indentOf(s)
	inner := body[:len(body)-1]
	b := cutil.Blank(inner)
	d := cutil.Depths(b)

	if bytes.ContainsAny(b, "()") {
		return nil
	}

	var commas []int
	for j := 0; j < len(b); j++ {
		if b[j] == ',' && d[j] == 0 {
			commas = append(commas, j)
		}
	}
	if len(commas) == 0 {
		return nil
	}

	var parts [][]byte
	start := 0
	for _, j := range commas {
		parts = append(parts, inner[start:j])
		start = j + 1
	}
	parts = append(parts, inner[start:])

	// The type prefix ends where the first declarator's name begins: the last
	// identifier before any '[' or '=', backed up over the '*'s that bind to
	// it -- `char *a, b;` really does declare a pointer and a char.
	first := parts[0]
	fb := cutil.Blank(first)
	fd := cutil.Depths(fb)
	cut := len(first)
	for j := 0; j < len(fb); j++ {
		if fd[j] == 0 && (fb[j] == '[' || fb[j] == '=') {
			cut = j
			break
		}
	}
	core := first[:cut]
	ids := ident.FindAllIndex(core, -1)
	if len(ids) < 2 {
		return nil // a type and a name, at least
	}
	k := ids[len(ids)-1][0]
	for k > 0 && (core[k-1] == ' ' || core[k-1] == '\t' || core[k-1] == '*') {
		k--
	}
	typePrefix := rtrim(first[:k])
	if len(typePrefix) == 0 || !ident.Match(typePrefix) {
		return nil
	}
	for _, p := range parts[1:] {
		if !declarator.Match(trim(p)) {
			return nil
		}
	}

	out := [][]byte{decl(indent, typePrefix, trim(first[k:]))}
	for _, p := range parts[1:] {
		out = append(out, decl(indent, typePrefix, trim(p)))
	}
	return out
}

func decl(indent, typePrefix, name []byte) []byte {
	out := make([]byte, 0, len(indent)+len(typePrefix)+len(name)+2)
	out = append(out, indent...)
	out = append(out, typePrefix...)
	out = append(out, ' ')
	out = append(out, name...)
	return append(out, ';')
}

// OneDecl puts one declarator on each declaration.
//
// On whim and zero it splits nothing, measured over 150 inputs including 53
// real phase-edit outputs; on slim's sources it splits hundreds.
func OneDecl(src []byte) (out []byte, changed, nIn, nOut int) {
	lines := split(src)
	nIn = len(lines)
	kept := make([][]byte, 0, len(lines))
	for _, line := range lines {
		if got := splitDecl(line); got != nil {
			kept = append(kept, got...)
			changed++
			continue
		}
		kept = append(kept, line)
	}
	nOut = len(kept)
	return joinWithFinalNewline(kept), changed, nIn, nOut
}
