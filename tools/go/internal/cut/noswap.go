package cut

import (
	"bytes"
	"fmt"
	"io"
	"regexp"

	"slimvim.local/tools/internal/cutil"
)

// noswapStubs: the flag matters.  check_need_swap() and changed() call
// ml_open_file() on every edit, and a body that simply returned would search
// 'directory' again on the next keystroke if the flag were left set.
var noswapStubs = []struct{ name, body string }{
	{"ml_open_file", "    buf->b_may_swap = FALSE;"},
	{"ml_preserve", ""},
	{"ml_sync_all", ""},
	{"ml_setname", ""},
}

const recoverArm = `(?m)[ \t]*else if \(swap_exists_action == SEA_RECOVER\)\n` +
	`[ \t]*\{\n(?:[^\n]*\n)*?[ \t]*ml_recover\(FALSE\);\n(?:[^\n]*\n)*?[ \t]*\}\n`

// noswapBody stubs a body, writing `{\n}` for an EMPTY one rather than
// `{\n\n}` -- this file has no run of two blank lines anywhere.
func noswapBody(text []byte, name, body string) ([]byte, int, error) {
	o, c, found, balanced := cutil.Body(text, name)
	if !found {
		return nil, 0, fmt.Errorf("noswap: %s is not defined at file scope any more", name)
	}
	if !balanced {
		return nil, 0, fmt.Errorf("noswap: %s is unbalanced", name)
	}
	was := bytes.Count(text[o:c], []byte{'\n'})
	out := make([]byte, 0, len(text))
	out = append(out, text[:o]...)
	out = append(out, "{\n"...)
	if body != "" {
		out = append(out, body...)
		out = append(out, '\n')
	}
	out = append(out, '}')
	return append(out, text[c+1:]...), was, nil
}

// NoSwap takes the swap file away.
func NoSwap(text []byte, w io.Writer) ([]byte, error) {
	total := 0
	for _, s := range noswapStubs {
		var was int
		var err error
		text, was, err = noswapBody(text, s.name, s.body)
		if err != nil {
			return nil, err
		}
		total += was
		shape := "empty"
		if s.body != "" {
			shape = "one"
		}
		fmt.Fprintf(w, "  noswap       %-14s was %3d lines, is now %s\n", s.name, was, shape)
	}

	// Counted over the WHOLE text and not capped at one: the Python's re.subn
	// has no count here, so two arms would report 2 and refuse.  A search that
	// stopped at the first would accept them and cut one.
	re := regexp.MustCompile(recoverArm)
	if n := len(re.FindAll(text, -1)); n != 1 {
		return nil, fmt.Errorf("noswap: expected one SEA_RECOVER arm, matched %d -- it is "+
			"the only way into ml_recover once :recover is retired, and leaving it keeps "+
			"576 lines alive", n)
	}
	text = re.ReplaceAll(text, nil)
	var err error
	fmt.Fprintln(w, "  noswap       the SEA_RECOVER arm of the ATTENTION prompt")

	// A ROW IS WHAT INITIALISES ITS GLOBAL, so a row can only go once nothing
	// reads the global -- otherwise a `char_u *` stays NULL for ever and the
	// first dereference is a segfault.  Two of the three options here were
	// dropped without that check, before `dropoptions --strict` existed:
	//
	//   'swapsync'   p_sws, read in mf_sync()'s MFS_FLUSH tail.  Removed here.
	//                It is also the only caller of sync().
	//   'directory'  p_dir, read in check_overwrite() -- and in recover_names(),
	//                which scans every directory in it for swap files and lives
	//                until Phase 21.  So 'directory' CANNOT be dropped here at
	//                all, and used to be: it left p_dir NULL, and for twelve
	//                phases `:w!` over an existing other file segfaulted.
	//
	// Invisible to everything until then -- the build is clean, an orphaned
	// global is *used* so no warning names it, and no harness writes over an
	// existing file under a different name with `!`.  orphanopts is the
	// standing check now, and it runs in every whim phase.
	//
	// 'updatecount' is the third and is safe: p_uc is a long, so an orphan
	// reads as 0 -- which is exactly "never create a swap file".
	if text, err = cutil.DropIf(text,
		`(?m)^[ \t]*if \(\(flags & MFS_FLUSH\) && \*p_sws != NUL\)$`, 1); err != nil {
		return nil, err
	}
	fmt.Fprintln(w, "  noswap       mf_sync's fsync/sync tail, the last reader of p_sws")

	fmt.Fprintf(w, "  noswap       %d lines stubbed; %d findswapname mentions left for "+
		"the sweep\n", total, bytes.Count(text, []byte("findswapname")))
	return text, nil
}
