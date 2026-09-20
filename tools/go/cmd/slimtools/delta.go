package main

import (
	"fmt"
	"os"
	"strconv"
	"strings"

	"slimvim.local/tools/internal/delta"
)

// runWhimdelta is tools/whimdelta.sh.
//
//	slimtools whimdelta <binary> <source> --phase N
//	slimtools whimdelta <binary> <source> [--term-moved] [--cases c1,c2] [cmds...]
//	slimtools whimdelta --declared N
func runWhimdelta(args []string) int {
	if len(args) >= 2 && args[0] == "--declared" {
		n, err := strconv.Atoi(args[1])
		if err != nil {
			fmt.Fprintln(os.Stderr, "usage: slimtools whimdelta --declared N")
			return 1
		}
		d, err := delta.Parse("pipes/whim.delta", n)
		if err != nil {
			fmt.Fprintf(os.Stderr, "slimtools: %v\n", err)
			return 1
		}
		for _, s := range d.Own {
			fmt.Println(s)
		}
		return 0
	}
	if len(args) < 2 {
		fmt.Fprintln(os.Stderr,
			"usage: slimtools whimdelta <binary> <source> --phase N | [--term-moved] [--cases c1,c2] [cmds...]")
		return 1
	}
	bin, src := args[0], args[1]
	rest := args[2:]

	var termMoved bool
	var cases, expected []string

	if len(rest) >= 2 && rest[0] == "--phase" {
		n, err := strconv.Atoi(rest[1])
		if err != nil {
			fmt.Fprintln(os.Stderr, "usage: slimtools whimdelta <binary> <source> --phase N")
			return 1
		}
		d, err := delta.Parse("pipes/whim.delta", n)
		if err != nil {
			fmt.Fprintf(os.Stderr, "slimtools: %v\n", err)
			return 1
		}
		termMoved, cases, expected = d.Term, d.Cases, d.Cmds
	} else {
		for len(rest) > 0 {
			switch {
			case rest[0] == "--term-moved":
				termMoved = true
				rest = rest[1:]
			case rest[0] == "--cases" && len(rest) > 1:
				cases = strings.Split(rest[1], ",")
				rest = rest[2:]
			default:
				expected = append(expected, rest[0])
				rest = rest[1:]
			}
		}
	}

	if err := delta.WhimDelta(bin, src, termMoved, cases, expected, os.Stdout); err != nil {
		return 1
	}
	return 0
}

// runDeclared prints what a delta file declares for one phase, for either
// pipeline -- the parser alone, with no harness run.  It is how the parse can
// be compared against the shell's awk without building a binary.
func runDeclared(args []string) int {
	if len(args) != 2 {
		fmt.Fprintln(os.Stderr, "usage: slimtools declared <delta-file> <phase>")
		return 1
	}
	n, err := strconv.Atoi(args[1])
	if err != nil {
		fmt.Fprintf(os.Stderr, "slimtools: %v\n", err)
		return 1
	}
	d, err := delta.Parse(args[0], n)
	if err != nil {
		fmt.Fprintf(os.Stderr, "slimtools: %v\n", err)
		return 1
	}
	fmt.Printf("term %v\n", d.Term)
	fmt.Printf("cmds %s\n", strings.Join(d.Cmds, " "))
	fmt.Printf("cases %s\n", strings.Join(d.Cases, " "))
	fmt.Printf("own %s\n", strings.Join(d.Own, " "))
	return 0
}
