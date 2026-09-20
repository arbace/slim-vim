package harness

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"time"
)

// CliCheck is tools/clicheck.py: run every command-line option, and require the
// dropped ones to be unknown and the kept ones to work.
//
// WRITTEN BECAUSE NO HARNESS PASSED A SINGLE OPTION, and that is how three
// stayed broken for thirty phases.  --clean, --noplugin and --not-a-term each
// matched their own branch of a chain tools/dropopts.py had split, failed every
// test after it, and reached mainerr anyway -- while behaviour.py, exsweep.py
// and termcheck.py all ran `-u NONE -e -s` and nothing else, and agreed.
//
// A DROPPED option must exit 1 with `Unknown option argument` naming itself.  A
// KEPT one must not, and where it has an effect that :set, a file or an exit
// status can show, THAT EFFECT IS CHECKED: an option that parses and then does
// nothing is exactly the failure this exists to catch, so "it did not complain"
// is the weakest pass and is used only where nothing stronger can be observed
// without a terminal.
//
// EVERY RUN AT ONCE.  The runs are independent -- each has its own directory,
// so -W and -w cannot find each other's files -- and one of them, -v, waits two
// seconds for a terminal that is not there.  In sequence that wait is paid on
// top of fifty-one other launches; concurrently it is the whole cost.

const cliUnknown = `Unknown option argument: "%s"`

var cliDropped = [][]string{
	{"-h"}, {"-?"}, {"--help"}, {"--version"},
	{"-A"}, {"-F"}, {"-H"}, {"-g"},
	{"-f"}, {"-X"}, {"-Y"}, {"--nofork"}, {"--literal"}, {"--gui-dialog-file", "x"},
	{"--clean"}, {"--noplugin"}, {"--not-a-term"},
	{"--startuptime", "st.log"}, {"--log", "x.log"}, {"-d", "x"}, {"-U", "x"}, {"-nb"},
	{"-l"}, {"-C"}, {"-N"}, {"-n"}, {"-p"}, {"-p2"}, {"-V"}, {"-V9"},
}

var cliEx = []string{"-e", "-s"}

var cliFiles = []struct{ name, content string }{
	{"f.txt", "hello\n"}, {"g.txt", "world\n"}, {"s.vim", "set ts=2\n"},
	{"rc.vim", "set sw=7\n"}, {"keys.in", ""},
}

// cliCheckFn returns a complaint, or "" when the case is satisfied.
type cliCheckFn func(rc int, out, dir string) string

// shows requires the token to appear as a whitespace-separated field of the
// output, and the exit status to be what was asked for.
func cliShows(token string, want int) cliCheckFn {
	return func(rc int, out, dir string) string {
		if rc != want {
			return fmt.Sprintf("exit %d, expected %d", rc, want)
		}
		for _, f := range strings.Fields(out) {
			if f == token {
				return ""
			}
		}
		return fmt.Sprintf("%s not in the output", pyRepr(token))
	}
}

func cliMade(name string) cliCheckFn {
	return func(rc int, out, dir string) string {
		if rc != 0 {
			return fmt.Sprintf("exit %d, expected 0", rc)
		}
		if _, err := os.Stat(filepath.Join(dir, name)); err != nil {
			return fmt.Sprintf("%s was not written", name)
		}
		return ""
	}
}

func cliAccepted(rc int, out, dir string) string {
	if rc != 0 {
		return fmt.Sprintf("exit %d, expected 0", rc)
	}
	return ""
}

type cliCase struct {
	what  string
	argv  []string
	check cliCheckFn
}

func cliQ(cmd string) []string { return []string{"-c", cmd, "-c", "qa!", "f.txt"} }

func cliJoin(parts ...[]string) []string {
	var out []string
	for _, p := range parts {
		out = append(out, p...)
	}
	return out
}

func cliKept() []cliCase {
	return []cliCase{
		{"a file, and nothing else", cliJoin(cliEx, cliQ("set ts?")), cliShows("tabstop=4", 0)},
		{"+cmd", cliJoin(cliEx, []string{"+set ts=5"}, cliQ("set ts?")), cliShows("tabstop=5", 0)},
		{"-c", cliJoin(cliEx, []string{"-c", "set ts=3"}, cliQ("set ts?")), cliShows("tabstop=3", 0)},
		{"--cmd", cliJoin(cliEx, []string{"--cmd", "set sw=6"}, cliQ("set sw?")), cliShows("shiftwidth=6", 0)},
		{"-S", cliJoin(cliEx, []string{"-S", "s.vim"}, cliQ("set ts?")), cliShows("tabstop=2", 0)},
		{"-u", cliJoin([]string{"-u", "rc.vim", "-e", "-s"}, cliQ("set sw?")), cliShows("shiftwidth=7", 0)},
		{"-b", cliJoin(cliEx, []string{"-b"}, cliQ("set bin?")), cliShows("binary", 0)},
		{"-R", cliJoin(cliEx, []string{"-R"}, cliQ("set ro?")), cliShows("readonly", 0)},
		{"-m", cliJoin(cliEx, []string{"-m"}, cliQ("set write?")), cliShows("nowrite", 0)},
		{"-M", cliJoin(cliEx, []string{"-M"}, cliQ("set ma?")), cliShows("nomodifiable", 0)},
		{"-wN", cliJoin(cliEx, []string{"-w7"}, cliQ("set window?")), cliShows("window=7", 0)},
		{"-E", cliJoin([]string{"-E", "-s"}, cliQ("set ts?")), cliShows("tabstop=4", 0)},
		// -v leaves Ex mode, so with no terminal it warns -- which is the proof.
		{"-v", cliJoin(cliEx, []string{"-v"}, cliQ("set ts?")), cliShows("terminal", 0)},
		{"--ttyfail", cliJoin([]string{"--ttyfail"}, cliQ("set ts?")), cliShows("terminal", 1)},
		{"-W", cliJoin(cliEx, []string{"-W", "w.out"}, cliQ("set ts?")), cliMade("w.out")},
		{"-w file", cliJoin(cliEx, []string{"-w", "a.out"}, cliQ("set ts?")), cliMade("a.out")},
		{"-s file", cliJoin([]string{"-s", "keys.in", "-e", "-s"}, cliQ("set ts?")), cliAccepted},
		{"-oN", cliJoin(cliEx, []string{"-o2", "-c", "qa!", "f.txt", "g.txt"}), cliAccepted},
		{"-ON", cliJoin(cliEx, []string{"-O2", "-c", "qa!", "f.txt", "g.txt"}), cliAccepted},
		{"-T", cliJoin(cliEx, []string{"-T", "xterm"}, cliQ("set ts?")), cliAccepted},
		{"-", cliJoin(cliEx, []string{"-"}, cliQ("set ts?")), cliAccepted},
		{"--", cliJoin(cliEx, []string{"-c", "qa!", "--", "f.txt"}), cliAccepted},
	}
}

// cliRun is one run, in a directory of its own.
func cliRun(vim, root string, argv []string) (int, string, string) {
	d, err := os.MkdirTemp(root, "")
	if err != nil {
		return -1, err.Error(), ""
	}
	for _, f := range cliFiles {
		os.WriteFile(filepath.Join(d, f.name), []byte(f.content), 0644)
	}
	cmd := exec.Command(vim, argv...)
	cmd.Dir = d
	// No -u NONE: an empty $HOME, $VIM and $VIMRUNTIME are the isolation.  -u
	// itself is still checked above, as an option, at the phase where it exists.
	cmd.Env = probeEnvNoTerm(d)
	devnull, _ := os.Open(os.DevNull)
	if devnull != nil {
		defer devnull.Close()
		cmd.Stdin = devnull
	}
	var buf strings.Builder
	cmd.Stdout, cmd.Stderr = &buf, &buf
	cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
	if err := cmd.Start(); err != nil {
		return -1, err.Error(), d
	}
	done := make(chan error, 1)
	go func() { done <- cmd.Wait() }()
	rc := -1
	select {
	case werr := <-done:
		rc = 0
		if ee, ok := werr.(*exec.ExitError); ok {
			rc = ee.ExitCode()
		}
	case <-time.After(30 * time.Second):
		cmd.Process.Kill()
		<-done
	}
	return rc, buf.String(), d
}

// probeEnvNoTerm is probeEnv without forcing TERM: clicheck runs with no
// terminal at all, which is the condition -v and --ttyfail are checked under.
func probeEnvNoTerm(d string) []string {
	drop := map[string]bool{
		"HOME": true, "VIM": true, "VIMRUNTIME": true,
		"XDG_CONFIG_HOME": true, "VIMINIT": true, "EXINIT": true, "MYVIMRC": true,
	}
	var env []string
	for _, kv := range os.Environ() {
		k := kv
		if i := strings.IndexByte(kv, '='); i >= 0 {
			k = kv[:i]
		}
		if !drop[k] {
			env = append(env, kv)
		}
	}
	return append(env,
		"HOME="+d,
		"VIM="+filepath.Join(d, "novim"),
		"VIMRUNTIME="+filepath.Join(d, "novim"),
		"XDG_CONFIG_HOME="+filepath.Join(d, "xdg"))
}

func cliClip(out string) string {
	s := strings.ReplaceAll(strings.TrimSpace(out), "\n", " | ")
	if len(s) > 90 {
		s = s[:90]
	}
	return s
}

func CliCheck(binary string, out *os.File) error {
	abs, err := filepath.Abs(binary)
	if err != nil {
		return err
	}
	root, err := os.MkdirTemp("", "clicheck")
	if err != nil {
		return err
	}
	defer os.RemoveAll(root)

	// Staged once, as `vim`: the name the binary is called by is not neutral.
	stage := filepath.Join(root, "bin")
	if err := os.Mkdir(stage, 0755); err != nil {
		return err
	}
	vim := filepath.Join(stage, "vim")
	data, err := os.ReadFile(abs)
	if err != nil {
		return err
	}
	if err := os.WriteFile(vim, data, 0755); err != nil {
		return err
	}

	cases := cliKept()
	results := make([]string, len(cliDropped)+len(cases))
	var wg sync.WaitGroup
	for i, opt := range cliDropped {
		wg.Add(1)
		go func(i int, opt []string) {
			defer wg.Done()
			argv := cliJoin([]string{"-e", "-s"}, opt, []string{"-c", "qa!", "f.txt"})
			rc, o, _ := cliRun(vim, root, argv)
			if rc != 1 || !strings.Contains(o, fmt.Sprintf(cliUnknown, opt[0])) {
				results[i] = fmt.Sprintf("dropped %-20s exit %d: %s",
					strings.Join(opt, " "), rc, cliClip(o))
			}
		}(i, opt)
	}
	for j, c := range cases {
		wg.Add(1)
		go func(i int, c cliCase) {
			defer wg.Done()
			rc, o, d := cliRun(vim, root, c.argv)
			if strings.Contains(o, "Unknown option") || strings.Contains(o, "Garbage after option") {
				results[i] = fmt.Sprintf("kept    %-20s refused: %s", c.what, cliClip(o))
				return
			}
			if complaint := c.check(rc, o, d); complaint != "" {
				results[i] = fmt.Sprintf("kept    %-20s %s", c.what, complaint)
			}
		}(len(cliDropped)+j, c)
	}
	wg.Wait()

	var bad []string
	for _, r := range results {
		if r != "" {
			bad = append(bad, r)
		}
	}
	if len(bad) > 0 {
		fmt.Fprintf(out, "  clicheck     %d of %d options wrong:\n", len(bad), len(cliDropped)+len(cases))
		for _, b := range bad {
			fmt.Fprintln(out, "                 "+b)
		}
		return ErrReported
	}
	fmt.Fprintf(out, "  clicheck     %d dropped options unknown, %d kept ones doing what they say\n",
		len(cliDropped), len(cases))
	return nil
}
