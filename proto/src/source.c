/* source.c -- reading a file, and turning an offset back into a place. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "proto/source.h"

char *proto_path_identity(const char *path)
{
    char *resolved = realpath(path, NULL);
    if (resolved == NULL) return proto_strndup(path, strlen(path));

    /* Onto this allocator, so every string a ProtoSource owns is freed the one
       way. `realpath` allocates with malloc and a caller cannot tell. */
    char *identity = proto_strndup(resolved, strlen(resolved));
    free(resolved);
    return identity;
}

bool proto_source_read(ProtoSource *source, const char *path)
{
    source->path = proto_strndup(path, strlen(path));
    source->identity = proto_path_identity(path);
    source->text = NULL;
    source->length = 0;

    FILE *file = fopen(path, "rb");
    if (file == NULL) goto failed;

    if (fseek(file, 0, SEEK_END) != 0) { fclose(file); goto failed; }
    long size = ftell(file);
    if (size < 0) { fclose(file); goto failed; }
    rewind(file);

    char *text = proto_alloc((size_t)size + 1);
    size_t read = fread(text, 1, (size_t)size, file);
    fclose(file);

    /* Short reads are not an error to paper over: a file that is not all there
       compiles to something that is not all there, and silently. */
    if (read != (size_t)size) { free(text); goto failed; }

    text[read] = '\0';
    source->text = text;
    source->length = read;
    return true;

/* Every failure leaves here, and not one of them by its own `return`: the
   `fopen` path had its own copy of this and did not gain `identity` when the
   field did. One exit is what keeps the next field from being freed on one
   path and leaked on the other. */
failed:
    free(source->path);
    free(source->identity);
    source->path = NULL;
    source->identity = NULL;
    return false;
}

void proto_source_adopt(ProtoSource *source, const char *path, const char *text)
{
    source->path = proto_strndup(path, strlen(path));
    /* Nothing on disk to resolve, so a source built in memory is itself. */
    source->identity = proto_strndup(path, strlen(path));
    source->length = strlen(text);
    source->text = proto_strndup(text, source->length);
}

void proto_source_free(ProtoSource *source)
{
    free(source->path);
    free(source->identity);
    free(source->text);
    source->path = NULL;
    source->identity = NULL;
    source->text = NULL;
    source->length = 0;
}

void proto_span_position(ProtoSpan span, int *line, int *column)
{
    if (span.source == NULL) { *line = 0; *column = 0; return; }
    proto_source_position(span.source, span.offset, line, column);
}

/* Counted from the start each time rather than from a table built up front.
 *
 * A line table is the obvious optimisation and is not worth having yet: this
 * runs once per diagnostic, and a compiler printing enough diagnostics for the
 * difference to be measurable has a bigger problem than the scan. */
void proto_source_position(const ProtoSource *source, uint32_t offset,
                         int *line, int *column)
{
    if (offset > source->length) offset = (uint32_t)source->length;

    int l = 1, c = 1;
    for (uint32_t i = 0; i < offset; i++) {
        if (source->text[i] == '\n') { l++; c = 1; } else { c++; }
    }
    *line = l;
    *column = c;
}

const char *proto_source_line(const ProtoSource *source, uint32_t offset,
                            int *length)
{
    if (offset > source->length) offset = (uint32_t)source->length;

    uint32_t start = offset;
    while (start > 0 && source->text[start - 1] != '\n') start--;

    uint32_t end = offset;
    while (end < source->length && source->text[end] != '\n') end++;

    *length = (int)(end - start);
    return source->text + start;
}
