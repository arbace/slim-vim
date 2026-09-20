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
	"strings"

	"slimvim.local/tools/internal/dead"
)

// PhaseCheck is tools/phasecheck.sh: the generic post-edit check every phase
// runs -- it compiles clean, it warns about nothing but the fall-throughs, it
// still exports exactly main, its normal-mode index is still a permutation,
// and it reports what the phase cost in libc symbols.
//
// THE SWEEP ALREADY COMPILED THIS FILE, twice over.  Its last round is by
// definition a round on a file it then did not change, so if the source is
// still what that round saw, two of its answers are the two this compile is
// for.  The warnings are deadsweep's stderr, from a compile that generates no
// code; the object is the plain -O0 one the sweep builds in the background,
// and which symbols an object defines and needs does not depend on warning
// flags.  Both are keyed by content, so nothing goes stale.
func PhaseCheck(work, src, before string, w io.Writer) error {
	obj := filepath.Join(work, "phase.o")
	gccTxt := filepath.Join(work, "gcc.txt")

	data, err := os.ReadFile(src)
	if err != nil {
		return err
	}
	sum := sha256.Sum256(data)
	srcSha := hex.EncodeToString(sum[:])

	reused := false
	if lastSha, err := os.ReadFile(".cache/compile/last.sha"); err == nil {
		if buildSha, err := os.ReadFile(".cache/compile/build.sha"); err == nil {
			if strings.TrimSpace(string(lastSha)) == srcSha &&
				strings.TrimSpace(string(buildSha)) == srcSha {
				if err := copyFile(".cache/compile/build.o", obj); err == nil {
					if err := copyFile(".cache/compile/last.txt", gccTxt); err == nil {
						reused = true
					}
				}
			}
		}
	}

	if !reused {
		cmd := exec.Command("gcc", "-c", "-O0", "-Wall", "-Wextra",
			"-Wno-unused-parameter", "-o", obj, src)
		var stderr bytes.Buffer
		cmd.Stderr = &stderr
		runErr := cmd.Run()
		os.WriteFile(gccTxt, stderr.Bytes(), 0o644)
		if runErr != nil {
			fmt.Fprintln(w, "  compile      FAILED -- the cut did not leave valid C")
			n := 0
			for _, line := range strings.Split(stderr.String(), "\n") {
				if strings.Contains(line, "error:") {
					fmt.Fprintf(w, "               %s\n", line)
					if n++; n >= 5 {
						break
					}
				}
			}
			return fmt.Errorf("phasecheck: compile failed")
		}
	}

	txt, _ := os.ReadFile(gccTxt)
	var warns []string
	for _, line := range strings.Split(string(txt), "\n") {
		if strings.Contains(line, "warning:") && !strings.Contains(line, "implicit-fallthrough") {
			warns = append(warns, line)
		}
	}
	if len(warns) != 0 {
		fmt.Fprintf(w, "  warnings     %d besides the fall-throughs -- the sweep is not finished\n",
			len(warns))
		for i, line := range warns {
			if i >= 5 {
				break
			}
			fmt.Fprintf(w, "               %s\n", line)
		}
		return fmt.Errorf("phasecheck: %d warnings", len(warns))
	}
	os.Remove(gccTxt)

	ext, err := nmField(obj, []string{"--extern-only", "--defined-only"}, -1)
	if err != nil {
		return err
	}
	var other []string
	for _, n := range strings.Split(strings.TrimRight(string(ext), "\n"), "\n") {
		if n != "" && n != "main" {
			other = append(other, n)
		}
	}
	if len(other) > 0 {
		fmt.Fprintf(w, "  linkage      these became external: %s\n", strings.Join(other, "\n"))
		fmt.Fprintln(w, "               a dropped static declaration is a dropped linkage")
		return fmt.Errorf("phasecheck: external linkage")
	}
	fmt.Fprintln(w, "  linkage      nm on the object still prints exactly main")

	// A table index the compiler cannot check.
	line, ok := dead.NvIdxCheck(data)
	fmt.Fprintln(w, line)
	if !ok {
		return fmt.Errorf("phasecheck: nv_cmd_idx")
	}

	sha := srcSha[:32]
	if err := os.MkdirAll(SymbolCache, 0o755); err != nil {
		return err
	}
	undef, err := nmField(obj, []string{"-u"}, 1)
	if err != nil {
		return err
	}
	uPath := filepath.Join(SymbolCache, sha+".u")
	if err := os.WriteFile(uPath, undef, 0o644); err != nil {
		return err
	}
	if err := os.WriteFile(filepath.Join(SymbolCache, sha+".d"), ext, 0o644); err != nil {
		return err
	}
	os.Remove(obj)

	// The answers go BESIDE the cache and not into the work directory.  A file
	// left in the work tree is a file the boundary digest counts, and the
	// first run of this refactor changed twenty-one boundaries by writing
	// three of them -- the phases produced identical C and disagreed anyway.
	out := filepath.Join(SymbolCache, "last")
	if err := os.MkdirAll(out, 0o755); err != nil {
		return err
	}
	if err := os.WriteFile(filepath.Join(out, "undefined"), undef, 0o644); err != nil {
		return err
	}

	after := countLines(undef)
	if beforeData, err := os.ReadFile(filepath.Join(before, "undefined")); err == nil {
		nBefore := countLines(beforeData)
		gone := onlyInFirst(beforeData, undef)
		msg := fmt.Sprintf("  symbols      %d -> %d", nBefore, after)
		if gone != "" {
			msg += ", gone: " + gone
		}
		fmt.Fprintln(w, msg)
		os.WriteFile(filepath.Join(out, "before"), []byte(fmt.Sprintf("%d\n", nBefore)), 0o644)
	} else {
		fmt.Fprintf(w, "  symbols      %d\n", after)
		os.WriteFile(filepath.Join(out, "before"), []byte(fmt.Sprintf("%d\n", after)), 0o644)
	}
	os.WriteFile(filepath.Join(out, "after"), []byte(fmt.Sprintf("%d\n", after)), 0o644)
	os.RemoveAll(before)
	return nil
}

// onlyInFirst is `comm -23`: the lines in a and not in b, both sorted.  The
// shell joins them with a trailing space, which is kept.
func onlyInFirst(a, b []byte) string {
	inB := map[string]bool{}
	for _, l := range bytes.Split(b, []byte{'\n'}) {
		if len(l) > 0 {
			inB[string(l)] = true
		}
	}
	var out strings.Builder
	for _, l := range bytes.Split(a, []byte{'\n'}) {
		if len(l) > 0 && !inB[string(l)] {
			out.Write(l)
			out.WriteByte(' ')
		}
	}
	return out.String()
}

// countLines is what `grep -c` with an empty pattern answers: the number of
// lines, where a file not ending in a newline still counts its last one.
func countLines(b []byte) int {
	if len(b) == 0 {
		return 0
	}
	n := bytes.Count(b, []byte{'\n'})
	if b[len(b)-1] != '\n' {
		n++
	}
	return n
}

func copyFile(src, dst string) error {
	data, err := os.ReadFile(src)
	if err != nil {
		return err
	}
	return os.WriteFile(dst, data, 0o644)
}
