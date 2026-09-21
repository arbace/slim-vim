package check

import (
	"fmt"
	"os"
	"regexp"
	"strings"
	"sync"
	"time"

	"slimvim.local/tools/internal/harness"
)

const z10NoName = `"[No Name]" [Modified] 1 line --100%--`

func z10Probes(r *rep, old, bin string) error {
	esc, cr := []byte("\x1b"), []byte("\r")
	quit := []byte("\x1b:q!\r")
	hello := []byte("hello")
	ctrlG, ctrlR, ctrlF, ctrlP := []byte("\x07"), []byte("\x12"), []byte("\x06"), []byte("\x10")
	typed := func(seed []byte, keys ...[]byte) ([]string, [][]byte) {
		k := [][]byte{append(append([]byte("i"), seed...), esc...), []byte(":set nopaste\r")}
		return []string{"+set paste"}, append(append(k, keys...), quit)
	}
	var probes []z6Probe
	one := func(name string, seed []byte, diff bool, keys ...[]byte) {
		a, k := typed(seed, keys...)
		probes = append(probes, z6Probe{name, a, k, diff})
	}
	ab := append(append([]byte("a"), cr...), []byte("b")...)
	cmdOf := func(mid ...[]byte) []byte {
		out := []byte(":")
		for _, m := range mid {
			out = append(out, m...)
		}
		return append(out, cr...)
	}
	one("file_rename", hello, true, []byte(":file NEWNAME\r"), ctrlG)
	one("file_bang", hello, true, []byte(":file! NEWNAME\r"), ctrlG)
	one("cp_missing", []byte("nosuchfile"), true, []byte("0"), cmdOf(ctrlR, ctrlP))
	one("cp_existing", []byte("keys"), false, []byte("0"), cmdOf(ctrlR, ctrlP))
	one("cf_existing", []byte("keys"), false, []byte("0"), cmdOf(ctrlR, ctrlF))
	one("ctrl_g", ab, false, ctrlG)
	one("g_ctrl_g", ab, false, append([]byte("g"), ctrlG...))
	one("registers", hello, false, []byte("yy"), []byte(":registers\r"))
	one("reg_percent", hello, false, []byte("A \x1b\"%p\x1b"))
	one("reg_hash", hello, false, []byte("A \x1b\"#p\x1b"))
	one("cmd_filter", hello, false, []byte(":filter\r"))
	one("cmd_fixdel", hello, false, []byte(":fixdel\r"))
	one("cmd_ls", hello, false, []byte(":ls\r"))
	one("quit_modified", hello, false, []byte(":q\r"))
	probes = append(probes, z6Probe{"quit_bang", []string{"+set paste"},
		[][]byte{append(append([]byte("i"), hello...), esc...), []byte(":set nopaste\r"), []byte(":q!\r")}, false})
	one("editing", append(append([]byte("alpha"), cr...), []byte("beta")...), false,
		[]byte("0dwA-tail\x1b"), []byte("u"), []byte("yyp"))
	// The spellings are appended, as the Python's comprehension is.
	for _, s := range z10Spellings {
		one("spell_"+s, hello, true, []byte(":"+s+"\r"))
	}

	type outcome struct {
		name           string
		oT, nT, oS, nS string
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
	for _, name := range []string{"file_rename", "file_bang"} {
		o := by[name]
		if !strings.Contains(o.oT, `"NEWNAME" [Modified][Not edited] 1 line --100%--`) {
			fail = append(fail, fmt.Sprintf("%s: the input binary did not name the buffer NEWNAME, so this proves nothing about naming one", name))
		}
		if strings.Contains(o.nT, `NEWNAME"`) {
			fail = append(fail, fmt.Sprintf("%s: the new binary named the buffer anyway", name))
		}
		if !strings.Contains(o.nT, z10NoName) {
			fail = append(fail, fmt.Sprintf(`%s: CTRL-G does not answer "[No Name]" now, and that is the only name a buffer has`, name))
		}
		if !strings.Contains(o.nT, z6E492) {
			fail = append(fail, fmt.Sprintf("%s: `:file` is not an unknown command", name))
		}
		if strings.Contains(o.nT, "Not edited") {
			fail = append(fail, fmt.Sprintf("%s: [Not edited] is still shown, and BF_NOTEDITED has no writer left", name))
		}
	}
	o := by["cp_missing"]
	if strings.Contains(o.oT, z6E492) {
		fail = append(fail, "cp_missing: the input binary already put the word on the command line, so it never asked the filesystem and this proves nothing")
	}
	if !strings.Contains(o.nT, "E492: Not an editor command: nosuchfile") {
		fail = append(fail, "cp_missing: CTRL-P does not yield the word under the cursor now")
	}
	const trailing = "E488: Trailing characters: eys"
	for _, name := range []string{"cp_existing", "cf_existing"} {
		o := by[name]
		if !strings.Contains(o.oT, trailing) || !strings.Contains(o.nT, trailing) {
			fail = append(fail, fmt.Sprintf("%s: `keys` did not reach the command line on both binaries, so \"it did not move\" is two failures agreeing", name))
		}
	}
	for _, s := range z10Spellings {
		o := by["spell_"+s]
		if strings.Contains(o.oT, z6E492) {
			fail = append(fail, fmt.Sprintf(":%s already answered E492 before this phase, so it proves nothing", s))
		}
		if !strings.Contains(o.oT, z10NoName) {
			fail = append(fail, fmt.Sprintf(":%s did not report the buffer on the input binary", s))
		}
		if !strings.Contains(o.nT, z6E492) {
			fail = append(fail, fmt.Sprintf(":%s does not answer E492: a removed name has been inherited", s))
		}
	}
	for _, name := range []string{"cmd_filter", "cmd_fixdel"} {
		o := by[name]
		if strings.Contains(o.nT, z6E492) && !strings.Contains(o.oT, z6E492) {
			fail = append(fail, fmt.Sprintf("%s: a surviving command became unknown", name))
		}
	}
	if o := by["ctrl_g"]; !strings.Contains(o.nT, `"[No Name]" [Modified] 2 lines --100%--`) {
		fail = append(fail, "ctrl_g: CTRL-G no longer reports the buffer, and it is what `:file` printed and what must survive")
	}
	if o := by["g_ctrl_g"]; !strings.Contains(o.nT, "Col 1 of 1") {
		fail = append(fail, "g_ctrl_g: `g CTRL-G` printed no count")
	}
	if o := by["quit_modified"]; !strings.Contains(o.nT, "E37: No write since last change") {
		fail = append(fail, "quit_modified: :q no longer refuses on a modified buffer, and that is the :q phase's to change")
	}
	for _, p := range []struct{ name, want string }{
		{"editing", "alpha"}, {"reg_percent", "hello"}, {"reg_hash", "hello"},
	} {
		if o := by[p.name]; !strings.Contains(o.nT, p.want) {
			fail = append(fail, fmt.Sprintf("%s: the new binary no longer shows %s, so \"it did not move\" is two failures agreeing", p.name, cutilRepr(p.want)))
		}
	}
	o = by["registers"]
	if !strings.Contains(o.nS, "Type Name Content") || !strings.Contains(o.oS, "Type Name Content") {
		fail = append(fail, "registers: :registers printed no table, so \"it did not move\" is two failures agreeing")
	}
	for _, p := range []struct{ tag, stream string }{{"the input binary", o.oS}, {"this one", o.nS}} {
		if strings.Contains(p.stream, `"%`) || strings.Contains(p.stream, `"#`) {
			fail = append(fail, fmt.Sprintf("registers: %s printed a `\"%%` or `\"#` line, and neither has been printable since phase 5", p.tag))
		}
	}
	if len(fail) > 0 {
		for _, l := range fail {
			r.say("%s", l)
		}
		r.cont("the corpus cannot see a buffer being named: `cmd_file` types")
		r.cont("`:file` with no argument and records the CTRL-G line for")
		r.cont("[No Name].  `file_rename` is the only probe that can tell a")
		r.cont("removed command from a changed message, and `cp_missing` the")
		r.cont("only one that shows the old binary asking the filesystem.")
		return harness.ErrReported
	}
	r.say("probes: %d moved (%s), %d unchanged", len(moved), strings.Join(moved, " "), len(static))
	r.cont("the input binary answered `\"NEWNAME\" [Modified][Not edited]` to CTRL-G after `:file NEWNAME`, and found `nosuchfile` absent from the disk through CTRL-P; five spellings answer E492 and none did before")
	r.cont("and what did not move is doing its work: CTRL-G and g CTRL-G, :registers with its table and without a `\"%%` or `\"#` line, the %% and # registers, :filter, :fixdel, :ls, :q on a modified buffer and :q!")
	return nil
}

// z10AGO blinds ONE FIELD of the pty editing session, and the field is a WALL
// CLOCK.  The `u` prints `1 change; before #3  N second(s) ago`, which neither
// binary decides: ptyrun writes the keystrokes 0.6 s apart, so the elapsed time
// sits ON the one-second boundary and which side it falls is how busy the
// machine is.  Measured on the phase that owns these keys: 30 of 240 runs
// failed, every one differing in that field ALONE, and 0 of 120 with it
// blinded.  Everything else, `1 change; before #3` included, is still compared
// byte for byte -- and the guard below is what stops the blinding from quietly
// becoming a blinding of nothing.
var z10AGO = regexp.MustCompile(`\d+ seconds? ago`)

func z10Pty(r *rep, old, bin string) error {
	home, err := os.MkdirTemp("", "zero10-home-")
	if err != nil {
		return err
	}
	session := func(binary string, keys [][]byte) (string, int, error) {
		d, err := os.MkdirTemp("", "zero10-pty-")
		if err != nil {
			return "", -1, err
		}
		text, status, err := harness.Session(binary, nil, keys, "xterm",
			20*time.Second, 600*time.Millisecond, d, z2Env(home), 0, 0)
		return string(text), status, err
	}
	rename := [][]byte{[]byte("ityped on a terminal\x1b"), []byte(":file NEWNAME\r"), []byte("\x07"), []byte(":q!\r")}
	edit := [][]byte{[]byte("ialpha\rbeta\x1b"), []byte("ggdwA-tail\x1b"), []byte("u"), []byte(":q!\r")}
	var fail []string
	o, _, err := session(old, rename)
	if err != nil {
		return err
	}
	n, _, err := session(bin, rename)
	if err != nil {
		return err
	}
	if !strings.Contains(o, "NEWNAME") {
		fail = append(fail, "the pty session did not rename the buffer on the input binary, so it proves nothing")
	}
	if strings.Contains(n, `NEWNAME"`) {
		fail = append(fail, "the pty session renamed the buffer on the new binary")
	}
	if !strings.Contains(n, "E492") || !strings.Contains(n, "[No Name]") {
		fail = append(fail, fmt.Sprintf("the pty session does not answer E492 and [No Name]: %s", cutilRepr(tail200(n))))
	}
	eo, eos, err := session(old, edit)
	if err != nil {
		return err
	}
	en, ens, err := session(bin, edit)
	if err != nil {
		return err
	}
	if !strings.Contains(eo, "change; before #") || !z10AGO.MatchString(eo) {
		fail = append(fail, fmt.Sprintf("the undo report with its `N seconds ago` is not in the pty session on the input binary, so blinding the clock blinds nothing and the comparison below is not the one described: %s", cutilRepr(tail200(eo))))
	}
	if z10AGO.ReplaceAllString(eo, "<ago>") != z10AGO.ReplaceAllString(en, "<ago>") || eos != ens {
		fail = append(fail, "an ordinary pty editing session moved, and nothing here may move it")
	}
	if !strings.Contains(en, "alpha") {
		fail = append(fail, "the pty editing session did nothing, so \"identical\" is two failures agreeing")
	}
	if len(fail) > 0 {
		for _, l := range fail {
			r.say("%s", l)
		}
		return harness.ErrReported
	}
	r.say("a real terminal: `:file NEWNAME` then CTRL-G renames on the binary this phase was handed and answers E492 and [No Name] here, and an ordinary editing session is identical either side")
	return nil
}

func tail200(s string) string {
	if len(s) > 200 {
		return s[len(s)-200:]
	}
	return s
}
