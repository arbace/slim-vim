package check

import (
	"fmt"
	"os"
	"strings"
	"sync"
	"time"

	"slimvim.local/tools/internal/harness"
)

// z5Probes is section 6: 22 command lines recorded on BOTH binaries, six of
// which the declared delta says move.  Each of the six is a way of naming a
// FILE or a STREAM to edit and is required to do that on the OLD binary -- a
// probe that only looks at the new binary passes on a phase that did nothing.
func z5Probes(r *rep, old, bin string) error {
	quit := []byte("\x1b:q!\r")
	esc := []byte("\x1b")
	only := [][]byte{quit}
	alpha := []byte("alpha\rbeta")
	typed := func(seed []byte, keys ...[]byte) ([]string, [][]byte) {
		k := [][]byte{append(append([]byte("i"), seed...), esc...), []byte(":set nopaste\r")}
		return []string{"+set paste"}, append(append(k, keys...), quit)
	}
	ea, ek := typed(alpha, []byte("0dwA-tail\x1b"), []byte("u"), []byte("\x12"), []byte("yyp"))
	probes := []z4Probe{
		{"argv_file", []string{"f.txt"}, only, true},
		{"argv_files", []string{"f.txt", "g.txt"}, only, true},
		// A bare `-` read the keystroke file itself as the buffer, closed fd 0
		// and waited on fd 2 for keys that never came: the old record is
		// `blocked`.
		{"argv_minus", []string{"-"}, [][]byte{[]byte("text on stdin\r"), quit}, true},
		{"argv_minmin", []string{"--"}, only, true},
		{"argv_minmin_plus", []string{"--", "+q!"}, only, true},
		{"argv_plus_file", []string{"+q!", "f.txt"}, only, true},
		{"argv_none", nil, only, false},
		{"argv_plus", []string{"+"}, only, false},
		{"argv_plus_q", []string{"+q!"}, only, false},
		{"argv_plus_nu", []string{"+set nu"}, only, false},
		{"argv_plus_two", []string{"+set nu", "+q!"}, only, false},
		// 'paste' is what every case of the corpus seeds itself under, and it
		// goes in as a +{command}: this phase is where both could have been
		// lost together.
		{"argv_plus_paste", []string{"+set paste"}, [][]byte{[]byte("ihello\x1b"), quit}, false},
		{"argv_T_xterm", []string{"-T", "xterm"}, only, false},
		{"argv_T", []string{"-T"}, only, false},
		{"argv_Txterm", []string{"-Txterm"}, only, false},
		{"argv_T_unknown", []string{"-T", "no-such-term-9x"}, only, false},
		{"argv_R", []string{"-R"}, only, false},
		{"argv_e", []string{"-e"}, only, false},
		{"argv_help", []string{"--help"}, only, false},
		{"argv_version", []string{"--version"}, only, false},
		{"argv_ttyfail", []string{"--ttyfail"}, only, false},
		{"editing", ea, ek, false},
	}
	type outcome struct {
		name   string
		o, n   zRec
		differ bool
	}
	outs := make([]outcome, len(probes))
	var wg sync.WaitGroup
	for i, p := range probes {
		wg.Add(1)
		go func(i int, p z4Probe) {
			defer wg.Done()
			outs[i] = outcome{p.name, zRecord(old, p.args, p.keys), zRecord(bin, p.args, p.keys), p.differ}
		}(i, p)
	}
	wg.Wait()

	var fail, moved, static []string
	by := map[string]outcome{}
	for _, o := range outs {
		by[o.name] = o
		same := o.o.text == o.n.text
		if o.differ && same {
			fail = append(fail, fmt.Sprintf("%s was to move and did not", o.name))
		}
		if !o.differ && !same {
			fail = append(fail, fmt.Sprintf("%s moved and was not to", o.name))
		}
		if same {
			static = append(static, o.name)
		} else {
			moved = append(moved, o.name)
		}
	}
	// Each of the six must have moved FOR ITS OWN REASON, visible on the old
	// binary.
	for _, name := range []string{"argv_file", "argv_minmin", "argv_minmin_plus", "argv_plus_file"} {
		o := by[name]
		if strings.Contains(o.o.text, z5Unk) {
			fail = append(fail, fmt.Sprintf("%s: the input binary already refused it, so this proves nothing", name))
		}
		if !strings.Contains(o.n.text, z5Unk) {
			fail = append(fail, fmt.Sprintf("%s: it is not an unknown option now", name))
		}
	}
	if o := by["argv_file"]; !strings.Contains(o.o.text, "exit 0") || len(o.o.out) < 500 {
		fail = append(fail, fmt.Sprintf("argv_file: the input binary did not open a buffer and draw (%d bytes)", len(o.o.out)))
	}
	o := by["argv_files"]
	if !strings.Contains(o.o.text, "Too many edit arguments") {
		fail = append(fail, "argv_files: the input binary did not answer ME_TOO_MANY_ARGS, so removing that row proves nothing")
	}
	if strings.Contains(o.n.text, "Too many edit arguments") || !strings.Contains(o.n.text, z5Unk) {
		fail = append(fail, "argv_files: the second file argument is not an unknown option now")
	}
	o = by["argv_minus"]
	if !strings.Contains(o.o.text, "blocked") {
		fail = append(fail, "argv_minus: the input binary did not take stdin over, so this proves nothing")
	}
	if strings.Contains(o.n.text, "blocked") || !strings.Contains(o.n.text, z5Unk) {
		fail = append(fail, "argv_minus: a bare `-` is not an unknown option now")
	}
	// `--` and `-- +q!` disagreed with each other before, because `+q!` after
	// `--` was a file name; they agree now, and that is the whole of what `--`
	// did.
	if by["argv_minmin"].o.text == by["argv_minmin_plus"].o.text {
		fail = append(fail, "the input binary read `--` and `-- +q!` the same, so `--` was not ending the options")
	}
	if by["argv_minmin"].n.text != by["argv_minmin_plus"].n.text {
		fail = append(fail, "`--` and `-- +q!` still differ, so something still ends the options")
	}
	for _, name := range []string{"argv_T_xterm", "argv_none"} {
		if o := by[name]; !strings.Contains(o.n.text, "exit 0") || len(o.n.out) < 500 {
			fail = append(fail, fmt.Sprintf("%s: the new binary did not start and draw", name))
		}
	}
	if o := by["argv_plus_q"]; !strings.Contains(o.n.text, "exit 0") {
		fail = append(fail, "argv_plus_q: `+q!` no longer runs and quits")
	}
	if o := by["argv_T"]; !strings.Contains(o.n.text, "Argument missing after") {
		fail = append(fail, "argv_T: a bare -T is not mainerr_arg_missing now")
	}
	if o := by["argv_Txterm"]; !strings.Contains(o.n.text, "Garbage after option argument") {
		fail = append(fail, "argv_Txterm: -Txterm is not ME_GARBAGE now -- the renumbering is wrong")
	}
	if o := by["argv_plus_paste"]; !strings.Contains(o.n.text, "exit 0") || !strings.Contains(o.n.text, "hello") {
		fail = append(fail, "argv_plus_paste: `+set paste` and typing under it no longer work")
	}
	if len(fail) > 0 {
		for _, l := range fail {
			r.say("%s", l)
		}
		r.cont("a probe that cannot fail is not evidence, and one that fails")
		r.cont("differently is not this probe.")
		return harness.ErrReported
	}
	r.say("probes: %d moved (%s), %d unchanged", len(moved), strings.Join(moved, " "), len(static))
	return nil
}

// z5Pty is section 7: a file on the command line on a real terminal, where the
// old binary edits it and the new one refuses before the screen exists.
func z5Pty(r *rep, old, bin string) error {
	home, err := os.MkdirTemp("", "zero5-home-")
	if err != nil {
		return err
	}
	session := func(binary string, args []string, keys [][]byte) (string, int, error) {
		d, err := os.MkdirTemp("", "zero5-pty-")
		if err != nil {
			return "", -1, err
		}
		os.WriteFile(d+"/f.txt", []byte("one\ntwo\nthree\n"), 0o644)
		text, status, err := harness.Session(binary, args, keys, "xterm",
			20*time.Second, 600*time.Millisecond, d, z2Env(home), 0, 0)
		return string(text), status, err
	}
	say := func(format string, a ...any) error { r.say(format, a...); return harness.ErrReported }
	fileKeys := [][]byte{[]byte("Gdd"), []byte(":q!\r")}
	oTxt, _, err := session(old, []string{"f.txt"}, fileKeys)
	if err != nil {
		return err
	}
	nTxt, nRC, err := session(bin, []string{"f.txt"}, fileKeys)
	if err != nil {
		return err
	}
	if !strings.Contains(oTxt, "three") {
		return say("the input binary did not open the file on a pty -- this proves nothing")
	}
	if !strings.Contains(nTxt, "Unknown option argument") {
		return say("the new binary did not refuse the file argument on a pty")
	}
	// THE TWO HARNESSES REPORT DIFFERENT THINGS and the message names the
	// Python's.  ptyrun returns the raw wait status, so mainerr()'s mch_exit(1)
	// arrives there as 256; harness.Session returns the EXIT CODE, which is 1.
	// Shifted rather than compared against 1, so that the refusal says 256 as
	// the shell's does instead of the message and the test disagreeing.
	if nRC<<8 != 256 {
		return say("the refused file argument left wait status %d, expected 256 (exit 1)", nRC)
	}
	edKeys := [][]byte{[]byte("ityped here\x1b"), []byte("0dw"), []byte(":set ruler?\r"), []byte(":q!\r")}
	eo, eoRC, err := session(old, nil, edKeys)
	if err != nil {
		return err
	}
	en, enRC, err := session(bin, nil, edKeys)
	if err != nil {
		return err
	}
	if !strings.Contains(eo, "here") || !strings.Contains(eo, "ruler") {
		return say("the editing pty session did not edit on the input binary")
	}
	if eo != en || eoRC != enRC {
		return say("the editing pty session moved: %d -> %d", eoRC, enRC)
	}
	r.say("pty: the file argument edited by the old binary and refused by the new; the editing session identical either side")
	return nil
}
