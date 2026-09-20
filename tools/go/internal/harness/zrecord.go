package harness

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sync"
)

// ZRecord is tools/zrecord.sh: one recording of a zero binary, six parts.
//
// The parts are independent and run at once.  Their shape is checked
// afterwards rather than assumed: a harness that wrote nothing would turn
// every later comparison into a tautology, so an empty file or an empty
// directory is a failure here and not a quiet pass downstream.
//
// The terminal part is ZTermCheck and NOT TermCheck, and the difference is one
// argument: the whim tool opens a FILE to put something on the screen, and
// from zero phase 5 a file argument is an unknown option, so every row would
// read `(none)`.
func ZRecord(bin, src, out string, w io.Writer) error {
	if err := os.RemoveAll(out); err != nil {
		return err
	}
	if err := os.MkdirAll(out, 0o755); err != nil {
		return err
	}

	type part struct {
		name string
		run  func() error
	}
	parts := []part{
		{"screen", func() error { return ZCases(bin, filepath.Join(out, "screen"), io.Discard) }},
		{"memline", func() error { return ZMemline(bin, filepath.Join(out, "memline"), io.Discard) }},
		{"ref-excmds.txt", func() error {
			return ZExCmds(bin, src, filepath.Join(out, "ref-excmds.txt"), io.Discard)
		}},
		{"ref-argv.txt", func() error { return ZArgv(bin, filepath.Join(out, "ref-argv.txt"), io.Discard) }},
		{"ref-pty.txt", func() error { return ZPty(bin, filepath.Join(out, "ref-pty.txt"), io.Discard) }},
		{"ref-term.txt", func() error {
			return ZTermCheck(bin, filepath.Join(out, "ref-term.txt"), io.Discard)
		}},
	}

	errs := make([]error, len(parts))
	var wg sync.WaitGroup
	for i, p := range parts {
		wg.Add(1)
		go func(i int, p part) {
			defer wg.Done()
			errs[i] = p.run()
		}(i, p)
	}
	wg.Wait()

	for _, err := range errs {
		if err != nil {
			fmt.Fprintf(w, "  record       a harness failed on %s\n", bin)
			return fmt.Errorf("zrecord: a harness failed")
		}
	}

	for _, f := range []string{"ref-excmds.txt", "ref-argv.txt", "ref-pty.txt", "ref-term.txt"} {
		fi, err := os.Stat(filepath.Join(out, f))
		if err != nil || fi.Size() == 0 {
			fmt.Fprintf(w, "  record       %s is empty\n", filepath.Join(out, f))
			return fmt.Errorf("zrecord: %s is empty", f)
		}
	}
	for _, d := range []string{"screen", "memline"} {
		ents, err := os.ReadDir(filepath.Join(out, d))
		if err != nil || len(ents) == 0 {
			fmt.Fprintf(w, "  record       %s is empty\n", filepath.Join(out, d))
			return fmt.Errorf("zrecord: %s is empty", d)
		}
	}
	return nil
}
