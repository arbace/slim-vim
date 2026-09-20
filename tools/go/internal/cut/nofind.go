package cut

import (
	"bytes"
	"fmt"
	"io"

	"slimvim.local/tools/internal/cutil"
)

// nofindBody answers "is there a file of this name?" and nothing else.
const nofindBody = `    char_u      *name;

    if (!first)
    {
        return NULL;
    }

    name = vim_strnsave(ptr, len);
    if (name == NULL)
    {
        return NULL;
    }

    if (mch_getperm(name) < 0)
    {
        vim_free(name);
        return NULL;
    }

    return name;`

// NoFind stops find_file_in_path searching 'path'.
//
// The extent is BRACE MATCHED from the definition's head, and the old body must
// still delegate to find_file_in_path_option -- which is how the tool tells a
// file it has not seen from one it has already cut, rather than replacing its
// own output with itself.
func NoFind(text []byte, w io.Writer) ([]byte, error) {
	opening, closing, err := cutil.FindBody(text, "find_file_in_path")
	if err != nil {
		return nil, fmt.Errorf("nofind: %v", err)
	}
	if !bytes.Contains(text[opening:closing], []byte("find_file_in_path_option")) {
		return nil, fmt.Errorf("nofind: find_file_in_path no longer delegates to the " +
			"'path' search, so this has run already")
	}
	var buf []byte
	buf = append(buf, text[:opening]...)
	buf = append(buf, "{\n"...)
	buf = append(buf, nofindBody...)
	buf = append(buf, "\n}"...)
	buf = append(buf, text[closing+1:]...)
	text = buf

	fmt.Fprintln(w, `  nofind       find_file_in_path answers "is there a file of this `+
		`name?" and nothing else`)
	fmt.Fprintf(w, "  nofind       %d find_file_in_path_option mentions left for the sweep\n",
		bytes.Count(text, []byte("find_file_in_path_option")))
	return text, nil
}
