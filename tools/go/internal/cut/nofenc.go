package cut

import (
	"bytes"
	"fmt"
	"io"
	"regexp"

	"slimvim.local/tools/internal/cutil"
)

var nofencStubs = []struct{ name, body string }{
	{"bomb_size", "    return 0;"},
	{"add_b0_fenc", ""},
}

// nofencEdits: a nil pattern means the edit is brace-matched below, because
// the block holds inner blocks and a lazy line scan would stop at the first
// one's closing brace.
var nofencEdits = []struct {
	what, pat, repl string
	want            int
}{
	{"buf_write taking the buffer's 'fileencoding' as its target",
		`(?m)([ \t]*else\n[ \t]*\{\n)[ \t]*fenc = buf->b_p_fenc;\n`,
		"${1}        fenc = (char_u *)\"\";\n", 1},
	{"readfile taking the buffer's 'fileencoding' when there is no list",
		`(?m)[ \t]*fenc = curbuf->b_p_fenc;\n`, "        fenc = (char_u *)\"\";\n", 1},
	{"readfile setting 'bomb' after stripping one",
		`(?m)[ \t]*if \(set_options\)\n[ \t]*\{\n` +
			`[ \t]*curbuf->b_p_bomb = TRUE;\n` +
			`[ \t]*curbuf->b_start_bomb = TRUE;\n[ \t]*\}\n`, "", 1},
	{"readfile clearing it, twice", `(?m)[ \t]*curbuf->b_p_bomb = FALSE;\n`, "", 2},
	// The test is longer than it looks: the 'bomb' term is one of four in a
	// nested disjunction, and only that term goes.
	{"the BOM this build never has, in readfile's first-block test",
		`(?m)!curbuf->b_p_bomb && tmpname == NULL`, "tmpname == NULL", 1},
	{"save_file_ff remembering the BOM and the encoding",
		`(?m)[ \t]*buf->b_start_bomb = buf->b_p_bomb;\n\n` +
			`[ \t]*if \(buf->b_start_fenc == NULL \|\|  strcmp[^\n]*\n[ \t]*\{\n` +
			`[ \t]*vim_free\(buf->b_start_fenc\);\n` +
			`[ \t]*buf->b_start_fenc = vim_strsave\(buf->b_p_fenc\);\n[ \t]*\}\n`, "", 1},
	{"file_ff_differs comparing them",
		`(?m)[ \t]*if \(!buf->b_p_bin && buf->b_start_bomb != buf->b_p_bomb\)\n` +
			`[ \t]*\{\n[ \t]*return TRUE;\n[ \t]*\}\n` +
			`[ \t]*if \(buf->b_start_fenc == NULL\)\n[ \t]*\{\n` +
			`[ \t]*return \(\*buf->b_p_fenc != NUL\);\n[ \t]*\}\n` +
			`[ \t]*return \( strcmp[^\n]*\n`, "    return FALSE;\n", 1},
	{"g8 converting to the buffer's 'fileencoding' to find an illegal byte",
		`(?m)[ \t]*if \(enc_utf8 && \(enc_canon_props\(curbuf->b_p_fenc\) & ENC_8BIT\)\)\n` +
			`[ \t]*\{\n[ \t]*convert_setup\(&vimconv, p_enc, curbuf->b_p_fenc\);\n[ \t]*\}\n`,
		"", 1},
	{"buf_write writing a BOM it no longer makes", "", "", 0},
	// What the two options leave behind once nothing compares them: the
	// remembered copies, written on every read and looked at by nobody.  A
	// struct field is not a variable, so no warning reports it and the sweep
	// cannot see it -- which is why these are listed rather than swept.
	{"the remembered BOM and encoding a file was read with",
		`(?m)^[ \t]*char_u[ \t]*\*b_start_fenc;\n`, "", 1},
	{"them, in buf_T", `(?m)^[ \t]*int[ \t]*b_start_bomb;\n`, "", 1},
	{"freeing the remembered encoding",
		`(?m)^[ \t]* vim_free\(buf->b_start_fenc\);\n[ \t]* \(buf->b_start_fenc\) = NULL;\n`,
		"", 1},
	{"clearing the remembered BOM",
		`(?m)^[ \t]*(?:cur)?buf->b_start_bomb = FALSE;\n`, "", 3},
	{"did_set_encoding's arm for 'fileencoding'", "", "", 0},
	{"the empty test Phase 15 left in did_set_encoding",
		`(?m)\n[ \t]*if \(errmsg == NULL\)\n[ \t]*\{\n[ \t]*\}\n`, "", 1},
	// THREE LOOKUPS BY NAME, and the reason this phase needed two attempts.
	// set_string_option_direct((char_u *)"fenc", ...) resolves the option
	// through findoption(), which answers -1 for a row that is not there; the
	// caller does not check, so silent Ex mode exits 1 without printing
	// anything, and every recorded exit status in the harness moves at once.
	{"readfile recording the encoding it read a file in",
		`(?m)\n[ \t]*if \(set_options\)\n[ \t]*\{\n` +
			`[ \t]*set_string_option_direct\(\(char_u \*\)"fenc",[^\n]*\n[ \t]*\}\n`, "\n", 1},
	{"`:e ++enc=` forcing one",
		`(?m)[ \t]*char_u \*fenc = enc_canonize\(eap->cmd \+ eap->force_enc\);\n\n` +
			`[ \t]*if \(fenc != NULL\)\n[ \t]*\{\n` +
			`[ \t]*set_string_option_direct\(\(char_u \*\)"fenc",[^\n]*\n[ \t]*\}\n` +
			`[ \t]*vim_free\(fenc\);\n`, "", 1},
	{"reading one out of a recovered swap file's block zero",
		`(?m)[ \t]*if \(b0p-> b0_fname\[B0_FNAME_SIZE_ORG - 2\]  & B0_HAS_FENC\)\n` +
			`[ \t]*\{\n[ \t]*int fnsize = B0_FNAME_SIZE_NOCRYPT;\n\n` +
			`[ \t]*for \(p = b0p->b0_fname \+ fnsize; p > b0p->b0_fname && p\[-1\] != NUL; --p\)\n` +
			`[ \t]*\{\n[ \t]*;\n[ \t]*\}\n` +
			`[ \t]*b0_fenc = vim_strnsave\(p, b0p->b0_fname \+ fnsize - p\);\n[ \t]*\}\n\n?`,
		"", 1},
	{"the local it was read into", `(?m)^[ \t]*char_u[ \t]*\*b0_fenc = NULL;\n`, "", 1},
	{"a recovered swap file restoring one",
		`(?m)[ \t]*if \(b0_fenc != NULL\)\n[ \t]*\{\n` +
			`[ \t]*set_option_value_give_err\(\(char_u \*\)"fenc",[^\n]*\n` +
			`[ \t]*vim_free\(b0_fenc\);\n[ \t]*\}\n`, "", 1},
	// gvarp existed to ask which of the three encoding options was being set.
	// There is one.  -Wunused-but-set-variable is not a shape deadsweep
	// deletes, so it goes here.
	{"the local that asked which encoding option was being set",
		`(?m)^[ \t]*char_u[ \t]*\*\*gvarp;\n`, "", 1},
	{"its one assignment",
		`(?m)^[ \t]*gvarp = \(char_u \*\*\)get_option_varp_scope\(args->os_idx, OPT_GLOBAL\);\n\n?`,
		"", 1},
}

// dropIfBlock removes an `if` and the block it guards, found by BRACE
// MATCHING from the condition's own parenthesis.
func dropIfBlock(text []byte, pat, what string) ([]byte, error) {
	blanked := cutil.Blank(text)
	m := regexp.MustCompile(pat).FindIndex(text)
	if m == nil {
		return nil, fmt.Errorf("nofenc: %s is not where this expects", what)
	}
	lp := m[0] + bytes.IndexByte(text[m[0]:], '(')
	rp := cutil.Match(blanked, lp)
	i := rp + 1
	for i < len(text) && (text[i] == ' ' || text[i] == '\t' || text[i] == '\n') {
		i++
	}
	closing := cutil.Match(blanked, i)
	if closing < 0 {
		return nil, fmt.Errorf("nofenc: %s is unbalanced", what)
	}
	end := closing + 1
	for end < len(text) && (text[end] == ' ' || text[end] == '\t') {
		end++
	}
	if end < len(text) && text[end] == '\n' {
		end++
	}
	out := make([]byte, 0, len(text))
	out = append(out, text[:m[0]]...)
	return append(out, text[end:]...), nil
}

// NoFenc takes 'fileencoding' and 'bomb' away.
func NoFenc(text []byte, w io.Writer) ([]byte, error) {
	var err error
	for _, e := range nofencEdits {
		if e.pat == "" {
			if e.what == "buf_write writing a BOM it no longer makes" {
				text, err = dropIfBlock(text,
					`(?m)^[ \t]*if \(buf->b_p_bomb && !write_bin`,
					"buf_write no longer writes a BOM")
				if err != nil {
					return nil, fmt.Errorf("nofenc: buf_write no longer writes a BOM")
				}
			} else {
				if text, err = dropIfBlock(text,
					`(?m)^[ \t]*if \(gvarp == &p_fenc\)$`, e.what); err != nil {
					return nil, err
				}
			}
		} else {
			re := regexp.MustCompile(e.pat)
			n := len(re.FindAll(text, -1))
			if n != e.want {
				return nil, fmt.Errorf("nofenc: %s -- expected %d, matched %d",
					e.what, e.want, n)
			}
			text = re.ReplaceAll(text, []byte(e.repl))
		}
		fmt.Fprintf(w, "  nofenc       %s\n", e.what)
	}

	for _, s := range nofencStubs {
		o, c, found, balanced := cutil.Body(text, s.name)
		if !found || !balanced {
			return nil, fmt.Errorf("nofenc: %s is not defined at file scope any more", s.name)
		}
		var buf []byte
		buf = append(buf, text[:o]...)
		buf = append(buf, "{\n"...)
		if s.body != "" {
			buf = append(buf, s.body...)
			buf = append(buf, '\n')
		}
		buf = append(buf, '}')
		text = append(buf, text[c+1:]...)
		fmt.Fprintf(w, "  nofenc       %s answers for a file that has no BOM\n", s.name)
	}
	return text, nil
}
