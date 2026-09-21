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

func init() { register("whim54", Whim54) }

// w54Row is the option row with no variable: a name, an abbreviation or NULL, a
// run of P_ flags, and `(char_u *)NULL` where the variable belongs.
//
// IT MUST BE MULTILINE AND THAT IS THE WHOLE REASON THIS WAS EVER PYTHON.  A
// row's flags and its variable are on two lines, so a line-oriented `grep -c`
// counts 0 whatever the file holds -- a check that cannot fail.  `(?m)` is for
// the `^` alone; the `\s*` between the fields is what crosses the break.
var w54Row = regexp.MustCompile(`(?m)^[ \t]*\{"\w+",\s*(?:"\w*"|NULL),\s*P_[\w|\s]+,\s*\(char_u ?\*\)NULL,`)

// w54Unknown are four options whose variables this phase removed, so `:set x?`
// must now be refused.  They are named rather than computed because the point
// is that THESE four went, and a computed set would pass against a build that
// had removed different ones.
var w54Unknown = []string{"foldmethod", "cursorline", "undofile", "clipboard"}

// Whim54 is phase 54's check: no option without a variable.
//
// It does NOT collect.  The shell it replaces exits at its first refusal, so
// phasecheck and the build never run once the count is wrong, and a Go that
// collected would print a report the phase never produced -- and would run a
// build that the shell had already declined to reach.
func Whim54(w io.Writer, args []string) error {
	if len(args) < 2 {
		return fmt.Errorf("usage: check whim54 <work-dir> <state-dir>")
	}
	work, state := args[0], args[1]
	r := &rep{tag: "novar", w: w}
	f := filepath.Join(work, "whim-vim.c")

	beforeLines, err := os.ReadFile(filepath.Join(state, "input-lines"))
	if err != nil {
		return err
	}
	src, err := os.ReadFile(f)
	if err != nil {
		return err
	}
	if n := len(w54Row.FindAll(src, -1)); n != 0 {
		r.say("%d rows without a variable remain", n)
		return harness.ErrReported
	}
	r.say("every option row has a variable")

	if err := run(w, "sh", "tools/phasecheck.sh", work, f, filepath.Join(state, "symbols")); err != nil {
		return harness.ErrReported
	}
	if err := run(w, "sh", "tools/phasebuild.sh", work, strings.TrimSpace(string(beforeLines))); err != nil {
		return harness.ErrReported
	}

	// The binary is staged as `vim` because argv[0] decides what a vim does --
	// a name beginning with `r` is restricted mode and every shell-out fails.
	// $HOME is the scratch so no real ~/.vimrc is found.
	d, err := os.MkdirTemp("", "whim54")
	if err != nil {
		return err
	}
	defer os.RemoveAll(d)
	bin, err := os.ReadFile(filepath.Join(work, "whim-vim"))
	if err != nil {
		return err
	}
	vim := filepath.Join(d, "vim")
	if err := os.WriteFile(vim, bin, 0o755); err != nil {
		return err
	}
	set := func(opt string) error {
		c := exec.Command("./vim", "-e", "-s", "+set "+opt, "+q!")
		c.Dir = d
		c.Env = append(os.Environ(), "HOME="+d)
		c.Stdin, c.Stdout, c.Stderr = nil, nil, nil
		return c.Run()
	}
	if set("sw=3") != nil {
		r.say("the control :set sw=3 failed")
		return harness.ErrReported
	}
	for _, o := range w54Unknown {
		if set(o+"?") == nil {
			r.say(":set %s? was accepted", o)
			return harness.ErrReported
		}
	}
	r.say(":set sw works; :set %s and %s are unknown",
		strings.Join(w54Unknown[:3], ", "), w54Unknown[3])
	return nil
}

// run is a shell tool the check shells out to, with its output going to the
// report exactly where the shell put it.  Its own refusal message is its
// output, so nothing is added here.
func run(w io.Writer, name string, arg ...string) error {
	c := exec.Command(name, arg...)
	c.Stdout, c.Stderr = w, w
	return c.Run()
}
