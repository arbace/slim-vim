package dead

import (
	"bytes"
	"os"
	"os/exec"
	"regexp"
	"sort"
	"strings"

	"slimvim.local/tools/internal/cutil"
)

var enumHead = regexp.MustCompile(`^\s*(typedef\s+)?enum\b`)

// Edit is one enum body rewritten in place.
type Edit struct {
	Start, End int
	Text       string
}

// EnumStats is what analyse reports beside its edits.
type EnumStats struct {
	DeadTotal  int
	Pinned     int
	Stuck      int
	Unpinnable int
}

// LoadVals reads tools/enumvals.sh's output: NAME = VALUE per line.  A missing
// file is not an error -- it means the values have not been needed yet.
func LoadVals(path string) map[string]string {
	vals := map[string]string{}
	data, err := os.ReadFile(path)
	if err != nil {
		return vals
	}
	for _, line := range strings.Split(string(data), "\n") {
		if i := strings.Index(line, "="); i >= 0 {
			vals[strings.TrimSpace(line[:i])] = strings.TrimSpace(line[i+1:])
		}
	}
	return vals
}

// DumpVals runs tools/enumvals.sh, which compiles with -g and reads the
// enumerator values out of DWARF.  The compiler has already done the
// arithmetic, which is why the values are read rather than evaluated: several
// are `1 << 3`, `0x80000000L`, or defined in terms of another.
func DumpVals(src, out string) error {
	return exec.Command("sh", "tools/enumvals.sh", src, out).Run()
}

// AnalyseEnums finds enumerators nothing mentions and the edits that remove
// them without moving the ones that stay.
//
// Deleting one is not free: an enumerator's value is its POSITION, so removing
// one renumbers every implicit one after it, and several enums here are the
// index of a parallel table.  The build is perfectly happy to re-point every
// later entry.  So the first survivor after each deleted run is pinned to the
// value it had, and everything after it follows implicitly as before.
//
// A survivor DWARF has no value for cannot be pinned, and the run before it
// stays.  gcc does not emit every enum, and an unpinned survivor is silently
// renumbered -- which the before-and-after comparison cannot see either,
// because the name is in neither dump.  Keeping the run is the only answer
// known to be right.
func AnalyseEnums(text []byte, vals map[string]string) ([]Edit, EnumStats) {
	b := cutil.Blank(text)
	defs := Definitions(text, b)

	counts := map[string]int{}
	for _, m := range identRe.FindAll(b, -1) {
		counts[string(m)]++
	}

	var edits []Edit
	var st EnumStats

	for _, def := range defs {
		body := text[def.Start:def.End]
		if !enumHead.Match(body) {
			continue
		}
		o := bytes.IndexByte(body, '{')
		c := bytes.LastIndexByte(body, '}')
		if o < 0 || c < 0 {
			continue
		}
		inner := body[o+1 : c]
		parts := cutil.SplitTop(inner, cutil.Blank(inner), ",")

		type entry struct {
			name string
			raw  []byte
		}
		ent := make([]entry, 0, len(parts))
		anyDead := false
		for _, p := range parts {
			nm := ""
			if m := identRe.Find(p); m != nil {
				nm = string(m)
			}
			ent = append(ent, entry{nm, p})
			if nm != "" && counts[nm] == 1 {
				anyDead = true
			}
		}
		if !anyDead {
			continue
		}

		var keep [][]byte
		var run [][]byte
		deleted, keptBack := 0, 0
		for _, e := range ent {
			if e.name != "" && counts[e.name] == 1 {
				run = append(run, e.raw)
				continue
			}
			raw := e.raw
			if e.name != "" && len(run) > 0 && bytes.IndexByte(raw, '=') < 0 {
				val, ok := vals[e.name]
				if !ok {
					keptBack += len(run)
					keep = append(keep, run...)
					run = nil
					keep = append(keep, raw)
					continue
				}
				// Pin it, so nothing after this point moves.
				re := regexp.MustCompile(`\b` + regexp.QuoteMeta(e.name) + `\b`)
				if loc := re.FindIndex(raw); loc != nil {
					pinned := make([]byte, 0, len(raw)+len(val)+3)
					pinned = append(pinned, raw[:loc[1]]...)
					pinned = append(pinned, " = "...)
					pinned = append(pinned, val...)
					pinned = append(pinned, raw[loc[1]:]...)
					raw = pinned
				}
				st.Pinned++
			}
			deleted += len(run)
			run = nil
			keep = append(keep, raw)
		}
		deleted += len(run)

		// SplitTop leaves a trailing empty fragment after the last comma, and
		// a run of deletions can leave fragments that are only whitespace.  An
		// enum rebuilt from those is `enum { }`, which is not C -- so count
		// what actually declares something before deciding anything is left.
		declares := false
		for _, k := range keep {
			if identRe.Match(k) {
				declares = true
				break
			}
		}
		if !declares {
			// Every constant in this enum is dead and it still cannot go: an
			// empty enum is not C and the enum's own type is in use.  Counted
			// apart, because a sweep has to tell "you did not finish" from
			// "this cannot be expressed".
			st.Stuck += deleted + keptBack
			continue
		}
		st.DeadTotal += deleted
		st.Unpinnable += keptBack
		if deleted > 0 {
			edits = append(edits, Edit{
				Start: def.Start + o + 1,
				End:   def.Start + c,
				Text:  string(bytes.Join(keep, []byte{','})),
			})
		}
	}
	return edits, st
}

// ApplyEnumEdits rewrites the enum bodies, back to front.
func ApplyEnumEdits(text []byte, edits []Edit) []byte {
	order := append([]Edit(nil), edits...)
	sort.Slice(order, func(i, j int) bool { return order[i].Start > order[j].Start })
	for _, e := range order {
		out := make([]byte, 0, len(text))
		out = append(out, text[:e.Start]...)
		out = append(out, e.Text...)
		out = append(out, text[e.End:]...)
		text = out
	}
	return text
}

// VerifyEnums dumps DWARF again and requires every name present in both dumps
// to have the value it started with.  That is stronger than the build, which
// compiles a silently renumbered table without complaint.
func VerifyEnums(src, before string) (moved []string, gone int, err error) {
	f, err := os.CreateTemp("", "enumvals.")
	if err != nil {
		return nil, 0, err
	}
	after := f.Name()
	f.Close()
	defer os.Remove(after)
	if err := DumpVals(src, after); err != nil {
		return nil, 0, err
	}
	b, a := LoadVals(before), LoadVals(after)
	for k, v := range b {
		av, ok := a[k]
		if !ok {
			gone++
			continue
		}
		if av != v {
			moved = append(moved, k)
		}
	}
	sort.Strings(moved)
	return moved, gone, nil
}
