/* reader.h -- source text and a dialect in, a tree out. */
#ifndef PROTO_READER_H
#define PROTO_READER_H

#include "proto/diag.h"
#include "proto/dialect.h"
#include "proto/tree.h"
#include "proto/unit.h"

/* Reads the directive header into `dialect`, then the body into a
   PROTO_NODE_SEQUENCE using it. Answers NULL if anything was reported; the
   caller checks `diag->errors` for how much.

   The dialect is an out-parameter rather than an in-parameter because a module
   declares its own: there is no ambient grammar to pass in, and a caller who
   could pass one would be a caller who could parse a file two ways. */
ProtoNode *proto_read(const ProtoSource *source, ProtoUnit *unit,
                  ProtoDialect *dialect, ProtoDiagnostics *diag);

#endif /* PROTO_READER_H */
