package edit

import (
	"bytes"
	"io"
)

func init() { register("zero18", Zero18) }

// head is upstream's #ifdef'ed signature with the conditional gone: the name
// sits on a line of its own because there was a directive between it and the
// argument list, and slim's phase 5 took the conditional and left the break.
const zero18Head = "\n    int\nmain\n(int argc, char **argv)\n{\n"

const zero18NewHead = "\n    static int\nvim_main(int argc, char **argv)\n{\n"

// The launcher.  Five lines, and every one of them is what ZERO-PLAN.md 4c
// says the host file will hold: it calls the editor and it does nothing else.
//
// No prototype is written for vim_main -- it is DEFINED above its only call,
// so a declaration would be one the sweep is entitled to delete.
const zero18Launch = "\n" +
	"    int\n" +
	"main(int argc, char **argv)\n" +
	"{\n" +
	"    return vim_main(argc, argv);\n" +
	"}\n"

// Zero18 demotes main() to a static vim_main() and appends a launcher, both
// still in the one file.
func Zero18(text []byte, w io.Writer) ([]byte, error) {
	p := ph{"demote", w}
	linesBefore := p.lines(text)
	runsBefore := p.blankRuns(text)

	// ---- 1. the name is free, and `vim_main2` is not it ------------------
	// C has no prefix collisions, but a reader greps, and so does this file's
	// own machinery.
	if k := p.mentions(text, "vim_main"); k != 0 {
		return nil, p.die("`vim_main` already has %d mentions as a whole word -- the name this phase "+
			"gives the editor is taken", k)
	}
	if k := p.mentions(text, "vim_main2"); k != 2 {
		return nil, p.die("`vim_main2` has %d mentions, expected 2 -- its definition and the one call at "+
			"the bottom of main().  It is upstream's second half of main(), it is NOT the "+
			"name this phase introduces, and pinning it is what keeps a substring grep "+
			"from confusing the two", k)
	}
	if err := p.assertOnce(text, "    static int\nvim_main2(void)\n{\n", "vim_main2()'s definition",
		"it is the function the new vim_main() ends by calling, and it does not move"); err != nil {
		return nil, err
	}
	p.say("`vim_main` is free -- ZERO mentions as a whole word -- and `vim_main2` is the two " +
		"it has always had: upstream's second half of main(), which this phase does not " +
		"touch.  They are different identifiers and C has no prefix collision")

	// ---- 2. main() is where and what this phase was written against ------
	if err := p.assertOnce(text, zero18Head, "main()'s three-line head",
		"the name sits on a line of its own because upstream had an #ifdef between it "+
			"and the argument list; slim's phase 5 took the conditional and left the break"); err != nil {
		return nil, err
	}
	if k := p.mentions(text, "main"); k != 1 {
		return nil, p.die("`main` as a whole word has %d mentions, expected 1 -- the definition below is "+
			"the ONLY place this file writes the bare word.  `main_loop`, `main_errors`, "+
			"`vim_main2` and `domain` are different words and \\b does not match inside "+
			"them", k)
	}
	if !bytes.HasSuffix(text, []byte("    return vim_main2();\n}\n")) {
		return nil, p.die("zero-vim.c does not end with main()'s `return vim_main2();` and its closing " +
			"brace -- CLAUDE.md states that as the shape of this file, and this phase " +
			"appends after it")
	}
	p.say("main() is the last function in the file, its head spelled over THREE lines, and " +
		"`main` as a whole word occurs ONCE in 80,000 lines -- that one line, the name on " +
		"its own.  `main_loop` and `main_errors` are different words")

	// ---- 3. the demotion: one head rewritten, one function appended ------
	text = bytes.Replace(text, []byte(zero18Head), []byte(zero18NewHead), 1)
	text = append(text, []byte(zero18Launch)...)

	// ---- 4. what the file is now -----------------------------------------
	if err := p.assertOnce(text, "    static int\nvim_main(int argc, char **argv)\n{\n", "vim_main()'s head",
		"the editor entry point, static, in the two-line shape every other function here "+
			"uses"); err != nil {
		return nil, err
	}
	if err := p.assertOnce(text, zero18Launch, "the launcher",
		"it is appended once and it is the last thing in the file"); err != nil {
		return nil, err
	}
	if !bytes.HasSuffix(text, []byte(zero18Launch)) {
		return nil, p.die("the launcher is not the last thing in the file")
	}
	if k := p.mentions(text, "vim_main"); k != 2 {
		return nil, p.die("`vim_main` has %d mentions, expected 2 -- its definition and the one call from "+
			"main().  A third would be a prototype, and a prototype for a function defined "+
			"above its only call is redundant", k)
	}
	if p.mentions(text, "vim_main2") != 2 {
		return nil, p.die("`vim_main2` moved, and this phase does not touch it")
	}
	if k := p.mentions(text, "main"); k != 1 {
		return nil, p.die("`main` as a whole word has %d mentions after the demotion, expected 1 -- the "+
			"launcher's head and nothing else.  `vim_main` and `vim_main2` are different "+
			"words", k)
	}
	if bytes.Contains(text, []byte("main\n(int argc")) {
		return nil, p.die("the three-line head survives somewhere")
	}
	if r := p.blankRuns(text); r != runsBefore {
		return nil, p.die("the demotion left %d runs of two blank lines where there were %d", r, runsBefore)
	}
	if n := p.lines(text); n != linesBefore+5 {
		return nil, p.die("the file gained %d lines, expected 5 -- the three-line head became two (-1) "+
			"and the launcher is six (+6)", n-linesBefore)
	}
	p.say("main() is now `static int vim_main(int argc, char **argv)` with the same body, and " +
		"the last six lines of the file are a launcher whose whole content is `return " +
		"vim_main(argc, argv);`.  +5 lines: the fossil head lost one, the launcher added six")
	return text, nil
}
