package edit

import "io"

// Whim33 takes the quickfix arms of :cdo, :ldo, :cfdo and :lfdo, which answer
// "not implemented".
//
// Its report tag is `listdo` and is written per act rather than per phase,
// which is why this one does not use New()'s tag column the way the others do:
// the heredoc prints "  listdo       <what>: gone".
func Whim33(text []byte, w io.Writer) ([]byte, error) {
	e := New("listdo", text, w)
	e.InFunction("ex_listdo", func(e *E) {
		for _, f := range []struct{ what, pattern string }{
			{"the winfixbuf refusal for :ldo and :lfdo",
				`(?m)^[ \t]*if \(\(eap->cmdidx == CMD_ldo \|\| eap->cmdidx == CMD_lfdo\) && !eap->forceit\)$`},
			{"the quickfix commands answering not implemented",
				`(?m)^[ \t]*if \(eap->cmdidx == CMD_cdo \|\| eap->cmdidx == CMD_ldo \|\| eap->cmdidx == CMD_cfdo \|\| eap->cmdidx == CMD_lfdo\)$`},
		} {
			e.FoldNever(f.pattern, f.what+": gone")
		}
	})
	return e.Done()
}

func init() { register("whim33", Whim33) }
