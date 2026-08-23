/* The format spec: the optional argument to asString. */
#include <assert.h>
#include <stdio.h>
#include <string.h>

#include "solas/compiler.h"
#include "solum/vm.h"

static SolResult run(SolVM *vm, SolChunk *chunk, const char *source)
{
    sol_chunk_init(chunk);
    if (!sol_compile(source, chunk)) return SOL_COMPILE_ERROR;
    return sol_vm_run(vm, chunk);
}

static SolValue global(SolVM *vm, const char *name)
{
    SolSlot *slot = sol_object_lookup(vm->root, name);
    return slot ? slot->value : SOL_NIL_VAL;
}

static bool is_text(SolValue value, const char *expected)
{
    if (!SOL_IS_STRING(value)) return false;
    const SolString *s = SOL_AS_STRING(value);
    return s->length == (int)strlen(expected) &&
           memcmp(s->chars, expected, (size_t)s->length) == 0;
}

/* Width and decimals, and the case that motivated the whole thing: a leading
   space for a positive number falls out of the width, so no sign mode is
   needed. */
static void test_width_and_decimals(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "a := 45.8:asString(\"6.2\")."
        "b := 45.8:asString(\".2\")."
        "c := 45.8:asString(\"8\")."
        "d := #45:asString(\"6\")."
        "e := 2.5:asString(\".4\")."
        "f := 1.0:div(3.0):asString(\".3\").") == SOL_OK);
    assert(is_text(global(&vm, "a"), " 45.80"));
    assert(is_text(global(&vm, "b"), "45.80"));
    assert(is_text(global(&vm, "c"), "    45.8"));
    assert(is_text(global(&vm, "d"), "    45"));
    assert(is_text(global(&vm, "e"), "2.5000"));
    assert(is_text(global(&vm, "f"), "0.333"));

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* Numbers align right and text aligns left by default; either can be overridden. */
static void test_alignment(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "a := #45:asString(\"6\")."          /* right by default */
        "b := \"ab\":asString(\"6\")."       /* left by default */
        "c := #45:asString(\"<6\")."
        "d := \"ab\":asString(\">6\")."
        "e := \"ab\":asString(\"^6\")."
        "f := #45:asString(\"^7\")."
        "g := true:asString(\"7\")."
        "h := nil:asString(\"5\").") == SOL_OK);
    assert(is_text(global(&vm, "a"), "    45"));
    assert(is_text(global(&vm, "b"), "ab    "));
    assert(is_text(global(&vm, "c"), "45    "));
    assert(is_text(global(&vm, "d"), "    ab"));
    assert(is_text(global(&vm, "e"), "  ab  "));
    assert(is_text(global(&vm, "f"), "  45   "));   /* odd padding leans left */
    assert(is_text(global(&vm, "g"), "true   "));
    assert(is_text(global(&vm, "h"), "nil  "));

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* Zero fill goes after the sign, or -45 in width 6 would read 000-45. */
static void test_zero_fill(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "a := 45.8:asString(\"08.2\")."
        "b := -45.8:asString(\"08.2\")."
        "c := #45:asString(\"06\")."
        "d := #-45:asString(\"06\")."
        "e := 45.8:asString(\">08.2\").") == SOL_OK);
    assert(is_text(global(&vm, "a"), "00045.80"));
    assert(is_text(global(&vm, "b"), "-0045.80"));   /* sign first, then zeros */
    assert(is_text(global(&vm, "c"), "000045"));
    assert(is_text(global(&vm, "d"), "-00045"));
    assert(is_text(global(&vm, "e"), "00045.80"));

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* A value wider than the width is never cut: losing digits would be worse than
   a ragged column. */
static void test_width_never_truncates(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "a := #123456:asString(\"3\")."
        "b := \"abcdef\":asString(\"2\")."
        "c := 1.23456:asString(\"2.4\").") == SOL_OK);
    assert(is_text(global(&vm, "a"), "123456"));
    assert(is_text(global(&vm, "b"), "abcdef"));
    assert(is_text(global(&vm, "c"), "1.2346"));

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* Decimals belong to floats; asking anything else for them is a mistake. */
static void test_strictness(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    const char *bad[] = {
        "#45:asString(\".2\").",
        "\"ab\":asString(\".2\").",
        "true:asString(\".1\").",
        "nil:asString(\".1\").",
        "[#1]:asString(\".1\").",
        "45.8:asString(\"<08.2\").",     /* zero fill must align right */
        "45.8:asString(\"^08\").",
        "45.8:asString(\"x\").",
        "45.8:asString(\"6.\").",
        "45.8:asString(\"6x\").",
        "45.8:asString(#6).",
        "45.8:asString(\"99999\").",     /* width cap */
        "45.8:asString(\"6\", \"7\").",
    };
    for (size_t i = 0; i < sizeof bad / sizeof bad[0]; i++) {
        assert(run(&vm, &chunk, bad[i]) == SOL_RUNTIME_ERROR);
        sol_chunk_free(&chunk);
    }

    sol_vm_free(&vm);
}

/* No argument means what it always meant, so display, fill, and array rendering
   are untouched. */
static void test_no_spec_is_unchanged(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "a := #45:asString."
        "b := 1.0:div(3.0):asString."
        "c := \"hi\":asString."
        "d := [#1, 2.5]:asString."
        "e := \"you have {} apples\":fill([#3]).") == SOL_OK);
    assert(is_text(global(&vm, "a"), "45"));
    assert(is_text(global(&vm, "b"), "0.3333333333333333"));
    assert(is_text(global(&vm, "c"), "hi"));
    assert(is_text(global(&vm, "d"), "[#1, 2.5]"));
    assert(is_text(global(&vm, "e"), "you have 3 apples"));

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* Infinity and not-a-number keep their names: rounding them to two places means
   nothing, but padding a column of them still should. */
static void test_non_finite_with_a_spec(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "a := infinity:asString(\".2\")."
        "b := nan:asString(\"6\")."
        "c := infinity:asString(\"10\").") == SOL_OK);
    assert(is_text(global(&vm, "a"), "infinity"));
    assert(is_text(global(&vm, "b"), "   nan"));
    assert(is_text(global(&vm, "c"), "  infinity"));

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* The point of it: columns that line up. */
static void test_a_table(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "row := { n, v | \"{}{}\":fill([n:asString(\"<8\"), v:asString(\"8.2\")]) }."
        "a := row:value(\"apples\", 3.5)."
        "b := row:value(\"pears\", 12.25).") == SOL_OK);
    assert(is_text(global(&vm, "a"), "apples      3.50"));
    assert(is_text(global(&vm, "b"), "pears      12.25"));

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* `,` groups whole-number digits in threes. Only the digits: a sign, a
   fraction, and an exponent all pass through untouched. */
static void test_grouping(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "a := #1234567:asString(\",\")."
        "b := #-1234567:asString(\",\")."
        "c := #123:asString(\",\")."
        "d := #1000:asString(\",\")."
        "e := #0:asString(\",\")."
        "f := 1234567.891:asString(\",.2\")."
        "g := 1234.5:asString(\",10.2\")."
        "h := #1234:asString(\"<,8\")."
        "i := #1234:asString(\">,8\").") == SOL_OK);
    assert(is_text(global(&vm, "a"), "1,234,567"));
    assert(is_text(global(&vm, "b"), "-1,234,567"));   /* sign, then the digits */
    assert(is_text(global(&vm, "c"), "123"));
    assert(is_text(global(&vm, "d"), "1,000"));
    assert(is_text(global(&vm, "e"), "0"));
    assert(is_text(global(&vm, "f"), "1,234,567.89")); /* the fraction is not grouped */
    assert(is_text(global(&vm, "g"), "  1,234.50"));   /* grouped, then padded */
    assert(is_text(global(&vm, "h"), "1,234   "));
    assert(is_text(global(&vm, "i"), "   1,234"));
    sol_chunk_free(&chunk);

    /* Text that is not a run of digits passes through. */
    assert(run(&vm, &chunk,
        "a := 1e20:asString(\",\")."
        "b := infinity:asString(\",\")."
        "c := nan:asString(\",\").") == SOL_OK);
    assert(is_text(global(&vm, "a"), "1e+20"));
    assert(is_text(global(&vm, "b"), "infinity"));
    assert(is_text(global(&vm, "c"), "nan"));
    sol_chunk_free(&chunk);

    sol_vm_free(&vm);
}

/* Grouping belongs to numbers, and cannot be combined with zero fill: the
   leading zeros would not themselves be grouped, which reads as a mistake. */
static void test_grouping_is_refused_where_it_means_nothing(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    const char *bad[] = {
        "\"ab\":asString(\",\").",
        "true:asString(\",\").",
        "nil:asString(\",\").",
        "[#1]:asString(\",\").",
        "object:new:asString(\",\").",
        "1234.5:asString(\",08.2\").",   /* grouped and zero-filled */
        "1234.5:asString(\"0,8.2\").",   /* flags out of order */
    };
    for (size_t i = 0; i < sizeof bad / sizeof bad[0]; i++) {
        assert(run(&vm, &chunk, bad[i]) == SOL_RUNTIME_ERROR);
        sol_chunk_free(&chunk);
    }

    sol_vm_free(&vm);
}

/* A number too long for the buffer it is written into.
 *
 * `snprintf` does not overflow -- it truncates, and answers the length it
 * *would* have written. That length was handed on as the length of the text, so
 * a float needing more than 64 characters produced a string whose tail was the
 * stack behind the buffer. `1e150:asString("0.6")` is 157 characters, of which
 * 93 came from nowhere; a script could print them.
 *
 * Found by programs/bench.sol, which needed a square root the language does not
 * have, wrote one, and tested it at 1e300.
 *
 * What is checked here is the whole text, digit for digit, against what the C
 * library writes -- a length alone would have passed while the bug was live,
 * the length having been right all along. */
static void test_a_float_longer_than_its_buffer(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    const double values[] = { 1e150, 1e300, 1.7976931348623157e308, -1e200, 1e39 };
    for (size_t i = 0; i < sizeof values / sizeof values[0]; i++) {
        char source[128], expected[512];
        snprintf(source, sizeof source, "text := %.17g:asString(\"0.6\").", values[i]);
        snprintf(expected, sizeof expected, "%.6f", values[i]);

        assert(run(&vm, &chunk, source) == SOL_OK);
        assert(is_text(global(&vm, "text"), expected));
        sol_chunk_free(&chunk);
    }

    /* And the widest thing the spec can ask for: 40 decimals on the largest
       double there is, which is 350 characters. */
    char expected[512];
    snprintf(expected, sizeof expected, "%.40f", 1.7976931348623157e308);
    assert(run(&vm, &chunk,
        "widest := 1.7976931348623157e308:asString(\".40\").") == SOL_OK);
    assert(is_text(global(&vm, "widest"), expected));
    assert(strlen(expected) == 350);       /* 309 digits, a point, 40 decimals */
    sol_chunk_free(&chunk);

    sol_vm_free(&vm);
}

int main(void)
{
    test_grouping();
    test_a_float_longer_than_its_buffer();
    test_grouping_is_refused_where_it_means_nothing();
    test_width_and_decimals();
    test_alignment();
    test_zero_fill();
    test_width_never_truncates();
    test_strictness();
    test_no_spec_is_unchanged();
    test_non_finite_with_a_spec();
    test_a_table();
    printf("test_format: ok\n");
    return 0;
}
