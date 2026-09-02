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
#ifndef PROTO_DIALECT_H
#define PROTO_DIALECT_H

#include "proto/source.h"
#include "proto/tree.h"

typedef enum { PROTO_ASSOC_LEFT, PROTO_ASSOC_RIGHT } ProtoAssoc;

/* An operator becomes either a message or a template.
 *
 *     @infix && 30 and.                      ->  a:and(b)
 *     @infix && 30 => left:and({ right }).   ->  a:and({ b })
 *
 * The second exists because the first cannot express a short-circuit. Solveig's
 * `and` takes a *block*, so naming it as the message produces `a:and(b)` and a
 * run-time refusal -- and `@syntax` could not fill the gap either, a pattern
 * having to begin with a word. programs/ember fell into it and wrote `:and`
 * by hand six times.
 *
 * `form` indexes the dialect's macro table, or is -1 for a plain message. An
 * operator with a template *is* a form, and reusing the expander for it means
 * hygiene, provenance and the expansion trail all arrive without a second
 * implementation. The two operands are called `left` and `right`, and a prefix
 * operand is called `operand`: an operator has exactly as many operands as it
 * has, so there is nothing to name. */
typedef struct {
    char *spelling;         /* "+"                                       */
    char *selector;         /* "add" -- the message it becomes; or NULL  */
    int form;               /* the template, as a macro index; or -1     */
    int precedence;
    ProtoAssoc assoc;
    ProtoSpan declared_at;    /* for "previously declared here"            */
} ProtoInfix;

typedef struct {
    char *spelling;
    char *selector;
    int form;
    ProtoSpan declared_at;
} ProtoPrefix;

/* What a hole will accept.
 *
 * All five are decided by looking at what was parsed, so none of them needs an
 * evaluator and none of them answers the tower question -- see
 * docs/rules-and-logic.md, which puts these below a real guard for exactly that
 * reason. What they buy is not the check but the message: a form saying what it
 * wants, at the use, instead of Solveig failing somewhere further down. */
typedef enum {
    PROTO_HOLE_EXPRESSION,    /* anything at all, and the default          */
    PROTO_HOLE_NAME,
    PROTO_HOLE_LITERAL,
    PROTO_HOLE_BLOCK,
    PROTO_HOLE_PLACE          /* something that may be assigned to         */
} ProtoHoleKind;

const char *proto_hole_kind_name(ProtoHoleKind kind);

/* Answers false if the word is not one of the five. */
bool proto_hole_kind_from(const char *text, int length, ProtoHoleKind *out);

/* One element of a pattern: a literal word, or a hole with the name the
   template knows it by. */
typedef struct {
    bool is_hole;
    char *text;
} ProtoPatternPart;

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
    ProtoHoleKind *kinds;     /* what each will accept; parallel to params */
    int param_count;
    ProtoPatternPart *parts;  /* NULL for a call-shaped form */
    int part_count;
    ProtoNode *template;      /* owned */
    ProtoSpan declared_at;
} ProtoMacro;

typedef struct {
    ProtoInfix *infix;
    int infix_count, infix_capacity;

    ProtoPrefix *prefix;
    int prefix_count, prefix_capacity;

    ProtoMacro *macro;
    int macro_count, macro_capacity;
} ProtoDialect;

void proto_dialect_init(ProtoDialect *dialect);
void proto_dialect_free(ProtoDialect *dialect);

/* Answer NULL when the operator was never declared. A spelling with no
   declaration is an error at the use site, not a guess -- an undeclared `+`
   meaning `add` by default is the one convenience that would make every
   dialect secretly the same dialect. */
const ProtoInfix *proto_dialect_infix(const ProtoDialect *dialect,
                                  const char *spelling, int length);
const ProtoPrefix *proto_dialect_prefix(const ProtoDialect *dialect,
                                    const char *spelling, int length);

/* Always added; lookup finds the last, so a later declaration wins. Answers the
   one it displaced, or NULL -- what to say about that is the reader's policy
   and not the table's. See *When two dialects collide* in the README. */
const ProtoInfix *proto_dialect_add_infix(ProtoDialect *dialect,
                                      const char *spelling, int length,
                                      const char *selector, int selector_length,
                                      int form, int precedence, ProtoAssoc assoc,
                                      ProtoSpan declared_at);
const ProtoPrefix *proto_dialect_add_prefix(ProtoDialect *dialect,
                                        const char *spelling, int length,
                                        const char *selector, int selector_length,
                                        int form, ProtoSpan declared_at);

/* Appends without the collision check the other adders run. For an operator's
   template, whose collision is reported against the *operator* -- saying it
   twice, once about `&&` and once about a form nobody named `&&`, would be
   saying it twice. */
int proto_dialect_add_template(ProtoDialect *dialect, const char *name, int length,
                             char **params, ProtoHoleKind *kinds, int param_count,
                             ProtoNode *template, ProtoSpan declared_at);

/* The last form declared under this name, which for a call-shaped form is the
   only one there may be. */
const ProtoMacro *proto_dialect_macro(const ProtoDialect *dialect,
                                  const char *name, int length);

/* The form a PROTO_NODE_MACRO's `form` index names. */
const ProtoMacro *proto_dialect_form_at(const ProtoDialect *dialect, int index);

/* Every form under this name, earliest first. More than one only where they are
   patterns that differ -- `if <c> then <a>` beside `if <c> then <a> else <b>`,
   which is the case the whole matcher exists for. Answers how many were
   written, which may exceed `max`. */
int proto_dialect_forms(const ProtoDialect *dialect, const char *name, int length,
                      const ProtoMacro **out, int max);

/* The index of a form, for a use to record. */
int proto_dialect_index_of(const ProtoDialect *dialect, const ProtoMacro *macro);

/* Takes the template and the parts. Answers the declaration it displaced, or
   NULL -- which for a pattern means one spelled exactly the same way, two that
   differ being allowed to stand together. */
const ProtoMacro *proto_dialect_add_macro(ProtoDialect *dialect,
                                      const char *name, int length,
                                      char **params, ProtoHoleKind *kinds,
                                      int param_count,
                                      ProtoPatternPart *parts, int part_count,
                                      ProtoNode *template, ProtoSpan declared_at);

#endif /* PROTO_DIALECT_H */
