package main

import (
	"fmt"
	"os"
	"time"

	"modernc.org/cc/v4"
)

// runParse is the front end's smoke test: it parses a whole product and
// reports how long that took.  It proves the PATCHED cc/v4 is the one linked
// in, because whim-vim.c and zero-vim.c do not parse without the patch --
// twenty '[[fallthrough]];' and two labels at the end of a compound
// statement.  A build against pristine cc/v4 fails here, loudly, which is what
// makes this a check rather than a demonstration.
//
// Nothing in the sweep uses this.  Parsing is for the phase edit programs,
// whose input is a boundary that compiled.
func runParse(args []string) int {
	if len(args) != 1 {
		fmt.Fprintln(os.Stderr, "usage: slimtools parse <file.c>")
		return 1
	}
	path := args[0]
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
