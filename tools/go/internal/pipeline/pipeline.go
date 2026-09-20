// Package pipeline is tools/pipeline.sh: the two -- now three -- pipelines,
// and the only place that knows how they differ.
//
//	slim-vim.c = F(upstream@sha)   ten phases, work in upstream/
//	whim-vim.c = G(slim-vim.c)     work in whim/
//	zero-vim.c = H(whim-vim.c)     work in zero/
//
// All three are the same construct -- a phase is a function of the tree it is
// handed, memoized in three tiers -- so the driver, the boundaries, the oracle
// and the synthesiser are shared and this is the whole of the parameterisation.
// A second copy of the memoize would be a second place for it to be subtly
// wrong.
package pipeline

import (
	"bufio"
	"fmt"
	"os"
	"strconv"
	"strings"
)

// P is one pipeline's parameters.
type P struct {
	Name   string // slim, whim, zero
	Tag    string // p, q, r -- the boundary tag
	Impl   string // the pipes/ prefix
	Doc    string
	Work   string // the work directory
	Build  string // where boundaries are recorded
	Source string // the one file a sweep runs on; slim has none
	Delta  string // the declared-delta checker; slim has none
	Phases []int
}

// Get returns the named pipeline.
//
// The boundary tag differs so that one .cache/ can hold all three without a
// key collision, and so that a stray p3 in a whim build is obviously wrong
// rather than plausibly right.
//
// Zero's phase list is NOT written here, and that is measured rather than
// tidy: this file is hashed into every whim stage's key and every whim edit's,
// so a byte changed here re-keys all of whim -- 12 stages and 82 edits.  A
// zero phase list written here would do that every time a zero phase was
// added.  It is the `phases` line of pipes/zero.stages instead, which no key
// reads.
func Get(name string) (P, error) {
	switch name {
	case "", "slim":
		return P{
			Name: "slim", Tag: "p", Impl: "slim", Doc: "SLIM-GOAL.md",
			Work: "upstream", Build: ".build-slim",
			Phases: seq(0, 11),
		}, nil
	case "whim":
		return P{
			Name: "whim", Tag: "q", Impl: "whim", Doc: "WHIM-GOAL.md",
			Work: "whim", Build: ".build-whim", Source: "whim-vim.c",
			Delta: "tools/whimdelta.sh", Phases: seq(0, 82),
		}, nil
	case "zero":
		ph, err := zeroPhases()
		if err != nil {
			return P{}, err
		}
		return P{
			Name: "zero", Tag: "r", Impl: "zero", Doc: "ZERO-GOAL.md",
			Work: "zero", Build: ".build-zero", Source: "zero-vim.c",
			Delta: "tools/zerodelta.sh", Phases: ph,
		}, nil
	}
	return P{}, fmt.Errorf("pipeline: no such pipeline: %s", name)
}

func seq(a, b int) []int {
	out := make([]int, 0, b-a+1)
	for i := a; i <= b; i++ {
		out = append(out, i)
	}
	return out
}

func zeroPhases() ([]int, error) {
	f, err := os.Open("pipes/zero.stages")
	if err != nil {
		return nil, err
	}
	defer f.Close()
	s := bufio.NewScanner(f)
	s.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	for s.Scan() {
		fields := strings.Fields(s.Text())
		if len(fields) < 2 || fields[0] != "phases" {
			continue
		}
		out := make([]int, 0, len(fields)-1)
		for _, f := range fields[1:] {
			n, err := strconv.Atoi(f)
			if err != nil {
				continue
			}
			out = append(out, n)
		}
		return out, nil
	}
	return nil, s.Err()
}

// Parts is tools/phaserun.sh --parts: the programs a unit runs, in order.  A
// unit is a phase N or a stage A-B.  A split phase contributes its edit and
// its check; a whole phase contributes its one file; a phase with neither
// contributes nothing, and a unit with no programs at all is an agent's.
func (p P) Parts(unit string) []string {
	first, last := unit, unit
	if i := strings.Index(unit, "-"); i >= 0 {
		first, last = unit[:i], unit[i+1:]
	}
	a, err1 := strconv.Atoi(first)
	b, err2 := strconv.Atoi(last)
	if err1 != nil || err2 != nil {
		return nil
	}
	var out []string
	for n := a; n <= b; n++ {
		edit := fmt.Sprintf("pipes/%s%d-edit.sh", p.Impl, n)
		check := fmt.Sprintf("pipes/%s%d-check.sh", p.Impl, n)
		whole := fmt.Sprintf("pipes/%s%d.sh", p.Impl, n)
		if exists(edit) && exists(check) {
			out = append(out, edit, check)
		} else if exists(whole) {
			out = append(out, whole)
		}
	}
	return out
}

func exists(p string) bool {
	_, err := os.Stat(p)
	return err == nil
}
