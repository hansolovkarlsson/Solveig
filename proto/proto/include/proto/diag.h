/* diag.h -- diagnostics, reported against a span of the source the programmer
 * actually wrote.
 *
 * This exists in the first commit rather than a later one because the failure
 * it prevents is the one that kills syntax-extension systems: a programmer
 * writes surface syntax, and the compiler complains about something further
 * down that they have never seen. Every error here takes a `ProtoSpan`, and there
 * is no overload that does not, so the compiler cannot grow a diagnostic that
 * has forgotten where it came from. */
#ifndef PROTO_DIAG_H
#define PROTO_DIAG_H

#include <stdio.h>

#include "proto/source.h"
#include "proto/tree.h"

typedef struct {
    FILE *out;
    int errors;
    int warnings;
    ProtoSpan last;           /* what the previous report underlined */
} ProtoDiagnostics;

void proto_diag_init(ProtoDiagnostics *diag, FILE *out);

/* Prints the message, the line it happened on, and a caret under `span`. */
void proto_error(ProtoDiagnostics *diag, ProtoSpan span, const char *format, ...);

/* Solveig's own answer to two files claiming one name: the later wins, and the
   compiler says so rather than letting it pass. Proto follows it for syntax,
   and the reasoning is in the README under *When two dialects collide*. */
void proto_warning(ProtoDiagnostics *diag, ProtoSpan span, const char *format, ...);

/* A second span attached to the report just printed -- "declared here". Counts
   towards neither total. */
void proto_note(ProtoDiagnostics *diag, ProtoSpan span, const char *format, ...);

/* The chain of forms a node was expanded out of, innermost first.
 *
 * Prints nothing for a node the programmer wrote, which is the common case and
 * the reason this is a separate call rather than something `proto_error` does:
 * an error in ordinary code should not gain a blank line explaining that it
 * came from nowhere. */
void proto_note_expansion(ProtoDiagnostics *diag, const ProtoNode *node);

/* One line of the chain of files that led here, without a caret:
 *
 *     ... used from prog.pro, line 3
 *
 * Solveig prints `... included from` the same way for the same reason, and a
 * span with a caret would be wrong here -- the interesting thing is the path,
 * not the eight characters of the directive. */
void proto_note_from(ProtoDiagnostics *diag, ProtoSpan at, const char *what);

#endif /* PROTO_DIAG_H */
