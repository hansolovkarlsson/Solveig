/* parser.h -- Solas parser.
 *
 * Grammar (as far as docs/design.md pins it down):
 *
 *     program    -> statement* EOF
 *     statement  -> expression '.'?
 *     expression -> IDENT ':=' expression
 *                |  send
 *     send       -> primary ( ':' IDENT arguments? )*
 *     arguments  -> '(' ( expression ( ',' expression )* )? ')'
 *     primary    -> IDENT | INT | FLOAT | STRING | '(' expression ')'
 *
 * A bare IDENT in receiver position is a name lookup, not a message send: in
 * `integer:new(a)` the receiver `integer` is the class object found in the
 * globals namespace, and `new` is the message sent to it.
 */
#ifndef SOLAS_PARSER_H
#define SOLAS_PARSER_H

#include "solum/common.h"
#include "solas/lexer.h"

typedef struct {
    SolLexer lexer;
    SolToken current;
    SolToken previous;
    bool     had_error;
    bool     panicked;   /* suppresses cascaded errors until resynchronised */
} SolParser;

void sol_parser_init(SolParser *parser, const char *source);

/* Token-stream helpers used by the single-pass compiler. */
void sol_parser_advance(SolParser *parser);
bool sol_parser_match(SolParser *parser, SolTokenType type);
void sol_parser_consume(SolParser *parser, SolTokenType type, const char *message);
void sol_parser_error(SolParser *parser, const SolToken *token, const char *message);

#endif /* SOLAS_PARSER_H */
