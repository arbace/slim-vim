package sweep

import (
	"fmt"
	"os"
	"strings"

	"slimvim.local/tools/internal/canon"
	"slimvim.local/tools/internal/dead"
)

// Each adapter takes the current text and returns the new text and the line
// the driver reports for it -- which is the tool's LAST line of stdout, since
// that is what sweep.sh's `said=$("$@" | tail -1)` captures.
//
// Five of the seven are pure functions of the bytes and never touch the file.
// Two must: deadsweep asks gcc about the file and deadenums asks
// tools/enumvals.sh, so those write the current text out first.  That is the
// whole of what a round still does with the disk, against seven writes and
// seven reads per round in the shell.

func runDeadsweep(path string, cur []byte) ([]byte, string, error) {
	if err := os.WriteFile(path, cur, 0o644); err != nil {
		return cur, "", err
	}
	out, c, err := dead.DeadSweep(path, CompileDir)
	if err != nil {
		return cur, "", err
	}
	return out, fmt.Sprintf(
		"prototypes %d, functions %d, variables %d, left alone %d -- %d lines removed",
		c.Proto, c.Func, c.Var, c.Other, c.Lines), nil
}

func runDeadprotos(cur []byte) ([]byte, string, error) {
	out, dropped := dead.DeadProtos(cur)
	tail := ""
	if len(dropped) > 0 {
		n := len(dropped)
		if n > 4 {
			n = 4
		}
		names := make([]string, n)
		for i := 0; i < n; i++ {
			names[i] = string(dropped[i])
		}
		tail = ": " + strings.Join(names, ", ")
		if len(dropped) > 4 {
			tail += "..."
		}
	}
	if len(dropped) == 0 {
		out = cur // the Python writes only when it dropped something
	}
	return out, fmt.Sprintf("  deadprotos   %d declared, never defined, never called%s",
		len(dropped), tail), nil
}

func runTypereach(cur []byte) ([]byte, string, error) {
	defs, deadIdx := dead.TypeReach(cur)
	line := fmt.Sprintf("%d type definitions, %d unreachable", len(defs), len(deadIdx))
	if len(deadIdx) == 0 {
		return cur, line, nil
	}
	// The last line the Python prints when it deletes is this one, and it is
	// what the driver reports.
	return dead.DeleteDefs(cur, defs, deadIdx),
		fmt.Sprintf("deleted %d definitions", len(deadIdx)), nil
}

func runFuncreach(cur []byte) ([]byte, string, error) {
	defs, reachable, deadNames, deadLines := dead.FuncReach(cur)
	if len(defs) < dead.MinDefinitions {
		// The floor exits 1 with a message on stderr and the sweep carries
		// on: pass() masks the status.  Nothing is changed.
		return cur, fmt.Sprintf("  funcreach    only %d definitions found", len(defs)), nil
	}
	line := fmt.Sprintf("  funcreach    %d definitions, %d reachable, %d not (%d lines)",
		len(defs), reachable, len(deadNames), deadLines)
	if len(deadNames) == 0 {
		return cur, line, nil
	}
	n := len(deadNames)
	if n > 6 {
		n = 6
	}
	tail := ""
	if len(deadNames) > 6 {
		tail = "..."
	}
	return dead.DeleteFuncs(cur, defs, deadNames),
		fmt.Sprintf("  funcreach    deleted: %s%s", strings.Join(deadNames[:n], ", "), tail), nil
}

func runDeadfields(cur []byte) ([]byte, string, error) {
	cands, refused := dead.DeadFields(cur)
	if refused {
		return cur, "  deadfields   not while ml_recover() can read a swap file: " +
			"a struct layout is still a disk format", nil
	}
	line := fmt.Sprintf("  deadfields   %d fields nothing outside a type names", len(cands))
	if len(cands) == 0 {
		return cur, line, nil
	}
	return dead.DeleteFields(cur, cands), line, nil
}

func runDeadenums(path string, cur []byte, vals string) ([]byte, string, error) {
	if err := os.WriteFile(path, cur, 0o644); err != nil {
		return cur, "", err
	}
	v := dead.LoadVals(vals)
	edits, st := dead.AnalyseEnums(cur, v)
	if _, err := os.Stat(vals); err != nil && (st.DeadTotal > 0 || st.Unpinnable > 0) {
		// First need: the values of THIS text, before anything is deleted.
		if err := dead.DumpVals(path, vals); err != nil {
			return cur, "", err
		}
		v = dead.LoadVals(vals)
		edits, st = dead.AnalyseEnums(cur, v)
	}
	stuck, unpin := "", ""
	if st.Stuck > 0 {
		stuck = fmt.Sprintf("; %d in enums where every constant is dead and the type is in "+
			"use, which cannot be expressed", st.Stuck)
	}
	if st.Unpinnable > 0 {
		unpin = fmt.Sprintf("; %d kept before a survivor DWARF has no value for", st.Unpinnable)
	}
	line := fmt.Sprintf("  deadenums    %d enumerators nothing mentions, %d survivors pinned%s%s",
		st.DeadTotal, st.Pinned, stuck, unpin)
	if len(edits) == 0 {
		return cur, line, nil
	}
	return dead.ApplyEnumEdits(cur, edits), line, nil
}

func runCanon(cur []byte) ([]byte, string, error) {
	out, _, changed, _ := canon.Fixpoint(cur, true)
	if changed {
		return out, "canon changed it", nil
	}
	return out, "canon settled", nil
}
