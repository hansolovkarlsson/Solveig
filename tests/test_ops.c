/* The operations filled in around the core: short-circuit logic, ordering,
 * negation, and asString on composites. */
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

/* `and` and `or` take a block precisely so the answer can be settled without
   running it. Testing the value alone would not show that. */
static void test_and_or_short_circuit(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "ran := false."
        "a := false:and({ ran := true. true })."
        "skipped := ran:not."
        "ran := false."
        "b := true:or({ ran := true. true })."
        "skipped2 := ran:not."
        "ran := false."
        "c := true:and({ ran := true. true })."
        "entered := ran."
        "ran := false."
        "d := false:or({ ran := true. false })."
        "entered2 := ran.") == SOL_OK);

    assert(SOL_AS_BOOL(global(&vm, "a")) == false);
    assert(SOL_AS_BOOL(global(&vm, "skipped")) == true);    /* never ran */
    assert(SOL_AS_BOOL(global(&vm, "b")) == true);
    assert(SOL_AS_BOOL(global(&vm, "skipped2")) == true);
    assert(SOL_AS_BOOL(global(&vm, "c")) == true);
    assert(SOL_AS_BOOL(global(&vm, "entered")) == true);    /* did run */
    assert(SOL_AS_BOOL(global(&vm, "d")) == false);
    assert(SOL_AS_BOOL(global(&vm, "entered2")) == true);
    sol_chunk_free(&chunk);

    /* Strict about what the block answers, as whileTrue is. */
    assert(run(&vm, &chunk, "true:and({ #1 }).") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);
    assert(run(&vm, &chunk, "false:or({ nil }).") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);
    /* And a value where a block belongs is an error, not a coercion. */
    assert(run(&vm, &chunk, "true:and(true).") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);

    sol_vm_free(&vm);
}

static void test_ordering(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "a := [#1:lessOrEqual(#1), #1:lessOrEqual(#2), #2:lessOrEqual(#1)]."
        "b := [#1:greaterOrEqual(#1), #2:greaterOrEqual(#1), #1:greaterOrEqual(#2)]."
        "c := [1.5:lessOrEqual(1.5), 2.5:greaterOrEqual(1.5)].") == SOL_OK);

    const bool expect_a[] = {true, true, false};
    const bool expect_b[] = {true, true, false};
    const bool expect_c[] = {true, true};
    const char *names[] = {"a", "b", "c"};
    const bool *expected[] = {expect_a, expect_b, expect_c};
    const int counts[] = {3, 3, 2};

    for (int g = 0; g < 3; g++) {
        SolValue v = global(&vm, names[g]);
        for (int i = 0; i < counts[g]; i++) {
            assert(SOL_AS_BOOL(SOL_AS_ARRAY(v)->items[i]) == expected[g][i]);
        }
    }
    sol_chunk_free(&chunk);

    /* Still strict: an integer does not order against a float. */
    assert(run(&vm, &chunk, "#1:lessOrEqual(1.0).") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);

    sol_vm_free(&vm);
}

/* Strings order by characters, with the shorter first when one is a prefix --
   which is what sorting them will want. */
static void test_string_ordering(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "r := [\"abc\":lessThan(\"abd\"),"
        "      \"ab\":lessThan(\"abc\"),"
        "      \"b\":lessThan(\"abc\"),"
        "      \"abc\":greaterThan(\"ab\"),"
        "      \"ab\":lessOrEqual(\"ab\"),"
        "      \"\":lessThan(\"a\"),"
        "      \"abc\":lessThan(\"abc\")].") == SOL_OK);

    const bool expected[] = {true, true, false, true, true, true, false};
    SolValue r = global(&vm, "r");
    for (int i = 0; i < 7; i++) {
        assert(SOL_AS_BOOL(SOL_AS_ARRAY(r)->items[i]) == expected[i]);
    }

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* notEquals is defined as the negation of equals, so it inherits whatever
   equality means for each type -- value for strings, identity for arrays. */
static void test_not_equals_tracks_equals(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "r := [#1:notEquals(#2), #1:notEquals(#1),"
        "      \"a\":notEquals(\"a\"), \"a\":notEquals(\"b\"),"
        "      [#1]:notEquals([#1]),"          /* identity: two arrays */
        "      true:notEquals(false), nil:notEquals(nil),"
        "      #1:notEquals(1.0)].") == SOL_OK);

    const bool expected[] = {true, false, false, true, true, true, false, true};
    SolValue r = global(&vm, "r");
    for (int i = 0; i < 8; i++) {
        assert(SOL_AS_BOOL(SOL_AS_ARRAY(r)->items[i]) == expected[i]);
    }

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

static void test_negation_and_abs(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "a := #5:negated. b := #-5:negated. c := #-5:abs. d := #5:abs."
        "e := 2.5:negated. f := -2.5:abs."
        "g := float:new(1.5).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "a")) == -5);
    assert(SOL_AS_INT(global(&vm, "b")) == 5);
    assert(SOL_AS_INT(global(&vm, "c")) == 5);
    assert(SOL_AS_INT(global(&vm, "d")) == 5);
    assert(SOL_AS_FLOAT(global(&vm, "e")) == -2.5);
    assert(SOL_AS_FLOAT(global(&vm, "f")) == 2.5);
    assert(SOL_AS_FLOAT(global(&vm, "g")) == 1.5);
    sol_chunk_free(&chunk);

    /* The most negative integer has no positive counterpart -- the same edge
       that guards INT64_MIN div #-1. */
    assert(run(&vm, &chunk, "#-9223372036854775808:negated.") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);
    assert(run(&vm, &chunk, "#-9223372036854775808:abs.") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);

    sol_vm_free(&vm);
}

/* A composite has no unambiguous flat text, so its asString is the literal form
   print shows -- rendered once, so the two cannot disagree. */
static void test_composite_as_string(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "a := [#1, \"a\", [#2, true], nil]:asString."
        "e := []:asString.") == SOL_OK);
    assert(is_text(global(&vm, "a"), "[#1, \"a\", [#2, true], nil]"));
    assert(is_text(global(&vm, "e"), "[]"));
    sol_chunk_free(&chunk);

    /* Self-reference is depth-limited rather than infinite. */
    assert(run(&vm, &chunk, "s := []. s:add(s). t := s:asString.") == SOL_OK);
    assert(SOL_IS_STRING(global(&vm, "t")));
    sol_chunk_free(&chunk);

    sol_vm_free(&vm);
}

static void test_fill(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "a := \"you have {} apples and {} pears\":fill([#3, #4])."
        "b := \"{}\":fill([\"hi\"])."
        "c := \"none\":fill([])."
        "d := \"{} and {} and {}\":fill([#1, 2.5, true])."
        "e := \"\":fill([]).") == SOL_OK);
    assert(is_text(global(&vm, "a"), "you have 3 apples and 4 pears"));
    assert(is_text(global(&vm, "b"), "hi"));
    assert(is_text(global(&vm, "c"), "none"));
    assert(is_text(global(&vm, "d"), "1 and 2.5 and true"));
    assert(is_text(global(&vm, "e"), ""));
    sol_chunk_free(&chunk);

    /* `{{` writes a brace; a `{` that is neither `{}` nor `{{` is a mistake.
       `}` is never special, so it needs no escape and `}}` is two of them --
       unlike Python, where `}` closes a placeholder that can have content. Here
       a placeholder is exactly `{}`, so a lone `}` cannot be ambiguous. */
    assert(run(&vm, &chunk,
        "a := \"{{} literal\":fill([])."
        "b := \"{{}}\":fill([])."
        "c := \"} alone\":fill([]).") == SOL_OK);
    assert(is_text(global(&vm, "a"), "{} literal"));
    assert(is_text(global(&vm, "b"), "{}}"));
    assert(is_text(global(&vm, "c"), "} alone"));
    sol_chunk_free(&chunk);

    sol_vm_free(&vm);
}

/* Both directions of mismatch are errors: filling gaps or dropping extras would
   turn a mistake into output that looks deliberate. */
static void test_fill_counts_must_match(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    const char *bad[] = {
        "\"{} and {}\":fill([#1]).",        /* too few values */
        "\"{}\":fill([#1, #2]).",           /* too many */
        "\"{}\":fill([]).",
        "\"none\":fill([#1]).",
        "\"a { b\":fill([]).",              /* a brace that is neither form */
        "\"trailing {\":fill([]).",
        "\"{}\":fill(#1).",                 /* not an array */
        "\"{}\":fill().",
    };
    for (size_t i = 0; i < sizeof bad / sizeof bad[0]; i++) {
        assert(run(&vm, &chunk, bad[i]) == SOL_RUNTIME_ERROR);
        sol_chunk_free(&chunk);
    }

    sol_vm_free(&vm);
}

/* fill asks each value for its asString by sending it, so a type that
   overrides asString is honoured rather than bypassed. */
static void test_fill_honours_an_overridden_as_string(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "point := object:new."
        "point:x := #0."
        "point:asString := { \"point(\":concat(self:x:asString):concat(\")\") }."
        "p := point:new. p:x := #7."
        "r := \"the answer is {}\":fill([p]).") == SOL_OK);
    assert(is_text(global(&vm, "r"), "the answer is point(7)"));
    sol_chunk_free(&chunk);

    /* An asString that answers something else is caught, not concatenated. */
    assert(run(&vm, &chunk,
        "bad := object:new. bad:asString := { #1 }."
        "\"{}\":fill([bad:new]).") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);

    sol_vm_free(&vm);
}

int main(void)
{
    test_fill();
    test_fill_counts_must_match();
    test_fill_honours_an_overridden_as_string();
    test_and_or_short_circuit();
    test_ordering();
    test_string_ordering();
    test_not_equals_tracks_equals();
    test_negation_and_abs();
    test_composite_as_string();
    printf("test_ops: ok\n");
    return 0;
}
