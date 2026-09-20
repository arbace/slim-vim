package edit

import (
	"bytes"
	"fmt"
	"io"
	"regexp"

	"slimvim.local/tools/internal/cutil"
)

const (
	fwdWalk = `for ((buf) = firstbuf; (buf) != NULL; (buf) = (buf)->b_next)`
	bwdWalk = `for ((buf) = lastbuf; (buf) != NULL; (buf) = (buf)->b_prev)`
)

var enclosingLoop = regexp.MustCompile(`\b(for|while|switch|do)\b`)

// foldWalk turns `for ((v) = firstbuf; ...)` and its block into `v = curbuf;`
// followed by the block's body, dedented.
//
// IT REFUSES A BODY WITH A `break` OR `continue` THAT BINDS TO THE WALK.
// Deleting the `for` header rebinds such a statement to whatever encloses it,
// or to nothing at all -- getout()'s walk did exactly that and produced "break
// statement not within loop or switch".  It is the same hazard CLAUDE.md
// records for unwrapping `do { } while (0)`, and it must be a refusal rather
// than a silent miscompile.
//
// The test is "is there an enclosing loop or switch INSIDE the body", not "is
// it at brace depth 0": C binds break to the nearest enclosing loop or switch
// and brace depth has nothing to do with it -- getout()'s break sits two ifs
// deep and still bound to the `for`.  An earlier version tested depth and would
// have passed it.
func (e *E) foldWalk(fn, v, head, what string, n int) {
	e.InFunction(fn, func(e *E) {
		if e.Failed() {
			return
		}
		pat := regexp.MustCompile(`(?m)^([ \t]*)` + regexp.QuoteMeta(head) + `[ \t]*\n([ \t]*)\{\n`)
		if k := len(pat.FindAll(e.text, -1)); k != n {
			e.die("%s -- the walk matches %d times, expected %d", what, k, n)
			return
		}
		for i := 0; i < n; i++ {
			m := pat.FindSubmatchIndex(e.text)
			b := cutil.Blank(e.text)
			o := indexFrom(e.text, []byte("{"), m[0])
			c := cutil.Match(b, o)
			raw := e.text[indexFrom(e.text, []byte("\n"), o)+1 : lastNewlineBefore(e.text, c)+1]
			if bad := bindsToWalk(raw); bad != "" {
				e.die("%s -- the body has a `%s;` that binds to the walk being removed, not to anything inside it", what, bad)
				return
			}
			body := cutil.Dedent4(raw)
			end := indexFrom(e.text, []byte("\n"), c) + 1
			out := append([]byte{}, e.text[:m[0]]...)
			out = append(out, e.text[m[2]:m[3]]...)
			out = append(out, (v + " = curbuf;\n")...)
			out = append(out, body...)
			e.text = append(out, e.text[end:]...)
		}
		e.say(what)
	})
}

// bindsToWalk names a `break` or `continue` in the body that is not inside a
// loop or switch of the body's own, or "" if there is none.
func bindsToWalk(raw []byte) string {
	rb := cutil.Blank(raw)
	type span struct{ a, z int }
	var spans []span
	for _, mm := range enclosingLoop.FindAllIndex(rb, -1) {
		j := indexFrom(rb, []byte("{"), mm[1])
		if j >= 0 {
			if k := cutil.Match(rb, j); k > 0 {
				spans = append(spans, span{j, k})
			}
		}
	}
	for _, kw := range []string{"break", "continue"} {
		re := regexp.MustCompile(`\b` + kw + `\b[ \t]*;`)
		for _, mm := range re.FindAllIndex(rb, -1) {
			inside := false
			for _, s := range spans {
				if s.a < mm[0] && mm[0] < s.z {
					inside = true
					break
				}
			}
			if !inside {
				return kw
			}
		}
	}
	return ""
}

// dropWalk replaces `for (<head>)` and the block it runs with repl.
//
// The head is matched as a REGEX built from the literal, never compared as one:
// these walk lines are macro-expanded and carry a trailing space after the
// closing paren, and a literal written out in a shell heredoc is a bad place to
// depend on invisible whitespace -- one written that way already failed here.
func (e *E) dropWalk(fn, head, repl, what string, n int) {
	e.InFunction(fn, func(e *E) {
		if e.Failed() {
			return
		}
		pat := regexp.MustCompile(`(?m)^[ \t]*` + regexp.QuoteMeta(head) + `[ \t]*\n[ \t]*\{\n`)
		if k := len(pat.FindAll(e.text, -1)); k != n {
			e.die("%s -- the walk matches %d times, expected %d", what, k, n)
			return
		}
		for i := 0; i < n; i++ {
			m := pat.FindIndex(e.text)
			b := cutil.Blank(e.text)
			o := indexFrom(e.text, []byte("{"), m[0])
			c := cutil.Match(b, o)
			end := indexFrom(e.text, []byte("\n"), c) + 1
			out := append([]byte{}, e.text[:m[0]]...)
			out = append(out, repl...)
			e.text = append(out, e.text[end:]...)
		}
		e.say(what)
	})
}

// Whim71 makes the buffer list one buffer: buf_valid() is `buf == curbuf`,
// every walk over firstbuf folds to curbuf, and the list pointers go.
func Whim71(text []byte, w io.Writer) ([]byte, error) {
	e := New("onebuf", text, w)

	// 1. the keystone: a buffer is valid exactly when it is THE buffer
	e.Body("buf_valid", w71lit3, "buf_valid, which walked the list to find the buffer it was given")
	e.Body("anyBufIsChanged", w71lit4, "anyBufIsChanged, which asked every buffer")
	e.Body("buflist_findname_stat", w71lit5, "buflist_findname_stat, which searched the list by name")

	e.foldWalk("ml_close_all", "buf", fwdWalk, "ml_close_all closing every buffer", 1)
	e.foldWalk("ml_close_notmod", "buf", fwdWalk, "ml_close_notmod closing every buffer", 1)
	e.foldWalk("shorten_fnames", "buf", fwdWalk, "shorten_fnames shortening every name", 1)
	e.foldWalk("did_set_paste", "buf", fwdWalk, "'paste' saving and restoring every buffer", 3)
	e.foldWalk("set_termname", "buf", fwdWalk, "a new terminal notifying every buffer", 1)
	e.dropWalk("getout", fwdWalk, w71lit6, "quitting unloading every buffer, whose break bound to the walk", 1)
	e.Body("buflist_findpat", w71lit7, "buflist_findpat matching against every buffer")
	e.dropWalk("check_changed_any", fwdWalk, w71lit8,
		"counting the buffers to check, and re-adding the one already seeded", 2)
	e.dropWalk("open_buffer", fwdWalkCurbuf(), "", "open_buffer looking for another loaded buffer", 1)

	e.InFunction("open_buffer", func(e *E) {
		if e.Failed() {
			return
		}
		out, err := cutil.FoldAlways(e.Text(), `(?m)^[ \t]*if \(curbuf == NULL\)$`, 1)
		if err != nil {
			e.Refuse("%v", err)
			return
		}
		e.Set(out)
	})
	if !e.Failed() {
		e.say("open_buffer testing whether it found one")
	}
	e.InFunction("open_buffer", func(e *E) {
		e.Literal(w71lit15, "", "open_buffer carrying on in another buffer instead")
	})
	e.Body("compute_buffer_local_count", w71lit9, "computing a buffer address by walking to an offset")

	e.InFunction("parse_cmd_address", func(e *E) {
		e.Literal(w71AddrPair1, w71NewPair1, "the default buffer range")
	})
	e.InFunction("address_default_all", func(e *E) {
		e.Literal(w71AddrPair2, w71NewPair2, "the :% buffer range")
	})
	e.InFunction("get_address", func(e *E) {
		e.Literal(w71AddrPair3, w71NewPair3, "the $ of a buffer range")
	})
	e.InFunction("invalid_range", func(e *E) {
		e.Literal(w71AddrPair4, w71NewPair4, "validating a buffer range")
	})

	e.InFunction("free_buffer", func(e *E) {
		e.Literal(w71lit16, w71lit17, "free_buffer deferring onto a chain nothing ever drained")
	})
	e.Lines(`static buf_T[ \t]+\*au_pending_free_buf[ \t]*=[ \t]*NULL[ \t]*;`, 1, "that chain")
	e.Literal(w71lit10, w71lit11, "the mapping scan walking the list, still twice: curbuf then the globals")
	e.InFunction("set_curbuf", func(e *E) {
		e.Literal(w71lit18, w71lit19, "set_curbuf entering a different buffer")
	})
	e.InFunction("set_curbuf", func(e *E) {
		e.Lines(`int[ \t]+valid;`, 1, "its validity flag")
	})
	e.InFunction("close_buffer", func(e *E) {
		if e.Failed() {
			return
		}
		out, err := cutil.FoldNever(e.Text(), `(?m)^[ \t]*if \(wipe_buf && buf->b_nwindows <= 0 && \(buf->b_prev != NULL \|\| buf->b_next != NULL\)\)$`, 1)
		if err != nil {
			e.Refuse("%v", err)
			return
		}
		e.Set(out)
	})
	if !e.Failed() {
		e.say("close_buffer unlinking a buffer that was never linked to another")
	}
	e.InFunction("buflist_new", func(e *E) {
		e.Literal(w71lit20, "", "buflist_new appending to the list")
	})

	// The wiped-fnum branch is cut from its head to the plain else after it.
	if !e.Failed() {
		t := e.Text()
		if k := bytes.Count(t, []byte(w71OldReuseStart)); k != 1 {
			e.Refuse("the wiped-fnum branch -- its head occurs %d times, expected 1", k)
		} else {
			i := bytes.Index(t, []byte(w71OldReuseStart))
			j := bytes.Index(t[i:], []byte(w71OldReuseEnd))
			if j < 0 {
				e.Refuse("the wiped-fnum branch -- no plain `b_fnum = top_file_num++` else after it")
			} else {
				j += i
				out := append([]byte{}, t[:i]...)
				out = append(out, w71lit13...)
				e.Set(append(out, t[j+len(w71OldReuseEnd):]...))
				e.say("buflist_new reusing a wiped fnum and re-sorting the list for it")
			}
		}
	}
	e.Lines(`static buf_T[ \t]+\*firstbuf[ \t]*=[ \t]*NULL[ \t]*;`, 1, "firstbuf")
	e.Lines(`static buf_T[ \t]+\*lastbuf[ \t]*=[ \t]*NULL[ \t]*;`, 1, "lastbuf")
	e.Lines(`static garray_T buf_reuse[ \t]*=[ \t]*\{0, 0, 0, 0, NULL\}[ \t]*;`, 1, "the wiped-fnum pool")
	e.Literal(w71lit12, "", "the buffer list pointers in buf_T")
	return e.Done()
}

func fwdWalkCurbuf() string {
	return regexpReplaceAll(fwdWalk, "(buf)", "(curbuf)")
}

func regexpReplaceAll(s, old, new string) string {
	return string(bytes.ReplaceAll([]byte(s), []byte(old), []byte(new)))
}

var _ = fmt.Sprintf
var _ = bwdWalk

func init() { register("whim71", Whim71) }
