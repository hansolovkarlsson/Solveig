/* Deciding when a submission at the prompt is finished, and holding what has
   been typed. Roadmap 5.1. */
#define _POSIX_C_SOURCE 200809L

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "solis/input.h"

/* Feeds `text` a line at a time, the way the loop does, and answers whether
   the input is still waiting for more. */
static bool wants_more_after(const char *text)
{
    SolisScan state;
    sol_scan_reset(&state);
    sol_scan(&state, text);
    return sol_scan_wants_more(&state);
}

static void test_balanced_input_is_finished(void)
{
    static const char *finished[] = {
        "#1:print.",
        "a := [#1, #2, #3].",
        "integer:double := { self:mul(#2) }.",
        "f := { a | { b | a:add(b) } }.",
        "x := ( #1. #2 ).",
        "\"a string\":display.",
        "\"{}\":fill([#1]):display.",           /* braces inside a string */
        "#1:print. ; a { brace } in a comment",  /* and inside a comment   */
        "\"he said \\\"{\\\" once\":size:print.", /* an escaped quote      */
        ").",                                    /* a stray closer         */
        "",
    };

    for (size_t i = 0; i < sizeof(finished) / sizeof(finished[0]); i++) {
        assert(!wants_more_after(finished[i]));
    }
    printf("  %zu finished forms, none of them waiting\n",
           sizeof(finished) / sizeof(finished[0]));
}

static void test_unfinished_input_waits(void)
{
    static const char *waiting[] = {
        "integer:double := {",
        "a := [#1, #2,",
        "x := ( #1.",
        "x := \"unterminated",
        "f := { a | { b |",
        "x := \"a \\\"",                 /* the escape does not close it */
        "; a comment then\n{",
    };

    for (size_t i = 0; i < sizeof(waiting) / sizeof(waiting[0]); i++) {
        assert(wants_more_after(waiting[i]));
    }
    printf("  %zu unfinished forms, all of them waiting\n",
           sizeof(waiting) / sizeof(waiting[0]));
}

/* The state carries across lines, which is the whole point: a bracket or a
   string opened on one line is still open on the next. */
static void test_the_state_carries_across_lines(void)
{
    SolisScan state;
    sol_scan_reset(&state);

    sol_scan(&state, "integer:double := {\n");
    assert(sol_scan_wants_more(&state));
    sol_scan(&state, "    self:mul(#2)\n");
    assert(sol_scan_wants_more(&state));
    sol_scan(&state, "}.\n");
    assert(!sol_scan_wants_more(&state));

    /* A string opened on one line and closed on the next. */
    sol_scan_reset(&state);
    sol_scan(&state, "x := \"one\n");
    assert(sol_scan_wants_more(&state));
    sol_scan(&state, "two\".\n");
    assert(!sol_scan_wants_more(&state));

    printf("  a bracket or a string opened on one line is open on the next\n");
}

/* A comment ends at its newline, so a brace after one counts again. */
static void test_a_comment_ends_at_its_line(void)
{
    assert(!wants_more_after("#1:print. ; {\n"));
    assert(wants_more_after("#1:print. ; comment\nf := {\n"));
    printf("  a comment hides a brace only to the end of its own line\n");
}

/* A stray closer must not go negative, or the count would never come back to
   zero and the prompt would wait for input that could not arrive. */
static void test_a_stray_closer_does_not_go_negative(void)
{
    SolisScan state;
    sol_scan_reset(&state);

    sol_scan(&state, ")))].\n");
    assert(state.depth == 0);
    assert(!sol_scan_wants_more(&state));

    sol_scan(&state, "f := {\n");
    assert(sol_scan_wants_more(&state));      /* still counts from zero */
    sol_scan(&state, "}.\n");
    assert(!sol_scan_wants_more(&state));

    printf("  a stray closer leaves the depth at zero, not below it\n");
}

/* ---- the buffer --------------------------------------------------------- */

static void test_the_buffer_grows(void)
{
    SolisInput input = { NULL, 0, 0 };

    /* Well past the 1024 bytes the old fixed buffer held. */
    for (int i = 0; i < 500; i++) sol_input_append(&input, "0123456789");
    assert(input.length == 5000);
    assert(strlen(input.text) == 5000);
    assert(input.text[4999] == '9');

    sol_input_clear(&input);
    assert(input.length == 0);
    assert(input.text[0] == '\0');

    sol_input_append(&input, "again");
    assert(strcmp(input.text, "again") == 0);

    sol_input_free(&input);
    printf("  the buffer grows past the old 1024-byte cap and clears\n");
}

/* A line longer than the read chunk arrives whole rather than cut, which is
   the failure the old buffer had: the tail came back as the next line. */
static void test_a_long_line_is_not_cut(void)
{
    char path[] = "/tmp/solis-line-XXXXXX";
    int fd = mkstemp(path);
    assert(fd >= 0);

    FILE *out = fdopen(fd, "w");
    assert(out != NULL);
    for (int i = 0; i < 5000; i++) fputc('x', out);
    fputc('\n', out);
    fputs("second\n", out);
    fclose(out);

    FILE *in = fopen(path, "rb");
    assert(in != NULL);

    SolisInput input = { NULL, 0, 0 };
    assert(sol_input_read_line(&input, in));
    assert(input.length == 5001);            /* the x's and the newline */
    assert(input.text[0] == 'x' && input.text[4999] == 'x');
    assert(input.text[5000] == '\n');

    sol_input_clear(&input);
    assert(sol_input_read_line(&input, in));
    assert(strcmp(input.text, "second\n") == 0);

    /* And nothing left to read. */
    sol_input_clear(&input);
    assert(!sol_input_read_line(&input, in));

    fclose(in);
    remove(path);
    sol_input_free(&input);
    printf("  a 5000-byte line arrives whole, and the next line is the next line\n");
}

/* A final line with no newline of its own still counts as read. */
static void test_a_last_line_without_a_newline(void)
{
    char path[] = "/tmp/solis-tail-XXXXXX";
    int fd = mkstemp(path);
    assert(fd >= 0);
    FILE *out = fdopen(fd, "w");
    fputs("#1:print.", out);                 /* no trailing newline */
    fclose(out);

    FILE *in = fopen(path, "rb");
    SolisInput input = { NULL, 0, 0 };
    assert(sol_input_read_line(&input, in));
    assert(strcmp(input.text, "#1:print.") == 0);
    assert(!sol_input_read_line(&input, in));

    fclose(in);
    remove(path);
    sol_input_free(&input);
    printf("  a last line with no newline is still a line\n");
}

int main(void)
{
    printf("solis input\n");
    test_balanced_input_is_finished();
    test_unfinished_input_waits();
    test_the_state_carries_across_lines();
    test_a_comment_ends_at_its_line();
    test_a_stray_closer_does_not_go_negative();
    test_the_buffer_grows();
    test_a_long_line_is_not_cut();
    test_a_last_line_without_a_newline();
    printf("ok\n");
    return 0;
}
