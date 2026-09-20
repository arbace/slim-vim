package edit

import (
	"io"

	"slimvim.local/tools/internal/cutil"
)

// opFunctionCase is g@'s arm in do_pending_operator.  It is matched as a
// literal because it is a whole block with its own braces and a saved
// redo_VIsual, and a pattern for it would be longer than the block.
const opFunctionCase = "        case OP_FUNCTION:\n" +
	"            {\n" +
	"                redo_VIsual_T   save_redo_VIsual = redo_VIsual;\n" +
	"\n" +
	"                op_function(oap);\n" +
	"\n" +
	"                redo_VIsual = save_redo_VIsual;\n" +
	"                break;\n" +
	"            }\n" +
	"\n"

// Whim65 takes g? and g@ -- rot13 and the operator function -- and an empty
// call left behind by completion.
func Whim65(text []byte, w io.Writer) ([]byte, error) {
	e := New("norot13", text, w)

	// The case labels are scoped to nv_g_cmd: another switch entirely has '?'
	// and '@' next to each other, and an unscoped edit would have two places to
	// choose from.
	e.InFunction("nv_g_cmd", func(e *E) {
		e.Sub(`(?m)^([ \t]*case 'U':\n)[ \t]*case '\?':\n[ \t]*case '@':\n`, "${1}", 1, "g? and g@ as operators")
	})
	e.InFunction("nv_search", func(e *E) {
		e.DropIf(`(?m)^[ \t]*if \(cap->cmdchar == '\?' && cap->oap->op_type == OP_ROT13\)$`,
			"g? reaching the operator with a search pending")
	})
	e.InFunction("do_pending_operator", func(e *E) {
		e.Lines(`case OP_ROT13:`, 1, "rot13 sharing the case-change dispatch")
	})
	e.InFunction("swapchar", func(e *E) {
		e.DropIf(`(?m)^[ \t]*if \(c >= 0x80 && op_type == OP_ROT13\)$`, "rot13 refusing a multibyte character")
		e.FoldNeverRepeat(`(?m)^[ \t]*if \(op_type == OP_ROT13\)$`, 2, "rot13 rotating a letter")
	})

	// The operator function.
	e.InFunction("do_pending_operator", func(e *E) {
		e.Literal(opFunctionCase, "", "g@ reaching the operator function")
	})
	e.InFunction("do_pending_operator", func(e *E) {
		e.Literal(" || oap->op_type == OP_FUNCTION", "", "the operator function deciding whether the motion is inclusive")
	})
	e.deleteDefinition("op_function", "op_function, which only said the eval feature is not available")

	// An empty call.
	e.InFunction("edit", func(e *E) {
		e.Sub(`(?m)^([ \t]*case Ctrl_X:\n)[ \t]*ins_ctrl_x\(\);\n`, "${1}", 1, "CTRL-X calling an empty function")
	})
	e.deleteDefinition("ins_ctrl_x", "ins_ctrl_x, whose body has been empty since completion went")
	return e.Done()
}

// deleteDefinition removes a file-scope definition and says so, refusing if it
// is not there.  The refusal names the function, because "not defined" about a
// function the phase is removing on purpose is the case where an earlier phase
// has already taken it and this one is about to claim work it did not do.
func (e *E) deleteDefinition(name, what string) {
	if e.Failed() {
		return
	}
	out, gone := cutil.DeleteDefinition(e.Text(), name)
	if !gone {
		e.Refuse("%s is not defined", name)
		return
	}
	e.Set(out)
	e.say(what)
}

func init() { register("whim65", Whim65) }
