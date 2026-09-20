package edit

import (
	"io"

	"slimvim.local/tools/internal/cutil"
)

// linesT deletes n whole lines matching the pattern, TOLERATING TRAILING
// WHITESPACE -- `^[ \t]*<pattern>[ \t]*\n`, which is what whim70's own lines()
// spells.  E.Lines does not allow the trailing run, and the difference decides
// whether a line with a stray space at its end is found or silently left.
func (e *E) linesT(pattern string, n int, what string) {
	e.Cut(`(?m)^[ \t]*`+pattern+`[ \t]*\n`, n, what)
}

// Whim70 makes one buffer the invariant: :edit stops opening a second, the
// swap-file dialog goes with everything that armed or answered it, and the
// swap file itself is never opened.
func Whim70(text []byte, w io.Writer) ([]byte, error) {
	e := New("onebuffer", text, w)

	// fname2fnum's body goes entirely: a file mark gets its own buffer now.
	e.Body("fname2fnum", "", "fname2fnum giving a file mark its own buffer")

	e.InFunction("do_ecmd", func(e *E) {
		e.Literal(w70OldOpen, w70NewOpen, ":edit opening a second buffer")
	})
	e.InFunction("do_ecmd", func(e *E) {
		e.Literal(w70OldOldbuf, w70lit2, ":edit deciding the buffer was already loaded")
	})
	// Brace-matched: the body may be any length, which is the point.
	e.InFunction("do_ecmd", func(e *E) {
		e.DropIf(`(?m)^[ \t]*if \(buf != curbuf\)\n[ \t]*\{\n[ \t]*bufref_T[ \t]+save_au_new_curbuf;$`,
			":edit leaving one buffer for another")
	})
	e.InFunction("do_ecmd", func(e *E) {
		e.Literal(w70lit3, w70lit4, "the reload path asking whether the file changed")
	})
	e.deleteDefinition("handle_swap_exists", `handle_swap_exists, which swapped in a buffer on "quit"`)
	e.deleteDefinition("check_swap_exists_action", "check_swap_exists_action, which quit for it")
	e.InFunction("do_ecmd", func(e *E) {
		e.Literal(w70lit5, w70lit6, ":edit arming the swap-file dialog")
	})
	e.InFunction("do_ecmd", func(e *E) {
		e.Literal(w70lit7, "", ":edit answering it")
	})
	e.InFunction("readfile", func(e *E) {
		e.Literal(w70lit8, "", "reading a file abandoning it for a swap file")
	})
	e.InFunction("create_windows", func(e *E) {
		e.Literal(w70lit9, w70lit10, "the startup open arming and answering the dialog")
	})
	e.InFunction("read_stdin", func(e *E) {
		e.Literal(w70lit11, "", "reading stdin arming the dialog")
	})
	e.InFunction("read_stdin", func(e *E) {
		e.Literal(w70lit12, "", "reading stdin answering it")
	})
	e.linesT(`static int[ \t]+swap_exists_action[ \t]*=[ \t]*SEA_NONE[ \t]*;`, 1, "the swap-file action itself")
	e.linesT(`enum \{ SEA_(?:NONE|DIALOG|QUIT) = [0-9]+ \};`, 3, "the SEA_* actions")
	e.InFunction("ml_open", func(e *E) {
		e.linesT(`buf->b_may_swap = false;`, 1, "ml_open clearing b_may_swap")
	})
	// The fold and its report are separate in the phase: cutil.fold_never is
	// called directly and say() follows outside in_function, so the message
	// lands after the edit rather than as part of it.
	e.InFunction("changed", func(e *E) {
		if e.Failed() {
			return
		}
		out, err := cutil.FoldNever(e.Text(), `(?m)^[ \t]*if \(curbuf->b_may_swap\)$`, 1)
		if err != nil {
			e.Refuse("%v", err)
			return
		}
		e.Set(out)
	})
	if !e.Failed() {
		e.say("the first change to a buffer opening a swap file")
	}
	e.linesT(`check_need_swap\(newfile\);`, 2, "the two calls that asked for a swap file")
	e.deleteDefinition("check_need_swap", "check_need_swap, which only reached ml_open_file")
	e.deleteDefinition("ml_open_file", "ml_open_file, whose body was one assignment")
	e.linesT(`bool[ \t]+b_may_swap;`, 1, "the b_may_swap field")
	return e.Done()
}

func init() { register("whim70", Whim70) }
