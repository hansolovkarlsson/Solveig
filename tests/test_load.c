/* `system:load`: running a file that is already compiled, in the machine that
 * is already running.
 *
 * The run-time twin of `@include`, and the tests split the same way the feature
 * does: what it shares with the directive (one flat namespace, and everything
 * the loaded file binds is simply there), and what only a message can get
 * wrong -- a chunk arriving mid-run has to be rooted, unwound and accounted for
 * by hand, and each of those was a bug before it was a test. */
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#include "solas/compiler.h"
#include "solum/gc.h"
#include "solum/serialize.h"
#include "solum/vm.h"

#define DIR "build/tests/load"

static void make_directories(void)
{
    mkdir("build/tests", 0777);
    mkdir(DIR, 0777);
}

/* Compiles `source` and writes it out, which is what gives a test something to
   load: `system:load` takes a .sob and never a .sol. */
static void compile_to_sob(const char *source, const char *path)
{
    SolChunk chunk;
    sol_chunk_init(&chunk);
    assert(sol_compile_source(source, path, &chunk));
    assert(sol_chunk_save(&chunk, path) == SOL_SER_OK);
    sol_chunk_free(&chunk);
}

/* Runs `source` in `vm` and answers how it went. The chunk is the collector's,
   because a program under test may bind a block and be asked about it after
   this returns -- the same reason `system:load` loads into a code cell. */
static SolResult run_source(SolVM *vm, const char *source)
{
    SolCode *code = sol_code_new(vm);
    sol_gc_push_temp(vm, &code->gc);
    bool compiled = sol_compile_source(source, "test", &code->chunk);
    assert(compiled);
    sol_gc_pop_temp(vm);
    return sol_vm_run(vm, &code->chunk);
}

static SolValue global(SolVM *vm, const char *name)
{
    SolSlot *slot = sol_object_lookup(vm->root, name);
    return slot ? slot->value : SOL_NIL_VAL;
}

/* A machine that keeps its failures to itself, so a test can read the message
   instead of the suite printing it. */
static void quiet_vm(SolVM *vm)
{
    sol_vm_init(vm);
    vm->report_errors = false;
}

/* ------------------------------------------------------------------ */

/* The whole of the connection between two files is the names one binds and the
   other sends -- so a value, a block and a method on a built-in class all cross
   the same way, because all three are slots in one flat namespace. */
static void test_what_the_loaded_file_bound_is_simply_there(void)
{
    compile_to_sob("mark := #40.\n"
                   "greet := { who | \"hello, \":concat(who) }.\n"
                   "integer:twice := { self:mul(#2) }.\n",
                   DIR "/lib.sob");

    SolVM vm;
    quiet_vm(&vm);
    assert(run_source(&vm, "system:load(\"" DIR "/lib.sob\").\n"
                           "value := mark:add(#2).\n"
                           "text := greet:value(\"world\").\n"
                           "doubled := #21:twice.\n") == SOL_OK);

    assert(SOL_AS_INT(global(&vm, "value")) == 42);
    assert(strcmp(SOL_AS_STRING(global(&vm, "text"))->chars, "hello, world") == 0);
    assert(SOL_AS_INT(global(&vm, "doubled")) == 42);
    sol_vm_free(&vm);
}

/* The bug this feature was born with.
 *
 * `sol_chunk_load` initialises the chunk it is handed -- it must, since `solvm`
 * gives it a bare one -- and initialising clears the owner that `sol_code_new`
 * had set. Every method read afterwards inherited that, so every block the file
 * defined carried no owner, and a block with no owner is, to the collector,
 * code that nothing refers to. The load worked; the call afterwards ran into
 * freed memory, but only if a collection happened to fall in between.
 *
 * Which is why this test collects on purpose. Under `gc_stress` the sweep
 * happens at every allocation, so the window is not a window but a certainty. */
static void test_a_block_survives_the_collection_after_the_load(void)
{
    compile_to_sob("greet := { who | \"hello, \":concat(who) }.\n",
                   DIR "/block.sob");

    SolVM vm;
    quiet_vm(&vm);
    vm.gc_stress = true;

    assert(run_source(&vm, "system:load(\"" DIR "/block.sob\").\n") == SOL_OK);

    /* Nothing is executing the loaded chunk any more: the only thing reaching
       it is the block in `greet`, which is the whole point. */
    sol_gc_collect(&vm);
    sol_gc_collect(&vm);

    assert(run_source(&vm, "text := greet:value(\"world\").\n") == SOL_OK);
    assert(strcmp(SOL_AS_STRING(global(&vm, "text"))->chars, "hello, world") == 0);
    sol_vm_free(&vm);
}

/* Once-only, as `@include` is: a file runs the first time it is asked for and
   not again, so two files may each load what they need without arranging
   between themselves who loads what.
 *
   The answer is what says which happened -- true for a file that ran, false for
   one already there -- on the model of `makeDirectory`, which answers the same
   question about the same kind of idempotence. */
static void test_loading_twice_runs_the_file_once(void)
{
    compile_to_sob("times := times:add(#1).\n", DIR "/count.sob");

    SolVM vm;
    quiet_vm(&vm);
    assert(run_source(&vm, "times := #0.\n"
                           "first  := system:load(\"" DIR "/count.sob\").\n"
                           "second := system:load(\"" DIR "/count.sob\").\n"
                           "third  := system:load(\"" DIR "/count.sob\").\n") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "times")) == 1);
    assert(SOL_AS_BOOL(global(&vm, "first")) == true);
    assert(SOL_AS_BOOL(global(&vm, "second")) == false);
    assert(SOL_AS_BOOL(global(&vm, "third")) == false);
    sol_vm_free(&vm);
}

/* The memory is keyed by identity and not by spelling -- the realpath, which is
   how `@include` keys its own list. Three names for one file are one file. */
static void test_two_names_for_one_file_are_one_file(void)
{
    compile_to_sob("seen := seen:add(#1).\n", DIR "/same.sob");

    SolVM vm;
    quiet_vm(&vm);
    assert(run_source(&vm, "seen := #0.\n"
                           "system:load(\"" DIR "/same.sob\").\n"
                           "system:load(\"./" DIR "/same.sob\").\n"
                           "system:load(\"" DIR "/../load/same.sob\").\n") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "seen")) == 1);
    sol_vm_free(&vm);
}

/* A file that could not be used is not remembered as though it had been, so the
   memory holds files that ran rather than files that were mentioned. */
static void test_a_file_that_failed_to_load_is_not_remembered(void)
{
    /* The build directory outlives a run, and the second half of this test
       creates the file -- so without this, a rerun starts with it already
       there and tests nothing. */
    remove(DIR "/appears-later.sob");

    SolVM vm;
    quiet_vm(&vm);
    assert(run_source(&vm, "system:load(\"" DIR "/appears-later.sob\").\n") != SOL_OK);
    sol_vm_free(&vm);

    /* Now it exists. A machine that had refused it must still be willing. */
    compile_to_sob("arrived := #1.\n", DIR "/appears-later.sob");

    quiet_vm(&vm);
    assert(run_source(&vm, "system:load(\"" DIR "/appears-later.sob\").\n") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "arrived")) == 1);
    sol_vm_free(&vm);
}

/* And it shares `@include`'s hazard undiluted: one flat namespace, nothing
   marks where a name came from, and a name bound twice is silently the second
   one. ROADMAP 3.10, reached by a different road. */
static void test_a_name_bound_twice_is_the_second_one(void)
{
    compile_to_sob("shared := #1.\n", DIR "/first.sob");
    compile_to_sob("shared := #2.\n", DIR "/second.sob");

    SolVM vm;
    quiet_vm(&vm);
    assert(run_source(&vm, "system:load(\"" DIR "/first.sob\").\n"
                           "system:load(\"" DIR "/second.sob\").\n") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "shared")) == 2);
    sol_vm_free(&vm);
}

/* A loaded file may load another, because there is nothing special about the
   frame it runs in. */
static void test_a_loaded_file_may_load_another(void)
{
    compile_to_sob("deep := #7.\n", DIR "/deep.sob");
    compile_to_sob("system:load(\"" DIR "/deep.sob\").\n", DIR "/mid.sob");

    SolVM vm;
    quiet_vm(&vm);
    assert(run_source(&vm, "system:load(\"" DIR "/mid.sob\").\n") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "deep")) == 7);
    sol_vm_free(&vm);
}

/* A file loading itself ends, and ends quietly, because the file is written
   down before it runs -- so the inner load finds it already there and does
   nothing. `@include` calls this "a cycle that ends on purpose"; this is the
   same cycle ending for the same reason.
 *
 * It ran twice here rather than once, and that is not the memory failing. The
 * program the machine was *started* with did not arrive through `system:load`
 * and so was never written down; the load inside it is the first time this file
 * is asked for. The second is the one that stops. */
static void test_a_file_loading_itself_ends(void)
{
    compile_to_sob("ran := ran:add(#1).\n"
                   "system:load(\"" DIR "/self.sob\").\n", DIR "/self.sob");

    SolVM vm;
    quiet_vm(&vm);
    assert(run_source(&vm, "ran := #0.\n"
                           "system:load(\"" DIR "/self.sob\").\n") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "ran")) == 1);
    sol_vm_free(&vm);
}

/* Deep nesting still has a floor, and it is the machine's own.
 *
 * Once-only makes the runaway hard to write by hand -- a file cannot reach
 * itself any more -- so this builds a chain of distinct files long enough to
 * pass SOL_FRAMES_MAX. It ends in `call depth exceeded`, catchable, with the
 * machine still standing. The version of this that mattered was the one before
 * it: the chunk used to be held across the nested run by a temporary root, the
 * roots are eight deep with a hard exit(1) on top, and the ninth nested load
 * killed the process outright. */
static void test_a_long_chain_reaches_the_frame_limit(void)
{
    enum { LINKS = 300 };
    for (int i = 0; i < LINKS; i++) {
        char path[256], source[512];
        snprintf(path, sizeof path, DIR "/chain%d.sob", i);
        snprintf(source, sizeof source,
                 "system:load(\"" DIR "/chain%d.sob\").\n", i + 1);
        compile_to_sob(source, path);
    }

    SolVM vm;
    quiet_vm(&vm);
    assert(run_source(&vm, "system:load(\"" DIR "/chain0.sob\").\n") != SOL_OK);
    assert(strstr(vm.error_message.chars, "call depth exceeded") != NULL);
    sol_vm_free(&vm);
}

/* A failure inside the loaded file is an ordinary failure. It unwinds through
   the load, and the trace names both files -- the line in the file that failed,
   and the line that loaded it. */
static void test_a_failure_inside_unwinds_through_the_load(void)
{
    compile_to_sob("nil:noSuchMessage.\n", DIR "/boom.sob");

    SolVM vm;
    quiet_vm(&vm);
    assert(run_source(&vm, "before := #1.\n"
                           "system:load(\"" DIR "/boom.sob\").\n"
                           "after := #2.\n") != SOL_OK);

    assert(strstr(vm.error_message.chars, "noSuchMessage") != NULL);
    assert(strstr(vm.error_trace.chars, "boom.sob") != NULL);
    assert(strstr(vm.error_trace.chars, "test") != NULL);
    sol_vm_free(&vm);
}

/* Anything wrong with the file is a failure the program can see, rather than a
   crash: a .sob is untrusted input and is verified before it can run. */
static void test_a_file_that_cannot_be_used_is_refused(void)
{
    SolVM vm;
    quiet_vm(&vm);

    assert(run_source(&vm, "system:load(\"" DIR "/nothing-here.sob\").\n") != SOL_OK);
    assert(strstr(vm.error_message.chars, "cannot load") != NULL);
    sol_vm_free(&vm);

    FILE *f = fopen(DIR "/garbage.sob", "wb");
    assert(f != NULL);
    assert(fwrite("not a sob file at all", 1, 21, f) == 21);
    fclose(f);

    quiet_vm(&vm);
    assert(run_source(&vm, "system:load(\"" DIR "/garbage.sob\").\n") != SOL_OK);
    assert(strstr(vm.error_message.chars, "cannot load") != NULL);
    sol_vm_free(&vm);

    quiet_vm(&vm);
    assert(run_source(&vm, "system:load(#5).\n") != SOL_OK);
    assert(strstr(vm.error_message.chars, "expects a path") != NULL);
    sol_vm_free(&vm);
}

/* A top-level chunk ends in OP_HALT, and HALT unwinds nothing -- it returns
   from wherever it stands, leaving its frame and its slots behind. So the
   nested run puts both back by hand, and this is what says it did: a loop that
   loads a hundred times would run out of stack if each load kept its slots, and
   a frame left behind would show up as depth that never comes back. */
static void test_the_load_leaves_the_stack_as_it_found_it(void)
{
    compile_to_sob("kept := #1.\n", DIR "/small.sob");

    /* Measured against the same loop with the loads taken out, rather than
       against a number written here: what matters is that loading two hundred
       times costs nothing that not loading does not, and a baseline says that
       without this test having an opinion about what a finished run leaves. */
    SolVM plain;
    quiet_vm(&plain);
    assert(run_source(&plain, "kept := #1.\n"
                              "n := #0.\n"
                              "#200:repeat({ n := n:add(kept). }).\n") == SOL_OK);
    int plain_frames = plain.frame_count;
    long plain_stack = plain.stack_top - plain.stack;
    assert(SOL_AS_INT(global(&plain, "n")) == 200);
    sol_vm_free(&plain);

    SolVM vm;
    quiet_vm(&vm);
    assert(run_source(&vm, "n := #0.\n"
                           "#200:repeat({ system:load(\"" DIR "/small.sob\"). "
                           "              n := n:add(kept). }).\n") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "n")) == 200);
    assert(vm.frame_count == plain_frames);
    assert(vm.stack_top - vm.stack == plain_stack);
    sol_vm_free(&vm);
}

int main(void)
{
    make_directories();

    test_what_the_loaded_file_bound_is_simply_there();
    test_a_block_survives_the_collection_after_the_load();
    test_loading_twice_runs_the_file_once();
    test_two_names_for_one_file_are_one_file();
    test_a_file_that_failed_to_load_is_not_remembered();
    test_a_name_bound_twice_is_the_second_one();
    test_a_loaded_file_may_load_another();
    test_a_file_loading_itself_ends();
    test_a_long_chain_reaches_the_frame_limit();
    test_a_failure_inside_unwinds_through_the_load();
    test_a_file_that_cannot_be_used_is_refused();
    test_the_load_leaves_the_stack_as_it_found_it();

    printf("test_load: ok\n");
    return 0;
}
