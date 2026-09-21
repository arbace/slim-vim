package check

import (
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"sync"

	"slimvim.local/tools/internal/cutil"
	"slimvim.local/tools/internal/harness"
)

func init() { register("zero9", Zero9) }

var z9Gone = []string{"readfile", "read_buffer", "read_eintr", "readfile_linenr", "filemess",
	"msg_add_fname", "msg_add_lines", "msg_add_eol", "after_pathsep",
	"dir_of_file_exists", "fix_help_buffer", "gettail_sep", "mch_isdir",
	"set_rw_fname", "u_find_first_changed", "utf_ptr2len_len",
	"read_stdin", "read_fifo", "check_readonly",
	"READ_NEW", "READ_STDIN", "READ_BUFFER", "READ_FIFO", "READ_FILTER", "READ_NOFILE",
	"READ_KEEP_UNDO", "READ_DUMMY"}

// z9GoneStrings are the twenty-four literals the message layer was the last to
// say: filemess(), msg_add_fname(), msg_add_lines() and msg_add_eol() are the
// whole of what printed `"keys" [noeol] 1L, 30B` after a read.
var z9GoneStrings = []string{
	`"%s%ldL, %lldB"`, `"%s%ld line, "`, `"%s%ld lines, "`, `"%lld byte"`,
	`"%lld bytes"`, `"[noeol]"`, `"[READ ERRORS]"`, `"[New DIRECTORY]"`,
	`"[Incomplete last line]"`, `"[long lines split]"`, `"[ILLEGAL BYTE in line %ld]"`,
	`"[File too big]"`, `"[Permission Denied]"`, `"[fifo]"`, `"[socket]"`,
	`"is a directory"`, `"is not a file"`, `"Illegal file name"`, `"-stdin-"`,
	`"Vim: Reading from stdin...\n"`, `"\" "`,
	`"E200: *ReadPre autocommands made the file unreadable"`,
	`"E201: *ReadPre autocommands must not change current buffer"`,
	`"E812: Autocommands changed buffer or buffer name"`,
}

var z9Kept = map[string]int{
	"open_buffer": 5, "read_cmd_fd": 12, "b_ffname": 32, "b_fname": 29, "b_sfname": 26,
	"setfname": 2, "check_fname": 3, "readonlymode": 3, "msg_scrolled_ign": 2,
	"b_mtime_read": 3, "b_mtime_read_ns": 3, "b_orig_size": 3, "b_orig_mode": 3,
	"buf_store_time": 3, "set_b0_fname": 4, "ml_open": 3, "p_ur": 2,
	"check_changed": 4, "nv_error": 46, "secure": 11,
	"eval_vars": 4, "expand_filename": 3, "fix_fname": 3,
	"vim_FullName": 3, "mch_FullName": 3, "mch_dirname": 5,
}

var z9EnumWant = []string{"BF_NEW_W", "CONV_RESTLEN", "CPO_FNAMER", "NOTDONE", "O_EXTRA",
	"READ_BUFFER", "READ_DUMMY", "READ_FIFO", "READ_FILTER", "READ_KEEP_UNDO",
	"READ_NEW", "READ_NOFILE", "READ_STDIN", "SHM_LAST", "SHM_LINES", "SHM_OVER", "SHM_OVERALL"}

const z9Mark = "READFILE-ENTERED"

// Zero9 is phase 9's check: the machinery under every way of naming a file.
//
// THIS IS THE ONE ZERO PHASE NO RECORDING CAN SEE, and it says so.  readfile()
// was already unreachable when the phase ran -- phases 5 to 8 took every way to
// name a file -- so the declared delta is nothing at all and two full
// recordings are byte-identical.  The evidence is an INSTRUMENTED PAIR: the
// input source built twice, with a write(2, ...) first in readfile() and then
// in open_buffer(), the identical instrument.
func Zero9(w io.Writer, args []string) error {
	if len(args) < 2 {
		return fmt.Errorf("usage: check zero9 <work-dir> <state-dir>")
	}
	work, state := args[0], args[1]
	r := &rep{tag: "nobyte", w: w}
	f := filepath.Join(work, "zero-vim.c")
	beforeLines := strings.TrimSpace(readFile(filepath.Join(state, "input-lines")))
	stop := func(format string, a ...any) error { r.say(format, a...); return harness.ErrReported }
	tmp, err := os.MkdirTemp("", "zero9")
	if err != nil {
		return err
	}
	defer os.RemoveAll(tmp)
	inst := filepath.Join(tmp, "i")
	os.MkdirAll(inst, 0o755)

	// The two instrumented builds start FIRST and are waited for in section 6:
	// three and a half seconds each of wall time the source checks below can be
	// spending instead.  The flags are the boundary's, as everywhere.
	mk := readFile(filepath.Join(work, "Makefile"))
	cflags := strings.Fields(z9Flag(mk, "CFLAGS"))
	ldflags := strings.Fields(z9Flag(mk, "LDFLAGS"))
	oldC := readFile(filepath.Join(state, "old.c"))
	for _, p := range []struct{ fn, name string }{{"readfile", "probe.c"}, {"open_buffer", "ctl.c"}} {
		var heads []string
		for _, l := range strings.Split(oldC, "\n") {
			if strings.HasPrefix(l, p.fn+"(") {
				heads = append(heads, l)
			}
		}
		if len(heads) != 1 {
			return stop("%s is not one definition head in the input source", p.fn)
		}
		head := heads[0] + "\n{\n"
		if strings.Count(oldC, head) != 1 {
			return stop("%s does not open exactly once in the input source", p.fn)
		}
		os.WriteFile(filepath.Join(inst, p.name),
			[]byte(strings.Replace(oldC, head, head+"    (void)write(2, \""+z9Mark+"\\n\", 17);\n", 1)), 0o644)
	}
	var bwg sync.WaitGroup
	buildErr := map[string]error{}
	var bmu sync.Mutex
	for _, n := range []string{"probe", "ctl"} {
		bwg.Add(1)
		go func(n string) {
			defer bwg.Done()
			a := append(append([]string{}, cflags...), ldflags...)
			a = append(a, "-o", n, n+".c")
			c := exec.Command("gcc", a...)
			c.Dir = inst
			e := c.Run()
			bmu.Lock()
			buildErr[n] = e
			bmu.Unlock()
		}(n)
	}

	src, err := os.ReadFile(f)
	if err != nil {
		return err
	}
	newT := string(src)

	// --- 1. what the sweep took ----------------------------------------------
	for _, g := range z9Gone {
		if n := countWord(src, g); n != 0 {
			return stop("'%s' still has %d mentions", g, n)
		}
	}
	r.say("sixteen functions, read_stdin, read_fifo, check_readonly and the eight READ_ enumerators at 0 mentions -- all of it the sweep's, the edit named none of them")

	// --- 2. the source, in both directions -----------------------------------
	var fail []string
	count := func(t, name string) int {
		return len(regexp.MustCompile(`\b` + regexp.QuoteMeta(name) + `\b`).FindAllString(t, -1))
	}
	var still, missing []string
	for _, s := range z9GoneStrings {
		if strings.Contains(newT, s) {
			still = append(still, s)
		}
		if !strings.Contains(oldC, s) {
			missing = append(missing, s)
		}
	}
	if len(still) > 0 {
		fail = append(fail, fmt.Sprintf("%d of the 24 strings the message layer was the last to say are still here: %s",
			len(still), strings.Join(head4(still), " ")))
	}
	if len(missing) > 0 {
		fail = append(fail, fmt.Sprintf("the input did not say %s, so this phase is being checked against a file it was not written for",
			strings.Join(head4(missing), " ")))
	}
	// THE OTHER DIRECTION, where a copied "no mention anywhere" loop fails.
	for _, lw := range []struct {
		lit  string
		want int
	}{{`"[RO]"`, 2}, {`"[readonly]"`, 1}, {`"%ld line --%d%%--"`, 1}} {
		if k := strings.Count(newT, lw.lit); k != lw.want {
			fail = append(fail, fmt.Sprintf("%s occurs %d times, expected %d -- readfile was one speaker of the first two and none of the third",
				lw.lit, k, lw.want))
		}
	}
	names := make([]string, 0, len(z9Kept))
	for n := range z9Kept {
		names = append(names, n)
	}
	sort.Strings(names)
	for _, name := range names {
		want := z9Kept[name]
		if k := count(newT, name); k != want {
			why := "something survived that should not have"
			if k < want {
				why = "this phase reached too far"
			}
			fail = append(fail, fmt.Sprintf("%s has %d mentions, expected %d -- %s", name, k, want, why))
		}
	}
	// msg_scrolled_ign IS A LEFTOVER AND IS NAMED AS ONE: four writers, all
	// inside filemess() and readfile(), and one reader.  After this phase it is
	// FALSE for ever with the reader still testing it, and NOTHING SEES THAT.
	writes := regexp.MustCompile(`\bmsg_scrolled_ign\b\s*=`).FindAllString(newT, -1)
	if len(writes) != 1 || !strings.Contains(newT, "static int      msg_scrolled_ign  = FALSE ;") {
		fail = append(fail, fmt.Sprintf("msg_scrolled_ign is assigned %d times: after this phase the only one left must be its initialiser, FALSE", len(writes)))
	}
	if a, z, ok := cutil.FindDefinition(src, cutil.Blank(src), "msg_puts_attr_len"); !ok || !strings.Contains(newT[a:z], "msg_scrolled_ign") {
		fail = append(fail, "msg_puts_attr_len no longer reads msg_scrolled_ign, and this phase removed its writers and not its reader")
	}
	// THE FOUR FIELDS THAT BECOME WRITE-ONLY, and why no tool here can take
	// them: deadfields.py removes a field nothing NAMES, and these are named.
	for _, fld := range []string{"b_mtime_read", "b_mtime_read_ns", "b_orig_size", "b_orig_mode"} {
		var reads int
		for _, m := range regexp.MustCompile(`\b`+regexp.QuoteMeta(fld)+`\b`).FindAllStringIndex(newT, -1) {
			tail := newT[m[1]:min(m[1]+3, len(newT))]
			if !regexp.MustCompile(`^\s*=[^=]`).MatchString(tail) {
				reads++
			}
		}
		if !regexp.MustCompile(`(?m)^    \w+[ \t]+`+regexp.QuoteMeta(fld)+`;$`).MatchString(newT) {
			fail = append(fail, fmt.Sprintf("%s is no longer a field of buf_T, and this phase leaves it write-only rather than removing it", fld))
		}
		if reads != 1 {
			fail = append(fail, fmt.Sprintf("%s is read %d times outside an assignment; after this phase every mention but the declaration must be a write", fld, reads-1))
		}
	}
	if strings.Count(newT, "E32: No file name") != 1 {
		fail = append(fail, "E32: No file name went, and it is reachable through check_fname()")
	}
	if !strings.Contains(newT, "E37: No write since last change") {
		fail = append(fail, "E37 went, and check_changed() is the :q phase's")
	}
	for _, kept := range []string{"open_buffer", "ml_open", "buflist_new", "do_one_cmd", "nv_g_cmd",
		"msg_puts_attr_len", "fileinfo", "get_spec_reg"} {
		if count(newT, kept) == 0 {
			fail = append(fail, fmt.Sprintf("%s went, and it is a later phase's or this phase only cut inside it", kept))
		}
	}
	rows := z6RowRe.FindAllString(newT, -1)
	got, err9 := harness.CommandNamesIn(src, "zero-vim.c")
	// THE FLOOR, ASSERTED BY USING IT rather than by grepping for the number.
	if err9 != nil {
		fail = append(fail, fmt.Sprintf("the checked parser refuses this table -- the row floor is no longer below 99: %s", err9))
	}
	if len(rows) != 99 || len(got) != 99 {
		fail = append(fail, fmt.Sprintf("cmdnames[] has %d rows and names() reads %d; both must be 99, unchanged: this phase removes no command", len(rows), len(got)))
	}
	if len(z6RowRe.FindAllString(oldC, -1)) != 99 {
		fail = append(fail, "the input does not have 99 rows, so this is not the file this phase was written against")
	}
	if !strings.Contains(newT, "static_assert(sizeof(cmdnames) / sizeof(cmdnames[0]) == CMD_SIZE") {
		fail = append(fail, "the static_assert on the row count went, and it is what catches an enumerator removed without its row")
	}
	for _, name := range []string{"file", "quit", "print", "append", "registers"} {
		if !contains(got, name) {
			fail = append(fail, fmt.Sprintf(":%s went, and no command is this phase's", name))
		}
	}
	for _, p := range []struct {
		name string
		want int
	}{{"readfile", 5}, {"read_buffer", 17}, {"open_buffer", 5}, {"read_stdin", 23},
		{"check_readonly", 4}, {"readonlymode", 5}} {
		if count(oldC, p.name) != p.want {
			fail = append(fail, fmt.Sprintf("the input is not the file this phase was written against: %s %d, expected %d",
				p.name, count(oldC, p.name), p.want))
		}
	}
	if len(fail) > 0 {
		for _, l := range fail {
			r.say("%s", l)
		}
		r.cont(`a "no mention anywhere" check fails on a correct phase here:`)
		r.cont("check_readonly was readfile's LOCAL and reaches 0 only now,")
		r.cont(`readonlymode goes 5 -> 3 where phase 8 asserted 5, "[RO]" and`)
		r.cont(`"[readonly]" each keep a speaker, and read_cmd_fd is the`)
		r.cont("terminal's and does not move at all.")
		return harness.ErrReported
	}
	r.say(`the 24 strings gone and "[RO]" 3 -> 2, "[readonly]" 2 -> 1 and CTRL-G's counter kept: readfile was one speaker of the first two and none of the third`)
	r.cont("kept: open_buffer 5, read_cmd_fd 12 on 11 lines (the terminal's), b_ffname 32 and b_fname 29 (phase 10's), setfname 2 (set_rw_fname was its second caller), E32 and E37 with their speakers")
	r.cont("left and named rather than folded: msg_scrolled_ign at 2 mentions, FALSE for ever with one reader in msg_puts_attr_len, and b_mtime_read, b_mtime_read_ns, b_orig_size and b_orig_mode write-only -- phase 10's")
	r.cont("table: 99 rows and names() reads 99, unchanged -- this phase removes no command, and the floor keeps its 19 rows of margin")

	// --- 3. the compile, the linkage and the libc surface --------------------
	before := strings.Fields(readFile(filepath.Join(state, "symbols", "undefined")))
	if err := run(w, "sh", "tools/phasecheck.sh", work, f, filepath.Join(state, "symbols")); err != nil {
		return harness.ErrReported
	}
	after := strings.Fields(readFile(".cache/symbols/last/undefined"))
	goneU, cameU := comm23(before, after), comm23(after, before)
	if strings.Join(goneU, "\n") != "access\nfcntl\nopen" || len(cameU) > 0 {
		r.say("the libc surface did not move by exactly access, fcntl and open:")
		r.cont("  gone: %s ", strings.Join(goneU, " "))
		r.cont("  came: %s ", strings.Join(cameU, " "))
		return harness.ErrReported
	}
	for _, keep := range []string{"stat", "getcwd", "strerror", "fsync", "read", "close", "dup"} {
		if !contains(after, keep) {
			return stop("%s went, and it is not this phase's: read, close and dup are the terminal's, stat, getcwd and strerror are phase 10's, fsync the FILE* phase's", keep)
		}
	}
	r.say("symbols %s -> %s, and the set is exactly access fcntl open; read close dup stat getcwd strerror fsync all still undefined",
		strings.TrimSpace(readFile(".cache/symbols/last/before")),
		strings.TrimSpace(readFile(".cache/symbols/last/after")))

	// --- 4. the enumerators --------------------------------------------------
	evOld, evNew := filepath.Join(tmp, "ev.old"), filepath.Join(tmp, "ev.new")
	var ewg sync.WaitGroup
	ewg.Add(1)
	go func() { defer ewg.Done(); exec.Command("sh", "tools/enumvals.sh", filepath.Join(state, "old.c"), evOld).Run() }()
	exec.Command("sh", "tools/enumvals.sh", f, evNew).Run()
	ewg.Wait()
	if err := z9Enums(r, readFile(evOld), readFile(evNew)); err != nil {
		return err
	}

	// --- 5. the binary -------------------------------------------------------
	_ = exec.Command("make", "-C", work, "clean").Run()
	if err := exec.Command("make", "-C", work).Run(); err != nil {
		(&rep{tag: "build", w: w}).say("FAILED -- rerun by hand: make -C %s", work)
		return harness.ErrReported
	}
	bin, _ := filepath.Abs(filepath.Join(work, "zero-vim"))
	old, _ := filepath.Abs(filepath.Join(state, "old"))
	now, _ := os.ReadFile(f)
	(&rep{tag: "build", w: w}).say("ok, %s -> %d lines, %d bytes", beforeLines, countLines(now), sizeOf(bin))

	// --- 6, 7, 8 -------------------------------------------------------------
	bwg.Wait()
	if buildErr["probe"] != nil {
		return stop("the readfile() probe did not build")
	}
	if buildErr["ctl"] != nil {
		return stop("the open_buffer() control did not build")
	}
	return z9Evidence(r, tmp, inst, state, f, old, bin)
}

func z9Flag(mk, name string) string {
	m := regexp.MustCompile(`(?m)^` + name + `  *= *(.*)$`).FindStringSubmatch(mk)
	if m == nil {
		return ""
	}
	return m[1]
}

func head4(s []string) []string {
	if len(s) > 4 {
		return s[:4]
	}
	return s
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}

// z9Enums: SEVENTEEN GO AND NOTHING RENUMBERS, which is the opposite of phase 8
// and worth the four seconds either side to say.  A whole anonymous definition
// leaving takes no survivor's value with it.
func z9Enums(r *rep, oldTxt, newTxt string) error {
	load := func(s string) map[string]string {
		m := map[string]string{}
		for _, l := range strings.Split(s, "\n") {
			if i := strings.LastIndexByte(l, '='); i > 0 {
				m[l[:i]] = l[i+1:]
			}
		}
		return m
	}
	o, n := load(oldTxt), load(newTxt)
	var gone, came, moved []string
	for k := range o {
		if _, ok := n[k]; !ok {
			gone = append(gone, k)
		} else if n[k] != o[k] {
			moved = append(moved, k)
		}
	}
	for k := range n {
		if _, ok := o[k]; !ok {
			came = append(came, k)
		}
	}
	sort.Strings(gone)
	sort.Strings(came)
	sort.Strings(moved)
	if strings.Join(gone, " ") != strings.Join(z9EnumWant, " ") || len(came) > 0 || len(moved) > 0 {
		if strings.Join(gone, " ") != strings.Join(z9EnumWant, " ") {
			r.say("enumerators gone: %s", strings.Join(gone, " "))
			r.cont("expected exactly: %s", strings.Join(z9EnumWant, " "))
		}
		if len(came) > 0 {
			r.say("enumerators arrived: %s", strings.Join(came, " "))
		}
		if len(moved) > 0 {
			r.say("enumerators moved value, and none may: %s", strings.Join(moved, " "))
		}
		return harness.ErrReported
	}
	r.say("enumerators %d -> %d: 17 whole anonymous definitions gone, NOT ONE survivor renumbered and none arriving -- no parallel table can have shifted", len(o), len(n))
	return nil
}

var _ = io.Discard
