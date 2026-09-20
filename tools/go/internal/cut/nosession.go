package cut

import (
	"bytes"
	"fmt"
	"io"
	"regexp"

	"slimvim.local/tools/internal/cutil"
)

// The four tables are GENERATED from the Python module's own, imported rather
// than retyped: PARSER's third entry carries `\"` and `\n` inside C string
// literals, and transcribing those by hand is how a cut stops matching for a
// reason nobody can see in a diff.
var nosessionStubs = []struct{ name, body string }{
	{"apply_autocmds_group", "    return FALSE;\n"},
	{"has_autocmd", "    return FALSE;\n"},
	{"has_cursorhold", "    return FALSE;\n"},
	{"has_winresized", "    return FALSE;\n"},
	{"has_winscrolled", "    return FALSE;\n"},
	{"has_cursormoved", "    return FALSE;\n"},
	{"has_textchanged", "    return FALSE;\n"},
	{"has_insertcharpre", "    return FALSE;\n"},
	{"has_cmdundefined", "    return FALSE;\n"},
	{"has_tabclosedpre", "    return FALSE;\n"},
	{"trigger_cursorhold", "    return FALSE;\n"},
	{"trigger_undo_ftplugin", ""},
	{"trigger_cmd_autocmd", ""},
	{"trigger_winnewpre", ""},
	{"trigger_winclosed", ""},
	{"trigger_tabclosedpre", ""},
	{"may_trigger_win_scrolled_resized", ""},
	{"in_vim9script", "    return FALSE;\n"},
}

var nosessionDrops = []struct{ what, pat string }{
	{"the legacy modifier", "(?m)^[ \\t]*if \\(checkforcmd_noparen\\(&eap->cmd, \"legacy\", 3\\)\\)$"},
	{"the noautocmd modifier", "(?m)^[ \\t]*if \\(checkforcmd_noparen\\(&eap->cmd, \"noautocmd\", 3\\)\\)$"},
	{"the sandbox modifier", "(?m)^[ \\t]*if \\(checkforcmd_noparen\\(&eap->cmd, \"sandbox\", 3\\)\\)$"},
	{"the vim9cmd modifier", "(?m)^[ \\t]*if \\(checkforcmd_noparen\\(&eap->cmd, \"vim9cmd\", 4\\)\\)$"},
	{"noautocmd saving 'eventignore'", "(?m)^[ \\t]*if \\(\\(cmod->cmod_flags & CMOD_NOAUTOCMD\\) && cmod->cmod_save_ei == NULL\\)$"},
	{"noautocmd restoring 'eventignore'", "(?m)^[ \\t]*if \\(cmod->cmod_save_ei != NULL\\)$"},
}

var nosessionLiteral = []struct{ what, old, new string }{
	{"the window's 'eventignorewin' field", "    char_u      *wo_eiw;\n", ""},
	{"get_varp() handing out 'eventignorewin'", "        case   (idopt_T)(PV_WIN + (int)(WV_EIW))  :\n            return (char_u *)&(curwin-> w_onebuf_opt.wo_eiw );\n", ""},
	{"copy_winopt() copying 'eventignorewin'", "    to->wo_eiw = copy_option_val(from->wo_eiw);\n", ""},
	{"check_winopt() checking 'eventignorewin'", "    check_string_option(&wop->wo_eiw);\n", ""},
	{"clear_winopt() freeing 'eventignorewin'", "    clear_string_option(&wop->wo_eiw);\n", ""},
}

var nosessionParser = []struct{ what, old, new string }{
	{"-s outside Ex mode taking a keystroke file", "            case 's':\n                if (exmode_active)\n                {\n                    silent_mode = TRUE;\n                }\n                else\n                {\n                    want_argument = TRUE;\n                }\n                break;\n", "            case 's':\n                if (exmode_active)\n                {\n                    silent_mode = TRUE;\n                }\n                else\n                {\n                    mainerr(ME_UNKNOWN_OPTION, (char_u *)argv[0]);\n                }\n                break;\n"},
	{"-w taking a file to record keystrokes to", "                    set_option_value_give_err((char_u *)\"window\", n, NULL, 0);\n                    break;\n                }\n                want_argument = TRUE;\n                break;\n", "                    set_option_value_give_err((char_u *)\"window\", n, NULL, 0);\n                    break;\n                }\n                mainerr(ME_UNKNOWN_OPTION, (char_u *)argv[0]);\n                break;\n"},
	{"-w and -W opening the keystroke record", "                case 'w':\n                    if (vim_isdigit(*((char_u *)argv[0])))\n                    {\n                        argv_idx = 0;\n                        n = get_number_arg((char_u *)argv[0], &argv_idx, 10);\n                        set_option_value_give_err((char_u *)\"window\", n, NULL, 0);\n                        argv_idx = -1;\n                        break;\n                    }\n                __attribute__((fallthrough));\n                case 'W':\n                    if (scriptout != NULL)\n                    {\n                        goto scripterror;\n                    }\n                    if ((scriptout =  fopen((argv[0]), (c == 'w' ?  \"a\"  :  \"w\" )) ) == NULL)\n                    {\n                         fprintf(stderr, \"%s\", (_(\"Cannot open for script output: \\\"\"))) ;\n                         fprintf(stderr, \"%s\", (argv[0])) ;\n                         fprintf(stderr, \"%s\", (\"\\\"\\n\")) ;\n                        mch_exit(2);\n                    }\n                    break;\n", ""},
	{"-S being the one option allowed no argument", "argc < 1 && c != 'S'", "argc < 1"},
}

// nosessionBody replaces a definition's body, scoped to the definition's own
// span -- the first `{` inside it is the body opener.
func nosessionBody(text []byte, name, newBody string) ([]byte, error) {
	a, z, ok := cutil.FindDefinition(text, cutil.Blank(text), name)
	if !ok {
		return nil, fmt.Errorf("nosession: %s is not defined at file scope", name)
	}
	seg := text[a:z]
	b := cutil.Blank(seg)
	o := bytes.IndexByte(b, '{')
	c := cutil.Match(b, o)
	if o < 0 || c < 0 {
		return nil, fmt.Errorf("nosession: %s is unbalanced", name)
	}
	out := make([]byte, 0, len(text))
	out = append(out, text[:a]...)
	out = append(out, seg[:o]...)
	out = append(out, "{\n"...)
	out = append(out, newBody...)
	out = append(out, '}')
	out = append(out, seg[c+1:]...)
	return append(out, text[z:]...), nil
}

// NoSession removes sessions, autocommands and the Vim9 modifiers.
func NoSession(text []byte, w io.Writer) ([]byte, error) {
	var err error
	for _, s := range nosessionStubs {
		if text, err = nosessionBody(text, s.name, s.body); err != nil {
			return nil, err
		}
	}
	fmt.Fprintf(w, "  nosession    %d doors of the autocommand engine and Vim9 answer "+
		"without it\n", len(nosessionStubs))

	for _, d := range nosessionDrops {
		n := len(regexp.MustCompile(d.pat).FindAll(text, -1))
		if n != 1 {
			return nil, fmt.Errorf("nosession: %s -- matches %d times, not once", d.what, n)
		}
		if text, err = cutil.DropIf(text, d.pat, 1); err != nil {
			return nil, err
		}
		fmt.Fprintf(w, "  nosession    %s\n", d.what)
	}

	for _, l := range nosessionLiteral {
		n := bytes.Count(text, []byte(l.old))
		if n != 1 {
			return nil, fmt.Errorf("nosession: %s -- occurs %d times, not once", l.what, n)
		}
		text = bytes.ReplaceAll(text, []byte(l.old), []byte(l.new))
		fmt.Fprintf(w, "  nosession    %s\n", l.what)
	}

	// :write and :file to a new name re-run filetype detection when the
	// `filetypedetect` group exists -- a group only :augroup or :autocmd made.
	// The test is known now, and with it goes the last caller of do_doautocmd().
	if text, err = cutil.FoldNever(text,
		`(?m)^[ \t]*if \(au_has_group\(\(char_u \*\)"filetypedetect"\)\)$`, 2); err != nil {
		return nil, fmt.Errorf("nosession: filetype detection after a rename -- %v", err)
	}
	fmt.Fprintln(w, "  nosession    :write and :file no longer re-detect a filetype no "+
		"group can detect")

	a, z, ok := cutil.FindDefinition(text, cutil.Blank(text), "command_line_scan")
	if !ok {
		return nil, fmt.Errorf("nosession: command_line_scan is not defined at file scope")
	}
	fn := text[a:z]
	for _, p := range nosessionParser {
		n := bytes.Count(fn, []byte(p.old))
		if n != 1 {
			return nil, fmt.Errorf("nosession: %s -- occurs %d times in the parser, not once",
				p.what, n)
		}
		fn = bytes.ReplaceAll(fn, []byte(p.old), []byte(p.new))
		fmt.Fprintf(w, "  nosession    %s\n", p.what)
	}
	fn, held, err := DropShort(fn, 0, map[string]bool{"S": true, "W": true})
	if err != nil {
		return nil, err
	}
	if !setEqual(held, "S", "W") {
		return nil, fmt.Errorf("nosession: -S and -W are not both labels in the option "+
			"switch: %s", pyList(sortedKeys(held)))
	}
	fn, held2, err := DropShort(fn, 1, map[string]bool{"S": true, "s": true})
	if err != nil {
		return nil, err
	}
	if !setEqual(held2, "S", "s") {
		return nil, fmt.Errorf("nosession: -S and -s are not both in the argument "+
			"switch: %s", pyList(sortedKeys(held2)))
	}
	if fn, err = cutil.FoldNever(fn, `(?m)^[ \t]*if \(c == 'S'\)$`, 1); err != nil {
		return nil, fmt.Errorf("nosession: the session file becoming a :source -- %v", err)
	}
	fmt.Fprintln(w, "  nosession    -S, -s file, -w file and -W are unknown options")
	var rebuilt []byte
	rebuilt = append(rebuilt, text[:a]...)
	rebuilt = append(rebuilt, fn...)
	text = append(rebuilt, text[z:]...)

	for _, l := range []struct {
		what, pattern string
		want          int
	}{
		{"the four modifiers in the modifier parser",
			`checkforcmd_noparen\([^,]+, "(legacy|noautocmd|sandbox|vim9cmd)"`, 0},
		{"cmod_save_ei outside its declaration", `\bcmod_save_ei\b`, 1},
		{"scriptout opened by the parser", `\bscripterror\b`, 0},
		{"p_lpl outside its declaration and row", `\bp_lpl\b`, 2},
	} {
		n := len(regexp.MustCompile(l.pattern).FindAll(text, -1))
		if n != l.want {
			return nil, fmt.Errorf("nosession: %s -- %d left, expected %d",
				l.what, n, l.want)
		}
	}

	fmt.Fprintln(w, "  nosession    nothing parses a script modifier, suspends from a key, "+
		"or reads a script file")
	return text, nil
}
