package harness

import (
	"fmt"
	"io"
	"os"
	"runtime"
	"strings"
	"sync"
	"time"
)

// zexcmdsSeed is what every command is given to work on.
var zexcmdsSeed = "alpha\rbeta\rgamma"

// zexcmdsSkip hand the process group to the shell.  They are skipped here as
// they are in the file sweep, although every run gets a session of its own
// anyway.
var zexcmdsSkip = map[string]bool{"stop": true, "suspend": true}

// ZExCmds types every Ex command at ':' and records the message it printed.
//
// Two details in the key sequence are load-bearing.  `:highlight` pages and
// ESC does NOT stop a --More-- listing, so a session without an answer for it
// ran to the timeout; `q` ends the listing, and in Normal mode `q` followed by
// ESC is an aborted recording that changes nothing.  (`.` also ends it, and
// repeats the last change, which polluted the row.)
//
// The editor starts with +set paste and the seed is typed under it, then
// 'nopaste' is set back: the corpus types its own text rather than opening a
// file, because from zero phase 8 there is no way to name one.
func ZExCmds(bin, table, out string, w io.Writer) error {
	names, err := CommandNames(table)
	if err != nil {
		return err
	}
	start := time.Now()
	rows := make([]string, len(names))
	n := runtime.NumCPU() * 2
	if n > len(names) {
		n = len(names)
	}
	sem := make(chan struct{}, n)
	var wg sync.WaitGroup
	for i, name := range names {
		wg.Add(1)
		go func(i int, name string) {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()
			rows[i] = zexcmdsOne(bin, name)
		}(i, name)
	}
	wg.Wait()
	if err := os.WriteFile(out, []byte(strings.Join(rows, "")), 0o644); err != nil {
		return err
	}
	fmt.Fprintf(w, "%d commands -> %s in %.1fs\n", len(rows), out, time.Since(start).Seconds())
	return nil
}

func zexcmdsOne(bin, name string) string {
	if zexcmdsSkip[name] {
		body := "hands over the process group"
		return "=== " + name + "\n" + Section("skipped", &body)
	}
	keys := [][]byte{
		[]byte("i" + zexcmdsSeed + "\x1b"),
		[]byte(":set nopaste\r"),
		[]byte(":" + name + "\r"),
		[]byte("q"), []byte("\x1b"), []byte(":q!\r"),
	}
	scr, _, stderr, rc, err := ZSession(bin, keys, "xterm", []string{"+set paste"},
		24, 80, 20*time.Second)
	if err != nil {
		body := "never returned"
		return "=== " + name + "\n" + Section("blocked", &body)
	}

	text := ""
	var msgs []string
	for i, snap := range scr.Snaps {
		lines := strings.Split(snap.Text, "\n")
		// The seed and the `:set nopaste` make the first two snapshots; from
		// the command's own onwards, the top of the screen and every distinct
		// last row.
		if i < 2 {
			continue
		}
		if text == "" {
			var keep []string
			hi := 6
			if len(lines) < hi {
				hi = len(lines)
			}
			for _, l := range lines[:hi] {
				t := strings.TrimSpace(l)
				if t != "" && t != "~" {
					keep = append(keep, l)
				}
			}
			text = strings.Join(keep, " | ")
		}
		m := strings.TrimRight(lines[len(lines)-1], " \t\n\v\f\r")
		if m != "" && !containsStr(msgs, m) {
			msgs = append(msgs, m)
		}
	}

	row := "=== " + name + "\n"
	row += Section(fmt.Sprintf("exit %d", rc), nil)
	row += Section(fmt.Sprintf("bells %d", scr.Bells), nil)
	errBody := strings.TrimRight(decodeReplace(stderr), "\n")
	row += Section("stderr", &errBody)
	row += Section("text", &text)
	msgBody := strings.Join(msgs, "\n")
	row += Section("msgs", &msgBody)
	return Scrub(row)
}

func containsStr(xs []string, s string) bool {
	for _, x := range xs {
		if x == s {
			return true
		}
	}
	return false
}
