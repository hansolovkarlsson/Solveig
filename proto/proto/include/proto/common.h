/* common.h -- shared basics for Proto. */
#ifndef PROTO_COMMON_H
#define PROTO_COMMON_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define PROTO_VERSION "0.17.0"

/* The Solveig language level this speaks to. Nothing checks it at build
 * time, and since Proto moved into Solveig's tree nothing checks it at test
 * time either: the parent is the version by construction. It is kept because
 * `proto --version` reports it and because a reader building against some
 * other Solveig should be told which one the output was written for.
 *
 * Proto compiles without Solveig present: it emits Solveig *source*, and
 * source is text. That is on purpose -- see "What Proto is allowed to know
 * about Solveig" in the README. */
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
