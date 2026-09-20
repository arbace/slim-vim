package main

import (
	"fmt"
	"os"
	"strings"

	"slimvim.local/tools/internal/edit"
)

func runEdit(args []string) int {
	if len(args) != 2 {
		fmt.Fprintf(os.Stderr, "usage: slimtools edit <phase> <file>\n  phases: %s\n",
			strings.Join(edit.Names(), " "))
		return 1
	}
	f, ok := edit.Lookup(args[0])
	if !ok {
		fmt.Fprintf(os.Stderr, "slimtools edit: no edit for phase %q\n  phases: %s\n",
			args[0], strings.Join(edit.Names(), " "))
		return 1
	}
	return oneFile(args[1:], "edit "+args[0], func(t []byte, w *os.File) ([]byte, error) {
		return f(t, w)
	})
}
