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
    assert(strstr(out, "[line 5]") != NULL);     /* where the call is written */

    /* And with it off, stderr is empty. */
    assert(run("bin/solvm " DIR "/traced.sob 2>&1 >/dev/null", out, sizeof out) == 0);
    assert(out[0] == '\0');
    printf("  --trace writes the call tree to stderr and leaves stdout alone\n");
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
    assert(strstr(shallow, "[line 4]") != NULL);   /* the outermost call */
    assert(strstr(shallow, "[line 3]") == NULL);   /* and not the one inside it */
    assert(strstr(deep, "[line 3]") != NULL);

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

int main(void)
{
    test_help_is_not_an_error();
    test_version_names_the_format();
    test_a_mistake_goes_to_stderr();
    test_the_program_keeps_its_own_arguments();
    test_trace_writes_the_call_tree();
    test_trace_is_quiet_where_there_are_no_calls();
    test_trace_takes_a_depth();
    test_the_other_options_still_work();
    printf("test_cli: ok\n");
    return 0;
}
