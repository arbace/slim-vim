package edit

import (
	"fmt"
	"io"
	"regexp"

	"slimvim.local/tools/internal/cutil"
)

var (
	noswapModifier = regexp.MustCompile(`(?m)^[ \t]*case 'n':\n[ \t]*if \(!checkforcmd_noparen\(&eap->cmd, "noswapfile", 3\)\)\n[ \t]*\{\n[ \t]*break;\n[ \t]*\}\n[ \t]*cmod->cmod_flags \|= CMOD_NOSWAPFILE;\n[ \t]*continue;\n\n`)
	noswapComplete = regexp.MustCompile(`(?m)^[ \t]*case CMD_noswapfile:\n`)
	noswapTest     = `(?m)^[ \t]*if \(cmdmod\.cmod_flags & CMOD_NOSWAPFILE\)$`
	cmodNoSwapFile = regexp.MustCompile(`\bCMOD_NOSWAPFILE\b`)
)

// inFunction applies edit to one file-scope definition's body and splices it
// back, which is what the heredoc's in_function() did.
func inFunction(text []byte, name string, edit func([]byte) ([]byte, error)) ([]byte, error) {
	a, z, ok := cutil.FindDefinition(text, cutil.Blank(text), name)
	if !ok {
		return nil, fmt.Errorf("%s is not defined at file scope", name)
	}
	body, err := edit(text[a:z])
	if err != nil {
		return nil, err
	}
	out := append([]byte{}, text[:a]...)
	out = append(out, body...)
	return append(out, text[z:]...), nil
}

// cutOnce deletes the pattern's single match, refusing on any other count.
func cutOnce(re *regexp.Regexp, what string) func([]byte) ([]byte, error) {
	return func(s []byte) ([]byte, error) {
		if n := len(re.FindAll(s, -1)); n != 1 {
			return nil, fmt.Errorf("whim48: %s -- matched %d times", what, n)
		}
		return re.ReplaceAll(s, nil), nil
	}
}

// Whim48 takes the :noswapfile modifier and everything that reads it.
func Whim48(text []byte, w io.Writer) ([]byte, error) {
	steps := []struct {
		fn, what string
		re       *regexp.Regexp
	}{
		{"parse_command_modifiers", "the :noswapfile modifier", noswapModifier},
		{"set_context_by_cmdname", "completion for :noswapfile", noswapComplete},
	}
	var err error
	for _, s := range steps {
		if text, err = inFunction(text, s.fn, cutOnce(s.re, s.what)); err != nil {
			return nil, err
		}
		fmt.Fprintf(w, "  noswapfile   %s\n", s.what)
	}

	if text, err = inFunction(text, "ml_open", func(s []byte) ([]byte, error) {
		return cutil.DropIf(s, noswapTest, 1)
	}); err != nil {
		return nil, err
	}
	fmt.Fprintln(w, "  noswapfile   ml_open asking for it")

	if text, err = inFunction(text, "buf_copy_options", func(s []byte) ([]byte, error) {
		return cutil.FoldNever(s, noswapTest, 1)
	}); err != nil {
		return nil, err
	}
	fmt.Fprintln(w, "  noswapfile   buf_copy_options asking for it")

	// The enumerator is the only mention that may survive: anything else is a
	// reader this phase did not find, and shipping it would be the phase
	// half-done.
	if n := len(cmodNoSwapFile.FindAll(text, -1)); n != 1 {
		return nil, fmt.Errorf("whim48: CMOD_NOSWAPFILE outside its enumerator -- %d mentions, expected 1", n)
	}
	return text, nil
}

func init() { register("whim48", Whim48) }
