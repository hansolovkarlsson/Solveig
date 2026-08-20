/* `system`: stopping with a status, the program's arguments, and the clock. */
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

/* The status is the program's to choose, and it reaches the caller. */
static void test_exit_carries_its_status(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk, "system:exit(#7).") == SOL_EXIT);
    assert(vm.exit_code == 7);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);

    sol_vm_init(&vm);
    assert(run(&vm, &chunk, "system:exit(#0).") == SOL_EXIT);
    assert(vm.exit_code == 0);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
    printf("  exit answers the status it was given\n");
}

/* Nothing after it runs -- it is a stop, not a jump to the end. */
static void test_nothing_runs_after_an_exit(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "reached := false. system:exit(#1). reached := true.") == SOL_EXIT);
    assert(SOL_AS_BOOL(global(&vm, "reached")) == false);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
    printf("  statements after an exit do not run\n");
}

/* It has to unwind out of a primitive that is calling back into the language,
   or `do` would keep going over the rest of the array. */
static void test_exit_unwinds_out_of_a_loop(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "seen := #0."
        "[#1, #2, #3, #4]:do({ n |"
        "    seen := seen:add(#1)."
        "    n:equals(#2):ifTrue({ system:exit(#3) }) }).") == SOL_EXIT);
    assert(vm.exit_code == 3);
    assert(SOL_AS_INT(global(&vm, "seen")) == 2);      /* not 4 */

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);

    sol_vm_init(&vm);
    assert(run(&vm, &chunk,
        "i := #0."
        "{ true }:whileTrue({ i := i:add(#1)."
        "    i:equals(#5):ifTrue({ system:exit(#2) }) }).") == SOL_EXIT);
    assert(vm.exit_code == 2);
    assert(SOL_AS_INT(global(&vm, "i")) == 5);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
    printf("  an exit unwinds out of a loop rather than finishing it\n");
}

/* A status is #0 to #255. Anything else is refused rather than masked: POSIX
   keeps the low eight bits, so #256 would leave with 0 and look like success. */
static void test_a_status_out_of_range_is_refused(void)
{
    static const char *refused[] = {
        "system:exit(#256).",
        "system:exit(#0:sub(#1)).",        /* -1, there being no negative literal */
        "system:exit(1.5).",
        "system:exit(\"0\").",
        "system:exit.",
        "system:exit(#1, #2).",
    };

    for (size_t i = 0; i < sizeof(refused) / sizeof(refused[0]); i++) {
        SolVM vm; sol_vm_init(&vm);
        SolChunk chunk;
        SolResult result = run(&vm, &chunk, refused[i]);
        assert(result == SOL_RUNTIME_ERROR || result == SOL_COMPILE_ERROR);
        sol_chunk_free(&chunk);
        sol_vm_free(&vm);
    }
    printf("  a status that is not #0 to #255 is refused\n");
}

/* With nothing given, the empty array -- not nil, so a program may walk it
   without asking whether it is there. */
static void test_arguments_default_to_none(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk, "args := system:arguments. n := args:size.") == SOL_OK);
    assert(SOL_IS_ARRAY(global(&vm, "args")));
    assert(SOL_AS_INT(global(&vm, "n")) == 0);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
    printf("  arguments with none given is the empty array\n");
}

/* They arrive as strings, in order, and `arguments` is one array rather than a
   fresh one per ask -- it is a slot holding data, not a primitive. */
static void test_arguments_arrive_as_strings(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    char *args[] = { (char *)"one", (char *)"two three", (char *)"" };
    sol_vm_set_arguments(&vm, 3, args);

    assert(run(&vm, &chunk,
        "n := system:arguments:size."
        "first := system:arguments:at(#1)."
        "second := system:arguments:at(#2)."
        "empty := system:arguments:at(#3)."
        "same := system:arguments:equals(system:arguments).") == SOL_OK);

    assert(SOL_AS_INT(global(&vm, "n")) == 3);
    assert(strcmp(SOL_AS_STRING(global(&vm, "first"))->chars, "one") == 0);
    assert(strcmp(SOL_AS_STRING(global(&vm, "second"))->chars, "two three") == 0);
    assert(strcmp(SOL_AS_STRING(global(&vm, "empty"))->chars, "") == 0);
    assert(SOL_AS_BOOL(global(&vm, "same")) == true);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
    printf("  arguments arrive as strings, in order, as one array\n");
}

/* Monotonic seconds as a float. Only differences mean anything, so that is
   what is checked: a later reading is never earlier than an earlier one. */
static void test_the_clock_is_a_float_and_moves_forward(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "first := system:clock."
        "i := #0. { i:lessThan(#20000) }:whileTrue({ i := i:add(#1) })."
        "second := system:clock."
        "isFloat := first:isKindOf(float)."
        "forward := second:greaterOrEqual(first).") == SOL_OK);

    assert(SOL_AS_BOOL(global(&vm, "isFloat")) == true);
    assert(SOL_AS_BOOL(global(&vm, "forward")) == true);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
    printf("  the clock answers a float that does not go backwards\n");
}

/* `system` is not a class. It is one object with slots, and it delegates to
   `object` like everything else does. */
static void test_system_is_an_ordinary_object(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "kind := system:isKindOf(object)."
        "answers := system:respondsTo('exit)."
        "text := system:asString.") == SOL_OK);

    assert(SOL_AS_BOOL(global(&vm, "kind")) == true);
    assert(SOL_AS_BOOL(global(&vm, "answers")) == true);
    assert(SOL_IS_STRING(global(&vm, "text")));

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
    printf("  system is an ordinary object\n");
}

int main(void)
{
    test_exit_carries_its_status();
    test_nothing_runs_after_an_exit();
    test_exit_unwinds_out_of_a_loop();
    test_a_status_out_of_range_is_refused();
    test_arguments_default_to_none();
    test_arguments_arrive_as_strings();
    test_the_clock_is_a_float_and_moves_forward();
    test_system_is_an_ordinary_object();

    printf("test_system: ok\n");
    return 0;
}
