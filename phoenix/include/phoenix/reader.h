/* reader.h -- source text and a dialect in, a tree out. */
#ifndef PHOENIX_READER_H
#define PHOENIX_READER_H

#include "phoenix/diag.h"
#include "phoenix/dialect.h"
#include "phoenix/tree.h"

/* Reads the directive header into `dialect`, then the body into a
   PHX_NODE_SEQUENCE using it. Answers NULL if anything was reported; the
   caller checks `diag->errors` for how much.

   The dialect is an out-parameter rather than an in-parameter because a module
   declares its own: there is no ambient grammar to pass in, and a caller who
   could pass one would be a caller who could parse a file two ways. */
PhxNode *phx_read(const PhxSource *source, PhxDialect *dialect,
                  PhxDiagnostics *diag);

#endif /* PHOENIX_READER_H */
