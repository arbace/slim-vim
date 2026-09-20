package edit

import (
	"io"
	"regexp"
)

func init() { register("zero2", Zero2) }

// Zero2 stops the core diagnosing its own terminal.
//
// An embeddable core is handed its input and output by a host.  Whether either
// is a terminal is the host's business, and vim's answer to it is to print two
// warnings on stderr and then stop for two seconds so a user can read them.
//
// WHAT GOES: check_tty()'s second branch entirely -- both warnings, the
// out_flush() that pushes them, the exit(1) that --ttyfail asked for, and the
// ui_delay(2005L) under `scriptin[0] == NULL` that exists only so the warnings
// can be read -- and with it the --ttyfail flag itself.
//
// WHAT STAYS, each with the reader that forces it: the exmode_active branch,
// because Ex mode goes in a later phase and not this one; stdout_isatty, read
// outside main by `out_redir = !stdout_isatty`; and want_full_screen, whose
// second reader survives the branch that went.  So all five isatty() calls
// remain and the undefined symbol count does not move.  This phase is the
// warnings, the pause and the flag -- not every isatty caller.
func Zero2(text []byte, w io.Writer) ([]byte, error) {
	p := ph{"nottywarn", w}
	var err error

	// ---- 0. the invariants the cut rests on ------------------------------
	// Asserted rather than trusted from the survey: if an upstream gives
	// tty_fail a second reader, or moves the pause out of the branch, this
	// fails loudly instead of taking a decision that is no longer the one
	// written down.
	for _, inv := range []struct {
		name string
		want int
	}{{"tty_fail", 3}, {"ui_delay(2005L", 1}} {
		if err = p.count(text, regexp.QuoteMeta(inv.name), inv.want, inv.name); err != nil {
			return nil, err
		}
	}
	if err = p.count(text, `\bisatty\(`, 5, "isatty"); err != nil {
		return nil, err
	}
	p.say("tty_fail has its field, its one write and its one read; the 2005 ms pause is the only one")

	// ---- 1. the warnings, the pause and the exit -------------------------
	// One `else if` in a chain, so foldNever takes the whole branch and
	// leaves the exmode_active one before it.
	text, err = p.foldNever(text, "check_tty",
		`^[ \t]*else if \(parmp->want_full_screen && \(!stdout_isatty \|\| !input_isatty\)\)$`,
		"both warnings, the flush, the --ttyfail exit and the two-second pause", 1)
	if err != nil {
		return nil, err
	}

	// ---- 2. the flag that asked for the exit -----------------------------
	// The test can no longer be true -- there is no --ttyfail -- so foldNever
	// keeps what it chose between: the else branch, where an unrecognised
	// word after `--` is ME_UNKNOWN_OPTION and a bare `--` sets had_minmin.
	text, err = p.foldNever(text, "command_line_scan",
		`^[ \t]*if \( strncasecmp\(\(char \*\)\(argv\[0\] \+ argv_idx\), \(char \*\)\("ttyfail"\), \(7\)\)  == 0\)$`,
		"--ttyfail, which is now an unknown option like any other", 1)
	if err != nil {
		return nil, err
	}
	text, err = p.literal(text, "    int         tty_fail;\n", "", "the mparm_T field it set", 1)
	if err != nil {
		return nil, err
	}

	// ---- 3. the argument check_tty no longer reads -----------------------
	// The alternative is __attribute__((unused)) on a parameter nothing will
	// ever read again, which is how slim MARKS an unused parameter and how
	// whim 67 got rid of one.
	text, err = p.literal(text, "check_tty(mparm_T *parmp)\n", "check_tty(void)\n",
		"check_tty takes nothing: its only use of parmp went with the branch", 1)
	if err != nil {
		return nil, err
	}
	text, err = p.literal(text, "    check_tty(&params);\n", "    check_tty();\n",
		"and its one caller", 1)
	if err != nil {
		return nil, err
	}

	if err = p.gone(text, "tty_fail", "ttyfail", "not to a terminal",
		"not from a terminal", "ui_delay(2005L"); err != nil {
		return nil, err
	}
	return text, nil
}
