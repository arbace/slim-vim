package memo

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"slimvim.local/tools/internal/pipeline"
)

// Key is the memoize key: the unit, the input boundary's digest and the
// implementation's digest together.  Those three say "this implementation,
// applied to this input", which is the only thing a cached result is an answer
// to -- neither half alone is enough, and that is why a cache entry cannot go
// stale rather than merely being unlikely to.
func Key(unit, inDigest, impl string) string {
	sum := sha256.Sum256([]byte(fmt.Sprintf("%s\n%s\n%s\n", unit, inDigest, impl)))
	return hex.EncodeToString(sum[:])[:32]
}

// MemoKey computes the key a unit would be looked up under, reading the input
// boundary from the build directory the way Memo does.
func MemoKey(p pipeline.P, unit, build string) (string, error) {
	first := unit
	if i := strings.Index(unit, "-"); i >= 0 {
		first = unit[:i]
	}
	a, err := strconv.Atoi(first)
	if err != nil {
		return "", fmt.Errorf("memo: bad unit %q", unit)
	}
	var inDigest []byte
	if a == 0 {
		inDigest, err = os.ReadFile(filepath.Join(build, "input.sha256"))
	} else {
		inDigest, err = os.ReadFile(filepath.Join(build, fmt.Sprintf("%s%d.sha256", p.Tag, a-1)))
	}
	if err != nil {
		return "", err
	}
	impl, err := ImplHash(p, unit, false)
	if err != nil {
		return "", err
	}
	return Key(unit, strings.TrimRight(string(inDigest), "\n"), impl), nil
}

// Memo is tools/memo.sh: one unit, through the three tiers.
//
//	tier 3   the RESULT -- the boundary itself, keyed by content.  Costs
//	         nothing and can do nothing; it is an answer.
//	tier 2   the CODE -- the phase's program, or its edit and check parts.
//	         Does exactly what it was written for.
//	tier 1   the AGENT.  Can cope with something it has not seen, and is not
//	         a function: two runs on identical input have been measured to
//	         differ, so its boundary is advisory and never a check.
//
// The fall-through is the whole construct -- result, else code, else agent --
// and an agent run always leaves a tier 2 behind, so the same input never
// costs an agent twice.
func Memo(p pipeline.P, unit, work, build string, w io.Writer) error {
	first, last := unit, unit
	if i := strings.Index(unit, "-"); i >= 0 {
		first, last = unit[:i], unit[i+1:]
	}
	a, err := strconv.Atoi(first)
	if err != nil {
		return fmt.Errorf("memo: bad unit %q", unit)
	}
	phase, err := strconv.Atoi(last)
	if err != nil {
		return fmt.Errorf("memo: bad unit %q", unit)
	}

	cache := filepath.Join(".cache", p.Tag+unit)
	if err := os.MkdirAll(cache, 0o755); err != nil {
		return err
	}

	// The input half of the key, and it must be a FUNCTION of the input.  The
	// pipeline's own immutable input is right for the FIRST unit only: a unit
	// starting at 0 has no boundary before it.  Anything else reads the
	// boundary before it and REFUSES when that file is absent -- a missing one
	// means the phase list has a gap, and falling back to the pipeline input
	// there keys the unit on a digest that never moves, so a cached result is
	// served back whatever the real input became.  Measured: a phase's result,
	// cached against r30, was a hit after a rebase onto r32, and the pass
	// reported a boundary in twelve seconds that was the phase applied to the
	// wrong tree.
	var inDigest []byte
	if a == 0 {
		inDigest, err = os.ReadFile(filepath.Join(build, "input.sha256"))
		if err != nil {
			return err
		}
	} else {
		prev := filepath.Join(build, fmt.Sprintf("%s%d.sha256", p.Tag, a-1))
		inDigest, err = os.ReadFile(prev)
		if err != nil {
			fmt.Fprintf(os.Stderr, "memo: %s unit %s wants %s%d, which does not exist.\n",
				p.Name, unit, p.Tag, a-1)
			fmt.Fprintf(os.Stderr, "      Phases must be contiguous; %s's list has a gap before %d.\n",
				p.Name, a)
			return fmt.Errorf("memo: gap before %d", a)
		}
	}

	impl, err := ImplHash(p, unit, false)
	if err != nil {
		return err
	}
	key := Key(unit, strings.TrimRight(string(inDigest), "\n"), impl)

	start := time.Now()
	printHeader(p, unit, a, phase, w)

	// --- tier 3: the result ---------------------------------------------
	tarPath := filepath.Join(cache, key+".tar")
	shaPath := filepath.Join(cache, key+".sha256")
	if fileExists(tarPath) && fileExists(shaPath) {
		if err := Restore(tarPath, work); err != nil {
			return err
		}
		copyFile(shaPath, filepath.Join(build, fmt.Sprintf("%s%d.sha256", p.Tag, phase)))
		copyFile(shaPath+".files", filepath.Join(build, fmt.Sprintf("%s%d.sha256.files", p.Tag, phase)))
		copyFile(tarPath, filepath.Join(build, fmt.Sprintf("%s%d.tar", p.Tag, phase)))
		os.WriteFile(filepath.Join(build, fmt.Sprintf("%s%d.kind", p.Tag, phase)), []byte("cached\n"), 0o644)
		os.WriteFile(filepath.Join(build, fmt.Sprintf("%s%d.seconds", p.Tag, phase)), []byte("0\n"), 0o644)
		d, _ := os.ReadFile(shaPath)
		fmt.Fprintf(w, "      %-12s %s  cached for this input%s\n", "tier 3",
			shortDigest(d), since(build))
		return nil
	}

	// --- tier 2: the code -----------------------------------------------
	tier := ""
	if len(p.Parts(unit)) >= phase-a+1 {
		// Keep the input, so a failure can still be handed to tier 1 from the
		// state the phase was actually given.
		in := filepath.Join(build, ".memo-in.tar")
		src := filepath.Join(build, "input.tar")
		if a != 0 {
			src = filepath.Join(build, fmt.Sprintf("%s%d.tar", p.Tag, a-1))
		}
		copyFile(src, in)

		var buf bytes.Buffer
		runErr := PhaseRun(p, unit, work, &buf)
		indent(w, buf.Bytes())
		if runErr == nil {
			tier = "program"
		} else {
			if a == phase {
				fmt.Fprintf(w, "  tier 2       %s%d FAILED -- falling through to the agent\n",
					p.Tag, phase)
			} else {
				fmt.Fprintf(w, "  tier 2       stage %s FAILED -- running its phases one at a time\n",
					unit)
			}
			if err := Restore(in, work); err != nil {
				return err
			}
		}
		os.Remove(in)
	}

	// --- a stage that failed: one phase at a time -------------------------
	// A stage's failure does not say which phase is at fault, or whether any
	// is: a SCHEDULE can fail where each phase on its own does not.  So each
	// runs as a unit of its own, through this same memoize, from the stage's
	// input -- its own sweep, its own boundary, its own tier 1 -- exactly as
	// before stages existed.  The boundaries written in between are real ones
	// and the stage's result is the last of them.
	if tier == "" && a != phase {
		for ph := a; ph <= phase; ph++ {
			prev := filepath.Join(build, fmt.Sprintf("%s%d.tar", p.Tag, ph-1))
			if Restore(prev, work) != nil {
				if err := Restore(filepath.Join(build, "input.tar"), work); err != nil {
					return err
				}
			}
			if err := Memo(p, strconv.Itoa(ph), work, build, w); err != nil {
				return err
			}
		}
		tier = "phases"
	}

	// --- tier 1: the agent ------------------------------------------------
	if tier == "" {
		cmd := exec.Command("tools/agentphase.sh", strconv.Itoa(phase), work, p.Name)
		cmd.Stdout, cmd.Stderr = w, os.Stderr
		if err := cmd.Run(); err != nil {
			return err
		}
		tier = "agent"
	}

	elapsed := int(time.Since(start).Seconds())
	os.WriteFile(filepath.Join(build, fmt.Sprintf("%s%d.kind", p.Tag, phase)),
		[]byte(tier+"\n"), 0o644)
	os.WriteFile(filepath.Join(build, fmt.Sprintf("%s%d.seconds", p.Tag, phase)),
		[]byte(fmt.Sprintf("%d\n", elapsed)), 0o644)
	label := "2"
	switch tier {
	case "agent":
		label = "1"
	case "phases":
		label = "1/2"
	}
	fmt.Fprintf(w, "      %-12s %s, %dm%02ds%s\n", "tier "+label, tier,
		elapsed/60, elapsed%60, since(build))

	// --- memoize the result -----------------------------------------------
	bTar := filepath.Join(build, fmt.Sprintf("%s%d.tar", p.Tag, phase))
	bSha := filepath.Join(build, fmt.Sprintf("%s%d.sha256", p.Tag, phase))
	if err := Snapshot(work, bTar, bSha, w); err != nil {
		return err
	}
	copyFile(bTar, tarPath)
	copyFile(bSha, shaPath)
	copyFile(bSha+".files", shaPath+".files")

	// --- and memoize the AGENT'S BEHAVIOUR as code ------------------------
	// This is the part that makes the construct pay.  An agent run that is
	// merely cached saves nothing the next time upstream moves; one that
	// leaves a program behind turns an expensive answer into a cheap one for
	// ever.
	if tier == "agent" {
		cmd := exec.Command("tools/synth.sh", strconv.Itoa(phase), build, p.Name)
		cmd.Stdout, cmd.Stderr = w, os.Stderr
		return cmd.Run()
	}
	return nil
}

// printHeader says what is starting before it starts.  A pass is a
// long-running thing whose only feedback is this log, and a phase that prints
// nothing for six minutes is indistinguishable from a hung one.
func printHeader(p pipeline.P, unit string, a, phase int, w io.Writer) {
	name := PhaseName(p, phase)
	what := "phase"
	if a != phase {
		what = "stage"
		name = fmt.Sprintf("%d phases, one sweep: %s ... %s",
			phase-a+1, PhaseName(p, a), PhaseName(p, phase))
	}
	// Bold only for a terminal.  This output is piped as often as it is
	// watched, and an escape sequence in a log file is noise.
	b, r := "", ""
	if isTerminal(w) {
		b, r = "\033[1m", "\033[0m"
	}
	of := ""
	if us, err := Units(p); err == nil {
		i := 0
		for n, u := range us {
			if u == unit {
				i = n + 1
			}
		}
		if i == 0 {
			if u, err := UnitOf(p, phase); err == nil {
				of = "[of " + u + "]"
			}
		} else {
			of = fmt.Sprintf("[%d/%d]", i, len(us))
		}
	}
	fmt.Fprintf(w, "\n  %s%s %s %s%s  %s\n", b, of, what, unit, r, name)
}

func isTerminal(w io.Writer) bool {
	f, ok := w.(*os.File)
	if !ok {
		return false
	}
	fi, err := f.Stat()
	return err == nil && fi.Mode()&os.ModeCharDevice != 0
}

// since is the cumulative elapsed time, so the clock is visible without
// waiting for the summary.
func since(build string) string {
	data, err := os.ReadFile(filepath.Join(build, "pass-start"))
	if err != nil {
		return ""
	}
	t0, err := strconv.ParseInt(strings.TrimSpace(string(data)), 10, 64)
	if err != nil {
		return ""
	}
	t := time.Now().Unix() - t0
	return fmt.Sprintf(" - %dm%02ds into the pass", t/60, t%60)
}

func shortDigest(b []byte) string {
	if len(b) > 12 {
		return string(b[:12])
	}
	return strings.TrimRight(string(b), "\n")
}

// indent puts the tools' own reports one level in, so they read as
// subordinate to the phase lines rather than competing with them.
func indent(w io.Writer, b []byte) {
	for _, line := range bytes.Split(bytes.TrimRight(b, "\n"), []byte{'\n'}) {
		fmt.Fprintf(w, "      %s\n", line)
	}
}
