package edit

import (
	"fmt"
	"io"
	"regexp"
	"strings"
)

var (
	bufnameRows = regexp.MustCompile(`\[CMD_[a-zA-Z]+\] = \{\(char_u \*\)"([a-zA-Z]+)", [^,]+, *([a-z_]+)[^}]*EX_BUFNAME`)
	niComputed  = regexp.MustCompile(`(?m)^[ \t]*ni = \(! \(\(int\)\(ea\.cmdidx\) < 0\)  && \(cmdnames\[ea\.cmdidx\]\.cmd_func == ex_ni`)
)

// Whim77 stops a command naming a buffer by pattern, having first proved that
// every command that could is already ex_ni.
func Whim77(text []byte, w io.Writer) ([]byte, error) {
	e := New("nobufpat", text, w)

	rows := bufnameRows.FindAllSubmatch(text, -1)
	if len(rows) == 0 {
		e.Refuse("no command carries EX_BUFNAME -- the block this phase removes is already gone")
		return e.Done()
	}
	var live []string
	for _, r := range rows {
		fn := string(r[2])
		if fn != "ex_ni" && fn != "ex_script_ni" {
			live = append(live, string(r[1]))
		}
	}
	if len(live) > 0 {
		e.Refuse("these EX_BUFNAME commands have a LIVE handler and still need the pattern matching: %s",
			strings.Join(live, " "))
		return e.Done()
	}
	e.say(fmt.Sprintf("confirmed: all %d EX_BUFNAME commands are ex_ni", len(rows)))

	if !niComputed.Match(text) {
		e.Refuse("`ni` is no longer computed as \"the handler is ex_ni\"")
		return e.Done()
	}
	e.FoldNeverIn2("do_one_cmd",
		`(?m)^[ \t]*if \(\(ea\.argt & EX_BUFNAME\) && \*ea\.arg != NUL && ea\.addr_count == 0 && ! \(\(int\)\(ea\.cmdidx\) < 0\) \)$`,
		"naming a buffer by pattern for commands that cannot run", 1)
	return e.Done()
}

func init() { register("whim77", Whim77) }
