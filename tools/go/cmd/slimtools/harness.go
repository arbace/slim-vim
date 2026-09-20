package main

import (
	"fmt"
	"os"

	"slimvim.local/tools/internal/harness"
)

// runExsweep is tools/exsweep.py.
func runExsweep(args []string) int {
	if len(args) != 3 {
		fmt.Fprintln(os.Stderr, "usage: slimtools exsweep <vim-binary> <table> <outfile>")
		return 1
	}
	if err := harness.ExSweep(args[0], args[1], args[2], os.Stdout); err != nil {
		fmt.Fprintf(os.Stderr, "slimtools: %v\n", err)
		return 1
	}
	return 0
}

// runBehaviour is tools/behaviour.py.
func runBehaviour(args []string) int {
	if len(args) != 2 {
		fmt.Fprintln(os.Stderr, "usage: slimtools behaviour <vim-binary> <outdir>")
		return 1
	}
	if err := harness.Behaviour(args[0], args[1], os.Stdout); err != nil {
		fmt.Fprintf(os.Stderr, "slimtools: %v\n", err)
		return 1
	}
	return 0
}

// runCmdnames is create_cmdidxs.names(): the Ex command table, in order.  It
// is exposed so the parse can be compared against the Python's without
// running the editor six hundred times.
func runCmdnames(args []string) int {
	if len(args) != 1 {
		fmt.Fprintln(os.Stderr, "usage: slimtools cmdnames <file>")
		return 1
	}
	names, err := harness.CommandNames(args[0])
	if err != nil {
		fmt.Fprintf(os.Stderr, "%v\n", err)
		return 1
	}
	for _, n := range names {
		fmt.Println(n)
	}
	return 0
}
