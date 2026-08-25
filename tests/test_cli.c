/* The three binaries' command lines. Everything else in this suite links
   libsol.a and calls in; a `main` is not in the library, so these run the
   binaries as a shell would and read what comes back. That is the only way to
   check the two things that matter here: which stream the text went to, and
   what status the process left with. */
#define _POSIX_C_SOURCE 200809L

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "solum/common.h"
#include "solum/serialize.h"

#define DIR "build/tests/cli"

/* Runs `command` and answers its exit status, copying up to `size` bytes of
   whatever it wrote to `out`. Only one stream is captured per call, so the
   caller redirects the one it does not want. */
static int run(const char *command, char *out, size_t size)
{
    out[0] = '\0';
    FILE *pipe = popen(command, "r");
    assert(pipe != NULL);

    size_t filled = 0;
    size_t n;
    while (filled + 1 < size &&
           (n = fread(out + filled, 1, size - filled - 1, pipe)) > 0) {
        filled += n;
    }
    out[filled] = '\0';

    int status = pclose(pipe);
    return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}

/* `--help` was asked for, so it is not an error: the text goes to stdout where
   a pipe or a pager can have it, and the status is 0. */
static void test_help_is_not_an_error(void)
{
    static const char *commands[] = {
        "bin/solas --help 2>/dev/null",
        "bin/solvm --help 2>/dev/null",
        "bin/solis --help 2>/dev/null",
        "bin/solas -h 2>/dev/null",
        "bin/solvm -h 2>/dev/null",
        "bin/solis -h 2>/dev/null",
    };
    char out[4096];

    for (size_t i = 0; i < sizeof commands / sizeof commands[0]; i++) {
        assert(run(commands[i], out, sizeof out) == 0);
        assert(strstr(out, "usage:") != NULL);
        /* Every option the binary accepts is named, which is the whole job. */
        assert(strstr(out, "--help") != NULL);
        assert(strstr(out, "--version") != NULL);
    }
    printf("  --help goes to stdout and leaves with 0\n");
}

/* `--version` names the binary, the release, and the `.sob` format it speaks.
   The format number is the useful half: a file from a build with a different
   one is refused, and this is where you find out which number you are holding.
   Checked against the constants rather than against a copy of the text, so a
   release that bumps either cannot leave this passing and wrong. */
static void test_version_names_the_format(void)
{
    static const char *names[] = { "solas", "solvm", "solis" };
    char out[4096];
    char command[256];
    char expected[256];

    snprintf(expected, sizeof expected, SOLUM_VERSION " (.sob format %d)",
             SOL_SOB_VERSION);

    for (size_t i = 0; i < sizeof names / sizeof names[0]; i++) {
        snprintf(command, sizeof command, "bin/%s --version 2>/dev/null", names[i]);
        assert(run(command, out, sizeof out) == 0);
        assert(strstr(out, names[i]) == out);   /* the name it was called by */
        assert(strstr(out, expected) != NULL);
    }
    printf("  --version names the binary, the release and the .sob format\n");
}

/* The same words after a mistake are a different thing: stderr, and a status
   that says the command line was wrong. */
static void test_a_mistake_goes_to_stderr(void)
{
    char out[4096];

    /* stdout discarded, so anything read here came from stderr. */
    assert(run("bin/solas 2>&1 1>/dev/null", out, sizeof out) == 64);
    assert(strstr(out, "usage:") != NULL);

    assert(run("bin/solvm 2>&1 1>/dev/null", out, sizeof out) == 64);
    assert(strstr(out, "usage:") != NULL);

    /* And nothing went to stdout on that path. */
    assert(run("bin/solas 2>/dev/null", out, sizeof out) == 64);
    assert(out[0] == '\0');
    printf("  a mistake goes to stderr and leaves with 64\n");
}

/* The rule that makes the flags workable at all: everything after the file
   belongs to the program. A script that takes its own --help must receive it,
   which is why these options are only read before the file. */
static void test_the_program_keeps_its_own_arguments(void)
{
    system("mkdir -p " DIR);
    FILE *f = fopen(DIR "/args.sol", "w");
    assert(f != NULL);
    fputs("system:arguments:size:print.\n"
          "system:arguments:do({ a | a:display }).\n", f);
    fclose(f);

    assert(system("bin/solas " DIR "/args.sol -o " DIR "/args.sob") == 0);

    char out[4096];
    assert(run("bin/solvm " DIR "/args.sob --help --dump -h --version 2>/dev/null",
               out, sizeof out) == 0);
    assert(strstr(out, "#4") != NULL);          /* all four reached the program */
    assert(strstr(out, ".sob format") == NULL); /* and solvm printed no banner */
    assert(strstr(out, "--help") != NULL);
    assert(strstr(out, "usage:") == NULL);      /* and solvm said nothing */

    assert(run("bin/solis " DIR "/args.sol --help extra 2>/dev/null",
               out, sizeof out) == 0);
    assert(strstr(out, "#2") != NULL);
    assert(strstr(out, "usage:") == NULL);
    printf("  options after the file belong to the program\n");
}

/* `--trace` writes the call tree to stderr, so a program's own output is
   untouched -- which is the property that lets it be turned on without changing
   what a program does. */
static void test_trace_writes_the_call_tree(void)
{
    char out[65536];

    /* A method sent to an object, so the trace has a receiver and a selector
       worth reading, and a return value to match it. */
    FILE *f = fopen(DIR "/traced.sol", "w");
    assert(f != NULL);
    fputs("point := object:new.\n"
          "point:double := { self:x:mul(#2) }.\n"
          "p := point:new.\n"
          "p:x := #21.\n"
          "p:double:print.\n", f);
    fclose(f);
    assert(system("bin/solas " DIR "/traced.sol -o " DIR "/traced.sob") == 0);

    /* stdout alone: the program's answer, and nothing else. */
    assert(run("bin/solvm --trace " DIR "/traced.sob 2>/dev/null", out, sizeof out) == 0);
    assert(strstr(out, "#42") != NULL);
    assert(strstr(out, "[line") == NULL);        /* the trace stayed on stderr */

    /* stderr alone: the call, by the name it was sent as, and the return. */
    assert(run("bin/solvm --trace " DIR "/traced.sob 2>&1 >/dev/null",
               out, sizeof out) == 0);
    assert(strstr(out, ":double") != NULL);
    assert(strstr(out, "-> #42") != NULL);
    /* Where the call is written -- the file as well as the line, since a chunk
       holds code from every file an include reached. */
    assert(strstr(out, "traced.sol:5]") != NULL);

    /* And with it off, stderr is empty. */
    assert(run("bin/solvm " DIR "/traced.sob 2>&1 >/dev/null", out, sizeof out) == 0);
    assert(out[0] == '\0');
    printf("  --trace writes the call tree to stderr and leaves stdout alone\n");
}

/* The trace names arguments, which is what the chunk's slot names are for --
   and is how the table gets checked: if the names line up with the values, the
   right name is against the right slot. */
static void test_trace_names_arguments(void)
{
    char out[65536];

    FILE *f = fopen(DIR "/named.sol", "w");
    assert(f != NULL);
    fputs("account := object:new.\n"
          "account:balance := #100.\n"
          "account:withdraw := { amount | self:balance:sub(amount) }.\n"
          "a := account:new.\n"
          "a:withdraw(#30):print.\n", f);
    fclose(f);
    assert(system("bin/solas " DIR "/named.sol -o " DIR "/named.sob") == 0);

    assert(run("bin/solvm --trace " DIR "/named.sob 2>&1 >/dev/null",
               out, sizeof out) == 0);
    assert(strstr(out, "amount: #30") != NULL);
    printf("  --trace names its arguments\n");
}

/* Inlined control flow costs no trace at all, which is what makes this readable
   on a real program: a loop that runs three hundred thousand times compiles to
   jumps, and jumps are not calls. */
static void test_trace_is_quiet_where_there_are_no_calls(void)
{
    char out[65536];

    FILE *f = fopen(DIR "/looped.sol", "w");
    assert(f != NULL);
    fputs("i := #0.\n"
          "{ i:lessThan(#100000) }:whileTrue({ i := i:inc }).\n"
          "i:print.\n", f);
    fclose(f);
    assert(system("bin/solas " DIR "/looped.sol -o " DIR "/looped.sob") == 0);

    assert(run("bin/solvm --trace " DIR "/looped.sob 2>&1 >/dev/null",
               out, sizeof out) == 0);
    assert(out[0] == '\0');                      /* a hundred thousand turns, no lines */
    printf("  an inlined loop leaves no trace, however many turns it takes\n");
}

/* A depth follows the outermost calls only, which is where a program's shape
   is. The refusals are checked too, since a depth that is not one is a mistake
   in the command line rather than something to guess at. */
static void test_trace_takes_a_depth(void)
{
    char shallow[65536], deep[65536];

    FILE *f = fopen(DIR "/nested.sol", "w");
    assert(f != NULL);
    fputs("inner := { #1 }.\n"
          "middle := { inner:value }.\n"
          "outer := { middle:value }.\n"
          "outer:value:print.\n", f);
    fclose(f);
    assert(system("bin/solas " DIR "/nested.sol -o " DIR "/nested.sob") == 0);

    assert(run("bin/solvm --trace=1 " DIR "/nested.sob 2>&1 >/dev/null",
               shallow, sizeof shallow) == 0);
    assert(run("bin/solvm --trace " DIR "/nested.sob 2>&1 >/dev/null",
               deep, sizeof deep) == 0);
    assert(strlen(shallow) < strlen(deep));
    assert(strstr(shallow, "nested.sol:4]") != NULL);   /* the outermost call */
    assert(strstr(shallow, "nested.sol:3]") == NULL);   /* and not the one inside */
    assert(strstr(deep, "nested.sol:3]") != NULL);

    static const char *refused[] = {
        "bin/solvm --trace=0 " DIR "/nested.sob 2>&1 >/dev/null",
        "bin/solvm --trace=x " DIR "/nested.sob 2>&1 >/dev/null",
        "bin/solvm --trace=99 " DIR "/nested.sob 2>&1 >/dev/null",
        "bin/solvm --trace= " DIR "/nested.sob 2>&1 >/dev/null",
    };
    for (size_t i = 0; i < sizeof refused / sizeof refused[0]; i++) {
        char out[4096];
        assert(run(refused[i], out, sizeof out) == 64);
        assert(strstr(out, "depth from 1 to 64") != NULL);
    }
    printf("  --trace=N follows the outermost calls, and a bad depth is refused\n");
}

/* `--interactive` runs the file and then stays at the prompt with what it left
   behind. After a failure that is most of what a debugger would offer here: a
   script's own names are globals, so they survive the unwind -- only a block's
   temporaries are lost with the frames. */
static void test_interactive_keeps_what_the_program_left(void)
{
    FILE *f = fopen(DIR "/failing.sol", "w");
    assert(f != NULL);
    fputs("tally := array:new.\n"
          "[#1,#4]:loop({ n | tally:add(n:mul(n)) }).\n"
          "host := \"localhost\".\n"
          "tally:at(#99).\n"                    /* out of bounds: it stops here */
          "never := #1.\n", f);
    fclose(f);

    char out[8192];

    /* Without the flag it fails and leaves, which is what a runner should do. */
    assert(run("bin/solis " DIR "/failing.sol 2>/dev/null", out, sizeof out) == 70);
    assert(strstr(out, "solis") == NULL);       /* no banner: no prompt */

    /* With it, the prompt is there and so are the program's names. */
    assert(run("printf 'tally:print.\\nhost:display.\\n"
               "{ never:print }:onError({ e | \"unset\":display }).\\n' | "
               "bin/solis --interactive " DIR "/failing.sol 2>/dev/null",
               out, sizeof out) == 0);
    assert(strstr(out, "program failed") != NULL);
    assert(strstr(out, "[#1, #4, #9, #16]") != NULL);   /* built before the fall */
    assert(strstr(out, "localhost") != NULL);
    /* And what the program never reached is unbound -- reading it is an error
       here rather than nil, so the prompt shows the line was never run. */
    assert(strstr(out, "unset") != NULL);
    printf("  --interactive keeps the program's names after it fails\n");
}

/* It stays after a program that finishes too, which is the other half of being
   able to look at what a program did. */
static void test_interactive_stays_after_success(void)
{
    FILE *f = fopen(DIR "/finishing.sol", "w");
    assert(f != NULL);
    fputs("answer := #6:mul(#7).\n", f);
    fclose(f);

    char out[8192];
    assert(run("printf 'answer:print.\\n' | bin/solis --interactive "
               DIR "/finishing.sol 2>/dev/null", out, sizeof out) == 0);
    assert(strstr(out, "program finished") != NULL);
    assert(strstr(out, "#42") != NULL);
    printf("  --interactive stays after a program that finishes\n");
}

/* And a method the program defined can be called from the prompt, which is the
   half-stepper part: the failing call can be made again, and looked at. */
static void test_interactive_can_call_what_the_program_defined(void)
{
    FILE *f = fopen(DIR "/account.sol", "w");
    assert(f != NULL);
    fputs("account := object:new.\n"
          "account:balance := #100.\n"
          "account:withdraw := { amount |\n"
          "    amount:greaterThan(self:balance):ifTrue({ error:raise(\"not enough\") }).\n"
          "    self:balance := self:balance:sub(amount) }.\n"
          "a := account:new.\n"
          "a:withdraw(#30).\n"
          "a:withdraw(#500).\n", f);
    fclose(f);

    char out[8192];
    assert(run("printf 'a:balance:print.\\na:withdraw(#20).\\na:balance:print.\\n' | "
               "bin/solis --interactive " DIR "/account.sol 2>/dev/null",
               out, sizeof out) == 0);
    assert(strstr(out, "#70") != NULL);         /* the first withdrawal stuck */
    assert(strstr(out, "#50") != NULL);         /* and another one works now */
    printf("  --interactive can call what the program defined\n");
}

/* The options still do what they did. A help flag that broke -I or --dump on
   the way in would pass every test above. */
static void test_the_other_options_still_work(void)
{
    char out[4096];

    assert(run("bin/solas -I lib " DIR "/args.sol -o " DIR "/args2.sob 2>&1",
               out, sizeof out) == 0);
    assert(run("bin/solvm --dump " DIR "/args.sob 2>/dev/null", out, sizeof out) == 0);
    assert(strstr(out, "GLOBAL") != NULL);      /* the disassembly is there */
    printf("  -I and --dump are unchanged\n");
}

/* A program that will not stop, stopped. 124 rather than 70, because it did
   not fail: it was taken away, and a host that read that as a bug would go
   looking for one that is not there. */
static void test_a_step_limit_stops_a_program(void)
{
    char out[16384];

    /* Written literally, so it compiles to jumps and enters no frames -- the
       shape nothing watching calls could ever have caught. */
    FILE *f = fopen(DIR "/endless.sol", "w");
    assert(f != NULL);
    fputs("started := true.\n"
          "{ true }:whileTrue({ nil }).\n"
          "\"never\":display.\n", f);
    fclose(f);
    assert(system("bin/solas " DIR "/endless.sol -o " DIR "/endless.sob") == 0);

    assert(run("bin/solvm --steps=50000 " DIR "/endless.sob 2>&1 >/dev/null",
               out, sizeof out) == 124);
    assert(strstr(out, "step limit") != NULL);
    assert(strstr(out, "endless.sol") != NULL);   /* and where it had got to */

    /* Nothing after the loop ran. */
    assert(run("bin/solvm --steps=50000 " DIR "/endless.sob 2>/dev/null",
               out, sizeof out) == 124);
    assert(strstr(out, "never") == NULL);

    /* Without a limit it is the same program, and would not come back -- so
       that half is not tested here, which is the point of the flag. */
    printf("  --steps stops a loop that enters no frames, with 124\n");
}

/* Holding is what is measured, not allocating. The two programs below do the
   same amount of work under the same ceiling and only one of them is holding
   it when the collector looks. */
static void test_a_memory_limit_measures_what_is_held(void)
{
    char out[16384];

    FILE *f = fopen(DIR "/hoard.sol", "w");
    assert(f != NULL);
    fputs("held := array:new.\n"
          "{ true }:whileTrue({ held:add(\"kept forever\") }).\n", f);
    fclose(f);
    assert(system("bin/solas " DIR "/hoard.sol -o " DIR "/hoard.sob") == 0);

    assert(run("bin/solvm --memory=1M " DIR "/hoard.sob 2>&1 >/dev/null",
               out, sizeof out) == 124);
    assert(strstr(out, "memory limit") != NULL);

    f = fopen(DIR "/churn.sol", "w");
    assert(f != NULL);
    fputs("i := #0.\n"
          "{ i:lessThan(#20000) }:whileTrue({\n"
          "    scratch := \"made and dropped\":concat(i:asString).\n"
          "    i := i:inc }).\n"
          "\"finished\":display.\n", f);
    fclose(f);
    assert(system("bin/solas " DIR "/churn.sol -o " DIR "/churn.sob") == 0);

    assert(run("bin/solvm --memory=1M " DIR "/churn.sob 2>/dev/null",
               out, sizeof out) == 0);
    assert(strstr(out, "finished") != NULL);

    printf("  --memory stops what is held, not what has been through\n");
}

/* Both limits are off unless asked for, and both refuse a value that is not a
   count. */
static void test_the_limits_are_off_and_are_checked(void)
{
    char out[4096];

    FILE *f = fopen(DIR "/quick.sol", "w");
    assert(f != NULL);
    fputs("n := #0. [#1,#2000]:loop({ i | n := n:inc }). n:print.\n", f);
    fclose(f);
    assert(system("bin/solas " DIR "/quick.sol -o " DIR "/quick.sob") == 0);

    /* No flag, and the same program that a small budget would have stopped. */
    assert(run("bin/solvm " DIR "/quick.sob 2>/dev/null", out, sizeof out) == 0);
    assert(strstr(out, "#2000") != NULL);
    assert(run("bin/solvm --steps=200 " DIR "/quick.sob 2>/dev/null",
               out, sizeof out) == 124);

    static const char *bad[] = {
        "bin/solvm --steps=0 " DIR "/quick.sob 2>&1 >/dev/null",
        "bin/solvm --steps=lots " DIR "/quick.sob 2>&1 >/dev/null",
        "bin/solvm --memory=0 " DIR "/quick.sob 2>&1 >/dev/null",
        "bin/solvm --memory=64X " DIR "/quick.sob 2>&1 >/dev/null",
    };
    for (size_t i = 0; i < sizeof bad / sizeof bad[0]; i++) {
        assert(run(bad[i], out, sizeof out) == 64);
        assert(strstr(out, "wants") != NULL);
    }

    /* A suffix is a suffix, and the program still runs under a real one. */
    assert(run("bin/solvm --memory=64M " DIR "/quick.sob 2>/dev/null",
               out, sizeof out) == 0);
    assert(strstr(out, "#2000") != NULL);

    printf("  the limits are off by default and refuse a nonsense value\n");
}

/* Everything this repository writes down about what it prints.
 *
 * Two notations, one job. `examples/` carries about four hundred claims in
 * comments -- `#2:add(#3):print.  ; #5` -- and the documents carry two hundred
 * more inside ``` fences, in the same notation. Nothing checked either until
 * programs/expect.sol existed: the rest of this suite compiles every example
 * and never ran one, so those comments were true because somebody looked, once.
 *
 * Checking them found two things wrong: the guide showed a stack trace in a
 * format that predates 6.27 adding the filename, and class-and-instance.md said
 * `integer` has 24 slots where it has 38.
 *
 * A block that will not run is a failure, and the escape is a word after the
 * fence: a `text` tag for a session or a sketch, `sh` for a shell transcript.
 * That
 * used to be a count instead, and the count hid 54 claims in 42 blocks --
 * including the guide's `point:slots` answering slots that page never defined,
 * the reference using an `integer:poly` that appears nowhere else in it, and
 * class-and-instance.md's `#45:new(#1):print. ; #1`, which the language stopped
 * doing at some point without the document noticing.
 *
 * CHANGELOG.md is the one document skipped: it records what was true at each
 * release, so its snippets describe past states on purpose. */
static void test_everything_written_down_is_true(void)
{
    char out[64 * 1024];

    assert(run("bin/solas programs/expect.sol -o " DIR "/expect.sob 2>&1",
               out, sizeof out) == 0);

    int status = run("bin/solvm " DIR "/expect.sob"
                     " examples docs README.md index.md 2>/dev/null",
                     out, sizeof out);
    if (status != 0 || strstr(out, "every claim holds") == NULL) {
        printf("\n%s\n", out);
        assert(false);
    }

    /* And the count, so that a checker which quietly stopped finding anything
       to check fails too. It was 589 across 40 files when this went in and 729
       across 41 once blocks began to be read on the page they were written
       under; the floor is there to catch a collapse, not to be updated for
       every example that gains a line. */
    int claims = 0;
    const char *at = strstr(out, "claims checked");
    assert(at != NULL);
    while (at > out && *at != ',') at--;
    assert(sscanf(at, ", %d claims checked", &claims) == 1);
    assert(claims >= 700);

    /* And the counts the prose states about this repository, which are neither
       a comment on a printing line nor a fenced block, and so went stale in
       three documents at once for three releases. A marker in the sentence says
       what the number counts and the checker recounts it -- so a floor here
       catches the other direction, a run that quietly stops finding any. */
    int counts = 0;
    at = strstr(out, "counts stated in prose");
    assert(at != NULL);
    while (at > out && at[-1] != '\n') at--;
    assert(sscanf(at, "%d counts stated in prose", &counts) == 1);
    assert(counts >= 15);

    int placed = 0;
    at = strstr(out, "programs say where they come in the order");
    assert(at != NULL);
    while (at > out && at[-1] != '\n') at--;
    assert(sscanf(at, "%d programs say where they come", &placed) == 1);
    assert(placed >= 8);

    printf("  everything written down is true (%d claims, %d counts, %d "
           "positions)\n", claims, counts, placed);
}

/* The BASIC interpreter, held to the standard it says it implements.
 *
 * programs/basic.sol carries its listings inline with their output in comments,
 * the way every program here does -- and nothing checks a comment in
 * programs/, because expect.sol's subjects are the examples and the documents.
 * So these lines were true because somebody looked, once, which is exactly the
 * shape 0.31.0 went back and fixed for two libraries.
 *
 * What is asserted is not the whole transcript but the handful of lines that
 * encode a rule from ECMA-55 rather than a choice made here. A golden file
 * would churn on every stage that adds a listing; these do not, because the
 * standard does not.
 *
 * Stage five replaces this with the same comparison over `.bas` files in
 * programs/basic/, which is when a whole recorded transcript starts being worth
 * keeping. */
static void test_basic_runs_the_way_the_standard_says(void)
{
    char out[64 * 1024];

    assert(run("bin/solas programs/basic.sol -o " DIR "/basic.sob 2>&1",
               out, sizeof out) == 0);
    assert(run("bin/solvm " DIR "/basic.sob 2>/dev/null",
               out, sizeof out) == 0);

    /* A number is a sign character -- a space when it is not negative -- then
       the digits, then a trailing space. Every one of these would still read
       correctly to a person with the spaces wrong, which is why they are here
       and not left to the eye. */
    assert(strstr(out, "\n 14 \n") != NULL);
    assert(strstr(out, "\n 2.5 \n") != NULL);
    assert(strstr(out, "\n-7 \n") != NULL);

    /* A comma moves to the next print zone; a semicolon moves nowhere. */
    assert(strstr(out, "\nA              B              C\n") != NULL);
    assert(strstr(out, "\n 1  2  3 \n") != NULL);
    assert(strstr(out, "\nCOUNT:  99 \n") != NULL);

    /* Lines run in the order of their numbers, not the order they were typed. */
    assert(strstr(out, "\nFIRST\nSECOND\nTHIRD\n") != NULL);

    /* A sign belongs at the front of an expression and nowhere inside one, so
       `2 * -3` is not a BASIC expression -- a rule every dialect since 1978
       relaxed, which makes it the one most likely to be "fixed" by accident. */
    assert(strstr(out, "line 10: '-' cannot start a value") != NULL);

    /* `^` and the six functions that waited on ROADMAP 3.14. This used to assert
       that they refused; the entry was decided and they are arithmetic now.
       2^0.5 is here because it is the case repeated multiplication cannot do
       and the reason the operator was never stubbed, and ATN(1)*4 because it is
       the shortest program that would notice if an angle were wrong. */
    assert(strstr(out, "\n 8  1.4142135623730951 \n") != NULL);
    assert(strstr(out, "\n 0  1  0 \n") != NULL);
    assert(strstr(out, "\n 3.141592653589793 \n") != NULL);

    /* Equal precedence groups left, so 2^3^2 is 64 here and 512 in almost every
       BASIC since. The one rule of the dialect that no other assertion covers,
       because it needed an operator that did not work until today. */
    assert(strstr(out, "\n 64 \n") != NULL);

    /* Control flow, by way of two programs a BASIC book opens with. Fibonacci
       is the loop, the accumulator and the counted range in one line each; the
       times table is the same nesting seen through print zones. Either one
       going wrong says the jumps are wrong, which no assertion about a single
       statement would catch. */
    assert(strstr(out, "\n 1  1  2  3  5  8  13  21  34  55  89  144 \n") != NULL);
    assert(strstr(out, "\n 4              8              12             16") != NULL);
    assert(strstr(out, "\nSUM 1..100 IS 5050 \n") != NULL);

    /* A counted loop reads its limit and step once and counts down when told
       to, and a range that is already empty runs its body no times -- which
       shows up as the absence of anything between these two lines. */
    assert(strstr(out, "\n 1  2  3  4  5 \n 10  7  4  1 \n") != NULL);

    /* Two rules of the dialect that every later BASIC relaxed, and so the two
       most likely to be "fixed" by somebody who knows a later one: THEN takes
       a line number rather than a statement, and text compares with = and <>
       only. */
    assert(strstr(out, "THEN takes a line number in this dialect") != NULL);
    assert(strstr(out, "'<' compares numbers, not strings") != NULL);

    /* FOR and NEXT are paired at load, so crossed loops are a listing error
       and not a surprise thirty seconds into a run. */
    assert(strstr(out, "line 20: NEXT J closes FOR I") != NULL);
    assert(strstr(out, "line 10: there is no line 999") != NULL);

    /* Arrays start at nought and an array nobody declared has a bound of ten,
       both of which are the standard and neither of which is guessable. */
    assert(strstr(out, "\n 0  1  4  9  16  25 \n") != NULL);
    assert(strstr(out, "\n 3  0 \n") != NULL);

    /* INT floors rather than truncating, so INT(-2.5) is -3 and not -2. */
    assert(strstr(out, "\n 3 -3 -1  4 \n") != NULL);

    /* RND repeats until RANDOMIZE says otherwise, so the same three numbers
       come out twice. Written as one search for both lines, which is the
       claim: not that they are those numbers, but that they are the same. */
    assert(strstr(out, "\n 18  31  12 \n 18  31  12 \n") != NULL);

    /* A DATA word with no quotes round it is text, which catches everybody. */
    assert(strstr(out, "\n 1  2 THREE\n") != NULL);

    printf("  BASIC runs a program the way ECMA-55 says, arithmetic included\n");
}

/* And a listing of its own, from a file, which is the only way INPUT can be
 * tested: it reads standard input, so a listing using it cannot be one of the
 * demonstrations that run on every build.
 *
 * The sieve is here because it is the shortest program that would fail if
 * anything about arrays, nested loops or jumps were wrong, and it says so in
 * one line of output that is checked against the primes rather than against
 * what this interpreter happened to print. */
static void test_basic_runs_a_listing_from_a_file(void)
{
    char out[8192];

    assert(run("bin/solvm " DIR "/basic.sob programs/basic/sieve.bas 2>&1",
               out, sizeof out) == 0);
    assert(strcmp(out, " 2  3  5  7  11  13  17  19  23  29  31  37  41  43  47 \n")
           == 0);

    /* INPUT, with the answers piped in. The prompt sits beside the answer now:
       whatever the PRINT on the line before left open goes out without a
       newline, then the `?`, then what was typed. It read "?\n" on a line of
       its own until ROADMAP 3.18 was closed with system:write. Nothing echoes
       a piped answer, so what follows the `?` here is the next PRINT. */
    assert(run("printf '3, 4\\nHans\\n' | bin/solvm " DIR "/basic.sob"
               " programs/basic/adder.bas 2>&1", out, sizeof out) == 0);
    assert(strstr(out, "TWO NUMBERS, SEPARATED BY A COMMA? SUM IS 7 \n") != NULL);
    assert(strstr(out, "AND YOUR NAME? THANK YOU, Hans\n") != NULL);
    assert(strstr(out, "PRODUCT IS 12 \n") != NULL);
    assert(strstr(out, "THANK YOU, Hans\n") != NULL);

    /* A file that is not there is a message and a status, not a stack trace. */
    assert(run("bin/solvm " DIR "/basic.sob no-such-file.bas 2>&1",
               out, sizeof out) == 1);
    assert(strstr(out, "there is no file no-such-file.bas") != NULL);

    printf("  BASIC runs a .bas file, INPUT included\n");
}

int main(void)
{
    test_help_is_not_an_error();
    test_version_names_the_format();
    test_a_mistake_goes_to_stderr();
    test_the_program_keeps_its_own_arguments();
    test_trace_writes_the_call_tree();
    test_trace_names_arguments();
    test_trace_is_quiet_where_there_are_no_calls();
    test_trace_takes_a_depth();
    test_interactive_keeps_what_the_program_left();
    test_interactive_stays_after_success();
    test_interactive_can_call_what_the_program_defined();
    test_the_other_options_still_work();
    test_a_step_limit_stops_a_program();
    test_a_memory_limit_measures_what_is_held();
    test_the_limits_are_off_and_are_checked();
    test_everything_written_down_is_true();
    test_basic_runs_the_way_the_standard_says();
    test_basic_runs_a_listing_from_a_file();
    printf("test_cli: ok\n");
    return 0;
}
