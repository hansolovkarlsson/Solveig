/* common.h -- shared basics for Parasol. */
#ifndef PARASOL_COMMON_H
#define PARASOL_COMMON_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define PARASOL_VERSION "0.17.0"

/* The Solveig language level this speaks to. Nothing checks it at build
 * time, and since Parasol moved into Solveig's tree nothing checks it at test
 * time either: the parent is the version by construction. It is kept because
 * `parasol --version` reports it and because a reader building against some
 * other Solveig should be told which one the output was written for.
 *
 * Parasol compiles without Solveig present: it emits Solveig *source*, and
 * source is text. That is on purpose -- see "What Parasol is allowed to know
 * about Solveig" in the README. */
#define PARASOL_SOLVEIG_MINIMUM "0.40.0"

/* Allocation that stops rather than returning NULL.
 *
 * A compiler that runs to completion or prints a diagnostic is a compiler with
 * two outcomes, and threading a third through every constructor buys nothing
 * here: there is no partial result worth salvaging and no caller who could. */
void *parasol_alloc(size_t size);
void *parasol_realloc(void *pointer, size_t size);
char *parasol_strndup(const char *chars, size_t length);

#endif /* PARASOL_COMMON_H */
