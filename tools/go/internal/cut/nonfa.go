package cut

import (
	"bytes"
	"fmt"
	"io"
)

// The literals are generated from the Python module's own constants, imported
// rather than scraped: they are non-raw triple-quoted strings, so `\\\\%#=`
// in the source is `\\%#=` in the value and a regex over the text would carry
// the wrong one into the C.
const nfaOldCompile = "    regexp_engine = p_re;\n" +
	"\n" +
	"    if ( strncmp((char *)(expr), (char *)(\"\\\\%#=\"), (4))  == 0)\n" +
	""

const nfaNewCompile = "    rex.reg_buf = curbuf;\n" +
	"\n" +
	"    prog = bt_regengine.regcomp(expr, re_flags);\n" +
	"\n" +
	"    if (prog != NULL)\n" +
	"    {\n" +
	"        prog->re_engine = BACKTRACKING_ENGINE;\n" +
	"        prog->re_flags  = re_flags;\n" +
	"    }\n" +
	"\n" +
	"    return prog;\n" +
	"}\n" +
	""

const nfaIsland = "static regengine_T nfa_regengine =\n" +
	"{\n" +
	"    nfa_regcomp,\n" +
	"    nfa_regfree,\n" +
	"    nfa_regexec_nl,\n" +
	"    nfa_regexec_multi\n" +
	"};\n" +
	"\n" +
	""

const nfaBackref = "    prog->engine = &nfa_regengine;\n" +
	""

const nfaMagic = "    if (prog->engine == &nfa_regengine)\n" +
	"    {\n" +
	"        return FALSE;\n" +
	"    }\n" +
	"\n" +
	""

const nfaTail = "\n    return prog;\n}\n"

// NoNfa leaves the backtracking engine as the only one.
func NoNfa(text []byte, w io.Writer) ([]byte, error) {
	// The whole body of vim_regcomp from the engine choice to its closing brace.
	start := bytes.Index(text, []byte(nfaOldCompile))
	if start < 0 {
		return nil, fmt.Errorf("nonfa: vim_regcomp does not begin the way this expects -- " +
			"it has moved, and replacing a body by guesswork is how an editor ends up " +
			"with no regexp engine at all")
	}
	rel := bytes.Index(text[start:], []byte(nfaTail))
	if rel < 0 {
		return nil, fmt.Errorf("nonfa: vim_regcomp does not end the way this expects")
	}
	end := start + rel + len(nfaTail)
	var buf []byte
	buf = append(buf, text[:start]...)
	buf = append(buf, nfaNewCompile...)
	text = append(buf, text[end:]...)

	if !bytes.Contains(text, []byte(nfaMagic)) {
		return nil, fmt.Errorf("nonfa: prog_magic_wrong no longer tests for the NFA engine")
	}
	text = bytes.Replace(text, []byte(nfaMagic), nil, 1)

	// The island: BOTH HALVES OR NEITHER.  Removing the struct alone leaves
	// nfa_regcomp assigning the address of something that no longer exists.
	for _, p := range []struct{ part, what string }{
		{nfaIsland, "the nfa_regengine definition"},
		{nfaBackref, "nfa_regcomp's back-reference to it"},
	} {
		if !bytes.Contains(text, []byte(p.part)) {
			return nil, fmt.Errorf("nonfa: cannot find %s, and cutting one half without "+
				"the other does not compile", p.what)
		}
		text = bytes.Replace(text, []byte(p.part), nil, 1)
	}

	fmt.Fprintf(w, "  nonfa        vim_regcomp compiles with bt only; prog_magic_wrong "+
		"stops asking; %d nfa_regengine mentions left for the sweep\n",
		bytes.Count(text, []byte("nfa_regengine")))
	return text, nil
}
