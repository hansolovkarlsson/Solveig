/* source.c -- reading a file, and turning an offset back into a place. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>


#include "phoenix/source.h"

bool phx_source_read(PhxSource *source, const char *path)
{
    source->path = phx_strndup(path, strlen(path));
    source->text = NULL;
    source->length = 0;

    FILE *file = fopen(path, "rb");
    if (file == NULL) { free(source->path); source->path = NULL; return false; }

    if (fseek(file, 0, SEEK_END) != 0) { fclose(file); goto failed; }
    long size = ftell(file);
    if (size < 0) { fclose(file); goto failed; }
    rewind(file);

    char *text = phx_alloc((size_t)size + 1);
    size_t read = fread(text, 1, (size_t)size, file);
    fclose(file);

    /* Short reads are not an error to paper over: a file that is not all there
       compiles to something that is not all there, and silently. */
    if (read != (size_t)size) { free(text); goto failed; }

    text[read] = '\0';
    source->text = text;
    source->length = read;
    return true;

failed:
    free(source->path);
    source->path = NULL;
    return false;
}

void phx_source_adopt(PhxSource *source, const char *path, const char *text)
{
    source->path = phx_strndup(path, strlen(path));
    source->length = strlen(text);
    source->text = phx_strndup(text, source->length);
}

void phx_source_free(PhxSource *source)
{
    free(source->path);
    free(source->text);
    source->path = NULL;
    source->text = NULL;
    source->length = 0;
}

void phx_span_position(PhxSpan span, int *line, int *column)
{
    if (span.source == NULL) { *line = 0; *column = 0; return; }
    phx_source_position(span.source, span.offset, line, column);
}

/* Counted from the start each time rather than from a table built up front.
 *
 * A line table is the obvious optimisation and is not worth having yet: this
 * runs once per diagnostic, and a compiler printing enough diagnostics for the
 * difference to be measurable has a bigger problem than the scan. */
void phx_source_position(const PhxSource *source, uint32_t offset,
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

const char *phx_source_line(const PhxSource *source, uint32_t offset,
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
