// Command slimtools is the Go implementation of what tools/*.py does.
//
// It is one binary with subcommands rather than one binary per tool, because
// every subcommand shares the same C front end and the same parse of the same
// multi-megabyte file: the sweep runs thirteen tools to a fixpoint, and the
// whole point of this rewrite is that they stop re-reading the file thirteen
// times a round.  Phase programs still name a distinct tools/go path per
// subcommand so that tools/implhash.sh keeps its per-tool invalidation; see
// that file.
//
// The C front end is modernc.org/cc/v4, pinned in go.mod and patched by
// tools/patches/cc-v4-c23.patch.  Parsing is used to LOCATE things -- every
// node carries a byte offset into the original source -- and never to reprint
// one: a reprint would lose the blank lines and indentation that no
// verification tier in this tree can see.
package main

import (
	"fmt"
	"os"
	"time"

	"modernc.org/cc/v4"
)

func usage() {
	fmt.Fprintln(os.Stderr, "usage: slimtools parse <file.c>")
	os.Exit(2)
}

func main() {
	if len(os.Args) < 2 {
		usage()
	}
	switch os.Args[1] {
	case "parse":
		if len(os.Args) != 3 {
			usage()
		}
		os.Exit(parse(os.Args[2]))
	default:
		usage()
	}
}

// parse is the stage-0 smoke test: it proves the patched front end is the one
// linked in, by parsing a whole product and reporting the time it took.  The
// two constructs the patch adds -- a C23 attribute in statement position and a
// label at the end of a compound statement -- are what make whim-vim.c and
// zero-vim.c parse at all, so an unpatched build fails here loudly.
func parse(path string) int {
	cfg, err := cc.NewConfig("linux", "amd64")
	if err != nil {
		fmt.Fprintf(os.Stderr, "slimtools: config: %v\n", err)
		return 1
	}
	src := []cc.Source{
		{Name: "<predefined>", Value: cfg.Predefined},
		{Name: "<builtin>", Value: cc.Builtin},
		{Name: path},
	}
	t0 := time.Now()
	ast, err := cc.Translate(cfg, src)
	elapsed := time.Since(t0)
	if err != nil {
		fmt.Fprintf(os.Stderr, "slimtools: %v\n", err)
		return 1
	}
	if ast == nil {
		fmt.Fprintln(os.Stderr, "slimtools: no AST and no error")
		return 1
	}
	fmt.Printf("parsed %s in %v\n", path, elapsed.Round(time.Millisecond))
	return 0
}
