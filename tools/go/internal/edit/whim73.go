package edit

import (
	"io"
	"regexp"
)

// frameLinkWrite is any write to the frame tree's four pointers.  THE PHASE
// OPENS BY PROVING THERE ARE NONE, because every replacement below assumes a
// frame is a leaf -- if the tree really were linked somewhere, all fifteen
// bodies would be wrong and the boundary would be the first thing to say so.
var frameLinkWrite = regexp.MustCompile(`fr_(?:child|next|prev|parent)[ \t]*(?:=[^=]|\+\+|--)`)

// Whim73 makes a frame a leaf: fifteen functions that recursed into children or
// climbed to parents become constants, and the four tree pointers go.
func Whim73(text []byte, w io.Writer) ([]byte, error) {
	e := New("oneframe", text, w)

	if k := len(frameLinkWrite.FindAll(text, -1)); k > 0 {
		e.Refuse("the frame tree IS linked somewhere (%d writes) -- the invariant this phase rests on is false, and every replacement below would be wrong", k)
		return e.Done()
	}
	e.say("confirmed: nothing writes fr_child, fr_next, fr_prev or fr_parent")

	for _, f := range []struct{ name, body, what string }{
		{"frame_fixed_height", w73lit1, "frame_fixed_height, asked of a leaf"},
		{"frame_fixed_width", w73lit1, "frame_fixed_width, asked of a leaf"},
		{"frame_minheight", w73lit2, "frame_minheight recursing into a row or column"},
		{"frame_minwidth", w73lit3, "frame_minwidth recursing into a row or column"},
		{"frame_check_height", w73lit4, "frame_check_height comparing against children"},
		{"frame_check_width", w73lit5, "frame_check_width comparing against children"},
		{"frame_comp_pos", w73lit6, "frame_comp_pos descending into children"},
		{"frame_new_height", w73lit7, "frame_new_height distributing height over children"},
		{"frame_new_width", w73lit8, "frame_new_width distributing width over children"},
		{"frame_setheight", w73lit9, "frame_setheight taking room from siblings"},
		{"frame_setwidth", w73lit10, "frame_setwidth taking room from siblings"},
		{"frame_add_height", w73lit11, "frame_add_height propagating to parents"},
		{"last_status_rec", w73lit12, "last_status_rec descending a row or column of frames"},
		{"command_height", w73lit13, "command_height walking to the widest ancestor"},
		{"stl_connected", w73lit1, "stl_connected, which climbed the tree for a neighbour"},
	} {
		e.Body(f.name, f.body, f.what)
	}
	e.Lines(`frame_T[ \t]+\*fr_parent;`, 1, "the parent pointer")
	e.Lines(`frame_T[ \t]+\*fr_next;`, 1, "the next pointer")
	e.Lines(`frame_T[ \t]+\*fr_prev;`, 1, "the previous pointer")
	e.Lines(`frame_T[ \t]+\*fr_child;`, 1, "the child pointer")
	return e.Done()
}

func init() { register("whim73", Whim73) }
