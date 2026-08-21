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

/* Directories an `@include` falls back to when the named file is not beside the
 * one including it.
 *
 * Relative-first, then the path, which is C's `"..."` rule: your own files are
 * found without ceremony, and a name you do not have locally comes from the
 * library. The cost of that order is the same as C's -- a local file can shadow
 * a library one by name -- and the benefit is that no program has to say where
 * the library lives.
 *
 * An absolute name is taken as it stands and searches nothing. */
typedef struct {
    char **directories;
    int    count;
    int    capacity;
} SolSearchPath;

void sol_search_path_init(SolSearchPath *search);

/* Copies `directory`, so the caller's string need not outlive the call.
   Order matters: the first directory holding the file wins. */
void sol_search_path_add(SolSearchPath *search, const char *directory);

/* The two a front end should add after its own -I arguments: the entries of
   `SOLUM_PATH`, colon-separated, and then the library shipped beside the
   binary, derived from `argv0` when it says where that is. */
void sol_search_path_add_defaults(SolSearchPath *search, const char *argv0);

void sol_search_path_free(SolSearchPath *search);

/* Compiles a file, falling back to `search` for an include that is not beside
   the file including it. `search` may be NULL, which is `sol_compile_source`. */
bool sol_compile_file(const char *source, const char *path,
                      const SolSearchPath *search, SolChunk *chunk);

/* Reads a whole file into a NUL-terminated heap buffer, or answers NULL.
   Says nothing on failure: the caller knows how it wants to report one. */
char *sol_read_file(const char *path);

#endif /* SOLAS_COMPILER_H */
