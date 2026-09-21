package check

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"strings"
	"sync"
	"time"

	"slimvim.local/tools/internal/harness"
)

type z14Res struct {
	ok    bool
	rc    int
	text  string
	first string
}

// z14Run records one session.  It returns the EXIT STATUS as subprocess would
// -- minus the signal number for a signal death -- because the overflow probe's
// whole evidence is that the binary it was handed dies with SIGSEGV, -11.
func z14Run(binary string, args []string, keys [][]byte) z14Res {
	scr, out, errb, rc, err := harness.ZSession(binary, keys, "xterm", args, 24, 80, 20*time.Second)
	if err == harness.ErrBlocked {
		return z14Res{}
	}
	if err != nil {
		return z14Res{ok: true, rc: -1, text: "ERROR " + err.Error()}
	}
	text := harness.Section(fmt.Sprintf("exit %d", rc), nil)
	text += harness.Section(fmt.Sprintf("bells %d", scr.Bells), nil)
	sum := sha256.Sum256(out)
	text += harness.Section(fmt.Sprintf("stream %d sha=%s", len(out), hex.EncodeToString(sum[:])[:16]), nil)
	e := strings.TrimRight(string(errb), "\n")
	text += harness.Section("stderr", &e)
	first := ""
	for i, s := range scr.Snaps {
		d := s.Text
		text += harness.Section(fmt.Sprintf("snap %d cursor=%d,%d bells=%d", i, s.Y, s.X, s.Bells), &d)
	}
	if n := len(scr.Snaps); n > 0 {
		first = strings.SplitN(scr.Snaps[n-1].Text, "\n", 2)[0]
	}
	return z14Res{true, rc, harness.Scrub(text), first}
}

func z14Probes(r *rep, old, bin string) error {
	esc, cr, cg, ca := []byte("\x1b"), []byte("\r"), []byte("\x07"), []byte("\x01")
	quit := []byte("\x1b:q!\r")
	seed := func(t []byte) [][]byte {
		return [][]byte{append(append([]byte("i"), t...), esc...), []byte(":set nopaste\r")}
	}
	cat := func(parts ...[]byte) []byte { return bytes.Join(parts, nil) }
	lines := func(format string, n int) []byte {
		var out [][]byte
		for i := 1; i <= n; i++ {
			out = append(out, []byte(fmt.Sprintf(format, i)))
		}
		return bytes.Join(out, cr)
	}
	rep20 := func(s string, n int) []byte {
		var out [][]byte
		for i := 0; i < n; i++ {
			out = append(out, []byte(s))
		}
		return bytes.Join(out, cr)
	}
	long := cat(bytes.Repeat([]byte("X"), 40), []byte("%d"))
	overflow := append(seed([]byte("aaa bbb")), cat([]byte(":set t_CF="), long, cr),
		[]byte(":highlight Search ctermfont=3\r"), []byte("/aaa\r"), []byte(":redraw!\r"), quit)
	tcf := func(fmtS []byte) [][]byte {
		return append(seed([]byte("aaa")), cat([]byte(":set t_CF="), fmtS, cr),
			[]byte(":highlight Search ctermfont=3\r"), []byte("/aaa\r"), []byte(":redraw!\r"), quit)
	}
	LINES := lines("x%d", 39)
	type probe struct {
		name string
		args []string
		pre  [][]byte
		keys [][]byte
	}
	P := []string{"+set paste"}
	b := func(s string) []byte { return []byte(s) }
	probes := []probe{
		{"hl_list", P, seed(b("x")), [][]byte{b(":highlight\r"), b("q")}},
		{"hl_one", P, seed(b("x")), [][]byte{b(":highlight Search\r"), cr}},
		{"marks_many", P, seed(b("aaa\rbbb\rccc\rddd")), [][]byte{b("ma"), b("jmb"), b("jmc"), b(":marks\r"), cr}},
		{"changes", P, seed(b("one\rtwo\rthree\rfour")), [][]byte{b("ciwX\x1b"), b("jciwY\x1b"), b("jciwZ\x1b"), b(":changes\r"), cr}},
		{"ga_ascii", P, seed(b("A")), [][]byte{b("0ga")}},
		{"ga_multi", P, seed([]byte{0xc3, 0xa9}), [][]byte{b("0ga")}},
		{"ga_combining", P, seed([]byte{'e', 0xcc, 0x81}), [][]byte{b("0ga")}},
		{"set_num", P, seed(b("x")), [][]byte{b(":set sw?\r"), cr, b(":set ts?\r"), cr, b(":set ul?\r"), cr}},
		{"set_all", P, seed(b("x")), [][]byte{b(":set all\r"), b("q")}},
		{"set_neg", P, seed(b("x")), [][]byte{b(":set scrolloff=-1\r"), b(":set so?\r"), cr}},
		{"set_big", P, seed(b("x")), [][]byte{b(":set undolevels=123456789\r"), b(":set ul?\r"), cr}},
		{"recording", P, seed(b("abc")), [][]byte{b("qq"), b("x"), b("q")}},
		{"recording_reg", P, seed(b("abc")), [][]byte{b("qZ"), b("x"), b("q"), b("@Z")}},
		{"term_query", P, seed(b("x")), [][]byte{b(":set term?\r"), cr, b(":set t_Co?\r"), cr}},
		{"term_cf", P, seed(b("x")), [][]byte{b(":set t_CF=[CF%d]\r"), b(":set t_CF?\r"), cr}},
		{"ctrl_g", P, seed(lines("line%d", 59)), [][]byte{b("30G"), cg, cr}},
		{"search_count", P, seed(rep20("aaa bbb aaa", 20)), [][]byte{b("gg"), b("/aaa\r"), b("n"), b("n"), b("n")}},
		{"subst_count", P, seed(rep20("aaa bbb aaa", 30)), [][]byte{b(":%s/aaa/ZZZ/g\r"), cr}},
		{"lines_report", P, seed(LINES), [][]byte{b("gg"), b("20dd"), cr}},
		{"shift_report", P, seed(LINES), [][]byte{b("gg"), b("20>>"), cr}},
		{"undo_report", P, seed(LINES), [][]byte{b("gg"), b("15dd"), b("u"), cr}},
		{"e_number", P, seed(b("x")), [][]byte{b(":nosuchcommandhere\r"), cr}},
		{"ruler", []string{"+set paste", "+set ruler"}, seed(lines("a longer line number %d", 39)), [][]byte{b("25G"), b("$")}},
		{"percent_ruler", []string{"+set paste", "+set ruler"}, seed(lines("x%d", 199)), [][]byte{b("100G")}},
		{"map_list", P, seed(b("x")), [][]byte{b(":map\r"), cr}},
		{"registers", P, seed(b("aaa\rbbb")), [][]byte{b("yy"), b("jyy"), b(":registers\r"), b("q")}},
		{"history", P, seed(b("x")), [][]byte{b(":set sw=2\r"), b(":set sw=3\r"), b(":history\r"), b("q")}},
		{"version", P, seed(b("x")), [][]byte{b(":version\r"), b("q")}},
		{"nrformats", P, seed(b("0x0f 017 99 -1")), [][]byte{cat(b("0"), ca), cat(b("w"), ca), cat(b("w"), ca), cat(b("w"), ca)}},
		{"hist_case", P, seed(b("x")), [][]byte{b(":set sw=2\r"), b(":history SEARCH\r"), b("q")}},
		{"hist_case_all", P, seed(b("x")), [][]byte{b(":set sw=2\r"), b(":history ALL\r"), b("q")}},
		{"hi_change_twice", P, seed(b("x")), [][]byte{b(":highlight Search ctermfg=1\r"), b(":highlight Search ctermfg=1\r"), b(":highlight Search\r"), cr}},
		{"winhighlight", P, seed(b("aaa\rbbb")), [][]byte{b(":set winhighlight=Normal:Search\r"), b("/aaa\r"), b(":redraw\r")}},
	}
	tcfs := []string{"[%f]", "[%b]", "[%*d]", "[%z]", "[%d]", "[%1$d]"}

	type job struct {
		name, binary string
		args         []string
		keys         [][]byte
	}
	var jobs []job
	for _, bi := range []string{old, bin} {
		jobs = append(jobs, job{"OVERFLOW", bi, P, overflow})
	}
	for _, t := range tcfs {
		for _, bi := range []string{old, bin} {
			jobs = append(jobs, job{"TCF" + t, bi, P, tcf([]byte(t))})
		}
	}
	for _, p := range probes {
		for _, bi := range []string{old, bin} {
			k := append(append(append([][]byte{}, p.pre...), p.keys...), quit)
			jobs = append(jobs, job{p.name, bi, p.args, k})
		}
	}
	res := map[[2]string]z14Res{}
	var mu sync.Mutex
	sem := make(chan struct{}, 64)
	var wg sync.WaitGroup
	for _, j := range jobs {
		wg.Add(1)
		sem <- struct{}{}
		go func(j job) {
			defer wg.Done()
			defer func() { <-sem }()
			x := z14Run(j.binary, j.args, j.keys)
			mu.Lock()
			res[[2]string{j.name, j.binary}] = x
			mu.Unlock()
		}(j)
	}
	wg.Wait()

	var fail []string
	o, n := res[[2]string{"OVERFLOW", old}], res[[2]string{"OVERFLOW", bin}]
	if !o.ok || !n.ok {
		fail = append(fail, "the t_CF overflow probe blocked, so it says nothing either way")
	} else {
		if o.rc != -11 {
			fail = append(fail, fmt.Sprintf("t_CF overflow: the binary this phase was handed exited %d and not -11.  sprintf writing 42 bytes into char buf[20] is what this phase fixes, and a check that cannot see it happening is not evidence that it stopped", o.rc))
		}
		if n.rc != 0 {
			fail = append(fail, fmt.Sprintf("t_CF overflow: this phase's binary exited %d, and vim_snprintf must truncate into buf[20] and carry on", n.rc))
		}
		if !strings.HasPrefix(n.first, strings.Repeat("X", 19)+"aaa") {
			shown := n.first
			if len(shown) > 40 {
				shown = shown[:40]
			}
			fail = append(fail, fmt.Sprintf("t_CF overflow: the new binary drew %s and not nineteen X and the buffer text -- sizeof(buf) is 20, so nineteen characters and a NUL is exactly what fits", cutilRepr(shown)))
		}
		if o.text == n.text {
			fail = append(fail, "t_CF overflow: the two records agree, so nothing was measured")
		}
	}
	moves := map[string]bool{"[%f]": true, "[%b]": true, "[%*d]": true, "[%z]": true}
	same := map[string]bool{"[%d]": true, "[%1$d]": true}
	for _, t := range tcfs {
		o, n := res[[2]string{"TCF" + t, old}], res[[2]string{"TCF" + t, bin}]
		if !o.ok || !n.ok {
			fail = append(fail, fmt.Sprintf("the t_CF %s probe blocked", t))
			continue
		}
		if moves[t] && o.text == n.text {
			fail = append(fail, fmt.Sprintf("t_CF %s renders the same on both binaries, and vim's own printf is not musl's: this phase changes what a USER-SET t_CF does for the directives vim spells differently, and the check records that rather than hiding it", t))
		}
		if same[t] && o.text != n.text {
			fail = append(fail, fmt.Sprintf("t_CF %s moved, and it must not: %%d is the only directive the `debug` terminal's built-in t_CF uses, and %%1$d is positional and identical in both implementations", t))
		}
	}
	for _, p := range probes {
		o, n := res[[2]string{p.name, old}], res[[2]string{p.name, bin}]
		if !o.ok || !n.ok {
			fail = append(fail, fmt.Sprintf("%s blocked, so it says nothing either way", p.name))
			continue
		}
		if o.text != n.text {
			fail = append(fail, fmt.Sprintf("%s moved, and vendoring the strings may move NOTHING the editor draws", p.name))
		}
	}
	if len(fail) > 0 {
		for _, l := range fail {
			r.say("%s", l)
		}
		return harness.ErrReported
	}
	r.say("the t_CF overflow: `:set t_CF=` + 40 X + `%%d` and a ctermfont kills the binary this phase was handed -- exit -11, SIGSEGV, sprintf writing 42 bytes into char buf[20] -- and truncates to nineteen characters here.  That is a BUG FIX and it is the only reachable input on which this phase changes what the editor does")
	r.cont(`and the formats a USER-SET t_CF can still reach: %%f, %%b, %%*d and %%z render differently because vim's own printf is not musl's, while %%d and %%1$d are identical -- recorded here and NOT declared, because nothing in the instrument sets t_CF and the only built-in t_CF is the debug terminal's "[CF%%d]".  %%s segfaults on BOTH binaries and is not this phase's`)
	r.cont("%d probes byte-identical either side: every one of the thirteen external sprintf sites, the numbers the nine internal ones formatted, and the case fold, the memcmp and the memcpy that the 106-record corpus never reaches", len(probes))
	return nil
}
