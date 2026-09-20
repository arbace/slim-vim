package main

import (
	"fmt"
	"os"
	"reflect"
	"sort"

	"modernc.org/cc/v4"
)

// runFieldRef reports, for every struct member in a product, how many times it
// is READ, how many times it is WRITTEN and how many times its address is
// taken -- resolved to the field of a SPECIFIC struct and not to a name.
//
// WHY IT EXISTS.  tools/deadfields.py matches a field by NAME, so a name two
// structs share is invisible to it for ever: zero phase 39 removes
// `mparm_T.term` while `attr_entry.ae_u.term` has 32 mentions in the same file,
// and that phase had to compute the partition by hand to earn the right to take
// the member.  And the tool reports 0 for a field that is WRITTEN -- zero 42's
// eight `struct block0` members with 12 writes and 0 reads, `pe_old_lnum` with
// 7 and 0, zero 43's `mf_used_last` -- because a field only written is still
// named.  Both of those are what cc/v4 answers exactly: a member access
// resolves to a *cc.Field, which carries the struct it belongs to, and the
// context says whether the value was wanted or replaced.
//
// IT REPORTS AND CHANGES NOTHING.  That is the order this work was asked to go
// in: a verifier first, and an edit that trusts it afterwards.
func runFieldRef(args []string) int {
	if len(args) != 1 {
		fmt.Fprintln(os.Stderr, "usage: slimtools fieldref <file.c>")
		return 1
	}
	ast, err := parseProduct(args[0])
	if err != nil {
		fmt.Fprintf(os.Stderr, "slimtools: %v\n", err)
		return 1
	}

	// Pass one: the field accesses that are NOT plain reads.  A write is the
	// left side of an assignment; `++`/`--` is both; `&x.f` is neither until
	// something dereferences it, and is counted apart because taking an address
	// is what makes gcc's -Wunused-but-set-variable go quiet.
	write := map[cc.Node]bool{}
	rmw := map[cc.Node]bool{}
	addr := map[cc.Node]bool{}
	walk(ast.TranslationUnit, func(n cc.Node) {
		switch x := n.(type) {
		case *cc.AssignmentExpression:
			// AssignmentExpressionCond is not an assignment at all -- it is
			// the grammar's pass-through for a conditional expression -- so it
			// is the one case that marks nothing.
			switch x.Case {
			case cc.AssignmentExpressionCond:
			case cc.AssignmentExpressionAssign:
				mark(x.UnaryExpression, write)
			default:
				mark(x.UnaryExpression, rmw)
			}
		case *cc.UnaryExpression:
			switch x.Case {
			case cc.UnaryExpressionInc, cc.UnaryExpressionDec:
				mark(x.UnaryExpression, rmw)
			case cc.UnaryExpressionAddrof:
				mark(x.CastExpression, addr)
			}
		case *cc.PostfixExpression:
			if x.Case == cc.PostfixExpressionInc || x.Case == cc.PostfixExpressionDec {
				mark(x.PostfixExpression, rmw)
			}
		}
	})

	type tally struct{ reads, writes, addrs int }
	counts := map[string]*tally{}
	get := func(k string) *tally {
		if counts[k] == nil {
			counts[k] = &tally{}
		}
		return counts[k]
	}
	walk(ast.TranslationUnit, func(n cc.Node) {
		x, ok := n.(*cc.PostfixExpression)
		if !ok || (x.Case != cc.PostfixExpressionSelect && x.Case != cc.PostfixExpressionPSelect) {
			return
		}
		f := x.Field()
		if f == nil {
			return
		}
		t := get(fieldKey(f))
		switch {
		// AN ARRAY MEMBER IS NEVER A VALUE READ.  `b0p->b0_version` in
		// `musl_memmove((char *)(b0p->b0_version), ...)` decays to a pointer
		// with no `&` written, and `b0p->b0_id[0] = x` reads the member only to
		// index it -- both are the member's ADDRESS and neither consults what
		// it holds.  Counting them as reads is correct C and answers the wrong
		// question: it makes zero42's eight write-only `struct block0` members
		// look read, which is exactly the claim that phase had to make by hand.
		case f.Type() != nil && f.Type().Kind() == cc.Array:
			t.addrs++
		case addr[n]:
			t.addrs++
		case write[n]:
			t.writes++
		case rmw[n]:
			t.reads++
			t.writes++
		default:
			t.reads++
		}
	})

	// Pass two: every field a struct DECLARES, so that a member nothing touches
	// is a row of zeroes and not an absence.  A field that is in no row at all
	// would be indistinguishable from a struct this walk never reached.
	declared := map[string]bool{}
	walk(ast.TranslationUnit, func(n cc.Node) {
		st, ok := n.(*cc.StructOrUnionSpecifier)
		if !ok {
			return
		}
		s, ok := st.Type().(*cc.StructType)
		if !ok {
			return
		}
		for i := 0; i < s.NumFields(); i++ {
			if f := s.FieldByIndex(i); f != nil && f.Name() != "" {
				declared[fieldKey(f)] = true
				get(fieldKey(f))
			}
		}
	})

	keys := make([]string, 0, len(counts))
	for k := range counts {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	unread := 0
	for _, k := range keys {
		t := counts[k]
		if t.reads == 0 {
			unread++
		}
		fmt.Printf("%s\t%d\t%d\t%d\n", k, t.reads, t.writes, t.addrs)
	}
	fmt.Printf("# %d fields in %d declared members; %d are never read\n",
		len(keys), len(declared), unread)
	return 0
}

// fieldKey names a field by the struct it belongs to, which is the whole point:
// `mparm_T.term` and `attr_entry.ae_u.term` are two different rows.
func fieldKey(f *cc.Field) string {
	return fieldOwner(f) + "." + f.Name()
}

// fieldOwner names the struct a field belongs to.  An anonymous struct behind a
// typedef is named by the typedef and an anonymous member is named THROUGH the
// field that holds it, so that `mparm_T.term` and `attr_entry.ae_u.term` -- the
// collision zero phase 39 had to partition by hand, 1 mention against 32 -- are
// two rows and not one.  Without this the tool is blind in exactly the way it
// exists to cure.
func fieldOwner(f *cc.Field) string {
	if p := f.ParentField(); p != nil {
		return fieldOwner(p) + "." + p.Name()
	}
	s, ok := f.ParentType().(*cc.StructType)
	if !ok || s == nil {
		return "<anonymous>"
	}
	if tag := s.Tag(); tag.SrcStr() != "" {
		return tag.SrcStr()
	}
	if d := s.Typedef(); d != nil {
		return d.Name()
	}
	// A TYPEDEF'D ANONYMOUS STRUCT KEEPS THE `<anonymous>` LABEL, and that is a
	// measurement and not an omission.  cc/v4's Typedef() is nil for `typedef
	// struct { ... } mparm_T;`, and reading the name off the declaration fails
	// in a way that is worse than the label: the type a StructOrUnionSpecifier
	// reports and the type a member access's ParentType reports are two
	// instances with different field signatures, so the declaration's copy gets
	// the name and the accesses do not -- producing TWO rows for one field,
	// `mparm_T.term 0 0 0` beside `<anonymous>.term 1 1 0`.  A row that claims
	// a field nothing touches is a worse answer than a row with a dull name.
	return "<anonymous>"
}

// mark records a node as a non-read access, unwrapping the one-child grammar
// chain cc/v4 leaves between an assignment's left side and the member access.
func mark(n cc.Node, set map[cc.Node]bool) {
	for i := 0; i < 8 && n != nil; i++ {
		if x, ok := n.(*cc.PostfixExpression); ok {
			if x.Case == cc.PostfixExpressionSelect || x.Case == cc.PostfixExpressionPSelect {
				set[cc.Node(x)] = true
			}
			return
		}
		next := onlyChild(n)
		if next == nil {
			return
		}
		n = next
	}
}

// onlyChild returns n's single Node-valued exported field, if it has exactly
// one -- which is how the grammar chain collapses.
func onlyChild(n cc.Node) cc.Node {
	v := reflect.ValueOf(n)
	if v.Kind() != reflect.Ptr || v.IsNil() {
		return nil
	}
	e := v.Elem()
	if e.Kind() != reflect.Struct {
		return nil
	}
	t := e.Type()
	var found cc.Node
	for i := 0; i < e.NumField(); i++ {
		if c := t.Field(i).Name[0]; c < 'A' || c > 'Z' {
			continue
		}
		if x, ok := e.Field(i).Interface().(cc.Node); ok && !isNilNode(x) {
			if found != nil {
				return nil
			}
			found = x
		}
	}
	return found
}

// walk visits n and every Node reachable from an exported field of it, which is
// the traversal cc/v4's own findAllNodes uses.
func walk(n cc.Node, f func(cc.Node)) {
	if isNilNode(n) {
		return
	}
	f(n)
	v := reflect.ValueOf(n)
	if v.Kind() != reflect.Ptr || v.IsNil() {
		return
	}
	e := v.Elem()
	if e.Kind() != reflect.Struct {
		return
	}
	t := e.Type()
	for i := 0; i < e.NumField(); i++ {
		if c := t.Field(i).Name[0]; c < 'A' || c > 'Z' {
			continue
		}
		if x, ok := e.Field(i).Interface().(cc.Node); ok {
			walk(x, f)
		}
	}
}

func isNilNode(n cc.Node) bool {
	if n == nil {
		return true
	}
	v := reflect.ValueOf(n)
	return v.Kind() == reflect.Ptr && v.IsNil()
}

// parseProduct is runParse's translate, without the timing.
func parseProduct(path string) (*cc.AST, error) {
	cfg, err := cc.NewConfig("linux", "amd64")
	if err != nil {
		return nil, err
	}
	return cc.Translate(cfg, []cc.Source{
		{Name: "<predefined>", Value: cfg.Predefined},
		{Name: "<builtin>", Value: cc.Builtin},
		{Name: path},
	})
}
