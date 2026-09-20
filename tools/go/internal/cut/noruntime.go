package cut

import (
	"bytes"
	"fmt"
	"io"
	"regexp"
)

var runtimeCommands = []string{"help", "helpclose", "helptags", "runtime", "exusage", "viusage"}

// runtimePaths are the path strings the runtime layer assembles or defaults
// to.  Each becomes empty; NONE is deleted, so the options still exist and
// still report.
var runtimePaths = []string{
	`"$VIMRUNTIME/doc/help.txt"`,
	`"~/.vim,$VIM/vimfiles,$VIMRUNTIME,$VIM/vimfiles/after,~/.vim/after"`,
	`"$VIM/vimfiles,$VIMRUNTIME,$VIM/vimfiles/after"`,
	`"$XDG_CONFIG_HOME/vim,$VIM/vimfiles,$VIMRUNTIME,$VIM/vimfiles/after,` +
		`$XDG_CONFIG_HOME/vim/after"`,
	`"~/.config/vim,$VIM/vimfiles,$VIMRUNTIME,$VIM/vimfiles/after,` +
		`~/.config/vim/after"`,
}

const getenvTest = `vimruntime = ( strcmp((char *)(name), (char *)("VIMRUNTIME"))  == 0);`

// NoRuntime takes away the runtime directory: the commands that read it, the
// paths that name it, and the derivation that invented one.
//
// vim_getenv() derives a runtime directory from argv[0]'s directory when
// $VIMRUNTIME is unset.  Making the test never fire is enough -- the code
// behind it becomes unreachable and the sweep takes it.
func NoRuntime(text []byte, w io.Writer) ([]byte, error) {
	nCmd := 0
	for _, name := range runtimeCommands {
		pat := regexp.MustCompile(fmt.Sprintf(
			`(\[CMD_%s\] = \{\(char_u \*\)"%s", sizeof\("%s"\) - 1, )(\w+)`,
			name, name, name))
		locs := pat.FindAllSubmatchIndex(text, -1)
		if len(locs) != 1 {
			return nil, fmt.Errorf("noruntime: expected one row for :%s, matched %d",
				name, len(locs))
		}
		l := locs[0]
		var buf []byte
		buf = append(buf, text[:l[3]]...)
		buf = append(buf, "ex_ni"...)
		text = append(buf, text[l[1]:]...)
		nCmd++
	}

	nPath := 0
	for _, s := range runtimePaths {
		c := bytes.Count(text, []byte(s))
		if c == 0 {
			return nil, fmt.Errorf("noruntime: this runtime path is not here any more, so "+
				"the file has moved under this phase: %s", s)
		}
		nPath += c
		text = bytes.ReplaceAll(text, []byte(s), []byte(`""`))
	}

	if !bytes.Contains(text, []byte(getenvTest)) {
		return nil, fmt.Errorf("noruntime: vim_getenv no longer tests for VIMRUNTIME")
	}
	text = bytes.ReplaceAll(text, []byte(getenvTest), []byte("vimruntime = FALSE;"))

	fmt.Fprintf(w, "  noruntime    %d commands to ex_ni, %d runtime paths emptied, "+
		"vim_getenv no longer derives one\n", nCmd, nPath)
	return text, nil
}
