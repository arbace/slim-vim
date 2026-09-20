package cut

import (
	"fmt"
	"io"
	"regexp"

	"slimvim.local/tools/internal/cutil"
)

var (
	optModeline   = regexp.MustCompile(`\bOPT_MODELINE\b`)
	doModelines   = regexp.MustCompile(`\bdo_modelines\(`)
	optLessThan   = `^[ \t]*else if \(nextchar == '<'\)$`
	ftIsEmptyIf   = `^[ \t]*if \(\*curbuf->b_p_ft == NUL\)$`
	mlSaveRestore = `^[ \t]*(?:curbuf->b_p_ml(?:_nobin)?|p_ml(?:_nobin)?) = [^;\n]*;\n`
)

// OneOptSet leaves :set as the only way to give an option a value.
func OneOptSet(text []byte, w io.Writer) ([]byte, error) {
	e := ed{"oneoptset", w}
	var err error

	text, err = e.inFunction(text, "ex_set", func(s []byte) ([]byte, error) {
		s, err := e.foldNever(s, `^[ \t]*if \(eap->cmdidx == CMD_setlocal\)$`,
			":setlocal choosing OPT_LOCAL")
		if err != nil {
			return nil, err
		}
		return e.foldNever(s, `^[ \t]*if \(eap->cmdidx == CMD_setglobal\)$`,
			":setglobal choosing OPT_GLOBAL")
	})
	if err != nil {
		return nil, err
	}

	text, err = e.inFunction(text, "set_context_by_cmdname", func(s []byte) ([]byte, error) {
		return e.subOnce(s,
			`^[ \t]*case CMD_setglobal:\n[ \t]*set_context_in_set_cmd\(xp, arg, OPT_GLOBAL\);\n`+
				`[ \t]*break;\n[ \t]*case CMD_setlocal:\n`+
				`[ \t]*set_context_in_set_cmd\(xp, arg, OPT_LOCAL\);\n[ \t]*break;\n`,
			"completion for :setglobal and :setlocal")
	})
	if err != nil {
		return nil, err
	}

	text, err = e.inFunction(text, "do_set_option", func(s []byte) ([]byte, error) {
		return e.literal(s, `(char_u *)"?=:!&<"`, `(char_u *)"?=:!&"`,
			":set accepting the < suffix", 1)
	})
	if err != nil {
		return nil, err
	}
	for _, f := range []struct{ name, kind string }{
		{"do_set_option_bool", "a boolean"},
		{"do_set_option_numeric", "a number"},
		{"stropt_get_newval", "a string"},
	} {
		kind := f.kind
		text, err = e.inFunction(text, f.name, func(s []byte) ([]byte, error) {
			return e.foldNever(s, optLessThan,
				":set opt< copying the global value of "+kind)
		})
		if err != nil {
			return nil, err
		}
	}

	// THE ORDER IS THE PYTHON'S, and it is load-bearing: each edit prints a
	// line as it succeeds, so grouping these into loops by shape -- which they
	// invite -- would emit the same lines in a different order and the
	// comparison would differ on every input that cuts.
	text, err = e.inFunction(text, "open_buffer", func(s []byte) ([]byte, error) {
		return e.literal(s, "            do_modelines(0);\n", "",
			"reading a buffer applying its modelines", 1)
	})
	if err != nil {
		return nil, err
	}

	text, err = e.inFunction(text, "do_write", func(s []byte) ([]byte, error) {
		return e.dropIf(s, ftIsEmptyIf, ":saveas applying modelines")
	})
	if err != nil {
		return nil, err
	}

	text, err = e.inFunction(text, "do_ecmd", func(s []byte) ([]byte, error) {
		return e.literal(s, "            do_modelines(OPT_WINONLY);\n\n", "",
			"editing a file applying its window modelines", 1)
	})
	if err != nil {
		return nil, err
	}

	text, err = e.inFunction(text, "set_rw_fname", func(s []byte) ([]byte, error) {
		return e.dropIf(s, ftIsEmptyIf, "naming a buffer applying modelines")
	})
	if err != nil {
		return nil, err
	}

	text, err = e.inFunction(text, "validate_opt_idx", func(s []byte) ([]byte, error) {
		return e.foldNever(s, `^[ \t]*if \(opt_flags & OPT_MODELINE\)$`,
			"the options a modeline may not set")
	})
	if err != nil {
		return nil, err
	}

	text, err = e.inFunction(text, "do_set", func(s []byte) ([]byte, error) {
		return e.literal(s, " && !(opt_flags & OPT_MODELINE)", "",
			":set all and :set termcap refused in a modeline", 2)
	})
	if err != nil {
		return nil, err
	}

	text, err = e.inFunction(text, "do_set_option_string", func(s []byte) ([]byte, error) {
		return e.literal(s, "(opt_flags & OPT_MODELINE) || ", "",
			"a modeline string option run securely", 1)
	})
	if err != nil {
		return nil, err
	}

	text, err = e.inFunction(text, "did_set_option", func(s []byte) ([]byte, error) {
		return e.literal(s, "(secure || (opt_flags & OPT_MODELINE))", "secure",
			"a modeline value marked insecure", 1)
	})
	if err != nil {
		return nil, err
	}

	text, err = e.inFunction(text, "do_filetype_autocmd", func(s []byte) ([]byte, error) {
		return e.foldNever(s,
			`^[ \t]*if \(\(opt_flags & OPT_MODELINE\) && !value_changed\)$`,
			"a modeline's unchanged 'filetype'")
	})
	if err != nil {
		return nil, err
	}

	text, err = e.inFunction(text, "set_options_bin", func(s []byte) ([]byte, error) {
		return e.subCount(s, mlSaveRestore, "'binary' saving and restoring 'modeline'", 6)
	})
	if err != nil {
		return nil, err
	}

	// b_p_ml_nobin is where 'binary' kept 'modeline' while it was off.  It is
	// not an option, so it has no get_varp() case and droplocal does not know
	// its shape: its declaration and its one copy go here, and p_ml_nobin,
	// with no reader left, goes to the sweep.
	text, err = e.subOnce(text, `^[ \t]*int[ \t]+b_p_ml_nobin;\n`,
		"the buffer's saved 'modeline' field")
	if err != nil {
		return nil, err
	}
	text, err = e.inFunction(text, "buf_copy_options", func(s []byte) ([]byte, error) {
		return e.subOnce(s, `^[ \t]*buf->b_p_ml_nobin = p_ml_nobin;\n`,
			"a new buffer copying the saved 'modeline'")
	})
	if err != nil {
		return nil, err
	}

	blanked := cutil.Blank(text)
	var dying [][2]int
	for _, n := range []string{"chk_modeline", "do_modelines"} {
		if a, z, ok := cutil.FindDefinition(text, blanked, n); ok {
			dying = append(dying, [2]int{a, z})
		}
	}
	live := 0
	for _, m := range optModeline.FindAllIndex(text, -1) {
		inDying := false
		for _, sp := range dying {
			if sp[0] <= m[0] && m[0] < sp[1] {
				inDying = true
				break
			}
		}
		if !inDying {
			live++
		}
	}
	if live != 1 {
		return nil, fmt.Errorf("oneoptset: OPT_MODELINE outside its enumerator and the "+
			"dying modeline code -- %d, expected 1", live)
	}
	if n := len(doModelines.FindAll(text, -1)); n != 2 {
		return nil, fmt.Errorf("oneoptset: do_modelines is still called")
	}

	e.say(":set is the only way to give an option a value")
	return text, nil
}
