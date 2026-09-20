package harness

// hostExceptions is zhostonly.py's EXCEPTIONS, transcribed by a program.
//
// Every one is a place the CORE still says one of the host words, and each
// is there because it was read and kept, not because the pattern was
// loosened.  COUNTS IS A LIST because the tool runs at more than one
// boundary and the core's vocabulary shrinks between them -- an exception
// that is 2 at r20 and 0 at r26 is not a contradiction, it is the pipeline
// working.  What it refuses is a count NOBODY HAS WRITTEN DOWN.
var hostExceptions = []struct {
	fn, word string
	counts   []int
	why      string
}{
	{"signal_info[]", "SIGHUP", []int{1}, "the deadly-signal table: the two signals whose NAME the editor reports.  The host installs the handler; the core still owns the message"},
	{"signal_info[]", "SIGTERM", []int{1}, "the same row of the same table"},
	{"deathtrap", "SIGHUP", []int{1}, "deathtrap's own test for the two signals it may defer.  The core keeps this function on purpose: it is what restores the terminal and writes `Vim: Caught deadly signal` before the editor ends, and the host installs it rather than replacing it"},
	{"deathtrap", "SIGTERM", []int{1}, "the same test"},
	{"vim_handle_signal", "kill", []int{0, 1}, "re-raising a deadly signal that arrived while the editor was not reading.  It was the ONLY core mention of any of these words that was not a message, and it was kept -- up to zero phase 35 -- because deleting it would make a deadly signal act in the middle of a screen update, a behaviour change no recording can see.  0 from phase 36: the DEFERRAL stays and only the re-raise crosses the boundary, as `host_raise(got_signal)`, so the core still decides WHEN the signal acts and the host is what raises it"},
	{"vim_handle_signal", "getpid", []int{0, 1}, "the other half of that one expression -- `kill(getpid(), got_signal)` asked for this process by number, and 0 from zero phase 36 because `host_raise(int sig)` names no pid.  A core that can no longer ask for its own process id must not be handed one, which is the same rule that kept fd 1 out of host_write (phase 35) and fd 0 out of musl_read_input (phase 20)"},
	{"mch_get_pid", "getpid", []int{0, 1}, "the core's other getpid, `return (long)getpid();`, whose ONE caller wrote a `b0_pid` into block zero that nothing has read since the filesystem phases.  0 from zero phase 36, which took the write, the function and the field: that getpid was AVOIDABLE outright and crossed no boundary.  Zero phase 20 said so in advance -- \"one line frees it whenever block zero is somebody's phase\""},
	{"<file scope>", "kill", []int{0, 1}, "1 from zero phase 26, which gave the core its own PROTOTYPE for it; 0 before, and 0 again from phase 36, which took the last core call and the declaration with it.  It is the exception above wearing its other face -- the core re-raised a deadly signal, and from phase 26 it DECLARED what it called instead of taking the declaration from <signal.h>, because the headers were on their way below the boundary"},
	{"<file scope>", "getpid", []int{0, 1}, "1 from zero phase 26, which wrote `int getpid(void);` into the core's block of ordinary declarations, and 0 before and after.  Phase 36 empties that block: the two lines it took were this one and `kill`, and from that boundary the core names NO libc function at all"},
	{"<file scope>", "SIGHUP", []int{0, 2}, "2 from zero phase 27, which moved the eleven `#include`s below the core: the core's own `enum { SIGHUP = 1 };` above the boundary, and the `static_assert(1 == SIGHUP, \"SIGHUP\");` below the includes that checks it against <signal.h>.  0 before, the name having come from the header.  It is the two exceptions above wearing another face -- the core still NAMES the two deadly signals it reports, and from that phase it declares the numbers instead of being given them.  Both lines are outside the host region this tool reads, the assert because the region begins at host_winch_pending and the includes are above it"},
	{"<file scope>", "SIGTERM", []int{0, 2}, "the same two lines for the other signal"},
	{"<file scope>", "struct timeval", []int{0, 2}, "2 up to zero phase 25 -- `elapsed_T`'s typedef and `elapsed`'s prototype, the clock's -- and 0 from phase 26, which is the \"somebody else's later phase\" the old wording pointed at: `elapsed_T` is now the core's own TAGLESS `struct { long tv_sec; long tv_usec; }`"},
	{"elapsed", "struct timeval", []int{0, 2}, "the same clock, in the one function that reads it, and 0 from the same phase: the five `gettimeofday` calls go through the host block.  Zero phase 28 deletes `elapsed()` itself, so from that boundary this bucket cannot exist at all -- it stays here because the tool is run at r20, r21 and r25 too, where the function and its `struct timeval` are both there"},
	{"do_sleep", "gettimeofday", []int{0, 1}, "do_sleep's stamp, 1 up to zero phase 25 and 0 from phase 26, which routed it through the host.  It is one of five, and from phase 28 the core stamps with `start_tv = musl_now_ms();`"},
	{"vim_beep", "gettimeofday", []int{0, 1}, "vim_beep's stamp, the second of the five"},
	{"elapsed", "gettimeofday", []int{0, 1}, "elapsed()'s own read of the clock, the third of the five -- and the only one that was a READ rather than a stamp.  Phase 28 deletes the function"},
	{"handle_osc", "gettimeofday", []int{0, 1}, "handle_osc's stamp into osc_state.start_tv, the fourth"},
	{"inchar_loop", "gettimeofday", []int{0, 1}, "inchar_loop's stamp, the fifth and last"},
}

var hostFuncs = []string{"host_catch", "host_on_winch", "host_on_tstp", "host_on_int", "host_tty_set", "musl_host_init", "musl_get_winsize", "musl_term_start", "musl_term_stop", "musl_tty_keys", "musl_delay", "musl_wait_for_input", "musl_read_input", "musl_suspend"}

var hostMust = []string{"sigaction", "ioctl", "tcsetattr", "nanosleep", "select", "kill"}

const hostBegin = "static volatile sig_atomic_t host_winch_pending"
const hostLast = "musl_suspend"
