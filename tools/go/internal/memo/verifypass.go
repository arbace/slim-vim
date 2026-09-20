package memo

import (
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"time"

	"slimvim.local/tools/internal/pipeline"
)

// VerifyPass re-derives every recorded boundary from the recorded boundary
// BEFORE it, each in a scratch root of its own, and requires each one back.
//
// This is the only thing that can FALSIFY a boundary rather than replay one.
// A tier-3 hit copies the recorded digest instead of recomputing it, so a warm
// pass agrees with the oracle whatever the oracle says -- which is how a wrong
// boundary went unnoticed for eleven phases.  By induction over the units this
// is the same proof as a cold sequential pass, in the time of its longest
// unit.
func VerifyPass(p pipeline.P, units []string, jobs int, w io.Writer) error {
	root, err := os.Getwd()
	if err != nil {
		return err
	}
	scratch, err := os.MkdirTemp("", "verifypass-"+p.Name+".")
	if err != nil {
		return err
	}

	// ONE SNAPSHOT OF THE CODE, taken before any unit starts, that every unit
	// links to instead of the live tree.
	//
	// `sh` reads a script BY BYTE OFFSET as it executes it, so rewriting one
	// in place while a check runs makes the shell resume at a stale offset in
	// new content -- and every unit used to symlink the one live pipes/, so a
	// single edit could reach every running check at once.  The quiet case is
	// why it matters: a tear mid-token gives a syntax error at a line that
	// exists in neither version, but a tear at a command boundary in a shorter
	// file just ENDS the script -- ten truncation points out of ten exited
	// zero, silently, with the remaining assertions never run.
	//
	// git is not the hazard: it writes by atomic rename, so a running shell
	// keeps its fd on the old inode and reads it to the end.  In-place writers
	// are -- an editor saving over a file, sed -i without a temp, a cp onto
	// the original.
	src := filepath.Join(scratch, ".src")
	if err := os.MkdirAll(src, 0o755); err != nil {
		return err
	}
	for _, d := range []string{"tools", "pipes"} {
		if err := exec.Command("cp", "-a", d, filepath.Join(src, d)).Run(); err != nil {
			return err
		}
	}

	if jobs <= 0 {
		jobs = runtime.NumCPU()
	}
	start := time.Now()
	fmt.Fprintf(w, "  %-12s %d units of %s, %d at a time, in %s\n",
		"verifypass", len(units), p.Name, jobs, scratch)

	results := make([]string, len(units))
	sem := make(chan struct{}, jobs)
	var wg sync.WaitGroup
	for i, u := range units {
		wg.Add(1)
		go func(i int, u string) {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()
			results[i] = verifyOne(p, u, root, scratch)
		}(i, u)
	}
	wg.Wait()

	fail := false
	sum := 0
	for i, u := range units {
		r := results[i]
		if !strings.HasPrefix(r, p.Tag+u+" ok ") {
			fail = true
		}
		sum += secondsIn(r)
		fmt.Fprintf(w, "      %s\n", r)
	}
	wall := int(time.Since(start).Seconds())
	if !fail {
		fmt.Fprintf(w, "  %-12s every boundary reproduces: %ds of phases in %ds of wall time\n",
			"verifypass", sum, wall)
		if os.Getenv("KEEP") != "" {
			fmt.Fprintf(w, "               kept in %s\n", scratch)
		} else {
			os.RemoveAll(scratch)
		}
		return nil
	}
	fmt.Fprintf(w, "  %-12s NOT every boundary reproduces -- the work is kept in %s\n",
		"verifypass", scratch)
	return fmt.Errorf("verifypass: a boundary did not reproduce")
}

// verifyOne runs one unit in its own scratch root and returns its result line.
func verifyOne(p pipeline.P, u, root, scratch string) string {
	first, last := u, u
	if i := strings.Index(u, "-"); i >= 0 {
		first, last = u[:i], u[i+1:]
	}
	a, _ := strconv.Atoi(first)
	n, _ := strconv.Atoi(last)

	wantOf := func(k int) string {
		data, err := os.ReadFile(filepath.Join(root, p.Build,
			fmt.Sprintf("%s%d.sha256", p.Tag, k)))
		if err != nil {
			return ""
		}
		return strings.TrimSpace(string(data))
	}

	var inTar, inWant string
	if a == 0 {
		inTar = filepath.Join(p.Build, "input.tar")
		data, _ := os.ReadFile(filepath.Join(root, p.Build, "input.sha256"))
		inWant = strings.TrimSpace(string(data))
	} else {
		inTar = filepath.Join(p.Build, fmt.Sprintf("%s%d.tar", p.Tag, a-1))
		inWant = wantOf(a - 1)
	}
	want := wantOf(n)
	if want == "" {
		return fmt.Sprintf("%s%s UNRECORDED", p.Tag, u)
	}

	d := filepath.Join(scratch, p.Tag+u)
	os.MkdirAll(filepath.Join(d, ".reference"), 0o755)
	os.MkdirAll(filepath.Join(d, ".cache"), 0o755)
	os.Symlink(filepath.Join(scratch, ".src", "tools"), filepath.Join(d, "tools"))
	os.Symlink(filepath.Join(scratch, ".src", "pipes"), filepath.Join(d, "pipes"))
	os.Symlink(filepath.Join(root, ".reference", "baselines"),
		filepath.Join(d, ".reference", "baselines"))
	if fileExists(filepath.Join(root, "slim-vim.c")) {
		os.Symlink(filepath.Join(root, "slim-vim.c"), filepath.Join(d, "slim-vim.c"))
	}
	if p.Name == "zero" {
		if fileExists(filepath.Join(root, "whim-vim.c")) {
			os.Symlink(filepath.Join(root, "whim-vim.c"), filepath.Join(d, "whim-vim.c"))
		}
		if fileExists(filepath.Join(root, ".reference", "zero-baselines")) {
			os.Symlink(filepath.Join(root, ".reference", "zero-baselines"),
				filepath.Join(d, ".reference", "zero-baselines"))
		}
	}

	start := time.Now()
	if err := Restore(filepath.Join(root, inTar), filepath.Join(d, p.Work)); err != nil {
		return fmt.Sprintf("%s%s FAILED to restore its input", p.Tag, u)
	}
	inSha := filepath.Join(d, "in.sha256")
	if err := Snapshot(filepath.Join(d, p.Work), filepath.Join(d, "in.tar"), inSha, io.Discard); err != nil {
		return fmt.Sprintf("%s%s FAILED to snapshot its input", p.Tag, u)
	}
	got, _ := os.ReadFile(inSha)
	if strings.TrimSpace(string(got)) != inWant {
		return fmt.Sprintf("%s%s INPUT %s is not the recorded %s",
			p.Tag, u, first12(string(got)), first12(inWant))
	}
	os.Remove(filepath.Join(d, "in.tar"))

	// The status is REPORTED and not merely tested.  A unit killed by a
	// signal, one whose script was torn by a concurrent rewrite, and one whose
	// assertion genuinely failed are three different events, and `if ! ...`
	// renders all three as the same word.
	logFile, err := os.Create(filepath.Join(d, "log"))
	if err != nil {
		return fmt.Sprintf("%s%s FAILED to open its log", p.Tag, u)
	}
	cmd := exec.Command("tools/phaserun.sh", p.Name, u, p.Work)
	cmd.Dir = d
	cmd.Stdout, cmd.Stderr = logFile, logFile
	runErr := cmd.Run()
	logFile.Close()
	if runErr != nil {
		rc := 1
		if ee, ok := runErr.(*exec.ExitError); ok {
			rc = ee.ExitCode()
		}
		why := fmt.Sprintf(" (rc %d)", rc)
		switch {
		case rc == 2:
			why = " (rc 2: shell syntax -- a torn read?)"
		case rc >= 130 && rc <= 149:
			why = fmt.Sprintf(" (rc %d: killed by signal %d)", rc, rc-128)
		}
		return fmt.Sprintf("%s%s FAILED %ds%s -- %s/log",
			p.Tag, u, int(time.Since(start).Seconds()), why, d)
	}

	outSha := filepath.Join(d, "out.sha256")
	if err := Snapshot(filepath.Join(d, p.Work), filepath.Join(d, "out.tar"), outSha, io.Discard); err != nil {
		return fmt.Sprintf("%s%s FAILED to snapshot its output", p.Tag, u)
	}
	os.Remove(filepath.Join(d, "out.tar"))
	secs := int(time.Since(start).Seconds())
	outGot, _ := os.ReadFile(outSha)
	if strings.TrimSpace(string(outGot)) == want {
		return fmt.Sprintf("%s%s ok %s %ds", p.Tag, u, first12(string(outGot)), secs)
	}
	return fmt.Sprintf("%s%s DIFFERS got %s, recorded %s %ds -- %s",
		p.Tag, u, first12(string(outGot)), first12(want), secs, d)
}

func first12(s string) string {
	s = strings.TrimSpace(s)
	if len(s) > 12 {
		return s[:12]
	}
	return s
}

// secondsIn pulls the " NNNs" a result line carries, so the total of the
// phases' own time can be set against the wall clock.
func secondsIn(r string) int {
	for _, f := range strings.Fields(r) {
		if strings.HasSuffix(f, "s") {
			if n, err := strconv.Atoi(strings.TrimSuffix(f, "s")); err == nil {
				return n
			}
		}
	}
	return 0
}
