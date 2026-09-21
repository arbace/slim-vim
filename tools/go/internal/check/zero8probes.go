package check

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"os"
	"os/exec"
	"sort"
	"strings"
	"sync"
	"time"

	"slimvim.local/tools/internal/harness"
)

// z8Spellings are the ten ways to say the five commands, each of which answered
// E37 before and must answer E492 now.  `:en` is the ELEVENTH and is not this
// phase's: enew's shortest abbreviation is three characters.
var z8Spellings = []string{"e", "ed", "edit", "enew", "ex", "vi", "vis", "vie", "view", "visual"}

func z8Probes(r *rep, old, bin string) error {
	esc, cr := []byte("\x1b"), []byte("\r")
	quit := []byte("\x1b:q!\r")
	hello, word := []byte("hello"), []byte("nosuchfile")
	typed := func(seed []byte, keys ...[]byte) ([]string, [][]byte) {
		k := [][]byte{append(append([]byte("i"), seed...), esc...), []byte(":set nopaste\r")}
		return []string{"+set paste"}, append(append(k, keys...), quit)
	}
	var probes []z6Probe
	one := func(name string, seed []byte, diff bool, keys ...[]byte) {
		a, k := typed(seed, keys...)
		probes = append(probes, z6Probe{name, a, k, diff})
	}
	one("edit_keys", hello, true, []byte(":e! keys\r"))
	one("ex_keys", hello, true, []byte(":ex! keys\r"))
	one("visual_keys", hello, true, []byte(":visual! keys\r"))
	one("view_keys", hello, true, []byte(":view! keys\r"), []byte(":set ro?\r"))
	one("enew_bang", hello, true, []byte(":enew!\r"))
	one("key_gf", word, true, []byte("0gf"))
	one("key_gF", word, true, []byte("0gF"))
	one("key_br_f", word, true, []byte("0[f"))
	one("key_brc_f", word, true, []byte("0]f"))
	one("cmd_edit", []byte("x"), true, []byte(":edit\r"))
	one("spell_en", hello, false, []byte(":en\r"))
	one("cmd_earlier", hello, false, []byte("x"), []byte(":earlier\r"))
	one("verbose_ro", hello, false, []byte(":verbose set ro?\r"))
	one("cmd_vglobal", []byte("a1\rb2\ra3"), false, []byte(":v/a/d\r"))
	one("cmd_vmap", hello, false, []byte(":vmap\r"))
	one("cmd_file", hello, false, []byte(":file\r"))
	one("cmd_read", hello, false, []byte(":read keys\r"))
	one("cmd_print", hello, false, []byte(":print\r"))
	one("cmd_append", hello, false, []byte(":append\r"), []byte("added\r"), []byte(".\r"))
	one("cmd_registers", hello, false, []byte(":registers\r"))
	one("ctrl_g", append(append([]byte("a"), cr...), []byte("b")...), false, []byte("\x07"))
	one("quit_modified", hello, false, []byte(":q\r"))
	probes = append(probes, z6Probe{"quit_bang", []string{"+set paste"},
		[][]byte{append(append([]byte("i"), hello...), esc...), []byte(":set nopaste\r"), []byte(":q!\r")}, false})
	one("editing", append(append([]byte("alpha"), cr...), []byte("beta")...), false,
		[]byte("0dwA-tail\x1b"), []byte("u"), []byte("yyp"))
	// THE SPELLINGS COME LAST, because the Python builds them with a list
	// comprehension appended to the literal table -- and the report names the
	// probes that moved in table order.
	for _, s := range z8Spellings {
		one("spell_"+s, hello, true, []byte(":"+s+"\r"))
	}

	type outcome struct {
		name           string
		oT, nT, oS, nS string
		oSn, nSn       int
		differ         bool
	}
	outs := make([]outcome, len(probes))
	var wg sync.WaitGroup
	for i, p := range probes {
		wg.Add(1)
		go func(i int, p z6Probe) {
			defer wg.Done()
			ot, os_, osn := zRecordSnaps(old, p.args, p.keys, 10*time.Second)
			nt, ns, nsn := zRecordSnaps(bin, p.args, p.keys, 10*time.Second)
			outs[i] = outcome{p.name, ot, nt, os_, ns, osn, nsn, p.differ}
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
	for _, name := range []string{"edit_keys", "ex_keys", "visual_keys", "view_keys"} {
		o := by[name]
		if !strings.Contains(o.oT, z7ReadIn) {
			fail = append(fail, fmt.Sprintf("%s: the keystroke file did not reach the buffer on the input binary, so this proves nothing about opening a file", name))
		}
		if strings.Contains(o.nT, z7ReadIn) {
			fail = append(fail, fmt.Sprintf("%s: the new binary opened the file anyway", name))
		}
		if !strings.Contains(o.nT, z6E492) {
			fail = append(fail, fmt.Sprintf("%s: the new binary does not answer E492", name))
		}
		if !strings.Contains(o.oT, `"keys"`) {
			fail = append(fail, fmt.Sprintf("%s: the input binary did not name the file it opened", name))
		}
		if strings.Contains(o.nT, `"keys"`) {
			fail = append(fail, fmt.Sprintf("%s: the new binary still names a file it opened", name))
		}
	}
	o := by["view_keys"]
	if strings.Contains(o.oT, "noreadonly") || !strings.Contains(o.oT, "readonly") {
		fail = append(fail, "view_keys: `:set ro?` did not answer `readonly` on the input binary, so `:view` being `:edit` with the option set is not shown")
	}
	if !strings.Contains(o.nT, "noreadonly") {
		fail = append(fail, "view_keys: `:set ro?` does not answer `noreadonly` now, so the option was set by something other than the command that went")
	}
	lastSnap := func(s string) string {
		if i := strings.LastIndex(s, "--- snap"); i >= 0 {
			return s[i:]
		}
		return s
	}
	o = by["enew_bang"]
	if strings.Contains(lastSnap(o.oT), "hello") {
		fail = append(fail, "enew_bang: the input binary did not empty the buffer, so this proves nothing about `:enew`")
	}
	if !strings.Contains(lastSnap(o.nT), "hello") {
		fail = append(fail, "enew_bang: the new binary emptied the buffer anyway")
	}
	if !strings.Contains(o.nT, z6E492) {
		fail = append(fail, "enew_bang: `:enew!` is not an unknown command")
	}
	for _, name := range []string{"key_gf", "key_gF", "key_br_f", "key_brc_f"} {
		o := by[name]
		if !strings.Contains(o.oT, `E447: Can't find file "nosuchfile" in path`) {
			fail = append(fail, fmt.Sprintf("%s: the key did not look for a file on the input binary, so this proves nothing", name))
		}
		if strings.Contains(o.nT, "E447") {
			fail = append(fail, fmt.Sprintf("%s: the key still looks for a file", name))
		}
		if o.nSn != o.oSn-1 {
			fail = append(fail, fmt.Sprintf("%s: %d snapshots against the input binary's %d, expected one fewer -- the message drew a redraw of its own", name, o.nSn, o.oSn))
		}
	}
	for _, s := range z8Spellings {
		o := by["spell_"+s]
		if strings.Contains(o.oT, z6E492) {
			fail = append(fail, fmt.Sprintf(":%s already answered E492 before this phase, so it proves nothing", s))
		}
		if !strings.Contains(o.oT, "E37: No write since last change") {
			fail = append(fail, fmt.Sprintf(":%s did not reach its own refusal on the input binary", s))
		}
		if !strings.Contains(o.nT, z6E492) {
			fail = append(fail, fmt.Sprintf(":%s does not answer E492: a removed name has been inherited", s))
		}
	}
	o = by["spell_en"]
	if !strings.Contains(o.oT, z6E492) || !strings.Contains(o.nT, z6E492) {
		fail = append(fail, "spell_en: `:en` was E492 on both sides before this phase was written -- enew's shortest abbreviation is three characters")
	}
	o = by["cmd_edit"]
	if !strings.Contains(o.oT, "E37: No write since last change") || strings.Contains(o.nT, "E37") {
		fail = append(fail, "cmd_edit: E37 was to be the old answer -- `:edit` with no file name reached check_changed() -- and to be gone now")
	}
	if !strings.Contains(o.nT, z6E492) {
		fail = append(fail, "cmd_edit: `:edit` is not an unknown command")
	}
	if o := by["quit_modified"]; !strings.Contains(o.nT, "E37: No write since last change") {
		fail = append(fail, "quit_modified: :q no longer refuses on a modified buffer, and that is the :q phase's to change")
	}
	if o := by["cmd_file"]; !strings.Contains(o.nT, "[No Name]") {
		fail = append(fail, "cmd_file: `:file` no longer reports the buffer, and it is the buffer-name phase's")
	}
	for _, p := range []struct{ name, want string }{
		{"cmd_append", "added"}, {"editing", "alpha"}, {"cmd_vglobal", "b2"}, {"verbose_ro", "noreadonly"},
	} {
		if o := by[p.name]; !strings.Contains(o.nT, p.want) {
			fail = append(fail, fmt.Sprintf("%s: the new binary no longer shows %s, so \"it did not move\" is two failures agreeing", p.name, cutilRepr(p.want)))
		}
	}
	o = by["cmd_registers"]
	if !strings.Contains(o.nS, "Type Name Content") || !strings.Contains(o.oS, "Type Name Content") {
		fail = append(fail, "cmd_registers: :registers printed no table, so \"it did not move\" is two failures agreeing")
	}
	o = by["cmd_read"]
	if !strings.Contains(o.oT, z6E492) || !strings.Contains(o.nT, z6E492) {
		fail = append(fail, "cmd_read: `:read keys` was E492 on both sides before this phase was written -- zero phase 7 took it")
	}
	if len(fail) > 0 {
		for _, l := range fail {
			r.say("%s", l)
		}
		r.cont("the corpus cannot see a file being opened -- `cmd_edit` types")
		r.cont("`:edit` with no file name and records E37, and `key_gf` presses")
		r.cont("`gf` on a word naming nothing.  These are the only probes that")
		r.cont("can tell a removed command from a changed message.")
		return harness.ErrReported
	}
	r.say("probes: %d moved (%s), %d unchanged", len(moved), strings.Join(moved, " "), len(static))
	r.cont("the input binary opened `keys` through :e :ex :visual and :view, answered `readonly` under the last, emptied the buffer for :enew! and found four ways to look for a file from the keyboard; ten spellings answer E492 and none did before")
	return nil
}

// z8Keys is section 7: fifty g*, [ and ] keys, of which exactly four may move.
// No nv_cmds[] row is deleted or repointed here -- gf, gF, [f and ]f are ARMS
// inside nv_g_cmd() and nv_brackets(), whose rows dispatch dozens of other
// keys.  That is an argument; this is the measurement.
func z8Keys(r *rep, old, bin string) error {
	g := []string{"ga", "g8", "g_", "gI", "gi", "gJ", "gj", "gk", "gv", "gp", "gP", "gq", "gu",
		"gU", "g~", "g?", "gg", "ge", "gE", "gm", "gM", "go", "gs", "gt", "gT", "g0",
		"g^", "g$", "g&", "g;"}
	b := []string{"[(", "[{", "])", "]}", "[[", "[]", "]]", "][", "[p", "]p", "[P", "]P",
		"['", "]'", "[`", "]`"}
	movers := []string{"gf", "gF", "[f", "]f"}
	keys := append(append(append([]string{}, g...), b...), movers...)

	rec := func(binary, k string) string {
		ks := [][]byte{[]byte("ialpha beta\rnosuchfile\x1b"), []byte(":set nopaste\r"),
			[]byte("gg0" + k), []byte("\x1b:q!\r")}
		return z8KeyRecord(binary, ks)
	}
	type kr struct{ k, o, n string }
	res := make([]kr, len(keys))
	var wg sync.WaitGroup
	for i, k := range keys {
		wg.Add(1)
		go func(i int, k string) {
			defer wg.Done()
			res[i] = kr{k, rec(old, k), rec(bin, k)}
		}(i, k)
	}
	wg.Wait()
	var moved []string
	for _, x := range res {
		if x.o != x.n {
			moved = append(moved, x.k)
		}
	}
	sm, mm := append([]string{}, moved...), append([]string{}, movers...)
	sort.Strings(sm)
	sort.Strings(mm)
	if strings.Join(sm, " ") != strings.Join(mm, " ") {
		shown := strings.Join(moved, " ")
		if shown == "" {
			shown = "(none)"
		}
		r.say("of %d g*/[/] keys, %d moved: %s -- exactly %s were to", len(keys), len(moved), shown, strings.Join(movers, " "))
		r.cont("a key that moved and was not to means one of the two cuts took part of the chain it sat in")
		return harness.ErrReported
	}
	r.say("keys: %d of %d moved -- %s -- and the other %d are identical in exit, bells, snapshots and stream digest, which is what proves nv_g_cmd() and nv_brackets() survived",
		len(moved), len(keys), strings.Join(movers, " "), len(keys)-len(moved))
	return nil
}

// z8KeyRecord is the key sweep's own record shape: no stderr section, and the
// stream is a DIGEST with no length, because fifty keys make fifty records and
// the length adds nothing the digest does not.
func z8KeyRecord(binary string, keys [][]byte) string {
	vim, err := harness.Stage(binary)
	if err != nil {
		return "ERROR " + err.Error()
	}
	home, _ := os.MkdirTemp("", "zero8-kh-")
	defer os.RemoveAll(home)
	d, _ := os.MkdirTemp("", "zero8-kr-")
	defer os.RemoveAll(d)
	kf := d + "/keys"
	var buf []byte
	for _, k := range keys {
		buf = append(buf, k...)
	}
	os.WriteFile(kf, buf, 0o644)
	in, _ := os.Open(kf)
	defer in.Close()
	c := exec.Command(vim, "+set paste")
	c.Stdin, c.Dir, c.Env = in, d, z2Env(home)
	harness.Setsid(c)
	out, _ := c.Output()
	rcText := "0"
	if c.ProcessState != nil && c.ProcessState.ExitCode() != 0 {
		rcText = fmt.Sprintf("%d", c.ProcessState.ExitCode())
	}
	scr := harness.NewScreen(24, 80)
	scr.Feed(out)
	sum := sha256.Sum256(out)
	text := harness.Section("exit "+rcText, nil) + harness.Section(fmt.Sprintf("bells %d", scr.Bells), nil)
	text += harness.Section("stream sha="+hex.EncodeToString(sum[:])[:16], nil)
	for i, s := range scr.Snaps {
		dd := s.Text
		text += harness.Section(fmt.Sprintf("snap %d cursor=%d,%d bells=%d", i, s.Y, s.X, s.Bells), &dd)
	}
	return harness.Scrub(text)
}

func z8Pty(r *rep, old, bin string) error {
	home, err := os.MkdirTemp("", "zero8-home-")
	if err != nil {
		return err
	}
	session := func(binary string, keys [][]byte, plant bool) (string, int, error) {
		d, err := os.MkdirTemp("", "zero8-pty-")
		if err != nil {
			return "", -1, err
		}
		if plant {
			os.WriteFile(d+"/planted.txt", []byte("FROMTHEDISK\n"), 0o644)
		}
		text, status, err := harness.Session(binary, nil, keys, "xterm",
			20*time.Second, 600*time.Millisecond, d, z2Env(home), 0, 0)
		return string(text), status, err
	}
	say := func(format string, a ...any) error { r.say(format, a...); return harness.ErrReported }
	ek := [][]byte{[]byte("ityped on a terminal\x1b"), []byte(":e! planted.txt\r"), []byte(":q!\r")}
	oT, _, err := session(old, ek, true)
	if err != nil {
		return err
	}
	nT, _, err := session(bin, ek, true)
	if err != nil {
		return err
	}
	if !strings.Contains(oT, "FROMTHEDISK") {
		return say("the input binary opened nothing on a pty, so this proves nothing")
	}
	if strings.Contains(nT, "FROMTHEDISK") {
		return say("the new binary opened planted.txt on a pty")
	}
	if !strings.Contains(nT, "E492") {
		return say("`:e!` on a pty did not answer E492 on the new binary")
	}
	ed := [][]byte{[]byte("ityped here\x1b"), []byte("0dw"), []byte(":set ruler?\r"), []byte(":q!\r")}
	eo, eoRC, err := session(old, ed, false)
	if err != nil {
		return err
	}
	en, enRC, err := session(bin, ed, false)
	if err != nil {
		return err
	}
	if !strings.Contains(eo, "here") || !strings.Contains(eo, "ruler") {
		return say("the editing pty session did not edit on the input binary")
	}
	if eo != en || eoRC != enRC {
		return say("the editing pty session moved: %d -> %d", eoRC, enRC)
	}
	r.say("pty: the input binary opened a planted file into the buffer and this one answers E492; the editing session identical either side")
	return nil
}
