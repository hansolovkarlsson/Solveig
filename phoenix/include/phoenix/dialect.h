/* dialect.h -- what a module declared its syntax to be.
 *
 * The declarations are read from the top of the file before any statement is,
 * and they are the only thing that changes how the rest of it parses. This is
 * the per-module grammar: a file's syntax is settled by that file's own header,
 * so a tool can parse it by reading it top to bottom and never has to run
 * anything, and two files in one program may be written in different dialects
 * without either of them knowing.
 *
 * Operators came first because a precedence table composes: adding one cannot
 * change what an expression without it already meant. Forms came second, with
 * hygiene in the same commit rather than after it -- a system that expands
 * without hygiene grows programs that depend on the capture, and those programs
 * are what make hygiene impossible to add later. */
#ifndef PHOENIX_DIALECT_H
#define PHOENIX_DIALECT_H

#include "phoenix/source.h"
#include "phoenix/tree.h"

typedef enum { PHX_ASSOC_LEFT, PHX_ASSOC_RIGHT } PhxAssoc;

typedef struct {
    char *spelling;         /* "+"                                       */
    char *selector;         /* "add" -- the message it becomes           */
    int precedence;
    PhxAssoc assoc;
    PhxSpan declared_at;    /* for "previously declared here"            */
} PhxInfix;

typedef struct {
    char *spelling;
    char *selector;
    PhxSpan declared_at;
} PhxPrefix;

/* A form the module declared:  @syntax unless(test, body) => ... .
 *
 * The template is a tree, parsed under the header as it stood where the
 * declaration appeared -- so a form may use the operators above it and the
 * forms above it, and may not use what comes after. A header that reads
 * top to bottom is a header a person can read the same way. */
typedef struct {
    char *name;
    char **params;
    int param_count;
    PhxNode *template;      /* owned */
    PhxSpan declared_at;
} PhxMacro;

typedef struct {
    char *name;             /* what @language named; NULL if unstated    */
    PhxSpan declared_at;

    PhxInfix *infix;
    int infix_count, infix_capacity;

    PhxPrefix *prefix;
    int prefix_count, prefix_capacity;

    PhxMacro *macro;
    int macro_count, macro_capacity;
} PhxDialect;

void phx_dialect_init(PhxDialect *dialect);
void phx_dialect_free(PhxDialect *dialect);

/* Answer NULL when the operator was never declared. A spelling with no
   declaration is an error at the use site, not a guess -- an undeclared `+`
   meaning `add` by default is the one convenience that would make every
   dialect secretly the same dialect. */
const PhxInfix *phx_dialect_infix(const PhxDialect *dialect,
                                  const char *spelling, int length);
const PhxPrefix *phx_dialect_prefix(const PhxDialect *dialect,
                                    const char *spelling, int length);

/* Always added; lookup finds the last, so a later declaration wins. Answers the
   one it displaced, or NULL -- what to say about that is the reader's policy
   and not the table's. See *When two dialects collide* in the README. */
const PhxInfix *phx_dialect_add_infix(PhxDialect *dialect,
                                      const char *spelling, int length,
                                      const char *selector, int selector_length,
                                      int precedence, PhxAssoc assoc,
                                      PhxSpan declared_at);
const PhxPrefix *phx_dialect_add_prefix(PhxDialect *dialect,
                                        const char *spelling, int length,
                                        const char *selector, int selector_length,
                                        PhxSpan declared_at);

const PhxMacro *phx_dialect_macro(const PhxDialect *dialect,
                                  const char *name, int length);

/* Takes the template. Answers the declaration it displaced, or NULL. */
const PhxMacro *phx_dialect_add_macro(PhxDialect *dialect,
                                      const char *name, int length,
                                      char **params, int param_count,
                                      PhxNode *template, PhxSpan declared_at);

#endif /* PHOENIX_DIALECT_H */
