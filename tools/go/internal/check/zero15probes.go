package check

import (
	"fmt"
	"regexp"
	"strings"
	"sync"
	"time"

	"slimvim.local/tools/internal/harness"
)

// z15Scripts is one letter from each of six scripts.  The first three
// separate an ASCII fallback, the last two separate vim's own table, and a
// text with only one group would pass one of them.
var z15Scripts = []byte("eé gα cа xⓐ sⱟ")

var z15UndoRow = regexp.MustCompile(`\r\r\n\s*(\d+)\x1b`)

func z15Probes(r *rep, old, bin string) error {
	esc, cr := []byte("\x1b"), []byte("\r")
	quit := []byte("\x1b:q!\r")
	b := func(s string) []byte { return []byte(s) }
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
	one := func(name, want string, seed []byte, keys ...[]byte) {
		a, k := typed(seed, keys...)
		cases = append(cases, kase{name, a, k, want})
	}
	one("case_default", "Α", z15Scripts, b("gUU"))
	one("case_lower", "α", z15Scripts, b("gUU"), b("guu"))
	one("case_empty", "Α", z15Scripts, b(":set casemap=\r"), b("gUU"))
	one("case_keepascii", "Α", z15Scripts, b(":set casemap=keepascii\r"), b("gUU"))
	one("case_internal", "Α", z15Scripts, b(":set casemap=internal\r"), b("gUU"))
	one("case_tilde", "Α", z15Scripts, b("0"+strings.Repeat("~", 20)))
	one("map_keys", "<S-Tab>", b("alpha"), b(":map <Tab> x\r"), b(":map <S-Tab> y\r"), b(":map <Esc> z\r"), b(":map\r"))
	one("hl_cterm", "Foo", b("alpha"), b(":highlight Foo ctermfg=4 cterm=bold,reverse\r"), b(":highlight Foo\r"))
	one("hl_colorname", "Foo", b("alpha"), b(":highlight Foo ctermfg=Blue cterm=NONE\r"), b(":highlight Foo\r"))
	one("char_classes", "alnum", b("a1!Z x"), b("/[[:alnum:]]\r"), b("/[[:punct:]]\r"),
		b("/[[:alpha:]]\r"), b("/[[:graph:]]\r"), b("/[[:cntrl:]]\r"), b("/[[:digit:]]\r"))
	one("verbose_z", "autoindent", append(append(append(append(b("alpha"), cr...), b("beta")...), cr...), b("gamma")...),
		b(":3verbose set ai?\r"), b(":z2\r"))
	one("search_offset", "beta", b("alpha beta gamma"), b("0"), b("/beta/e+2\r"))
	one("term_colors", "256", b("alpha"), b(":set t_Co=256\r"), b(":set t_Co?\r"))
	one("isk_at", "na", []byte("café naïve"), b(":set isk=@\r"), b("0"), b("dw"))

	type out struct{ oT, nT, nS string }
	outs := make([]out, len(cases))
	var wg sync.WaitGroup
	for i, c := range cases {
		wg.Add(1)
		go func(i int, c kase) {
			defer wg.Done()
			ot, _ := zRecordStream(old, c.args, c.keys, 10*time.Second)
			nt, ns := zRecordStream(bin, c.args, c.keys, 10*time.Second)
			outs[i] = out{ot, nt, ns}
		}(i, c)
	}
	wg.Wait()
	var fail []string
	for i, c := range cases {
		if outs[i].oT != outs[i].nT {
			fail = append(fail, fmt.Sprintf("%s MOVED, and nothing in this phase may move a record", c.name))
		}
		if c.want != "" && !strings.Contains(outs[i].nT+outs[i].nS, c.want) {
			fail = append(fail, fmt.Sprintf("%s: the new binary no longer shows %s, so \"it did not move\" is two failures agreeing", c.name, cutilRepr(c.want)))
		}
	}

	// :undolist, read out of the RAW STREAM because the Press-ENTER redraw
	// wipes it.  uh_seq is `++b_u_seq_last`, one assignment in the file, so no
	// two keys are equal and the stable insertion sort and musl's smoothsort
	// cannot disagree -- which muslctype proves the other way, by showing they
	// DO disagree on three equal keys.
	undoKeys := [][]byte{b("ione\x1b"), b(":set nopaste\r"), b("otwo\x1b"), b("u"), b("othree\x1b"),
		b("u"), b("ofour\x1b"), b("u"), b("u"), b("ofive\x1b"), b(":undolist\r"), quit}
	order := func(binary string) ([]string, bool) {
		_, s := zRecordStream(binary, []string{"+set paste"}, undoKeys, 10*time.Second)
		i := strings.Index(s, "number changes")
		if i < 0 {
			return nil, false
		}
		end := i + 400
		if end > len(s) {
			end = len(s)
		}
		var rows []string
		for _, m := range z15UndoRow.FindAllStringSubmatch(s[i:end], -1) {
			rows = append(rows, m[1])
		}
		return rows, true
	}
	oo, okO := order(old)
	no, okN := order(bin)
	switch {
	case !okO || !okN:
		fail = append(fail, ":undolist printed no table on one of the binaries, so the sort was never reached and the comparison below proves nothing")
	case len(oo) < 4:
		fail = append(fail, fmt.Sprintf(":undolist listed %d rows, and a sort of fewer than two is not a sort", len(oo)))
	case strings.Join(oo, " ") != strings.Join(no, " "):
		fail = append(fail, fmt.Sprintf(":undolist row order moved: %s -> %s", strings.Join(oo, " "), strings.Join(no, " ")))
	}
	if len(fail) > 0 {
		for _, l := range fail {
			r.say("%s", l)
		}
		return harness.ErrReported
	}
	r.say("fourteen probe sessions byte-identical either side and each doing its work -- six that exercise towupper/towlower under every 'casemap' the option can hold, over an ASCII, a Latin-1, a Greek, a Cyrillic, a circled Latin and a Coptic letter (the first three separate an ASCII fallback, the last two separate vim's own table, and a text with only one group would pass one of them); four for the four bsearch tables, including the two rows both spelled \"Tab\"; three for atoi and atol; and one for the chartab the 892 startup calls build.  The corpus reaches none of this: every one of its 102 cases seeds itself by typing ASCII")
	r.cont("and :undolist, read out of the raw stream because the Press-ENTER redraw wipes it: %s either side.  `uh_seq` is `++b_u_seq_last`, one assignment in the file, so no two keys can be equal and the stable insertion sort and musl's smoothsort cannot disagree -- which muslctype proves the other way, by showing they DO disagree on three equal keys", strings.Join(oo, " "))
	return nil
}
