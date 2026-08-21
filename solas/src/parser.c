#include <stdio.h>

#include "solas/parser.h"

void sol_parser_init(SolParser *parser, const char *source, const char *path)
{
    sol_lexer_init(&parser->lexer, source);
    parser->path = path;
    parser->had_error = false;
    parser->panicked = false;
    parser->current.type = TOK_EOF;
    parser->current.start = source;
    parser->current.length = 0;
    parser->current.line = 1;
    parser->current.column = 1;
    parser->current.message = NULL;
    parser->previous = parser->current;
    sol_parser_advance(parser);
}

/* How much of a line to show. A line has no length limit -- Solis will read one
   of any size -- so a long one is windowed around the token rather than spilled
   whole down the terminal. */
#define SOL_ERROR_LINE_MAX 78
#define SOL_ERROR_LEAD     24    /* kept before the token when windowing */

/* Prints the offending line and a caret under the token.
 *
 * The pad is built from the line's own characters rather than from spaces, so a
 * tab before the token indents the caret by a tab too and the two still line up
 * however the terminal renders it. */
static void show_source(const SolToken *token)
{
    const char *line = sol_token_line_start(token);

    int length = 0;
    while (line[length] != '\0' && line[length] != '\n') length++;

    int column = token->column;
    int from = 0;

    /* Window a long line around the token, keeping a little of what precedes
       it so the position still reads in context. */
    if (length > SOL_ERROR_LINE_MAX) {
        if (column - 1 > SOL_ERROR_LEAD) from = column - 1 - SOL_ERROR_LEAD;
        if (from + SOL_ERROR_LINE_MAX > length) {
            from = length - SOL_ERROR_LINE_MAX;
            if (from < 0) from = 0;
        }
    }
    int shown = length - from;
    if (shown > SOL_ERROR_LINE_MAX) shown = SOL_ERROR_LINE_MAX;

    fprintf(stderr, "  %s%.*s%s\n",
            from > 0 ? "..." : "", shown, line + from,
            from + shown < length ? "..." : "");

    fprintf(stderr, "  %s", from > 0 ? "   " : "");
    for (int i = from; i < column - 1 && i < from + shown; i++) {
        fputc(line[i] == '\t' ? '\t' : ' ', stderr);
    }

    /* A caret per character of the token, so a misplaced name is underlined
       rather than merely pointed at. Nothing to underline at end of input. */
    int width = token->length;
    if (width < 1) width = 1;
    if (column - 1 + width > from + shown) width = from + shown - (column - 1);
    if (width < 1) width = 1;
    for (int i = 0; i < width; i++) fputc('^', stderr);
    fputc('\n', stderr);
}

void sol_parser_error(SolParser *parser, const SolToken *token, const char *message)
{
    if (parser->panicked) return;    /* one error per statement is plenty */
    parser->panicked = true;
    parser->had_error = true;

    if (parser->path != NULL) {
        fprintf(stderr, "[%s:%d:%d] solas: %s",
                parser->path, token->line, token->column, message);
    } else {
        fprintf(stderr, "[line %d:%d] solas: %s", token->line, token->column, message);
    }
    if (token->type == TOK_EOF) {
        fprintf(stderr, " at end\n");
    } else if (token->type == TOK_ERROR) {
        fprintf(stderr, "\n");
    } else {
        fprintf(stderr, " at '%.*s'\n", token->length, token->start);
    }
    show_source(token);
}

/* Not an error: the file compiles, the status is unchanged, and this is a note
   about something that will not do what it looks like. It goes to stderr with
   the same location and the same echoed line, because the reader wants the same
   two things either way -- where, and what.

   Suppressed while panicking for the reason errors are: the parser is already
   lost, and a note about a line it is skipping past is noise. */
void sol_parser_warning(SolParser *parser, const SolToken *token, const char *message)
{
    if (parser->panicked) return;

    if (parser->path != NULL) {
        fprintf(stderr, "[%s:%d:%d] solas: warning: %s\n",
                parser->path, token->line, token->column, message);
    } else {
        fprintf(stderr, "[line %d:%d] solas: warning: %s\n",
                token->line, token->column, message);
    }
    show_source(token);
}

void sol_parser_advance(SolParser *parser)
{
    parser->previous = parser->current;
    for (;;) {
        parser->current = sol_lexer_next(&parser->lexer);
        if (parser->current.type != TOK_ERROR) break;
        sol_parser_error(parser, &parser->current, parser->current.message);
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
