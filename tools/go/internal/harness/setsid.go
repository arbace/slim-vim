package harness

import (
	"os/exec"
	"syscall"
)

func setsidAttr(c *exec.Cmd) {
	if c.SysProcAttr == nil {
		c.SysProcAttr = &syscall.SysProcAttr{}
	}
	c.SysProcAttr.Setsid = true
}

// Setsid is setsidAttr for another package: a check that runs the editor
// itself -- zero6 keeps its run directory, which ZSession throws away -- needs
// the same session of its own, because :suspend and :stop signal the PROCESS
// GROUP and without one that reaches the caller's shell (exit 148, measured).
func Setsid(c *exec.Cmd) { setsidAttr(c) }

// PyReturnCode is subprocess's returncode for a process that has exited: its
// exit status, or MINUS THE SIGNAL NUMBER if a signal killed it.
//
// Go's ExitCode() answers -1 for every signal death, so a SIGSEGV and a SIGKILL
// and a SIGABRT all read the same -- and the Python harnesses this package
// replaced record `exit -11` for a segfault.  The difference was latent for as
// long as nothing in the corpus crashed, and it surfaced at zero phase 14,
// whose whole evidence is that the binary it was handed dies with SIGSEGV and
// the one it made does not: `-1` there would pass for a clean exit's cousin
// and say nothing about WHICH signal.
func PyReturnCode(ee *exec.ExitError) int {
	if ws, ok := ee.Sys().(syscall.WaitStatus); ok && ws.Signaled() {
		return -int(ws.Signal())
	}
	return ee.ExitCode()
}
