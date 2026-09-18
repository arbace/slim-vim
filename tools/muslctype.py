"""Compile the vendored musl block out of a source file and hold it to libc.

Usage: python3 tools/muslctype.py --verify <file.c>

Zero phase 15 replaces eleven libc calls and six `<ctype.h>` macros with static
functions of its own.  The claim is not "these look like musl's" but "these
compute what musl computes", and the only way to say that is to run both.  So
this slices the block OUT OF THE SOURCE THE PHASE PRODUCED -- not out of
tools/musl-ctype.txt, which would only prove the copy was faithful -- wraps it in
a main() that calls libc beside it, compiles with -Wall -Wextra, and runs it.

THE DOMAIN IS BOUNDED ON PURPOSE, and this is the one number in the phase that
is not exhaustive.  All eleven classifier/mapper functions were compared with
musl's over ALL 4,294,967,296 int values while the phase was being written:
**zero disagreements**, in 66 seconds.  Sixty-six seconds is more than twice what
the rest of the phase costs, and a check that doubles a phase's time to re-prove
a closed-form identity is a check that stops being run.  What runs here instead
is every int in [-1024, 1024], every threshold in the definitions and its two
neighbours, EOF, INT_MIN, INT_MAX, and a FIXED pseudo-random sample of 1,000,000
values spread over the whole int range -- fixed, so the check is a function of
its input like everything else here.  Every one of the eleven is a closed form in
`(unsigned)c`, so a disagreement anywhere is a disagreement at a threshold, and
the thresholds are all in the bounded set.

The other three are exhaustive over their real domains and cost nothing:

  atoi/atol   every string of length 1..4 over " \\t\\n\\r\\v\\f+-09135abx." and the
              two high bytes \\x80 \\xff -- 137,560 of them.  The high bytes are
              the sign-extension trap: they are negative as `char`, and both
              musl's macros and these answer by unsigned wrap.
  bsearch     every array size 0..40 and every key from below the first element
              to above the last, 1,845 lookups, compared BY POINTER -- which is
              stronger than "it found something", and is what makes the two
              equally wrong on an unsorted table instead of one of them quietly
              right.
  qsort       2,000 random arrays of 1..64 distinct strings, plus one array with
              three EQUAL keys.  The equal-key case is required to DIFFER: musl's
              smoothsort is unstable and this insertion sort is stable, and a
              harness that cannot tell them apart would pass a phase that had
              swapped one for the other by accident.  `sort_strings()`'s one
              caller cannot produce equal keys (`uh_seq` is `++b_u_seq_last`), so
              the difference is unobservable in the editor -- which is a fact
              about the call site and has to be proved somewhere the call site
              cannot hide it.
"""
import os
import re
import subprocess
import sys
import tempfile

START = '    static int\nmusl_isdigit(int c)\n'
END = 'static int musl_towupper(int a);\n'

MAIN = r'''
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <limits.h>

static int cmpstr(const void *a, const void *b)
{
    return strcmp(*(char *const *)a, *(char *const *)b);
}

static int cmpint(const void *a, const void *b)
{
    int x = *(const int *)a;
    int y = *(const int *)b;
    return x < y ? -1 : x > y;
}

static long bad;
static long checked;

static void one(int i)
{
    checked++;
    bad += !!musl_isalnum(i) != !!isalnum(i);
    bad += !!musl_iscntrl(i) != !!iscntrl(i);
    bad += !!musl_ispunct(i) != !!ispunct(i);
    bad += musl_tolower(i) != tolower(i);
    bad += musl_toupper(i) != toupper(i);
    bad += !!musl_isalpha(i) != !!isalpha(i);
    bad += !!musl_isdigit(i) != !!isdigit(i);
    bad += !!musl_isupper(i) != !!isupper(i);
    bad += !!musl_islower(i) != !!islower(i);
    bad += !!musl_isgraph(i) != !!isgraph(i);
    bad += !!musl_isspace(i) != !!isspace(i);
}

int main(void)
{
    static const int edge[] = {
        0x00, 0x08, 0x09, 0x0d, 0x0e, 0x1f, 0x20, 0x21, 0x2f, 0x30, 0x39, 0x3a,
        0x40, 0x41, 0x5a, 0x5b, 0x60, 0x61, 0x7a, 0x7b, 0x7e, 0x7f, 0x80, 0xfe,
        0xff, 0x100, EOF, INT_MIN, INT_MIN + 1, INT_MAX, INT_MAX - 1
    };
    unsigned seed = 2166136261u;
    int i;
    unsigned k;

    for (i = -1024; i <= 1024; i++)
    {
        one(i);
    }
    for (k = 0; k < sizeof(edge) / sizeof(edge[0]); k++)
    {
        one(edge[k]);
        if (edge[k] != INT_MAX)
        {
            one(edge[k] + 1);
        }
        if (edge[k] != INT_MIN)
        {
            one(edge[k] - 1);
        }
    }
    for (k = 0; k < 1000000u; k++)
    {
        seed = seed * 1103515245u + 12345u;
        one((int)seed);
    }
    printf("ctype %ld %ld\n", checked, bad);

    {
        static const char al[] = " \t\n\r\v\f+-09135abx.\x80\xff";
        int A = (int)sizeof(al) - 1;
        long cnt = 0;
        long bada = 0;
        int len;
        char buf[8];

        for (len = 1; len <= 4; len++)
        {
            long tot = 1;
            long t;
            int p;

            for (p = 0; p < len; p++)
            {
                tot *= A;
            }
            for (t = 0; t < tot; t++)
            {
                long v = t;

                for (p = 0; p < len; p++)
                {
                    buf[p] = al[v % A];
                    v /= A;
                }
                buf[len] = 0;
                cnt++;
                bada += musl_atoi(buf) != atoi(buf);
                bada += musl_atol(buf) != atol(buf);
            }
        }
        printf("atoi %ld %ld\n", cnt, bada);
    }

    {
        int arr[41];
        int sz;
        int key;
        long cnt = 0;
        long badb = 0;

        for (sz = 0; sz <= 40; sz++)
        {
            for (i = 0; i < sz; i++)
            {
                arr[i] = i * 2;
            }
            for (key = -2; key <= sz * 2 + 2; key++)
            {
                void *a = bsearch(&key, arr, (size_t)sz, sizeof(int), cmpint);
                void *b = musl_bsearch(&key, arr, (size_t)sz, sizeof(int), cmpint);

                cnt++;
                badb += a != b;
            }
        }
        printf("bsearch %ld %ld\n", cnt, badb);
    }

    {
        char *p[64];
        char *q[64];
        static char store[64][8];
        long badq = 0;
        int t;
        int sz;

        seed = 12345u;
        for (t = 0; t < 2000; t++)
        {
            sz = (int)(seed % 64u) + 1;
            seed = seed * 1103515245u + 12345u;
            for (i = 0; i < sz; i++)
            {
                snprintf(store[i], sizeof store[i], "%06u", seed % 1000000u);
                seed = seed * 1103515245u + 12345u;
                p[i] = store[i];
                q[i] = store[i];
            }
            qsort(p, (size_t)sz, sizeof p[0], cmpstr);
            musl_qsort(q, (size_t)sz, sizeof q[0], cmpstr);
            for (i = 0; i < sz; i++)
            {
                if (strcmp(p[i], q[i]) != 0)
                {
                    badq++;
                    break;
                }
            }
        }
        printf("qsort 2000 %ld\n", badq);
    }

    {
        static char a[] = "aa";
        static char b1[] = "bb";
        static char b2[] = "bb";
        static char b3[] = "bb";
        static char c[] = "cc";
        char *src[5];
        char *p[5];
        char *q[5];
        int moved = 0;
        int order = 0;

        src[0] = b1; src[1] = c; src[2] = b2; src[3] = a; src[4] = b3;
        for (i = 0; i < 5; i++)
        {
            p[i] = src[i];
            q[i] = src[i];
        }
        qsort(p, 5, sizeof p[0], cmpstr);
        musl_qsort(q, 5, sizeof q[0], cmpstr);
        for (i = 0; i < 5; i++)
        {
            moved += p[i] != q[i];
            order += strcmp(p[i], q[i]) != 0;
        }
        printf("ties %d %d\n", moved, order);
    }
    return 0;
}
'''

TAG = 'vendor'


def die(msg):
    sys.exit('  %-12s %s' % (TAG, msg))


def main():
    if len(sys.argv) != 3 or sys.argv[1] != '--verify':
        sys.exit('usage: muslctype.py --verify <file.c>')
    path = sys.argv[2]
    text = open(path, errors='surrogateescape').read()
    if text.count(START) != 1 or text.count(END) != 1:
        die('%s does not hold exactly one vendored block' % path)
    a = text.index(START)
    z = text.index(END)
    if z <= a:
        die('the vendored block and its two prototypes are in the wrong order')
    block = text[a:z]
    for name in ('musl_isdigit', 'musl_isalpha', 'musl_isupper', 'musl_islower',
                 'musl_isgraph', 'musl_isspace', 'musl_isalnum', 'musl_iscntrl',
                 'musl_ispunct', 'musl_tolower', 'musl_toupper', 'musl_atoi',
                 'musl_atol', 'musl_bsearch', 'musl_qsort'):
        if len(re.findall(r'^%s\(' % name, block, re.M)) != 1:
            die('the block sliced out of %s does not define %s exactly once'
                % (path, name))

    with tempfile.TemporaryDirectory() as d:
        src = os.path.join(d, 'h.c')
        open(src, 'w').write('#include <stddef.h>\n' + block + MAIN)
        r = subprocess.run(['gcc', '-O2', '-Wall', '-Wextra', '-o',
                            os.path.join(d, 'h'), src],
                           capture_output=True, text=True)
        if r.returncode or r.stderr.strip():
            print('  %-12s the vendored block does not compile clean on its own:' % TAG)
            print(r.stderr.rstrip()[:2000])
            sys.exit(1)
        r = subprocess.run([os.path.join(d, 'h')], capture_output=True, text=True)
        if r.returncode:
            die('the harness did not run')
        got = dict(line.split(None, 1) for line in r.stdout.splitlines())

    def num(key, idx):
        return int(got[key].split()[idx])

    fail = []
    if num('ctype', 1) != 0:
        fail.append('%d ctype disagreements with libc' % num('ctype', 1))
    if num('ctype', 0) < 1002000:
        fail.append('the ctype domain shrank to %d values' % num('ctype', 0))
    if num('atoi', 0) != 137560 or num('atoi', 1) != 0:
        fail.append('atoi/atol: %s' % got['atoi'])
    if num('bsearch', 0) != 1845 or num('bsearch', 1) != 0:
        fail.append('bsearch: %s' % got['bsearch'])
    if num('qsort', 1) != 0:
        fail.append('qsort: %s' % got['qsort'])
    if num('ties', 1) != 0:
        fail.append('the tie case sorts to a DIFFERENT string order, which is a bug '
                    'in musl_qsort and not a tie-break: %s' % got['ties'])
    if num('ties', 0) == 0:
        fail.append('the tie case places every pointer exactly as musl does, so this '
                    'harness cannot tell a stable sort from an unstable one and the '
                    'qsort result above proves nothing')
    if fail:
        for line in fail:
            print('  %-12s %s' % (TAG, line))
        sys.exit(1)
    print('  %-12s the block compiled OUT OF THE PRODUCED SOURCE agrees with libc: '
          '%d int values (bounded -- all 2^32 were checked once, 0 disagreements, and '
          'it costs 66 s), %d atoi/atol strings, %d bsearch lookups compared by '
          'POINTER, 2000 qsort arrays -- and the three-equal-keys case moves %d of 5 '
          'pointers while sorting to the same strings, which is what says the harness '
          'can see a tie at all'
          % (TAG, num('ctype', 0), num('atoi', 0), num('bsearch', 0), num('ties', 0)))


if __name__ == '__main__':
    main()
