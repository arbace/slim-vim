package harness

import (
	"fmt"
	"io"
	"os"
	"strings"
	"sync"
	"time"
)

// zargvKeys is what every invocation is typed: escape out of whatever mode the
// command line left the editor in, then quit without writing.
var zargvKeys = [][]byte{[]byte("\x1b:q!\r")}

// zargvInvocations is every command line the parser may see.
//
// It is a RECORDING and not a test of correctness: what each answers is
// whatever the editor does, and a phase that removes an option declares the
// rows that move.  That is why the list holds spellings that were already
// errors -- `-T` with no argument, `--` alone -- since a phase can move the
// MESSAGE without moving the outcome, which zero phase 39 did when the
// enumerators behind ME_ARG_MISSING and ME_GARBAGE went.
var zargvInvocations = [][]string{
	{}, {"+q!"}, {"+set nu", "+q!"}, {"+set nu"},
	{"-T", "xterm"}, {"-T"}, {"-Txterm"}, {"-T", "no-such-term-9x"},
	{"-e"}, {"-E"}, {"-e", "-s"}, {"-v"}, {"-"}, {"--"}, {"--ttyfail"},
	{"-R"}, {"-c", "q!"}, {"-u", "NONE"}, {"-i", "NONE"}, {"-m"}, {"-Z"}, {"-y"},
	{"f.txt"}, {"f.txt", "g.txt"}, {"--version"}, {"--help"}, {"-h"},
	{"+"}, {"+q!", "f.txt"}, {"--", "+q!"},
}

// ZArgv records every command line the parser may see.
func ZArgv(bin, out string, w io.Writer) error {
	start := time.Now()
	rows := make([]string, len(zargvInvocations))
	var wg sync.WaitGroup
	for i, args := range zargvInvocations {
		wg.Add(1)
		go func(i int, args []string) {
			defer wg.Done()
			rows[i] = zargvOne(bin, args)
		}(i, args)
	}
	wg.Wait()
	if err := os.WriteFile(out, []byte(strings.Join(rows, "")), 0o644); err != nil {
		return err
	}
	fmt.Fprintf(w, "%d invocations -> %s in %.1fs\n",
		len(rows), out, time.Since(start).Seconds())
	return nil
}

func zargvOne(bin string, args []string) string {
	name := "(none)"
	if len(args) > 0 {
		name = strings.Join(args, " ")
	}
	row := "=== " + name + "\n"

	_, stdout, stderr, rc, err := ZSession(bin, zargvKeys, "xterm", args, 24, 80, 5*time.Second)
	if err == ErrBlocked {
		body := "took the input over and never returned"
		return row + Section("blocked", &body)
	}
	if err != nil {
		body := err.Error()
		return row + Section("blocked", &body)
	}
	row += Section(fmt.Sprintf("exit %d", rc), nil)
	row += Section(fmt.Sprintf("stream %d", len(stdout)), nil)
	errBody := strings.TrimRight(decodeReplace(stderr), "\n")
	row += Section("stderr", &errBody)
	return Scrub(row)
}
