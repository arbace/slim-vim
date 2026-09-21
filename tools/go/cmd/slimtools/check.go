package main

import (
	"fmt"
	"os"
	"strings"

	"slimvim.local/tools/internal/check"
	"slimvim.local/tools/internal/harness"
)

// runCheck is `edit`'s twin and deliberately not its copy.  An edit is a
// function from a tree to a tree, so oneFile() rewrites a path in place and the
// driver owns the file.  A check has no tree to give back: it reads a work
// directory, a state directory and the world, prints its report as it goes, and
// its answer is the exit status.  So there is no file argument to rewrite and
// nothing to write back -- the arguments after the phase are handed to the check
// unread, because what they mean is the phase's business and not this file's.
func runCheck(args []string) int {
	if len(args) < 1 {
		fmt.Fprintf(os.Stderr, "usage: slimtools check <phase> [args...]\n  phases: %s\n",
			strings.Join(check.Names(), " "))
		return 2
	}
	f, ok := check.Lookup(args[0])
	if !ok {
		fmt.Fprintf(os.Stderr, "slimtools check: no check for phase %q\n  phases: %s\n",
			args[0], strings.Join(check.Names(), " "))
		return 2
	}
	// ErrReported means the check has already printed its own refusal, so
	// nothing further is said: a line this driver added would be a line the
	// phase did not write, and the phase's report IS its argument.  Anything
	// else is the harness failing rather than the phase, and is said.
	if err := f(os.Stdout, args[1:]); err != nil {
		if err != harness.ErrReported {
			fmt.Fprintln(os.Stderr, err)
		}
		return 1
	}
	return 0
}
