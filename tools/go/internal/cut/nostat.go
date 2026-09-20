package cut

import (
	"bytes"
	"fmt"
	"io"
	"regexp"

	"slimvim.local/tools/internal/cutil"
)

// nostatCalls are the three direct buf_check_timestamp() sites, each with the
// function it sits in, so a refusal names WHERE the shape moved.
var nostatCalls = []struct{ pat, where string }{
	{`(?m)^[ \t]*\(void\)buf_check_timestamp\(curbuf, FALSE\);\n`, "do_ecmd"},
	{`(?m)^[ \t]*\(void\)buf_check_timestamp\(buf, FALSE\);\n`, "enter_buffer"},
	{`(?m)^[ \t]*buf_check_timestamp\(curbuf, FALSE\);\n`, "ex_drop"},
}

// NoStat stops the editor re-reading a file it has already read.
//
// check_timestamps() becomes `return 0` -- its four callers each already handle
// that answer, so stubbing is deliberate where unpicking four different control
// structures is not.  The three direct buf_check_timestamp() calls then go,
// because with the poll gone they are the only thing keeping 339 lines alive.
//
// check_mtime() is NOT touched: it runs only when the user asks to write, and
// it is what stops a write silently clobbering someone else's edit.
func NoStat(text []byte, w io.Writer) ([]byte, error) {
	blanked := cutil.Blank(text)
	head := regexp.MustCompile(`(?m)^check_timestamps\([^\n]*\n`)
	m := head.FindIndex(text)
	if m == nil {
		return nil, fmt.Errorf("nostat: check_timestamps is not defined at file scope any more")
	}
	rel := bytes.IndexByte(blanked[m[1]:], '{')
	if rel < 0 {
		return nil, fmt.Errorf("nostat: check_timestamps is unbalanced")
	}
	opening := m[1] + rel
	closing := cutil.Match(blanked, opening)
	if closing < 0 {
		return nil, fmt.Errorf("nostat: check_timestamps is unbalanced")
	}
	was := bytes.Count(text[opening:closing], []byte{'\n'})
	var buf []byte
	buf = append(buf, text[:opening]...)
	buf = append(buf, "{\n    return 0;\n}"...)
	buf = append(buf, text[closing+1:]...)
	text = buf
	fmt.Fprintf(w, "  nostat       check_timestamps was %d lines, and now looks at nothing\n", was)

	for _, c := range nostatCalls {
		re := regexp.MustCompile(c.pat)
		n := len(re.FindAll(text, -1))
		if n != 1 {
			return nil, fmt.Errorf("nostat: expected one buf_check_timestamp call in %s, "+
				"matched %d", c.where, n)
		}
		text = re.ReplaceAll(text, nil)
		fmt.Fprintf(w, "  nostat       %s stops checking on the way in\n", c.where)
	}
	fmt.Fprintf(w, "  nostat       %d buf_check_timestamp mentions left for the sweep\n",
		bytes.Count(text, []byte("buf_check_timestamp")))
	return text, nil
}
