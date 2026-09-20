package edit

import (
	"fmt"
	"io"
)

// langmapCmds are the four commands that make a language mapping.  A row is
// pointed at ex_ni rather than deleted, which is this table's own rule.
var langmapCmds = []struct{ name, handler string }{
	{"lmap", "ex_map"},
	{"lnoremap", "ex_map"},
	{"lunmap", "ex_unmap"},
	{"lmapclear", "ex_mapclear"},
}

// Whim58 takes language mappings: the four commands, the two CTRL-^ toggles,
// and every place a mode flag said a key was being read through one.
func Whim58(text []byte, w io.Writer) ([]byte, error) {
	e := New("nolangmap", text, w)

	for _, c := range langmapCmds {
		e.Sub(fmt.Sprintf(`(?m)^([ \t]*\[CMD_%s\] = \{\(char_u \*\)"%s", sizeof\("%s"\) - 1, )%s,`,
			c.name, c.name, c.name, c.handler), "${1}ex_ni,", 1,
			fmt.Sprintf(":%s points at ex_ni", c.name))
	}
	e.InFunction("set_context_by_cmdname", func(e *E) {
		for _, c := range langmapCmds {
			e.Cut(fmt.Sprintf(`(?m)^[ \t]*case CMD_%s:\n`, c.name), 1,
				fmt.Sprintf("no completion for :%s", c.name))
		}
	})

	// CTRL-^: consumed, and nothing to toggle.
	e.InFunction("edit", func(e *E) {
		e.DropIf(`(?m)^[ \t]*if \(curbuf->b_p_iminsert == B_IMODE_LMAP\)$`,
			"Insert mode starting with language mappings")
		e.Sub(`(?m)^([ \t]*case Ctrl_HAT:\n)[ \t]*ins_ctrl_hat\(\);\n`, "${1}", 1,
			"CTRL-^ in Insert mode toggling nothing")
	})
	e.InFunction("getcmdline_int", func(e *E) {
		e.DropIf(`(?m)^[ \t]*if \(firstc == '/' \|\| firstc == '\?' \|\| firstc == '@'\)$`,
			"a search line starting with language mappings")
		e.Sub(`(?m)^([ \t]*case Ctrl_HAT:\n)[ \t]*cmdline_toggle_langmap\([^\n]*\);\n`, "${1}", 1,
			"CTRL-^ on the command line toggling nothing")
	})
	e.InFunction("ex_append", func(e *E) {
		e.DropIf(`(?m)^[ \t]*if \(curbuf->b_p_iminsert == B_IMODE_LMAP\)$`,
			":append starting with language mappings")
	})
	e.InFunction("ins_insert", func(e *E) {
		e.LiteralN(" | (State & MODE_LANGMAP)", "", 2,
			"<Insert> keeping the language-mapping flag")
	})
	e.InFunction("normal_cmd_get_more_chars", func(e *E) {
		e.DropIf(`(?m)^[ \t]*if \(lang && curbuf->b_p_iminsert == B_IMODE_LMAP\)$`,
			"r, f and t reading through language mappings")
		e.DropIf(`(?m)^[ \t]*if \(langmap_active\)$`,
			"r, f and t restoring after language mappings")
	})
	e.InFunction("handle_mapping", func(e *E) {
		e.Literal(" && ((mp->m_mode & MODE_LANGMAP) == 0 || typebuf.tb_maplen == 0)", "",
			"a mapping refused only for a language mapping")
	})
	e.InFunction("vgetorpeek", func(e *E) {
		e.Literal("((State & (MODE_NORMAL | MODE_INSERT)) || State == MODE_LANGMAP)",
			"(State & (MODE_NORMAL | MODE_INSERT))",
			"the cursor placed while waiting in language-mapping state")
	})
	e.InFunction("get_map_mode", func(e *E) {
		e.FoldNever(`(?m)^[ \t]*else if \(modec == 'l'\)$`, "the 'l' map mode")
	})
	e.InFunction("map_mode_to_chars", func(e *E) {
		e.FoldNever(`(?m)^[ \t]*else if \(mode & MODE_LANGMAP\)$`, "listing a mapping as 'l'")
	})
	e.InFunction("win_redr_status", func(e *E) {
		e.DropIf(`(?m)^[ \t]*if \(\(NameBufflen = get_keymap_str\(wp, \(char_u \*\)"<%s>", NameBuff,  PATH_MAX \)\) > 0`,
			"the status line's <lang>")
	})
	return e.Done()
}

func init() { register("whim58", Whim58) }
