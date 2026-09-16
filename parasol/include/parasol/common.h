/* common.h -- shared basics for Parasol. */
#ifndef PARASOL_COMMON_H
#define PARASOL_COMMON_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/* PARASOL_VERSION is the tree's, since 0.47.0: the Makefile writes it into
 * the generated config.h from SOLUM_VERSION, beside PARASOL_LIB_DIR, so this
 * file still includes nothing of Solveig's. Until then Parasol carried its own
 * number, 0.17.0 at the last, and a PARASOL_SOLVEIG_MINIMUM naming the Solveig
 * its output was written for; the parent is that version by construction now.
 *
 * Parasol compiles without Solveig present: it emits Solveig *source*, and
 * source is text. That is on purpose -- see "What Parasol is allowed to know
 * about Solveig" in the README. */
#include "config.h"

/* Allocation that stops rather than returning NULL.
 *
 * A compiler that runs to completion or prints a diagnostic is a compiler with
 * two outcomes, and threading a third through every constructor buys nothing
 * here: there is no partial result worth salvaging and no caller who could. */
void *parasol_alloc(size_t size);
void *parasol_realloc(void *pointer, size_t size);
char *parasol_strndup(const char *chars, size_t length);

#endif /* PARASOL_COMMON_H */
