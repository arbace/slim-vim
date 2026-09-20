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

// runFuncreach is tools/funcreach.py.
//
// Its <100-definition floor exits 1 with a message on stderr, and the sweep
// carries on regardless: pass() runs the tool through a pipe to tail, so the
// status is tail's and set -e never sees it.  That is a warning and not a
// stop, and it is reproduced as one.
func runFuncreach(args []string) int {
	del := false
	var files []string
	for _, a := range args {
		if strings.HasPrefix(a, "--") {
			if a == "--delete" {
				del = true
			}
			continue
		}
		files = append(files, a)
	}
	if len(files) == 0 {
		fmt.Fprintln(os.Stderr, "usage: slimtools funcreach <file> [--delete]")
		return 1
	}
	text, err := os.ReadFile(files[0])
	if err != nil {
		fmt.Fprintf(os.Stderr, "slimtools: %v\n", err)
		return 1
	}
	defs, reachable, deadNames, deadLines := dead.FuncReach(text)
	if len(defs) < dead.MinDefinitions {
		fmt.Fprintf(os.Stderr, "funcreach: only %d definitions found, which cannot be right "+
			"for this file -- the shape it matches has changed, and acting "+
			"on the answer would delete most of the program\n", len(defs))
		return 1
	}
	fmt.Printf("  funcreach    %d definitions, %d reachable, %d not (%d lines)\n",
		len(defs), reachable, len(deadNames), deadLines)
	if len(deadNames) > 0 && del {
		if err := writeFile(files[0], dead.DeleteFuncs(text, defs, deadNames)); err != nil {
			fmt.Fprintf(os.Stderr, "slimtools: %v\n", err)
			return 1
		}
		n := len(deadNames)
		if n > 6 {
			n = 6
		}
		tail := ""
		if len(deadNames) > 6 {
			tail = "..."
		}
		fmt.Printf("  funcreach    deleted: %s%s\n", strings.Join(deadNames[:n], ", "), tail)
	}
	return 0
}

// runDeadfields is tools/deadfields.py.
//
// Its exit polarity is the OPPOSITE of deadsweep's and is reproduced as it
// stands: 0 when nothing was found, 1 when fields were.  Nothing depends on
// either today, because pass() masks both, but a drop-in matches what it
// replaces rather than what would be tidier.
func runDeadfields(args []string) int {
	del := false
	var files []string
	for _, a := range args {
		if a == "--delete" {
			del = true
			continue
		}
		files = append(files, a)
	}
	if len(files) == 0 {
		fmt.Fprintln(os.Stderr, "usage: slimtools deadfields <file> [--delete]")
		return 1
	}
	text, err := os.ReadFile(files[0])
	if err != nil {
		fmt.Fprintf(os.Stderr, "slimtools: %v\n", err)
		return 1
	}
	cands, refused := dead.DeadFields(text)
	if refused {
		fmt.Println("  deadfields   not while ml_recover() can read a swap file: " +
			"a struct layout is still a disk format")
		return 0
	}
	if del && len(cands) > 0 {
		if err := writeFile(files[0], dead.DeleteFields(text, cands)); err != nil {
			fmt.Fprintf(os.Stderr, "slimtools: %v\n", err)
			return 1
		}
	}
	fmt.Printf("  deadfields   %d fields nothing outside a type names\n", len(cands))
	if len(cands) == 0 {
		return 0
	}
	return 1
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
