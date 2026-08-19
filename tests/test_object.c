/* User-defined objects: creation, delegation, and what a "class" turns out to be. */
#include <assert.h>
#include <stdio.h>
#include <string.h>

#include "solas/compiler.h"
#include "solum/gc.h"
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

static void test_new_makes_a_distinct_object(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "a := object:new. b := object:new."
        "same := a:equals(a). other := a:equals(b).") == SOL_OK);
    assert(SOL_IS_OBJ(global(&vm, "a")));
    assert(SOL_IS_OBJ(global(&vm, "b")));
    assert(SOL_AS_OBJ(global(&vm, "a")) != SOL_AS_OBJ(global(&vm, "b")));
    assert(SOL_AS_BOOL(global(&vm, "same")) == true);
    assert(SOL_AS_BOOL(global(&vm, "other")) == false);   /* identity, not shape */

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* A slot on the prototype is a default every instance sees. */
static void test_slots_are_inherited(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "point := object:new."
        "point:x := #0. point:y := #0."
        "p := point:new."
        "px := p:x. py := p:y.") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "px")) == 0);
    assert(SOL_AS_INT(global(&vm, "py")) == 0);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* Assigning on an instance makes the instance's own slot rather than writing
   through to the prototype -- otherwise one instance would change all of them. */
static void test_assignment_shadows_rather_than_writes_through(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "base := object:new. base:v := #1."
        "a := base:new. b := base:new."
        "a:v := #99."
        "av := a:v. bv := b:v. basev := base:v.") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "av")) == 99);
    assert(SOL_AS_INT(global(&vm, "bv")) == 1);
    assert(SOL_AS_INT(global(&vm, "basev")) == 1);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* A method is a slot holding a block, and `self` is whoever was sent to. */
static void test_methods_receive_the_instance_as_self(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "point := object:new."
        "point:x := #0. point:y := #0."
        "point:sum := { self:x:add(self:y) }."
        "point:make := { a, b | | p | p := self:new. p:x := a. p:y := b. p }."
        "p := point:make(#3, #4)."
        "s := p:sum."
        "d := point:new:sum.") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "s")) == 7);
    assert(SOL_AS_INT(global(&vm, "d")) == 0);   /* the defaults still apply */

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* Delegation chains, and a nearer slot wins. */
static void test_inheritance_and_override(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "animal := object:new."
        "animal:name := \"animal\". animal:speak := { \"...\" }."
        "animal:describe := { self:name:concat(\" says \"):concat(self:speak) }."
        "dog := animal:new."
        "dog:name := \"dog\". dog:speak := { \"woof\" }."
        "rex := dog:new. rex:name := \"rex\"."
        "a := animal:describe. d := dog:describe. r := rex:describe.") == SOL_OK);

    const SolString *a = SOL_AS_STRING(global(&vm, "a"));
    const SolString *d = SOL_AS_STRING(global(&vm, "d"));
    const SolString *r = SOL_AS_STRING(global(&vm, "r"));
    assert(memcmp(a->chars, "animal says ...", 15) == 0);
    assert(memcmp(d->chars, "dog says woof", 13) == 0);
    /* `describe` comes from animal, `speak` from dog, `name` from rex. */
    assert(memcmp(r->chars, "rex says woof", 13) == 0);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* The default `print` is a fallback, not a fixture. */
static void test_print_can_be_overridden(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "thing := object:new."
        "thing:print := { \"a thing\" }."
        "r := thing:new:print.") == SOL_OK);
    assert(SOL_IS_STRING(global(&vm, "r")));

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

static void test_errors(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    /* A value is not an object and has no slots of its own. */
    assert(run(&vm, &chunk, "#1:new.") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);
    assert(run(&vm, &chunk, "x := #1. x:field := #2.") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);

    /* An object understands only what it or its prototypes hold. */
    assert(run(&vm, &chunk, "object:new:nosuch.") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);

    sol_vm_free(&vm);
}

/* An object's slots and its prototype are both tracing edges. */
static void test_objects_are_collected(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "point := object:new."
        "point:label := \"origin\"."
        "kept := point:new."
        "kept:tag := [\"a\", \"b\"].") == SOL_OK);

    sol_gc_collect(&vm);
    sol_gc_collect(&vm);

    /* Reached through the instance's own slot, and through its prototype. */
    SolChunk second;
    assert(run(&vm, &second,
        "n := kept:tag:size. l := kept:label.") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "n")) == 2);
    assert(SOL_IS_STRING(global(&vm, "l")));
    sol_chunk_free(&second);

    /* Objects nobody keeps go away. */
    sol_gc_collect(&vm);
    int baseline = sol_gc_live_count(&vm);
    SolChunk third;
    assert(run(&vm, &third,
        "i := #0."
        "{ i:lessThan(#300) }:whileTrue({ i := i:add(#1). object:new. }).") == SOL_OK);
    sol_gc_collect(&vm);
    assert(sol_gc_live_count(&vm) <= baseline + 8);

    sol_chunk_free(&third);
    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

int main(void)
{
    test_new_makes_a_distinct_object();
    test_slots_are_inherited();
    test_assignment_shadows_rather_than_writes_through();
    test_methods_receive_the_instance_as_self();
    test_inheritance_and_override();
    test_print_can_be_overridden();
    test_errors();
    test_objects_are_collected();
    printf("test_object: ok\n");
    return 0;
}
