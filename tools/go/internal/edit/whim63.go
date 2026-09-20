package edit

import (
	"bytes"
	"fmt"
	"io"
	"regexp"
)

var jumplistAppend = regexp.MustCompile(`(?m)^[ \t]*if \(\+\+curwin->w_jumplistlen > JUMPLISTSIZE\)$`)

// Whim63 takes the jump list: :jumps and :clearjumps, CTRL-I and CTRL-O, and
// every place a line or column change moved its marks.
func Whim63(text []byte, w io.Writer) ([]byte, error) {
	e := New("nojumplist", text, w)

	for _, c := range []struct{ name, handler string }{{"jumps", "ex_jumps"}, {"clearjumps", "ex_clearjumps"}} {
		e.Sub(fmt.Sprintf(`(?m)^([ \t]*\[CMD_%s\] = \{\(char_u \*\)"%s", sizeof\("%s"\) - 1, )%s,`,
			c.name, c.name, c.name, c.handler), "${1}ex_ni,", 1,
			fmt.Sprintf(":%s points at ex_ni", c.name))
	}
	e.Sub(`(?m)^([ \t]*\{Ctrl_I, )nv_pcmark(, 0, 0\} ,)`, "${1}nv_error${2}", 1,
		"CTRL-I in Normal mode points at nv_error")

	// The append is cut from its test to the last line of its body.  It is
	// matched by its two ends because the body is the whole of building a
	// jump-list entry, which shares no shape with the test above it.
	e.InFunction("setpcmark", func(e *E) {
		if e.Failed() {
			return
		}
		t := e.Text()
		m := jumplistAppend.FindIndex(t)
		tail := []byte("fm->fname = NULL;\n")
		z := bytes.Index(t, tail)
		if m == nil || z < 0 || bytes.Count(t, tail) != 1 {
			e.Refuse("setpcmark -- the jump-list append was not found once")
			return
		}
		e.say("setpcmark appending to the jump list")
		out := append([]byte{}, t[:m[0]]...)
		e.Set(append(out, t[z+len(tail):]...))
	})

	e.InFunction("nv_ctrlo", func(e *E) {
		e.Sub(`(?m)^([ \t]*)cap->count1 = -cap->count1;\n[ \t]*nv_pcmark\(cap\);\n`,
			"${1}clearopbeep(cap->oap);\n", 1, "CTRL-O walking back through the jump list")
	})
	e.InFunction("nv_pcmark", func(e *E) {
		e.DropIf(`(?m)^[ \t]*if \(cap->cmdchar == TAB && mod_mask == MOD_MASK_CTRL\)$`,
			"CTRL-Tab refused by the jump-list command")
		e.Sub(`(?m)^([ \t]*)if \(cap->cmdchar == 'g'\)\n[ \t]*\{\n[ \t]*pos = movechangelist\(\(int\)cap->count1\);\n[ \t]*\}\n[ \t]*else\n[ \t]*\{\n[ \t]*pos = movemark\(\(int\)cap->count1\);\n[ \t]*\}\n`,
			"${1}pos = movechangelist((int)cap->count1);\n", 1,
			"the jump list as the other half of nv_pcmark")
		e.Sub(`(?m)^([ \t]*)else if \(cap->cmdchar == 'g'\)$`, "${1}else", 1,
			"the change-list messages no longer choosing by key")
		e.Cut(`(?m)^[ \t]*else\n[ \t]*\{\n[ \t]*clearopbeep\(cap->oap\);\n[ \t]*\}\n`, 1,
			"a jump-list miss beeping")
	})
	e.InFunction("mark_adjust_internal", func(e *E) {
		e.DropIf(`(?m)^[ \t]*for \(i = 0; i < win->w_jumplistlen; \+\+i\)$`, "line changes moving jump-list marks")
		e.Cut(`(?m)^[ \t]*if \(\(cmdmod\.cmod_flags & CMOD_LOCKMARKS\) == 0\)\n[ \t]*\{\n[ \t]*\}\n\n?`, 1,
			"the now-empty 'lockmarks' test around them")
	})
	e.InFunction("mark_col_adjust", func(e *E) {
		e.DropIf(`(?m)^[ \t]*for \(i = 0; i < win->w_jumplistlen; \+\+i\)$`, "column changes moving jump-list marks")
	})
	e.InFunction("mark_forget_file", func(e *E) {
		e.DropIf(`(?m)^[ \t]*for \(i = wp->w_jumplistlen - 1; i >= 0; --i\)$`, "a forgotten file leaving the jump list")
	})
	e.InFunction("fmarks_check_names", func(e *E) {
		e.Cut(`(?m)^[ \t]*for \(\(wp\) = firstwin; \(wp\) != NULL; \(wp\) = \(wp\)->w_next\)\s*\n[ \t]*\{\n[ \t]*for \(i = 0; i < wp->w_jumplistlen; \+\+i\)\n[ \t]*\{\n[ \t]*fmarks_check_one\(&wp->w_jumplist\[i\], name, buf\);\n[ \t]*\}\n[ \t]*\}\n\n?`,
			1, "a named buffer resolving jump-list file names")
	})
	e.InFunction("win_init", func(e *E) {
		e.Cut(`(?m)^[ \t]*copy_jumplist\(oldp, newp\);\n`, 1, "a new window copying the jump list")
	})
	e.InFunction("win_free", func(e *E) {
		e.Cut(`(?m)^[ \t]*free_jumplist\(wp\);\n\n?`, 1, "a closed window freeing the jump list")
	})
	return e.Done()
}

func init() { register("whim63", Whim63) }
