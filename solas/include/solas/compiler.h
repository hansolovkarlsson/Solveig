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

/* The same, for source that came from a file. `path` is named in errors and is
   what an `include` inside it resolves against -- an included file is found
   relative to the file including it, not to the working directory. Pass NULL
   for `path` and `sol_compile` is what you get. */
bool sol_compile_source(const char *source, const char *path, SolChunk *chunk);

/* Reads a whole file into a NUL-terminated heap buffer, or answers NULL.
   Says nothing on failure: the caller knows how it wants to report one. */
char *sol_read_file(const char *path);

#endif /* SOLAS_COMPILER_H */
