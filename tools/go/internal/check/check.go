// Package check is a PROBE and not a decision.
//
// Every zero and whim check is still a shell program with Python heredocs in
// it, and the recorded reason for leaving them there is that "a check part is
// an argument that executes" -- 12,429 lines of pipes/ being that argument,
// which Go would move into `//` comments above three times the code.  Three
// measurements since say that reason is wrong on all three counts: the prose
// is in the SHELL (38.6% comment) and not the heredocs (11.6%); every module a
// check imports already has a Go package; and of 166 check heredocs only two
// need a hand-written scanner, 18 of the 21 lookarounds being local to one
// line.  What is actually left is size, about 12,600 lines.
//
// So one check is ported end to end here to find out what that costs, on the
// phase where the answer is cleanest: zero16 changes no code, its binary is
// byte-identical either side, and its argument is the shortest in the
// pipeline.  Nothing calls this package.  pipes/zero16-check.sh is untouched
// and is still what runs.
//
// THE SHAPE IS NOT THE EDITS'.  An edit is a function from a tree to a tree,
// and internal/edit's signature says so.  A check is not: it reads a work
// tree, a state directory and the world, prints a report as it goes, and
// either says nothing is wrong or exits non-zero.  It returns an error and
// writes its report to w, and the error is the exit -- there is no tree to
// give back.
package check

import (
	"fmt"
	"io"
	"sort"

	"slimvim.local/tools/internal/harness"
)

// A Func is one phase's check: work directory and state directory in, a report
// on w, and an error if the phase is wrong.
type Func func(w io.Writer, args []string) error

var checks = map[string]Func{}

func register(name string, f Func) {
	if _, dup := checks[name]; dup {
		panic("check: " + name + " registered twice")
	}
	checks[name] = f
}

// Lookup returns the check for a phase, and whether there is one.
func Lookup(phase string) (Func, bool) {
	f, ok := checks[phase]
	return f, ok
}

// Names returns every phase that has a check here, sorted.
func Names() []string {
	out := make([]string, 0, len(checks))
	for k := range checks {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}

// rep is the report a check prints, and it is the whole reason this package
// cannot borrow internal/edit's driver.
//
// A check does not stop at its first disagreement.  It COLLECTS -- `fail` in
// every heredoc in pipes/ -- so that a phase that is wrong in four ways says
// so in one run rather than over four twenty-minute gates.  say() prints as it
// goes because ORDER IS OUTPUT; bad() appends; and the error at the end is the
// exit status.
type rep struct {
	tag  string
	w    io.Writer
	fail []string
}

func (r *rep) say(format string, a ...any) {
	fmt.Fprintf(r.w, "  %-12s %s\n", r.tag, fmt.Sprintf(format, a...))
}

// cont is say with the tag column left blank: a continuation of the line
// above, which several checks use for a list under a heading.
func (r *rep) cont(format string, a ...any) {
	fmt.Fprintf(r.w, "  %-12s %s\n", "", fmt.Sprintf(format, a...))
}

func (r *rep) bad(format string, a ...any) {
	r.fail = append(r.fail, fmt.Sprintf(format, a...))
}

// done prints every collected disagreement and returns the failure, or nil.
//
// It returns harness.ErrReported and never a described error, because THE
// REPORT IS THE MESSAGE: the heredoc prints its `fail` lines and calls
// sys.exit(1), which adds nothing, and a Go caller that printed an error on
// top would put a line in the report that the phase did not write.  Measured
// -- the control below refused on both sides with the same assertion and the
// Go added `includes: 1 assertion(s) failed`, which is exactly the kind of
// difference a report comparison exists to catch.
func (r *rep) done() error {
	if len(r.fail) == 0 {
		return nil
	}
	for _, l := range r.fail {
		fmt.Fprintf(r.w, "  %-12s %s\n", r.tag, l)
	}
	return harness.ErrReported
}
