package harness

import (
	"os"
	"os/exec"
	"path/filepath"
	"sync"
)

// stageLock serialises the copy below.
//
// shutil.copy2 -- and os.WriteFile here -- holds a write fd on its
// destination, and a fork in another goroutine hands that child the same fd
// until it execs.  execve refuses a file any process holds open for writing,
// so the COPYING side's own exec dies with "Text file busy".  Measured in the
// zero pipeline: 0 of 20 runs failed idle and 8 of 20 under a steady 64-way
// load, and a whole verify under that load lost 15 of its 18 units, almost
// every one of them this.
//
// Go's os/exec does not fork a shell per command the way a thread pool does,
// but it does fork, and the window is the same.  One copy per binary, under a
// lock, before anything is started.
var (
	stageLock sync.Mutex
	staged    = map[string]string{}
)

// Stage copies a binary into a scratch directory under the name "vim" and
// returns the path.
//
// A VIM BINARY'S OWN NAME CHANGES WHAT IT DOES.  parse_command_name() reads
// argv[0]: a basename beginning with 'r' turns on restricted mode and every
// shell-out fails, 'e' selects evim, 'g' the GUI, and "view", "diff" and "ex"
// prefixes change the mode again.  A binary saved as "ref" is a DIFFERENT
// EDITOR, and comparing it against one called "vim" reports differences that
// are not in the code -- which is how this was found, with :%!sort and
// :r !echo failing against a byte-identical binary.
func Stage(bin string) (string, error) {
	abs, err := filepath.Abs(bin)
	if err != nil {
		return "", err
	}
	stageLock.Lock()
	defer stageLock.Unlock()
	if p, ok := staged[abs]; ok {
		return p, nil
	}
	dir, err := os.MkdirTemp("", "harness-bin-")
	if err != nil {
		return "", err
	}
	dst := filepath.Join(dir, "vim")
	// THE COPY HAPPENS IN A CHILD PROCESS, and that is the half a lock does
	// not give.  Writing the file here would hold a write fd in THIS address
	// space, and a goroutine forking at that instant inherits it until it
	// execs -- which is the whole failure.  Handing the copy to cp means the
	// fd exists only in cp, so there is nothing for anyone else to inherit,
	// however late a caller asks to stage a second binary from inside a pool
	// already forking the first.
	if err := exec.Command("cp", abs, dst).Run(); err != nil {
		return "", err
	}
	if err := os.Chmod(dst, 0o755); err != nil {
		return "", err
	}
	staged[abs] = dst
	return dst, nil
}

// Env is the isolation every harness runs under.
//
// No -u NONE.  An empty $HOME, $VIM and $VIMRUNTIME are the isolation instead:
// slim-vim finds no ~/.vimrc, system vimrc or runtime defaults in them, and
// whim-vim, which has had no -u since its phase 18, looks for none of them
// anyway.  Measured against the recorded baselines with a real ~/.vimrc on the
// machine: nothing moved.
func Env(home string) []string {
	drop := map[string]bool{
		"HOME": true, "VIM": true, "VIMRUNTIME": true, "XDG_CONFIG_HOME": true,
		"VIMINIT": true, "EXINIT": true, "MYVIMRC": true,
	}
	var out []string
	for _, kv := range os.Environ() {
		k := kv
		if i := indexByte(kv, '='); i >= 0 {
			k = kv[:i]
		}
		if !drop[k] {
			out = append(out, kv)
		}
	}
	return append(out,
		"HOME="+home,
		"VIM="+filepath.Join(home, "novim"),
		"VIMRUNTIME="+filepath.Join(home, "novim"),
		"XDG_CONFIG_HOME="+filepath.Join(home, "xdg"))
}

func indexByte(s string, c byte) int {
	for i := 0; i < len(s); i++ {
		if s[i] == c {
			return i
		}
	}
	return -1
}

// setsid puts a child in a session of its own.
//
// :suspend and :stop signal the whole PROCESS GROUP with SIGTSTP.  Without a
// session of its own the sweep stops its own shell, which looks like the
// harness crashing at command 500 -- exit 148, which is 128 + SIGTSTP.
func setsid(c *exec.Cmd) { setsidAttr(c) }
