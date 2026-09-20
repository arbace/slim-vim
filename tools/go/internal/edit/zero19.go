package edit

import (
	"bytes"
	"io"
	"regexp"
)

func init() { register("zero19", Zero19) }

var zero19ExitCall = regexp.MustCompile(`(?m)^\s*exit\(`)

// zero19Old is phase 18's five-line launcher; zero19New is the twenty-line one
// that lands on __builtin_setjmp and RETURNS the status.
const zero19Old = "\n    int\nmain(int argc, char **argv)\n{\n" +
	"    return vim_main(argc, argv);\n}\n"

const zero19New = "\nstatic void *host_jump[5];\n" +
	"static int host_code;\n" +
	"\n" +
	"    static void\n" +
	"host_exit(int r)\n" +
	"{\n" +
	"    host_code = r;\n" +
	"    __builtin_longjmp(host_jump, 1);\n" +
	"}\n" +
	"\n" +
	"    int\n" +
	"main(int argc, char **argv)\n" +
	"{\n" +
	"    if (__builtin_setjmp(host_jump) != 0)\n" +
	"    {\n" +
	"        return host_code;\n" +
	"    }\n" +
	"    return vim_main(argc, argv, host_exit);\n" +
	"}\n"

// Zero19 takes the core's last way of stopping the process: mch_exit()'s
// `exit(r);` becomes a call through a pointer the launcher installs.
//
// __builtin_setjmp rather than <setjmp.h> because this phase adds no header,
// and the directive count is asserted at the end to say so.
func Zero19(text []byte, w io.Writer) ([]byte, error) {
	p := ph{"hostexit", w}
	linesBefore := p.lines(text)
	runsBefore := p.blankRuns(text)
	var err error

	// ---- 1. there is exactly one way out, and phase 17 is why ------------
	// The counting trap first: `exit` is five words and one call.
	for _, f := range []struct{ s, why string }{
		{"                char *ms = _(\"Type  :qa!  and press <Enter> to abandon all " +
			"changes and exit Vim\");\n", "a string literal"},
		{"                    msg(_(\"Type  :qa  and press <Enter> to exit Vim\"));\n",
			"a string literal"},
		{"    exit(r);\n", "mch_exit's, and the ONLY exit() call in the file"},
		{"                        goto exit;\n", "a GOTO, in vim_regsub_both()"},
		{"exit:\n", "a LABEL, in vim_regsub_both()"},
	} {
		if err = p.assertOnce(text, f.s, "`"+trimSpace(f.s)+"`", f.why); err != nil {
			return nil, err
		}
	}
	if k := p.mentions(text, "exit"); k != 5 {
		return nil, p.die("`exit` as a word has %d mentions, expected the 5 named above", k)
	}
	if p.mentions(text, "_exit") != 0 {
		return nil, p.die("`_exit` is back, and phase 17 took it to zero")
	}
	if k := len(zero19ExitCall.FindAll(text, -1)); k != 1 {
		return nil, p.die("%d statements begin with `exit(`, expected exactly 1 -- phase 17 left "+
			"mch_exit's `exit(r);` as the file's only one, which is what makes this phase "+
			"ONE line in ONE function", k)
	}
	for _, name := range []string{"vim_host_exit", "host_exit", "host_jump", "host_code"} {
		if k := p.mentions(text, name); k != 0 {
			return nil, p.die("`%s` already has %d mentions -- a name this phase introduces is taken",
				name, k)
		}
	}
	p.say("`exit` is FIVE mentions and exactly ONE call -- two string literals, a `goto " +
		"exit;` and its `exit:` label in vim_regsub_both(), and mch_exit's `exit(r);`.  " +
		"Phase 17 is what left one call site, and it is why this phase is one line in one " +
		"function")

	// ---- 2. the pointer, beside the function that is its only reader -----
	// A file-scope OBJECT, not a prototype: objects do not inherit linkage
	// from a declaration, so the keyword is written here and is the whole
	// reason `nm --extern-only` still prints one name.
	text, err = p.swapOnce(text,
		"    static void\nmch_exit(int r)\n{\n",
		"static void (*vim_host_exit)(int);\n\n    static void\nmch_exit(int r)\n{\n",
		"mch_exit()'s definition",
		"the pointer is declared immediately above its one reader, which is the only "+
			"function in the file that has ever ended the process")
	if err != nil {
		return nil, err
	}

	// ---- 3. the one line -------------------------------------------------
	text, err = p.swapOnce(text,
		"    ml_close_all(TRUE);\n\n    exit(r);\n}\n",
		"    ml_close_all(TRUE);\n\n    vim_host_exit(r);\n}\n",
		"mch_exit()'s tail",
		"everything mch_exit does before it is unchanged -- the terminal is restored, the "+
			"screen scrolled, the memfile closed -- and only the last statement moves")
	if err != nil {
		return nil, err
	}

	// ---- 4. the host installs it, through a parameter and not a global ---
	text, err = p.swapOnce(text,
		"    static int\nvim_main(int argc, char **argv)\n{\n\n",
		"    static int\nvim_main(int argc, char **argv, void (*exit_fn)(int))\n{\n\n"+
			"    vim_host_exit = exit_fn;\n\n",
		"vim_main()'s head, which phase 18 made",
		"the pointer is installed by the caller and is not a global the host assigns, "+
			"because \"nothing is global but main()\" is still the invariant")
	if err != nil {
		return nil, err
	}

	// ---- 5. the launcher -------------------------------------------------
	if !bytes.HasSuffix(text, []byte(zero19Old)) {
		return nil, p.die("zero-vim.c does not end with phase 18's five-line launcher, so this is not " +
			"the file this phase was written against")
	}
	text = append(text[:len(text)-len(zero19Old)], []byte(zero19New)...)

	// ---- 6. what the file is now -----------------------------------------
	if k := p.mentions(text, "exit"); k != 4 {
		return nil, p.die("`exit` as a word has %d mentions after the swap, expected 4 -- the two string "+
			"literals and the goto with its label", k)
	}
	if len(zero19ExitCall.FindAll(text, -1)) != 0 {
		return nil, p.die("a statement still begins with `exit(`")
	}
	for _, inv := range []struct {
		name string
		want int
		why  string
	}{
		{"vim_host_exit", 3, "its declaration, the one call in mch_exit and the one " +
			"assignment in vim_main"},
		{"host_exit", 2, "the launcher's definition and the argument main() passes.  " +
			"`vim_host_exit` is a DIFFERENT word and \\b does not match " +
			"inside it, which is why these two counts are separate"},
		{"host_jump", 3, "its declaration, the longjmp and the setjmp"},
		{"host_code", 3, "its declaration, the write in host_exit and the return in " +
			"main"},
		{"vim_main", 2, "its definition and the one call from the launcher"},
		{"main", 1, "the launcher's head, still the only bare `main` in the file"},
	} {
		if k := p.mentions(text, inv.name); k != inv.want {
			return nil, p.die("`%s` has %d mentions, expected %d -- %s", inv.name, k, inv.want, inv.why)
		}
	}
	if err = p.assertOnce(text, "    vim_host_exit(r);\n", "the one call through the pointer",
		"mch_exit is the only function in the file that ends the editor"); err != nil {
		return nil, err
	}
	if err = p.assertOnce(text, "    vim_host_exit = exit_fn;\n", "the one installation",
		"vim_main is the only function that is handed the host callback"); err != nil {
		return nil, err
	}
	if !bytes.HasSuffix(text, []byte(zero19New)) {
		return nil, p.die("the launcher is not the last thing in the file")
	}
	if r := p.blankRuns(text); r != runsBefore {
		return nil, p.die("the edit left %d runs of two blank lines where there were %d", r, runsBefore)
	}
	if n := p.lines(text); n != linesBefore+18 {
		return nil, p.die("the file gained %d lines, expected 18 -- two for the pointer and its blank "+
			"line, two for the installation and its blank line, and fourteen for the "+
			"launcher growing from six lines to twenty", n-linesBefore)
	}
	n := 0
	for _, l := range bytes.Split(text, []byte{'\n'}) {
		if bytes.HasPrefix(l, []byte("#")) {
			n++
		}
	}
	if n != 12 {
		return nil, p.die("the directive count moved, and the whole reason for __builtin_setjmp rather " +
			"than <setjmp.h> is that this phase adds no header")
	}
	p.say("mch_exit ends `vim_host_exit(r);`, vim_main takes the callback as its third " +
		"parameter and installs it, and the launcher is twenty lines that land on " +
		"__builtin_setjmp and RETURN the status.  `exit` is FOUR mentions and NONE is a " +
		"call; the twelve #includes are untouched")
	return text, nil
}

// trimSpace is Python's str.strip() for the one place these blocks use it: the
// `what` of an anchor is the anchor's own text with its indentation and
// newline taken off.
func trimSpace(s string) string { return string(bytes.TrimSpace([]byte(s))) }
