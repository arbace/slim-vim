package cutil

import "bytes"

func isAlnum(c byte) bool {
	return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}

func identChar(c byte) bool { return isAlnum(c) || c == '_' }

// FindDefinition locates a top-level function definition by name and returns
// the span covering the whole definition, including its closing brace and the
// newline after it, or ok=false.
//
// A definition is the identifier at brace depth 0, followed by '(' ... ')' and
// then '{'.  A declaration ends in ';' and is not matched.  The return type on
// its own preceding line belongs to the definition, so the start walks back
// over lines that are plainly not the end of something else.
//
// s is the original text and b is Blank(s): the search runs over the blanked
// copy, so a name inside a string literal is not a definition.
func FindDefinition(s, b []byte, name string) (start, end int, ok bool) {
	d := Depths(b)
	n := len(s)
	nm := []byte(name)
	pos := 0
	for {
		rel := bytes.Index(b[pos:], nm)
		if rel < 0 {
			return 0, 0, false
		}
		i := pos + rel
		pos = i + 1
		if d[i] != 0 {
			continue
		}
		if (i > 0 && identChar(s[i-1])) || (i+len(nm) < n && identChar(s[i+len(nm)])) {
			continue
		}
		j := i + len(nm)
		for j < n && (b[j] == ' ' || b[j] == '\t' || b[j] == '\n') {
			j++
		}
		if j >= n || b[j] != '(' {
			continue
		}
		k := Match(b, j)
		if k < 0 {
			continue
		}
		k++
		for k < n && (b[k] == ' ' || b[k] == '\t' || b[k] == '\n') {
			k++
		}
		if k >= n || b[k] != '{' {
			continue
		}
		e := Match(b, k)
		if e < 0 {
			continue
		}

		st := bytes.LastIndexByte(s[:i], '\n')
		if st < 0 {
			st = 0
		} else {
			st++
		}
		for {
			p := 0
			if st > 0 {
				p = bytes.LastIndexByte(s[:st-1], '\n')
			}
			if p < 0 {
				p = 0
			} else if st > 0 {
				p++
			}
			line := bytes.TrimSpace(s[p:st])
			if len(line) == 0 || endsAny(line, ";}{:") || bytes.HasPrefix(line, []byte("#")) {
				break
			}
			if bytes.HasPrefix(line, []byte("//")) || bytes.HasPrefix(line, []byte("/*")) ||
				bytes.HasSuffix(line, []byte("*/")) {
				break
			}
			if p == st {
				break
			}
			st = p
		}

		e++
		if e < n && s[e] == '\n' {
			e++
		}
		return st, e, true
	}
}

func endsAny(s []byte, set string) bool {
	if len(s) == 0 {
		return false
	}
	return bytes.IndexByte([]byte(set), s[len(s)-1]) >= 0
}

// HasDefinition reports whether a top-level function of that name is defined.
func HasDefinition(s []byte, name string) bool {
	_, _, ok := FindDefinition(s, Blank(s), name)
	return ok
}

// DeleteDefinition removes a function definition by name.  Reports whether one
// was there to remove, so a caller can refuse with its own words.
func DeleteDefinition(s []byte, name string) ([]byte, bool) {
	a, z, ok := FindDefinition(s, Blank(s), name)
	if !ok {
		return s, false
	}
	out := make([]byte, 0, len(s)-(z-a))
	out = append(out, s[:a]...)
	return append(out, s[z:]...), true
}
