/* The operations filled in around the core: short-circuit logic, ordering,
 * negation, and asString on composites. */
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
        "e := 2.5:negated. f := -2.5:abs.") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "a")) == -5);
    assert(SOL_AS_INT(global(&vm, "b")) == 5);
    assert(SOL_AS_INT(global(&vm, "c")) == 5);
    assert(SOL_AS_INT(global(&vm, "d")) == 5);
    assert(SOL_AS_FLOAT(global(&vm, "e")) == -2.5);
    assert(SOL_AS_FLOAT(global(&vm, "f")) == 2.5);
    sol_chunk_free(&chunk);

    /* The most negative integer has no positive counterpart -- the same edge
       that guards INT64_MIN div #-1. */
    assert(run(&vm, &chunk, "#-9223372036854775808:negated.") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);
    assert(run(&vm, &chunk, "#-9223372036854775808:abs.") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);

    sol_vm_free(&vm);
}

/* Checked against the C library rather than against a written-down constant,
   because that is the whole argument for the primitive: two hand-written
   versions in programs/bench.sol were both wrong and neither was caught by
   looking at its answers. 1e10 is where the first went wrong in the fourth
   digit; 1e40 and 1e300 are where the second, written to fix the first, went
   wrong by nineteen orders of magnitude and said nothing. */
static void test_square_root(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    static const double cases[] = { 0.0, 1.0, 4.0, 0.25, 2.0, 1e-10, 1e10,
                                    1e20, 1e40, 1e300, 1e-300 };
    for (size_t i = 0; i < sizeof cases / sizeof cases[0]; i++) {
        char source[64];
        snprintf(source, sizeof source, "a := %.17g:sqrt.", cases[i]);
        assert(run(&vm, &chunk, source) == SOL_OK);
        assert(SOL_AS_FLOAT(global(&vm, "a")) == sqrt(cases[i]));
        sol_chunk_free(&chunk);
    }

    /* A negative answers nan and does not raise, which is the rule float
       division already follows: this arithmetic reaches nan and infinity
       instead of trapping. nan is not equal to itself, so ask it that. */
    assert(run(&vm, &chunk, "a := -1.0:sqrt. b := a:equals(a)."
                            "c := infinity:sqrt. d := -0.0:sqrt.") == SOL_OK);
    assert(isnan(SOL_AS_FLOAT(global(&vm, "a"))));
    assert(SOL_AS_BOOL(global(&vm, "b")) == false);
    assert(isinf(SOL_AS_FLOAT(global(&vm, "c"))));
    assert(signbit(SOL_AS_FLOAT(global(&vm, "d"))));
    sol_chunk_free(&chunk);

    /* Float only: an integer says which way it is converting. */
    assert(run(&vm, &chunk, "#4:sqrt.") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);
    assert(run(&vm, &chunk, "a := #4:asFloat:sqrt.") == SOL_OK);
    assert(SOL_AS_FLOAT(global(&vm, "a")) == 2.0);
    sol_chunk_free(&chunk);

    assert(run(&vm, &chunk, "4.0:sqrt(#1).") == SOL_RUNTIME_ERROR);
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

/* One more, one less. `add(#1)` and `sub(#1)` under shorter names, and they trap
   at the ends the way those two do. */
static void test_inc_and_dec(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "a := #5:inc."
        "b := #5:dec."
        "c := #0:dec."
        "d := #0:sub(#1):inc."
        /* The idiom: a value, so the assignment is the whole of it. */
        "count := #10. count := count:dec. count := count:dec.") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "a")) == 6);
    assert(SOL_AS_INT(global(&vm, "b")) == 4);
    assert(SOL_AS_INT(global(&vm, "c")) == -1);
    assert(SOL_AS_INT(global(&vm, "d")) == 0);
    assert(SOL_AS_INT(global(&vm, "count")) == 8);
    sol_chunk_free(&chunk);

    /* Both ends trap rather than wrapping, like add and sub. */
    assert(run(&vm, &chunk, "#9223372036854775807:inc.") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);
    assert(run(&vm, &chunk,
        "#0:sub(#9223372036854775807):dec:dec.") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);

    /* Integers only, and no argument. */
    assert(run(&vm, &chunk, "1.5:inc.") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);
    assert(run(&vm, &chunk, "#1:inc(#2).") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);

    sol_vm_free(&vm);
    printf("  inc and dec, trapping at the ends\n");
}

/* The bitwise messages, on a signed 64-bit two's-complement integer. */
static void test_bit_operations(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "a := #12:bitAnd(#10)."          /* 1100 & 1010 */
        "b := #12:bitOr(#10)."
        "c := #12:bitXor(#10)."
        "d := #0:bitNot."
        "e := #5:bitNot."
        /* Negatives work, being two's complement. */
        "f := #0:sub(#1):bitAnd(#255)."
        "g := #0:bitOr(#0).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "a")) == 8);
    assert(SOL_AS_INT(global(&vm, "b")) == 14);
    assert(SOL_AS_INT(global(&vm, "c")) == 6);
    assert(SOL_AS_INT(global(&vm, "d")) == -1);
    assert(SOL_AS_INT(global(&vm, "e")) == -6);
    assert(SOL_AS_INT(global(&vm, "f")) == 255);
    assert(SOL_AS_INT(global(&vm, "g")) == 0);
    sol_chunk_free(&chunk);

    assert(run(&vm, &chunk, "#1:bitAnd(1.0).") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);

    sol_vm_free(&vm);
    printf("  bitAnd, bitOr, bitXor and bitNot\n");
}

/* Shifting, and the two decisions in it: right keeps the sign, and left refuses
   to lose the number. */
static void test_shifting(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "a := #1:shiftLeft(#10)."
        "b := #1024:shiftRight(#3)."
        "c := #1:shiftLeft(#0)."
        "d := #1:shiftLeft(#62)."
        "e := #0:sub(#1):shiftRight(#63)."   /* the sign, spread out */
        "f := #0:shiftRight(#63).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "a")) == 1024);
    assert(SOL_AS_INT(global(&vm, "b")) == 128);
    assert(SOL_AS_INT(global(&vm, "c")) == 1);
    assert(SOL_AS_INT(global(&vm, "d")) == ((int64_t)1 << 62));
    assert(SOL_AS_INT(global(&vm, "e")) == -1);
    assert(SOL_AS_INT(global(&vm, "f")) == 0);
    sol_chunk_free(&chunk);

    /* A shift right is div by a power of two, floored -- which is the whole
       argument for keeping the sign, so it is asserted rather than described.
       The negatives are where trunc and floor disagree. */
    assert(run(&vm, &chunk,
        "same := true."
        "[#100, #7, #1, #0]:do({ n | | neg |"
        "    neg := #0:sub(n)."
        "    n:shiftRight(#2):equals(n:div(#4)):ifFalse({ same := false })."
        "    neg:shiftRight(#2):equals(neg:div(#4)):ifFalse({ same := false }) })."
        "seven := #0:sub(#7):shiftRight(#2).") == SOL_OK);
    assert(SOL_AS_BOOL(global(&vm, "same")) == true);
    assert(SOL_AS_INT(global(&vm, "seven")) == -2);      /* floored, not -1 */
    sol_chunk_free(&chunk);

    /* Losing the number is refused, and so is a count that is not one. */
    static const char *refused[] = {
        "#1:shiftLeft(#63).",
        "#2:shiftLeft(#62).",
        /* -2 << 62 is exactly INT64_MIN and is fine; -3 is one too far. */
        "#0:sub(#3):shiftLeft(#62).",
        "#1:shiftLeft(#64).",
        "#1:shiftRight(#64).",
        "#1:shiftLeft(#0:sub(#1)).",
        "#1:shiftLeft(1.0).",
    };
    for (size_t i = 0; i < sizeof refused / sizeof refused[0]; i++) {
        assert(run(&vm, &chunk, refused[i]) == SOL_RUNTIME_ERROR);
        sol_chunk_free(&chunk);
    }

    /* The largest shift that does fit, at both ends. */
    assert(run(&vm, &chunk,
        "big := #0:sub(#1):shiftLeft(#63)."       /* -1 << 63 is INT64_MIN */
        "alsoBig := #0:sub(#2):shiftLeft(#62)."   /* and so is -2 << 62 */
        "small := #1:shiftLeft(#62).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "alsoBig")) == INT64_MIN);
    assert(SOL_AS_INT(global(&vm, "big")) == INT64_MIN);
    assert(SOL_AS_INT(global(&vm, "small")) == ((int64_t)1 << 62));
    sol_chunk_free(&chunk);

    sol_vm_free(&vm);
    printf("  shifting, keeping the sign and refusing to lose the number\n");
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
    test_square_root();
    test_composite_as_string();
    test_inc_and_dec();
    test_bit_operations();
    test_shifting();
    printf("test_ops: ok\n");
    return 0;
}
