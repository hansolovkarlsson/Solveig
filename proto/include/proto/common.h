/* common.h -- shared basics for Proto. */
#ifndef PROTO_COMMON_H
#define PROTO_COMMON_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define PROTO_VERSION "0.14.0"

/* The Solveig this speaks to, checked by the Makefile's `run` and `test`
 * targets and by nothing at build time.
 *
 * Proto compiles without Solveig present: it emits Solveig *source*, and
 * source is text. That is on purpose -- see "What Proto is allowed to know
 * about Solveig" in the README. The version matters only when something is
 * about to hand a file to `solas`. */
#define PROTO_SOLVEIG_MINIMUM "0.40.0"

/* Allocation that stops rather than returning NULL.
 *
 * A compiler that runs to completion or prints a diagnostic is a compiler with
 * two outcomes, and threading a third through every constructor buys nothing
 * here: there is no partial result worth salvaging and no caller who could. */
void *proto_alloc(size_t size);
void *proto_realloc(void *pointer, size_t size);
char *proto_strndup(const char *chars, size_t length);

#endif /* PROTO_COMMON_H */
