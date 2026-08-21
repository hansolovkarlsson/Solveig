/* Conversions between the value types, and back from text. */
#include <assert.h>
#include <math.h>
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

/* `asString` answers plain text; `print` shows the literal form. They are
   different jobs, and the difference is the point. */
static void test_as_string_is_plain_text(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk, again;

    assert(run(&vm, &chunk,
        "i := #45:asString. f := 2.5:asString."
        "t := true:asString. n := nil:asString. s := \"hi\":asString."
        "neg := #-3:asString.") == SOL_OK);
    assert(is_text(global(&vm, "i"), "45"));      /* not "#45" */
    assert(is_text(global(&vm, "f"), "2.5"));
    assert(is_text(global(&vm, "t"), "true"));
    assert(is_text(global(&vm, "n"), "nil"));
    assert(is_text(global(&vm, "s"), "hi"));
    assert(is_text(global(&vm, "neg"), "-3"));

    /* The motivating case: building text around a number. */
    assert(run(&vm, &again,
        "msg := \"you have \":concat(#45:asString):concat(\" apples\").") == SOL_OK);
    assert(is_text(global(&vm, "msg"), "you have 45 apples"));

    sol_chunk_free(&chunk);
    sol_chunk_free(&again);
    sol_vm_free(&vm);
}

/* Widening, and with it the fractional answer that floored division cannot give. */
static void test_as_float(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "a := #45:asFloat."
        "q := #7:asFloat:div(#2:asFloat)."
        "whole := #7:div(#2).") == SOL_OK);
    assert(SOL_AS_FLOAT(global(&vm, "a")) == 45.0);
    assert(SOL_AS_FLOAT(global(&vm, "q")) == 3.5);
    assert(SOL_AS_INT(global(&vm, "whole")) == 3);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* Narrowing makes the caller say which way, so there is no ambiguous default. */
static void test_narrowing_names_its_direction(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "p := [2.7:floor, 2.7:ceiling, 2.7:rounded, 2.7:truncated]."
        "n := [-2.7:floor, -2.7:ceiling, -2.7:rounded, -2.7:truncated]."
        "h := [2.5:rounded, -2.5:rounded]."
        "e := [3.0:floor, 3.0:ceiling].") == SOL_OK);

    const int expect_p[] = {2, 3, 3, 2};
    const int expect_n[] = {-3, -2, -3, -2};
    const int expect_h[] = {3, -3};              /* half away from zero */
    const int expect_e[] = {3, 3};
    const char *names[] = {"p", "n", "h", "e"};
    const int *expected[] = {expect_p, expect_n, expect_h, expect_e};
    const int counts[] = {4, 4, 2, 2};

    for (int g = 0; g < 4; g++) {
        SolValue v = global(&vm, names[g]);
        assert(SOL_IS_ARRAY(v));
        assert(SOL_AS_ARRAY(v)->count == counts[g]);
        for (int i = 0; i < counts[g]; i++) {
            assert(SOL_AS_INT(SOL_AS_ARRAY(v)->items[i]) == expected[g][i]);
        }
    }

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* Most floats have no integer counterpart, so narrowing can fail. */
static void test_narrowing_guards(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk, "1.0:div(0.0):floor.") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);
    assert(run(&vm, &chunk, "-1.0:div(0.0):truncated.") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);
    assert(run(&vm, &chunk,
        "nan := 1.0:div(0.0):sub(1.0:div(0.0)). nan:rounded.") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);

    /* Beyond the integer range, reached without exponent notation. */
    assert(run(&vm, &chunk,
        "big := 100000000.0. i := #0."
        "{ i:lessThan(#3) }:whileTrue({ i := i:add(#1). big := big:mul(big). })."
        "big:truncated.") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);

    sol_vm_free(&vm);
}

/* Parsing is strict at both ends: the whole string, and nothing else. */
static void test_parsing_is_strict(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "a := \"45\":asInteger. b := \"-3\":asInteger. c := \"2.5\":asFloat.") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "a")) == 45);
    assert(SOL_AS_INT(global(&vm, "b")) == -3);
    assert(SOL_AS_FLOAT(global(&vm, "c")) == 2.5);
    sol_chunk_free(&chunk);

    const char *bad[] = {
        "\"12abc\":asInteger.",
        "\"\":asInteger.",
        "\" 45\":asInteger.",        /* leading space, which strtoll would skip */
        "\"45 \":asInteger.",
        "\"99999999999999999999\":asInteger.",
        "\"hello\":asFloat.",
        "\" 2.5\":asFloat.",
        "\"\":asFloat.",
    };
    for (size_t i = 0; i < sizeof bad / sizeof bad[0]; i++) {
        assert(run(&vm, &chunk, bad[i]) == SOL_RUNTIME_ERROR);
        sol_chunk_free(&chunk);
    }

    /* Round trip. */
    assert(run(&vm, &chunk,
        "r := #45:asString:asInteger. s := 2.5:asString:asFloat.") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "r")) == 45);
    assert(SOL_AS_FLOAT(global(&vm, "s")) == 2.5);
    sol_chunk_free(&chunk);

    sol_vm_free(&vm);
}

/* Printing must not lose the value. %g alone gives six significant digits,
   which made 1234567.0 print as 1.23457e+06 -- a different number, and asString
   baked it into a string. */
static void test_printing_keeps_the_value(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "a := 1234567.0:asString."
        "b := 1.0:div(3.0):asString."
        "c := 0.1:asString."
        "d := 1e3:asString."
        "e := 100.0:asString."
        "f := 0.0:asString.") == SOL_OK);
    assert(is_text(global(&vm, "a"), "1234567"));
    assert(is_text(global(&vm, "b"), "0.3333333333333333"));
    assert(is_text(global(&vm, "c"), "0.1"));       /* not 0.10000000000000001 */
    assert(is_text(global(&vm, "d"), "1000"));      /* not 1e+03 */
    assert(is_text(global(&vm, "e"), "100"));
    assert(is_text(global(&vm, "f"), "0"));

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* The text a float renders to must compile back to the same bits. Built by
   rendering the value, wrapping the text in source, and running it -- so this
   goes through the scanner, not just through asFloat. */
static void test_rendered_text_compiles_back(void)
{
    const char *literals[] = {
        "0.1", "1.0:div(3.0)", "1e3", "1234567.0", "1e308", "1.5e-3", "0.0",
        "100.0", "2.5", "1e-300", "123456789012345.0", "0.30000000000000004",
        "1.0:div(7.0)", "1e3:negated", "2.5:negated",
    };

    for (size_t i = 0; i < sizeof literals / sizeof literals[0]; i++) {
        SolVM vm; sol_vm_init(&vm);
        SolChunk chunk;

        char source[128];
        snprintf(source, sizeof source, "v := %s.", literals[i]);
        assert(run(&vm, &chunk, source) == SOL_OK);

        SolValue original = global(&vm, "v");
        assert(SOL_IS_FLOAT(original));

        SolText text;
        sol_text_init(&text);
        sol_value_render(&vm, original, &text);

        /* Feed the rendered text back in as source. */
        SolVM again; sol_vm_init(&again);
        SolChunk second;
        char round[160];
        snprintf(round, sizeof round, "v := %s.", text.chars);
        assert(run(&again, &second, round) == SOL_OK);

        SolValue back = global(&again, "v");
        assert(SOL_IS_FLOAT(back));
        /* Bit-identical, not merely close. */
        assert(memcmp(&original.as.real, &back.as.real, sizeof(double)) == 0);

        sol_text_free(&text);
        sol_chunk_free(&second);
        sol_vm_free(&again);
        sol_chunk_free(&chunk);
        sol_vm_free(&vm);
    }
}

/* Infinity and not-a-number have no literal form, so they are written by name.
   `infinity` and `nan` are globals and read back; `-infinity` does not, and
   asFloat is the way home for it. */
static void test_non_finite_floats(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "a := infinity:asString."
        "b := infinity:negated:asString."
        "c := nan:asString."
        "d := 1.0:div(0.0):equals(infinity)."
        "e := \"infinity\":asFloat:equals(infinity)."
        "f := \"-infinity\":asFloat:equals(infinity:negated).") == SOL_OK);
    assert(is_text(global(&vm, "a"), "infinity"));
    assert(is_text(global(&vm, "b"), "-infinity"));
    assert(is_text(global(&vm, "c"), "nan"));
    assert(SOL_AS_BOOL(global(&vm, "d")) == true);
    assert(SOL_AS_BOOL(global(&vm, "e")) == true);
    assert(SOL_AS_BOOL(global(&vm, "f")) == true);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* Bases are a message rather than a letter in the format spec: a letter buys one
   base, a number buys all of them, and nothing in the spec starts looking like
   printf's conversion character. */
static void test_as_base(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "a := #255:asBase(#16)."
        "b := #255:asBase(#2)."
        "c := #255:asBase(#8)."
        "d := #-255:asBase(#16)."
        "e := #0:asBase(#16)."
        "f := #35:asBase(#36)."
        "g := #255:asBase(#10).") == SOL_OK);
    assert(is_text(global(&vm, "a"), "ff"));
    assert(is_text(global(&vm, "b"), "11111111"));
    assert(is_text(global(&vm, "c"), "377"));
    assert(is_text(global(&vm, "d"), "-ff"));
    assert(is_text(global(&vm, "e"), "0"));
    assert(is_text(global(&vm, "f"), "z"));
    assert(is_text(global(&vm, "g"), "255"));
    sol_chunk_free(&chunk);

    /* Padding comes from the spec, by chaining. */
    assert(run(&vm, &chunk, "h := #255:asBase(#16):asString(\"08\").") == SOL_OK);
    assert(is_text(global(&vm, "h"), "000000ff"));
    sol_chunk_free(&chunk);

    /* The most negative integer has no positive counterpart, so the magnitude is
       taken unsigned and it converts like any other rather than trapping. */
    assert(run(&vm, &chunk,
        "i := #-9223372036854775808:asBase(#16).") == SOL_OK);
    assert(is_text(global(&vm, "i"), "-8000000000000000"));

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* asInteger takes the base back, so the pair round-trips. */
static void test_base_round_trip(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "ok := true."
        "b := #2."
        "{ b:lessOrEqual(#36) }:whileTrue({"
        "    [#255, #-255, #1, #0, #123456789, #-9223372036854775807]:do({ n |"
        "        n:asBase(b):asInteger(b):equals(n):ifFalse({ ok := false })"
        "    })."
        "    b := b:add(#1)"
        "}).") == SOL_OK);
    assert(SOL_AS_BOOL(global(&vm, "ok")) == true);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

static void test_base_errors(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    const char *bad[] = {
        "#255:asBase(#1).",
        "#255:asBase(#37).",
        "#255:asBase(#0).",
        "#255:asBase(#-16).",
        "#255:asBase(16.0).",
        "#255:asBase(\"16\").",
        "#255:asBase.",
        "#255:asBase(#16, #2).",
        "\"0xff\":asInteger(#16).",   /* the digits alone, no prefix */
        "\"fg\":asInteger(#16).",
        "\"2\":asInteger(#2).",       /* not a digit in that base */
        "\" ff\":asInteger(#16).",
        "\"\":asInteger(#16).",
        "\"45\":asInteger(#1).",
        "\"ff\":asInteger(#16, #2).",
        "\"ff\":asInteger(16.0).",
    };
    for (size_t i = 0; i < sizeof bad / sizeof bad[0]; i++) {
        assert(run(&vm, &chunk, bad[i]) == SOL_RUNTIME_ERROR);
        sol_chunk_free(&chunk);
    }

    /* Base 10 stays the default, so nothing that worked before changes. */
    assert(run(&vm, &chunk, "a := \"45\":asInteger. b := \"-3\":asInteger.") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "a")) == 45);
    assert(SOL_AS_INT(global(&vm, "b")) == -3);
    sol_chunk_free(&chunk);

    sol_vm_free(&vm);
}

int main(void)
{
    test_as_base();
    test_base_round_trip();
    test_base_errors();
    test_printing_keeps_the_value();
    test_rendered_text_compiles_back();
    test_non_finite_floats();
    test_as_string_is_plain_text();
    test_as_float();
    test_narrowing_names_its_direction();
    test_narrowing_guards();
    test_parsing_is_strict();
    printf("test_convert: ok\n");
    return 0;
}
