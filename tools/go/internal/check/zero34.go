package check

import (
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"

	"slimvim.local/tools/internal/harness"
)

func init() { register("zero34", Zero34) }

var (
	z34Realloc = regexp.MustCompile(`\brealloc\b`)
	z34Proto   = regexp.MustCompile(`^(?:void \*|void |long |int )[a-z_]+\(`)
	z34Pid     = regexp.MustCompile(`==[0-9]+==`)
	z34Addr    = regexp.MustCompile(`0x[0-9a-f]+`)
	z34DrvPath = regexp.MustCompile(`/[^ \n]*/d\.[a-z_]+\.c`)
	z34LC      = regexp.MustCompile(`:[0-9]+:[0-9]+`)
)

const z34GA = `    new_len = (usize)gap->ga_itemsize * (gap->ga_len + n);
    old_len = (usize)gap->ga_itemsize * gap->ga_maxlen;
    pp = malloc(new_len);
    if (pp == nullptr)
    {
        return FAIL;
    }
    if (gap->ga_data != nullptr)
    {
        musl_memcpy(pp, gap->ga_data, old_len);
        free(gap->ga_data);
    }
     musl_memset((pp + old_len), (0), (new_len - old_len)) ;
`

const z34KS = `            char_u  *t_buf = buf;
            int     t_buflen = buflen;

            buflen += 100;
            buf = malloc(buflen);
            if (buf == nullptr)
            {
                vim_free(t_buf);
            }
            else
            {
                musl_memcpy(buf, t_buf, t_buflen);
                free(t_buf);
            }
`

const z34Head = `
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

typedef unsigned char char_u;
typedef typeof(sizeof(0)) usize;
enum { OK = 1 };
enum { FAIL = 0 };
static void *musl_memcpy(void *dest, const void *src, usize n);
static void *musl_memset(void *dest, int c, usize n);
static int ga_grow_inner(garray_T *gap, int n);
static int n_vim_free = 0;
static void vim_free(void *x) { if (x != nullptr) { ++n_vim_free; free(x); } }
`

const z34Tail = `
static void hexline(const char *tag, const unsigned char *p, int n)
{
    int i;
    printf("%s", tag);
    for (i = 0; i < n; i++) { printf(" %02x", p[i]); }
    printf("\n");
}

/* A -- from EMPTY through eight doublings, the live region written after every grow and
   read back before the next.  Step 1 is the null-ga_data case, which on a full
   recording of the editor is 2,739 of ga_grow_inner's 4,289 calls.  Reading the live
   region back is the ONLY thing that says the copy happened; checking the tail is
   zero is the only thing that says the memset still runs after it. */
static void test_grow(void)
{
    garray_T ga = { 0, 0, 0, 0, nullptr };
    int step, i, r;
    unsigned char *d;

    ga.ga_itemsize = 1;
    ga.ga_growsize = 4;
    printf("A.start data=%s maxlen=%d\n", ga.ga_data == nullptr ? "null" : "set", ga.ga_maxlen);
    for (step = 1; step <= 8; step++)
    {
        int want = ga.ga_len + 3;
        r = ga_grow_inner(&ga, want - ga.ga_len);
        d = ga.ga_data;
        printf("A.%d r=%d len=%d maxlen=%d data=%s\n", step, r, ga.ga_len, ga.ga_maxlen,
               d == nullptr ? "null" : "set");
        if (r != OK) { continue; }
        for (i = ga.ga_len; i < ga.ga_maxlen; i++)
        {
            if (d[i] != 0) { printf("A.%d TAIL-NOT-ZERO at %d = %02x\n", step, i, d[i]); }
        }
        for (i = 0; i < ga.ga_len; i++)
        {
            if (d[i] != (unsigned char)(0xA0 + i))
            { printf("A.%d LOST at %d = %02x want %02x\n", step, i, d[i], (unsigned char)(0xA0 + i)); }
        }
        ga.ga_len = want;
        for (i = 0; i < ga.ga_len; i++) { d[i] = (unsigned char)(0xA0 + i); }
        hexline("A.live", d, ga.ga_len);
    }
    free(ga.ga_data);
}

/* A2 -- six INDEPENDENT growarrays grown once each, so the null-ga_data path is taken
   seven times in the run and the --nullwatch driver has something to count. */
static void test_fresh(void)
{
    int k, r;
    for (k = 1; k <= 6; k++)
    {
        garray_T ga = { 0, 0, 0, 0, nullptr };
        ga.ga_itemsize = k;
        ga.ga_growsize = k + 1;
        r = ga_grow_inner(&ga, 2);
        printf("A2.%d r=%d maxlen=%d itemsize=%d\n", k, r, ga.ga_maxlen, ga.ga_itemsize);
        free(ga.ga_data);
    }
}

/* B -- THE FAILURE PATH.  realloc leaves the old block valid and allocated, so
   ga_grow_inner must return FAIL with ga_data untouched and NOTHING freed.  The
   allocation is made to fail by asking for more than the sanitizer's allocator will
   give, rather than by interposing anything.  The grow that follows is what turns a
   premature free into a use-after-free the harness can name. */
static void test_grow_fail(void)
{
    garray_T ga = { 0, 0, 0, 0, nullptr };
    int i, r;
    unsigned char *before;

    ga.ga_itemsize = 1;
    ga.ga_growsize = 4;
    r = ga_grow_inner(&ga, 16);
    printf("B.setup r=%d\n", r);
    ga.ga_len = 16;
    for (i = 0; i < 16; i++) { ((unsigned char *)ga.ga_data)[i] = (unsigned char)(0x50 + i); }
    before = ga.ga_data;

    r = ga_grow_inner(&ga, 600 * 1024 * 1024);
    printf("B.fail r=%d same=%d maxlen=%d\n", r, ga.ga_data == before, ga.ga_maxlen);
    hexline("B.after", ga.ga_data, 16);
    r = ga_grow_inner(&ga, 8);
    printf("B.again r=%d\n", r);
    hexline("B.live", ga.ga_data, 16);
    free(ga.ga_data);
}

/* C -- get_keystroke's 100-byte extension, driven directly.  It is UNREACHABLE in a
   recording: an instrumented build of the input marks each of the five ` + "`continue`" + ` paths
   in its loop at 0 of 106 records, so ` + "`len`" + ` never exceeds one ui_inchar() and ` + "`maxlen`" + `
   never falls below 10.  This block is the only instrument that can see it. */
static void test_keystroke(void)
{
    char_u *buf;
    int buflen = 150;
    int len = 115;
    int maxlen;
    int i;

    n_vim_free = 0;
    buf = malloc(buflen);
    for (i = 0; i < buflen; i++) { buf[i] = (char_u)(i * 7 + 1); }
    maxlen = (buflen - 6 - len) / 3;
    printf("C.before buflen=%d len=%d maxlen=%d\n", buflen, len, maxlen);
    if (buf == nullptr)
    {
        printf("C.unreachable\n");
    }
KSBLOCK
    printf("C.after buflen=%d maxlen=%d buf=%s vim_frees=%d\n", buflen, maxlen,
           buf == nullptr ? "null" : "set", n_vim_free);
    if (buf != nullptr)
    {
        for (i = 0; i < len; i++)
        {
            if (buf[i] != (char_u)(i * 7 + 1)) { printf("C LOST at %d\n", i); }
        }
        hexline("C.live", buf, 16);
        free(buf);
    }
}

int main(void)
{
    setbuf(stdout, nullptr);
    test_grow();
    test_fresh();
    test_grow_fail();
    test_keystroke();
    return 0;
}
`

// z34Fn is mkdriver.py's fn(): the definition whose head line is `head`,
// brace-matched, with its return-type line put back in front.
func z34Fn(t, head, rtype string) (string, error) {
	i := strings.Index(t, "\n"+head)
	if i < 0 {
		return "", fmt.Errorf("%s is not in the source", head)
	}
	j := strings.Index(t[i:], "\n{\n")
	if j < 0 {
		return "", fmt.Errorf("%s has no body", head)
	}
	j += i
	d, k := 0, j+1
	for ; k < len(t); k++ {
		if t[k] == '{' {
			d++
		} else if t[k] == '}' {
			d--
			if d == 0 {
				break
			}
		}
	}
	end := k + 2
	if end > len(t) {
		end = len(t)
	}
	return rtype + "\n" + t[i+1:end], nil
}

// z34Block is mkdriver.py's block(): from `head` to the brace that closes
// the first one after it.
func z34Block(t, head, need string) (string, error) {
	i := strings.Index(t, head)
	if i < 0 {
		return "", fmt.Errorf("%s is not in the source", head)
	}
	j := strings.Index(t[i:], "{")
	if j < 0 {
		return "", fmt.Errorf("%s has no brace", head)
	}
	j += i
	d, k := 0, j
	for ; k < len(t); k++ {
		if t[k] == '{' {
			d++
		} else if t[k] == '}' {
			d--
			if d == 0 {
				break
			}
		}
	}
	b := t[i : k+1]
	if !strings.Contains(b, need) {
		return "", fmt.Errorf("the extracted block does not hold %s", cutilRepr(need))
	}
	return b, nil
}

// z34Driver is mkdriver.py: the two rewritten sites extracted at run time
// from a source and dropped into one AddressSanitizer driver.
func z34Driver(src, out string, nullwatch bool) error {
	t := readFile(src)
	ga, err := z34Fn(t, "ga_grow_inner(garray_T *gap, int n)", "    static int")
	if err != nil {
		return err
	}
	mcpy, err := z34Fn(t, "musl_memcpy(void *dest, const void *src, usize n)", "    static void *")
	if err != nil {
		return err
	}
	mset, err := z34Fn(t, "musl_memset(void *dest, int c, usize n)", "    static void *")
	if err != nil {
		return err
	}
	ks, err := z34Block(t, "        else if (maxlen < 10)", "buflen += 100;")
	if err != nil {
		return err
	}
	a := strings.Index(t, "typedef struct growarray")
	b := strings.Index(t, "} garray_T;")
	if a < 0 || b < 0 {
		return fmt.Errorf("garray_T is not in the source")
	}
	gt := t[a : b+len("} garray_T;")]
	if nullwatch {
		// The ONE line that turns the driver into an instrument for trap 1.
		const anchor = "    const unsigned char *s = src;\n"
		if strings.Count(mcpy, anchor) != 1 {
			return fmt.Errorf("musl_memcpy does not have its `const unsigned char *s = src;` line")
		}
		mcpy = strings.Replace(mcpy, anchor,
			anchor+"    if (src == nullptr) { printf(\"MEMCPY-NULL n=%d\\n\", (int)n); }\n", 1)
	}
	body := gt + z34Head + "\n" + ga + "\n" + mcpy + "\n" + mset + "\n" + strings.ReplaceAll(z34Tail, "KSBLOCK", ks)
	return os.WriteFile(out, []byte(body), 0o644)
}

// Zero34 is phase 34's check: the core stops reallocating.
func Zero34(w io.Writer, args []string) error {
	if len(args) != 2 {
		return fmt.Errorf("usage: check zero34 <work-dir> <state-dir>")
	}
	work, state := args[0], args[1]
	f := filepath.Join(work, "zero-vim.c")
	oldC := filepath.Join(state, "old.c")
	r := &rep{tag: "realloc", w: w}
	stop := func(format string, a ...any) error {
		r.say(format, a...)
		return harness.ErrReported
	}
	head := func(ls []string, n int) {
		for i, l := range ls {
			if i >= n {
				break
			}
			fmt.Fprintln(w, l)
		}
	}
	fileLines := func(p string) []string {
		s := strings.TrimRight(readFile(p), "\n")
		if s == "" {
			return nil
		}
		return strings.Split(s, "\n")
	}
	grepLines := func(p string, pred func(string) bool) []string {
		var out []string
		for _, l := range fileLines(p) {
			if pred(l) {
				out = append(out, l)
			}
		}
		return out
	}
	beforeRaw := strings.TrimRight(readFile(filepath.Join(state, "input-lines")), "\n")
	tmp, err := os.MkdirTemp("", "zero34-")
	if err != nil {
		return err
	}
	defer os.RemoveAll(tmp)
	T := func(n string) string { return filepath.Join(tmp, n) }
	mk := readFile(filepath.Join(work, "Makefile"))
	cflagsS, ldflagsS := "", ""
	if m := z29CFlags.FindStringSubmatch(mk); m != nil {
		cflagsS = m[1]
	}
	if m := z29LDFlags.FindStringSubmatch(mk); m != nil {
		ldflagsS = m[1]
	}
	link := func(src, out string) error {
		a := append(append(strings.Fields(cflagsS), strings.Fields(ldflagsS)...), "-o", out, src)
		c := exec.Command("gcc", a...)
		c.Env = append(os.Environ(), "SOURCE_DATE_EPOCH=0")
		return c.Run()
	}

	var wgNew, wgCanon sync.WaitGroup
	var errNew, errCanon error
	var canonLog []byte
	wgNew.Add(1)
	go func() { defer wgNew.Done(); errNew = link(f, T("new")) }()
	newT := readFile(f)
	os.WriteFile(T("canon.c"), []byte(newT), 0o644)
	wgCanon.Add(1)
	go func() {
		defer wgCanon.Done()
		canonLog, errCanon = exec.Command("sh", "tools/canon.sh", T("canon.c")).CombinedOutput()
	}()
	defer func() { wgNew.Wait(); wgCanon.Wait() }()

	// --- 1. the source, as arithmetic on the input ------------------------------
	oldT := readFile(oldC)
	beforeLines, _ := strconv.Atoi(strings.TrimSpace(beforeRaw))
	O, N := strings.Split(oldT, "\n"), strings.Split(newT, "\n")
	if len(O)-1 != beforeLines {
		r.bad("the state directory says the edit was handed %d lines and old.c has %d", beforeLines, len(O)-1)
	}
	split := func(L []string) ([]int, string, string, error) {
		var d []int
		for i, l := range L {
			if z30Dir.MatchString(l) {
				d = append(d, i)
			}
		}
		ok := len(d) > 0
		for k := range d {
			if ok && d[k] != d[0]+k {
				ok = false
			}
		}
		if !ok {
			return nil, "", "", stop("the directives are not one consecutive block, so there is no " +
				"boundary and nothing below distinguishes a core call from a host one")
		}
		return d, strings.Join(L[:d[0]], "\n"), strings.Join(L[d[0]:], "\n"), nil
	}
	od, ocore, ohost, e := split(O)
	if e != nil {
		return e
	}
	nd, ncore, nhost, e := split(N)
	if e != nil {
		return e
	}
	cnt := func(s string) int { return len(z34Realloc.FindAllStringIndex(s, -1)) }
	oc, oh, nc, nh := cnt(ocore), cnt(ohost), cnt(ncore), cnt(nhost)
	if oc != 3 || oh != 1 {
		r.bad("the input has %d `realloc` in the core and %d in the host, where 3 and "+
			"1 were expected", oc, oh)
	}
	if nc != 0 {
		r.bad("`realloc` still occurs %d times in the core, and the phase's whole "+
			"product is that it is 0", nc)
	}
	if nh != oh {
		r.bad("the host's `realloc` went from %d to %d: adjust_types() is below the "+
			"boundary, is the HOST's, and is the reason the symbol does not leave", oh, nh)
	}
	if !strings.Contains(nhost, "adjust_types") {
		r.bad("adjust_types() is not in the host part of the output, and it is what " +
			"the surviving `realloc` belongs to")
	}
	protos := func(text string) []string {
		var out []string
		for _, l := range strings.Split(text, "\n") {
			if z34Proto.MatchString(l) && strings.HasSuffix(l, ";") && !strings.HasPrefix(l, "static") {
				out = append(out, l)
			}
		}
		return out
	}
	op, np := protos(ocore), protos(ncore)
	if len(op)-len(np) != 1 {
		r.bad("the core's plain libc prototype block is %d lines and the input's was "+
			"%d, a difference of %d where 1 was expected.  Input: %s.  Output: %s",
			len(np), len(op), len(op)-len(np), strings.Join(op, " "), strings.Join(np, " "))
	}
	if strings.Contains(ncore, "void *realloc(void *p, usize n);") {
		r.bad("the core still declares realloc")
	}
	setMinus := func(a, b []string) []string {
		in := map[string]bool{}
		for _, x := range b {
			in[x] = true
		}
		seen := map[string]bool{}
		var out []string
		for _, x := range a {
			if !in[x] && !seen[x] {
				out = append(out, x)
				seen[x] = true
			}
		}
		sort.Strings(out)
		return out
	}
	if lost := setMinus(op, np); strings.Join(lost, "\x00") != "void *realloc(void *p, usize n);" {
		r.bad("the prototype block lost [%s] and not realloc's line alone", strings.Join(lost, " / "))
	}
	if gained := setMinus(np, op); len(gained) > 0 {
		r.bad("the prototype block GAINED %s", strings.Join(gained, " / "))
	}
	if strings.Count(newT, z34GA) != 1 {
		r.bad("ga_grow_inner's rewrite is not in the output exactly once, with the " +
			"copy and the free guarded by `ga_data != nullptr` (trap 1), the " +
			"`return FAIL` above anything being freed (trap 2) and the tail-zeroing " +
			"statement unmoved below the copy (trap 3)")
	}
	if strings.Count(newT, z34KS) != 1 {
		r.bad("get_keystroke's rewrite is not in the output exactly once, with the " +
			"old size saved as `t_buflen` beside `t_buf`, `vim_free(t_buf)` left " +
			"exactly where the input had it, and the success-path free being " +
			"`free()` -- vim_free declines while really_exiting and realloc did not")
	}
	if strings.Count(newT, "vim_free(t_buf);") != 1 {
		r.bad("the input's own `vim_free(t_buf)` failure path is not in the output " +
			"exactly once")
	}
	const added = 5 + 6 - 1
	if len(N)-len(O) != added {
		r.bad("the output is %d lines and the input was %d, a difference of %d where "+
			"%d was expected -- 5 at ga_grow_inner, 6 at get_keystroke and -1 for "+
			"the prototype", len(N)-1, len(O)-1, len(N)-len(O), added)
	}
	if len(nd) != len(od) {
		r.bad("the output has %d directives and the input %d", len(nd), len(od))
	} else {
		same := true
		for k := range nd {
			if N[nd[k]] != O[od[k]] {
				same = false
			}
		}
		if !same {
			r.bad("the directives are not the ones the input had")
		} else if nd[0]-od[0] != len(N)-len(O) {
			r.bad("the boundary moved by %d lines and the file by %d: every line this "+
				"phase touches is above the first `#include`", nd[0]-od[0], len(N)-len(O))
		}
	}
	if z27Runs(N) != z27Runs(O) {
		r.bad("the edit and the sweep left %d runs of two blank lines where there "+
			"were %d", z27Runs(N), z27Runs(O))
	}
	if err := r.done(); err != nil {
		return err
	}
	r.say("`realloc` is 3 -> 0 above the boundary and %d -> %d below it.  THE "+
		"SYMBOL DOES NOT LEAVE and this phase does not claim it does: adjust_types(), in "+
		"the formatter island phase 27 moved down, is the host's and still calls it", oh, nh)
	r.say("the core's plain libc prototype block is %d lines where the input's was "+
		"%d, and the one it lost is `void *realloc(void *p, usize n);` -- counted from the "+
		"input, never stated here, because phases 31 and 35 shrink the same block", len(np), len(op))
	r.say("both rewrites are in the output exactly once: ga_grow_inner with the copy " +
		"and the free GUARDED by `ga_data != nullptr`, its `return FAIL` above anything " +
		"being freed, and its tail-zeroing statement unmoved below the copy; " +
		"get_keystroke with the old size saved as `t_buflen` beside `t_buf`, the " +
		"`vim_free(t_buf)` failure path untouched, and `free()` on the success path")
	r.say("%d lines -> %d, exactly the %d this phase adds, the %d directives are the "+
		"input's own and the boundary moved by exactly the lines the file gained.  "+
		"Blank-line runs unmoved at %d", len(O)-1, len(N)-1, added, len(nd), z27Runs(N))

	// --- 2. canon.sh -----------------------------------------------------------------
	wgCanon.Wait()
	if errCanon != nil {
		r.say("tools/canon.sh failed on the output:")
		head(strings.Split(string(canonLog), "\n"), 10)
		return harness.ErrReported
	}
	if !z30Same(f, T("canon.c")) {
		r.say("tools/canon.sh is not a no-op on the output -- the new lines are not written the way this " +
			"file writes everything else:")
		head(z30Diff(f, T("canon.c")), 12)
		return harness.ErrReported
	}
	r.say("tools/canon.sh is a NO-OP on the output: the eleven new lines are written the way this file " +
		"writes everything else")
	for _, tool := range []string{"orphanopts", "nvidx", "zhostonly"} {
		c := exec.Command("sh", "tools/st.sh", tool, f)
		c.Stdout, c.Stderr = w, w
		if err := c.Run(); err != nil {
			return harness.ErrReported
		}
	}

	// --- 3. THE UNIT HARNESS -----------------------------------------------------------
	type ctl struct{ name, a, b string }
	controls := []ctl{
		{"c_copynew", "musl_memcpy(pp, gap->ga_data, old_len);", "musl_memcpy(pp, gap->ga_data, new_len);"},
		{"c_nocopy", "musl_memcpy(pp, gap->ga_data, old_len);", "musl_memcpy(pp, gap->ga_data, 0);"},
		{"c_freefail", `    pp = malloc(new_len);
    if (pp == nullptr)
    {
        return FAIL;
    }`, `    pp = malloc(new_len);
    if (pp == nullptr)
    {
        free(gap->ga_data);
        return FAIL;
    }`},
		{"c_noguard", `    if (gap->ga_data != nullptr)
    {
        musl_memcpy(pp, gap->ga_data, old_len);
        free(gap->ga_data);
    }`, `    musl_memcpy(pp, gap->ga_data, old_len);
    free(gap->ga_data);`},
		{"c_keycopy", "musl_memcpy(buf, t_buf, t_buflen);", "musl_memcpy(buf, t_buf, buflen);"},
		{"c_keynofree", `                musl_memcpy(buf, t_buf, t_buflen);
                free(t_buf);`, `                musl_memcpy(buf, t_buf, t_buflen);`},
		{"c_keyfreeboth", `            if (buf == nullptr)
            {
                vim_free(t_buf);
            }
            else
            {
                musl_memcpy(buf, t_buf, t_buflen);
                free(t_buf);
            }`, `            vim_free(t_buf);
            if (buf != nullptr)
            {
                musl_memcpy(buf, t_buf, t_buflen);
            }`},
	}
	for _, c := range controls {
		if strings.Count(newT, c.a) != 1 {
			return stop("the control %s has no unique anchor in the output", c.name)
		}
		os.WriteFile(T(c.name+".c"), []byte(strings.Replace(newT, c.a, c.b, 1)), 0o644)
	}
	r.say("seven controls written on the output: c_copynew copies new_len where the " +
		"block is old_len, c_nocopy copies nothing, c_freefail frees the old block on the " +
		"failure path where the original does not, c_noguard drops the `ga_data != " +
		"nullptr` guard, c_keycopy copies buflen where the block is t_buflen, c_keynofree " +
		"leaves the old buffer allocated, c_keyfreeboth frees it on both paths")

	const asanOpt = "allocator_may_return_null=1:max_allocation_size_mb=256:detect_leaks=1"
	drivers := []string{"old", "new", "c_copynew", "c_nocopy", "c_freefail", "c_noguard", "c_keycopy",
		"c_keynofree", "c_keyfreeboth"}
	var wgD sync.WaitGroup
	build := func(v string) {
		wgD.Add(1)
		go func() {
			defer wgD.Done()
			c := exec.Command("gcc", "-O0", "-g", "-fsanitize=address", "-o", T("d."+v), T("d."+v+".c"))
			lf, _ := os.Create(T("dbuild." + v))
			c.Stderr = lf
			c.Run()
			lf.Close()
		}()
	}
	for _, v := range drivers {
		src := T(v + ".c")
		switch v {
		case "old":
			src = oldC
		case "new":
			src = f
		}
		if err := z34Driver(src, T("d."+v+".c"), false); err != nil {
			wgD.Wait()
			fmt.Fprintln(w, err.Error())
			return harness.ErrReported
		}
		build(v)
	}
	for _, x := range []struct{ v, src string }{{"nw_new", f}, {"nw_noguard", T("c_noguard.c")}} {
		if err := z34Driver(x.src, T("d."+x.v+".c"), true); err != nil {
			wgD.Wait()
			fmt.Fprintln(w, err.Error())
			return harness.ErrReported
		}
	}
	build("nw_new")
	build("nw_noguard")
	wgD.Wait()
	all := append(append([]string{}, drivers...), "nw_new", "nw_noguard")
	for _, v := range all {
		if fi, e := os.Stat(T("d." + v)); e != nil || fi.Mode()&0o111 == 0 {
			r.say("the unit driver for %s did not build:", v)
			head(fileLines(T("dbuild."+v)), 8)
			return harness.ErrReported
		}
	}
	runDriver := func(v string) {
		raw, _ := os.Create(T("raw." + v))
		c := exec.Command(T("d." + v))
		c.Env = append(os.Environ(), "ASAN_OPTIONS="+asanOpt)
		c.Stdout, c.Stderr = raw, raw
		c.Run()
		raw.Close()
		s := readFile(T("raw." + v))
		s = z34Pid.ReplaceAllString(s, "==PID==")
		s = z34Addr.ReplaceAllString(s, "0xADDR")
		s = z34DrvPath.ReplaceAllString(s, "DRIVER.c")
		s = z34LC.ReplaceAllString(s, ":L:C")
		os.WriteFile(T("run."+v), []byte(s), 0o644)
	}
	for _, v := range all {
		runDriver(v)
	}
	// The transcript must be reproducible, or nothing below it means anything.
	runDriver("new")
	os.WriteFile(T("run.new2"), []byte(readFile(T("run.new"))), 0o644)
	runDriver("new")
	if !z30Same(T("run.new"), T("run.new2")) {
		r.say("two runs of the output's unit driver differ, so the comparison below is not one:")
		head(z30Diff(T("run.new2"), T("run.new")), 8)
		return harness.ErrReported
	}
	isFinding := func(l string) bool { return strings.Contains(l, "ERROR: ") || strings.Contains(l, "SUMMARY: ") }
	for _, v := range []string{"old", "new"} {
		if g := grepLines(T("run."+v), isFinding); len(g) > 0 {
			r.say("the %s unit driver reports a sanitizer finding, and neither may:", v)
			head(g, 2)
			return harness.ErrReported
		}
	}
	if !z30Same(T("run.old"), T("run.new")) {
		r.say("THE REWRITE IS NOT THE SAME FUNCTION: the input's ga_grow_inner and get_keystroke block and " +
			"the output's give different transcripts:")
		head(z30Diff(T("run.old"), T("run.new")), 14)
		return harness.ErrReported
	}
	runNew := fileLines(T("run.new"))
	for _, want := range []string{"A.start data=null maxlen=0", "B.fail r=0 same=1 maxlen=16", "B.again r=1",
		"C.before buflen=150 len=115 maxlen=9", "C.after buflen=250 maxlen=43 buf=set vim_frees=0"} {
		if !contains(runNew, want) {
			r.say("the unit transcript does not hold `%s`, so it is not driving what this check says it drives:", want)
			head(runNew, 20)
			return harness.ErrReported
		}
	}
	lostOrTail := func(l string) bool { return strings.Contains(l, "LOST at ") || strings.Contains(l, "TAIL-NOT-ZERO") }
	if g := grepLines(T("run.new"), lostOrTail); len(g) > 0 {
		r.say("the output's unit driver loses bytes across a grow, or leaves the new tail non-zero:")
		head(g, 4)
		return harness.ErrReported
	}
	r.say("THE UNIT HARNESS: ga_grow_inner(), musl_memcpy(), musl_memset(), garray_T and get_keystroke's "+
		"extension block, EXTRACTED AT RUN TIME from %s/old.c and from the output and run through the same "+
		"AddressSanitizer driver -- eight doublings from an empty growarray, six independent first grows, a "+
		"failed allocation and the 100-byte extension.  The two transcripts are IDENTICAL, %d lines, neither "+
		"reports a finding, no byte is lost across a grow and every new tail is zero.  `B.fail r=0 same=1` IS "+
		"TRAP 2: the allocation failed, ga_data is the block it was, and the grow after it reads that block "+
		"back intact", state, countLines([]byte(readFile(T("run.new")))))

	for _, x := range []struct{ name, want string }{
		{"c_copynew", "heap-buffer-overflow"}, {"c_freefail", "heap-use-after-free"},
		{"c_keycopy", "heap-buffer-overflow"}, {"c_keynofree", "detected"},
		{"c_keyfreeboth", "heap-use-after-free"},
	} {
		if z30Same(T("run.new"), T("run."+x.name)) {
			return stop("the control %s changes nothing in the unit harness, so the harness is not testing what "+
				"this phase claims", x.name)
		}
		if !strings.Contains(readFile(T("run."+x.name)), x.want) {
			r.say("the control %s was expected to give `%s` and gave:", x.name, x.want)
			if g := grepLines(T("run."+x.name), isFinding); len(g) > 0 {
				head(g, 2)
			} else {
				head(fileLines(T("run."+x.name)), 6)
			}
			return harness.ErrReported
		}
	}
	if z30Same(T("run.new"), T("run.c_nocopy")) {
		return stop("c_nocopy, which copies nothing at all, gives the same transcript as the output")
	}
	lostN := len(grepLines(T("run.c_nocopy"), func(l string) bool { return strings.Contains(l, "LOST at ") }))
	if lostN == 0 {
		return stop("c_nocopy does not lose bytes, so the transcript is not reading the copy back")
	}
	r.say("SIX CONTROLS MOVE, each with its own named finding and not one bucket: c_copynew (copies new_len) "+
		"heap-buffer-overflow READ past the old block -- which is INVISIBLE to any recording, the overread "+
		"bytes being overwritten by the memset that follows; c_freefail (frees on the failure path) "+
		"heap-use-after-free at the grow that follows; c_keycopy heap-buffer-overflow; c_keynofree a "+
		"LeakSanitizer report; c_keyfreeboth heap-use-after-free.  c_nocopy gives no sanitizer finding at all "+
		"and is caught by the transcript instead, %d bytes lost", lostN)

	if !z30Same(T("run.new"), T("run.c_noguard")) {
		r.say("c_noguard was measured to change NOTHING in this harness and now changes something, which is a " +
			"better result than the one this check was written against -- read the diff and rewrite this " +
			"paragraph:")
		head(z30Diff(T("run.new"), T("run.c_noguard")), 10)
		return harness.ErrReported
	}
	nullN := func(v string) int {
		return len(grepLines(T("run."+v), func(l string) bool { return strings.Contains(l, "MEMCPY-NULL") }))
	}
	nwNew, nwNg := nullN("nw_new"), nullN("nw_noguard")
	if nwNew != 0 || nwNg < 7 {
		return stop("the null watch reports %d nulls reaching the copy in the output and %d in the unguarded "+
			"control, where 0 and at least 7 were expected", nwNew, nwNg)
	}
	r.say("THE GUARD BUYS NOTHING HERE AND IS KEPT ANYWAY, and that is reported rather than hidden.  c_noguard "+
		"-- the rewrite WITHOUT `if (gap->ga_data != nullptr)` -- gives a byte-identical unit transcript and no "+
		"sanitizer finding, because a null ga_data implies ga_maxlen == 0 implies old_len == 0, musl_memcpy's "+
		"`for (; n; n--)` never dereferences and free(nullptr) is a no-op.  What the guard buys is on the PAGE, "+
		"which is what ZERO-PLAN.md 4c's transpilation rule asks for: the same driver with musl_memcpy "+
		"announcing a null source reports %d from the output and %d from the unguarded control.  A null passed "+
		"to a copy is not something the core may leave for a runtime to be lenient about", nwNew, nwNg)

	// --- 4. the symbols, and the binary ------------------------------------------------
	wgNew.Wait()
	if errNew != nil {
		return stop("the output did not build with '%s' '%s'", cflagsS, ldflagsS)
	}
	for _, x := range []struct{ src, obj string }{{oldC, "old.o"}, {f, "new.o"}} {
		if out, err := exec.Command("gcc", "-c", "-O0", "-fno-stack-protector", "-o", T(x.obj), x.src).CombinedOutput(); err != nil {
			w.Write(out)
			return harness.ErrReported
		}
	}
	uOld := nmField26(T("old.o"), []string{"-u"}, 1)
	uNew := nmField26(T("new.o"), []string{"-u"}, 1)
	if g, c := minus26(uOld, uNew), minus26(uNew, uOld); len(g)+len(c) > 0 {
		return stop("`nm -u` moved: gone [%s] arrived [%s].  THIS IS AN EQUALITY AND THE PHASE PREDICTS IT: "+
			"the core stops calling realloc and adjust_types(), below the boundary, does not, so the symbol stays",
			z31Words(g), z31Words(c))
	}
	if !contains(uNew, "realloc") {
		return stop("`realloc` is NOT undefined any more, and this phase does not claim to free it: " +
			"adjust_types() is the host's and still calls it.  Phases 14, 15 and 21 each require it to be there")
	}
	if !contains(uNew, "malloc") || !contains(uNew, "free") {
		return stop("`malloc` or `free` left, and the rewrite is written over both")
	}
	ext := nmField26(T("new.o"), []string{"--extern-only", "--defined-only"}, 2)
	if s := z31Words(ext); s != "main " {
		return stop("the output defines external symbols other than main: %s", s)
	}
	r.say("`nm -u` is THE SAME SET, %d names, as a `comm` empty in BOTH directions, and `main` is still the "+
		"only external symbol.  `realloc` IS STILL IN IT, which is what a reader will not expect: the core no "+
		"longer calls it, adjust_types() below the boundary does, and phases 14, 15 and 21 each assert it is "+
		"there", len(uNew))
	r.say("the binary is %d bytes against the input's %d.  This phase is NOT tier 1 of CLAUDE.md's table and "+
		"does not pretend to be: one call becomes a test, a call, a copy loop and a free, and at -O0 that is "+
		"different instructions", sizeOf(T("new")), sizeOf(filepath.Join(state, "old")))
	pc := exec.Command("sh", "tools/phasecheck.sh", work, f, filepath.Join(state, "symbols"))
	pc.Stdout, pc.Stderr = w, w
	if err := pc.Run(); err != nil {
		return harness.ErrReported
	}

	// --- 5. the editor.c cut, and its warning set compared WITH THE INPUT'S ------------
	bset := map[string][]string{}
	cutN := map[string]int{}
	for _, x := range []struct{ side, src string }{{"old", oldC}, {"new", f}} {
		lines := z28Cut(readFile(x.src))
		var dl []string
		for i, l := range lines {
			if z30Dir.MatchString(l) {
				dl = append(dl, fmt.Sprintf("%d:%s", i+1, l))
			}
		}
		if len(dl) > 0 {
			r.say("the %s cut holds a directive, so it found the wrong line:", x.side)
			head(dl, 3)
			return harness.ErrReported
		}
		text := ""
		for _, l := range lines {
			text += l + "\n"
		}
		cp := T("ed." + x.side + ".c")
		os.WriteFile(cp, []byte(text), 0o644)
		c := exec.Command("gcc", "-O0", "-fno-stack-protector", "-Wall", "-Wextra", "-Wno-unused-parameter",
			"-fsyntax-only", cp)
		var eb strings.Builder
		c.Stderr = &eb
		c.Run()
		var errs, warns []string
		for _, l := range strings.Split(eb.String(), "\n") {
			if strings.Contains(l, ": error:") {
				errs = append(errs, l)
			}
			if strings.Contains(l, ": warning: ") && !strings.Contains(l, "used but never defined") {
				warns = append(warns, l)
			}
		}
		if len(errs) > 0 {
			r.say("the %s cut does not parse on its own:", x.side)
			head(errs, 4)
			return harness.ErrReported
		}
		set := map[string]bool{}
		for _, m := range z30Undef.FindAllStringSubmatch(eb.String(), -1) {
			set[m[1]] = true
		}
		bset[x.side] = z27Keys(set)
		if len(warns) > 0 {
			r.say("the %s cut has a warning that is not a boundary name:", x.side)
			head(warns, 3)
			return harness.ErrReported
		}
		cutN[x.side] = len(lines)
	}
	if strings.Join(bset["old"], " ") != strings.Join(bset["new"], " ") {
		return stop("the core -> host boundary moved: gone [%s] arrived [%s].  malloc and free are declared "+
			"non-static and are not in this set, and dropping realloc's prototype removes nothing from it",
			z31Words(minus26(bset["old"], bset["new"])), z31Words(minus26(bset["new"], bset["old"])))
	}
	r.say("the `make editor.c` cut: %d lines -> %d, 0 directives, 0 errors under `-fsyntax-only`, and the "+
		"WHOLE warning set is the core -> host boundary -- %d names, IDENTICAL to the input's, compared name "+
		"by name at run time", cutN["old"], cutN["new"], len(bset["new"]))

	// --- 6. the instrumented pair on the two FULL binaries ------------------------------
	const anch = "    new_len = (usize)gap->ga_itemsize * (gap->ga_len + n);\n"
	const ins = anch + "    if (gap->ga_data == nullptr) { write(2, \"GA-NULL\\n\", 8); } else { write(2, \"GA-HAVE\\n\", 8); }\n" +
		"    if ((usize)gap->ga_itemsize * (usize)gap->ga_maxlen > new_len) { write(2, \"GA-SHRINK\\n\", 10); }\n"
	for _, x := range []struct{ src, name string }{{oldC, "i_old"}, {f, "i_new"}} {
		t := readFile(x.src)
		if strings.Count(t, anch) != 1 {
			return stop("ga_grow_inner's new_len line is not in %s exactly once, so "+
				"the instrument cannot be identical on the two sides", x.src)
		}
		os.WriteFile(T(x.name+".c"), []byte(strings.Replace(t, anch, ins, 1)), 0o644)
	}
	os.WriteFile(T("c_ncopy_full.c"), []byte(readFile(T("c_nocopy.c"))), 0o644)
	var wgI sync.WaitGroup
	for _, v := range []string{"i_old", "i_new", "c_ncopy_full"} {
		v := v
		wgI.Add(1)
		go func() { defer wgI.Done(); link(T(v+".c"), T(v)) }()
	}
	wgI.Wait()
	for _, v := range []string{"i_old", "i_new", "c_ncopy_full"} {
		if fi, e := os.Stat(T(v)); e != nil || fi.Mode()&0o111 == 0 {
			return stop("the instrumented build %s did not link", v)
		}
	}

	// --- 7. the recordings: the declared delta is NOTHING AT ALL -------------------------
	oldBin, _ := filepath.Abs(filepath.Join(state, "old"))
	var wgR sync.WaitGroup
	recErr := make([]error, 4)
	for k, x := range []struct{ bin, src, out string }{
		{oldBin, oldC, "REC.old"}, {T("new"), f, "REC.new"},
		{T("i_old"), T("i_old.c"), "REC.i_old"}, {T("i_new"), T("i_new.c"), "REC.i_new"},
	} {
		k, x := k, x
		wgR.Add(1)
		go func() {
			defer wgR.Done()
			recErr[k] = exec.Command("sh", "tools/zrecord.sh", x.bin, x.src, T(x.out)).Run()
		}()
	}
	wgR.Add(1)
	go func() {
		defer wgR.Done()
		exec.Command("sh", "tools/st.sh", "zcases", T("c_ncopy_full"), T("SCR.nocopy")).Run()
	}()
	wgR.Wait()
	// Collected by bare `wait $pid`s, as the shell does: a recording that fails
	// ends the check with nothing printed.  One of the fifteen sites a later
	// pass repairs; repairing it here would break report identity.
	for _, e := range recErr {
		if e != nil {
			return harness.ErrReported
		}
	}
	if dl := diffRQ(T("REC.old"), T("REC.new")); len(dl) > 0 {
		r.say("the declared delta is NOTHING AT ALL and the two recordings differ:")
		head(dl, 12)
		return harness.ErrReported
	}
	type mk3 struct{ hit, total, files int }
	marks := func(rec, token string) mk3 {
		var m mk3
		for _, rel := range walkFiles(rec) {
			m.files++
			if c := strings.Count(readFile(filepath.Join(rec, rel)), token); c > 0 {
				m.hit++
				m.total += c
			}
		}
		return m
	}
	r7 := &rep{tag: "realloc", w: w}
	seen := map[[2]string]mk3{}
	for _, side := range []string{"i_old", "i_new"} {
		for _, tok := range []string{"GA-NULL\n", "GA-HAVE\n", "GA-SHRINK\n"} {
			seen[[2]string{side, tok}] = marks(T("REC."+side), tok)
		}
		if s := seen[[2]string{side, "GA-SHRINK\n"}]; s.total != 0 {
			r7.bad("the %s instrument marks a SHRINK %d times: musl_memcpy copies the "+
				"OLD size at both sites and that is only right because neither can "+
				"ask for less than it has", side, s.total)
		}
	}
	for _, tok := range []string{"GA-NULL\n", "GA-HAVE\n"} {
		a, b := seen[[2]string{"i_old", tok}], seen[[2]string{"i_new", tok}]
		if a != b {
			r7.bad("the identical instrument marks `%s` (%d, %d, %d) on the input and (%d, %d, %d) on the "+
				"output: the two take the branch a different number of times",
				strings.TrimSpace(tok), a.hit, a.total, a.files, b.hit, b.total, b.files)
		}
	}
	nl := seen[[2]string{"i_new", "GA-NULL\n"}]
	hv := seen[[2]string{"i_new", "GA-HAVE\n"}]
	if nl.files < 100 {
		r7.bad("a recording is %d records, and a measurement over a corpus nothing "+
			"wrote passes.  The count is REPORTED and not pinned: it was 106 when "+
			"this phase was written and is 122 since zero phase 40 added the "+
			"memline corpus", nl.files)
	}
	if nl.total < 1000 || hv.total < 500 {
		r7.bad("ga_grow_inner is called %d times with a null ga_data and %d times with "+
			"one, and this phase's claim that a byte-identical recording is STRONG "+
			"evidence rests on it being the hot path it was measured to be", nl.total, hv.total)
	}
	if err := r7.done(); err != nil {
		return err
	}
	r.say("THE INSTRUMENTED PAIR, identical text inserted at a line both sources "+
		"have: ga_grow_inner runs %d times per recording on the INPUT and %d on the "+
		"OUTPUT -- %d of them with `ga_data == nullptr`, which is trap 1 and is the "+
		"MAJORITY case and not an edge -- in %d of the %d records, the two that do not "+
		"mark being ref-pty.txt and ref-term.txt.  A SHRINK is marked 0 times on either "+
		"side, which is why copying the old size is right",
		nl.total+hv.total, nl.total+hv.total, nl.total, nl.hit, nl.files)
	moved := len(diffRQ(T("REC.new")+"/screen", T("SCR.nocopy")))
	if moved < 100 {
		return stop("the control whose ga_grow_inner copies nothing moves only %d of the 102 screen cases, "+
			"where 102 were measured -- the byte-identical recording above would then be two numbers agreeing", moved)
	}
	r.say("the declared delta is NOTHING AT ALL and TWO FULL RECORDINGS ARE BYTE-IDENTICAL -- 102 screen cases, "+
		"every Ex command, every command line, the pty scenarios and the terminal table.  AND HERE THAT IS "+
		"STRONG EVIDENCE RATHER THAN THE WEAK KIND, because ga_grow_inner is on the path of every growarray in "+
		"the editor: the control that keeps the rewrite and copies NOTHING moves %d of the 102 screen cases", moved)
	return nil
}
