/* Arrays: one-based access, growth, iteration, and the tracing edge they add. */
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

static void test_of_and_new(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "a := array:of(#10, #20, #30)."
        "e := array:new."
        "n := a:size. m := e:size.") == SOL_OK);

    assert(SOL_IS_ARRAY(global(&vm, "a")));
    assert(SOL_AS_INT(global(&vm, "n")) == 3);
    assert(SOL_AS_INT(global(&vm, "m")) == 0);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* One-based: the first element is #1, and #0 is out of bounds rather than an
   off-by-one that silently reads something. */
static void test_indices_are_one_based(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "a := array:of(#10, #20, #30)."
        "x := a:at(#1). y := a:at(#3).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "x")) == 10);
    assert(SOL_AS_INT(global(&vm, "y")) == 30);
    sol_chunk_free(&chunk);

    assert(run(&vm, &chunk, "array:of(#1, #2):at(#0).") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);

    assert(run(&vm, &chunk, "array:of(#1, #2):at(#3).") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);

    assert(run(&vm, &chunk, "array:new:at(#1).") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);

    /* Strict, like the rest of the language: an index is an integer. */
    assert(run(&vm, &chunk, "array:of(#1, #2):at(1.0).") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);

    sol_vm_free(&vm);
}

static void test_at_put_and_add(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "a := array:of(#1, #2, #3)."
        "r := a:at_put(#2, #99)."
        "v := a:at(#2). n := a:size.") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "v")) == 99);
    assert(SOL_AS_INT(global(&vm, "r")) == 99);   /* answers the value stored */
    assert(SOL_AS_INT(global(&vm, "n")) == 3);    /* at_put does not grow */
    sol_chunk_free(&chunk);

    /* add answers the array, so it chains. */
    assert(run(&vm, &chunk,
        "b := array:new."
        "b:add(#1):add(#2):add(#3)."
        "n := b:size. last := b:at(#3).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "n")) == 3);
    assert(SOL_AS_INT(global(&vm, "last")) == 3);
    sol_chunk_free(&chunk);

    assert(run(&vm, &chunk, "array:new:at_put(#1, #5).") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);

    sol_vm_free(&vm);
}

/* Growth past the initial capacity, which is where the backing store moves. */
static void test_growth(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "a := array:new. i := #0."
        "{ i:lessThan(#500) }:whileTrue({ i := i:add(#1). a:add(i). })."
        "n := a:size. first := a:at(#1). last := a:at(#500).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "n")) == 500);
    assert(SOL_AS_INT(global(&vm, "first")) == 1);
    assert(SOL_AS_INT(global(&vm, "last")) == 500);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

static void test_do_iterates_in_order(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "a := array:of(#1, #2, #3, #4)."
        "sum := #0."
        "a:do({ e | sum := sum:add(e) }).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "sum")) == 10);
    sol_chunk_free(&chunk);

    /* Order, not just the total. */
    assert(run(&vm, &chunk,
        "a := array:of(#1, #2, #3)."
        "acc := #0."
        "a:do({ e | acc := acc:mul(#10):add(e) }).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "acc")) == 123);
    sol_chunk_free(&chunk);

    /* An empty array runs the block zero times, and do answers the array. */
    assert(run(&vm, &chunk,
        "n := #0. r := array:new:do({ e | n := n:add(#1) }).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "n")) == 0);
    assert(SOL_IS_ARRAY(global(&vm, "r")));
    sol_chunk_free(&chunk);

    sol_vm_free(&vm);
}

/* Growing an array while iterating it moves the backing store, so `do` re-reads
   it every pass and bounds the count once. It must not run away or read freed
   memory. */
static void test_do_survives_growth_during_iteration(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "a := array:of(#1, #2, #3)."
        "seen := #0."
        "a:do({ e | seen := seen:add(#1). a:add(e). })."
        "n := a:size.") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "seen")) == 3);   /* the original three only */
    assert(SOL_AS_INT(global(&vm, "n")) == 6);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* Arrays are references, like objects -- two names, one array. */
static void test_arrays_are_references(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "a := array:of(#1, #2)."
        "b := a."
        "b:at_put(#1, #99)."
        "through_a := a:at(#1)."
        "same := a:equals(b)."
        "other := a:equals(array:of(#99, #2)).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "through_a")) == 99);
    assert(SOL_AS_BOOL(global(&vm, "same")) == true);
    /* equals is identity: equal contents are still a different array. */
    assert(SOL_AS_BOOL(global(&vm, "other")) == false);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

static void test_nesting(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "n := array:of(array:of(#1, #2), array:of(#3))."
        "inner := n:at(#1). v := inner:at(#2).") == SOL_OK);
    assert(SOL_IS_ARRAY(global(&vm, "inner")));
    assert(SOL_AS_INT(global(&vm, "v")) == 2);

    /* An array can hold itself; printing is depth-limited, not infinite. */
    assert(run(&vm, &chunk, "s := array:new. s:add(s).") == SOL_OK);
    sol_gc_collect(&vm);                    /* and the cycle must not confuse marking */
    assert(SOL_IS_ARRAY(global(&vm, "s")));

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* The reason arrays came before strings: an element is a tracing edge, so an
   array can be the only thing keeping a value alive. */
static void test_elements_are_traced(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "holder := array:new."
        "holder:add({ #42 }).") == SOL_OK);

    /* The block is reachable only through the array now. */
    sol_gc_collect(&vm);
    sol_gc_collect(&vm);

    SolChunk second;
    assert(run(&vm, &second, "r := holder:at(#1):value().") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "r")) == 42);

    sol_chunk_free(&second);
    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* And an unreachable array, with everything it held, goes away. */
static void test_unreachable_arrays_are_reclaimed(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    sol_gc_collect(&vm);
    int baseline = sol_gc_live_count(&vm);

    assert(run(&vm, &chunk,
        "i := #0."
        "{ i:lessThan(#300) }:whileTrue({ i := i:add(#1). array:of(#1, #2, #3). }).")
        == SOL_OK);

    sol_gc_collect(&vm);
    assert(sol_gc_live_count(&vm) <= baseline + 8);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* `[a, b]` is not merely equivalent to `array:of(a, b)` -- it compiles to the
   same instructions, which is what keeps the two spellings from ever drifting. */
static void test_literal_is_the_same_bytecode(void)
{
    SolChunk sugar, plain;
    sol_chunk_init(&sugar);
    sol_chunk_init(&plain);

    assert(sol_compile("a := [#1, #2, #3].", &sugar));
    assert(sol_compile("a := array:of(#1, #2, #3).", &plain));

    assert(sugar.count == plain.count);
    assert(memcmp(sugar.code, plain.code, (size_t)sugar.count) == 0);
    assert(sugar.names.count == plain.names.count);
    for (int i = 0; i < sugar.names.count; i++) {
        assert(strcmp(sol_chunk_name(&sugar, i), sol_chunk_name(&plain, i)) == 0);
    }

    sol_chunk_free(&plain);
    sol_chunk_free(&sugar);
}

static void test_literals(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "a := [#10, #20, #30]."
        "n := a:size. first := a:at(#1). last := a:at(#3).") == SOL_OK);
    assert(SOL_IS_ARRAY(global(&vm, "a")));
    assert(SOL_AS_INT(global(&vm, "n")) == 3);
    assert(SOL_AS_INT(global(&vm, "first")) == 10);
    assert(SOL_AS_INT(global(&vm, "last")) == 30);
    sol_chunk_free(&chunk);

    /* `[]` answers an empty array. */
    assert(run(&vm, &chunk, "e := []. n := e:size.") == SOL_OK);
    assert(SOL_IS_ARRAY(global(&vm, "e")));
    assert(SOL_AS_INT(global(&vm, "n")) == 0);
    sol_chunk_free(&chunk);

    /* Elements are ordinary expressions, and literals nest. */
    assert(run(&vm, &chunk,
        "x := #5."
        "a := [x, x:add(#1), { #9 }:value()]."
        "p := a:at(#1). q := a:at(#2). r := a:at(#3)."
        "n := [[#1, #2], [#3]]."
        "deep := n:at(#1):at(#2).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "p")) == 5);
    assert(SOL_AS_INT(global(&vm, "q")) == 6);
    assert(SOL_AS_INT(global(&vm, "r")) == 9);
    assert(SOL_AS_INT(global(&vm, "deep")) == 2);
    sol_chunk_free(&chunk);

    sol_vm_free(&vm);
}

/* A literal is a construction, not a pooled constant: every evaluation must
   answer a new array, or two calls would share one and mutating either would be
   visible through the other. */
static void test_each_evaluation_builds_a_fresh_array(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "integer:make := { [#1, #2] }."
        "p := #0:make. q := #0:make."
        "p:at_put(#1, #99)."
        "through_q := q:at(#1)."
        "same := p:equals(q).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "through_q")) == 1);   /* q is untouched */
    assert(SOL_AS_BOOL(global(&vm, "same")) == false);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

static void test_literal_errors(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk, "a := [#1, #2.") == SOL_COMPILE_ERROR);
    sol_chunk_free(&chunk);

    assert(run(&vm, &chunk, "a := [#1, ].") == SOL_COMPILE_ERROR);
    sol_chunk_free(&chunk);

    /* Real desugaring, so the `array` it sends to is the ordinary global. */
    assert(run(&vm, &chunk, "array := #5. a := [#1].") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);

    sol_vm_free(&vm);
}

static void test_collect(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "xs := [#1, #2, #3, #4]."
        "sq := xs:collect({ x | x:mul(x) })."
        "a := sq:at(#1). d := sq:at(#4). n := sq:size."
        "untouched := xs:at(#2)."
        "shared := sq:equals(xs).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "a")) == 1);
    assert(SOL_AS_INT(global(&vm, "d")) == 16);
    assert(SOL_AS_INT(global(&vm, "n")) == 4);
    assert(SOL_AS_INT(global(&vm, "untouched")) == 2);   /* the source is not changed */
    assert(SOL_AS_BOOL(global(&vm, "shared")) == false); /* nor is it reused */
    sol_chunk_free(&chunk);

    assert(run(&vm, &chunk, "n := []:collect({ x | x }):size.") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "n")) == 0);
    sol_chunk_free(&chunk);

    sol_vm_free(&vm);
}

static void test_select(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "xs := [#1, #2, #3, #4, #5]."
        "big := xs:select({ x | x:greaterThan(#2) })."
        "n := big:size. first := big:at(#1). last := big:at(#3).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "n")) == 3);
    assert(SOL_AS_INT(global(&vm, "first")) == 3);
    assert(SOL_AS_INT(global(&vm, "last")) == 5);
    sol_chunk_free(&chunk);

    /* Keeping none and keeping all are the two ends of the count-rewind. */
    assert(run(&vm, &chunk,
        "xs := [#1, #2, #3]."
        "none := xs:select({ x | false }):size."
        "all := xs:select({ x | true }):size.") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "none")) == 0);
    assert(SOL_AS_INT(global(&vm, "all")) == 3);
    sol_chunk_free(&chunk);

    /* Strict, like whileTrue: the block has to answer a boolean. */
    assert(run(&vm, &chunk, "[#1]:select({ x | #1 }).") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);

    assert(run(&vm, &chunk, "[#1]:select(#2).") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);

    sol_vm_free(&vm);
}

static void test_collect_and_select_chain(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "r := [#1, #2, #3, #4, #5]"
        "     :collect({ x | x:mul(#2) })"
        "     :select({ x | x:lessThan(#7) })."
        "n := r:size. last := r:at(#3).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "n")) == 3);
    assert(SOL_AS_INT(global(&vm, "last")) == 6);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* The result array is reachable only from a C local while the block runs, so it
   needs a temporary root. Without one, a block that allocates gets the result
   swept out from under it -- confirmed by removing the root and watching this
   become a use-after-free under GC stress. */
static void test_result_survives_an_allocating_block(void)
{
    SolVM vm; sol_vm_init(&vm);
    vm.gc_stress = true;                 /* collect on every allocation */
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "xs := [#1, #2, #3, #4, #5, #6]."
        "r := xs:collect({ x | [x, x] })."
        "n := r:size. inner := r:at(#6):at(#1).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "n")) == 6);
    assert(SOL_AS_INT(global(&vm, "inner")) == 6);
    sol_chunk_free(&chunk);

    assert(run(&vm, &chunk,
        "xs := [#1, #2, #3, #4, #5, #6]."
        "s := xs:select({ x | { x:greaterThan(#3) }:value() })."
        "n := s:size. first := s:at(#1).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "n")) == 3);
    assert(SOL_AS_INT(global(&vm, "first")) == 4);
    sol_chunk_free(&chunk);

    sol_vm_free(&vm);
}

int main(void)
{
    test_collect();
    test_select();
    test_collect_and_select_chain();
    test_result_survives_an_allocating_block();
    test_literal_is_the_same_bytecode();
    test_literals();
    test_each_evaluation_builds_a_fresh_array();
    test_literal_errors();
    test_of_and_new();
    test_indices_are_one_based();
    test_at_put_and_add();
    test_growth();
    test_do_iterates_in_order();
    test_do_survives_growth_during_iteration();
    test_arrays_are_references();
    test_nesting();
    test_elements_are_traced();
    test_unreachable_arrays_are_reclaimed();
    printf("test_array: ok\n");
    return 0;
}
