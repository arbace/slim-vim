package cut

import (
	"bytes"
	"fmt"
	"io"
	"regexp"

	"slimvim.local/tools/internal/cutil"
)

const vimrcNoneTest = `^[ \t]*if \(params\.use_vimrc != NULL && \( strcmp\(\(char \*\)\(params\.use_vimrc\), \(char \*\)\("NONE"\)\)  == 0`

var (
	startupCall = regexp.MustCompile(`(?m)^[ \t]*source_startup_scripts\(&params\);\n`)
	xdgRtpCall  = regexp.MustCompile(`(?m)^[ \t]*set_init_xdg_rtp\(\);\n`)
)

// NoStartup stops the editor reading anything at startup.
//
// source_startup_scripts() keeps its name and loses its body ENTIRELY -- the
// braces go back empty, which is why this splices the offsets itself rather
// than ReplaceBody: a body of "" through that helper would leave a blank line
// between the braces, and this file has no run of two blank lines anywhere.
func NoStartup(text []byte, w io.Writer) ([]byte, error) {
	o, c, found, balanced := cutil.Body(text, "source_startup_scripts")
	if !found {
		return nil, fmt.Errorf("nostartup: source_startup_scripts is not defined at file scope")
	}
	if !balanced {
		return nil, fmt.Errorf("nostartup: source_startup_scripts is unbalanced")
	}
	was := bytes.Count(text[o:c], []byte{'\n'})
	var err error
	var buf []byte
	buf = append(buf, text[:o]...)
	buf = append(buf, "{\n}"...)
	text = append(buf, text[c+1:]...)
	fmt.Fprintf(w, "  nostartup    source_startup_scripts was %d lines; it now has no body\n", was)

	if n := len(startupCall.FindAll(text, -1)); n != 1 {
		return nil, fmt.Errorf("nostartup: expected one source_startup_scripts call, "+
			"matched %d", n)
	}
	text = startupCall.ReplaceAll(text, nil)
	fmt.Fprintln(w, "  nostartup    startup reads nothing, so it does not call the "+
		"function that read")

	if n := len(regexp.MustCompile("(?m)"+vimrcNoneTest).FindAll(text, -1)); n != 1 {
		return nil, fmt.Errorf("nostartup: the -u NONE test in main() is not where this expects")
	}
	if text, err = cutil.DropIf(text, "(?m)"+vimrcNoneTest, 1); err != nil {
		return nil, err
	}
	fmt.Fprintln(w, "  nostartup    -u NONE no longer switches 'loadplugins' off")

	if n := len(xdgRtpCall.FindAll(text, -1)); n != 1 {
		return nil, fmt.Errorf("nostartup: expected one set_init_xdg_rtp call, matched %d", n)
	}
	text = xdgRtpCall.ReplaceAll(text, nil)
	fmt.Fprintln(w, "  nostartup    'runtimepath' stops being rebuilt from $XDG_CONFIG_HOME")

	fmt.Fprintf(w, "  nostartup    %d process_env mentions left for the sweep\n",
		bytes.Count(text, []byte("process_env")))
	return text, nil
}
