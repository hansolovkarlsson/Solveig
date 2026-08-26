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
/* Reads a whole file, for comparing a program's output against a recorded one. */
static char *slurp_file(const char *path)
{
    FILE *f = fopen(path, "rb");
    assert(f != NULL);
    assert(fseek(f, 0, SEEK_END) == 0);
    long size = ftell(f);
    assert(size >= 0);
    rewind(f);

    char *text = malloc((size_t)size + 1);
    assert(text != NULL);
    assert(fread(text, 1, (size_t)size, f) == (size_t)size);
    text[size] = '\0';
    fclose(f);
    return text;
}

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
    assert(strstr(out, "\n 8  1.41421 \n") != NULL);
    assert(strstr(out, "\n 0  1  0 \n") != NULL);
    assert(strstr(out, "\n 3.14159 \n") != NULL);

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

    /* Six significant digits and no nought before the point, which is what
       BASIC shows and what Solum does not: 1/3 is 0.3333333333333333 here and
       .333333 there. A million in scaled form looks like a defect and is the
       standard -- seven digits to the left is more than six can describe. */
    assert(strstr(out, "\n .333333  .666667 \n") != NULL);
    assert(strstr(out, "\n 1E+06  1.23457E+08 \n") != NULL);

    /* TAB puts the next thing in a column, and does nothing when the column has
       already gone by. */
    assert(strstr(out, "\n         X         Y\n") != NULL);
    assert(strstr(out, "\nAB  C\n") != NULL);

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

    /* Every listing in programs/basic/ that needs no input, against a recorded
       transcript, byte for byte.
     *
     * This is what the claims in comments cannot be. programs/ is not one of
     * expect.sol's subjects, so a comment there is true because somebody looked
     * -- and the output of a BASIC program is exactly where that fails: print
     * zones, six significant digits and a trailing space after every number are
     * all invisible to a reader and all load-bearing.
     *
     * wave.bas is here for a second reason. ROADMAP 3.14 said it was waiting
     * for "a plotter, a simulation, anything with coordinates or a waveform",
     * and for two days this interpreter could not run one. */
    static const char *listings[] = { "sieve", "wave", "temperature", "stats" };
    for (size_t i = 0; i < sizeof listings / sizeof listings[0]; i++) {
        char command[512], expected_path[512];
        snprintf(command, sizeof command,
                 "bin/solvm " DIR "/basic.sob programs/basic/%s.bas 2>&1",
                 listings[i]);
        snprintf(expected_path, sizeof expected_path,
                 "programs/basic/%s.out", listings[i]);

        assert(run(command, out, sizeof out) == 0);

        char *expected = slurp_file(expected_path);
        if (strcmp(out, expected) != 0) {
            printf("\n%s.bas printed\n%s\nand %s.out records\n%s\n",
                   listings[i], out, listings[i], expected);
            assert(false);
        }
        free(expected);
    }
    printf("  %zu recorded transcripts still match\n",
           sizeof listings / sizeof listings[0]);

    /* A file that is not there is a message and a status, not a stack trace --
       and the message is on stderr, so stdout stays empty. */
    assert(run("bin/solvm " DIR "/basic.sob no-such-file.bas 2>/dev/null",
               out, sizeof out) == 1);
    assert(strcmp(out, "") == 0);
    assert(run("bin/solvm " DIR "/basic.sob no-such-file.bas 2>&1 >/dev/null",
               out, sizeof out) == 1);
    assert(strstr(out, "there is no file no-such-file.bas") != NULL);

    /* **A listing that failed leaves non-zero**, which it did not until it was
     * asked for directly: the error was reported and the status was 0, so
     * `solvm basic.sob x.bas && ...` ran the next thing after a program that
     * never worked. One case fails at load and one part-way through, because
     * the two leave by different paths.
     *
     * The second also checks that output a PRINT left pending is written before
     * the error. PRINT builds a line and ends it, so a listing that fails
     * halfway through one has already produced text -- the cost of buffering,
     * invisible until the moment it is not. */
    assert(run("printf '10 GOTO 999\\n' > " DIR "/broken.bas", out, sizeof out) == 0);
    assert(run("bin/solvm " DIR "/basic.sob " DIR "/broken.bas 2>/dev/null",
               out, sizeof out) == 1);
    assert(strcmp(out, "") == 0);
    assert(run("bin/solvm " DIR "/basic.sob " DIR "/broken.bas 2>&1 >/dev/null",
               out, sizeof out) == 1);
    assert(strcmp(out, "line 10: there is no line 999\n") == 0);

    /* **The two streams carry different things**, which is ROADMAP 3.19 and the
     * reason this is asserted twice rather than once with 2>&1. The listing
     * prints `A` and then fails: `A` is the program's output and belongs in a
     * redirect, and the complaint is not and does not. Merging them would also
     * put them in the wrong order -- stdout is block-buffered down a pipe and
     * stderr is not -- which is how this assertion was written the first time
     * and why it failed the moment the streams were separated. */
    assert(run("printf '10 PRINT \"A\";\\n20 PRINT 1/0\\n' > " DIR "/half.bas",
               out, sizeof out) == 0);
    assert(run("bin/solvm " DIR "/basic.sob " DIR "/half.bas 2>/dev/null",
               out, sizeof out) == 1);
    assert(strcmp(out, "A\n") == 0);
    assert(run("bin/solvm " DIR "/basic.sob " DIR "/half.bas 2>&1 >/dev/null",
               out, sizeof out) == 1);
    assert(strcmp(out, "line 20: division by zero\n") == 0);

    printf("  BASIC runs a .bas file, INPUT included\n");
}

/* The prompt, driven by a recorded session and compared against a recorded
 * transcript.
 *
 * A REPL is exactly the thing that cannot be checked by a claim in a comment:
 * what it does is a *conversation*, and the interesting part is what it
 * remembers between one line and the next. programs/basic/session.in types a
 * program out of order, lists it, runs it, reads a variable the run left
 * behind, inserts a line, deletes it, saves, clears, loads back, runs again,
 * and then makes four different mistakes to check the prompt survives each.
 *
 * The SAVE in it writes into build/, which exists because this suite has just
 * built. That is deliberate: a round trip through a file is the only way to
 * check that what LIST shows and what SAVE writes are the same text. */
static void test_basic_has_a_prompt(void)
{
    char out[64 * 1024];

    assert(run("bin/solvm " DIR "/basic.sob --repl < programs/basic/session.in"
               " 2>&1", out, sizeof out) == 0);

    char *expected = slurp_file("programs/basic/session.out");
    if (strcmp(out, expected) != 0) {
        printf("\nthe session printed\n%s\nand session.out records\n%s\n",
               out, expected);
        assert(false);
    }
    free(expected);

    /* And what SAVE wrote is what LIST showed, byte for byte -- which is the
       claim that nothing is regenerated from the parsed form on the way out. */
    char *saved = slurp_file("build/basic-session.bas");
    assert(strcmp(saved,
                  "10 PRINT \"SQUARES\"\n"
                  "20 FOR I = 1 TO 4\n"
                  "30 PRINT I; I * I\n"
                  "40 NEXT I\n") == 0);
    free(saved);

    printf("  BASIC has a prompt, and it remembers between lines\n");
}

/* The editor, driven by a recorded stream of keys and compared against the
 * bytes it drew.
 *
 * A full-screen program is the other thing a claim in a comment cannot check:
 * what it does is a *picture*, and the interesting part is which escape
 * sequence went where. programs/edit/session.in moves by word, deletes a
 * character, appends to a line, opens a new one, goes to the top, deletes a
 * line, goes to the bottom, runs off the end of a line long enough to scroll
 * the screen sideways, searches for a pattern and wraps round to find it,
 * deletes a character of it, searches again and is told there is no second
 * one, substitutes across the whole file, deletes a word with `dw`, yanks a
 * line and puts it at the end, marks that line and comes back to it with `'a`,
 * deletes a character there and repeats that with `.`, deletes the line and
 * undoes that, redoes it and undoes it again, writes and quits
 * -- and programs/edit/session.out is every byte that reached the terminal
 * while it did.
 *
 * The sideways scroll is in there because leaving it out cost a crash: a line
 * that ends before the scrolled screen begins asks `copyFrom` for a start past
 * the end of a string, which is an error rather than an empty answer, and the
 * first session recorded had no long line in it to find that.
 *
 * It is deterministic for one reason: standard output is a pipe here, so
 * `system:terminalSize` answers nil and the editor falls back to the 24 by 80
 * it names in its own file. On a terminal this transcript would be a different
 * size and would still be right, which is why the fallback is the program's
 * decision and not the language's.
 *
 * The file it edits is copied into build/ first, because a test that edits a
 * tracked file passes once. */
/* ------------------------------------------------------------------------
 * sola: a compiler rather than an interpreter
 *
 * programs/sola.sol turns SolaBasic into a .sob, and what is checked here is
 * the file it writes rather than the compiler -- each listing is compiled,
 * then run by solvm with nothing of the compiler present, and its output
 * compared against a recorded transcript byte for byte.
 *
 * That is docs/SOLABASIC.md's second mechanism for deciding done, and it is
 * the one that can be had today: there is no standard for this dialect and no
 * conformance suite, so a transcript is what holds a feature true.
 *
 * The listings are chosen for the jumps they make, not the answers they get.
 * spaghetti.bas in particular nests nothing -- two loops woven from GOTO
 * alone, with jumps that cross -- because the claim being tested is that an
 * arbitrary jump between statements verifies, and a structured program would
 * not test it.
 */
static void test_sola_compiles_a_program_that_runs(void)
{
    char out[8192];

    assert(run("bin/solas programs/sola.sol -o " DIR "/sola.sob 2>&1",
               out, sizeof out) == 0);

    static const char *listings[] = { "counter", "spaghetti", "labels",
                                      "structure", "escape", "procedures",
                                      "byref", "types", "functions", "print" };
    for (size_t i = 0; i < sizeof listings / sizeof listings[0]; i++) {
        char command[512], expected_path[512];

        snprintf(command, sizeof command,
                 "bin/solvm " DIR "/sola.sob programs/sola/%s.bas "
                 DIR "/%s.sob >/dev/null 2>&1", listings[i], listings[i]);
        assert(run(command, out, sizeof out) == 0);

        snprintf(command, sizeof command,
                 "bin/solvm " DIR "/%s.sob 2>&1", listings[i]);
        assert(run(command, out, sizeof out) == 0);

        snprintf(expected_path, sizeof expected_path,
                 "programs/sola/%s.out", listings[i]);
        char *expected = slurp_file(expected_path);
        if (strcmp(out, expected) != 0) {
            printf("\n%s.bas printed\n%s\nand %s.out records\n%s\n",
                   listings[i], out, listings[i], expected);
            assert(false);
        }
        free(expected);
    }

    /* A jump to a label that is not there is refused before anything runs,
       which is the same rule basic.sol keeps for a GOTO to a missing line: a
       program that prints half its output and then discovers it cannot go
       where it was told has already done that half wrongly. */
    system("printf 'PRINT \"before\"\\nGOTO Nowhere\\n' > " DIR "/missing.bas");
    assert(run("bin/solvm " DIR "/sola.sob " DIR "/missing.bas "
               DIR "/missing.sob 2>&1", out, sizeof out) != 0);
    assert(strstr(out, "there is no label 'NOWHERE' to jump to") != NULL);
    assert(strstr(out, "before") == NULL);

    /* And a label written twice is a mistake rather than a silent choice of
       one of them. The line it names is the line the label is on. */
    system("printf 'Top:\\nPRINT \"one\"\\nTop:\\nPRINT \"two\"\\n' > "
           DIR "/twice.bas");
    assert(run("bin/solvm " DIR "/sola.sob " DIR "/twice.bas "
               DIR "/twice.sob 2>&1", out, sizeof out) != 0);
    assert(strstr(out, "line 3: the label 'TOP' is used twice") != NULL);

    /* A block left open is reported where it was *opened*, which is the line
       somebody has to go and look at -- the end of the file is where you
       already know something is wrong. */
    system("printf 'FOR i = 1 TO 3\\nPRINT i\\n' > " DIR "/open.bas");
    assert(run("bin/solvm " DIR "/sola.sob " DIR "/open.bas " DIR "/open.sob 2>&1",
               out, sizeof out) != 0);
    assert(strstr(out, "line 1: this FOR is never closed by its NEXT") != NULL);

    /* And a closing line that closes the wrong thing says which thing, and
       where it was opened. This is what the stack of open blocks buys that a
       parser building a tree would have had to refuse without explaining. */
    system("printf 'DO\\nNEXT i\\n' > " DIR "/cross.bas");
    assert(run("bin/solvm " DIR "/sola.sob " DIR "/cross.bas " DIR "/cross.sob 2>&1",
               out, sizeof out) != 0);
    assert(strstr(out, "NEXT closes the DO opened on line 1") != NULL);

    /* EXIT FOR looks for the innermost FOR rather than the innermost block,
       so being inside only a DO is a mistake it can name. */
    system("printf 'DO\\nEXIT FOR\\nLOOP\\n' > " DIR "/exit.bas");
    assert(run("bin/solvm " DIR "/sola.sob " DIR "/exit.bas " DIR "/exit.sob 2>&1",
               out, sizeof out) != 0);
    assert(strstr(out, "EXIT FOR with no FOR loop around it") != NULL);

    /* A call to something that is not there, and a call with the wrong number
       of arguments, are both compile-time. Nothing about either has to wait
       for the program to reach that line. */
    system("printf 'CALL Nope(1)\\n' > " DIR "/nope.bas");
    assert(run("bin/solvm " DIR "/sola.sob " DIR "/nope.bas " DIR "/nope.sob 2>&1",
               out, sizeof out) != 0);
    assert(strstr(out, "there is no SUB or FUNCTION called 'NOPE'") != NULL);

    system("printf 'SUB S (a)\\nEND SUB\\nCALL S(1, 2)\\n' > " DIR "/arity.bas");
    assert(run("bin/solvm " DIR "/sola.sob " DIR "/arity.bas " DIR "/arity.sob 2>&1",
               out, sizeof out) != 0);
    assert(strstr(out, "S takes 1 argument and was given 2") != NULL);

    /* A procedure is a frame, so SolaBasic recursion is SolVM recursion and
       stops where ROADMAP 3.5 says -- which SOLABASIC.md predicted before any
       of this was written. The trace names the BASIC procedure and the BASIC
       line, not this compiler's. */
    system("printf 'FUNCTION D (n)\\nIF n <= 0 THEN\\nD = 0\\nELSE\\n"
           "D = 1 + D(n - 1)\\nEND IF\\nEND FUNCTION\\nPRINT D(400)\\n' > "
           DIR "/deep.bas");
    assert(run("bin/solvm " DIR "/sola.sob " DIR "/deep.bas " DIR "/deep.sob 2>&1",
               out, sizeof out) == 0);
    assert(run("bin/solvm " DIR "/deep.sob 2>&1", out, sizeof out) != 0);
    assert(strstr(out, "call depth exceeded") != NULL);
    assert(strstr(out, "in D") != NULL);

    printf("  %zu SolaBasic listings compile, run and still match\n",
           sizeof listings / sizeof listings[0]);
}

static void test_the_editor_draws_what_it_recorded(void)
{
    char out[64 * 1024];

    assert(run("bin/solas programs/edit.sol -o " DIR "/edit.sob 2>&1",
               out, sizeof out) == 0);
    assert(run("cp programs/edit/session.txt " DIR "/edit-session.txt",
               out, sizeof out) == 0);

    assert(run("bin/solvm " DIR "/edit.sob " DIR "/edit-session.txt"
               " < programs/edit/session.in 2>&1", out, sizeof out) == 0);

    char *expected = slurp_file("programs/edit/session.out");
    if (strcmp(out, expected) != 0) {
        printf("\nthe editor drew %zu bytes and session.out records %zu\n",
               strlen(out), strlen(expected));
        assert(false);
    }
    free(expected);

    /* And what it wrote is what the keys asked for: a character gone from the
       second line, four added to its end, a line opened after it, the first
       line deleted, a character taken off the line the search found, four
       substitutions across three lines -- the last of them twice on the long
       line, which is what `g` is for -- a word deleted by `dw`, a yanked line
       put back at the end, edited where the mark said it was and edited again
       by `.`, and a line deleted, restored, deleted again and restored again,
       which is why the file ends where it did before any of that. The fourth line is untouched and is there to be
       *drawn* -- it opens with a tab and runs past the eightieth column, so
       the transcript covers both of the things a screen does to a line it
       cannot show as it is. */
    char *edited = slurp_file(DIR "/edit-session.txt");
    assert(strcmp(edited,
                  "THE line END\n"
                  "ew\n"
                  "THE third line\n"
                  "\tan indented line that runs well past THE eightieth column,"
                  " so THE screen has to scroll sideways to show its end\n"
                  "E line END\n") == 0);
    free(edited);

    printf("  the editor draws the screen it recorded, and writes the file\n");
}

/* The editor's behaviour, where the transcript above is its drawing.
 *
 * programs/edit/checks.sol writes a file, feeds the editor a string of keys
 * through a pipe, and compares what was written against what those keys should
 * have done -- a hundred and sixty-five times. It is a Solum program because
 * that is what this repository writes its tools in, and because `readKey`
 * reading a pipe exactly as it reads a terminal is what makes an editor
 * testable at all.
 *
 * The floor is here rather than in that file: a checker that quietly stopped
 * finding anything to check would pass every one of its own assertions. */
static void test_the_editor_does_what_the_keys_say(void)
{
    char out[64 * 1024];

    assert(run("bin/solas programs/edit/checks.sol -o " DIR "/checks.sob 2>&1",
               out, sizeof out) == 0);

    int status = run("bin/solvm " DIR "/checks.sob 2>&1", out, sizeof out);
    if (status != 0 || strstr(out, "every session holds") == NULL) {
        printf("\n%s\n", out);
        assert(false);
    }

    int sessions = 0;
    const char *at = strstr(out, "sessions checked");
    assert(at != NULL);
    while (at > out && at[-1] != '\n') at--;
    assert(sscanf(at, "%d sessions checked", &sessions) == 1);
    assert(sessions >= 160);

    printf("  the editor does what %d scripted sessions say it does\n", sessions);
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
    test_basic_has_a_prompt();
    test_sola_compiles_a_program_that_runs();
    test_the_editor_draws_what_it_recorded();
    test_the_editor_does_what_the_keys_say();
    printf("test_cli: ok\n");
    return 0;
}
