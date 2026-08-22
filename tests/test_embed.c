/* The embedding contract: what a host may rely on.
 *
 * docs/embedding.md is the prose and this is what holds it. Every promise that
 * page makes has a case here, so a change that breaks a host fails the build
 * rather than being discovered by somebody else's program -- which is exactly
 * how the 0.14.1 use-after-free got out, there having been nothing to state and
 * therefore nothing to check.
 *
 * These deliberately do what a host does and not what a test finds convenient:
 * VMs are built inside called functions, chunks outlive the machines that ran
 * them, and one chunk serves several. A test that holds two VMs as locals of
 * one function is the shape that missed the defect. */
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "solas/compiler.h"
#include "solum/embed.h"
#include "solum/object.h"

static void compile(SolChunk *chunk, const char *source)
{
    sol_chunk_init(chunk);
    assert(sol_compile_source(source, "<test>", chunk));
}

/* ---- values in and out -------------------------------------------------- */

static void test_text_goes_in_and_comes_back(void)
{
    SolChunk chunk;
    compile(&chunk, "answer := request:asUppercase:concat(\"!\").");

    SolVM vm;
    sol_vm_init(&vm);
    sol_vm_set_global_text(&vm, "request", "hello");

    assert(sol_vm_run(&vm, &chunk) == SOL_OK);

    char *answer = sol_vm_global_text(&vm, "answer");
    assert(answer != NULL);
    assert(strcmp(answer, "\"HELLO!\"") == 0);   /* rendered, as `print` shows */
    free(answer);

    sol_vm_free(&vm);
    sol_chunk_free(&chunk);
    printf("  text handed in comes back out\n");
}

/* The text form outlives the machine, which is the whole reason it copies. */
static char *run_and_take_the_answer(const char *source)
{
    SolChunk chunk;
    compile(&chunk, source);

    SolVM vm;
    sol_vm_init(&vm);
    char *answer = NULL;
    if (sol_vm_run(&vm, &chunk) == SOL_OK) answer = sol_vm_global_text(&vm, "answer");

    sol_vm_free(&vm);
    sol_chunk_free(&chunk);       /* after the VM, never before */
    return answer;
}

static void test_the_answer_outlives_the_machine(void)
{
    char *answer = run_and_take_the_answer(
        "answer := [#1, #2, #3]:inject(#0, { a, b | a:add(b) }).");
    assert(answer != NULL);
    assert(strcmp(answer, "#6") == 0);
    free(answer);
    printf("  the answer outlives the machine that made it\n");
}

static void test_an_unbound_name_answers_nothing(void)
{
    SolChunk chunk;
    compile(&chunk, "x := #1.");

    SolVM vm;
    sol_vm_init(&vm);
    assert(sol_vm_run(&vm, &chunk) == SOL_OK);

    SolValue value;
    assert(!sol_vm_global(&vm, "nosuchname", &value));
    assert(sol_vm_global_text(&vm, "nosuchname") == NULL);

    /* And a name that is bound answers the value itself, not only its text. */
    assert(sol_vm_global(&vm, "x", &value));
    assert(SOL_AS_INT(value) == 1);

    sol_vm_free(&vm);
    sol_chunk_free(&chunk);
    printf("  an unbound name answers nothing, a bound one answers its value\n");
}

/* A host usually has text, but it may hand over any value it can build. */
static void test_a_value_may_be_handed_in(void)
{
    SolChunk chunk;
    compile(&chunk, "answer := seed:mul(#7).");

    SolVM vm;
    sol_vm_init(&vm);
    sol_vm_set_global(&vm, "seed", SOL_INT_VAL(6));
    assert(sol_vm_run(&vm, &chunk) == SOL_OK);

    SolValue answer;
    assert(sol_vm_global(&vm, "answer", &answer));
    assert(SOL_AS_INT(answer) == 42);

    sol_vm_free(&vm);
    sol_chunk_free(&chunk);
    printf("  a value handed in is an ordinary global\n");
}

/* Binding a string allocates, and the define that follows it allocates too, so
   the string must stay rooted in between. Under stress this collects on every
   allocation, which is what would find it if it did not. */
static void test_handing_text_in_is_collection_safe(void)
{
    SolChunk chunk;
    compile(&chunk, "answer := a:concat(b):concat(c).");

    SolVM vm;
    sol_vm_init(&vm);
    vm.gc_stress = true;
    sol_vm_set_global_text(&vm, "a", "one ");
    sol_vm_set_global_text(&vm, "b", "two ");
    sol_vm_set_global_text(&vm, "c", "three");

    assert(sol_vm_run(&vm, &chunk) == SOL_OK);
    char *answer = sol_vm_global_text(&vm, "answer");
    assert(answer != NULL && strcmp(answer, "\"one two three\"") == 0);
    free(answer);

    sol_vm_free(&vm);
    sol_chunk_free(&chunk);
    printf("  handing text in survives a collection on every allocation\n");
}

/* ---- one chunk, many machines ------------------------------------------- */

/* The shape a host actually has: the VM is a local of the function that serves
   one request, so every request builds it at the same address. This is what the
   0.14.1 defect needed and what nothing here had ever done. */
static SolResult serve(SolChunk *chunk, int input, long *answer)
{
    SolVM vm;
    sol_vm_init(&vm);
    sol_vm_set_global(&vm, "input", SOL_INT_VAL(input));

    SolResult result = sol_vm_run(&vm, chunk);
    if (result == SOL_OK) {
        SolValue value;
        assert(sol_vm_global(&vm, "answer", &value));
        *answer = (long)SOL_AS_INT(value);
    }
    sol_vm_free(&vm);
    return result;
}

static void test_one_chunk_serves_many_machines(void)
{
    SolChunk chunk;
    compile(&chunk, "answer := input:mul(input):add(#1).");

    for (int i = 1; i <= 8; i++) {
        long answer = 0;
        assert(serve(&chunk, i, &answer) == SOL_OK);
        assert(answer == (long)i * i + 1);
    }

    sol_chunk_free(&chunk);
    printf("  one chunk serves eight machines built at one address\n");
}

/* ---- the allowance ------------------------------------------------------ */

static SolResult serve_with_limits(SolChunk *chunk, uint64_t steps, size_t memory)
{
    SolVM vm;
    sol_vm_init(&vm);
    sol_vm_set_step_limit(&vm, steps);
    sol_vm_set_memory_limit(&vm, memory);

    SolResult result = sol_vm_run(&vm, chunk);
    sol_vm_free(&vm);
    return result;
}

static void test_the_allowance_is_per_run(void)
{
    SolChunk chunk;
    compile(&chunk, "n := #0. { n:lessThan(#2000) }:whileTrue({ n := n:add(#1) }).");

    /* Starved, then not, then starved again -- and the middle one is unaffected
       by the run before it. A budget that carried over would fail this. */
    assert(serve_with_limits(&chunk, 50, 0) == SOL_STOPPED);
    assert(serve_with_limits(&chunk, 0, 0) == SOL_OK);
    assert(serve_with_limits(&chunk, 50, 0) == SOL_STOPPED);
    assert(serve_with_limits(&chunk, 0, 0) == SOL_OK);

    sol_chunk_free(&chunk);
    printf("  the allowance is per run, not per machine\n");
}

/* Zero lifts a limit, which is the default and is what every front end that
   does not offer one relies on. */
static void test_zero_is_no_limit(void)
{
    SolChunk chunk;
    compile(&chunk, "n := #0. { n:lessThan(#5000) }:whileTrue({ n := n:add(#1) }).");
    assert(serve_with_limits(&chunk, 0, 0) == SOL_OK);
    sol_chunk_free(&chunk);
    printf("  zero is no limit\n");
}

/* ---- how a run ended ---------------------------------------------------- */

static SolResult outcome(const char *source, int *status)
{
    SolChunk chunk;
    compile(&chunk, source);

    SolVM vm;
    sol_vm_init(&vm);
    sol_vm_set_step_limit(&vm, 100000);

    SolResult result = sol_vm_run(&vm, &chunk);
    if (status != NULL) *status = vm.exit_code;

    sol_vm_free(&vm);
    sol_chunk_free(&chunk);
    return result;
}

static void test_the_five_endings_are_distinct(void)
{
    int status = -1;

    assert(outcome("x := #1.", NULL) == SOL_OK);
    assert(outcome("system:exit(#3).", &status) == SOL_EXIT && status == 3);
    assert(outcome("nil:boom.", NULL) == SOL_RUNTIME_ERROR);

    /* And a stop, which is neither of the two above: the program did not
       finish and did not ask to stop. */
    SolChunk chunk;
    compile(&chunk, "n := #0. { true }:whileTrue({ n := n:add(#1) }).");
    assert(serve_with_limits(&chunk, 500, 0) == SOL_STOPPED);
    sol_chunk_free(&chunk);

    printf("  ok, exit, failed and stopped are told apart\n");
}

/* ---- what went wrong ---------------------------------------------------- */

static void test_a_host_can_read_the_failure(void)
{
    SolChunk chunk;
    compile(&chunk, "x := #1.\nnil:boom.\n");

    SolVM vm;
    sol_vm_init(&vm);
    assert(sol_vm_run(&vm, &chunk) == SOL_RUNTIME_ERROR);

    const char *message = sol_vm_error_message(&vm);
    const char *trace   = sol_vm_error_trace(&vm);
    assert(message != NULL);
    assert(strstr(message, "boom") != NULL);
    assert(trace != NULL && strstr(trace, "<test>:2") != NULL);

    sol_vm_free(&vm);
    sol_chunk_free(&chunk);
    printf("  a host can read the message and the trace of a failed run\n");
}

/* A run that went well leaves nothing to report, and the next run clears what
   the last one left -- so a host testing the message is testing this run. */
static void test_the_failure_is_this_run_s(void)
{
    SolChunk bad, good;
    compile(&bad, "nil:boom.");
    compile(&good, "x := #1.");

    SolVM vm;
    sol_vm_init(&vm);

    assert(sol_vm_run(&vm, &bad) == SOL_RUNTIME_ERROR);
    assert(sol_vm_error_message(&vm) != NULL);

    assert(sol_vm_run(&vm, &good) == SOL_OK);
    assert(sol_vm_error_message(&vm) == NULL);
    assert(sol_vm_error_trace(&vm) == NULL);

    sol_vm_free(&vm);
    sol_chunk_free(&bad);
    sol_chunk_free(&good);
    printf("  a run clears what the last one left\n");
}

/* And a stop says which limit, since that is what a host has to act on. */
static void test_a_stop_says_which_limit(void)
{
    SolChunk chunk;
    compile(&chunk, "n := #0. { true }:whileTrue({ n := n:add(#1) }).");

    SolVM vm;
    sol_vm_init(&vm);
    sol_vm_set_step_limit(&vm, 400);
    assert(sol_vm_run(&vm, &chunk) == SOL_STOPPED);

    const char *message = sol_vm_error_message(&vm);
    assert(message != NULL && strstr(message, "step limit") != NULL);

    sol_vm_free(&vm);
    sol_chunk_free(&chunk);
    printf("  a stop says which limit stopped it\n");
}

/* ---- arguments ---------------------------------------------------------- */

static void test_arguments_reach_the_script(void)
{
    SolChunk chunk;
    compile(&chunk, "answer := system:arguments:join(\"-\").");

    char *args[] = { (char *)"one", (char *)"two" };
    SolVM vm;
    sol_vm_init(&vm);
    sol_vm_set_arguments(&vm, 2, args);
    assert(sol_vm_run(&vm, &chunk) == SOL_OK);

    char *answer = sol_vm_global_text(&vm, "answer");
    assert(answer != NULL && strcmp(answer, "\"one-two\"") == 0);
    free(answer);

    sol_vm_free(&vm);
    sol_chunk_free(&chunk);
    printf("  arguments given from C reach system:arguments\n");
}

int main(void)
{
    printf("the embedding contract\n");
    test_text_goes_in_and_comes_back();
    test_the_answer_outlives_the_machine();
    test_an_unbound_name_answers_nothing();
    test_a_value_may_be_handed_in();
    test_handing_text_in_is_collection_safe();
    test_one_chunk_serves_many_machines();
    test_the_allowance_is_per_run();
    test_zero_is_no_limit();
    test_the_five_endings_are_distinct();
    test_a_host_can_read_the_failure();
    test_the_failure_is_this_run_s();
    test_a_stop_says_which_limit();
    test_arguments_reach_the_script();
    printf("ok\n");
    return 0;
}
