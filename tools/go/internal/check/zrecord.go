package check

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
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

// zRecordFiles is zRecord except that the run directory is LOOKED IN.
//
// tools/zstream.py's session() throws its directory away, which is the one
// thing a phase about writing files cannot do -- so the runner is here, and
// everything else is that tool's for its reasons: the binary is staged as `vim`
// because argv[0] decides what the editor is, the environment is emptied so no
// vimrc is found, and the session is its own so a stop signal cannot reach the
// caller's shell.
func zRecordFiles(binary string, args []string, keys [][]byte, timeout time.Duration) (string, map[string]int64) {
	x := zRun(binary, args, keys, timeout, true)
	return x.text, x.files
}

// zRecordStream is the same runner with no `files` section and the raw STREAM
// handed back beside the record.  zero7 needs it because E319 and :registers
// are drawn, followed by a Press ENTER prompt, and the next redraw wipes the
// line before the cursor comes back -- which is where zscreen takes its
// picture.  So those two live in the stream and in no snapshot.
func zRecordStream(binary string, args []string, keys [][]byte, timeout time.Duration) (string, string) {
	x := zRun(binary, args, keys, timeout, false)
	return x.text, x.stream
}

// zRecordSnaps is zRecordStream with the SNAPSHOT COUNT as well, which zero8
// needs: its four keys stop drawing a message, and one redraw fewer is the
// check where the bell is not -- the key beeps from the same place every other
// unused g/[/] key does, so the bell is identical either side and only the
// snapshot count moves.
func zRecordSnaps(binary string, args []string, keys [][]byte, timeout time.Duration) (string, string, int) {
	x := zRun(binary, args, keys, timeout, false)
	return x.text, x.stream, x.snaps
}

// zRecordFull adds the EXIT STATUS and the bell count, which zero11 needs
// because its whole phase is a status: `:q` with nothing after it draws E37,
// runs out of stdin and exits 1 on the binary that refuses, and exits 0 on the
// one that quits.  No recording can see that -- every zcases case ends with a
// trailing `:q!`, which quits both.
func zRecordFull(binary string, args []string, keys [][]byte, timeout time.Duration) (string, string, int, string, int) {
	x := zRun(binary, args, keys, timeout, false)
	return x.text, x.stream, x.snaps, x.rc, x.bells
}

// zRecordTimed adds the ELAPSED TIME of the run alone -- not the staging --
// which zero12 needs: change_warning() ends in ui_delay(1002L, TRUE), and a
// second of wall clock is the clearest evidence there is that the warning was
// really drawn and not merely a string in the binary.
func zRecordTimed(binary string, args []string, keys [][]byte, timeout time.Duration) (string, string, int64) {
	x := zRun(binary, args, keys, timeout, false)
	return x.text, x.stream, x.ms
}

// zRes is everything one run can say.  It is a struct and not six positional
// returns because five shapes of recorder had already made the tuple
// unreadable, and each new check needs one more field rather than one more
// arity.
type zRes struct {
	text   string
	files  map[string]int64
	stream string
	snaps  int
	rc     string
	bells  int
	ms     int64
}

func zRun(binary string, args []string, keys [][]byte, timeout time.Duration, withFiles bool) zRes {
	vim, err := harness.Stage(binary)
	if err != nil {
		return zRes{text: "ERROR " + err.Error()}
	}
	home, _ := os.MkdirTemp("", "zrun-home-")
	defer os.RemoveAll(home)
	d, _ := os.MkdirTemp("", "zrun-")
	defer os.RemoveAll(d)
	kf := filepath.Join(d, "keys")
	var buf []byte
	for _, k := range keys {
		buf = append(buf, k...)
	}
	os.WriteFile(kf, buf, 0o644)

	env := z2Env(home)
	for i := 0; i < len(env); i++ {
		if strings.HasPrefix(env[i], "LINES=") || strings.HasPrefix(env[i], "COLUMNS=") {
			env = append(env[:i], env[i+1:]...)
			i--
		}
	}
	rcText := ""
	var out, errb []byte
	in, _ := os.Open(kf)
	c := exec.Command(vim, args...)
	c.Stdin, c.Dir, c.Env = in, d, env
	var ob, eb bytes.Buffer
	c.Stdout, c.Stderr = &ob, &eb
	// start_new_session: :suspend and :stop signal the PROCESS GROUP, and
	// without a session of its own that reaches the caller's shell.
	harness.Setsid(c)
	done := make(chan error, 1)
	if err := c.Start(); err != nil {
		return zRes{text: "ERROR " + err.Error()}
	}
	t0 := time.Now()
	go func() { done <- c.Wait() }()
	select {
	case e := <-done:
		out, errb = ob.Bytes(), eb.Bytes()
		if e == nil {
			rcText = "0"
		} else {
			rcText = fmt.Sprintf("%d", exitCode(e))
		}
	case <-time.After(timeout):
		_ = c.Process.Kill()
		<-done
		rcText, out, errb = "timeout", nil, nil
	}
	in.Close()
	ms := time.Since(t0).Milliseconds()

	scr := harness.NewScreen(24, 80)
	scr.Feed(out)
	left := map[string]int64{}
	ents, _ := os.ReadDir(d)
	for _, e := range ents {
		if e.Name() == "keys" {
			continue
		}
		fi, err := e.Info()
		if err == nil {
			left[e.Name()] = fi.Size()
		}
	}
	text := harness.Section("exit "+rcText, nil)
	text += harness.Section(fmt.Sprintf("bells %d", scr.Bells), nil)
	if withFiles {
		text += harness.Section("files "+pyDict(left), nil)
	}
	sum := sha256.Sum256(out)
	text += harness.Section(fmt.Sprintf("stream %d sha=%s", len(out), hex.EncodeToString(sum[:])[:16]), nil)
	e := strings.TrimRight(string(errb), "\n")
	text += harness.Section("stderr", &e)
	for i, s := range scr.Snaps {
		dd := s.Text
		text += harness.Section(fmt.Sprintf("snap %d cursor=%d,%d bells=%d", i, s.Y, s.X, s.Bells), &dd)
	}
	return zRes{harness.Scrub(text), left, string(out), len(scr.Snaps), rcText, scr.Bells, ms}
}

// pyDict is Python's %r of a dict of name -> size, which is what the record
// carries: `{'out.txt': 6}`, keys in sorted order because the Python built it
// from a sorted listdir.
func pyDict(m map[string]int64) string {
	if len(m) == 0 {
		return "{}"
	}
	names := make([]string, 0, len(m))
	for k := range m {
		names = append(names, k)
	}
	sort.Strings(names)
	parts := make([]string, len(names))
	for i, n := range names {
		parts[i] = fmt.Sprintf("'%s': %d", n, m[n])
	}
	return "{" + strings.Join(parts, ", ") + "}"
}
