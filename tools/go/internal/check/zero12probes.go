package check

import (
	"fmt"
	"strings"
	"sync"
	"time"

	"slimvim.local/tools/internal/harness"
)

const z12W10 = "W10: Warning: Changing a readonly file"

var z12GoneOpts = []string{"ro", "fsync", "write", "wa", "undoreload", "prompt"}

func z12Probes(r *rep, old, bin string) error {
	esc, cr := []byte("\x1b"), []byte("\r")
	quit := []byte("\x1b:q!\r")
	hello := []byte("hello")
	ctrlG := []byte("\x07")
	typed := func(seed []byte, keys ...[]byte) ([]string, [][]byte) {
		k := [][]byte{append(append([]byte("i"), seed...), esc...), []byte(":set nopaste\r")}
		return []string{"+set paste"}, append(append(k, keys...), quit)
	}
	// No seed: the buffer is UNMODIFIED, which change_warning() requires.
	plain := func(keys ...[]byte) ([]string, [][]byte) {
		return []string{"+set paste"}, append(append([][]byte{[]byte(":set nopaste\r")}, keys...), quit)
	}
	var probes []z6Probe
	add := func(name string, a []string, k [][]byte, d bool) { probes = append(probes, z6Probe{name, a, k, d}) }
	b := func(s string) []byte { return []byte(s) }

	add("ro_w10", []string{"+set paste"}, [][]byte{b(":set ro\r"), b(":set nopaste\r"), b("ix\x1b"), ctrlG, quit}, true)
	a, k := plain(b(":set ro\r"), ctrlG)
	add("ro_ctrlg", a, k, true)
	a, k = plain(b(":set shm=r\r"), b(":set ro\r"), ctrlG)
	add("ro_shm_r", a, k, true)
	add("ro_statusline", []string{"+set paste", "+set laststatus=2"}, [][]byte{b(":set nopaste\r"), b(":set ro\r"), quit}, true)
	a, k = plain(b(":set all\r"))
	add("set_all", a, k, true)
	a, k = plain(b(":set readonly\r"))
	add("set_readonly", a, k, true)
	a, k = plain(b(":set ro\r"))
	add("set_ro", a, k, true)
	add("paste_roundtrip", []string{"+set paste"}, [][]byte{b("ione two\x1b"), b(":set nopaste\r"), b(":set paste?\r"), quit}, false)
	a, k = typed(hello, b(":set modified?\r"))
	add("mod_query", a, k, false)
	for _, p := range []struct {
		name string
		keys []string
	}{
		{"shm_query", []string{":set shm?\r"}},
		{"cpo_query", []string{":set cpo?\r"}},
		{"shm_F", []string{":set shm=F\r", ":set shm?\r"}},
		{"shm_bad", []string{":set shm=y\r"}},
		{"cpo_g", []string{":set cpo=g\r", ":set cpo?\r"}},
		{"cpo_bad", []string{":set cpo=h\r"}},
		{"nu_query", []string{":set nu?\r"}},
		{"bare_set", []string{":set\r"}},
		{"set_listing", []string{":set all&\r", ":set ai?\r"}},
	} {
		var ks [][]byte
		for _, x := range p.keys {
			ks = append(ks, b(x))
		}
		a, k = plain(ks...)
		add(p.name, a, k, false)
	}
	a, k = typed(append(append(b("a"), cr...), b("b")...), ctrlG)
	add("ctrl_g", a, k, false)
	a, k = typed(b("alpha"), b("x"), b("u"))
	add("undo_case", a, k, false)
	a, k = typed(append(append(b("alpha"), cr...), b("beta")...), b("0dwA-tail\x1b"), b("u"), b("yyp"))
	add("editing", a, k, false)
	for _, n := range z12GoneOpts {
		a, k = plain(b(":set " + n + "?\r"))
		add("q_"+n, a, k, true)
	}

	type outcome struct {
		name           string
		oT, nT, oS, nS string
		oMs, nMs       int64
		differ         bool
	}
	outs := make([]outcome, len(probes))
	var wg sync.WaitGroup
	for i, p := range probes {
		wg.Add(1)
		go func(i int, p z6Probe) {
			defer wg.Done()
			ot, os_, oms := zRecordTimed(old, p.args, p.keys, 10*time.Second)
			nt, ns, nms := zRecordTimed(bin, p.args, p.keys, 10*time.Second)
			outs[i] = outcome{p.name, ot, nt, os_, ns, oms, nms, p.differ}
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
	o := by["ro_w10"]
	if !strings.Contains(o.oS, z12W10) {
		fail = append(fail, "ro_w10: the input binary did not warn, so this proves nothing -- change_warning() returns early on b_did_warn || curbufIsChanged(), so the buffer must be UNMODIFIED when `:set ro` runs")
	}
	if o.oMs < 500 {
		fail = append(fail, fmt.Sprintf("ro_w10: the input binary took %d ms and the warning ends in ui_delay(1002L, TRUE); under half a second means it never drew it", o.oMs))
	}
	if strings.Contains(o.nS, z12W10) {
		fail = append(fail, "ro_w10: this binary still warns")
	}
	if o.nMs > 400 {
		fail = append(fail, fmt.Sprintf("ro_w10: this binary took %d ms, so something is still pausing", o.nMs))
	}
	o = by["ro_ctrlg"]
	if !strings.Contains(o.oS, "[readonly]") {
		fail = append(fail, "ro_ctrlg: the input binary did not print [readonly] -- note it is [readonly] and not [RO], because 'shortmess' default has no `r`")
	}
	if strings.Contains(o.nS, "[readonly]") || strings.Contains(o.nS, "[RO]") {
		fail = append(fail, "ro_ctrlg: an indicator survives")
	}
	o = by["ro_shm_r"]
	if !strings.Contains(o.oS, "[RO]") {
		fail = append(fail, "ro_shm_r: the input binary did not print [RO] with shm=r, and it is the only probe that reaches SHM_RO")
	}
	if strings.Contains(o.nS, "[RO]") {
		fail = append(fail, "ro_shm_r: [RO] survives")
	}
	o = by["ro_statusline"]
	if !strings.Contains(o.oS, "[RO]") {
		fail = append(fail, "ro_statusline: the input binary drew no [RO] on the status line, and win_redr_status is reached by nothing else here")
	}
	if strings.Contains(o.nS, "[RO]") {
		fail = append(fail, "ro_statusline: the status line still draws [RO]")
	}
	o = by["set_all"]
	for _, name := range []string{"readonly", "fsync", "prompt", "undoreload"} {
		if !strings.Contains(o.oS, name) {
			fail = append(fail, fmt.Sprintf("set_all: the input binary did not list %s, so this proves nothing", cutilRepr(name)))
		}
		if strings.Contains(o.nS, name) {
			fail = append(fail, fmt.Sprintf("set_all: %s is still listed", cutilRepr(name)))
		}
	}
	if !strings.Contains(o.nS, "paste") || !strings.Contains(o.nS, "modified") {
		fail = append(fail, "set_all: 'paste' or 'modified' is no longer listed, and both stay")
	}
	for _, n := range z12GoneOpts {
		o := by["q_"+n]
		if strings.Contains(o.oS, "E518") {
			fail = append(fail, fmt.Sprintf(":set %s? already answered E518 before this phase, so it proves nothing", n))
		}
		if !strings.Contains(o.nS, "E518: Unknown option: "+n+"?") {
			fail = append(fail, fmt.Sprintf(":set %s? does not answer E518 now", n))
		}
	}
	for _, p := range []struct{ name, sp string }{{"set_readonly", "readonly"}, {"set_ro", "ro"}} {
		o := by[p.name]
		if strings.Contains(o.oS, "E518") {
			fail = append(fail, fmt.Sprintf(":set %s was already unknown before this phase", p.sp))
		}
		if !strings.Contains(o.nS, "E518: Unknown option: "+p.sp) {
			fail = append(fail, fmt.Sprintf(":set %s does not answer E518 now, so something can still mark a buffer read only", p.sp))
		}
	}
	for _, p := range []struct{ name, want string }{{"shm_F", "shortmess=F"}, {"cpo_g", "cpoptions=g"}} {
		o := by[p.name]
		for _, s := range []struct{ tag, stream string }{{"the input binary", o.oS}, {"this one", o.nS}} {
			if !strings.Contains(s.stream, p.want) || strings.Contains(s.stream, "E539") {
				fail = append(fail, fmt.Sprintf("%s: %s did not accept the inert letter silently and answer %s", p.name, s.tag, cutilRepr(p.want)))
			}
		}
	}
	for _, name := range []string{"shm_bad", "cpo_bad"} {
		o := by[name]
		for _, s := range []struct{ tag, stream string }{{"the input binary", o.oS}, {"this one", o.nS}} {
			if !strings.Contains(s.stream, "E539") {
				fail = append(fail, fmt.Sprintf("%s: %s did not answer E539, so \"the validity list is untouched\" is two failures agreeing", name, s.tag))
			}
		}
	}
	if o := by["paste_roundtrip"]; !strings.Contains(o.nS, "paste") {
		fail = append(fail, "paste_roundtrip: `:set paste?` answered nothing, and 'paste' is the exempt option the whole corpus depends on")
	}
	if o := by["mod_query"]; !strings.Contains(o.nS, "modified") {
		fail = append(fail, "mod_query: `:set modified?` answered nothing, and 'modified' is the row decision 5 keeps")
	}
	if o := by["ctrl_g"]; !strings.Contains(o.nS, "[Modified]") {
		fail = append(fail, "ctrl_g: CTRL-G no longer says [Modified], and this phase removes only the read-only indicators from that line")
	}
	for _, p := range []struct{ name, want string }{
		{"editing", "alpha"}, {"shm_query", "shortmess="}, {"cpo_query", "cpoptions="}, {"nu_query", "number"},
	} {
		if o := by[p.name]; !strings.Contains(o.nS, p.want) {
			fail = append(fail, fmt.Sprintf("%s: the new binary no longer shows %s, so \"it did not move\" is two failures agreeing", p.name, cutilRepr(p.want)))
		}
	}
	if len(fail) > 0 {
		for _, l := range fail {
			r.say("%s", l)
		}
		r.cont("EVERY VISIBLE EFFECT OF THIS PHASE IS OUTSIDE THE INSTRUMENT:")
		r.cont("no recorded case or row asks any of the six, bare `:set` does")
		r.cont("not move, and zexcmds.py keeps no stream digest for the `set`")
		r.cont("row.  These probes are not a supplement, they are the check.")
		return harness.ErrReported
	}
	r.say("probes: %d moved (%s), %d unchanged", len(moved), strings.Join(moved, " "), len(static))
	w10 := by["ro_w10"]
	r.cont("ro_w10 is the phase: `:set ro` then an insert draws `W10: Warning: Changing a readonly file` and pauses %d ms on the binary this phase was handed, and %d ms here with no warning at all", w10.oMs, w10.nMs)
	r.cont("and the flag letters are asserted rather than described: `:set shm=F` and `:set cpo=g` are accepted silently on BOTH binaries and `:set shm=y` answers E539 on both -- the validity lists were not touched")
	r.cont("what did not move is doing its work: `:set paste?`, `:set modified?`, `:set shm?`, `:set cpo?`, `:set nu?`, bare `:set`, `:set all&`, CTRL-G with [Modified], undo and an ordinary editing session")
	return nil
}
