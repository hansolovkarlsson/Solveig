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

typedef struct {
    const PhxSource *source;
    FILE *out;
    int errors;
    PhxSpan last;           /* what the previous report underlined */
} PhxDiagnostics;

void phx_diag_init(PhxDiagnostics *diag, const PhxSource *source, FILE *out);

/* Prints the message, the line it happened on, and a caret under `span`. */
void phx_error(PhxDiagnostics *diag, PhxSpan span, const char *format, ...);

/* A second span attached to the error just printed -- "declared here", and
   later "introduced by this expansion". Does not count towards `errors`. */
void phx_note(PhxDiagnostics *diag, PhxSpan span, const char *format, ...);

#endif /* PHOENIX_DIAG_H */
