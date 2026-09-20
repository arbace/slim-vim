package cut

import (
	"bytes"
	"fmt"
	"io"
	"regexp"
	"strings"

	"slimvim.local/tools/internal/cutil"
)

// keepThen is an `if (T) { A } else { B }` whose condition is always true:
// keep A, lose B.
//
// FoldAlways refuses a block with an else, rightly -- it cannot tell whether
// the else is meant.  Here it is meant, so this does the one shape by the same
// brace matching FoldNever uses.
func (e ed) keepThen(seg []byte, pattern, what string) ([]byte, error) {
	re := regexp.MustCompile("(?m)" + pattern)
	ms := re.FindAllIndex(seg, -1)
	if len(ms) != 1 {
		return nil, fmt.Errorf("%s: %s -- the condition occurs %d times, expected 1",
			e.tool, what, len(ms))
	}
	b := cutil.Blank(seg)
	k, o, c, head, err := cutil.Guarded(seg, b, ms[0])
	if err != nil {
		return nil, fmt.Errorf("%s: %s -- %v", e.tool, what, err)
	}
	if head != "if" {
		return nil, fmt.Errorf("%s: %s -- not a plain if", e.tool, what)
	}
	end := c + bytes.IndexByte(seg[c:], '\n') + 1
	rest := seg[end:]
	nxt := regexp.MustCompile(`^[ \t]*else\b`).FindIndex(rest)
	if nxt == nil || regexp.MustCompile(`^[ \t]*else[ \t]+if\b`).Match(rest) {
		return nil, fmt.Errorf("%s: %s -- expected a plain else after the block", e.tool, what)
	}
	at := end + nxt[1]
	o2 := at + bytes.IndexByte(b[at:], '{')
	c2 := cutil.Match(b, o2)
	if c2 < 0 {
		return nil, fmt.Errorf("%s: %s -- the else block is unbalanced", e.tool, what)
	}
	body := cutil.Dedent4(seg[o+bytes.IndexByte(seg[o:], '\n')+1 : bytes.LastIndexByte(seg[:c], '\n')+1])
	e.say(what)
	out := make([]byte, 0, len(seg))
	out = append(out, seg[:k]...)
	out = append(out, body...)
	return append(out, seg[c2+bytes.IndexByte(seg[c2:], '\n')+1:]...), nil
}

// lfonlyDying are the format functions and the option callbacks whose rows
// whim50 drops.  Every call left must sit inside one of them.
var lfonlyDying = []string{
	"get_fileformat", "get_fileformat_force", "set_fileformat", "default_fileformat",
	"file_ff_differs", "save_file_ff", "set_file_options", "set_options_bin",
	"msg_add_fileformat", "check_ff_value", "did_set_binary", "did_set_fileformat",
	"did_set_fileformats", "did_set_textmode", "did_set_textauto",
	"did_set_eof_eol_fixeol_bomb",
}

var lfonlyHeads = regexp.MustCompile(`(?m)^(\w+)\([^;\n]*\)[ \t]*\n\{`)

// LfOnly makes every line end with LF, read and written.
func LfOnly(text []byte, w io.Writer) ([]byte, error) {
	e := ed{"lfonly", w}
	var err error

	text, err = e.inFunction(text, "readfile", func(s []byte) ([]byte, error) {
		var err error
		if s, err = e.literal(s, "    set_file_options(set_options, eap);\n", "",
			"readfile setting the format from ++ff and ++bin", 1); err != nil {
			return nil, err
		}
		// The two guarded calls first: the bare-call pattern matches their
		// lines too.
		if s, err = e.subCount(s,
			`^[ \t]*if \(set_options\)\n[ \t]*\{\n[ \t]*save_file_ff\(curbuf\);\n[ \t]*\}\n`,
			"readfile saving the format it read", 2); err != nil {
			return nil, err
		}
		if s, err = e.subOnce(s, `^[ \t]*save_file_ff\(curbuf\);\n`,
			"readfile saving the format of a new file"); err != nil {
			return nil, err
		}
		if s, err = e.subOnce(s,
			`^[ \t]*if \(set_options\)\n[ \t]*\{\n[ \t]*if \(!read_buffer\)\n[ \t]*\{\n`+
				`[ \t]*curbuf->b_p_eof = FALSE;\n[ \t]*curbuf->b_start_eof = FALSE;\n`+
				`[ \t]*curbuf->b_p_eol = TRUE;\n[ \t]*curbuf->b_start_eol = TRUE;\n[ \t]*\}\n[ \t]*\}\n\n`,
			"readfile resetting 'endofline' and 'endoffile'"); err != nil {
			return nil, err
		}
		if s, err = e.subCount(s,
			`^[ \t]*try_(?:mac|dos|unix) = \(vim_strchr\(p_ffs, '[mdx]'\) != NULL\);\n`,
			"readfile reading 'fileformats'", 6); err != nil {
			return nil, err
		}
		// The format chain first: its 'binary' link is an
		// `else if (curbuf->b_p_bin)` too, until the ++ff link before it folds
		// and makes it an `if`.
		for _, f := range []struct{ pat, what string }{
			{`^[ \t]*if \(eap != NULL && eap->force_ff != 0\)$`, "readfile honouring ++ff"},
			{`^[ \t]*if \(curbuf->b_p_bin\)$`, "readfile honouring 'binary'"},
			{`^[ \t]*else if \(curbuf->b_p_bin\)$`, "readfile reading 'binary' as no encoding"},
		} {
			if s, err = e.foldNever(s, f.pat, f.what); err != nil {
				return nil, err
			}
		}
		if s, err = e.subOnce(s,
			`^[ \t]*if \(\*p_ffs == NUL\)\n[ \t]*\{\n[ \t]*fileformat = get_fileformat\(curbuf\);\n[ \t]*\}\n`+
				`[ \t]*else\n[ \t]*\{\n[ \t]*fileformat =  \(-1\) ;\n[ \t]*\}\n`,
			"readfile choosing between 'fileformat' and detection"); err != nil {
			return nil, err
		}
		if s, err = e.foldNever(s, `^[ \t]*if \(!curbuf->b_p_eol\)$`,
			"readfile dropping a filter's last LF"); err != nil {
			return nil, err
		}
		for _, l := range []struct{ old, new, what string }{
			{"if (size < 2 || curbuf->b_p_bin)", "if (size < 2)",
				"readfile's BOM check under 'binary'"},
			{"else if (enc_utf8 && !curbuf->b_p_bin)", "else if (enc_utf8)",
				"readfile's UTF-8 check under 'binary'"},
		} {
			if s, err = e.literal(s, l.old, l.new, l.what, 1); err != nil {
				return nil, err
			}
		}
		// The detection block tests fileformat == -1 again INSIDE itself, so
		// the outer test is the one followed by the try_dos || try_unix test.
		// The Python spells that as a LOOKAHEAD; RE2 has none, and inlining it
		// is exact here because Guarded uses only the match's START.
		if s, err = e.foldNever(s,
			`^[ \t]*if \(fileformat ==  \(-1\) \)\n[ \t]*\{\n[ \t]*if \(try_dos \|\| try_unix\)$`,
			"readfile detecting DOS and Mac line ends"); err != nil {
			return nil, err
		}
		for _, f := range []struct{ pat, what string }{
			{`^[ \t]*if \(linerest != 0 && !curbuf->b_p_bin && fileformat == EOL_DOS && ptr\[-1\] == Ctrl_Z\)$`,
				"readfile's CTRL-Z at the end of a DOS file"},
			{`^[ \t]*if \(fileformat == EOL_MAC\)$`, "readfile splitting lines at CR"},
			{`^[ \t]*if \(fileformat == EOL_DOS\)$`, "readfile stripping CR, and retrying as Unix"},
		} {
			if s, err = e.foldNever(s, f.pat, f.what); err != nil {
				return nil, err
			}
		}
		if s, err = e.subOnce(s,
			`^[ \t]*if \(set_options\)\n[ \t]*\{\n[ \t]*curbuf->b_p_eol = FALSE;\n[ \t]*\}\n`,
			"readfile clearing 'endofline' for a missing last LF"); err != nil {
			return nil, err
		}
		if s, err = e.foldNever(s, `^[ \t]*if \(ff_error == EOL_DOS\)$`,
			`the "[CR missing]" message`); err != nil {
			return nil, err
		}
		if s, err = e.dropIf(s, `^[ \t]*if \(msg_add_fileformat\(fileformat\)\)$`,
			`the "[dos]" and "[mac]" read messages`); err != nil {
			return nil, err
		}
		if s, err = e.literal(s, "    curbuf->b_no_eol_lnum = read_no_eol_lnum;\n", "",
			"readfile remembering the no-LF line for 'binary'", 1); err != nil {
			return nil, err
		}
		return e.foldNever(s, `^[ \t]*if \(keep_fileformat\)$`,
			"readfile keeping a format across a retry")
	})
	if err != nil {
		return nil, err
	}

	text, err = e.inFunction(text, "buf_write", func(s []byte) ([]byte, error) {
		var err error
		if s, err = e.subOnce(s,
			`^[ \t]*if \(eap != NULL && eap->force_bin != 0\)\n[ \t]*\{\n`+
				`[ \t]*write_bin = \(eap->force_bin == FORCE_BIN\);\n`+
				`[ \t]*\}\n[ \t]*else\n[ \t]*\{\n[ \t]*write_bin = buf->b_p_bin;\n[ \t]*\}\n\n`,
			"buf_write choosing 'binary' or ++bin"); err != nil {
			return nil, err
		}
		if s, err = e.subOnce(s, `^[ \t]*int[ \t]+write_bin;\n`,
			"buf_write declaring write_bin"); err != nil {
			return nil, err
		}
		if s, err = e.literal(s, "        fileformat = get_fileformat_force(buf, eap);\n", "",
			"buf_write choosing a format", 1); err != nil {
			return nil, err
		}
		if s, err = e.subOnce(s, `^[ \t]*int[ \t]+fileformat;\n`,
			"buf_write declaring the format"); err != nil {
			return nil, err
		}
		if s, err = e.foldNever(s, `^[ \t]*else if \(c == CAR && fileformat == EOL_MAC\)$`,
			"buf_write writing CR as a line end"); err != nil {
			return nil, err
		}
		if s, err = e.literal(s,
			"if (end == 0 || (lnum == end && (write_bin || !buf->b_p_fixeol) && ((write_bin && lnum == buf->b_no_eol_lnum) || (lnum == buf->b_ml.ml_line_count && !buf->b_p_eol))))",
			"if (end == 0)", "buf_write leaving the last LF off", 1); err != nil {
			return nil, err
		}
		if s, err = e.keepThen(s, `^[ \t]*if \(fileformat == EOL_UNIX\)$`,
			"buf_write writing CR LF or CR"); err != nil {
			return nil, err
		}
		if s, err = e.foldNever(s, `^[ \t]*if \(!buf->b_p_fixeol && buf->b_p_eof\)$`,
			"buf_write appending CTRL-Z"); err != nil {
			return nil, err
		}
		return e.dropIf(s, `^[ \t]*if \(msg_add_fileformat\(fileformat\)\)$`,
			`the "[dos]" and "[mac]" write messages`)
	})
	if err != nil {
		return nil, err
	}

	text, err = e.inFunction(text, "open_buffer", func(s []byte) ([]byte, error) {
		var err error
		if s, err = e.subCount(s, `^[ \t]*int[ \t]+save_bin = curbuf->b_p_bin;\n\n?`,
			"open_buffer saving 'binary'", 2); err != nil {
			return nil, err
		}
		if s, err = e.subOnce(s,
			`^[ \t]*if \(read_fifo\)\n[ \t]*\{\n[ \t]*curbuf->b_p_bin = TRUE;\n[ \t]*\}\n`,
			"a fifo read as binary"); err != nil {
			return nil, err
		}
		if s, err = e.subCount(s, `^[ \t]*curbuf->b_p_bin = save_bin;\n`,
			"open_buffer restoring 'binary'", 2); err != nil {
			return nil, err
		}
		if s, err = e.subOnce(s, `^[ \t]*curbuf->b_p_bin = TRUE;\n`,
			"stdin read as binary"); err != nil {
			return nil, err
		}
		return e.literal(s, "    save_file_ff(curbuf);\n", "",
			"open_buffer saving the format", 1)
	})
	if err != nil {
		return nil, err
	}

	if text, err = e.inFunction(text, "do_ecmd", func(s []byte) ([]byte, error) {
		return e.subOnce(s, `^[ \t]*set_file_options\(TRUE, eap\);\n`,
			"do_ecmd setting ++ff and ++bin")
	}); err != nil {
		return nil, err
	}

	// 'endofline' and 'endoffile' had no initialiser in buf_copy_options():
	// their only resets were the ones removed above.  droplocal wants an
	// initialiser to recognise the shape, so their field and get_varp() case
	// go here.
	if text, err = e.subCount(text, `^[ \t]*int[ \t]+b_p_eo[lf];\n`,
		"the 'endofline' and 'endoffile' fields", 2); err != nil {
		return nil, err
	}
	if text, err = e.inFunction(text, "get_varp", func(s []byte) ([]byte, error) {
		return e.subCount(s,
			`^[ \t]*case   \(idopt_T\)\(PV_BUF \+ \(int\)\(BV_EO[LF]\)\)  :\n`+
				`[ \t]*return \(char_u \*\)&\(curbuf->b_p_eo[lf]\);\n`,
			"get_varp handing out 'endofline' and 'endoffile'", 2)
	}); err != nil {
		return nil, err
	}
	if text, err = e.subCount(text, `^[ \t]*curbuf->b_no_eol_lnum = 0;\n`,
		"resetting the no-LF line for 'binary'", 2); err != nil {
		return nil, err
	}
	if text, err = e.inFunction(text, "set_init_1", func(s []byte) ([]byte, error) {
		return e.literal(s, "    save_file_ff(curbuf);\n\n", "",
			"startup saving the format of the first buffer", 1)
	}); err != nil {
		return nil, err
	}
	if text, err = e.inFunction(text, "did_set_modified", func(s []byte) ([]byte, error) {
		return e.dropIf(s, `^[ \t]*if \(!args->os_newval\.boolean\)$`,
			"'nomodified' saving the format")
	}); err != nil {
		return nil, err
	}

	if text, err = e.inFunction(text, "cursor_pos_info", func(s []byte) ([]byte, error) {
		var err error
		for _, f := range []struct{ pat, what string }{
			{`^[ \t]*if \(get_fileformat\(curbuf\) == EOL_DOS\)$`,
				"g CTRL-G counting CR LF as two bytes"},
			{`^[ \t]*if \(lnum == curbuf->b_ml\.ml_line_count && !curbuf->b_p_eol && \(curbuf->b_p_bin \|\| !curbuf->b_p_fixeol\) && [^\n]*\)$`,
				"g CTRL-G at a last line with no LF"},
			{`^[ \t]*if \(!curbuf->b_p_eol && \(curbuf->b_p_bin \|\| !curbuf->b_p_fixeol\)\)$`,
				"g CTRL-G counting a missing last LF"},
		} {
			if s, err = e.foldNever(s, f.pat, f.what); err != nil {
				return nil, err
			}
		}
		return s, nil
	}); err != nil {
		return nil, err
	}

	if text, err = e.inFunction(text, "unchanged", func(s []byte) ([]byte, error) {
		s, err := e.literal(s, "buf->b_changed || (ff && file_ff_differs(buf, FALSE))",
			"buf->b_changed", "a changed format counting as a change", 1)
		if err != nil {
			return nil, err
		}
		return e.dropIf(s, `^[ \t]*if \(ff\)$`, "unchanged saving the format")
	}); err != nil {
		return nil, err
	}
	if text, err = e.inFunction(text, "bufIsChangedNotTerm", func(s []byte) ([]byte, error) {
		return e.literal(s, "(buf->b_changed || file_ff_differs(buf, TRUE))",
			"(buf->b_changed)", "a changed format counting as changed", 1)
	}); err != nil {
		return nil, err
	}
	if text, err = e.inFunction(text, "buf_clear_file", func(s []byte) ([]byte, error) {
		return e.subCount(s, `^[ \t]*buf->b_(?:p|start)_eo[fl] = (?:FALSE|TRUE);\n`,
			"buf_clear_file resetting 'endofline' and 'endoffile'", 4)
	}); err != nil {
		return nil, err
	}
	if text, err = e.inFunction(text, "transchar_nonprint", func(s []byte) ([]byte, error) {
		return e.foldNever(s,
			`^[ \t]*else if \(buf != NULL && c == CAR && get_fileformat\(buf\) == EOL_MAC\)$`,
			"CR shown as a line end")
	}); err != nil {
		return nil, err
	}
	if text, err = e.inFunction(text, "do_ascii", func(s []byte) ([]byte, error) {
		return e.foldNever(s, `^[ \t]*if \(c == CAR && get_fileformat\(curbuf\) == EOL_MAC\)$`,
			"ga showing CR as a line end")
	}); err != nil {
		return nil, err
	}
	if text, err = e.inFunction(text, "ml_open", func(s []byte) ([]byte, error) {
		return e.subOnce(s,
			`^[ \t]*b0p-> b0_fname\[B0_FNAME_SIZE_ORG - 2\]  = get_fileformat\(buf\) \+ 1;\n`,
			"block 0 recording the format")
	}); err != nil {
		return nil, err
	}
	if text, err = e.inFunction(text, "ml_setflags", func(s []byte) ([]byte, error) {
		return e.subOnce(s,
			`^[ \t]*b0p-> b0_fname\[B0_FNAME_SIZE_ORG - 2\]  = \(b0p-> b0_fname\[B0_FNAME_SIZE_ORG - 2\]  & ~B0_FF_MASK\)\n`+
				`[ \t]*\| \(get_fileformat\(buf\) \+ 1\);\n`,
			"block 0 updating the format")
	}); err != nil {
		return nil, err
	}
	if text, err = e.inFunction(text, "set_init_3", func(s []byte) ([]byte, error) {
		return e.dropIf(s,
			`^[ \t]*if \( \(curbuf->b_ml\.ml_line_count == 1 && \*ml_get\(\(linenr_T\)1\) == NUL\) \)$`,
			"startup applying 'fileformats' to an empty buffer")
	}); err != nil {
		return nil, err
	}

	if text, err = e.inFunction(text, "getargopt", func(s []byte) ([]byte, error) {
		var err error
		if s, err = e.dropIf(s,
			`^[ \t]*if \( strncmp\(\(char \*\)\(arg\), \(char \*\)\("bin"\), \(3\)\)  == 0 \|\|  strncmp\(\(char \*\)\(arg\), \(char \*\)\("nobin"\), \(5\)\)  == 0\)$`,
			"++bin and ++nobin"); err != nil {
			return nil, err
		}
		for _, f := range []struct{ pat, what string }{
			{`^[ \t]*if \( strncmp\(\(char \*\)\(arg\), \(char \*\)\("ff"\), \(2\)\)  == 0\)$`, "++ff"},
			{`^[ \t]*if \( strncmp\(\(char \*\)\(arg\), \(char \*\)\("fileformat"\), \(10\)\)  == 0\)$`,
				"++fileformat"},
			{`^[ \t]*if \(pp == &eap->force_ff\)$`, "++ff checking its value"},
		} {
			if s, err = e.foldNever(s, f.pat, f.what); err != nil {
				return nil, err
			}
		}
		return s, nil
	}); err != nil {
		return nil, err
	}
	if text, err = e.inFunction(text, "prepare_help_buffer", func(s []byte) ([]byte, error) {
		return e.literal(s, "    curbuf->b_p_bin = FALSE;\n", "",
			"the help buffer clearing 'binary'", 1)
	}); err != nil {
		return nil, err
	}

	if text, err = e.inFunction(text, "buf_copy_options", func(s []byte) ([]byte, error) {
		a := bytes.Index(s, []byte("switch (*p_ffs)"))
		if a < 0 {
			return nil, fmt.Errorf("lfonly: buf_copy_options has no 'fileformats' switch")
		}
		a = bytes.LastIndexByte(s[:a], '\n') + 1
		b := cutil.Blank(s)
		o := a + bytes.IndexByte(b[a:], '{')
		c := cutil.Match(b, o)
		if c < 0 {
			return nil, fmt.Errorf("lfonly: buf_copy_options' switch is unbalanced")
		}
		out := make([]byte, 0, len(s))
		out = append(out, s[:a]...)
		s = append(out, s[c+bytes.IndexByte(s[c:], '\n')+1:]...)
		e.say("a new buffer's 'fileformat' from 'fileformats'")
		var err error
		if s, err = e.dropIf(s, `^[ \t]*if \(buf->b_p_ff != NULL\)$`,
			"a new buffer's remembered format"); err != nil {
			return nil, err
		}
		return e.subCount(s, `^[ \t]*buf->b_p_(?:tw|wm|et)_nobin = p_(?:tw|wm|et)_nobin;\n`,
			"a new buffer's values saved for 'binary'", 3)
	}); err != nil {
		return nil, err
	}

	// Every call left must be inside code the sweep takes with them.  Counted
	// by WHERE each call sits, not by a tally that has to be guessed.
	blanked := cutil.Blank(text)
	var spans [][2]int
	for _, n := range lfonlyDying {
		if a, z, ok := cutil.FindDefinition(text, blanked, n); ok {
			spans = append(spans, [2]int{a, z})
		}
	}
	type head struct {
		at   int
		name string
	}
	var heads []head
	for _, m := range lfonlyHeads.FindAllSubmatchIndex(text, -1) {
		heads = append(heads, head{m[0], string(text[m[2]:m[3]])})
	}
	var live []string
	for _, n := range lfonlyDying {
		for _, m := range regexp.MustCompile(`\b`+n+`\(`).FindAllIndex(text, -1) {
			ls := bytes.LastIndexByte(text[:m[0]], '\n') + 1
			le := bytes.IndexByte(text[m[0]:], '\n')
			var line []byte
			if le < 0 {
				line = text[ls:]
			} else {
				line = text[ls : m[0]+le]
			}
			if bytes.HasPrefix(line, []byte("static ")) ||
				bytes.HasPrefix(line, []byte(n+"(")) {
				continue
			}
			inDying := false
			for _, sp := range spans {
				if sp[0] <= m[0] && m[0] < sp[1] {
					inDying = true
					break
				}
			}
			if inDying {
				continue
			}
			owner := "?"
			for _, h := range heads {
				if h.at <= m[0] {
					owner = h.name
				}
			}
			live = append(live, n+" in "+owner)
		}
	}
	if len(live) > 0 {
		return nil, fmt.Errorf("lfonly: still called from live code: %s", strings.Join(live, ", "))
	}

	e.say("every line ends with LF, read and written")
	return text, nil
}
