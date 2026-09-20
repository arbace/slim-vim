package canon

import (
	"bytes"

	"slimvim.local/tools/internal/cutil"
)

// isWord reports whether c is what a regex word boundary counts as a word
// character, in ASCII.  Python's \b is Unicode-aware and Go's is not; the
// corpus is pure ASCII, measured, so the two agree, and this spells out which
// one is meant.
func isWord(c byte) bool {
	return c == '_' || (c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}

// indentOf returns the leading whitespace run.
func indentOf(line []byte) []byte {
	i := 0
	for i < len(line) && isSpace(line[i]) {
		i++
	}
	return line[:i]
}

// keywordHead matches `^(\s*)(kw)\b` and returns the end offset of the
// keyword, or -1.  Written out rather than compiled as a regex because Go's
// \s does not include \v and Python's does; no product contains one, and
// saying so here is cheaper than relying on it.
func keywordHead(line []byte, kw string) int {
	i := len(indentOf(line))
	if !bytes.HasPrefix(line[i:], []byte(kw)) {
		return -1
	}
	end := i + len(kw)
	if end < len(line) && isWord(line[end]) {
		return -1
	}
	return end
}

// controlHead matches `^(\s*)(if|for|while|switch)\s*\(` and returns the
// keyword's end offset, or -1.
func controlHead(line []byte) int {
	for _, kw := range []string{"if", "for", "while", "switch"} {
		end := keywordHead(line, kw)
		if end < 0 {
			continue
		}
		j := end
		for j < len(line) && isSpace(line[j]) {
			j++
		}
		if j < len(line) && line[j] == '(' {
			return end
		}
	}
	return -1
}

// SplitHeads puts the body of a control statement on its own line, so that
// `if (x) return;` becomes two lines.  Bracing is far simpler once every body
// starts on a line of its own, and one-statement-per-line wants it anyway.
//
// Two things must not be split: `} while (cond);`, which is a do-while's tail
// and not a head with a body, and `else if (...)`, which is one statement
// rather than an else with an if body.
//
// On whim and zero this splits nothing, measured over 97 inputs; on slim's
// sources it splits thousands.
func SplitHeads(src []byte) (out []byte, splits, nIn, nOut int) {
	lines := split(src)
	nIn = len(lines)
	kept := make([][]byte, 0, len(lines))

	for _, line := range lines {
		s := trim(line)
		if len(s) == 0 || s[0] == '#' || bytes.HasPrefix(s, []byte("//")) {
			kept = append(kept, line)
			continue
		}

		if end := controlHead(line); end >= 0 && !bytes.HasPrefix(ltrim(line), []byte("}")) {
			b := cutil.Blank(line)
			openI := bytes.IndexByte(b[end:], '(')
			if openI < 0 {
				kept = append(kept, line)
				continue
			}
			openI += end
			closeI := cutil.Match(b, openI)
			if closeI < 0 {
				kept = append(kept, line)
				continue
			}
			tail := trim(line[closeI+1:])
			if len(tail) > 0 && !bytes.Equal(tail, []byte("{")) {
				kept = append(kept, line[:closeI+1])
				kept = append(kept, body(indentOf(line), tail))
				splits++
				continue
			}
			kept = append(kept, line)
			continue
		}

		if end := keywordHead(line, "else"); end >= 0 {
			tail := trim(line[end:])
			if len(tail) > 0 && !bytes.Equal(tail, []byte("{")) && !startsWithWord(tail, "if") {
				kept = append(kept, append(append([]byte{}, indentOf(line)...), []byte("else")...))
				kept = append(kept, body(indentOf(line), tail))
				splits++
				continue
			}
			kept = append(kept, line)
			continue
		}

		if end := keywordHead(line, "do"); end >= 0 {
			tail := trim(line[end:])
			if len(tail) > 0 && !bytes.Equal(tail, []byte("{")) {
				kept = append(kept, append(append([]byte{}, indentOf(line)...), []byte("do")...))
				kept = append(kept, body(indentOf(line), tail))
				splits++
				continue
			}
		}

		kept = append(kept, line)
	}

	nOut = len(kept)
	return joinWithFinalNewline(kept), splits, nIn, nOut
}

// body is the moved-out statement: the head's indent, one level in, then the
// statement.
func body(indent, tail []byte) []byte {
	out := make([]byte, 0, len(indent)+4+len(tail))
	out = append(out, indent...)
	out = append(out, ' ', ' ', ' ', ' ')
	return append(out, tail...)
}

// startsWithWord is `re.match(r'^kw\b', s)`.
func startsWithWord(s []byte, kw string) bool {
	if !bytes.HasPrefix(s, []byte(kw)) {
		return false
	}
	return len(s) == len(kw) || !isWord(s[len(kw)])
}
