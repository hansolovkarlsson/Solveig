/* source.h -- a file being compiled, and positions within it.
 *
 * Everything downstream refers to source by `ParasolSpan`, which is a byte offset
 * and a length and nothing else. Line and column are worked out here, on
 * demand, when a diagnostic is about to be printed.
 *
 * That direction matters. Carrying line and column on every node instead is the
 * arrangement that stops working the moment a node comes from an expansion
 * rather than from a file, because there is no line for it to have -- while an
 * offset into the text that *caused* it is a thing every node can name. */
#ifndef PARASOL_SOURCE_H
#define PARASOL_SOURCE_H

#include "parasol/common.h"

typedef struct {
    char *path;             /* owned; what a diagnostic shows */
    char *identity;         /* owned; what decides whether two are one file */
    char *text;             /* NUL-terminated; owned */
    size_t length;
} ParasolSource;

/* A region of a source text, and which text.
 *
 * The source is on the span rather than held once beside the compiler, because
 * `@use` means a module is made of several files and a tree holds nodes from
 * more than one of them. A span that only knew an offset would need a registry
 * and an id to go with it; carrying the file costs a pointer and means a
 * diagnostic never has to be told which file it is about.
 *
 * Length may be 0, which points between two characters and is what an
 * "expected X here" diagnostic wants. */
typedef struct {
    const ParasolSource *source;
    uint32_t offset;
    uint32_t length;
} ParasolSpan;

#define PARASOL_SPAN_NONE ((ParasolSpan){ NULL, 0, 0 })

/* The canonical path, for comparing one file against another. The caller
 * frees. Answers a copy of `path` when it cannot be resolved -- a source built
 * in memory, or a file that went away between the two calls.
 *
 * `path` is what somebody wrote and is what a diagnostic must show:
 * `examples/../lib/control.psol` is where they can look. This is the other
 * question, and the two were one string until 0.17.0 -- so `x.psol` and
 * `./x.psol` were two files, a diamond collided with itself, and a cycle was
 * not a cycle. Collapsing `x/../` textually would be wrong across a symlink,
 * which is why this asks the filesystem. */
char *parasol_path_identity(const char *path);

bool parasol_source_read(ParasolSource *source, const char *path);

/* For a source built in memory rather than read: the tests, and nothing else
   so far. Both strings are copied. */
void parasol_source_adopt(ParasolSource *source, const char *path, const char *text);
void parasol_source_free(ParasolSource *source);

/* A span's place, for a diagnostic. Answers 0:0 for PARASOL_SPAN_NONE, which no
   diagnostic should be reporting against and which is worth seeing if one is. */
void parasol_span_position(ParasolSpan span, int *line, int *column);

/* One-based, because these are for people rather than for arithmetic. */
void parasol_source_position(const ParasolSource *source, uint32_t offset,
                         int *line, int *column);

/* The whole line `offset` falls on, without its newline, for the caret line of
   a diagnostic. Points into the source text and is not owned. */
const char *parasol_source_line(const ParasolSource *source, uint32_t offset,
                            int *length);

#endif /* PARASOL_SOURCE_H */
