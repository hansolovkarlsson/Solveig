/* diag.h -- diagnostics, reported against a span of the source the programmer
 * actually wrote.
 *
 * This exists in the first commit rather than a later one because the failure
 * it prevents is the one that kills syntax-extension systems: a programmer
 * writes surface syntax, and the compiler complains about something further
 * down that they have never seen. Every error here takes a `PhxSpan`, and there
 * is no overload that does not, so the compiler cannot grow a diagnostic that
 * has forgotten where it came from. */
#ifndef PHOENIX_DIAG_H
#define PHOENIX_DIAG_H

#include <stdio.h>

#include "phoenix/source.h"
#include "phoenix/tree.h"

typedef struct {
    const PhxSource *source;
    FILE *out;
    int errors;
    PhxSpan last;           /* what the previous report underlined */
} PhxDiagnostics;

void phx_diag_init(PhxDiagnostics *diag, const PhxSource *source, FILE *out);

/* Prints the message, the line it happened on, and a caret under `span`. */
void phx_error(PhxDiagnostics *diag, PhxSpan span, const char *format, ...);

/* A second span attached to the error just printed -- "declared here". Does not
   count towards `errors`. */
void phx_note(PhxDiagnostics *diag, PhxSpan span, const char *format, ...);

/* The chain of forms a node was expanded out of, innermost first.
 *
 * Prints nothing for a node the programmer wrote, which is the common case and
 * the reason this is a separate call rather than something `phx_error` does:
 * an error in ordinary code should not gain a blank line explaining that it
 * came from nowhere. */
void phx_note_expansion(PhxDiagnostics *diag, const PhxNode *node);

#endif /* PHOENIX_DIAG_H */
