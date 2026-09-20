package main

import (
	"bytes"
	"fmt"
	"os"
	"sort"
	"strings"

	"slimvim.local/tools/internal/dead"
)

// The dead-code tools tools/sweep.sh runs before canon.
//
// Their CLI contracts differ from the canonicalisers' and from each other's,
// and the differences are load-bearing because tools/sweep.sh decides a tool
// did something by taking sha256 of the file: a tool that writes when the
// Python would not, or normalises a newline the Python leaves alone, adds a
// round to every sweep.

// runDeadprotos is tools/deadprotos.py.  It writes only when it dropped
// something and does not touch a missing trailing newline.  Its exit status is
// 0 on the happy path; a wrong argument count is 1, which is Python's
// sys.exit(__doc__).
func runDeadprotos(args []string) int {
	if len(args) != 1 {
		fmt.Fprintln(os.Stderr, "usage: slimtools deadprotos <file>")
		return 1
	}
	src, err := os.ReadFile(args[0])
	if err != nil {
		fmt.Fprintf(os.Stderr, "slimtools: %v\n", err)
		return 1
	}
	out, dropped := dead.DeadProtos(src)
	if len(dropped) > 0 {
		if err := writeFile(args[0], out); err != nil {
			fmt.Fprintf(os.Stderr, "slimtools: %v\n", err)
			return 1
		}
	}
	fmt.Printf("  deadprotos   %d declared, never defined, never called%s\n",
		len(dropped), droppedTail(dropped))
	return 0
}

// runTypereach is tools/typereach.py.  It prints a summary, then up to twenty
// detail lines, then -- only when deleting and only when something was dead --
// a final line.  tools/sweep.sh reads the last line printed, so which of the
// three it is depends on what happened, and all three are matched.
func runTypereach(args []string) int {
	del := false
	var files []string
	for _, a := range args {
		if a == "--delete" {
			del = true
			continue
		}
		files = append(files, a)
	}
	if len(files) != 1 {
		fmt.Fprintln(os.Stderr, "usage: slimtools typereach <file> [--delete]")
		return 1
	}
	text, err := os.ReadFile(files[0])
	if err != nil {
		fmt.Fprintf(os.Stderr, "slimtools: %v\n", err)
		return 1
	}
	defs, deadIdx := dead.TypeReach(text)
	fmt.Printf("%d type definitions, %d unreachable\n", len(defs), len(deadIdx))
	for n, i := range deadIdx {
		if n >= 20 {
			break
		}
		d := defs[i]
		names := make([]string, 0, len(d.Names))
		for nm := range d.Names {
			names = append(names, nm)
		}
		sort.Strings(names)
		label := strings.Join(names, ",")
		if len(label) > 40 {
			label = label[:40]
		}
		lines := bytes.Count(text[d.Start:d.End], []byte{'\n'}) + 1
		fmt.Printf("   %-40s %d lines\n", label, lines)
	}
	if del && len(deadIdx) > 0 {
		if err := writeFile(files[0], dead.DeleteDefs(text, defs, deadIdx)); err != nil {
			fmt.Fprintf(os.Stderr, "slimtools: %v\n", err)
			return 1
		}
		fmt.Printf("deleted %d definitions\n", len(deadIdx))
	}
	return 0
}

// droppedTail is the Python's report suffix: the first four names, and an
// ellipsis when there were more.
func droppedTail(dropped [][]byte) string {
	if len(dropped) == 0 {
		return ""
	}
	n := len(dropped)
	if n > 4 {
		n = 4
	}
	names := make([]string, n)
	for i := 0; i < n; i++ {
		names[i] = string(dropped[i])
	}
	tail := ""
	if len(dropped) > 4 {
		tail = "..."
	}
	return ": " + strings.Join(names, ", ") + tail
}
