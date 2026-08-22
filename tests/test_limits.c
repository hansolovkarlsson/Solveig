/* What a host may lend a program: a number of instructions, and an amount of
 * memory to be holding at once.
 *
 * The interesting half is not that a limit stops a program -- that is a
 * counter -- but that the program cannot decline it. Everything a language
 * offers for dealing with failure is a way of running more code after
 * something went wrong, and running more code is exactly what there is no
 * longer any allowance for. So `onError` and `ensure` both have to let a stop
 * past untouched, and those are the tests worth having.
 */
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

/* The loop from the roadmap entry: written literally, so it compiles to jumps
   and enters no frames at all. Nothing that counted calls could see it go
   round, which is why the budget counts instructions. */
static void test_an_inlined_loop_is_stopped(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    sol_vm_set_step_limit(&vm, 10000);
    assert(run(&vm, &chunk,
        "reached := false."
        "i := #0."
        "{ true }:whileTrue({ i := i:inc })."
        "reached := true.") == SOL_STOPPED);

    /* It really was running: the counter got somewhere before it was stopped. */
    assert(SOL_IS_INT(global(&vm, "i")));
    assert(SOL_AS_INT(global(&vm, "i")) > 0);
    assert(SOL_AS_BOOL(global(&vm, "reached")) == false);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* A limit is spent, not merely reached: a program that finishes inside its
   allowance is not disturbed, and answers what it always would. */
static void test_a_program_inside_its_allowance_is_untouched(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    sol_vm_set_step_limit(&vm, 1000000);
    assert(run(&vm, &chunk,
        "total := #0."
        "#1:toDo(#100, { n | total := total:add(n) }).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "total")) == 5050);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* Zero is no limit, which is the default and what every other test in this
   repository has always run under. */
static void test_no_limit_is_the_default(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(vm.step_limit == 0);
    assert(vm.memory_limit == 0);
    assert(run(&vm, &chunk, "n := #0. #1:toDo(#10000, { i | n := n:inc }).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "n")) == 10000);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* The whole of what makes it a limit. A handler is code, and there is no
   allowance left to run code with. */
static void test_a_stop_cannot_be_caught(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    sol_vm_set_step_limit(&vm, 10000);
    assert(run(&vm, &chunk,
        "caught := false."
        "{ { true }:whileTrue({ nil }) }:onError({ e | caught := true })."
        "after := true.") == SOL_STOPPED);

    assert(SOL_AS_BOOL(global(&vm, "caught")) == false);
    assert(SOL_IS_NIL(global(&vm, "after")));

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* And `ensure`, which is the same argument by a different road: it works by
   setting the failure aside so the cleanup may run, and a program could
   otherwise put its work in the cleanup. */
static void test_a_stop_does_not_run_a_cleanup(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    sol_vm_set_step_limit(&vm, 10000);
    assert(run(&vm, &chunk,
        "cleaned := false."
        "{ { true }:whileTrue({ nil }) }:ensure({ cleaned := true }).") == SOL_STOPPED);

    assert(SOL_AS_BOOL(global(&vm, "cleaned")) == false);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* An ordinary failure is still ordinary. The limit did not make the language
   stop catching things, which is the regression this guards. */
static void test_an_error_is_still_catchable_under_a_limit(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    sol_vm_set_step_limit(&vm, 1000000);
    assert(run(&vm, &chunk,
        "caught := { nil:frobnicate }:onError({ e | #7 })."
        "cleaned := false."
        "{ { nil:boom }:ensure({ cleaned := true }) }:onError({ e | nil })."
        "after := true.") == SOL_OK);

    assert(SOL_AS_INT(global(&vm, "caught")) == 7);
    assert(SOL_AS_BOOL(global(&vm, "cleaned")) == true);
    assert(SOL_AS_BOOL(global(&vm, "after")) == true);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* An exit is the program's own decision and keeps its own answer, rather than
   being reported as though something took it away. */
static void test_an_exit_is_not_a_stop(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    sol_vm_set_step_limit(&vm, 1000000);
    assert(run(&vm, &chunk, "system:exit(#3).") == SOL_EXIT);
    assert(vm.exit_code == 3);
    assert(vm.stopped == false);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* The allowance is per run, not per VM: a server handing one machine a request
   and then another means each of them to have the whole of it. */
static void test_the_allowance_is_restored_for_each_run(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk first, second;

    sol_vm_set_step_limit(&vm, 20000);
    assert(run(&vm, &first, "{ true }:whileTrue({ nil }).") == SOL_STOPPED);

    /* The next run gets the whole limit again rather than the nothing the last
       one left behind. */
    assert(run(&vm, &second, "n := #1:add(#2).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "n")) == 3);

    sol_chunk_free(&second);
    sol_chunk_free(&first);
    sol_vm_free(&vm);
}

/* Holding is what is measured. This one holds everything it makes. */
static void test_holding_too_much_is_stopped(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    sol_vm_set_memory_limit(&vm, 512 * 1024);
    assert(run(&vm, &chunk,
        "held := array:new."
        "{ true }:whileTrue({ held:add(\"something kept forever\") }).") == SOL_STOPPED);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* And this one makes just as much and keeps none of it, under the same
   ceiling. The figure is live bytes after a collection, so a program is
   stopped for what it holds and not for what it has been through. */
static void test_allocating_without_holding_is_not_stopped(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    sol_vm_set_memory_limit(&vm, 512 * 1024);
    assert(run(&vm, &chunk,
        "i := #0."
        "{ i:lessThan(#20000) }:whileTrue({"
        "    scratch := \"a string made and dropped\":concat(i:asString)."
        "    i := i:inc })."
        "done := true.") == SOL_OK);
    assert(SOL_AS_BOOL(global(&vm, "done")) == true);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* A stop says so, and says which limit, and where the program had got to. */
static void test_a_stop_reports_which_limit_and_where(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    sol_vm_set_step_limit(&vm, 5000);
    assert(run(&vm, &chunk, "{ true }:whileTrue({ nil }).") == SOL_STOPPED);

    assert(strstr(vm.error_message.chars, "step limit") != NULL);
    assert(strstr(vm.error_message.chars, "5000") != NULL);
    assert(vm.error_trace.length > 0);
    assert(strstr(vm.error_trace.chars, "in script") != NULL);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* Nothing inside the language can read or change either limit. If a program
   could turn one off, it would not be a limit. */
static void test_no_message_reaches_the_limits(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    const char *attempts[] = {
        "system:setStepLimit(#0).",
        "system:stepLimit.",
        "system:setMemoryLimit(#0).",
        "system:memoryLimit.",
        "system:limits.",
    };

    for (size_t i = 0; i < sizeof attempts / sizeof attempts[0]; i++) {
        sol_vm_set_step_limit(&vm, 1000000);
        /* Not understood, rather than quietly doing something. */
        assert(run(&vm, &chunk, attempts[i]) == SOL_RUNTIME_ERROR);
        assert(strstr(vm.error_message.chars, "does not understand") != NULL);
        sol_chunk_free(&chunk);
    }

    sol_vm_free(&vm);
}

int main(void)
{
    test_an_inlined_loop_is_stopped();
    test_a_program_inside_its_allowance_is_untouched();
    test_no_limit_is_the_default();
    test_a_stop_cannot_be_caught();
    test_a_stop_does_not_run_a_cleanup();
    test_an_error_is_still_catchable_under_a_limit();
    test_an_exit_is_not_a_stop();
    test_the_allowance_is_restored_for_each_run();
    test_holding_too_much_is_stopped();
    test_allocating_without_holding_is_not_stopped();
    test_a_stop_reports_which_limit_and_where();
    test_no_message_reaches_the_limits();
    printf("test_limits: ok\n");
    return 0;
}
