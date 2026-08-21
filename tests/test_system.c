/* `system`: stopping with a status, the program's arguments, and the clock. */
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "solas/compiler.h"
#include "solum/gc.h"
#include "solum/vm.h"

/* Points stdin at `text`, so a test can drive `readLine`. freopen resets the
   stream entirely, which matters after a test has read one to its end. */
static void stdin_is(const char *text)
{
    static const char *path = "build/tests/test_system.stdin";

    FILE *f = fopen(path, "wb");
    assert(f != NULL);
    assert(fwrite(text, 1, strlen(text), f) == strlen(text));
    fclose(f);

    assert(freopen(path, "rb", stdin) != NULL);
}

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

/* A line is its text: the terminator is not part of it, an empty line is the
   empty string rather than the end, and a last line without a newline of its own
   still counts. */
static void test_read_line_answers_each_line_without_its_terminator(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    stdin_is("alpha\n\nbeta gamma\nno newline here");
    assert(run(&vm, &chunk,
        "first := system:readLine."
        "blank := system:readLine."
        "third := system:readLine."
        "last := system:readLine."
        "past := system:readLine.") == SOL_OK);

    assert(strcmp(SOL_AS_STRING(global(&vm, "first"))->chars, "alpha") == 0);
    assert(strcmp(SOL_AS_STRING(global(&vm, "blank"))->chars, "") == 0);
    assert(strcmp(SOL_AS_STRING(global(&vm, "third"))->chars, "beta gamma") == 0);
    assert(strcmp(SOL_AS_STRING(global(&vm, "last"))->chars, "no newline here") == 0);
    assert(SOL_IS_NIL(global(&vm, "past")));

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
    printf("  readLine answers a line at a time, and nil at the end\n");
}

/* `\r\n` is one terminator, so a file written on another system reads the same
   as one written here. */
static void test_read_line_takes_crlf_as_one_terminator(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    stdin_is("a\r\nb\r\n");
    assert(run(&vm, &chunk,
        "one := system:readLine. two := system:readLine.") == SOL_OK);

    assert(strcmp(SOL_AS_STRING(global(&vm, "one"))->chars, "a") == 0);
    assert(strcmp(SOL_AS_STRING(global(&vm, "two"))->chars, "b") == 0);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
    printf("  readLine takes CRLF as one terminator\n");
}

/* It reads in chunks, so a line longer than one has to come back whole -- the
   bug Solis had, where a long line was severed mid-token. */
static void test_read_line_reads_a_line_of_any_length(void)
{
    char *big = malloc(5002);
    assert(big != NULL);
    memset(big, 'x', 5000);
    big[5000] = '\n';
    big[5001] = '\0';

    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    stdin_is(big);
    free(big);

    assert(run(&vm, &chunk, "n := system:readLine:size.") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "n")) == 5000);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
    printf("  readLine reads a line of any length\n");
}

/* Nothing to read at all is the end, not an empty line. */
static void test_read_line_on_empty_input_is_nil(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    stdin_is("");
    assert(run(&vm, &chunk, "got := system:readLine.") == SOL_OK);
    assert(SOL_IS_NIL(global(&vm, "got")));

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
    printf("  readLine on empty input is nil\n");
}

static void test_read_line_takes_no_arguments(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    stdin_is("a\n");
    assert(run(&vm, &chunk, "system:readLine(#1).") == SOL_RUNTIME_ERROR);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
    printf("  readLine takes no arguments\n");
}

#define FILE_PATH "build/tests/test_system.file"

static void remove_the_test_file(void)
{
    remove(FILE_PATH);
}

/* What is written comes back, byte for byte. */
static void test_a_file_round_trips(void)
{
    remove_the_test_file();

    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "before := system:fileExists(\"" FILE_PATH "\")."
        "system:writeFile(\"" FILE_PATH "\", \"one\\ntwo\\n\")."
        "after := system:fileExists(\"" FILE_PATH "\")."
        "text := system:readFile(\"" FILE_PATH "\").") == SOL_OK);

    assert(SOL_AS_BOOL(global(&vm, "before")) == false);
    assert(SOL_AS_BOOL(global(&vm, "after")) == true);
    assert(strcmp(SOL_AS_STRING(global(&vm, "text"))->chars, "one\ntwo\n") == 0);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
    remove_the_test_file();
    printf("  a file written is a file read back\n");
}

/* Writing replaces what was there rather than adding to it, and answers nil --
   there is nothing useful to chain from a write. */
static void test_writing_replaces_and_answers_nil(void)
{
    remove_the_test_file();

    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "system:writeFile(\"" FILE_PATH "\", \"the first thing\")."
        "answer := system:writeFile(\"" FILE_PATH "\", \"short\")."
        "text := system:readFile(\"" FILE_PATH "\").") == SOL_OK);

    assert(SOL_IS_NIL(global(&vm, "answer")));
    assert(strcmp(SOL_AS_STRING(global(&vm, "text"))->chars, "short") == 0);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
    remove_the_test_file();
    printf("  writing replaces what was there, and answers nil\n");
}

/* An empty file is a file: `""` back, and it is there to be found. */
static void test_an_empty_file_is_a_file(void)
{
    remove_the_test_file();

    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "system:writeFile(\"" FILE_PATH "\", \"\")."
        "there := system:fileExists(\"" FILE_PATH "\")."
        "n := system:readFile(\"" FILE_PATH "\"):size.") == SOL_OK);

    assert(SOL_AS_BOOL(global(&vm, "there")) == true);
    assert(SOL_AS_INT(global(&vm, "n")) == 0);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
    remove_the_test_file();
    printf("  an empty file is a file, not an absent one\n");
}

/* A string is bytes, so a file of them survives the round trip -- a NUL is a
   byte like any other and `size` counts it. Taking a binary file apart is
   another matter, `at` answering a one-character string. */
static void test_bytes_survive_the_round_trip(void)
{
    remove_the_test_file();

    FILE *f = fopen(FILE_PATH, "wb");
    assert(f != NULL);
    assert(fwrite("a\0b", 1, 3, f) == 3);
    fclose(f);

    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "text := system:readFile(\"" FILE_PATH "\")."
        "n := text:size."
        "system:writeFile(\"" FILE_PATH "\", text)."
        "again := system:readFile(\"" FILE_PATH "\"):size.") == SOL_OK);

    assert(SOL_AS_INT(global(&vm, "n")) == 3);
    assert(SOL_AS_INT(global(&vm, "again")) == 3);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
    remove_the_test_file();
    printf("  bytes survive a read and a write, NUL included\n");
}

/* Bigger than any buffer inside the reader. */
static void test_a_large_file_round_trips(void)
{
    remove_the_test_file();

    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "line := \"0123456789\"."
        "text := \"\"."
        "i := #0."
        "{ i:lessThan(#2000) }:whileTrue({ text := text:concat(line). i := i:add(#1) })."
        "system:writeFile(\"" FILE_PATH "\", text)."
        "n := system:readFile(\"" FILE_PATH "\"):size.") == SOL_OK);

    assert(SOL_AS_INT(global(&vm, "n")) == 20000);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
    remove_the_test_file();
    printf("  a large file round trips\n");
}

/* A file that is not there is an error, not nil. `readLine` answering nil at
   the end is not the precedent: running out of input is how a loop finishes,
   where a missing file is a program expecting something that is not so. */
static void test_a_file_that_is_not_there_is_an_error(void)
{
    static const char *refused[] = {
        "system:readFile(\"build/tests/test_system.absent\").",
        "system:readFile(\"build/tests\").",              /* a directory is not a file */
        "system:writeFile(\"build/tests/no-such-dir/x\", \"hi\").",
        "system:readFile(#1).",
        "system:writeFile(\"" FILE_PATH "\", #1).",
        "system:readFile.",
        "system:writeFile(\"" FILE_PATH "\").",
        "system:fileExists.",
    };

    for (size_t i = 0; i < sizeof(refused) / sizeof(refused[0]); i++) {
        SolVM vm; sol_vm_init(&vm);
        SolChunk chunk;
        assert(run(&vm, &chunk, refused[i]) == SOL_RUNTIME_ERROR);
        sol_chunk_free(&chunk);
        sol_vm_free(&vm);
    }
    remove_the_test_file();
    printf("  a missing file, a directory, and a bad argument are all errors\n");
}

/* `fileExists` answers the question `readFile` asks, so a directory is not a
   file -- otherwise looking before you leap would be a trap. */
static void test_file_exists_means_a_file(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "missing := system:fileExists(\"build/tests/test_system.absent\")."
        "directory := system:fileExists(\"build/tests\").") == SOL_OK);

    assert(SOL_AS_BOOL(global(&vm, "missing")) == false);
    assert(SOL_AS_BOOL(global(&vm, "directory")) == false);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
    printf("  fileExists is about a file, so a directory is not one\n");
}

/* A search has to respect the length rather than stopping at the first NUL,
   which is the only way `split` is any use on a file that holds one. There is
   no escape for a NUL in a literal, so the string has to come from a file. */
static void test_splitting_a_string_that_holds_a_nul(void)
{
    remove_the_test_file();

    FILE *f = fopen(FILE_PATH, "wb");
    assert(f != NULL);
    assert(fwrite("a\0b,c\0d", 1, 7, f) == 7);
    fclose(f);

    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "pieces := system:readFile(\"" FILE_PATH "\"):split(\",\")."
        "n := pieces:size."
        "first := pieces:at(#1):size."
        "second := pieces:at(#2):size."
        "at := system:readFile(\"" FILE_PATH "\"):indexOf(\"b,\").") == SOL_OK);

    assert(SOL_AS_INT(global(&vm, "n")) == 2);
    assert(SOL_AS_INT(global(&vm, "first")) == 3);    /* a NUL b */
    assert(SOL_AS_INT(global(&vm, "second")) == 3);   /* c NUL d */
    assert(SOL_AS_INT(global(&vm, "at")) == 3);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
    remove_the_test_file();
    printf("  split and indexOf see past a NUL\n");
}

/* Seconds as a float, which is the only answer that needs no duration type. */
static void test_time_to_run_answers_a_float(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "taken := { #1:add(#1) }:timeToRun."
        "isFloat := taken:isKindOf(float)."
        "notNegative := taken:greaterOrEqual(0.0).") == SOL_OK);

    assert(SOL_AS_BOOL(global(&vm, "isFloat")) == true);
    assert(SOL_AS_BOOL(global(&vm, "notNegative")) == true);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
    printf("  timeToRun answers seconds as a float\n");
}

/* Work that takes longer measures longer. The only claim a timing test can make
   without being flaky, and the one that matters: that it measures at all. */
static void test_time_to_run_measures_the_block(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "spin := { | i | i := #0."
        "    { i:lessThan(#200000) }:whileTrue({ i := i:add(#1) }) }."
        "slow := spin:timeToRun."
        "fast := { #1 }:timeToRun(#100)."
        "longer := slow:greaterThan(fast).") == SOL_OK);

    assert(SOL_AS_BOOL(global(&vm, "longer")) == true);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
    printf("  a slower block measures longer than a faster one\n");
}

/* The count exists because the clock has a floor -- a microsecond where this was
   written -- and one run of anything small measures as exactly 0.0. Running it
   enough times clears the floor, which is what makes the message useful for the
   sub-microsecond things it was asked for. */
static void test_a_count_clears_the_clock_floor(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "many := { #1:add(#1) }:timeToRun(#200000)."
        "measured := many:greaterThan(0.0).") == SOL_OK);
    assert(SOL_AS_BOOL(global(&vm, "measured")) == true);
    sol_chunk_free(&chunk);

    /* More runs of the same block take longer than fewer. */
    assert(run(&vm, &chunk,
        "few := { #1:add(#1) }:timeToRun(#20000)."
        "lots := { #1:add(#1) }:timeToRun(#400000)."
        "ordered := lots:greaterThan(few).") == SOL_OK);
    assert(SOL_AS_BOOL(global(&vm, "ordered")) == true);
    sol_chunk_free(&chunk);

    sol_vm_free(&vm);
    printf("  a count clears the clock's floor\n");
}

/* The block really does run, and run the number of times it was given. */
static void test_the_block_runs_and_its_answer_is_dropped(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "calls := #0."
        "taken := { calls := calls:add(#1). \"an answer\" }:timeToRun(#5).") == SOL_OK);

    assert(SOL_AS_INT(global(&vm, "calls")) == 5);
    assert(SOL_IS_FLOAT(global(&vm, "taken")));      /* not the block's answer */

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
    printf("  the block runs, and the time is what comes back\n");
}

/* An error inside the block stops the run rather than being timed through. */
static void test_an_error_in_the_block_stops_it(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "calls := #0."
        "{ calls := calls:add(#1). nil:frobnicate }:timeToRun(#10).")
        == SOL_RUNTIME_ERROR);
    assert(SOL_AS_INT(global(&vm, "calls")) == 1);      /* not 10 */

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
    printf("  an error in the block stops the timing\n");
}

static void test_a_bad_count_is_refused(void)
{
    static const char *refused[] = {
        "{ #1 }:timeToRun(#0).",
        "{ #1 }:timeToRun(#0:sub(#5)).",     /* -5, there being no negative literal */
        "{ #1 }:timeToRun(1.0).",
        "{ #1 }:timeToRun(\"x\").",
        "{ #1 }:timeToRun(#1, #2).",
        "{ x | x }:timeToRun.",              /* a block wanting an argument */
        "#1:timeToRun.",                     /* not a block at all */
    };

    for (size_t i = 0; i < sizeof(refused) / sizeof(refused[0]); i++) {
        SolVM vm; sol_vm_init(&vm);
        SolChunk chunk;
        assert(run(&vm, &chunk, refused[i]) == SOL_RUNTIME_ERROR);
        sol_chunk_free(&chunk);
        sol_vm_free(&vm);
    }
    printf("  a count that is not #1 or more is refused\n");
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
    test_time_to_run_answers_a_float();
    test_time_to_run_measures_the_block();
    test_a_count_clears_the_clock_floor();
    test_the_block_runs_and_its_answer_is_dropped();
    test_an_error_in_the_block_stops_it();
    test_a_bad_count_is_refused();
    test_system_is_an_ordinary_object();

    test_read_line_answers_each_line_without_its_terminator();
    test_read_line_takes_crlf_as_one_terminator();
    test_read_line_reads_a_line_of_any_length();
    test_read_line_on_empty_input_is_nil();
    test_read_line_takes_no_arguments();

    test_a_file_round_trips();
    test_writing_replaces_and_answers_nil();
    test_an_empty_file_is_a_file();
    test_bytes_survive_the_round_trip();
    test_splitting_a_string_that_holds_a_nul();
    test_a_large_file_round_trips();
    test_a_file_that_is_not_there_is_an_error();
    test_file_exists_means_a_file();

    printf("test_system: ok\n");
    return 0;
}
