package harness

import (
	"bytes"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"runtime"
	"sort"
	"sync"
	"time"
)

// zmemTimeout is generous because these cases build up to 25,000 lines by
// typing them.
const zmemTimeout = 180 * time.Second

// ZMemline records the sixteen memline cases: the only part of the recording
// that can see the text layer as a tree.
//
// Until it existed nothing in the pipeline could tell a working memline from a
// broken one -- a zero-vim with pp->pb_pointer[idx].pe_line_count-- deleted
// from ml_find_line()'s descent recorded ALL 102 SCREEN CASES BYTE FOR BYTE,
// because every one of them allocates exactly one data block, so idx is 0
// every time and a pointer entry's line count never decides anything.
func ZMemline(bin, outdir string, w io.Writer) error {
	if err := os.RemoveAll(outdir); err != nil {
		return err
	}
	if err := os.MkdirAll(outdir, 0o755); err != nil {
		return err
	}
	start := time.Now()

	var mu sync.Mutex
	var blocked []string

	n := runtime.NumCPU() * 2
	if n > len(zmemCases) {
		n = len(zmemCases)
	}
	sem := make(chan struct{}, n)
	var wg sync.WaitGroup
	for _, c := range zmemCases {
		wg.Add(1)
		go func(name string, args []string, keys [][]byte) {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()
			text, stalled := zmemRecord(bin, args, keys)
			os.WriteFile(filepath.Join(outdir, name), []byte(text), 0o644)
			if stalled {
				mu.Lock()
				blocked = append(blocked, name)
				mu.Unlock()
			}
		}(c.name, c.args, c.keys)
	}
	wg.Wait()

	fmt.Fprintf(w, "%d memline cases -> %s in %.1fs\n",
		len(zmemCases), outdir, time.Since(start).Seconds())
	if len(blocked) > 0 {
		sort.Strings(blocked)
		fmt.Fprintf(os.Stderr, "%d case(s) stalled and did not return: %s\n",
			len(blocked), joinSpace(blocked))
		return fmt.Errorf("zmemline: %d stalled", len(blocked))
	}
	return nil
}

// zmemRedraws counts how many times the editor finished a redraw -- and NOT
// the stream's digest.
//
// zcases records `stream <bytes> sha=<digest>` as a tripwire under its
// screens.  That cannot be done here, and the reason is MEASURED rather than
// assumed: an undo in this corpus reports its age, and the editor writes the
// message and then positions the cursor to clear the rest of the line -- so
// `0 seconds ago` gives \x1b[24;40H\x1b[K and `1 second ago` gives
// \x1b[24;39H, a COLUMN NUMBER derived from the width of a timestamp.  The
// scrub cannot reach it: it rewrites the age's TEXT, and this is arithmetic on
// that text's length.  Caught as a one-byte stream difference in mem_undo_big,
// once in 48 whole recordings, with every screen identical.
//
// The 102 screen cases keep their digest and are right to: their undos are
// sub-second, so the age is always `0 seconds ago`.  A corpus that undoes
// 2,000 lines of a 12,000-line buffer straddles the second.
//
// What is kept instead is the count of show-cursor, where a redraw ENDS and
// where the screen model snapshots, which is the same number as the snapshots
// and is clock-free.
func zmemRedraws(out []byte) int {
	return bytes.Count(out, []byte(showCursor))
}

func zmemRecord(bin string, args []string, keys [][]byte) (string, bool) {
	scr, out, errOut, rc, err := ZSession(bin, keys, "xterm", args, 24, 80, zmemTimeout)
	if err != nil {
		why := "the editor took the input over and did not return"
		return Section("blocked", nil) + Section("why", &why), true
	}
	text := Section(fmt.Sprintf("exit %d", rc), nil)
	text += Section(fmt.Sprintf("bells %d", scr.Bells), nil)
	text += Section(fmt.Sprintf("stream %d redraws", zmemRedraws(out)), nil)
	errBody := trimTrailingNewlines(decodeReplace(errOut))
	text += Section("stderr", &errBody)
	for i, snap := range scr.Snaps {
		dump := snap.Text
		text += Section(fmt.Sprintf("snap %d cursor=%d,%d bells=%d",
			i, snap.Y, snap.X, snap.Bells), &dump)
	}
	return Scrub(text), false
}

func joinSpace(xs []string) string {
	out := ""
	for i, x := range xs {
		if i > 0 {
			out += " "
		}
		out += x
	}
	return out
}
