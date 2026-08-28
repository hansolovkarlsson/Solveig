/* `@math(...)` -- infix arithmetic, and the claim that it is notation only.
 *
 * The language has no operators, and the grammar offers that as the point of it
 * rather than a fact about the file. What this region adds is a *spelling*: `+`
 * lowers to `add`, `^` to `pow`, and the bytes are the bytes the send chain
 * would have produced. That is the rule `[#1, #2]` already lives under -- two
 * spellings of the same thing mean the same thing -- and it is checkable to the
 * byte, which is most of what this file does.
 *
 * The rest is the precedence, which is the whole reason the notation is wanted:
 * a send chain reads left to right and arithmetic does not.
 */
#define _POSIX_C_SOURCE 200809L

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "solas/compiler.h"
#include "solum/bytecode.h"
#include "solum/vm.h"

static SolResult run(SolVM *vm, SolChunk *chunk, const char *source)
{
    sol_chunk_init(chunk);
    if (!sol_compile(source, chunk)) return SOL_COMPILE_ERROR;
    return sol_vm_run(vm, chunk);
}

static void expect_compile_error(const char *source);

static SolValue global(SolVM *vm, const char *name)
{
    SolSlot *slot = sol_object_lookup(vm->root, name);
    return slot ? slot->value : SOL_NIL_VAL;
}

/* Binds `x` to the expression and answers it. */
static SolValue value_of(SolVM *vm, SolChunk *chunk, const char *expression)
{
    char source[512];
    snprintf(source, sizeof(source), "a := 5.0. b := 9.0. x := %s.", expression);
    assert(run(vm, chunk, source) == SOL_OK);
    return global(vm, "x");
}

static void expect_float(const char *expression, double want)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;
    SolValue got = value_of(&vm, &chunk, expression);

    if (!SOL_IS_FLOAT(got) || SOL_AS_FLOAT(got) != want) {
        fprintf(stderr, "%s answered %s%g, expected the float %g\n", expression,
                SOL_IS_FLOAT(got) ? "the float " : "something that is not a float: ",
                SOL_IS_FLOAT(got) ? SOL_AS_FLOAT(got) : 0.0, want);
        assert(false);
    }
    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

static void expect_int(const char *expression, int64_t want)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;
    SolValue got = value_of(&vm, &chunk, expression);

    if (!SOL_IS_INT(got) || SOL_AS_INT(got) != want) {
        fprintf(stderr, "%s answered %s%lld, expected the integer %lld\n", expression,
                SOL_IS_INT(got) ? "the integer " : "something that is not an integer: ",
                (long long)(SOL_IS_INT(got) ? SOL_AS_INT(got) : 0), (long long)want);
        assert(false);
    }
    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* ---- the claim: notation, never a second semantics -------------------- */

/* The two spellings must reach the same bytes, not merely the same answer.
 * An answer test would pass on an implementation that computed the right number
 * by a different route -- through a helper, or with an extra conversion -- and
 * the whole case for the notation is that there is no different route. */
static void test_the_bytes_are_the_chain_s_bytes(void)
{
    static const struct { const char *infix; const char *chain; } pairs[] = {
        { "@math( a + b )",        "a:add(b)"                       },
        { "@math( a - b )",        "a:sub(b)"                       },
        { "@math( a * b )",        "a:mul(b)"                       },
        { "@math( a / b )",        "a:div(b)"                       },
        { "@math( a^b )",          "a:pow(b)"                       },
        { "@math( a + b * a )",    "a:add(b:mul(a))"                },
        { "@math( (a + b) * a )",  "a:add(b):mul(a)"                },
        { "@math( a + b + a )",    "a:add(b):add(a)"                },
        { "@math( a - b - a )",    "a:sub(b):sub(a)"                },
        { "@math( a^b^a )",        "a:pow(b:pow(a))"                },
        { "@math( -a )",           "a:negated"                      },
        { "@math( -a^b )",         "a:pow(b):negated"               },
        { "@math( a + 3 * ((a/2):sin + b:sqrt) )",
          "a:add(3:mul(a:div(2):sin:add(b:sqrt)))"                  },

        /* Prefix application is a send to its argument, so it is the same
           bytes by construction and not merely by arithmetic. */
        { "@math( sqrt(b) )",      "b:sqrt"                         },
        { "@math( sin(a/2) )",     "a:div(2):sin"                   },
        { "@math( sqrt(b):abs )",  "b:sqrt:abs"                     },
        { "@math( -sqrt(b) )",     "b:sqrt:negated"                 },
        { "@math( sqrt(b)^2 )",    "b:sqrt:pow(2)"                  },
        { "@math( a^2 + 3 * (sin(a/2) + sqrt(b)) )",
          "a:pow(2):add(3:mul(a:div(2):sin:add(b:sqrt)))"           },

        /* The fold. `-3` inside a region is the constant `-3`, not `3` with a
           `negated` after it, so the region's minus is value-preserving to the
           byte rather than merely to the value. */
        { "@math( -3 )",           "-3"                             },
        { "@math( a + -3 )",       "a:add(-3)"                      },
        { "@math( #0 - #3 )",      "#0:sub(#3)"                     },
        { "@math( -#3 )",          "#-3"                            },
    };

    for (size_t i = 0; i < sizeof(pairs) / sizeof(pairs[0]); i++) {
        char one[512], two[512];
        SolChunk left, right;

        snprintf(one, sizeof(one), "a := 5.0. b := 9.0. x := %s.", pairs[i].infix);
        snprintf(two, sizeof(two), "a := 5.0. b := 9.0. x := %s.", pairs[i].chain);

        sol_chunk_init(&left);
        sol_chunk_init(&right);
        assert(sol_compile(one, &left));
        assert(sol_compile(two, &right));

        if (left.count != right.count ||
            memcmp(left.code, right.code, (size_t)left.count) != 0) {
            fprintf(stderr, "%s and %s compile differently (%d bytes vs %d)\n",
                    pairs[i].infix, pairs[i].chain, left.count, right.count);
            assert(false);
        }

        sol_chunk_free(&left);
        sol_chunk_free(&right);
    }
}

/* ---- precedence, which is the reason for any of it -------------------- */

static void test_precedence(void)
{
    expect_float("@math( 1 + 2 * 3 )", 7.0);
    expect_float("@math( (1 + 2) * 3 )", 9.0);
    expect_float("@math( 1 + 2 * 3 + 4 )", 11.0);
    expect_float("@math( 2 * 3 + 4 * 5 )", 26.0);

    /* Left-associative, so these are not the same number read either way. */
    expect_float("@math( 10 - 3 - 2 )", 5.0);
    expect_float("@math( 100 / 10 / 2 )", 5.0);

    /* `^` is right-associative and binds tighter than the unary minus above it,
       which are the two calls SolaBasic's ladder already made. */
    expect_float("@math( 2^3^2 )", 512.0);
    expect_float("@math( -2^2 )", -4.0);
    expect_float("@math( 2^-2 )", 0.25);
    expect_float("@math( 2 * 3^2 )", 18.0);
    expect_float("@math( --3 )", 3.0);
}

/* A term is an ordinary Solum expression, which is what makes `sin(x)`
   unnecessary rather than merely absent. */
static void test_a_term_is_an_ordinary_expression(void)
{
    expect_float("@math( b:sqrt * b:sqrt )", 9.0);
    expect_float("@math( b:sqrt + 1 )", 4.0);
    expect_int("@math( (a/5):floor + #1 )", 2);
    expect_int("@math( #2:add(#3) * #2 )", 10);
    expect_float("@math( [1.0, 2.0]:at(#2) + 1 )", 3.0);
}

/* The mode covers the whole region, nested constructs included -- an argument
   list, an array literal, a group and a block body all read as infix inside
   one. Without that, `-3` in an argument would be the one corner where the
   rules quietly changed back. */
static void test_the_region_reaches_into_nested_constructs(void)
{
    expect_float("@math( [1.0, -3.0, 2.5]:inject(0.0, { t, e | t + e }) )", 0.5);
    expect_float("@math( [1.0, -3.0]:at(#2) * -2 )", 6.0);
    expect_float("@math( { p, q | p * q }:value(-3, 4) + 1 )", -11.0);
}

/* `sin(x)` is `x:sin`, and one argument exactly.
 *
 * The rule has no exceptions because it has no two-argument form to have them
 * in: `float:atan2` is class-side, so `atan2(y, x)` could never have meant
 * `y:atan2(x)`, and `pow` already has `^`. Both are still written out, as terms
 * like any other.
 *
 * And the name is an ordinary identifier rather than a blessed list, which is
 * what keeps `sin` and `cos` usable as names. The grammar's reserved-word count
 * stays at nought, which `test_cli` asserts by reading check_syntax's report. */
static void test_prefix_application(void)
{
    expect_float("@math( sqrt(b) )", 3.0);
    expect_float("@math( sqrt(b) + 1 )", 4.0);
    expect_float("@math( sqrt(b):abs )", 3.0);
    expect_float("@math( sqrt(b)^2 )", 9.0);
    expect_float("@math( -sqrt(b) )", -3.0);
    expect_int("@math( floor(a/2) )", 2);

    /* The argument is a whole expression, so it needs no parentheses of its
       own -- which is the difference between `sin(a/2)` and `(a/2):sin` and the
       reason for the form. */
    expect_float("@math( sqrt(b + 7) )", 4.0);

    /* It reaches any unary message, not a list of blessed ones. */
    expect_int("@math( asInteger(\"12\") + #1 )", 13);

    /* Two arguments is refused rather than guessed at, and `float:atan2` is
       written out as the class-side send it is. */
    expect_compile_error("x := @math( atan2(1.0, 2.0) ).");
    expect_compile_error("x := @math( sqrt() ).");
    expect_float("@math( float:atan2(0.0, 1.0) + 1 )", 1.0);

    /* The one thing to know: it is a send and not a block call, and it says so
       rather than quietly doing the other thing. */
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;
    assert(run(&vm, &chunk, "f := { x | x:mul(x) }. y := @math( f(3) ).")
           == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);
    sol_vm_free(&vm);

    /* And outside a region there is no prefix form either. */
    expect_compile_error("b := 9.0. x := sqrt(b).");
}

/* Two numeric types and no coercion between them, which the notation neither
   hides nor helps with: it is the same send, so it is the same refusal. */
static void test_the_strictness_shows_through(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk, "x := @math( #1 + 1.0 ).") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);

    /* `pow` is float-only, so an integer raised to a power says what it always
       said rather than being quietly widened. */
    assert(run(&vm, &chunk, "x := @math( #4^#2 ).") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);

    sol_vm_free(&vm);

    expect_int("@math( #7 - #2 )", 5);
    expect_int("@math( #2 + #3 * #4 )", 14);
}

/* The lexer's mode is set before the '(' is consumed and cleared before the ')'
 * is, so the tokens on either side belong to where they actually are. The way
 * to see that it was cleared is a negative literal after a region: outside one
 * that is a number, and if the mode leaked it would be a subtraction with
 * nothing to its left. */
static void test_the_mode_ends_with_the_region(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk, "x := @math( 2 + 3 ). y := -4. z := x:add(y).") == SOL_OK);
    assert(SOL_IS_FLOAT(global(&vm, "y")) && SOL_AS_FLOAT(global(&vm, "y")) == -4.0);
    assert(SOL_AS_FLOAT(global(&vm, "z")) == 1.0);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);

    /* Saved and restored rather than assigned, so the inner one leaves the
       outer as it found it. */
    expect_float("@math( @math( 2 + 3 ) * 2 )", 10.0);
}

/* ---- what it refuses -------------------------------------------------- */

static void expect_compile_error(const char *source)
{
    SolChunk chunk;
    sol_chunk_init(&chunk);
    if (sol_compile(source, &chunk)) {
        fprintf(stderr, "compiled and should not have: %s\n", source);
        assert(false);
    }
    sol_chunk_free(&chunk);
}

static void test_refusals(void)
{
    /* An operator outside a region. Three of these five characters were
       *unexpected character* before this existed. */
    expect_compile_error("a := 1. b := a + 2.");
    expect_compile_error("a := 1. b := a * 2.");
    expect_compile_error("a := 1. f := { p | p }. f:value(a / 2):print.");

    /* And `-`, which was a lexical error and stays one. */
    expect_compile_error("a := 1. b := a - 2.");

    /* An operator with nothing to its left; only `-` may open one. */
    expect_compile_error("x := @math( * 2 ).");
    expect_compile_error("x := @math( 1 + ).");

    /* The region is a pair of parentheses and says so. */
    expect_compile_error("x := @math 1 + 2.");
    expect_compile_error("x := @math( 1 + 2.");

    /* Every other directive is still a statement and still says so. */
    expect_compile_error("x := @include \"lib.sol\".");
    expect_compile_error("@frobnicate \"x\".");
}

/* It answers a value, so it may stand as a statement, be a receiver, and be an
   argument -- which is the whole of what "the first directive that is an
   expression" buys. */
static void test_it_is_an_expression_everywhere_one_may_be(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
               "x := @math( 1 + 2 ):asString. "
               "y := [@math( 1 + 1 ), #3]. "
               "z := { p | p }:value(@math( 4 / 2 )).") == SOL_OK);

    SolValue x = global(&vm, "x");
    assert(SOL_IS_STRING(x));
    assert(SOL_AS_FLOAT(global(&vm, "z")) == 2.0);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);

    /* And a statement may open with one. */
    sol_vm_init(&vm);
    assert(run(&vm, &chunk, "@math( 1 + 1 ):print.") == SOL_OK);
    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

int main(void)
{
    test_the_bytes_are_the_chain_s_bytes();
    test_precedence();
    test_a_term_is_an_ordinary_expression();
    test_the_region_reaches_into_nested_constructs();
    test_prefix_application();
    test_the_strictness_shows_through();
    test_the_mode_ends_with_the_region();
    test_refusals();
    test_it_is_an_expression_everywhere_one_may_be();

    printf("test_math: ok\n");
    return 0;
}
