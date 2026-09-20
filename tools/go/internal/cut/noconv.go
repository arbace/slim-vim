package cut

import (
	"bytes"
	"fmt"
	"io"
	"os"
	"regexp"

	"slimvim.local/tools/internal/cutil"
)

// noconvPointers are the ten mb_* indirections and the UTF-8 function each
// becomes.
//
// A SLICE AND NOT A MAP.  Python 3.7+ dicts iterate in insertion order and Go
// maps iterate randomly; nothing in the rewriting depends on the order, since
// the ten names are disjoint, but the refusal names the first one that fails
// and that should be the same name on both sides.
var noconvPointers = []struct{ ptr, fn string }{
	{"mb_ptr2len", "utfc_ptr2len"}, {"mb_ptr2len_len", "utfc_ptr2len_len"},
	{"mb_char2len", "utf_char2len"}, {"mb_char2bytes", "utf_char2bytes"},
	{"mb_ptr2cells", "utf_ptr2cells"}, {"mb_ptr2cells_len", "utf_ptr2cells_len"},
	{"mb_char2cells", "utf_char2cells"}, {"mb_off2cells", "utf_off2cells"},
	{"mb_ptr2char", "utf_ptr2char"}, {"mb_head_off", "utf_head_off"},
}

// noconvDie mirrors the Python's die(): with $NOCONV_DUMP set it writes the
// segment it refused on, which is how this phase was debugged.
func noconvDie(msg string, seg []byte) error {
	if dump := os.Getenv("NOCONV_DUMP"); dump != "" {
		_ = os.WriteFile(dump, seg, 0o644)
	}
	return fmt.Errorf("noconv: %s", msg)
}

// ncFold folds ONE AT A TIME, FROM THE LAST: a condition can repeat inside its
// own block, and folding the first would then fold an inner copy out from
// under the outer one.
func (e ed) ncFold(seg []byte, pattern, what, kind string, count int) ([]byte, error) {
	re := regexp.MustCompile("(?m)" + pattern)
	n := count
	if n < 0 {
		n = len(re.FindAll(seg, -1))
	}
	if n == 0 {
		return nil, noconvDie(what+" -- no occurrence", seg)
	}
	for i := 0; i < n; i++ {
		ms := re.FindAllIndex(seg, -1)
		if len(ms) == 0 {
			return nil, noconvDie(fmt.Sprintf("%s -- list index out of range", what), seg)
		}
		last := ms[len(ms)-1]
		start := bytes.LastIndexByte(seg[:last[0]], '\n') + 1
		var out []byte
		var err error
		if kind == "never" {
			out, err = cutil.FoldNever(seg[start:], "(?m)"+pattern, 1)
		} else {
			out, err = cutil.FoldAlways(seg[start:], "(?m)"+pattern, 1)
		}
		if err != nil {
			return nil, noconvDie(fmt.Sprintf("%s -- %v", what, err), seg)
		}
		joined := make([]byte, 0, len(seg))
		joined = append(joined, seg[:start]...)
		seg = append(joined, out...)
	}
	suffix := ""
	if n != 1 {
		suffix = fmt.Sprintf(" (%d)", n)
	}
	fmt.Fprintf(e.w, "  %-13s%s%s\n", e.tool, what, suffix)
	return seg, nil
}

// directCall rewrites `(*ptr)(` and a bare `ptr(` into `fn(`.
//
// The bare form is written `(?<![\w*])ptr\(` in the Python -- a NEGATIVE
// LOOKBEHIND, which RE2 does not have.  Testing the preceding byte is exact
// and does the same thing: it skips `xx_mb_ptr2len(` and `*mb_ptr2len)(`,
// which is what the lookbehind is for.
func directCall(text []byte, ptr, fn string) ([]byte, int) {
	n := 0
	indirect := regexp.MustCompile(`\(\*` + regexp.QuoteMeta(ptr) + `\)\(`)
	n += len(indirect.FindAll(text, -1))
	text = indirect.ReplaceAll(text, []byte(fn+"("))

	name := []byte(ptr + "(")
	var out []byte
	prev := 0
	for i := 0; ; {
		j := bytes.Index(text[i:], name)
		if j < 0 {
			break
		}
		at := i + j
		i = at + len(name)
		if at > 0 {
			b := text[at-1]
			if b == '*' || b == '_' || ('0' <= b && b <= '9') ||
				('a' <= b && b <= 'z') || ('A' <= b && b <= 'Z') {
				continue
			}
		}
		out = append(out, text[prev:at]...)
		out = append(out, (fn + "(")...)
		prev = i
		n++
	}
	if prev == 0 {
		return text, n
	}
	return append(out, text[prev:]...), n
}

// NoConv makes a file read and written as the UTF-8 bytes it holds.
func NoConv(text []byte, w io.Writer) ([]byte, error) {
	e := ed{"noconv", w}
	var err error

	text, err = e.inFunction(text, "getargopt", func(s []byte) ([]byte, error) {
		s, err := e.dropIf(s,
			`^[ \t]*if \( strncmp\(\(char \*\)\(arg\), \(char \*\)\("enc"\), \(3\)\)  == 0\)$`,
			"++enc and ++encoding")
		if err != nil {
			return nil, err
		}
		return e.subCountRepl(s,
			`(?ms)^    if \(pp == NULL \|\| \*arg != '='\)\n.*?^    return OK;\n`,
			"    return FAIL;\n",
			"getargopt: every ++ argument but ++edit is unknown", 1)
	})
	if err != nil {
		return nil, err
	}

	text, err = e.inFunction(text, "readfile", func(s []byte) ([]byte, error) {
		var err error
		if s, err = e.subOnce(s,
			`^[ \t]*if \(eap != NULL\)\n[ \t]*\{\n[ \t]*set_forced_fenc\(eap\);\n[ \t]*\}\n`,
			"a new file taking ++enc"); err != nil {
			return nil, err
		}
		for _, f := range []struct{ pat, what string }{
			{`^[ \t]*if \(eap != NULL && eap->force_enc != 0\)$`, "readfile honouring ++enc"},
			{`^[ \t]*if \(curbuf->b_help\)$`, "a help buffer read as latin1 or utf-8"},
			{`^[ \t]*if \(advance_fenc\)$`, "readfile moving to the next encoding"},
		} {
			if s, err = e.ncFold(s, f.pat, f.what, "never", -1); err != nil {
				return nil, err
			}
		}
		if s, err = e.subOnce(s, `^[ \t]*converted = need_conversion\(fenc\);\n`,
			"readfile asking whether to convert"); err != nil {
			return nil, err
		}
		if s, err = e.ncFold(s, `^[ \t]*if \(converted\)$`,
			"readfile choosing a conversion", "never", -1); err != nil {
			return nil, err
		}
		if s, err = e.subOnce(s,
			`^[ \t]*can_retry = \(\*fenc != NUL && !read_stdin && !read_fifo && !keep_dest_enc\);\n\n`,
			"readfile deciding it may retry"); err != nil {
			return nil, err
		}
		for _, f := range []struct{ pat, what string }{
			{`^[ \t]*if \(fio_flags != 0\)$`,
				"the latin1, UCS-2, UTF-16 and UCS-4 read loops"},
			{`^[ \t]*if \(fio_flags != 0 \|\| iconv_fd != \(iconv_t\)-1\)$`,
				"an incomplete converted tail"},
			{`^[ \t]*if \(iconv_fd != \(iconv_t\)-1\)$`, "reading room for iconv"},
		} {
			if s, err = e.ncFold(s, f.pat, f.what, "never", -1); err != nil {
				return nil, err
			}
		}
		for _, flag := range []string{`fio_flags & FIO_LATIN1`,
			`fio_flags & \(FIO_UCS2 \| FIO_UTF16\)`, `fio_flags & FIO_UCS4`,
			`fio_flags == FIO_UCSBOM`} {
			plain := regexp.MustCompile(`\\`).ReplaceAllString(flag, "")
			if s, err = e.ncFold(s, `^[ \t]*if \(`+flag+`\)$`,
				"reading room for a "+plain, "never", -1); err != nil {
				return nil, err
			}
		}
		if s, err = e.dropIf(s,
			`^[ \t]*if \(\(filesize == 0\) && \(fio_flags == FIO_UCSBOM \|\| \(tmpname == NULL && \(\*fenc == 'u' \|\| \(\*fenc == NUL\)\)\)\)\)$`,
			"the byte-order-mark check, which finds none"); err != nil {
			return nil, err
		}
		for _, f := range []struct{ pat, what string }{
			{`^[ \t]*if \(iconv_fd != \(iconv_t\)-1 && conv_error == 0\)$`,
				"an iconv error in the UTF-8 check"},
			{`^[ \t]*if \(can_retry && !incomplete_tail\)$`,
				"the UTF-8 check stopping to retry"},
		} {
			if s, err = e.ncFold(s, f.pat, f.what, "never", -1); err != nil {
				return nil, err
			}
		}
		if s, err = e.dropIf(s, `^[ \t]*if \(p < ptr \+ size && !incomplete_tail\)$`,
			"the rewind to retry another encoding"); err != nil {
			return nil, err
		}
		if s, err = e.literal(s, "if (conv_error == 0 && illegal_byte == 0)",
			"if (illegal_byte == 0)",
			"an illegal byte deferring to a conversion error", 1); err != nil {
			return nil, err
		}
		if s, err = e.ncFold(s, `^[ \t]*if \(file_rewind\)$`,
			"readfile rewinding for a retry", "never", -1); err != nil {
			return nil, err
		}
		if bytes.Contains(s, []byte("goto retry")) {
			return nil, fmt.Errorf("noconv: readfile still jumps to retry")
		}
		if s, err = e.subOnce(s, `^retry:\n\n`, "the retry label"); err != nil {
			return nil, err
		}
		for _, f := range []struct{ pat, what string }{
			{`^[ \t]*if \(tmpname != NULL\)$`, "'charconvert''s temporary file"},
			{`^[ \t]*if \(fenc_alloced\)$`, "readfile freeing an encoding name"},
			{`^[ \t]*if \(notconverted\)$`, `the "[NOT converted]" message`},
			{`^[ \t]*if \(converted\)$`, `the "[converted]" message`},
			{`^[ \t]*if \(conv_error != 0\)$`, `the "[CONVERSION ERROR]" message`},
		} {
			if s, err = e.ncFold(s, f.pat, f.what, "never", -1); err != nil {
				return nil, err
			}
		}
		if bytes.Contains(s, []byte("goto failed")) {
			return nil, noconvDie("readfile still jumps to failed", s)
		}
		if s, err = e.subOnce(s, `^failed:\n`,
			"the failed label, which only a rewind jumped to"); err != nil {
			return nil, err
		}
		if s, err = e.literal(s, "if (newfile && (error || conv_error != 0))",
			"if (newfile && error)",
			"a conversion error making the buffer read-only", 1); err != nil {
			return nil, err
		}
		if s, err = e.subCount(s, `^[ \t]*fio_flags = 0;\n`,
			"readfile clearing the conversion flags", 2); err != nil {
			return nil, err
		}
		for _, c := range []struct{ pat, what string }{
			{`^[ \t]*fenc = \(char_u \*\)"";\n`, "readfile setting the empty encoding"},
			{`^[ \t]*fenc_alloced = FALSE;\n`, "readfile noting it owns no encoding name"},
			{`^[ \t]*real_size = \(int\)size;\n`,
				"readfile remembering the converted buffer's size"},
		} {
			if s, err = e.subOnce(s, c.pat, c.what); err != nil {
				return nil, err
			}
		}
		return s, nil
	})
	if err != nil {
		return nil, err
	}

	text, err = e.inFunction(text, "buf_write", func(s []byte) ([]byte, error) {
		var err error
		if s, err = e.ncFold(s, `^[ \t]*if \(eap != NULL && eap->force_enc != 0\)$`,
			"buf_write honouring ++enc", "never", -1); err != nil {
			return nil, err
		}
		if s, err = e.subOnce(s, `^[ \t]*fenc = \(char_u \*\)"";\n`,
			"buf_write setting the empty encoding"); err != nil {
			return nil, err
		}
		if s, err = e.subOnce(s, `^[ \t]*converted = need_conversion\(fenc\);\n\n`,
			"buf_write asking whether to convert"); err != nil {
			return nil, err
		}
		for _, f := range []struct{ pat, what, kind string }{
			{`^[ \t]*if \(converted\)$`, "buf_write allocating conversion buffers", "never"},
			{`^[ \t]*if \(converted && wb_flags == 0 && write_info\.bw_iconv_fd == \(iconv_t\)-1\)$`,
				"buf_write refusing a conversion it cannot do", "never"},
			{`^[ \t]*if \(!converted\)$`, "buf_write skipping the conversion check", "always"},
			{`^[ \t]*else if \(notconverted\)$`, `the "[NOT converted]" write message`, "never"},
			{`^[ \t]*else if \(converted\)$`, `the "[converted]" write message`, "never"},
		} {
			if s, err = e.ncFold(s, f.pat, f.what, f.kind, -1); err != nil {
				return nil, err
			}
		}
		if s, err = e.subOnce(s, `^[ \t]*vim_free\(fenc_tofree\);\n`,
			"buf_write freeing ++enc's name"); err != nil {
			return nil, err
		}
		// Only buf_write_bytes()'s conversion set bw_conv_error, and it has gone.
		if s, err = e.ncFold(s, `^[ \t]*if \(write_info\.bw_conv_error\)$`,
			"a conversion error in a write", "never", 2); err != nil {
			return nil, err
		}
		if s, err = e.literal(s, " && !write_info.bw_conv_error && ", " && ",
			"a conversion error keeping the buffer modified", 1); err != nil {
			return nil, err
		}
		// The pass that only checked a conversion is never taken: the loop
		// body clears the flag before its first test.
		if s, err = e.ncFold(s, `^[ \t]*if \(checking_conversion\)$`,
			"buf_write checking a conversion without writing", "never", -1); err != nil {
			return nil, err
		}
		if s, err = e.ncFold(s, `^[ \t]*if \(!checking_conversion\)$`,
			"buf_write syncing after the pass that wrote", "always", -1); err != nil {
			return nil, err
		}
		for _, c := range []struct{ pat, what string }{
			{`^[ \t]*write_info\.bw_conv_buf = NULL;\n`, "buf_write clearing the conversion buffer"},
			{`^[ \t]*vim_free\(write_info\.bw_conv_buf\);\n`, "buf_write freeing the conversion buffer"},
		} {
			if s, err = e.subOnce(s, c.pat, c.what); err != nil {
				return nil, err
			}
		}
		return s, nil
	})
	if err != nil {
		return nil, err
	}

	if text, err = e.inFunction(text, "buf_write_bytes", func(s []byte) ([]byte, error) {
		return e.dropIf(s, `^[ \t]*if \(!\(flags & FIO_NOCONVERT\)\)$`,
			"buf_write_bytes converting, which no write flag asks for")
	}); err != nil {
		return nil, err
	}
	if text, err = e.inFunction(text, "do_ecmd", func(s []byte) ([]byte, error) {
		return e.subOnce(s,
			`^[ \t]*if \(!oldbuf && eap != NULL\)\n[ \t]*\{\n[ \t]*set_forced_fenc\(eap\);\n[ \t]*\}\n`,
			"editing a file taking ++enc")
	}); err != nil {
		return nil, err
	}

	if text, err = e.inFunction(text, "mb_init", func(s []byte) ([]byte, error) {
		var err error
		for _, f := range []struct{ pat, what string }{
			{`^[ \t]*if \(p_enc == NULL\)$`, "mb_init without an encoding"},
			{`^[ \t]*if \( strcmp\(\(char \*\)\(p_enc\), \(char \*\)\("utf-8"\)\)  != 0\)$`,
				"mb_init refusing another encoding"},
		} {
			if s, err = e.ncFold(s, f.pat, f.what, "never", -1); err != nil {
				return nil, err
			}
		}
		if s, err = e.subCount(s, `^[ \t]*mb_\w+ = utf\w+;\n`,
			"mb_init pointing the mb_* functions at UTF-8", 10); err != nil {
			return nil, err
		}
		for _, c := range []struct{ pat, what string }{
			{`^[ \t]*vimconv_T[ \t]+vimconv;\n`, "mb_init's conversion"},
			{`^[ \t]*vimconv\.vc_type = CONV_NONE;\n`, "mb_init clearing a conversion"},
			{`^[ \t]*convert_setup\(&vimconv, NULL, NULL\);\n`, "mb_init setting up no conversion"},
		} {
			if s, err = e.subOnce(s, c.pat, c.what); err != nil {
				return nil, err
			}
		}
		return e.subCountRepl(s, `(?m)^for \(i = 0; i < 256; \+\+i\)$`,
			"    for (i = 0; i < 256; ++i)", "mb_init's byte-length loop, indented", 1)
	}); err != nil {
		return nil, err
	}

	// THE BRANCH FOLDED ABOVE WAS TAKEN, ONCE.  common_init_1() calls
	// mb_init() before any option exists, and p_enc NULL sent that call to the
	// 1s and back; set_init_1() makes the real call later.  Without the branch
	// the first call ran on into init_chartab() with no curbuf, and the editor
	// crashed before its first command.
	if text, err = e.inFunction(text, "common_init_1", func(s []byte) ([]byte, error) {
		return e.literal(s, "    (void)mb_init();\n",
			"    for (int i = 0; i < 256; ++i)\n    {\n        mb_bytelen_tab[i] = 1;\n    }\n",
			"startup filling the byte lengths before any option exists", 1)
	}); err != nil {
		return nil, err
	}
	if text, err = e.inFunction(text, "set_options_default", func(s []byte) ([]byte, error) {
		return e.literal(s,
			" && (opt_flags == 0 || (options[i].var != (char_u *)&p_enc))", "",
			"setting defaults skipping 'encoding'", 1)
	}); err != nil {
		return nil, err
	}

	if text, err = e.inFunction(text, "utf_find_illegal", func(s []byte) ([]byte, error) {
		s, err := e.ncFold(s, `^[ \t]*if \(vimconv\.vc_type != CONV_NONE\)$`,
			":ga-style search converting a line first", "never", -1)
		if err != nil {
			return nil, err
		}
		if s, err = e.keepThen(s, `^[ \t]*if \(vimconv\.vc_type == CONV_NONE\)$`,
			"the illegal byte found in the line itself"); err != nil {
			return nil, err
		}
		for _, c := range []struct{ pat, what string }{
			{`^[ \t]*vimconv_T[ \t]+vimconv;\n`, "utf_find_illegal's conversion"},
			{`^[ \t]*char_u[ \t]+\*tofree = NULL;\n`, "utf_find_illegal's converted copy"},
			{`^[ \t]*vimconv\.vc_type = CONV_NONE;\n\n`, "utf_find_illegal clearing a conversion"},
			{`^[ \t]*vim_free\(tofree\);\n`, "utf_find_illegal freeing a converted copy"},
			{`^[ \t]*convert_setup\(&vimconv, NULL, NULL\);\n`, "utf_find_illegal ending no conversion"},
		} {
			if s, err = e.subOnce(s, c.pat, c.what); err != nil {
				return nil, err
			}
		}
		return s, nil
	}); err != nil {
		return nil, err
	}
	if text, err = e.inFunction(text, "ui_write", func(s []byte) ([]byte, error) {
		return e.ncFold(s, `^[ \t]*if \(output_conv\.vc_type != CONV_NONE\)$`,
			"output converted for the terminal", "never", 2)
	}); err != nil {
		return nil, err
	}
	if text, err = e.inFunction(text, "fill_input_buf", func(s []byte) ([]byte, error) {
		s, err := e.literal(s, "((INBUFLEN - inbufcount) / input_conv.vc_factor)",
			"(INBUFLEN - inbufcount)",
			"input read in room for a conversion to grow", 1)
		if err != nil {
			return nil, err
		}
		for _, f := range []struct{ pat, what string }{
			{`^[ \t]*if \(input_conv\.vc_type != CONV_NONE\)$`,
				"input converted from the terminal"},
			{`^[ \t]*if \(rest != NULL\)$`, "input left over from a conversion"},
		} {
			if s, err = e.ncFold(s, f.pat, f.what, "never", -1); err != nil {
				return nil, err
			}
		}
		return e.subOnce(s, `^[ \t]*unconverted = 0;\n`, "nothing left unconverted")
	}); err != nil {
		return nil, err
	}

	if text, err = e.subCount(text,
		`^static int \(\*mb_\w+\)\([^;\n]*\)\s*=\s*latin_\w+\s*;\n`,
		"the mb_* function pointers", 10); err != nil {
		return nil, err
	}
	calls := 0
	for _, p := range noconvPointers {
		var n int
		text, n = directCall(text, p.ptr, p.fn)
		calls += n
		if regexp.MustCompile(`\b` + p.ptr + `\b`).Match(text) {
			return nil, fmt.Errorf("noconv: %s is still named after its calls were made direct",
				p.ptr)
		}
	}
	fmt.Fprintf(w, "  noconv       %d calls through an mb_* pointer are direct calls\n", calls)

	if text, err = e.inFunction(text, "mb_tail_off", func(s []byte) ([]byte, error) {
		return e.literal(s,
			"    return i;\n\n    return 0;\n\n    return 1 - dbcs_head_off(base, p);\n",
			"    return i;\n", "mb_tail_off's dead DBCS returns", 1)
	}); err != nil {
		return nil, err
	}

	if text, err = e.inFunction(text, "expand_argopt", func(s []byte) ([]byte, error) {
		var err error
		link := `^[ \t]*if \(name_end - xp->xp_line >= \d+ &&  strncmp\(\(char \*\)\(name_end - \d+\), \(char \*\)\("\w+"\), \(\d+\)\)  == 0\)$`
		for i := 0; i < 5; i++ {
			if s, err = e.ncFold(s, link, "completion for an ++ argument value",
				"never", 1); err != nil {
				return nil, err
			}
		}
		if s, err = e.ncFold(s, `^[ \t]*if \(cb != NULL\)$`,
			"completing an ++ argument value", "never", -1); err != nil {
			return nil, err
		}
		return e.dropIf(s,
			`^[ \t]*if \(xp->xp_pattern_len == 2 &&  strncmp\(\(char \*\)\(xp->xp_pattern\), \(char \*\)\("ff"\), \(xp->xp_pattern_len\)\)  == 0\)$`,
			"completing ++ff to ++fileformat=")
	}); err != nil {
		return nil, err
	}
	if text, err = e.inFunction(text, "get_argopt_name", func(s []byte) ([]byte, error) {
		return e.subCount(s, `^[ \t]*"(?:fileformat=|encoding=|nobinary|bad=)",\n`,
			"the ++ff, ++enc, ++nobin and ++bad names", 4)
	}); err != nil {
		return nil, err
	}

	e.say("a file is read and written as the UTF-8 bytes it holds")
	return text, nil
}
