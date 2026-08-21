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
        "integer:double := { self:mul(#2) }."
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
        "integer:poly := { a, b | self:mul(a):add(b) }."
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
        "integer:quadruple := { | d | d := self:mul(#2). d:mul(#2) }."
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
        "integer:tmp := { | scratch | scratch := self:mul(#2). scratch }."
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
        "integer:shifted := { self:add(offset) }."
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
        "integer:double := { self:mul(#2) }."
        "integer:octuple := { self:double():double():double() }."
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
        "integer:one := { a | self:add(a) }."
        "#1:one().") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);

    assert(run(&vm, &chunk,
        "integer:one := { a | self:add(a) }."
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
        "integer:loop := { self:loop() }."
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

    /* `integer:double` with no ':=' is a send, and fails as undefined. */
    assert(run(&vm, &chunk, "integer:double.") == SOL_RUNTIME_ERROR);
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
        "integer:f := { self:add(#1) }. r := #10:f().") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "r")) == 11);

    assert(run(&vm, &second,
        "integer:f := { self:add(#2) }. r := #10:f().") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "r")) == 12);

    sol_chunk_free(&second);
    sol_chunk_free(&first);
    sol_vm_free(&vm);
}

/* Only parameters and names declared with `| ... |` are locals. Everything else
   is a global, so a method can update one instead of shadowing it. */
static void test_a_method_updates_a_global(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "counter := #0."
        "integer:bump := { counter := counter:add(#1). counter }."
        "a := #1:bump(). b := #1:bump(). c := #1:bump().") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "a")) == 1);
    assert(SOL_AS_INT(global(&vm, "b")) == 2);
    assert(SOL_AS_INT(global(&vm, "c")) == 3);
    assert(SOL_AS_INT(global(&vm, "counter")) == 3);   /* the global, not a copy */

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

static void test_declared_temporaries_stay_local(void)
{
    SolVM vm; sol_vm_init(&vm);
    /* Two chunks: each binds a block to a slot on `integer`, and a chunk has to
       outlive anything defined in it -- so neither can be freed while the VM
       that holds those methods is still alive. */
    SolChunk first, second;

    assert(run(&vm, &first,
        "integer:quad := { | d | d := self:mul(#2). d:mul(#2) }."
        "r := #3:quad().") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "r")) == 12);
    assert(sol_object_lookup(vm.root, "d") == NULL);

    /* A declared temporary shadows a global of the same name. */
    assert(run(&vm, &second,
        "shadowed := #100."
        "integer:hide := { | shadowed | shadowed := #1. shadowed }."
        "s := #1:hide().") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "s")) == 1);
    assert(SOL_AS_INT(global(&vm, "shadowed")) == 100);

    sol_vm_free(&vm);
    sol_chunk_free(&first);
    sol_chunk_free(&second);
}

/* A name that is neither declared nor an existing global is a mistake, not a
   new variable -- otherwise a typo would silently look like a local. */
static void test_methods_cannot_invent_globals(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "total := #0."
        "integer:oops := { totl := #5. totl }."
        "#1:oops().") == SOL_RUNTIME_ERROR);
    assert(sol_object_lookup(vm.root, "totl") == NULL);
    sol_chunk_free(&chunk);

    /* The same restriction applies inside a block. */
    assert(run(&vm, &chunk, "{ nope := #1 }:value().") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);

    /* But the top level still makes globals freely. */
    assert(run(&vm, &chunk, "brandNew := #7.") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "brandNew")) == 7);
    sol_chunk_free(&chunk);

    sol_vm_free(&vm);
}

/* Declaring the same name twice in one frame is a mistake worth catching. */
static void test_duplicate_declaration_is_rejected(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "integer:dup := { | a, a | a }." ) == SOL_COMPILE_ERROR);
    sol_chunk_free(&chunk);

    assert(run(&vm, &chunk,
        "integer:dup := { x | | x | x }." ) == SOL_COMPILE_ERROR);
    sol_chunk_free(&chunk);

    sol_vm_free(&vm);
}

/* `:=` is one operator now: the right-hand side is always evaluated, and a slot
   holding a block is what makes a method. */
static void test_a_slot_holds_whatever_it_is_given(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    /* A block bound to a slot answers to a send by running. */
    assert(run(&vm, &chunk,
        "integer:twice := { self:mul(#2) }."
        "r := #21:twice.") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "r")) == 42);
    sol_chunk_free(&chunk);

    /* Anything else is data: evaluated once, then simply answered. */
    assert(run(&vm, &chunk,
        "integer:limit := #45:add(#32)."
        "a := #1:limit. b := #99:limit.") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "a")) == 77);
    assert(SOL_AS_INT(global(&vm, "b")) == 77);
    sol_chunk_free(&chunk);

    sol_vm_free(&vm);
}

/* The payoff of `:=` evaluating: a method can be computed rather than written
   out, because by the time it is bound it is just a value. */
static void test_a_method_can_be_constructed(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    /* A block that answers a block. `self` inside the inner one is the receiver
       of whatever ends up sending it, not of the block that built it. */
    assert(run(&vm, &chunk,
        "maker := { { self:mul(#2) } }."
        "integer:double := maker:value()."
        "r := #21:double.") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "r")) == 42);
    sol_chunk_free(&chunk);

    /* Choosing an implementation at run time. */
    assert(run(&vm, &chunk,
        "fast := true."
        "integer:scale := fast:ifElse({ { self:mul(#2) } }, { { self:add(self) } })."
        "a := #21:scale."
        "fast := false."
        "integer:scale := fast:ifElse({ { self:mul(#2) } }, { { self:add(self) } })."
        "b := #21:scale.") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "a")) == 42);
    assert(SOL_AS_INT(global(&vm, "b")) == 42);   /* same answer, different body */
    sol_chunk_free(&chunk);

    /* A block bound under two names is one value, reachable through both. */
    assert(run(&vm, &chunk,
        "body := { self:add(#1) }."
        "integer:inc := body."
        "integer:bump := body."
        "x := #10:inc. y := #10:bump.") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "x")) == 11);
    assert(SOL_AS_INT(global(&vm, "y")) == 11);
    sol_chunk_free(&chunk);

    sol_vm_free(&vm);
}

/* Capture chains one frame at a time, so a name several blocks out is still
   reachable -- and writable. */
static void test_capture_chains_through_nesting(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "integer:deep := { | n |"
        "    n := self."
        "    { { { n := n:add(#1) }:value() }:value() }:value()."
        "    n"
        "}."
        "r := #10:deep.") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "r")) == 11);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* Binding a slot needs an object; a value has no slots of its own. */
static void test_binding_needs_an_object(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk, "x := #1. x:frob := { #2 }.") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);

    assert(run(&vm, &chunk, "self:frob := { #2 }.") == SOL_COMPILE_ERROR);
    sol_chunk_free(&chunk);

    sol_vm_free(&vm);
}

int main(void)
{
    test_a_slot_holds_whatever_it_is_given();
    test_a_method_can_be_constructed();
    test_capture_chains_through_nesting();
    test_binding_needs_an_object();
    test_a_method_updates_a_global();
    test_declared_temporaries_stay_local();
    test_methods_cannot_invent_globals();
    test_duplicate_declaration_is_rejected();
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
