package harness

import (
	"fmt"
	"os"
	"strings"
	"sync"
	"time"
)

// Terms are the nineteen names asked about: the ten built-in entries, the six
// upstream entries this build dropped, an unknown name, and the empty string.
// The six dropped ones are here so that one creeping back in would show as a
// row that stopped resolving to the fallback.
var Terms = []string{
	"xterm", "xterm-256color", "screen", "screen-256color",
	"tmux", "tmux-256color", "alacritty-256color", "vt100", "ansi",
	"dumb", "debug",
	"vt320", "vt52", "iris-ansi", "pcansi", "win32", "amiga",
	"no-such-term-9x", "",
}

// TermCheck asks each terminal what it resolved to and how many colours it
// has, through a real pty.
//
// Anything about terminals, mappings, screen drawing or :set reporting needs a
// real pty: -e -s never initialises the terminal and reports empty values.
func TermCheck(bin, out string, w interface{ Write([]byte) (int, error) }) error {
	home, err := os.MkdirTemp("", "termcheck-home-")
	if err != nil {
		return err
	}
	defer os.RemoveAll(home)
	env := Env(home)

	rows := make([]string, len(Terms))
	var wg sync.WaitGroup
	for i, t := range Terms {
		wg.Add(1)
		go func(i int, t string) {
			defer wg.Done()
			rows[i] = askTerm(bin, env, t)
		}(i, t)
	}
	wg.Wait()

	body := strings.Join(rows, "\n") + "\n"
	if err := os.WriteFile(out, []byte(body), 0o644); err != nil {
		return err
	}
	fmt.Fprint(w, body)
	return nil
}

// askTerm retries at a longer settle before believing an empty answer.
//
// An empty answer means the screen had not been drawn when the read stopped,
// not that the terminal resolves to nothing -- and it happens only under load,
// when every harness runs at once.  Waiting longer is the whole fix; a
// terminal that really answers nothing answers nothing three times.
func askTerm(bin string, env []string, t string) string {
	var got []string
	for _, settle := range []time.Duration{500 * time.Millisecond,
		1500 * time.Millisecond, 3000 * time.Millisecond} {
		got = ask(bin, env, t, settle)
		if len(got) > 0 {
			break
		}
	}
	answer := strings.Join(got, " ")
	if answer == "" {
		answer = "(none)"
	}
	return fmt.Sprintf("TERM=%-20s -> %s", pyRepr(t), answer)
}

func ask(bin string, env []string, t string, settle time.Duration) []string {
	d, err := os.MkdirTemp("", "termcheck-")
	if err != nil {
		return nil
	}
	// AND IT IS REMOVED.  The Python made a directory per pty session and left
	// it: 182,319 were once lying in /tmp, and an ext4 directory that full
	// answers mkdir with ENOSPC on a disk with 70 GB free.  It failed a phase
	// that has nothing to do with terminals, which is how this kind of leak is
	// always found -- somewhere else.
	defer os.RemoveAll(d)

	os.WriteFile(d+"/f.txt", []byte("one\ntwo\nthree\n"), 0o644)
	text, _, err := Session(bin, []string{"f.txt"},
		[][]byte{[]byte(":set term? t_Co?\r"), []byte(":q!\r")},
		t, 20*time.Second, settle, d, env, 0, 0)
	if err != nil {
		return nil
	}

	// The screen is full of '~' filler and the two answers land on different
	// screen lines; take each from its keyword onwards.
	var got []string
	for _, line := range strings.Split(string(text), "\n") {
		for _, kw := range []string{"term=", "t_Co="} {
			if i := strings.Index(line, kw); i >= 0 {
				f := strings.Fields(line[i:])
				if len(f) > 0 {
					got = append(got, f[0])
				}
			}
		}
	}
	return got
}
