package edit

// The multi-line literals /root/.claude/jobs/107d6bd5/tmp/w72.sh matches on, EXTRACTED from the phase's
// heredoc by tools/gocmp/genlits.py rather than retyped.  They carry BLANK
// LINES, which a filtered read of a phase program does not show, and a
// literal that is 90%% right matches nothing.  See that tool for the
// measurement.
const (
	w72lit1  = "True if `raw` holds a break/continue that binds to the loop AROUND it.\n\n    Not a depth test.  C binds break to the nearest enclosing loop or switch, so the\n    question is whether one of those lies between the statement and the body's edge.\n    An earlier version of this tested brace depth and would have passed getout().\n    "
	w72lit2  = "Fold every walk of one shape, refusing if any body's break/continue rebinds.\n\n    Walks of a single shape are disjoint, so the matches are rewritten back to front\n    and the blanked copy stays valid for every offset still to be processed.\n    "
	w72lit3  = "        win = (curwin->w_buffer == buf) ? curwin : NULL;\n"
	w72lit4  = "        if (curwin->w_buffer == buf)\n        {\n            can_unload = FALSE;\n        }\n"
	w72lit5  = "    return 1;\n"
	w72lit6  = "        if (curwin->w_buffer != NULL && buf_valid(curwin->w_buffer))\n        {\n            buf = curwin->w_buffer;\n            if ( ((buf)->b_ct_di.di_tv.vval.v_number)  != -1)\n            {\n                bufref_T bufref;\n\n                set_bufref(&bufref, buf);\n                apply_autocmds(EVENT_BUFWINLEAVE, buf->b_fname, buf->b_fname, FALSE, buf);\n                if (bufref_valid(&bufref))\n                {\n                     ((buf)->b_ct_di.di_tv.vval.v_number)  = -1;\n                }\n            }\n        }\n"
	w72lit7  = "    ++autocmd_no_enter;\n    ++autocmd_no_leave;\n\n    curbuf = curwin->w_buffer;\n    if (curbuf->b_ml.ml_mfp == NULL)\n    {\n        (void)open_buffer(FALSE, NULL, 0);\n    }\n    ui_breakcheck();\n    if (got_int)\n    {\n        (void)vgetc();\n    }\n\n    curbuf = curwin->w_buffer;\n    --autocmd_no_enter;\n    --autocmd_no_leave;\n"
	w72lit8  = "    return win != NULL && win == curwin;\n"
	w72lit9  = "    return (curwin->w_id == id) ? curwin : NULL;\n"
	w72lit10 = "    return tpc == curtab;\n"
	w72lit11 = "    curwin = win_alloc(NULL, FALSE);\n    if (curwin == NULL)\n    {\n        return FAIL;\n    }\n    curbuf = buflist_new(NULL, NULL, 1L, BLN_LISTED);\n    if (curbuf == NULL)\n    {\n        return FAIL;\n    }\n    curwin->w_buffer = curbuf;\n    curbuf->b_nwindows = 1;\n    curwin_init();\n\n    new_frame(curwin);\n    if (curwin->w_frame == NULL)\n    {\n        return FAIL;\n    }\n    topframe = curwin->w_frame;\n    topframe->fr_width =  Columns ;\n    topframe->fr_height = Rows - p_ch;\n\n    return OK;\n"
	w72lit12 = "    if (win_alloc_firstwin(NULL) == FAIL)\n    {\n        return FAIL;\n    }\n\n    curtab = alloc_tabpage();\n    if (curtab == NULL)\n    {\n        return FAIL;\n    }\n    unuse_tabpage(curtab);\n\n    return OK;\n"
	w72lit13 = "    tp->tp_topframe = topframe;\n    tp->tp_curwin = curwin;\n"
	w72lit14 = "    redraw_win_later(wp, UPD_NOT_VALID);\n    wp->w_redr_status = true;\n    redraw_cmdline = TRUE;\n"
	w72lit15 = "}\n"
	w72lit16 = "    if (wp->w_next != NULL || wp->w_status_height)\n"
	w72lit17 = "    if (wp->w_status_height)\n"
	w72lit18 = "        else if (wp->w_next)\n        {\n            return FAIL;\n        }\n"
	w72lit19 = "        if (did_delete)\n        {\n            wp->w_redr_status = true;\n            win_rest_invalid( ((wp)->w_next) );\n        }\n"
	w72lit20 = "        if (did_delete)\n        {\n            wp->w_redr_status = true;\n        }\n"
	w72lit21 = "    if (wp->w_next || wp->w_status_height || cmdline_row < Rows - 1)\n"
	w72lit22 = "    if (wp->w_status_height || cmdline_row < Rows - 1)\n"
	w72lit23 = "            wp->w_redr_status = true;\n            win_rest_invalid(wp->w_next);\n"
	w72lit24 = "            wp->w_redr_status = true;\n"
	w72lit25 = "    if (wp->w_next != NULL && p_tf)\n    {\n        return FAIL;\n    }\n\n"
	w72lit26 = "\n"
	w72lit27 = "{\n"
)
