package edit

// The multi-line literals /root/.claude/jobs/107d6bd5/tmp/w75.sh matches on, EXTRACTED from the phase's
// heredoc by tools/gocmp/genlits.py rather than retyped.  They carry BLANK
// LINES, which a filtered read of a phase program does not show, and a
// literal that is 90%% right matches nothing.  See that tool for the
// measurement.
const (
	w75OldCb = "    if ((win_valid || closed_popup) && win->w_buffer == buf && buf->b_nwindows == 1)\n    {\n        ++buf->b_locked;\n        ++buf->b_locked_split;\n        if (apply_autocmds(EVENT_BUFWINLEAVE, buf->b_fname, buf->b_fname, FALSE, buf) && !bufref_valid(&bufref))\n        {\naucmd_abort:\n            emsg(_(e_autocommands_caused_command_to_abort));\n            return FALSE;\n        }\n        --buf->b_locked;\n        --buf->b_locked_split;\n        if (abort_if_last)\n        {\n            goto aucmd_abort;\n        }\n\n        if (!unload_buf)\n        {\n            ++buf->b_locked;\n            ++buf->b_locked_split;\n            if (apply_autocmds(EVENT_BUFHIDDEN, buf->b_fname, buf->b_fname, FALSE, buf) && !bufref_valid(&bufref))\n            {\n                goto aucmd_abort;\n            }\n            --buf->b_locked;\n            --buf->b_locked_split;\n            if (abort_if_last)\n            {\n                goto aucmd_abort;\n            }\n        }\n        win_valid = win_valid && win_valid_any_tab(win);\n    }\n"
	w75NewCb = "    if ((win_valid || closed_popup) && win->w_buffer == buf && buf->b_nwindows == 1)\n    {\n        if (abort_if_last)\n        {\n            emsg(_(e_autocommands_caused_command_to_abort));\n            return FALSE;\n        }\n        win_valid = win_valid && win_valid_any_tab(win);\n    }\n"
	w75lit1  = "Assignments TO `name` (or to an element of it), skipping the subscript.\n\n    A first version of this matched `name[^\\n;]*=` and reported three writes that\n    were the `!=` of the has_* predicates -- it spanned the subscript and landed on\n    the comparison.  An assertion that cries wolf is worse than none, because the\n    temptation is to loosen it until it passes.  This one steps over a balanced\n    subscript and then looks at the operator that actually follows.\n    "
	w75lit2  = "    return FALSE;\n"
	w75lit3  = "}\n"
	w75lit4  = "            int was_changed = curbufIsChanged();\n\n            did_cmd = apply_autocmds_exarg(EVENT_BUFWRITECMD, sfname, sfname, FALSE, curbuf, eap);\n            if (did_cmd)\n            {\n                if (was_changed && !curbufIsChanged())\n                {\n                    u_unchanged(curbuf);\n                    u_update_save_nr(curbuf);\n                }\n            }\n            else\n            {\n                apply_autocmds_exarg(EVENT_BUFWRITEPRE, sfname, sfname, FALSE, curbuf, eap);\n            }\n"
	w75lit5  = "    need_redraw |= apply_autocmds(in_focus ? EVENT_FOCUSGAINED : EVENT_FOCUSLOST, NULL, NULL, FALSE, curbuf);\n\n"
	w75lit6  = "    if (bufref_valid(&old_curbuf) && old_curbuf.br_buf->b_ml.ml_mfp != NULL)\n    {\n        aco_save_T      aco;\n\n        aucmd_prepbuf(&aco, old_curbuf.br_buf);\n        if (curbuf == old_curbuf.br_buf)\n        {\n            curbuf->b_flags &= ~(BF_CHECK_RO | BF_NEVERLOADED);\n\n            if ((flags & READ_NOWINENTER) == 0)\n            {\n            apply_autocmds(EVENT_BUFWINENTER, NULL, NULL, FALSE, curbuf);\n            }\n\n            aucmd_restbuf(&aco);\n        }\n    }\n"
	w75lit7  = "    if (bufref_valid(&old_curbuf) && old_curbuf.br_buf->b_ml.ml_mfp != NULL)\n    {\n        curbuf->b_flags &= ~(BF_CHECK_RO | BF_NEVERLOADED);\n    }\n"
	w75lit8  = "    if (quitmore && !getline_equal(fgetline, cookie, getnextac))\n"
	w75lit9  = "    if (quitmore)\n"
	w75lit10 = "        aucmd_prepbuf(&aco, buf);\n        if (curbuf != buf)\n        {\n            return FAIL;\n        }\n\n        set_bufref(&bufref, buf);\n\n        if (append)\n        {\n        }\n        else if (filtering)\n        {\n        }\n        else if (reset_changed && whole)\n        {\n        }\n        else\n        {\n        }\n\n        aucmd_restbuf(&aco);\n\n        if (!bufref_valid(&bufref))\n        {\n            buf = NULL;\n        }\n"
	w75lit11 = "        if (buf == NULL || (buf->b_ml.ml_mfp == NULL && !empty_memline) || did_cmd)\n"
	w75lit12 = "        if (buf == NULL || (buf->b_ml.ml_mfp == NULL && !empty_memline))\n"
	w75lit13 = "\n"
	w75lit14 = "        if (is_autocmd_blocked())\n        {\n            unblock_autocmds();\n            ++unblock;\n        }\n        apply_autocmds(EVENT_%s, NULL, NULL, FALSE, curbuf);\n        if (unblock)\n        {\n            block_autocmds();\n        }\n"
	w75lit15 = "{\n"
)
