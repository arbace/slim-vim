package cut

import (
	"bytes"
	"fmt"
	"io"
	"regexp"
	"sort"
	"strings"

	"slimvim.local/tools/internal/cutil"
	"slimvim.local/tools/internal/dead"
)

const signalTable = `{
    {SIGHUP,        "HUP",      TRUE},
    {SIGTERM,       "TERM",     TRUE},
    {SIGINT,        "INT",      FALSE},
    {SIGWINCH,      "WINCH",    FALSE},
    {SIGTSTP,       "TSTP",     FALSE},
    {-1,            "Unknown!", FALSE}
}`

var signalsKeep = []string{"SIGHUP", "SIGTERM", "SIGINT", "SIGWINCH", "SIGTSTP"}

var (
	sigRow   = regexp.MustCompile(`\{SIG`)
	sigNames = regexp.MustCompile(`\bSIG[A-Z0-9]+\b`)
)

var nosignalsCuts = []struct {
	pat, what string
	count     int
}{
	{`(?m)^[ \t]*mch_signal\(SIGUSR1, catch_sigusr1\);\n`, "the SIGUSR1 install", 1},
	{`(?m)^[ \t]*mch_signal\(SIGPWR, catch_sigpwr\);\n`, "the SIGPWR install", 1},
	{`(?m)^[ \t]*may_core_dump\(\);\n`, "the may_core_dump calls", 2},
	{`(?m)^[ \t]*signal_stack = alloc\(get_signal_stack_size\(\)\);\n`, "the signal stack", 1},
	{`(?m)^[ \t]*init_signal_stack\(\);\n`, "its install", 1},
	{`(?m)^static char \*signal_stack;\n`, "signal_stack", 1},
	{`(?m)^static stack_t sigstk;\n`, "sigstk", 1},
	{`(?m)^static volatile sig_atomic_t got_sigusr1  = FALSE ;\n`, "got_sigusr1", 1},
}

// cookTerminal is what prepare_to_exit's settmode line becomes.
//
// THE CLAIM WAS FALSE WHEN THIS PHASE WAS WRITTEN.  prepare_to_exit() calls
// settmode(TMODE_COOK) to put the terminal back, and settmode opens with
// `if (!full_screen) return;` -- while deathtrap() sets full_screen = FALSE
// several lines before it gets there.  So the editor printed "Vim: Caught
// deadly signal TERM", emitted stoptermcap's escapes, exited, and left the
// terminal with ICANON and ECHO off.  Measured on the slave side of a pty,
// before and after this phase: identical, and wrong both times.  Upstream has
// the same hole.
const cookTerminal = `        // settmode() returns at once when !full_screen, and deathtrap()
        // clears it before this runs -- so on the way out from a signal
        // the one thing this function exists for never happened: the
        // terminal was left with ICANON and ECHO off and the shell that
        // got it back was unusable.  The guard is there to avoid drawing
        // on a screen that is not there, and putting the terminal back is
        // not drawing, so it is lent full_screen for the length of the
        // call.  Upstream has the same hole.
        {
            int was_full_screen = full_screen;

            full_screen = TRUE;
            settmode(TMODE_COOK);
            full_screen = was_full_screen;
        }
`

// NoSignals leaves the five signals this editor can still be sent.
func NoSignals(text []byte, w io.Writer) ([]byte, error) {
	b := cutil.Blank(text)
	k := bytes.Index(text, []byte("} signal_info[] ="))
	if k < 0 {
		return nil, fmt.Errorf("nosignals: signal_info is not where this expects")
	}
	o := k + 10 + bytes.IndexByte(b[k+10:], '{')
	c := cutil.Match(b, o)
	if c < 0 {
		return nil, fmt.Errorf("nosignals: signal_info is unbalanced")
	}
	was := len(sigRow.FindAll(text[o:c], -1))
	var buf []byte
	buf = append(buf, text[:o]...)
	buf = append(buf, signalTable...)
	text = append(buf, text[c+1:]...)
	fmt.Fprintf(w, "  nosignals    signal_info: %d entries -> %d\n", was, len(signalsKeep))

	for _, name := range []string{"catch_sigusr1", "catch_sigpwr", "may_core_dump",
		"init_signal_stack", "get_signal_stack_size"} {
		var ok bool
		if text, ok = cutil.DeleteDefinition(text, name); !ok {
			return nil, fmt.Errorf("nosignals: %s is not defined at file scope", name)
		}
	}
	var err error
	for _, e := range nosignalsCuts {
		if text, err = cutCounted(text, e.pat, "nosignals", e.what, e.count); err != nil {
			return nil, err
		}
	}
	fmt.Fprintln(w, "  nosignals    SIGPWR, whose handler called an empty function; "+
		"SIGUSR1, whose flag nothing reads")

	text = bytes.Replace(text, []byte("            sa.sa_flags = SA_ONSTACK;\n"),
		[]byte("            sa.sa_flags = 0;\n"), 1)
	fmt.Fprintln(w, "  nosignals    the alternate signal stack: sigaltstack, sysconf")

	if text, err = cutCounted(text,
		`(?m)[ \t]*if \(sig != SIGPWR\)\n[ \t]*\{\n[ \t]*got_int = TRUE;\n[ \t]*\}\n`,
		"nosignals", "the SIGPWR test", 1); err != nil {
		return nil, err
	}
	text = bytes.Replace(text,
		[]byte("                             got_signal = sig;\n"),
		[]byte("                             got_signal = sig;\n"+
			"                             got_int = TRUE;\n"), 1)
	fmt.Fprintln(w, "  nosignals    the test for a signal that can no longer arrive")

	// `in_mch_delay && sigarg == SIGQUIT` and the early return for
	// HUP/QUIT/TERM/PWR/USR1/USR2 were written when all six could arrive here.
	// Two can.  Left alone they would be a lie in the one function whose
	// remaining job is to be trustworthy.
	if text, err = cutil.DropIf(text,
		`(?m)^[ \t]*if \(in_mch_delay && sigarg == SIGQUIT\)$`, 1); err != nil {
		return nil, err
	}
	early := regexp.MustCompile(
		`\(0 \|\| sigarg == SIGHUP \|\| sigarg == SIGQUIT \|\| sigarg == SIGTERM` +
			` \|\| sigarg == SIGPWR \|\| sigarg == SIGUSR1 \|\| sigarg == SIGUSR2\)`)
	var hit bool
	if text, hit = replaceFirst(early, text, "(sigarg == SIGHUP || sigarg == SIGTERM)"); !hit {
		return nil, fmt.Errorf("nosignals: deathtrap's early-return test is not where this expects")
	}
	fmt.Fprintln(w, "  nosignals    deathtrap stops testing for signals it cannot be sent")

	// SCOPED TO prepare_to_exit: `settmode(TMODE_COOK);` at this indent also
	// appears in buf_write(), and an unanchored substitution took that one --
	// the same mistake this pipeline has made twice before with `case 't':`
	// and `char_u *tagname;`.
	//
	// And it uses settmode() rather than mch_settmode(), because mch_settmode()
	// is defined 89,000 lines further down with no forward declaration left to
	// reach it -- Phase 8 removed the ones nothing needed.
	blanked := cutil.Blank(text)
	span, ok := dead.FuncDefinitions(text, blanked)["prepare_to_exit"]
	if !ok {
		return nil, fmt.Errorf("nosignals: prepare_to_exit is not defined at file scope")
	}
	body := text[span[0]:span[1]]
	old := []byte("        settmode(TMODE_COOK);\n")
	if !bytes.Contains(body, old) {
		return nil, fmt.Errorf("nosignals: prepare_to_exit's settmode is not where this expects")
	}
	body = bytes.Replace(body, old, []byte(cookTerminal), 1)
	var rebuilt []byte
	rebuilt = append(rebuilt, text[:span[0]]...)
	rebuilt = append(rebuilt, body...)
	text = append(rebuilt, text[span[1]:]...)
	fmt.Fprintln(w, "  nosignals    a killed editor puts the terminal back, which is what "+
		"SIGHUP and SIGTERM are kept for")

	seen := map[string]bool{}
	for _, m := range sigNames.FindAll(text, -1) {
		seen[string(m)] = true
	}
	left := make([]string, 0, len(seen))
	for s := range seen {
		left = append(left, s)
	}
	sort.Strings(left)
	fmt.Fprintf(w, "  nosignals    signals named in the file: %s\n", strings.Join(left, " "))
	return text, nil
}
