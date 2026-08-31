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

/* One element of a pattern: a literal word, or a hole with the name the
   template knows it by. */
typedef struct {
    bool is_hole;
    char *text;
} PhxPatternPart;

/* A form the module declared, in one of two shapes.
 *
 *     @syntax unless(test, body) => ... .        a call
 *     @syntax unless <test> then <body> => ... . a pattern
 *
 * The call shape is for a form that reads like an application and the pattern
 * for one that reads like a statement, and `params` means the same thing in
 * both: the holes, in the order the arguments arrive. The expander never
 * learned which shape it came from, and does not need to.
 *
 * A pattern begins with a word and never has two holes in a row. Both are
 * forced rather than chosen: a reader finds a form by seeing a name it knows,
 * so a pattern starting with a hole would put it back to guessing -- and two
 * holes in a row have no boundary between them for anything to find.
 *
 * @syntax unless(test, body) => ... .
 *
 * The template is a tree, parsed under the header as it stood where the
 * declaration appeared -- so a form may use the operators above it and the
 * forms above it, and may not use what comes after. A header that reads
 * top to bottom is a header a person can read the same way. */
typedef struct {
    char *name;             /* the leading word, in both shapes */
    char **params;          /* the holes, in order */
    int param_count;
    PhxPatternPart *parts;  /* NULL for a call-shaped form */
    int part_count;
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

/* The last form declared under this name, which for a call-shaped form is the
   only one there may be. */
const PhxMacro *phx_dialect_macro(const PhxDialect *dialect,
                                  const char *name, int length);

/* The form a PHX_NODE_MACRO's `form` index names. */
const PhxMacro *phx_dialect_form_at(const PhxDialect *dialect, int index);

/* Every form under this name, earliest first. More than one only where they are
   patterns that differ -- `if <c> then <a>` beside `if <c> then <a> else <b>`,
   which is the case the whole matcher exists for. Answers how many were
   written, which may exceed `max`. */
int phx_dialect_forms(const PhxDialect *dialect, const char *name, int length,
                      const PhxMacro **out, int max);

/* The index of a form, for a use to record. */
int phx_dialect_index_of(const PhxDialect *dialect, const PhxMacro *macro);

/* Takes the template and the parts. Answers the declaration it displaced, or
   NULL -- which for a pattern means one spelled exactly the same way, two that
   differ being allowed to stand together. */
const PhxMacro *phx_dialect_add_macro(PhxDialect *dialect,
                                      const char *name, int length,
                                      char **params, int param_count,
                                      PhxPatternPart *parts, int part_count,
                                      PhxNode *template, PhxSpan declared_at);

#endif /* PHOENIX_DIALECT_H */
