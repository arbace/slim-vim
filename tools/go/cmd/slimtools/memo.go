package main

import (
	"fmt"
	"os"
	"strconv"

	"slimvim.local/tools/internal/dead"
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

// runSymbols is tools/symbols.sh.
func runSymbols(args []string) int {
	if len(args) != 2 {
		fmt.Fprintln(os.Stderr, "usage: slimtools symbols <file.c> <outdir>")
		return 1
	}
	if err := memo.Symbols(args[0], args[1]); err != nil {
		fmt.Fprintf(os.Stderr, "slimtools: %v\n", err)
		return 1
	}
	return 0
}

// runOracle is tools/oracle.sh.
func runOracle(args []string) int {
	if len(args) < 3 {
		fmt.Fprintln(os.Stderr, "usage: slimtools oracle <phase> <build-dir> <oracle-dir> [pipeline]")
		return 1
	}
	name := "slim"
	if len(args) > 3 {
		name = args[3]
	}
	p, err := pipeline.Get(name)
	if err != nil {
		fmt.Fprintf(os.Stderr, "slimtools: %v\n", err)
		return 1
	}
	if err := memo.Oracle(p, args[0], args[1], args[2], os.Stdout); err != nil {
		return 1
	}
	return 0
}

// runPhasecheck is tools/phasecheck.sh.
func runPhasecheck(args []string) int {
	if len(args) != 3 {
		fmt.Fprintln(os.Stderr, "usage: slimtools phasecheck <work-dir> <source> <before-dir>")
		return 1
	}
	if err := memo.PhaseCheck(args[0], args[1], args[2], os.Stdout); err != nil {
		return 1
	}
	return 0
}

// runNvidx is tools/nvidxcheck.py.
func runNvidx(args []string) int {
	if len(args) != 1 {
		fmt.Fprintln(os.Stderr, "usage: slimtools nvidx <file>")
		return 1
	}
	data, err := os.ReadFile(args[0])
	if err != nil {
		fmt.Fprintf(os.Stderr, "slimtools: %v\n", err)
		return 1
	}
	line, ok := dead.NvIdxCheck(data)
	fmt.Println(line)
	if !ok {
		return 1
	}
	return 0
}

// runPhaserun is tools/phaserun.sh.
func runPhaserun(args []string) int {
	if len(args) == 2 && args[0] == "--parts" {
		fmt.Fprintln(os.Stderr, "usage: slimtools phaserun <pipeline> <unit> <work-dir>")
		return 1
	}
	if len(args) != 3 {
		fmt.Fprintln(os.Stderr, "usage: slimtools phaserun <pipeline> <unit> <work-dir>")
		return 1
	}
	p, err := pipeline.Get(args[0])
	if err != nil {
		fmt.Fprintf(os.Stderr, "slimtools: %v\n", err)
		return 1
	}
	if err := memo.PhaseRun(p, args[1], args[2], os.Stdout); err != nil {
		fmt.Fprintf(os.Stderr, "slimtools: %v\n", err)
		return 1
	}
	return 0
}

// runTreedigest is phaserun.sh's tree_digest: the digest of a work tree, which
// is half of an edit's cache key.
func runTreedigest(args []string) int {
	if len(args) != 1 {
		fmt.Fprintln(os.Stderr, "usage: slimtools treedigest <work-dir>")
		return 1
	}
	d, err := memo.TreeDigest(args[0])
	if err != nil {
		fmt.Fprintf(os.Stderr, "slimtools: %v\n", err)
		return 1
	}
	fmt.Println(d)
	return 0
}

// runPhasename is tools/phasename.sh.
func runPhasename(args []string) int {
	if len(args) == 0 {
		fmt.Fprintln(os.Stderr, "usage: slimtools phasename <phase> [pipeline]")
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
	n, err := strconv.Atoi(args[0])
	if err != nil {
		fmt.Fprintf(os.Stderr, "slimtools: %v\n", err)
		return 1
	}
	fmt.Println(memo.PhaseName(p, n))
	return 0
}

// runRestore is tools/restore.sh.
func runRestore(args []string) int {
	if len(args) != 2 {
		fmt.Fprintln(os.Stderr, "usage: slimtools restore <in.tar> <dir>")
		return 1
	}
	if err := memo.Restore(args[0], args[1]); err != nil {
		fmt.Fprintf(os.Stderr, "slimtools: %v\n", err)
		return 1
	}
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
