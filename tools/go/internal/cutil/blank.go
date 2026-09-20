// Package cutil is what tools/cutil.py is: the substrate the text tools stand
// on.  Only the part the sweep actually uses is here.
//
// Measured, the sweep reaches 159 of cutil.py's 375 statements; the rest --
// strip_comments_only, collapse_ws, rmatch, delete_definition, drop_if,
// fold_always, fold_never and their helpers -- is called by phase programs and
// never by a sweep tool, and linear_pass and balanced have no caller anywhere
// in tools/ or pipes/ at all.  They are left out until something needs them.
package cutil

import "bytes"

// Blank returns a copy of the same length with the CONTENTS of string
// literals, character constants and comments replaced by spaces.
//
// Offsets are preserved exactly, so an index into the result is an index into
// the input, and newlines survive so line numbers hold.  A literal's own
// quotes survive; a comment's delimiters do not, which the Python's docstring
// does not say but its code does.
//
// This is for LOCATING things -- parens, braces, operators -- and not for
// reading them.  What was inside a literal is gone here, and a pass that needs
// the real characters must walk the original.  The Python carries the warning
// that deciding whitespace from blanked text turned a backslash-n escape into
// the empty string and produced 630 compile errors; the same applies here.
//
// No cache.  cutil.py keeps a two-entry one keyed on object identity, because
// re-blanking a five-megabyte string costs a third of a second and phase
// programs call it dozens of times against the same text.  Inside the sweep
// that cache is not what pays: typereach, deadfields and deadenums each blank
// the file once and pass the result down explicitly.  A Go port that shares
// one blanked copy across a round gets the same saving structurally, and
// without an identity trick whose own docstring has to explain why it is not
// a correctness bug.
func Blank(s []byte) []byte {
	out := make([]byte, len(s))
	n := len(s)
	for i := 0; i < n; {
		c := s[i]

		if c == '"' || c == '\'' {
			q := c
			out[i] = c
			i++
			for i < n {
				// An escape consumes two bytes, and a backslash-newline
				// keeps its newline so that line numbers still hold.
				if s[i] == '\\' && i+1 < n {
					out[i] = ' '
					if s[i+1] == '\n' {
						out[i+1] = '\n'
					} else {
						out[i+1] = ' '
					}
					i += 2
					continue
				}
				if s[i] == q {
					out[i] = q
					i++
					break
				}
				out[i] = keepNewline(s[i])
				i++
			}
			continue
		}

		if c == '/' && i+1 < n && s[i+1] == '*' {
			j := bytes.Index(s[i+2:], []byte("*/"))
			if j < 0 {
				j = n
			} else {
				j = i + 2 + j + 2
			}
			for k := i; k < j; k++ {
				out[k] = keepNewline(s[k])
			}
			i = j
			continue
		}

		if c == '/' && i+1 < n && s[i+1] == '/' {
			j := i
			for j < n && s[j] != '\n' {
				// A // comment continues across a spliced line break.
				if s[j] == '\\' && j+1 < n && s[j+1] == '\n' {
					j += 2
					continue
				}
				j++
			}
			for k := i; k < j; k++ {
				out[k] = keepNewline(s[k])
			}
			i = j
			continue
		}

		out[i] = c
		i++
	}
	return out
}

func keepNewline(c byte) byte {
	if c == '\n' {
		return '\n'
	}
	return ' '
}
