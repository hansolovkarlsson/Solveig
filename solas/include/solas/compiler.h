/* compiler.h -- Solas front end: source text in, Solum bytecode out.
 *
 * Single pass: the parser drives emission directly into the chunk, so there is
 * no AST. If constant folding or a real optimiser is ever wanted, that is the
 * decision to revisit first.
 */
#ifndef SOLAS_COMPILER_H
#define SOLAS_COMPILER_H

#include "solum/common.h"
#include "solum/bytecode.h"

/* Compiles `source` into `chunk`. Returns false and reports to stderr on error;
   `chunk` is left in an unspecified but safely freeable state. */
bool sol_compile(const char *source, SolChunk *chunk);

#endif /* SOLAS_COMPILER_H */
