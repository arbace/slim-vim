// checkprobe runs one ported CHECK, and it is a probe and not a tool.
//
// It is a separate command rather than a `slimtools check` subcommand on
// purpose: `cmd/slimtools/main.go` is the other session's dispatch and the one
// file a shared edit would collide on, and nothing here is meant to be merged
// or to enter any phase's implementation digest.  Nothing in pipes/ names it.
//
// Usage: checkprobe <phase> <work-dir> <state-dir>
package main

import (
	"fmt"
	"os"
	"strings"

	"slimvim.local/tools/internal/check"
	"slimvim.local/tools/internal/harness"
)

func main() {
	if len(os.Args) < 3 {
		fmt.Fprintf(os.Stderr, "usage: checkprobe <phase> <work-dir> <state-dir>\n  phases: %s\n",
			strings.Join(check.Names(), " "))
		os.Exit(2)
	}
	f, ok := check.Lookup(os.Args[1])
	if !ok {
		fmt.Fprintf(os.Stderr, "checkprobe: no check for phase %q\n  phases: %s\n",
			os.Args[1], strings.Join(check.Names(), " "))
		os.Exit(2)
	}
	// ErrReported means the check has already printed its own refusal, so
	// nothing further is said -- printing an error on top would add a line the
	// phase did not write.  Anything else is the harness failing rather than
	// the phase, and is said.
	if err := f(os.Stdout, os.Args[2:]); err != nil {
		if err != harness.ErrReported {
			fmt.Fprintln(os.Stderr, err)
		}
		os.Exit(1)
	}
}
