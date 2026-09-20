package main

import (
	"fmt"
	"os"

	"slimvim.local/tools/internal/memo"
	"slimvim.local/tools/internal/pipeline"
)

// runImplhash is tools/implhash.sh.
//
//	slimtools implhash <unit> [pipeline]
//	slimtools implhash --edit <phase> [pipeline]
func runImplhash(args []string) int {
	editOnly := false
	if len(args) > 0 && args[0] == "--edit" {
		editOnly = true
		args = args[1:]
	}
	if len(args) == 0 {
		fmt.Fprintln(os.Stderr, "usage: slimtools implhash [--edit] <unit> [pipeline]")
		return 1
	}
	name := "slim"
	if len(args) > 1 {
		name = args[1]
	}
	p, err := pipeline.Get(name)
	if err != nil {
		fmt.Fprintf(os.Stderr, "slimtools: %v\n", err)
		return 1
	}
	h, err := memo.ImplHash(p, args[0], editOnly)
	if err != nil {
		fmt.Fprintf(os.Stderr, "%v\n", err)
		return 1
	}
	fmt.Println(h)
	return 0
}

// runParts is tools/phaserun.sh --parts: the programs a unit runs, in order.
func runParts(args []string) int {
	if len(args) != 2 {
		fmt.Fprintln(os.Stderr, "usage: slimtools parts <pipeline> <unit>")
		return 1
	}
	p, err := pipeline.Get(args[0])
	if err != nil {
		fmt.Fprintf(os.Stderr, "slimtools: %v\n", err)
		return 1
	}
	for _, s := range p.Parts(args[1]) {
		fmt.Println(s)
	}
	return 0
}
