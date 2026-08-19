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
    SolChunk chunk;

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
    assert(run(&vm, &chunk,
        "msg := \"you have \":concat(#45:asString):concat(\" apples\").") == SOL_OK);
    assert(is_text(global(&vm, "msg"), "you have 45 apples"));

    sol_chunk_free(&chunk);
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

int main(void)
{
    test_as_string_is_plain_text();
    test_as_float();
    test_narrowing_names_its_direction();
    test_narrowing_guards();
    test_parsing_is_strict();
    printf("test_convert: ok\n");
    return 0;
}
