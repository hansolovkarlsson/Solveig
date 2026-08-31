/* dialect.h -- what a module declared its syntax to be.
 *
 * The declarations are read from the top of the file before any statement is,
 * and they are the only thing that changes how the rest of it parses. This is
 * the per-module grammar: a file's syntax is settled by that file's own header,
 * so a tool can parse it by reading it top to bottom and never has to run
 * anything, and two files in one program may be written in different dialects
 * without either of them knowing.
 *
 * 0.1.0 declares operators and nothing else. Operators are the extension point
 * to start with because a precedence table composes -- adding one cannot change
 * what an expression without it already meant -- while a general grammar rule
 * can, silently. Statement forms and macros come next, and they come with a
 * hygiene story or they do not come at all. */
#ifndef PHOENIX_DIALECT_H
#define PHOENIX_DIALECT_H

#include "phoenix/source.h"

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

typedef struct {
    char *name;             /* what @language named; NULL if unstated    */
    PhxSpan declared_at;

    PhxInfix *infix;
    int infix_count, infix_capacity;

    PhxPrefix *prefix;
    int prefix_count, prefix_capacity;
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

/* Answer the earlier declaration when there is one, so the caller can report
   the collision with both spans; NULL when the addition was clean. */
const PhxInfix *phx_dialect_add_infix(PhxDialect *dialect,
                                      const char *spelling, int length,
                                      const char *selector, int selector_length,
                                      int precedence, PhxAssoc assoc,
                                      PhxSpan declared_at);
const PhxPrefix *phx_dialect_add_prefix(PhxDialect *dialect,
                                        const char *spelling, int length,
                                        const char *selector, int selector_length,
                                        PhxSpan declared_at);

#endif /* PHOENIX_DIALECT_H */
