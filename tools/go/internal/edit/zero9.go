package edit

import (
	"io"
	"regexp"
	"strings"

	"slimvim.local/tools/internal/cutil"
)

func init() { register("zero9", Zero9) }

// z9Before is the file the four anchors were counted against.
var z9Before = map[string]int{
	"readfile": 5, "read_buffer": 17, "read_stdin": 23, "read_fifo": 9,
	"check_readonly": 4, "msg_scrolled_ign": 6, "filemess": 11, "read_cmd_fd": 12,
}

// z9After is what the sweep is handed, as a count rather than as trust.
var z9After = map[string]int{"readfile": 3, "read_buffer": 15, "read_stdin": 20, "read_fifo": 4}

var z9Assign = regexp.MustCompile(`\bretval\b\s*=[^=]`)

// Zero9 takes the machinery under every way to name a file: readfile(),
// read_buffer() and the message layer that reported what had been read.
//
// IT IS THE ONE ZERO PHASE NO RECORDING CAN SEE, and its declared delta is
// nothing at all: readfile() was already unreachable when it ran, phases 5 to 8
// having taken every way to name a file.
func Zero9(text []byte, w io.Writer) ([]byte, error) {
	p := ph{"nobyte", w}
	var err error

	mentions := func(t []byte, name string) int {
		return len(regexp.MustCompile(`\b`+name+`\b`).FindAll(t, -1))
	}
	within := func(t []byte, fn, old, new, what string, n int) ([]byte, error) {
		a, z, ok := cutil.FindDefinition(t, cutil.Blank(t), fn)
		if !ok {
			return nil, p.die("%s is not defined", fn)
		}
		body := string(t[a:z])
		k := strings.Count(body, old)
		if k != n {
			return nil, p.die("%s -- %s occurs %d times in %s, expected %d",
				what, cutil.PyRepr(zHead(old, 60)), k, fn, n)
		}
		p.say(what)
		return []byte(string(t[:a]) + strings.ReplaceAll(body, old, new) + string(t[z:])), nil
	}

	// ---- 0. the shape the anchors below were counted on -----------------------
	// open_buffer AT EXACTLY 5 IS WHY THIS PHASE NEEDS SWEPT TEXT.
	if k := mentions(text, "open_buffer"); k != 5 {
		return nil, p.die("open_buffer has %d mentions, expected 5 -- the definition and four callers, "+
			"every one of them `open_buffer(FALSE, NULL, 0)`.  On the text phase 8's "+
			"EDIT leaves there are six: do_ecmd is still there to make "+
			"`(void)open_buffer(FALSE, eap, readfile_flags);`, which anchor 4 would not "+
			"rewrite.  This phase needs swept text", k)
	}
	for _, name := range sortedKeys2(z9Before) {
		if k := mentions(text, name); k != z9Before[name] {
			return nil, p.die("%s has %d mentions, expected %d -- the anchors below were counted "+
				"against a different file", name, k, z9Before[name])
		}
	}
	p.say("open_buffer 5, readfile 5, read_buffer 17, read_stdin 23 -- the file the four " +
		"anchors were counted against")

	// ---- 1. the two arms, which hold every call into the read path ------------
	if text, err = within(text, "open_buffer", z9Arms, "",
		"open_buffer's two read arms, 36 lines: both calls to readfile(), both "+
			"to read_buffer(), and the fifo test between them", 1); err != nil {
		return nil, err
	}
	// ---- 2. read_fifo, written nowhere now ------------------------------------
	if text, err = within(text, "open_buffer", z9lit1, "",
		"the read_fifo local: anchor 1 was its only writer", 1); err != nil {
		return nil, err
	}
	// ---- 3. the unchanged() test, where its second reader was -----------------
	if text, err = within(text, "open_buffer", z9lit2, z9lit3,
		"the unchanged() arm: !read_stdin and !read_fifo were both constantly true", 1); err != nil {
		return nil, err
	}
	// ---- 4. the signature, and the four callers -------------------------------
	if text, err = within(text, "open_buffer", z9lit4, z9lit5,
		"open_buffer(void): read_stdin, eap and flags_arg are read by nothing "+
			"now, and there is no prototype to follow", 1); err != nil {
		return nil, err
	}
	if text, err = within(text, "open_buffer", z9lit6, "",
		"the flags local, which only the deleted arms passed on", 1); err != nil {
		return nil, err
	}
	if k := strings.Count(string(text), "open_buffer(FALSE, NULL, 0)"); k != 4 {
		return nil, p.die("open_buffer is called %d times as `open_buffer(FALSE, NULL, 0)`, expected "+
			"%d -- every caller already passes FALSE, NULL and 0, and a caller that "+
			"does not is one this fold would change", k, 4)
	}
	text = []byte(strings.ReplaceAll(string(text), "open_buffer(FALSE, NULL, 0)", "open_buffer()"))
	p.say("the four call sites -- enter_buffer, ml_append_flags, ml_replace_len and " +
		"create_windows -- every one of which passed FALSE, NULL, 0")

	// ---- 5. what is left, and what is deliberately left -----------------------
	a, z, ok := cutil.FindDefinition(text, cutil.Blank(text), "open_buffer")
	if !ok {
		return nil, p.die("open_buffer no longer parses as a definition")
	}
	body := text[a:z]
	for _, gone := range []string{"read_stdin", "read_fifo", "eap", "flags", "readfile", "read_buffer"} {
		if mentions(body, gone) > 0 {
			return nil, p.die("%s is still named inside open_buffer", gone)
		}
	}
	assigns := len(z9Assign.FindAll(body, -1))
	if assigns != 1 || mentions(body, "retval") != 5 {
		return nil, p.die("retval is assigned %d times in open_buffer and mentioned %d: this phase "+
			"leaves exactly one assignment, the initialiser, and 5 mentions",
			assigns, mentions(body, "retval"))
	}
	p.sayf("open_buffer is %d lines and calls nothing that reads: retval is OK from its "+
		"initialiser to its return, so `if (retval != OK) return retval;` is dead and "+
		"the two ml_ guards can never hold -- left for a later tidy, not folded here",
		strings.Count(string(body), "\n"))

	for _, name := range sortedKeys2(z9After) {
		if k := mentions(text, name); k != z9After[name] {
			return nil, p.die("%s has %d mentions after the cut, expected %d", name, k, z9After[name])
		}
	}
	p.say("readfile 5 -> 3 and read_buffer 17 -> 15, and the survivors are not calls: a " +
		"prototype, two definitions and fourteen mentions of readfile's own local of " +
		"the same name.  read_buffer and fix_help_buffer are the two entry points the " +
		"sweep starts from, and they are exactly the two -Wunused-function warnings " +
		"this text produces")
	return text, nil
}
