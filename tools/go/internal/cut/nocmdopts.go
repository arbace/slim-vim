package cut

import (
	"fmt"
	"io"
	"regexp"

	"slimvim.local/tools/internal/cutil"
	"slimvim.local/tools/internal/dead"
)

// nocmdoptsInParser is SCOPED TO THE PARSER.
//
// `case 't':` occurs in get_c_indent() as well, three thousand lines away and
// about 'cinoptions', and a substitution with count=1 takes whichever comes
// first in the FILE.  It did: the first attempt cut a branch out of the C
// indenter and gcc reported a duplicate case value in a function this phase
// never meant to touch.  Everything that edits the option parser is applied to
// command_line_scan()'s body alone.
var nocmdoptsInParser = []struct{ what, pat, repl string }{
	{"-t, which ran a :tag that is not implemented",
		`(?m)[ \t]*case 't':\n(?:[^\n]*\n)*?[ \t]*break;\n\n`, ""},
	{"-t's argument",
		`(?m)[ \t]*case 't':\n[ \t]*parmp->tagname = \(char_u \*\)argv\[0\];\n[ \t]*break;\n\n`, ""},
	{"-i's argument, which set an option wired to NULL",
		`(?m)[ \t]*case 'i':\n` +
			`[ \t]*set_option_value_give_err\(\(char_u \*\)"vif", 0L, \(char_u \*\)argv\[0\], 0\);\n` +
			`[ \t]*break;\n\n`, ""},
	// Phase 3 already took `case 'd':` out of this group, with -d itself.
	{"-i from the list of options that take one",
		`(?m)([ \t]*case 'S':\n)[ \t]*case 'i':\n`, "${1}"},
}

// nocmdoptsElsewhere are the fields the four options set, their now-unreachable
// readers, and restricted mode.
//
// A struct field is not a variable, so no warning reports it and the sweep
// cannot see it -- the same shape Phase 17 met with b_start_fenc.  SCOPED BY
// THEIR NEIGHBOUR: `char_u *tagname;` is also a field of taggy_T, seventeen
// hundred lines earlier, and an unanchored pattern takes the first -- which
// removed the tag stack's field and broke five lines in two functions this
// phase never meant to touch.  `int edit_type;` sits immediately above
// mparm_T's and nowhere else.
var nocmdoptsElsewhere = []struct {
	what, pat, repl string
	want            int
}{
	{"mparm_T's evim_mode field", `(?m)^[ \t]*int[ \t]*evim_mode;\n`, "", 1},
	{"the startup tag jump, which nothing can now ask for",
		`(?m)[ \t]*if \(params\.tagname != NULL\)\n[ \t]*\{\n(?:[^\n]*\n)*?` +
			`[ \t]*do_cmdline_cmd\(IObuff\);\n(?:[^\n]*\n)*?^[ \t]{4}\}\n\n?`, "", 1},
	{"exe_pre_commands testing for one",
		`(?m)[ \t]*if \(parmp->tagname == NULL && curwin->w_cursor\.lnum <= 1\)\n` +
			`([ \t]*\{\n[ \t]*curwin->w_cursor\.lnum = 0;\n[ \t]*\}\n)`,
		"    if (curwin->w_cursor.lnum <= 1)\n${1}", 1},
	{"mparm_T's tagname field",
		`(?m)(^[ \t]*int[ \t]*edit_type;\n)[ \t]*char_u[ \t]*\*tagname;\n`, "${1}", 1},
	// And the flag itself, out of the twenty-four rows that carry it.  With
	// the gate gone it is a bit nothing reads; leaving it is leaving a concept
	// in the table that the code no longer has.
	{"EX_RESTRICT out of the command table", `(?m)\|EX_RESTRICT\)`, ")", 24},
	// The other way in, and a small find of its own: set_init_restricted_mode()
	// reads $SHELL at startup and turns the mode on when it is nologin or
	// false.  An environment read, deciding a mode that now restricts nothing.
	{"$SHELL deciding restricted mode at startup",
		`(?m)^[ \t]*set_init_restricted_mode\(\);\n`, "", 1},
	{"restricted mode in do_bang and ex_stop",
		`(?m)check_restricted\(\) \|\| check_secure\(\)`, "check_secure()", 1},
	{"ex_stop's restricted check",
		`(?m)[ \t]*if \(check_restricted\(\)\)\n[ \t]*\{\n[ \t]*return;\n[ \t]*\}\n\n?`, "", 1},
	{"the EX_RESTRICT gate, which no live command reaches",
		`(?m)[ \t]*if \(restricted != 0 && \(ea\.argt & EX_RESTRICT\)\)\n` +
			`[ \t]*\{\n(?:[^\n]*\n)*?[ \t]*\}\n`, "", 1},
	{"restricted deciding whether SIGTSTP is ignored",
		`(?m)ignore_sigtstp = restricted \|\| SIG_IGN`, "ignore_sigtstp = SIG_IGN", 1},
}

// NoCmdOpts removes -t, -i, -y and -Z, the fields they set, and restricted
// mode.
func NoCmdOpts(text []byte, w io.Writer) ([]byte, error) {
	blanked := cutil.Blank(text)
	defs := dead.FuncDefinitions(text, blanked)
	span, ok := defs["command_line_scan"]
	if !ok {
		return nil, fmt.Errorf("nocmdopts: command_line_scan is not defined at file scope")
	}
	body := text[span[0]:span[1]]
	for _, e := range nocmdoptsInParser {
		var hit bool
		body, hit = replaceFirst(regexp.MustCompile(e.pat), body, e.repl)
		if !hit {
			return nil, fmt.Errorf("nocmdopts: %s -- not found in the option parser", e.what)
		}
		fmt.Fprintf(w, "  nocmdopts    %s\n", e.what)
	}
	var buf []byte
	buf = append(buf, text[:span[0]]...)
	buf = append(buf, body...)
	text = append(buf, text[span[1]:]...)

	for _, e := range nocmdoptsElsewhere {
		re := regexp.MustCompile(e.pat)
		n := len(re.FindAll(text, -1))
		if e.want > 1 {
			if n != e.want {
				return nil, fmt.Errorf("nocmdopts: %s -- expected %d, matched %d",
					e.what, e.want, n)
			}
			text = re.ReplaceAll(text, []byte(e.repl))
		} else {
			if n < 1 {
				return nil, fmt.Errorf("nocmdopts: %s -- expected 1, matched 0", e.what)
			}
			text, _ = replaceFirst(re, text, e.repl)
		}
		fmt.Fprintf(w, "  nocmdopts    %s\n", e.what)
	}
	return text, nil
}
