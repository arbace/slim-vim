// Proof that tools/nofloat.py's rounding rewrite is the same arithmetic.
//
// Usage: gcc -O0 -o /tmp/nolibm_check tools/nolibm_check.c && /tmp/nolibm_check
//
// This is not a test of whim-vim; it is a test of the CLAIM the phase makes,
// which is that a double-to-int conversion truncating toward zero is `ceil` for
// a negative value and `floor` for a positive one -- so biasing by half in the
// sign's own direction and converting is the same answer as calling both.
//
// IT IS ALSO WHY log10 IS REMOVED RATHER THAN TRANSLATED.  The first version of
// this file checked a digit-counting loop against `(size_t)log10(x)` and found
// 79 disagreements in a million: just below a power of ten, log10() returns a
// double that rounds up to the integer, so (size_t)log10(99.999999999999986)
// is 2 where counting digits gives 1.  A claim about rounding that is merely
// believed is how an off-by-one reaches a release -- and here it turned a
// translation into a removal, which is a better phase.
#include <math.h>
#include <stdio.h>

enum { SCORE_SCALE = 1000 };

static int old_round(double s)
{
    return (s < 0) ? (int)ceil(s * SCORE_SCALE - 0.5)
                   : (int)floor(s * SCORE_SCALE + 0.5);
}

static int new_round(double s)
{
    return (int)(s * SCORE_SCALE + ((s < 0) ? -0.5 : 0.5));
}

int main(void)
{
    long        n = 0;
    long        bad = 0;
    double      x;

    // The scorer's range, swept finely through zero in both signs.
    for (x = -50.0; x <= 50.0; x += 0.0001)
    {
        ++n;
        if (old_round(x) != new_round(x))
        {
            if (bad++ < 5)
            {
                printf("round differs at %.6f: %d vs %d\n",
                       x, old_round(x), new_round(x));
            }
        }
    }
    // And on the exact halves, which is the only place the two could disagree.
    for (x = -10.0; x <= 10.0; x += 0.0005)
    {
        ++n;
        if (old_round(x) != new_round(x))
        {
            if (bad++ < 5)
            {
                printf("round differs at %.6f: %d vs %d\n",
                       x, old_round(x), new_round(x));
            }
        }
    }

    printf("%ld values, %ld differ\n", n, bad);
    return bad != 0;
}
