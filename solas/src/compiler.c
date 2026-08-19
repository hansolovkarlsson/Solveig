/* compiler.c -- single pass: the parser drives emission straight into the
 * chunk, so there is no AST. */
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "solas/compiler.h"
#include "solas/parser.h"

typedef struct {
    SolParser parser;
    SolChunk *chunk;
} Compiler;

static void expression(Compiler *c);

static void emit(Compiler *c, uint8_t byte)
{
    sol_chunk_write(c->chunk, byte, c->parser.previous.line);
}

static void emit_pair(Compiler *c, uint8_t a, uint8_t b)
{
    emit(c, a);
    emit(c, b);
}

/* Interns the token's text and returns its operand index, refusing to overflow
   the one-byte operand. */
static uint8_t name_operand(Compiler *c, const SolToken *token)
{
    int index = sol_chunk_add_name(c->chunk, token->start, token->length);
    if (index > UINT8_MAX) {
        sol_parser_error(&c->parser, token, "too many names in one chunk");
        return 0;
    }
    return (uint8_t)index;
}

static uint8_t constant_operand(Compiler *c, SolValue value)
{
    int index = sol_chunk_add_constant(c->chunk, value);
    if (index > UINT8_MAX) {
        sol_parser_error(&c->parser, &c->parser.previous,
                         "too many constants in one chunk");
        return 0;
    }
    return (uint8_t)index;
}

/* ---- literals -------------------------------------------------------- */

static void integer_literal(Compiler *c)
{
    const SolToken *token = &c->parser.previous;

    /* Skip the '#' type tag; strtoll handles the optional sign. */
    errno = 0;
    char *end;
    long long value = strtoll(token->start + 1, &end, 10);
    if (errno == ERANGE) {
        sol_parser_error(&c->parser, token, "integer literal out of range");
        return;
    }
    emit_pair(c, OP_CONST, constant_operand(c, SOL_INT_VAL((int64_t)value)));
}

static void float_literal(Compiler *c)
{
    const SolToken *token = &c->parser.previous;
    double value = strtod(token->start, NULL);
    emit_pair(c, OP_CONST, constant_operand(c, SOL_FLOAT_VAL(value)));
}

/* ---- expressions ----------------------------------------------------- */

/* IDENT is either an assignment target or a name to resolve. One token of
   lookahead is enough because a target is always a bare identifier. */
static void identifier(Compiler *c)
{
    SolToken name = c->parser.previous;

    if (sol_parser_match(&c->parser, TOK_ASSIGN)) {
        expression(c);
        emit_pair(c, OP_SET_GLOBAL, name_operand(c, &name));
    } else {
        emit_pair(c, OP_GLOBAL, name_operand(c, &name));
    }
}

static void primary(Compiler *c)
{
    SolParser *p = &c->parser;

    if (sol_parser_match(p, TOK_IDENT))      { identifier(c); return; }
    if (sol_parser_match(p, TOK_INT))        { integer_literal(c); return; }
    if (sol_parser_match(p, TOK_FLOAT))      { float_literal(c); return; }
    if (sol_parser_match(p, TOK_LPAREN)) {
        /* Parentheses only group; they carry no meaning of their own. */
        expression(c);
        sol_parser_consume(p, TOK_RPAREN, "expected ')'");
        return;
    }
    if (sol_parser_match(p, TOK_STRING)) {
        sol_parser_error(p, &p->previous,
                         "strings are scanned but have no runtime type yet");
        return;
    }
    if (sol_parser_match(p, TOK_SYMBOL)) {
        sol_parser_error(p, &p->previous,
                         "symbols are scanned but have no runtime type yet");
        return;
    }

    sol_parser_error(p, &p->current, "expected an expression");
}

/* Arguments to one message: '(' expression ( ',' expression )* ')' */
static uint8_t arguments(Compiler *c)
{
    SolParser *p = &c->parser;
    int argc = 0;

    if (!sol_parser_match(p, TOK_LPAREN)) return 0;   /* a bare `a:print` */

    if (!sol_parser_match(p, TOK_RPAREN)) {
        do {
            expression(c);
            if (++argc > UINT8_MAX) {
                sol_parser_error(p, &p->current, "too many arguments");
                return 0;
            }
        } while (sol_parser_match(p, TOK_COMMA));
        sol_parser_consume(p, TOK_RPAREN, "expected ')' after arguments");
    }
    return (uint8_t)argc;
}

static void expression(Compiler *c)
{
    SolParser *p = &c->parser;

    primary(c);

    /* Sends chain left to right: `a:add(#1):print` sends print to the sum. */
    while (sol_parser_match(p, TOK_COLON)) {
        sol_parser_consume(p, TOK_IDENT, "expected a message name after ':'");
        SolToken selector = p->previous;
        uint8_t argc = arguments(c);

        emit(c, OP_SEND);
        emit(c, name_operand(c, &selector));
        emit(c, argc);
    }
}

/* After an error, skip to the next statement boundary so one mistake does not
   cascade into a screenful. */
static void synchronise(Compiler *c)
{
    SolParser *p = &c->parser;
    p->panicked = false;

    while (p->current.type != TOK_EOF) {
        if (p->previous.type == TOK_DOT) return;
        sol_parser_advance(p);
    }
}

static void statement(Compiler *c)
{
    expression(c);
    sol_parser_match(&c->parser, TOK_DOT);   /* the terminator stays optional */
    emit(c, OP_POP);                         /* a statement leaves nothing behind */

    if (c->parser.panicked) synchronise(c);
}

bool sol_compile(const char *source, SolChunk *chunk)
{
    Compiler c;
    c.chunk = chunk;
    sol_parser_init(&c.parser, source);

    while (!sol_parser_match(&c.parser, TOK_EOF)) {
        statement(&c);
    }
    emit(&c, OP_HALT);

    return !c.parser.had_error;
}
