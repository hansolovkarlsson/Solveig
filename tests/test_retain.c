/* Keeping a value alive while foreign code holds it.
 *
 * This is the other half of rule 3. `sol_gc_push_temp` covers a window inside
 * one primitive; a toolkit holding a block as its callback holds it *between*
 * calls, where nothing the tracer walks can see it.
 *
 * The failure this prevents was measured before the registry existed, with a
 * GTK timer calling a Solum block on every tick and collection turned up to
 * every allocation:
 *
 *     #1
 *     probe: callback failed: 'block' takes 1 argument, got 0
 *
 * The first tick ran; the collection between ticks swept the block; the second
 * tick called whatever then occupied the cell -- an inner block from the same
 * script, of a different arity. **Not a crash, and nothing in it points at the
 * collector.** Every case below exists so that no version of that can happen
 * again, including the version where the registry itself hands back the wrong
 * value.
 */
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "solas/compiler.h"
#include "solum/extend.h"

static void compile(SolChunk *chunk, const char *source)
{
    sol_chunk_init(chunk);
    assert(sol_compile_source(source, "<test>", chunk));
}

/* Binds `answer` to a block that answers 42, and hands it back. The block is
   reachable from the globals, so getting hold of one costs nothing. */
static SolValue a_block(SolVM *vm, SolChunk *chunk, const char *body)
{
    compile(chunk, body);
    assert(sol_vm_run(vm, chunk) == SOL_OK);

    SolValue block;
    assert(sol_vm_global(vm, "answer", &block));
    assert(SOL_IS_BLOCK(block));
    return block;
}

/* ---- what it is for ------------------------------------------------------ */

/* The case from the probe, in C: a value held only by "foreign code" -- here, a
   plain C local -- across collections that would otherwise sweep it. */
static void test_a_retained_block_survives_collection(void)
{
    SolVM vm;
    sol_vm_init(&vm);

    SolChunk chunk;
    SolValue block = a_block(&vm, &chunk, "answer := { #42 }.");

    SolRetained token = sol_extension_retain(&vm, block);
    assert(token != SOL_RETAINED_NONE);

    /* Now take away every other way of reaching it: the global is rebound and
       the stack is empty between runs. The registry is the only root left. */
    sol_vm_set_global(&vm, "answer", SOL_NIL_VAL);

    vm.gc_stress = true;
    for (int i = 0; i < 20; i++) sol_gc_collect(&vm);

    SolValue got;
    assert(sol_extension_retained(&vm, token, &got));
    assert(SOL_IS_BLOCK(got));
    assert(SOL_AS_BLOCK(got) == SOL_AS_BLOCK(block));   /* the same one */

    /* And it still runs, which is what the toolkit would be doing. */
    vm.gc_stress = false;
    SolValue answered = sol_vm_call_block(&vm, got, NULL, 0);
    assert(!vm.had_error);
    assert(SOL_IS_INT(answered) && SOL_AS_INT(answered) == 42);

    sol_vm_free(&vm);
    sol_chunk_free(&chunk);
    printf("  a retained block survives collection and is still that block\n");
}

/* The other direction, so the test above is known to be testing something: an
   unretained block, unreachable from anywhere, is collected. */
static void test_an_unretained_block_is_collected(void)
{
    SolVM vm;
    sol_vm_init(&vm);

    SolChunk chunk;
    a_block(&vm, &chunk, "answer := { #42 }.");
    sol_vm_set_global(&vm, "answer", SOL_NIL_VAL);

    int before = sol_gc_live_count(&vm);
    sol_gc_collect(&vm);
    int after = sol_gc_live_count(&vm);

    assert(after < before);          /* something went, and the block is what */

    sol_vm_free(&vm);
    sol_chunk_free(&chunk);
    printf("  an unretained one is collected, so the case above is a real one\n");
}

/* ---- the failure the registry must not reproduce ------------------------- */

/* **The case this design exists for.** A token outliving its slot must answer
   *nothing*, not the value that was retained into that slot afterwards. Without
   the generation counter this is the collector's silent misdispatch moved one
   layer up: a plausible wrong block, confidently returned. */
static void test_a_stale_token_answers_nothing(void)
{
    SolVM vm;
    sol_vm_init(&vm);

    SolChunk first, second;
    SolValue one = a_block(&vm, &first, "answer := { #1 }.");
    SolRetained token = sol_extension_retain(&vm, one);
    assert(sol_extension_release(&vm, token));

    /* The next retain takes the slot that was just freed -- which is the whole
       point of a free list, and the whole danger. */
    SolValue two = a_block(&vm, &second, "answer := { #2 }.");
    SolRetained reused = sol_extension_retain(&vm, two);

    /* Same index, and the tokens are still not the same. */
    assert((reused & 0xffffffffu) == (token & 0xffffffffu));
    assert(reused != token);

    SolValue got = SOL_INT_VAL(-1);
    assert(!sol_extension_retained(&vm, token, &got));
    assert(SOL_IS_INT(got) && SOL_AS_INT(got) == -1);   /* out left untouched */

    /* And the live token is unharmed by the dead one being asked about. */
    assert(sol_extension_retained(&vm, reused, &got));
    assert(SOL_AS_BLOCK(got) == SOL_AS_BLOCK(two));

    sol_vm_free(&vm);
    sol_chunk_free(&first);
    sol_chunk_free(&second);
    printf("  a token whose slot was reused answers nothing, not the new value\n");
}

static void test_a_token_that_was_never_valid_answers_nothing(void)
{
    SolVM vm;
    sol_vm_init(&vm);

    SolValue got = SOL_INT_VAL(-1);
    assert(!sol_extension_retained(&vm, SOL_RETAINED_NONE, &got));
    assert(!sol_extension_retained(&vm, 999999, &got));
    assert(!sol_extension_retained(&vm, (SolRetained)-1, &got));
    assert(SOL_IS_INT(got) && SOL_AS_INT(got) == -1);

    assert(!sol_extension_release(&vm, SOL_RETAINED_NONE));
    assert(!sol_extension_release(&vm, 999999));

    sol_vm_free(&vm);
    printf("  a token that was never valid answers nothing, and does not crash\n");
}

static void test_releasing_twice_is_not_an_error(void)
{
    SolVM vm;
    sol_vm_init(&vm);

    SolChunk chunk;
    SolValue block = a_block(&vm, &chunk, "answer := { #42 }.");
    SolRetained token = sol_extension_retain(&vm, block);

    assert(sol_extension_release(&vm, token));
    assert(!sol_extension_release(&vm, token));
    assert(!sol_extension_retained(&vm, token, NULL));

    sol_vm_free(&vm);
    sol_chunk_free(&chunk);
    printf("  releasing twice is not an error and says so the second time\n");
}

/* Not reference counted, and the direction of the mistake matters: retaining
   twice and releasing once leaves it rooted, which is a leak rather than a
   dangling value. */
static void test_two_retains_are_two_tokens(void)
{
    SolVM vm;
    sol_vm_init(&vm);

    SolChunk chunk;
    SolValue block = a_block(&vm, &chunk, "answer := { #42 }.");
    sol_vm_set_global(&vm, "answer", SOL_NIL_VAL);

    SolRetained a = sol_extension_retain(&vm, block);
    SolRetained b = sol_extension_retain(&vm, block);
    assert(a != b);

    assert(sol_extension_release(&vm, a));
    sol_gc_collect(&vm);

    /* Still rooted by the second, and still the same block. */
    SolValue got;
    assert(sol_extension_retained(&vm, b, &got));
    assert(SOL_AS_BLOCK(got) == SOL_AS_BLOCK(block));

    sol_vm_free(&vm);
    sol_chunk_free(&chunk);
    printf("  two retains are two tokens, and one release leaves it rooted\n");
}

/* ---- the table itself ---------------------------------------------------- */

/* The free list has to be right for more than one slot, and the table has to
   grow. Nothing may shift while it does: a token is an index. */
static void test_many_retained_and_released_keep_their_identities(void)
{
    SolVM vm;
    sol_vm_init(&vm);

    enum { MANY = 200 };
    SolChunk chunks[MANY];
    SolValue blocks[MANY];
    SolRetained tokens[MANY];

    for (int i = 0; i < MANY; i++) {
        char source[64];
        snprintf(source, sizeof source, "answer := { #%d }.", i);
        blocks[i] = a_block(&vm, &chunks[i], source);
        tokens[i] = sol_extension_retain(&vm, blocks[i]);
    }
    sol_vm_set_global(&vm, "answer", SOL_NIL_VAL);

    /* Release every other one, then retain into the holes, then check that
       every surviving token still names what it named. */
    for (int i = 0; i < MANY; i += 2) assert(sol_extension_release(&vm, tokens[i]));
    sol_gc_collect(&vm);

    for (int i = 0; i < MANY; i += 2) {
        tokens[i] = sol_extension_retain(&vm, blocks[i + 1 < MANY ? i + 1 : i]);
    }
    sol_gc_collect(&vm);

    for (int i = 1; i < MANY; i += 2) {
        SolValue got;
        assert(sol_extension_retained(&vm, tokens[i], &got));
        assert(SOL_AS_BLOCK(got) == SOL_AS_BLOCK(blocks[i]));
    }

    sol_vm_free(&vm);
    for (int i = 0; i < MANY; i++) sol_chunk_free(&chunks[i]);
    printf("  two hundred retained and half released keep their identities\n");
}

/* Anything still retained when the machine goes down goes with it -- so an
   extension that never releases leaks nothing beyond the VM's own life. Run
   under a sanitiser, this is the case that would say otherwise. */
static void test_what_is_still_retained_goes_with_the_machine(void)
{
    SolVM vm;
    sol_vm_init(&vm);

    SolChunk chunk;
    SolValue block = a_block(&vm, &chunk, "answer := { #42 }.");
    for (int i = 0; i < 50; i++) sol_extension_retain(&vm, block);

    sol_vm_free(&vm);                 /* and nothing is released by hand */
    sol_chunk_free(&chunk);
    printf("  what is still retained is let go when the machine is\n");
}

/* A retained *foreign* cell is a resource with a release, and being retained
   must postpone that release rather than skip it. */
static int releases;
static void count_release(void *handle) { (void)handle; releases++; }

static void test_a_retained_resource_is_given_back_when_released(void)
{
    releases = 0;

    SolVM vm;
    sol_vm_init(&vm);

    SolValue socket = SOL_FOREIGN_VAL(
        sol_foreign_new(&vm, (void *)(long)0x1234, count_release, "socket", 0));
    SolRetained token = sol_extension_retain(&vm, socket);

    sol_gc_collect(&vm);
    assert(releases == 0);            /* retained, so still open */

    assert(sol_extension_release(&vm, token));
    sol_gc_collect(&vm);
    assert(releases == 1);            /* and now nothing holds it */

    sol_vm_free(&vm);
    assert(releases == 1);
    printf("  retaining a resource postpones its release rather than skipping it\n");
}

int main(void)
{
    printf("keeping a value alive between calls\n");
    test_a_retained_block_survives_collection();
    test_an_unretained_block_is_collected();
    test_a_stale_token_answers_nothing();
    test_a_token_that_was_never_valid_answers_nothing();
    test_releasing_twice_is_not_an_error();
    test_two_retains_are_two_tokens();
    test_many_retained_and_released_keep_their_identities();
    test_what_is_still_retained_goes_with_the_machine();
    test_a_retained_resource_is_given_back_when_released();
    printf("ok\n");
    return 0;
}
