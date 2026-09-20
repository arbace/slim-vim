package main

import (
	"fmt"
	"os"

	"slimvim.local/tools/internal/sweep"
)

// runSweep is tools/sweep.sh.  It must be run from the repository root, as the
// shell one must: .cache/compile is a relative path.
func runSweep(args []string) int {
	if len(args) != 1 {
		fmt.Fprintln(os.Stderr, "usage: slimtools sweep <file.c>")
		return 1
	}
	if _, err := os.Stat("tools"); err != nil {
		fmt.Fprintln(os.Stderr, "slimtools: run me from the repository root")
		return 1
	}
	if _, err := sweep.Sweep(args[0], os.Stdout); err != nil {
		fmt.Fprintf(os.Stderr, "slimtools: %v\n", err)
		return 1
	}
	return 0
}
