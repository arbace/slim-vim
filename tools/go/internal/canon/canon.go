package canon

import "bytes"

// Pass is one canonicaliser: bytes in, bytes out.
type Pass struct {
	Name string
	Run  func([]byte) []byte
}

// Passes are the seven tools/canon.sh runs, in its order, which is load-
// bearing and not alphabetical:
//
//	brace runs after joinparens and splitheads, so a head is a whole line
//	ending in ')' and a body starts on the next line; forcomma runs after
//	brace, because hoisting a statement in front of a `for` is only safe once
//	every body is a brace block and the statement therefore lands in the same
//	block the `for` is in.
//
// One pass of the seven is not enough, which is why there is a fixpoint at
// all: forcomma's hoist reshapes lines and gives splitheads and brace
// something new to find, and onestmt splits one label off a
// `case A: case B: case C:` line per pass, so that line alone needs five.
var Passes = []Pass{
	{"blankruns", func(b []byte) []byte { out, _, _, _, _ := BlankRuns(b); return out }},
	{"joinparens", func(b []byte) []byte { out, _, _, _ := JoinParens(b); return out }},
	{"splitheads", func(b []byte) []byte { out, _, _, _ := SplitHeads(b); return out }},
	{"brace", func(b []byte) []byte { out, _, _, _, _ := Brace(b); return out }},
	{"onestmt", func(b []byte) []byte { out, _, _, _ := OneStmt(b); return out }},
	{"onedecl", func(b []byte) []byte { out, _, _, _ := OneDecl(b); return out }},
	{"forcomma", func(b []byte) []byte { out, _, _, _, _, _ := ForComma(b, false); return out }},
}

// MaxRounds is canon.sh's ceiling.  Exceeding it is a hard failure and not a
// number to raise: two passes undoing each other is a bug in one of them.
const MaxRounds = 20

// Round runs the seven passes once, in order.
//
// The Python writes the file after every pass and the next one reads it back.
// Chaining in memory is the same computation -- each pass is a pure function
// of the bytes -- and nothing observes the intermediate states: canon.sh sends
// every pass's stdout to /dev/null and no other process holds the file during
// a round.  What it saves is seven process starts and seven read-write cycles
// over a multi-megabyte file, per round.
func Round(src []byte) []byte {
	for _, p := range Passes {
		src = p.Run(src)
	}
	return src
}

// Fixpoint runs rounds until one changes nothing, or until MaxRounds is
// exceeded, in which case converged is false and the caller must refuse.
// With once, it runs exactly one round, for a caller that has a fixpoint of
// its own -- sweep.sh loops until a whole round changes nothing and canon is
// part of that round, so proving canon settled separately would prove it
// twice.
func Fixpoint(src []byte, once bool) (out []byte, rounds int, changed, converged bool) {
	for {
		rounds++
		before := src
		src = Round(src)
		changed = !bytes.Equal(before, src)
		if once {
			return src, rounds, changed, true
		}
		if !changed {
			return src, rounds, false, true
		}
		if rounds >= MaxRounds {
			return src, rounds, true, false
		}
	}
}
