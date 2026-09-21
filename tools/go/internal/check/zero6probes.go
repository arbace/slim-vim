package check

import (
	"fmt"
	"os"
	"strings"
	"sync"
	"time"

	"slimvim.local/tools/internal/harness"
)

// z6Probe is a probe whose run directory is kept, because what this phase is
// about is whether a file reached the disk.
type z6Probe struct {
	name   string
	args   []string
	keys   [][]byte
	differ bool
}

const z6E492 = "E492: Not an editor command"

func z6Probes(r *rep, old, bin string) error {
	esc, cr := []byte("\x1b"), []byte("\r")
	quit := append(append([]byte{}, esc...), []byte(":q!\r")...)
	hello := []byte("hello")
	// zcases's shape: type the seed under 'paste', then the real keys.
	typed := func(seed []byte, keys ...[]byte) ([]string, [][]byte) {
		k := [][]byte{append(append([]byte("i"), seed...), esc...), []byte(":set nopaste\r")}
		return []string{"+set paste"}, append(append(k, keys...), quit)
	}
	// The same, for a command that is meant to quit by itself.
	unquit := func(seed []byte, keys ...[]byte) ([]string, [][]byte) {
		k := [][]byte{append(append([]byte("i"), seed...), esc...), []byte(":set nopaste\r")}
		return []string{"+set paste"}, append(k, keys...)
	}
	mk := func(name string, a []string, k [][]byte, d bool) z6Probe { return z6Probe{name, a, k, d} }
	var probes []z6Probe
	add := func(name string, a []string, k [][]byte, d bool) { probes = append(probes, mk(name, a, k, d)) }

	a, k := typed([]byte("WROTEME"), []byte(":w out.txt\r"), []byte(":%d\r"), []byte(":r out.txt\r"))
	add("write_roundtrip", a, k, true)
	a, k = typed(hello, []byte(":w out.txt\r"))
	add("w_named", a, k, true)
	a, k = typed(hello, []byte(":sav out.txt\r"))
	add("sav_named", a, k, true)
	a, k = typed(hello, []byte(":update out.txt\r"))
	add("up_named", a, k, true)
	a, k = unquit(hello, []byte(":wq out.txt\r"))
	add("wq_named", a, k, true)
	a, k = unquit(hello, []byte(":x out.txt\r"))
	add("x_named", a, k, true)
	for _, s := range []struct{ name, cmd string }{
		{"w_bare", ":w\r"}, {"x_bare", ":x\r"}, {"wq_bare", ":wq\r"}, {"up_bare", ":up\r"},
		{"sav_a", ":sav a\r"}, {"w_bang", ":w!\r"}, {"w_append", ":w >>f\r"}, {"w_filter", ":w !cat\r"},
	} {
		a, k = typed(hello, []byte(s.cmd))
		add(s.name, a, k, true)
	}
	a, k = typed([]byte("x"), []byte(":write\r"))
	add("cmd_write", a, k, true)
	a, k = typed([]byte("x"), []byte("ZZ"))
	add("zz_key", a, k, true)
	a, k = typed(hello, []byte(":q\r"))
	add("quit_modified", a, k, false)
	a, k = unquit(hello, []byte(":q!\r"))
	add("quit_bang", a, k, false)
	for _, s := range []struct{ name, cmd string }{
		{"cmd_edit", ":edit\r"}, {"cmd_file", ":file\r"}, {"cmd_read", ":read\r"},
	} {
		a, k = typed(hello, []byte(s.cmd))
		add(s.name, a, k, false)
	}
	a, k = typed(append(append([]byte("b"), cr...), []byte("a")...), []byte(":%!sort\r"))
	add("cmd_filter", a, k, false)
	a, k = typed([]byte("x"), []byte(":s/x/y/\r"))
	add("cmd_subst", a, k, false)
	a, k = typed(hello, []byte("x"), []byte("u"))
	add("key_undo", a, k, false)
	a, k = typed(hello, []byte("\x07"))
	add("key_ctrl_g", a, k, false)
	a, k = typed(append(append([]byte("alpha"), cr...), []byte("beta")...),
		[]byte("0dwA-tail\x1b"), []byte("u"), []byte("yyp"))
	add("editing", a, k, false)

	type outcome struct {
		name           string
		oT, nT         string
		oF, nF         map[string]int64
		differ         bool
	}
	outs := make([]outcome, len(probes))
	var wg sync.WaitGroup
	for i, p := range probes {
		wg.Add(1)
		go func(i int, p z6Probe) {
			defer wg.Done()
			ot, of := zRecordFiles(old, p.args, p.keys, 10*time.Second)
			nt, nf := zRecordFiles(bin, p.args, p.keys, 10*time.Second)
			outs[i] = outcome{p.name, ot, nt, of, nf, p.differ}
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
	// THE SIX THAT WROTE A FILE.  Each must have left one on the OLD binary and
	// none on the new: a probe that only looks at the new binary passes on a
	// phase that did nothing.
	for _, name := range []string{"write_roundtrip", "w_named", "sav_named", "up_named", "wq_named", "x_named"} {
		o := by[name]
		want := int64(6)
		if name == "write_roundtrip" {
			want = 8
		}
		if len(o.oF) != 1 || o.oF["out.txt"] != want {
			fail = append(fail, fmt.Sprintf("%s: the input binary left %s, not a %d-byte out.txt, so this proves nothing about writing",
				name, pyDict(o.oF), want))
		}
		if len(o.nF) > 0 {
			fail = append(fail, fmt.Sprintf("%s: the new binary left %s on the disk", name, pyDict(o.nF)))
		}
	}
	o := by["write_roundtrip"]
	if !strings.Contains(o.oT, "1L, 8B") {
		fail = append(fail, "write_roundtrip: the input binary did not read its own file back")
	}
	if !strings.Contains(o.nT, "E484: Can't open file out.txt") {
		fail = append(fail, "write_roundtrip: the new binary found something to read back")
	}
	for _, name := range []string{"wq_named", "x_named"} {
		o := by[name]
		if !strings.Contains(o.oT, "exit 0") || !strings.Contains(o.nT, "exit 1") {
			fail = append(fail, fmt.Sprintf("%s: the exit status did not go 0 -> 1", name))
		}
	}
	if o := by["sav_a"]; len(o.oF) != 1 || o.oF["a"] != 6 {
		fail = append(fail, fmt.Sprintf("sav_a: the input binary left %s, not a 6-byte `a`", pyDict(o.oF)))
	}
	// THE INHERITANCE CHECK: every spelling answers E492 now and none did
	// before.  `:w` becoming `:winsize` would be invisible to everything else.
	for _, name := range []string{"w_bare", "x_bare", "wq_bare", "up_bare", "sav_a", "w_bang",
		"w_append", "w_filter", "w_named", "sav_named", "up_named", "wq_named", "x_named", "cmd_write"} {
		o := by[name]
		if strings.Contains(o.oT, z6E492) {
			fail = append(fail, fmt.Sprintf("%s already answered E492 before this phase, so it proves nothing", name))
		}
		if !strings.Contains(o.nT, z6E492) {
			fail = append(fail, fmt.Sprintf("%s does not answer E492: a removed name has been inherited", name))
		}
	}
	o = by["cmd_write"]
	if !strings.Contains(o.oT, "E32: No file name") || strings.Contains(o.nT, "E32: No file name") {
		fail = append(fail, "cmd_write: E32 was to be the old answer and to be gone now")
	}
	o = by["zz_key"]
	if !strings.Contains(o.oT, "bells 1") || !strings.Contains(o.nT, "bells 0") {
		fail = append(fail, "zz_key: ZZ rang once before and must ring not at all now")
	}
	if !strings.Contains(o.oT, "E32: No file name") {
		fail = append(fail, "zz_key: ZZ did not run :x on the input binary, so this proves nothing")
	}
	if strings.Contains(o.nT, z6E492) {
		fail = append(fail, "zz_key: ZZ still names a command that does not exist")
	}
	if !strings.Contains(o.nT, "exit 0") {
		fail = append(fail, "zz_key: ZZ no longer quits")
	}
	if o := by["quit_modified"]; !strings.Contains(o.nT, "E37: No write since last change") {
		fail = append(fail, "quit_modified: :q no longer refuses on a modified buffer, and that is the :q phase's to change")
	}
	// `:read` still IS a command -- it answers E32 for want of a file name,
	// exactly as `:write` did before this phase.
	if o := by["cmd_read"]; !strings.Contains(o.nT, "E32: No file name") || strings.Contains(o.nT, z6E492) {
		fail = append(fail, "cmd_read: `:read` is no longer a command, and it is the read phase's")
	}
	if o := by["editing"]; !strings.Contains(o.nT, "alpha") {
		fail = append(fail, "editing: an ordinary edit no longer draws its text")
	}
	if len(fail) > 0 {
		for _, l := range fail {
			r.say("%s", l)
		}
		r.cont("the corpus cannot see writing -- every case types `:write` with")
		r.cont("no file name and records E32.  These are the only probes that")
		r.cont("can tell a removed command from a changed message.")
		return harness.ErrReported
	}
	r.say("probes: %d moved (%s), %d unchanged", len(moved), strings.Join(moved, " "), len(static))
	r.cont("six wrote a file on the input binary and none does now; eight spellings of :w answer E492 and none did before")
	return nil
}

// z6Pty is section 6: `:wq` on a pty is how a person leaves this editor, and
// every probe above went through a pipe.
func z6Pty(r *rep, old, bin string) error {
	home, err := os.MkdirTemp("", "zero6-home-")
	if err != nil {
		return err
	}
	session := func(binary string, keys [][]byte) (string, int, []string, error) {
		d, err := os.MkdirTemp("", "zero6-pty-")
		if err != nil {
			return "", -1, nil, err
		}
		text, status, err := harness.Session(binary, nil, keys, "xterm",
			20*time.Second, 600*time.Millisecond, d, z2Env(home), 0, 0)
		var left []string
		ents, _ := os.ReadDir(d)
		for _, e := range ents {
			left = append(left, e.Name())
		}
		return string(text), status, left, err
	}
	say := func(format string, a ...any) error { r.say(format, a...); return harness.ErrReported }
	wqKeys := [][]byte{[]byte("ityped on a terminal\x1b"), []byte(":wq out.txt\r"), []byte(":q!\r")}
	oT, _, oL, err := session(old, wqKeys)
	if err != nil {
		return err
	}
	nT, _, nL, err := session(bin, wqKeys)
	if err != nil {
		return err
	}
	_ = oT
	if !contains(oL, "out.txt") {
		return say("the input binary wrote nothing on a pty, so this proves nothing")
	}
	if contains(nL, "out.txt") {
		return say("the new binary wrote out.txt on a pty")
	}
	if !strings.Contains(nT, "E492") {
		return say("`:wq` on a pty did not answer E492 on the new binary")
	}
	edKeys := [][]byte{[]byte("ityped here\x1b"), []byte("0dw"), []byte(":set ruler?\r"), []byte(":q!\r")}
	eo, eoRC, eoL, err := session(old, edKeys)
	if err != nil {
		return err
	}
	en, enRC, enL, err := session(bin, edKeys)
	if err != nil {
		return err
	}
	if !strings.Contains(eo, "here") || !strings.Contains(eo, "ruler") {
		return say("the editing pty session did not edit on the input binary")
	}
	if eo != en || eoRC != enRC || strings.Join(eoL, " ") != strings.Join(enL, " ") {
		return say("the editing pty session moved: %d -> %d", eoRC, enRC)
	}
	r.say("pty: `:wq` wrote the file on the input binary and answers E492 here; the editing session identical either side")
	return nil
}
