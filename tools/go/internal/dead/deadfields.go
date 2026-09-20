package dead

import (
	"bytes"
	"regexp"
	"sort"

	"slimvim.local/tools/internal/cutil"
)

// fieldRe is `type name;` or `type name[...];` -- one declarator, which is
// this file's shape everywhere.  A bitfield (`int x : 1;`), a function pointer
// and an anonymous member all fail to match, which is the intent.
var fieldRe = regexp.MustCompile(`^([A-Za-z_][\w \t]*?[ \t\*])([A-Za-z_]\w*)[ \t]*(\[[^;]*\])?[ \t]*;$`)

var (
	structHead   = regexp.MustCompile(`^\s*(typedef\s+)?(static\s+)?(struct|union)\b`)
	initialiser  = regexp.MustCompile(`\b([A-Za-z_]\w*)\s+\w+\s*(?:\[[^\]]*\])?\s*=\s*\{`)
	designatedRe = regexp.MustCompile(`\.\s*\w+\s*=`)
)

// FieldCand is one removable field declaration: the line's byte span, its
// name, and the definition it belongs to.
type FieldCand struct {
	Start, End int
	Name       string
	Def        int
}

// DeadFields finds struct and union members nothing outside a type definition
// names.  gcc has no warning for one, in either direction, so this is the only
// sweep for them.
//
// recoverable reports that the tool refused: removing a field moves the ones
// after it, and until the editor can no longer read a swap file, block zero
// and the memfile's pages are a DISK FORMAT -- a field nothing in the code
// reads is still a field another vim wrote.  ml_recover() is what reads them,
// so its presence is the question, asked of the file rather than of a phase
// number.
func DeadFields(text []byte) (cands []FieldCand, recoverable bool) {
	if cutil.HasDefinition(text, "ml_recover") {
		return nil, true
	}
	b := cutil.Blank(text)
	defs := Definitions(text, b)

	inside := make([]bool, len(text))
	for _, d := range defs {
		for i := d.Start; i < d.End && i < len(inside); i++ {
			inside[i] = true
		}
	}
	outside := map[string]bool{}
	for _, loc := range identRe.FindAllIndex(b, -1) {
		if !inside[loc[0]] {
			outside[string(b[loc[0]:loc[1]])] = true
		}
	}

	for idx, d := range defs {
		body := text[d.Start:d.End]
		if !structHead.Match(body) {
			continue
		}
		pos := d.Start
		for _, line := range bytes.Split(body, []byte{'\n'}) {
			ls, le := pos, pos+len(line)
			pos = le + 1
			t := trimSpace(line)
			if len(t) == 0 || bytes.IndexByte(t, '(') >= 0 || bytes.HasPrefix(t, []byte("//")) {
				continue
			}
			m := fieldRe.FindSubmatch(t)
			if m == nil || typeKeywords[string(m[2])] {
				continue
			}
			if outside[string(m[2])] {
				continue
			}
			cands = append(cands, FieldCand{ls, le + 1, string(m[2]), idx})
		}
	}

	// A POSITIONAL INITIALISER NAMES NO FIELD AT ALL.
	// `static termrequest_T crv_status = {STATUS_GET, -1};` fills two fields
	// and mentions neither, so the second looks dead by the rule above and
	// removing it leaves "excess elements in struct initializer" -- a warning
	// and not an error, which means a sweep keyed on errors would have shipped
	// it.  So a type ever initialised WITHOUT designators keeps all its
	// fields; a designated initialiser is fine, since it names what it sets.
	//
	// One pass, not one per type: searching the whole file for every known
	// type name was about 1,500 scans of six megabytes and took five and a
	// half minutes.  Find the initialisers once and look their type up.
	//
	// On the BLANKED text: a '{' inside a string literal is not an
	// initialiser, and Match would refuse it.
	positionalNames := map[string]bool{}
	for _, m := range initialiser.FindAllSubmatchIndex(b, -1) {
		o := bytes.IndexByte(b[m[1]-1:], '{')
		if o < 0 {
			continue
		}
		o += m[1] - 1
		c := cutil.Match(b, o)
		if c > 0 && !designatedRe.Match(text[o:c]) {
			positionalNames[string(b[m[2]:m[3]])] = true
		}
	}
	positional := map[int]bool{}
	for idx, d := range defs {
		for nm := range d.Names {
			if positionalNames[nm] {
				positional[idx] = true
				break
			}
		}
	}
	kept := cands[:0]
	for _, c := range cands {
		if !positional[c.Def] {
			kept = append(kept, c)
		}
	}
	cands = kept

	// Never empty a struct out: that is not C, and typereach owns whole types.
	perDef := map[int]int{}
	for _, c := range cands {
		perDef[c.Def]++
	}
	totalFields := map[int]int{}
	for idx, d := range defs {
		if _, ok := perDef[idx]; !ok {
			continue
		}
		n := 0
		for _, line := range bytes.Split(text[d.Start:d.End], []byte{'\n'}) {
			t := trimSpace(line)
			if len(t) > 0 && bytes.IndexByte(t, '(') < 0 && fieldRe.Match(t) {
				n++
			}
		}
		totalFields[idx] = n
	}
	kept = cands[:0]
	for _, c := range cands {
		if totalFields[c.Def] > perDef[c.Def] {
			kept = append(kept, c)
		}
	}
	return kept, false
}

// DeleteFields removes the candidate declarations, back to front.
func DeleteFields(text []byte, cands []FieldCand) []byte {
	order := append([]FieldCand(nil), cands...)
	sort.Slice(order, func(i, j int) bool { return order[i].Start > order[j].Start })
	for _, c := range order {
		text = append(append([]byte{}, text[:c.Start]...), text[c.End:]...)
	}
	return text
}
