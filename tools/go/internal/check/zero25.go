package check

import (
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"

	"slimvim.local/tools/internal/harness"
)

func init() { register("zero25", Zero25) }

var (
	z25ProtoLn = regexp.MustCompile(`^static \w+ host_(exit|message)\(.*\);$`)
	z25CmdRow  = regexp.MustCompile(`(?m)^    \[CMD_\w+\] = \{.*$`)
	z25OptRow  = regexp.MustCompile(`(?m)^[ \t]*\{"([a-z]+)",`)
	z25ErrWord = regexp.MustCompile(`\berror\b`)
	z25ErrLine = regexp.MustCompile(`error:`)
	z25CFlags  = regexp.MustCompile(`(?m)^CFLAGS  *= *(.*)$`)
	z25LDFlags = regexp.MustCompile(`(?m)^LDFLAGS  *= *(.*)$`)
	z25CanonN  = regexp.MustCompile(`(?s).*canon *`)
)

// z25Mentions is `\bname\b` over the whole text, which is what the heredoc's
// own `mentions` does.  It is NOT blanked: these are identifiers the phase
// counts, and the file's string literals hold none of them.
func z25Mentions(text, name string) int {
	return len(regexp.MustCompile(`\b`+name+`\b`).FindAllString(text, -1))
}

// z25Calls is `(?<!\w)name\(` -- a call of name and not the tail of a longer
// identifier.  RE2 has no lookbehind, so the preceding byte is tested, which
// is exact because the excluded character is consumed by nothing.
func z25Calls(line, name string) bool {
	re := regexp.MustCompile(regexp.QuoteMeta(name) + `\(`)
	for _, loc := range re.FindAllStringIndex(line, -1) {
		if loc[0] > 0 && isWordByteC(line[loc[0]-1]) {
			continue
		}
		return true
	}
	return false
}

func isWordByteC(c byte) bool {
	return c == '_' || (c >= '0' && c <= '9') ||
		(c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')
}

// Zero25 is phase 25's check: the two function pointers the launcher installed
// become a forward declaration and a direct call.
//
// WHAT IT ASSERTS, in the shell's order, because ORDER IS OUTPUT:
//
//	the five controls   written from this phase's own output, one thing changed
//	the arithmetic      every count stated as a transformation of the INPUT
//	declared before use the prototype above every call, the definition below
//	the `static` trap   both halves, measured: the loud one and the SILENT one
//	the libc surface    a `cmp` of the whole undefined set, empty both ways
//	the binary          the same SIZE and NOT the same bytes, both measured
//	the recording       byte-identical, with one control per name
//	zhostonly           phase 20's structural check, re-run because this phase
//	                    moves host calls about and should say so
func Zero25(w io.Writer, args []string) error {
	if len(args) != 2 {
		return fmt.Errorf("usage: check zero25 <work-dir> <state-dir>")
	}
	work, state := args[0], args[1]
	f := filepath.Join(work, "zero-vim.c")
	r := &rep{tag: "hostcall", w: w}
	stop := func(format string, a ...any) error {
		r.say(format, a...)
		return harness.ErrReported
	}

	beforeLines, err := strconv.Atoi(strings.TrimSpace(readFile(filepath.Join(state, "input-lines"))))
	if err != nil {
		return stop("the state directory holds no usable input-lines")
	}

	tmp, err := os.MkdirTemp("", "zero25-")
	if err != nil {
		return err
	}
	defer os.RemoveAll(tmp)

	mk := readFile(filepath.Join(work, "Makefile"))
	cflags := strings.Fields(z25CFlags.FindStringSubmatch(mk)[1])
	ldflags := strings.Fields(z25LDFlags.FindStringSubmatch(mk)[1])
	build := func(src, out string) *exec.Cmd {
		a := append(append([]string{}, cflags...), ldflags...)
		a = append(a, "-o", out, src)
		c := exec.Command("gcc", a...)
		c.Env = append(os.Environ(), "SOURCE_DATE_EPOCH=0")
		return c
	}

	// The reproducible build of the OUTPUT and the five controls are started
	// first and waited for below.  Every control is this phase's own product
	// with ONE thing changed.
	var wgNew sync.WaitGroup
	var errNew error
	wgNew.Add(1)
	go func() { defer wgNew.Done(); errNew = build(f, filepath.Join(tmp, "new")).Run() }()

	newS := readFile(f)
	NL := strings.Split(newS, "\n")

	// ---- the five controls ----------------------------------------------
	var protos []string
	for _, l := range NL {
		if z25ProtoLn.MatchString(l) {
			protos = append(protos, l)
		}
	}
	if len(protos) != 2 {
		shown := strings.Join(protos, " / ")
		if shown == "" {
			shown = "none"
		}
		return stop("the output does not hold exactly the two `static` prototypes this "+
			"phase adds: %s", shown)
	}

	// c1 -- the two prototypes DELETED.  It must not compile: that is what
	// says they are load-bearing rather than decorative, and it is the control
	// for the ordering section.
	c1 := newS
	for _, p := range protos {
		c1 = strings.Replace(c1, p+"\n", "", 1)
	}
	if strings.Count(c1, "\n") != strings.Count(newS, "\n")-2 {
		return stop("deleting the two prototype lines did not remove exactly two lines")
	}

	// c2 -- `static` off the two PROTOTYPES only.  A hard error against the
	// static definitions, which is the loud half of the linkage trap.
	c2 := newS
	for _, p := range protos {
		c2 = strings.Replace(c2, p+"\n", strings.TrimPrefix(p, "static ")+"\n", 1)
	}

	// c3 -- `static` off the prototypes AND the definitions.  THE SILENT HALF:
	// it builds, and two symbols become external.
	c3 := c2
	for _, name := range []string{"host_exit", "host_message"} {
		re := regexp.MustCompile(`(?m)^    static (\w+)\n(` + name + `\()`)
		m := re.FindStringSubmatchIndex(c3)
		if m == nil {
			return stop("`%s` is not defined in the `    static <type>` shape, so c3 "+
				"would not be a control", name)
		}
		c3 = c3[:m[0]] + "    " + c3[m[2]:m[3]] + "\n" + c3[m[4]:m[5]] + c3[m[1]:]
	}

	// c4 -- host_exit's own statement.  The core calls host_exit DIRECTLY now;
	// this is what says the call arrives.  It is phase 18's control, which was
	// `exit(r);` -> `exit(r + 1);` before there was a launcher.
	const exitStmt = "    host_code = r;\n"
	if strings.Count(newS, exitStmt) != 1 {
		return stop("`%s` is not in the output exactly once, so c4 would not be a "+
			"control", strings.TrimSpace(exitStmt))
	}
	c4 := strings.Replace(newS, exitStmt, "    host_code = r + 1;\n", 1)

	// c5 -- host_message's two streams swapped.  The same statement for the
	// other name.
	const msgStmt = "write(err ? 2 : 1, msg + off"
	if strings.Count(newS, msgStmt) != 1 {
		return stop("`%s` is not in the output exactly once, so c5 would not be a "+
			"control", msgStmt)
	}
	c5 := strings.Replace(newS, msgStmt, "write(err ? 1 : 2, msg + off", 1)

	for _, c := range []struct{ name, text string }{
		{"c1", c1}, {"c2", c2}, {"c3", c3}, {"c4", c4}, {"c5", c5},
	} {
		if c.text == newS {
			return stop("%s changed nothing", c.name)
		}
		if err := os.WriteFile(filepath.Join(tmp, c.name+".c"), []byte(c.text), 0o644); err != nil {
			return err
		}
	}
	r.say("five controls written: c1 the two prototypes DELETED, c2 `static` off them, " +
		"c3 `static` off them AND the definitions, c4 host_exit's `host_code = r;` -> " +
		"`r + 1`, c5 host_message's two streams swapped")

	// c1 and c2 are expected to FAIL, so their status is discarded.
	var wgC sync.WaitGroup
	syn := func(name string) {
		wgC.Add(1)
		go func() {
			defer wgC.Done()
			c := exec.Command("gcc", "-O0", "-fno-stack-protector", "-fsyntax-only",
				filepath.Join(tmp, name+".c"))
			b, _ := c.CombinedOutput()
			os.WriteFile(filepath.Join(tmp, "e."+name), b, 0o644)
		}()
	}
	syn("c1")
	syn("c2")
	wgC.Add(1)
	go func() {
		defer wgC.Done()
		c := exec.Command("gcc", "-c", "-O0", "-fno-stack-protector",
			"-o", filepath.Join(tmp, "c3.o"), filepath.Join(tmp, "c3.c"))
		b, _ := c.CombinedOutput()
		os.WriteFile(filepath.Join(tmp, "e.c3"), b, 0o644)
	}()
	var errC4, errC5 error
	wgC.Add(2)
	go func() { defer wgC.Done(); errC4 = build(filepath.Join(tmp, "c4.c"), filepath.Join(tmp, "c4")).Run() }()
	go func() { defer wgC.Done(); errC5 = build(filepath.Join(tmp, "c5.c"), filepath.Join(tmp, "c5")).Run() }()

	// tools/canon.sh must be a NO-OP on the output.
	canonC := filepath.Join(tmp, "canon.c")
	os.WriteFile(canonC, []byte(newS), 0o644)
	var wgCanon sync.WaitGroup
	wgCanon.Add(1)
	go func() {
		defer wgCanon.Done()
		c := exec.Command("sh", "tools/canon.sh", canonC)
		b, _ := c.CombinedOutput()
		os.WriteFile(filepath.Join(tmp, "canon.log"), b, 0o644)
	}()

	// ---- 1. the source, as arithmetic on the input -----------------------
	oldS := readFile(filepath.Join(state, "old.c"))
	OL := strings.Split(oldS, "\n")

	for _, x := range []struct {
		name             string
		wantOld, wantNew int
		why              string
	}{
		{"vim_host_exit", 3, 0, "its declaration, its one assignment and its one call"},
		{"vim_host_message", 10, 0, "its declaration, its one assignment and EIGHT calls"},
		{"exit_fn", 2, 0, "vim_main's third parameter and the assignment reading it"},
		{"message_fn", 2, 0, "vim_main's fourth parameter and its assignment"},
		{"host_exit", 2, 3, "two -- the definition and main()'s argument -- become three: " +
			"the prototype, the call in mch_exit and the definition"},
		{"host_message", 2, 10, "the same, with EIGHT calls"},
		{"vim_main", 2, 2, "its definition and the one call from the launcher"},
		{"main", 1, 1, "still the only bare `main` in the file"},
	} {
		if got := z25Mentions(oldS, x.name); got != x.wantOld {
			r.bad("the INPUT has %d mentions of `%s` and this phase was written against "+
				"%d -- %s", got, x.name, x.wantOld, x.why)
		} else if got := z25Mentions(newS, x.name); got != x.wantNew {
			r.bad("`%s` has %d mentions in the output, expected %d -- %s",
				x.name, got, x.wantNew, x.why)
		}
	}

	// THE TWO PROTOTYPES, AND THAT THEY DECLARE WHAT IS DEFINED.  Built here
	// the same way the edit built them -- out of the definition's own two
	// lines -- so a prototype that had drifted from its definition would show
	// up as text and not only as a compile error.
	var built []string
	for _, name := range []string{"host_exit", "host_message"} {
		re := regexp.MustCompile(`(?m)^    (static \w+)\n(` + name + `\([^\n]*\))\n\{\n`)
		m := re.FindStringSubmatch(newS)
		if m == nil {
			r.bad("`%s` is not defined `    static <type>` / declarator / `{` in the "+
				"output", name)
			continue
		}
		built = append(built, m[1]+" "+m[2]+";")
	}
	if len(built) == 2 {
		var have []string
		for _, l := range NL {
			if z25ProtoLn.MatchString(l) {
				have = append(have, l)
			}
		}
		if strings.Join(have, "\x00") != strings.Join(built, "\x00") {
			h := strings.Join(have, " / ")
			if h == "" {
				h = "none"
			}
			r.bad("the output's two prototypes are %s and the definitions say they "+
				"should be %s", h, strings.Join(built, " / "))
		}
		var block []int
		for i, l := range NL {
			if l == "static void musl_suspend(void);" {
				block = append(block, i)
			}
		}
		ok := len(block) == 1
		if ok {
			if block[0]+3 > len(NL) ||
				strings.Join(NL[block[0]+1:block[0]+3], "\x00") != strings.Join(built, "\x00") {
				ok = false
			}
		}
		if !ok {
			r.bad("the two prototypes are not the two lines below phase 20's last " +
				"`musl_` prototype -- the core -> host boundary is ONE block of eleven")
		}
		anyPtr := false
		for _, l := range OL {
			if strings.Contains(l, "static void (*vim_host") {
				anyPtr = true
				break
			}
		}
		if !anyPtr {
			r.bad("the INPUT held no `static void (*vim_host...)` object, so this is " +
				"not the file this phase was written against")
		}
	}

	// THE SHAPE OF THE EDIT.  Five lines fewer.
	if len(NL)-1 != beforeLines-5 || len(OL)-1 != beforeLines {
		r.bad("the file is %d lines and the input was %d (%d recorded) -- expected "+
			"exactly five fewer", len(NL)-1, len(OL)-1, beforeLines)
	}
	runs := 0
	for k := 1; k < len(NL); k++ {
		if NL[k] == "" && NL[k-1] == "" {
			runs++
		}
	}
	if runs > 0 {
		r.bad("there is a run of two blank lines, which canon.sh should have taken")
	}

	// THE SHAPE OF THE FILE.  Nothing here is a command, an option or a
	// directive, and the check says so rather than assuming it.
	// tools/create_cmdidxs.py -- named as a PATH so tools/implhash.sh hashes
	// it into this phase's key.  Do not delete it.
	rows := z25CmdRow.FindAllString(newS, -1)
	names, nerr := harness.CommandNames(f)
	if len(rows) != 98 || nerr != nil || len(names) != 98 {
		r.bad("cmdnames[] is not the 98 rows phase 10 left -- this phase touches no Ex " +
			"command")
	}
	i := strings.Index(newS, "static struct vimoption options[]")
	j := strings.Index(newS[i:], "\n};") + i
	if nOpt := len(z25OptRow.FindAllString(newS[i:j], -1)); nOpt != 107 {
		r.bad("options[] has %d rows, expected the 107 phase 20 left -- this phase "+
			"removes no option", nOpt)
	}
	var d []string
	for _, l := range NL {
		if strings.HasPrefix(l, "#") {
			d = append(d, l)
		}
	}
	badInc := len(d) != 11
	for _, l := range d {
		if !strings.HasPrefix(l, "#include <") {
			badInc = true
		}
	}
	if !badInc && strings.Join(NL[:11], "\x00") != strings.Join(d, "\x00") {
		badInc = true
	}
	if badInc {
		r.bad("the output does not have exactly the eleven `#include` directives phase " +
			"21 left, on its first eleven lines.  This phase adds a DECLARATION, and " +
			"MOVING THE INCLUDES IS A LATER PHASE")
	}

	if err := r.done(); err != nil {
		return err
	}
	r.say("`vim_host_exit` 3 -> 0 and `vim_host_message` 10 -> 0; `host_exit` 2 -> 3 " +
		"and `host_message` 2 -> 10; `exit_fn` and `message_fn` 2 -> 0.  Two objects, " +
		"two parameters, two assignments and two arguments gone, TWO PROTOTYPES " +
		"arrived, and every count is computed FROM THE INPUT")
	r.cont("the two prototypes are what the definitions say they must be, byte for "+
		"byte -- %s -- and they are the two lines below phase 20's last `musl_` "+
		"prototype, so the core -> host boundary is ONE block of eleven",
		strings.Join(built, " / "))
	r.cont("%d -> %d lines, five fewer; cmdnames[] 98 and options[] 107 unmoved; "+
		"ELEVEN #includes on the first eleven lines", beforeLines, len(NL)-1)

	// ---- 2. declaration before use, and the control that says it is needed --
	wgC.Wait()
	errC1 := readFile(filepath.Join(tmp, "e.c1"))

	type placed struct {
		name              string
		proto, lo, hi, df int
		uses              int
	}
	var out []placed
	for _, name := range []string{"host_exit", "host_message"} {
		reP := regexp.MustCompile(`^static \w+ ` + name + `\(.*\);$`)
		var proto, defn, uses []int
		for i, l := range NL {
			if reP.MatchString(l) {
				proto = append(proto, i)
			}
			if strings.HasPrefix(l, name+"(") && i+1 < len(NL) && NL[i+1] == "{" {
				defn = append(defn, i)
			}
		}
		for i, l := range NL {
			if z25Calls(l, name) && !containsInt25(proto, i) && !containsInt25(defn, i) {
				uses = append(uses, i)
			}
		}
		if len(proto) != 1 || len(defn) != 1 || len(uses) == 0 {
			return stop("`%s` has %d prototypes, %d definitions and %d call sites in "+
				"the output", name, len(proto), len(defn), len(uses))
		}
		lo, hi := uses[0], uses[len(uses)-1]
		if !(proto[0] < lo && hi < defn[0]) {
			return stop("`%s`: prototype at %d, calls at %d..%d, definition at %d -- "+
				"the prototype must be ABOVE every call and the definition BELOW every "+
				"one, which is what makes the declaration load-bearing",
				name, proto[0]+1, lo+1, hi+1, defn[0]+1)
		}
		out = append(out, placed{name, proto[0] + 1, lo + 1, hi + 1, defn[0] + 1, len(uses)})
	}
	if !z25ErrWord.MatchString(errC1) {
		return stop("THE CONTROL c1 DID NOT SHOW: with the two prototype lines DELETED " +
			"the file still compiles, so the declarations this phase adds are not what " +
			"lets the core name the host and the ordering above proves nothing")
	}
	for _, name := range []string{"host_exit", "host_message"} {
		if !strings.Contains(errC1, name) {
			return stop("the control c1 failed without naming `%s`, so it is not the "+
				"control it claims to be", name)
		}
	}
	nErr := len(z25ErrLine.FindAllString(errC1, -1))
	first := true
	for _, p := range out {
		plural, span := "", ""
		if p.uses != 1 {
			plural, span = "s", fmt.Sprintf("..%d", p.hi)
		}
		line := fmt.Sprintf("`%s`: prototype line %d, %d call site%s at %d%s, definition "+
			"line %d -- DECLARED ABOVE EVERY USE AND DEFINED BELOW EVERY ONE.  A later "+
			"phase moves the definitions further down and this stays true, which is the "+
			"whole job of a forward declaration", p.name, p.proto, p.uses, plural, p.lo, span, p.df)
		if first {
			r.say("%s", line)
			first = false
		} else {
			r.cont("%s", line)
		}
	}
	r.cont("AND THE DECLARATIONS ARE LOAD-BEARING: this phase's own output with the two "+
		"prototype lines DELETED gives %d errors naming both `host_exit` and "+
		"`host_message`.  Without that control the two lines above are a statement "+
		"about line numbers and not about the program", nErr)

	// ---- 3. linkage, WHICH IS THE ASSERTION THAT MATTERS MOST -------------
	errC2 := readFile(filepath.Join(tmp, "e.c2"))
	errC3 := readFile(filepath.Join(tmp, "e.c3"))
	if !strings.Contains(errC2, "static declaration of 'host_exit' follows non-static declaration") {
		r.say("THE CONTROL c2 DID NOT SHOW.  With `static` off the two PROTOTYPES")
		r.cont("and left on the definitions, gcc must refuse:")
		for k, l := range strings.Split(errC2, "\n") {
			if k >= 4 {
				break
			}
			r.cont("%s", l)
		}
		return harness.ErrReported
	}
	if errC3 != "" || sizeOf(filepath.Join(tmp, "c3.o")) < 0 {
		r.say("the control c3 did not build, and the point of it is that it DOES:")
		for k, l := range strings.Split(errC3, "\n") {
			if k >= 4 {
				break
			}
			r.cont("%s", l)
		}
		return harness.ErrReported
	}
	nmOut, _ := exec.Command("nm", "--extern-only", "--defined-only",
		filepath.Join(tmp, "c3.o")).Output()
	var ext []string
	for _, l := range strings.Split(strings.TrimRight(string(nmOut), "\n"), "\n") {
		if fs := strings.Fields(l); len(fs) > 0 {
			ext = append(ext, fs[len(fs)-1])
		}
	}
	sort.Strings(ext)
	c3ext := strings.Join(ext, " ") + " "
	if c3ext != "host_exit host_message main " {
		r.say("THE CONTROL c3 DID NOT SHOW.  With `static` off the prototypes AND")
		r.cont("the definitions the object must define host_exit, host_message and")
		r.cont("main; it defines: %s", c3ext)
		return harness.ErrReported
	}
	r.say("THE `static` TRAP, BOTH HALVES, MEASURED ON THIS PHASE'S OWN OUTPUT: with "+
		"the keyword off the two PROTOTYPES gcc REFUSES -- \"static declaration of "+
		"'host_exit' follows non-static declaration\" -- and with it off the prototypes "+
		"AND the definitions the build is SILENT and the object defines %s.  The second "+
		"is the mistake this phase could have made without anything else noticing, and "+
		"tools/phasecheck.sh below is what catches it", c3ext)

	// ---- 4. the compile, the linkage and the libc surface -----------------
	beforeU := readFile(filepath.Join(state, "symbols", "undefined"))
	pc := exec.Command("sh", "tools/phasecheck.sh", work, f, filepath.Join(state, "symbols"))
	pc.Stdout, pc.Stderr = w, w
	if err := pc.Run(); err != nil {
		return harness.ErrReported
	}
	afterU := readFile(".cache/symbols/last/undefined")
	if beforeU != afterU {
		r.say("the libc surface moved, and TURNING AN INDIRECT CALL INTO A DIRECT ONE")
		r.cont("CANNOT MOVE IT -- both name a function defined in this file:")
		r.cont("gone: %s", strings.Join(minus25(beforeU, afterU), " "))
		r.cont("came: %s", strings.Join(minus25(afterU, beforeU), " "))
		return harness.ErrReported
	}
	r.say("symbols %s -> %s, and the set is IDENTICAL as a cmp -- nothing left and "+
		"nothing arrived.  `exit` does NOT come back: the host still records a status "+
		"and jumps, phase 19's __builtin_longjmp launcher being untouched here.  main "+
		"is still the only external symbol",
		strings.TrimSpace(readFile(".cache/symbols/last/before")),
		strings.TrimSpace(readFile(".cache/symbols/last/after")))

	// ---- 5. the binary: the same size, and NOT the same bytes -------------
	wgCanon.Wait()
	if readFile(canonC) != newS {
		r.say("tools/canon.sh CHANGED THE OUTPUT, and it must be a no-op:")
		return harness.ErrReported
	}
	canonLine := ""
	for _, l := range strings.Split(readFile(filepath.Join(tmp, "canon.log")), "\n") {
		if strings.Contains(l, "canon") {
			canonLine = z25CanonN.ReplaceAllString(l, "")
			break
		}
	}
	r.say("tools/canon.sh is a NO-OP on the output (%s)", canonLine)

	_ = exec.Command("make", "-C", work, "clean").Run()
	bin := filepath.Join(work, "zero-vim")
	if _, err := os.Stat(bin); err == nil {
		(&rep{tag: "build", w: w}).say("the clean did not remove zero-vim, so a " +
			"'rebuild' below could be no rebuild at all")
		return harness.ErrReported
	}
	if err := exec.Command("make", "-C", work).Run(); err != nil {
		(&rep{tag: "build", w: w}).say("FAILED -- rerun by hand: make -C %s", work)
		return harness.ErrReported
	}
	(&rep{tag: "build", w: w}).say("ok, %d -> %d lines, %d bytes",
		beforeLines, len(strings.Split(newS, "\n"))-1, sizeOf(bin))

	wgNew.Wait()
	if errNew != nil {
		return stop("the reproducible build of the output failed")
	}
	oldSize := sizeOf(filepath.Join(state, "old"))
	newSize := sizeOf(filepath.Join(tmp, "new"))
	if newSize < 500000 || oldSize < 500000 {
		return stop("one of the two binaries is %d / %d bytes, which is not an editor",
			oldSize, newSize)
	}
	if newSize != sizeOf(bin) {
		return stop("the reproducible build is %d bytes and make produced %d: the two "+
			"differ by more than a timestamp, so nothing below would be about this "+
			"boundary", newSize, sizeOf(bin))
	}
	if oldSize != newSize {
		r.say("the binary is %d bytes in and %d out.  Nine call sites", oldSize, newSize)
		r.cont("change instruction and two file-scope pointers go, and the whole")
		r.cont("of that was MEASURED to leave the image exactly the same length.")
		r.cont("A different length is a different phase and wants reading.")
		return harness.ErrReported
	}
	a := readFile(filepath.Join(state, "old"))
	b := readFile(filepath.Join(tmp, "new"))
	if a == b {
		r.say("THE BINARY IS BYTE-IDENTICAL, and it must not be.  An indirect call")
		r.cont("loads a pointer and calls a register; a direct call is a relative")
		r.cont("call to a known address.  Identical bytes would mean the nine call")
		r.cont("sites did not change at all.")
		return harness.ErrReported
	}
	differing := 0
	for k := 0; k < len(a) && k < len(b); k++ {
		if a[k] != b[k] {
			differing++
		}
	}
	r.say("THE BINARY IS THE SAME SIZE AND NOT THE SAME BYTES: %d either side, %d of "+
		"them differing.  That is stated as a MEASUREMENT and not aimed for -- an "+
		"indirect call through a pointer and a direct call are different instructions "+
		"at -O0, and removing two file-scope objects moves what follows.  So this phase "+
		"cannot use tier 1 of CLAUDE.md's verification table and does not pretend to; "+
		"the evidence is the recording below", newSize, differing)

	// ---- 6. THE EVIDENCE: two recordings, and one control per name --------
	if errC4 != nil {
		r.say("the control c4 did not build:")
		return harness.ErrReported
	}
	if errC5 != nil {
		r.say("the control c5 did not build:")
		return harness.ErrReported
	}
	var wgR sync.WaitGroup
	recErr := make([]error, 4)
	for k, x := range []struct{ name, bin, src string }{
		{"old", filepath.Join(state, "old"), filepath.Join(state, "old.c")},
		{"new", filepath.Join(tmp, "new"), f},
		{"c4", filepath.Join(tmp, "c4"), filepath.Join(tmp, "c4.c")},
		{"c5", filepath.Join(tmp, "c5"), filepath.Join(tmp, "c5.c")},
	} {
		wgR.Add(1)
		go func(k int, name, b, s string) {
			defer wgR.Done()
			c := exec.Command("sh", "tools/zrecord.sh", b, s, filepath.Join(tmp, "REC-"+name))
			recErr[k] = c.Run()
		}(k, x.name, x.bin, x.src)
	}
	wgR.Wait()
	for _, e := range recErr {
		if e != nil {
			return stop("a recording failed")
		}
	}

	base, err := recFiles(filepath.Join(tmp, "REC-new"))
	if err != nil || len(base) < 100 {
		return stop("a recording holds %d records, and a zero recording is 106 -- 102 "+
			"screen cases and four sweeps.  A comparison of two things nothing wrote "+
			"passes", len(base))
	}
	moved := func(which string) ([]string, error) {
		d := filepath.Join(tmp, "REC-"+which)
		got, err := recFiles(d)
		if err != nil || strings.Join(got, "\x00") != strings.Join(base, "\x00") {
			return nil, stop("the recording of %s holds different records from the "+
				"output's", which)
		}
		var out []string
		for _, n := range base {
			if readFile(filepath.Join(tmp, "REC-new", n)) != readFile(filepath.Join(d, n)) {
				out = append(out, n)
			}
		}
		return out, nil
	}
	same, e := moved("old")
	if e != nil {
		return e
	}
	if len(same) > 0 {
		shown := same
		if len(shown) > 8 {
			shown = shown[:8]
		}
		r.say("THE RECORDING MOVED, in %d of %d records: %s",
			len(same), len(base), strings.Join(shown, " "))
		r.cont("This phase declares NOTHING.  Two objects became two prototypes and " +
			"nine indirect calls became direct ones; the editor does the same thing or " +
			"the phase is wrong.")
		return harness.ErrReported
	}
	m4, e := moved("c4")
	if e != nil {
		return e
	}
	m5, e := moved("c5")
	if e != nil {
		return e
	}
	inM4 := map[string]bool{}
	for _, n := range m4 {
		inM4[n] = true
	}
	var still []string
	for _, n := range base {
		if !inM4[n] {
			still = append(still, n)
		}
	}
	sort.Strings(still)
	if strings.Join(still, "\x00") != "ref-term.txt" {
		s := strings.Join(still, " ")
		if s == "" {
			s = "nothing"
		}
		return stop("THE CONTROL c4 DID NOT SHOW AS MEASURED: host_exit recording `r + "+
			"1` instead of `r` moves %d of %d records and leaves %s unmoved, where it "+
			"was measured to leave ref-term.txt alone and move everything else -- the "+
			"terminal table is the one sweep that records no exit status",
			len(m4), len(base), s)
	}
	if strings.Join(m5, "\x00") != "ref-argv.txt" {
		s := strings.Join(m5, " ")
		if s == "" {
			s = "nothing"
		}
		return stop("THE CONTROL c5 DID NOT SHOW AS MEASURED: host_message with its two "+
			"streams swapped moves %s, and it was measured to move ref-argv.txt and "+
			"nothing else -- everything that reaches host_message is a message printed "+
			"before there is a screen (phase 21)", s)
	}
	r.say("THE RECORDING IS BYTE-IDENTICAL, all %d records -- 102 screen cases, every "+
		"Ex command typed at `:`, every command line the parser may see, the four pty "+
		"scenarios and the terminal table.  That is this phase's whole evidence, and it "+
		"is the shape every zero phase before 23 used: the binary cannot be `cmp`-ed "+
		"here, so what the editor DRAWS is what is compared", len(base))
	r.cont("AND IT CAN FAIL, ONCE FOR EACH NAME THIS PHASE MAKES DIRECT.  host_exit "+
		"with `host_code = r + 1;` moves %d of the %d -- every record but the terminal "+
		"table, which does not record an exit status.  host_message with its two "+
		"streams swapped moves ref-argv.txt AND NOTHING ELSE, which is phase 21's own "+
		"finding read back: everything reaching host_message is printed before there "+
		"is a screen", len(m4), len(base))

	// ---- 7. phase 20's structural check, which a phase that renames host
	// calls owes.
	zh := exec.Command("sh", "tools/st.sh", "zhostonly", f)
	zh.Stdout, zh.Stderr = w, w
	if err := zh.Run(); err != nil {
		return harness.ErrReported
	}
	r.say("and that is phase 20's check, undisturbed: its vocabulary is libc's " +
		"terminal, signal and descriptor names, and `host_exit`/`host_message` are not " +
		"in it -- so renaming nine call sites adds no host WORD to the core.  Running " +
		"it here rather than assuming it is the point")
	return nil
}

func containsInt25(xs []int, x int) bool {
	for _, v := range xs {
		if v == x {
			return true
		}
	}
	return false
}

func minus25(a, b string) []string {
	in := map[string]bool{}
	for _, l := range strings.Split(b, "\n") {
		in[l] = true
	}
	var out []string
	for _, l := range strings.Split(a, "\n") {
		if l != "" && !in[l] {
			out = append(out, l)
		}
	}
	return out
}

// recFiles is `os.walk` flattened to relative paths, sorted -- the heredoc's
// own `files()`.
func recFiles(d string) ([]string, error) {
	var out []string
	err := filepath.Walk(d, func(p string, fi os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if !fi.IsDir() {
			rel, _ := filepath.Rel(d, p)
			out = append(out, rel)
		}
		return nil
	})
	sort.Strings(out)
	return out, err
}
