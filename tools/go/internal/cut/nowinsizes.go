package cut

import (
	"fmt"
	"io"
	"regexp"
	"strings"
)

var winsizeDefaults = []struct{ typ, name, value string }{
	{"int", "p_sb", "FALSE"},
	{"int", "p_spr", "FALSE"},
	{"char_u *", "p_spk", `(char_u *)"cursor"`},
	{"int", "p_ea", "TRUE"},
	{"char_u *", "p_ead", `(char_u *)"both"`},
	{"long", "p_wh", "1L"},
	{"long", "p_wmh", "1L"},
	{"long", "p_wiw", "20L"},
	{"long", "p_wmw", "1L"},
}

// wfOpt is `-> w_onebuf_opt.wo_wfh ` / `...wfw `, the spelling the macro
// expander leaves.
func wfOpt(h string) string { return `-> w_onebuf_opt\.wo_wf` + h + ` ` }

var woWf = regexp.MustCompile(`\bwo_wf[hw]\b`)

// NoWinSizes fixes the window-size options at their defaults and stops any
// window being fixed against another.
func NoWinSizes(text []byte, w io.Writer) ([]byte, error) {
	e := ed{"nowinsizes", w}
	var err error

	// Go's QuoteMeta and Python's re.escape DO NOT AGREE: a space is in
	// Python's special set and comes back as `\ `, where Go leaves it alone.
	// So the Python's `.replace(r'\ ', r'\s*')` is not the no-op it looks
	// like -- it turns `char_u\ \*` into `char_u\s*\*`, and the pattern then
	// matches the declaration however it is spaced.  Measured: without it,
	// `char_u *` matched 0 of 84 inputs while `int` and `long` matched every
	// one, because only the pointer types have a space in them.
	for _, d := range winsizeDefaults {
		typ := strings.ReplaceAll(regexp.QuoteMeta(d.typ), " ", `\s*`)
		pat := `(?m)^(static\s+` + typ + `\s*` + d.name + `);$`
		text, err = e.subCountRepl(text, pat, "${1} = "+d.value+";",
			fmt.Sprintf("%s keeps its default, %s", d.name, d.value), 1)
		if err != nil {
			return nil, err
		}
	}

	text, err = e.inFunction(text, "win_split_ins", func(s []byte) ([]byte, error) {
		s, err := e.foldNever(s, `^[ \t]*if \(oldwin`+wfOpt("w")+`\)$`,
			"win_split_ins keeping a fixed width")
		if err != nil {
			return nil, err
		}
		return e.foldNever(s, `^[ \t]*if \(oldwin`+wfOpt("h")+`\)$`,
			"win_split_ins keeping a fixed height")
	})
	if err != nil {
		return nil, err
	}

	text, err = e.inFunction(text, "winframe_remove", func(s []byte) ([]byte, error) {
		s, err := e.foldNever(s,
			`^[ \t]*if \(frp2->fr_win != NULL && frp2->fr_win`+wfOpt("h")+`\)$`,
			"winframe_remove passing over a fixed height")
		if err != nil {
			return nil, err
		}
		return e.foldNever(s,
			`^[ \t]*if \(frp2->fr_win != NULL && frp2->fr_win`+wfOpt("w")+`\)$`,
			"winframe_remove passing over a fixed width")
	})
	if err != nil {
		return nil, err
	}

	for _, f := range []struct{ name, h string }{
		{"frame_fixed_height", "h"}, {"frame_fixed_width", "w"},
	} {
		f := f
		text, err = e.inFunction(text, f.name, func(s []byte) ([]byte, error) {
			return e.literal(s,
				"return frp->fr_win-> w_onebuf_opt.wo_wf"+f.h+" ;", "return FALSE;",
				f.name+" of a window", 1)
		})
		if err != nil {
			return nil, err
		}
	}

	for _, f := range []struct{ name, h, dim string }{
		{"frame_setheight", "h", "height"}, {"frame_setwidth", "w", "width"},
	} {
		f := f
		text, err = e.inFunction(text, f.name, func(s []byte) ([]byte, error) {
			s, err := e.foldNever(s,
				`^[ \t]*if \(frp != curfrp && frp->fr_win != NULL && frp->fr_win`+wfOpt(f.h)+`\)$`,
				fmt.Sprintf("frame_set%s reserving a fixed %s", f.dim, f.dim))
			if err != nil {
				return nil, err
			}
			return e.foldNever(s,
				`^[ \t]*if \(room_reserved > 0 && frp->fr_win != NULL && frp->fr_win`+wfOpt(f.h)+`\)$`,
				fmt.Sprintf("frame_set%s sparing a fixed %s", f.dim, f.dim))
		})
		if err != nil {
			return nil, err
		}
	}

	text, err = e.inFunction(text, "command_height", func(s []byte) ([]byte, error) {
		return e.subOnce(s,
			`^[ \t]*while \(frp->fr_prev != NULL && frp->fr_layout == FR_LEAF && frp->fr_win`+
				wfOpt("h")+`\)\n[ \t]*\{\n[ \t]*frp = frp->fr_prev;\n[ \t]*\}\n\n`,
			"command_height stepping over fixed heights")
	})
	if err != nil {
		return nil, err
	}

	text, err = e.inFunction(text, "win_enter_ext", func(s []byte) ([]byte, error) {
		s, err := e.literal(s, " && !curwin-> w_onebuf_opt.wo_wfh ", "",
			"win_enter_ext sparing a fixed height", 1)
		if err != nil {
			return nil, err
		}
		return e.literal(s, " && !curwin-> w_onebuf_opt.wo_wfw ", "",
			"win_enter_ext sparing a fixed width", 1)
	})
	if err != nil {
		return nil, err
	}

	text, err = e.inFunction(text, "close_buffer", func(s []byte) ([]byte, error) {
		return e.dropIfUncounted(s,
			`^[ \t]*if \(bt_quickfix\(buf\) && win_valid && win->w_buffer == buf\)$`,
			"close_buffer clearing a quickfix height")
	})
	if err != nil {
		return nil, err
	}

	for _, v := range []struct{ wv, fld string }{{"WFH", "wfh"}, {"WFW", "wfw"}} {
		text, err = e.subOnce(text,
			`^[ \t]*case   \(idopt_T\)\(PV_WIN \+ \(int\)\(WV_`+v.wv+`\)\)  :\n`+
				`[ \t]*return \(char_u \*\)&\(curwin-> w_onebuf_opt\.wo_`+v.fld+` \);\n`,
			"get_varp for WV_"+v.wv)
		if err != nil {
			return nil, err
		}
	}

	if n := len(woWf.FindAll(text, -1)); n != 2 {
		return nil, fmt.Errorf("nowinsizes: wo_wfh and wo_wfw outside their declarations "+
			"-- %d mentions, expected 2", n)
	}

	e.say("the sizes are fixed at their defaults, and no window is fixed against another")
	return text, nil
}
