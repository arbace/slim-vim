package cut

import (
	"bytes"
	"fmt"
	"io"
	"regexp"

	"slimvim.local/tools/internal/cutil"
)

const fnameModArm = `        else if (!skip_mod)
        {
            valid |= modify_fname(src, tilde_file, usedlen, &result, &resultbuf, &resultlen);
            if (result == NULL)
            {
                *errormsg = "";
                return NULL;
            }
        }
`

// fnameModFeeders are the locals that existed only to be passed to
// modify_fname() or to suppress it.
//
// -Wunused-but-set-variable is not a shape deadsweep deletes -- they are
// ASSIGNED, so nothing calls them unused -- so they are named here, which is
// the same reason Phase 20 had to name at_start.
var fnameModFeeders = []struct {
	pat, what string
	n         int
}{
	{`(?m)^[ \t]*int         tilde_file = FALSE;\n`, "tilde_file's declaration", 1},
	{`(?m)^[ \t]*int         skip_mod = FALSE;\n`, "skip_mod's declaration", 1},
	{`(?m)^[ \t]*tilde_file =  strcmp\(\(char \*\)\(result\), \(char \*\)\("~"\)\)  == 0;\n`,
		"a tilde_file assignment", 2},
	{`(?m)^[ \t]*skip_mod = TRUE;\n`, "skip_mod's assignment", 1},
}

var modifyFname = regexp.MustCompile(`\bmodify_fname\b`)

// NoFnameMod makes % a file name and nothing more.
//
// eval_vars' modifier arm goes as exact text, then the two locals that only fed
// it, then the function itself.
func NoFnameMod(text []byte, w io.Writer) ([]byte, error) {
	if !bytes.Contains(text, []byte(fnameModArm)) {
		return nil, fmt.Errorf("nofnamemod: eval_vars' modifier arm is not where this expects")
	}
	text = bytes.Replace(text, []byte(fnameModArm), nil, 1)
	fmt.Fprintln(w, "  nofnamemod   %% is a file name and nothing more")

	for _, f := range fnameModFeeders {
		re := regexp.MustCompile(f.pat)
		locs := re.FindAllIndex(text, f.n)
		if len(locs) != f.n {
			return nil, fmt.Errorf("nofnamemod: %s -- expected %d, matched %d",
				f.what, f.n, len(locs))
		}
		var buf []byte
		prev := 0
		for _, l := range locs {
			buf = append(buf, text[prev:l[0]]...)
			prev = l[1]
		}
		text = append(buf, text[prev:]...)
	}
	fmt.Fprintln(w, "  nofnamemod   tilde_file and skip_mod, which only fed it")

	text, ok := cutil.DeleteDefinition(text, "modify_fname")
	if !ok {
		return nil, fmt.Errorf("nofnamemod: modify_fname is not defined at file scope")
	}
	fmt.Fprintf(w, "  nofnamemod   %d modify_fname mentions left for the sweep\n",
		len(modifyFname.FindAll(text, -1)))
	return text, nil
}
