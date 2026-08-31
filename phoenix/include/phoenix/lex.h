/* lex.h -- the core lexer, which dialects do not get to change.
 *
 * A dialect declares operators, precedence and what they mean. It does not
 * declare tokens. That line is where the whole design sits: an extensible
 * grammar over a *fixed* token stream can still be parsed by something that has
 * not yet run the file's own declarations, and every editor, formatter and
 * `grep` downstream depends on that being true. Moving the line is what turned
 * TeX and Forth into languages no tool can read without executing them.
 *
 * If it has to move later, it moves at the module boundary and nowhere else --
 * `@language` names a reader before a single statement is read. */
#ifndef PHOENIX_LEX_H
#define PHOENIX_LEX_H

#include "phoenix/source.h"

typedef enum {
    PHX_TOK_EOF,
    PHX_TOK_ERROR,

    PHX_TOK_NAME,        /* greet, upto, x                                  */
    PHX_TOK_INTEGER,     /* #42   -- Solveig tags integers with '#'         */
    PHX_TOK_FLOAT,       /* 42, 4.5                                         */
    PHX_TOK_STRING,      /* "..."                                           */
    PHX_TOK_SYMBOL,      /* 'quit                                           */
    PHX_TOK_DIRECTIVE,   /* @infix                                          */
    PHX_TOK_OPERATOR,    /* + ++ <= >>  -- spelling only; meaning is declared */

    PHX_TOK_ASSIGN,      /* :=                                              */
    PHX_TOK_COLON,       /* :                                               */
    PHX_TOK_DOT,         /* .                                               */
    PHX_TOK_COMMA,       /* ,                                               */
    PHX_TOK_BAR,         /* |                                               */
    PHX_TOK_LPAREN, PHX_TOK_RPAREN,
    PHX_TOK_LBRACKET, PHX_TOK_RBRACKET,
    PHX_TOK_LBRACE, PHX_TOK_RBRACE
} PhxTokenType;

typedef struct {
    PhxTokenType type;
    PhxSpan span;
    const char *start;      /* into the source text; not owned */
    int length;
    const char *message;    /* PHX_TOK_ERROR only */
} PhxToken;

typedef struct {
    const char *source;     /* the whole text, for computing offsets */
    const char *current;
} PhxLexer;

void phx_lexer_init(PhxLexer *lexer, const char *source);
PhxToken phx_lexer_next(PhxLexer *lexer);

const char *phx_token_type_name(PhxTokenType type);

#endif /* PHOENIX_LEX_H */
