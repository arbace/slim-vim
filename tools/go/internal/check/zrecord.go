package check

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"strings"
	"time"

	"slimvim.local/tools/internal/harness"
)

// zRec is one probe recording: the scrubbed record text, the raw stream and the
// bell count.  Several zero checks build exactly this and compare it between
// two binaries, so it is written once here rather than in each.
type zRec struct {
	text  string
	out   []byte
	bells int
}

// zRecord is `record()` in the heredocs: zcases's record format, scrubbed the
// same way, because mainerr() prints the version banner and that carries
// __DATE__ and __TIME__ -- two binaries built a minute apart would disagree on
// stderr for a reason that is not the editor's behaviour.
func zRecord(binary string, args []string, keys [][]byte) zRec {
	scr, out, errb, rc, err := harness.ZSession(binary, keys, "xterm", args, 24, 80, 8*time.Second)
	if err == harness.ErrBlocked {
		// `vim -` reads the keystroke file as buffer text and then waits for
		// keys that never come.  That is a recording, not a crash.
		body := "took the input over and never returned"
		return zRec{harness.Section("blocked", &body), nil, 0}
	}
	if err != nil {
		return zRec{"ERROR " + err.Error(), nil, 0}
	}
	text := harness.Section(fmt.Sprintf("exit %d", rc), nil)
	text += harness.Section(fmt.Sprintf("bells %d", scr.Bells), nil)
	sum := sha256.Sum256(out)
	text += harness.Section(fmt.Sprintf("stream %d sha=%s", len(out), hex.EncodeToString(sum[:])[:16]), nil)
	e := strings.TrimRight(string(errb), "\n")
	text += harness.Section("stderr", &e)
	for i, s := range scr.Snaps {
		d := s.Text
		text += harness.Section(fmt.Sprintf("snap %d cursor=%d,%d bells=%d", i, s.Y, s.X, s.Bells), &d)
	}
	return zRec{harness.Scrub(text), out, scr.Bells}
}
