package dead

import (
	"bytes"
	"regexp"
	"sort"

	"slimvim.local/tools/internal/cutil"
)

// defn is a definition at file scope: the name at column 0, a parameter list,
// and a body that opens on the next line -- the shape the canonicalisers
// guarantee, one statement per line and every brace where it belongs.
//
// Two things here are load-bearing and both were wrong the first time, with
// the same symptom: a span that ended at the wrong brace, so the deletion took
// a function's header and left its body as a file-scope fragment.
//
//	[^;\n]* and never [^;]*  -- a negated class matches newlines too, so a
//	greedy parameter list runs into the body and stops at some later ')' that
//	happens to end a line.
//	[ \t]*$ and never \s*$   -- \s matches a newline, with the same effect.
var defn = regexp.MustCompile(`(?m)^([A-Za-z_]\w*)\([^;\n]*\)[ \t]*$`)

var (
	protoLine = regexp.MustCompile(`(?m)^[A-Za-z_][A-Za-z0-9_ \t*]*\b\w+\([^;]*\)\s*;\s*$`)
	attrLine  = regexp.MustCompile(`(?m)^\s+__attribute__.*;\s*$`)
	// A two-line prototype: the declaration ends on a continuation carrying
	// an attribute, so the first line has no semicolon.
	protoTwoLine = regexp.MustCompile(`(?m)^[A-Za-z_][A-Za-z0-9_ \t*]*\b\w+\([^;]*\)\s*$\n\s*$`)
)

// FuncDefs maps a function name to its byte span.
type FuncDefs map[string][2]int

// FuncDefinitions finds every function defined at file scope.
func FuncDefinitions(text, blanked []byte) FuncDefs {
	out := FuncDefs{}
	for _, m := range defn.FindAllSubmatchIndex(blanked, -1) {
		i := m[1]
		for i < len(blanked) && (blanked[i] == ' ' || blanked[i] == '\t' || blanked[i] == '\n') {
			i++
		}
		if i >= len(blanked) || blanked[i] != '{' {
			continue
		}
		end := cutil.Match(blanked, i)
		if end < 0 {
			continue
		}
		// The return type sits on the line above; take it with the function.
		start := bytes.LastIndexByte(text[:m[0]], '\n')
		if start > 0 {
			start = bytes.LastIndexByte(text[:start], '\n') + 1
		} else {
			start = 0
		}
		out[string(blanked[m[2]:m[3]])] = [2]int{start, end + 1}
	}
	return out
}

// FuncReach returns the definitions, the reachable set and the dead names in
// sorted order.
//
// Reachability from roots, not reference counting.  A prototype names a
// function and does not use it, and this file has nearly two thousand of them
// in one block, so the declarations are stripped before the roots are taken.
// What is left outside every body -- tables, initialisers -- is where a
// handler reached only through cmdnames[] lives.
//
// Deliberately conservative in one direction: a name that merely appears in a
// live body counts as reached, even where it might be a variable of the same
// name.  Over-keeping is recoverable; the other error deletes something that
// runs.
func FuncReach(text []byte) (defs FuncDefs, reachable int, deadNames []string, deadLines int) {
	blanked := cutil.Blank(text)
	defs = FuncDefinitions(text, blanked)

	mentions := map[string][]string{}
	for name, span := range defs {
		seen := map[string]bool{}
		for _, m := range identRe.FindAll(text[span[0]:span[1]], -1) {
			s := string(m)
			if _, ok := defs[s]; ok && !seen[s] {
				seen[s] = true
				mentions[name] = append(mentions[name], s)
			}
		}
	}

	spans := make([][2]int, 0, len(defs))
	for _, s := range defs {
		spans = append(spans, s)
	}
	sort.Slice(spans, func(i, j int) bool { return spans[i][0] < spans[j][0] })

	var outside [][]byte
	prev := 0
	for _, s := range spans {
		outside = append(outside, text[prev:s[0]])
		prev = s[1]
	}
	outside = append(outside, text[prev:])

	cleaned := protoLine.ReplaceAll(bytes.Join(outside, []byte{'\n'}), nil)
	cleaned = attrLine.ReplaceAll(cleaned, nil)
	cleaned = protoTwoLine.ReplaceAll(cleaned, nil)

	roots := map[string]bool{"main": true}
	for _, m := range identRe.FindAll(cleaned, -1) {
		if _, ok := defs[string(m)]; ok {
			roots[string(m)] = true
		}
	}

	seen := map[string]bool{}
	var stack []string
	for r := range roots {
		if _, ok := defs[r]; ok {
			stack = append(stack, r)
		}
	}
	for len(stack) > 0 {
		f := stack[len(stack)-1]
		stack = stack[:len(stack)-1]
		if seen[f] {
			continue
		}
		seen[f] = true
		stack = append(stack, mentions[f]...)
	}

	for name := range defs {
		if !seen[name] {
			deadNames = append(deadNames, name)
		}
	}
	sort.Strings(deadNames)
	for _, f := range deadNames {
		s := defs[f]
		deadLines += bytes.Count(text[s[0]:s[1]], []byte{'\n'})
	}
	return defs, len(seen), deadNames, deadLines
}

// DeleteFuncs removes the dead definitions, back to front so that earlier
// offsets stay valid, taking the newlines that follow each with it.
func DeleteFuncs(text []byte, defs FuncDefs, deadNames []string) []byte {
	order := append([]string(nil), deadNames...)
	sort.Slice(order, func(i, j int) bool { return defs[order[i]][0] > defs[order[j]][0] })
	for _, f := range order {
		a, b := defs[f][0], defs[f][1]
		for b < len(text) && text[b] == '\n' {
			b++
		}
		text = append(append([]byte{}, text[:a]...), text[b:]...)
	}
	return text
}

// MinDefinitions is funcreach.py's floor.  Finding fewer than this many
// definitions means the shape it matches has changed, and acting on the
// answer would delete most of the program.  The Python exits 1 with a message
// and tools/sweep.sh carries on regardless, because pass() masks the status --
// it is a warning, not a stop.
const MinDefinitions = 100
