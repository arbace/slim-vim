package check

// Zero phase 16, the check -- the includes nothing names.
// See pipes/zero16-edit.sh, and ZERO-GOAL.md.
//
// Runs after pipes/zero16-edit.sh and the sweep tools/phaserun.sh runs between
// them, and reads nothing from the edit's shell -- only the work tree and the
// state directory.  What the edit left there is `old.c`, the source this phase
// was HANDED, and `old`, that source built with SOURCE_DATE_EPOCH=0 and the
// boundary's own flags.
//
// THIS PHASE CHANGES NO CODE, so there is no behavioural probe to offer and
// none is offered.  What it has instead is stronger than any recording: THE
// BINARY IS THE SAME BYTES.  That is tier 1 of CLAUDE.md's verification table
// -- "pure formatting: the binary is byte-identical (cmp)" -- and a
// byte-identical binary subsumes every screen case, every Ex-command row,
// every command line and every pty scenario at once, because the program that
// would be run is literally the same program.  tools/zerodelta.sh --phase 16
// still runs, from tools/phaserun.sh after this check, and it corroborates; it
// is not the evidence.
//
// THE ARGUMENT IS A COMPUTATION AND NOT A LIST, and section 3 is the whole
// phase.  A phase that deleted six named headers proves only that six named
// headers were deletable.  What this proves is EVERY INCLUDE THAT SURVIVES IS
// NEEDED and EVERY INCLUDE THAT WENT WAS NOT, by removing each one in turn and
// asking the compiler:
//
//	on the output    12 compiles, and EVERY ONE MUST FAIL.  A dead include
//	                 that survived this phase would be a compile that
//	                 succeeded.
//	on the input     18 compiles, and EXACTLY SIX MUST SUCCEED -- the six
//	                 this phase removed -- while the other twelve fail.  That
//	                 is the same loop proving it can fail, in the same run, on
//	                 the same code path: it is phase 13's ui_write() control
//	                 in this phase's shape.
//
// Measured: the two loops together are 30 compiles and about 5 seconds, run at
// once.  gcc 15 defaults to C23, where an implicit function declaration is a
// HARD ERROR, so a header that still supplies a function, a type, a macro
// constant or an enum constant cannot be dropped quietly -- there is no
// -Wimplicit-* to look for because there is nothing left to warn about.
//
// THE ONE SILENT DROP IN THIS FILE, and section 2 is where it is caught.
// Removing <sys/stat.h> while keeping `typedef struct stat stat_T;` COMPILES
// CLEANLY: the typedef declares a new, incomplete `struct stat` at file scope.
// Only `sizeof(stat_T)` would ever have exposed it.  So the typedef is
// required at zero mentions and `struct stat` with it, and section 3's loop
// would NOT have caught this one on its own.
//
// WHY THE cmp IS AS SENSITIVE AS IT IS.  gcc writes a GNU build-id note near
// the front of the image, and it is a hash of the whole output -- so ANY
// difference anywhere moves it and the FIRST difference cmp reports is always
// that note, at char 633 of this binary.  Measured three ways on the stand-in:
// two ordinary builds of the same bytes differ there (which is why
// SOURCE_DATE_EPOCH=0 is set on both sides), a one-character change to one
// string literal differs there, and the phase's own output does not differ at
// all.

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
	"sync"

	"slimvim.local/tools/internal/harness"
)

func init() { register("zero16", Zero16) }

var (
	z16Inc     = regexp.MustCompile(`^#include <([A-Za-z0-9_/.]+)>$`)
	z16File    = regexp.MustCompile(`\bFILE\b`)
	z16StatT   = regexp.MustCompile(`\bstat_T\b`)
	z16Struct  = regexp.MustCompile(`\bstruct\s+stat\b`)
	z16Row     = regexp.MustCompile(`(?m)^    \[CMD_\w+\] = \{.*$`)
	z16OptRow  = regexp.MustCompile(`(?m)^[ \t]*\{"([a-z]+)",`)
	z16CFlags  = regexp.MustCompile(`(?m)^CFLAGS  *= *(.*)$`)
	z16LDFlags = regexp.MustCompile(`(?m)^LDFLAGS  *= *(.*)$`)
	z16GccErr  = regexp.MustCompile(`.*error: `)
)

var z16Keep = []string{"stdio.h", "stdlib.h", "unistd.h", "sys/param.h", "time.h",
	"signal.h", "errno.h", "stdint.h", "stdarg.h", "stddef.h", "sys/ioctl.h", "termios.h"}

var z16Gone = []string{"sys/stat.h", "fcntl.h", "iconv.h", "string.h", "ctype.h", "wctype.h"}

// The six identifier sets are the MEASURED ones: what zero-vim.c was measured
// to take from each header, and nothing speculative.  A list written from what
// a header OFFERS refuses on a correct phase -- `isprint` is in this file, as
// the name of the 'isprint' option in a string literal, and it is not a ctype
// call.
//
// A SLICE and not a map, because the report walks it: the Python iterates
// `sorted(SUPPLIED.items())` and ranging a Go map would reorder a refusal
// every run.
var z16Supplied = []struct{ header, ids string }{
	{"ctype.h", "isalnum isalpha iscntrl isdigit isgraph islower ispunct isupper " +
		"tolower toupper"},
	{"fcntl.h", "fcntl creat openat O_RDONLY O_WRONLY O_RDWR O_CREAT O_TRUNC " +
		"O_APPEND O_EXCL O_NONBLOCK F_GETFD F_SETFD FD_CLOEXEC"},
	{"iconv.h", "iconv iconv_t iconv_open iconv_close"},
	{"string.h", "memchr memcmp memcpy memmove memset strcasecmp strcat strchr " +
		"strcmp strcpy strlen strncasecmp strncmp strncpy strpbrk strstr"},
	{"sys/stat.h", "fstat lstat chmod fchmod ftruncate mkdir umask st_mode st_size"},
	{"wctype.h", "iswupper towlower towupper"},
}

// Nothing that could open or name a file may be CALLED.  `(?<![\w.>])name\s*\(`
// in the Python; RE2 has no lookbehind, so the preceding byte is tested
// instead -- exact for the reason every byte test in this tree is exact, that
// the excluded character is consumed by nothing.
var z16Absent = []string{"open", "creat", "openat", "fopen", "fdopen", "opendir",
	"stat", "access", "fcntl", "getcwd", "strerror", "fclose", "getc", "putc",
	"fsync", "mkdir", "rename", "unlink", "readlink"}

var z16BadDirectives = []string{"#define", "#undef", "#if", "#ifdef", "#ifndef",
	"#elif", "#else", "#endif", "#pragma", "#line", "#error", "#include_next"}

func z16Runs(text string) int {
	L := strings.Split(text, "\n")
	n := 0
	for i := 1; i < len(L); i++ {
		if L[i] == "" && L[i-1] == "" {
			n++
		}
	}
	return n
}

func z16IsWord(c byte) bool {
	return c == '_' || (c >= '0' && c <= '9') || (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')
}

// z16Called is `(?<![\w.>])name\s*\(`: a call of name that is not a member
// access and not the tail of a longer identifier.
func z16Called(text, name string) bool {
	re := regexp.MustCompile(regexp.QuoteMeta(name) + `\s*\(`)
	for _, loc := range re.FindAllStringIndex(text, -1) {
		if loc[0] > 0 {
			c := text[loc[0]-1]
			if z16IsWord(c) || c == '.' || c == '>' {
				continue
			}
		}
		return true
	}
	return false
}

type z16Directive struct {
	at   int
	line string
}

func z16Directives(text string) []z16Directive {
	var out []z16Directive
	for i, l := range strings.Split(text, "\n") {
		if strings.HasPrefix(l, "#") {
			out = append(out, z16Directive{i, l})
		}
	}
	return out
}

// Zero16 is the check for zero phase 16.
func Zero16(w io.Writer, args []string) error {
	if len(args) != 2 {
		return fmt.Errorf("usage: check zero16 <work-dir> <state-dir>")
	}
	work, state := args[0], args[1]
	f := filepath.Join(work, "zero-vim.c")

	beforeLines, err := os.ReadFile(filepath.Join(state, "input-lines"))
	if err != nil {
		return fmt.Errorf("  includes     the input line count is not in the state directory: %v", err)
	}

	tmp, err := os.MkdirTemp("", "zero16-check-")
	if err != nil {
		return err
	}
	defer os.RemoveAll(tmp)

	mk, err := os.ReadFile(filepath.Join(work, "Makefile"))
	if err != nil {
		return err
	}
	cflags := strings.Fields(z16CFlags.FindStringSubmatch(string(mk))[1])
	ldflags := strings.Fields(z16LDFlags.FindStringSubmatch(string(mk))[1])

	// The reproducible build of the OUTPUT is started first and waited for in
	// section 5: it is three seconds of wall time that sections 1 to 3 can be
	// spending instead.  It is built from f directly, and neither the file's
	// name nor its path reaches the image -- measured, `old.c` in state and
	// `zero-vim.c` in work give identical bytes, because zero-vim.c names no
	// __FILE__ and no __LINE__ and gcc is not given -g.
	newBin := filepath.Join(tmp, "new")
	var buildWG sync.WaitGroup
	var buildErr error
	buildWG.Add(1)
	go func() {
		defer buildWG.Done()
		a := append(append([]string{}, cflags...), ldflags...)
		a = append(a, "-o", newBin, f)
		cmd := exec.Command("gcc", a...)
		cmd.Env = append(os.Environ(), "SOURCE_DATE_EPOCH=0")
		buildErr = cmd.Run()
	}()

	newB, err := os.ReadFile(f)
	if err != nil {
		return err
	}
	oldB, err := os.ReadFile(filepath.Join(state, "old.c"))
	if err != nil {
		return err
	}
	newS, oldS := string(newB), string(oldB)

	r := &rep{tag: "includes", w: w}

	// --- 1. the directives, which are the whole of what this phase changed --
	headers := func(text, where string) []string {
		var out []string
		for _, d := range z16Directives(text) {
			m := z16Inc.FindStringSubmatch(d.line)
			if m == nil {
				r.bad("%s has a directive that is not an #include of a system header: %s "+
					"-- the charter is that zero-vim.c stays pure C without a "+
					"preprocessor", where, strconv.Quote(d.line))
			} else {
				out = append(out, m[1])
			}
		}
		return out
	}

	// THE INPUT, so that "six went" is a difference and not a number.
	oldD := z16Directives(oldS)
	if !z16Consecutive(oldD, 0, 18) {
		r.bad("the input did not have eighteen directives on its first eighteen lines, " +
			"so this is not the file the phase was written against")
	}
	oldH := headers(oldS, "the input")
	if !z16SameSet(oldH, append(append([]string{}, z16Keep...), z16Gone...)) {
		s := append([]string{}, oldH...)
		sort.Strings(s)
		r.bad("the input is not the eighteen headers this phase was written against: %s",
			strings.Join(s, " "))
	}

	// THE OUTPUT.
	d := z16Directives(newS)
	if !z16Consecutive(d, 0, 12) {
		var at []string
		for _, x := range d {
			at = append(at, strconv.Itoa(x.at))
		}
		r.bad("the output has %d directives, at lines %s -- twelve are expected and they "+
			"must be the first twelve lines of the file", len(d), strings.Join(at, " "))
	}
	newH := headers(newS, "the output")
	if strings.Join(newH, "\x00") != strings.Join(z16Keep, "\x00") {
		r.bad("the twelve that are left are not the twelve this phase keeps, in order: %s",
			strings.Join(newH, " "))
	}
	for _, h := range z16Gone {
		if strings.Contains(newS, "#include <"+h+">") {
			r.bad("<%s> is still included", h)
		}
	}

	// NOTHING BUT #include, ANYWHERE.  The charter's other half, and this is
	// the only phase that has ever had a reason to look.
	for _, bad := range z16BadDirectives {
		if regexp.MustCompile(`(?m)^\s*` + regexp.QuoteMeta(bad) + `\b`).MatchString(newS) {
			r.bad("%s appears in zero-vim.c, and no phase may add a directive that is "+
				"not an #include of a system header", bad)
		}
	}

	// --- 2. what the six supplied, at zero -- and the one silent drop ------
	body := strings.Join(strings.Split(newS, "\n")[12:], "\n")
	for _, s := range z16Supplied {
		var live []string
		for _, i := range strings.Fields(s.ids) {
			if regexp.MustCompile(`\b` + i + `\b`).MatchString(body) {
				live = append(live, i)
			}
		}
		if len(live) > 0 {
			r.bad("<%s> was removed and zero-vim.c still names %s",
				s.header, strings.Join(live, ", "))
		}
	}

	// THE SILENT ONE.  A typedef of an undeclared struct tag compiles, so
	// section 3's loop could not have caught this: <sys/stat.h> is droppable
	// WITH the typedef in place, and what is left is a lie that only
	// sizeof(stat_T) would expose.
	if z16StatT.MatchString(body) {
		r.bad("stat_T survives with no <sys/stat.h>: the typedef would declare a NEW, " +
			"INCOMPLETE `struct stat` and compile cleanly, which is the only silent " +
			"drop in this file")
	}
	if z16Struct.MatchString(body) {
		r.bad("`struct stat` survives with no <sys/stat.h>")
	}
	if k := len(z16StatT.FindAllString(oldS, -1)); k != 1 {
		r.bad("the input had %d stat_T mentions, expected 1 -- \"its only user is its own "+
			"typedef\" was not true of the file this ran on", k)
	}

	// --- what must NOT have moved ------------------------------------------
	if z16File.MatchString(newS) {
		r.bad("FILE is named in zero-vim.c, and phase 13 took it to zero")
	}
	for _, absent := range z16Absent {
		if z16Called(newS, absent) {
			r.bad("%s( is called in the source, and the core has had no way to name or "+
				"open anything since phase 13", absent)
		}
	}

	// THE PARAGRAPHING, WHICH NO VERIFICATION TIER CAN SEE.  The typedef sat
	// between two blank lines; deleting the line alone would leave a run of
	// two, and neither a byte-identical binary nor an identical token stream
	// would show it.
	if z16Runs(newS) != z16Runs(oldS) {
		r.bad("runs of two blank lines: %d in the output against %d in the input. The "+
			"typedef sat between two blanks and one of them goes with it; no "+
			"verification tier can see this, which is why it is counted",
			z16Runs(newS), z16Runs(oldS))
	}

	// The tables this phase does not touch.
	rows := z16Row.FindAllString(newS, -1)
	got, err := harness.CommandNames(f)
	if err != nil {
		r.bad("the command table could not be read: %v", err)
	}
	if len(rows) != 98 || len(got) != 98 {
		r.bad("cmdnames[] has %d rows and names() reads %d; both must be 98, and this "+
			"phase touches no table", len(rows), len(got))
	}
	i := strings.Index(newS, "static struct vimoption options[]")
	j := strings.Index(newS[i:], "\n};") + i
	if k := len(z16OptRow.FindAllString(newS[i:j], -1)); k != 108 {
		r.bad("options[] is not the 108 rows phase 12 left")
	}

	// And the line count: EIGHT lines and no more -- the six `#include` lines,
	// the stat_T typedef and one of its two blank lines.  Nothing else may go,
	// and the sweep between the edit and this check must have found nothing,
	// which is what a phase that removes no code predicts.
	nNew := len(strings.Split(newS, "\n"))
	nOld := len(strings.Split(oldS, "\n"))
	if nNew != nOld-8 {
		r.bad("the file lost %d lines, expected 8 -- six `#include` lines, the stat_T "+
			"typedef and one of its two blanks", nOld-nNew)
	}

	if err := r.done(); err != nil {
		return err
	}
	r.say("eighteen directives -> TWELVE, every one an `#include <...>` of a system " +
		"header on the first twelve lines, and no #define, #if or #pragma anywhere: " +
		"<sys/stat.h>, <fcntl.h>, <iconv.h>, <string.h>, <ctype.h> and <wctype.h> are " +
		"gone")
	r.cont("and with <sys/stat.h> its only user, `typedef struct stat stat_T;` -- the " +
		"ONE silent drop in this file, because a typedef of an undeclared struct tag " +
		"compiles cleanly and declares a new, incomplete type.  The loop below could " +
		"not have caught it")
	r.cont("nothing else moved: FILE still at 0, nothing that could open or name a file " +
		"is called, cmdnames[] 98 rows, options[] 108, and the same number of runs of " +
		"two blank lines -- which no verification tier can see")

	// --- 3. THE PHASE: every surviving include is needed -------------------
	// Thirty compiles, run at once.  This is what makes the phase a
	// computation rather than a list, and the second loop is what proves the
	// first can fail.
	kept, was, err := z16DropLoop(newS, oldS, tmp)
	if err != nil {
		return err
	}
	r2 := &rep{tag: "includes", w: w}
	if len(kept) != 12 {
		r2.bad("the output has %d includes to test, expected 12", len(kept))
	}
	var dead []string
	for _, x := range kept {
		if x.ok {
			dead = append(dead, strings.TrimSpace(x.line))
		}
	}
	if len(dead) > 0 {
		r2.bad("%d include(s) survive this phase and are needed by NOTHING: %s -- a phase "+
			"whose whole subject is the includes may not leave a dead one",
			len(dead), strings.Join(dead, ", "))
	}
	if len(was) != 18 {
		r2.bad("the input has %d includes to test, expected 18", len(was))
	}
	var droppable []string
	for _, x := range was {
		if x.ok {
			droppable = append(droppable, strings.TrimSpace(x.line))
		}
	}
	sort.Strings(droppable)
	var want []string
	for _, h := range z16Gone {
		want = append(want, "#include <"+h+">")
	}
	sort.Strings(want)
	if strings.Join(droppable, "\x00") != strings.Join(want, "\x00") {
		shown := strings.Join(droppable, ", ")
		if shown == "" {
			shown = "none"
		}
		r2.bad("on the source this phase was HANDED the identical loop finds %d droppable "+
			"include(s), %s -- it must find exactly the six this phase removes, or the "+
			"loop above is a check that cannot fail", len(droppable), shown)
	}
	if err := r2.done(); err != nil {
		return err
	}
	r2.say("EVERY SURVIVING INCLUDE IS NEEDED, computed and not listed: each of the " +
		"twelve dropped in turn, and all twelve compiles FAIL.  gcc 15 defaults to " +
		"C23, where an implicit declaration is a hard error, so a header that still " +
		"supplies a function, a type or a macro constant cannot go quietly")
	for _, x := range kept {
		why := x.why
		if len(why) > 78 {
			why = why[:78]
		}
		r2.cont("  %-24s %s", strings.Replace(x.line, "#include ", "", 1), why)
	}
	r2.cont("and the same loop on the source this phase was handed finds EXACTLY the six " +
		"it removes -- that is this check proving it can fail, in the same run and on " +
		"the same code path")

	// --- 4. the compile, the linkage and the libc surface ------------------
	// NOTHING IS FREED AND NOTHING ARRIVES.  Stated as a `cmp` of the whole
	// undefined set, which is phase 5's, 11's and 12's equality: a symbol
	// ARRIVING must fail as loudly as one leaving.  A header is not code, so
	// this is what the phase predicts.
	beforeU, err := os.ReadFile(filepath.Join(state, "symbols", "undefined"))
	if err != nil {
		return err
	}
	pc := exec.Command("sh", "tools/phasecheck.sh", work, f, filepath.Join(state, "symbols"))
	pc.Stdout, pc.Stderr = w, w
	if err := pc.Run(); err != nil {
		return fmt.Errorf("  includes     tools/phasecheck.sh refused")
	}
	afterU, err := os.ReadFile(".cache/symbols/last/undefined")
	if err != nil {
		return err
	}
	if !bytes.Equal(beforeU, afterU) {
		r.say("the libc surface moved, and REMOVING AN #include CANNOT MOVE IT:")
		r.cont("gone: %s", strings.Join(z16Minus(beforeU, afterU), " "))
		r.cont("came: %s", strings.Join(z16Minus(afterU, beforeU), " "))
		return fmt.Errorf("includes: the libc surface moved")
	}
	sb, _ := os.ReadFile(".cache/symbols/last/before")
	sa, _ := os.ReadFile(".cache/symbols/last/after")
	r.say("symbols %s -> %s, and the set is IDENTICAL as a cmp -- this phase frees "+
		"nothing and nothing arrives, which is what removing a header that supplied "+
		"nothing must do; main is still the only external symbol, which is also what "+
		"says phases 14 and 15 did not forget a 'static' keyword",
		strings.TrimSpace(string(sb)), strings.TrimSpace(string(sa)))

	// --- 5. the binary, which is the whole of this phase's evidence --------
	_ = exec.Command("make", "-C", work, "clean").Run()
	bin := filepath.Join(work, "zero-vim")
	if _, err := os.Stat(bin); err == nil {
		return fmt.Errorf("  build        the clean did not remove zero-vim, so a 'rebuild' " +
			"below could be no rebuild at all")
	}
	if err := exec.Command("make", "-C", work).Run(); err != nil {
		return fmt.Errorf("  build        FAILED -- rerun by hand: make -C %s", work)
	}
	binSt, err := os.Stat(bin)
	if err != nil {
		return err
	}
	rep := &rep{tag: "build", w: w}
	rep.say("ok, %s -> %d lines, %d bytes", strings.TrimSpace(string(beforeLines)),
		z16CountLines(newB), binSt.Size())

	buildWG.Wait()
	if buildErr != nil {
		return fmt.Errorf("  includes     the reproducible build of the output failed")
	}
	oldSt, err := os.Stat(filepath.Join(state, "old"))
	if err != nil {
		return err
	}
	newSt, err := os.Stat(newBin)
	if err != nil {
		return err
	}
	// A cmp of two files that were never written passes.  Both must exist,
	// both must be the size of an editor, and the one under test must be the
	// size make just produced.
	if newSt.Size() < 500000 || oldSt.Size() < 500000 {
		return fmt.Errorf("  includes     one of the two binaries is %d / %d bytes, which is "+
			"not an editor -- a cmp of two files nothing wrote passes",
			oldSt.Size(), newSt.Size())
	}
	if newSt.Size() != binSt.Size() {
		return fmt.Errorf("  includes     the reproducible build is %d bytes and make produced "+
			"%d: the two differ by more than a timestamp, so the comparison below "+
			"would not be about this boundary", newSt.Size(), binSt.Size())
	}
	a, err := os.ReadFile(filepath.Join(state, "old"))
	if err != nil {
		return err
	}
	b, err := os.ReadFile(newBin)
	if err != nil {
		return err
	}
	if !bytes.Equal(a, b) {
		r.say("THE BINARY MOVED.  This phase removes six '#include' lines and one")
		r.cont("typedef and must change no code at all, so the two binaries -- the")
		r.cont("input's and the output's, both built with SOURCE_DATE_EPOCH=0 and")
		r.cont("the boundary's own flags -- must be the same bytes.")
		r.cont("%d in, %d out.  The GNU build-id note is a hash of", oldSt.Size(), newSt.Size())
		r.cont("the whole image and sits near the front, so the first difference")
		r.cont("below is always that note and never the change itself:")
		r.cont("%s", z16FirstDiff(a, b))
		return fmt.Errorf("includes: the binary moved")
	}
	r.say("THE BINARY IS BYTE-IDENTICAL, %d bytes either side -- tier 1 of CLAUDE.md's "+
		"verification table, and the whole of this phase's evidence.  A byte-identical "+
		"binary subsumes every screen case, every Ex-command row, every command line "+
		"and every pty scenario at once, because the program that would be run is the "+
		"same program; tools/zerodelta.sh --phase 16 runs next and corroborates rather "+
		"than proves", newSt.Size())
	return nil
}

type z16Drop struct {
	src, line, why string
	ok             bool
}

// z16DropLoop removes each `#include` in turn from both files and compiles,
// all thirty at once.
func z16DropLoop(newS, oldS, dir string) (kept, was []z16Drop, err error) {
	cc := []string{"-fsyntax-only", "-O0", "-w", "-fmax-errors=1"}
	d, err := os.MkdirTemp("", "zero16-drop-")
	if err != nil {
		return nil, nil, err
	}
	defer os.RemoveAll(d)

	type job struct {
		src, tag string
		i        int
	}
	var jobs []job
	for _, x := range z16Directives(newS) {
		jobs = append(jobs, job{newS, "out", x.at})
	}
	for _, x := range z16Directives(oldS) {
		jobs = append(jobs, job{oldS, "in", x.at})
	}

	res := make([]z16Drop, len(jobs))
	sem := make(chan struct{}, 16)
	var wg sync.WaitGroup
	for k, jb := range jobs {
		wg.Add(1)
		go func(k int, jb job) {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()
			L := strings.Split(jb.src, "\n")
			// The two loops run at once in one directory, and both index from
			// zero: a name made from the index alone has each file written
			// and unlinked twice.
			out := filepath.Join(d, fmt.Sprintf("%s%d.c", jb.tag, jb.i))
			body := append(append([]string{}, L[:jb.i]...), L[jb.i+1:]...)
			if err := os.WriteFile(out, []byte(strings.Join(body, "\n")), 0o644); err != nil {
				return
			}
			cmd := exec.Command("gcc", append(append([]string{}, cc...), out)...)
			var errb strings.Builder
			cmd.Stderr = &errb
			runErr := cmd.Run()
			os.Remove(out)
			why := ""
			for _, l := range strings.Split(errb.String(), "\n") {
				if strings.Contains(l, "error:") {
					why = strings.TrimSpace(z16GccErr.ReplaceAllString(l, ""))
					break
				}
			}
			res[k] = z16Drop{jb.tag, L[jb.i], why, runErr == nil}
		}(k, jb)
	}
	wg.Wait()
	for _, x := range res {
		if x.src == "out" {
			kept = append(kept, x)
		} else {
			was = append(was, x)
		}
	}
	return kept, was, nil
}

func z16Consecutive(d []z16Directive, from, n int) bool {
	if len(d) != n {
		return false
	}
	for k, x := range d {
		if x.at != from+k {
			return false
		}
	}
	return true
}

func z16SameSet(a, b []string) bool {
	x := append([]string{}, a...)
	y := append([]string{}, b...)
	sort.Strings(x)
	sort.Strings(y)
	return strings.Join(x, "\x00") == strings.Join(y, "\x00")
}

func z16Minus(a, b []byte) []string {
	in := map[string]bool{}
	for _, l := range strings.Split(string(b), "\n") {
		in[l] = true
	}
	var out []string
	for _, l := range strings.Split(string(a), "\n") {
		if l != "" && !in[l] {
			out = append(out, l)
		}
	}
	return out
}

func z16CountLines(b []byte) int {
	return bytes.Count(b, []byte{'\n'})
}

func z16FirstDiff(a, b []byte) string {
	n := len(a)
	if len(b) < n {
		n = len(b)
	}
	for i := 0; i < n; i++ {
		if a[i] != b[i] {
			return fmt.Sprintf("differ: char %d, line %d", i+1,
				bytes.Count(a[:i], []byte{'\n'})+1)
		}
	}
	return fmt.Sprintf("EOF on the shorter at char %d", n)
}
