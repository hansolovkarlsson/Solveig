#include <stdio.h>

#include "solas/parser.h"

void sol_parser_init(SolParser *parser, const char *source)
{
    sol_lexer_init(&parser->lexer, source);
    parser->had_error = false;
    parser->panicked = false;
    parser->current.type = TOK_EOF;
    parser->current.start = source;
    parser->current.length = 0;
    parser->current.line = 1;
    parser->previous = parser->current;
    sol_parser_advance(parser);
}

void sol_parser_error(SolParser *parser, const SolToken *token, const char *message)
{
    if (parser->panicked) return;    /* one error per statement is plenty */
    parser->panicked = true;
    parser->had_error = true;

    fprintf(stderr, "[line %d] solas: %s", token->line, message);
    if (token->type == TOK_EOF) {
        fprintf(stderr, " at end\n");
    } else if (token->type == TOK_ERROR) {
        fprintf(stderr, "\n");
    } else {
        fprintf(stderr, " at '%.*s'\n", token->length, token->start);
    }
}

void sol_parser_advance(SolParser *parser)
{
    parser->previous = parser->current;
    for (;;) {
        parser->current = sol_lexer_next(&parser->lexer);
        if (parser->current.type != TOK_ERROR) break;
        sol_parser_error(parser, &parser->current, parser->current.start);
    }
}

bool sol_parser_match(SolParser *parser, SolTokenType type)
{
    if (parser->current.type != type) return false;
    sol_parser_advance(parser);
    return true;
}

void sol_parser_consume(SolParser *parser, SolTokenType type, const char *message)
{
    if (parser->current.type == type) {
        sol_parser_advance(parser);
        return;
    }
    sol_parser_error(parser, &parser->current, message);
}
