/* One machine per thread.
 *
 * ROADMAP 3.11 said nothing was known about threads and that what would settle
 * it was a test rather than a decision. This is the test. It found two things,
 * and only the first was the one it was written to look for.
 *
 * **The serial was not atomic.** `sol_vm_init` stamped each machine from a
 * plain `next_vm_id++`, so two threads building one at the same time could be
 * handed the same number -- and a chunk they shared would then believe it was
 * already resolved for the second and dispatch against the first's name table.
 * That is the 0.14.1 use-after-free reappearing inside its own fix.
 *
 * The window looked negligible, three instructions inside a `sol_vm_init` that
 * takes 52us, and it was not: 16 threads building 480,000 machines produced
 * **10,319 duplicate serials**, a rate of 2.1%. A contended increment is
 * nothing like as brief as its instruction count. Fixed with `_Atomic` and
 * relaxed ordering; the same 480,000 then produced none.
 *
 * **And a chunk cannot be shared between threads at all**, which the fix does
 * not touch and no synchronisation inside the machine could. Running a chunk
 * *mutates* it -- the interned names are cached on it, keyed to one machine at
 * a time -- so two threads running one chunk free and rebuild that table under
 * each other. Eight threads, one chunk, 2,400 runs: a segmentation fault. The
 * same with the runs serialised behind a mutex: 0 failures of 2,400.
 *
 * So what is promised, and what these hold, is **one VM and one chunk per
 * thread**, with source text shared freely because reading text mutates
 * nothing. Two threads in one VM is not supported either: a machine has one
 * stack, one heap and one frame array, and nothing guards any of them.
 */
#include <assert.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "solas/compiler.h"
#include "solum/embed.h"

#define THREADS 8
#define EACH    4000

/* ---- serials ------------------------------------------------------------ */

static uint64_t serials[THREADS][EACH];

static void *build_machines(void *arg)
{
    long t = (long)arg;
    for (int i = 0; i < EACH; i++) {
        SolVM vm;
        sol_vm_init(&vm);
        serials[t][i] = vm.id;
        sol_vm_free(&vm);
    }
    return NULL;
}

static int by_value(const void *a, const void *b)
{
    uint64_t x = *(const uint64_t *)a, y = *(const uint64_t *)b;
    return x < y ? -1 : x > y ? 1 : 0;
}

/* No two machines may be handed one serial, however many threads are asking.
   This is what a chunk uses to tell one machine from another, so a repeat is
   not a cosmetic collision -- it is two machines claiming to be the same one. */
static void test_serials_are_unique_across_threads(void)
{
    pthread_t threads[THREADS];
    for (long t = 0; t < THREADS; t++)
        assert(pthread_create(&threads[t], NULL, build_machines, (void *)t) == 0);
    for (int t = 0; t < THREADS; t++)
        assert(pthread_join(threads[t], NULL) == 0);

    size_t total = (size_t)THREADS * EACH;
    uint64_t *all = malloc(total * sizeof *all);
    assert(all != NULL);

    size_t k = 0;
    for (int t = 0; t < THREADS; t++)
        for (int i = 0; i < EACH; i++) {
            assert(serials[t][i] != 0);      /* zero means "no VM yet" */
            all[k++] = serials[t][i];
        }
    qsort(all, total, sizeof *all, by_value);

    for (size_t i = 1; i < total; i++) {
        if (all[i] == all[i - 1]) {
            printf("\nserial %llu was handed to two machines\n",
                   (unsigned long long)all[i]);
            assert(false);
        }
    }
    free(all);
    printf("  %zu machines on %d threads, every serial its own\n", total, THREADS);
}

/* ---- a machine each ----------------------------------------------------- */

/* Each thread compiles its own source and runs it on its own machine, which is
   the shape a threaded host would have. Nothing is shared but the library. */
static void *run_alone(void *arg)
{
    long t = (long)arg;
    char source[128];
    snprintf(source, sizeof source, "answer := #%ld:mul(#%ld):add(#1).", t, t);

    for (int i = 0; i < 200; i++) {
        SolChunk chunk;
        sol_chunk_init(&chunk);
        assert(sol_compile_source(source, "<thread>", &chunk));

        SolVM vm;
        sol_vm_init(&vm);
        assert(sol_vm_run(&vm, &chunk) == SOL_OK);

        SolValue answer;
        assert(sol_vm_global(&vm, "answer", &answer));
        assert(SOL_AS_INT(answer) == t * t + 1);

        sol_vm_free(&vm);
        sol_chunk_free(&chunk);
    }
    return NULL;
}

static void test_each_thread_runs_its_own_machine(void)
{
    pthread_t threads[THREADS];
    for (long t = 0; t < THREADS; t++)
        assert(pthread_create(&threads[t], NULL, run_alone, (void *)t) == 0);
    for (int t = 0; t < THREADS; t++)
        assert(pthread_join(threads[t], NULL) == 0);
    printf("  %d threads, a machine and a chunk each, %d runs apiece\n",
           THREADS, 200);
}

/* ---- what may not be shared -------------------------------------------- *
 *
 * A chunk may not be. Running one *mutates* it: `sol_vm_intern_chunk` resolves
 * the names to the machine about to run them and caches the result on the
 * chunk, freeing whatever the last machine left. Two threads running one chunk
 * therefore free and rebuild that table under each other.
 *
 * Measured: eight threads, one chunk, 2,400 runs -- a segmentation fault. The
 * same eight threads and the same chunk with the runs serialised behind a
 * mutex -- 0 failures of 2,400. So the fault is entirely in the sharing and not
 * in anything else the machine does.
 *
 * There is no test here for that, deliberately: a test that provokes undefined
 * behaviour on purpose is a test that crashes the suite. It is written down in
 * ROADMAP 3.11 and in docs/embedding.md instead, and what is tested is the
 * shape that works -- one chunk per thread, compiled from whatever source the
 * threads care to share, since source is text and text is not mutated by being
 * read.
 */

static const char *SHARED_SOURCE = "answer := input:concat(input):asUppercase.";

static void *compile_and_run_own(void *arg)
{
    long t = (long)arg;
    char input[32];
    snprintf(input, sizeof input, "ab%ld", t);

    char expected[64];
    snprintf(expected, sizeof expected, "\"AB%ldAB%ld\"", t, t);

    /* One chunk of this thread's own, from source every thread reads. */
    SolChunk chunk;
    sol_chunk_init(&chunk);
    assert(sol_compile_source(SHARED_SOURCE, "<thread>", &chunk));

    for (int i = 0; i < 100; i++) {
        SolVM vm;
        sol_vm_init(&vm);
        sol_vm_set_global_text(&vm, "input", input);

        assert(sol_vm_run(&vm, &chunk) == SOL_OK);
        char *answer = sol_vm_global_text(&vm, "answer");
        assert(answer != NULL && strcmp(answer, expected) == 0);
        free(answer);

        sol_vm_free(&vm);
    }
    sol_chunk_free(&chunk);               /* after every machine that ran it */
    return NULL;
}

static void test_threads_share_source_not_chunks(void)
{
    pthread_t threads[THREADS];
    for (long t = 0; t < THREADS; t++)
        assert(pthread_create(&threads[t], NULL, compile_and_run_own, (void *)t) == 0);
    for (int t = 0; t < THREADS; t++)
        assert(pthread_join(threads[t], NULL) == 0);
    printf("  %d threads compile one source into a chunk each, 100 runs apiece\n",
           THREADS);
}

/* ---- and with the collector in the way ---------------------------------- *
 *
 * The same, collecting on every allocation. Each machine owns its heap and the
 * collector never leaves it, so this should be no different -- and a suite that
 * only ever ran the fast path would not be evidence of that.
 */
static void *run_own_under_stress(void *arg)
{
    (void)arg;
    SolChunk chunk;
    sol_chunk_init(&chunk);
    assert(sol_compile_source(SHARED_SOURCE, "<stress>", &chunk));

    for (int i = 0; i < 10; i++) {
        SolVM vm;
        sol_vm_init(&vm);
        vm.gc_stress = true;
        sol_vm_set_global_text(&vm, "input", "abc");

        assert(sol_vm_run(&vm, &chunk) == SOL_OK);
        char *answer = sol_vm_global_text(&vm, "answer");
        assert(answer != NULL && strcmp(answer, "\"ABCABC\"") == 0);
        free(answer);

        sol_vm_free(&vm);
    }
    sol_chunk_free(&chunk);
    return NULL;
}

static void test_collection_is_each_machine_s_own(void)
{
    pthread_t threads[THREADS];
    for (long t = 0; t < THREADS; t++)
        assert(pthread_create(&threads[t], NULL, run_own_under_stress, (void *)t) == 0);
    for (int t = 0; t < THREADS; t++)
        assert(pthread_join(threads[t], NULL) == 0);
    printf("  and again with a collection on every allocation\n");
}

int main(void)
{
    printf("one machine per thread\n");
    test_serials_are_unique_across_threads();
    test_each_thread_runs_its_own_machine();
    test_threads_share_source_not_chunks();
    test_collection_is_each_machine_s_own();
    printf("ok\n");
    return 0;
}
