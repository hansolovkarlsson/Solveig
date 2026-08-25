/* Dictionaries: values under keys, found by hashing.
 *
 * The interesting half is the table -- growth, tombstones, and the collector.
 * A dictionary is the first type whose *keys* are edges as well as its values,
 * and the first whose backing store is rebuilt rather than grown in place. */
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

static bool is_text(SolValue value, const char *expected)
{
    if (!SOL_IS_STRING(value)) return false;
    const SolString *s = SOL_AS_STRING(value);
    return s->length == (int)strlen(expected) &&
           memcmp(s->chars, expected, (size_t)s->length) == 0;
}

static void test_binding_and_reading(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "d := dictionary:new. empty := d:size."
        "d:atPut(\"a\", #1). d:atPut(\"b\", #2)."
        "n := d:size. a := d:at(\"a\"). b := d:at(\"b\")."
        /* binding again replaces rather than adding */
        "d:atPut(\"a\", #9). again := d:size. nine := d:at(\"a\")."
        /* atPut answers the value stored, as atPut on an array does */
        "answered := d:atPut(\"c\", #3).") == SOL_OK);

    assert(SOL_AS_INT(global(&vm, "empty")) == 0);
    assert(SOL_AS_INT(global(&vm, "n")) == 2);
    assert(SOL_AS_INT(global(&vm, "a")) == 1);
    assert(SOL_AS_INT(global(&vm, "b")) == 2);
    assert(SOL_AS_INT(global(&vm, "again")) == 2);
    assert(SOL_AS_INT(global(&vm, "nine")) == 9);
    assert(SOL_AS_INT(global(&vm, "answered")) == 3);

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  binding, reading, and replacing\n");
}

/* `at` errors on a missing key, the same answer an out-of-range index gets.
   `at(key, default)` is the form for a lookup that may legitimately miss. */
static void test_a_missing_key(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk, "dictionary:new:at(\"nope\").") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk); sol_vm_free(&vm);

    sol_vm_init(&vm);
    assert(run(&vm, &chunk,
        "d := dictionary:new. d:atPut(\"a\", #1)."
        "there := d:at(\"a\", #0). missing := d:at(\"z\", #0)."
        "yes := d:includes(\"a\"). no := d:includes(\"z\").") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "there")) == 1);
    assert(SOL_AS_INT(global(&vm, "missing")) == 0);
    assert(SOL_AS_BOOL(global(&vm, "yes")));
    assert(SOL_AS_BOOL(global(&vm, "no")) == false);

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  a missing key is an error, or the default when one is given\n");
}

/* Keys are values -- the types `equals` compares by content. A reference is
   compared by identity, so two that look alike would be two keys: the right
   answer for `equals` and a useless one here. */
static void test_what_may_be_a_key(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "d := dictionary:new."
        "d:atPut(#1, \"int\"). d:atPut(1.0, \"float\"). d:atPut(\"1\", \"string\")."
        "d:atPut('one, \"symbol\"). d:atPut(true, \"bool\"). d:atPut(nil, \"nil\")."
        "n := d:size."
        "i := d:at(#1). f := d:at(1.0). s := d:at(\"1\")."
        "y := d:at('one). b := d:at(true). z := d:at(nil).") == SOL_OK);

    assert(SOL_AS_INT(global(&vm, "n")) == 6);      /* none of them is another */
    assert(is_text(global(&vm, "i"), "int"));
    assert(is_text(global(&vm, "f"), "float"));
    assert(is_text(global(&vm, "s"), "string"));
    assert(is_text(global(&vm, "y"), "symbol"));
    assert(is_text(global(&vm, "b"), "bool"));
    assert(is_text(global(&vm, "z"), "nil"));
    sol_chunk_free(&chunk); sol_vm_free(&vm);

    static const char *refused[] = {
        "dictionary:new:atPut([#1], #2).",
        "dictionary:new:atPut(object:new, #2).",
        "dictionary:new:atPut({ #1 }, #2).",
        "dictionary:new:atPut(dictionary:new, #2).",
        "dictionary:new:includes([#1]).",
        "dictionary:new:remove([#1]).",
    };
    for (size_t i = 0; i < sizeof(refused) / sizeof(refused[0]); i++) {
        SolVM v; sol_vm_init(&v);
        SolChunk c;
        assert(run(&v, &c, refused[i]) == SOL_RUNTIME_ERROR);
        sol_chunk_free(&c); sol_vm_free(&v);
    }
    printf("  keys are values; a reference is refused\n");
}

/* -0.0 equals 0.0, so the two have to be one key or the table would disagree
   with `equals` about what one key being another means. */
static void test_negative_zero_is_one_key(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "d := dictionary:new. d:atPut(0.0, \"first\"). d:atPut(-0.0, \"second\")."
        "n := d:size. held := d:at(0.0). also := d:at(-0.0).") == SOL_OK);

    assert(SOL_AS_INT(global(&vm, "n")) == 1);
    assert(is_text(global(&vm, "held"), "second"));
    assert(is_text(global(&vm, "also"), "second"));

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  -0.0 and 0.0 are one key\n");
}

static void test_removing(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "d := dictionary:new."
        "d:atPut(\"a\", #1). d:atPut(\"b\", #2). d:atPut(\"c\", #3)."
        "held := d:remove(\"b\"). n := d:size."
        "gone := d:includes(\"b\")."
        /* the ones that probed past it must still be found */
        "a := d:at(\"a\"). c := d:at(\"c\")."
        /* and the key may be bound again afterwards */
        "d:atPut(\"b\", #7). back := d:at(\"b\"). after := d:size.") == SOL_OK);

    assert(SOL_AS_INT(global(&vm, "held")) == 2);
    assert(SOL_AS_INT(global(&vm, "n")) == 2);
    assert(SOL_AS_BOOL(global(&vm, "gone")) == false);
    assert(SOL_AS_INT(global(&vm, "a")) == 1);
    assert(SOL_AS_INT(global(&vm, "c")) == 3);
    assert(SOL_AS_INT(global(&vm, "back")) == 7);
    assert(SOL_AS_INT(global(&vm, "after")) == 3);
    sol_chunk_free(&chunk); sol_vm_free(&vm);

    sol_vm_init(&vm);
    assert(run(&vm, &chunk, "dictionary:new:remove(\"nope\").") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  removing leaves a tombstone the probe passes through\n");
}

/* Enough keys to rehash several times, then enough churn that the tombstones
   crowd the table and force a rebuild that drops them. */
static void test_growth_and_churn(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "d := dictionary:new. i := #1."
        "{ i:lessOrEqual(#500) }:whileTrue({"
        "    d:atPut(\"k\":concat(i:asString), i:mul(#2)). i := i:add(#1) })."
        "filled := d:size."
        "first := d:at(\"k1\"). last := d:at(\"k500\")."
        "sum := #0. d:do({ v | sum := sum:add(v) })."
        /* remove half, then add as many again */
        "j := #1."
        "{ j:lessOrEqual(#250) }:whileTrue({"
        "    d:remove(\"k\":concat(j:asString)). j := j:add(#1) })."
        "halved := d:size."
        "m := #501."
        "{ m:lessOrEqual(#750) }:whileTrue({"
        "    d:atPut(\"k\":concat(m:asString), m). m := m:add(#1) })."
        "churned := d:size."
        "survived := d:at(\"k251\"). fresh := d:at(\"k750\")."
        "removed := d:includes(\"k100\").") == SOL_OK);

    assert(SOL_AS_INT(global(&vm, "filled")) == 500);
    assert(SOL_AS_INT(global(&vm, "first")) == 2);
    assert(SOL_AS_INT(global(&vm, "last")) == 1000);
    assert(SOL_AS_INT(global(&vm, "sum")) == 500 * 501);    /* 2*(1+..+500) */
    assert(SOL_AS_INT(global(&vm, "halved")) == 250);
    assert(SOL_AS_INT(global(&vm, "churned")) == 500);
    assert(SOL_AS_INT(global(&vm, "survived")) == 502);
    assert(SOL_AS_INT(global(&vm, "fresh")) == 750);
    assert(SOL_AS_BOOL(global(&vm, "removed")) == false);

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  growth and churn keep every live entry\n");
}

/* Both halves of an entry are edges, and this is what a dictionary added that
   no other type had: a *key* the collector has to keep alive. It was missed --
   `mark_value` was a chain of `if (SOL_IS_...)` rather than a switch, so the
   compiler could not say SOL_DICT was unhandled, and live dictionaries were
   swept. Keys and values here are freshly allocated and referred to by nothing
   else, so a collection that got this wrong would lose them. */
static void test_keys_and_values_survive_collection(void)
{
    SolVM vm; sol_vm_init(&vm);
    /* Two chunks rather than one reused: a chunk has to outlive anything
       defined in it (roadmap 3.6), so it cannot be freed between the two runs
       -- and reusing the variable would leak the first one. */
    SolChunk built, checked;

    assert(run(&vm, &built,
        "d := dictionary:new. i := #1."
        "{ i:lessOrEqual(#200) }:whileTrue({"
        "    d:atPut(\"key-\":concat(i:asString), \"value-\":concat(i:asString))."
        "    i := i:add(#1) }).") == SOL_OK);

    sol_gc_collect(&vm);
    sol_gc_collect(&vm);

    assert(run(&vm, &checked,
        "n := d:size. one := d:at(\"key-1\"). last := d:at(\"key-200\").") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "n")) == 200);
    assert(is_text(global(&vm, "one"), "value-1"));
    assert(is_text(global(&vm, "last"), "value-200"));

    sol_chunk_free(&built); sol_chunk_free(&checked); sol_vm_free(&vm);
    printf("  keys and values survive collection\n");
}

/* `do` takes a one-argument block over the values, exactly as an array's does:
   the same selector should not want a different shape of block depending on
   the receiver. `keysAndValuesDo` is the two-argument form. */
static void test_walking(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "d := dictionary:new."
        "d:atPut(\"a\", #1). d:atPut(\"b\", #2). d:atPut(\"c\", #3)."
        "sum := #0. d:do({ v | sum := sum:add(v) })."
        "names := array:new. paired := #0."
        "d:keysAndValuesDo({ k, v | names:add(k). paired := paired:add(v) })."
        "sorted := names:sorted:join(\",\")."
        "keys := d:keys:sorted:join(\",\"). values := d:values:size."
        /* answers the receiver, as an array's `do` does */
        "same := d:do({ v | v }):equals(d).") == SOL_OK);

    assert(SOL_AS_INT(global(&vm, "sum")) == 6);
    assert(SOL_AS_INT(global(&vm, "paired")) == 6);
    assert(is_text(global(&vm, "sorted"), "a,b,c"));
    assert(is_text(global(&vm, "keys"), "a,b,c"));
    assert(SOL_AS_INT(global(&vm, "values")) == 3);
    assert(SOL_AS_BOOL(global(&vm, "same")));

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  do walks the values, keysAndValuesDo the pairs\n");
}

/* The walk is over a snapshot of the keys, so a block that adds to the
   dictionary it is walking does not rehash the table underneath itself. */
static void test_walking_while_changing(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "d := dictionary:new. i := #1."
        "{ i:lessOrEqual(#20) }:whileTrue({ d:atPut(i, i). i := i:add(#1) })."
        "seen := #0."
        "d:keysAndValuesDo({ k, v | seen := seen:add(#1)."
        "    d:atPut(k:add(#100), v) })."
        "grew := d:size.") == SOL_OK);

    assert(SOL_AS_INT(global(&vm, "seen")) == 20);      /* the twenty it started with */
    assert(SOL_AS_INT(global(&vm, "grew")) == 40);
    sol_chunk_free(&chunk); sol_vm_free(&vm);

    /* And one that removes as it goes skips what it took away. */
    sol_vm_init(&vm);
    assert(run(&vm, &chunk,
        "d := dictionary:new."
        "d:atPut(#1, #1). d:atPut(#2, #2). d:atPut(#3, #3)."
        "seen := #0."
        "d:keysAndValuesDo({ k, v | seen := seen:add(#1)."
        "    d:includes(#3):ifTrue({ d:remove(#3) }) })."
        "left := d:size.") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "left")) == 2);
    assert(SOL_AS_INT(global(&vm, "seen")) <= 3);
    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  walking a dictionary that changes underneath\n");
}

/* A dictionary is a reference, like an array: two with equal contents are two
   dictionaries. And it is an object in the type graph like everything else. */
static void test_identity_and_kind(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "a := dictionary:new. b := dictionary:new."
        "a:atPut(\"k\", #1). b:atPut(\"k\", #1)."
        "differ := a:equals(b). same := a:equals(a)."
        "kind := a:isKindOf(dictionary). rooted := a:isKindOf(object)."
        "nil_ := a:isNil. there := a:notNil."
        "named := a:isKindOf(array).") == SOL_OK);

    assert(SOL_AS_BOOL(global(&vm, "differ")) == false);
    assert(SOL_AS_BOOL(global(&vm, "same")));
    assert(SOL_AS_BOOL(global(&vm, "kind")));
    assert(SOL_AS_BOOL(global(&vm, "rooted")));
    assert(SOL_AS_BOOL(global(&vm, "nil_")) == false);
    assert(SOL_AS_BOOL(global(&vm, "there")));
    assert(SOL_AS_BOOL(global(&vm, "named")) == false);

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  a dictionary is a reference, and an object like everything else\n");
}

/* It cannot be a constant, for the same reason an array cannot: it is built at
   run time, so a literal would be a construction rather than a pooled value. */
static void test_it_holds_anything_including_itself(void)
{
    SolVM vm; sol_vm_init(&vm);
    /* The block in the dictionary is defined in `built`, so `built` has to
       outlive it -- freeing it before the second run is the 3.6 hazard, and
       doing it deliberately here is how that was confirmed. */
    SolChunk built, checked;

    assert(run(&vm, &built,
        "d := dictionary:new."
        "d:atPut(\"self\", d)."                    /* a cycle, for the marker */
        "d:atPut(\"array\", [#1, #2])."
        "d:atPut(\"block\", { #42 })."
        "d:atPut(\"object\", object:new).") == SOL_OK);

    sol_gc_collect(&vm);                            /* must not loop or lose it */

    assert(run(&vm, &checked,
        "n := d:size. cycle := d:at(\"self\"):equals(d)."
        "answered := d:at(\"block\"):value.") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "n")) == 4);
    assert(SOL_AS_BOOL(global(&vm, "cycle")));
    assert(SOL_AS_INT(global(&vm, "answered")) == 42);

    sol_chunk_free(&built); sol_chunk_free(&checked); sol_vm_free(&vm);
    printf("  a dictionary holds anything, itself included\n");
}

int main(void)
{
    test_binding_and_reading();
    test_a_missing_key();
    test_what_may_be_a_key();
    test_negative_zero_is_one_key();
    test_removing();
    test_growth_and_churn();
    test_keys_and_values_survive_collection();
    test_walking();
    test_walking_while_changing();
    test_identity_and_kind();
    test_it_holds_anything_including_itself();
    printf("test_dict: ok\n");
    return 0;
}
