/* `random`: a generator you make, rather than one everybody shares.
 *
 * The state lives in an object, which is the decision 3.14 was blocked on. So
 * the tests that matter are about *whose* state it is: two generators made from
 * one seed agree forever, two made by the machine do not, and a VM that is
 * never asked for one is as deterministic as it was before this existed. */
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

/* A seed names a sequence, and it names it for good. */
static void test_a_seed_names_a_sequence(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "a := random:new(#20260824)."
        "b := random:new(#20260824)."
        "c := random:new(#20260825)."
        "agree := true. differ := false."
        "#200:repeat({ | x, y |"
        "    x := a:upTo(#1000000). y := b:upTo(#1000000)."
        "    x:equals(y):ifFalse({ agree := false })."
        "    x:equals(c:upTo(#1000000)):ifFalse({ differ := true }) })."
        "recorded := a:seed."
        /* The seed is a slot, so it is ordinary data and reflection sees it. */
        "named := a:slots:indexOf('seed):notNil.") == SOL_OK);

    assert(SOL_AS_BOOL(global(&vm, "agree")));
    assert(SOL_AS_BOOL(global(&vm, "differ")));
    assert(SOL_AS_INT(global(&vm, "recorded")) == 20260824);
    assert(SOL_AS_BOOL(global(&vm, "named")));
    sol_chunk_free(&chunk);

    sol_vm_free(&vm);
    printf("  a seed names a sequence, and the sequence keeps its name\n");
}

/* Two VMs, one seed. This is the claim embedding.md rests on: a chunk that does
   not ask for entropy runs the same twice, and one that seeds itself by hand is
   as repeatable as the machine it runs on. */
static void test_two_machines_agree_on_a_seed(void)
{
    static const char *source =
        "r := random:new(#7)."
        "drawn := []."
        "#50:repeat({ drawn:add(r:upTo(#1000)) })."
        "joined := drawn:collect({ v | v:asString }):join(\",\").";

    SolVM one; sol_vm_init(&one);
    SolVM two; sol_vm_init(&two);
    SolChunk a, b;

    assert(run(&one, &a, source) == SOL_OK);
    assert(run(&two, &b, source) == SOL_OK);

    SolValue first = global(&one, "joined"), second = global(&two, "joined");
    assert(SOL_IS_STRING(first) && SOL_IS_STRING(second));
    assert(SOL_AS_STRING(first)->length == SOL_AS_STRING(second)->length);
    assert(memcmp(SOL_AS_STRING(first)->chars, SOL_AS_STRING(second)->chars,
                  (size_t)SOL_AS_STRING(first)->length) == 0);

    sol_chunk_free(&a); sol_chunk_free(&b);
    sol_vm_free(&one); sol_vm_free(&two);
    printf("  two machines given one seed answer the same sequence\n");
}

/* And without a seed it comes from the machine, which is the entropy no Solum
   program can reach on its own -- the clock being the only other candidate, and
   the clock's low bits being what 3.14 measured going wrong. */
static void test_the_machine_seeds_it_differently_each_time(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "seeds := dictionary:new."
        "#50:repeat({ seeds:atPut(random:new:seed, true) })."
        "distinct := seeds:size."
        /* Non-negative, so a seed the machine chose reads like one a person
           would write and can be handed straight back to `new`. */
        "lowest := #0."
        "seeds:keysAndValuesDo({ k, v | k:lessThan(lowest):ifTrue({ lowest := k }) })."
        "again := random:new(#1234)."
        "back := random:new(again:seed):upTo(#100000):equals("
        "            random:new(#1234):upTo(#100000)).") == SOL_OK);

    assert(SOL_AS_INT(global(&vm, "distinct")) == 50);
    assert(SOL_AS_INT(global(&vm, "lowest")) == 0);
    assert(SOL_AS_BOOL(global(&vm, "back")));
    sol_chunk_free(&chunk);

    sol_vm_free(&vm);
    printf("  the machine seeds it, and the seed it chose can be handed back\n");
}

/* Ranges, at both ends and in the corners. */
static void test_the_range_is_the_range_asked_for(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "r := random:new(#3)."
        "outside := #0. sawLow := false. sawHigh := false."
        "#20000:repeat({ | v |"
        "    v := r:upTo(#6)."
        "    v:lessThan(#1):or({ v:greaterThan(#6) }):ifTrue({ outside := outside:inc })."
        "    v:equals(#1):ifTrue({ sawLow := true })."
        "    v:equals(#6):ifTrue({ sawHigh := true }) })."
        /* One thing to choose from is the one thing that cannot be random. */
        "onlyOne := true."
        "#100:repeat({ r:upTo(#1):equals(#1):ifFalse({ onlyOne := false }) })."
        /* between takes both ends, and works below zero. */
        "spread := dictionary:new."
        "#20000:repeat({ | v |"
        "    v := r:between(#-3, #3)."
        "    v:lessThan(#-3):or({ v:greaterThan(#3) }):ifTrue({ outside := outside:inc })."
        "    spread:atPut(v, true) })."
        "seven := spread:size."
        "same := r:between(#5, #5)."
        /* A fraction is at least zero and never one. */
        "loose := #0. sum := 0.0."
        "#20000:repeat({ | f |"
        "    f := r:fraction."
        "    f:lessThan(0.0):or({ f:greaterThan(0.9999999999) })"
        "        :ifTrue({ loose := loose:inc })."
        "    sum := sum:add(f) })."
        "mean := sum:div(20000.0).") == SOL_OK);

    assert(SOL_AS_INT(global(&vm, "outside")) == 0);
    assert(SOL_AS_BOOL(global(&vm, "sawLow")) && SOL_AS_BOOL(global(&vm, "sawHigh")));
    assert(SOL_AS_BOOL(global(&vm, "onlyOne")));
    assert(SOL_AS_INT(global(&vm, "seven")) == 7);     /* -3 to 3, all of them */
    assert(SOL_AS_INT(global(&vm, "same")) == 5);
    assert(SOL_AS_INT(global(&vm, "loose")) == 0);

    double mean = SOL_AS_FLOAT(global(&vm, "mean"));
    assert(mean > 0.49 && mean < 0.51);
    sol_chunk_free(&chunk);

    /* The whole of int64, which is the one span a uint64 cannot count and so
       the one where every draw is already in range. */
    assert(run(&vm, &chunk,
        "wide := random:new(#11)."
        "sawNegative := false. sawPositive := false."
        "#200:repeat({ | v |"
        "    v := wide:between(#-9223372036854775807:sub(#1), #9223372036854775807)."
        "    v:lessThan(#0):ifTrue({ sawNegative := true })."
        "    v:greaterThan(#0):ifTrue({ sawPositive := true }) }).") == SOL_OK);
    assert(SOL_AS_BOOL(global(&vm, "sawNegative")));
    assert(SOL_AS_BOOL(global(&vm, "sawPositive")));
    sol_chunk_free(&chunk);

    sol_vm_free(&vm);
    printf("  every draw lands in the range asked for, both ends included\n");
}

/* The bias `mod n` leaves is what a hand-written generator gets wrong, and it
   is invisible: the numbers look fine and the low ones come up more often. This
   is the check that the rejection loop is doing something -- a bound that does
   not divide the word evenly, over enough draws to see a one-part-in-seven
   lean if there were one. */
static void test_no_bound_is_favoured(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "r := random:new(#99)."
        "counts := []."
        "#7:repeat({ counts:add(#0) })."
        "#700000:repeat({ | v | v := r:upTo(#7)."
        "    counts:at_put(v, counts:at(v):inc) })."
        "lowest := counts:at(#1). highest := counts:at(#1)."
        "counts:do({ c | c:lessThan(lowest):ifTrue({ lowest := c })."
        "               c:greaterThan(highest):ifTrue({ highest := c }) }).") == SOL_OK);

    /* 100,000 expected in each, and one standard deviation is about 293. Four
       of those either way is a wide gate for chance and a narrow one for bias:
       taking `mod #7` of a 64-bit draw would not show here, but the same
       mistake on a bound near the word size is a lean of a third. */
    assert(SOL_AS_INT(global(&vm, "lowest")) > 100000 - 1200);
    assert(SOL_AS_INT(global(&vm, "highest")) < 100000 + 1200);
    sol_chunk_free(&chunk);

    sol_vm_free(&vm);
    printf("  no value inside the bound is favoured over another\n");
}

/* State in an object is state the collector walks past. */
static void test_a_generator_survives_collection(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "kept := random:new(#42)."
        "before := kept:upTo(#1000000)."
        /* Enough litter to collect several times over, generators included. */
        "#2000:repeat({ random:new(#1):upTo(#10). object:new })."
        "after := kept:upTo(#1000000)."
        "stillThere := kept:seed."
        "fresh := random:new(#42)."
        "fresh:upTo(#1000000)."
        "matches := fresh:upTo(#1000000):equals(after).") == SOL_OK);

    assert(SOL_AS_INT(global(&vm, "stillThere")) == 42);
    /* The kept generator advanced exactly twice, whatever happened around it. */
    assert(SOL_AS_BOOL(global(&vm, "matches")));
    assert(SOL_AS_INT(global(&vm, "before")) != SOL_AS_INT(global(&vm, "after")));
    sol_chunk_free(&chunk);

    sol_vm_free(&vm);
    printf("  a generator keeps its place across a collection\n");
}

static void test_what_it_refuses(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    static const char *refused[] = {
        /* The prototype is not a generator. Answering here would be one stream
           shared by everything that reached for it, which is the arrangement
           this design exists to avoid. */
        "random:upTo(#6).",
        "random:between(#1, #6).",
        "random:fraction.",
        "random:new(#1):upTo(#0).",          /* nothing to choose from */
        "random:new(#1):upTo(#-5).",
        "random:new(#1):upTo(1.5).",         /* a count is an integer */
        "random:new(#1):upTo(\"6\").",
        "random:new(#1):between(#5, #1).",   /* the low end comes first */
        "random:new(#1):between(#1).",
        "random:new(#1):fraction(#1).",
        "random:new(1.0).",                  /* a seed is an integer */
        "random:new(\"today\").",
        "random:new(#1, #2).",
    };
    for (size_t i = 0; i < sizeof refused / sizeof refused[0]; i++) {
        assert(run(&vm, &chunk, refused[i]) == SOL_RUNTIME_ERROR);
        sol_chunk_free(&chunk);
    }

    /* And the prototype is still an object, so what it does understand works. */
    assert(run(&vm, &chunk, "made := random:new:notNil.") == SOL_OK);
    assert(SOL_AS_BOOL(global(&vm, "made")));
    sol_chunk_free(&chunk);

    sol_vm_free(&vm);
    printf("  a generator has to be made, and its arguments are checked\n");
}

int main(void)
{
    test_a_seed_names_a_sequence();
    test_two_machines_agree_on_a_seed();
    test_the_machine_seeds_it_differently_each_time();
    test_the_range_is_the_range_asked_for();
    test_no_bound_is_favoured();
    test_a_generator_survives_collection();
    test_what_it_refuses();
    printf("test_random: ok\n");
    return 0;
}
