package check

import (
	"fmt"
	"io"
	"path/filepath"
	"regexp"
	"strings"

	"slimvim.local/tools/internal/cutil"
	"slimvim.local/tools/internal/harness"
)

func init() { register("whim33", Whim33) }

// Whim33 is phase 33's check: commands whose machinery has already gone.
func Whim33(w io.Writer, args []string) error {
	if len(args) < 2 {
		return fmt.Errorf("usage: check whim33 <work-dir> <state-dir>")
	}
	work, state := args[0], args[1]
	r := &rep{tag: "deadcmds", w: w}
	f := filepath.Join(work, "whim-vim.c")
	beforeLines := strings.TrimSpace(readFile(filepath.Join(state, "input-lines")))
	src := []byte(readFile(f))
	for _, g := range []string{"ex_shell", "ex_nogui", "ex_digraphs", "ex_redrawtabpanel", "ex_colorscheme", "load_colors"} {
		if n := countWord(src, g); n != 0 {
			r.say("%s still has %d mentions after the sweep", g, n)
			re := regexp.MustCompile(`\b` + g + `\b`)
			k := 0
			for i, l := range strings.Split(string(src), "\n") {
				if re.MatchString(l) {
					line := fmt.Sprintf("               %d:%s", i+1, l)
					if len(line) > 100 {
						line = line[:100]
					}
					fmt.Fprintln(w, line)
					if k++; k == 3 {
						break
					}
				}
			}
			return harness.ErrReported
		}
	}
	// tools/cutil.py's find_definition, as the Go package the sweep runs.  A
	// definition that is not there is a pass, as it was in the heredoc, whose
	// unpacking of None raised and exited 1 -- which the shell read as "no
	// quickfix command found".
	if a, z, ok := cutil.FindDefinition(src, cutil.Blank(src), "ex_listdo"); ok &&
		regexp.MustCompile(`\bCMD_(cdo|cfdo|ldo|lfdo)\b`).Match(src[a:z]) {
		r.say("ex_listdo still tests for a quickfix command")
		return harness.ErrReported
	}
	r.say("no handler that only refused is left, and ex_listdo asks nothing about quickfix")
	if err := run(w, "sh", "tools/phasecheck.sh", work, f, filepath.Join(state, "symbols")); err != nil {
		return harness.ErrReported
	}
	if err := run(w, "sh", "tools/phasebuild.sh", work, beforeLines); err != nil {
		return harness.ErrReported
	}
	return nil
}
