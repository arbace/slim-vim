package cut

import (
	"bytes"
	"fmt"
	"io"
	"regexp"
	"strings"

	"slimvim.local/tools/internal/cutil"
)

var nolocaleEdits = []struct {
	what, pat, repl string
	want            int
}{
	{"the setlocale at startup", `(?m)^[ \t]*init_locale\(\);\n\n?`, "", 1},
	// NOT a deletion.  set_init_default_encoding() did three things: ask the
	// locale, re-initialise the multibyte layer for whatever it answered, and
	// write that back as the option's default.  Only the first is locale.  The
	// second is load-bearing and invisible: p_enc is set from the option
	// table's default, and nothing acts on it until mb_init() runs.  Delete
	// the call outright and 'encoding' reports utf-8 while enc_utf8 is still
	// FALSE -- the editor says UTF-8 and behaves like latin1, which is worse
	// than either, and which five multibyte behaviour cases caught.
	{"deriving 'encoding' from the locale, keeping the mbyte init it also did",
		`(?m)^([ \t]*)set_init_default_encoding\(\);$`, "${1}(void)mb_init();", 1},
	{"'encoding' defaults to utf-8 instead of latin1",
		`(?m)(\{"encoding",[^\n]*\n[^\n]*\n[ \t]*\{\(char_u \*\) )"latin1"`, `${1}"utf-8"`, 1},
	{"locale-aware collation in :sort",
		`(?m)[ \t]*if \(sort_lc\)\n[ \t]*\{\n[ \t]*return strcoll\([^\n]*\n[ \t]*\}\n\n?`, "", 1},
	{"the $LANG-gated maintainer line in :messages",
		`(?m)[ \t]*s =  \(char_u \*\)getenv\(\(char \*\)\(\(char_u \*\)"LANG"\)\) ;\n` +
			`[ \t]*if \(s != NULL && \*s != NUL\)\n[ \t]*\{\n[ \t]*msg_attr\([^\n]*\n[ \t]*\}\n`, "", 1},
	{"the :language completion case",
		`(?m)[ \t]*case CMD_language:\n[ \t]*return set_context_in_lang_cmd\(xp, arg\);\n`, "", 1},
	{"the two locale rows of the completion dispatch table",
		`(?m)[ \t]*\{EXPAND_LANGUAGE, get_lang_arg, TRUE, FALSE\},\n` +
			`[ \t]*\{EXPAND_LOCALES, get_locales, TRUE, FALSE\},\n`, "", 1},
	{"-complete=locale as a name :command accepts",
		`(?m)[ \t]*\{\(EXPAND_LOCALES\), \{\(\(char_u \*\)"locale"\),[^\n]*\n`, "", 1},
}

// dropDbcsConversion is the one that kept `setlocale` alive after everything
// else had gone, and the one that cannot be done with a regex.
//
// mb_init() asks the locale what a DBCS terminal is speaking so it can convert
// messages into it; the block is guarded by `if (enc_dbcs)`, which made it easy
// to miss and impossible to reach for any encoding this build has.
//
// A lazy `(?:[^\n]*\n)*?\}` stops at the FIRST line that is just a brace, which
// here is the inner `if (p == NULL || ...)`'s -- leaving `vim_free(p);` and a
// stray `}` at file scope.  gcc reports that four hundred lines away as "data
// definition has no type or storage class".  Match braces.
func dropDbcsConversion(text []byte) ([]byte, error) {
	i := bytes.Index(text, []byte("    vimconv.vc_type = CONV_NONE;\n"))
	if i < 0 {
		return nil, fmt.Errorf("nolocale: mb_init no longer sets up a conversion here")
	}
	blanked := cutil.Blank(text)
	at := i + bytes.Index(text[i:], []byte("if (enc_dbcs)"))
	opening := at + bytes.IndexByte(blanked[at:], '{')
	closing := cutil.Match(blanked, opening)
	if closing < 0 {
		return nil, fmt.Errorf("nolocale: the enc_dbcs block is unbalanced")
	}
	end := closing + 1
	for end < len(text) && (text[end] == ' ' || text[end] == '\t' || text[end] == '\n') {
		end++
	}
	// Only the block.  `vimconv` and its CONV_NONE initialiser STAY: mb_init
	// tests vimconv.vc_type again two hundred lines further down, and taking
	// the declaration on the strength of one visible use is how a phase turns
	// into a compile error four hundred lines from the edit.
	start := i + bytes.Index(text[i:], []byte("    if (enc_dbcs)"))
	out := make([]byte, 0, len(text))
	out = append(out, text[:start]...)
	return append(out, text[end:]...), nil
}

// NoLocale stops the editor asking the locale anything.
func NoLocale(text []byte, w io.Writer) ([]byte, error) {
	for _, e := range nolocaleEdits {
		re := regexp.MustCompile(e.pat)
		n := len(re.FindAll(text, -1))
		if n != e.want {
			return nil, fmt.Errorf("nolocale: %s -- expected %d, matched %d", e.what, e.want, n)
		}
		text = re.ReplaceAll(text, []byte(e.repl))
		fmt.Fprintf(w, "  nolocale     %s\n", e.what)
	}

	text, err := dropDbcsConversion(text)
	if err != nil {
		return nil, err
	}
	fmt.Fprintln(w, "  nolocale     the DBCS locale conversion in mb_init, and its local")

	parts := strings.SplitN(string(text), `{"encoding"`, 2)
	if len(parts) > 1 {
		head := parts[1]
		if len(head) > 400 {
			head = head[:400]
		}
		if strings.Contains(head, `"latin1"`) {
			return nil, fmt.Errorf("nolocale: 'encoding' still defaults to latin1, which " +
				"would make this a latin1 editor the moment the locale stops being asked")
		}
	}

	fmt.Fprintf(w, "  nolocale     %d setlocale calls left for the sweep\n",
		bytes.Count(text, []byte("setlocale(")))
	return text, nil
}
