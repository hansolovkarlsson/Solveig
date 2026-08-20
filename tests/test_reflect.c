/* Reflection: asking an object what it is and what it understands. */
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

static bool is_symbol(SolValue value, const char *expected)
{
    if (!SOL_IS_SYMBOL(value)) return false;
    const SolSymbol *s = SOL_AS_SYMBOL(value);
    return s->length == (int)strlen(expected) &&
           memcmp(s->chars, expected, (size_t)s->length) == 0;
}

/* The names come back in the order they were defined, not the order the slot
   list happens to keep them in -- which is the reverse. */
static void test_slots_are_in_definition_order(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "p := object:new. p:x := #1. p:y := #2. p:show := { #0 }. s := p:slots.")
        == SOL_OK);

    SolValue s = global(&vm, "s");
    assert(SOL_IS_ARRAY(s));
    const SolArray *names = SOL_AS_ARRAY(s);
    assert(names->count == 3);
    assert(is_symbol(names->items[0], "x"));
    assert(is_symbol(names->items[1], "y"));
    assert(is_symbol(names->items[2], "show"));

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  slots are in definition order\n");
}

/* Own slots only. An inherited name is not one of yours, and `parent:slots`
   is how you ask about those. */
static void test_slots_are_not_inherited(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "base := object:new. base:a := #1. base:b := #2."
        "kid := base:new. kid:c := #3."
        "mine := kid:slots. theirs := kid:parent:slots.") == SOL_OK);

    assert(SOL_AS_ARRAY(global(&vm, "mine"))->count == 1);
    assert(is_symbol(SOL_AS_ARRAY(global(&vm, "mine"))->items[0], "c"));
    assert(SOL_AS_ARRAY(global(&vm, "theirs"))->count == 2);

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  slots are own, not inherited\n");
}

/* The array is built while symbols are being interned, and interning allocates.
   Under stress every one of those allocations collects. */
static void test_slots_survives_collection(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;
    vm.gc_stress = true;

    assert(run(&vm, &chunk,
        "p := object:new."
        "p:alpha := #1. p:beta := #2. p:gamma := #3. p:delta := #4."
        "n := p:slots:size. first := p:slots:at(#1). last := p:slots:at(#4).")
        == SOL_OK);

    assert(SOL_AS_INT(global(&vm, "n")) == 4);
    assert(is_symbol(global(&vm, "first"), "alpha"));
    assert(is_symbol(global(&vm, "last"), "delta"));

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  slots survives collection mid-build\n");
}

static void test_is_kind_of(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "base := object:new. kid := base:new. grand := kid:new."
        "a := grand:isKindOf(base). b := grand:isKindOf(kid)."
        "c := base:isKindOf(grand). d := grand:isKindOf(grand)."
        /* A value answers for the class it dispatches to. */
        "e := #45:isKindOf(integer). f := #45:isKindOf(string)."
        "g := 'sym:isKindOf(symbol). h := \"s\":isKindOf(string).") == SOL_OK);

    assert(SOL_AS_BOOL(global(&vm, "a")) == true);
    assert(SOL_AS_BOOL(global(&vm, "b")) == true);
    assert(SOL_AS_BOOL(global(&vm, "c")) == false);
    assert(SOL_AS_BOOL(global(&vm, "d")) == true);
    assert(SOL_AS_BOOL(global(&vm, "e")) == true);
    assert(SOL_AS_BOOL(global(&vm, "f")) == false);
    assert(SOL_AS_BOOL(global(&vm, "g")) == true);
    assert(SOL_AS_BOOL(global(&vm, "h")) == true);

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  isKindOf walks the delegation chain\n");
}

static void test_responds_to(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "base := object:new. base:greet := { #1 }. kid := base:new."
        /* Inherited counts: the question is whether a send would land. */
        "a := kid:respondsTo('greet). b := kid:respondsTo('nope)."
        /* So do the built-in messages -- they are slots too. */
        "c := #45:respondsTo('add). d := #45:respondsTo('concat).") == SOL_OK);

    assert(SOL_AS_BOOL(global(&vm, "a")) == true);
    assert(SOL_AS_BOOL(global(&vm, "b")) == false);
    assert(SOL_AS_BOOL(global(&vm, "c")) == true);
    assert(SOL_AS_BOOL(global(&vm, "d")) == false);

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  respondsTo includes inherited and built-in\n");
}

static void test_perform(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "p := object:new. p:n := #10. p:twice := { self:n:mul(#2) }."
        "a := p:perform('twice)."
        "b := #45:perform('add, #5)."
        "c := \"ab\":perform('concat, \"cd\")."
        /* The name can be computed, which is the point of it. */
        "which := 'sub. d := #10:perform(which, #3)."
        /* And perform is itself a message. */
        "e := p:perform('perform, 'twice).") == SOL_OK);

    assert(SOL_AS_INT(global(&vm, "a")) == 20);
    assert(SOL_AS_INT(global(&vm, "b")) == 50);
    assert(SOL_IS_STRING(global(&vm, "c")));
    assert(SOL_AS_INT(global(&vm, "d")) == 7);
    assert(SOL_AS_INT(global(&vm, "e")) == 20);

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  perform sends a name decided at run time\n");
}

/* A slot holding a block is a method, so this is the only way to get at one as
   a value. The block comes back unbound -- `self` is supplied by a send, and
   fetching is not a send. */
static void test_slot_at(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "p := object:new. p:n := #7. p:show := { #1 }."
        "v := p:slotAt('n). m := p:slotAt('show)."
        /* Inherited, like a send. */
        "kid := p:new. k := kid:slotAt('n).") == SOL_OK);

    assert(SOL_AS_INT(global(&vm, "v")) == 7);
    assert(SOL_IS_BLOCK(global(&vm, "m")));
    assert(SOL_AS_INT(global(&vm, "k")) == 7);

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  slotAt answers the value, method blocks included\n");
}

static void test_errors(void)
{
    struct { const char *source; const char *why; } cases[] = {
        { "object:new:perform(\"greet\").",  "a selector must be a symbol" },
        { "object:new:respondsTo(\"x\").",   "so must the name asked about" },
        { "object:new:slotAt(\"x\").",       "and the one fetched" },
        { "object:new:perform().",           "perform needs a name" },
        { "#45:slots.",                      "only an object has slots" },
        { "#45:slotAt('add).",               "and only an object has slotAt" },
        { "integer:slotAt('add).",           "a primitive has no value" },
        { "object:new:slotAt('nope).",       "an absent slot is an error" },
        { "#45:isKindOf(#45).",              "isKindOf wants a class" },
        { "object:new:slots(#1).",           "slots takes nothing" },
    };

    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        SolVM vm; sol_vm_init(&vm);
        SolChunk chunk;
        assert(run(&vm, &chunk, cases[i].source) == SOL_RUNTIME_ERROR);
        sol_chunk_free(&chunk); sol_vm_free(&vm);
        printf("  rejected: %s\n", cases[i].why);
    }
}

/* ---- boundTo: calling the method you fetched ---------------------------- */

/* The gap 2.14 recorded: slotAt answers the plain block, so `self` inside it is
   whatever it was where the block was written -- nil, for a method written at
   the top level. boundTo chooses one. */
static void test_bound_to_supplies_self(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "point := object:new. point:x := #3. point:y := #4."
        "point:sum := { self:x:add(self:y) }."
        "p := point:new. p:x := #10."
        "m := point:slotAt('sum)."
        "bound := m:boundTo(p)."
        "answer := bound:value."
        /* Sending it as a method still answers the same thing. */
        "sent := p:sum.") == SOL_OK);

    assert(SOL_AS_INT(global(&vm, "answer")) == 14);
    assert(SOL_AS_INT(global(&vm, "sent")) == 14);

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  a fetched method answers the same bound as it does sent\n");
}

/* Binding answers a second block; it does not reach into the first. */
static void test_bound_to_does_not_mutate(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "b := { self }."
        "p := object:new."
        "c := b:boundTo(p)."
        "still_nil := b:value:equals(nil)."       /* the original is untouched */
        "bound_ok := c:value:equals(p)."
        "distinct := c:equals(b):not."
        /* Binding a bound block binds again, and leaves the middle one alone. */
        "d := c:boundTo(#2)."
        "rebound := d:value. middle := c:value:equals(p).") == SOL_OK);

    assert(SOL_AS_BOOL(global(&vm, "still_nil")));
    assert(SOL_AS_BOOL(global(&vm, "bound_ok")));
    assert(SOL_AS_BOOL(global(&vm, "distinct")));
    assert(SOL_AS_INT(global(&vm, "rebound")) == 2);
    assert(SOL_AS_BOOL(global(&vm, "middle")));

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  binding answers a new block and leaves the old one alone\n");
}

/* Arguments still belong to the block, which is the reason for answering a
   block rather than calling it: `value` means exactly what it always meant. */
static void test_bound_to_leaves_arity_alone(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "integer:poly := { a, b | self:mul(a):add(b) }."
        "m := integer:slotAt('poly):boundTo(#10)."
        "answer := m:value(#3, #7).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "answer")) == 37);
    sol_chunk_free(&chunk); sol_vm_free(&vm);

    /* Too few is the block's own arity error, not a receiver going missing. */
    SolVM vm2; sol_vm_init(&vm2);
    SolChunk chunk2;
    assert(run(&vm2, &chunk2,
        "integer:poly := { a, b | self:mul(a):add(b) }."
        "integer:slotAt('poly):boundTo(#10):value(#3).") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk2); sol_vm_free(&vm2);

    printf("  the block keeps its own arity; the receiver is not an argument\n");
}

/* Any value can be the receiver, since `self` can be any value. */
static void test_bound_to_takes_any_receiver(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "f := { x | self:add(x) }."
        "a := f:boundTo(#3):value(#4)."
        "g := { self:size }."
        "b := g:boundTo(\"hello\"):value."
        "c := g:boundTo([#1, #2, #3]):value.") == SOL_OK);

    assert(SOL_AS_INT(global(&vm, "a")) == 7);
    assert(SOL_AS_INT(global(&vm, "b")) == 5);
    assert(SOL_AS_INT(global(&vm, "c")) == 3);

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  a receiver may be any value, as self may be\n");
}

/* Binding chooses a receiver, not a lifetime. A block that reads its home frame
   is no freer for having been bound (3.1). */
static void test_bound_to_does_not_lift_the_frame_restriction(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "f := { | t | t := #5. { t:add(#1) } }."
        "escaped := f:value."
        "escaped:boundTo(#1):value.") == SOL_RUNTIME_ERROR);

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  a bound block still cannot outlive the frame it captured\n");
}

/* A send supplies its own receiver, which is what makes an installed block a
   method -- so installing a bound one does not smuggle its receiver past the
   send. Worth pinning: it is the one place binding looks like it should win
   and does not. */
static void test_a_send_still_overrides_a_binding(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "a := object:new. a:tag := #9."
        "m := { self:tag }."
        "bound := m:boundTo(a)."
        "b := object:new. b:tag := #1. b:show := bound."
        "sent := b:show."                 /* the send wins: b, not a */
        "called := bound:value.") == SOL_OK);   /* called directly: a */

    assert(SOL_AS_INT(global(&vm, "sent")) == 1);
    assert(SOL_AS_INT(global(&vm, "called")) == 9);

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  a send overrides a binding; calling one directly keeps it\n");
}

/* boundTo allocates, so it can collect. The receiver and the block are both on
   the value stack while the primitive runs, which is why it needs no temp root
   -- and this is what would catch that reasoning being wrong. */
static void test_bound_to_under_collection(void)
{
    SolVM vm; sol_vm_init(&vm);
    vm.gc_stress = true;
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "point := object:new. point:sum := { self:x:add(self:y) }."
        "m := point:slotAt('sum)."
        "total := #0. i := #0."
        "{ i:lessThan(#100) }:whileTrue({"
        "    p := point:new. p:x := i. p:y := #1."
        "    total := total:add(m:boundTo(p):value)."
        "    i := i:add(#1)."
        "}).") == SOL_OK);

    /* sum of 0..99, plus 1 a hundred times */
    assert(SOL_AS_INT(global(&vm, "total")) == 4950 + 100);

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  100 bindings under GC stress, each answering correctly\n");
}

int main(void)
{
    printf("reflection\n");
    test_slots_are_in_definition_order();
    test_slots_are_not_inherited();
    test_slots_survives_collection();
    test_is_kind_of();
    test_responds_to();
    test_perform();
    test_slot_at();
    test_bound_to_supplies_self();
    test_bound_to_does_not_mutate();
    test_bound_to_leaves_arity_alone();
    test_bound_to_takes_any_receiver();
    test_bound_to_does_not_lift_the_frame_restriction();
    test_a_send_still_overrides_a_binding();
    test_bound_to_under_collection();
    test_errors();
    printf("ok\n");
    return 0;
}
