package main

import (
	"fmt"
	"os"

	"slimvim.local/tools/internal/canon"
)

// The canonicalisers tools/canon.sh runs.  Each is a drop-in for its Python
// original: same argv, same rewrite-in-place, same single line of stdout.
//
// All of them rewrite UNCONDITIONALLY, which the Python does too and which
// matters more than it looks: tools/sweep.sh decides a tool changed something
// by taking sha256 of the file, so a run that finds nothing has to leave the
// bytes exactly as they were.  They also normalise a missing trailing newline,
// and which tools do that is not uniform -- eight of the thirteen do, five do
// not -- so it is matched per tool rather than centrally.

func runBlankruns(args []string) int {
	return rewrite(args, "blankruns", func(src []byte) ([]byte, string) {
		out, runs, dropped, nIn, nOut := canon.BlankRuns(src)
		return out, fmt.Sprintf("%d runs of >1 blank line collapsed, %d lines dropped; %d lines -> %d",
			runs, dropped, nIn, nOut)
	})
}

func runJoinparens(args []string) int {
	return rewrite(args, "joinparens", func(src []byte) ([]byte, string) {
		out, joined, nIn, nOut := canon.JoinParens(src)
		return out, fmt.Sprintf("%d lines joined; %d lines -> %d", joined, nIn, nOut)
	})
}

func runSplitheads(args []string) int {
	return rewrite(args, "splitheads", func(src []byte) ([]byte, string) {
		out, splits, nIn, nOut := canon.SplitHeads(src)
		return out, fmt.Sprintf("%d bodies moved onto their own line; %d lines -> %d",
			splits, nIn, nOut)
	})
}

// rewrite is the shape every canonicaliser has: one file argument, read it
// whole, transform it, write it back, print one line.
func rewrite(args []string, name string, f func([]byte) ([]byte, string)) int {
	if len(args) != 1 {
		fmt.Fprintf(os.Stderr, "usage: slimtools %s <file>\n", name)
		return 1
	}
	path := args[0]
	src, err := os.ReadFile(path)
	if err != nil {
		fmt.Fprintf(os.Stderr, "slimtools: %v\n", err)
		return 1
	}
	out, report := f(src)
	if err := writeFile(path, out); err != nil {
		fmt.Fprintf(os.Stderr, "slimtools: %v\n", err)
		return 1
	}
	fmt.Println(report)
	return 0
}

// writeFile replaces a file's contents, preserving its mode.  The Python opens
// with 'w', which truncates in place and keeps the inode; nothing in the sweep
// holds a descriptor across a tool, so either that or a rename would do, but
// in place is what is being replaced.
func writeFile(path string, data []byte) error {
	fi, err := os.Stat(path)
	mode := os.FileMode(0o644)
	if err == nil {
		mode = fi.Mode().Perm()
	}
	return os.WriteFile(path, data, mode)
}
