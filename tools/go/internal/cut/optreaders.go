package cut

import (
	"bytes"
	"fmt"
	"io"
	"regexp"

	"slimvim.local/tools/internal/cutil"
)

const cleanPrescan = `    for (i = 1; i < argc; ++i)
    {
        if ( strcasecmp((char *)(argv[i]), (char *)("--clean"))  == 0)
        {
            params.clean = TRUE;
            break;
        }
    }

`

// optreadersLiteral: each must occur exactly once.
var optreadersLiteral = []struct{ what, old, new string }{
	{"-nb: the scan that existed to refuse it",
		"    early_arg_scan(paramp);\n\n", ""},
	{"--clean: the pre-scan of argv at the top of main", cleanPrescan, ""},
	{"--clean: main passing set_init_1 what only --clean could set",
		"set_init_1(paramp->clean);", "set_init_1();"},
	{"--clean: set_init_1 taking it",
		"set_init_1(int clean_arg)", "set_init_1(void)"},
	{"--not-a-term: whether a filter's output counts as redirected",
		"!stdout_isatty && !is_not_a_term_or_gui();", "!stdout_isatty;"},
	{"--not-a-term: clearing the command line on exit",
		"else if (!is_not_a_term())", "else"},
	{"--not-a-term: check_tty's warning", " && !parmp->not_a_term)", ")"},
	{"--not-a-term: \"N files to edit\"", " && !is_not_a_term())", ")"},
	{"-p: equalising the windows it did not make",
		" && parmp->window_layout != WIN_TABS)", ")"},
	{"-h: the pointer to it at the end of every usage error",
		`     fprintf(stderr, "%s", (_("\nMore info with: \"vim -h\"\n"))) ;` + "\n", ""},
}

var optreadersFolds = []struct {
	what, kind, pattern string
	count               int
}{
	{"--not-a-term: \"Reading from stdin\" and restoring the title",
		"always", `^[ \t]*if \(!is_not_a_term\(\)\)$`, 2},
	{"--not-a-term: the cursor to the last line on exit",
		"always", `^[ \t]*if \(!is_not_a_term_or_gui\(\)\)$`, 2},
	{"--clean: emptying 'runtimepath' and 'packpath'",
		"never", `^[ \t]*if \(clean_arg\)$`, 1},
	{"-n: 'updatecount' set to 0",
		"never", `^[ \t]*if \(params\.no_swap_file\)$`, 1},
	{"-p: tab pages instead of windows",
		"never", `^[ \t]*if \(parmp->window_layout == WIN_TABS\)$`, 5},
	{"-p: moving to the next tab page",
		"never", `^[ \t]*else if \(parmp->window_layout == WIN_TABS\)$`, 1},
	{"-p: restoring 'shortmess' after filling the tab pages",
		"never", `^[ \t]*if \(p_shm_save != NULL\)$`, 1},
}

var optreadersDeletions = []struct {
	what, pattern string
	count         int
}{
	{"-p: the p_shm_save local", `(?m)^[ \t]*char_u[ \t]+\*p_shm_save = NULL;\n`, 1},
	{"--not-a-term: the two prototypes",
		`(?m)^static int is_not_a_term(?:_or_gui)?\(void\);\n`, 2},
}

// optreadersAfter is what must be LEFT, counted after every edit.
var optreadersAfter = []struct {
	what, pattern string
	want          int
}{
	{"is_not_a_term", `\bis_not_a_term`, 0},
	{"p_shm_save", `\bp_shm_save\b`, 0},
	{"the clean field outside its declaration", `(?:\.|->)clean\b`, 0},
	{"clean_arg", `\bclean_arg\b`, 0},
	{"not_a_term outside its declaration", `\bnot_a_term\b`, 1},
	{"no_swap_file outside its declaration", `\bno_swap_file\b`, 1},
	{"WIN_TABS outside its enumerator", `\bWIN_TABS\b`, 1},
	{"early_arg_scan outside its definition and prototype", `\bearly_arg_scan\(paramp\)`, 0},
}

// OptReaders removes what read the options a previous phase dropped.
func OptReaders(text []byte, w io.Writer) ([]byte, error) {
	for _, l := range optreadersLiteral {
		n := bytes.Count(text, []byte(l.old))
		if n != 1 {
			return nil, fmt.Errorf("optreaders: %s -- occurs %d times, not once", l.what, n)
		}
		text = bytes.ReplaceAll(text, []byte(l.old), []byte(l.new))
		fmt.Fprintf(w, "  optreaders   %s\n", l.what)
	}

	for _, f := range optreadersFolds {
		var err error
		if f.kind == "always" {
			text, err = cutil.FoldAlways(text, "(?m)"+f.pattern, f.count)
		} else {
			text, err = cutil.FoldNever(text, "(?m)"+f.pattern, f.count)
		}
		if err != nil {
			return nil, fmt.Errorf("optreaders: %s -- %v", f.what, err)
		}
		places := ""
		if f.count > 1 {
			places = fmt.Sprintf(", %d places", f.count)
		}
		fmt.Fprintf(w, "  optreaders   %s%s\n", f.what, places)
	}

	for _, name := range []string{"is_not_a_term", "is_not_a_term_or_gui"} {
		var ok bool
		text, ok = cutil.DeleteDefinition(text, name)
		if !ok {
			return nil, fmt.Errorf("optreaders: %s is not defined at file scope", name)
		}
	}

	for _, d := range optreadersDeletions {
		re := regexp.MustCompile(d.pattern)
		n := len(re.FindAll(text, -1))
		if n != d.count {
			return nil, fmt.Errorf("optreaders: %s -- expected %d, matched %d",
				d.what, d.count, n)
		}
		text = re.ReplaceAll(text, nil)
		fmt.Fprintf(w, "  optreaders   %s\n", d.what)
	}

	for _, a := range optreadersAfter {
		n := len(regexp.MustCompile(a.pattern).FindAll(text, -1))
		if n != a.want {
			return nil, fmt.Errorf("optreaders: %s -- %d left, expected %d", a.what, n, a.want)
		}
	}

	fmt.Fprintln(w, "  optreaders   nothing reads what a dropped option set")
	return text, nil
}
