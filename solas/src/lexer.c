#include <string.h>

#include "solas/lexer.h"

void sol_lexer_init(SolLexer *lexer, const char *source)
{
    lexer->start = source;
    lexer->current = source;
    lexer->line = 1;
    lexer->line_start = source;
    lexer->token_line = 1;
    lexer->token_line_start = source;
}

/* Consumes a newline the cursor is sitting on, moving to the next line. Every
   place that crosses one goes through here, so the line number and the line's
   first character cannot come apart -- and a column is only meaningful if they
   agree. */
static void newline(SolLexer *lexer)
{
    lexer->line++;
    lexer->current++;
    lexer->line_start = lexer->current;
}

const char *sol_token_line_start(const SolToken *token)
{
    return token->start - (token->column - 1);
}

const char *sol_token_type_name(SolTokenType type)
{
    switch (type) {
    case TOK_IDENT:  return "identifier";
    case TOK_INT:    return "integer";
    case TOK_FLOAT:  return "float";
    case TOK_STRING: return "string";
    case TOK_SYMBOL: return "symbol";
    case TOK_COLON:  return "':'";
    case TOK_ASSIGN: return "':='";
    case TOK_LPAREN: return "'('";
    case TOK_RPAREN: return "')'";
    case TOK_LBRACE: return "'{'";
    case TOK_RBRACE: return "'}'";
    case TOK_LBRACKET: return "'['";
    case TOK_RBRACKET: return "']'";
    case TOK_PIPE:   return "'|'";
    case TOK_COMMA:  return "','";
    case TOK_DOT:    return "'.'";
    case TOK_ERROR:  return "error";
    case TOK_EOF:    return "end of file";
    }
    return "?";
}

static bool is_at_end(SolLexer *lexer)   { return *lexer->current == '\0'; }
static char peek(SolLexer *lexer)        { return *lexer->current; }
static char peek_next(SolLexer *lexer)
{
    return is_at_end(lexer) ? '\0' : lexer->current[1];
}
static char advance(SolLexer *lexer)     { return *lexer->current++; }

static bool match(SolLexer *lexer, char expected)
{
    if (is_at_end(lexer) || *lexer->current != expected) return false;
    lexer->current++;
    return true;
}

static bool is_digit(char c) { return c >= '0' && c <= '9'; }
static bool is_alpha(char c)
{
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_';
}

static SolToken make_token(SolLexer *lexer, SolTokenType type)
{
    SolToken token;
    token.type = type;
    token.start = lexer->start;
    token.length = (int)(lexer->current - lexer->start);
    /* Where the token *began*: a string that spans lines is reported at its
       opening quote, not at the line the closing one happens to land on. */
    token.line = lexer->token_line;
    token.column = (int)(lexer->start - lexer->token_line_start) + 1;
    token.message = NULL;
    return token;
}

/* The offending characters stay in `start`/`length` and the complaint goes in
   `message`, so an error token can be pointed at like any other. */
static SolToken error_token(SolLexer *lexer, const char *message)
{
    SolToken token = make_token(lexer, TOK_ERROR);
    token.message = message;
    return token;
}

/* Whitespace and ';' comments carry no tokens. */
static void skip_ignorable(SolLexer *lexer)
{
    for (;;) {
        char c = peek(lexer);
        switch (c) {
        case ' ':
        case '\r':
        case '\t':
            advance(lexer);
            break;
        case '\n':
            newline(lexer);
            break;
        case ';':
            while (peek(lexer) != '\n' && !is_at_end(lexer)) advance(lexer);
            break;
        default:
            return;
        }
    }
}

static SolToken identifier(SolLexer *lexer)
{
    while (is_alpha(peek(lexer)) || is_digit(peek(lexer))) advance(lexer);
    return make_token(lexer, TOK_IDENT);
}

/* `#45` -- the '#' is a type tag, so the digits must follow immediately. */
static SolToken integer(SolLexer *lexer)
{
    match(lexer, '-');
    if (!is_digit(peek(lexer))) {
        return error_token(lexer, "expected digits after '#'");
    }
    while (is_digit(peek(lexer))) advance(lexer);

    if (peek(lexer) == '.' && is_digit(peek_next(lexer))) {
        return error_token(lexer, "'#' marks an integer; drop it for a float");
    }
    return make_token(lexer, TOK_INT);
}

/* A bare number is a float. The '.' only continues the number when a digit
   follows, so `45.` is the float 45 plus a statement terminator. */
static SolToken number(SolLexer *lexer)
{
    while (is_digit(peek(lexer))) advance(lexer);
    if (peek(lexer) == '.' && is_digit(peek_next(lexer))) {
        advance(lexer);
        while (is_digit(peek(lexer))) advance(lexer);
    }

    /* An exponent, but only if it really is one: `1e3`, `1E+3`, `1.5e-3`. A bare
       `e` is left alone rather than claimed, so `1e` stays a float and an
       identifier instead of becoming a malformed number. */
    if (peek(lexer) == 'e' || peek(lexer) == 'E') {
        const char *before = lexer->current;
        advance(lexer);
        if (peek(lexer) == '+' || peek(lexer) == '-') advance(lexer);
        if (is_digit(peek(lexer))) {
            while (is_digit(peek(lexer))) advance(lexer);
        } else {
            lexer->current = before;
        }
    }
    return make_token(lexer, TOK_FLOAT);
}

/* Scanning only needs to know that a backslash claims the next character, so
   that `\"` does not end the string. Which escapes are legal is the compiler's
   business, decided in one place when it decodes them. */
static SolToken string(SolLexer *lexer)
{
    while (peek(lexer) != '"' && !is_at_end(lexer)) {
        if (peek(lexer) == '\n') { newline(lexer); continue; }
        if (peek(lexer) == '\\') {
            advance(lexer);
            if (is_at_end(lexer)) break;
        }
        advance(lexer);
    }
    if (is_at_end(lexer)) return error_token(lexer, "unterminated string");
    advance(lexer);   /* closing quote */
    return make_token(lexer, TOK_STRING);
}

/* `'foo` -- a quote prefix, no closing quote, the way Lisp reads a symbol. */
static SolToken symbol(SolLexer *lexer)
{
    if (!is_alpha(peek(lexer))) {
        return error_token(lexer, "expected a name after \"'\"");
    }
    while (is_alpha(peek(lexer)) || is_digit(peek(lexer))) advance(lexer);
    return make_token(lexer, TOK_SYMBOL);
}

SolToken sol_lexer_next(SolLexer *lexer)
{
    skip_ignorable(lexer);
    lexer->start = lexer->current;
    lexer->token_line = lexer->line;
    lexer->token_line_start = lexer->line_start;

    if (is_at_end(lexer)) return make_token(lexer, TOK_EOF);

    char c = advance(lexer);

    if (is_alpha(c)) return identifier(lexer);
    if (is_digit(c)) return number(lexer);

    switch (c) {
    case '#':  return integer(lexer);
    case '"':  return string(lexer);
    case '\'': return symbol(lexer);
    case '(':  return make_token(lexer, TOK_LPAREN);
    case ')':  return make_token(lexer, TOK_RPAREN);
    case '{':  return make_token(lexer, TOK_LBRACE);
    case '}':  return make_token(lexer, TOK_RBRACE);
    case '[':  return make_token(lexer, TOK_LBRACKET);
    case ']':  return make_token(lexer, TOK_RBRACKET);
    case '|':  return make_token(lexer, TOK_PIPE);
    case ',':  return make_token(lexer, TOK_COMMA);
    case '.':  return make_token(lexer, TOK_DOT);
    /* ':' followed by '=' is one token, never a send. This is why selectors
       must be identifiers -- if '=' were one, `a:=(b)` would be ambiguous. */
    case ':':  return make_token(lexer, match(lexer, '=') ? TOK_ASSIGN : TOK_COLON);
    case '-':
        if (is_digit(peek(lexer))) return number(lexer);
        return error_token(lexer, "'-' must be followed by digits");
    }

    return error_token(lexer, "unexpected character");
}
