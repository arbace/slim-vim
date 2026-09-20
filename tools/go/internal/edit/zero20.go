package edit

import (
	"fmt"
	"io"
	"regexp"
	"strconv"
	"strings"
)

func init() { register("zero20", Zero20) }

// z20Before is counted on the INPUT, so a later phase that moved one of these
// fails here and not in the middle of a cut.
var z20Before = []struct {
	name string
	want int
}{
	{"mch_signal", 18}, {"signal_info", 9}, {"settmode", 13},
	{"mch_settmode", 2}, {"isatty", 4}, {"deathtrap", 3},
	{"win_resize_enabled", 6}, {"got_tstp", 4}, {"do_resize", 6},
}

// Zero20 gives the signals and the terminal to the host: the five signal
// handlers, mch_settmode's three-valued mode, mch_delay's sleep,
// RealWaitForChar's select, mch_get_shellsize and all three isatty() calls move
// into a 229-line host block at the bottom of the same file.
func Zero20(text []byte, w io.Writer) ([]byte, error) {
	p := ph{"host", w}
	t := string(text)

	mentions := func(name string) int {
		return len(regexp.MustCompile(`\b`+name+`\b`).FindAllString(t, -1))
	}
	blankRuns := func(s string) int {
		L := strings.Split(s, "\n")
		n := 0
		for i := 1; i < len(L); i++ {
			if L[i] == "" && L[i-1] == "" {
				n++
			}
		}
		return n
	}
	sub := func(old, new string, n int, tag string) error {
		c := strings.Count(t, old)
		if c != n {
			return p.die("%s: `%s` occurs %d times, expected %d",
				tag, zHead(strings.Split(strings.TrimSpace(old), "\n")[0], 70), c, n)
		}
		t = strings.ReplaceAll(t, old, new)
		return nil
	}
	// delfunc deletes a whole definition by brace matching from its name line.
	delfunc := func(sigline, tag string) error {
		if c := strings.Count(t, sigline); c != 1 {
			return p.die("%s: the definition line `%s` occurs %d times, expected 1",
				tag, zHead(strings.TrimSpace(sigline), 60), c)
		}
		i := strings.Index(t, sigline)
		k := strings.Index(t[i:], "{") + i
		d := 0
		for {
			if t[k] == '{' {
				d++
			} else if t[k] == '}' {
				d--
				if d == 0 {
					break
				}
			}
			k++
		}
		a := strings.LastIndex(t[:i], "\n")
		st := strings.LastIndex(t[:a], "\n") + 1
		t = t[:st] + t[strings.Index(t[k:], "\n")+k+1:]
		return nil
	}

	linesBefore := len(strings.Split(t, "\n"))

	// ---- 0. this is the file the phase was written against -------------------
	for _, b := range z20Before {
		if k := mentions(b.name); k != b.want {
			return nil, p.die("the input has %d mentions of `%s`, expected %d -- this is not the tree "+
				"this phase was written against", k, b.name, b.want)
		}
	}
	if strings.Contains(t, `\033[?2048$p`) || strings.Contains(t, "2048$p") {
		return nil, p.die("the DECRQM query for mode 2048 is in the file, so the negotiation this phase " +
			"deletes as dead code is not dead")
	}
	// The report line for this section is the FIRST ROW OF THE TABLE and is not
	// written here: every say() the phase makes is lifted with its acts, and a
	// second copy printed by hand is a duplicated line the tree cannot see.
	// Measured -- it printed twice.

	// ---- the acts, in the order the phase performs them ----------------------
	// TWO ACTS ARE NOT IN THE TABLE, and missing the second one is what the
	// first run of this port did.  Both are index splices rather than sub()
	// calls -- one deletes from get_tty_fd()'s head to get_stty()'s, the other
	// REPLACES RealWaitForChar()'s whole definition with a three-line one -- so
	// neither has text to count and neither is a call the generator can lift.
	// Each is performed by the TAG of the act that follows it and never by a
	// line number, because a table keyed on line numbers is a dependency on
	// every line above it (CLAUDE.md, `apart 24 25`).
	//
	// The way the omission showed was one mention short at the very end:
	// `musl_wait_for_input has 2 mentions, expected 3 -- its prototype, its
	// definition and RealWaitForChar()'s one call`.  The prototype and the
	// definition had landed; the call had not, because the function that makes
	// it had never been rewritten.
	for _, op := range z20Ops {
		if len(op.args) > 0 {
			switch op.args[len(op.args)-1] {
			case "K2":
				i := strings.Index(t, "    static int\nget_tty_fd(int fd)")
				j := strings.Index(t, "    static void\nget_stty(void)")
				if i < 0 || j < 0 || i >= j {
					return nil, p.die("K1: get_tty_fd() and get_stty() are not the adjacent pair this phase " +
						"cuts between")
				}
				t = t[:i] + t[j:]
			case "T1":
				i := strings.Index(t, "RealWaitForChar(int fd, long msec, int *check_for_gpm")
				j := strings.Index(t, "    static int\nno_Magic(int x)")
				if i < 0 || j < 0 || i >= j {
					return nil, p.die("K5: RealWaitForChar() and no_Magic() are not the adjacent pair " +
						"this phase replaces between")
				}
				t = t[:i] + z20RealWait + t[j:]
			}
		}
		switch op.kind {
		case "say":
			// The LAST say is computed by the phase and carries no literal, so
			// it is written after the loop with the line counts it reports.
			if op.args != nil {
				p.say(op.args[0])
			}
		case "cut", "sub":
			// cut(old, n, tag) is sub(old, "", n, tag); the defaults are n=1 and
			// an empty tag, and the table carries only the arguments the phase
			// actually passed.
			a := op.args
			if a == nil {
				// The computed splice: the host block goes INSIDE the launcher
				// region phase 18 created and phase 19 filled, immediately above
				// `host_jump`, because that region is what becomes the second
				// file at the split.
				old := "\nstatic void *host_jump[5];\nstatic int host_code;\n"
				if err := sub(old, "\n"+z20Host+"static void *host_jump[5];\nstatic int host_code;\n",
					1, "H3"); err != nil {
					return nil, err
				}
				continue
			}
			old, new, rest := a[0], "", a[1:]
			if op.kind == "sub" {
				new, rest = a[1], a[2:]
			}
			n, tag := 1, ""
			if len(rest) > 0 {
				n, _ = strconv.Atoi(rest[0])
			}
			if len(rest) > 1 {
				tag = rest[1]
			}
			if err := sub(old, new, n, tag); err != nil {
				return nil, err
			}
		case "delfunc":
			tag := ""
			if len(op.args) > 1 {
				tag = op.args[1]
			}
			if err := delfunc(op.args[0], tag); err != nil {
				return nil, err
			}
		}
	}

	// ---- what the file is now ------------------------------------------------
	var left []string
	for _, n := range z20Gone {
		if mentions(n) > 0 {
			left = append(left, n)
		}
	}
	if len(left) > 0 {
		return nil, p.die("these names should be at 0 mentions and are not: %s", strings.Join(left, " "))
	}
	for _, r := range z20Want {
		if k := mentions(r.name); k != r.want {
			return nil, p.die("`%s` has %d mentions, expected %d -- %s", r.name, k, r.want, r.why)
		}
	}
	n := 0
	for _, l := range strings.Split(t, "\n") {
		if strings.HasPrefix(l, "#") {
			n++
		}
	}
	if n != 12 {
		return nil, p.die("the twelve #include directives moved, and this phase adds and removes none")
	}
	if blankRuns(t) == 0 {
		return nil, p.die("the edit left no run of two blank lines at all, which means the deletions did " +
			"not happen where they were expected -- the sweep's canon.sh is what takes " +
			"them out, and the check asserts 0 AFTER the sweep")
	}
	p.say(fmt.Sprintf("%d -> %d lines.  The core installs no handler, sets no terminal mode, runs no "+
		"select and asks the kernel nothing about a window; the host block is %d lines at "+
		"the bottom, inside the launcher region",
		linesBefore, len(strings.Split(t, "\n")), strings.Count(z20Host, "\n")))
	return []byte(t), nil
}
