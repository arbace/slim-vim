package harness

import (
	"regexp"
	"strconv"
)

// The two facts about the memline corpus that zero phase 40 sizes against the
// editor's block arithmetic.  tools/zmemline.py states them as LINE_BYTES and
// SIZES; the table here was transcribed flat, so both are READ BACK out of it
// rather than written a second time -- a number restated beside a table is a
// number that can disagree with it.

// ZmemLineBytes is what one line of the corpus costs the text layer: the seed
// line every case types first, without its `i` and its Escape.
func ZmemLineBytes() int {
	seed := zmemCases[0].keys[0]
	return len(seed) - 2
}

var zmemReplay = regexp.MustCompile(`^(\d+)@q$`)

// ZmemSizes is every size the cases build, in case order: recording the macro
// makes the second line, so `N@q` leaves N+2.
func ZmemSizes() []int {
	var out []int
	for _, c := range zmemCases {
		for _, k := range c.keys {
			if m := zmemReplay.FindSubmatch(k); m != nil {
				n, _ := strconv.Atoi(string(m[1]))
				out = append(out, n+2)
				break
			}
		}
	}
	return out
}

// ZmemCaseCount is len(CASES).
func ZmemCaseCount() int { return len(zmemCases) }
