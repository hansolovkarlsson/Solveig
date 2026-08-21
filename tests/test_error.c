/* Raising an error, and catching one.
 *
 * The catching half is where the interesting failures live. An error used to
 * unwind all the way to `sol_vm_run`, which resets the stack on its way out, so
 * nothing between the failure and the top had to leave things tidy. A handler
 * stops the unwind part-way, and everything the unwind used to be allowed to
 * leave behind is suddenly still there. */
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

/* The handler is given the error and its answer is the answer, so `onError` is
   an expression rather than a statement. */
static void test_catching_answers_something(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "caught := { nil:frobnicate }:onError({ e | e:message })."
        "fine := { #1:add(#2) }:onError({ e | #0 })."
        "failed := { nil:boom }:onError({ e | #0 })."
        /* the run as a whole succeeded: a caught error is not a failure */
        "after := #7.") == SOL_OK);

    assert(is_text(global(&vm, "caught"), "nil does not understand 'frobnicate'"));
    assert(SOL_AS_INT(global(&vm, "fine")) == 3);
    assert(SOL_AS_INT(global(&vm, "failed")) == 0);
    assert(SOL_AS_INT(global(&vm, "after")) == 7);
    assert(!vm.had_error);

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  onError answers the block's value, or the handler's\n");
}

/* A caught error says nothing. The whole reason the message stopped going
   straight to stderr was that a message already written cannot be taken back. */
static void test_a_caught_error_is_silent(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk, "{ nil:frobnicate }:onError({ e | nil }).") == SOL_OK);
    assert(vm.error_message.length == 0);
    assert(vm.error_trace.length == 0);
    assert(!vm.had_error);

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  a caught error leaves nothing to report\n");
}

static void test_raising(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "m := { error:raise(\"bad input\") }:onError({ e | e:message })."
        "kind := { error:raise(\"x\") }:onError({ e | e:isKindOf(error) })."
        "rooted := { error:raise(\"x\") }:onError({ e | e:isKindOf(object) })."
        "text := { error:raise(\"x\") }:onError({ e | e:message:isKindOf(string) }).")
        == SOL_OK);

    assert(is_text(global(&vm, "m"), "bad input"));
    assert(SOL_AS_BOOL(global(&vm, "kind")));
    assert(SOL_AS_BOOL(global(&vm, "rooted")));
    assert(SOL_AS_BOOL(global(&vm, "text")));
    sol_chunk_free(&chunk); sol_vm_free(&vm);

    /* Uncaught, a raised error stops the program like any other. */
    sol_vm_init(&vm);
    assert(run(&vm, &chunk, "error:raise(\"stop here\").") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk); sol_vm_free(&vm);

    static const char *refused[] = {
        "error:raise(#1).",
        "error:raise.",
        "error:raise(\"a\", \"b\").",
        "{ #1 }:onError.",
    };
    for (size_t i = 0; i < sizeof(refused) / sizeof(refused[0]); i++) {
        SolVM v; sol_vm_init(&v);
        SolChunk c;
        assert(run(&v, &c, refused[i]) == SOL_RUNTIME_ERROR);
        sol_chunk_free(&c); sol_vm_free(&v);
    }
    printf("  raising, and what a raise refuses\n");
}

/* Re-raising is `error:raise(e:message)`, there being one way to raise. */
static void test_re_raising_passes_it_on(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "inner := { { error:raise(\"deep\") }:onError({ e |"
        "    error:raise(e:message:concat(\" (passed on)\")) }) }."
        "seen := { inner:value }:onError({ e | e:message }).") == SOL_OK);
    assert(is_text(global(&vm, "seen"), "deep (passed on)"));
    sol_chunk_free(&chunk); sol_vm_free(&vm);

    /* And a handler that raises fails outward rather than catching itself. */
    sol_vm_init(&vm);
    assert(run(&vm, &chunk,
        "out := { { error:raise(\"first\") }:onError({ e | nil:boom }) }"
        "    :onError({ e | e:message }).") == SOL_OK);
    assert(is_text(global(&vm, "out"), "nil does not understand 'boom'"));
    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  a re-raise reaches the handler outside\n");
}

/* An exit is a stop rather than a failure and travels by the same flag, so it
   has to pass straight through something that was only watching for errors. */
static void test_an_exit_is_not_caught(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "reached := false."
        "{ system:exit(#4) }:onError({ e | reached := true })."
        "after := true.") == SOL_EXIT);

    assert(vm.exit_code == 4);
    assert(SOL_AS_BOOL(global(&vm, "reached")) == false);
    assert(SOL_IS_NIL(global(&vm, "after")));      /* nothing after it ran */

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  an exit passes through a handler\n");
}

/* The bug this whole thing nearly shipped with. `sol_vm_call_block` restored
   the frame count on failure but not the stack pointer, which was invisible
   while every error unwound to `sol_vm_run` -- that resets the stack. Catching
   stops the unwind, so the receiver and arguments of the failed call were still
   sitting there when execution resumed, and the next send found the wrong
   thing. `xs:add({ ... }:onError({ e | e }))` answered
   `block does not understand 'add'`. */
static void test_the_stack_is_left_as_it_was_found(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "xs := array:new."
        "xs:add({ error:raise(\"one\") }:onError({ e | e:message }))."
        "xs:add({ error:raise(\"two\") }:onError({ e | e:message }))."
        "n := xs:size. first := xs:at(#1). second := xs:at(#2).") == SOL_OK);

    assert(SOL_AS_INT(global(&vm, "n")) == 2);
    assert(is_text(global(&vm, "first"), "one"));
    assert(is_text(global(&vm, "second"), "two"));
    sol_chunk_free(&chunk); sol_vm_free(&vm);

    /* And it must not creep: many catches in a loop would overflow a stack that
       grew by a few slots each time. */
    sol_vm_init(&vm);
    assert(run(&vm, &chunk,
        "i := #0."
        "{ i:lessThan(#20000) }:whileTrue({"
        "    { nil:boom }:onError({ e | nil }). i := i:add(#1) })."
        "done := i.") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "done")) == 20000);
    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  a caught failure leaves the stack where it found it\n");
}

/* Errors are objects, allocated while a failure is being handled, so the
   collector has to keep them like anything else. */
static void test_errors_survive_collection(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "kept := array:new. i := #0."
        "{ i:lessThan(#200) }:whileTrue({"
        "    kept:add({ error:raise(\"number \":concat(i:asString)) }"
        "        :onError({ e | e }))."
        "    i := i:add(#1) }).") == SOL_OK);

    sol_gc_collect(&vm);
    sol_gc_collect(&vm);

    SolChunk after;
    assert(run(&vm, &after,
        "n := kept:size. first := kept:at(#1):message."
        "last := kept:at(#200):message."
        "kind := kept:at(#100):isKindOf(error).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "n")) == 200);
    assert(is_text(global(&vm, "first"), "number 0"));
    assert(is_text(global(&vm, "last"), "number 199"));
    assert(SOL_AS_BOOL(global(&vm, "kind")));

    sol_chunk_free(&chunk); sol_chunk_free(&after); sol_vm_free(&vm);
    printf("  errors are objects and survive collection\n");
}

/* An error raised inside a primitive that is part-way through a temp root must
   still leave the collector's temporaries balanced, or catching in a loop would
   exhaust them. */
static void test_catching_does_not_leak_temporaries(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "i := #0."
        "{ i:lessThan(#50) }:whileTrue({"
        "    { [#1, #2, #3]:collect({ x | nil:boom }) }:onError({ e | nil })."
        "    { [#1, #2]:inject(#0, { a, b | nil:boom }) }:onError({ e | nil })."
        "    { \"a,b\":split(\",\"):select({ s | #5 }) }:onError({ e | nil })."
        "    i := i:add(#1) }).") == SOL_OK);
    assert(vm.temp_count == 0);

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  catching leaves the collector's temporaries balanced\n");
}

/* ---- ensure ------------------------------------------------------------- *
 *
 * Runs the cleanup whether the body finished or not, then goes on doing
 * whatever the body was going to do. The difficulty is that a failure has to be
 * set aside for the cleanup to run at all: `had_error` is what stops the
 * machine, and a cleanup started with the flag still up would manage one
 * instruction.
 */
static void test_ensure_runs_either_way(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "cleaned := #0."
        /* the body finishes */
        "r := { #7 }:ensure({ cleaned := cleaned:add(#1) })."
        /* the body fails */
        "caught := { { error:raise(\"boom\") }:ensure({ cleaned := cleaned:add(#1) }) }"
        "    :onError({ e | e:message })."
        /* the answer is the body's, not the cleanup's */
        "answer := { #1 }:ensure({ #999 }).") == SOL_OK);

    assert(SOL_AS_INT(global(&vm, "cleaned")) == 2);   /* both times */
    assert(SOL_AS_INT(global(&vm, "r")) == 7);
    assert(is_text(global(&vm, "caught"), "boom"));
    assert(SOL_AS_INT(global(&vm, "answer")) == 1);

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  ensure runs the cleanup either way, and answers the body\n");
}

/* When both go wrong the body's failure survives, which is the rule everywhere
   here: the first error wins, and the second is usually a consequence. */
static void test_the_bodys_failure_wins(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "both := { { error:raise(\"from the body\") }"
        "    :ensure({ error:raise(\"from the cleanup\") }) }"
        "    :onError({ e | e:message })."
        /* and a cleanup failing alone has nothing to compete with */
        "alone := { { #1 }:ensure({ error:raise(\"cleanup alone\") }) }"
        "    :onError({ e | e:message }).") == SOL_OK);

    assert(is_text(global(&vm, "both"), "from the body"));
    assert(is_text(global(&vm, "alone"), "cleanup alone"));

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  when both fail, the body's failure is the one that carries on\n");
}

/* An exit is set aside the same way and for the same reason: releasing a thing
   you borrowed is as necessary when a program is stopping as when it is
   failing. The cleanup runs, and the program still exits with its status. */
static void test_ensure_runs_on_an_exit(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "cleaned := false."
        "{ system:exit(#4) }:ensure({ cleaned := true })."
        "after := true.") == SOL_EXIT);

    assert(vm.exit_code == 4);
    assert(SOL_AS_BOOL(global(&vm, "cleaned")));
    assert(SOL_IS_NIL(global(&vm, "after")));      /* the exit still stopped it */

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  an exit runs the cleanup and still exits\n");
}

/* Nested, the cleanups run innermost first as the failure travels out. */
static void test_nested_ensures_unwind_outward(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "order := array:new."
        "seen := { { { error:raise(\"deep\") }:ensure({ order:add(\"inner\") }) }"
        "    :ensure({ order:add(\"outer\") }) }:onError({ e | e:message })."
        "n := order:size. first := order:at(#1). second := order:at(#2).") == SOL_OK);

    assert(is_text(global(&vm, "seen"), "deep"));
    assert(SOL_AS_INT(global(&vm, "n")) == 2);
    assert(is_text(global(&vm, "first"), "inner"));
    assert(is_text(global(&vm, "second"), "outer"));

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  nested cleanups run innermost first\n");
}

/* The message and its stack are put back untouched, so an uncaught failure that
   passed through a cleanup still names where it happened rather than where it
   was tidied up after. */
static void test_the_error_survives_the_cleanup_intact(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "deep := { error:raise(\"the original\") }."
        "{ deep:value }:ensure({ nil }).") == SOL_RUNTIME_ERROR);

    assert(strcmp(vm.error_message.chars, "the original") == 0);
    assert(strstr(vm.error_trace.chars, "in block") != NULL);

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  the failure comes out with its own message and stack\n");
}

/* Unlike `onError`'s handler, the cleanup always runs, so a cleanup that is not
   a block is refused every time rather than only when something fails. */
static void test_ensure_refuses(void)
{
    static const char *refused[] = {
        "{ #1 }:ensure.",
        "{ #1 }:ensure({ #1 }, { #2 }).",
        "#5:ensure({ #1 }).",
        "{ #1 }:ensure(#2).",
    };

    for (size_t i = 0; i < sizeof(refused) / sizeof(refused[0]); i++) {
        SolVM vm; sol_vm_init(&vm);
        SolChunk chunk;
        assert(run(&vm, &chunk, refused[i]) == SOL_RUNTIME_ERROR);
        sol_chunk_free(&chunk); sol_vm_free(&vm);
    }
    printf("  a cleanup that is not a block is refused, always\n");
}

/* Setting a failure aside moves two growable buffers about. Doing it many times
   must not creep the stack or lose the collector's temporaries. */
static void test_many_ensures_stay_level(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "i := #0."
        "{ i:lessThan(#20000) }:whileTrue({"
        "    { { error:raise(\"x\") }:ensure({ nil }) }:onError({ e | nil })."
        "    i := i:add(#1) })."
        "done := i.") == SOL_OK);

    assert(SOL_AS_INT(global(&vm, "done")) == 20000);
    assert(vm.temp_count == 0);

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  twenty thousand cleanups leave the machine level\n");
}

int main(void)
{
    test_catching_answers_something();
    test_a_caught_error_is_silent();
    test_raising();
    test_re_raising_passes_it_on();
    test_an_exit_is_not_caught();
    test_the_stack_is_left_as_it_was_found();
    test_errors_survive_collection();
    test_catching_does_not_leak_temporaries();
    test_ensure_runs_either_way();
    test_the_bodys_failure_wins();
    test_ensure_runs_on_an_exit();
    test_nested_ensures_unwind_outward();
    test_the_error_survives_the_cleanup_intact();
    test_ensure_refuses();
    test_many_ensures_stay_level();
    printf("test_error: ok\n");
    return 0;
}
