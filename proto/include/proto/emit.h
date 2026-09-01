/* emit.h -- a tree out as Solveig source, with a map back to the .pro.
 *
 * Source text rather than bytecode, and the map rather than trusting nobody
 * will need it. Both are argued in the README under "What Proto is allowed to
 * know about Solveig"; the short of it is that the generated `.sol` is an
 * artefact, and an artefact nobody can trace back to what they wrote is where a
 * language like this stops being usable by anyone but its author. */
#ifndef PROTO_EMIT_H
#define PROTO_EMIT_H

#include "proto/tree.h"

/* One generated position, and the source offset it came from. Recorded at the
   first character of every node that has a span, in generated order -- so the
   file is already sorted for a binary search over the generated side, which is
   the direction a debugger looks things up in. */
typedef struct {
    int line, column;       /* in the generated .sol, one-based */
    ProtoSpan span;           /* what it came from, and which file that is */
} ProtoMapping;

typedef struct {
    char *text;
    size_t length, capacity;

    ProtoMapping *mappings;
    int mapping_count, mapping_capacity;

    int line, column;       /* where the next character will land */
    int indent;
    bool flat;              /* measuring: never break a line */
} ProtoEmitter;

void proto_emitter_init(ProtoEmitter *emitter);
void proto_emitter_free(ProtoEmitter *emitter);

void proto_emit(ProtoEmitter *emitter, const ProtoNode *module);

bool proto_emit_write(const ProtoEmitter *emitter, const char *path);

/* The mapping covering a position in the generated file: the last one at or
   before it, since a mapping holds from where it starts until the next begins.
   NULL when the position is before the first.

   This is the direction anything downstream asks in. `solas` names a line in
   the `.sol`; a person wants the line in the `.pro`. */
const ProtoMapping *proto_emit_lookup(const ProtoEmitter *emitter,
                                  int line, int column);

/* The map as its own file. A plain text format on purpose: it has to be
   readable by `less` and diffable by `git` long before anything consumes it
   programmatically, and Source Map v3 is neither. */
bool proto_emit_map_write(const ProtoEmitter *emitter, const char *map_path,
                        const ProtoSource *source, const char *output_path);

#endif /* PROTO_EMIT_H */
