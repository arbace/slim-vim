// Package delta is the rule that separates WHIM-GOAL.md from SLIM-GOAL.md.
//
// In slim, any behavioural change is a bug and the check is "nothing moved".
// Here a change is the point, so the check is "exactly this moved" -- the
// phase says which behaviour it is removing, in advance, and the harness
// proves it removed that and nothing else.
//
// "Six commands differ" is a check.  "Some commands differ" is not.
package delta

import (
	"bufio"
	"os"
	"sort"
	"strconv"
	"strings"
)

// Declared is what a delta file says about the phases up to N.
type Declared struct {
	Cmds  []string // commands whose behaviour moved, cumulative
	Cases []string // behaviour cases that moved, cumulative
	Term  bool     // the terminal table moved
	Own   []string // the commands phase N ITSELF declares, in file order
}

// Parse reads a delta file and accumulates every line for a phase <= n.
//
// A command is added by its name and taken out by drop:name; a case by
// case:name and drop:case:name; the terminal table by term-moved.  The lines
// up to a phase are the whole difference from the pipeline's baselines at that
// phase, and so contain every earlier phase's -- which is why a stage checks
// only its LAST phase's.
//
// Own is phase N's own words, in file order and not sorted, because phase 80's
// edit reads its table cut from there and order is part of the answer.
func Parse(path string, n int) (Declared, error) {
	f, err := os.Open(path)
	if err != nil {
		return Declared{}, err
	}
	defer f.Close()

	cmds := map[string]bool{}
	cases := map[string]bool{}
	var d Declared
	phase := 0

	s := bufio.NewScanner(f)
	s.Buffer(make([]byte, 0, 64*1024), 4*1024*1024)
	for s.Scan() {
		line := s.Text()
		t := strings.TrimLeft(line, " \t")
		if strings.HasPrefix(t, "#") || strings.TrimSpace(line) == "" {
			continue
		}
		fields := strings.Fields(line)
		i := 0
		if line[0] >= '0' && line[0] <= '9' {
			if v, err := strconv.Atoi(fields[0]); err == nil {
				phase = v
			}
			i = 1
		}
		if phase > n {
			continue
		}
		for ; i < len(fields); i++ {
			w := fields[i]
			if phase == n && !strings.HasPrefix(w, "case:") &&
				!strings.HasPrefix(w, "drop:") && w != "term-moved" {
				d.Own = append(d.Own, w)
			}
			switch {
			case w == "term-moved":
				d.Term = true
			case strings.HasPrefix(w, "drop:case:"):
				delete(cases, w[len("drop:case:"):])
			case strings.HasPrefix(w, "drop:"):
				delete(cmds, w[len("drop:"):])
			case strings.HasPrefix(w, "case:"):
				cases[w[len("case:"):]] = true
			default:
				cmds[w] = true
			}
		}
	}
	if err := s.Err(); err != nil {
		return Declared{}, err
	}

	d.Cmds = sortedKeys(cmds)
	d.Cases = sortedKeys(cases)
	return d, nil
}

func sortedKeys(m map[string]bool) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}
