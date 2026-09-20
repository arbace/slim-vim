package cut

import (
	"fmt"
	"io"
	"regexp"
	"strings"

	"slimvim.local/tools/internal/cutil"
)

var noinertLeft = regexp.MustCompile(`"(browse|confirm)", \d, TRUE|modec == 't'|CMD_behave:`)

// NoInert removes the modifiers, mapping modes and argument lists that do
// nothing in this build: :browse, :confirm, the terminal-job mapping mode and
// :behave's argument list.
func NoInert(text []byte, w io.Writer) ([]byte, error) {
	e := ed{"noinert", w}
	var err error

	text, err = e.inFunction(text, "parse_command_modifiers", func(seg []byte) ([]byte, error) {
		seg, err := cutil.DropIf(seg,
			`(?m)^[ \t]*if \(checkforcmd_opt\(&eap->cmd, "browse", 3, TRUE\)\)$`, 1)
		if err != nil {
			return nil, err
		}
		e.say("the :browse modifier")
		return e.subOnce(seg, `^[ \t]*case 'c':\n`+
			`[ \t]*if \(!checkforcmd_opt\(&eap->cmd, "confirm", 4, TRUE\)\)\n`+
			`[ \t]*\{\n[ \t]*break;\n[ \t]*\}\n[ \t]*continue;\n\n`,
			"the :confirm modifier")
	})
	if err != nil {
		return nil, err
	}

	text, err = e.inFunction(text, "get_map_mode", func(seg []byte) ([]byte, error) {
		return e.subOnce(seg,
			`^[ \t]*else if \(modec == 't'\)\n[ \t]*\{\n[ \t]*mode = MODE_TERMINAL;\n[ \t]*\}\n`,
			"get_map_mode's 't'")
	})
	if err != nil {
		return nil, err
	}

	text, err = e.inFunction(text, "map_mode_to_chars", func(seg []byte) ([]byte, error) {
		return e.subOnce(seg,
			`^[ \t]*if \(mode & MODE_TERMINAL\)\n[ \t]*\{\n[ \t]*ga_append\(&mapmode, 't'\);\n[ \t]*\}\n`,
			"map_mode_to_chars printing 't'")
	})
	if err != nil {
		return nil, err
	}

	text, err = e.inFunction(text, "set_context_by_cmdname", func(seg []byte) ([]byte, error) {
		var err error
		for _, name := range []string{"browse", "confirm", "tmap", "tnoremap", "tunmap", "tmapclear"} {
			seg, err = e.subOnce(seg, `^[ \t]*case CMD_`+name+`:\n`, "completion for :"+name)
			if err != nil {
				return nil, err
			}
		}
		return e.subOnce(seg, `^[ \t]*case CMD_behave:\n[ \t]*xp->xp_context = EXPAND_BEHAVE;\n`+
			`[ \t]*xp->xp_pattern = arg;\n[ \t]*break;\n\n`, "completion for :behave")
	})
	if err != nil {
		return nil, err
	}

	text, err = e.literal(text, "        {EXPAND_BEHAVE, get_behave_arg, TRUE, TRUE},\n", "",
		":behave's argument list", 1)
	if err != nil {
		return nil, err
	}

	if left := noinertLeft.FindAllString(string(text), -1); len(left) > 0 {
		return nil, fmt.Errorf("noinert: still present after the cut: %s",
			strings.Join(left, ", "))
	}

	e.say("no modifier, mapping mode or argument list that does nothing")
	return text, nil
}
