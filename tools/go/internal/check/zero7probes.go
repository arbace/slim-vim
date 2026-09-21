package check

import (
	"fmt"
	"os"
	"strings"
	"sync"
	"time"

	"slimvim.local/tools/internal/harness"
)

// READ_IN is what proves the bytes arrived: the keystroke file holds
// `...\x1b:q!\r`, which zscreen draws as `^[:q!^M`, and an Escape can only be
// in the buffer if the file was read -- nothing typed at `:` puts one there.
// The file MESSAGE is not the check: `:1r keys` reads the file and leaves the
// message line blank, measured, so only `:r keys` can be asked for `"keys"`.
const z7ReadIn = "^[:q!^M"

func z7Probes(r *rep, old, bin string) error {
	esc, cr := []byte("\x1b"), []byte("\r")
	quit := []byte("\x1b:q!\r")
	hello := []byte("hello")
	typed := func(seed []byte, keys ...[]byte) ([]string, [][]byte) {
		k := [][]byte{append(append([]byte("i"), seed...), esc...), []byte(":set nopaste\r")}
		return []string{"+set paste"}, append(append(k, keys...), quit)
	}
	var probes []z6Probe
	add := func(name string, a []string, k [][]byte, d bool) {
		probes = append(probes, z6Probe{name, a, k, d})
	}
	// THE ORDER IS THE OUTPUT.  The report names the probes that moved in table
	// order, so a table built in a different sequence passes every assertion
	// and prints a different line -- measured, r_range landing last instead of
	// second.
	one := func(name string, seed []byte, diff bool, keys ...[]byte) {
		a, k := typed(seed, keys...)
		add(name, a, k, diff)
	}
	ab := append(append([]byte("a"), cr...), []byte("b")...)
	ba := append(append([]byte("b"), cr...), []byte("a")...)
	one("r_keys", hello, true, []byte(":r keys\r"))
	one("r_range", ab, true, []byte(":1r keys\r"))
	one("r_missing", hello, true, []byte(":1r nosuch\r"))
	one("r_bang", hello, true, []byte(":r !echo piped\r"))
	one("r_bare", hello, true, []byte(":r\r"))
	one("re_bare", hello, true, []byte(":re\r"))
	one("rea_bare", hello, true, []byte(":rea\r"))
	one("r_forceit", hello, true, []byte(":r!\r"))
	one("r_cat", hello, true, []byte(":r !cat\r"))
	one("cmd_read", []byte("x"), true, []byte(":read\r"))
	one("read_cmd_gone", []byte("x"), true, []byte(":r !echo piped\r"))
	one("filter_gone", ba, false, []byte(":%!sort\r"))
	one("cmd_redo", hello, false, []byte("x"), []byte("u"), []byte(":redo\r"))
	one("cmd_redraw", hello, false, []byte(":redraw\r"))
	one("cmd_registers", hello, false, []byte(":registers\r"))
	one("cmd_reg", hello, false, []byte(":reg\r"))
	one("cmd_undo", hello, false, []byte("x"), []byte(":undo\r"))
	one("cmd_edit", hello, false, []byte(":edit\r"))
	one("cmd_print", hello, false, []byte(":print\r"))
	one("cmd_append", hello, false, []byte(":append\r"), []byte("added\r"), []byte(".\r"))
	one("cmd_insert", hello, false, []byte(":insert\r"), []byte("ins\r"), []byte(".\r"))
	one("cmd_change", hello, false, []byte(":change\r"), []byte("chg\r"), []byte(".\r"))
	one("quit_modified", hello, false, []byte(":q\r"))
	add("quit_bang", []string{"+set paste"},
		[][]byte{append(append([]byte("i"), hello...), esc...), []byte(":set nopaste\r"), []byte(":q!\r")}, false)
	one("editing", append(append([]byte("alpha"), cr...), []byte("beta")...), false,
		[]byte("0dwA-tail\x1b"), []byte("u"), []byte("yyp"))

	type outcome struct {
		name           string
		oT, nT         string
		oS, nS         string
		differ         bool
	}
	outs := make([]outcome, len(probes))
	var wg sync.WaitGroup
	for i, p := range probes {
		wg.Add(1)
		go func(i int, p z6Probe) {
			defer wg.Done()
			ot, os_ := zRecordStream(old, p.args, p.keys, 10*time.Second)
			nt, ns := zRecordStream(bin, p.args, p.keys, 10*time.Second)
			outs[i] = outcome{p.name, ot, nt, os_, ns, p.differ}
		}(i, p)
	}
	wg.Wait()

	var fail, moved, static []string
	by := map[string]outcome{}
	for _, o := range outs {
		by[o.name] = o
		same := o.oT == o.nT
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
	for _, name := range []string{"r_keys", "r_range"} {
		o := by[name]
		if !strings.Contains(o.oT, z7ReadIn) {
			fail = append(fail, fmt.Sprintf("%s: the keystroke file did not reach the buffer on the input binary, so this proves nothing about reading", name))
		}
		if strings.Contains(o.nT, z7ReadIn) {
			fail = append(fail, fmt.Sprintf("%s: the new binary read the file anyway", name))
		}
		if !strings.Contains(o.nT, z6E492) {
			fail = append(fail, fmt.Sprintf("%s: the new binary does not answer E492", name))
		}
	}
	o := by["r_keys"]
	if !strings.Contains(o.oT, `"keys"`) || !strings.Contains(o.oT, "1L,") {
		fail = append(fail, "r_keys: the input binary did not report `\"keys\" ... 1L,` for the file it read")
	}
	if strings.Contains(o.nT, `"keys"`) {
		fail = append(fail, "r_keys: the new binary still names a file it read")
	}
	o = by["r_missing"]
	if !strings.Contains(o.oT, "E484: Can't open file nosuch") {
		fail = append(fail, "r_missing: the input binary did not try to open the file")
	}
	if !strings.Contains(o.nT, z6E492) || strings.Contains(o.nT, "E484") {
		fail = append(fail, "r_missing: E484 has a speaker left")
	}
	// `:r !cmd` went through do_bang() to whim's do_shell() stub, which
	// answered E319 BEFORE running anything -- so E319 on the old binary is
	// also the proof that no shell ran.
	o = by["r_bang"]
	if !strings.Contains(o.oS, "E319: Sorry, the command is not available in this version") {
		fail = append(fail, "r_bang: the input binary did not reach the shell stub, so this proves nothing about `:r !cmd`")
	}
	if strings.Contains(o.nS, "E319") {
		fail = append(fail, "r_bang: the shell stub still speaks")
	}
	if !strings.Contains(o.nS, z6E492) {
		fail = append(fail, "r_bang: `:r !echo piped` is not an unknown command")
	}
	for _, name := range []string{"r_keys", "r_range", "r_missing", "r_bang", "r_bare", "re_bare",
		"rea_bare", "r_forceit", "r_cat", "cmd_read", "read_cmd_gone"} {
		o := by[name]
		if strings.Contains(o.oT, z6E492) {
			fail = append(fail, fmt.Sprintf("%s already answered E492 before this phase, so it proves nothing", name))
		}
		if !strings.Contains(o.nT, z6E492) {
			fail = append(fail, fmt.Sprintf("%s does not answer E492: a removed name has been inherited", name))
		}
	}
	o = by["cmd_read"]
	if !strings.Contains(o.oT, "E32: No file name") || strings.Contains(o.nT, "E32: No file name") {
		fail = append(fail, "cmd_read: E32 was to be the old answer and to be gone now")
	}
	o = by["read_cmd_gone"]
	if !strings.Contains(o.oT, "bells 1") || !strings.Contains(o.nT, "bells 1") {
		fail = append(fail, "read_cmd_gone: the bell was to ring once either side")
	}
	if !strings.Contains(o.oS, "E319") {
		fail = append(fail, "read_cmd_gone: `:r !echo piped` did not reach the shell stub before")
	}
	// `:%!sort` IS THE TRAP IN THE DECLARATION: `:!` has not existed since
	// whim, so this record was ALREADY E492 and is not this phase's to declare.
	o = by["filter_gone"]
	if !strings.Contains(o.oT, z6E492) || !strings.Contains(o.nT, z6E492) {
		fail = append(fail, "filter_gone: `:%!sort` was E492 on both sides before this phase was written, and declaring it would be a delta the phase did not cause")
	}
	if o := by["quit_modified"]; !strings.Contains(o.nT, "E37: No write since last change") {
		fail = append(fail, "quit_modified: :q no longer refuses on a modified buffer, and that is the :q phase's to change")
	}
	for _, p := range []struct{ name, want string }{
		{"cmd_append", "added"}, {"cmd_insert", "ins"}, {"cmd_change", "chg"}, {"editing", "alpha"},
	} {
		if o := by[p.name]; !strings.Contains(o.nT, p.want) {
			fail = append(fail, fmt.Sprintf("%s: the new binary no longer shows %s, so \"it did not move\" is two failures agreeing",
				p.name, cutilRepr(p.want)))
		}
	}
	o = by["cmd_registers"]
	if !strings.Contains(o.nS, "Type Name Content") || !strings.Contains(o.oS, "Type Name Content") {
		fail = append(fail, "cmd_registers: :registers printed no table, so \"it did not move\" is two failures agreeing")
	}
	if len(fail) > 0 {
		for _, l := range fail {
			r.say("%s", l)
		}
		r.cont("the corpus cannot see a file being read -- every case types")
		r.cont("`:read` with no file name and records E32.  These are the only")
		r.cont("probes that can tell a removed command from a changed message.")
		return harness.ErrReported
	}
	r.say("probes: %d moved (%s), %d unchanged", len(moved), strings.Join(moved, " "), len(static))
	r.cont("the input binary read `keys` back and opened `nosuch`; eleven spellings of :r answer E492 and none did before")
	return nil
}

func z7Pty(r *rep, old, bin string) error {
	home, err := os.MkdirTemp("", "zero7-home-")
	if err != nil {
		return err
	}
	session := func(binary string, keys [][]byte, plantName, plantBody string) (string, int, error) {
		d, err := os.MkdirTemp("", "zero7-pty-")
		if err != nil {
			return "", -1, err
		}
		if plantName != "" {
			os.WriteFile(d+"/"+plantName, []byte(plantBody), 0o644)
		}
		text, status, err := harness.Session(binary, nil, keys, "xterm",
			20*time.Second, 600*time.Millisecond, d, z2Env(home), 0, 0)
		return string(text), status, err
	}
	say := func(format string, a ...any) error { r.say(format, a...); return harness.ErrReported }
	// THE RUNNER WRITES THE FILE, because the editor has had no way to write
	// one since phase 6 -- which is what makes this a probe of reading alone.
	rk := [][]byte{[]byte("ityped on a terminal\x1b"), []byte(":r planted.txt\r"), []byte(":q!\r")}
	oT, _, err := session(old, rk, "planted.txt", "FROMTHEDISK\n")
	if err != nil {
		return err
	}
	nT, _, err := session(bin, rk, "planted.txt", "FROMTHEDISK\n")
	if err != nil {
		return err
	}
	if !strings.Contains(oT, "FROMTHEDISK") {
		return say("the input binary read nothing on a pty, so this proves nothing")
	}
	if strings.Contains(nT, "FROMTHEDISK") {
		return say("the new binary read planted.txt on a pty")
	}
	if !strings.Contains(nT, "E492") {
		return say("`:r` on a pty did not answer E492 on the new binary")
	}
	ed := [][]byte{[]byte("ityped here\x1b"), []byte("0dw"), []byte(":set ruler?\r"), []byte(":q!\r")}
	eo, eoRC, err := session(old, ed, "", "")
	if err != nil {
		return err
	}
	en, enRC, err := session(bin, ed, "", "")
	if err != nil {
		return err
	}
	if !strings.Contains(eo, "here") || !strings.Contains(eo, "ruler") {
		return say("the editing pty session did not edit on the input binary")
	}
	if eo != en || eoRC != enRC {
		return say("the editing pty session moved: %d -> %d", eoRC, enRC)
	}
	r.say("pty: the input binary read a planted file into the buffer and this one answers E492; the editing session identical either side")
	return nil
}
