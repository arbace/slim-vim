package harness

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"time"
)

// Behaviour runs the 67 cases and writes one file per case.
//
// EVERY ARTIFACT IS DELETED FIRST.  A harness that diffs an output file it did
// not first remove keeps passing on the previous run's file.
//
// A case that writes nothing records that fact, so a crash cannot pass as a
// match -- which is why the file body is the literal <NO FILE WRITTEN> rather
// than an absent file or an empty one.
func Behaviour(bin, out string, w interface{ Write([]byte) (int, error) }) error {
	vim, err := Stage(bin)
	if err != nil {
		return err
	}
	home, err := os.MkdirTemp("", "behaviour-home-")
	if err != nil {
		return err
	}
	defer os.RemoveAll(home)
	env := Env(home)

	if err := os.RemoveAll(out); err != nil {
		return err
	}
	if err := os.MkdirAll(out, 0o755); err != nil {
		return err
	}

	// Every case at once.  Each has a directory of its own and writes one
	// output file named after itself, so the order they finish in cannot
	// reach the recording -- and in sequence 67 launches of an editor were
	// 4.4 seconds of every phase.
	n := runtime.NumCPU()
	if n > len(behaviourCases) {
		n = len(behaviourCases)
	}
	sem := make(chan struct{}, n)
	var wg sync.WaitGroup
	for _, c := range behaviourCases {
		wg.Add(1)
		go func(name, text string, cmds []string) {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()
			runBehaviourCase(vim, env, out, name, text, cmds)
		}(c.name, c.text, c.cmds)
	}
	wg.Wait()
	fmt.Fprintf(w, "%d cases -> %s\n", len(behaviourCases), out)
	return nil
}

func runBehaviourCase(vim string, env []string, out, name, text string, cmds []string) {
	d, err := os.MkdirTemp("", "behaviour-")
	if err != nil {
		return
	}
	defer os.RemoveAll(d)
	src := filepath.Join(d, "in.txt")
	dst := filepath.Join(d, "out.txt")
	os.WriteFile(src, []byte(text), 0o644)

	// +{command}, not -c: whim-vim has no -c, and the two fill the same list,
	// so every binary either pipeline makes runs the same commands in the
	// same order.
	argv := []string{"-e", "-s"}
	for _, c := range cmds {
		argv = append(argv, "+"+c)
	}
	argv = append(argv, "+w! "+dst, "+q!", src)

	cmd := exec.Command(vim, argv...)
	cmd.Env = env
	cmd.Dir = d
	cmd.Stdin = nil
	var stdout, stderr strings.Builder
	cmd.Stdout, cmd.Stderr = &stdout, &stderr

	code := 0
	done := make(chan error, 1)
	if err := cmd.Start(); err == nil {
		go func() { done <- cmd.Wait() }()
		select {
		case runErr := <-done:
			if ee, ok := runErr.(*exec.ExitError); ok {
				code = ee.ExitCode()
			} else if runErr != nil {
				code = -1
			}
		case <-time.After(30 * time.Second):
			if cmd.Process != nil {
				cmd.Process.Kill()
			}
			<-done
			code = -1
		}
	} else {
		code = -1
	}

	body, err := os.ReadFile(dst)
	if err != nil {
		body = []byte("<NO FILE WRITTEN>")
	}

	var rec []byte
	rec = append(rec, fmt.Sprintf("exit=%d\n", code)...)
	rec = append(rec, "stdout="+stdout.String()+"\n"...)
	rec = append(rec, "stderr="+stderr.String()+"\n"...)
	rec = append(rec, "file="...)
	rec = append(rec, body...)
	os.WriteFile(filepath.Join(out, name), rec, 0o644)
}
