package main

import (
	"fmt"
	"os"
	"strconv"
	"strings"

	"slimvim.local/tools/internal/cut"
	"slimvim.local/tools/internal/cutil"
)

// oneFile is the shape most cutters have: one file argument, read it whole,
// transform it, write it back, and print what was done.  A cutter that cannot
// do its work REFUSES rather than reporting a job it did not do.
func oneFile(args []string, name string, f func([]byte, *os.File) ([]byte, error)) int {
	if len(args) != 1 {
		fmt.Fprintf(os.Stderr, "usage: slimtools %s <file>\n", name)
		return 1
	}
	text, err := os.ReadFile(args[0])
	if err != nil {
		fmt.Fprintf(os.Stderr, "slimtools: %v\n", err)
		return 1
	}
	out, err := f(text, os.Stdout)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	if err := writeFile(args[0], out); err != nil {
		fmt.Fprintf(os.Stderr, "slimtools: %v\n", err)
		return 1
	}
	return 0
}

func runNointro(args []string) int {
	return oneFile(args, "nointro", func(t []byte, w *os.File) ([]byte, error) {
		return cut.NoIntro(t, w)
	})
}

func runNoargv0(args []string) int {
	return oneFile(args, "noargv0", func(t []byte, w *os.File) ([]byte, error) {
		return cut.NoArgv0(t, w)
	})
}

func runNoglob(args []string) int {
	return oneFile(args, "noglob", func(t []byte, w *os.File) ([]byte, error) {
		return cut.NoGlob(t, w)
	})
}

// runFold exercises cutil's fold primitives directly.
//
// cutil.py has no CLI -- phase programs import it -- so this exists so the
// three can be compared against the Python on the same input and the same
// pattern.  A primitive that 142 call sites in pipes/ depend on should be
// testable without running a phase.
func runFold(args []string) int {
	if len(args) != 4 {
		fmt.Fprintln(os.Stderr, "usage: slimtools fold <always|never|dropif> <file> <pattern> <count>")
		return 2
	}
	kind, path, pattern := args[0], args[1], args[2]
	count, err := strconv.Atoi(args[3])
	if err != nil {
		fmt.Fprintf(os.Stderr, "slimtools: %v\n", err)
		return 2
	}
	text, err := os.ReadFile(path)
	if err != nil {
		fmt.Fprintf(os.Stderr, "slimtools: %v\n", err)
		return 1
	}
	var out []byte
	switch kind {
	case "always":
		out, err = cutil.FoldAlways(text, pattern, count)
	case "never":
		out, err = cutil.FoldNever(text, pattern, count)
	case "dropif":
		out, err = cutil.DropIf(text, pattern, count)
	default:
		fmt.Fprintln(os.Stderr, "usage: slimtools fold <always|never|dropif> <file> <pattern> <count>")
		return 2
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	if err := writeFile(path, out); err != nil {
		fmt.Fprintf(os.Stderr, "slimtools: %v\n", err)
		return 1
	}
	return 0
}

func runNowild(args []string) int {
	return oneFile(args, "nowild", func(t []byte, w *os.File) ([]byte, error) {
		return cut.NoWild(t, w)
	})
}

func runNoequiclass(args []string) int {
	return oneFile(args, "noequiclass", func(t []byte, w *os.File) ([]byte, error) {
		return cut.NoEquiClass(t, w)
	})
}

// runRetire is tools/retire.py.
func runRetire(args []string) int {
	if len(args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: slimtools retire <file> <command>...")
		return 1
	}
	path, names := args[0], args[1:]
	text, err := os.ReadFile(path)
	if err != nil {
		fmt.Fprintf(os.Stderr, "slimtools: %v\n", err)
		return 1
	}
	out, done, already, err := cut.Retire(text, names)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	if err := writeFile(path, out); err != nil {
		fmt.Fprintf(os.Stderr, "slimtools: %v\n", err)
		return 1
	}
	fmt.Printf("  retire       %d commands now answer \"not implemented\": %s\n",
		len(done), strings.Join(done, " "))
	if len(already) > 0 {
		fmt.Printf("  retire       %d were already inert: %s\n",
			len(already), strings.Join(already, " "))
	}
	return 0
}

// runDroplocal is tools/droplocal.py.
func runDroplocal(args []string) int {
	if len(args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: slimtools droplocal <file> <field>...")
		return 1
	}
	path := args[0]
	text, err := os.ReadFile(path)
	if err != nil {
		fmt.Fprintf(os.Stderr, "slimtools: %v\n", err)
		return 1
	}
	for _, bvar := range args[1:] {
		var n int
		text, n, err = cut.DropLocal(text, bvar)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			return 1
		}
		fmt.Printf("  droplocal    %-10s %d plumbing sites\n", bvar, n)
	}
	if err := writeFile(path, text); err != nil {
		fmt.Fprintf(os.Stderr, "slimtools: %v\n", err)
		return 1
	}
	return 0
}

// runDropoptions is tools/dropoptions.py.
func runDropoptions(args []string) int {
	strict, local := false, false
	var rest []string
	for _, a := range args {
		switch a {
		case "--strict":
			strict = true
		case "--local":
			local = true
		default:
			if strings.HasPrefix(a, "--") {
				continue
			}
			rest = append(rest, a)
		}
	}
	if len(rest) < 2 {
		fmt.Fprintln(os.Stderr, "usage: slimtools dropoptions <file> <option-name>...")
		return 1
	}
	path, names := rest[0], rest[1:]
	text, err := os.ReadFile(path)
	if err != nil {
		fmt.Fprintf(os.Stderr, "slimtools: %v\n", err)
		return 1
	}
	out, whitelisted, err := cut.DropOptions(text, names, strict, local)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	if err := writeFile(path, out); err != nil {
		fmt.Fprintf(os.Stderr, "slimtools: %v\n", err)
		return 1
	}
	fmt.Printf("  options      %d rows dropped (%s), %d modeline entries with them\n",
		len(names), strings.Join(names, ", "), whitelisted)
	return 0
}

func runNostat(args []string) int {
	return oneFile(args, "nostat", func(t []byte, w *os.File) ([]byte, error) {
		return cut.NoStat(t, w)
	})
}

func runNofnamemod(args []string) int {
	return oneFile(args, "nofnamemod", func(t []byte, w *os.File) ([]byte, error) {
		return cut.NoFnameMod(t, w)
	})
}

func runNotags(args []string) int {
	return oneFile(args, "notags", func(t []byte, w *os.File) ([]byte, error) {
		return cut.NoTags(t, w)
	})
}

func runNofind(args []string) int {
	return oneFile(args, "nofind", func(t []byte, w *os.File) ([]byte, error) {
		return cut.NoFind(t, w)
	})
}

func runNoterm(args []string) int {
	return oneFile(args, "noterm", func(t []byte, w *os.File) ([]byte, error) {
		return cut.NoTerm(t, w)
	})
}

func runNoshellout(args []string) int {
	return oneFile(args, "noshellout", func(t []byte, w *os.File) ([]byte, error) {
		return cut.NoShellOut(t, w)
	})
}

func runNoruntime(args []string) int {
	return oneFile(args, "noruntime", func(t []byte, w *os.File) ([]byte, error) {
		return cut.NoRuntime(t, w)
	})
}

func runNoabbr(args []string) int {
	return oneFile(args, "noabbr", func(t []byte, w *os.File) ([]byte, error) {
		return cut.NoAbbr(t, w)
	})
}

// runDropopts is tools/dropopts.py -- NOT tools/dropoptions.py, which is a
// different tool with a confusingly similar name: that one removes rows from
// options[], this one removes options from command_line_scan.
func runDropopts(args []string) int {
	if len(args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: slimtools dropopts <file> <-x|--long>...")
		return 1
	}
	path := args[0]
	text, err := os.ReadFile(path)
	if err != nil {
		fmt.Fprintf(os.Stderr, "slimtools: %v\n", err)
		return 1
	}
	out, err := cut.DropOpts(text, args[1:], os.Stdout)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	if err := writeFile(path, out); err != nil {
		fmt.Fprintf(os.Stderr, "slimtools: %v\n", err)
		return 1
	}
	return 0
}

func runNostartup(args []string) int {
	return oneFile(args, "nostartup", func(t []byte, w *os.File) ([]byte, error) {
		return cut.NoStartup(t, w)
	})
}

func runNohome(args []string) int {
	return oneFile(args, "nohome", func(t []byte, w *os.File) ([]byte, error) {
		return cut.NoHome(t, w)
	})
}

func runNocmdargs(args []string) int {
	return oneFile(args, "nocmdargs", func(t []byte, w *os.File) ([]byte, error) {
		return cut.NoCmdArgs(t, w)
	})
}

func runNoinert(args []string) int {
	return oneFile(args, "noinert", func(t []byte, w *os.File) ([]byte, error) {
		return cut.NoInert(t, w)
	})
}

func runNoarglist(args []string) int {
	return oneFile(args, "noarglist", func(t []byte, w *os.File) ([]byte, error) {
		return cut.NoArgList(t, w)
	})
}

func runNoinertopts(args []string) int {
	return oneFile(args, "noinertopts", func(t []byte, w *os.File) ([]byte, error) {
		return cut.NoInertOpts(t, w)
	})
}

func runNofencs(args []string) int {
	return oneFile(args, "nofencs", func(t []byte, w *os.File) ([]byte, error) {
		return cut.NoFencs(t, w)
	})
}

func runNocmdopts(args []string) int {
	return oneFile(args, "nocmdopts", func(t []byte, w *os.File) ([]byte, error) {
		return cut.NoCmdOpts(t, w)
	})
}

func runNobuflist(args []string) int {
	return oneFile(args, "nobuflist", func(t []byte, w *os.File) ([]byte, error) {
		return cut.NoBufList(t, w)
	})
}

func runNofloat(args []string) int {
	return oneFile(args, "nofloat", func(t []byte, w *os.File) ([]byte, error) {
		return cut.NoFloat(t, w)
	})
}

func runKeepbytes(args []string) int {
	return oneFile(args, "keepbytes", func(t []byte, w *os.File) ([]byte, error) {
		return cut.KeepBytes(t, w)
	})
}

func runOneoptset(args []string) int {
	return oneFile(args, "oneoptset", func(t []byte, w *os.File) ([]byte, error) {
		return cut.OneOptSet(t, w)
	})
}

func runOptreaders(args []string) int {
	return oneFile(args, "optreaders", func(t []byte, w *os.File) ([]byte, error) {
		return cut.OptReaders(t, w)
	})
}

func runNoowner(args []string) int {
	return oneFile(args, "noowner", func(t []byte, w *os.File) ([]byte, error) {
		return cut.NoOwner(t, w)
	})
}

func runNogetenv(args []string) int {
	return oneFile(args, "nogetenv", func(t []byte, w *os.File) ([]byte, error) {
		return cut.NoGetEnv(t, w)
	})
}

func runNochdir(args []string) int {
	return oneFile(args, "nochdir", func(t []byte, w *os.File) ([]byte, error) {
		return cut.NoChdir(t, w)
	})
}

func runNosignals(args []string) int {
	return oneFile(args, "nosignals", func(t []byte, w *os.File) ([]byte, error) {
		return cut.NoSignals(t, w)
	})
}

func runNoswap(args []string) int {
	return oneFile(args, "noswap", func(t []byte, w *os.File) ([]byte, error) {
		return cut.NoSwap(t, w)
	})
}

func runNorecover(args []string) int {
	return oneFile(args, "norecover", func(t []byte, w *os.File) ([]byte, error) {
		return cut.NoRecover(t, w)
	})
}

func runNoucmd(args []string) int {
	return oneFile(args, "noucmd", func(t []byte, w *os.File) ([]byte, error) {
		return cut.NoUcmd(t, w)
	})
}

func runNonfa(args []string) int {
	return oneFile(args, "nonfa", func(t []byte, w *os.File) ([]byte, error) {
		return cut.NoNfa(t, w)
	})
}

func runNolocale(args []string) int {
	return oneFile(args, "nolocale", func(t []byte, w *os.File) ([]byte, error) {
		return cut.NoLocale(t, w)
	})
}

func runNowinsizes(args []string) int {
	return oneFile(args, "nowinsizes", func(t []byte, w *os.File) ([]byte, error) {
		return cut.NoWinSizes(t, w)
	})
}

func runNocompl(args []string) int {
	return oneFile(args, "nocompl", func(t []byte, w *os.File) ([]byte, error) {
		return cut.NoCompl(t, w)
	})
}

func runNofenc(args []string) int {
	return oneFile(args, "nofenc", func(t []byte, w *os.File) ([]byte, error) {
		return cut.NoFenc(t, w)
	})
}

func runNoident(args []string) int {
	return oneFile(args, "noident", func(t []byte, w *os.File) ([]byte, error) {
		return cut.NoIdent(t, w)
	})
}

func runNobackup(args []string) int {
	return oneFile(args, "nobackup", func(t []byte, w *os.File) ([]byte, error) {
		return cut.NoBackup(t, w)
	})
}

func runNosession(args []string) int {
	return oneFile(args, "nosession", func(t []byte, w *os.File) ([]byte, error) {
		return cut.NoSession(t, w)
	})
}

func runOnebuffer(args []string) int {
	return oneFile(args, "onebuffer", func(t []byte, w *os.File) ([]byte, error) {
		return cut.OneBuffer(t, w)
	})
}

func runNocindent(args []string) int {
	return oneFile(args, "nocindent", func(t []byte, w *os.File) ([]byte, error) {
		return cut.NoCindent(t, w)
	})
}

func runNowildmenu(args []string) int {
	return oneFile(args, "nowildmenu", func(t []byte, w *os.File) ([]byte, error) {
		return cut.NoWildMenu(t, w)
	})
}

func runNomouse(args []string) int {
	return oneFile(args, "nomouse", func(t []byte, w *os.File) ([]byte, error) {
		return cut.NoMouse(t, w)
	})
}

func runNotabs(args []string) int {
	return oneFile(args, "notabs", func(t []byte, w *os.File) ([]byte, error) {
		return cut.NoTabs(t, w)
	})
}

func runNomemfile(args []string) int {
	return oneFile(args, "nomemfile", func(t []byte, w *os.File) ([]byte, error) {
		return cut.NoMemfile(t, w)
	})
}

func runNocomplkeys(args []string) int {
	return oneFile(args, "nocomplkeys", func(t []byte, w *os.File) ([]byte, error) {
		return cut.NoComplKeys(t, w)
	})
}

func runLfonly(args []string) int {
	return oneFile(args, "lfonly", func(t []byte, w *os.File) ([]byte, error) {
		return cut.LfOnly(t, w)
	})
}

func runNowindows(args []string) int {
	return oneFile(args, "nowindows", func(t []byte, w *os.File) ([]byte, error) {
		return cut.NoWindows(t, w)
	})
}

func runNoconv(args []string) int {
	return oneFile(args, "noconv", func(t []byte, w *os.File) ([]byte, error) {
		return cut.NoConv(t, w)
	})
}
