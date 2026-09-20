// Package cut holds the phase cutters: the tools a phase program calls to
// remove one named thing from the source.
//
// They share a rule that is WHIM-GOAL.md's first: cut the entry point and let
// the compiler find the rest.  A cutter does not decide what becomes
// unreachable next -- that is the sweep's job -- and it REFUSES on a name it
// cannot find, because a silent miss leaves the thing in place and the report
// would say the work was done.
package cut

import (
	"bytes"
	"fmt"
	"regexp"
	"strings"

	"slimvim.local/tools/internal/cutil"
)

var (
	optRowStart = `(?m)^[ \t]*\{"%s",`
	reachedBy   = regexp.MustCompile(
		`\b(findoption|set_string_option_direct|set_option_value\w*|option_was_set)\s*\(`)
	varOfRow  = regexp.MustCompile(`\(char_u \*\)&(\w+)`)
	pvOfRow   = regexp.MustCompile(`PV_\w+`)
	quotedStr = regexp.MustCompile(`"([^"]+)"`)
)

// DropRow removes options[]'s row for name, found by BRACE MATCHING rather
// than by counting lines: a row may run to several lines and ends at the brace
// that closes its initialiser.
//
// strict turns on the two guards that ask whether the row is really inert;
// local suppresses the PV_ guard, for a phase that has already removed the
// buffer- or window-local field.
func DropRow(text []byte, name string, strict, local bool) ([]byte, bool, error) {
	re := regexp.MustCompile(fmt.Sprintf(optRowStart, regexp.QuoteMeta(name)))
	loc := re.FindIndex(text)
	if loc == nil {
		return text, false, nil
	}
	start := loc[0]

	// THE ROW'S OWN EXTENT, computed before the guards, because every guard
	// asks a question about "this row" and a fixed window of lines would ask
	// it of the wrong text.
	b := cutil.Blank(text)
	open := start + bytes.IndexByte(text[start:], '{')
	rowEnd := cutil.Match(b, open)
	if rowEnd < 0 {
		return text, false, nil
	}

	// A row reached BY NAME is not inert however dead its variable is: a
	// lookup of a row that is not there returns -1, and the caller does not
	// check.
	if strict {
		spellings := quotedStr.FindAllSubmatch(text[start:rowEnd], -1)
		if len(spellings) > 2 {
			spellings = spellings[:2]
		}
		for _, sp := range spellings {
			spelling := string(sp[1])
			hitRe := regexp.MustCompile(`"` + regexp.QuoteMeta(spelling) + `"`)
			for _, hit := range hitRe.FindAllIndex(text, -1) {
				if hit[0] >= start && hit[0] <= rowEnd {
					continue
				}
				line := lineAt(text, hit[0])
				if regexp.MustCompile(`^[ \t]*\{"`).Match(line) {
					continue
				}
				if !reachedBy.Match(line) {
					continue
				}
				return text, false, fmt.Errorf(
					"dropoptions: '%s' is reached by name as \"%s\" here, not only "+
						"through its variable:\n    %s\nA lookup of a row that is not "+
						"there returns -1, and the caller does not check. Remove the "+
						"caller first.", name, spelling, trunc(strings.TrimSpace(string(line)), 100))
			}
		}
	}

	// A row that INITIALISES a variable live code dereferences is not inert
	// either: removing it leaves the variable at its static zero.
	if v := varOfRow.FindSubmatch(text[start:rowEnd]); v != nil && strict {
		nameOfVar := string(v[1])
		word := regexp.MustCompile(`\b` + regexp.QuoteMeta(nameOfVar) + `\b`)
		var reads []string
		for _, o := range word.FindAllIndex(text, -1) {
			if o[0] >= start && o[0] <= rowEnd {
				continue
			}
			line := lineAt(text, o[0])
			if regexp.MustCompile(`^[ \t]*\{"`).Match(line) ||
				regexp.MustCompile(`^[ \t]*\(char_u \*\)&`).Match(line) ||
				regexp.MustCompile(`^static\b[^=]*\b`+regexp.QuoteMeta(nameOfVar)+`;$`).Match(line) {
				continue
			}
			// A mention that is only `&var` is the table's own reference, not
			// a read: strip it and see whether the name is still there.
			bare := regexp.MustCompile(`&\s*`+regexp.QuoteMeta(nameOfVar)+`\b`).
				ReplaceAll(line, nil)
			if !word.Match(bare) {
				continue
			}
			reads = append(reads, trunc(strings.TrimSpace(string(line)), 90))
		}
		if len(reads) > 0 {
			if len(reads) > 3 {
				reads = reads[:3]
			}
			return text, false, fmt.Errorf(
				"dropoptions: '%s' still has readers of %s, so its row is not inert -- "+
					"it is what initialises a variable live code dereferences:\n    %s\n"+
					"Remove the readers first.", name, nameOfVar, strings.Join(reads, "\n    "))
		}
	}

	// A buffer- or window-local option's row ALSO initialises its global.
	if !local {
		if pv := pvOfRow.Find(text[start:rowEnd]); pv != nil && string(pv) != "PV_NONE" {
			return text, false, fmt.Errorf(
				// One space after "startup.", not two.  The Python's string
				// concatenation puts it there, the recorded phase output
				// carries it, and a check that quotes this message would
				// differ on the whitespace alone.
				"dropoptions: '%s' is %s -- a buffer- or window-local option whose row "+
					"also initialises its global.  Removing the row leaves that global "+
					"NULL and the editor segfaults at startup. Remove the local field "+
					"first, in a phase that says it is doing that.", name, pv)
		}
	}

	end := cutil.Match(cutil.Blank(text), open)
	if end < 0 {
		return text, false, fmt.Errorf("dropoptions: the row for %s is not balanced", name)
	}
	end++
	for end < len(text) && (text[end] == ' ' || text[end] == '\t' || text[end] == ',') {
		end++
	}
	if end < len(text) && text[end] == '\n' {
		end++
	}
	out := make([]byte, 0, len(text))
	out = append(out, text[:start]...)
	out = append(out, text[end:]...)
	return out, true, nil
}

// DropOptions removes each named option's row and its modeline_whitelist[]
// entry.
//
// Two places name an option and both are handled, because leaving either
// behind is a different kind of wrong: the options[] row, and
// modeline_whitelist[], the options a modeline is allowed to set -- a name
// left there OUTLIVES the option it names.
func DropOptions(text []byte, names []string, strict, local bool) ([]byte, int, error) {
	for _, name := range names {
		var ok bool
		var err error
		text, ok, err = DropRow(text, name, strict, local)
		if err != nil {
			return nil, 0, err
		}
		if !ok {
			return nil, 0, fmt.Errorf("dropoptions: no options[] row for '%s' -- it has "+
				"already gone, or the table has moved under this phase", name)
		}
	}
	whitelisted := 0
	for _, name := range names {
		pat := regexp.MustCompile(`(?m)^[ \t]*"` + regexp.QuoteMeta(name) + `",\n`)
		n := len(pat.FindAll(text, -1))
		text = pat.ReplaceAll(text, nil)
		whitelisted += n
	}
	return text, whitelisted, nil
}

// lineAt returns the whole line containing the byte at pos, without its
// newline.
func lineAt(text []byte, pos int) []byte {
	start := bytes.LastIndexByte(text[:pos], '\n') + 1
	end := bytes.IndexByte(text[pos:], '\n')
	if end < 0 {
		return text[start:]
	}
	return text[start : pos+end]
}

func trunc(s string, n int) string {
	if len(s) > n {
		return s[:n]
	}
	return s
}
