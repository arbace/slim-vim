package edit

// The multi-line literals /root/.claude/jobs/107d6bd5/tmp/w70.sh matches on, EXTRACTED from the phase's
// heredoc by tools/gocmp/genlits.py rather than retyped.  They carry BLANK
// LINES, which a filtered read of a phase program does not show, and a
// literal that is 90%% right matches nothing.  See that tool for the
// measurement.
const (
	w70OldOpen   = "        if (fnum)\n        {\n            buf = buflist_findnr(fnum);\n        }\n        else\n        {\n            buf = buflist_new(ffname, sfname, 0L, BLN_CURBUF | ((flags & ECMD_SET_HELP) ? 0 : BLN_LISTED));\n\n            if (oldwin != NULL)\n            {\n                oldwin = curwin;\n            }\n            set_bufref(&old_curbuf, curbuf);\n        }\n        if (buf == NULL)\n        {\n            goto theend;\n        }\n"
	w70NewOpen   = "        if (ffname != NULL && setfname(curbuf, ffname, sfname, FALSE) == FAIL)\n        {\n            goto theend;\n        }\n        if (oldwin != NULL)\n        {\n            oldwin = curwin;\n        }\n        set_bufref(&old_curbuf, curbuf);\n        buf = curbuf;\n"
	w70OldOldbuf = "        if (buf->b_ml.ml_mfp == NULL)\n        {\n            oldbuf = FALSE;\n        }\n        else\n        {\n            oldbuf = TRUE;\n            set_bufref(&bufref, buf);\n            if (!bufref_valid(&bufref) || curbuf != old_curbuf.br_buf)\n            {\n                goto theend;\n            }\n        }\n"
	w70lit1      = "}\n"
	w70lit2      = "        oldbuf = FALSE;\n"
	w70lit3      = "    if (!other_file && !oldbuf)\n"
	w70lit4      = "    if (!oldbuf)\n"
	w70lit5      = "            swap_exists_action = SEA_DIALOG;\n            curbuf->b_flags |= BF_CHECK_RO;\n"
	w70lit6      = "            curbuf->b_flags |= BF_CHECK_RO;\n"
	w70lit7      = "\n            if (swap_exists_action == SEA_QUIT)\n            {\n                retval = FAIL;\n            }\n            handle_swap_exists(&old_curbuf);\n"
	w70lit8      = "    if (swap_exists_action == SEA_QUIT)\n    {\n        if (!read_buffer && !read_stdin)\n        {\n            close(fd);\n        }\n        goto theend;\n    }\n\n"
	w70lit9      = "            swap_exists_action = SEA_DIALOG;\n\n            (void)open_buffer(FALSE, NULL, 0);\n\n            if (swap_exists_action == SEA_QUIT)\n            {\n                if (TRUE)\n                {\n                    did_emsg = FALSE;\n                    getout(1);\n                }\n                setfname(curbuf, NULL, NULL, FALSE);\n                swap_exists_action = SEA_NONE;\n            }\n            else\n            {\n                handle_swap_exists(NULL);\n            }\n"
	w70lit10     = "            (void)open_buffer(FALSE, NULL, 0);\n"
	w70lit11     = "    swap_exists_action = SEA_DIALOG;\n\n"
	w70lit12     = "    check_swap_exists_action();\n\n"
	w70lit13     = "{\n"
)
