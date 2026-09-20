// Command slimtools is the Go implementation of what tools/*.py does.
//
// It is one binary with subcommands rather than one binary per tool, because
// every subcommand works on the same multi-megabyte file and the sweep runs
// thirteen of them to a fixpoint: as separate processes they re-read and
// re-scan that file thirteen times a round, which is the cost this rewrite is
// meant to remove.  Phase programs still name a distinct tools/go path per
// subcommand so that tools/implhash.sh keeps its per-tool invalidation.
//
// The subcommands are drop-in replacements: same argv, same rewrite-in-place,
// same stdout, same exit codes as the Python they stand in for.  tools/sweep.sh
// detects that a tool did something by taking sha256 of the file and by
// nothing else, so agreement means BYTE agreement and each one is held to it
// against real inputs -- see the difftest subcommand, which also reports how
// many of those inputs actually exercised the tool.
//
// The C front end (modernc.org/cc/v4, pinned and patched) is deliberately not
// used by any sweep subcommand.  Those run on text that six deleting tools
// have already cut and that nothing has compiled since, so it need not be
// valid C.  Parsing belongs to the phase edit programs, whose input is a
// boundary that compiled.
package main

import (
	"fmt"
	"os"
)

// A tool is one subcommand.  It is handed everything after the subcommand
// name and returns the process exit status.
type tool struct {
	run   func(args []string) int
	usage string
}

// order is the subcommands as they are listed, fixed rather than taken from
// the map: ranging a Go map yields a different order every run, which is the
// Go-shaped version of the determinism trap the Python tools avoid by sorting
// before they report.
var order = []string{
	"blankruns", "joinparens", "splitheads", "brace", "onestmt", "onedecl", "forcomma",
	"sweep", "canon",
	"deadsweep", "deadprotos", "typereach", "funcreach", "deadfields", "deadenums",
	"memo", "memokey", "phaserun", "snapshot", "verifypass", "specpass",
	"implhash", "parts", "symbols", "oracle", "phasecheck", "nvidx", "orphanopts", "exsweep", "cmdnames", "behaviour",
	"treedigest", "phasename", "restore", "stages", "whimdelta", "declared",
	"parse", "difftest",
}

var tools = map[string]tool{
	"blankruns":  {runBlankruns, "blankruns <file>"},
	"joinparens": {runJoinparens, "joinparens <file>"},
	"splitheads": {runSplitheads, "splitheads <file>"},
	"onestmt":    {runOnestmt, "onestmt <file>"},
	"onedecl":    {runOnedecl, "onedecl <file>"},
	"forcomma":   {runForcomma, "forcomma <file> [--check]"},
	"brace":      {runBrace, "brace <file>"},
	"canon":      {runCanon, "canon <file> [--once]"},
	"deadprotos": {runDeadprotos, "deadprotos <file>"},
	"typereach":  {runTypereach, "typereach <file> [--delete]"},
	"funcreach":  {runFuncreach, "funcreach <file> [--delete]"},
	"deadfields": {runDeadfields, "deadfields <file> [--delete]"},
	"deadenums":  {runDeadenums, "deadenums <file> <enumvals.txt> [--delete|--verify]"},
	"deadsweep":  {runDeadsweep, "deadsweep <file> [--keep <dir>]"},
	"sweep":      {runSweep, "sweep <file.c>"},
	"implhash":   {runImplhash, "implhash [--edit] <unit> [pipeline]"},
	"parts":      {runParts, "parts <pipeline> <unit>"},
	"symbols":    {runSymbols, "symbols <file.c> <outdir>"},
	"oracle":     {runOracle, "oracle <phase> <build-dir> <oracle-dir> [pipeline]"},
	"phasecheck": {runPhasecheck, "phasecheck <work-dir> <source> <before-dir>"},
	"nvidx":      {runNvidx, "nvidx <file>"},
	"orphanopts": {runOrphanopts, "orphanopts <file>"},
	"exsweep":    {runExsweep, "exsweep <vim-binary> <table> <outfile>"},
	"cmdnames":   {runCmdnames, "cmdnames <file>"},
	"behaviour":  {runBehaviour, "behaviour <vim-binary> <outdir>"},
	"phaserun":   {runPhaserun, "phaserun <pipeline> <unit> <work-dir>"},
	"treedigest": {runTreedigest, "treedigest <work-dir>"},
	"phasename":  {runPhasename, "phasename <phase> [pipeline]"},
	"restore":    {runRestore, "restore <in.tar> <dir>"},
	"stages":     {runStages, "stages <pipeline> [--of N | --check]"},
	"whimdelta":  {runWhimdelta, "whimdelta <binary> <source> --phase N"},
	"declared":   {runDeclared, "declared <delta-file> <phase>"},
	"memo":       {runMemo, "memo <unit> <work-dir> <build-dir> [pipeline]"},
	"snapshot":   {runSnapshot, "snapshot <dir> <out.tar> <out.sha256>"},
	"memokey":    {runMemokey, "memokey <unit> <build-dir> [pipeline]"},
	"verifypass": {runVerifypass, "verifypass <pipeline> [unit...]"},
	"specpass":   {runSpecpass, "specpass <pipeline>"},
	"parse":      {runParse, "parse <file.c>"},
	"difftest":   {runDifftest, "difftest <tool> <file>..."},
}

func main() {
	if len(os.Args) < 2 {
		usage()
	}
	t, ok := tools[os.Args[1]]
	if !ok {
		usage()
	}
	os.Exit(t.run(os.Args[2:]))
}

func usage() {
	fmt.Fprintln(os.Stderr, "usage: slimtools <subcommand> [args]")
	for _, name := range order {
		fmt.Fprintf(os.Stderr, "    %s\n", tools[name].usage)
	}
	os.Exit(2)
}
