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
