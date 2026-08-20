/* parser.h -- Solas parser.
 *
 * Grammar (as far as docs/design.md pins it down):
 *
 *     program    -> statement* EOF
 *     statement  -> include | expression '.'?
 *     include    -> STRING ':' 'include' '.'?
 *     expression -> IDENT ':=' expression
 *                |  send
 *     send       -> primary ( ':' IDENT arguments? )*
 *     arguments  -> '(' ( expression ( ',' expression )* )? ')'
 *     primary    -> IDENT | INT | FLOAT | STRING | '(' expression ')'
 *
 * A bare IDENT in receiver position is a name lookup, not a message send: in
 * `integer:new(a)` the receiver `integer` is the class object found in the
 * globals namespace, and `new` is the message sent to it.
 *
 * `include` is the one place the grammar is not uniform. It parses as a send to
 * a string literal, and the compiler takes it before the send is emitted; the
 * shape is a directive rather than an expression, which is why it appears as a
 * statement and nowhere else.
 */
#ifndef SOLAS_PARSER_H
#define SOLAS_PARSER_H

#include "solum/common.h"
#include "solas/lexer.h"

typedef struct {
    SolLexer lexer;
    SolToken current;
    SolToken previous;
    /* The file this source came from, named in errors. NULL when the source is
       text rather than a file -- the prompt, or a test -- and errors then carry
       only a line and column, as they always did. */
    const char *path;
    bool     had_error;
    bool     panicked;   /* suppresses cascaded errors until resynchronised */
} SolParser;

void sol_parser_init(SolParser *parser, const char *source, const char *path);

/* Token-stream helpers used by the single-pass compiler. */
void sol_parser_advance(SolParser *parser);
bool sol_parser_match(SolParser *parser, SolTokenType type);
void sol_parser_consume(SolParser *parser, SolTokenType type, const char *message);
void sol_parser_error(SolParser *parser, const SolToken *token, const char *message);

#endif /* SOLAS_PARSER_H */
