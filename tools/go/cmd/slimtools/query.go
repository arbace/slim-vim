package main

import (
	"fmt"
	"os"
	"strings"

	"slimvim.local/tools/internal/edit"
)

func runQuery(args []string) int {
	if len(args) != 2 {
		fmt.Fprintf(os.Stderr, "usage: slimtools query <phase> <file>\n  queries: %s\n",
			strings.Join(edit.QueryNames(), " "))
		return 1
	}
	f, ok := edit.LookupQuery(args[0])
	if !ok {
		fmt.Fprintf(os.Stderr, "slimtools query: no query for phase %q\n  queries: %s\n",
			args[0], strings.Join(edit.QueryNames(), " "))
		return 1
	}
	text, err := os.ReadFile(args[1])
	if err != nil {
		fmt.Fprintf(os.Stderr, "slimtools: %v\n", err)
		return 1
	}
	if err := f(text, os.Stdout); err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	return 0
}
