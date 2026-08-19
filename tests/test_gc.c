/* The collector: what it reclaims, what it must not, and that it can trace a
 * graph deeper than the C stack. */
#include <assert.h>
#include <stdio.h>
#include <string.h>

#include "solas/compiler.h"
#include "solum/gc.h"
#include "solum/vm.h"

/* Chunks must outlive the run: a slot holds a pointer to code the chunk owns. */
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

/* A block bound to nothing is garbage once the statement ends. */
static void test_unreachable_blocks_are_reclaimed(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    sol_gc_collect(&vm);
    int baseline = sol_gc_live_count(&vm);

    /* 500 blocks, none of them kept. */
    assert(run(&vm, &chunk,
        "i := #0."
        "{ i:lessThan(#500) }:whileTrue({ i := i:add(#1). { #1 }. }).") == SOL_OK);

    sol_gc_collect(&vm);
    int after = sol_gc_live_count(&vm);

    /* The loop's own two blocks are still reachable from the chunk's frame? No --
       the run has finished and the stack is empty, so everything it made is gone.
       Allow a small margin rather than demanding an exact figure. */
    assert(after <= baseline + 8);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* Anything a global can reach must survive, and still work afterwards. */
static void test_reachable_values_survive(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk, "saved := { #42 }.") == SOL_OK);
    assert(SOL_IS_BLOCK(global(&vm, "saved")));

    sol_gc_collect(&vm);
    sol_gc_collect(&vm);                    /* twice, to catch a stale mark bit */

    assert(SOL_IS_BLOCK(global(&vm, "saved")));

    /* The chunk stays alive: it owns the code the block points at, which is what
       1.1b in the roadmap is about. Collecting the block is this test's subject;
       freeing its code is not. */
    SolChunk second;
    assert(run(&vm, &second, "r := saved:value().") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "r")) == 42);

    sol_chunk_free(&second);
    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* A method is a block in a slot, so collecting must not unbind it. */
static void test_methods_survive_collection(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk, "integer:double := { self:mul(#2) }.") == SOL_OK);
    sol_gc_collect(&vm);

    SolChunk second;
    assert(run(&vm, &second, "r := #21:double.") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "r")) == 42);

    sol_chunk_free(&second);
    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* A block's captured receiver is an edge the tracer has to follow. */
static void test_captured_self_is_traced(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    /* `held` captures the integer class object as its self. */
    assert(run(&vm, &chunk,
        "integer:grab := { { self } }."
        "held := integer:grab.") == SOL_OK);
    assert(SOL_IS_BLOCK(global(&vm, "held")));

    sol_gc_collect(&vm);

    SolBlock *block = SOL_AS_BLOCK(global(&vm, "held"));
    assert(SOL_IS_OBJ(block->self));
    assert(SOL_AS_OBJ(block->self) == vm.integer_class);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* Marking uses an explicit worklist, so a graph far deeper than the C stack
   would tolerate must trace without overflowing it. */
static void test_deep_graph_does_not_recurse(void)
{
    SolVM vm; sol_vm_init(&vm);
    /* Immune to SOLUM_GC_STRESS: collecting on each of 200k allocations would be
       quadratic. Depth is this test's subject, not collection frequency. */
    vm.gc_stress = false;

    enum { DEPTH = 200000 };
    SolObject *head = sol_object_new(&vm, NULL);
    sol_object_define(vm.root, "head", SOL_OBJ_VAL(head));

    /* A proto chain 200k long -- recursive marking would die well before this. */
    SolObject *tail = head;
    for (int i = 1; i < DEPTH; i++) {
        SolObject *next = sol_object_new(&vm, NULL);
        tail->proto = next;
        tail = next;
    }

    int before = sol_gc_live_count(&vm);
    assert(before >= DEPTH);

    sol_gc_collect(&vm);

    /* Every link is reachable from the global, so none may be freed. */
    assert(sol_gc_live_count(&vm) == before);

    /* And the chain is still intact end to end. */
    int walked = 0;
    for (SolObject *o = head; o != NULL; o = o->proto) walked++;
    assert(walked == DEPTH);

    sol_vm_free(&vm);
}

/* Collecting on every single allocation must not change any answer. */
static void test_stress_mode_changes_nothing(void)
{
    const char *program =
        "integer:factorial := {"
        "    self:lessThan(#2):ifElse({ #1 }, { self:mul( self:sub(#1):factorial ) })"
        "}."
        "integer:sumTo := { | total, i |"
        "    total := #0. i := #1."
        "    { i:greaterThan(self):not() }:whileTrue({"
        "        total := total:add(i). i := i:add(#1)"
        "    })."
        "    total"
        "}."
        "a := #10:factorial. b := #100:sumTo.";

    for (int stress = 0; stress <= 1; stress++) {
        SolVM vm; sol_vm_init(&vm);
        vm.gc_stress = stress != 0;

        SolChunk chunk;
        assert(run(&vm, &chunk, program) == SOL_OK);
        assert(SOL_AS_INT(global(&vm, "a")) == 3628800);
        assert(SOL_AS_INT(global(&vm, "b")) == 5050);

        sol_chunk_free(&chunk);
        sol_vm_free(&vm);
    }
}

/* The heap must not grow without bound when the garbage outlives nothing. */
static void test_heap_stays_bounded(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "i := #0. b := nil."
        "{ i:lessThan(#20000) }:whileTrue({ i := i:add(#1). b := { #1 }. }).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "i")) == 20000);

    /* 20k blocks were made; only the last is still reachable. */
    assert(sol_gc_live_count(&vm) < 2000);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* Code handed to the collector is reclaimed once nothing refers to it. This is
   what lets Solis compile a line per input line without accumulating chunks. */
static void test_unreferenced_code_is_reclaimed(void)
{
    SolVM vm; sol_vm_init(&vm);

    sol_gc_collect(&vm);
    int baseline = sol_gc_live_count(&vm);

    /* 200 "lines", none of which leaves anything behind. */
    for (int i = 0; i < 200; i++) {
        SolCode *code = sol_code_new(&vm);
        sol_gc_push_temp(&vm, &code->gc);
        assert(sol_compile("x := #1:add(#2).", &code->chunk));
        assert(sol_vm_run(&vm, &code->chunk) == SOL_OK);
        sol_gc_pop_temp(&vm);
    }

    sol_gc_collect(&vm);
    assert(sol_gc_live_count(&vm) <= baseline + 8);

    sol_vm_free(&vm);
}

/* ...but code a live block points into must survive, or the block would be
   running freed bytecode. */
static void test_code_referenced_by_a_block_survives(void)
{
    SolVM vm; sol_vm_init(&vm);

    SolCode *first = sol_code_new(&vm);
    sol_gc_push_temp(&vm, &first->gc);
    assert(sol_compile("integer:double := { self:mul(#2) }. saved := { #42 }.",
                       &first->chunk));
    assert(sol_vm_run(&vm, &first->chunk) == SOL_OK);
    sol_gc_pop_temp(&vm);

    /* Nothing holds `first` now except the two blocks bound above. */
    sol_gc_collect(&vm);
    sol_gc_collect(&vm);

    SolCode *second = sol_code_new(&vm);
    sol_gc_push_temp(&vm, &second->gc);
    assert(sol_compile("a := #21:double. b := saved:value().", &second->chunk));
    assert(sol_vm_run(&vm, &second->chunk) == SOL_OK);
    sol_gc_pop_temp(&vm);

    assert(SOL_AS_INT(global(&vm, "a")) == 42);
    assert(SOL_AS_INT(global(&vm, "b")) == 42);

    sol_vm_free(&vm);
}

/* A temporary root keeps a cell alive across an allocation that would otherwise
   sweep it, since a C local is invisible to the tracer. */
static void test_temp_roots_protect_a_cell(void)
{
    SolVM vm; sol_vm_init(&vm);
    vm.gc_stress = true;                 /* collect on every allocation */

    SolCode *code = sol_code_new(&vm);
    sol_gc_push_temp(&vm, &code->gc);

    /* Allocating now collects, and `code` is reachable only through the temp. */
    SolObject *scratch = sol_object_new(&vm, NULL);
    assert(scratch != NULL);

    /* Still usable: compiling and running it would fault if it had been swept. */
    assert(sol_compile("t := #7.", &code->chunk));
    assert(sol_vm_run(&vm, &code->chunk) == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "t")) == 7);

    sol_gc_pop_temp(&vm);
    sol_vm_free(&vm);
}

int main(void)
{
    test_unreferenced_code_is_reclaimed();
    test_code_referenced_by_a_block_survives();
    test_temp_roots_protect_a_cell();
    test_unreachable_blocks_are_reclaimed();
    test_reachable_values_survive();
    test_methods_survive_collection();
    test_captured_self_is_traced();
    test_deep_graph_does_not_recurse();
    test_stress_mode_changes_nothing();
    test_heap_stays_bounded();
    printf("test_gc: ok\n");
    return 0;
}
