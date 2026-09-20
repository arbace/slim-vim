package main

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
)

// difftest runs a Go subcommand and the Python tool it replaces on the same
// input and requires them to agree.
//
// What agreement means is fixed by tools/sweep.sh and not by taste.  The
// driver decides a tool changed something by taking sha256 of the file, so the
// FILE must agree byte for byte.  It reports with the tool's last line of
// stdout, so that line must agree too.  Exit codes are masked inside sweep.sh's
// pass() -- `said=$("$@" | tail -1)` makes the status tail's -- but a drop-in
// should match them anyway, and one caller does read one: deadenums --verify.
//
// Each case runs on its own copy.  These tools rewrite in place, so running
// two implementations on one file would have the second read the first's
// output, and running twice over a corpus would measure already-transformed
// text.
type spec struct {
	// script is the Python tool, relative to the repository root.
	script string
	// args, if non-nil, is appended after the file path for both sides.
	args []string
}

var specs = map[string]spec{
	"blankruns": {script: "tools/blankruns.py"},
}

func runDifftest(args []string) int {
	if len(args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: slimtools difftest <tool> <file>...")
		return 2
	}
	name := args[0]
	sp, ok := specs[name]
	if !ok {
		fmt.Fprintf(os.Stderr, "difftest: no spec for %q\n", name)
		return 2
	}
	if _, err := os.Stat(sp.script); err != nil {
		fmt.Fprintf(os.Stderr, "difftest: %v -- run me from the repository root\n", err)
		return 2
	}
	self, err := os.Executable()
	if err != nil {
		fmt.Fprintf(os.Stderr, "difftest: %v\n", err)
		return 2
	}

	inputs := args[1:]
	results := make([]string, len(inputs))
	var agreed, differed int
	var mu sync.Mutex

	sem := make(chan struct{}, runtime.NumCPU())
	var wg sync.WaitGroup
	for i, in := range inputs {
		wg.Add(1)
		go func(i int, in string) {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()
			why := compare(self, name, sp, in)
			mu.Lock()
			defer mu.Unlock()
			if why == "" {
				agreed++
			} else {
				differed++
				results[i] = fmt.Sprintf("  %s\n    %s", in, why)
			}
		}(i, in)
	}
	wg.Wait()

	// Reported in input order, not completion order: results is indexed by
	// input, so walking it is already the stable ordering.
	for _, r := range results {
		if r != "" {
			fmt.Println(r)
		}
	}
	fmt.Printf("difftest %s: %d agreed, %d differed, of %d\n", name, agreed, differed, len(inputs))
	if differed != 0 {
		return 1
	}
	return 0
}

// compare runs both implementations on their own copy of one input and
// returns "" when they agree, or a description of the first difference.
func compare(self, name string, sp spec, in string) string {
	dir, err := os.MkdirTemp("", "difftest.")
	if err != nil {
		return fmt.Sprintf("mkdtemp: %v", err)
	}
	defer os.RemoveAll(dir)

	src, err := os.ReadFile(in)
	if err != nil {
		return fmt.Sprintf("read: %v", err)
	}
	base := filepath.Base(in)
	pyFile := filepath.Join(dir, "py."+base)
	goFile := filepath.Join(dir, "go."+base)
	for _, f := range []string{pyFile, goFile} {
		if err := os.WriteFile(f, src, 0o644); err != nil {
			return fmt.Sprintf("write: %v", err)
		}
	}

	pyOut, pyCode := run("python3", append([]string{sp.script, pyFile}, sp.args...))
	goOut, goCode := run(self, append([]string{name, goFile}, sp.args...))

	pyBytes, err := os.ReadFile(pyFile)
	if err != nil {
		return fmt.Sprintf("read back python: %v", err)
	}
	goBytes, err := os.ReadFile(goFile)
	if err != nil {
		return fmt.Sprintf("read back go: %v", err)
	}

	if !bytes.Equal(pyBytes, goBytes) {
		return fmt.Sprintf("FILE differs: python %d bytes, go %d bytes%s",
			len(pyBytes), len(goBytes), firstDiff(pyBytes, goBytes))
	}
	if lastLine(pyOut) != lastLine(goOut) {
		return fmt.Sprintf("STDOUT differs:\n      python: %s\n      go:     %s",
			lastLine(pyOut), lastLine(goOut))
	}
	if pyCode != goCode {
		return fmt.Sprintf("EXIT differs: python %d, go %d", pyCode, goCode)
	}
	return ""
}

func run(bin string, args []string) (string, int) {
	cmd := exec.Command(bin, args...)
	var out bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = nil
	err := cmd.Run()
	code := 0
	if ee, ok := err.(*exec.ExitError); ok {
		code = ee.ExitCode()
	} else if err != nil {
		return out.String(), -1
	}
	return out.String(), code
}

// firstDiff names the byte offset where two outputs part, which is the thing
// worth knowing when a whole file disagrees.
func firstDiff(a, b []byte) string {
	n := len(a)
	if len(b) < n {
		n = len(b)
	}
	for i := 0; i < n; i++ {
		if a[i] != b[i] {
			return fmt.Sprintf(", first at byte %d (python %q, go %q)", i, a[i], b[i])
		}
	}
	return fmt.Sprintf(", identical for the first %d bytes", n)
}

func lastLine(s string) string {
	s = strings.TrimRight(s, "\n")
	if i := strings.LastIndexByte(s, '\n'); i >= 0 {
		return s[i+1:]
	}
	return s
}
