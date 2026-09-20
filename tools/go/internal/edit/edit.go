// Package edit holds the per-phase edits that were Python heredocs in pipes/.
//
// A cutter in internal/cut is a rule several phases share.  These are the other
// kind: one phase's own transformation, written for one boundary and run
// nowhere else.  They were `python3 - "$f" <<'PY'` blocks inside the phase
// program, and there are 225 of them across whim and zero -- 34,284 lines --
// so they are the larger half of the port and they do not collapse.  Measured
// over all 225: 94 are bespoke drivers over cutil, 60 are bespoke regex
// programs, and exactly ONE is the simple "assert a literal occurs once and
// replace it" shape.  There is no idiom to factor out; there is a phase's
// argument, written once, per phase.
//
// THE SHAPE IS THE CUTTERS', deliberately: func([]byte, io.Writer) ([]byte,
// error), rewrite in place, report each act on stdout as it succeeds, refuse
// with an error rather than writing a half-done tree.  ORDER IS OUTPUT -- a
// phase program's log is read by a human comparing two phase commits, so the
// lines a port prints must be the lines the heredoc printed, in the order it
// printed them.
//
// They are reached as `slimtools edit <phase> <file>` through one registry
// rather than as 76 subcommands, so the table below is the whole of what a new
// phase has to join.
package edit

import (
	"fmt"
	"io"
	"sort"
)

// A Func is one phase's edit: it takes the tree and returns it rewritten.
type Func func(text []byte, w io.Writer) ([]byte, error)

// An ArgFunc is a Func that is handed the phase program's remaining arguments.
type ArgFunc func(text []byte, w io.Writer, args []string) ([]byte, error)

// phases is populated by each phase file's init(), NOT by a literal here, and
// that is a working arrangement rather than a style: two sessions port whim and
// zero in parallel, and a shared map literal is the one file they would both
// have to edit for every phase.  register() makes each phase's registration
// live beside its code, so the packages never collide.
var phases = map[string]ArgFunc{}

func register(name string, f Func) {
	registerArgs(name, func(t []byte, w io.Writer, _ []string) ([]byte, error) { return f(t, w) })
}

func registerArgs(name string, f ArgFunc) {
	if _, dup := phases[name]; dup {
		panic("edit: " + name + " registered twice")
	}
	phases[name] = f
}

// Lookup returns the edit for a phase, and whether there is one.
func Lookup(phase string) (ArgFunc, bool) {
	f, ok := phases[phase]
	return f, ok
}

// Names returns every phase that has an edit here, sorted, for the usage
// message -- ranging a Go map yields a different order every run, and a usage
// message that reorders itself is a diff nobody wanted.
func Names() []string {
	out := make([]string, 0, len(phases))
	for k := range phases {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}

// Once replaces the single occurrence of old with new, refusing unless it
// occurs exactly once.
//
// The refusal is the point and not a courtesy: these edits run on a tree
// produced by every phase before them, so an anchor that has stopped matching
// means the phase is about to cut something other than what it was written to
// cut.  CLAUDE.md's rule is to assert a partition rather than a count wherever
// the text allows it; a single literal occurrence IS that partition when the
// literal is unique, and the count is how it is stated.
func Once(text []byte, old, new string, what string) ([]byte, error) {
	n := countBytes(text, old)
	if n != 1 {
		return nil, fmt.Errorf("  %s occurs %d times, expected 1", what, n)
	}
	return replaceBytes(text, old, new), nil
}

func countBytes(text []byte, s string) int {
	n, b := 0, []byte(s)
	for i := 0; i+len(b) <= len(text); {
		j := indexFrom(text, b, i)
		if j < 0 {
			break
		}
		n++
		i = j + len(b)
	}
	return n
}

func replaceBytes(text []byte, old, new string) []byte {
	o, nw := []byte(old), []byte(new)
	i := indexFrom(text, o, 0)
	if i < 0 {
		return text
	}
	out := make([]byte, 0, len(text)-len(o)+len(nw))
	out = append(out, text[:i]...)
	out = append(out, nw...)
	return append(out, text[i+len(o):]...)
}

func indexFrom(text, needle []byte, from int) int {
	for i := from; i+len(needle) <= len(text); i++ {
		k := 0
		for k < len(needle) && text[i+k] == needle[k] {
			k++
		}
		if k == len(needle) {
			return i
		}
	}
	return -1
}
