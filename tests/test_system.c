/* `system`: stopping with a status, the program's arguments, and the clock. */
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>

#include <sys/stat.h>

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

/* ---- directories -------------------------------------------------------- *
 *
 * Reading a file needed you to know its path already, so a program could be
 * told what to work on and could never go and look. `filesIn` is what makes a
 * walk possible at all.
 */
static void test_listing_a_directory(void)
{
    remove_the_test_file();
    static const char *dir = "build/tests/listing";
    mkdir(dir, 0777);

    FILE *f = fopen("build/tests/listing/one.txt", "wb");
    assert(f != NULL); fputs("1", f); fclose(f);
    f = fopen("build/tests/listing/two.txt", "wb");
    assert(f != NULL); fputs("22", f); fclose(f);
    mkdir("build/tests/listing/inner", 0777);

    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "names := system:filesIn(\"build/tests/listing\"):sorted."
        "n := names:size."
        /* neither `.` nor `..`, and directories are in it */
        "joined := names:join(\",\")."
        "isDir := system:isDirectory(\"build/tests/listing/inner\")."
        "notDir := system:isDirectory(\"build/tests/listing/one.txt\")."
        /* fileExists and isDirectory answer opposite things about a directory */
        "existsSaysNo := system:fileExists(\"build/tests/listing/inner\").") == SOL_OK);

    assert(SOL_AS_INT(global(&vm, "n")) == 3);
    assert(strcmp(SOL_AS_STRING(global(&vm, "joined"))->chars,
                  "inner,one.txt,two.txt") == 0);
    assert(SOL_AS_BOOL(global(&vm, "isDir")));
    assert(SOL_AS_BOOL(global(&vm, "notDir")) == false);
    assert(SOL_AS_BOOL(global(&vm, "existsSaysNo")) == false);

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  filesIn answers the names, directories included, without . or ..\n");
}

/* A path that is not a directory is an error, as a missing file is to
   `readFile`: a program asking to walk something that is not one is wrong. */
static void test_listing_what_is_not_a_directory(void)
{
    static const char *refused[] = {
        "system:filesIn(\"build/tests/no-such-directory\").",
        "system:filesIn(\"build/tests/listing/one.txt\").",
        "system:filesIn(#1).",
        "system:filesIn.",
        "system:isDirectory(#1).",
    };

    for (size_t i = 0; i < sizeof(refused) / sizeof(refused[0]); i++) {
        SolVM vm; sol_vm_init(&vm);
        SolChunk chunk;
        assert(run(&vm, &chunk, refused[i]) == SOL_RUNTIME_ERROR);
        sol_chunk_free(&chunk); sol_vm_free(&vm);
    }
    printf("  listing something that is not a directory is an error\n");
}

/* `writeFile` replaces; this is the other one. */
static void test_appending(void)
{
    remove_the_test_file();

    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        /* it creates the file when it is not there, as writeFile does */
        "system:appendFile(\"" FILE_PATH "\", \"one\\n\")."
        "system:appendFile(\"" FILE_PATH "\", \"two\\n\")."
        "text := system:readFile(\"" FILE_PATH "\")."
        "n := text:size."
        /* and replacing still replaces */
        "system:writeFile(\"" FILE_PATH "\", \"fresh\")."
        "after := system:readFile(\"" FILE_PATH "\").") == SOL_OK);

    assert(SOL_AS_INT(global(&vm, "n")) == 8);          /* "one\ntwo\n" */
    assert(strcmp(SOL_AS_STRING(global(&vm, "text"))->chars, "one\ntwo\n") == 0);
    assert(strcmp(SOL_AS_STRING(global(&vm, "after"))->chars, "fresh") == 0);

    sol_chunk_free(&chunk); sol_vm_free(&vm);

    sol_vm_init(&vm);
    assert(run(&vm, &chunk, "system:appendFile(\"" FILE_PATH "\", #1).")
           == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk); sol_vm_free(&vm);
    remove_the_test_file();
    printf("  appendFile adds to the end, and creates what is not there\n");
}

/* A variable that is not set answers nil rather than failing: it is a
   legitimate answer to a legitimate question, the way the end of input is. */
static void test_the_environment(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(setenv("SOLUM_TEST_VARIABLE", "a value", 1) == 0);

    assert(run(&vm, &chunk,
        "set := system:environment(\"SOLUM_TEST_VARIABLE\")."
        "unset := system:environment(\"SOLUM_NO_SUCH_VARIABLE\")."
        "missing := unset:isNil.") == SOL_OK);

    assert(strcmp(SOL_AS_STRING(global(&vm, "set"))->chars, "a value") == 0);
    assert(SOL_AS_BOOL(global(&vm, "missing")));
    assert(SOL_IS_NIL(global(&vm, "unset")));

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    unsetenv("SOLUM_TEST_VARIABLE");

    sol_vm_init(&vm);
    assert(run(&vm, &chunk, "system:environment(#1).") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  environment answers the variable, or nil when it is not set\n");
}

/* ---- changing what is there --------------------------------------------- *
 *
 * These do something that cannot be undone, which is a different sort of
 * message from reading one and is worth testing as carefully.
 */
static void test_making_moving_and_removing(void)
{
    static const char *base = "build/tests/fs";
    /* From whatever a previous run left. */
    remove("build/tests/fs/inner/deep.txt");
    remove("build/tests/fs/inner");
    remove("build/tests/fs/b.txt");
    remove("build/tests/fs/a.txt");
    remove(base);

    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "base := \"build/tests/fs\"."
        "system:makeDirectory(base)."
        "made := system:isDirectory(base)."

        "system:writeFile(base:concat(\"/a.txt\"), \"hello\")."
        "size := system:fileSize(base:concat(\"/a.txt\"))."

        /* renaming is moving, and works on a directory too */
        "system:rename(base:concat(\"/a.txt\"), base:concat(\"/b.txt\"))."
        "gone := system:fileExists(base:concat(\"/a.txt\"))."
        "there := system:fileExists(base:concat(\"/b.txt\"))."
        "system:makeDirectory(base:concat(\"/sub\"))."
        "system:rename(base:concat(\"/sub\"), base:concat(\"/inner\"))."
        "listed := system:filesIn(base):sorted:join(\",\")."

        /* remove takes a file, or an empty directory */
        "system:remove(base:concat(\"/inner\"))."
        "system:remove(base:concat(\"/b.txt\"))."
        "empty := system:filesIn(base):size."
        "system:remove(base)."
        "cleared := system:isDirectory(base):not.") == SOL_OK);

    assert(SOL_AS_BOOL(global(&vm, "made")));
    assert(SOL_AS_INT(global(&vm, "size")) == 5);
    assert(SOL_AS_BOOL(global(&vm, "gone")) == false);
    assert(SOL_AS_BOOL(global(&vm, "there")));
    assert(strcmp(SOL_AS_STRING(global(&vm, "listed"))->chars, "b.txt,inner") == 0);
    assert(SOL_AS_INT(global(&vm, "empty")) == 0);
    assert(SOL_AS_BOOL(global(&vm, "cleared")));

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  making, moving and removing, and measuring without reading\n");
}

/* Each refusal names the reason the system gave, because "cannot remove" alone
   leaves a script no way to tell a missing file from a full directory. */
static void test_changing_what_is_there_refuses(void)
{
    mkdir("build/tests/notempty", 0777);
    FILE *f = fopen("build/tests/notempty/keep.txt", "wb");
    assert(f != NULL); fputs("x", f); fclose(f);

    static const char *refused[] = {
        "system:remove(\"build/tests/notempty\").",    /* not empty */
        "system:remove(\"build/tests/no-such-thing\").",
        "system:makeDirectory(\"build/tests/no/such/parent/x\").",
        "system:rename(\"build/tests/no-such-thing\", \"build/tests/x\").",
        "system:fileSize(\"build/tests/no-such-thing\").",
        "system:remove(#1).",
        "system:rename(\"a\").",
        "system:makeDirectory.",
    };

    for (size_t i = 0; i < sizeof(refused) / sizeof(refused[0]); i++) {
        SolVM vm; sol_vm_init(&vm);
        SolChunk chunk;
        assert(run(&vm, &chunk, refused[i]) == SOL_RUNTIME_ERROR);
        sol_chunk_free(&chunk); sol_vm_free(&vm);
    }

    /* The directory is still there, which is the point of refusing. */
    struct stat info;
    assert(stat("build/tests/notempty/keep.txt", &info) == 0);

    remove("build/tests/notempty/keep.txt");
    remove("build/tests/notempty");
    printf("  a full directory, a missing file and a bad argument are refused\n");
}

/* Removing is not a failure to catch but a thing to look before doing, and the
   pieces to look with are all here. */
static void test_the_look_before_you_leap_idiom(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "p := \"build/tests/leap\"."
        /* "make sure of it" is two messages, and says which of the two it meant */
        "system:isDirectory(p):ifFalse({ system:makeDirectory(p) })."
        "once := system:isDirectory(p)."
        "system:isDirectory(p):ifFalse({ system:makeDirectory(p) })."
        "twice := system:isDirectory(p)."
        /* and a failure is catchable like any other */
        "caught := { system:remove(\"build/tests/no-such-thing\") }"
        "    :onError({ e | e:message:size:greaterThan(#0) })."
        "system:remove(p).") == SOL_OK);

    assert(SOL_AS_BOOL(global(&vm, "once")));
    assert(SOL_AS_BOOL(global(&vm, "twice")));
    assert(SOL_AS_BOOL(global(&vm, "caught")));

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  looking first, and catching when you did not\n");
}

/* Whether a value is exactly this text. */
static bool is_text(SolValue value, const char *expected)
{
    if (!SOL_IS_STRING(value)) return false;
    const SolString *s = SOL_AS_STRING(value);
    return s->length == (int)strlen(expected) &&
           memcmp(s->chars, expected, (size_t)s->length) == 0;
}

/* Running another program. An array of arguments rather than a command line,
   which is the decision in it: nothing in an array is ever read as syntax. */
static void test_running_a_program(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "ok := system:run([\"true\"])."
        "no := system:run([\"false\"])."
        "code := system:run([\"sh\", \"-c\", \"exit 3\"])."
        /* A command that is not there answers 127, which is what a shell
           answers, rather than failing: asking whether a tool is installed is a
           question rather than a mistake. */
        "missing := system:run([\"solveig-no-such-program\"]).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "ok")) == 0);
    assert(SOL_AS_INT(global(&vm, "no")) == 1);
    assert(SOL_AS_INT(global(&vm, "code")) == 3);
    assert(SOL_AS_INT(global(&vm, "missing")) == 127);
    sol_chunk_free(&chunk);

    static const char *refused[] = {
        "system:run(\"ls\").",              /* a string is not an argument list */
        "system:run([]).",                  /* nothing to run */
        "system:run([\"echo\", #1]).",      /* every argument is a string */
        "system:run().",
    };
    for (size_t i = 0; i < sizeof refused / sizeof refused[0]; i++) {
        assert(run(&vm, &chunk, refused[i]) == SOL_RUNTIME_ERROR);
        sol_chunk_free(&chunk);
    }

    sol_vm_free(&vm);
    printf("  running a program answers its status\n");
}

/* Capturing what it wrote, with the status beside it -- because a command's
   output is worth little without knowing whether it worked. */
static void test_capturing_output(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "r := system:capture([\"echo\", \"one two\"])."
        "text := r:at(\"output\")."
        "status := r:at(\"status\")."
        /* An argument with a space in it is one argument, which is the whole
           reason this takes an array. A shell would have made it two. */
        "spaced := system:capture([\"echo\", \"a b c\"]):at(\"output\")."
        /* And a failing command still hands back what it managed to say. */
        "failed := system:capture([\"sh\", \"-c\", \"echo said; exit 2\"])."
        "saidAnyway := failed:at(\"output\")."
        "failedStatus := failed:at(\"status\").") == SOL_OK);

    assert(is_text(global(&vm, "text"), "one two\n"));
    assert(SOL_AS_INT(global(&vm, "status")) == 0);
    assert(is_text(global(&vm, "spaced"), "a b c\n"));
    assert(is_text(global(&vm, "saidAnyway"), "said\n"));
    assert(SOL_AS_INT(global(&vm, "failedStatus")) == 2);
    sol_chunk_free(&chunk);

    /* More than a pipe holds, which deadlocks anything that waits for the child
       before reading what it wrote. */
    assert(run(&vm, &chunk,
        "big := system:capture([\"sh\", \"-c\", \"seq 1 200000\"])."
        "size := big:at(\"output\"):size."
        "bigStatus := big:at(\"status\").") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "size")) > 1000000);
    assert(SOL_AS_INT(global(&vm, "bigStatus")) == 0);
    sol_chunk_free(&chunk);

    sol_vm_free(&vm);
    printf("  capturing answers the output and the status\n");
}

/* Whatever a file holds now, as a string the caller frees. */
static char *file_holds(const char *path)
{
    FILE *f = fopen(path, "rb");
    assert(f != NULL);
    static char text[4096];
    size_t got = fread(text, 1, sizeof text - 1, f);
    text[got] = '\0';
    fclose(f);
    return text;
}

/* Where a child's streams go: an array of alternating name and value, a symbol
   for a manner and a string for a path.
 *
 * The claim worth testing hardest is `'discard`, because it is the one a
 * benchmark harness rests on and the one whose failure is invisible -- output
 * that should not appear looks exactly like output that appeared somewhere
 * else. So this test points its *own* stderr at a file for the length of the
 * call and reads it back, which is the only way to say "nothing reached ours"
 * rather than "we did not notice anything". */
static void test_a_childs_streams_go_where_they_are_told(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    /* Discarded, and proved by watching our own stderr. */
    static const char *ours = "build/tests/our-stderr";
    fflush(stderr);
    int saved = dup(STDERR_FILENO);
    FILE *sink = fopen(ours, "wb");
    assert(saved >= 0 && sink != NULL);
    assert(dup2(fileno(sink), STDERR_FILENO) >= 0);

    SolResult quiet = run(&vm, &chunk,
        "noisy := [\"/bin/sh\", \"-c\", \"echo out; echo err 1>&2; exit 3\"]."
        "r := system:capture(noisy, [\"stderr\", 'discard])."
        "quietText := r:at(\"output\")."
        "quietStatus := r:at(\"status\").");

    fflush(stderr);
    assert(dup2(saved, STDERR_FILENO) >= 0);
    close(saved);
    fclose(sink);

    assert(quiet == SOL_OK);
    assert(is_text(global(&vm, "quietText"), "out\n"));
    assert(SOL_AS_INT(global(&vm, "quietStatus")) == 3);   /* the status stays */
    assert(file_holds(ours)[0] == '\0');                   /* and nothing else */
    sol_chunk_free(&chunk);

    /* Merged, which for `capture` means into the answer. Order matters: stderr
       follows stdout to where it is *now*, so both land in the same place. */
    assert(run(&vm, &chunk,
        "merged := system:capture(noisy, [\"stderr\", 'merge]):at(\"output\").") == SOL_OK);
    assert(is_text(global(&vm, "merged"), "out\nerr\n"));
    sol_chunk_free(&chunk);

    /* To a file, through `run`, which is the message that can move stdout. */
    static const char *out = "build/tests/child-out";
    assert(run(&vm, &chunk,
        "status := system:run(noisy, [\"stdout\", \"build/tests/child-out\","
        "                             \"stderr\", 'merge]).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "status")) == 3);
    assert(strcmp(file_holds(out), "out\nerr\n") == 0);
    sol_chunk_free(&chunk);

    /* And in, which is the half the entry never mentioned: there was no way to
       give a child anything to read either. */
    assert(run(&vm, &chunk,
        "system:writeFile(\"build/tests/child-in\", \"fed in\")."
        "fed := system:capture([\"cat\"], [\"stdin\", \"build/tests/child-in\"])"
        "           :at(\"output\")."
        "starved := system:capture([\"cat\"], [\"stdin\", 'discard]):at(\"output\")."
        /* Saying 'share is saying the default out loud, and must change nothing.
           Not "stdout" though, even to share it: `capture` refuses that name
           whatever the value, because sharing stdout is the one thing it does
           not do. */
        "same := system:capture([\"echo\", \"hi\"], [\"stdin\", 'share, \"stderr\", 'share])"
        "            :at(\"output\")."
        ) == SOL_OK);
    assert(is_text(global(&vm, "fed"), "fed in"));
    assert(is_text(global(&vm, "starved"), ""));
    assert(is_text(global(&vm, "same"), "hi\n"));
    sol_chunk_free(&chunk);

    static const char *refused[] = {
        "system:run([\"true\"], \"stderr\").",          /* not an array */
        "system:run([\"true\"], [\"stderr\"]).",        /* a name with no value */
        "system:run([\"true\"], [#1, 'discard]).",      /* a name is a string */
        "system:run([\"true\"], [\"stdrr\", 'discard])."/* no such stream */,
        "system:run([\"true\"], [\"stderr\", 'quiet]).",/* no such manner */
        "system:run([\"true\"], [\"stdout\", 'merge]).",/* only stderr follows */
        "system:run([\"true\"], [\"stderr\", #1]).",    /* neither a manner nor a path */
        "system:run([\"true\"], [\"stderr\", 'share, \"stderr\", 'discard]).", /* twice */
        "system:run([\"true\"], [\"stdin\", \"build/tests/no-such-file\"]).",
        "system:run([\"true\"], [\"stdout\", \"build/tests/no/such/directory/x\"]).",
        /* `capture` keeps stdout by definition, so moving it is refused rather
           than quietly emptying the answer. */
        "system:capture([\"true\"], [\"stdout\", \"build/tests/child-out\"]).",
        "system:capture([\"true\"], [\"stdout\", 'discard]).",
        "system:run([\"true\"], [], []).",
    };
    for (size_t i = 0; i < sizeof refused / sizeof refused[0]; i++) {
        assert(run(&vm, &chunk, refused[i]) == SOL_RUNTIME_ERROR);
        sol_chunk_free(&chunk);
    }

    /* Nothing was left open by any of that -- thirteen refusals, several of
       which opened a file before meeting the pair that was wrong. */
    static const char *loop =
        "i := #0."
        "{ i:lessThan(#300) }:whileTrue({"
        "    system:run([\"true\"], [\"stdout\", \"build/tests/child-out\","
        "                           \"stderr\", 'discard, \"stdin\", 'discard])."
        "    i := i:inc })."
        "reached := i.";
    assert(run(&vm, &chunk, loop) == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "reached")) == 300);
    sol_chunk_free(&chunk);

    sol_vm_free(&vm);
    printf("  a child's streams go where they are told\n");
}

/* One byte at a time, without waiting for a line.
 *
 * Driven through a pipe, which is deterministic and is also half the contract:
 * raw mode is for a terminal, and a byte from a pipe is already a byte. The
 * terminal half -- that a key arrives before return is pressed -- needs a pty
 * and is in test_line.c, where the pty harness lives. */
static void test_read_key_takes_one_byte(void)
{
    /* stdin is replaced for the duration, since these primitives read it
       directly rather than through anything that could be handed a file. */
    FILE *script = fopen("build/tests/keys-in", "w");
    assert(script != NULL);
    fputs("aZ\n", script);
    fclose(script);

    int saved = dup(STDIN_FILENO);
    assert(saved >= 0);
    FILE *in = freopen("build/tests/keys-in", "r", stdin);
    assert(in != NULL);

    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;
    SolResult result = run(&vm, &chunk,
        "one := system:readKey."
        "two := system:readKey."
        "three := system:readKey."          /* the newline is a byte too */
        "past := system:readKey."           /* and then there are none */
        "oneCode := one:asByte."
        "threeCode := three:asByte."
        "ended := past:isNil.");

    /* Put stdin back before asserting, so a failure does not leave the harness
       reading from a file. */
    fflush(stdin);
    dup2(saved, STDIN_FILENO);
    close(saved);
    clearerr(stdin);

    assert(result == SOL_OK);
    assert(is_text(global(&vm, "one"), "a"));
    assert(is_text(global(&vm, "two"), "Z"));
    assert(SOL_AS_INT(global(&vm, "oneCode")) == 97);
    assert(SOL_AS_INT(global(&vm, "threeCode")) == 10);   /* the newline */
    assert(SOL_AS_BOOL(global(&vm, "ended")) == true);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
    remove("build/tests/keys-in");
    printf("  readKey takes one byte, and answers nil at the end\n");
}

/* `makeDirectory` answers whether it made one, rather than refusing a directory
   that is already there. "Make sure this exists" is what a script wants nine
   times in ten, and it was a test and a make before this. */
static void test_making_a_directory_answers_whether_it_did(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    remove("build/tests/made/inner");
    remove("build/tests/made");

    assert(run(&vm, &chunk,
        "first := system:makeDirectory(\"build/tests/made\")."
        "again := system:makeDirectory(\"build/tests/made\")."
        "third := system:makeDirectory(\"build/tests/made\").") == SOL_OK);
    assert(SOL_AS_BOOL(global(&vm, "first")) == true);
    assert(SOL_AS_BOOL(global(&vm, "again")) == false);
    assert(SOL_AS_BOOL(global(&vm, "third")) == false);
    sol_chunk_free(&chunk);

    /* Still one level: a missing parent is an error, not a thing it makes. */
    assert(run(&vm, &chunk,
        "system:makeDirectory(\"build/tests/made/a/b\").") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);

    /* And something that is not a directory in the way is an error rather than
       a false, because false means "it is there and it is fine" and this never
       will be. mkdir reports both the same way, which is why this is separated
       out here. */
    assert(run(&vm, &chunk,
        "system:writeFile(\"build/tests/made-file\", \"x\")."
        "system:makeDirectory(\"build/tests/made-file\").") == SOL_RUNTIME_ERROR);
    assert(strstr(vm.error_message.chars, "not a directory") != NULL);
    sol_chunk_free(&chunk);

    remove("build/tests/made-file");
    remove("build/tests/made");
    sol_vm_free(&vm);
    printf("  makeDirectory answers whether it made one\n");
}

/* A mode, read and written. An integer because that is what a mode is, with
   `asBase` and `asInteger` crossing to the octal text people recognise -- Solum
   has no octal literal, so #493 is what 0755 looks like written down. */
static void test_a_mode_can_be_read_and_set(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "system:writeFile(\"build/tests/mode-a\", \"x\")."
        "system:setMode(\"build/tests/mode-a\", \"755\":asInteger(#8))."
        "as755 := system:modeOf(\"build/tests/mode-a\"):asBase(#8)."
        "system:setMode(\"build/tests/mode-a\", \"600\":asInteger(#8))."
        "as600 := system:modeOf(\"build/tests/mode-a\"):asBase(#8)."
        /* The round trip a copy makes: read one, set the other. */
        "system:writeFile(\"build/tests/mode-b\", \"y\")."
        "system:setMode(\"build/tests/mode-b\","
        "                system:modeOf(\"build/tests/mode-a\"))."
        "same := system:modeOf(\"build/tests/mode-a\"):equals("
        "            system:modeOf(\"build/tests/mode-b\")).") == SOL_OK);
    assert(is_text(global(&vm, "as755"), "755"));
    assert(is_text(global(&vm, "as600"), "600"));
    assert(SOL_AS_BOOL(global(&vm, "same")) == true);
    sol_chunk_free(&chunk);

    /* The file type is masked off, so what comes back is permissions alone and
       setMode(to, modeOf(from)) cannot try to change what a thing is. */
    assert(run(&vm, &chunk,
        "d := system:modeOf(\"build/tests\")."
        "withinRange := d:greaterOrEqual(#0):and({ d:lessOrEqual(#4095) }).") == SOL_OK);
    assert(SOL_AS_BOOL(global(&vm, "withinRange")) == true);
    sol_chunk_free(&chunk);

    remove("build/tests/mode-a");
    remove("build/tests/mode-b");
    sol_vm_free(&vm);
    printf("  a mode is read and set as an integer\n");
}

/* A mode that is not one is refused rather than partly applied, which is what
   chmod would do with the bits it does not know. */
static void test_a_mode_out_of_range_is_refused(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk, "system:writeFile(\"build/tests/mode-c\", \"x\").") == SOL_OK);
    sol_chunk_free(&chunk);

    static const char *refused[] = {
        "system:setMode(\"build/tests/mode-c\", #99999).",
        "system:setMode(\"build/tests/mode-c\", #0:sub(#1)).",
        "system:setMode(\"build/tests/mode-c\", \"755\").",   /* a string is not a mode */
        "system:modeOf(\"build/tests/not-there-at-all\").",
    };
    for (size_t i = 0; i < sizeof refused / sizeof refused[0]; i++) {
        assert(run(&vm, &chunk, refused[i]) == SOL_RUNTIME_ERROR);
        sol_chunk_free(&chunk);
    }

    remove("build/tests/mode-c");
    sol_vm_free(&vm);
    printf("  a mode out of range, or of the wrong type, is refused\n");
}

/* `setModifiedAt` is why `modifiedAt` is worth having exactly: a copy can carry
   the original's time, so two matching files compare equal rather than the
   copy always being later. */
static void test_a_time_can_be_carried_across(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "system:writeFile(\"build/tests/time-a\", \"one\")."
        "system:writeFile(\"build/tests/time-b\", \"two\")."
        "before := system:modifiedAt(\"build/tests/time-a\"):equals("
        "              system:modifiedAt(\"build/tests/time-b\"))."
        "system:setModifiedAt(\"build/tests/time-b\","
        "                     system:modifiedAt(\"build/tests/time-a\"))."
        "after := system:modifiedAt(\"build/tests/time-a\"):equals("
        "             system:modifiedAt(\"build/tests/time-b\")).") == SOL_OK);
    /* Two files written in turn are almost never stamped identically now that
       the sub-second part survives -- but the test that matters is the second. */
    assert(SOL_AS_BOOL(global(&vm, "after")) == true);
    sol_chunk_free(&chunk);

    /* A time from before the epoch, where the seconds and nanoseconds have to
       be split by flooring rather than by truncating. */
    assert(run(&vm, &chunk,
        "old := \"1965-03-04T05:06:07Z\":asTime."
        "system:setModifiedAt(\"build/tests/time-a\", old)."
        "back := system:modifiedAt(\"build/tests/time-a\")."
        "kept := back:equals(old).") == SOL_OK);
    assert(SOL_AS_BOOL(global(&vm, "kept")) == true);
    sol_chunk_free(&chunk);

    assert(run(&vm, &chunk,
        "system:setModifiedAt(\"build/tests/time-a\", #5).") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);

    remove("build/tests/time-a");
    remove("build/tests/time-b");
    sol_vm_free(&vm);
    printf("  a time is carried from one file to another\n");
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
    test_listing_a_directory();
    test_listing_what_is_not_a_directory();
    test_appending();
    test_the_environment();
    test_making_moving_and_removing();
    test_changing_what_is_there_refuses();
    test_the_look_before_you_leap_idiom();
    test_a_large_file_round_trips();
    test_a_file_that_is_not_there_is_an_error();
    test_file_exists_means_a_file();

    test_running_a_program();
    test_capturing_output();
    test_a_childs_streams_go_where_they_are_told();
    test_read_key_takes_one_byte();
    test_making_a_directory_answers_whether_it_did();
    test_a_mode_can_be_read_and_set();
    test_a_mode_out_of_range_is_refused();
    test_a_time_can_be_carried_across();
    printf("test_system: ok\n");
    return 0;
}
