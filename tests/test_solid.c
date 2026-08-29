/* Solid, the debugger: driven the way a person drives it, through its own
   prompt.
 *
 * The commands go in on stdin and what comes back is read, which is exactly
 * what a session is -- and unlike the prompt in solis this needs no terminal,
 * since Solid reads lines rather than keys. */
#define _POSIX_C_SOURCE 200809L

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>

#define DIR "build/tests/solid"

static void write_file(const char *path, const char *text)
{
    FILE *f = fopen(path, "w");
    assert(f != NULL);
    fputs(text, f);
    fclose(f);
}

/* Runs solid over `program` with `commands` typed at it, and answers what it
   said. The caller frees nothing; the buffer is static-sized on purpose. */
static void session(const char *program, const char *commands,
                    char *out, size_t size)
{
    system("mkdir -p " DIR);
    write_file(DIR "/program.sol", program);

    char line[4096];
    snprintf(line, sizeof line, "printf '%s' | bin/solid " DIR "/program.sol 2>&1",
             commands);

    FILE *pipe = popen(line, "r");
    assert(pipe != NULL);

    size_t filled = 0, got;
    out[0] = '\0';
    while (filled + 1 < size &&
           (got = fread(out + filled, 1, size - filled - 1, pipe)) > 0) {
        filled += got;
    }
    out[filled] = '\0';
    pclose(pipe);
}

/* Compiles a library beside the program, for the `system:load` tests below.
   They need a `.sob`, since loading takes bytecode and never source. */
static void library(const char *source)
{
    system("mkdir -p " DIR);
    write_file(DIR "/lib.sol", source);
    assert(system("bin/solas " DIR "/lib.sol -o " DIR "/lib.sob") == 0);
}

/* It stops before the first line, so there is somewhere to work from. */
static void test_it_stops_at_the_start(void)
{
    char out[16384];
    session("a := #1.\nb := #2.\n", "quit\\n", out, sizeof out);

    assert(strstr(out, "program.sol:1") != NULL);
    assert(strstr(out, "a := #1.") != NULL);      /* the source line, shown */
    printf("  it stops before the first line\n");
}

/* Stepping walks a line at a time; `next` goes over a call where `step` goes
   into it. */
static void test_stepping(void)
{
    char out[16384];
    const char *program =
        "double := { n | n:mul(#2) }.\n"
        "x := double:value(#21).\n"
        "x:print.\n";

    session(program, "step\\nstep\\nwhere\\nquit\\n", out, sizeof out);
    /* Two steps from line 1 reach line 2 and then inside the block. */
    assert(strstr(out, "program.sol:2") != NULL);
    assert(strstr(out, "#1  ") != NULL);          /* a second frame in `where` */

    session(program, "step\\nnext\\nwhere\\nquit\\n", out, sizeof out);
    /* `next` from line 2 goes over the call and lands on line 3. */
    assert(strstr(out, "program.sol:3") != NULL);
    printf("  step goes into a call and next goes over it\n");
}

/* A breakpoint, and the locals of the frame it stops in -- by name, which is
   what 6.28 was built for. */
static void test_breakpoint_and_locals(void)
{
    char out[16384];
    const char *program =
        "withdraw := { amount | | after |\n"
        "    after := #100:sub(amount).\n"
        "    after }.\n"
        "withdraw:value(#30):print.\n";

    session(program, "break program.sol:3\\ncontinue\\nlocals\\n"
                     "print amount\\nprint after\\nquit\\n", out, sizeof out);

    assert(strstr(out, "program.sol:3") != NULL);
    assert(strstr(out, "amount") != NULL);
    assert(strstr(out, "#30") != NULL);
    assert(strstr(out, "after") != NULL);
    assert(strstr(out, "#70") != NULL);
    printf("  a breakpoint stops, and locals are named\n");
}

/* The globals, which is the one namespace a program cannot ask about itself:
   they are slots on an object with no name in the language, so neither `slots`
   nor `perform` reaches them. The debugger holds the root, so it can.

   Two claims, and the second is the one worth having. The names this program
   bound are listed **in the order they were bound**, not the order the slot
   list holds them in -- a new slot goes on the front, so reading the list
   straight through would put the last line of the program first. And the
   eighty-odd names the machine arrived with stay out of the way until asked
   for, since a listing they dominate answers a question nobody asked. */
static void test_globals_are_what_this_program_bound(void)
{
    char out[16384];
    /* The breakpoint is on a line that does not mention the method, so that
       "not in the listing" is about the listing rather than about the source
       line the debugger echoes when it stops. */
    const char *program =
        "first := #1.\n"
        "second := \"two\".\n"
        "integer:tripled := { self:mul(#3) }.\n"
        "answer := #5:tripled.\n"
        "answer:print.\n";

    session(program, "break program.sol:5\\ncontinue\\nglobals\\nquit\\n",
            out, sizeof out);

    const char *a = strstr(out, "first");
    const char *b = strstr(out, "second");
    assert(a != NULL && b != NULL);
    assert(a < b);                       /* bound first, listed first */
    assert(strstr(out, "#1") != NULL);
    assert(strstr(out, "\"two\"") != NULL);

    /* A method is a slot on `integer`, not a global, so it is not here. */
    assert(strstr(out, "tripled") == NULL);

    /* And what the machine brought is counted rather than printed. */
    assert(strstr(out, "built in") != NULL);
    assert(strstr(out, "system") == NULL);

    /* Until it is asked for, and then it is marked. */
    session(program, "break program.sol:5\\ncontinue\\nglobals all\\nquit\\n",
            out, sizeof out);
    assert(strstr(out, "system") != NULL);
    assert(strstr(out, "random") != NULL);
    assert(strstr(out, "(built in)") != NULL);
    /* The program's own are still last, and still unmarked. */
    const char *mine = strstr(out, "second");
    assert(mine != NULL && strstr(out, "system") < mine);

    /* A program that binds nothing says so rather than printing an empty list. */
    session("integer:doubled := { self:mul(#2) }.\n#5:doubled:print.\n",
            "break program.sol:2\\ncontinue\\nglobals\\nquit\\n", out, sizeof out);
    assert(strstr(out, "none bound by this program") != NULL);

    printf("  globals are what this program bound, in the order it bound them\n");
}

/* A breakpoint inside a loop fires every time round. The first version of this
   suppressed the repeats, having confused "coming back to a line" with "coming
   back from a call written on it". */
static void test_a_breakpoint_in_a_loop_fires_each_time(void)
{
    char out[16384];
    /* The breakpoint line holds nothing but the block's body. A line a block
       *literal* also ends on belongs to the frame that defines it as well as
       to the one that runs it, and a line breakpoint rightly matches both --
       which is a fine thing for it to do and a poor thing to write a test on. */
    const char *program =
        "total := #0.\n"
        "adder := { n |\n"
        "    total := total:add(n).\n"
        "    total }.\n"
        "[#1,#3]:loop(adder).\n"
        "total:print.\n";

    session(program, "break program.sol:3\\ncontinue\\nprint n\\ncontinue\\n"
                     "print n\\ncontinue\\nprint n\\nquit\\n", out, sizeof out);

    assert(strstr(out, "n = #1") != NULL);
    assert(strstr(out, "n = #2") != NULL);
    assert(strstr(out, "n = #3") != NULL);
    printf("  a breakpoint in a loop fires every time round\n");
}

/* And a breakpoint on a line a call is written on fires once for that visit,
   not twice -- arriving and returning are one arrival. */
static void test_a_breakpoint_fires_once_per_visit(void)
{
    char out[16384];
    const char *program =
        "double := { n | n:mul(#2) }.\n"
        "x := double:value(#21).\n"
        "y := #1.\n";

    session(program, "break program.sol:2\\ncontinue\\ncontinue\\nquit\\n",
            out, sizeof out);

    /* The second `continue` runs to the end rather than stopping again. */
    assert(strstr(out, "the program finished") != NULL);
    printf("  a breakpoint fires once for one visit to its line\n");
}

/* The thing a debugger can do that a prompt afterwards cannot: stop where it
   broke, with the frames still standing and the bad value still in one. */
static void test_it_stops_where_it_broke(void)
{
    char out[16384];
    const char *program =
        "divide := { a, b | a:div(b) }.\n"
        "divide:value(#100, #0):print.\n";

    session(program, "continue\\nwhere\\nlocals\\nprint b\\nquit\\n",
            out, sizeof out);

    assert(strstr(out, "division by zero") != NULL);
    assert(strstr(out, "cannot go on from here") != NULL);
    /* The frames are still there, and so is what made it fail. */
    assert(strstr(out, "b = #0") != NULL);
    assert(strstr(out, "a  ") != NULL);
    printf("  it stops where the program broke, with the frames standing\n");
}

/* Leaving is not a failure of the program. */
static void test_quitting_is_not_a_failure(void)
{
    system("mkdir -p " DIR);
    write_file(DIR "/quiet.sol", "a := #1.\n");
    int status = system("printf 'quit\\n' | bin/solid " DIR "/quiet.sol >/dev/null 2>&1");
    assert(WIFEXITED(status) && WEXITSTATUS(status) == 0);
    printf("  quitting leaves with 0\n");
}

/* ------------------------------------------------------------------
 * `system:load`, from the debugger's side.
 *
 * A loaded file is a frame like any other -- that is the whole claim, and it is
 * what `sol_vm_call_chunk` pushing an ordinary frame buys. None of this needed
 * a line of Solid to be written; these tests exist so that it keeps being true.
 */

/* Stepping goes into the loaded file, and the stack shows both. */
static void test_stepping_into_a_loaded_file(void)
{
    char out[16384];
    library("greet := { who |\n    \"hello, \":concat(who) }.\nlibMark := #7.\n");

    session("before := #1.\n"
            "system:load(\"" DIR "/lib.sob\").\n"
            "greet:value(\"world\"):display.\n",
            "step\\nstep\\nwhere\\nlist\\ncontinue\\n", out, sizeof out);

    assert(strstr(out, DIR "/lib.sol:") != NULL);       /* it went in */
    assert(strstr(out, "#1  " DIR "/program.sol:2") != NULL);  /* and can see out */
    assert(strstr(out, "libMark := #7.") != NULL);      /* `list` found the source */
    assert(strstr(out, "hello, world") != NULL);
    printf("  stepping goes into a loaded file, and `where` shows both\n");
}

/* A breakpoint may be set in a file that has not been loaded yet -- which is
   the only order that is any use, since after it has loaded it has run. */
static void test_a_breakpoint_in_a_file_not_yet_loaded(void)
{
    char out[16384];
    library("libMark := #7.\nlibAgain := #8.\n");

    session("before := #1.\n"
            "system:load(\"" DIR "/lib.sob\").\n"
            "after := #2.\n",
            "break " DIR "/lib.sol:2\\ncontinue\\nwhere\\ncontinue\\n",
            out, sizeof out);

    assert(strstr(out, "break at " DIR "/lib.sol:2") != NULL);
    assert(strstr(out, DIR "/lib.sol:2") != NULL);
    assert(strstr(out, "#1  " DIR "/program.sol:2") != NULL);
    printf("  a breakpoint fires in a file that had not been loaded yet\n");
}

/* `next` treats a load as one step, and `finish` leaves one from inside --
   even though a top-level chunk ends in HALT rather than RETURN. */
static void test_next_over_a_load_and_finish_out_of_one(void)
{
    char out[16384];
    library("libMark := #7.\nlibAgain := #8.\n");

    const char *program = "before := #1.\n"
                          "system:load(\"" DIR "/lib.sob\").\n"
                          "after := #2.\n";

    session(program, "next\\nnext\\nwhere\\ncontinue\\n", out, sizeof out);
    assert(strstr(out, DIR "/program.sol:3") != NULL);   /* stepped over it */
    assert(strstr(out, DIR "/lib.sol") == NULL);         /* and never showed it */

    session(program, "break " DIR "/lib.sol:2\\ncontinue\\nfinish\\nwhere\\ncontinue\\n",
            out, sizeof out);
    assert(strstr(out, "#0  " DIR "/program.sol:2") != NULL);
    printf("  `next` goes over a load and `finish` comes back out of one\n");
}

/* The case loading makes ordinary: a compiled library shipped without its
   source. Everything but `list` still works, and `list` says why. */
static void test_a_loaded_file_without_its_source(void)
{
    char out[16384];
    library("libMark := #7.\nlibAgain := #8.\n");
    remove(DIR "/lib.sol");

    session("system:load(\"" DIR "/lib.sob\").\n"
            "after := #2.\n",
            "step\\nlist\\nwhere\\nstep\\nstep\\nprint libMark\\ncontinue\\n",
            out, sizeof out);

    assert(strstr(out, "cannot read " DIR "/lib.sol") != NULL);
    assert(strstr(out, "#1  " DIR "/program.sol:1") != NULL);
    assert(strstr(out, "libMark = #7") != NULL);
    printf("  a loaded file with no source still steps, and `list` says why\n");
}

/* And the one a debugger is actually for: a failure inside a loaded file stops
   where it failed, in that file, with the frame that loaded it still under it
   and both files' globals readable. */
static void test_a_failure_inside_a_loaded_file_stops_there(void)
{
    char out[16384];
    library("libMark := #7.\nnil:noSuchMessage.\n");

    session("before := #1.\n"
            "system:load(\"" DIR "/lib.sob\").\n"
            "after := #2.\n",
            "continue\\nwhere\\nlist\\nprint libMark\\nprint before\\nquit\\n",
            out, sizeof out);

    assert(strstr(out, "nil does not understand 'noSuchMessage'") != NULL);
    assert(strstr(out, DIR "/lib.sol:2") != NULL);       /* stopped in there */
    assert(strstr(out, "#1  " DIR "/program.sol:2") != NULL);
    assert(strstr(out, "libMark = #7") != NULL);         /* the loaded file's */
    assert(strstr(out, "before = #1") != NULL);          /* and the caller's */
    printf("  a failure inside a loaded file stops there, over the loading frame\n");
}


/* ---- --exports: the surface rather than the stepping --------------------- *
 *
 * A different mode with no prompt: it runs the file and reports, so what is
 * driven here is a command line rather than a session. */

/* Runs solid over `program` in --exports mode and answers what it said, with
   the status put where an assertion can reach it. `flags` is what goes before
   the file -- `--exports`, `--exports=all`, or an --extension= beside one. */
static int reported(const char *program, const char *flags, char *out, size_t size)
{
    system("mkdir -p " DIR);
    if (program != NULL) write_file(DIR "/program.sol", program);

    char line[4096];
    snprintf(line, sizeof line, "bin/solid %s %s 2>&1",
             flags, program != NULL ? DIR "/program.sol" : "");

    FILE *pipe = popen(line, "r");
    assert(pipe != NULL);

    size_t filled = 0, got;
    out[0] = '\0';
    while (filled + 1 < size &&
           (got = fread(out + filled, 1, size - filled - 1, pipe)) > 0) {
        filled += got;
    }
    out[filled] = '\0';
    int status = pclose(pipe);
    return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}

/* The ordinary case: a library binds a name, and what may be sent to it is
   listed with the arity each one takes. */
static void test_exports_lists_what_a_file_bound(void)
{
    char out[16384];
    int status = reported("greet := object:new.\n"
                          "greet:hello := { name | name }.\n"
                          "greet:count := #3.\n",
                          "--exports", out, sizeof out);

    assert(status == 0);
    assert(strstr(out, "greet") != NULL);
    assert(strstr(out, "hello") != NULL);
    assert(strstr(out, "takes 1 argument") != NULL);
    assert(strstr(out, "count") != NULL);
    assert(strstr(out, "#3") != NULL);          /* a data slot shows its value */
    printf("  --exports lists what a file bound, with each arity\n");
}

/* The case a reader of OP_SET_GLOBAL would get wrong. `lib/text.sol` is this
   shape: it binds no name at all and hangs a method on `integer`, so a report
   built from what the file *bound* would be empty and would be wrong. */
static void test_exports_sees_a_class_that_was_extended(void)
{
    char out[16384];
    int status = reported("integer:double := { self:mul(#2) }.\n",
                          "--exports", out, sizeof out);

    assert(status == 0);
    assert(strstr(out, "integer") != NULL);
    assert(strstr(out, "(extended)") != NULL);
    assert(strstr(out, "double") != NULL);
    printf("  --exports sees a class extended by a file that binds nothing\n");
}

/* A boundary is the answer to the question, so it is honoured: what it keeps
   private is counted and not listed, and `--exports=all` lists it. */
static void test_exports_honours_a_boundary(void)
{
    char out[16384];
    const char *program =
        "counter := object:new.\n"
        "counter:total := #0.\n"
        "counter:secret := { #42 }.\n"
        "counter:bump := { self:total := self:total:add(#1) }.\n"
        "counter:exports(['bump, 'total]).\n";

    int status = reported(program, "--exports", out, sizeof out);
    assert(status == 0);
    assert(strstr(out, "bump") != NULL);
    assert(strstr(out, "total") != NULL);
    assert(strstr(out, "secret") == NULL);              /* behind the boundary */
    assert(strstr(out, "1 behind an `exports` boundary") != NULL);

    status = reported(program, "--exports=all", out, sizeof out);
    assert(status == 0);
    assert(strstr(out, "secret") != NULL);
    assert(strstr(out, "(not exported)") != NULL);
    printf("  --exports honours an `exports` boundary, and =all steps over it\n");
}

/* A `.sob` is the file somebody actually has when they are asking this, since a
   library may be shipped without its source. It reads the same. */
static void test_exports_reads_bytecode(void)
{
    char out[16384];
    library("shipped := object:new.\nshipped:go := { #1 }.\n");
    remove(DIR "/lib.sol");

    int status = reported(NULL, "--exports " DIR "/lib.sob", out, sizeof out);
    assert(status == 0);
    assert(strstr(out, "shipped") != NULL);
    assert(strstr(out, "go") != NULL);
    printf("  --exports reads a .sob with no source beside it\n");
}

/* A `.so` has no bytecode to read at all: its surface exists only once
   `sol_extension_init` has run. Same report, and with nothing else named there
   is no file to give. */
static void test_exports_reads_an_extension(void)
{
    char out[16384];
    int status = reported(NULL, "--exports --extension=build/tests/ext_probe.so",
                          out, sizeof out);

    assert(status == 0);
    assert(strstr(out, "probe") != NULL);
    assert(strstr(out, "shout") != NULL);
    assert(strstr(out, "a primitive") != NULL);
    printf("  --exports reads a .so, with no file to give it\n");
}

/* Two subjects on one command line are two reports, so which of them bound a
   name is never a guess. */
static void test_exports_keeps_the_two_subjects_apart(void)
{
    char out[16384];
    int status = reported("mine := object:new.\nmine:own := { #1 }.\n",
                          "--exports --extension=build/tests/ext_probe.so",
                          out, sizeof out);
    assert(status == 0);

    const char *probe = strstr(out, "probe");
    const char *mine  = strstr(out, "mine");
    assert(probe != NULL && mine != NULL);
    assert(strstr(out, "ext_probe.so") < probe);   /* each under its own name */
    assert(probe < strstr(out, "program.sol"));
    assert(strstr(out, "program.sol") < mine);
    printf("  --exports reports an extension and a file separately\n");
}

/* It runs the file, so a file that fails is a thing that happens. What it had
   bound by then is still the useful answer, said as what it is. */
static void test_exports_reports_a_file_that_did_not_finish(void)
{
    char out[16384];
    int status = reported("half := object:new.\n"
                          "half:there := { #1 }.\n"
                          "nil:noSuchMessage.\n",
                          "--exports", out, sizeof out);

    assert(status == 70);
    assert(strstr(out, "did not finish") != NULL);
    assert(strstr(out, "noSuchMessage") != NULL);
    assert(strstr(out, "half") != NULL);           /* still says what it got to */
    assert(strstr(out, "there") != NULL);
    printf("  --exports says what a file that failed had bound by then\n");
}

/* The surface is measured before the file runs and read after, which means
   holding an object across a run that may have freed it: rebind the name an
   extension bound and the object that was there has no root left. What is
   recorded is checked against the name it came from before it is read again, so
   this is a report that skips it rather than a read of freed memory -- which is
   what the sanitised build is here to prove. */
static void test_exports_survives_a_global_being_replaced(void)
{
    char out[16384];
    int status = reported("probe := #1.\nafter := #2.\n",
                          "--exports --extension=build/tests/ext_probe.so",
                          out, sizeof out);

    assert(status == 0);
    assert(strstr(out, "shout") != NULL);          /* the bundle, before */
    assert(strstr(out, "after") != NULL);          /* the file, after */
    printf("  --exports survives a file replacing what an extension bound\n");
}

/* And the empty answer is an answer, rather than an empty report that reads
   like something went wrong. */
static void test_exports_says_when_there_is_nothing(void)
{
    char out[16384];
    int status = reported("#1:add(#2).\n", "--exports", out, sizeof out);

    assert(status == 0);
    assert(strstr(out, "binds nothing and extends nothing") != NULL);
    printf("  --exports says so when a file binds nothing\n");
}

int main(void)
{
    test_it_stops_at_the_start();
    test_stepping();
    test_breakpoint_and_locals();
    test_globals_are_what_this_program_bound();
    test_a_breakpoint_in_a_loop_fires_each_time();
    test_a_breakpoint_fires_once_per_visit();
    test_it_stops_where_it_broke();
    test_quitting_is_not_a_failure();
    test_stepping_into_a_loaded_file();
    test_a_breakpoint_in_a_file_not_yet_loaded();
    test_next_over_a_load_and_finish_out_of_one();
    test_a_loaded_file_without_its_source();
    test_a_failure_inside_a_loaded_file_stops_there();
    test_exports_lists_what_a_file_bound();
    test_exports_sees_a_class_that_was_extended();
    test_exports_honours_a_boundary();
    test_exports_reads_bytecode();
    test_exports_reads_an_extension();
    test_exports_keeps_the_two_subjects_apart();
    test_exports_reports_a_file_that_did_not_finish();
    test_exports_survives_a_global_being_replaced();
    test_exports_says_when_there_is_nothing();
    printf("test_solid: ok\n");
    return 0;
}
