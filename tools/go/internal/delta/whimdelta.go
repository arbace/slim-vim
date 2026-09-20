package delta

import (
	"bytes"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"sync"
)

// Baselines is where slim's recorded behaviour lives.
const Baselines = ".reference/baselines"

// WhimDelta is tools/whimdelta.sh: what whim-vim does differently from
// slim-vim, as a check rather than a report.
//
// termMoved, cases and expected are what the phase DECLARED.  The harnesses
// say what actually moved, and the two must be equal -- not contained in, not
// compatible with.  A delta list merely widened to fit is not a check.
func WhimDelta(bin, src string, termMoved bool, cases, expected []string, w io.Writer) error {
	tmp, err := os.MkdirTemp("", "whimdelta.")
	if err != nil {
		return err
	}
	defer os.RemoveAll(tmp)
	fail := false

	// Before anything behavioural: no option global may be left without the
	// row that initialises it.  This is a source question rather than a
	// behavioural one, and it belongs here because what it catches is
	// invisible to every check that follows -- an orphaned global is USED, so
	// no warning names it, and it segfaults only on the one command that
	// reaches it.
	//
	// It runs ALONGSIDE the harnesses rather than before them: it reads the
	// source, they run the binary, and neither waits for the other.
	var orphanOut []byte
	var orphanErr error
	var wg sync.WaitGroup
	wg.Add(1)
	go func() {
		defer wg.Done()
		cmd := exec.Command("python3", "tools/orphanopts.py", src)
		orphanOut, orphanErr = cmd.CombinedOutput()
	}()

	if _, err := os.Stat(filepath.Join(Baselines, "behaviour")); err != nil {
		wg.Wait()
		w.Write(orphanOut)
		fmt.Fprintln(w, "  delta        no slim baselines to compare against")
		if orphanErr != nil {
			return fmt.Errorf("delta: orphaned option globals")
		}
		return nil
	}

	// THE THREE HARNESSES ARE INDEPENDENT, so they run at once.  Each writes
	// into its own directory and reads nothing the others write.  Serially
	// they were 4.4 + 1.7 + 2.2 seconds, which is a third of a phase that does
	// its actual work in two.
	var hwg sync.WaitGroup
	run := func(args ...string) {
		defer hwg.Done()
		exec.Command("python3", args...).Run()
	}
	hwg.Add(3)
	go run("tools/behaviour.py", bin, filepath.Join(tmp, "b"))
	go run("tools/termcheck.py", bin, filepath.Join(tmp, "m"))
	go run("tools/exsweep.py", bin, src, filepath.Join(tmp, "s"))
	hwg.Wait()

	wg.Wait()
	w.Write(orphanOut)
	if orphanErr != nil {
		fail = true
	}

	moved := dirsDiffer(filepath.Join(Baselines, "behaviour"), filepath.Join(tmp, "b"))
	if joinTrail(moved) != joinTrail(cases) {
		fmt.Fprintln(w, "  delta        behaviour cases that moved:")
		fmt.Fprintf(w, "                 got      %s\n", orNone(moved))
		fmt.Fprintf(w, "                 expected %s\n", orNone(cases))
		fail = true
	}

	// The terminal table is declared the same way the behaviour cases are.
	// Until a phase could move it, "expected unchanged" was the whole check;
	// a phase that makes every terminal resolve to one entry has to be able
	// to say so.
	termSame := filesEqual(filepath.Join(Baselines, "ref-term.txt"), filepath.Join(tmp, "m"))
	if termMoved && termSame {
		fmt.Fprintln(w, "  delta        the terminal table was declared to move and did not")
		fail = true
	} else if !termMoved && !termSame {
		fmt.Fprintln(w, "  delta        the terminal table moved, expected unchanged")
		fail = true
	}

	// Field 0, not 1.  The shell says awk '{print $2}' -- but that runs on
	// DIFF's output, where $1 is the < or > marker, so $2 is the first field
	// of the line itself.  Reading the files directly, that is field 0.  The
	// first version took field 1 and reported `exit=0 exit=1` where the
	// command names belonged.
	changed := fieldsDiffer(filepath.Join(Baselines, "ref-exsweep.txt"), filepath.Join(tmp, "s"), 0)
	if joinTrail(changed) != joinTrail(expected) {
		fmt.Fprintln(w, "  delta        Ex commands that moved:")
		fmt.Fprintf(w, "                 got      %s\n", joinTrail(changed))
		fmt.Fprintf(w, "                 expected %s\n", joinTrail(expected))
		fail = true
	}

	if fail {
		fmt.Fprintln(w, "               A phase here may change behaviour, but only the behaviour")
		fmt.Fprintln(w, "               it said it would.  Anything else is a bug, and a delta")
		fmt.Fprintln(w, "               list that is merely widened to fit is not a check.")
		return fmt.Errorf("delta: not exactly as declared")
	}
	if len(cases) > 0 {
		fmt.Fprintf(w, "  delta        exactly as declared: %s; cases: %s\n",
			joinTrail(expected), joinTrail(cases))
	} else {
		fmt.Fprintf(w, "  delta        exactly as declared: %s\n", joinTrail(expected))
	}
	return nil
}

// joinTrail is `sort -u | tr '\n' ' '`: sorted, unique, space-separated, with
// the trailing space tr leaves.  The shell compares these strings directly, so
// the trailing space is part of the value.
func joinTrail(in []string) string {
	if len(in) == 0 {
		return ""
	}
	seen := map[string]bool{}
	var out []string
	for _, s := range in {
		if s != "" && !seen[s] {
			seen[s] = true
			out = append(out, s)
		}
	}
	if len(out) == 0 {
		return ""
	}
	sort.Strings(out)
	return strings.Join(out, " ") + " "
}

func orNone(in []string) string {
	if s := joinTrail(in); s != "" {
		return s
	}
	return "(none)"
}

// dirsDiffer is `diff -rq A B | grep '^Files'`: the names of files present in
// BOTH and differing.  "Only in" lines do not begin with Files, so a file
// present on one side alone is not a moved case.
func dirsDiffer(a, b string) []string {
	var out []string
	filepath.Walk(a, func(path string, info os.FileInfo, err error) error {
		if err != nil || info.IsDir() {
			return nil
		}
		rel, err := filepath.Rel(a, path)
		if err != nil {
			return nil
		}
		other := filepath.Join(b, rel)
		if _, err := os.Stat(other); err != nil {
			return nil
		}
		if !filesEqual(path, other) {
			out = append(out, rel)
		}
		return nil
	})
	return out
}

func filesEqual(a, b string) bool {
	da, ea := os.ReadFile(a)
	db, eb := os.ReadFile(b)
	if ea != nil || eb != nil {
		return false
	}
	return bytes.Equal(da, db)
}

// fieldsDiffer is `diff A B | grep '^[<>]' | awk '{print $field+1}'`: the
// field of every line unique to one side or the other.
//
// Computed as a symmetric difference of line sets rather than by parsing
// diff's output.  For these files -- one line per command, in a stable order
// -- the two agree, and it removes a dependency on which lines diff chooses to
// pair.  The agreement is measured, not assumed.
func fieldsDiffer(a, b string, field int) []string {
	la := lineSet(a)
	lb := lineSet(b)
	var out []string
	add := func(line string) {
		f := strings.Fields(line)
		if field < len(f) {
			out = append(out, f[field])
		}
	}
	for l := range la {
		if !lb[l] {
			add(l)
		}
	}
	for l := range lb {
		if !la[l] {
			add(l)
		}
	}
	return out
}

func lineSet(path string) map[string]bool {
	out := map[string]bool{}
	data, err := os.ReadFile(path)
	if err != nil {
		return out
	}
	for _, l := range strings.Split(string(data), "\n") {
		if l != "" {
			out[l] = true
		}
	}
	return out
}
