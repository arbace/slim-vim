package harness

import (
	"fmt"
	"io"
	"os"
	"regexp"
	"strings"
	"sync"
	"time"
)

// vimError is any Vim error code, not only the two this table draws, so a name
// that starts failing a NEW way is recorded rather than scraped for a `term=`
// that is only the echoed request.
var vimError = regexp.MustCompile(`\bE\d+:`)

// ZTermCheck asks the terminal table with `+set term={name}` instead of $TERM.
//
// The old question was CONTENT-FREE and measurably so.  whim phase 19 removed
// the getenv("TERM") the editor read, so every one of the nineteen rows said
// the same thing: nineteen ways of recording that the environment does
// nothing.  A prototype that deleted eight of the ten built-in terminal names
// and three of the nine capability tables -- 118 lines of terminal description
// -- passed the comparator declaring nothing at all.
//
// `+set term={name}` reaches did_set_term(), and a refused name answers
// E522 with the terminal the editor STAYED ON, which is what makes a refusal
// distinguishable from the old vacuous row.  Proven able to fail in the same
// measurement that proved the old one was not: with one row deleted from
// builtin_terminals[], the new table moves exactly 1 of 19 and the old one
// moves 0 of 19.
//
// No file argument and no file: zero phase 5 made a file argument an unknown
// option.
func ZTermCheck(bin, out string, w io.Writer) error {
	home, err := os.MkdirTemp("", "ztermcheck-home-")
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
			rows[i] = zaskTerm(bin, env, t)
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

func zaskTerm(bin string, env []string, t string) string {
	var got []string
	for _, settle := range []time.Duration{500 * time.Millisecond,
		1500 * time.Millisecond, 3000 * time.Millisecond} {
		got = zask(bin, env, t, settle)
		if len(got) > 0 {
			break
		}
	}
	answer := strings.Join(got, " ")
	if answer == "" {
		answer = "(none)"
	}
	return fmt.Sprintf(":set term=%-20s -> %s", pyRepr(t), answer)
}

func zask(bin string, env []string, t string, settle time.Duration) []string {
	d, err := os.MkdirTemp("", "ztermcheck-")
	if err != nil {
		return nil
	}
	defer os.RemoveAll(d)

	// $TERM is left at the pty's default, since nothing in the editor has read
	// it since whim phase 19, and pinning it keeps the pty itself constant.
	text, _, err := Session(bin, []string{"+set term=" + t},
		[][]byte{[]byte(":set term? t_Co?\r"), []byte(":q!\r")},
		"xterm", 20*time.Second, settle, d, env, 0, 0)
	if err != nil {
		return nil
	}

	var errs, got []string
	for _, line := range strings.Split(string(text), "\n") {
		if m := vimError.FindString(line); m != "" {
			// The refusal, and NOT the `term=` it echoes back at us.
			code := m[:len(m)-1]
			if !containsStr(errs, code) {
				errs = append(errs, code)
			}
			continue
		}
		for _, kw := range []string{"term=", "t_Co="} {
			if i := strings.Index(line, kw); i >= 0 {
				f := strings.Fields(line[i:])
				if len(f) > 0 {
					got = append(got, f[0])
				}
			}
		}
	}
	if len(got) == 0 {
		return nil
	}
	return append(errs, got...)
}
