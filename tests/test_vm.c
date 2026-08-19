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

int main(void)
{
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
