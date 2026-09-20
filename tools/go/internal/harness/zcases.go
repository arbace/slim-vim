package harness

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"runtime"
	"sync"
	"time"
)

// ZCases records the 102 screen cases: keystrokes in, escape sequences out,
// and a screen rebuilt per redraw.
//
// This is zero's instrument, and it is zero's own.  The file-based harnesses
// are whim's and slim's and cannot be zero's, because the editor they measure
// is on its way to having no file to write and no stream to print on.
//
// It is proven able to fail: do_addsub() returning FAIL moves exactly 11 of
// the 102 cases and nothing else.
func ZCases(bin, outdir string, w io.Writer) error {
	if err := os.RemoveAll(outdir); err != nil {
		return err
	}
	if err := os.MkdirAll(outdir, 0o755); err != nil {
		return err
	}
	start := time.Now()

	n := runtime.NumCPU() * 2
	if n > len(zcaseList) {
		n = len(zcaseList)
	}
	sem := make(chan struct{}, n)
	var wg sync.WaitGroup
	for _, c := range zcaseList {
		wg.Add(1)
		go func(name string, args []string, keys [][]byte) {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()
			os.WriteFile(filepath.Join(outdir, name), []byte(zrecord(bin, args, keys)), 0o644)
		}(c.name, c.args, c.keys)
	}
	wg.Wait()
	fmt.Fprintf(w, "%d cases -> %s in %.1fs\n", len(zcaseList), outdir, time.Since(start).Seconds())
	return nil
}

// zrecord is one case's record.
//
// The stream's own sha is kept, which is DELIBERATELY the strongest part and
// the part that is open: it is named in eighty files, so replacing it is
// expensive rather than difficult and deserves a pass of its own.  The memline
// recorder carries no digest for the opposite reason -- see ZMemline.
func zrecord(bin string, args []string, keys [][]byte) string {
	scr, out, errOut, rc, err := ZSession(bin, keys, "xterm", args, 24, 80, 20*time.Second)
	if err != nil {
		why := "the editor took the input over and did not return"
		return Section("blocked", nil) + Section("why", &why)
	}
	sum := sha256.Sum256(out)
	text := Section(fmt.Sprintf("exit %d", rc), nil)
	text += Section(fmt.Sprintf("bells %d", scr.Bells), nil)
	text += Section(fmt.Sprintf("stream %d sha=%s", len(out), hex.EncodeToString(sum[:])[:16]), nil)
	errBody := trimTrailingNewlines(decodeReplace(errOut))
	text += Section("stderr", &errBody)
	for i, snap := range scr.Snaps {
		dump := snap.Text
		text += Section(fmt.Sprintf("snap %d cursor=%d,%d bells=%d", i, snap.Y, snap.X, snap.Bells), &dump)
	}
	return Scrub(text)
}

func trimTrailingNewlines(s string) string {
	for len(s) > 0 && s[len(s)-1] == '\n' {
		s = s[:len(s)-1]
	}
	return s
}
