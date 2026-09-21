package check

import (
	"bytes"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"

	"slimvim.local/tools/internal/harness"
)

func init() { register("zero24", Zero24) }

// pyRepr is Python's repr() of a str: single quotes unless the text holds a
// single quote and no double one, and backslash escapes for the rest.
func pyRepr(s string) string {
	q := byte('\'')
	if strings.IndexByte(s, '\'') >= 0 && strings.IndexByte(s, '"') < 0 {
		q = '"'
	}
	var b strings.Builder
	b.WriteByte(q)
	for i := 0; i < len(s); i++ {
		c := s[i]
		switch {
		case c == '\\':
			b.WriteString(`\\`)
		case c == q:
			b.WriteByte('\\')
			b.WriteByte(c)
		case c == '\n':
			b.WriteString(`\n`)
		case c == '\r':
			b.WriteString(`\r`)
		case c == '\t':
			b.WriteString(`\t`)
		case c < 0x20 || c == 0x7f:
			fmt.Fprintf(&b, `\x%02x`, c)
		default:
			b.WriteByte(c)
		}
	}
	b.WriteByte(q)
	return b.String()
}

// wformat reads a -Wformat=2 run's stderr: the -Wformat-nonliteral count and
// every function heading, in order.  gcc quotes an identifier with ‘x’ or 'x'
// depending on the locale, so both are matched.
func wformat(txt string) (int, []string) {
	n := strings.Count(txt, "[-Wformat-nonliteral]")
	var fns []string
	for _, m := range z22InFunc.FindAllStringSubmatch(txt, -1) {
		if m[1] != "" {
			fns = append(fns, m[1])
		} else {
			fns = append(fns, m[2])
		}
	}
	return n, fns
}

func distinct(s []string) map[string]bool {
	m := map[string]bool{}
	for _, v := range s {
		m[v] = true
	}
	return m
}

// z24StripUnused is re.sub(r'(?<=\S)  __attribute__\(\(unused\)\) (?=[,)])', '', l).
func z24StripUnused(l string) string {
	const a = "  __attribute__((unused)) "
	var b strings.Builder
	i := 0
	for {
		k := strings.Index(l[i:], a)
		if k < 0 {
			b.WriteString(l[i:])
			return b.String()
		}
		k += i
		e := k + len(a)
		if k > 0 && l[k-1] != ' ' && l[k-1] != '\t' && l[k-1] != '\n' && l[k-1] != '\r' && l[k-1] != '\f' && l[k-1] != '\v' &&
			e < len(l) && (l[e] == ',' || l[e] == ')') {
			b.WriteString(l[i:k])
			i = e
			continue
		}
		b.WriteString(l[i : k+1])
		i = k + 1
	}
}

type z24Job struct {
	done chan struct{}
	err  error
	out  string
}

func z24Go(env []string, name string, a ...string) *z24Job {
	j := &z24Job{done: make(chan struct{})}
	go func() {
		defer close(j.done)
		c := exec.Command(name, a...)
		if env != nil {
			c.Env = env
		}
		var eb bytes.Buffer
		c.Stderr = &eb
		j.err = c.Run()
		j.out = eb.String()
	}()
	return j
}

func (j *z24Job) wait() *z24Job { <-j.done; return j }

var (
	z24AttrKind = regexp.MustCompile(`__attribute__\(\((\w+)`)
	z24Warn     = regexp.MustCompile(`^.*?:(\d+):\d+: warning: .*\[-W([a-z-]+)=?\]$`)
	z24Unused   = regexp.MustCompile(`^.*?:(\d+):\d+: warning: unused parameter .(\w+)`)
)

// Zero24 is phase 24's check: the attributes.
func Zero24(w io.Writer, args []string) error {
	if len(args) < 2 {
		return fmt.Errorf("usage: check zero24 <work-dir> <state-dir>")
	}
	work, state := args[0], args[1]
	r := &rep{tag: "attrs", w: w}
	f := filepath.Join(work, "zero-vim.c")
	oldF := filepath.Join(state, "old.c")
	beforeLines := strings.TrimSpace(readFile(filepath.Join(state, "input-lines")))
	tmp, err := os.MkdirTemp("", "zero24")
	if err != nil {
		return err
	}
	var jobs []*z24Job
	defer func() {
		for _, j := range jobs {
			j.wait()
		}
		os.RemoveAll(tmp)
	}()
	T := func(n string) string { return filepath.Join(tmp, n) }
	mk := readFile(filepath.Join(work, "Makefile"))
	cflags, ldflags := strings.Fields(z9Flag(mk, "CFLAGS")), strings.Fields(z9Flag(mk, "LDFLAGS"))
	newC, oldC := readFile(f), readFile(oldF)
	stop := func(format string, a ...any) error { r.say(format, a...); return harness.ErrReported }
	sde := append(os.Environ(), "SOURCE_DATE_EPOCH=0")
	link := func(out, src string) *z24Job {
		a := append(append(append([]string{}, cflags...), ldflags...), "-o", out, src)
		j := z24Go(sde, "gcc", a...)
		jobs = append(jobs, j)
		return j
	}
	gcc := func(a ...string) *z24Job { j := z24Go(nil, "gcc", a...); jobs = append(jobs, j); return j }
	jNew := link(T("new"), f)

	// the four controls
	const FMT = "  __attribute__((format(printf, 3, 4))) "
	if strings.Count(newC, FMT) != 1 {
		return stop("vim_snprintf's `%s` is not in the output exactly once, so c1 would not be a control", strings.TrimSpace(FMT))
	}
	c1 := strings.Replace(newC, FMT, " ", 1)
	const ARG = "static inline __attribute__((format_arg(1))) char *_(const char *x)"
	if strings.Count(newC, ARG) != 1 {
		return stop("`%s` is not in the output exactly once, so c2 would not be a control", ARG)
	}
	c2 := strings.Replace(newC, ARG, "static inline char *_(const char *x)", 1)
	const FT = "[[fallthrough]];"
	n3 := strings.Count(newC, FT)
	if n3 == 0 {
		return stop("there is no `[[fallthrough]];` in the output, so c3 would not be a control")
	}
	c3 := strings.ReplaceAll(newC, FT, strings.Repeat(" ", len(FT)))
	i4 := strings.Index(newC, FT)
	c4 := newC[:i4] + "break;" + strings.Repeat(" ", len(FT)-len("break;")) + newC[i4+len(FT):]
	for _, p := range [][2]string{{"c1", c1}, {"c2", c2}, {"c3", c3}, {"c4", c4}} {
		if p[1] == newC {
			return stop("%s changed nothing", p[0])
		}
		os.WriteFile(T(p[0]+".c"), []byte(p[1]), 0o644)
	}
	r.say("four controls written: c1 vim_snprintf's format(printf, 3, 4) removed, c2 `_()`'s format_arg(1) removed, c3 all %d `[[fallthrough]];` blanked, c4 one of them replaced by `break;`", n3)
	jC4 := link(T("c4"), T("c4.c"))
	wf2 := func(src string) *z24Job { return gcc("-O0", "-fno-stack-protector", "-Wformat=2", "-fsyntax-only", src) }
	jC1, jC2 := wf2(T("c1.c")), wf2(T("c2.c"))
	jC3 := gcc("-c", "-O0", "-fno-stack-protector", "-Wall", "-Wextra", "-Wno-unused-parameter", "-o", "/dev/null", T("c3.c"))
	jC3s := gcc("-O0", "-fno-stack-protector", "-Wall", "-Wextra", "-Wno-unused-parameter", "-fsyntax-only", T("c3.c"))
	jPo := gcc("-O0", "-fno-stack-protector", "-fsyntax-only", "-Wall", "-Wextra", oldF)
	jPn := gcc("-O0", "-fno-stack-protector", "-fsyntax-only", "-Wall", "-Wextra", f)
	jWo, jWn := wf2(oldF), wf2(f)
	j11o, j11n := gcc("-std=c11", "-fsyntax-only", oldF), gcc("-std=c11", "-fsyntax-only", f)
	os.WriteFile(T("canon.c"), []byte(newC), 0o644)
	jCanon := &z24Job{done: make(chan struct{})}
	jobs = append(jobs, jCanon)
	go func() {
		defer close(jCanon.done)
		o, e := exec.Command("tools/canon.sh", T("canon.c")).CombinedOutput()
		jCanon.out, jCanon.err = string(o), e
	}()

	// --- 1. the source, as arithmetic on the input ---------------------------
	var before int
	fmt.Sscan(beforeLines, &before)
	var fail []string
	KINDS := []string{"unused", "fallthrough", "format", "format_arg"}
	kinds := func(t string) map[string]int {
		d := map[string]int{}
		for _, k := range KINDS {
			d[k] = 0
		}
		for _, m := range z24AttrKind.FindAllStringSubmatch(t, -1) {
			d[m[1]]++
		}
		return d
	}
	ko, kn := kinds(oldC), kinds(newC)
	var unknown []string
	for k := range ko {
		if !contains(KINDS, k) {
			unknown = append(unknown, k)
		}
	}
	sort.Strings(unknown)
	if len(unknown) > 0 {
		fail = append(fail, "the INPUT holds an attribute this phase never looked at: "+strings.Join(unknown, " "))
	}
	for _, p := range []struct {
		name string
		want int
		why  string
	}{
		{"unused", 0, fmt.Sprintf("every one of the %d, and they said nothing under -Wno-unused-parameter", ko["unused"])},
		{"fallthrough", 0, fmt.Sprintf("every one of the %d, respelled rather than removed", ko["fallthrough"])},
		{"format", ko["format"], "KEPT: it is what type-checks the arguments of every formatted message in the file"},
		{"format_arg", ko["format_arg"], "KEPT: it is what lets -Wformat see THROUGH `_()` and `NGETTEXT`"},
	} {
		if kn[p.name] != p.want {
			fail = append(fail, fmt.Sprintf("`%s` has %d attributes in the output, expected %d -- %s", p.name, kn[p.name], p.want, p.why))
		}
	}
	nC23 := len(regexp.MustCompile(`(?m)^[ ]*\[\[fallthrough\]\];$`).FindAllString(newC, -1))
	if nC23 != ko["fallthrough"] || strings.Count(newC, "[[") != ko["fallthrough"] {
		fail = append(fail, fmt.Sprintf("the output has %d standalone `[[fallthrough]];` and %d `[[` where the input had %d GNU fallthrough attributes -- the swap is ONE FOR ONE", nC23, strings.Count(newC, "[["), ko["fallthrough"]))
	}
	if strings.Contains(oldC, "[[") {
		fail = append(fail, "the INPUT already held `[[`, so this phase did not introduce the C23 spelling and the count above is not its own")
	}
	OL, NL := strings.Split(oldC, "\n"), strings.Split(newC, "\n")
	fmtRe := regexp.MustCompile(`format(_arg)?\(`)
	var keep []int
	for i, l := range OL {
		if strings.Contains(l, "__attribute__") && fmtRe.MatchString(l) {
			keep = append(keep, i)
		}
	}
	var moved []string
	for _, i := range keep {
		if i >= len(NL) || NL[i] != OL[i] {
			moved = append(moved, strconv.Itoa(i+1))
		}
	}
	if len(moved) > 0 {
		s := "s"
		if len(moved) == 1 {
			s = ""
		}
		fail = append(fail, fmt.Sprintf("a line carrying a kept attribute is not the line it was, byte for byte: line%s %s", s, strings.Join(moved, " ")))
	}
	ka := 0
	for _, i := range keep {
		if i < len(NL) {
			ka += strings.Count(NL[i], "__attribute__")
		}
	}
	if ka != ko["format"]+ko["format_arg"] {
		fail = append(fail, fmt.Sprintf("the %d kept attributes are not all on the %d lines this phase named", ko["format"]+ko["format_arg"], len(keep)))
	}
	var changed, heads, falls []int
	if len(NL) != len(OL) || len(NL)-1 != before {
		fail = append(fail, fmt.Sprintf("the file is %d lines and the input was %d (%d recorded) -- neither edit adds or removes a line", len(NL)-1, len(OL)-1, before))
	} else {
		hf := map[int]bool{}
		for i := range OL {
			if OL[i] != NL[i] {
				changed = append(changed, i)
			}
			if strings.Contains(OL[i], "__attribute__((unused))") {
				heads = append(heads, i)
				hf[i] = true
			}
			if strings.Contains(OL[i], "__attribute__((fallthrough));") {
				falls = append(falls, i)
				hf[i] = true
			}
		}
		var u []int
		for i := range hf {
			u = append(u, i)
		}
		sort.Ints(u)
		if fmt.Sprint(changed) != fmt.Sprint(u) {
			fail = append(fail, fmt.Sprintf("%d lines changed and the attributes sat on %d -- the two must be the same set", len(changed), len(u)))
		}
		for _, i := range heads {
			want := z24StripUnused(OL[i])
			if NL[i] != want {
				fail = append(fail, fmt.Sprintf("line %d is %s and stripping its attributes gives %s", i+1, pyRepr(NL[i]), pyRepr(want)))
				break
			}
		}
		if len(falls) != ko["fallthrough"] {
			fail = append(fail, fmt.Sprintf("the %d fallthrough attributes are not on %d lines of their own", ko["fallthrough"], len(falls)))
		}
	}
	dsp := regexp.MustCompile(`  [,)]`)
	po, pn := len(dsp.FindAllString(oldC, -1)), len(dsp.FindAllString(newC, -1))
	if po != pn {
		fail = append(fail, fmt.Sprintf("%d doubled spaces before a `,` or `)` in the output where the input had %d -- the attribute must go with ITS OWN two spaces and the one after it", pn, po))
	}
	sds := regexp.MustCompile(`\S  [,)]`)
	if sds.MatchString(newC) && !sds.MatchString(oldC) {
		fail = append(fail, "the output has a declarator followed by two spaces and a `,` or `)` where the input had none")
	}
	rows := z6RowRe.FindAllString(newC, -1)
	got, _ := harness.CommandNamesIn([]byte(newC), "zero-vim.c")
	if len(rows) != 98 || len(got) != 98 {
		fail = append(fail, "cmdnames[] is not the 98 rows phase 10 left -- this phase touches no Ex command")
	}
	if i := strings.Index(newC, "static struct vimoption options[]"); i >= 0 {
		j := strings.Index(newC[i:], "\n};")
		if m := len(z12RowRe.FindAllString(newC[i:i+j], -1)); m != 107 {
			fail = append(fail, fmt.Sprintf("options[] has %d rows, expected the 107 phase 20 left -- this phase removes no option", m))
		}
	}
	var d []string
	for _, l := range NL {
		if strings.HasPrefix(l, "#") {
			d = append(d, l)
		}
	}
	dirOK := len(d) == 11 && len(NL) >= 11 && strings.Join(NL[:11], "\n") == strings.Join(d, "\n")
	for _, l := range d {
		if !strings.HasPrefix(l, "#include <") {
			dirOK = false
		}
	}
	if !dirOK {
		fail = append(fail, "the output does not have exactly the eleven `#include` directives phase 21 left, on its first eleven lines.  `[[fallthrough]]` is a STATEMENT and not a directive, and MOVING THEM IS A LATER PHASE")
	}
	for k := 1; k < len(NL); k++ {
		if NL[k] == "" && NL[k-1] == "" {
			fail = append(fail, "there is a run of two blank lines, which canon.sh should have taken")
			break
		}
	}
	if len(fail) > 0 {
		for _, l := range fail {
			r.say("%s", l)
		}
		return harness.ErrReported
	}
	sum := func(m map[string]int) int {
		s := 0
		for _, v := range m {
			s += v
		}
		return s
	}
	r.say("`__attribute__` %d -> %d.  unused %d -> 0, fallthrough %d -> 0 and `[[fallthrough]];` 0 -> %d, format %d and format_arg %d KEPT on %d lines that are BYTE-IDENTICAL to the input's.  Every count is computed FROM THE INPUT, so this is a check on the phase and not on whatever it was handed",
		sum(ko), sum(kn), ko["unused"], ko["fallthrough"], nC23, ko["format"], ko["format_arg"], len(keep))
	r.cont("%d lines, unchanged, and the %d that differ are exactly the %d function headers and the %d fallthrough statements -- both edits are WITHIN lines.  The doubled-space count before a `,` or `)` is %d either side, which is the trap: an attribute deleted without its own two spaces leaves something canon.sh does not fix",
		len(NL)-1, len(changed), len(heads), len(falls), pn)
	r.cont("cmdnames[] 98 unchanged, options[] 107 unchanged, and ELEVEN #includes on the first eleven lines -- `[[fallthrough]]` is C23 attribute syntax, a statement in the grammar, and adds no preprocessor line")

	// --- 2. the 113 were parameters, and 21 of them were used -----------------
	jPo.wait()
	jPn.wait()
	if err := z24Params(r, oldC, jPo.out, jPn.out); err != nil {
		return err
	}

	// --- 3. the fallthroughs -------------------------------------------------
	jC3.wait()
	jC3s.wait()
	if err := z24Fall(r, NL, jC3.out, jC3s.out); err != nil {
		return err
	}

	// --- 4. C23, and that it is not a new dependency --------------------------
	if err := z24C23(w, r, newC, tmp, j11o, j11n); err != nil {
		return err
	}

	// --- 5. -Wformat=2 -------------------------------------------------------
	jWo.wait()
	jWn.wait()
	jC1.wait()
	jC2.wait()
	no, fo := wformat(jWo.out)
	nn, fn := wformat(jWn.out)
	n1, _ := wformat(jC1.out)
	n2, _ := wformat(jC2.out)
	if no != nn || strings.Join(fo, "\x00") != strings.Join(fn, "\x00") {
		r.say("-Wformat=2 MOVED: %d warnings in %d function headings before, %d in %d after -- the six attributes this phase KEEPS are what gcc reads to produce them", no, len(fo), nn, len(fn))
		a, b := distinct(fo), distinct(fn)
		var ab, ba []string
		for k := range a {
			if !b[k] {
				ab = append(ab, k)
			}
		}
		for k := range b {
			if !a[k] {
				ba = append(ba, k)
			}
		}
		sort.Strings(ab)
		sort.Strings(ba)
		if len(ab) > 0 {
			r.cont("functions that stopped warning: %s", strings.Join(ab, " "))
		}
		if len(ba) > 0 {
			r.cont("functions that started: %s", strings.Join(ba, " "))
		}
		return harness.ErrReported
	}
	if no != 115 || len(distinct(fo)) != 53 {
		return stop("-Wformat=2 gives %d warnings in %d distinct functions, expected 115 in 53 -- the equality above still holds, but this is not the tree the phase was measured on", no, len(distinct(fo)))
	}
	if n1 != 0 || n2 <= no {
		return stop("THE CONTROLS DID NOT SHOW.  Removing vim_snprintf's format(printf, 3, 4) gives %d warnings and must give 0 -- gcc stops checking formats at all -- and removing `_()`'s format_arg(1) gives %d and must give MORE than %d, gcc losing the ability to see through the translation wrapper.  Without both, the equality above is two numbers agreeing (CLAUDE.md)", n1, n2, no)
	}
	r.say("-Wformat=2: THE IDENTICAL %d `-Wformat-nonliteral` warnings in THE IDENTICAL %d functions, before and after.  THIS IS THE EVIDENCE FOR THE SIX SURVIVORS AND THE BINARY CANNOT GIVE IT: an attribute emits no code, so a cmp-identical build is equally happy without them", no, len(distinct(fo)))
	r.cont("AND IT CAN FAIL, IN BOTH DIRECTIONS.  With vim_snprintf's format(printf, 3, 4) removed the count is %d -- gcc checks no format anywhere, and phase 22 is why one attribute now carries 201 `vim_snprintf` mentions.  With `_()`'s format_arg(1) removed it is %d, %d MORE: that attribute is what lets -Wformat see THROUGH the translation wrapper, which CLAUDE.md names as the reason `_()` and `NGETTEXT` were never macro-expanded", n1, n2, n2-no)
	if err := z24Buys(w, r, NL, tmp); err != nil {
		return err
	}

	// --- 6. the compile, the linkage and the libc surface ---------------------
	beforeU := readFile(filepath.Join(state, "symbols", "undefined"))
	if err := run(w, "sh", "tools/phasecheck.sh", work, f, filepath.Join(state, "symbols")); err != nil {
		return harness.ErrReported
	}
	afterU := readFile(".cache/symbols/last/undefined")
	if beforeU != afterU {
		b, a := strings.Fields(beforeU), strings.Fields(afterU)
		r.say("the libc surface moved, and DELETING A DIAGNOSTIC HINT CANNOT MOVE IT:")
		r.cont("gone: %s", trSpace(comm23(b, a)))
		r.cont("came: %s", trSpace(comm23(a, b)))
		return harness.ErrReported
	}
	r.say("symbols %s -> %s, and the set is IDENTICAL as a cmp -- nothing left and nothing arrived; main is still the only external symbol",
		strings.TrimSpace(readFile(".cache/symbols/last/before")), strings.TrimSpace(readFile(".cache/symbols/last/after")))

	// --- 7. the binary -------------------------------------------------------
	jCanon.wait()
	if readFile(T("canon.c")) != newC {
		r.say("tools/canon.sh CHANGED THE OUTPUT, and it must be a no-op:")
		o, _ := exec.Command("diff", f, T("canon.c")).Output()
		for _, l := range head(strings.Split(strings.TrimRight(string(o), "\n"), "\n"), 6) {
			fmt.Fprintln(w, "               "+l)
		}
		r.cont("The 113 deletions take the two spaces before the attribute and")
		r.cont("the one after with them.  If canon moved something, the edit is")
		r.cont("wrong and canon is not the fix.")
		return harness.ErrReported
	}
	canonTail := ""
	cre := regexp.MustCompile(`^.*canon *(.*)$`)
	for _, l := range strings.Split(jCanon.out, "\n") {
		if m := cre.FindStringSubmatch(l); m != nil {
			canonTail = m[1]
			break
		}
	}
	r.say("tools/canon.sh is a NO-OP on the output (%s)", canonTail)

	bl := &rep{tag: "build", w: w}
	_ = exec.Command("make", "-C", work, "clean").Run()
	if _, err := os.Stat(filepath.Join(work, "zero-vim")); err == nil {
		bl.say("the clean did not remove zero-vim, so a 'rebuild' below could be no rebuild at all")
		return harness.ErrReported
	}
	if err := exec.Command("make", "-C", work).Run(); err != nil {
		bl.say("FAILED -- rerun by hand: make -C %s", work)
		return harness.ErrReported
	}
	bin := filepath.Join(work, "zero-vim")
	bl.say("ok, %s -> %d lines, %d bytes", beforeLines, countLines([]byte(readFile(f))), sizeOf(bin))
	if jNew.wait().err != nil {
		return stop("the reproducible build of the output failed")
	}
	oldBin := filepath.Join(state, "old")
	oldSize, newSize := sizeOf(oldBin), sizeOf(T("new"))
	if newSize < 500000 || oldSize < 500000 {
		return stop("one of the two binaries is %d / %d bytes, which is not an editor -- a cmp of two files nothing wrote passes", oldSize, newSize)
	}
	if newSize != sizeOf(bin) {
		return stop("the reproducible build is %d bytes and make produced %d: the two differ by more than a timestamp, so the comparison below would not be about this boundary", newSize, sizeOf(bin))
	}
	ob := []byte(readFile(oldBin))
	if !bytes.Equal(ob, []byte(readFile(T("new")))) {
		r.say("THE BINARY MOVED.  This phase deletes 113 attributes that only")
		for _, l := range []string{
			"ever suppressed a diagnostic and respells 20 that only ever",
			"gave one a hint, so the two binaries -- the input's and the",
			"output's, both built with SOURCE_DATE_EPOCH=0 and the",
			"boundary's own flags -- must be the same bytes.",
			fmt.Sprintf("%d in, %d out.  The GNU build-id note is a hash of", oldSize, newSize),
			"the whole image and sits near the front, so the first difference",
			"below is always that note and never the change itself:"} {
			r.cont("%s", l)
		}
		o, _ := exec.Command("cmp", oldBin, T("new")).CombinedOutput()
		for _, l := range strings.Split(strings.TrimRight(string(o), "\n"), "\n") {
			fmt.Fprintln(w, "               "+l)
		}
		return harness.ErrReported
	}
	r.say("THE BINARY IS BYTE-IDENTICAL, %d bytes either side -- tier 1 of CLAUDE.md's verification table, and the whole of this phase's evidence for the 133 it removed and respelled.  A byte-identical binary subsumes every screen case, every Ex-command row, every command line and every pty scenario at once, because the program that would be run is the same program; tools/zerodelta.sh --phase 24 runs next and corroborates rather than proves", newSize)
	if jC4.wait().err != nil {
		r.say("the control c4 did not build:")
		for _, l := range head(strings.Split(strings.TrimRight(jC4.out, "\n"), "\n"), 5) {
			fmt.Fprintln(w, "               "+l)
		}
		return harness.ErrReported
	}
	c4b := []byte(readFile(T("c4")))
	if bytes.Equal(ob, c4b) {
		r.say("THE CONTROL c4 DID NOT SHOW.  This phase's own output with one")
		r.cont("`[[fallthrough]];` replaced by `break;` gives a binary IDENTICAL")
		r.cont("to the input's, so the cmp above is two numbers agreeing and")
		r.cont("proves nothing.  A test that cannot fail is not evidence")
		r.cont("(CLAUDE.md).")
		return harness.ErrReported
	}
	r.say("AND IT CAN FAIL: this phase's own output with ONE `[[fallthrough]];` replaced by `break;` -- the smallest change at these 20 sites that is a change to the PROGRAM and not to a diagnostic -- differs from the input's binary in %d bytes", z23CmpL(ob, c4b))
	return nil
}

type z24W struct {
	line int
	name string
}

func z24Params(r *rep, oldC, pOld, pNew string) error {
	OL := strings.Split(oldC, "\n")
	warns := func(txt string) (map[z24W]bool, map[string]int) {
		out, kinds := map[z24W]bool{}, map[string]int{}
		for _, l := range strings.SplitAfter(txt, "\n") {
			if l == "" {
				continue
			}
			if m := z24Warn.FindStringSubmatch(strings.TrimRight(l, " \t\n\r\f\v")); m != nil {
				kinds[m[2]]++
			}
			if m := z24Unused.FindStringSubmatch(l); m != nil {
				n, _ := strconv.Atoi(m[1])
				out[z24W{n, m[2]}] = true
			}
		}
		return out, kinds
	}
	a, ka := warns(pOld)
	b, kb := warns(pNew)
	onlyUP := len(kb) == 1 && kb["unused-parameter"] > 0
	extraA := false
	for k := range ka {
		if k != "unused-parameter" {
			extraA = true
		}
	}
	if !onlyUP || extraA {
		all := map[string]bool{}
		for k := range ka {
			all[k] = true
		}
		for k := range kb {
			all[k] = true
		}
		var ks []string
		for k := range all {
			ks = append(ks, k)
		}
		sort.Strings(ks)
		return (func() error {
			r.say("with -Wunused-parameter ON the output warns about %s -- if a deletion had reached an object the compiler would have said `unused-variable`, and this section is what would catch it", strings.Join(ks, " "))
			return harness.ErrReported
		})()
	}
	var nw []z24W
	for k := range b {
		if !a[k] {
			nw = append(nw, k)
		}
	}
	subset := len(b) < len(a)
	if subset {
		for k := range b {
			if !a[k] {
				subset = false
			}
		}
	}
	if subset || len(nw) == 0 {
		r.say("the output warns %d times and the input %d, and every input warning must still be there with more beside it", len(b), len(a))
		return harness.ErrReported
	}
	unRe := regexp.MustCompile(`__attribute__\(\(unused\)\)`)
	perLine := map[int]int{}
	sites := map[int]bool{}
	nSites := 0
	for _, m := range unRe.FindAllStringIndex(oldC, -1) {
		i := strings.Count(oldC[:m[0]], "\n") + 1
		perLine[i]++
		sites[i] = true
		nSites++
	}
	var stray []z24W
	for _, x := range nw {
		if !sites[x.line] {
			stray = append(stray, x)
		}
	}
	if len(stray) > 0 {
		sort.Slice(stray, func(i, j int) bool {
			if stray[i].line != stray[j].line {
				return stray[i].line < stray[j].line
			}
			return stray[i].name < stray[j].name
		})
		var s []string
		for _, x := range head2(stray, 5) {
			s = append(s, fmt.Sprintf("(%d, %s)", x.line, pyRepr(x.name)))
		}
		r.say("%d of the new warnings are not on a line that carried an attribute: [%s]", len(stray), strings.Join(s, ", "))
		return harness.ErrReported
	}
	var lines []int
	for i := range perLine {
		lines = append(lines, i)
	}
	sort.Ints(lines)
	type ik struct{ i, k int }
	var used []ik
	usedSum := 0
	for _, i := range lines {
		c := 0
		for _, x := range nw {
			if x.line == i {
				c++
			}
		}
		if k := perLine[i] - c; k != 0 {
			used = append(used, ik{i, k})
			usedSum += k
		}
	}
	if usedSum != nSites-len(nw) {
		r.say("the per-site arithmetic does not add up: %d sites, %d warnings, %d unaccounted", nSites, len(nw), usedSum-(nSites-len(nw)))
		return harness.ErrReported
	}
	fname := func(i int) string {
		if m := regexp.MustCompile(`^(\w+)`).FindString(OL[i-1]); m != "" {
			return m
		}
		return "?"
	}
	var names []string
	for k, u := range used {
		if k >= 6 {
			break
		}
		names = append(names, fname(u.i)+"()")
	}
	r.say("WITH `-Wunused-parameter` TURNED BACK ON -- the one warning the sweep switches off -- the output warns %d times and the input %d, and every one of the %d new is `-Wunused-parameter` at a line that carried an attribute.  Not one is `-Wunused-variable`, which is what a deletion that reached an object would have produced", len(b), len(a), len(nw))
	r.cont("AND %d SITES GAVE %d WARNINGS, so %d OF THE %d MARKED A PARAMETER THIS BUILD USES -- the attribute was not redundant there, it was FALSE, and deleting it deletes a wrong statement rather than a useless one.  In %d functions, among them %s", nSites, len(nw), nSites-len(nw), nSites, len(used), strings.Join(names, ", "))
	return nil
}

func head2(s []z24W, n int) []z24W {
	if len(s) > n {
		return s[:n]
	}
	return s
}

func z24Fall(r *rep, NL []string, ctl, syn string) error {
	var sites []int
	for i, l := range NL {
		if strings.TrimSpace(l) == "[[fallthrough]];" {
			sites = append(sites, i+1)
		}
	}
	n := strings.Count(ctl, "may fall through")
	if n != len(sites)-2 {
		r.say("the control -- this phase's own output with all %d `[[fallthrough]];` blanked -- warns %d times, and the phase was measured on %d.  Two of the %d sit after a case label with NO statement, where C falls through silently and gcc has nothing to diagnose; a third one becoming redundant, or one of those two becoming live, is a change in the switch and not in this phase", len(sites), n, len(sites)-2, len(sites))
		return harness.ErrReported
	}
	if strings.Contains(syn, "may fall through") {
		r.say("`-fsyntax-only` reported a fallthrough warning, and the note at the top of this file says it cannot -- if that has changed, the reason this section uses a real compile has changed with it")
		return harness.ErrReported
	}
	if !regexp.MustCompile(`\bwarning\b`).MatchString(ctl) || !strings.Contains(ctl, "-Wimplicit-fallthrough") {
		r.say("the control produced no `-Wimplicit-fallthrough` warning at all, so this section is checking nothing")
		return harness.ErrReported
	}
	type q struct {
		s int
		l string
	}
	var quiet []q
	for _, s := range sites {
		j := s - 2
		for j >= 0 && strings.TrimSpace(NL[j]) == "" {
			j--
		}
		if j >= 0 && strings.HasSuffix(strings.TrimSpace(NL[j]), ":") {
			quiet = append(quiet, q{s, strings.TrimSpace(NL[j])})
		}
	}
	if len(quiet) != len(sites)-n {
		var s []string
		for _, x := range quiet {
			s = append(s, fmt.Sprintf("%d %s", x.s, pyRepr(x.l)))
		}
		r.say("%d of the %d sites follow a bare label and the control leaves %d unwarned -- the structure and the compiler must agree on WHICH are already redundant, and they do not: %s", len(quiet), len(sites), len(sites)-n, strings.Join(s, " "))
		return harness.ErrReported
	}
	var qs []string
	for _, x := range quiet {
		qs = append(qs, fmt.Sprintf("line %d after %s", x.s, pyRepr(x.l)))
	}
	r.say("`-Wimplicit-fallthrough` is silent on the output, and the control -- all %d `[[fallthrough]];` blanked -- warns %d times.  So the C23 spelling suppresses exactly what the GNU one did and not one of the %d suppressions was lost", len(sites), n, len(sites))
	r.cont("%d OF THE %d ARE ALREADY REDUNDANT AND THEY ARE KEPT: %s.  Each follows a case label with no statement at all, where the language falls through silently and gcc has nothing to diagnose -- computed from the STRUCTURE and agreeing with the control on the number, which is two independent methods rather than one.  What makes a fallthrough deliberate is the author saying so, not the compiler currently asking; pruning them would be pruning by the shape of a switch that a later phase may change back", len(quiet), len(sites), strings.Join(qs, ", "))
	r.cont("AND THE TOOL MATTERS: the same control under `-fsyntax-only` warns ZERO times, because -Wimplicit-fallthrough needs the CFG.  That is CLAUDE.md's `-fsyntax-only` lesson on a second warning -- a section written with it would have passed while checking nothing")
	return nil
}

func z24C23(w io.Writer, r *rep, newC, tmp string, j11o, j11n *z24Job) error {
	const stmt = "[[fallthrough]];"
	if !strings.Contains(newC, stmt) {
		r.say("there is no [[fallthrough]]; in the output to take")
		return harness.ErrReported
	}
	ft := "static int f(int x)\n{\n    int r = 0;\n    switch (x)\n    {\n    case 1:\n        r = 1;\n        " + stmt +
		"\n    case 2:\n        r += 2;\n        break;\n    }\n    return r;\n}\nint main(void) { return f(1) - 3; }\n"
	ftc, gnuc := filepath.Join(tmp, "ft.c"), filepath.Join(tmp, "gnu.c")
	os.WriteFile(ftc, []byte(ft), 0o644)
	os.WriteFile(gnuc, []byte(strings.Replace(ft, stmt, "__attribute__((fallthrough));", 1)), 0o644)
	indent4 := func(s string) {
		for _, l := range head(strings.Split(strings.TrimRight(s, "\n"), "\n"), 4) {
			fmt.Fprintln(w, "               "+l)
		}
	}
	for _, std := range []string{"DEFAULT", "-std=c23"} {
		a := []string{"-Wall", "-Wextra", "-Wpedantic", "-Wimplicit-fallthrough", "-o", filepath.Join(tmp, "ft"), ftc}
		if std != "DEFAULT" {
			a = append([]string{std}, a...)
		}
		c := exec.Command("gcc", a...)
		var eb bytes.Buffer
		c.Stderr = &eb
		if c.Run() != nil {
			r.say("%s is REFUSED under %s, and this phase requires it:", stmt, std)
			indent4(eb.String())
			return harness.ErrReported
		}
		if eb.Len() > 0 {
			r.say("the C23 statement draws a diagnostic under %s -Wpedantic, and it must not:", std)
			indent4(eb.String())
			return harness.ErrReported
		}
		if exec.Command(filepath.Join(tmp, "ft")).Run() != nil {
			r.say("the probe ran and the fallthrough did not fall through")
			return harness.ErrReported
		}
	}
	for _, std := range []string{"-std=c11", "-std=c99"} {
		if exec.Command("gcc", std, "-pedantic-errors", "-c", "-o", "/dev/null", ftc).Run() == nil {
			r.say("the C23 statement is ACCEPTED under %s -pedantic-errors, and it must not be:", std)
			r.cont("`[[]]` attributes are C23, and a check that passes there is")
			r.cont("not stating what this spelling costs.")
			return harness.ErrReported
		}
		if exec.Command("gcc", std, "-pedantic-errors", "-c", "-o", "/dev/null", gnuc).Run() != nil {
			r.say("the GNU spelling is REFUSED under %s -pedantic-errors, and the honest", std)
			r.cont("comparison this phase makes is that it is NOT -- a reserved identifier")
			r.cont("is pedantically clean everywhere, which is what the swap gives up.")
			return harness.ErrReported
		}
	}
	j11o.wait()
	j11n.wait()
	eOld, eNew := countLinesWith([]byte(j11o.out), "error:"), countLinesWith([]byte(j11n.out), "error:")
	if eOld != eNew || eOld < 100 {
		r.say("the whole file gives %d errors under -std=c11 before this phase and %d after.", eOld, eNew)
		r.cont("They must be equal and large: this file has been C23 since long before")
		r.cont("this phase -- enum : long, static_assert, lowercase bool, and phase 23's")
		r.cont("typeof and nullptr -- and respelling 20 attributes must not move the floor.")
		return harness.ErrReported
	}
	r.say("C23 IS NOT A NEW DEPENDENCY AND WHAT THE SPELLING COSTS IS STATED RATHER THAN GLOSSED: the statement taken out of the output compiles clean under gcc's default and -std=c23 with -Wall -Wextra -Wpedantic, and its probe runs; under -std=c11 and -std=c99 -pedantic-errors it is REFUSED, where the GNU spelling it replaces is ACCEPTED, being a reserved identifier.  So this swap alone would narrow the dialects -- and it costs nothing, because the WHOLE FILE already gives the same %d errors under -std=c11 before this phase and after it", eOld)
	return nil
}

func z24Buys(w io.Writer, r *rep, NL []string, tmp string) error {
	protoRe := regexp.MustCompile(`^static int vim_snprintf\(char \*, .*format\(printf, 3, 4\)`)
	proto, tdef := "", ""
	for _, l := range NL {
		if proto == "" && protoRe.MatchString(l) {
			proto = l
		}
		if tdef == "" && l == "typedef typeof(sizeof(0)) usize;" {
			tdef = l
		}
	}
	if proto == "" || tdef == "" {
		r.say("vim_snprintf's prototype, or phase 23's usize typedef, is not in the")
		r.cont("output in the shape this probe reads them -- the probe is built from")
		r.cont("the output's own lines and not from retyped ones, so it cannot pass")
		r.cont("while the file says something else.")
		return harness.ErrReported
	}
	fm := tdef + "\n" + proto + "\n" + "int probe(char *b, const char *s) { return vim_snprintf(b, 10, \"%d\", s); }\n"
	var nf []string
	for _, l := range strings.Split(fm, "\n") {
		nf = append(nf, strings.Replace(l, "  __attribute__((format(printf, 3, 4))) ", " ", 1))
	}
	nofm := strings.Join(nf, "\n")
	if fm == nofm {
		r.say("the probe and its control are the same text")
		return harness.ErrReported
	}
	fc, nc := filepath.Join(tmp, "fmt.c"), filepath.Join(tmp, "nofmt.c")
	os.WriteFile(fc, []byte(fm), 0o644)
	os.WriteFile(nc, []byte(nofm), 0o644)
	cc := func(src string) string {
		c := exec.Command("gcc", "-c", "-Wall", "-Wextra", "-o", "/dev/null", src)
		var eb bytes.Buffer
		c.Stderr = &eb
		c.Run()
		return eb.String()
	}
	fe, ne := cc(fc), cc(nc)
	if !strings.Contains(fe, "expects argument of type") {
		r.say("the %%d probe did not warn WITH the attribute, so it is not a probe:")
		for _, l := range head(strings.Split(strings.TrimRight(fe, "\n"), "\n"), 4) {
			fmt.Fprintln(w, "               "+l)
		}
		return harness.ErrReported
	}
	if strings.Contains(ne, "expects argument of type") {
		r.say("the %%d probe warned WITHOUT the attribute, so the attribute is not what catches it")
		return harness.ErrReported
	}
	r.say("AND WHAT IT BUYS, built from the output's OWN prototype and phase 23's OWN typedef: vim_snprintf(b, 10, \"%%d\", s) handed a const char * draws %d warning with the attribute and NOTHING AT ALL without it.  That is the whole argument for stopping at 133 removals and not 139", countLinesWith([]byte(fe), "expects argument of type"))
	return nil
}
