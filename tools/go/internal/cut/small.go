package cut

import (
	"bytes"
	"fmt"
	"io"
	"regexp"
	"strings"

	"slimvim.local/tools/internal/cutil"
)

// NoIntro points :intro and :version at ex_ni and cuts the splash screen.
//
// Both counts are asserted, not hoped for: one row each, and exactly TWO
// maybe_intro_message() call sites.  A different number means the redraw path
// has moved under the phase, and a partial cut would leave one splash behind.
func NoIntro(text []byte, w io.Writer) ([]byte, error) {
	for _, name := range []string{"intro", "version"} {
		pat := regexp.MustCompile(fmt.Sprintf(
			`(\[CMD_%s\] = \{\(char_u \*\)"%s", sizeof\("%s"\) - 1, )(\w+)`,
			name, name, name))
		locs := pat.FindAllSubmatchIndex(text, -1)
		if len(locs) != 1 {
			return nil, fmt.Errorf("nointro: expected one row for :%s, matched %d",
				name, len(locs))
		}
		l := locs[0]
		var buf []byte
		buf = append(buf, text[:l[3]]...)
		buf = append(buf, "ex_ni"...)
		buf = append(buf, text[l[1]:]...)
		text = buf
	}

	splash := regexp.MustCompile(`(?m)^[ \t]*maybe_intro_message\(\);\n`)
	n := len(splash.FindAll(text, -1))
	if n != 2 {
		return nil, fmt.Errorf("nointro: expected two splash call sites, removed %d -- "+
			"the redraw path has moved under this phase", n)
	}
	text = splash.ReplaceAll(text, nil)
	fmt.Fprintf(w, "  nointro      :intro and :version to ex_ni, %d splash call sites cut\n", n)
	return text, nil
}

// noargv0Required is every option that must still select the mode argv[0]
// used to.
var noargv0Required = []struct{ opt, proof string }{
	{"Z", "restricted = TRUE;"},
	{"R", "readonlymode = TRUE;"},
	{"y", "evim_mode = TRUE;"},
	{"e", "exmode_active = EXMODE_NORMAL;"},
	{"E", "exmode_active = EXMODE_VIM;"},
}

// NoArgv0 removes the editor's sensitivity to its own name.
//
// It first proves every mode argv[0] could select is still reachable by an
// OPTION.  Without that the cut would REMOVE capability rather than relocate
// it, which is a different phase and a different declaration.
func NoArgv0(text []byte, w io.Writer) ([]byte, error) {
	var missing []string
	for _, r := range noargv0Required {
		if !bytes.Contains(text, []byte(r.proof)) {
			missing = append(missing, "-"+r.opt)
		}
	}
	if len(missing) > 0 {
		return nil, fmt.Errorf("noargv0: these options no longer select their mode, so "+
			"dropping the name sensitivity would REMOVE capability rather than relocate "+
			"it: %s", strings.Join(missing, ", "))
	}
	pat := regexp.MustCompile(`(?m)^[ \t]*parse_command_name\(&params\);\n`)
	n := len(pat.FindAll(text, -1))
	if n != 1 {
		return nil, fmt.Errorf("noargv0: expected exactly one call to parse_command_name, "+
			"removed %d -- main() has moved under this phase", n)
	}
	text = pat.ReplaceAll(text, nil)
	fmt.Fprintf(w, "  argv0        name sensitivity gone; %d options still select every "+
		"mode it could\n", len(noargv0Required))
	return text, nil
}

// NoGlob replaces gen_expand_wildcards' body with one that treats every
// pattern as a name.
//
// The extent is found by BRACE MATCHING from the definition's head, because
// replacing a function by guesswork is how an editor stops opening files.
func NoGlob(text []byte, w io.Writer) ([]byte, error) {
	blanked := cutil.Blank(text)
	head := regexp.MustCompile(`(?m)^gen_expand_wildcards\([^\n]*\n`)
	m := head.FindIndex(text)
	if m == nil {
		return nil, fmt.Errorf("noglob: gen_expand_wildcards is not defined at file scope " +
			"any more, and replacing a function by guesswork is how an editor stops " +
			"opening files")
	}
	rel := bytes.IndexByte(blanked[m[1]:], '{')
	if rel < 0 {
		return nil, fmt.Errorf("noglob: gen_expand_wildcards is unbalanced")
	}
	opening := m[1] + rel
	close := cutil.Match(blanked, opening)
	if close < 0 {
		return nil, fmt.Errorf("noglob: gen_expand_wildcards is unbalanced")
	}
	was := bytes.Count(text[opening:close], []byte{'\n'})
	var buf []byte
	buf = append(buf, text[:opening]...)
	buf = append(buf, "{\n    return save_patterns(num_pat, pat, num_file, file);\n}"...)
	buf = append(buf, text[close+1:]...)
	fmt.Fprintf(w, "  noglob       gen_expand_wildcards was %d lines, is now one; every "+
		"pattern names a file\n", was)
	return buf, nil
}

const equiOld = `                                c_class = get_equi_class(&regparse);
                                if (c_class != 0)
                                {
                                    reg_equi_class(c_class);
                                }
                                else if ((c_class = get_coll_element(&regparse)) != 0)
`

const equiNew = `                                if ((c_class = get_coll_element(&regparse)) != 0)
`

var equiMentions = regexp.MustCompile(`\b(?:reg_equi_class|get_equi_class)\b`)

// NoEquiClass makes [= in a bracket expression no longer an equivalence
// class.
//
// Both edits are exact text, which is a dependency on spelling and is
// deliberate here: the bracket parser is a shape a regex would match in more
// places than it should.
func NoEquiClass(text []byte, w io.Writer) ([]byte, error) {
	if !bytes.Contains(text, []byte(equiOld)) {
		return nil, fmt.Errorf("noequiclass: the bracket parser is not where this expects")
	}
	text = bytes.Replace(text, []byte(equiOld), []byte(equiNew), 1)
	fmt.Fprintln(w, "  noequiclass  [= in a bracket expression is no longer an "+
		"equivalence class")

	skip := regexp.MustCompile(
		`get_char_class\(&p\) == CLASS_NONE && get_equi_class\(&p\) == 0 && `)
	locs := skip.FindAllIndex(text, -1)
	if len(locs) < 1 {
		return nil, fmt.Errorf("noequiclass: skip_regexp's scan is not where this expects")
	}
	l := locs[0]
	var buf []byte
	buf = append(buf, text[:l[0]]...)
	buf = append(buf, "get_char_class(&p) == CLASS_NONE && "...)
	buf = append(buf, text[l[1]:]...)
	text = buf
	fmt.Fprintln(w, "  noequiclass  skip_regexp stops asking the same question")
	fmt.Fprintf(w, "  noequiclass  %d mentions left for the sweep\n",
		len(equiMentions.FindAll(text, -1)))
	return text, nil
}
