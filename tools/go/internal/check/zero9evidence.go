package check

import (
	"fmt"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"

	"slimvim.local/tools/internal/harness"
)

// z9Sessions are the eight adversarial ways back into readfile() there were.
// NAMING A BUFFER AFTER A FILE THAT EXISTS is the shape of all of them: `:file`
// sets b_ffname, and open_buffer()'s outer arm was `if (curbuf->b_ffname !=
// NULL)`.  So each gives the buffer a real name and then asks the editor for
// something that used to load it.
func z9Sessions() []struct {
	name string
	keys [][]byte
} {
	esc := []byte("\x1b")
	quit := []byte("\x1b:q!\r")
	seed := [][]byte{append([]byte("ialpha"), esc...), []byte(":set nopaste\r")}
	named := append(append([][]byte{}, seed...), []byte(":file /etc/hostname\r"))
	with := func(base [][]byte, extra ...[]byte) [][]byte {
		out := append([][]byte{}, base...)
		return append(append(out, extra...), quit)
	}
	return []struct {
		name string
		keys [][]byte
	}{
		{"file_then_G", with(named, []byte("G"))},
		{"file_then_ins", with(named, []byte("ihi\x1b"), []byte("u"))},
		{"file_bdelete", with(named, []byte(":bdelete\r"))},
		{"file_reg_pct", with(named, []byte(`"%p`))},
		{"new_window", with(seed, []byte(":new\r"))},
		{"ball", with(seed, []byte(":ball\r"))},
		{"buffer_1", with(seed, []byte(":buffer 1\r"))},
		{"reg_hash", with(seed, []byte(`"#p`))},
	}
}

// z9Evidence is sections 6, 7 and 8: the instrumented pair, the two recordings
// compared directly, and the cases that must not move being shown to work.
func z9Evidence(r *rep, tmp, inst, state, f, old, bin string) error {
	stop := func(format string, a ...any) error { r.say(format, a...); return harness.ErrReported }
	rec := func(binary, src, out string) error {
		return exec.Command("sh", "tools/zrecord.sh", binary, src, out).Run()
	}
	var wg sync.WaitGroup
	errs := make([]error, 4)
	jobs := []struct{ bin, src, out string }{
		{filepath.Join(inst, "probe"), filepath.Join(inst, "probe.c"), filepath.Join(tmp, "REC.probe")},
		{filepath.Join(inst, "ctl"), filepath.Join(inst, "ctl.c"), filepath.Join(tmp, "REC.ctl")},
		{filepath.Join(state, "old"), filepath.Join(state, "old.c"), filepath.Join(tmp, "REC.old")},
		{bin, f, filepath.Join(tmp, "REC.new")},
	}
	for i, j := range jobs {
		wg.Add(1)
		go func(i int, j struct{ bin, src, out string }) {
			defer wg.Done()
			errs[i] = rec(j.bin, j.src, j.out)
		}(i, j)
	}
	wg.Wait()
	for _, e := range errs {
		if e != nil {
			return stop("a harness failed on one of the four recordings")
		}
	}

	probeWith, _ := marked(filepath.Join(tmp, "REC.probe"), z9Mark)
	total := len(walkFiles(filepath.Join(tmp, "REC.probe")))
	ctlWith, ctlQuiet := marked(filepath.Join(tmp, "REC.ctl"), z9Mark)
	// THE COUNT IS REPORTED AND NOT PINNED.  zero phase 40 added a sixth part
	// to a recording and this phase once said `not the 106 this phase counted`
	// at a corpus that had grown on purpose.
	if total < 100 {
		r.say("a recording is %d files, and a comparison of two things", total)
		r.cont("nothing wrote passes.  The COUNT is reported and not pinned:")
		r.cont("zero phase 40 added a sixth part to a recording and this")
		r.cont("phase said `not the 106 this phase counted` at a corpus that")
		r.cont("had grown on purpose.  What is asserted below is the SHAPE --")
		r.cont("0 marked, and the control marked everywhere but the two")
		r.cont("records that keep what a pty drew rather than stderr.")
		return harness.ErrReported
	}
	if len(probeWith) != 0 {
		r.say("%d of %d records ENTERED readfile() on the binary this phase was handed:", len(probeWith), total)
		for _, p := range probeWith {
			r.cont("  %s", filepath.Join(tmp, "REC.probe", p))
		}
		r.cont("so this phase removes code that CAN run, and the cut is wrong")
		return harness.ErrReported
	}
	quiet := strings.Join(ctlQuiet, " ") + " "
	if len(ctlWith) != total-2 || quiet != "ref-pty.txt ref-term.txt " {
		r.say("the control marked %d of %d records, quiet in: %s", len(ctlWith), total, quiet)
		r.cont("it must be %d, quiet only in ref-pty.txt and ref-term.txt,", total-2)
		r.cont("which keep what was DRAWN on a pty and not stderr.  Without")
		r.cont("that the zero above is a probe that cannot fail.")
		return harness.ErrReported
	}
	r.say("the instrumented pair: readfile() entered by 0 of %d records, open_buffer() by %d of %d through the identical instrument -- that, and nothing else, is what says this phase removed code that could not run",
		total, len(ctlWith), total)

	// The eight adversarial sessions, on both instrumented binaries.
	if err := z9Adversarial(r, filepath.Join(inst, "probe"), filepath.Join(inst, "ctl")); err != nil {
		return err
	}

	// --- 7. the two recordings, compared directly ----------------------------
	if d := diffRQ(filepath.Join(tmp, "REC.old"), filepath.Join(tmp, "REC.new")); len(d) > 0 {
		r.say("the recording moved, and this phase declares nothing at all:")
		for i, l := range d {
			if i >= 10 {
				break
			}
			r.cont("  %s", l)
		}
		return harness.ErrReported
	}
	r.say("two full recordings, the binary this phase was handed and the one it made: identical, all %d records -- 102 screen cases, 111 command rows, 30 command lines, the pty and the terminal table", total)

	// --- 8. the ones that must not move, shown to be DOING something ---------
	return z9Cases(r, old, bin)
}

func z9Adversarial(r *rep, probe, ctl string) error {
	sessions := z9Sessions()
	type res struct{ marks int; blocked bool }
	got := make([][2]res, len(sessions))
	var wg sync.WaitGroup
	for i, s := range sessions {
		for j, b := range []string{probe, ctl} {
			wg.Add(1)
			go func(i, j int, b string, keys [][]byte) {
				defer wg.Done()
				_, _, errb, _, err := harness.ZSession(b, keys, "xterm", []string{"+set paste"}, 24, 80, 8e9)
				if err == harness.ErrBlocked {
					got[i][j] = res{0, true}
					return
				}
				got[i][j] = res{strings.Count(string(errb), z9Mark), false}
			}(i, j, b, s.keys)
		}
	}
	wg.Wait()
	var fail []string
	for i, s := range sessions {
		if got[i][0].blocked || got[i][1].blocked {
			fail = append(fail, fmt.Sprintf("%s blocked, so it says nothing either way", s.name))
		}
		if got[i][0].marks > 0 {
			fail = append(fail, fmt.Sprintf("%s entered readfile() %d times on the binary this phase was handed", s.name, got[i][0].marks))
		}
		if got[i][1].marks == 0 {
			fail = append(fail, fmt.Sprintf("%s never reached open_buffer() either, so it proves nothing: a session that gets nowhere is not an adversary", s.name))
		}
	}
	if len(fail) > 0 {
		for _, l := range fail {
			r.say("%s", l)
		}
		return harness.ErrReported
	}
	r.say("eight adversarial sessions -- :file on a real file and then G, an insert and an undo, :bdelete, the %% register, :new, :ball, :buffer 1 and the # register -- each reached open_buffer() and not one reached readfile()")
	return nil
}

func z9Cases(r *rep, old, bin string) error {
	esc, cr := []byte("\x1b"), []byte("\r")
	quit := []byte("\x1b:q!\r")
	hello := []byte("hello")
	typed := func(seed []byte, keys ...[]byte) ([]string, [][]byte) {
		k := [][]byte{append(append([]byte("i"), seed...), esc...), []byte(":set nopaste\r")}
		return []string{"+set paste"}, append(append(k, keys...), quit)
	}
	type kase struct {
		name string
		args []string
		keys [][]byte
		want string
	}
	var cases []kase
	one := func(name string, seed []byte, want string, keys ...[]byte) {
		a, k := typed(seed, keys...)
		cases = append(cases, kase{name, a, k, want})
	}
	one("editing", append(append([]byte("alpha"), cr...), []byte("beta")...), "alpha",
		[]byte("0dwA-tail\x1b"), []byte("u"), []byte("yyp"))
	one("cmd_file", hello, "[No Name]", []byte(":file\r"))
	one("ctrl_g", append(append([]byte("a"), cr...), []byte("b")...), "[No Name]", []byte("\x07"))
	one("registers", hello, "", []byte("yy"), []byte(":registers\r"))
	one("reg_percent", hello, "hello", []byte("A \x1b\"%p\x1b"))
	one("reg_hash", hello, "hello", []byte("A \x1b\"#p\x1b"))
	one("quit_modified", hello, "E37: No write since last change", []byte(":q\r"))
	cases = append(cases, kase{"quit_bang", []string{"+set paste"},
		[][]byte{append(append([]byte("i"), hello...), esc...), []byte(":set nopaste\r"), []byte(":q!\r")}, ""})

	type out struct{ oT, nT, oS, nS string }
	outs := make([]out, len(cases))
	var wg sync.WaitGroup
	for i, c := range cases {
		wg.Add(1)
		go func(i int, c kase) {
			defer wg.Done()
			ot, os_ := zRecordStream(old, c.args, c.keys, 10e9)
			nt, ns := zRecordStream(bin, c.args, c.keys, 10e9)
			outs[i] = out{ot, nt, os_, ns}
		}(i, c)
	}
	wg.Wait()
	var fail []string
	for i, c := range cases {
		if outs[i].oT != outs[i].nT {
			fail = append(fail, fmt.Sprintf("%s moved, and this phase declares nothing at all", c.name))
		}
		if c.want != "" && !strings.Contains(outs[i].nT, c.want) {
			fail = append(fail, fmt.Sprintf("%s: the new binary no longer shows %s, so \"it did not move\" is two failures agreeing",
				c.name, cutilRepr(c.want)))
		}
		if c.name == "registers" && (!strings.Contains(outs[i].nS, "Type Name Content") || !strings.Contains(outs[i].oS, "Type Name Content")) {
			fail = append(fail, "registers: :registers printed no table, so \"it did not move\" is two failures agreeing")
		}
	}
	if len(fail) > 0 {
		for _, l := range fail {
			r.say("%s", l)
		}
		return harness.ErrReported
	}
	r.say("identical either side and each still doing its own work: an ordinary editing session, :file and CTRL-G (still [No Name]), :registers with its table, the %% and # registers, :q on a modified buffer (still E37) and :q!")
	return nil
}
