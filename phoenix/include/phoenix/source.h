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
    const char *path;
    char *text;             /* NUL-terminated; owned */
    size_t length;
} PhxSource;

/* A region of the source text. Length may be 0, which points between two
   characters and is what an "expected X here" diagnostic wants. */
typedef struct {
    uint32_t offset;
    uint32_t length;
} PhxSpan;

#define PHX_SPAN_NONE ((PhxSpan){ 0, 0 })

bool phx_source_read(PhxSource *source, const char *path);
void phx_source_free(PhxSource *source);

/* One-based, because these are for people rather than for arithmetic. */
void phx_source_position(const PhxSource *source, uint32_t offset,
                         int *line, int *column);

/* The whole line `offset` falls on, without its newline, for the caret line of
   a diagnostic. Points into the source text and is not owned. */
const char *phx_source_line(const PhxSource *source, uint32_t offset,
                            int *length);

#endif /* PHOENIX_SOURCE_H */
