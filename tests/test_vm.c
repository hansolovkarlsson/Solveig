/* End-to-end: source text through Solas and Solum, checked by inspecting the
 * globals the program left behind. */
#include <assert.h>
#include <stdio.h>
#include <string.h>

#include "solas/compiler.h"
#include "solum/vm.h"

/* Compiles and runs `source` in `vm`, returning the result. */
static SolResult run(SolVM *vm, const char *source)
{
    SolChunk chunk;
    sol_chunk_init(&chunk);

    SolResult result = SOL_COMPILE_ERROR;
    if (sol_compile(source, &chunk)) {
        result = sol_vm_run(vm, &chunk);
    }
    sol_chunk_free(&chunk);
    return result;
}

/* The value bound to `name`, or nil if unbound. */
static SolValue global(SolVM *vm, const char *name)
{
    SolSlot *slot = sol_object_lookup(vm->root, name);
    return slot ? slot->value : SOL_NIL_VAL;
}

static void test_assignment_binds_a_name(void)
{
    SolVM vm;
    sol_vm_init(&vm);

    assert(run(&vm, "a := #45.") == SOL_OK);
    assert(SOL_IS_INT(global(&vm, "a")));
    assert(SOL_AS_INT(global(&vm, "a")) == 45);

    sol_vm_free(&vm);
}

/* '#' picks the type: #45 is an integer, a bare 45 is a float. */
static void test_hash_selects_the_numeric_type(void)
{
    SolVM vm;
    sol_vm_init(&vm);

    assert(run(&vm, "i := #45. f := 45.") == SOL_OK);
    assert(SOL_IS_INT(global(&vm, "i")));
    assert(SOL_IS_FLOAT(global(&vm, "f")));
    assert(SOL_AS_FLOAT(global(&vm, "f")) == 45.0);

    sol_vm_free(&vm);
}

/* The point of the variable model: arithmetic returns a new value and leaves
   the receiver's binding alone. */
static void test_values_are_immutable(void)
{
    SolVM vm;
    sol_vm_init(&vm);

    assert(run(&vm, "a := #45. b := a:add(#5).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "b")) == 50);
    assert(SOL_AS_INT(global(&vm, "a")) == 45);   /* unchanged */

    /* Rebinding is how you "change" a name. */
    assert(run(&vm, "a := a:add(#5).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "a")) == 50);

    sol_vm_free(&vm);
}

static void test_sends_chain_left_to_right(void)
{
    SolVM vm;
    sol_vm_init(&vm);

    assert(run(&vm, "r := #2:add(#3):mul(#4).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "r")) == 20);   /* (2+3)*4, not 2+(3*4) */

    sol_vm_free(&vm);
}

/* `integer:new(#45)` is the long form of the literal, not a second kind of thing. */
static void test_new_is_the_long_form_of_a_literal(void)
{
    SolVM vm;
    sol_vm_init(&vm);

    assert(run(&vm, "a := integer:new(#45). b := #45.") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "a")) == SOL_AS_INT(global(&vm, "b")));

    sol_vm_free(&vm);
}

static void test_assignment_is_an_expression(void)
{
    SolVM vm;
    sol_vm_init(&vm);

    assert(run(&vm, "c := b := #45.") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "b")) == 45);
    assert(SOL_AS_INT(global(&vm, "c")) == 45);

    sol_vm_free(&vm);
}

/* Strict typing: mixing an integer and a float is an error, never a coercion. */
static void test_arithmetic_is_strict(void)
{
    SolVM vm;
    sol_vm_init(&vm);

    assert(run(&vm, "x := #45:add(1.5).") == SOL_RUNTIME_ERROR);
    assert(run(&vm, "y := 1.5:add(#45).") == SOL_RUNTIME_ERROR);
    assert(run(&vm, "z := 1.5:add(2.5).") == SOL_OK);
    assert(SOL_AS_FLOAT(global(&vm, "z")) == 4.0);

    sol_vm_free(&vm);
}

/* Overflow traps rather than wrapping silently. */
static void test_integer_overflow_traps(void)
{
    SolVM vm;
    sol_vm_init(&vm);

    assert(run(&vm, "big := #9223372036854775807. big:add(#1).") == SOL_RUNTIME_ERROR);
    assert(run(&vm, "small := #-9223372036854775807. small:sub(#2).") == SOL_RUNTIME_ERROR);
    assert(run(&vm, "ok := #9223372036854775806:add(#1).") == SOL_OK);

    sol_vm_free(&vm);
}

static void test_errors_are_reported_not_crashed(void)
{
    SolVM vm;
    sol_vm_init(&vm);

    assert(run(&vm, "undefined_name:print.") == SOL_RUNTIME_ERROR);
    assert(run(&vm, "#45:frobnicate.") == SOL_RUNTIME_ERROR);
    assert(run(&vm, "a := .") == SOL_COMPILE_ERROR);
    assert(run(&vm, "a := (#45.") == SOL_COMPILE_ERROR);

    /* The VM must still be usable after each failure -- Solis depends on it. */
    assert(run(&vm, "fine := #1.") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "fine")) == 1);

    sol_vm_free(&vm);
}

/* Globals outlive a chunk, which is what makes the REPL work line by line. */
static void test_globals_persist_across_chunks(void)
{
    SolVM vm;
    sol_vm_init(&vm);

    assert(run(&vm, "a := #45.") == SOL_OK);
    assert(run(&vm, "b := a:add(#5).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "b")) == 50);

    sol_vm_free(&vm);
}

/* Integer division floors, so it differs from C only on negatives, and the
   remainder takes the divisor's sign rather than the dividend's. */
static void test_division_floors(void)
{
    SolVM vm; sol_vm_init(&vm);

    assert(run(&vm,
        "a := #7:div(#2).  b := #-7:div(#2)."
        "c := #7:div(#-2). d := #-7:div(#-2).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "a")) == 3);
    assert(SOL_AS_INT(global(&vm, "b")) == -4);   /* not -3 */
    assert(SOL_AS_INT(global(&vm, "c")) == -4);
    assert(SOL_AS_INT(global(&vm, "d")) == 3);

    assert(run(&vm,
        "a := #7:mod(#2).  b := #-7:mod(#2)."
        "c := #7:mod(#-2). d := #-7:mod(#-2)."
        "e := #6:mod(#3).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "a")) == 1);
    assert(SOL_AS_INT(global(&vm, "b")) == 1);    /* not -1: divisor's sign */
    assert(SOL_AS_INT(global(&vm, "c")) == -1);
    assert(SOL_AS_INT(global(&vm, "d")) == -1);
    assert(SOL_AS_INT(global(&vm, "e")) == 0);

    sol_vm_free(&vm);
}

/* (a div b) * b + (a mod b) == a, whatever the signs. */
static void test_division_identity(void)
{
    SolVM vm; sol_vm_init(&vm);

    assert(run(&vm,
        "check := { a, b | a:sub( a:div(b):mul(b):add(a:mod(b)) ) }."
        "r := [check:value(#7, #2),  check:value(#-7, #2),"
        "      check:value(#7, #-2), check:value(#-7, #-2),"
        "      check:value(#0, #5),  check:value(#-1, #7),"
        "      check:value(#100, #7), check:value(#-100, #-7)].") == SOL_OK);

    SolValue r = global(&vm, "r");
    assert(SOL_IS_ARRAY(r));
    for (int i = 0; i < SOL_AS_ARRAY(r)->count; i++) {
        assert(SOL_AS_INT(SOL_AS_ARRAY(r)->items[i]) == 0);
    }

    sol_vm_free(&vm);
}

/* Integers have no infinity, so dividing by zero errors -- and the one division
   that overflows is guarded, since in C it is undefined rather than merely
   wrong. */
static void test_integer_division_guards(void)
{
    SolVM vm; sol_vm_init(&vm);

    assert(run(&vm, "#1:div(#0).") == SOL_RUNTIME_ERROR);
    assert(run(&vm, "#1:mod(#0).") == SOL_RUNTIME_ERROR);
    assert(run(&vm, "#0:div(#0).") == SOL_RUNTIME_ERROR);

    assert(run(&vm, "#-9223372036854775808:div(#-1).") == SOL_RUNTIME_ERROR);
    assert(run(&vm, "#-9223372036854775808:mod(#-1).") == SOL_RUNTIME_ERROR);

    /* But the neighbouring cases are fine. */
    assert(run(&vm,
        "a := #-9223372036854775808:div(#1)."
        "b := #-9223372036854775807:div(#-1).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "b")) == 9223372036854775807LL);

    /* Strict as ever. */
    assert(run(&vm, "#7:div(2.0).") == SOL_RUNTIME_ERROR);

    sol_vm_free(&vm);
}

/* Floats have an infinity, and already reach it by overflow, so dividing by
   zero answers one rather than erroring. */
static void test_float_division_follows_ieee(void)
{
    SolVM vm; sol_vm_init(&vm);

    assert(run(&vm,
        "q := 7.0:div(2.0). inf := 1.0:div(0.0). neg := -1.0:div(0.0)."
        "m := -7.0:mod(2.0).") == SOL_OK);
    assert(SOL_AS_FLOAT(global(&vm, "q")) == 3.5);
    assert(SOL_AS_FLOAT(global(&vm, "inf")) > 0 &&
           SOL_AS_FLOAT(global(&vm, "inf")) * 2 == SOL_AS_FLOAT(global(&vm, "inf")));
    assert(SOL_AS_FLOAT(global(&vm, "neg")) < 0);
    assert(SOL_AS_FLOAT(global(&vm, "m")) == 1.0);   /* floored, like integers */

    sol_vm_free(&vm);
}

/* `.` separates statements: required between two, optional after the last. */
static void test_statement_separator(void)
{
    SolVM vm; sol_vm_init(&vm);

    /* The last statement needs none. */
    assert(run(&vm, "a := #1. b := #2") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "b")) == 2);

    /* A trailing one is fine too. */
    assert(run(&vm, "c := #3.") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "c")) == 3);

    /* A single statement, with and without. */
    assert(run(&vm, "d := #4") == SOL_OK);
    assert(run(&vm, "e := #5.") == SOL_OK);

    /* Missing between two is now reported rather than silently accepted. */
    assert(run(&vm, "a := #1 b := #2.") == SOL_COMPILE_ERROR);
    assert(run(&vm, "#1 #2.") == SOL_COMPILE_ERROR);

    /* The same rule inside a group and a block, where it already held -- but the
       message now names the missing separator rather than the closing bracket. */
    assert(run(&vm, "r := ( #1 #2 ).") == SOL_COMPILE_ERROR);
    assert(run(&vm, "b := { #1 #2 }.") == SOL_COMPILE_ERROR);

    /* And they still accept the forms they always did. */
    assert(run(&vm, "r := ( #1. #2 ). s := { #1. #2. }:value().") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "r")) == 2);
    assert(SOL_AS_INT(global(&vm, "s")) == 2);

    sol_vm_free(&vm);
}

/* What the rule does not catch, recorded so it is a known limit rather than a
   surprise: a line beginning with ':' continues the expression above it, so
   these two lines are one statement and no separator is missing. */
static void test_a_leading_colon_still_continues(void)
{
    SolVM vm; sol_vm_init(&vm);

    assert(run(&vm, "total := #10\n:add(#5).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "total")) == 15);

    sol_vm_free(&vm);
}

int main(void)
{
    test_statement_separator();
    test_a_leading_colon_still_continues();
    test_division_floors();
    test_division_identity();
    test_integer_division_guards();
    test_float_division_follows_ieee();
    test_assignment_binds_a_name();
    test_hash_selects_the_numeric_type();
    test_values_are_immutable();
    test_sends_chain_left_to_right();
    test_new_is_the_long_form_of_a_literal();
    test_assignment_is_an_expression();
    test_arithmetic_is_strict();
    test_integer_overflow_traps();
    test_errors_are_reported_not_crashed();
    test_globals_persist_across_chunks();
    printf("test_vm: ok\n");
    return 0;
}
