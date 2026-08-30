/* End-to-end: source text through Solas and Solum, checked by inspecting the
 * globals the program left behind. */
#include <assert.h>
#include <stdio.h>
#include <string.h>

#include "solas/compiler.h"
#include "solum/vm.h"

/* Compiles and runs `source` in `vm`, returning the result. */
static SolResult run(SolVM *vm, const char *source)
{
    SolChunk chunk;
    sol_chunk_init(&chunk);

    SolResult result = SOL_COMPILE_ERROR;
    if (sol_compile(source, &chunk)) {
        result = sol_vm_run(vm, &chunk);
    }
    sol_chunk_free(&chunk);
    return result;
}

/* The value bound to `name`, or nil if unbound. */
static SolValue global(SolVM *vm, const char *name)
{
    SolSlot *slot = sol_object_lookup(vm->root, name);
    return slot ? slot->value : SOL_NIL_VAL;
}

static void test_assignment_binds_a_name(void)
{
    SolVM vm;
    sol_vm_init(&vm);

    assert(run(&vm, "a := #45.") == SOL_OK);
    assert(SOL_IS_INT(global(&vm, "a")));
    assert(SOL_AS_INT(global(&vm, "a")) == 45);

    sol_vm_free(&vm);
}

/* '#' picks the type: #45 is an integer, a bare 45 is a float. */
static void test_hash_selects_the_numeric_type(void)
{
    SolVM vm;
    sol_vm_init(&vm);

    assert(run(&vm, "i := #45. f := 45.") == SOL_OK);
    assert(SOL_IS_INT(global(&vm, "i")));
    assert(SOL_IS_FLOAT(global(&vm, "f")));
    assert(SOL_AS_FLOAT(global(&vm, "f")) == 45.0);

    sol_vm_free(&vm);
}

/* The point of the variable model: arithmetic returns a new value and leaves
   the receiver's binding alone. */
static void test_values_are_immutable(void)
{
    SolVM vm;
    sol_vm_init(&vm);

    assert(run(&vm, "a := #45. b := a:add(#5).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "b")) == 50);
    assert(SOL_AS_INT(global(&vm, "a")) == 45);   /* unchanged */

    /* Rebinding is how you "change" a name. */
    assert(run(&vm, "a := a:add(#5).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "a")) == 50);

    sol_vm_free(&vm);
}

static void test_sends_chain_left_to_right(void)
{
    SolVM vm;
    sol_vm_init(&vm);

    assert(run(&vm, "r := #2:add(#3):mul(#4).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "r")) == 20);   /* (2+3)*4, not 2+(3*4) */

    sol_vm_free(&vm);
}

/* `integer:new(#45)` used to answer #45 -- the literal spelled longer, and the
   last of a design where you built a mutable integer and then `set` it. There is
   nothing for it to construct, so it refuses now and says what to write. */
static void test_a_number_is_written_not_constructed(void)
{
    SolVM vm;
    sol_vm_init(&vm);

    assert(run(&vm, "a := integer:new(#45).") == SOL_RUNTIME_ERROR);
    sol_vm_free(&vm);

    sol_vm_init(&vm);
    assert(run(&vm, "a := float:new(1.5).") == SOL_RUNTIME_ERROR);
    sol_vm_free(&vm);

    /* The literal is the only way, and always was the short one. */
    sol_vm_init(&vm);
    assert(run(&vm, "a := #45. b := 1.5.") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "a")) == 45);
    assert(SOL_AS_FLOAT(global(&vm, "b")) == 1.5);
    sol_vm_free(&vm);
}

static void test_assignment_is_an_expression(void)
{
    SolVM vm;
    sol_vm_init(&vm);

    assert(run(&vm, "c := b := #45.") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "b")) == 45);
    assert(SOL_AS_INT(global(&vm, "c")) == 45);

    sol_vm_free(&vm);
}

/* Strict typing: mixing an integer and a float is an error, never a coercion. */
static void test_arithmetic_is_strict(void)
{
    SolVM vm;
    sol_vm_init(&vm);

    assert(run(&vm, "x := #45:add(1.5).") == SOL_RUNTIME_ERROR);
    assert(run(&vm, "y := 1.5:add(#45).") == SOL_RUNTIME_ERROR);
    assert(run(&vm, "z := 1.5:add(2.5).") == SOL_OK);
    assert(SOL_AS_FLOAT(global(&vm, "z")) == 4.0);

    sol_vm_free(&vm);
}

/* Overflow traps rather than wrapping silently. */
static void test_integer_overflow_traps(void)
{
    SolVM vm;
    sol_vm_init(&vm);

    assert(run(&vm, "big := #9223372036854775807. big:add(#1).") == SOL_RUNTIME_ERROR);
    assert(run(&vm, "small := #-9223372036854775807. small:sub(#2).") == SOL_RUNTIME_ERROR);
    assert(run(&vm, "ok := #9223372036854775806:add(#1).") == SOL_OK);

    sol_vm_free(&vm);
}

static void test_errors_are_reported_not_crashed(void)
{
    SolVM vm;
    sol_vm_init(&vm);

    assert(run(&vm, "undefined_name:print.") == SOL_RUNTIME_ERROR);
    assert(run(&vm, "#45:frobnicate.") == SOL_RUNTIME_ERROR);
    assert(run(&vm, "a := .") == SOL_COMPILE_ERROR);
    assert(run(&vm, "a := (#45.") == SOL_COMPILE_ERROR);

    /* The VM must still be usable after each failure -- Solis depends on it. */
    assert(run(&vm, "fine := #1.") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "fine")) == 1);

    sol_vm_free(&vm);
}

/* Globals outlive a chunk, which is what makes the REPL work line by line. */
static void test_globals_persist_across_chunks(void)
{
    SolVM vm;
    sol_vm_init(&vm);

    assert(run(&vm, "a := #45.") == SOL_OK);
    assert(run(&vm, "b := a:add(#5).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "b")) == 50);

    sol_vm_free(&vm);
}

/* Integer division floors, so it differs from C only on negatives, and the
   remainder takes the divisor's sign rather than the dividend's. */
static void test_division_floors(void)
{
    SolVM vm; sol_vm_init(&vm);

    assert(run(&vm,
        "a := #7:div(#2).  b := #-7:div(#2)."
        "c := #7:div(#-2). d := #-7:div(#-2).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "a")) == 3);
    assert(SOL_AS_INT(global(&vm, "b")) == -4);   /* not -3 */
    assert(SOL_AS_INT(global(&vm, "c")) == -4);
    assert(SOL_AS_INT(global(&vm, "d")) == 3);

    assert(run(&vm,
        "a := #7:mod(#2).  b := #-7:mod(#2)."
        "c := #7:mod(#-2). d := #-7:mod(#-2)."
        "e := #6:mod(#3).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "a")) == 1);
    assert(SOL_AS_INT(global(&vm, "b")) == 1);    /* not -1: divisor's sign */
    assert(SOL_AS_INT(global(&vm, "c")) == -1);
    assert(SOL_AS_INT(global(&vm, "d")) == -1);
    assert(SOL_AS_INT(global(&vm, "e")) == 0);

    sol_vm_free(&vm);
}

/* (a div b) * b + (a mod b) == a, whatever the signs. */
static void test_division_identity(void)
{
    SolVM vm; sol_vm_init(&vm);

    assert(run(&vm,
        "check := { a, b | a:sub( a:div(b):mul(b):add(a:mod(b)) ) }."
        "r := [check:value(#7, #2),  check:value(#-7, #2),"
        "      check:value(#7, #-2), check:value(#-7, #-2),"
        "      check:value(#0, #5),  check:value(#-1, #7),"
        "      check:value(#100, #7), check:value(#-100, #-7)].") == SOL_OK);

    SolValue r = global(&vm, "r");
    assert(SOL_IS_ARRAY(r));
    for (int i = 0; i < SOL_AS_ARRAY(r)->count; i++) {
        assert(SOL_AS_INT(SOL_AS_ARRAY(r)->items[i]) == 0);
    }

    sol_vm_free(&vm);
}

/* Integers have no infinity, so dividing by zero errors -- and the one division
   that overflows is guarded, since in C it is undefined rather than merely
   wrong. */
static void test_integer_division_guards(void)
{
    SolVM vm; sol_vm_init(&vm);

    assert(run(&vm, "#1:div(#0).") == SOL_RUNTIME_ERROR);
    assert(run(&vm, "#1:mod(#0).") == SOL_RUNTIME_ERROR);
    assert(run(&vm, "#0:div(#0).") == SOL_RUNTIME_ERROR);

    assert(run(&vm, "#-9223372036854775808:div(#-1).") == SOL_RUNTIME_ERROR);
    assert(run(&vm, "#-9223372036854775808:mod(#-1).") == SOL_RUNTIME_ERROR);

    /* But the neighbouring cases are fine. */
    assert(run(&vm,
        "a := #-9223372036854775808:div(#1)."
        "b := #-9223372036854775807:div(#-1).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "b")) == 9223372036854775807LL);

    /* Strict as ever. */
    assert(run(&vm, "#7:div(2.0).") == SOL_RUNTIME_ERROR);

    sol_vm_free(&vm);
}

/* Floats have an infinity, and already reach it by overflow, so dividing by
   zero answers one rather than erroring. */
static void test_float_division_follows_ieee(void)
{
    SolVM vm; sol_vm_init(&vm);

    assert(run(&vm,
        "q := 7.0:div(2.0). inf := 1.0:div(0.0). neg := -1.0:div(0.0)."
        "m := -7.0:mod(2.0).") == SOL_OK);
    assert(SOL_AS_FLOAT(global(&vm, "q")) == 3.5);
    assert(SOL_AS_FLOAT(global(&vm, "inf")) > 0 &&
           SOL_AS_FLOAT(global(&vm, "inf")) * 2 == SOL_AS_FLOAT(global(&vm, "inf")));
    assert(SOL_AS_FLOAT(global(&vm, "neg")) < 0);
    assert(SOL_AS_FLOAT(global(&vm, "m")) == 1.0);   /* floored, like integers */

    sol_vm_free(&vm);
}

/* `.` separates statements: required between two, optional after the last. */
static void test_statement_separator(void)
{
    SolVM vm; sol_vm_init(&vm);

    /* The last statement needs none. */
    assert(run(&vm, "a := #1. b := #2") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "b")) == 2);

    /* A trailing one is fine too. */
    assert(run(&vm, "c := #3.") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "c")) == 3);

    /* A single statement, with and without. */
    assert(run(&vm, "d := #4") == SOL_OK);
    assert(run(&vm, "e := #5.") == SOL_OK);

    /* Missing between two is now reported rather than silently accepted. */
    assert(run(&vm, "a := #1 b := #2.") == SOL_COMPILE_ERROR);
    assert(run(&vm, "#1 #2.") == SOL_COMPILE_ERROR);

    /* The same rule inside a group and a block, where it already held -- but the
       message now names the missing separator rather than the closing bracket. */
    assert(run(&vm, "r := ( #1 #2 ).") == SOL_COMPILE_ERROR);
    assert(run(&vm, "b := { #1 #2 }.") == SOL_COMPILE_ERROR);

    /* And they still accept the forms they always did. */
    assert(run(&vm, "r := ( #1. #2 ). s := { #1. #2. }:value().") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "r")) == 2);
    assert(SOL_AS_INT(global(&vm, "s")) == 2);

    sol_vm_free(&vm);
}

/* What the rule does not catch, recorded so it is a known limit rather than a
   surprise: a line beginning with ':' continues the expression above it, so
   these two lines are one statement and no separator is missing. */
static void test_a_leading_colon_still_continues(void)
{
    SolVM vm; sol_vm_init(&vm);

    assert(run(&vm, "total := #10\n:add(#5).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "total")) == 15);

    sol_vm_free(&vm);
}

/* Error recovery has to consume something, or a statement that failed without
   taking a token is retried forever. `primary` reports an unexpected token
   without consuming it, so when the token before happened to be a '.', the
   compiler produced identical errors until it was killed. */
static void test_error_recovery_makes_progress(void)
{
    SolVM vm; sol_vm_init(&vm);

    const char *malformed[] = {
        "b := { #1. | q | q }.",
        "a := #1. | b.",
        "x := #1. ) y := #2.",
        "#1. }",
        "a := #1. ,",
        "a := #1. . .",
    };
    for (size_t i = 0; i < sizeof malformed / sizeof malformed[0]; i++) {
        /* Reaching the assertion at all is the test: these used to not return. */
        assert(run(&vm, malformed[i]) == SOL_COMPILE_ERROR);
    }

    /* And recovery still works: an error early does not swallow what follows. */
    assert(run(&vm, "bad := . good := #7.") == SOL_COMPILE_ERROR);
    assert(run(&vm, "good := #7.") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "good")) == 7);

    sol_vm_free(&vm);
}

/* ---- the error is text the machine holds ------------------------------- *
 *
 * It used to go straight to stderr from wherever the failure was. It is built
 * into `vm->error_message` and `vm->error_trace` now and written out by `sol_vm_run` when nothing has
 * caught it -- which is nothing, yet. The visible behaviour is identical, and
 * the point is that the message exists as a value the machine could hand to a
 * handler instead.
 */
static void test_the_error_is_recorded_not_only_printed(void)
{
    SolVM vm;
    sol_vm_init(&vm);
    assert(vm.error_message.length == 0);

    assert(run(&vm, "nil:frobnicate.") == SOL_RUNTIME_ERROR);

    assert(vm.had_error);
    assert(vm.error_message.length > 0);
    assert(strcmp(vm.error_message.chars, "nil does not understand 'frobnicate'") == 0);
    assert(strstr(vm.error_trace.chars, "[line 1] in script") != NULL);

    sol_vm_free(&vm);
}

/* Each run starts clean, so a message cannot be reported twice or leak into a
   later program -- which Solis depends on, running one chunk after another in
   the same VM. */
static void test_each_run_starts_with_no_error(void)
{
    SolVM vm;
    sol_vm_init(&vm);

    assert(run(&vm, "nil:frobnicate.") == SOL_RUNTIME_ERROR);
    assert(vm.error_message.length > 0);

    assert(run(&vm, "x := #1:add(#2).") == SOL_OK);
    assert(!vm.had_error);
    assert(vm.error_message.length == 0);
    assert(vm.error_trace.length == 0);
    assert(SOL_AS_INT(global(&vm, "x")) == 3);

    /* And a second failure records its own message rather than the first. */
    assert(run(&vm, "nil:bang.") == SOL_RUNTIME_ERROR);
    assert(strstr(vm.error_message.chars, "'bang'") != NULL);
    assert(strstr(vm.error_message.chars, "'frobnicate'") == NULL);

    sol_vm_free(&vm);
}

/* The first error wins. Building a message can itself fail -- a complaint that
   names a value renders it, and rendering sends `asString` -- and the failure
   that started it is the one worth reporting. Hard to provoke from Solum, since
   every loop that could raise a second one checks the flag first, so it is
   asked of the function directly. */
static void test_the_first_error_wins(void)
{
    SolVM vm;
    sol_vm_init(&vm);

    sol_vm_runtime_error(&vm, "the real failure");
    sol_vm_runtime_error(&vm, "a consequence of reporting it");

    assert(strstr(vm.error_message.chars, "the real failure") != NULL);
    assert(strstr(vm.error_message.chars, "a consequence") == NULL);

    sol_vm_free(&vm);
}

/* `system:exit` unwinds through the same flag and is not a failure, so it
   records nothing and prints nothing. */
static void test_an_exit_records_no_error(void)
{
    SolVM vm;
    sol_vm_init(&vm);

    assert(run(&vm, "system:exit(#3).") == SOL_EXIT);
    assert(vm.exit_code == 3);
    assert(vm.error_message.length == 0);

    sol_vm_free(&vm);
}

/* Where a global lives is remembered per site -- see `global_slots` in
 * bytecode.h. These pin the three things that makes true rather than fast.
 *
 * The first is ordinary behaviour, which is the point: a remembered slot must
 * be indistinguishable from a looked-up one. */
static void test_a_remembered_global_still_reads_and_writes(void)
{
    SolVM vm; sol_vm_init(&vm);

    /* Read and written many times through the same two instructions, with the
       value changing under them and the slot never moving. */
    assert(run(&vm,
        "n := #0. seen := \"\"."
        "{ n:lessThan(#5) }:whileTrue({"
        "  n := n:add(#1). seen := seen:concat(n:asString) }).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "n")) == 5);
    assert(SOL_IS_STRING(global(&vm, "seen")));
    assert(strcmp(SOL_AS_STRING(global(&vm, "seen"))->chars, "12345") == 0);

    /* And rebinding to another type goes on working. */
    assert(run(&vm, "n := \"five\".") == SOL_OK);
    assert(SOL_IS_STRING(global(&vm, "n")));
    sol_vm_free(&vm);
}

/* The second: a name that was not bound when the instruction first ran is
 * looked up again rather than remembered as absent. Nothing caches a miss. */
static void test_an_absent_global_is_not_remembered_as_absent(void)
{
    SolVM vm; sol_vm_init(&vm);

    /* `later` does not exist when `get` first runs, and does the second time.
       One method, one OP_GLOBAL, both answers. */
    assert(run(&vm,
        "holder := object:new."
        "holder:get := { later }."
        "first := { holder:get }:onError({ e | \"absent\" })."
        "later := #42."
        "second := holder:get.") == SOL_OK);
    assert(SOL_IS_STRING(global(&vm, "first")));
    assert(strcmp(SOL_AS_STRING(global(&vm, "first"))->chars, "absent") == 0);
    assert(SOL_AS_INT(global(&vm, "second")) == 42);

    sol_vm_free(&vm);
}

/* The third, and the one that would be a real bug: a chunk carries the cache,
 * so a chunk run on a second machine must not read the first machine's root.
 * The slots there have been freed with it.
 *
 * This is the failure `interned_for` was made for -- see the note on it in
 * bytecode.h -- and the reason the two tables are emptied together. A VM is a
 * local here, so the second is very likely to land on the first's address,
 * which is exactly the case a pointer-keyed check got wrong. */
static void test_a_chunk_does_not_carry_globals_between_machines(void)
{
    SolChunk chunk;
    sol_chunk_init(&chunk);
    assert(sol_compile("out := seed:add(#1).", &chunk));

    for (int i = 1; i <= 20; i++) {
        SolVM vm; sol_vm_init(&vm);

        /* A different slot on a different root each time round. */
        SolChunk setup;
        sol_chunk_init(&setup);
        char source[64];
        snprintf(source, sizeof source, "seed := #%d.", i * 100);
        assert(sol_compile(source, &setup));
        assert(sol_vm_run(&vm, &setup) == SOL_OK);
        sol_chunk_free(&setup);

        assert(sol_vm_run(&vm, &chunk) == SOL_OK);
        assert(SOL_AS_INT(global(&vm, "out")) == i * 100 + 1);

        sol_vm_free(&vm);
    }
    sol_chunk_free(&chunk);
}

int main(void)
{
    test_error_recovery_makes_progress();
    test_statement_separator();
    test_a_leading_colon_still_continues();
    test_division_floors();
    test_division_identity();
    test_integer_division_guards();
    test_float_division_follows_ieee();
    test_assignment_binds_a_name();
    test_hash_selects_the_numeric_type();
    test_values_are_immutable();
    test_sends_chain_left_to_right();
    test_a_number_is_written_not_constructed();
    test_the_error_is_recorded_not_only_printed();
    test_each_run_starts_with_no_error();
    test_the_first_error_wins();
    test_an_exit_records_no_error();
    test_a_remembered_global_still_reads_and_writes();
    test_an_absent_global_is_not_remembered_as_absent();
    test_a_chunk_does_not_carry_globals_between_machines();
    test_assignment_is_an_expression();
    test_arithmetic_is_strict();
    test_integer_overflow_traps();
    test_errors_are_reported_not_crashed();
    test_globals_persist_across_chunks();
    printf("test_vm: ok\n");
    return 0;
}
