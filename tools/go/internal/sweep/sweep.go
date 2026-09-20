// Package sweep is tools/sweep.sh: delete what a cut left unreachable, to a
// fixpoint, all six kinds, with the canonicalisers as the seventh member of
// each round.
//
// The six feed each other -- deleting a function orphans a type, deleting a
// type orphans a prototype, deleting a field orphans an enumerator -- so none
// is finished until all are.  canon runs at the END of each round and not
// before the loop: the sweep DELETES, and deletion leaves blank runs that only
// canon removes.  Moving it before the loop was measured to commute on one
// phase and then moved 27 of 32 boundaries when the whole pass ran.
package sweep

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"

	"slimvim.local/tools/internal/dead"
)

// MaxRounds is sweep.sh's ceiling.  Exceeding it is a hard failure.
const MaxRounds = 15

// CompileDir is where the speculative object and the kept warnings go.  It is
// in .cache/ and NOT in the work tree: a file left in the work tree is a file
// the boundary digest counts.
const CompileDir = ".cache/compile"

func digest(b []byte) string {
	s := sha256.Sum256(b)
	return hex.EncodeToString(s[:])
}

// Sweep runs the loop over path and returns the number of rounds it took.
//
// Report lines go to w, one per round, in sweep.sh's format and order.
func Sweep(path string, w interface{ Write([]byte) (int, error) }) (rounds int, err error) {
	// The enumerator values of THIS input, kept for the whole sweep so every
	// round pins to the original numbering.  deadenums writes it the first
	// time something is dead and not before, so most sweeps never pay for the
	// -g build.  Like the shell's `mktemp -u`, the NAME is reserved and the
	// file is not created: deadenums asks whether it exists.
	valsFile, err := os.CreateTemp("", "enumvals.")
	if err != nil {
		return 0, err
	}
	vals := valsFile.Name()
	valsFile.Close()
	os.Remove(vals)
	defer os.Remove(vals)

	if err := os.MkdirAll(CompileDir, 0o755); err != nil {
		return 0, err
	}
	os.Remove(filepath.Join(CompileDir, "build.o"))
	os.Remove(filepath.Join(CompileDir, "build.sha"))

	var spec *specBuild
	defer func() {
		if spec != nil {
			spec.stop()
		}
		clearSpec()
	}()

	// A TOOL IS NOT RUN AGAIN ON TEXT IT HAS ALREADY PASSED.  Every one is a
	// pure function of the bytes, so a tool that ran and changed nothing on
	// text X cannot change it the next time the file is exactly X.  Clearing
	// the memory when a tool DOES change something is what keeps this from
	// changing the fixpoint.
	passed := map[string]string{}

	for {
		rounds++
		src, err := os.ReadFile(path)
		if err != nil {
			return rounds, err
		}
		was := digest(src)

		// The build rides along: a plain -O0 object of the text this round
		// starts from, compiled on a core that was idle anyway.  It cannot be
		// the warning compile's object -- -Wall -Wextra move the code by 64
		// bytes of .text -- and the round that changes nothing started from
		// the final text, so its object is the one phasebuild links.
		if spec != nil {
			spec.stop()
		}
		clearSpec()
		spec = startSpec(path, rounds, was)

		said := make([]string, 7)
		order := []struct {
			name string
			run  func([]byte) ([]byte, string, error)
		}{
			{"deadsweep", func(b []byte) ([]byte, string, error) { return runDeadsweep(path, b) }},
			{"deadprotos", runDeadprotos},
			{"typereach", runTypereach},
			{"funcreach", runFuncreach},
			{"deadfields", runDeadfields},
			{"deadenums", func(b []byte) ([]byte, string, error) { return runDeadenums(path, b, vals) }},
			{"canon", runCanon},
		}

		cur := src
		for i, t := range order {
			now := digest(cur)
			if passed[t.name] == now {
				said[i] = fmt.Sprintf("  %-12s passed this text already", t.name)
				continue
			}
			out, line, err := t.run(cur)
			if err != nil {
				// sweep.sh's pass() runs each tool through a pipe to tail, so
				// a tool's failure is invisible to set -e and the round goes
				// on.  Reproduced: the text is left as it was and the tool
				// records nothing.
				said[i] = line
				passed[t.name] = ""
				continue
			}
			said[i] = line
			cur = out
			if digest(cur) == now {
				passed[t.name] = now
			} else {
				passed[t.name] = ""
			}
		}

		if !bytes.Equal(cur, src) {
			if err := os.WriteFile(path, cur, 0o644); err != nil {
				return rounds, err
			}
		}

		fmt.Fprintf(w, "  sweep %d      %s; %s; %s; %s; %s; %s;   %s\n",
			rounds, said[0], said[1], said[2], said[3], said[4], said[5], said[6])

		if digest(cur) == was {
			break
		}
		if rounds >= MaxRounds {
			fmt.Fprintln(w, "  sweep        not converging")
			return rounds, fmt.Errorf("sweep: not converging after %d rounds", rounds)
		}
	}

	// The values file exists only if some round actually dumped DWARF.  This
	// check's exit status is the ONE in the whole sweep that is not masked.
	if _, err := os.Stat(vals); err == nil {
		moved, gone, err := dead.VerifyEnums(path, vals)
		if err != nil {
			return rounds, err
		}
		if len(moved) > 0 {
			n := len(moved)
			if n > 8 {
				n = 8
			}
			fmt.Fprintf(w, "  enumvals     %d surviving enumerators changed value: %v\n",
				len(moved), moved[:n])
			return rounds, fmt.Errorf("sweep: %d surviving enumerators changed value", len(moved))
		}
		fmt.Fprintf(w, "  enumvals     %d enumerators gone, and not one survivor moved\n", gone)
	}

	// Promote the speculative object, but only when its compile succeeded AND
	// the text it compiled is the text the sweep ended on.
	if spec != nil {
		if spec.wait() == nil {
			final, err := os.ReadFile(path)
			if err == nil && digest(final) == spec.sha {
				os.Rename(spec.obj, filepath.Join(CompileDir, "build.o"))
				os.WriteFile(filepath.Join(CompileDir, "build.sha"),
					[]byte(spec.sha+"\n"), 0o644)
			}
		}
		spec = nil
	}
	return rounds, nil
}

type specBuild struct {
	cmd  *exec.Cmd
	obj  string
	sha  string
	done chan error
}

func clearSpec() {
	matches, _ := filepath.Glob(filepath.Join(CompileDir, "spec.*"))
	for _, m := range matches {
		os.Remove(m)
	}
}

func startSpec(path string, round int, sha string) *specBuild {
	src, err := os.ReadFile(path)
	if err != nil {
		return nil
	}
	c := filepath.Join(CompileDir, fmt.Sprintf("spec.%d.c", round))
	if err := os.WriteFile(c, src, 0o644); err != nil {
		return nil
	}
	obj := filepath.Join(CompileDir, fmt.Sprintf("spec.%d.o", round))
	cmd := exec.Command("gcc", "-c", "-O0", "-o", obj, c)
	cmd.Stderr = nil
	if err := cmd.Start(); err != nil {
		return nil
	}
	s := &specBuild{cmd: cmd, obj: obj, sha: sha, done: make(chan error, 1)}
	go func() { s.done <- cmd.Wait() }()
	return s
}

func (s *specBuild) wait() error {
	if s == nil {
		return nil
	}
	return <-s.done
}

func (s *specBuild) stop() {
	if s == nil || s.cmd.Process == nil {
		return
	}
	s.cmd.Process.Kill()
	<-s.done
}
