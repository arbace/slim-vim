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

// SpecPass runs every unit at once on the PREVIOUS pass's boundaries and
// stores each result in the tier-3 cache under exactly the key memo will look
// it up by.
//
// A pass is sequential because unit N reads boundary N-1 -- but a repass has
// the previous pass's boundaries lying about, so each unit can be speculated
// on its old input.  Wherever a unit's real input turns out to be the one
// speculated on, its lookup is a hit; from the first unit whose input really
// changed, nothing matches and it runs as before.
//
// THE LOOKUP IS THE CHECK.  There is no separate "did the boundary change"
// step, which is why a wrong guess costs CPU and never correctness.  A unit
// that fails here is reported and left for the sequential pass to decide.  An
// agent phase is not a function and is never speculated on.
func SpecPass(p pipeline.P, jobs int, w io.Writer) error {
	root, err := os.Getwd()
	if err != nil {
		return err
	}
	scratch, err := os.MkdirTemp("", "specpass-"+p.Name+".")
	if err != nil {
		return err
	}
	units, err := Units(p)
	if err != nil {
		return err
	}
	if jobs <= 0 {
		jobs = runtime.NumCPU()
	}
	start := time.Now()
	fmt.Fprintf(w, "  %-12s %d units of %s speculated on the last pass's boundaries, %d at a time\n",
		"specpass", len(units), p.Name, jobs)

	results := make([]string, len(units))
	sem := make(chan struct{}, jobs)
	var wg sync.WaitGroup
	for i, u := range units {
		wg.Add(1)
		go func(i int, u string) {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()
			results[i] = specOne(p, u, root, scratch)
		}(i, u)
	}
	wg.Wait()

	ran, cached, other, sum := 0, 0, 0, 0
	for _, r := range results {
		sum += secondsIn(r)
		switch {
		case strings.Contains(r, " ran "):
			ran++
		case strings.HasSuffix(r, " cached"):
			cached++
		default:
			other++
			fmt.Fprintf(w, "      %s\n", r)
		}
	}
	wall := int(time.Since(start).Seconds())
	fmt.Fprintf(w, "  %-12s %d ran (%ds of phases in %ds), %d already cached, %d left to the pass\n",
		"specpass", ran, sum, wall, cached, other)
	if other == 0 && os.Getenv("KEEP") == "" {
		os.RemoveAll(scratch)
	} else {
		fmt.Fprintf(w, "               work in %s\n", scratch)
	}
	return nil
}

func specOne(p pipeline.P, u, root, scratch string) string {
	first := u
	if i := strings.Index(u, "-"); i >= 0 {
		first = u[:i]
	}
	a, _ := strconv.Atoi(first)

	inTar := filepath.Join(p.Build, "input.tar")
	inShaPath := filepath.Join(p.Build, "input.sha256")
	if a != 0 {
		inTar = filepath.Join(p.Build, fmt.Sprintf("%s%d.tar", p.Tag, a-1))
		inShaPath = filepath.Join(p.Build, fmt.Sprintf("%s%d.sha256", p.Tag, a-1))
	}
	if !fileExists(filepath.Join(root, inTar)) || !fileExists(filepath.Join(root, inShaPath)) {
		return fmt.Sprintf("%s%s no-input", p.Tag, u)
	}
	data, err := os.ReadFile(filepath.Join(root, inShaPath))
	if err != nil {
		return fmt.Sprintf("%s%s no-input", p.Tag, u)
	}
	inDigest := strings.TrimSpace(string(data))

	impl, err := ImplHash(p, u, false)
	if err != nil {
		return fmt.Sprintf("%s%s no-impl", p.Tag, u)
	}
	if impl == "agent" {
		return fmt.Sprintf("%s%s agent", p.Tag, u)
	}

	// The same three lines, in the same order, as Memo.
	key := Key(u, inDigest, impl)
	cache := filepath.Join(root, ".cache", p.Tag+u)
	if fileExists(filepath.Join(cache, key+".tar")) &&
		fileExists(filepath.Join(cache, key+".sha256")) {
		return fmt.Sprintf("%s%s cached", p.Tag, u)
	}

	d := filepath.Join(scratch, p.Tag+u)
	os.MkdirAll(filepath.Join(d, ".reference"), 0o755)
	os.MkdirAll(filepath.Join(d, ".cache"), 0o755)
	os.Symlink(filepath.Join(root, "tools"), filepath.Join(d, "tools"))
	os.Symlink(filepath.Join(root, "pipes"), filepath.Join(d, "pipes"))
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

	startT := time.Now()
	if err := Restore(filepath.Join(root, inTar), filepath.Join(d, p.Work)); err != nil {
		return fmt.Sprintf("%s%s no-input", p.Tag, u)
	}
	inSha := filepath.Join(d, "in.sha256")
	if err := Snapshot(filepath.Join(d, p.Work), filepath.Join(d, "in.tar"), inSha, io.Discard); err != nil {
		return fmt.Sprintf("%s%s no-input", p.Tag, u)
	}
	got, _ := os.ReadFile(inSha)
	if strings.TrimSpace(string(got)) != inDigest {
		return fmt.Sprintf("%s%s input-drift %s is not %s",
			p.Tag, u, first12(string(got)), first12(inDigest))
	}
	os.Remove(filepath.Join(d, "in.tar"))

	logFile, err := os.Create(filepath.Join(d, "log"))
	if err != nil {
		return fmt.Sprintf("%s%s failed to open its log", p.Tag, u)
	}
	cmd := exec.Command("tools/phaserun.sh", p.Name, u, p.Work)
	cmd.Dir = d
	cmd.Stdout, cmd.Stderr = logFile, logFile
	runErr := cmd.Run()
	logFile.Close()
	if runErr != nil {
		return fmt.Sprintf("%s%s failed %ds -- %s/log", p.Tag, u,
			int(time.Since(startT).Seconds()), d)
	}

	outSha := filepath.Join(d, "out.sha256")
	if err := Snapshot(filepath.Join(d, p.Work), filepath.Join(d, "out.tar"), outSha, io.Discard); err != nil {
		return fmt.Sprintf("%s%s failed to snapshot", p.Tag, u)
	}
	os.MkdirAll(cache, 0o755)

	// The tar and its file list first, the digest LAST and by rename: memo
	// takes a key as present only when the .tar and the .sha256 both exist, so
	// a half-written entry is never mistaken for a result.
	publish := func(from, to string) error {
		if err := copyFile(from, to+".part"); err != nil {
			return err
		}
		return os.Rename(to+".part", to)
	}
	if publish(filepath.Join(d, "out.tar"), filepath.Join(cache, key+".tar")) != nil ||
		publish(outSha+".files", filepath.Join(cache, key+".sha256.files")) != nil ||
		publish(outSha, filepath.Join(cache, key+".sha256")) != nil {
		return fmt.Sprintf("%s%s failed to publish", p.Tag, u)
	}
	outGot, _ := os.ReadFile(outSha)
	res := fmt.Sprintf("%s%s ran %s %ds", p.Tag, u, first12(string(outGot)),
		int(time.Since(startT).Seconds()))
	if os.Getenv("KEEP") == "" {
		os.RemoveAll(d)
	}
	return res
}
