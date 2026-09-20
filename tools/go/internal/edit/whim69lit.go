package edit

// The multi-line C literals whim69 matches on, EXTRACTED from the phase's
// heredoc rather than retyped.
//
// whim65 is why.  An OP_FUNCTION block transcribed by hand had lost the blank
// lines between its statements, and a literal that is 90% right matches
// nothing -- `occurs 0 times, expected 1`.  These carry blank lines too, and a
// filtered read of the phase program does not show them.  Generating is what
// the Go session did for muslctype's 230-line C driver, for the same reason:
// retyping is where a changed byte becomes invisible to the compile AND to
// the comparison.
const (
	w69OldArg = "            if (parmp->edit_type != EDIT_NONE && parmp->edit_type != EDIT_FILE)\n            {\n                mainerr(ME_TOO_MANY_ARGS, (char_u *)argv[0]);\n            }\n            parmp->edit_type = EDIT_FILE;\n\n            if (ga_grow(&global_alist.al_ga, 1) == FAIL || (p = vim_strsave((char_u *)argv[0])) == NULL)\n            {\n                mch_exit(2);\n            }\n\n            alist_add(&global_alist, p, 2);\n\n"
	w69NewArg = "            if (parmp->edit_type != EDIT_NONE)\n            {\n                mainerr(ME_TOO_MANY_ARGS, (char_u *)argv[0]);\n            }\n            parmp->edit_type = EDIT_FILE;\n\n            if ((p = vim_strsave((char_u *)argv[0])) == NULL)\n            {\n                mch_exit(2);\n            }\n\n            (void)buflist_add(p, BLN_CURBUF | BLN_LISTED);\n\n"
	w69lit1   = "    return OK;\n"
	w69lit2   = "    return 0;\n"
	w69lit3   = "                    case ADDR_ARGUMENTS:\n                        if ( ( (curwin)->w_alist ->al_ga.ga_len)  == 0)\n                        {\n                            eap->line1 = eap->line2 = 0;\n                        }\n                        else\n                        {\n                            eap->line1 = 1;\n                            eap->line2 =  ( (curwin)->w_alist ->al_ga.ga_len) ;\n                        }\n                        break;\n"
	w69lit4   = "                    case ADDR_ARGUMENTS:\n                        eap->line1 = eap->line2 = 0;\n                        break;\n"
	w69lit5   = "        case ADDR_ARGUMENTS:\n            if ( ( (curwin)->w_alist ->al_ga.ga_len)  == 0)\n            {\n                eap->line1 = eap->line2 = 0;\n            }\n            else\n            {\n                eap->line2 =  ( (curwin)->w_alist ->al_ga.ga_len) ;\n            }\n            break;\n"
	w69lit6   = "        case ADDR_ARGUMENTS:\n            eap->line1 = eap->line2 = 0;\n            break;\n"
	w69lit7   = "        case ADDR_ARGUMENTS:\n            lnum = curwin->w_arg_idx + 1;\n            if (lnum >  ( (curwin)->w_alist ->al_ga.ga_len) )\n            {\n                lnum =  ( (curwin)->w_alist ->al_ga.ga_len) ;\n            }\n            break;\n"
	w69lit8   = "        case ADDR_ARGUMENTS:\n            lnum = 0;\n            break;\n"
	w69lit9   = "                    case ADDR_ARGUMENTS:\n                        lnum = curwin->w_arg_idx + 1;\n                        break;\n"
	w69lit10  = "                    case ADDR_ARGUMENTS:\n                        lnum = 0;\n                        break;\n"
	w69lit11  = "                    case ADDR_ARGUMENTS:\n                        lnum =  ( (curwin)->w_alist ->al_ga.ga_len) ;\n                        break;\n"
	w69lit12  = "            case ADDR_ARGUMENTS:\n                if (eap->line2 >  ( (curwin)->w_alist ->al_ga.ga_len)  + (! ( (curwin)->w_alist ->al_ga.ga_len) ))\n                {\n                    return _(e_invalid_range);\n                }\n                break;\n"
	w69lit13  = "            case ADDR_ARGUMENTS:\n                break;\n"
	w69lit14  = "\n"
	w69lit15  = "}\n"
	w69lit16  = "                    result = arg_all();\n                    resultbuf = result;\n"
	w69lit17  = "                    result = (char_u *)\"\";\n                    resultbuf = NULL;\n"
	w69lit18  = "{\n"
)
