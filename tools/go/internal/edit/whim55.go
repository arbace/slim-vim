package edit

import (
	"fmt"
	"io"
)

// cdpathTest is 'cdpath' being offered as a directory list by command-line
// completion.  The option's row goes in the same edit, below; this is the one
// place that reads the global outside it, and dropoptions --strict refuses a
// row whose global still has a reader.
const cdpathTest = ` || p == (char_u *)&p_cdpath)`

// Whim55 stops 'cdpath' being completed as a directory list, so that the row
// can go.
func Whim55(text []byte, w io.Writer) ([]byte, error) {
	out, err := Once(text, cdpathTest, `)`, "unusedopts   the cdpath completion test")
	if err != nil {
		return nil, err
	}
	fmt.Fprintln(w, "  unusedopts   'cdpath' is no longer completed as a directory list")
	return out, nil
}

func init() { register("whim55", Whim55) }
