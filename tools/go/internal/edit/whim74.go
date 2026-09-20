package edit

import (
	"fmt"
	"io"
)

// markArm is the macro-expanded test for an uppercase letter or a digit, which
// is how a file mark is spelled.
const markArm = `\( \(\(unsigned\)\(c\) - 'A' < 26\)  \|\|  \(\(unsigned\)\(c\) - '0' < 10\) \)$`

// Whim74 takes file marks: the uppercase and numbered marks, the table that
// held them, and the type that carried a filename with each.
func Whim74(text []byte, w io.Writer) ([]byte, error) {
	e := New("nofmark", text, w)

	e.FoldNeverIn2("getmark_buf_fnum", `(?m)^[ \t]*else if `+markArm, "reading an uppercase or numbered mark", 1)
	e.DropIfIn("setmark_pos", `(?m)^[ \t]*if `+markArm, "setting an uppercase or numbered mark", 1)
	e.Body("clrallmarks", w74lit2, "clrallmarks initialising the file marks once")
	e.DropBlocks("ex_marks", `(?m)^[ \t]*for \(i = 0; i <  \('z' - 'a' \+ 1\)  \+ EXTRA_MARKS; \+\+i\)$`, 1,
		":marks listing the file marks")
	e.Body("ex_delmarks", w74lit3, ":delmarks clearing an uppercase or numbered mark")
	for _, fn := range []string{"mark_adjust_internal", "mark_col_adjust"} {
		e.DropBlocks(fn, `(?m)^[ \t]*if \(namedfm\[i\]\.fmark\.fnum == fnum\)$`, 2,
			fmt.Sprintf("adjusting the file marks in %s", fn))
		e.DropBlocks(fn, `(?m)^[ \t]*for \(i =  \('z' - 'a' \+ 1\) ; i <  \('z' - 'a' \+ 1\)  \+ EXTRA_MARKS; i\+\+\)$`, 1,
			fmt.Sprintf("and the loop over the numbered marks in %s", fn))
	}
	// fmarks_check_names existed to reattach a file mark to a buffer by name;
	// with no file marks there is nothing to reattach.
	e.Lines(`fmarks_check_names\(buf\);`, 2, "the two calls that rematched file marks")
	e.deleteDefinition("fmarks_check_names", "fmarks_check_names, which had nothing to match")
	e.deleteDefinition("fname2fnum", "fname2fnum, folded empty in phase 70 and now unreachable")
	e.Lines(`static xfmark_T namedfm\[ \('z' - 'a' \+ 1\)  \+ EXTRA_MARKS\];`, 1, "namedfm")
	e.Literal(w74lit4, "", "xfmark_T, a mark with a filename bolted on")
	e.Lines(`enum \{ EXTRA_MARKS = 10 \};`, 1, "the numbered-mark count")
	return e.Done()
}

func init() { register("whim74", Whim74) }
