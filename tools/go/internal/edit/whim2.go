package edit

import (
	"io"
	"regexp"
	"strings"
)

var cmdRow = regexp.MustCompile(`\[CMD_(\w+)\] = \{\(char_u \*\)"([^"]*)", sizeof\([^)]*\) - 1,\s*(\w+)\s*,`)

// menuSpellCommands are every menu and spell command.  whim2 prints the ones
// that still have a real handler, and the shell REFUSES if the list is not
// empty: if a menu or spell command ever acquires one again, that phase is no
// longer the whole story and should say so rather than quietly do half of it.
var menuSpellCommands = strings.Fields(
	"menu amenu nmenu vmenu imenu cmenu omenu xmenu smenu tmenu unmenu " +
		"menutranslate emenu popup tunmenu tlmenu spell spellgood spellwrong " +
		"spellrare spellundo spelldump spellinfo spellrepall mkspell")

// Whim2Live prints every menu or spell command whose handler is not ex_ni.
func Whim2Live(text []byte, w io.Writer) error {
	rows := map[string]string{}
	for _, m := range cmdRow.FindAllSubmatch(text, -1) {
		rows[string(m[2])] = string(m[3])
	}
	var live []string
	for _, n := range menuSpellCommands {
		h, ok := rows[n]
		if !ok {
			h = "ex_ni"
		}
		if h != "ex_ni" {
			live = append(live, n)
		}
	}
	_, err := io.WriteString(w, strings.Join(live, " ")+"\n")
	return err
}

func init() { registerQuery("whim2", Whim2Live) }
