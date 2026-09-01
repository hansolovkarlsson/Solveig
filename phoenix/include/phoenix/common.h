/* common.h -- shared basics for Phoenix. */
#ifndef PHOENIX_COMMON_H
#define PHOENIX_COMMON_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define PHOENIX_VERSION "0.9.0"

/* The Solveig this speaks to, checked by the Makefile's `run` and `test`
 * targets and by nothing at build time.
 *
 * Phoenix compiles without Solveig present: it emits Solveig *source*, and
 * source is text. That is on purpose -- see "What Phoenix is allowed to know
 * about Solveig" in the README. The version matters only when something is
 * about to hand a file to `solas`. */
#define PHOENIX_SOLVEIG_MINIMUM "0.40.0"

/* Allocation that stops rather than returning NULL.
 *
 * A compiler that runs to completion or prints a diagnostic is a compiler with
 * two outcomes, and threading a third through every constructor buys nothing
 * here: there is no partial result worth salvaging and no caller who could. */
void *phx_alloc(size_t size);
void *phx_realloc(void *pointer, size_t size);
char *phx_strndup(const char *chars, size_t length);

#endif /* PHOENIX_COMMON_H */
