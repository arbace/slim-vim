package main

import (
	"fmt"
	"os"
	"strings"

	"slimvim.local/tools/internal/cut"
)

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
