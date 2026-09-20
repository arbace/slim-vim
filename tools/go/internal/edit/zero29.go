package edit

import (
	"fmt"
	"io"
	"regexp"
	"sort"
	"strconv"
	"strings"

	"slimvim.local/tools/internal/cutil"
)

func init() { register("zero29", Zero29) }

var z29Row = regexp.MustCompile(`^        \{(0x[0-9a-f]+),(0x[0-9a-f]+),(-?\d+),(-?\d+)\},?$`)

// z29Names are the four convertStruct tables this phase merges into two.
var z29Names = []string{"toUpper", "toLower", "musl_toUpper", "musl_toLower"}

type z29Rec struct{ lo, hi, step, off int }

// Zero29 makes the case tables one, and it is the UNION: vim's toUpper[]/toLower[]
// and the musl_to*[] phase 15 vendored disagreed at 97 upper and 96 lower
// codepoints -- vim's newer by ninety-six and musl's knowing `ß -> ẞ` alone --
// and a core with no C library has nothing for 'casemap' to choose between.
func Zero29(text []byte, w io.Writer) ([]byte, error) {
	p := ph{"casemap", w}
	t := string(text)
	before := strings.Count(t, "\n")

	words := func(s, name string) int {
		return len(regexp.MustCompile(`\b`+name+`\b`).FindAllString(s, -1))
	}
	block := func(name string) ([]int, error) {
		m := regexp.MustCompile(`(?ms)^static convertStruct ` + name + `\[\] =\n\{\n(.*?)\n\};\n`).
			FindStringSubmatchIndex(t)
		if m == nil {
			return nil, p.die("there is no `static convertStruct %s[]` in the input, so this phase has "+
				"nothing to merge", name)
		}
		return m, nil
	}
	parse := func(name, body string) ([]z29Rec, error) {
		var rows []z29Rec
		for _, line := range strings.Split(body, "\n") {
			m := z29Row.FindStringSubmatch(line)
			if m == nil {
				return nil, p.die("%s has a row this phase cannot read: %s", name, cutil.PyRepr(line))
			}
			lo, _ := strconv.ParseInt(m[1][2:], 16, 64)
			hi, _ := strconv.ParseInt(m[2][2:], 16, 64)
			step, _ := strconv.Atoi(m[3])
			off, _ := strconv.Atoi(m[4])
			rows = append(rows, z29Rec{int(lo), int(hi), step, off})
		}
		return rows, nil
	}
	emit := func(rows []z29Rec) string {
		out := make([]string, len(rows))
		for i, r := range rows {
			out[i] = fmt.Sprintf("        {0x%x,0x%x,%d,%d}", r.lo, r.hi, r.step, r.off)
		}
		return strings.Join(out, ",\n")
	}
	// expand is {codepoint: target}, EXACTLY as utf_convert() reads the row.  A
	// row with `step < 0` is how this file spells a single codepoint, and it
	// works because `(a - lo) % step` is 0 for every a when step is -1.
	expand := func(name string, rows []z29Rec) (map[int]int, error) {
		out := map[int]int{}
		for _, r := range rows {
			if r.step < 0 {
				if r.lo != r.hi {
					return nil, p.die("%s has a step < 0 row spanning more than one codepoint: "+
						"{0x%x,0x%x,%d,%d}", name, r.lo, r.hi, r.step, r.off)
				}
				out[r.lo] = r.lo + r.off
			} else {
				for c := r.lo; c <= r.hi; c += r.step {
					out[c] = c + r.off
				}
			}
		}
		return out, nil
	}
	ascending := func(name string, rows []z29Rec) error {
		for i := 0; i+1 < len(rows); i++ {
			a, b := rows[i], rows[i+1]
			if a.hi >= b.lo {
				return p.die("%s is not ascending and non-overlapping at {0x%x,0x%x,%d,%d} / "+
					"{0x%x,0x%x,%d,%d}, and utf_convert() binary-searches on rangeEnd",
					name, a.lo, a.hi, a.step, a.off, b.lo, b.hi, b.step, b.off)
			}
		}
		return nil
	}

	// ---- the four tables, parsed and PROVEN to re-emit as the text they came from
	blocks := map[string][]int{}
	rows := map[string][]z29Rec{}
	maps := map[string]map[int]int{}
	for _, n := range z29Names {
		m, err := block(n)
		if err != nil {
			return nil, err
		}
		blocks[n] = m
		r, err := parse(n, t[m[2]:m[3]])
		if err != nil {
			return nil, err
		}
		rows[n] = r
		if emit(r) != t[m[2]:m[3]] {
			return nil, p.die("%s does not re-emit as the text it came from, so the rows this phase "+
				"writes would not be in the file's own shape", n)
		}
		if err := ascending(n, r); err != nil {
			return nil, err
		}
		e, err := expand(n, r)
		if err != nil {
			return nil, err
		}
		maps[n] = e
	}
	var fig []interface{}
	for _, n := range z29Names {
		fig = append(fig, len(rows[n]), len(maps[n]))
	}
	p.sayf("four convertStruct tables read and re-emitted BYTE FOR BYTE as the text they came "+
		"from -- toUpper %d rows / %d codepoints, toLower %d / %d, musl_toUpper %d / %d, "+
		"musl_toLower %d / %d -- so what this phase writes is in the file's shape by "+
		"construction and not by resemblance", fig...)

	// ---- A. the union, computed -----------------------------------------------
	merged := map[string][]z29Rec{}
	type rep struct {
		vimN, muslN string
		nv, nm      int
		muslOnly    []int
		r0, r1      int
	}
	var report []rep
	for _, pr := range []struct{ vimN, muslN string }{
		{"toUpper", "musl_toUpper"}, {"toLower", "musl_toLower"},
	} {
		ev, em := maps[pr.vimN], maps[pr.muslN]
		var clash []int
		for c, v := range ev {
			if m, ok := em[c]; ok && m != v {
				clash = append(clash, c)
			}
		}
		sort.Ints(clash)
		if len(clash) > 0 {
			return nil, p.die("%s and %s map %d codepoints to DIFFERENT characters (U+%04X -> %04X / "+
				"%04X is the first), and a union is not defined there",
				pr.vimN, pr.muslN, len(clash), clash[0], ev[clash[0]], em[clash[0]])
		}
		var vimOnly, muslOnly []int
		for c := range ev {
			if _, ok := em[c]; !ok {
				vimOnly = append(vimOnly, c)
			}
		}
		for c := range em {
			if _, ok := ev[c]; !ok {
				muslOnly = append(muslOnly, c)
			}
		}
		sort.Ints(vimOnly)
		sort.Ints(muslOnly)
		for _, c := range muslOnly {
			for _, r := range rows[pr.vimN] {
				if r.lo <= c && c <= r.hi {
					return nil, p.die("%s already has a row covering U+%04X ({0x%x,0x%x,%d,%d}), so a "+
						"single-codepoint row for it would be unreachable",
						pr.vimN, c, r.lo, r.hi, r.step, r.off)
				}
			}
		}
		newRows := append([]z29Rec{}, rows[pr.vimN]...)
		for _, c := range muslOnly {
			newRows = append(newRows, z29Rec{c, c, -1, em[c] - c})
		}
		sort.SliceStable(newRows, func(i, j int) bool { return newRows[i].lo < newRows[j].lo })
		union := map[int]int{}
		for c, v := range ev {
			union[c] = v
		}
		for c, v := range em {
			union[c] = v
		}
		got, err := expand(pr.vimN, newRows)
		if err != nil {
			return nil, err
		}
		if !z29SameMap(got, union) {
			return nil, p.die("the merged %s does not expand to the union of the two", pr.vimN)
		}
		if err := ascending(pr.vimN, newRows); err != nil {
			return nil, err
		}
		merged[pr.vimN] = newRows
		report = append(report, rep{pr.vimN, pr.muslN, len(vimOnly), len(muslOnly),
			muslOnly, len(rows[pr.vimN]), len(newRows)})
	}
	for _, r := range report {
		only := make([]string, len(r.muslOnly))
		for i, c := range r.muslOnly {
			only[i] = fmt.Sprintf("U+%04X", c)
		}
		shown := strings.Join(only, " ")
		if shown == "" {
			shown = "none"
		}
		p.sayf("%s: %d codepoints %s maps and %s does not -- they ARRIVE on the non-internal "+
			"arm -- and %d the other way (%s), which ARRIVE on the default one; 0 where both "+
			"map and disagree.  %d rows -> %d",
			r.vimN, r.nv, r.vimN, r.muslN, r.nm, shown, r.r0, r.r1)
	}
	for _, n := range []string{"toUpper", "toLower"} {
		oldText := t[blocks[n][0]:blocks[n][1]]
		if strings.Count(t, oldText) != 1 {
			return nil, p.die("%s[] is not in the file exactly once", n)
		}
		t = strings.Replace(t, oldText,
			fmt.Sprintf("static convertStruct %s[] =\n{\n%s\n};\n", n, emit(merged[n])), 1)
	}

	// ---- B. musl's two tables, deleted with the blank line above each ---------
	i := strings.Index(t, "static convertStruct musl_toUpper[] =")
	j := strings.Index(t[strings.Index(t, "static convertStruct musl_toLower[] ="):], "\n};\n") +
		strings.Index(t, "static convertStruct musl_toLower[] =") + 4
	if i < 2 || t[i-2:i] != "\n\n" {
		return nil, p.die("musl_toUpper[] does not open on its own paragraph, so the deletion would " +
			"leave a blank line behind or take one it should not")
	}
	cut := t[i-1 : j]
	if !strings.Contains(cut, "musl_toLower") || strings.Count(cut, "static convertStruct") != 2 {
		return nil, p.die("the span between musl_toUpper[] and the end of musl_toLower[] is not the " +
			"two tables and nothing else")
	}
	t = t[:i-1] + t[j:]
	p.sayf("musl_toUpper[] and musl_toLower[] deleted, %d lines including the blank line above "+
		"each -- one span, from the first table's head to the second's closing brace, and "+
		"it holds exactly two `static convertStruct`", strings.Count(cut, "\n"))

	// ---- C. the two wrappers, repointed ---------------------------------------
	for _, wp := range []struct{ w, table string }{
		{"musl_towupper", "toUpper"}, {"musl_towlower", "toLower"},
	} {
		oldCall := fmt.Sprintf("    return utf_convert(a, musl_%s, (int)sizeof(musl_%s));\n", wp.table, wp.table)
		newCall := fmt.Sprintf("    return utf_convert(a, %s, (int)sizeof(%s));\n", wp.table, wp.table)
		if strings.Count(t, oldCall) != 1 {
			return nil, p.die("%s() does not read musl_%s[] in the one shape this phase rewrites",
				wp.w, wp.table)
		}
		t = strings.ReplaceAll(t, oldCall, newCall)
	}
	p.say("musl_towupper() and musl_towlower() now read toUpper[] and toLower[] -- the two " +
		"wrappers STAY, being what the non-internal arm of utf_toupper()/utf_tolower() " +
		"calls and what the two dead `if (c >= 0x100)` arms of vim_toupper()/vim_tolower() " +
		"name; deleting them is a different idea")

	// ---- what must be true of the result --------------------------------------
	for _, gone := range []string{"musl_toUpper", "musl_toLower"} {
		if words(t, gone) > 0 {
			return nil, p.die("%s survives", gone)
		}
	}
	for _, kw := range []struct {
		keep string
		want int
	}{{"musl_towupper", 4}, {"musl_towlower", 4}} {
		if k := words(t, kw.keep); k != kw.want {
			return nil, p.die("%s has %d mentions, expected %d -- its prototype, its definition, the one "+
				"live call and the dead one", kw.keep, k, kw.want)
		}
	}
	for _, n := range []string{"toUpper", "toLower"} {
		if k := words(t, n); k != 5 {
			return nil, p.die("%s is named %d times, expected 5 -- its definition, utf_to%s()'s "+
				"utf_convert call and the wrapper's", n, k, strings.ToLower(n[2:]))
		}
	}
	if k := zCalls([]byte(t), "utf_convert"); k != 6 {
		return nil, p.die("utf_convert is called %d times, expected the same 6 -- this phase moves no "+
			"call, it changes what two of them read", k)
	}
	L := strings.Split(t, "\n")
	var directives []int
	for i, l := range L {
		if strings.HasPrefix(strings.TrimLeft(l, " \t"), "#") {
			directives = append(directives, i)
		}
	}
	inc := regexp.MustCompile(`^ *# *include `)
	okd := len(directives) == 11
	for _, i := range directives {
		if !inc.MatchString(L[i]) {
			okd = false
		}
	}
	if !okd {
		return nil, p.die("the directives are no longer eleven #includes and nothing else")
	}
	p.sayf("musl_toUpper and musl_toLower at 0 mentions, musl_towupper and musl_towlower at "+
		"4 each, toUpper and toLower at 5 each, utf_convert at the same 6 calls, and the "+
		"first of eleven #includes -- the boundary -- is still line %d with no directive "+
		"above it", directives[0]+1)
	p.sayf("the file is %d lines and the input was %d", strings.Count(t, "\n"), before)
	return []byte(t), nil
}

func z29SameMap(a, b map[int]int) bool {
	if len(a) != len(b) {
		return false
	}
	for k, v := range a {
		if w, ok := b[k]; !ok || w != v {
			return false
		}
	}
	return true
}
