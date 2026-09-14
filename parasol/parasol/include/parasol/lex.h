/* lex.h -- the core lexer, which dialects do not get to change.
 *
 * A dialect declares operators, precedence and what they mean. It does not
 * declare tokens. That line is where the whole design sits: an extensible
 * grammar over a *fixed* token stream can still be parsed by something that has
 * not yet run the file's own declarations, and every editor, formatter and
 * `grep` downstream depends on that being true. Moving the line is what turned
 * TeX and Forth into languages no tool can read without executing them.
 *
 * If it has to move later, it moves at the module boundary and nowhere else:
 * something read before the first statement would have to name the reader. No
 * directive holds that place -- `@language` did, inertly, for nine versions
 * and was removed in 0.10.0. The seam is a sentence until there is a second
 * reader. */
#ifndef PARASOL_LEX_H
#define PARASOL_LEX_H

#include "parasol/source.h"

typedef enum {
    PARASOL_TOK_EOF,
    PARASOL_TOK_ERROR,

    PARASOL_TOK_NAME,        /* greet, upto, x                                  */
    PARASOL_TOK_INTEGER,     /* #42   -- Solveig tags integers with '#'         */
    PARASOL_TOK_FLOAT,       /* 42, 4.5                                         */
    PARASOL_TOK_STRING,      /* "..."                                           */
    PARASOL_TOK_SYMBOL,      /* 'quit                                           */
    PARASOL_TOK_DIRECTIVE,   /* @infix                                          */
    PARASOL_TOK_OPERATOR,    /* + ++ <= >>  -- spelling only; meaning is declared */

    PARASOL_TOK_ASSIGN,      /* :=                                              */
    PARASOL_TOK_COLON,       /* :                                               */
    PARASOL_TOK_DOT,         /* .                                               */
    PARASOL_TOK_COMMA,       /* ,                                               */
    PARASOL_TOK_BAR,         /* |                                               */
    PARASOL_TOK_LPAREN, PARASOL_TOK_RPAREN,
    PARASOL_TOK_LBRACKET, PARASOL_TOK_RBRACKET,
    PARASOL_TOK_HASH_LBRACKET,  /* #[  -- opens a dictionary                  */
    PARASOL_TOK_LBRACE, PARASOL_TOK_RBRACE
} ParasolTokenType;

typedef struct {
    ParasolTokenType type;
    ParasolSpan span;
    const char *start;      /* into the source text; not owned */
    int length;
    const char *message;    /* PARASOL_TOK_ERROR only */
} ParasolToken;

typedef struct {
    const ParasolSource *source;
    const char *start;      /* source->text, for computing offsets */
    const char *current;
} ParasolLexer;

void parasol_lexer_init(ParasolLexer *lexer, const ParasolSource *source);
ParasolToken parasol_lexer_next(ParasolLexer *lexer);

const char *parasol_token_type_name(ParasolTokenType type);

#endif /* PARASOL_LEX_H */
