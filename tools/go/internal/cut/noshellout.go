package cut

import (
	"fmt"
	"io"
	"regexp"

	"slimvim.local/tools/internal/cutil"
)

const notHere = "    emsg(_(e_sorry_command_is_not_available_in_this_version));"

var shelloutStubs = []struct{ name, body string }{
	{"do_filter", notHere},
	{"do_shell", notHere},
	{"get_cmd_output", "    return NULL;"},
}

var delTempDir = regexp.MustCompile(`(?m)^[ \t]*vim_deltempdir\(\);[ \t]*\n\n?`)

// NoShellOut takes away every way to hand work to a shell.
//
// The three implementations become one line each, and then the TEARDOWN goes:
// vim_deltempdir() outlives the only things that ever made a temp directory,
// and a call left behind would be the phase half-done.
func NoShellOut(text []byte, w io.Writer) ([]byte, error) {
	total := 0
	for _, s := range shelloutStubs {
		var was int
		var err error
		text, was, err = cutil.ReplaceBody(text, s.name, s.body)
		if err != nil {
			return nil, fmt.Errorf("noshellout: %v", err)
		}
		total += was
		fmt.Fprintf(w, "  noshellout   %-16s was %4d lines, is now one\n", s.name, was)
	}

	if !delTempDir.Match(text) {
		return nil, fmt.Errorf("noshellout: nothing calls vim_deltempdir any more, so this " +
			"phase has already run or the exit path has moved")
	}
	text = delTempDir.ReplaceAll(text, nil)

	fmt.Fprintf(w, "  noshellout   %d lines of implementation gone; the temp directory "+
		"has nothing left to make it\n", total)
	return text, nil
}
