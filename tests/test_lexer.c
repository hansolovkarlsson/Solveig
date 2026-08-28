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

/* `$FF08` and `%10101100` -- the same integer written in another base. They are
 * TOK_INT like `#45`, because that is all they are: the base is a property of
 * how it was typed and nothing downstream is told. */
static void test_dollar_and_percent_are_integers(void)
{
    const SolTokenType ints[] = { TOK_INT, TOK_INT, TOK_INT, TOK_EOF };
    expect_tokens("$FF08 $ff %10101100", ints, 4);

    /* The tag needs digits of its own base, and nothing else may follow them.
     * Without that last rule `%1012` would be the binary `%101` and the float
     * `2` -- two good tokens, a wrong reading, and no complaint. */
    const SolTokenType bad[] = { TOK_ERROR };
    expect_tokens("$", bad, 1);
    expect_tokens("%", bad, 1);
    expect_tokens("%1012", bad, 1);
    expect_tokens("$FFg", bad, 1);

    /* No sign, unlike `#-45`: these are for looking at bits. */
    expect_tokens("$-FF", bad, 1);

    /* And no float in either base, for the reason `#45.5` is refused. */
    expect_tokens("$FF.5", bad, 1);
    expect_tokens("%101.1", bad, 1);
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

/* `@include` is one token, '@' and all: a directive can never be mistaken for a
   send, and the bare word stays free for anything else to use. */
static void test_directives_scan(void)
{
    const SolTokenType expected[] = { TOK_DIRECTIVE, TOK_STRING, TOK_DOT, TOK_EOF };
    expect_tokens("@include \"lib.sol\".", expected, 4);

    SolLexer lexer;
    sol_lexer_init(&lexer, "@include");
    SolToken t = sol_lexer_next(&lexer);
    assert(t.length == 8);                    /* the '@' belongs to the token */
    assert(t.start[0] == '@');

    /* A name has to follow, the same rule a symbol's quote lives by. */
    const SolTokenType bare[] = { TOK_ERROR };
    expect_tokens("@ include", bare, 1);
    expect_tokens("@3", bare, 1);
}

/* A `#!` on the very first line is skipped, so a `.sol` file can be marked
   executable and run directly. The newline is left for the scanner to find, so
   the line after it is line 2 and an error names the line an editor shows. */
static void test_a_shebang_is_skipped(void)
{
    const SolTokenType expected[] = { TOK_IDENT, TOK_ASSIGN, TOK_INT, TOK_DOT, TOK_EOF };
    expect_tokens("#!/usr/bin/env solis\na := #45.", expected, 5);

    SolLexer lexer;
    sol_lexer_init(&lexer, "#!/usr/bin/env solis\na := #45.");
    SolToken first = sol_lexer_next(&lexer);
    assert(first.line == 2);              /* not 1: the numbering does not shift */

    /* Only at the very start. Anywhere else `#` begins an integer, including
       on line 1 after column 0. */
    const SolTokenType later[] = { TOK_INT, TOK_ERROR };
    expect_tokens("#1 #!", later, 2);

    /* And a file that is nothing but a shebang is empty rather than broken. */
    const SolTokenType only[] = { TOK_EOF };
    expect_tokens("#!/usr/bin/env solis", only, 1);
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

static void test_brackets_scan(void)
{
    const SolTokenType expected[] = {
        TOK_LBRACKET, TOK_INT, TOK_COMMA, TOK_INT, TOK_RBRACKET, TOK_EOF
    };
    expect_tokens("[#1, #2]", expected, 6);

    const SolTokenType empty[] = { TOK_LBRACKET, TOK_RBRACKET, TOK_EOF };
    expect_tokens("[]", empty, 3);
}

static void test_exponents(void)
{
    const SolTokenType one[] = { TOK_FLOAT, TOK_EOF };
    expect_tokens("1e3", one, 2);
    expect_tokens("1E3", one, 2);
    expect_tokens("1e+3", one, 2);
    expect_tokens("1e-3", one, 2);
    expect_tokens("1.5e-3", one, 2);
    expect_tokens("1e308", one, 2);

    /* A bare `e` is left alone rather than claimed, so this is a float and an
       identifier -- which the statement rule then rejects as two things with no
       separator, a clearer failure than a malformed number. */
    const SolTokenType split[] = { TOK_FLOAT, TOK_IDENT, TOK_EOF };
    expect_tokens("1e", split, 3);
    expect_tokens("1ex", split, 3);

    /* `1e+` splits the same way, and the third token is the `+` itself. It used
       to be TOK_ERROR, `+` being a character the language did not use; `@math`
       gave it one. The program is rejected either way and by the same message
       -- *expected '.' between statements* at the `e`, which is what `1e` alone
       already says -- so what moved is where the complaint comes from, not
       whether there is one. */
    const SolTokenType dangling[] = { TOK_FLOAT, TOK_IDENT, TOK_PLUS };
    expect_tokens("1e+", dangling, 3);

    /* `#` is exact, so an integer takes no exponent. */
    const SolTokenType integer[] = { TOK_INT, TOK_IDENT, TOK_EOF };
    expect_tokens("#1e3", integer, 3);
}

/* A token carries where it is, not just which line it is on (5.4). The column
   is 1-based and counted in bytes. */
/* The five arithmetic operators, and the one that needed a mode.
 *
 * `+ * / ^` are tokens everywhere. They cost nothing to scan unconditionally,
 * because none of them was a character the language used -- `@math` is where
 * the compiler accepts them, and outside one it says so by name.
 *
 * `-` is the exception and the whole reason `infix` exists. Outside a region a
 * leading `-` belongs to the number after it, which is what leaves the language
 * with no negation operator to mistake it for; inside one it is always the
 * operator, and `-3` is unary minus applied to `3`. */
static void test_arithmetic_operators(void)
{
    const SolTokenType ops[] = {
        TOK_PLUS, TOK_STAR, TOK_SLASH, TOK_CARET, TOK_EOF
    };
    expect_tokens("+ * / ^", ops, 5);

    /* Outside a region: the number claims the sign, and a `-` with no digit
       after it is a lexical error rather than a token. */
    const SolTokenType outside[] = { TOK_IDENT, TOK_FLOAT, TOK_EOF };
    expect_tokens("a -3", outside, 3);

    const SolTokenType lone[] = { TOK_IDENT, TOK_ERROR };
    expect_tokens("a - 3", lone, 2);

    /* Inside one: the same two sources scan as subtraction, which is what makes
       the reading of `a-3` and `a - 3` the same. */
    SolLexer lexer;
    const SolTokenType inside[] = { TOK_IDENT, TOK_MINUS, TOK_FLOAT, TOK_EOF };
    const char *sources[] = { "a -3", "a - 3", "a-3" };
    for (int s = 0; s < 3; s++) {
        sol_lexer_init(&lexer, sources[s]);
        lexer.infix = true;
        for (int i = 0; i < 4; i++) {
            SolToken token = sol_lexer_next(&lexer);
            if (token.type != inside[i]) {
                fprintf(stderr, "in a region, %s: token %d was %s, expected %s\n",
                        sources[s], i, sol_token_type_name(token.type),
                        sol_token_type_name(inside[i]));
                assert(false);
            }
        }
    }

    /* The tagged integer keeps its own sign in either mode: the '#' scanner
       takes the '-' before the operator rule can see it. And an exponent's sign
       is inside the number for the same reason. */
    sol_lexer_init(&lexer, "#-3 1.5e-3");
    lexer.infix = true;
    assert(sol_lexer_next(&lexer).type == TOK_INT);
    assert(sol_lexer_next(&lexer).type == TOK_FLOAT);
    assert(sol_lexer_next(&lexer).type == TOK_EOF);
}

static void test_tokens_carry_a_column(void)
{
    SolLexer lexer;
    sol_lexer_init(&lexer, "a := #45.\n  b:print.\n");

    struct { int line; int column; } expected[] = {
        { 1, 1 },   /* a      */
        { 1, 3 },   /* :=     */
        { 1, 6 },   /* #45    */
        { 1, 9 },   /* .      */
        { 2, 3 },   /* b      */
        { 2, 4 },   /* :      */
        { 2, 5 },   /* print  */
        { 2, 10 },  /* .      */
    };

    for (size_t i = 0; i < sizeof(expected) / sizeof(expected[0]); i++) {
        SolToken token = sol_lexer_next(&lexer);
        assert(token.line == expected[i].line);
        assert(token.column == expected[i].column);
        /* And the column really does locate the token's first character. */
        assert(sol_token_line_start(&token) + token.column - 1 == token.start);
    }
}

/* A string may span lines, so the line it *ends* on is not the line it starts
   on. It is reported where it opened, which is where the reader has to look. */
static void test_a_multiline_token_is_placed_where_it_opens(void)
{
    SolLexer lexer;
    sol_lexer_init(&lexer, "x := \"one\ntwo\".\ny := #1.\n");

    SolToken t = sol_lexer_next(&lexer);   /* x  */
    t = sol_lexer_next(&lexer);            /* := */
    t = sol_lexer_next(&lexer);            /* the string */
    assert(t.type == TOK_STRING);
    assert(t.line == 1);
    assert(t.column == 6);

    /* The line after it is still counted correctly. */
    t = sol_lexer_next(&lexer);            /* .  */
    assert(t.line == 2);
    t = sol_lexer_next(&lexer);            /* y  */
    assert(t.line == 3 && t.column == 1);
}

/* An error token points at the offending characters, and carries its complaint
   separately -- so a caller can underline what went wrong. */
static void test_an_error_token_points_at_the_source(void)
{
    /* '?' is the third character to hold this job. '@' lost it to directives and
       '%' to binary literals, each time because the language grew a use for it
       -- so what this test really needs is a character nothing has claimed, and
       the list of those gets shorter. */
    SolLexer lexer;
    sol_lexer_init(&lexer, "b := ?.");

    SolToken t = sol_lexer_next(&lexer);   /* b  */
    t = sol_lexer_next(&lexer);            /* := */
    t = sol_lexer_next(&lexer);
    assert(t.type == TOK_ERROR);
    assert(t.message != NULL);
    assert(strcmp(t.message, "unexpected character") == 0);
    assert(t.line == 1 && t.column == 6);
    assert(t.start[0] == '?');             /* into the source, not the message */
    assert(t.length == 1);
}

int main(void)
{
    test_exponents();
    test_brackets_scan();
    test_assignment_is_one_token();
    test_colon_still_sends();
    test_period_disambiguation();
    test_hash_tags_integers();
    test_dollar_and_percent_are_integers();
    test_strings_symbols_and_comments();
    test_directives_scan();
    test_a_shebang_is_skipped();
    test_lines_are_counted();
    test_arithmetic_operators();
    test_tokens_carry_a_column();
    test_a_multiline_token_is_placed_where_it_opens();
    test_an_error_token_points_at_the_source();
    printf("test_lexer: ok\n");
    return 0;
}
