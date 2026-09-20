package memo

import (
	"bufio"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"

	"slimvim.local/tools/internal/pipeline"
	"slimvim.local/tools/internal/sweep"
)

// PhaseName is tools/phasename.sh: what a phase is called, read from the
// document that defines it rather than from a second list that can disagree
// with the first.
func PhaseName(p pipeline.P, phase int) string {
	data, err := os.ReadFile(p.Doc)
	if err != nil {
		return ""
	}
	re := regexp.MustCompile(fmt.Sprintf(`(?m)^## Phase %d [\x{2014}-] *(.*)$`, phase))
	if m := re.FindSubmatch(data); m != nil {
		return string(m[1])
	}
	return ""
}

// Restore puts a work tree back to a snapshot, so a phase is a pure function
// of its input rather than of whatever the last run left lying about.
//
// The directory is EMPTIED first.  A phase that deletes a file is as much a
// part of the phase as one that writes it, so unpacking over the top would
// silently keep the deleted file and make the boundary digest disagree for a
// reason nothing in the phase caused.
func Restore(tarIn, dir string) error {
	if err := os.RemoveAll(dir); err != nil {
		return err
	}
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	return exec.Command("tar", "--extract", "--file", tarIn, "-C", dir).Run()
}

// excludedFromTree is what the tree digest leaves out: build products, which
// are not the phase's output.  The built binary is excluded by name per
// pipeline, and the pattern must match whim-vim and zero-vim as well as vim --
// naming only /vim$ made every whim boundary count its own binary, and
// version.c embeds __DATE__ and __TIME__, so no boundary was ever equal to
// itself twice.  Nothing caught it for eleven phases, because a phase replayed
// from tier 3 copies the recorded digest rather than recomputing it.
var excludedFromTree = regexp.MustCompile(`/objects/|\.(o|d)$|/(whim-|zero-)?vim$`)

// TreeDigest is the digest of a work tree: a sha256 over every file's own
// sha256, build products excluded.
func TreeDigest(work string) (string, error) {
	var paths []string
	err := filepath.Walk(work, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if info.IsDir() {
			return nil
		}
		rel, err := filepath.Rel(work, path)
		if err != nil {
			return err
		}
		paths = append(paths, "./"+rel)
		return nil
	})
	if err != nil {
		return "", err
	}
	sort.Strings(paths)

	h := sha256.New()
	for _, rel := range paths {
		data, err := os.ReadFile(filepath.Join(work, rel))
		if err != nil {
			continue
		}
		sum := sha256.Sum256(data)
		// Matched WITHOUT the newline.  grep's $ is end of line and Go's,
		// outside (?m), is end of text -- so testing the terminated line would
		// never match `vim$` and the built binary would be hashed in, which is
		// the defect the exclusion exists to prevent: version.c embeds
		// __DATE__ and __TIME__, so a boundary counting its own binary is
		// never equal to itself twice.
		line := fmt.Sprintf("%s  %s", hex.EncodeToString(sum[:]), rel)
		if excludedFromTree.MatchString(line) {
			continue
		}
		h.Write([]byte(line))
		h.Write([]byte{'\n'})
	}
	return hex.EncodeToString(h.Sum(nil))[:32], nil
}

// PhaseRun is tools/phaserun.sh: it runs a unit, which is a phase N or a
// stage A-B.
//
// A STAGE is a run of split phases sharing ONE sweep: the symbol snapshot is
// taken once, every edit runs in order on text no sweep has touched since the
// stage began, the sweep runs once, every check runs in order on that one
// swept text and its one binary, and the declared delta is checked once, for
// the stage's last phase.
//
// THE CONTRACT, which is what makes a check runnable after other phases' edits
// and a shared sweep: the check part reads NOTHING from the edit part's shell.
// No variable, no function, no trap, no background job.  What passes between
// them is files in a state directory.
func PhaseRun(p pipeline.P, unit, work string, w io.Writer) error {
	first, last := unit, unit
	if i := strings.Index(unit, "-"); i >= 0 {
		first, last = unit[:i], unit[i+1:]
	}
	a, err := strconv.Atoi(first)
	if err != nil {
		return fmt.Errorf("phaserun: bad unit %q", unit)
	}
	b, err := strconv.Atoi(last)
	if err != nil {
		return fmt.Errorf("phaserun: bad unit %q", unit)
	}

	// A whole program is a unit of its own and runs as it always did.
	whole := fmt.Sprintf("pipes/%s%d.sh", p.Impl, a)
	edit0 := fmt.Sprintf("pipes/%s%d-edit.sh", p.Impl, a)
	check0 := fmt.Sprintf("pipes/%s%d-check.sh", p.Impl, a)
	if a == b && fileExists(whole) && !(fileExists(edit0) && fileExists(check0)) {
		cmd := exec.Command(whole, work)
		cmd.Stdout, cmd.Stderr = w, os.Stderr
		return cmd.Run()
	}

	for ph := a; ph <= b; ph++ {
		if !fileExists(fmt.Sprintf("pipes/%s%d-edit.sh", p.Impl, ph)) ||
			!fileExists(fmt.Sprintf("pipes/%s%d-check.sh", p.Impl, ph)) {
			fmt.Fprintf(os.Stderr,
				"  phaserun     %s phase %d has no edit and check to run in stage %s\n",
				p.Name, ph, unit)
			return fmt.Errorf("phaserun: phase %d is not split", ph)
		}
	}
	if p.Source == "" {
		fmt.Fprintf(os.Stderr,
			"  phaserun     the %s pipeline names no single source a sweep can run on\n", p.Name)
		return fmt.Errorf("phaserun: no source")
	}
	if err := runShell(w, "tools/stages.sh", p.Name, "--check"); err != nil {
		return err
	}
	f := filepath.Join(work, p.Source)

	// The stage's start: the symbol snapshot, once, of the text the first
	// edit is handed -- the one text in a stage certain to compile.
	stageState := filepath.Join(".cache/state", p.Tag+unit+".stage")
	os.RemoveAll(stageState)
	if err := os.MkdirAll(stageState, 0o755); err != nil {
		return err
	}
	if err := Symbols(f, filepath.Join(stageState, "symbols")); err != nil {
		return err
	}

	for ph := a; ph <= b; ph++ {
		state := filepath.Join(".cache/state", fmt.Sprintf("%s%d", p.Tag, ph))
		os.RemoveAll(state)
		if err := os.MkdirAll(state, 0o755); err != nil {
			return err
		}
		n, err := lineCount(f)
		if err != nil {
			return err
		}
		if err := os.WriteFile(filepath.Join(state, "input-lines"),
			[]byte(fmt.Sprintf("%d\n", n)), 0o644); err != nil {
			return err
		}
		name := PhaseName(p, ph)

		// EACH EDIT'S RESULT IS CACHED, keyed like any boundary: the phase,
		// the digest of the tree its edit is handed, and the implementation
		// digest of the edit part alone.  So editing phase K's program re-runs
		// K's edit and after it only the edits whose input really moved.  It
		// is tier 3 one level down, and as safe: a cached edit answers exactly
		// one input and one implementation.
		td, err := TreeDigest(work)
		if err != nil {
			return err
		}
		ih, err := ImplHash(p, strconv.Itoa(ph), true)
		if err != nil {
			return err
		}
		keySum := sha256.Sum256([]byte(fmt.Sprintf("%d\n%s\n%s\n", ph, td, ih)))
		ekey := hex.EncodeToString(keySum[:])[:32]
		edir := filepath.Join(".cache/edit", fmt.Sprintf("%s%d", p.Tag, ph))
		ecache := filepath.Join(edir, ekey)

		if fileExists(ecache+".tree.tar") && fileExists(ecache+".state.tar") {
			if err := Restore(ecache+".tree.tar", work); err != nil {
				return err
			}
			if err := exec.Command("tar", "--extract", "--file",
				ecache+".state.tar", "-C", state).Run(); err != nil {
				return err
			}
			fmt.Fprintf(w, "  %-12s %s  (edit cached for this input)\n",
				fmt.Sprintf("edit %d", ph), name)
			continue
		}
		if a != b {
			fmt.Fprintf(w, "  %-12s %s\n", fmt.Sprintf("edit %d", ph), name)
		}
		if err := runShell(w, fmt.Sprintf("pipes/%s%d-edit.sh", p.Impl, ph), work, state); err != nil {
			return err
		}
		if err := os.MkdirAll(edir, 0o755); err != nil {
			return err
		}
		if err := exec.Command("tar", "--create", "--file", ecache+".state.part",
			"-C", state, "--exclude=./input-lines", ".").Run(); err != nil {
			return err
		}
		if err := exec.Command("tar", "--create", "--file", ecache+".tree.part",
			"-C", work, ".").Run(); err != nil {
			return err
		}
		os.Rename(ecache+".state.part", ecache+".state.tar")
		os.Rename(ecache+".tree.part", ecache+".tree.tar")
	}

	if _, err := sweep.Sweep(f, w); err != nil {
		return err
	}

	// The checks, in order, all on the stage's one swept text and one binary.
	// Every check compares symbols with the STAGE's start, not its own.
	for ph := a; ph <= b; ph++ {
		state := filepath.Join(".cache/state", fmt.Sprintf("%s%d", p.Tag, ph))
		os.RemoveAll(filepath.Join(state, "symbols"))
		if err := copyTree(filepath.Join(stageState, "symbols"),
			filepath.Join(state, "symbols")); err != nil {
			return err
		}
		if a != b {
			fmt.Fprintf(w, "  %-12s %s\n", fmt.Sprintf("check %d", ph), PhaseName(p, ph))
		}
		if err := runShell(w, fmt.Sprintf("pipes/%s%d-check.sh", p.Impl, ph), work, state); err != nil {
			return err
		}
	}

	// The declared delta, once: the lines up to the stage's last phase are the
	// whole difference from the pipeline's baselines there, and so hold every
	// earlier phase's.
	if fileExists("pipes/" + p.Impl + ".delta") {
		if err := runShell(w, p.Delta,
			filepath.Join(work, strings.TrimSuffix(p.Source, ".c")), f,
			"--phase", strconv.Itoa(b)); err != nil {
			return err
		}
	}

	for ph := a; ph <= b; ph++ {
		os.RemoveAll(filepath.Join(".cache/state", fmt.Sprintf("%s%d", p.Tag, ph)))
	}
	return os.RemoveAll(stageState)
}

func runShell(w io.Writer, prog string, args ...string) error {
	cmd := exec.Command(prog, args...)
	cmd.Stdout, cmd.Stderr = w, os.Stderr
	return cmd.Run()
}

func fileExists(p string) bool {
	_, err := os.Stat(p)
	return err == nil
}

func lineCount(path string) (int, error) {
	f, err := os.Open(path)
	if err != nil {
		return 0, err
	}
	defer f.Close()
	s := bufio.NewScanner(f)
	s.Buffer(make([]byte, 0, 64*1024), 16*1024*1024)
	n := 0
	for s.Scan() {
		n++
	}
	return n, s.Err()
}

func copyTree(src, dst string) error {
	return filepath.Walk(src, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		rel, err := filepath.Rel(src, path)
		if err != nil {
			return err
		}
		target := filepath.Join(dst, rel)
		if info.IsDir() {
			return os.MkdirAll(target, 0o755)
		}
		data, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		return os.WriteFile(target, data, info.Mode().Perm())
	})
}
