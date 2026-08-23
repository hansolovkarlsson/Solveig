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

#include "solas/lexer.h"
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
          "#1:toDo(#4, { n | tally:add(n:mul(n)) }).\n"
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
    fputs("n := #0. #1:toDo(#2000, { i | n := n:inc }). n:print.\n", f);
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
 * A block that continues one further up, or that shows syntax rather than a
 * program, is **not checked and not a failure**. The checker counts those and
 * prints the count, because one that silently verified a quarter of its subject
 * would be worse than none.
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
       to check fails too. It was 589 across 40 files when this went in; the
       floor is there to catch a collapse, not to be updated for every example
       that gains a line. */
    int claims = 0;
    const char *at = strstr(out, "claims checked");
    assert(at != NULL);
    while (at > out && *at != ',') at--;
    assert(sscanf(at, ", %d claims checked", &claims) == 1);
    assert(claims >= 500);

    printf("  everything written down is true (%d claims)\n", claims);
}

/* Stage 0 of asking whether Solas could be written in Solum: a .sob written by
 * a Solum program, byte for byte, and run.
 *
 * The assertion is `cmp`, not "it behaves the same". A file that runs correctly
 * and differs in its tables would leave the interesting question open, and the
 * interesting question is whether the two compilers can be held to the same
 * answer -- which is what the later stages need if they are ever built.
 *
 * See docs/ideas.md, "Solas written in Solum". */
static void test_a_sob_written_by_solum_matches_the_compiler(void)
{
    char out[8 * 1024];

    assert(run("bin/solas programs/emit.sol -o " DIR "/emit.sob 2>&1",
               out, sizeof out) == 0);
    assert(run("bin/solvm " DIR "/emit.sob " DIR "/emitted 2>&1",
               out, sizeof out) == 0);

    /* The same two programs, through the compiler this is being compared to. */
    assert(run("printf '\"hi\":display.\\n' > " DIR "/hi.sol && "
               "printf '#45:print.\\n' > " DIR "/num.sol", out, sizeof out) == 0);

    static const char *const names[] = { "hi", "num" };
    for (size_t i = 0; i < sizeof names / sizeof names[0]; i++) {
        char command[512];

        /* Compiled from the same directory the emitter claims in the file's
           path table, since that path is part of the bytes being compared. */
        snprintf(command, sizeof command,
                 "cd " DIR " && ../../../bin/solas %s.sol 2>&1", names[i]);
        assert(run(command, out, sizeof out) == 0);

        snprintf(command, sizeof command,
                 "cmp " DIR "/%s.sob " DIR "/emitted/%s.sob 2>&1", names[i], names[i]);
        if (run(command, out, sizeof out) != 0) {
            printf("\n%s.sob differs from what solas produced:\n%s\n", names[i], out);
            assert(false);
        }

        /* And it runs, which cmp alone would not tell you if both were wrong. */
        snprintf(command, sizeof command, "bin/solvm " DIR "/emitted/%s.sob", names[i]);
        assert(run(command, out, sizeof out) == 0);
    }

    printf("  a .sob written by Solum is the one the compiler writes\n");
}

/* Stage 1 of asking whether Solas could be written in Solum: the scanner.
 *
 * lib/lexer.sol is written against solas/src/lexer.c rule for rule, and this is
 * what holds it there. Every .sol file in the repository is scanned by both and
 * the tokens compared -- kind, line, column and text, in order, to the end of
 * the file. Not "produces something reasonable": the same tokens.
 *
 * The corpus is the point. Hand-written cases test the rules somebody thought
 * of; a few thousand tokens of real Solum test the ones they did not, and the
 * awkward corners here -- `45.` against `45.5`, a bare `e` that is not an
 * exponent, ':' against ':=' -- are all in it because the language uses them.
 *
 * See docs/ideas.md, "Solas written in Solum". */
static const char *const token_kind[] = {
    "ident", "int", "float", "string", "symbol", "directive",
    "colon", "assign", "lparen", "rparen", "lbrace", "rbrace",
    "lbracket", "rbracket", "pipe", "comma", "dot", "error", "eof"
};

/* The same escaping lib/lexer.sol's dumper does, so that a token carrying a
   newline stays on one line of the dump on both sides. */
static void write_escaped(FILE *f, const char *text, int length)
{
    for (int i = 0; i < length; i++) {
        char c = text[i];
        if      (c == '\\') fputs("\\\\", f);
        else if (c == '\n') fputs("\\n", f);
        else if (c == '\r') fputs("\\r", f);
        else if (c == '\t') fputs("\\t", f);
        else                fputc(c, f);
    }
}

static void dump_tokens_with_c(const char *source, const char *out_path)
{
    FILE *f = fopen(out_path, "wb");
    assert(f != NULL);

    SolLexer lexer;
    sol_lexer_init(&lexer, source);
    for (;;) {
        SolToken token = sol_lexer_next(&lexer);
        fprintf(f, "%s|%d|%d|", token_kind[token.type], token.line, token.column);
        write_escaped(f, token.start, token.length);
        fputc('\n', f);
        if (token.type == TOK_EOF) break;
    }
    fclose(f);
}

/* The whole file, for handing to the C scanner. */
static char *read_source(const char *path)
{
    FILE *f = fopen(path, "rb");
    assert(f != NULL);
    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    fseek(f, 0, SEEK_SET);
    char *text = malloc((size_t)size + 1);
    assert(text != NULL);
    assert(fread(text, 1, (size_t)size, f) == (size_t)size);
    text[size] = '\0';
    fclose(f);
    return text;
}

/* Both scanners over one file, compared line for line. Answers the token count.
 *
 * The paths come from the shell rather than from opendir because this file
 * defines DIR as its own scratch directory, and dirent.h wants that name for a
 * type. Shelling out is what the rest of this file does anyway. */
static int scan_file_with_both(const char *path)
{
    char command[1024], out[8 * 1024];

    char *source = read_source(path);
    dump_tokens_with_c(source, DIR "/tokens-c.txt");
    free(source);

    snprintf(command, sizeof command,
             "bin/solvm " DIR "/lexdump.sob %s > " DIR "/tokens-sol.txt 2>&1", path);
    if (run(command, out, sizeof out) != 0) {
        printf("\nlib/lexer.sol failed on %s\n", path);
        run("cat " DIR "/tokens-sol.txt", out, sizeof out);
        printf("%s\n", out);
        assert(false);
    }

    if (run("cmp " DIR "/tokens-c.txt " DIR "/tokens-sol.txt 2>&1",
            out, sizeof out) != 0) {
        printf("\nlib/lexer.sol disagrees with solas/src/lexer.c on %s:\n%s\n",
               path, out);
        run("diff " DIR "/tokens-c.txt " DIR "/tokens-sol.txt | head -10",
            out, sizeof out);
        printf("%s\n", out);
        assert(false);
    }

    int tokens = 0;
    FILE *counted = fopen(DIR "/tokens-c.txt", "rb");
    assert(counted != NULL);
    for (int c = fgetc(counted); c != EOF; c = fgetc(counted)) {
        if (c == '\n') tokens++;
    }
    fclose(counted);
    return tokens;
}

/* The corner cases, as one file. */
static const char fixture[] =
          "; the awkward corners, which real code does not always reach\n"
          "a := #45. b := 45. c := 45.5.\n"
          "d := 1e3. e := 1E+3. f := 1.5e-3.\n"
          "g := 1e. h := 1E. i := 1e+. j := 45.\n"
          "k := #-5. m := -5. n := -5.5.\n"
          "s := \"a\\\"b\\n\\\\c\". t := \"spans\n"
          "a line\". u := 'sym. v := 'a1_b.\n"
          "@include \"x.sol\".\n"
          "w := [#1, #2]. x := { p , q | | r | p }. y := (a).\n"
          "z := a:print. aa:bb := #1.\n"
          "%\n"
          "#x\n"
          "-x\n"
          "'1\n"
          "@1\n"
          "\"unterminated\n"
          "";

static void test_solum_scans_solum_the_way_c_does(void)
{
    char out[8 * 1024];

    /* The dumper is written here rather than shipped: it exists to be compared
       against, and a program in programs/ would have to earn its place by doing
       a job somebody wants done. */
    FILE *f = fopen(DIR "/lexdump.sol", "wb");
    assert(f != NULL);
    fputs("@include \"lexer.sol\".\n"
          "escaped := { s | | out |\n"
          "    out := array:new.\n"
          "    #1:toDo(s:size, { i | | c |\n"
          "        c := s:at(i).\n"
          "        c:equals(\"\\\\\"):ifElse(\n"
          "            { out:add(\"\\\\\\\\\") },\n"
          "            { c:equals(\"\\n\"):ifElse(\n"
          "                { out:add(\"\\\\n\") },\n"
          "                { c:equals(\"\\r\"):ifElse(\n"
          "                    { out:add(\"\\\\r\") },\n"
          "                    { c:equals(\"\\t\"):ifElse({ out:add(\"\\\\t\") },\n"
          "                                            { out:add(c) }) }) }) }) }).\n"
          "    out:join(\"\") }.\n"
          "lexer:all(system:readFile(system:arguments:at(#1))):do({ t |\n"
          "    \"{}|{}|{}|{}\":fill([t:at(\"type\"):asString, t:at(\"line\"),\n"
          "                        t:at(\"column\"), escaped:value(t:at(\"text\"))]):display }).\n",
          f);
    fclose(f);

    assert(run("bin/solas " DIR "/lexdump.sol -o " DIR "/lexdump.sob -I lib 2>&1",
               out, sizeof out) == 0);

    char list[16 * 1024];
    assert(run("ls examples/*.sol lib/*.sol programs/*.sol", list, sizeof list) == 0);

    int files = 0, tokens = 0;
    for (char *path = strtok(list, "\n"); path != NULL; path = strtok(NULL, "\n")) {
        if (path[0] == '\0') continue;
        tokens += scan_file_with_both(path);
        files++;
    }

    /* And the corners the corpus does not reach, because working code does not
       contain them: a bare `e` that is not an exponent, `45.` against `45.5`, a
       string with a newline inside it -- which is the one place a token's line
       and the scanner's line differ -- and five ways to be wrong, since an
       error token has a position too and the two scanners have to recover from
       it identically or everything after it disagrees.

       This was written after the corpus passed on the first run and a
       deliberately broken exponent rule still passed: 33,000 tokens of real
       Solum contain no `1e` followed by a non-digit. A corpus tests what nobody
       thought of, and cases like these test what somebody did. */
    f = fopen(DIR "/corners.sol", "wb");
    assert(f != NULL);
    fputs(fixture, f);
    fclose(f);
    tokens += scan_file_with_both(DIR "/corners.sol");
    files++;

    /* A corpus that quietly stopped being scanned would pass every comparison
       it made, so the size is asserted too. */
    assert(files >= 40);
    assert(tokens >= 20000);

    printf("  Solum scans Solum the way C does (%d files, %d tokens)\n",
           files, tokens);
}

/* Stage 1: source in, bytecode out, and the bytecode is the compiler's.
 *
 * Every .sol file in the repository is offered to programs/compile.sol. What it
 * accepts must come out byte-identical to what solas produces from the same
 * path; what it refuses is fine and counted, because the subset is deliberate
 * and named in the program's own header.
 *
 * Both are given the *same* spelling of the path, which is not fussiness: the
 * path goes into the file's table so a stack trace can name it, so compiling
 * `hello.sol` and `corpus/hello.sol` correctly produces two different files.
 *
 * The shape of this test is what makes it useful as the compiler grows: nothing
 * lists which files ought to work, so a construct that starts compiling is
 * counted the moment it does, and one that starts compiling *wrongly* fails.
 *
 * See docs/ideas.md, "Solas written in Solum". */
static void test_solum_compiles_solum_to_the_same_bytes(void)
{
    char out[8 * 1024], list[16 * 1024], command[1024];

    assert(run("bin/solas programs/compile.sol -o " DIR "/compile.sob 2>&1",
               out, sizeof out) == 0);
    assert(run("ls examples/*.sol lib/*.sol programs/*.sol", list, sizeof list) == 0);

    int accepted = 0, refused = 0;
    for (char *path = strtok(list, "\n"); path != NULL; path = strtok(NULL, "\n")) {
        if (path[0] == '\0') continue;

        snprintf(command, sizeof command,
                 "bin/solvm " DIR "/compile.sob %s -o " DIR "/mine.sob"
                 " > /dev/null 2>&1", path);
        if (run(command, out, sizeof out) != 0) { refused++; continue; }

        snprintf(command, sizeof command,
                 "bin/solas %s -o " DIR "/theirs.sob 2>&1", path);
        assert(run(command, out, sizeof out) == 0);

        if (run("cmp " DIR "/mine.sob " DIR "/theirs.sob 2>&1", out, sizeof out) != 0) {
            printf("\nprograms/compile.sol and solas disagree on %s:\n%s\n", path, out);
            assert(false);
        }

        /* And the machine will load it. Not that it exits zero -- several
           examples exit non-zero on purpose -- and not that it prints what the
           other one printed, since a program that reads the clock prints
           something different every time it runs. What is checked is the one
           thing a byte comparison cannot already tell you: that the file gets
           past the verifier, which is where a malformed chunk is caught. */
        run("bin/solvm " DIR "/mine.sob < /dev/null > " DIR "/mine.out 2>&1",
            out, sizeof out);
        run("cat " DIR "/mine.out", out, sizeof out);
        if (strstr(out, "cannot load") != NULL) {
            printf("\n%s produced a file the machine refuses:\n%s\n", path, out);
            assert(false);
        }
        accepted++;
    }

    /* A compiler that quietly stopped accepting anything would pass every
       comparison it made. */
    assert(accepted >= 3);
    printf("  Solum compiles Solum to the same bytes (%d files, %d outside the subset)\n",
           accepted, refused);
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
    test_a_sob_written_by_solum_matches_the_compiler();
    test_solum_scans_solum_the_way_c_does();
    test_solum_compiles_solum_to_the_same_bytes();
    printf("test_cli: ok\n");
    return 0;
}
