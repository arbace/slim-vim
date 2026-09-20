package dead

import (
	"bytes"
	"fmt"
	"regexp"
	"sort"
	"strconv"
)

var (
	nvRow = regexp.MustCompile(`(?m)^[ \t]*\{[^\n]*\}[ \t]*,?[ \t]*$`)
	nvNum = regexp.MustCompile(`(?m)^[ \t]*(\d+),?[ \t]*$`)
)

// NvIdxCheck asserts that nv_cmd_idx[] still indexes nv_cmds[]: one entry per
// row, each row once.
//
// Normal mode finds a key's handler through nv_cmd_idx[], a sorted index into
// nv_cmds[] that upstream generates and this tree writes into the C as a
// constant.  Nothing recomputes it and the compiler cannot see that it is
// wrong: delete a row from nv_cmds[] and the index still compiles, still has
// its old length, and still points at row numbers that now belong to other
// keys.  The mouse phase did exactly that -- 22 rows deleted -- and
// normal-mode arrows stopped working for twelve phases, because every harness
// that typed an arrow typed it in insert mode, which decodes keys in a switch.
//
// So this asks the one thing a deletion always breaks: the index must be a
// permutation of 0..len(nv_cmds)-1.  It does not check the sort order, which
// would mean evaluating each row's key expression, and a table whose rows are
// only ever pointed at nv_error never needs it.
func NvIdxCheck(text []byte) (line string, ok bool) {
	a := bytes.Index(text, []byte("} nv_cmds[] ="))
	i := bytes.Index(text, []byte("nv_cmd_idx[] ="))
	if a < 0 || i < 0 {
		return "  nvidx        nv_cmds[] or nv_cmd_idx[] is not where this expects", false
	}
	endA := bytes.Index(text[a:], []byte("\n};"))
	endI := bytes.Index(text[i:], []byte("\n};"))
	if endA < 0 || endI < 0 {
		return "  nvidx        nv_cmds[] or nv_cmd_idx[] is not where this expects", false
	}
	rows := len(nvRow.FindAll(text[a:a+endA], -1))

	var idx []int
	for _, m := range nvNum.FindAllSubmatch(text[i:i+endI], -1) {
		n, err := strconv.Atoi(string(m[1]))
		if err != nil {
			continue
		}
		idx = append(idx, n)
	}
	sorted := append([]int(nil), idx...)
	sort.Ints(sorted)
	perm := len(sorted) == rows
	if perm {
		for k, v := range sorted {
			if v != k {
				perm = false
				break
			}
		}
	}
	if !perm {
		return fmt.Sprintf("  nvidx        nv_cmd_idx[] has %d entries for %d rows of nv_cmds[] -- "+
			"a row was deleted, and every key past it resolves to the wrong one",
			len(idx), rows), false
	}
	return fmt.Sprintf("  nvidx        nv_cmd_idx[] indexes each of the %d rows of nv_cmds[] once",
		rows), true
}
