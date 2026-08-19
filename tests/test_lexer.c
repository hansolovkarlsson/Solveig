/* Covers the scanning rules that keep ':=' and '.' unambiguous. */
#include <assert.h>
#include <stdio.h>
#include <string.h>

#include "solas/lexer.h"

/* Asserts that `source` scans to exactly `expected`, which must end in TOK_EOF. */
static void expect_tokens(const char *source, const SolTokenType *expected, int n)
{
    SolLexer lexer;
    sol_lexer_init(&lexer, source);

    for (int i = 0; i < n; i++) {
        SolToken token = sol_lexer_next(&lexer);
        if (token.type != expected[i]) {
            fprintf(stderr, "scanning %s: token %d was %s, expected %s\n",
                    source, i, sol_token_type_name(token.type),
                    sol_token_type_name(expected[i]));
            assert(false);
        }
    }
}

static void test_assignment_is_one_token(void)
{
    /* `a := #45.` -- ':=' must not scan as ':' followed by '='. */
    const SolTokenType expected[] = {
        TOK_IDENT, TOK_ASSIGN, TOK_INT, TOK_DOT, TOK_EOF
    };
    expect_tokens("a := #45.", expected, 5);
    expect_tokens("a:=#45.", expected, 5);   /* whitespace must not matter */
}

static void test_colon_still_sends(void)
{
    const SolTokenType expected[] = {
        TOK_IDENT, TOK_COLON, TOK_IDENT, TOK_DOT, TOK_EOF
    };
    expect_tokens("a:print.", expected, 5);
}

/* The rule that lets '.' be both a decimal point and a terminator. */
static void test_period_disambiguation(void)
{
    const SolTokenType terminated[] = { TOK_FLOAT, TOK_DOT, TOK_EOF };
    expect_tokens("45.", terminated, 3);

    const SolTokenType fractional[] = { TOK_FLOAT, TOK_EOF };
    expect_tokens("45.5", fractional, 2);

    const SolTokenType both[] = { TOK_FLOAT, TOK_DOT, TOK_EOF };
    expect_tokens("45.5.", both, 3);
}

static void test_hash_tags_integers(void)
{
    const SolTokenType ints[] = { TOK_INT, TOK_INT, TOK_EOF };
    expect_tokens("#45 #-45", ints, 3);

    /* A bare number is a float, not an integer. */
    const SolTokenType floats[] = { TOK_FLOAT, TOK_FLOAT, TOK_EOF };
    expect_tokens("45 -45", floats, 3);

    /* '#' on a fractional number is a mistake worth catching in the scanner. */
    const SolTokenType bad[] = { TOK_ERROR };
    expect_tokens("#45.5", bad, 1);
}

static void test_strings_symbols_and_comments(void)
{
    const SolTokenType expected[] = { TOK_STRING, TOK_SYMBOL, TOK_EOF };
    expect_tokens("\"hello\" 'foo", expected, 3);

    /* ';' comments produce no tokens at all. */
    const SolTokenType only_eof[] = { TOK_EOF };
    expect_tokens("; a := #45 is all commented out", only_eof, 1);

    const SolTokenType unterminated[] = { TOK_ERROR };
    expect_tokens("\"no closing quote", unterminated, 1);
}

static void test_lines_are_counted(void)
{
    SolLexer lexer;
    sol_lexer_init(&lexer, "a\n; comment\nb");

    SolToken first = sol_lexer_next(&lexer);
    SolToken second = sol_lexer_next(&lexer);
    assert(first.line == 1);
    assert(second.line == 3);
}

int main(void)
{
    test_assignment_is_one_token();
    test_colon_still_sends();
    test_period_disambiguation();
    test_hash_tags_integers();
    test_strings_symbols_and_comments();
    test_lines_are_counted();
    printf("test_lexer: ok\n");
    return 0;
}
