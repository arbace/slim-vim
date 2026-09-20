package main

import (
	"fmt"
	"os"
	"strconv"
	"strings"

	"slimvim.local/tools/internal/harness"
)

// runExsweep is tools/exsweep.py.
func runExsweep(args []string) int {
	if len(args) != 3 {
		fmt.Fprintln(os.Stderr, "usage: slimtools exsweep <vim-binary> <table> <outfile>")
		return 1
	}
	if err := harness.ExSweep(args[0], args[1], args[2], os.Stdout); err != nil {
		fmt.Fprintf(os.Stderr, "slimtools: %v\n", err)
		return 1
	}
	return 0
}

// runBehaviour is tools/behaviour.py.
func runBehaviour(args []string) int {
	if len(args) != 2 {
		fmt.Fprintln(os.Stderr, "usage: slimtools behaviour <vim-binary> <outdir>")
		return 1
	}
	if err := harness.Behaviour(args[0], args[1], os.Stdout); err != nil {
		fmt.Fprintf(os.Stderr, "slimtools: %v\n", err)
		return 1
	}
	return 0
}

// runTermcheck is tools/termcheck.py.
func runTermcheck(args []string) int {
	if len(args) != 2 {
		fmt.Fprintln(os.Stderr, "usage: slimtools termcheck <vim-binary> <outfile>")
		return 1
	}
	if err := harness.TermCheck(args[0], args[1], os.Stdout); err != nil {
		fmt.Fprintf(os.Stderr, "slimtools: %v\n", err)
		return 1
	}
	return 0
}

// runZscreen rebuilds a screen from a captured escape stream and prints every
// redraw.  tools/zscreen.py is a library with no CLI; this exists so the two
// can be compared on the same bytes without running the editor.
func runZscreen(args []string) int {
	if len(args) != 1 {
		fmt.Fprintln(os.Stderr, "usage: slimtools zscreen <streamfile>")
		return 1
	}
	data, err := os.ReadFile(args[0])
	if err != nil {
		fmt.Fprintf(os.Stderr, "slimtools: %v\n", err)
		return 1
	}
	s := harness.NewScreen(24, 80)
	s.Feed(data)
	for i, snap := range s.Snaps {
		fmt.Printf("--- snap %d cursor=%d,%d bells=%d\n", i, snap.Y, snap.X, snap.Bells)
		fmt.Println(snap.Text)
	}
	fmt.Printf("--- final cursor=%d,%d bells=%d snaps=%d\n", s.Y, s.X, s.Bells, len(s.Snaps))
	return 0
}

// runZhostonly is tools/zhostonly.py.
func runZhostonly(args []string) int {
	quiet := false
	var files []string
	for _, a := range args {
		if a == "--quiet" {
			quiet = true
			continue
		}
		files = append(files, a)
	}
	if len(files) != 1 {
		fmt.Fprintln(os.Stderr, "usage: slimtools zhostonly <file> [--quiet]")
		return 1
	}
	if err := harness.ZHostOnly(files[0], quiet, os.Stdout); err != nil {
		// The findings go to stdout, as the Python's print does; only the
		// three refusals that cannot proceed are an error message.
		if strings.HasPrefix(err.Error(), "zhostonly: the host block") ||
			strings.HasPrefix(err.Error(), "zhostonly: musl_suspend") {
			fmt.Fprintln(os.Stderr, err)
		}
		return 1
	}
	return 0
}

// runZargv is tools/zargv.py.
func runZargv(args []string) int {
	if len(args) != 2 {
		fmt.Fprintln(os.Stderr, "usage: slimtools zargv <vim-binary> <outfile>")
		return 1
	}
	if err := harness.ZArgv(args[0], args[1], os.Stdout); err != nil {
		fmt.Fprintf(os.Stderr, "slimtools: %v\n", err)
		return 1
	}
	return 0
}

// runZexcmds is tools/zexcmds.py.
func runZexcmds(args []string) int {
	if len(args) != 3 {
		fmt.Fprintln(os.Stderr, "usage: slimtools zexcmds <vim-binary> <table> <outfile>")
		return 1
	}
	if err := harness.ZExCmds(args[0], args[1], args[2], os.Stdout); err != nil {
		fmt.Fprintf(os.Stderr, "slimtools: %v\n", err)
		return 1
	}
	return 0
}

// runZcases is tools/zcases.py.
func runZcases(args []string) int {
	if len(args) != 2 {
		fmt.Fprintln(os.Stderr, "usage: slimtools zcases <vim-binary> <outdir>")
		return 1
	}
	if err := harness.ZCases(args[0], args[1], os.Stdout); err != nil {
		fmt.Fprintf(os.Stderr, "slimtools: %v\n", err)
		return 1
	}
	return 0
}

// runZtermcheck is tools/ztermcheck.py.
func runZtermcheck(args []string) int {
	if len(args) != 2 {
		fmt.Fprintln(os.Stderr, "usage: slimtools ztermcheck <vim-binary> <outfile>")
		return 1
	}
	if err := harness.ZTermCheck(args[0], args[1], os.Stdout); err != nil {
		fmt.Fprintf(os.Stderr, "slimtools: %v\n", err)
		return 1
	}
	return 0
}

// runZpty is tools/zpty.py.
func runZpty(args []string) int {
	if len(args) != 2 {
		fmt.Fprintln(os.Stderr, "usage: slimtools zpty <vim-binary> <outfile>")
		return 1
	}
	if err := harness.ZPty(args[0], args[1], os.Stdout); err != nil {
		return 1
	}
	return 0
}

// runZmemline is tools/zmemline.py.
func runZmemline(args []string) int {
	if len(args) != 2 {
		fmt.Fprintln(os.Stderr, "usage: slimtools zmemline <vim-binary> <outdir>")
		return 1
	}
	if err := harness.ZMemline(args[0], args[1], os.Stdout); err != nil {
		return 1
	}
	return 0
}

// runZcompare is tools/zcompare.py.
func runZcompare(args []string) int {
	if len(args) == 3 && args[0] == "--declared" {
		n, err := strconv.Atoi(args[2])
		if err != nil {
			fmt.Fprintln(os.Stderr, "usage: slimtools zcompare --declared <delta> <phase>")
			return 1
		}
		_, own, err := harness.ZDeclared(args[1], n)
		if err != nil {
			fmt.Fprintf(os.Stderr, "slimtools: %v\n", err)
			return 1
		}
		for _, s := range own {
			fmt.Println(s)
		}
		return 0
	}
	if len(args) != 4 {
		fmt.Fprintln(os.Stderr,
			"usage: slimtools zcompare <base> <new> <delta> <phase> | --declared <delta> <phase>")
		return 1
	}
	n, err := strconv.Atoi(args[3])
	if err != nil {
		fmt.Fprintf(os.Stderr, "slimtools: %v\n", err)
		return 1
	}
	if err := harness.ZCompare(args[0], args[1], args[2], n, os.Stdout); err != nil {
		return 1
	}
	return 0
}

// runZrecord is tools/zrecord.sh.
func runZrecord(args []string) int {
	if len(args) != 3 {
		fmt.Fprintln(os.Stderr, "usage: slimtools zrecord <binary> <source> <outdir>")
		return 1
	}
	if err := harness.ZRecord(args[0], args[1], args[2], os.Stdout); err != nil {
		return 1
	}
	return 0
}

// runCmdnames is create_cmdidxs.names(): the Ex command table, in order.  It
// is exposed so the parse can be compared against the Python's without
// running the editor six hundred times.
func runCmdnames(args []string) int {
	if len(args) != 1 {
		fmt.Fprintln(os.Stderr, "usage: slimtools cmdnames <file>")
		return 1
	}
	names, err := harness.CommandNames(args[0])
	if err != nil {
		fmt.Fprintf(os.Stderr, "%v\n", err)
		return 1
	}
	for _, n := range names {
		fmt.Println(n)
	}
	return 0
}

// runCmdidxs is tools/create_cmdidxs.py.  No flag prints the generated block,
// --check requires the file's block to match it, --update rewrites it.
func runCmdidxs(args []string) int {
	var path, mode string
	for _, a := range args {
		if strings.HasPrefix(a, "--") {
			mode = a
		} else if path == "" {
			path = a
		}
	}
	if path == "" {
		fmt.Fprintln(os.Stderr, "usage: slimtools cmdidxs <file> [--check|--update]")
		return 1
	}
	switch mode {
	case "--check":
		if err := harness.CheckCmdIdxs(path); err != nil {
			fmt.Fprintf(os.Stderr, "%v\n", err)
			return 1
		}
		fmt.Printf("%s: ex_cmdidxs block reproduces byte for byte\n", path)
	case "--update":
		if err := harness.UpdateCmdIdxs(path); err != nil {
			fmt.Fprintf(os.Stderr, "%v\n", err)
			return 1
		}
	default:
		names, err := harness.CommandNames(path)
		if err != nil {
			fmt.Fprintf(os.Stderr, "%v\n", err)
			return 1
		}
		fmt.Print(harness.GenerateCmdIdxs(names))
	}
	return 0
}

// runMuslctype is tools/muslctype.py --verify: compile the vendored musl block
// out of the source the phase produced and hold it to this machine's libc.
func runMuslctype(args []string) int {
	var path string
	verify := false
	for _, a := range args {
		if a == "--verify" {
			verify = true
		} else if path == "" {
			path = a
		}
	}
	if path == "" || !verify {
		fmt.Fprintln(os.Stderr, "usage: slimtools muslctype --verify <file.c>")
		return 1
	}
	if err := harness.MuslCtypeVerify(path, os.Stdout); err != nil {
		// A message that already starts with the two-space tag is the tool's
		// own reporting line and is printed as it stands; anything else is an
		// ordinary error.
		if s := err.Error(); strings.HasPrefix(s, "  ") {
			fmt.Fprintln(os.Stdout, s)
		} else if err != harness.ErrReported {
			fmt.Fprintln(os.Stderr, err)
		}
		return 1
	}
	return 0
}

// runMuslcase is tools/muslcase.py: --generate writes the convertStruct tables
// derived from this machine's libc, --verify holds a source's shipped tables
// to it over every codepoint.
func runMuslcase(args []string) int {
	var path, mode string
	for _, a := range args {
		if strings.HasPrefix(a, "--") {
			mode = a
		} else if path == "" {
			path = a
		}
	}
	switch {
	case mode == "--generate" && path == "":
		text, err := harness.MuslCaseGenerate()
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			return 1
		}
		fmt.Print(text)
	case mode == "--verify" && path != "":
		if err := harness.MuslCaseVerify(path, os.Stdout); err != nil {
			if err != harness.ErrReported {
				fmt.Fprintln(os.Stderr, err)
			}
			return 1
		}
	default:
		fmt.Fprintln(os.Stderr, "usage: slimtools muslcase --generate | --verify <file.c>")
		return 1
	}
	return 0
}

// runStarcheck is tools/starcheck.py: does `*` still find the next whole word?
func runStarcheck(args []string) int {
	if len(args) != 1 {
		fmt.Fprintln(os.Stderr, "usage: slimtools starcheck <vim-binary>")
		return 1
	}
	if err := harness.StarCheck(args[0], os.Stdout); err != nil {
		if err != harness.ErrReported {
			fmt.Fprintln(os.Stderr, err)
		}
		return 1
	}
	return 0
}

// runTermrestore is tools/termrestore.py: does a killed editor put the
// terminal back?
func runTermrestore(args []string) int {
	if len(args) != 1 {
		fmt.Fprintln(os.Stderr, "usage: slimtools termrestore <vim-binary>")
		return 1
	}
	if err := harness.TermRestore(args[0], os.Stdout); err != nil {
		if err != harness.ErrReported {
			fmt.Fprintln(os.Stderr, err)
		}
		return 1
	}
	return 0
}

// runComplcheck is tools/complcheck.py: insert mode still inserts, and CTRL-X
// CTRL-N no longer completes.
func runComplcheck(args []string) int {
	if len(args) != 1 {
		fmt.Fprintln(os.Stderr, "usage: slimtools complcheck <vim-binary>")
		return 1
	}
	if err := harness.ComplCheck(args[0], os.Stdout); err != nil {
		if err != harness.ErrReported {
			fmt.Fprintln(os.Stderr, err)
		}
		return 1
	}
	return 0
}

// runClicheck is tools/clicheck.py: every command-line option, the dropped ones
// unknown and the kept ones doing what they say.
func runClicheck(args []string) int {
	if len(args) != 1 {
		fmt.Fprintln(os.Stderr, "usage: slimtools clicheck <vim-binary>")
		return 1
	}
	if err := harness.CliCheck(args[0], os.Stdout); err != nil {
		if err != harness.ErrReported {
			fmt.Fprintln(os.Stderr, err)
		}
		return 1
	}
	return 0
}
