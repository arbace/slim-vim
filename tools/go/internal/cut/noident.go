package cut

import (
	"bytes"
	"fmt"
	"io"
	"regexp"

	"slimvim.local/tools/internal/cutil"
)

// identBody is nv_ident rewritten to the half that is search.  Generated from
// the Python module's own constant by importing it, because it is a non-raw
// triple-quoted string full of backslashes.
const identBody = "    char_u      *ptr = NULL;\n" +
	"    char_u      *buf;\n" +
	"    size_t      bufsize;\n" +
	"    size_t      buflen;\n" +
	"    char_u      *p;\n" +
	"    int         n = 0;\n" +
	"    int         cmdchar;\n" +
	"    int         g_cmd;\n" +
	"    char_u      *aux_ptr;\n" +
	"\n" +
	"    if (cap->cmdchar == 'g')\n" +
	"    {\n" +
	"        cmdchar = cap->nchar;\n" +
	"        g_cmd = TRUE;\n" +
	"    }\n" +
	"    else\n" +
	"    {\n" +
	"        cmdchar = cap->cmdchar;\n" +
	"        g_cmd = FALSE;\n" +
	"    }\n" +
	"\n" +
	"    if (cmdchar == POUND)\n" +
	"    {\n" +
	"        cmdchar = '#';\n" +
	"    }\n" +
	"\n" +
	"    if (ptr == NULL && (n = find_ident_under_cursor(&ptr, (cmdchar == '*' || cmdchar == '#') ? FIND_IDENT|FIND_STRING : FIND_IDENT)) == 0)\n" +
	"    {\n" +
	"        clearop(cap->oap);\n" +
	"        return;\n" +
	"    }\n" +
	"\n" +
	"    bufsize = (size_t)(n * 2 + 30);\n" +
	"    buf = alloc(bufsize);\n" +
	"    if (buf == NULL)\n" +
	"    {\n" +
	"        return;\n" +
	"    }\n" +
	"    buf[0] = NUL;\n" +
	"    buflen = 0;\n" +
	"\n" +
	"    setpcmark();\n" +
	"    curwin->w_cursor.col = (colnr_T) (ptr - ml_get_curline());\n" +
	"\n" +
	"    if (!g_cmd && vim_iswordp(ptr))\n" +
	"    {\n" +
	"         strcpy((char *)(buf), (char *)(\"\\\\<\")) ;\n" +
	"        buflen =  (sizeof(\"\\\\<\" \"\") - 1) ;\n" +
	"    }\n" +
	"    no_smartcase = TRUE;\n" +
	"\n" +
	"    if (cmdchar == '*')\n" +
	"    {\n" +
	"        aux_ptr = (char_u *)(magic_isset() ? \"/.*~[^$\\\\\" : \"/^$\\\\\");\n" +
	"    }\n" +
	"    else\n" +
	"    {\n" +
	"        aux_ptr = (char_u *)(magic_isset() ? \"/?.*~[^$\\\\\" : \"/?^$\\\\\");\n" +
	"    }\n" +
	"\n" +
	"    p = buf + buflen;\n" +
	"    while (n-- > 0)\n" +
	"    {\n" +
	"        if (vim_strchr(aux_ptr, *ptr) != NULL)\n" +
	"        {\n" +
	"            *p++ = '\\\\';\n" +
	"        }\n" +
	"\n" +
	"        if (has_mbyte)\n" +
	"        {\n" +
	"            int i;\n" +
	"            int len = (*mb_ptr2len)(ptr) - 1;\n" +
	"\n" +
	"            for (i = 0; i < len && n >= 1; ++i, --n)\n" +
	"            {\n" +
	"                *p++ = *ptr++;\n" +
	"            }\n" +
	"        }\n" +
	"        *p++ = *ptr++;\n" +
	"    }\n" +
	"    *p = NUL;\n" +
	"    buflen = p - buf;\n" +
	"\n" +
	"    if (!g_cmd && (has_mbyte ? vim_iswordp(mb_prevptr(ml_get_curline(), ptr)) : vim_iswordc(ptr[-1])))\n" +
	"    {\n" +
	"         strcpy((char *)(buf + buflen), (char *)(\"\\\\>\")) ;\n" +
	"        buflen +=  (sizeof(\"\\\\>\" \"\") - 1) ;\n" +
	"    }\n" +
	"\n" +
	"    init_history();\n" +
	"    add_to_history(HIST_SEARCH, buf, buflen, TRUE, NUL);\n" +
	"\n" +
	"    (void)normal_search(cap, cmdchar == '*' ? '/' : '?', buf, buflen, 0, NULL);\n" +
	"\n" +
	"    vim_free(buf);"

var identLeft = regexp.MustCompile(`\b(?:nv_K_getcmd|do_nv_ident|g_tag_at_cursor)\b`)

// NoIdent leaves `*` and `#` and takes K, CTRL-], g] and the two CTRL-W forms.
func NoIdent(text []byte, w io.Writer) ([]byte, error) {
	blanked := cutil.Blank(text)
	m := regexp.MustCompile(`(?m)^nv_ident\(cmdarg_T \*cap\)\n`).FindIndex(text)
	if m == nil {
		return nil, fmt.Errorf("noident: nv_ident is not defined at file scope")
	}
	o := m[1] + bytes.IndexByte(blanked[m[1]:], '{')
	c := cutil.Match(blanked, o)
	if c < 0 {
		return nil, fmt.Errorf("noident: nv_ident is unbalanced")
	}
	was := bytes.Count(text[o:c], []byte{'\n'})
	if !bytes.Contains(text[o:c], []byte("nv_K_getcmd")) {
		return nil, fmt.Errorf("noident: nv_ident does not look like the one this expects")
	}
	var buf []byte
	buf = append(buf, text[:o]...)
	buf = append(buf, "{\n"...)
	buf = append(buf, identBody...)
	buf = append(buf, "\n}"...)
	text = append(buf, text[c+1:]...)
	fmt.Fprintf(w, "  noident      nv_ident was %d lines and is now the search half\n", was)

	// A ROW IS NEVER DELETED FROM nv_cmds[], IT IS POINTED AT nv_error.
	// nv_cmd_idx[] is a static const array of INDICES INTO nv_cmds[],
	// precomputed and sorted by command character, so deleting two rows shifts
	// every later index while the precomputed table still points at the old
	// positions -- every normal command after them dispatches to the wrong
	// function.
	//
	// The first version of this phase deleted the rows.  It built, it swept
	// clean, it passed the linkage and symbol checks -- and 39 of the 67
	// behaviour cases moved: CTRL-A, joins, macros, marks, multibyte motions,
	// nothing to do with K or tags.
	n, n2 := 0, 0
	var hit bool
	if text, hit = replaceFirst(regexp.MustCompile(
		`(?m)^([ \t]*\{Ctrl_RSB, )nv_ident(, NV_NCW, 0\} ,\n)`),
		text, "${1}nv_error${2}"); hit {
		n = 1
	}
	if text, hit = replaceFirst(regexp.MustCompile(
		`(?m)^([ \t]*\{'K', )nv_ident(, 0, 0\} ,\n)`),
		text, "${1}nv_error${2}"); hit {
		n2 = 1
	}
	if n+n2 != 2 {
		return nil, fmt.Errorf("noident: the CTRL-] and K rows are not where this expects")
	}

	// TWO SPELLINGS, TRIED IN ORDER, as the Python tries them: the first
	// writes the label as `case ]:` with no quotes, which is what an earlier
	// expander produced.
	if text, hit = replaceFirst(regexp.MustCompile(
		`(    case '\*':\n    case '#':\n    case POUND:\n)    case Ctrl_RSB:\n    case \]:\n`),
		text, "${1}"); !hit {
		if text, hit = replaceFirst(regexp.MustCompile(
			`(\n[ \t]*case POUND:\n)[ \t]*case Ctrl_RSB:\n[ \t]*case '\]':\n`),
			text, "${1}"); !hit {
			return nil, fmt.Errorf("noident: nv_g_cmd's tag cases are not where this expects")
		}
	}
	fmt.Fprintln(w, "  noident      K and CTRL-] answer nv_error, and g] leaves nv_g_cmd")

	var err error
	if text, err = cutCounted(text,
		`(?m)^    case '\]':\n[ \t]*case Ctrl_RSB:\n(?:[^\n]*\n)*?`+
			`[ \t]*do_nv_ident\(Ctrl_RSB, NUL\);\n`+
			`[ \t]*postponed_split = 0;\n[ \t]*break;\n\n?`,
		"noident", "do_window's CTRL-W ]", 1); err != nil {
		return nil, err
	}
	if text, err = cutCounted(text,
		`(?m)^[ \t]*case '\]':\n[ \t]*case Ctrl_RSB:\n(?:[^\n]*\n)*?`+
			`[ \t]*do_nv_ident\('g', xchar\);\n`+
			`[ \t]*postponed_split = 0;\n[ \t]*break;\n\n?`,
		"noident", "do_window's CTRL-W g]", 1); err != nil {
		return nil, err
	}
	fmt.Fprintln(w, "  noident      CTRL-W ] and CTRL-W g], which split and then jump")

	fmt.Fprintf(w, "  noident      %d nv_K_getcmd/do_nv_ident mentions left for the sweep\n",
		len(identLeft.FindAll(text, -1)))
	return text, nil
}
