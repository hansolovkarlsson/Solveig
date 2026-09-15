/* reader.h -- source text and a dialect in, a tree out. */
#ifndef PARASOL_READER_H
#define PARASOL_READER_H

#include "parasol/diag.h"
#include "parasol/dialect.h"
#include "parasol/tree.h"
#include "parasol/unit.h"

/* Reads the directive header into `dialect`, then the body into a
   PARASOL_NODE_SEQUENCE using it. Answers NULL if anything was reported; the
   caller checks `diag->errors` for how much.

   The dialect is an out-parameter rather than an in-parameter because a module
   declares its own: there is no ambient grammar to pass in, and a caller who
   could pass one would be a caller who could parse a file two ways. */
ParasolNode *parasol_read(const ParasolSource *source, ParasolUnit *unit,
                  ParasolDialect *dialect, ParasolDiagnostics *diag);

#endif /* PARASOL_READER_H */
