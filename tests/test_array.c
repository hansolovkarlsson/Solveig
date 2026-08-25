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

static bool is_text(SolValue value, const char *expected)
{
    if (!SOL_IS_STRING(value)) return false;
    const SolString *s = SOL_AS_STRING(value);
    return s->length == (int)strlen(expected) &&
           memcmp(s->chars, expected, (size_t)s->length) == 0;
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
        "r := a:atPut(#2, #99)."
        "v := a:at(#2). n := a:size.") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "v")) == 99);
    assert(SOL_AS_INT(global(&vm, "r")) == 99);   /* answers the value stored */
    assert(SOL_AS_INT(global(&vm, "n")) == 3);    /* atPut does not grow */
    sol_chunk_free(&chunk);

    /* add answers the array, so it chains. */
    assert(run(&vm, &chunk,
        "b := array:new."
        "b:add(#1):add(#2):add(#3)."
        "n := b:size. last := b:at(#3).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "n")) == 3);
    assert(SOL_AS_INT(global(&vm, "last")) == 3);
    sol_chunk_free(&chunk);

    assert(run(&vm, &chunk, "array:new:atPut(#1, #5).") == SOL_RUNTIME_ERROR);
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
        "b:atPut(#1, #99)."
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
    sol_chunk_free(&chunk);        /* the next `run` inits over it */

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
        "p:atPut(#1, #99)."
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

/* The fourth iteration message. `do` throws its answers away and `collect` and
   `select` each answer an array; every reduction to a single value used to be a
   `do` with an accumulator declared outside it. */
static void test_inject(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "sum := [#1, #2, #3, #4]:inject(#0, { total, n | total:add(n) })."
        "product := [#2, #3, #4]:inject(#1, { total, n | total:mul(n) }).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "sum")) == 10);
    assert(SOL_AS_INT(global(&vm, "product")) == 24);
    sol_chunk_free(&chunk);

    /* An empty array answers the start without calling the block, which is what
       makes a fold safe to write without asking first whether there is one. */
    assert(run(&vm, &chunk,
        "empty := []:inject(#7, { total, n | total:add(#1000) })."
        "calls := #0."
        "[]:inject(#0, { total, n | calls := calls:add(#1). total }).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "empty")) == 7);
    assert(SOL_AS_INT(global(&vm, "calls")) == 0);
    sol_chunk_free(&chunk);

    /* The accumulated value may be any type, and need not be the element's. */
    assert(run(&vm, &chunk,
        "text := [#1, #2, #3]:inject(\"\", { s, n | s:concat(n:asString) })."
        "doubled := [#1, #2, #3]:inject([], { acc, n | acc:add(n:mul(#2)) })."
        "size := doubled:size. third := doubled:at(#3).") == SOL_OK);
    assert(is_text(global(&vm, "text"), "123"));
    assert(SOL_AS_INT(global(&vm, "size")) == 3);
    assert(SOL_AS_INT(global(&vm, "third")) == 6);
    sol_chunk_free(&chunk);

    /* Left to right, which a non-commutative fold is the only way to see. */
    assert(run(&vm, &chunk,
        "order := [\"a\", \"b\", \"c\"]:inject(\"\", { s, e | s:concat(e) }).") == SOL_OK);
    assert(is_text(global(&vm, "order"), "abc"));
    sol_chunk_free(&chunk);

    /* Unlike `do`, it is a value, so it can stand in the middle of an
       expression rather than only at the top of a frame. */
    assert(run(&vm, &chunk,
        "big := [#1, #2, #3]:inject(#0, { t, n | t:add(n) }):greaterThan(#5).") == SOL_OK);
    assert(SOL_AS_BOOL(global(&vm, "big")) == true);
    sol_chunk_free(&chunk);

    assert(run(&vm, &chunk, "[#1]:inject(#0).") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);
    assert(run(&vm, &chunk, "[#1]:inject(#0, #1).") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);
    assert(run(&vm, &chunk, "[#1]:inject(#0, { n | n }).") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);

    sol_vm_free(&vm);
}

/* The accumulated value is a fresh string at every step and nothing else refers
   to it. A collection between the steps must not take it. */
static void test_inject_survives_collection(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "words := [\"alpha\", \"beta\", \"gamma\", \"delta\", \"epsilon\"]."
        "joined := words:inject(\"\", { acc, w | acc:concat(w):concat(\"-\") }).") == SOL_OK);
    sol_gc_collect(&vm);
    assert(is_text(global(&vm, "joined"), "alpha-beta-gamma-delta-epsilon-"));

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* `join` is `split` backwards, and the round trip is why `split` keeps its
   empty pieces. */
static void test_join(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "plain := [\"a\", \"b\", \"c\"]:join(\",\")."
        "gap := [\"a\", \"\", \"b\"]:join(\",\")."
        "wide := [\"a\", \"b\"]:join(\"--\").") == SOL_OK);
    assert(is_text(global(&vm, "plain"), "a,b,c"));
    assert(is_text(global(&vm, "gap"), "a,,b"));
    assert(is_text(global(&vm, "wide"), "a--b"));
    sol_chunk_free(&chunk);

    /* No separator goes anywhere there is not a pair to go between. */
    assert(run(&vm, &chunk,
        "none := []:join(\",\")."
        "one := [\"only\"]:join(\",\").") == SOL_OK);
    assert(is_text(global(&vm, "none"), ""));
    assert(is_text(global(&vm, "one"), "only"));
    sol_chunk_free(&chunk);

    /* An empty separator is allowed, where `split` refuses one: nothing cannot
       be looked for, but putting nothing between pieces is concatenation. */
    assert(run(&vm, &chunk, "joined := [\"a\", \"b\", \"c\"]:join(\"\").") == SOL_OK);
    assert(is_text(global(&vm, "joined"), "abc"));
    sol_chunk_free(&chunk);

    /* The round trip, for every shape `split` can answer. */
    assert(run(&vm, &chunk,
        "a := \"a,,b\":split(\",\"):join(\",\")."
        "b := \",a,\":split(\",\"):join(\",\")."
        "c := \"\":split(\",\"):join(\",\")."
        "d := \"abc\":split(\",\"):join(\",\")."
        "e := \"a--b--c\":split(\"--\"):join(\"--\").") == SOL_OK);
    assert(is_text(global(&vm, "a"), "a,,b"));
    assert(is_text(global(&vm, "b"), ",a,"));
    assert(is_text(global(&vm, "c"), ""));
    assert(is_text(global(&vm, "d"), "abc"));
    assert(is_text(global(&vm, "e"), "a--b--c"));
    sol_chunk_free(&chunk);

    /* Strict about what it joins: rendering is what `asString` is for. */
    assert(run(&vm, &chunk, "[\"a\", #1]:join(\",\").") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);
    assert(run(&vm, &chunk, "[nil]:join(\",\").") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);
    assert(run(&vm, &chunk, "[\"a\"]:join(#1).") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);
    assert(run(&vm, &chunk, "[\"a\"]:join.") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);

    sol_vm_free(&vm);
}

/* `copyFrom` is the string's rule, exactly: both ends included, both one-based,
   and out of range is an error. Two collections disagreeing about what a slice
   means would be worse than either rule is good. */
static void test_copy_from(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "a := [#1, #2, #3, #4, #5]."
        "mid := a:copyFrom(#2, #4). all := a:copyFrom(#1, #5)."
        "one := a:copyFrom(#3, #3)."
        "n := mid:size. first := mid:at(#1). last := mid:at(#3)."
        "whole := all:size. single := one:size."
        /* the receiver is untouched, as collect and select leave it */
        "source := a:size."
        /* and it is a copy: changing one does not change the other */
        "mid:atPut(#1, #99). unchanged := a:at(#2).") == SOL_OK);

    assert(SOL_AS_INT(global(&vm, "n")) == 3);
    assert(SOL_AS_INT(global(&vm, "first")) == 2);
    assert(SOL_AS_INT(global(&vm, "last")) == 4);
    assert(SOL_AS_INT(global(&vm, "whole")) == 5);
    assert(SOL_AS_INT(global(&vm, "single")) == 1);
    assert(SOL_AS_INT(global(&vm, "source")) == 5);
    assert(SOL_AS_INT(global(&vm, "unchanged")) == 2);
    sol_chunk_free(&chunk);

    /* An empty slice has one spelling: `to` exactly one before `from`. */
    assert(run(&vm, &chunk,
        "a := [#1, #2, #3]."
        "front := a:copyFrom(#1, #0):size."
        "back := a:copyFrom(#4, #3):size."
        "middle := a:copyFrom(#2, #1):size."
        "nothing := []:copyFrom(#1, #0):size.") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "front")) == 0);
    assert(SOL_AS_INT(global(&vm, "back")) == 0);
    assert(SOL_AS_INT(global(&vm, "middle")) == 0);
    assert(SOL_AS_INT(global(&vm, "nothing")) == 0);
    sol_chunk_free(&chunk);

    static const char *refused[] = {
        "[#1, #2, #3]:copyFrom(#0, #2).",     /* before the start */
        "[#1, #2, #3]:copyFrom(#5, #5).",     /* more than one past the end */
        "[#1, #2, #3]:copyFrom(#1, #4).",     /* past the end */
        "[#1, #2, #3]:copyFrom(#3, #1).",     /* wider than empty, backwards */
        "[#1, #2, #3]:copyFrom(1.0, #2).",
        "[#1, #2, #3]:copyFrom(#1).",
    };
    for (size_t i = 0; i < sizeof(refused) / sizeof(refused[0]); i++) {
        assert(run(&vm, &chunk, refused[i]) == SOL_RUNTIME_ERROR);
        sol_chunk_free(&chunk);
    }

    sol_vm_free(&vm);
}

/* `first` and `last` **clamp** where `copyFrom` refuses, and that is two rules
   on purpose: `copyFrom` names positions, where being outside the array is a
   program wrong about something, and `first` names a quantity -- give me the
   top five -- which a list of three has answered correctly by handing over
   three. Refusing there would make every ranked report check the size first. */
static void test_first_and_last_clamp(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "a := [#1, #2, #3, #4, #5]."
        "top := a:first(#2). tail := a:last(#2)."
        "topFirst := top:at(#1). topLast := top:at(#2)."
        "tailFirst := tail:at(#1). tailLast := tail:at(#2)."
        /* more than there is answers everything there is */
        "allFirst := a:first(#99):size. allLast := a:last(#99):size."
        /* exactly as many is the whole thing too */
        "exact := a:first(#5):size."
        "none := a:first(#0):size. noneLast := a:last(#0):size."
        "empty := []:first(#3):size.") == SOL_OK);

    assert(SOL_AS_INT(global(&vm, "topFirst")) == 1);
    assert(SOL_AS_INT(global(&vm, "topLast")) == 2);
    assert(SOL_AS_INT(global(&vm, "tailFirst")) == 4);
    assert(SOL_AS_INT(global(&vm, "tailLast")) == 5);
    assert(SOL_AS_INT(global(&vm, "allFirst")) == 5);
    assert(SOL_AS_INT(global(&vm, "allLast")) == 5);
    assert(SOL_AS_INT(global(&vm, "exact")) == 5);
    assert(SOL_AS_INT(global(&vm, "none")) == 0);
    assert(SOL_AS_INT(global(&vm, "noneLast")) == 0);
    assert(SOL_AS_INT(global(&vm, "empty")) == 0);
    sol_chunk_free(&chunk);

    /* Clamping is for asking for more than there is, not for nonsense. */
    static const char *refused[] = {
        "[#1, #2]:first(#0:sub(#1)).",
        "[#1, #2]:last(#0:sub(#1)).",
        "[#1, #2]:first(1.0).",
        "[#1, #2]:first.",
        "[#1, #2]:first(#1, #2).",
    };
    for (size_t i = 0; i < sizeof(refused) / sizeof(refused[0]); i++) {
        assert(run(&vm, &chunk, refused[i]) == SOL_RUNTIME_ERROR);
        sol_chunk_free(&chunk);
    }

    sol_vm_free(&vm);
}

/* A slice is a fresh array of fresh-nothing: the elements are shared, since an
   array holds references and copying it copies those. So a slice of an array of
   arrays sees the same inner arrays, and a collection must not lose them. */
static void test_a_slice_shares_its_elements(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "inner := [#1, #2]."
        "outer := [inner, [#3], [#4]]."
        "head := outer:first(#1)."
        "same := head:at(#1):equals(inner)."
        /* the slice is a different array from the one it came out of */
        "distinct := head:equals(outer):not.") == SOL_OK);
    assert(SOL_AS_BOOL(global(&vm, "same")));
    assert(SOL_AS_BOOL(global(&vm, "distinct")));
    sol_chunk_free(&chunk);        /* the next `run` inits over it */

    sol_gc_collect(&vm);
    assert(run(&vm, &chunk, "still := head:at(#1):at(#2).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "still")) == 2);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* `add` puts one on the end and `removeLast` takes it off, which is what makes
   an array a stack. An empty one refuses rather than answering nil, the same
   choice `at` makes about an index out of range. */
static void test_remove_last(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "xs := [#1, #2, #3]."
        "last := xs:removeLast."
        "left := xs:size."
        "still := xs:at(#2)."
        "again := xs:removeLast."
        "one := xs:size.") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "last")) == 3);
    assert(SOL_AS_INT(global(&vm, "left")) == 2);
    assert(SOL_AS_INT(global(&vm, "still")) == 2);
    assert(SOL_AS_INT(global(&vm, "again")) == 2);
    assert(SOL_AS_INT(global(&vm, "one")) == 1);
    sol_chunk_free(&chunk);

    /* Down to empty and then refused. */
    assert(run(&vm, &chunk, "xs := [#1]. xs:removeLast. n := xs:size.") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "n")) == 0);
    sol_chunk_free(&chunk);

    assert(run(&vm, &chunk, "array:new:removeLast.") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);

    /* And what comes off can be put back, which is the round trip a stack is. */
    assert(run(&vm, &chunk,
        "xs := [#1, #2]. xs:add(xs:removeLast). n := xs:size."
        "top := xs:at(#2).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "n")) == 2);
    assert(SOL_AS_INT(global(&vm, "top")) == 2);
    sol_chunk_free(&chunk);

    sol_vm_free(&vm);
}

/* `indexOf` answers a one-based position or nil, the shape `string:indexOf`
   has. Equality is the language's: by content for values, by identity for the
   references. */
static void test_index_of(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "a := [\"a\", \"b\", \"c\"]:indexOf(\"b\")."
        "b := [\"a\", \"b\", \"c\"]:indexOf(\"z\")."
        "c := [#1, #2]:indexOf(#1)."
        "d := [#1, #2, #1]:indexOf(#1)."          /* the first one wins */
        "e := array:new:indexOf(#1)."
        "f := [nil, #1]:indexOf(nil)."
        "g := ['x, 'y]:indexOf('y).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "a")) == 2);
    assert(SOL_IS_NIL(global(&vm, "b")));
    assert(SOL_AS_INT(global(&vm, "c")) == 1);
    assert(SOL_AS_INT(global(&vm, "d")) == 1);
    assert(SOL_IS_NIL(global(&vm, "e")));
    assert(SOL_AS_INT(global(&vm, "f")) == 1);
    assert(SOL_AS_INT(global(&vm, "g")) == 2);
    sol_chunk_free(&chunk);

    /* A reference is found by identity, which is what `equals` says too. */
    assert(run(&vm, &chunk,
        "same := [#1]."
        "found := [same]:indexOf(same)."
        "alike := [[#1]]:indexOf([#1]).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "found")) == 1);
    assert(SOL_IS_NIL(global(&vm, "alike")));
    sol_chunk_free(&chunk);

    sol_vm_free(&vm);
}

int main(void)
{
    test_collect();
    test_select();
    test_collect_and_select_chain();
    test_inject();
    test_inject_survives_collection();
    test_join();
    test_copy_from();
    test_first_and_last_clamp();
    test_a_slice_shares_its_elements();
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
    test_remove_last();
    test_index_of();
    printf("test_array: ok\n");
    return 0;
}
