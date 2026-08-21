/* parser.h -- Solas parser.
 *
 * Grammar (as far as docs/design.md pins it down):
 *
 *     program    -> statement* EOF
 *     statement  -> directive | expression '.'?
 *     directive  -> DIRECTIVE STRING '.'?
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
 * A DIRECTIVE is `@include` and the '@' belongs to the token, so a directive is
 * never an expression and needs no lookahead to tell from one. It is the only
 * statement that is not an expression: what it does happens while compiling,
 * and there is nowhere inside an expression to compile a file into.
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

/* A note rather than a complaint: the file still compiles and the status is
   unchanged. */
void sol_parser_warning(SolParser *parser, const SolToken *token,
                        const char *message);

#endif /* SOLAS_PARSER_H */
