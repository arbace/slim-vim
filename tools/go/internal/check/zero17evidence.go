package check

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"syscall"
	"time"

	"slimvim.local/tools/internal/harness"
)

type z17Res struct {
	rc       int
	out, err []byte
}

// z17Session starts the editor on pipes, types into it, waits for it to go
// QUIET, and only then sends the signals -- so that what was drawn is a
// property of the editor and not of the machine's load.  argv[0] decides the
// mode, so the binary is staged as `vim`; the child gets a session of its own,
// because a signal sent to a process group reaches the harness too.
func z17Session(binary string, sigs []syscall.Signal) z17Res {
	vim, err := harness.Stage(binary)
	if err != nil {
		return z17Res{rc: -1, out: []byte("STAGE " + err.Error())}
	}
	home, _ := os.MkdirTemp("", "zero17-home-")
	defer os.RemoveAll(home)
	c := exec.Command(vim, "+set paste")
	c.Env = z2Env(home)
	harness.Setsid(c)
	stdin, _ := c.StdinPipe()
	stdout, _ := c.StdoutPipe()
	var errb bytes.Buffer
	c.Stderr = &errb
	if err := c.Start(); err != nil {
		return z17Res{rc: -1, out: []byte("START " + err.Error())}
	}
	stdin.Write([]byte("ihello"))

	chunks := make(chan []byte, 64)
	go func() {
		buf := make([]byte, 65536)
		for {
			n, e := stdout.Read(buf)
			if n > 0 {
				b := make([]byte, n)
				copy(b, buf[:n])
				chunks <- b
			}
			if e != nil {
				close(chunks)
				return
			}
		}
	}()
	var drawn []byte
	last, deadline := time.Now(), time.Now().Add(20*time.Second)
	closed := false
wait:
	for {
		if time.Now().After(deadline) {
			drawn = append(drawn, []byte("\n<<EDITOR NEVER DREW THE TYPED TEXT>>")...)
			break
		}
		select {
		case b, ok := <-chunks:
			if !ok {
				closed = true
				break wait
			}
			drawn = append(drawn, b...)
			last = time.Now()
		case <-time.After(50 * time.Millisecond):
			if bytes.Contains(drawn, []byte("hello")) && time.Since(last) > 300*time.Millisecond {
				break wait
			}
		}
	}
	for _, s := range sigs {
		if syscall.Kill(c.Process.Pid, s) != nil {
			break
		}
	}
	done := make(chan error, 1)
	go func() { done <- c.Wait() }()
	var werr error
	select {
	case werr = <-done:
	case <-time.After(20 * time.Second):
		c.Process.Kill()
		werr = <-done
	}
	if !closed {
		for b := range chunks {
			drawn = append(drawn, b...)
		}
	}
	rc := 0
	if werr != nil {
		rc = exitCode(werr)
	}
	return z17Res{rc, drawn, errb.Bytes()}
}

// z17Marks is the depths the handler reported and whether the ladder ran.
func z17Marks(err []byte) ([]int, bool) {
	var seen []int
	for _, l := range strings.Split(string(err), "\n") {
		if len(l) == 3 && strings.HasPrefix(l, "DT") && l[2] >= '0' && l[2] <= '9' {
			seen = append(seen, int(l[2]-'0'))
		}
	}
	return seen, bytes.Contains(err, []byte("DTLADDER"))
}

// z17Picture is what is compared: the exit, the snapshots, the final screen,
// the bells and stderr.  THE SCREEN AND NOT THE STREAM, because the stream is
// not comparable -- the editor emits `\x1b[?4m`, which draws nothing, at a
// point that depends on its own flush, and two runs of ONE binary differ there.
type z17Pic struct {
	rc    int
	snaps string
	dump  string
	bells int
	err   string
}

func z17Picture(x z17Res) z17Pic {
	s := harness.NewScreen(24, 80)
	s.Feed(x.out)
	var b strings.Builder
	for _, sn := range s.Snaps {
		fmt.Fprintf(&b, "%d,%d,%d\n%s\n", sn.Y, sn.X, sn.Bells, sn.Text)
	}
	return z17Pic{x.rc, b.String(), s.Dump(), s.Bells, string(x.err)}
}

func intsEq(a, b []int) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

func intsRepr(a []int) string {
	if len(a) == 0 {
		return "none"
	}
	s := make([]string, len(a))
	for i, v := range a {
		s[i] = fmt.Sprintf("%d", v)
	}
	return "[" + strings.Join(s, ", ") + "]"
}

func z17Evidence(r *rep, inst, old, bin string) error {
	TERM, HUP := syscall.SIGTERM, syscall.SIGHUP
	var bomb []syscall.Signal
	for i := 0; i < 60; i++ {
		if i%2 == 0 {
			bomb = append(bomb, TERM)
		} else {
			bomb = append(bomb, HUP)
		}
	}
	type job struct {
		name, binary string
		sigs         []syscall.Signal
	}
	var jobs []job
	for i := 0; i < 8; i++ {
		jobs = append(jobs, job{fmt.Sprintf("bomb%d", i), filepath.Join(inst, "in_mark"), bomb})
	}
	for _, n := range []string{"in_forced", "in_nodefer3", "in_nodefer4", "out_forced"} {
		jobs = append(jobs, job{n, filepath.Join(inst, n), []syscall.Signal{TERM}})
	}
	jobs = append(jobs, job{"old_term", old, []syscall.Signal{TERM}}, job{"new_term", bin, []syscall.Signal{TERM}},
		job{"old_hup", old, []syscall.Signal{HUP}}, job{"new_hup", bin, []syscall.Signal{HUP}})
	res := map[string]z17Res{}
	var mu sync.Mutex
	var wg sync.WaitGroup
	for _, j := range jobs {
		wg.Add(1)
		go func(j job) {
			defer wg.Done()
			x := z17Session(j.binary, j.sigs)
			mu.Lock()
			res[j.name] = x
			mu.Unlock()
		}(j)
	}
	wg.Wait()

	var stuck []string
	for n, x := range res {
		if bytes.Contains(x.out, []byte("NEVER DREW")) {
			stuck = append(stuck, n)
		}
	}
	if len(stuck) > 0 {
		sort.Strings(stuck)
		r.say("%s did not draw the typed text within fifteen seconds, so nothing below is a measurement of the editor", strings.Join(stuck, ", "))
		return harness.ErrReported
	}
	var fail, silent []string
	high, twos := 0, 0
	for i := 0; i < 8; i++ {
		seen, ladder := z17Marks(res[fmt.Sprintf("bomb%d", i)].err)
		if len(seen) == 0 {
			silent = append(silent, fmt.Sprintf("bomb%d", i))
		}
		mx := 0
		for _, v := range seen {
			if v > mx {
				mx = v
			}
		}
		if mx > high {
			high = mx
		}
		if mx >= 2 {
			twos++
		}
		if ladder {
			fail = append(fail, fmt.Sprintf("bomb%d reached the `entered >= 3` ladder, so this phase removes code that CAN run and the cut is wrong", i))
		}
	}
	if len(silent) > 0 {
		fail = append(fail, fmt.Sprintf("%s never entered deathtrap() at all, so the maximum below is a measurement of nothing", strings.Join(silent, ", ")))
	}
	if high > 2 {
		fail = append(fail, fmt.Sprintf("the bombardment drove `entered` to %d, and two deadly signals each blocked inside their own handler cannot do that", high))
	}
	for _, wnt := range []struct {
		name   string
		depths []int
		ladder bool
		rc     int
		why    string
	}{
		{"in_forced", []int{1, 2}, false, 1, "the input, forced: `entered` reaches its maximum of 2, the `Vim: Double signal, exiting` arm runs and calls getout(1)"},
		{"in_nodefer3", []int{1, 2, 3}, true, 7, "the SAME source with ONE FIELD changed to SA_NODEFER: the ladder runs and exit(7) ends the process"},
		{"in_nodefer4", []int{1, 2, 3, 4}, true, 8, "and one forced signal further: _exit(8) ends it"},
		{"out_forced", []int{1, 2}, false, 1, "THE OUTPUT, instrumented and forced identically: the same two depths and the same exit"},
	} {
		x := res[wnt.name]
		seen, gotLadder := z17Marks(x.err)
		if !intsEq(seen, wnt.depths) {
			fail = append(fail, fmt.Sprintf("%s reported depths %s, expected %s -- %s", wnt.name, intsRepr(seen), intsRepr(wnt.depths), wnt.why))
		}
		if gotLadder != wnt.ladder {
			verb, must := "did not enter", "not"
			if gotLadder {
				verb = "entered"
			}
			if wnt.ladder {
				must = "enter it"
			}
			fail = append(fail, fmt.Sprintf("%s %s the ladder and it must %s -- %s", wnt.name, verb, must, wnt.why))
		}
		if x.rc != wnt.rc {
			fail = append(fail, fmt.Sprintf("%s exited %d, expected %d -- %s", wnt.name, x.rc, wnt.rc, wnt.why))
		}
	}
	if z17Picture(res["in_forced"]) != z17Picture(res["out_forced"]) {
		fail = append(fail, "the forced double signal draws a different screen with the ladder and without it.  The ladder is not on that path, so it must not be")
	}
	for _, p := range []struct{ sig, tag string }{{"term", "TERM"}, {"hup", "HUP"}} {
		op, np := z17Picture(res["old_"+p.sig]), z17Picture(res["new_"+p.sig])
		for _, what := range []string{"Vim: Caught deadly signal " + p.tag, "Vim: Finished."} {
			if !strings.Contains(op.dump, what) {
				fail = append(fail, fmt.Sprintf("a single SIG%s did not make the binary this phase was handed draw %s, so the comparison below would agree for the wrong reason", p.tag, cutilRepr(what)))
			}
		}
		if op != np {
			var where []string
			if op.rc != np.rc {
				where = append(where, "exit")
			}
			if op.snaps != np.snaps {
				where = append(where, "snapshots")
			}
			if op.dump != np.dump {
				where = append(where, "final screen")
			}
			if op.bells != np.bells {
				where = append(where, "bells")
			}
			if op.err != np.err {
				where = append(where, "stderr")
			}
			fail = append(fail, fmt.Sprintf("a single SIG%s moved, in the %s: %d -> %d.  This phase removes a branch neither signal can reach", p.tag, strings.Join(where, " and the "), op.rc, np.rc))
		}
	}
	if len(fail) > 0 {
		for _, l := range fail {
			r.say("%s", l)
		}
		return harness.ErrReported
	}
	r.say("BOMBARDED: eight concurrent sessions, 60 alternating SIGTERM/SIGHUP each at full speed, every one of them reaching deathtrap() and %d of the eight reaching it twice.  The maximum `entered` ever observed is %d, and DTLADDER never appears", twos, high)
	r.cont("FORCED, and this is the argument in two binaries.  in_forced and in_nodefer3 are the same source differing in ONE `sigaction` FIELD: with `sa_flags = 0` the forced double signal stops at depth 2 and exits 1, and with `SA_NODEFER` it reaches depth 3, enters the ladder and EXITS 7 -- which is exit(7) running.  One forced signal further and it exits 8, which is _exit(8) running")
	r.cont("so the ladder is not dead code that happens to be dead: it is unreachable BECAUSE each deadly signal is blocked inside its own handler and BECAUSE there are only two of them.  `reset_signals()` is INSIDE the ladder and has nothing to do with it")
	r.cont("the output instrumented and forced identically stops at depth 2 and DRAWS THE SAME SCREEN as the input did, and a single SIGTERM and a single SIGHUP give the binary this phase was handed and the one it made the same exit status, the same stderr and the same snapshots, final screen and bell count -- with `Vim: Caught deadly signal` and `Vim: Finished.` required to be ON that screen, so the equality is not two blank screens agreeing.  The comparison is the screen and not the stream because the stream is not comparable: the editor emits `\\x1b[?4m`, which draws nothing, at a point that depends on its own flush, and two runs of ONE binary differ there")
	return nil
}
