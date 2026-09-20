package harness

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
	"sync"
	"time"
)

// handsOverTheTerminal are the commands whose result is the environment's and
// not the editor's, and is not reproducible from one run to the next.
var handsOverTheTerminal = map[string]bool{
	"shell": true, "suspend": true, "stop": true,
	"terminal": true, "gui": true, "gvim": true,
}

// ExSweep dispatches every Ex command name once and records what happened.
//
// This is the sweep that catches things.  The one segfault that reached a
// build here -- a version string overflowing a 20-byte buffer, so :intro
// crashed -- was invisible to all 67 behaviour cases and to every pty
// scenario.  The boring mechanical dispatch over every entry point found it.
//
// Each dispatch runs from a scratch directory of its own, ALWAYS.  :mkvimrc,
// :mkexrc, :mksession, :mkview and :wviminfo with no argument write into the
// cwd; a previous run did this from the repository root, committed two of the
// files by accident, and made the sweep lie in both directions -- with the
// files already present those two commands returned 1 instead of 0, so a
// comparison against a reference recorded the same way agreed for the WRONG
// REASON.
func ExSweep(bin, table, out string, w interface{ Write([]byte) (int, error) }) error {
	vim, err := Stage(bin)
	if err != nil {
		return err
	}
	names, err := CommandNames(table)
	if err != nil {
		return err
	}
	home, err := os.MkdirTemp("", "exsweep-home-")
	if err != nil {
		return err
	}
	defer os.RemoveAll(home)
	env := Env(home)

	// How a run quits.  :qall! closes every window a command opened, which is
	// what makes :new, :split and the rest deterministic in slim-vim.
	// whim-vim has one window and no :qall, and there :q! is the same thing.
	// ASKED OF THE BINARY ONCE, rather than assumed from its name.
	quit := "+q!"
	probe := exec.Command(vim, "-e", "-s", "+qall!")
	probe.Env = env
	probe.Dir = home
	probe.Stdin = nil
	if probe.Run() == nil {
		quit = "+qall!"
	}

	rows := make([]string, len(names))
	sem := make(chan struct{}, runtime.NumCPU())
	var wg sync.WaitGroup
	for i, name := range names {
		wg.Add(1)
		go func(i int, name string) {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()
			rows[i] = dispatch(vim, env, name, quit)
		}(i, name)
	}
	wg.Wait()

	// Rows are kept in TABLE order: each dispatch has its own scratch
	// directory and its own session, so nothing one command does can reach
	// another, and writing them by index keeps the recording the same bytes it
	// always was.
	if err := os.WriteFile(out, []byte(strings.Join(rows, "\n")+"\n"), 0o644); err != nil {
		return err
	}
	fmt.Fprintf(w, "%d commands -> %s\n", len(rows), out)
	return nil
}

func dispatch(vim string, env []string, name, quit string) string {
	if handsOverTheTerminal[name] {
		return fmt.Sprintf("%-24s SKIPPED (hands over the terminal)", name)
	}
	d, err := os.MkdirTemp("", "exsweep-")
	if err != nil {
		return fmt.Sprintf("%-24s TIMEOUT", name)
	}
	defer os.RemoveAll(d)
	src := filepath.Join(d, "f.txt")
	if err := os.WriteFile(src, []byte("alpha\nbeta\ngamma\n"), 0o644); err != nil {
		return fmt.Sprintf("%-24s TIMEOUT", name)
	}

	// +{command}, not -c: whim-vim has no -c, and both fill the same list.
	cmd := exec.Command(vim, "-e", "-s", "+"+name, quit, src)
	cmd.Env = env
	cmd.Dir = d
	cmd.Stdin = nil
	var stderr strings.Builder
	cmd.Stderr = &stderr
	cmd.Stdout = nil
	setsid(cmd)

	done := make(chan error, 1)
	if err := cmd.Start(); err != nil {
		return fmt.Sprintf("%-24s TIMEOUT", name)
	}
	go func() { done <- cmd.Wait() }()
	var runErr error
	select {
	case runErr = <-done:
	case <-time.After(20 * time.Second):
		if cmd.Process != nil {
			cmd.Process.Kill()
		}
		<-done
		return fmt.Sprintf("%-24s TIMEOUT", name)
	}

	code := 0
	if ee, ok := runErr.(*exec.ExitError); ok {
		code = ee.ExitCode()
	} else if runErr != nil {
		code = -1
	}
	errText := strings.ReplaceAll(strings.TrimSpace(stderr.String()), "\n", " | ")

	// Files a command left behind in the cwd are part of what it did.
	var left []string
	if ents, err := os.ReadDir(d); err == nil {
		for _, e := range ents {
			if e.Name() != "f.txt" {
				left = append(left, e.Name())
			}
		}
	}
	sort.Strings(left)
	leftStr := strings.Join(left, ",")
	if leftStr == "" {
		leftStr = "-"
	}
	return fmt.Sprintf("%-24s exit=%-3d left=%-40s err=%s", name, code, leftStr, errText)
}
