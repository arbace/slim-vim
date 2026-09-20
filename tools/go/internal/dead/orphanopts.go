package dead

import (
	"bytes"
	"fmt"
	"io"
	"regexp"
	"sort"
	"strings"
)

// RowFloor is 80, and it was 100.
//
// The parse below is a regex over options[], and a regex that stops matching
// after an edit to the table's shape returns an EMPTY set -- from which every
// global looks orphaned, or none does, depending which way the comparison
// falls.  So the floor is a deliberate number rather than a guard against
// zero, and it is the same number and the same argument as create_cmdidxs.py's
// so the two floors stay one idea.
//
// It was 100 while the smallest table in play was slim's and whim's 116
// distinct option globals.  Zero's phase 12 drops six rows, 102 -> 96, which
// the old floor refused.  zerodelta runs this beside its harnesses, so
// crossing the floor does not fail that phase -- it fails the delta check of
// EVERY zero phase after it, with a message about a table that moved.  Lowered
// in that phase's own commit and never silently; 80 leaves 16 globals of
// margin below zero's 96.
const RowFloor = 80

var (
	optRow    = regexp.MustCompile(`&(p_[a-z0-9_]+)\b`)
	optGlobal = regexp.MustCompile(`(?m)^static\s+(char_u\s*\*|long|int)\s*(p_[a-z0-9_]+)\s*(=[^;]*)?;$`)
)

// OrphanOpts reports option globals left without the row that initialises
// them.
//
// An orphan that is a POINTER is a crash waiting for the right command: it is
// NULL for ever, and the editor segfaults on whatever first dereferences it.
// A non-pointer orphan is reported and tolerated -- the p_ai_nopaste and
// p_tw_nobin save slots are exactly that shape on purpose, and int and long
// orphans read as 0 rather than trapping.
//
// This is a source question rather than a behavioural one, and it belongs
// beside the delta harnesses because what it catches is invisible to all of
// them: an orphaned global is USED, so no warning names it, and it fails only
// on the one command that reaches it.
func OrphanOpts(s []byte, w io.Writer) error {
	i := bytes.Index(s, []byte("static struct vimoption options[]"))
	if i < 0 {
		return fmt.Errorf("orphanopts: options[] is not in this file")
	}
	rel := bytes.Index(s[i:], []byte("\n};"))
	if rel < 0 {
		return fmt.Errorf("orphanopts: options[] is not in this file")
	}
	j := i + rel

	rows := map[string]bool{}
	for _, m := range optRow.FindAllSubmatch(s[i:j], -1) {
		rows[string(m[1])] = true
	}
	if len(rows) < RowFloor {
		return fmt.Errorf("orphanopts: only %d rows parsed -- the table has moved "+
			"and this would pass for the wrong reason", len(rows))
	}

	type orphan struct {
		name  string
		ptr   bool
		sites []string
	}
	var bad []orphan

	for _, m := range optGlobal.FindAllSubmatchIndex(s, -1) {
		typ := string(s[m[2]:m[3]])
		name := string(s[m[4]:m[5]])
		hasInit := m[6] >= 0
		if rows[name] || hasInit {
			continue
		}
		word := regexp.MustCompile(`\b` + regexp.QuoteMeta(name) + `\b`)
		if len(word.FindAll(s, -1)) <= 1 {
			continue // declared and unread; the sweep takes it
		}
		// ANY MENTION AT ALL, not just an explicit dereference.  Counting only
		// dereferences missed 'completeopt' once: a call passed the NULL
		// pointer to something that dereferenced it, and the editor segfaulted
		// before the first keystroke.  A pointer nothing mentions is harmless
		// -- the sweep takes it.  One mentioned at all, with no row to
		// initialise it, is a NULL going somewhere, and the shape of the
		// somewhere is not this tool's business to judge.
		decl := regexp.MustCompile(`^static\b[^=]*\b` + regexp.QuoteMeta(name) + `\s*;`)
		var sites []string
		for _, line := range strings.Split(string(s), "\n") {
			if !word.MatchString(line) {
				continue
			}
			t := strings.TrimSpace(line)
			if decl.MatchString(t) {
				continue
			}
			sites = append(sites, t)
		}
		bad = append(bad, orphan{name, strings.Contains(typ, "*"), sites})
	}

	var quiet []string
	var fatal []orphan
	for _, b := range bad {
		if b.ptr {
			fatal = append(fatal, b)
		} else {
			quiet = append(quiet, b.name)
		}
	}
	sort.Strings(quiet)
	if len(quiet) > 0 {
		fmt.Fprintf(w, "  orphanopts   %d non-pointer orphans read as 0: %s\n",
			len(quiet), strings.Join(quiet, " "))
	}
	for _, f := range fatal {
		plural := "s"
		if len(f.sites) == 1 {
			plural = ""
		}
		fmt.Fprintf(w, "  orphanopts   %s has no row and is a pointer -- NULL for ever, "+
			"%d dereference%s\n", f.name, len(f.sites), plural)
		for _, line := range f.sites {
			if len(line) > 96 {
				line = line[:96]
			}
			fmt.Fprintf(w, "               %s\n", line)
		}
	}
	if len(fatal) > 0 {
		return fmt.Errorf("orphanopts: %d pointer orphans", len(fatal))
	}
	fmt.Fprintln(w, "  orphanopts   every option pointer still has the row that sets it")
	return nil
}
