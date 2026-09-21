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

type z22Probe struct {
	tag  string
	args []string
	keys [][]byte
}

func z22Build() ([]z22Probe, int) {
	esc, cr, cg, ca := []byte("\x1b"), []byte("\r"), []byte("\x07"), []byte("\x01")
	quit := []byte("\x1b:q!\r")
	paste := []string{"+set paste"}
	cat := func(p ...[]byte) []byte { return bytes.Join(p, nil) }
	l4 := cat([]byte("aaa"), cr, []byte("bbb"), cr, []byte("aaa"), cr, []byte("ccc"))
	var l40p [][]byte
	for i := 1; i <= 40; i++ {
		l40p = append(l40p, []byte(fmt.Sprintf("line%d", i)))
	}
	l40 := bytes.Join(l40p, cr)
	seed := func(t []byte) [][]byte { return [][]byte{cat([]byte("i"), t, esc), cat([]byte(":set nopaste"), cr)} }
	var P []z22Probe
	probe := func(tag string, args []string, keys ...[]byte) {
		k := append(append([][]byte{}, keys...), quit)
		P = append(P, z22Probe{tag, args, k})
	}
	sk := func(s []byte, keys ...[]byte) [][]byte { return append(seed(s), keys...) }
	plus := func(extra ...string) []string { return append(append([]string{}, paste...), extra...) }
	c := func(s string) []byte { return []byte(s) }

	// 1. the command layer
	for _, p := range []struct {
		tag string
		cmd []byte
	}{{"set_nosuchopt", c(":set nosuchoption")}, {"set_badval", c(":set sw=zz")},
		{"winsize_zz", c(":winsize zz")}, {"later_3x", c(":later 3x")},
		{"earlier_bad", c(":earlier 9q")}, {"mark_ab", c(":mark ab")},
		{"delmarks_1", c(":delmarks 1")}, {"history_xyzzy", c(":history : xyzzy")},
		{"match_foo", c(":match Foo /x/")}, {"undo_99", c(":undo 99")},
		{"normal_bad", c(":normal")}, {"set_t_zz", c(":set t_zz=x")},
		{"map_bad", c(":map <Nosuch> x")}, {"unmap_bad", c(":unmap zqzq")},
		{"syntax_bad", c(":nosuchcommand")}, {"set_all_q", c(":set invalidopt?")},
		{"set_inv", c(":set noinvalidopt")}, {"hi_link_bad", c(":highlight link")},
		{"behave_bad", c(":behave zz")}, {"sleep_bad", c(":sleep 3q")},
		{"redir_bad", c(":redir zz")}, {"marks_zzz", c(":marks zzz")},
		{"set_ts_abc", c(":set ts=abc")}, {"set_unknown2", c(":set invopt=1")},
		{"set_ts_huge", c(":set ts=99999999999999999999")},
		{"hi_link3", c(":hi link a b c")}, {"hi_noeq", c(":hi Comment ctermfg")},
		{"hi_eq", c(":hi Comment =x")}, {"t_missing", c(":set <t_zz>=x")},
		{"t_long", cat(c(":set t_AB="), bytes.Repeat(c("x"), 200))}} {
		probe(p.tag, paste, sk(c("hello"), cat(p.cmd, cr))...)
	}
	for i, cmd := range []string{":hi Comment ctermfg=nosuch", ":hi Comment cterm=nosuch",
		":hi Comment start=", ":hi Comment guifg=nosuch", ":hi NoSuchGroup",
		":hi Comment nosucharg=1", ":hi clear NoSuchGroup", ":hi Comment ctermbg=999"} {
		probe(fmt.Sprintf("hi%d", i), paste, sk(c("hello"), cat(c(cmd), cr))...)
	}
	for _, p := range []struct {
		tag  string
		a, b string
	}{{"map_unique", ":map q1 x", ":map <unique> q1 y"},
		{"map_unique_ins", ":map! q1 x", ":map! <unique> q1 y"},
		{"abbr_unique", ":abbr q1 x", ":abbr <unique> q1 y"},
		{"cabbr_unique", ":cabbr q1 x", ":cabbr <unique> q1 y"}} {
		probe(p.tag, paste, sk(c("hello"), cat(c(p.a), cr), cat(c(p.b), cr))...)
	}
	for _, p := range [][2]string{{"invreg", "\"#p"}, {"emptyreg", "\"zp"}, {"reg_bang", "\"!p"},
		{"reg_caret", "\"^p"}, {"record_bad", "q!"}, {"e_nothing_in_reg", "\"qp"}} {
		probe(p[0], paste, sk(c("hello"), c(p[1]))...)
	}

	// 2. the regexp engine
	badpat := []string{`\(`, `[`, `a\{1,2,3}`, `\%[`, `\%(`, `\%d99999999`, `\z1`,
		`a\@`, `\(x\)\{1,2}\{3}`, `\%#=3`, `\{`, `a\{-`, `\%v`,
		`\%[abc`, `\)`, `\|\|`, `a**`, `\%da`, `[a-`, `\@=`,
		`\%(x`, `~\{`}
	for eng := 1; eng <= 2; eng++ {
		for _, mp := range [][2]string{{"magic", ""}, {"nomagic", ""}, {"magic", `\v`}} {
			for i, pat := range badpat {
				probe(fmt.Sprintf("re%d_%s%d_%d", eng, mp[0], len(mp[1]), i),
					plus(fmt.Sprintf("+set re=%d %s", eng, mp[0])),
					sk(c("aaa"), cat(c("/"+mp[1]+pat), cr))...)
			}
		}
	}
	for _, p := range []struct {
		tag  string
		keys []byte
	}{{"search_bad", cat(c(`/\%23`), cr)}, {"engine_mid", cat(c(`/a\%#=1`), cr)},
		{"empty_brackets", cat(c(`/x\%[]`), cr)},
		{"missing_rsb", cat(c(`/x\%[abc`), cr)},
		{"bad_in_brackets", cat(c(`/x\%[a*]`), cr)},
		{"too_many_open", cat(c("/"), bytes.Repeat(c(`\(`), 12), c("a"), cr)},
		{"too_many_curly", cat(c("/"), bytes.Repeat(c(`\(a\)\{1,2}`), 12), cr)}} {
		probe(p.tag, paste, sk(c("aaa"), p.keys)...)
	}
	for _, p := range [][2]string{{"nfa_repeat", `/\@<=*`}, {"nfa_repeat2", `/a\{1,2}\{3,4}`}} {
		probe(p[0], plus("+set re=2"), sk(c("aaa"), cat(c(p[1]), cr))...)
	}
	for i, pat := range []string{`\(`, `[`, `a\{1,2,3}`, `\%[`} {
		probe(fmt.Sprintf("incsearch%d", i), plus("+set incsearch"), sk(c("aaa"), c("/"+pat), esc)...)
	}

	// 3. smsg
	for _, p := range []struct {
		tag  string
		keys []byte
	}{{"eq_line", cat(c(":="), cr)}, {"global_print", cat(c(":g/aaa/p"), cr)},
		{"move_report", cat(c(":1,3m$"), cr)}, {"yank_block", c("gg\x16jjly")},
		{"g_notfound", cat(c(":g/zzzz/d"), cr)}, {"v_everyline", cat(c(":v/./d"), cr)},
		{"bar_here", cat(c(":g/aaa/normal x | p"), cr)}} {
		probe(p.tag, paste, sk(l4, p.keys)...)
	}
	for _, p := range [][2]string{{"tilde_report", "ggg~3j"}, {"yank_lines", "gg3yy"},
		{"join_report", "gg10J"}, {"shift_report", "gg10>>"}, {"delete_report", "gg10dd"}} {
		probe(p[0], paste, sk(l40, c(p[1]))...)
	}
	probe("ctrl_a_block", paste, sk(cat(c("1"), cr, c("2"), cr, c("3")), cat(c("gg\x16jj"), ca))...)
	probe("g_verbose", plus("+set verbose=1"), sk(l4, cat(c(":g/aaa/p"), cr))...)
	probe("g_verbose9", plus("+set verbose=9"), sk(l4, cat(c(":g/aaa/p"), cr))...)

	// 4. the substitution report, the confirm prompt and ask_yesno
	for _, p := range []struct {
		tag  string
		keys [][]byte
	}{{"sub_one", [][]byte{cat(c(":%s/aaa/ZZZ/g"), cr)}},
		{"sub_confirm", [][]byte{cat(c(":%s/aaa/ZZZ/gc"), cr), c("yn")}},
		{"ask_yesno", [][]byte{cat(c(":%s/aaa/ZZZ/gc"), cr), c("a")}},
		{"sub_nomatch", [][]byte{cat(c(":%s/zzzz/q/"), cr)}},
		{"sub_badflag", [][]byte{cat(c(":%s/a/b/zz"), cr)}},
		{"sub_bigcount", [][]byte{cat(c(":%s/a/b/c99999999"), cr)}},
		{"sub_pat_bad", [][]byte{cat(c(`:%s/\(/x/`), cr)}},
		{"sub_count0", [][]byte{cat(c(":%s/a/b/ 0"), cr)}},
		{"delmarks_bad", [][]byte{cat(c(":delmarks z-a"), cr)}},
		{"norm_bar", [][]byte{cat(c(":normal! x | y"), cr)}},
		{"e_val_large2", [][]byte{cat(c(":1,99999999999999999999p"), cr)}},
		{"e_val_large3", [][]byte{cat(c(":99999999999999999999"), cr)}},
		{"undo_msg", [][]byte{c("ggdd"), c("u")}}, {"redo_msg", [][]byte{c("ggdd"), c("u\x12")}},
		{"undolist", [][]byte{c("ggdd"), cat(c(":undolist"), cr)}}, {"undo_none", [][]byte{c("u")}},
		{"undo_time", [][]byte{c("ggdd"), cat(c(":earlier 1f"), cr)}},
		{"marks", [][]byte{c("ma"), cat(c(":marks"), cr)}},
		{"registers", [][]byte{c("yy"), cat(c(":registers"), cr)}}} {
		probe(p.tag, paste, sk(l4, p.keys...)...)
	}
	probe("sub_many", paste, sk(l40, cat(c(":%s/line/LN/g"), cr))...)
	probe("sub_report_msg", paste, sk(l40, cat(c(":%s/e/E/g"), cr))...)

	// 5. vim_snprintf_safelen: CTRL-G and the ruler
	for _, p := range []struct {
		tag  string
		args []string
		s, k []byte
	}{{"ctrl_g_1", paste, c("hello"), cg}, {"ctrl_g_40", paste, l40, cat(c("20G"), cg)},
		{"ctrl_g_top", paste, l40, cat(c("gg"), cg)}, {"ctrl_g_bot", paste, l40, cat(c("G"), cg)},
		{"ctrl_g_2", paste, l40, cat(c("20G2"), cg)},
		{"ctrl_g_shm", plus("+set shortmess="), l40, cat(c("20G"), cg)},
		{"ctrl_g_shm1", plus("+set shortmess="), c("hello"), cg},
		{"big_line", paste, bytes.Repeat(c("x"), 200), cat(c("$"), cg)},
		{"ml_get", paste, l40, cat(c("G"), bytes.Repeat(c("j"), 5), cg)},
		{"ruler_ru", plus("+set ruler"), l40, c("20G")},
		{"ruler_noru", plus("+set noruler"), l40, c("20G")},
		{"ruler_fmt", plus("+set ruler"), l40, c("Gllll")},
		{"ruler_virtual", plus("+set ruler ve=all"), l40, c("20G20l")},
		{"ruler_all", plus("+set ruler"), cat(c("a"), cr, c("b"), cr, c("c")), c("j")},
		{"ruler_all_shm", plus("+set ruler shortmess="), cat(c("a"), cr, c("b")), c("j")}} {
		probe(p.tag, p.args, sk(p.s, p.k)...)
	}
	probe("ruler_empty", plus("+set ruler"), c(""))

	// 6. the screens that format a great deal at once
	for _, p := range []struct {
		tag  string
		args []string
		s, k []byte
	}{{"intro", paste, c("x"), cat(c(":intro"), cr)}, {"version", paste, c("x"), cat(c(":version"), cr)},
		{"ga", paste, c("abc"), c("ga")}, {"ga_multi", paste, c("é"), c("ga")},
		{"set_all", paste, c("x"), cat(c(":set all"), cr)},
		{"set_termcap", paste, c("x"), cat(c(":set termcap"), cr)},
		{"digraph", paste, c("x"), cat(c(":digraphs"), cr)}, {"maps", paste, c("x"), cat(c(":map"), cr)},
		{"display_uhex", plus("+set display=uhex"), c("x"), cat(c("a\x16\x01"), esc)},
		{"list_mode", plus("+set list"), c("a\tb"), c("")},
		{"bad_command", paste, c("x"), cat(c(":qqqq"), cr)},
		{"trailing_chars", paste, c("x"), cat(c(":history : xyz abc"), cr)},
		{"e_invalid_arg", paste, c("x"), cat(c(":set backspace=nosuch"), cr)},
		{"term_sync", paste, c("x"), cat(c(":set t_RS=x"), cr)},
		{"buf_inuse", paste, c("x"), cat(c(":bdelete"), cr)},
		{"search_notfound", paste, c("aaa"), cat(c("/zzzz"), cr)},
		{"search_wrap", plus("+set nowrapscan"), c("aaa"), cat(c("/zzzz"), cr)},
		{"search_top", plus("+set nowrapscan"), c("aaa"), cat(c("?zzzz"), cr)}} {
		probe(p.tag, p.args, sk(p.s, p.k)...)
	}
	return P, 2 * 3 * len(badpat)
}

func z22Run(binary string, p z22Probe) string {
	scr, out, errb, rc, err := harness.ZSession(binary, p.keys, "xterm", p.args, 24, 80, 20*time.Second)
	if err == harness.ErrBlocked {
		return p.tag + "|BLOCKED"
	}
	if err != nil {
		return p.tag + "|ERROR " + err.Error()
	}
	body := ""
	if len(scr.Snaps) > 0 {
		body = scr.Snaps[len(scr.Snaps)-1].Text
	}
	so, sb := sha256.Sum256(out), sha256.Sum256([]byte(body))
	return fmt.Sprintf("%s|%d|%s|%d|%d|%s", p.tag, len(out), hex.EncodeToString(so[:])[:16], rc, len(errb), hex.EncodeToString(sb[:])[:16])
}

func z22Probes(r *rep, old, bin, b1, b2, b3, b4 string) error {
	P, nre := z22Build()
	bins := []string{old, bin, b1, b2, b3, b4}
	res := make([][]string, len(bins))
	for i := range res {
		res[i] = make([]string, len(P))
	}
	sem := make(chan struct{}, 48)
	var wg sync.WaitGroup
	for bi, b := range bins {
		for pi, p := range P {
			wg.Add(1)
			sem <- struct{}{}
			go func(bi, pi int, b string, p z22Probe) {
				defer wg.Done()
				res[bi][pi] = z22Run(b, p)
				<-sem
			}(bi, pi, b, p)
		}
	}
	wg.Wait()
	differ := func(bi int) []string {
		var d []string
		for i := range P {
			if res[0][i] != res[bi][i] {
				d = append(d, P[i].tag)
			}
		}
		return d
	}
	var fail []string
	if d := differ(1); len(d) > 0 {
		fail = append(fail, fmt.Sprintf("%d of %d probes differ, and this phase declares NOTHING: %s", len(d), len(P), strings.Join(head(d, 25), " ")))
	}
	n1, n2, n3, n4 := len(differ(2)), len(differ(3)), len(differ(4)), len(differ(5))
	if n1 < 50 {
		fail = append(fail, fmt.Sprintf("THE CONTROL b1 DID NOT SHOW.  This phase's own output with both room helpers returning 20 instead of IOSIZE moved %d of %d probes, and a truncated message is the first thing a wrong buffer size would do -- two numbers agreeing prove nothing if a wrong one is not caught", n1, len(P)))
	}
	if n2 < 50 {
		fail = append(fail, fmt.Sprintf("THE CONTROL b2 DID NOT SHOW.  This phase's own output with every `semsg` site given `msg()` for a tail instead of `emsg()` moved %d of %d probes -- an error that no longer sets did_emsg is the mistake this phase is most able to make", n2, len(P)))
	}
	if n3 > 0 || n4 > 0 {
		fail = append(fail, fmt.Sprintf("b3 moved %d probes and b4 moved %d, and BOTH ARE DECLARED TO MOVE NOTHING.  If they now move something, the probe set has grown a reach the phase's own account of its evidence does not describe, and that account has to be rewritten rather than the number quietly updated", n3, n4))
	}
	if len(fail) > 0 {
		for _, l := range fail {
			r.say("%s", l)
		}
		return harness.ErrReported
	}
	r.say("%d probes on both binaries, 0 differ -- the Ex-command errors, %d regexp errors across both engines and three magic settings (which are the 18 comma-expression sites), the message and report sites, the substitute-confirm prompt, undo, CTRL-G and the ruler in fifteen shapes, and four incsearch probes with a bad pattern, which are the ONLY way to reach a `semsg` with emsg_off > 0", len(P), nre)
	r.cont("AND THEY CAN FAIL: this phase's own output with both room helpers returning 20 moves %d of %d, and with every `semsg` tail made `msg()` instead of `emsg()` moves %d", n1, len(P), n2)
	r.cont("AND TWO CONTROLS MOVE NOTHING, WHICH IS REPORTED RATHER THAN HIDDEN: safelen_result's clamp removed moves %d, and all three guards removed moves %d. The clamp needs a message longer than 1,025 bytes out of fileinfo, and the guards need IObuff == NULL -- an out-of-memory failure of the first two allocations the process makes.  The guards are copied verbatim from the wrappers and are correct by construction; the evidence does not reach them, and saying so is the point", n3, n4)
	return nil
}
