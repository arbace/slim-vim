package check

import (
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"

	"slimvim.local/tools/internal/harness"
)

func init() { register("zero20", Zero20) }

const (
	z20SleepA = "    if (relax)\n    {\n        host_tty_set(FALSE, TRUE);\n    }\n"
	z20SleepB = "    if (relax)\n    {\n        host_tty_set(TRUE, FALSE);\n    }\n"
)

// Zero20 is phase 20's check: the signals and the terminal are the host's.
func Zero20(w io.Writer, args []string) error {
	if len(args) < 2 {
		return fmt.Errorf("usage: check zero20 <work-dir> <state-dir>")
	}
	work, state := args[0], args[1]
	r := &rep{tag: "host", w: w}
	f := filepath.Join(work, "zero-vim.c")
	beforeLines := strings.TrimSpace(readFile(filepath.Join(state, "input-lines")))
	tmp, err := os.MkdirTemp("", "zero20")
	if err != nil {
		return err
	}
	defer os.RemoveAll(tmp)
	mk := readFile(filepath.Join(work, "Makefile"))
	cflags, ldflags := strings.Fields(z9Flag(mk, "CFLAGS")), strings.Fields(z9Flag(mk, "LDFLAGS"))
	newC, oldC := readFile(f), readFile(filepath.Join(state, "old.c"))

	// --- 1. the control ------------------------------------------------------
	for _, t := range []string{z20SleepA, z20SleepB} {
		if strings.Count(newC, t) != 1 {
			r.say("the musl_delay sleep-mode pair is not in the output exactly once, so the control below would not be the control")
			return harness.ErrReported
		}
	}
	nosleep := filepath.Join(tmp, "nosleep")
	os.WriteFile(nosleep+".c", []byte(strings.ReplaceAll(strings.ReplaceAll(newC, z20SleepA, ""), z20SleepB, "")), 0o644)
	r.say("the control: this phase's own output with musl_delay()'s two host_tty_set() calls deleted and nothing else -- the sleep mode gone and the nanosleep left")
	ctl := make(chan error, 1)
	go func() {
		a := append(append(append([]string{}, cflags...), ldflags...), "-o", nosleep, nosleep+".c")
		ctl <- exec.Command("gcc", a...).Run()
	}()

	// --- 2. the source -------------------------------------------------------
	var fail []string
	mentions := func(t, name string) int {
		return len(regexp.MustCompile(`\b` + name + `\b`).FindAllString(t, -1))
	}
	for _, p := range []struct {
		name string
		want int
	}{{"mch_signal", 18}, {"signal_info", 9}, {"settmode", 13}, {"isatty", 4}, {"deathtrap", 3}, {"win_resize_enabled", 6}} {
		if n := mentions(oldC, p.name); n != p.want {
			fail = append(fail, fmt.Sprintf("the input has %d mentions of `%s`, expected %d", n, p.name, p.want))
		}
	}
	gone := strings.Fields("mch_signal set_signals reset_signals catch_signals catch_int_signal " +
		"catch_sigint sig_tstp sigcont_handler sigcont_received after_sigcont " +
		"in_mch_suspend ignore_sigtstp got_tstp sig_winch set_sigwinch_handler " +
		"handle_resize do_resize mch_get_shellsize win_resize_setting " +
		"win_resize_enabled term_set_win_resize did_set_termresize p_trz " +
		"settmode mch_settmode mch_tcgetattr get_tty_fd mch_cur_tmode cur_tmode " +
		"mch_check_win stdout_isatty did_read_something isatty out_redir " +
		"tmode_T TMODE_COOK TMODE_RAW TMODE_SLEEP sighandler_T " +
		"MCH_DELAY_SETTMODE")
	var left []string
	for _, n := range gone {
		if mentions(newC, n) > 0 {
			left = append(left, n)
		}
	}
	if len(left) > 0 {
		fail = append(fail, "these names should be at 0 mentions and are not: "+strings.Join(left, " "))
	}
	for _, n := range gone {
		if mentions(oldC, n) == 0 {
			fail = append(fail, fmt.Sprintf("`%s` was already at 0 in the input, so its absence proves nothing", n))
		}
	}
	for _, p := range []struct {
		name string
		want int
		why  string
	}{
		{"resize_func", 6, "inchar_loop's PARAMETER, which STAYS: the prototype, the definition and three uses inside it.  The core passes NULL and inchar_loop tests for it, so `assert resize_func at 0` fails on a correct phase"},
		{"deathtrap", 4, "a prototype, the definition and the TWO installations in musl_host_init().  It GOES UP: the host installs the core's deadly handler rather than replacing it, which is what keeps the terminal restored and the message printed"},
		{"vim_handle_signal", 5, "untouched -- a prototype, the definition, deathtrap's call and the two in ui_inchar"},
		{"signal_info", 4, "the struct tag, the array and deathtrap's two reads.  Its five rows are two and its `deadly` field is gone, because catch_signals() was its only reader"},
		{"term_enter", 6, "a prototype, the definition and four call sites"},
		{"term_leave", 5, "a prototype, the definition and three call sites"},
		{"term_entered", 6, "the flag that replaced the three-valued cur_tmode"},
		{"musl_host_init", 3, "prototype, definition, and the one call from mch_init()"},
		{"musl_get_winsize", 4, "prototype, definition, ui_get_shellsize()'s call and musl_read_input()'s"},
		{"musl_term_start", 3, "prototype, definition, term_enter()'s call"},
		{"musl_term_stop", 3, "prototype, definition, term_leave()'s call"},
		{"musl_tty_keys", 3, "prototype, definition, get_tty_info()'s call"},
		{"musl_delay", 3, "prototype, definition, mch_delay()'s call"},
		{"musl_wait_for_input", 3, "prototype, definition, RealWaitForChar()'s call -- ONE call site, because the pending check that was going to be a second function lives inside it"},
		{"musl_read_input", 3, "prototype, definition, fill_input_buf()'s call"},
		{"musl_suspend", 3, "prototype, definition, mch_suspend()'s call"},
		{"host_catch", 11, "its definition, eight installations in musl_host_init() and two in musl_suspend()"},
		{"errno", 3, "UNCHANGED, and said out loud: the #include and two uses, both of them host-side now.  So <errno.h> leaves the CORE and __errno_location stays in nm -u until the file splits"},
		{"sigaction", 2, "both in host_catch(), 0 in the core"},
		{"sigemptyset", 1, "host_catch(), 0 in the core"},
		{"kill", 2, "musl_suspend()'s kill(0, SIGTSTP) and vim_handle_signal()'s re-raise, which is the one core mention and a named exception in zhostonly"},
		{"ioctl", 2, "the #include and the host's one TIOCGWINSZ"},
		{"tcgetattr", 2, "host_tty_set() and musl_tty_keys()"},
		{"tcsetattr", 1, "host_tty_set()"},
		{"nanosleep", 1, "musl_delay()"},
		{"select", 1, "musl_wait_for_input().  There is no #include for it: it arrives transitively through <sys/param.h> (ZERO-PLAN.md 4c)"},
		{"getpid", 2, "mch_get_pid()'s and vim_handle_signal()'s -- neither is this phase's, and getpid stays"},
	} {
		if n := mentions(newC, p.name); n != p.want {
			fail = append(fail, fmt.Sprintf("`%s` has %d mentions, expected %d -- %s", p.name, n, p.want, p.why))
		}
	}
	rows := z6RowRe.FindAllString(newC, -1)
	got, _ := harness.CommandNamesIn([]byte(newC), "zero-vim.c")
	if len(rows) != 98 || len(got) != 98 {
		fail = append(fail, "cmdnames[] is not the 98 rows phase 10 left -- this phase touches no Ex command")
	}
	if i := strings.Index(newC, "static struct vimoption options[]"); i >= 0 {
		j := strings.Index(newC[i:], "\n};")
		if n := len(z12RowRe.FindAllString(newC[i:i+j], -1)); n != 107 {
			fail = append(fail, fmt.Sprintf("options[] has %d rows, expected 107 -- 'termresize' is the one row this phase removes, from the 108 phase 12 left", n))
		}
	}
	nd, allInc := 0, true
	L := strings.Split(newC, "\n")
	for _, l := range L {
		if strings.HasPrefix(l, "#") {
			nd++
			if !strings.HasPrefix(l, "#include <") {
				allInc = false
			}
		}
	}
	if nd != 12 || !allInc {
		fail = append(fail, "the output does not have exactly the twelve `#include` directives phase 16 left.  This phase adds none and removes none: <errno.h> and <termios.h> are still needed, by the HOST")
	}
	for k := 1; k < len(L); k++ {
		if L[k] == "" && L[k-1] == "" {
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
	r.say("40 names at 0: every signal handler, the installer, the three-valued terminal mode and every question about whether this is a terminal.  `resize_func` is NOT among them (it is inchar_loop's parameter) and `deathtrap` goes UP, 3 -> 4, because the host installs the core's deadly handler rather than replacing it")
	r.cont("the host is 11 host_catch() installations, 2 sigaction, 1 sigemptyset, 1 kill, 1 ioctl, 2 tcgetattr, 1 tcsetattr, 1 nanosleep and 1 select; `errno` does not move at all (3 -> 3), both its uses being host-side, so <errno.h> leaves the CORE and __errno_location stays until the split")
	r.cont("cmdnames[] 98 unchanged, options[] 108 -> 107 (`termresize`), twelve #includes unchanged, no run of two blank lines")

	// --- 3. the structural claim ---------------------------------------------
	if err := run(w, "tools/st.sh", "zhostonly", f); err != nil {
		return harness.ErrReported
	}

	// --- 4. the compile, the linkage and the libc surface --------------------
	before := strings.Fields(readFile(filepath.Join(state, "symbols", "undefined")))
	if err := run(w, "sh", "tools/phasecheck.sh", work, f, filepath.Join(state, "symbols")); err != nil {
		return harness.ErrReported
	}
	after := strings.Fields(readFile(".cache/symbols/last/undefined"))
	goneU, cameU := comm23(before, after), comm23(after, before)
	if strings.Join(goneU, " ") != "close dup isatty raise sigaddset sigismember sigprocmask" || len(cameU) > 0 {
		r.say("the libc surface did not move by exactly those seven:")
		r.cont("gone: %s", trSpace(goneU))
		r.cont("came: %s", trSpace(cameU))
		r.cont("NOTHING MAY ARRIVE, and nothing else may leave.")
		return harness.ErrReported
	}
	for _, want := range strings.Fields("sigaction sigemptyset kill ioctl tcgetattr tcsetattr nanosleep select read write __errno_location") {
		if !contains(after, want) {
			r.say("%s is NOT undefined any more, and this phase does not", want)
			r.cont("claim to free it -- the host block calls it from the same")
			r.cont("translation unit.  If this is really gone, the claim in")
			r.cont("pipes/zero20-edit.sh's header is wrong and needs rewriting")
			return harness.ErrReported
		}
	}
	for _, absent := range strings.Fields("open creat openat stat access fcntl getcwd strerror fopen fdopen opendir fclose getc putc fsync exit _exit") {
		if contains(after, absent) {
			r.say("%s is undefined, and no phase since 13 has put it back", absent)
			return harness.ErrReported
		}
	}
	r.say("symbols %s -> %s, the gone set is EXACTLY close dup isatty raise sigaddset sigismember sigprocmask and NOTHING arrives -- and sigaction sigemptyset kill ioctl tcgetattr tcsetattr nanosleep select are REQUIRED still present, because moving a call inside one translation unit frees nothing",
		strings.TrimSpace(readFile(".cache/symbols/last/before")), strings.TrimSpace(readFile(".cache/symbols/last/after")))
	r.say("ZERO-PLAN.md 4b in its strongest form: with close and dup gone the core cannot open, close or duplicate ANY descriptor -- it is handed fds 0, 1 and 2 and that is the whole of it")

	// --- 5. the binary -------------------------------------------------------
	b := &rep{tag: "build", w: w}
	_ = exec.Command("make", "-C", work, "clean").Run()
	if _, err := os.Stat(filepath.Join(work, "zero-vim")); err == nil {
		b.say("the clean did not remove zero-vim")
		return harness.ErrReported
	}
	if err := exec.Command("make", "-C", work).Run(); err != nil {
		b.say("FAILED -- rerun by hand: make -C %s", work)
		return harness.ErrReported
	}
	bin, _ := filepath.Abs(filepath.Join(work, "zero-vim"))
	old, _ := filepath.Abs(filepath.Join(state, "old"))
	b.say("ok, %s -> %d lines, %d bytes", beforeLines, countLines([]byte(readFile(f))), sizeOf(bin))
	if err := <-ctl; err != nil {
		r.say("the control did not build")
		return harness.ErrReported
	}

	// --- 6. the probes -------------------------------------------------------
	return z20Probes(r, old, bin, nosleep)
}
