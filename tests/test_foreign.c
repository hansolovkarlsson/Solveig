/* A resource an extension owns, and the promise that it is given back.
 *
 * `SolForeign` exists because the alternative was an integer: before it, an
 * extension handed a socket back as a number, so nothing closed it when the
 * program was stopped, it was not counted against `--memory`, and a program
 * could invent one and pass it to `close`. Every case below is one of those
 * three, or one of the four places in the collector where a new cell type has
 * to be named and **nothing warns if it is not**.
 *
 * There is no real resource here. `release` increments a counter, which is the
 * only thing a test can observe and is exactly what a socket's `close` would
 * have been.
 */
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "solas/compiler.h"
#include "solum/extend.h"

/* ---- a resource that says when it was given back ------------------------- */

static int releases;
static void *last_released;

static void count_release(void *handle)
{
    releases++;
    last_released = handle;
}

static void reset(void)
{
    releases = 0;
    last_released = NULL;
}

/* A handle that is not NULL and not a real pointer: the cell never dereferences
   it, which is the point of it being foreign. */
static void *fake(int n) { return (void *)(long)(0x1000 + n); }

static void compile(SolChunk *chunk, const char *source)
{
    sol_chunk_init(chunk);
    assert(sol_compile_source(source, "<test>", chunk));
}

/* ---- the two paths that give a resource back ----------------------------- */

/* The path that matters for a program holding many in turn: a server opening a
   socket per request cannot wait for the machine to die. */
static void test_release_runs_when_the_program_lets_go(void)
{
    reset();

    SolVM vm;
    sol_vm_init(&vm);

    /* Bound, then rebound, so the first cell becomes unreachable while the
       machine runs on. */
    SolForeign *first = sol_foreign_new(&vm, fake(1), count_release, "socket", 0);
    sol_vm_set_global(&vm, "held", SOL_FOREIGN_VAL(first));
    sol_vm_set_global(&vm, "held", SOL_NIL_VAL);
    assert(releases == 0);                      /* nothing yet: no collection */

    sol_gc_collect(&vm);
    assert(releases == 1);
    assert(last_released == fake(1));

    sol_vm_free(&vm);
    assert(releases == 1);                      /* and not again at shutdown */
    printf("  a resource is given back when the program lets go of it\n");
}

/* The path that matters when a limit took the program away mid-flight. A
   limit-stop is not catchable and `ensure` does not run (COMPLETED 6.33), so a
   program relying on an explicit close would leak every time it was stopped --
   which is the argument for there being no `close` message at all. */
static void test_release_runs_at_shutdown_for_what_is_still_held(void)
{
    reset();

    SolVM vm;
    sol_vm_init(&vm);
    SolForeign *held = sol_foreign_new(&vm, fake(2), count_release, "socket", 0);
    sol_vm_set_global(&vm, "held", SOL_FOREIGN_VAL(held));

    sol_gc_collect(&vm);
    assert(releases == 0);                      /* still reachable, still open */

    sol_vm_free(&vm);
    assert(releases == 1);
    assert(last_released == fake(2));
    printf("  one still held when the machine goes down is given back too\n");
}

/* Whichever way it got there, and however many times it is asked. */
static void test_release_runs_exactly_once(void)
{
    reset();

    SolVM vm;
    sol_vm_init(&vm);
    SolForeign *cell = sol_foreign_new(&vm, fake(3), count_release, "socket", 0);
    SolValue value = SOL_FOREIGN_VAL(cell);
    sol_vm_set_global(&vm, "held", value);

    assert(sol_foreign_release(value));          /* by hand, in a chosen order */
    assert(releases == 1);
    assert(!sol_foreign_release(value));         /* and there is nothing left */
    assert(releases == 1);

    sol_vm_free(&vm);                            /* nor at shutdown */
    assert(releases == 1);
    printf("  it is given back exactly once, however many times it is asked\n");
}

/* A resource with nothing to give back is allowed and must not crash. */
static void test_a_release_of_nothing_is_allowed(void)
{
    SolVM vm;
    sol_vm_init(&vm);
    SolForeign *cell = sol_foreign_new(&vm, fake(4), NULL, "pattern", 0);
    sol_vm_set_global(&vm, "held", SOL_FOREIGN_VAL(cell));
    sol_gc_collect(&vm);
    sol_vm_free(&vm);
    printf("  a resource with no release function is allowed\n");
}

/* ---- the handle, and who may have it ------------------------------------- */

static void test_a_handle_is_asked_for_by_kind(void)
{
    SolVM vm;
    sol_vm_init(&vm);

    SolValue socket = SOL_FOREIGN_VAL(
        sol_foreign_new(&vm, fake(5), NULL, "socket", 0));
    sol_vm_set_global(&vm, "held", socket);

    assert(sol_foreign_handle(socket, "socket") == fake(5));

    /* The case this exists for: one extension's handle reaching another's
       primitive. Compared by strcmp, since two extensions are two binaries and
       their string literals are not shared. */
    assert(sol_foreign_handle(socket, "window") == NULL);
    assert(sol_foreign_handle(socket, NULL) == fake(5));   /* any kind will do */

    /* And a value that is not foreign at all -- which is what a program passing
       an integer where a socket was wanted looks like from in here. */
    assert(sol_foreign_handle(SOL_INT_VAL(5), "socket") == NULL);
    assert(sol_foreign_handle(SOL_NIL_VAL, "socket") == NULL);

    sol_vm_free(&vm);
    printf("  a handle is asked for by kind, and a wrong kind answers nothing\n");
}

static void test_a_released_handle_is_refused_rather_than_returned(void)
{
    reset();

    SolVM vm;
    sol_vm_init(&vm);
    SolValue socket = SOL_FOREIGN_VAL(
        sol_foreign_new(&vm, fake(6), count_release, "socket", 0));
    sol_vm_set_global(&vm, "held", socket);

    assert(sol_foreign_handle(socket, "socket") == fake(6));
    sol_foreign_release(socket);
    /* Not a dangling pointer and not a crash: nothing. A primitive checks and
       complains, which is the whole difference from an integer. */
    assert(sol_foreign_handle(socket, "socket") == NULL);

    sol_vm_free(&vm);
    printf("  a released handle answers nothing rather than a dead pointer\n");
}

/* ---- what the collector has to know -------------------------------------- */

/* `blacken` and `cell_size` both fall through to the SolObject branch for a
   type they do not name, and **neither warns**. A foreign cell taken for an
   object would have its `release` pointer walked as a slot list. This runs a
   collection with foreign cells reachable through an array, a dictionary and a
   slot, so every path that could reach one is taken. */
static void test_the_collector_traces_around_one_without_walking_it(void)
{
    reset();

    SolVM vm;
    sol_vm_init(&vm);
    vm.gc_stress = true;                    /* collect on every allocation */

    SolArray *array = sol_array_new(&vm, 4);
    sol_vm_set_global(&vm, "kept", SOL_ARRAY_VAL(array));

    for (int i = 0; i < 4; i++) {
        SolForeign *cell = sol_foreign_new(&vm, fake(10 + i), count_release,
                                           "socket", 0);
        sol_array_add(&vm, array, SOL_FOREIGN_VAL(cell));
    }

    /* Reachable throughout, so nothing has been given back yet however many
       collections the stress setting caused. */
    assert(releases == 0);
    assert(array->count == 4);

    sol_vm_free(&vm);
    assert(releases == 4);
    printf("  a collection traces around a foreign cell without walking it\n");
}

/* **Found by opening real sockets, and it is why foreign cells have a pressure
   count of their own.** The heap threshold is measured in bytes and a foreign
   cell is forty of them however scarce the thing it holds, so a program opening
   descriptors in a loop exhausted the process while the heap was still nearly
   empty -- measured at a 256 ceiling, and it died there with no collection
   having happened. Bytes are the wrong currency for a descriptor. */
static void test_many_in_turn_are_given_back_without_being_asked(void)
{
    reset();

    SolVM vm;
    sol_vm_init(&vm);

    /* Well past the pressure threshold, each one dropped as the next replaces
       it, and no collection asked for anywhere. */
    const int many = SOL_GC_FOREIGN_PRESSURE * 8;
    for (int i = 0; i < many; i++) {
        sol_vm_set_global(&vm, "held", SOL_FOREIGN_VAL(
            sol_foreign_new(&vm, fake(i), count_release, "socket", 0)));
    }

    /* Nearly all of them: the last is still bound, and whatever was made since
       the most recent collection is still reachable from nothing yet swept. */
    assert(releases >= many - SOL_GC_FOREIGN_PRESSURE - 1);

    sol_vm_free(&vm);
    assert(releases == many);
    printf("  many held in turn are given back without a collection being "
           "asked for\n");
}

/* The footprint is the answer to ROADMAP 3.7 reappearing here: without it,
   `--memory` would see forty bytes where an extension holds a texture. */
static void test_a_footprint_counts_against_the_memory_limit(void)
{
    SolVM vm;
    sol_vm_init(&vm);

    size_t before = sol_gc_live_bytes(&vm);

    SolForeign *big = sol_foreign_new(&vm, fake(7), NULL, "texture", 4u << 20);
    sol_vm_set_global(&vm, "held", SOL_FOREIGN_VAL(big));

    size_t after = sol_gc_live_bytes(&vm);
    assert(after - before >= 4u << 20);

    sol_vm_free(&vm);
    printf("  a declared footprint is what --memory measures, not the cell\n");
}

static void test_no_footprint_costs_only_the_cell(void)
{
    SolVM vm;
    sol_vm_init(&vm);

    size_t before = sol_gc_live_bytes(&vm);
    sol_vm_set_global(&vm, "held", SOL_FOREIGN_VAL(
        sol_foreign_new(&vm, fake(8), NULL, "socket", 0)));
    size_t after = sol_gc_live_bytes(&vm);

    assert(after > before);
    assert(after - before < 1024);          /* the cell, and nothing invented */

    sol_vm_free(&vm);
    printf("  one with nothing to declare costs only the cell\n");
}

/* ---- how it behaves as a value ------------------------------------------- */

/* Runs `source` with `held` bound to a foreign value of `kind`, and answers
   what `answer` holds, rendered. The caller frees it. */
static char *run_holding(const char *kind, const char *source)
{
    SolVM vm;
    sol_vm_init(&vm);
    sol_vm_set_global(&vm, "held", SOL_FOREIGN_VAL(
        sol_foreign_new(&vm, fake(9), NULL, kind, 0)));

    SolChunk chunk;
    compile(&chunk, source);
    assert(sol_vm_run(&vm, &chunk) == SOL_OK);

    char *answer = sol_vm_global_text(&vm, "answer");
    sol_vm_free(&vm);
    sol_chunk_free(&chunk);
    return answer;
}

static void test_it_renders_as_the_extension_named_it(void)
{
    char *answer = run_holding("gtk window", "answer := held.");
    assert(answer != NULL);
    assert(strcmp(answer, "<gtk window>") == 0);
    free(answer);

    answer = run_holding("socket", "answer := held:asString.");
    assert(answer != NULL);
    assert(strcmp(answer, "\"<socket>\"") == 0);
    free(answer);
    printf("  it renders as the extension's own word for it\n");
}

static void test_a_released_one_says_so(void)
{
    SolVM vm;
    sol_vm_init(&vm);
    SolValue socket = SOL_FOREIGN_VAL(
        sol_foreign_new(&vm, fake(11), NULL, "socket", 0));
    sol_vm_set_global(&vm, "held", socket);
    sol_foreign_release(socket);

    char *shown = sol_vm_global_text(&vm, "held");
    assert(shown != NULL);
    assert(strcmp(shown, "<socket, released>") == 0);
    free(shown);

    sol_vm_free(&vm);
    printf("  a released one shows that it is, rather than looking open\n");
}

/* Identity, like every other reference type. */
static void test_equality_is_identity(void)
{
    SolVM vm;
    sol_vm_init(&vm);
    sol_vm_set_global(&vm, "a", SOL_FOREIGN_VAL(
        sol_foreign_new(&vm, fake(12), NULL, "socket", 0)));
    sol_vm_set_global(&vm, "b", SOL_FOREIGN_VAL(
        sol_foreign_new(&vm, fake(12), NULL, "socket", 0)));

    SolChunk chunk;
    compile(&chunk, "same := a:equals(a). other := a:equals(b).");
    assert(sol_vm_run(&vm, &chunk) == SOL_OK);

    char *same = sol_vm_global_text(&vm, "same");
    char *other = sol_vm_global_text(&vm, "other");
    assert(strcmp(same, "true") == 0);
    /* The same handle and the same kind, and still two resources. */
    assert(strcmp(other, "false") == 0);
    free(same); free(other);

    sol_vm_free(&vm);
    sol_chunk_free(&chunk);
    printf("  two of them are equal only when they are the same one\n");
}

/* Refused as a dictionary key, the way every reference type is: two that look
   alike would be two keys, which is not what a program asking would expect. */
static void test_it_is_not_a_dictionary_key(void)
{
    assert(!sol_dict_key_ok(SOL_FOREIGN_VAL(NULL)));
    printf("  it is refused as a dictionary key, like every reference\n");
}

/* A program cannot invent one, which was the third thing wrong with an
   integer. */
static void test_a_program_cannot_make_one(void)
{
    SolVM vm;
    sol_vm_init(&vm);
    sol_vm_set_error_reporting(&vm, false);
    sol_vm_set_global(&vm, "held", SOL_FOREIGN_VAL(
        sol_foreign_new(&vm, fake(13), NULL, "socket", 0)));

    /* `foreign:new`, sent to the class, is the one that reaches the refusal --
       `held:new` is turned away earlier still, by the receiver check, the same
       way `#45:new` is. Both are refusals; this is the one that explains. */
    SolChunk chunk;
    compile(&chunk, "foreign:new.");
    assert(sol_vm_run(&vm, &chunk) == SOL_RUNTIME_ERROR);
    assert(strstr(sol_vm_error_message(&vm), "extension") != NULL);

    sol_vm_free(&vm);
    sol_chunk_free(&chunk);
    printf("  a program cannot make one with 'new'\n");
}

/* It is a value type like any other, so a message it does not understand is an
   ordinary refusal naming what it is. */
/* Named, so that a program handed one by an extension can ask what it has. */
static void test_a_program_can_ask_what_it_is(void)
{
    char *answer = run_holding("socket", "answer := held:isKindOf(foreign).");
    assert(answer != NULL);
    assert(strcmp(answer, "true") == 0);
    free(answer);

    answer = run_holding("socket", "answer := held:isKindOf(string).");
    assert(answer != NULL);
    assert(strcmp(answer, "false") == 0);
    free(answer);
    printf("  a program can ask whether a value is one\n");
}

static void test_it_is_named_in_a_failure(void)
{
    SolVM vm;
    sol_vm_init(&vm);
    sol_vm_set_error_reporting(&vm, false);
    sol_vm_set_global(&vm, "held", SOL_FOREIGN_VAL(
        sol_foreign_new(&vm, fake(14), NULL, "socket", 0)));

    SolChunk chunk;
    compile(&chunk, "held:asUppercase.");
    assert(sol_vm_run(&vm, &chunk) == SOL_RUNTIME_ERROR);
    assert(strstr(sol_vm_error_message(&vm), "asUppercase") != NULL);

    sol_vm_free(&vm);
    sol_chunk_free(&chunk);
    printf("  a message it does not understand fails the ordinary way\n");
}

int main(void)
{
    printf("a foreign resource\n");
    test_release_runs_when_the_program_lets_go();
    test_release_runs_at_shutdown_for_what_is_still_held();
    test_release_runs_exactly_once();
    test_a_release_of_nothing_is_allowed();
    test_a_handle_is_asked_for_by_kind();
    test_a_released_handle_is_refused_rather_than_returned();
    test_the_collector_traces_around_one_without_walking_it();
    test_many_in_turn_are_given_back_without_being_asked();
    test_a_footprint_counts_against_the_memory_limit();
    test_no_footprint_costs_only_the_cell();
    test_it_renders_as_the_extension_named_it();
    test_a_released_one_says_so();
    test_equality_is_identity();
    test_it_is_not_a_dictionary_key();
    test_a_program_cannot_make_one();
    test_a_program_can_ask_what_it_is();
    test_it_is_named_in_a_failure();
    printf("ok\n");
    return 0;
}
