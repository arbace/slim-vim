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

func runOnestmt(args []string) int {
	return rewrite(args, "onestmt", func(src []byte) ([]byte, string) {
		out, changed, nIn, nOut := canon.OneStmt(src)
		return out, fmt.Sprintf("%d lines split; %d lines -> %d", changed, nIn, nOut)
	})
}

func runOnedecl(args []string) int {
	return rewrite(args, "onedecl", func(src []byte) ([]byte, string) {
		out, changed, nIn, nOut := canon.OneDecl(src)
		return out, fmt.Sprintf("%d declarations split; %d lines -> %d", changed, nIn, nOut)
	})
}

// runCanon is tools/canon.sh: the seven passes, in its order, once or to a
// fixpoint.  Its output lines are matched exactly, including the plural on
// "round".
func runCanon(args []string) int {
	once := false
	var files []string
	for _, a := range args {
		if a == "--once" {
			once = true
			continue
		}
		files = append(files, a)
	}
	if len(files) != 1 {
		fmt.Fprintln(os.Stderr, "usage: slimtools canon <file> [--once]")
		return 1
	}
	src, err := os.ReadFile(files[0])
	if err != nil {
		fmt.Fprintf(os.Stderr, "slimtools: %v\n", err)
		return 1
	}
	out, rounds, changed, converged := canon.Fixpoint(src, once)
	if err := writeFile(files[0], out); err != nil {
		fmt.Fprintf(os.Stderr, "slimtools: %v\n", err)
		return 1
	}
	if !converged {
		fmt.Printf("  canon        NOT CONVERGING after %d rounds -- two passes are\n", rounds)
		fmt.Println("               undoing each other; that is a bug in one of them,")
		fmt.Println("               not a reason to raise the limit.")
		return 1
	}
	if once {
		if changed {
			fmt.Println("canon changed it")
		} else {
			fmt.Println("canon settled")
		}
		return 0
	}
	s := "s"
	if rounds == 1 {
		s = ""
	}
	fmt.Printf("  canon        fixpoint after %d round%s\n", rounds, s)
	return 0
}

// runBrace is the one canonicaliser that prints TWO lines.  tools/sweep.sh
// reads only the last -- `said=$("$@" | tail -1)` -- but a drop-in matches
// what a program writes and not only what its caller happens to read.
func runBrace(args []string) int {
	if len(args) != 1 {
		fmt.Fprintln(os.Stderr, "usage: slimtools brace <file>")
		return 1
	}
	src, err := os.ReadFile(args[0])
	if err != nil {
		fmt.Fprintf(os.Stderr, "slimtools: %v\n", err)
		return 1
	}
	out, doTerms, braced, nIn, nOut := canon.Brace(src)
	fmt.Printf("%d do-terminating while lines identified\n", doTerms)
	if err := writeFile(args[0], out); err != nil {
		fmt.Fprintf(os.Stderr, "slimtools: %v\n", err)
		return 1
	}
	fmt.Printf("%d bodies braced; %d lines -> %d\n", braced, nIn, nOut)
	return 0
}

// runForcomma is the one canonicaliser with a second argument.  --check
// suppresses the write; nothing in tools/ or pipes/ passes it, and it is here
// so the CLI is a drop-in rather than nearly one.
func runForcomma(args []string) int {
	check := false
	var files []string
	for _, a := range args {
		if a == "--check" {
			check = true
			continue
		}
		files = append(files, a)
	}
	if len(files) != 1 {
		fmt.Fprintln(os.Stderr, "usage: slimtools forcomma <file> [--check]")
		return 1
	}
	src, err := os.ReadFile(files[0])
	if err != nil {
		fmt.Fprintf(os.Stderr, "slimtools: %v\n", err)
		return 1
	}
	out, found, hoisted, declined, nIn, nOut := canon.ForComma(src, check)
	if !check {
		if err := writeFile(files[0], out); err != nil {
			fmt.Fprintf(os.Stderr, "slimtools: %v\n", err)
			return 1
		}
	}
	fmt.Printf("%d init clauses with a comma: %d hoisted, %d declined; %d lines -> %d\n",
		found, hoisted, declined, nIn, nOut)
	return 0
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
