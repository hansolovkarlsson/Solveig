/* Sorting: order, stability, and surviving a comparison that calls back in. */
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

/* Asserts an array global holds exactly these integers, in this order. */
static void expect_ints(SolVM *vm, const char *name, const int *want, int n)
{
    SolValue value = global(vm, name);
    assert(SOL_IS_ARRAY(value));
    const SolArray *array = SOL_AS_ARRAY(value);
    assert(array->count == n);
    for (int i = 0; i < n; i++) {
        assert(SOL_IS_INT(array->items[i]));
        assert(SOL_AS_INT(array->items[i]) == want[i]);
    }
}

static void test_orders(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "a := [#3, #1, #2]:sorted."
        "b := []:sorted. c := [#5]:sorted."
        "d := [#2, #2, #1]:sorted."
        /* Already sorted, and exactly reversed. */
        "e := [#1, #2, #3]:sorted. f := [#4, #3, #2, #1]:sorted."
        "g := [#0, #-3, #7, #-9]:sorted.") == SOL_OK);

    expect_ints(&vm, "a", (int[]){1, 2, 3}, 3);
    expect_ints(&vm, "b", NULL, 0);
    expect_ints(&vm, "c", (int[]){5}, 1);
    expect_ints(&vm, "d", (int[]){1, 2, 2}, 3);
    expect_ints(&vm, "e", (int[]){1, 2, 3}, 3);
    expect_ints(&vm, "f", (int[]){1, 2, 3, 4}, 4);
    expect_ints(&vm, "g", (int[]){-9, -3, 0, 7}, 4);

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  orders numbers, including empty and single\n");
}

static void test_orders_other_types(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "s := [\"pear\", \"apple\", \"fig\"]:sorted."
        "f := [3.5, 1.25, 2.0]:sorted:collect({ x | x:asString }).") == SOL_OK);

    const SolArray *s = SOL_AS_ARRAY(global(&vm, "s"));
    assert(memcmp(SOL_AS_STRING(s->items[0])->chars, "apple", 5) == 0);
    assert(memcmp(SOL_AS_STRING(s->items[1])->chars, "fig", 3) == 0);
    assert(memcmp(SOL_AS_STRING(s->items[2])->chars, "pear", 4) == 0);
    assert(SOL_AS_ARRAY(global(&vm, "f"))->count == 3);

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  orders strings and floats\n");
}

/* Like collect and select, this answers a new array. */
static void test_source_is_untouched(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "xs := [#3, #1, #2]. ys := xs:sorted."
        "same := xs:equals(ys).") == SOL_OK);

    expect_ints(&vm, "xs", (int[]){3, 1, 2}, 3);
    expect_ints(&vm, "ys", (int[]){1, 2, 3}, 3);
    assert(SOL_AS_BOOL(global(&vm, "same")) == false);

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  answers a new array, leaving the source alone\n");
}

/* Stability is what makes sorting twice a way to sort by two keys, so it is a
   promise rather than an accident of the algorithm. */
static void test_is_stable(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "p1 := object:new. p1:k := #2. p1:tag := #1."
        "p2 := object:new. p2:k := #1. p2:tag := #2."
        "p3 := object:new. p3:k := #2. p3:tag := #3."
        "p4 := object:new. p4:k := #1. p4:tag := #4."
        "p5 := object:new. p5:k := #2. p5:tag := #5."
        "tags := [p1, p2, p3, p4, p5]"
        "        :sorted({ x, y | x:k:lessThan(y:k) })"
        "        :collect({ p | p:tag }).") == SOL_OK);

    /* Both k=1 entries first in their original order, then all three k=2. */
    expect_ints(&vm, "tags", (int[]){2, 4, 1, 3, 5}, 5);

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  equal elements keep their original order\n");
}

static void test_custom_comparison(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "down := [#1, #3, #2]:sorted({ a, b | b:lessThan(a) })."
        /* Ordering on something other than the value itself. */
        "byLast := [#31, #12, #23]:sorted({ a, b | a:mod(#10):lessThan(b:mod(#10)) }).")
        == SOL_OK);

    expect_ints(&vm, "down", (int[]){3, 2, 1}, 3);
    expect_ints(&vm, "byLast", (int[]){31, 12, 23}, 3);

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  takes a comparison block\n");
}

/* The default *sends* lessThan, so a type that defines one orders itself. */
static void test_default_sends_less_than(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "money := object:new. money:amount := #0."
        "money:lessThan := { other | self:amount:lessThan(other:amount) }."
        "a := money:new. a:amount := #30."
        "b := money:new. b:amount := #10."
        "c := money:new. c:amount := #20."
        "amounts := [a, b, c]:sorted:collect({ m | m:amount }).") == SOL_OK);

    expect_ints(&vm, "amounts", (int[]){10, 20, 30}, 3);

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  the default ordering is a real send of lessThan\n");
}

/* The comparison calls back into the VM and can allocate, so a collection can
   land in the middle of a merge -- with values living in the scratch array, the
   result array, or both. */
static void test_survives_collection(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;
    vm.gc_stress = true;

    assert(run(&vm, &chunk,
        "xs := [#5, #3, #9, #1, #7, #2, #8, #4, #6, #0]."
        /* Allocating on every single comparison. */
        "ys := xs:sorted({ a, b | | junk | junk := [a, b, \"pad\"]. a:lessThan(b) })."
        /* And with the default comparison, which also sends. */
        "zs := xs:sorted.") == SOL_OK);

    int want[] = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9};
    expect_ints(&vm, "ys", want, 10);
    expect_ints(&vm, "zs", want, 10);

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  survives collection during the comparison\n");
}

/* A program is free to hand us a comparison that contradicts itself. That may
   give nonsense order, but it must not lose an element or read out of bounds --
   which is a reason to merge rather than partition. */
static void test_contradictory_comparison_is_safe(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "always := [#1,#2,#3,#4,#5,#6,#7,#8]:sorted({ a, b | true })."
        "never  := [#1,#2,#3,#4,#5,#6,#7,#8]:sorted({ a, b | false })."
        /* Every element still there, whatever order it landed in. */
        "a := always:sorted. b := never:sorted.") == SOL_OK);

    int want[] = {1, 2, 3, 4, 5, 6, 7, 8};
    assert(SOL_AS_ARRAY(global(&vm, "always"))->count == 8);
    assert(SOL_AS_ARRAY(global(&vm, "never"))->count == 8);
    expect_ints(&vm, "a", want, 8);
    expect_ints(&vm, "b", want, 8);

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  a self-contradicting comparison loses nothing\n");
}

static void test_errors(void)
{
    struct { const char *source; const char *why; } cases[] = {
        { "[#1, 2.0]:sorted.",                "no implicit coercion, so mixed types" },
        { "[#1, \"a\"]:sorted.",              "and no ordering across types" },
        { "[#1,#2]:sorted({ a, b | #1 }).",   "the comparison must answer a boolean" },
        { "[#1,#2]:sorted({ a, b | a:nope }).", "an error inside it propagates" },
        { "[#1,#2]:sorted(#3).",              "the comparison must be a block" },
        { "[#1,#2]:sorted({ a | a }).",       "and must take two" },
        { "[object:new, object:new]:sorted.", "a type with no lessThan cannot order" },
        { "[#1,#2]:sorted({ a, b | true }, #1).", "sorted takes at most one" },
    };

    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        SolVM vm; sol_vm_init(&vm);
        SolChunk chunk;
        assert(run(&vm, &chunk, cases[i].source) == SOL_RUNTIME_ERROR);
        sol_chunk_free(&chunk); sol_vm_free(&vm);
        printf("  rejected: %s\n", cases[i].why);
    }
}

int main(void)
{
    printf("sorting\n");
    test_orders();
    test_orders_other_types();
    test_source_is_untouched();
    test_is_stable();
    test_custom_comparison();
    test_default_sends_less_than();
    test_survives_collection();
    test_contradictory_comparison_is_safe();
    test_errors();
    printf("ok\n");
    return 0;
}
