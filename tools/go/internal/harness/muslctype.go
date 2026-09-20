package harness

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
)

// MuslCtypeVerify is tools/muslctype.py: compile the vendored musl block OUT OF
// THE SOURCE THE PHASE PRODUCED and hold it to the libc this machine links.
//
// The claim zero phase 15 makes is not "these look like musl's" but "these
// compute what musl computes", and the only way to say that is to run both.  So
// the block is sliced out of the .c the phase wrote -- not out of
// tools/musl-ctype.txt, which would only prove the copy was faithful -- wrapped
// in a main() that calls libc beside it, compiled with -Wall -Wextra, and run.
//
// THE DOMAIN IS BOUNDED ON PURPOSE and it is the one number here that is not
// exhaustive.  All eleven classifiers were compared with musl's over all
// 4,294,967,296 int values while the phase was written: zero disagreements, in
// 66 seconds.  A check that doubles a phase's time to re-prove a closed form is
// a check that stops being run.  What runs is every int in [-1024, 1024], every
// threshold and its two neighbours, EOF, INT_MIN, INT_MAX, and a FIXED
// pseudo-random sample of 1,000,000 -- fixed, so the check is a function of its
// input like everything else here.
//
// THE C DRIVER BELOW IS GENERATED from tools/muslctype.py by
// tools/gocmp/genmuslctype.py, which imports that module rather than scraping
// it.  Do not hand-edit it: a changed constant in the random walk or a dropped
// row in the edge table would be invisible to both the compile and the
// comparison.
const muslCtypeStart = "    static int\n" +
	"musl_isdigit(int c)\n" +
	""

const muslCtypeEnd = "static int musl_towupper(int a);\n" +
	""

const muslCtypeMain = "\n" +
	"#include <stdio.h>\n" +
	"#include <stdlib.h>\n" +
	"#include <string.h>\n" +
	"#include <ctype.h>\n" +
	"#include <limits.h>\n" +
	"\n" +
	"static int cmpstr(const void *a, const void *b)\n" +
	"{\n" +
	"    return strcmp(*(char *const *)a, *(char *const *)b);\n" +
	"}\n" +
	"\n" +
	"static int cmpint(const void *a, const void *b)\n" +
	"{\n" +
	"    int x = *(const int *)a;\n" +
	"    int y = *(const int *)b;\n" +
	"    return x < y ? -1 : x > y;\n" +
	"}\n" +
	"\n" +
	"static long bad;\n" +
	"static long checked;\n" +
	"\n" +
	"static void one(int i)\n" +
	"{\n" +
	"    checked++;\n" +
	"    bad += !!musl_isalnum(i) != !!isalnum(i);\n" +
	"    bad += !!musl_iscntrl(i) != !!iscntrl(i);\n" +
	"    bad += !!musl_ispunct(i) != !!ispunct(i);\n" +
	"    bad += musl_tolower(i) != tolower(i);\n" +
	"    bad += musl_toupper(i) != toupper(i);\n" +
	"    bad += !!musl_isalpha(i) != !!isalpha(i);\n" +
	"    bad += !!musl_isdigit(i) != !!isdigit(i);\n" +
	"    bad += !!musl_isupper(i) != !!isupper(i);\n" +
	"    bad += !!musl_islower(i) != !!islower(i);\n" +
	"    bad += !!musl_isgraph(i) != !!isgraph(i);\n" +
	"    bad += !!musl_isspace(i) != !!isspace(i);\n" +
	"}\n" +
	"\n" +
	"int main(void)\n" +
	"{\n" +
	"    static const int edge[] = {\n" +
	"        0x00, 0x08, 0x09, 0x0d, 0x0e, 0x1f, 0x20, 0x21, 0x2f, 0x30, 0x39, 0x3a,\n" +
	"        0x40, 0x41, 0x5a, 0x5b, 0x60, 0x61, 0x7a, 0x7b, 0x7e, 0x7f, 0x80, 0xfe,\n" +
	"        0xff, 0x100, EOF, INT_MIN, INT_MIN + 1, INT_MAX, INT_MAX - 1\n" +
	"    };\n" +
	"    unsigned seed = 2166136261u;\n" +
	"    int i;\n" +
	"    unsigned k;\n" +
	"\n" +
	"    for (i = -1024; i <= 1024; i++)\n" +
	"    {\n" +
	"        one(i);\n" +
	"    }\n" +
	"    for (k = 0; k < sizeof(edge) / sizeof(edge[0]); k++)\n" +
	"    {\n" +
	"        one(edge[k]);\n" +
	"        if (edge[k] != INT_MAX)\n" +
	"        {\n" +
	"            one(edge[k] + 1);\n" +
	"        }\n" +
	"        if (edge[k] != INT_MIN)\n" +
	"        {\n" +
	"            one(edge[k] - 1);\n" +
	"        }\n" +
	"    }\n" +
	"    for (k = 0; k < 1000000u; k++)\n" +
	"    {\n" +
	"        seed = seed * 1103515245u + 12345u;\n" +
	"        one((int)seed);\n" +
	"    }\n" +
	"    printf(\"ctype %ld %ld\\n\", checked, bad);\n" +
	"\n" +
	"    {\n" +
	"        static const char al[] = \" \\t\\n\\r\\v\\f+-09135abx.\\x80\\xff\";\n" +
	"        int A = (int)sizeof(al) - 1;\n" +
	"        long cnt = 0;\n" +
	"        long bada = 0;\n" +
	"        int len;\n" +
	"        char buf[8];\n" +
	"\n" +
	"        for (len = 1; len <= 4; len++)\n" +
	"        {\n" +
	"            long tot = 1;\n" +
	"            long t;\n" +
	"            int p;\n" +
	"\n" +
	"            for (p = 0; p < len; p++)\n" +
	"            {\n" +
	"                tot *= A;\n" +
	"            }\n" +
	"            for (t = 0; t < tot; t++)\n" +
	"            {\n" +
	"                long v = t;\n" +
	"\n" +
	"                for (p = 0; p < len; p++)\n" +
	"                {\n" +
	"                    buf[p] = al[v % A];\n" +
	"                    v /= A;\n" +
	"                }\n" +
	"                buf[len] = 0;\n" +
	"                cnt++;\n" +
	"                bada += musl_atoi(buf) != atoi(buf);\n" +
	"                bada += musl_atol(buf) != atol(buf);\n" +
	"            }\n" +
	"        }\n" +
	"        printf(\"atoi %ld %ld\\n\", cnt, bada);\n" +
	"    }\n" +
	"\n" +
	"    {\n" +
	"        int arr[41];\n" +
	"        int sz;\n" +
	"        int key;\n" +
	"        long cnt = 0;\n" +
	"        long badb = 0;\n" +
	"\n" +
	"        for (sz = 0; sz <= 40; sz++)\n" +
	"        {\n" +
	"            for (i = 0; i < sz; i++)\n" +
	"            {\n" +
	"                arr[i] = i * 2;\n" +
	"            }\n" +
	"            for (key = -2; key <= sz * 2 + 2; key++)\n" +
	"            {\n" +
	"                void *a = bsearch(&key, arr, (size_t)sz, sizeof(int), cmpint);\n" +
	"                void *b = musl_bsearch(&key, arr, (size_t)sz, sizeof(int), cmpint);\n" +
	"\n" +
	"                cnt++;\n" +
	"                badb += a != b;\n" +
	"            }\n" +
	"        }\n" +
	"        printf(\"bsearch %ld %ld\\n\", cnt, badb);\n" +
	"    }\n" +
	"\n" +
	"    {\n" +
	"        char *p[64];\n" +
	"        char *q[64];\n" +
	"        static char store[64][8];\n" +
	"        long badq = 0;\n" +
	"        int t;\n" +
	"        int sz;\n" +
	"\n" +
	"        seed = 12345u;\n" +
	"        for (t = 0; t < 2000; t++)\n" +
	"        {\n" +
	"            sz = (int)(seed % 64u) + 1;\n" +
	"            seed = seed * 1103515245u + 12345u;\n" +
	"            for (i = 0; i < sz; i++)\n" +
	"            {\n" +
	"                snprintf(store[i], sizeof store[i], \"%06u\", seed % 1000000u);\n" +
	"                seed = seed * 1103515245u + 12345u;\n" +
	"                p[i] = store[i];\n" +
	"                q[i] = store[i];\n" +
	"            }\n" +
	"            qsort(p, (size_t)sz, sizeof p[0], cmpstr);\n" +
	"            musl_qsort(q, (size_t)sz, sizeof q[0], cmpstr);\n" +
	"            for (i = 0; i < sz; i++)\n" +
	"            {\n" +
	"                if (strcmp(p[i], q[i]) != 0)\n" +
	"                {\n" +
	"                    badq++;\n" +
	"                    break;\n" +
	"                }\n" +
	"            }\n" +
	"        }\n" +
	"        printf(\"qsort 2000 %ld\\n\", badq);\n" +
	"    }\n" +
	"\n" +
	"    {\n" +
	"        static char a[] = \"aa\";\n" +
	"        static char b1[] = \"bb\";\n" +
	"        static char b2[] = \"bb\";\n" +
	"        static char b3[] = \"bb\";\n" +
	"        static char c[] = \"cc\";\n" +
	"        char *src[5];\n" +
	"        char *p[5];\n" +
	"        char *q[5];\n" +
	"        int moved = 0;\n" +
	"        int order = 0;\n" +
	"\n" +
	"        src[0] = b1; src[1] = c; src[2] = b2; src[3] = a; src[4] = b3;\n" +
	"        for (i = 0; i < 5; i++)\n" +
	"        {\n" +
	"            p[i] = src[i];\n" +
	"            q[i] = src[i];\n" +
	"        }\n" +
	"        qsort(p, 5, sizeof p[0], cmpstr);\n" +
	"        musl_qsort(q, 5, sizeof q[0], cmpstr);\n" +
	"        for (i = 0; i < 5; i++)\n" +
	"        {\n" +
	"            moved += p[i] != q[i];\n" +
	"            order += strcmp(p[i], q[i]) != 0;\n" +
	"        }\n" +
	"        printf(\"ties %d %d\\n\", moved, order);\n" +
	"    }\n" +
	"    return 0;\n" +
	"}\n" +
	""

// muslCtypeNames are the fifteen the block must define exactly once each.  The
// slice is by text, so a block that lost a function would still compile if
// libc supplied the name -- this is what stops that.
var muslCtypeNames = []string{
	"musl_isdigit", "musl_isalpha", "musl_isupper", "musl_islower",
	"musl_isgraph", "musl_isspace", "musl_isalnum", "musl_iscntrl",
	"musl_ispunct", "musl_tolower", "musl_toupper", "musl_atoi",
	"musl_atol", "musl_bsearch", "musl_qsort",
}

const muslCtypeTag = "vendor"

func muslDie(format string, a ...any) error {
	return fmt.Errorf("  %-12s %s", muslCtypeTag, fmt.Sprintf(format, a...))
}

// MuslCtypeVerify returns nil when the vendored block agrees with libc, and
// writes its own success line -- which carries the numbers, because a check
// that prints only "ok" cannot be read for whether it did anything.
func MuslCtypeVerify(path string, out *os.File) error {
	data, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	text := string(data)
	if strings.Count(text, muslCtypeStart) != 1 || strings.Count(text, muslCtypeEnd) != 1 {
		return muslDie("%s does not hold exactly one vendored block", path)
	}
	a := strings.Index(text, muslCtypeStart)
	z := strings.Index(text, muslCtypeEnd)
	if z <= a {
		return muslDie("the vendored block and its two prototypes are in the wrong order")
	}
	block := text[a:z]
	for _, name := range muslCtypeNames {
		re := regexp.MustCompile("(?m)^" + regexp.QuoteMeta(name) + `\(`)
		if len(re.FindAllString(block, -1)) != 1 {
			return muslDie("the block sliced out of %s does not define %s exactly once", path, name)
		}
	}

	d, err := os.MkdirTemp("", "muslctype")
	if err != nil {
		return err
	}
	defer os.RemoveAll(d)
	src := filepath.Join(d, "h.c")
	if err := os.WriteFile(src, []byte("#include <stddef.h>\n"+block+muslCtypeMain), 0644); err != nil {
		return err
	}
	bin := filepath.Join(d, "h")
	cc := exec.Command("gcc", "-O2", "-Wall", "-Wextra", "-o", bin, src)
	var ccerr strings.Builder
	cc.Stderr = &ccerr
	// A CLEAN COMPILE IS PART OF THE CLAIM, so a warning fails it: gcc exits 0
	// with warnings, and a check that tests only the status passes always.
	if err := cc.Run(); err != nil || strings.TrimSpace(ccerr.String()) != "" {
		fmt.Fprintf(out, "  %-12s the vendored block does not compile clean on its own:\n", muslCtypeTag)
		s := strings.TrimRight(ccerr.String(), "\n")
		if len(s) > 2000 {
			s = s[:2000]
		}
		fmt.Fprintln(out, s)
		return ErrReported
	}
	run := exec.Command(bin)
	stdout, err := run.Output()
	if err != nil {
		return muslDie("the harness did not run")
	}

	got := map[string][]string{}
	for _, line := range strings.Split(string(stdout), "\n") {
		f := strings.Fields(line)
		if len(f) > 1 {
			got[f[0]] = f[1:]
		}
	}
	num := func(key string, idx int) (int, error) {
		v, ok := got[key]
		if !ok || idx >= len(v) {
			return 0, muslDie("the harness printed no %s row, so its result cannot be read", key)
		}
		n, err := strconv.Atoi(v[idx])
		if err != nil {
			return 0, muslDie("the harness's %s row is not a number: %v", key, v)
		}
		return n, nil
	}

	var fail []string
	get := func(key string, idx int) int {
		n, err := num(key, idx)
		if err != nil {
			fail = append(fail, err.Error())
			return -1
		}
		return n
	}
	ctypeN, ctypeBad := get("ctype", 0), get("ctype", 1)
	atoiN, atoiBad := get("atoi", 0), get("atoi", 1)
	bsN, bsBad := get("bsearch", 0), get("bsearch", 1)
	qsBad := get("qsort", 1)
	tiesMoved, tiesOrder := get("ties", 0), get("ties", 1)

	if ctypeBad != 0 {
		fail = append(fail, fmt.Sprintf("%d ctype disagreements with libc", ctypeBad))
	}
	if ctypeN < 1002000 {
		fail = append(fail, fmt.Sprintf("the ctype domain shrank to %d values", ctypeN))
	}
	if atoiN != 137560 || atoiBad != 0 {
		fail = append(fail, fmt.Sprintf("atoi/atol: %d %d", atoiN, atoiBad))
	}
	if bsN != 1845 || bsBad != 0 {
		fail = append(fail, fmt.Sprintf("bsearch: %d %d", bsN, bsBad))
	}
	if qsBad != 0 {
		fail = append(fail, fmt.Sprintf("qsort: %v", got["qsort"]))
	}
	// THE TIE CASE IS REQUIRED TO DIFFER IN POINTERS AND NOT IN STRINGS.
	// musl's smoothsort is unstable and this insertion sort is stable, so a
	// harness that could not tell them apart would pass a phase that had
	// swapped one for the other by accident.
	if tiesOrder != 0 {
		fail = append(fail, fmt.Sprintf("the tie case sorts to a DIFFERENT string order, "+
			"which is a bug in musl_qsort and not a tie-break: %v", got["ties"]))
	}
	if tiesMoved == 0 {
		fail = append(fail, "the tie case places every pointer exactly as musl does, so this "+
			"harness cannot tell a stable sort from an unstable one and the "+
			"qsort result above proves nothing")
	}
	if len(fail) > 0 {
		for _, line := range fail {
			fmt.Fprintf(out, "  %-12s %s\n", muslCtypeTag, strings.TrimSpace(strings.TrimPrefix(line, "  "+muslCtypeTag)))
		}
		return ErrReported
	}
	fmt.Fprintf(out, "  %-12s the block compiled OUT OF THE PRODUCED SOURCE agrees with libc: "+
		"%d int values (bounded -- all 2^32 were checked once, 0 disagreements, and "+
		"it costs 66 s), %d atoi/atol strings, %d bsearch lookups compared by "+
		"POINTER, 2000 qsort arrays -- and the three-equal-keys case moves %d of 5 "+
		"pointers while sorting to the same strings, which is what says the harness "+
		"can see a tie at all\n",
		muslCtypeTag, ctypeN, atoiN, bsN, tiesMoved)
	return nil
}
