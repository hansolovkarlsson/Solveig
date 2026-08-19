/* Methods defined in Solum source: compiling them, calling them, and the frame
 * discipline that makes calls nest safely. */
#include <assert.h>
#include <stdio.h>
#include <string.h>

#include "solas/compiler.h"
#include "solum/vm.h"

/* Chunks must outlive the VM run: a class holds a pointer to a method that the
   chunk owns. Tests keep the chunk on the stack for exactly that reason. */
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

static void test_defines_and_calls_a_method(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "integer:double() := self:mul(#2)."
        "r := #21:double().") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "r")) == 42);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* Parameters land in frame slots 1..arity, with self at slot 0. */
static void test_parameters_become_locals(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "integer:poly(a, b) := self:mul(a):add(b)."
        "r := #10:poly(#3, #7).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "r")) == 37);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* Parens holding several statements: earlier results are dropped, the last is
   the value. */
static void test_grouped_body_yields_its_last_expression(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "integer:quadruple() := ( d := self:mul(#2). d:mul(#2) )."
        "r := #3:quadruple().") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "r")) == 12);

    sol_chunk_free(&chunk);

    /* The same grouping works outside a method, and a trailing '.' is fine. */
    assert(run(&vm, &chunk, "g := ( #1. #2. #3 ).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "g")) == 3);
    sol_chunk_free(&chunk);

    assert(run(&vm, &chunk, "h := ( #1. #2. ).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "h")) == 2);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* A local declared in a body must not leak into the globals. */
static void test_locals_do_not_escape(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "integer:tmp() := ( scratch := self:mul(#2). scratch )."
        "r := #4:tmp().") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "r")) == 8);
    assert(sol_object_lookup(vm.root, "scratch") == NULL);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* A method still sees the globals for anything that is not one of its locals. */
static void test_methods_read_globals(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "offset := #100."
        "integer:shifted() := self:add(offset)."
        "r := #5:shifted().") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "r")) == 105);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* Nested calls must unwind cleanly, leaving exactly one value behind each. */
static void test_calls_nest(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "integer:double() := self:mul(#2)."
        "integer:octuple() := self:double():double():double()."
        "r := #5:octuple()."
        "s := #1:double():add(#2:double()).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "r")) == 40);
    assert(SOL_AS_INT(global(&vm, "s")) == 6);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

static void test_arity_is_checked(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "integer:one(a) := self:add(a)."
        "#1:one().") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);

    assert(run(&vm, &chunk,
        "integer:one(a) := self:add(a)."
        "#1:one(#1, #2).") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);

    sol_vm_free(&vm);
}

/* Runaway recursion must hit the frame cap, not the end of the stack. */
static void test_recursion_is_bounded(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "integer:loop() := self:loop()."
        "#1:loop().") == SOL_RUNTIME_ERROR);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* Methods can only be bound on objects; a value has no slots of its own. */
static void test_defining_on_a_value_is_an_error(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk, "x := #1. x:frob() := #2.") == SOL_RUNTIME_ERROR);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* A definition must not be mistaken for a send, or vice versa. */
static void test_definition_and_send_are_distinguished(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    /* `integer:double()` with no ':=' is a send, and fails as undefined. */
    assert(run(&vm, &chunk, "integer:double().") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);

    /* A plain assignment is still a plain assignment. */
    assert(run(&vm, &chunk, "a := #45.") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "a")) == 45);
    sol_chunk_free(&chunk);

    /* And a send whose result is assigned is not a definition. */
    assert(run(&vm, &chunk, "b := #21:add(#21).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "b")) == 42);
    sol_chunk_free(&chunk);

    sol_vm_free(&vm);
}

/* A method may be redefined; the newest binding wins. */
static void test_methods_can_be_redefined(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk first, second;

    assert(run(&vm, &first,
        "integer:f() := self:add(#1). r := #10:f().") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "r")) == 11);

    assert(run(&vm, &second,
        "integer:f() := self:add(#2). r := #10:f().") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "r")) == 12);

    sol_chunk_free(&second);
    sol_chunk_free(&first);
    sol_vm_free(&vm);
}

int main(void)
{
    test_defines_and_calls_a_method();
    test_parameters_become_locals();
    test_grouped_body_yields_its_last_expression();
    test_locals_do_not_escape();
    test_methods_read_globals();
    test_calls_nest();
    test_arity_is_checked();
    test_recursion_is_bounded();
    test_defining_on_a_value_is_an_error();
    test_definition_and_send_are_distinguished();
    test_methods_can_be_redefined();
    printf("test_methods: ok\n");
    return 0;
}
