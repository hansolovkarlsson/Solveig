/* `@expr(...)` -- infix arithmetic, and the claim that it is notation only.
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
        { "@expr( a + b )",        "a:add(b)"                       },
        { "@expr( a - b )",        "a:sub(b)"                       },
        { "@expr( a * b )",        "a:mul(b)"                       },
        { "@expr( a / b )",        "a:div(b)"                       },
        { "@expr( a^b )",          "a:pow(b)"                       },
        { "@expr( a + b * a )",    "a:add(b:mul(a))"                },
        { "@expr( (a + b) * a )",  "a:add(b):mul(a)"                },
        { "@expr( a + b + a )",    "a:add(b):add(a)"                },
        { "@expr( a - b - a )",    "a:sub(b):sub(a)"                },
        { "@expr( a^b^a )",        "a:pow(b:pow(a))"                },
        { "@expr( -a )",           "a:negated"                      },
        { "@expr( -a^b )",         "a:pow(b):negated"               },
        { "@expr( a + 3 * ((a/2):sin + b:sqrt) )",
          "a:add(3:mul(a:div(2):sin:add(b:sqrt)))"                  },

        /* Prefix application is a send to its argument, so it is the same
           bytes by construction and not merely by arithmetic. */
        { "@expr( sqrt(b) )",      "b:sqrt"                         },
        { "@expr( sin(a/2) )",     "a:div(2):sin"                   },
        { "@expr( sqrt(b):abs )",  "b:sqrt:abs"                     },
        { "@expr( -sqrt(b) )",     "b:sqrt:negated"                 },
        { "@expr( sqrt(b)^2 )",    "b:sqrt:pow(2)"                  },
        { "@expr( a^2 + 3 * (sin(a/2) + sqrt(b)) )",
          "a:pow(2):add(3:mul(a:div(2):sin:add(b:sqrt)))"           },

        /* Comparison: six ordinary one-argument sends. */
        { "@expr( a = b )",        "a:equals(b)"                    },
        { "@expr( a <> b )",       "a:notEquals(b)"                 },
        { "@expr( a < b )",        "a:lessThan(b)"                  },
        { "@expr( a > b )",        "a:greaterThan(b)"               },
        { "@expr( a <= b )",       "a:lessOrEqual(b)"               },
        { "@expr( a >= b )",       "a:greaterOrEqual(b)"            },
        { "@expr( a + 1 < b * 2 )","a:add(1):lessThan(b:mul(2))"    },

        /* `~` is looser than a comparison, so this is `~(a = b)`. */
        { "@expr( ~a = b )",       "a:equals(b):not"                },

        /* `&` and `|` take a block so that they can stop early, so their
           right-hand side is the only one not compiled where it stands -- it
           goes where the block's body would have gone, behind the jump. The
           bytes are still the send's bytes, short-circuiting included. */
        { "@expr( a < b & b < a )",
          "a:lessThan(b):and({ b:lessThan(a) })"                    },
        { "@expr( a < b | b < a )",
          "a:lessThan(b):or({ b:lessThan(a) })"                     },
        { "@expr( ~(a < b) & a = b )",
          "a:lessThan(b):not:and({ a:equals(b) })"                  },

        /* `@expr{...}` is the same region over a block, so the bytes are the
           ones `{ @expr(...) }` produces -- which is the same claim as every
           row above, one delimiter along. */
        { "@expr{ a + b }",        "{ a:add(b) }"                   },
        { "@expr{ a < b }",        "{ a:lessThan(b) }"              },
        { "@expr{ x | x * 2 }",    "{ x | x:mul(2) }"               },
        { "@expr{ a + b. a - b }", "{ a:add(b). a:sub(b) }"         },
        { "@expr{ }",              "{ }"                            },
        { "@expr{ a < b }:whileTrue(@expr{ a := a + 1 })",
          "{ a:lessThan(b) }:whileTrue({ a := a:add(1) })"          },

        /* The fold. `-3` inside a region is the constant `-3`, not `3` with a
           `negated` after it, so the region's minus is value-preserving to the
           byte rather than merely to the value. */
        { "@expr( -3 )",           "-3"                             },
        { "@expr( a + -3 )",       "a:add(-3)"                      },
        { "@expr( #0 - #3 )",      "#0:sub(#3)"                     },
        { "@expr( -#3 )",          "#-3"                            },
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
    expect_float("@expr( 1 + 2 * 3 )", 7.0);
    expect_float("@expr( (1 + 2) * 3 )", 9.0);
    expect_float("@expr( 1 + 2 * 3 + 4 )", 11.0);
    expect_float("@expr( 2 * 3 + 4 * 5 )", 26.0);

    /* Left-associative, so these are not the same number read either way. */
    expect_float("@expr( 10 - 3 - 2 )", 5.0);
    expect_float("@expr( 100 / 10 / 2 )", 5.0);

    /* `^` is right-associative and binds tighter than the unary minus above it,
       which are the two calls SolaBasic's ladder already made. */
    expect_float("@expr( 2^3^2 )", 512.0);
    expect_float("@expr( -2^2 )", -4.0);
    expect_float("@expr( 2^-2 )", 0.25);
    expect_float("@expr( 2 * 3^2 )", 18.0);
    expect_float("@expr( --3 )", 3.0);
}

/* A term is an ordinary Solum expression, which is what makes `sin(x)`
   unnecessary rather than merely absent. */
static void test_a_term_is_an_ordinary_expression(void)
{
    expect_float("@expr( b:sqrt * b:sqrt )", 9.0);
    expect_float("@expr( b:sqrt + 1 )", 4.0);
    expect_int("@expr( (a/5):floor + #1 )", 2);
    expect_int("@expr( #2:add(#3) * #2 )", 10);
    expect_float("@expr( [1.0, 2.0]:at(#2) + 1 )", 3.0);
}

/* The mode covers the whole region, nested constructs included -- an argument
   list, an array literal, a group and a block body all read as infix inside
   one. Without that, `-3` in an argument would be the one corner where the
   rules quietly changed back. */
static void test_the_region_reaches_into_nested_constructs(void)
{
    expect_float("@expr( [1.0, -3.0, 2.5]:inject(0.0, { t, e | t + e }) )", 0.5);
    expect_float("@expr( [1.0, -3.0]:at(#2) * -2 )", 6.0);
    expect_float("@expr( { p, q | p * q }:value(-3, 4) + 1 )", -11.0);
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
    expect_float("@expr( sqrt(b) )", 3.0);
    expect_float("@expr( sqrt(b) + 1 )", 4.0);
    expect_float("@expr( sqrt(b):abs )", 3.0);
    expect_float("@expr( sqrt(b)^2 )", 9.0);
    expect_float("@expr( -sqrt(b) )", -3.0);
    expect_int("@expr( floor(a/2) )", 2);

    /* The argument is a whole expression, so it needs no parentheses of its
       own -- which is the difference between `sin(a/2)` and `(a/2):sin` and the
       reason for the form. */
    expect_float("@expr( sqrt(b + 7) )", 4.0);

    /* It reaches any unary message, not a list of blessed ones. */
    expect_int("@expr( asInteger(\"12\") + #1 )", 13);

    /* Two arguments is refused rather than guessed at, and `float:atan2` is
       written out as the class-side send it is. */
    expect_compile_error("x := @expr( atan2(1.0, 2.0) ).");
    expect_compile_error("x := @expr( sqrt() ).");
    expect_float("@expr( float:atan2(0.0, 1.0) + 1 )", 1.0);

    /* The one thing to know: it is a send and not a block call, and it says so
       rather than quietly doing the other thing. */
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;
    assert(run(&vm, &chunk, "f := { x | x:mul(x) }. y := @expr( f(3) ).")
           == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);
    sol_vm_free(&vm);

    /* And outside a region there is no prefix form either. */
    expect_compile_error("b := 9.0. x := sqrt(b).");
}

/* Comparison, `~`, `&` and `|`.
 *
 * The two calls that had to be made are here rather than in prose: `~` is
 * looser than a comparison, so `~a = b` is `~(a = b)` -- the reading the words
 * have, and BASIC's and Pascal's, where C would have bound `!` tightest. And
 * comparison does not chain, so `a < b < c` is refused at compile time instead
 * of comparing a boolean to `c` at run time. */
static void test_comparison_and_logic(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
               "a := 5.0. b := 9.0. "
               "lt := @expr( a < b ). gt := @expr( a > b ). "
               "eq := @expr( a = 5.0 ). ne := @expr( a <> b ). "
               "le := @expr( a <= 5.0 ). ge := @expr( a >= b ). "
               "both := @expr( a < b & b < 10.0 ). "
               "either := @expr( a > b | b > 1.0 ). "
               "neg := @expr( ~a = b ). "
               "mixed := @expr( a + 1 < b & ~(a = b) ).") == SOL_OK);

    assert(SOL_AS_BOOL(global(&vm, "lt")) == true);
    assert(SOL_AS_BOOL(global(&vm, "gt")) == false);
    assert(SOL_AS_BOOL(global(&vm, "eq")) == true);
    assert(SOL_AS_BOOL(global(&vm, "ne")) == true);
    assert(SOL_AS_BOOL(global(&vm, "le")) == true);
    assert(SOL_AS_BOOL(global(&vm, "ge")) == false);
    assert(SOL_AS_BOOL(global(&vm, "both")) == true);
    assert(SOL_AS_BOOL(global(&vm, "either")) == true);
    assert(SOL_AS_BOOL(global(&vm, "neg")) == true);
    assert(SOL_AS_BOOL(global(&vm, "mixed")) == true);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);

    /* They stop early, which is the reason the block form exists and the reason
       these two are compiled behind a jump rather than beside their operator. */
    sol_vm_init(&vm);
    assert(run(&vm, &chunk,
               "ran := false. mark := { ran := true. true }. "
               "x := @expr( false & mark:value ). "
               "y := @expr( true | mark:value ).") == SOL_OK);
    assert(SOL_AS_BOOL(global(&vm, "ran")) == false);
    assert(SOL_AS_BOOL(global(&vm, "x")) == false);
    assert(SOL_AS_BOOL(global(&vm, "y")) == true);
    sol_chunk_free(&chunk);
    sol_vm_free(&vm);

    expect_compile_error("x := @expr( 1 < 2 < 3 ).");
    expect_compile_error("x := @expr( 1 = 2 = 3 ).");
}

/* `|` is the one operator the language already had a use for, and the rule is
 * that a block's parameters and a group's temporaries are consumed before a
 * body is -- so a `|` reaching the ladder is one standing where an operator may
 * stand. A block inside a region still takes its parameters, exactly as it does
 * outside one. */
static void test_the_pipe_still_opens_a_parameter_list(void)
{
    expect_float("@expr( [1.0, 2.0]:inject(0.0, { t, e | t + e }) )", 3.0);
    expect_float("@expr( { p, q | p * q }:value(2.0, 3.0) )", 6.0);

    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;
    assert(run(&vm, &chunk, "x := @expr( (true | false) & true ).") == SOL_OK);
    assert(SOL_AS_BOOL(global(&vm, "x")) == true);
    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* Two numeric types and no coercion between them, which the notation neither
   hides nor helps with: it is the same send, so it is the same refusal. */
static void test_the_strictness_shows_through(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk, "x := @expr( #1 + 1.0 ).") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);

    /* `pow` is float-only, so an integer raised to a power says what it always
       said rather than being quietly widened. */
    assert(run(&vm, &chunk, "x := @expr( #4^#2 ).") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);

    sol_vm_free(&vm);

    expect_int("@expr( #7 - #2 )", 5);
    expect_int("@expr( #2 + #3 * #4 )", 14);
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

    assert(run(&vm, &chunk, "x := @expr( 2 + 3 ). y := -4. z := x:add(y).") == SOL_OK);
    assert(SOL_IS_FLOAT(global(&vm, "y")) && SOL_AS_FLOAT(global(&vm, "y")) == -4.0);
    assert(SOL_AS_FLOAT(global(&vm, "z")) == 1.0);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);

    /* Saved and restored rather than assigned, so the inner one leaves the
       outer as it found it. */
    expect_float("@expr( @expr( 2 + 3 ) * 2 )", 10.0);

    /* And a block ends its region at the brace, so the `-4` that follows is a
       literal again. Without the hand-back every line after this one would be
       inside a region to the end of the file. */
    sol_vm_init(&vm);
    assert(run(&vm, &chunk, "f := @expr{ 2 + 3 }. y := -4. z := f:value:add(y).")
           == SOL_OK);
    assert(SOL_AS_FLOAT(global(&vm, "y")) == -4.0);
    assert(SOL_AS_FLOAT(global(&vm, "z")) == 1.0);
    sol_chunk_free(&chunk);
    sol_vm_free(&vm);

    /* An inner block region inside an outer paren region hands back *infix*,
       not the mode of the file: the `-` after it is still the operator. */
    expect_float("@expr( 10 - @expr{ 4 }:value )", 6.0);
}

/* ---- the region as a block -------------------------------------------- *
 *
 * `(a group)` runs now and `{a block}` is code held as a value, which the
 * language teaches on its own page. `@expr{...}` is that pair applied to the
 * region: a block whose body reads infix, answering the block rather than what
 * the block comes to.
 *
 * It says nothing `{ @expr(...) }` cannot say -- the bytes above are identical
 * -- and what it buys is the *width* of the region. Reaching a block by
 * wrapping the send that takes it puts the receiver and every other argument
 * inside a mode that changes what `-` means.
 */
static void test_a_region_may_be_a_block(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    /* The loop the notation was asked for: condition and body, one marker
       each, and no wrapping of the send that joins them. */
    assert(run(&vm, &chunk,
               "i := #0. total := #0."
               "@expr{ i < #5 }:whileTrue(@expr{ i := i + #1. total := total + i })."
              ) == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "total")) == 15);
    sol_chunk_free(&chunk);
    sol_vm_free(&vm);

    /* A block that is stored and called later, which is the case where the
       marker belongs to the block rather than to the statement around it. */
    expect_float("@expr{ x | x^2 + 1 }:value(3)", 10.0);

    /* Parameters and temporaries are matched before a body is, so a region
       changes neither -- the same rule that keeps `{ a | b }` a block taking
       `a` inside a region. */
    expect_float("@expr{ p, q | p * q }:value(-3, 4)", -12.0);
    expect_int("@expr{ | t | t := #2. t * #3 }:value", 6);

    /* An empty block answers nil in a region as anywhere else. */
    SolVM vm2; sol_vm_init(&vm2);
    SolChunk chunk2;
    assert(run(&vm2, &chunk2, "x := @expr{ }:value.") == SOL_OK);
    assert(SOL_IS_NIL(global(&vm2, "x")));
    sol_chunk_free(&chunk2);
    sol_vm_free(&vm2);
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
    /* `@expr` opens with one of two delimiters and nothing else. The message
       names both, because a reader who wrote neither is choosing between them
       rather than having forgotten the one. */
    expect_compile_error("x := @expr 1 + 2.");
    expect_compile_error("x := @expr[ 1, 2 ].");

    /* An operator outside a region. Three of these five characters were
       *unexpected character* before this existed. */
    expect_compile_error("a := 1. b := a + 2.");
    expect_compile_error("a := 1. b := a * 2.");
    expect_compile_error("a := 1. f := { p | p }. f:value(a / 2):print.");

    /* And `-`, which was a lexical error and stays one. */
    expect_compile_error("a := 1. b := a - 2.");

    /* An operator with nothing to its left; only `-` may open one. */
    expect_compile_error("x := @expr( * 2 ).");
    expect_compile_error("x := @expr( 1 + ).");

    /* The region is a pair of parentheses and says so. */
    expect_compile_error("x := @expr 1 + 2.");
    expect_compile_error("x := @expr( 1 + 2.");

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
               "x := @expr( 1 + 2 ):asString. "
               "y := [@expr( 1 + 1 ), #3]. "
               "z := { p | p }:value(@expr( 4 / 2 )).") == SOL_OK);

    SolValue x = global(&vm, "x");
    assert(SOL_IS_STRING(x));
    assert(SOL_AS_FLOAT(global(&vm, "z")) == 2.0);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);

    /* And a statement may open with one. */
    sol_vm_init(&vm);
    assert(run(&vm, &chunk, "@expr( 1 + 1 ):print.") == SOL_OK);
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
    test_comparison_and_logic();
    test_the_pipe_still_opens_a_parameter_list();
    test_the_strictness_shows_through();
    test_the_mode_ends_with_the_region();
    test_a_region_may_be_a_block();
    test_refusals();
    test_it_is_an_expression_everywhere_one_may_be();

    printf("test_expr: ok\n");
    return 0;
}
