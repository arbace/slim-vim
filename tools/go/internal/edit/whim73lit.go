package edit

// The multi-line literals /root/.claude/jobs/107d6bd5/tmp/w73.sh matches on, EXTRACTED from the phase's
// heredoc by tools/gocmp/genlits.py rather than retyped.  They carry BLANK
// LINES, which a filtered read of a phase program does not show, and a
// literal that is 90%% right matches nothing.  See that tool for the
// measurement.
const (
	w73lit1  = "    return FALSE;\n"
	w73lit2  = "    int         m;\n\n    if (topfrp->fr_win == next_curwin)\n    {\n        m = p_wh + topfrp->fr_win->w_status_height;\n    }\n    else\n    {\n        m = p_wmh + topfrp->fr_win->w_status_height;\n        if (topfrp->fr_win == curwin && next_curwin == NULL)\n        {\n            if (p_wmh == 0)\n            {\n                ++m;\n            }\n            m +=  0 ;\n        }\n    }\n\n    return m;\n"
	w73lit3  = "    int m;\n\n    if (topfrp->fr_win == next_curwin)\n    {\n        m = p_wiw + topfrp->fr_win->w_vsep_width;\n    }\n    else\n    {\n        m = p_wmw + topfrp->fr_win->w_vsep_width;\n        if (p_wmw == 0 && topfrp->fr_win == curwin && next_curwin == NULL)\n        {\n            ++m;\n        }\n    }\n\n    return m;\n"
	w73lit4  = "    return topfrp->fr_height == height;\n"
	w73lit5  = "    return topfrp->fr_width == width;\n"
	w73lit6  = "    win_T       *wp;\n    int         h;\n\n    wp = topfrp->fr_win;\n    if (wp != NULL)\n    {\n        if (wp->w_winrow != *row || wp->w_wincol != *col)\n        {\n            wp->w_winrow = *row;\n            wp->w_wincol = *col;\n            redraw_win_later(wp, UPD_NOT_VALID);\n            wp->w_redr_status = true;\n        }\n        h =  (wp)->w_height  + wp->w_status_height;\n        *row += h > topfrp->fr_height ? topfrp->fr_height : h;\n        *col += wp->w_width + wp->w_vsep_width;\n    }\n"
	w73lit7  = "    if (set_ch)\n    {\n        int new_ch = MAX(min_set_ch, p_ch + topfrp->fr_height - height);\n        int save_ch = min_set_ch;\n        if (new_ch != p_ch)\n        {\n            set_option_value((char_u *)\"cmdheight\", new_ch, NULL, 0);\n        }\n        min_set_ch = save_ch;\n        height = MIN(height,  (Rows - p_ch - tabline_height()) );\n    }\n    win_new_height(topfrp->fr_win, height - topfrp->fr_win->w_status_height -  0 );\n    topfrp->fr_height = height;\n"
	w73lit8  = "    win_T       *wp;\n\n    wp = topfrp->fr_win;\n    wp->w_vsep_width = 0;\n    win_new_width(wp, width - wp->w_vsep_width);\n    topfrp->fr_width = width;\n"
	w73lit9  = "    if (curfrp->fr_height == height)\n    {\n        return;\n    }\n\n    if (height > 0)\n    {\n        frame_new_height(curfrp, height, FALSE, FALSE, TRUE);\n    }\n"
	w73lit10 = "    if (curfrp->fr_width == width)\n    {\n        return;\n    }\n"
	w73lit11 = "    frame_new_height(frp, frp->fr_height + n, FALSE, FALSE, FALSE);\n"
	w73lit12 = "    win_T       *wp;\n\n    wp = fr->fr_win;\n    if (wp->w_status_height != 0 && !statusline)\n    {\n        win_new_height(wp, wp->w_height + wp->w_status_height);\n        wp->w_status_height = 0;\n        comp_col();\n    }\n    else if (wp->w_status_height == 0 && statusline)\n    {\n        if (fr->fr_height <= frame_minheight(fr, NULL))\n        {\n            emsg(_(e_not_enough_room));\n            return;\n        }\n        wp->w_status_height = statusline_height(wp);\n        win_new_height(wp, wp->w_height - wp->w_status_height);\n        comp_col();\n        redraw_all_later(UPD_SOME_VALID);\n    }\n    if (abs(wp->w_height - wp->w_prev_height) == 1)\n    {\n        wp->w_prev_height = wp->w_height;\n    }\n"
	w73lit13 = "    int         old_p_ch = curtab->tp_ch_used;\n    frame_T     *frp = curwin->w_frame;\n\n    if (p_ch > old_p_ch && command_frame_height)\n    {\n        int h = MIN(p_ch - old_p_ch, frp->fr_height - frame_minheight(frp, NULL));\n        frame_add_height(frp, -h);\n        old_p_ch += h;\n    }\n    if (p_ch < old_p_ch && command_frame_height)\n    {\n        frame_add_height(frp, (int)(old_p_ch - p_ch));\n    }\n\n    win_comp_pos();\n    win_fix_scroll(true);\n    cmdline_row = Rows - p_ch;\n    redraw_cmdline = TRUE;\n\n    if (msg_scrolled == 0 && full_screen)\n    {\n        screen_fill(cmdline_row, (int)Rows, 0, (int)Columns, ' ', ' ', 0);\n        msg_row = cmdline_row;\n    }\n\n    curtab->tp_ch_used = p_ch;\n    min_set_ch = p_ch;\n"
	w73lit14 = "}\n"
	w73lit15 = "{\n"
)
