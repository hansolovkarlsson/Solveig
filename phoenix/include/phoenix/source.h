/* source.h -- a file being compiled, and positions within it.
 *
 * Everything downstream refers to source by `PhxSpan`, which is a byte offset
 * and a length and nothing else. Line and column are worked out here, on
 * demand, when a diagnostic is about to be printed.
 *
 * That direction matters. Carrying line and column on every node instead is the
 * arrangement that stops working the moment a node comes from an expansion
 * rather than from a file, because there is no line for it to have -- while an
 * offset into the text that *caused* it is a thing every node can name. */
#ifndef PHOENIX_SOURCE_H
#define PHOENIX_SOURCE_H

#include "phoenix/common.h"

typedef struct {
    char *path;             /* owned */
    char *text;             /* NUL-terminated; owned */
    size_t length;
} PhxSource;

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
    const PhxSource *source;
    uint32_t offset;
    uint32_t length;
} PhxSpan;

#define PHX_SPAN_NONE ((PhxSpan){ NULL, 0, 0 })

bool phx_source_read(PhxSource *source, const char *path);

/* For a source built in memory rather than read: the tests, and nothing else
   so far. Both strings are copied. */
void phx_source_adopt(PhxSource *source, const char *path, const char *text);
void phx_source_free(PhxSource *source);

/* A span's place, for a diagnostic. Answers 0:0 for PHX_SPAN_NONE, which no
   diagnostic should be reporting against and which is worth seeing if one is. */
void phx_span_position(PhxSpan span, int *line, int *column);

/* One-based, because these are for people rather than for arithmetic. */
void phx_source_position(const PhxSource *source, uint32_t offset,
                         int *line, int *column);

/* The whole line `offset` falls on, without its newline, for the caret line of
   a diagnostic. Points into the source text and is not owned. */
const char *phx_source_line(const PhxSource *source, uint32_t offset,
                            int *length);

#endif /* PHOENIX_SOURCE_H */
