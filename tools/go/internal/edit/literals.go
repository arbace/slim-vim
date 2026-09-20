package edit

import "bytes"

// literalSpans is the string- and character-literal scanner several zero
// heredocs define for themselves, and it is a SCANNER and not a regex.
//
// zero-vim.c has no preprocessor and no comments, so a literal is exactly a
// quote, the escaped bytes to the matching quote, and nothing crossing a
// newline.  That last is asserted rather than assumed: a scanner that lost its
// place would put every span after it in the wrong position, and a
// substitution driven by those spans would rewrite code it believed was data
// or spare data it believed was code.  So an unterminated literal refuses, at
// the line it began on.
//
// WHY THE PHASES DO THIS AT ALL: a name inside a string is data, and data is
// the one thing a mechanical edit must not change.  zero23 turns `NULL` into
// `nullptr` and three literals in that file contain the word -- an E1507
// message, "[NULL]" and "NULL" -- and a line-wise sed rewrites all three and
// moves 1,598 bytes of the binary, 1,354 of them in .rodata, with `[nullptr]`
// visible in `strings`.  Neither verification tier can see that: the build is
// clean and the token stream is right.
//
// It lives in its own file rather than in driver.go because driver.go is the
// other session's from the merge on, and a shared helper added there is the
// one edit we would both make.
func literalSpans(p ph, t []byte) ([][2]int, error) {
	var out [][2]int
	i, n := 0, len(t)
	for i < n {
		c := t[i]
		if c == '"' || c == '\'' {
			j := i + 1
			for j < n {
				if t[j] == '\\' {
					j += 2
					continue
				}
				if t[j] == c || t[j] == '\n' {
					break
				}
				j++
			}
			if j >= n || t[j] != c {
				kind := "character"
				if c == '"' {
					kind = "string"
				}
				return nil, p.die("an unterminated %s literal at line %d -- the scanner has lost its "+
					"place and every span after it would be wrong",
					kind, bytes.Count(t[:i], []byte{'\n'})+1)
			}
			out = append(out, [2]int{i, j + 1})
			i = j + 1
		} else {
			i++
		}
	}
	return out, nil
}

// literalSpansShort is the same scanner with the shorter refusal zero34's
// heredoc writes -- `the scanner has lost its place`, with no tail.
//
// THE TWO MESSAGES DIFFER AND THAT IS WHY THERE ARE TWO FUNCTIONS.  A port is
// held to the heredoc it replaces byte for byte, report included, so folding
// these into one would change one phase's output to match the other's.  The
// difference is the Python's and is preserved rather than tidied.
func literalSpansShort(p ph, t []byte) ([][2]int, error) {
	var out [][2]int
	i, n := 0, len(t)
	for i < n {
		c := t[i]
		if c == '"' || c == '\'' {
			j := i + 1
			for j < n {
				if t[j] == '\\' {
					j += 2
					continue
				}
				if t[j] == c || t[j] == '\n' {
					break
				}
				j++
			}
			if j >= n || t[j] != c {
				kind := "character"
				if c == '"' {
					kind = "string"
				}
				return nil, p.die("an unterminated %s literal at line %d -- the scanner has lost its "+
					"place", kind, bytes.Count(t[:i], []byte{'\n'})+1)
			}
			out = append(out, [2]int{i, j + 1})
			i = j + 1
		} else {
			i++
		}
	}
	return out, nil
}
