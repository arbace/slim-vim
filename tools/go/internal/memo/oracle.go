package memo

import (
	"bytes"
	"fmt"
	"io"
	"os"
	"path/filepath"

	"slimvim.local/tools/internal/pipeline"
)

// Oracle compares a phase boundary against what the last pass produced there.
//
// There are two kinds of recorded boundary and the difference is the whole
// point:
//
//	<tag>N.sha256            a CHECK.  A deterministic run produced it, and a
//	                         pass that verified end to end promoted it.  A
//	                         mismatch is a failure.
//	<tag>N.sha256.advisory   a REPORT.  An agent produced it, and agents are
//	                         not required to be byte-reproducible in the middle
//	                         of a pass -- only the finished product is -- so a
//	                         mismatch here is information, not a verdict.
//
// The promotion is deliberate and one-way: a boundary becomes a hard check
// only after something OUTSIDE it proved the pass still correct.  Recording a
// boundary from the run you are trying to check would make the check agree
// with itself, which is the same mistake as regenerating the reference
// baselines from the current binary.
func Oracle(p pipeline.P, phase, build, oracle string, w io.Writer) error {
	got := filepath.Join(build, p.Tag+phase+".sha256")
	gotData, err := os.ReadFile(got)
	if err != nil {
		fmt.Fprintf(w, "  oracle       %s%s: no digest at %s\n", p.Tag, phase, got)
		return fmt.Errorf("oracle: no digest at %s", got)
	}

	want := filepath.Join(oracle, p.Tag+phase+".sha256")
	advisory := want + ".advisory"

	if wantData, err := os.ReadFile(want); err == nil {
		if bytes.Equal(gotData, wantData) {
			fmt.Fprintf(w, "  %-12s %s%s matches  %s\n", "oracle", p.Tag, phase, short(gotData))
			return nil
		}
		fmt.Fprintf(w, "  %-12s %s%s DIFFERS  got %s, recorded %s\n",
			"oracle", p.Tag, phase, short(gotData), short(wantData))
		fmt.Fprintln(w, "               this boundary is a check, not a report -- explain it.")
		if _, err := os.Stat(want + ".files"); err == nil {
			fmt.Fprintln(w, "               first differing files:")
			printFileDiff(w, want+".files", got+".files")
		}
		return fmt.Errorf("oracle: %s%s differs", p.Tag, phase)
	}

	if advData, err := os.ReadFile(advisory); err == nil {
		if bytes.Equal(gotData, advData) {
			fmt.Fprintf(w, "  %-12s %s%s matches (advisory)  %s\n",
				"oracle", p.Tag, phase, short(gotData))
		} else {
			fmt.Fprintf(w, "  %-12s %s%s differs (advisory, agent-recorded)  %s vs %s\n",
				"oracle", p.Tag, phase, short(gotData), short(advData))
		}
		return nil
	}

	fmt.Fprintf(w, "  %-12s %s%s unrecorded -- nothing to compare against yet\n",
		"oracle", p.Tag, phase)
	return nil
}

func short(b []byte) string {
	if len(b) > 12 {
		return string(b[:12])
	}
	return string(bytes.TrimRight(b, "\n"))
}

// printFileDiff lists the first ten lines that differ between two manifests.
// The shell uses diff(1); this reports the same thing in the same order for
// the line-set case these manifests are, which is one path per line.
func printFileDiff(w io.Writer, a, b string) {
	al, err1 := os.ReadFile(a)
	bl, err2 := os.ReadFile(b)
	if err1 != nil || err2 != nil {
		return
	}
	as := bytes.Split(al, []byte{'\n'})
	bs := bytes.Split(bl, []byte{'\n'})
	inB := map[string]bool{}
	for _, l := range bs {
		inB[string(l)] = true
	}
	inA := map[string]bool{}
	for _, l := range as {
		inA[string(l)] = true
	}
	n := 0
	for _, l := range as {
		if len(l) > 0 && !inB[string(l)] {
			fmt.Fprintf(w, "                 < %s\n", l)
			if n++; n >= 10 {
				return
			}
		}
	}
	for _, l := range bs {
		if len(l) > 0 && !inA[string(l)] {
			fmt.Fprintf(w, "                 > %s\n", l)
			if n++; n >= 10 {
				return
			}
		}
	}
}
