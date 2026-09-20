// Command slimtools is the Go implementation of what tools/*.py does.
//
// It is one binary with subcommands rather than one binary per tool, because
// every subcommand works on the same multi-megabyte file and the sweep runs
// thirteen of them to a fixpoint: as separate processes they re-read and
// re-scan that file thirteen times a round, which is the cost this rewrite is
// meant to remove.  Phase programs still name a distinct tools/go path per
// subcommand so that tools/implhash.sh keeps its per-tool invalidation.
//
// The subcommands are drop-in replacements: same argv, same rewrite-in-place,
// same stdout, same exit codes as the Python they stand in for.  tools/sweep.sh
// detects that a tool did something by taking sha256 of the file and by
// nothing else, so agreement means BYTE agreement and each one is held to it
// against the recorded boundaries -- see the difftest subcommand.
//
// The C front end (modernc.org/cc/v4, pinned and patched) is deliberately not
// used by any sweep subcommand.  Those run on text that six deleting tools
// have already cut and that nothing has compiled since, so it need not be
// valid C.  Parsing belongs to the phase edit programs, whose input is a
// boundary that compiled.
package main

import (
	"fmt"
	"os"

	"slimvim.local/tools/internal/canon"
)

// A tool is one subcommand.  It is handed everything after the subcommand
// name and returns the process exit status.
type tool struct {
	run   func(args []string) int
	usage string
}

var tools = map[string]tool{
	"blankruns": {runBlankruns, "blankruns <file>"},
	"parse":     {runParse, "parse <file.c>"},
	"difftest":  {runDifftest, "difftest <tool> <file>..."},
}

func main() {
	if len(os.Args) < 2 {
		usage()
	}
	t, ok := tools[os.Args[1]]
	if !ok {
		usage()
	}
	os.Exit(t.run(os.Args[2:]))
}

func usage() {
	fmt.Fprintln(os.Stderr, "usage: slimtools <subcommand> [args]")
	for _, name := range names() {
		fmt.Fprintf(os.Stderr, "    %s\n", tools[name].usage)
	}
	os.Exit(2)
}

// names returns the subcommands in a fixed order.  Ranging the map directly
// would print them differently every run, which is the Go-specific version of
// the determinism trap the Python tools avoid by sorting before they report.
func names() []string {
	return []string{"blankruns", "parse", "difftest"}
}

// runBlankruns is tools/blankruns.py.  It rewrites unconditionally -- the
// Python does, and the driver's only change signal is the file digest, so a
// run that finds nothing must leave the bytes exactly as they were.  Note it
// normalises a missing trailing newline; five of the thirteen tools do not,
// and which is which has to be matched per tool.
func runBlankruns(args []string) int {
	if len(args) != 1 {
		fmt.Fprintln(os.Stderr, "usage: slimtools blankruns <file>")
		return 1
	}
	path := args[0]
	src, err := os.ReadFile(path)
	if err != nil {
		fmt.Fprintf(os.Stderr, "slimtools: %v\n", err)
		return 1
	}
	out, runs, dropped, nIn, nOut := canon.BlankRuns(src)
	if err := writeFile(path, out); err != nil {
		fmt.Fprintf(os.Stderr, "slimtools: %v\n", err)
		return 1
	}
	fmt.Printf("%d runs of >1 blank line collapsed, %d lines dropped; %d lines -> %d\n",
		runs, dropped, nIn, nOut)
	return 0
}

// writeFile replaces a file's contents, preserving its mode.  The Python opens
// with 'w', which truncates in place and keeps the inode; a rename would
// change it, and tools/sweep.sh holds no descriptor across a tool, so either
// is safe -- but in place is what is being replaced, so it is what is done.
func writeFile(path string, data []byte) error {
	fi, err := os.Stat(path)
	mode := os.FileMode(0o644)
	if err == nil {
		mode = fi.Mode().Perm()
	}
	return os.WriteFile(path, data, mode)
}
