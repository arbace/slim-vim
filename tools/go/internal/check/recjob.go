package check

import (
	"bytes"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strings"
	"sync"
)

// A RECORDING THAT FAILS MUST SAY WHY, and this is how every check here runs
// one.
//
// The checks started recorders in the background and collected them with a
// bare wait, so a stalled recording -- tools/zpty.py reaching its deadline under
// load, a zmemline case that never returned -- ended the phase with rc 1 and
// NOTHING printed; and where a status was discarded instead, a recording that
// died left a short directory and the comparison after it reported a record
// as MOVED.  The first costs a reader the reason, and the reason is what tells
// a busy machine from a wrong phase.  The second is worse: it is a verdict
// that is true of both outcomes.  So a recorder's output is KEPT rather than
// thrown away, and a failure is reported with which recording it was, its
// exit status and the last lines it wrote.

type recJob struct {
	what string // how the report names it: "the recording of the input"
	argv []string
	out  bytes.Buffer
	err  error
}

// newRec is one recorder, not yet run: `sh tools/zrecord.sh BIN SRC DIR` or
// `sh tools/st.sh zcases|zmemline|ztermcheck BIN DIR`.
func newRec(what string, argv ...string) *recJob { return &recJob{what: what, argv: argv} }

func (j *recJob) run() *recJob {
	c := exec.Command(j.argv[0], j.argv[1:]...)
	c.Stdout, c.Stderr = &j.out, &j.out
	j.err = c.Run()
	return j
}

// recAll runs every job at once and waits for all of them.
func recAll(jobs ...*recJob) {
	var wg sync.WaitGroup
	for _, j := range jobs {
		wg.Add(1)
		go func(j *recJob) { defer wg.Done(); j.run() }(j)
	}
	wg.Wait()
}

func (j *recJob) failed() bool { return j.err != nil }

// tell prints one failed job: what it was, how it ended, what it last said.
func (j *recJob) tell(w io.Writer) {
	how := "could not be started: " + fmt.Sprint(j.err)
	if _, ok := j.err.(*exec.ExitError); ok {
		how = fmt.Sprintf("exited %d", exitCode(j.err))
	}
	fmt.Fprintf(w, "  %-12s %s did not finish -- `%s` %s.  It said:\n", "record", j.what, strings.Join(j.argv[1:], " "), how)
	ls := lines(strings.TrimRight(j.out.String(), "\n"))
	if len(ls) == 0 {
		fmt.Fprintf(w, "               (nothing at all)\n")
	}
	if len(ls) > 12 {
		ls = ls[len(ls)-12:]
	}
	for _, l := range ls {
		fmt.Fprintf(w, "               %s\n", l)
	}
}

// recRefuse reports every failed job and says whether there was one.  A
// caller refuses on true: whatever it would compare next is a comparison
// with a recording that is not whole.
func recRefuse(w io.Writer, jobs ...*recJob) bool {
	bad := false
	for _, j := range jobs {
		if j.failed() {
			j.tell(w)
			bad = true
		}
	}
	if bad {
		fmt.Fprintf(w, "               A recording that did not finish is a reading of the machine or of the\n")
		fmt.Fprintf(w, "               phase, and the lines above are what tells which; nothing after it was run.\n")
	}
	return bad
}

// missingRecords is every record the baseline directory holds and the
// candidate does not -- which is what a recorder that died leaves, and what a
// comparison would otherwise count as MOVED.
func missingRecords(base, cand string) []string {
	var out []string
	es, _ := os.ReadDir(base)
	for _, e := range es {
		if _, err := os.Stat(cand + "/" + e.Name()); err != nil {
			out = append(out, e.Name())
		}
	}
	return out
}

// recCmd is the drop-in for `exec.Command(argv...).Run()` at a recording site:
// the same run, with the output kept, and an error that carries it.  The
// recording is named by the directory it writes, which is its last argument.
func recCmd(argv ...string) error {
	j := newRec("the recording into "+recBase(argv[len(argv)-1]), argv...).run()
	if j.failed() {
		return &recError{j}
	}
	return nil
}

func recBase(p string) string {
	if i := strings.LastIndexByte(p, '/'); i >= 0 {
		return p[i+1:]
	}
	return p
}

type recError struct{ j *recJob }

func (e *recError) Error() string { return e.j.what + " did not finish" }

// recReport tells every failed recording among errs, and says whether any
// error at all is there -- the caller refuses on true, exactly where it used
// to refuse with nothing printed.
func recReport(w io.Writer, errs ...error) bool {
	var jobs []*recJob
	any := false
	for _, e := range errs {
		if e == nil {
			continue
		}
		any = true
		if re, ok := e.(*recError); ok {
			jobs = append(jobs, re.j)
		} else {
			fmt.Fprintf(w, "  %-12s a recording did not finish: %v\n", "record", e)
		}
	}
	recRefuse(w, jobs...)
	return any
}
