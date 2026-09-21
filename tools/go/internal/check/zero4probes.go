package check

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"

	"slimvim.local/tools/internal/harness"
)

// z4Probe is one probe: a command line, a key sequence, and whether this phase
// is required to MOVE it.  Both halves matter -- a probe that only checks the
// new binary passes just as well on a phase that did nothing.
type z4Probe struct {
	name   string
	args   []string
	keys   [][]byte
	differ bool
}

var (
	z4ESC   = []byte("\x1b")
	z4CR    = []byte("\r")
	z4QUIT  = []byte("\x1b:q!\r")
	z4ALPHA = []byte("alpha\rbeta")
)

// z4Typed is zcases's shape: type the seed under 'paste', then the real keys.
func z4Typed(seed []byte, keys ...[]byte) ([]string, [][]byte) {
	k := [][]byte{append(append([]byte("i"), seed...), z4ESC...), []byte(":set nopaste\r")}
	return []string{"+set paste"}, append(append(k, keys...), z4QUIT)
}

func z4KeysOnly(keys ...[]byte) ([]string, [][]byte) {
	return nil, append(append([][]byte{}, keys...), z4QUIT)
}

func z4Probes() []z4Probe {
	p := func(name string, args []string, keys [][]byte, differ bool) z4Probe {
		return z4Probe{name, args, keys, differ}
	}
	only := [][]byte{z4QUIT}
	ta, tk := z4Typed(z4ALPHA, []byte("Q"))
	ga, gk := z4Typed(z4ALPHA, []byte("gQ"))
	aa, ak := z4KeysOnly([]byte(":append\rone\rtwo\r.\r"))
	ia, ik := z4KeysOnly([]byte(":insert\rfirst\r.\r"))
	ca, ck := z4Typed(z4ALPHA, []byte(":change\rother\r.\r"))
	va, vk := z4Typed(z4ALPHA, []byte(":visual\r"))
	v2a, v2k := z4Typed(z4ALPHA, []byte(":vi\r"))
	v3a, v3k := z4Typed(z4ALPHA, []byte(":view\r"))
	xa, xk := z4Typed(z4ALPHA, []byte(":ex\r"))
	ea, ek := z4Typed(z4ALPHA, []byte("0dwA-tail\x1b"), []byte("u"), []byte("\x12"), []byte("yyp"))
	return []z4Probe{
		// the six the delta declares, each required to show Ex mode on the old
		// binary: a probe the input passes is a probe that proves nothing.
		p("key_Q", ta, tk, true),
		p("key_gQ", ga, gk, true),
		p("argv_e", []string{"-e"}, only, true),
		p("argv_E", []string{"-E"}, only, true),
		p("argv_e_s", []string{"-e", "-s"}, only, true),
		p("argv_v", []string{"-v"}, only, true),
		// and everything that must not move.  `-s` alone was never an option:
		// case 's' set silent mode only when Ex mode was already on and called
		// mainerr() otherwise, so it is not in the delta.
		p("argv_s", []string{"-s"}, only, false),
		p("argv_none", nil, only, false),
		p("argv_plus", []string{"+"}, only, false),
		p("argv_plus_q", []string{"+q!"}, only, false),
		p("argv_plus_set", []string{"+set nu", "+q!"}, only, false),
		p("argv_plus_nu", []string{"+set nu"}, only, false),
		p("argv_plus_file", []string{"+q!", "f.txt"}, only, false),
		p("argv_minus", []string{"-"}, only, false),
		p("argv_minmin", []string{"--"}, only, false),
		p("argv_minmin_plus", []string{"--", "+q!"}, only, false),
		p("argv_file", []string{"f.txt"}, only, false),
		p("argv_files", []string{"f.txt", "g.txt"}, only, false),
		p("argv_T", []string{"-T"}, only, false),
		p("argv_T_xterm", []string{"-T", "xterm"}, only, false),
		p("argv_Txterm", []string{"-Txterm"}, only, false),
		// getexline, not getexmodeline: the three that read their own lines.
		p("ex_append", aa, ak, false),
		p("ex_insert", ia, ik, false),
		p("ex_change", ca, ck, false),
		// the commands whose Ex-mode escape this phase folded away, from Normal
		// mode, where they never entered it.
		p("cmd_visual", va, vk, false),
		p("cmd_vi", v2a, v2k, false),
		p("cmd_view", v3a, v3k, false),
		p("cmd_ex", xa, xk, false),
		// and an ordinary edit, which is the whole point of keeping the rest.
		p("editing", ea, ek, false),
	}
}

// z4Pty is section 6: tools/zpty.py drives four sessions in the declared delta
// and none of them presses Q, so this is the before-and-after the delta cannot
// give, because it has no old binary.
func z4Pty(r *rep, old, bin string) error {
	home, err := os.MkdirTemp("", "zero4-home-")
	if err != nil {
		return err
	}
	session := func(binary string, keys [][]byte) (string, int, error) {
		d, err := os.MkdirTemp("", "zero4-pty-")
		if err != nil {
			return "", -1, err
		}
		text, status, err := harness.Session(binary, nil, keys, "xterm",
			20*time.Second, 600*time.Millisecond, d, z2Env(home), 0, 0)
		return string(text), status, err
	}
	// Q, then the word that leaves Ex mode, then quit.  On the old binary the
	// first key prints the banner and `visual` is the way out; on the new one Q
	// beeps and the same six letters are Normal-mode keys -- `v` starts Visual,
	// `a` ends up in Insert -- so the ESC is not decoration: without it `:q!` is
	// typed into the buffer and the session runs to the timeout and is killed.
	exKeys := [][]byte{[]byte("ialpha\x1b"), []byte("Q"), []byte("visual\r"), []byte("\x1b:q!\r")}
	oldTxt, oldRC, err := session(old, exKeys)
	if err != nil {
		return err
	}
	newTxt, newRC, err := session(bin, exKeys)
	if err != nil {
		return err
	}
	say := func(format string, a ...any) error { r.say(format, a...); return harness.ErrReported }
	if !strings.Contains(oldTxt, z4Enter) {
		return say("the input binary did not enter Ex mode on a pty -- this proves nothing")
	}
	if strings.Contains(newTxt, z4Enter) {
		return say("the new binary still enters Ex mode on a pty")
	}
	for _, s := range []struct {
		name string
		rc   int
	}{{"old", oldRC}, {"new", newRC}} {
		if s.rc != 0 {
			return say("the Ex-mode pty session exited %d on the %s binary", s.rc, s.name)
		}
	}
	// And an ordinary editing session, which must be the same on both.
	edKeys := [][]byte{[]byte("ityped here\x1b"), []byte("0dw"), []byte(":set ruler?\r"), []byte(":q!\r")}
	eOldTxt, eOldRC, err := session(old, edKeys)
	if err != nil {
		return err
	}
	eNewTxt, eNewRC, err := session(bin, edKeys)
	if err != nil {
		return err
	}
	if !strings.Contains(eOldTxt, "here") || !strings.Contains(eOldTxt, "ruler") {
		return say("the editing pty session did not edit on the input binary")
	}
	if eOldTxt != eNewTxt || eOldRC != eNewRC {
		return say("the editing pty session moved: %d -> %d", eOldRC, eNewRC)
	}
	r.say("pty: Ex mode entered by the old binary and by nothing now; the editing session identical either side")
	return nil
}

var _ = io.Discard
var _ = fmt.Sprintf
var _ = filepath.Join
