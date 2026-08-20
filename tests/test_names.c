/* Interned names: the pointer a send compares, and the hash that fills a
   chunk's side tables. Roadmap 4.3. */
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "solas/compiler.h"
#include "solum/gc.h"
#include "solum/serialize.h"
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

/* ---- the table ---------------------------------------------------------- */

static void test_one_copy_per_spelling(void)
{
    SolVM vm; sol_vm_init(&vm);

    const char *a = sol_vm_intern_name(&vm, "frobnicate", 10);
    const char *b = sol_vm_intern_name(&vm, "frobnicate", 10);
    assert(a == b);                       /* the same pointer, not a copy */
    assert(strcmp(a, "frobnicate") == 0);

    assert(sol_vm_intern_name(&vm, "other", 5) != a);

    /* Length decides, not a terminator: these share a prefix. */
    const char *ab  = sol_vm_intern_name(&vm, "abc", 2);
    const char *abc = sol_vm_intern_name(&vm, "abc", 3);
    assert(ab != abc);
    assert(strcmp(ab, "ab") == 0 && strcmp(abc, "abc") == 0);

    sol_vm_free(&vm);
    printf("  one copy per spelling, and length decides\n");
}

/* Enough names to grow the table several times, each still findable. */
static void test_the_table_grows(void)
{
    SolVM vm; sol_vm_init(&vm);

    enum { N = 5000 };
    const char **first = malloc(N * sizeof *first);
    assert(first != NULL);

    for (int i = 0; i < N; i++) {
        char spelling[32];
        snprintf(spelling, sizeof spelling, "name%d", i);
        first[i] = sol_vm_intern_name(&vm, spelling, (int)strlen(spelling));
    }
    for (int i = 0; i < N; i++) {
        char spelling[32];
        snprintf(spelling, sizeof spelling, "name%d", i);
        assert(sol_vm_intern_name(&vm, spelling, (int)strlen(spelling)) == first[i]);
    }

    free(first);
    sol_vm_free(&vm);
    printf("  %d names survive the table growing under them\n", 5000);
}

/* ---- slots -------------------------------------------------------------- */

static void test_slots_share_their_names(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "a := object:new. a:tally := #1."
        "b := object:new. b:tally := #2.") == SOL_OK);

    SolSlot *sa = sol_object_lookup(SOL_AS_OBJ(global(&vm, "a")), "tally");
    SolSlot *sb = sol_object_lookup(SOL_AS_OBJ(global(&vm, "b")), "tally");
    assert(sa != NULL && sb != NULL);
    assert(sa != sb);                     /* two slots */
    assert(sa->name == sb->name);         /* one name */
    assert(sa->name == sol_vm_intern_name(&vm, "tally", 5));

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  two slots of the same name share one string\n");
}

/* The fast lookup and the spelling lookup must never disagree, including up a
   proto chain and on a name that is not there at all. */
static void test_both_lookups_agree(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "base := object:new. base:deep := #7."
        "mid := base:new. mid:shallow := #8."
        "leaf := mid:new.") == SOL_OK);

    SolObject *leaf = SOL_AS_OBJ(global(&vm, "leaf"));
    static const char *names[] = { "deep", "shallow", "absent", "asString" };

    for (size_t i = 0; i < sizeof(names) / sizeof(names[0]); i++) {
        SolSlot *slow = sol_object_lookup(leaf, names[i]);
        SolSlot *fast = sol_object_lookup_interned(
            &vm, leaf, sol_vm_intern_name(&vm, names[i], (int)strlen(names[i])));
        assert(slow == fast);
    }

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  the interned lookup answers exactly what the spelling one does\n");
}

#ifndef SOLUM_CHECK_INTERNED
/* The trap the two names guard against, pinned so it stays a known shape: an
   equal string that is not *the* string finds nothing. Building with
   -DSOLUM_CHECK_INTERNED turns this from a silent NULL into an assertion,
   which is why the case is compiled out there. */
static void test_an_uninterned_name_finds_nothing(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;
    assert(run(&vm, &chunk, "o := object:new. o:tally := #1.") == SOL_OK);

    SolObject *o = SOL_AS_OBJ(global(&vm, "o"));
    char copy[] = "tally";                /* same characters, different address */

    assert(sol_object_lookup(o, copy) != NULL);
    assert(sol_object_lookup_interned(&vm, o, copy) == NULL);
    assert(sol_object_lookup_interned(&vm, o, sol_vm_intern_name(&vm, copy, 5)) != NULL);

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  an equal string that is not the interned one finds nothing\n");
}
#endif

/* ---- chunks ------------------------------------------------------------- */

static void test_a_chunk_resolves_its_names(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk, "x := #1:add(#2). y := x:add(#3).") == SOL_OK);

    assert(chunk.interned != NULL);
    assert(chunk.interned_for == &vm);
    for (int i = 0; i < chunk.names.count; i++) {
        const char *name = chunk.names.names[i];
        assert(chunk.interned[i] == sol_vm_intern_name(&vm, name, (int)strlen(name)));
    }

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  a chunk's name table resolves to this VM's names\n");
}

/* Nested methods are chunks too, and a block's body dispatches from its own. */
static void test_nested_chunks_resolve(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    /* Called where they were written, so nothing escapes its frame (3.1). */
    assert(run(&vm, &chunk,
        "o := object:new."
        "o:m := { { #1:add(#2) }:value:print }."
        "o:m.") == SOL_OK);

    assert(chunk.methods.count > 0);
    for (int i = 0; i < chunk.methods.count; i++) {
        SolChunk *inner = &chunk.methods.methods[i]->chunk;
        assert(inner->interned_for == &vm);
        if (inner->names.count > 0) assert(inner->interned != NULL);
    }

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  nested method chunks resolve too\n");
}

/* Names are the VM's, so a chunk run by a second VM must be resolved again --
   the pointers from the first are not that VM's and would match nothing. */
static void test_a_second_vm_reresolves(void)
{
    SolChunk chunk;
    sol_chunk_init(&chunk);
    assert(sol_compile("x := #1:add(#2).", &chunk));

    SolVM first; sol_vm_init(&first);
    assert(sol_vm_run(&first, &chunk) == SOL_OK);
    const char *from_first = chunk.interned[0];
    assert(chunk.interned_for == &first);
    sol_vm_free(&first);

    SolVM second; sol_vm_init(&second);
    assert(sol_vm_run(&second, &chunk) == SOL_OK);
    assert(chunk.interned_for == &second);
    assert(chunk.interned[0] ==
           sol_vm_intern_name(&second, chunk.names.names[0], (int)strlen(chunk.names.names[0])));
    assert(SOL_AS_INT(global(&second, "x")) == 3);
    (void)from_first;                     /* freed with the first VM */
    sol_vm_free(&second);

    sol_chunk_free(&chunk);
    printf("  a chunk run by a second VM is resolved again\n");
}

/* ---- the side-table index ----------------------------------------------- */

/* Interning must answer the same index whether the table is small enough to
   scan or large enough to be hashed -- the threshold is an accelerator, not a
   change of behaviour. */
static void test_interning_is_the_same_either_side_of_the_threshold(void)
{
    for (int total = 4; total <= 400; total *= 5) {
        SolChunk chunk;
        sol_chunk_init(&chunk);

        for (int i = 0; i < total; i++) {
            char spelling[32];
            snprintf(spelling, sizeof spelling, "n%d", i);
            int at = sol_chunk_add_name(&chunk, spelling, (int)strlen(spelling));
            assert(at == i);                       /* each new one appends */
            assert(sol_chunk_add_constant(&chunk, SOL_INT_VAL(i)) == i);
        }
        assert(chunk.names.count == total);
        assert(chunk.constants.count == total);

        /* Every repeat collapses onto the first, in any order. */
        for (int i = total - 1; i >= 0; i--) {
            char spelling[32];
            snprintf(spelling, sizeof spelling, "n%d", i);
            assert(sol_chunk_add_name(&chunk, spelling, (int)strlen(spelling)) == i);
            assert(sol_chunk_add_constant(&chunk, SOL_INT_VAL(i)) == i);
        }
        assert(chunk.names.count == total);
        assert(chunk.constants.count == total);

        sol_chunk_free(&chunk);
    }
    printf("  interning answers the same index, scanned or hashed\n");
}

/* Hashing must not fold what the bit comparison keeps apart, nor keep apart
   what it folds. These are the two constants that catch it. */
static void test_the_hash_agrees_with_the_bits(void)
{
    SolChunk chunk;
    sol_chunk_init(&chunk);

    /* Enough entries to be past the threshold, so the hash is in play. */
    for (int i = 0; i < 40; i++) sol_chunk_add_constant(&chunk, SOL_INT_VAL(i));

    int zero  = sol_chunk_add_constant(&chunk, SOL_FLOAT_VAL(0.0));
    int minus = sol_chunk_add_constant(&chunk, SOL_FLOAT_VAL(-0.0));
    assert(zero != minus);                       /* they print differently */
    assert(sol_chunk_add_constant(&chunk, SOL_FLOAT_VAL(0.0)) == zero);
    assert(sol_chunk_add_constant(&chunk, SOL_FLOAT_VAL(-0.0)) == minus);

    /* A NaN has the same bits as itself, so it folds like anything else. */
    double nan_value = strtod("nan", NULL);
    int first_nan = sol_chunk_add_constant(&chunk, SOL_FLOAT_VAL(nan_value));
    assert(sol_chunk_add_constant(&chunk, SOL_FLOAT_VAL(nan_value)) == first_nan);

    /* An integer and a float of the same magnitude are different constants. */
    int int_one = sol_chunk_add_constant(&chunk, SOL_INT_VAL(1));
    int float_one = sol_chunk_add_constant(&chunk, SOL_FLOAT_VAL(1.0));
    assert(int_one != float_one);

    assert(sol_chunk_add_constant(&chunk, SOL_BOOL_VAL(true)) !=
           sol_chunk_add_constant(&chunk, SOL_BOOL_VAL(false)));

    sol_chunk_free(&chunk);
    printf("  the hash folds exactly what the bit comparison folds\n");
}

/* The loader appends without interning, because a file's code refers to both
   tables by position. The index must not change that. */
static void test_the_loader_keeps_positions(void)
{
    SolChunk chunk;
    sol_chunk_init(&chunk);

    for (int i = 0; i < 40; i++) sol_chunk_append_name(&chunk, "same", 4);
    assert(chunk.names.count == 40);             /* every one kept its place */

    for (int i = 0; i < 40; i++) sol_chunk_append_constant(&chunk, SOL_INT_VAL(7));
    assert(chunk.constants.count == 40);

    /* Interning still answers the first of the repeats. */
    assert(sol_chunk_add_name(&chunk, "same", 4) == 0);
    assert(sol_chunk_add_constant(&chunk, SOL_INT_VAL(7)) == 0);

    sol_chunk_free(&chunk);
    printf("  appending keeps every position, and interning finds the first\n");
}

/* A program with many repeated names must still compile to the same bytes it
   always did: interning is what makes the side tables small. */
static void test_repeats_still_collapse(void)
{
    SolChunk chunk;
    sol_chunk_init(&chunk);

    char source[4096];
    int at = snprintf(source, sizeof source, "a := #0.");
    for (int i = 0; i < 100; i++) {
        at += snprintf(source + at, sizeof source - (size_t)at, " a := a:add(#1).");
    }
    assert(sol_compile(source, &chunk));

    /* `a`, `add`, and nothing else; `#0` and `#1`, and nothing else. */
    assert(chunk.names.count == 2);
    assert(chunk.constants.count == 2);

    sol_chunk_free(&chunk);
    printf("  a hundred repeats still make two names and two constants\n");
}

/* ---- the collector ------------------------------------------------------ */

/* Names outlive the objects that point at them, so a collection in the middle
   of all this must not leave a slot naming freed memory. */
static void test_names_survive_collection(void)
{
    SolVM vm; sol_vm_init(&vm);
    vm.gc_stress = true;
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "make := { | o | o := object:new. o:tally := #1. o }."
        "keep := make:value."
        "i := #0."
        "{ i:lessThan(#200) }:whileTrue({ make:value. i := i:add(#1) })."
        "answer := keep:tally.") == SOL_OK);

    assert(SOL_AS_INT(global(&vm, "answer")) == 1);

    SolSlot *slot = sol_object_lookup(SOL_AS_OBJ(global(&vm, "keep")), "tally");
    assert(slot != NULL);
    assert(slot->name == sol_vm_intern_name(&vm, "tally", 5));

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  a slot's name survives its neighbours being collected\n");
}

int main(void)
{
    printf("interned names\n");
    test_one_copy_per_spelling();
    test_the_table_grows();
    test_slots_share_their_names();
    test_both_lookups_agree();
#ifndef SOLUM_CHECK_INTERNED
    test_an_uninterned_name_finds_nothing();
#endif
    test_a_chunk_resolves_its_names();
    test_nested_chunks_resolve();
    test_a_second_vm_reresolves();
    test_interning_is_the_same_either_side_of_the_threshold();
    test_the_hash_agrees_with_the_bits();
    test_the_loader_keeps_positions();
    test_repeats_still_collapse();
    test_names_survive_collection();
    printf("ok\n");
    return 0;
}
