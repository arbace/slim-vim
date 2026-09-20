package memo

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"strconv"
	"strings"

	"slimvim.local/tools/internal/pipeline"
)

// A stage manifest declares the schedule and what constrains it:
//
//	stage A-B             these phases share one sweep
//	need P swept          P's edit needs input a sweep has been over, so P
//	                      must START a stage
//	need P silent         the same, for a phase whose anchor is silent about
//	                      unswept text rather than loud
//	need P swept-inner:K  P needs K's own inner sweep, run just before it in
//	                      the same stage
//	need P compiles       a note: nothing in the schedule can show it
//	apart P K             P's check was measured to fail once K has run, so P
//	                      must see a boundary before K
//
// What cannot be checked here is whether a stage lands on the recorded
// boundary.  That is the oracle, at the end of every stage, and it is not
// optional.
type manifest struct {
	units []string
	reqs  [][]string
}

func readManifest(p pipeline.P) (manifest, bool, error) {
	path := "pipes/" + p.Impl + ".stages"
	f, err := os.Open(path)
	if err != nil {
		return manifest{}, false, nil
	}
	defer f.Close()
	var m manifest
	s := bufio.NewScanner(f)
	s.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	for s.Scan() {
		fields := strings.Fields(s.Text())
		if len(fields) == 0 {
			continue
		}
		switch fields[0] {
		case "stage":
			if len(fields) > 1 {
				m.units = append(m.units, fields[1])
			}
		case "need", "apart":
			if len(fields) >= 3 {
				m.reqs = append(m.reqs, []string{fields[0], fields[1], fields[2]})
			}
		}
	}
	return m, true, s.Err()
}

// Units is the schedule: the stage list, or the plain phase list when a
// pipeline has no manifest.
func Units(p pipeline.P) ([]string, error) {
	m, ok, err := readManifest(p)
	if err != nil {
		return nil, err
	}
	if !ok {
		out := make([]string, 0, len(p.Phases))
		for _, n := range p.Phases {
			out = append(out, strconv.Itoa(n))
		}
		return out, nil
	}
	return m.units, nil
}

func splitUnit(u string) (int, int, error) {
	a, b := u, u
	if i := strings.Index(u, "-"); i >= 0 {
		a, b = u[:i], u[i+1:]
	}
	x, err := strconv.Atoi(a)
	if err != nil {
		return 0, 0, err
	}
	y, err := strconv.Atoi(b)
	if err != nil {
		return 0, 0, err
	}
	return x, y, nil
}

// CheckStages validates the schedule against what the manifest declares.
func CheckStages(p pipeline.P, w io.Writer) error {
	m, ok, err := readManifest(p)
	if err != nil {
		return err
	}
	if !ok {
		return nil
	}

	// Coverage: the ranges, expanded, are the phase list -- exactly once, in
	// order.
	var got []int
	for _, u := range m.units {
		a, b, err := splitUnit(u)
		if err != nil {
			return fmt.Errorf("stages: %s is not a unit", u)
		}
		if a > b {
			fmt.Fprintf(w, "stages: %s runs backwards\n", u)
			return fmt.Errorf("stages: %s runs backwards", u)
		}
		for n := a; n <= b; n++ {
			got = append(got, n)
		}
	}
	if len(got) != len(p.Phases) {
		return stageCoverageErr(p, w)
	}
	for i := range got {
		if got[i] != p.Phases[i] {
			return stageCoverageErr(p, w)
		}
	}

	// Every phase in a multi-phase stage must be an edit AND a check.
	unitOf := map[int]string{}
	firstOf := map[int]bool{}
	for _, u := range m.units {
		a, b, _ := splitUnit(u)
		for n := a; n <= b; n++ {
			unitOf[n] = u
			firstOf[n] = n == a
		}
		if a == b {
			continue
		}
		for n := a; n <= b; n++ {
			if len(p.Parts(strconv.Itoa(n))) != 2 {
				fmt.Fprintf(w, "stages: phase %d is in stage %s but is not an edit and a check\n", n, u)
				return fmt.Errorf("stages: phase %d is not split", n)
			}
		}
	}

	bad := false
	var innerNeeded []string
	for _, r := range m.reqs {
		if r[0] == "apart" {
			if unitOf[atoi(r[1])] == unitOf[atoi(r[2])] {
				fmt.Fprintf(w, "stages: %s and %s must be apart, and share stage %s\n",
					r[1], r[2], unitOf[atoi(r[1])])
				bad = true
			}
			continue
		}
		ph, what := atoi(r[1]), r[2]
		switch {
		case what == "swept" || what == "silent":
			if !firstOf[ph] {
				fmt.Fprintf(w, "stages: %s needs %s input and does not start a stage (%s)\n",
					r[1], what, unitOf[ph])
				bad = true
			}
		case strings.HasPrefix(what, "swept-inner:"):
			k := what[len("swept-inner:"):]
			if !firstOf[ph] && (atoi(k) != ph-1 || unitOf[atoi(k)] != unitOf[ph]) {
				fmt.Fprintf(w, "stages: %s needs %s run just before it, in its stage\n", r[1], k)
				bad = true
			} else if !firstOf[ph] {
				innerNeeded = append(innerNeeded, k)
			}
		}
	}
	if bad {
		return fmt.Errorf("stages: the schedule breaks what the manifest declares")
	}

	// A phase that a later one needs the inner sweep of must still run one.
	for _, k := range innerNeeded {
		path := fmt.Sprintf("pipes/%s%s-edit.sh", p.Impl, k)
		data, err := os.ReadFile(path)
		if err != nil || !strings.Contains(string(data), "tools/sweep.sh") {
			fmt.Fprintf(w, "stages: a later phase needs %s's inner sweep, and %s no longer runs one\n",
				k, path)
			return fmt.Errorf("stages: %s runs no inner sweep", k)
		}
	}
	return nil
}

func stageCoverageErr(p pipeline.P, w io.Writer) error {
	fmt.Fprintf(w, "stages: pipes/%s.stages does not cover the %s phases exactly once, in order\n",
		p.Impl, p.Name)
	return fmt.Errorf("stages: coverage")
}

// UnitOf is `stages.sh --of N`: the unit containing a phase.
func UnitOf(p pipeline.P, n int) (string, error) {
	us, err := Units(p)
	if err != nil {
		return "", err
	}
	for _, u := range us {
		a, b, err := splitUnit(u)
		if err != nil {
			continue
		}
		if n >= a && n <= b {
			return u, nil
		}
	}
	return "", fmt.Errorf("stages: no %s unit contains phase %d", p.Name, n)
}

func atoi(s string) int {
	n, _ := strconv.Atoi(s)
	return n
}
