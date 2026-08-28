/* lexer.h -- Solas token scanner.
 *
 * Surface syntax, from docs/design.md:
 *
 *     a := #45         ; ':=' binds a name; '#' tags an integer literal
 *     b := 45          ; a bare number is a float
 *     c := 1.5e-3      ; with an exponent, optionally signed
 *     s := "hello"     ; double quotes are strings
 *     e := "a\"b\n"     ; \" \\ \n \t \r are the escapes
 *     a:print.         ; ':' sends; '.' terminates a statement
 *     { a:print }      ; braces make a block: code as a value, not an action
 *     [#1, #2]         ; brackets make an array -- sugar for array:of(#1, #2)
 *     ( | t | ... )    ; '|' declares this frame's temporaries
 *     @math(a^2 + b/2) ; infix arithmetic, lowering to the sends it reads as
 *     @include "lib.sol"  ; '@' marks a directive: compile time, not run
 *                      ;     time, and not a message to anything
 *                      ; ';' begins a comment, running to end of line
 *
 * Two rules keep the scanner unambiguous:
 *   - ':' followed by '=' is one TOK_ASSIGN token, never a send.
 *   - A '.' only continues a float if a digit follows it, so `45.` is the
 *     float 45 followed by a statement terminator.
 */
#ifndef SOLAS_LEXER_H
#define SOLAS_LEXER_H

#include "solum/common.h"

typedef enum {
    TOK_IDENT,      /* a, integer, print            */
    TOK_INT,        /* #45                          */
    TOK_FLOAT,      /* 45, 45.5                     */
    TOK_STRING,     /* "hello"                      */
    TOK_SYMBOL,     /* 'foo                         */
    TOK_DIRECTIVE,  /* @include -- compile time     */
    TOK_COLON,      /* :   message send             */
    TOK_ASSIGN,     /* :=  binding                  */
    TOK_LPAREN,
    TOK_RPAREN,
    TOK_LBRACE,     /* {   block literal            */
    TOK_RBRACE,
    TOK_LBRACKET,   /* [   array literal            */
    TOK_RBRACKET,
    TOK_PIPE,       /* |   declares temporaries     */
    TOK_COMMA,      /* argument separator           */
    TOK_DOT,        /* .   statement terminator     */

    /* Arithmetic, and only inside `@math(...)`. The language has no operators
       and the grammar says so; these are notation for the sends they lower to,
       in a region that says where it begins and ends. Four of the five were
       *unexpected character* until now, so no program that compiled before can
       contain one -- `-` is the exception and is the reason for `infix` below. */
    TOK_PLUS,       /* +   add                      */
    TOK_MINUS,      /* -   sub, or unary negation   */
    TOK_STAR,       /* *   mul                      */
    TOK_SLASH,      /* /   div                      */
    TOK_CARET,      /* ^   pow                      */

    TOK_ERROR,
    TOK_EOF
} SolTokenType;

typedef struct {
    SolTokenType type;
    /* Always into the source, for every kind of token including TOK_ERROR: an
       error's text is in `message` rather than here, so that a caller wanting
       to point at the offending characters always can. */
    const char  *start;
    int          length;
    int          line;
    int          column;      /* 1-based, in bytes */
    const char  *message;     /* TOK_ERROR only; NULL otherwise */
} SolToken;

typedef struct {
    const char *start;      /* start of the token being scanned */
    const char *current;
    int         line;
    const char *line_start; /* first character of the line `current` is on */

    /* Where the token being scanned began. A string may span lines, so the
       line it *ends* on is not the line it is reported at. */
    int         token_line;
    const char *token_line_start;

    /* Inside `@math(...)`, where `-` is the subtraction operator rather than
     * part of the number after it.
     *
     * It is the *only* character that has to be told which region it is in.
     * Outside, a leading `-` belongs to the literal -- there is no negation
     * operator to mistake it for -- and `a - 3` is the lexical error
     * *'-' must be followed by digits*. So no program that compiles today
     * contains a `-` in operator position, and the mode changes the meaning of
     * nothing that is currently legal. Inside, `-3` reads as unary minus
     * applied to `3`, which the compiler folds back to the same constant.
     *
     * The compiler owns this: it is set before the '(' of a `@math` region is
     * consumed and cleared before the ')' is, so that the tokens either side of
     * the region are scanned by the rules of where they actually are. */
    bool        infix;
} SolLexer;

void     sol_lexer_init(SolLexer *lexer, const char *source);
SolToken sol_lexer_next(SolLexer *lexer);

/* Human-readable token name, for parser errors and lexer tests. */
const char *sol_token_type_name(SolTokenType type);

/* The first character of the line `token` sits on, derived from where the token
   starts and how far into its line it is. */
const char *sol_token_line_start(const SolToken *token);

#endif /* SOLAS_LEXER_H */
