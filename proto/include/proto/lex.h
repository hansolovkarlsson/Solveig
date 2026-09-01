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
#ifndef PROTO_LEX_H
#define PROTO_LEX_H

#include "proto/source.h"

typedef enum {
    PROTO_TOK_EOF,
    PROTO_TOK_ERROR,

    PROTO_TOK_NAME,        /* greet, upto, x                                  */
    PROTO_TOK_INTEGER,     /* #42   -- Solveig tags integers with '#'         */
    PROTO_TOK_FLOAT,       /* 42, 4.5                                         */
    PROTO_TOK_STRING,      /* "..."                                           */
    PROTO_TOK_SYMBOL,      /* 'quit                                           */
    PROTO_TOK_DIRECTIVE,   /* @infix                                          */
    PROTO_TOK_OPERATOR,    /* + ++ <= >>  -- spelling only; meaning is declared */

    PROTO_TOK_ASSIGN,      /* :=                                              */
    PROTO_TOK_COLON,       /* :                                               */
    PROTO_TOK_DOT,         /* .                                               */
    PROTO_TOK_COMMA,       /* ,                                               */
    PROTO_TOK_BAR,         /* |                                               */
    PROTO_TOK_LPAREN, PROTO_TOK_RPAREN,
    PROTO_TOK_LBRACKET, PROTO_TOK_RBRACKET,
    PROTO_TOK_LBRACE, PROTO_TOK_RBRACE
} ProtoTokenType;

typedef struct {
    ProtoTokenType type;
    ProtoSpan span;
    const char *start;      /* into the source text; not owned */
    int length;
    const char *message;    /* PROTO_TOK_ERROR only */
} ProtoToken;

typedef struct {
    const ProtoSource *source;
    const char *start;      /* source->text, for computing offsets */
    const char *current;
} ProtoLexer;

void proto_lexer_init(ProtoLexer *lexer, const ProtoSource *source);
ProtoToken proto_lexer_next(ProtoLexer *lexer);

const char *proto_token_type_name(ProtoTokenType type);

#endif /* PROTO_LEX_H */
