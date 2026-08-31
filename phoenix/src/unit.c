/* unit.c -- holding the files, and finding the next one. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "phoenix/unit.h"

void phx_unit_init(PhxUnit *unit)
{
    unit->sources = NULL;
    unit->count = unit->capacity = 0;
    unit->directories = NULL;
    unit->directory_count = unit->directory_capacity = 0;
}

void phx_unit_free(PhxUnit *unit)
{
    for (int i = 0; i < unit->count; i++) {
        phx_source_free(unit->sources[i]);
        free(unit->sources[i]);
    }
    free(unit->sources);
    for (int i = 0; i < unit->directory_count; i++) free(unit->directories[i]);
    free(unit->directories);
    phx_unit_init(unit);
}

void phx_unit_add_directory(PhxUnit *unit, const char *directory)
{
    if (unit->directory_count == unit->directory_capacity) {
        unit->directory_capacity = unit->directory_capacity < 8
                                 ? 8 : unit->directory_capacity * 2;
        unit->directories = phx_realloc(unit->directories,
                                        (size_t)unit->directory_capacity
                                            * sizeof *unit->directories);
    }
    unit->directories[unit->directory_count++] =
        phx_strndup(directory, strlen(directory));
}

void phx_unit_add_environment(PhxUnit *unit)
{
    const char *path = getenv("PHOENIX_PATH");
    if (path == NULL || *path == '\0') return;

    const char *start = path;
    for (;;) {
        const char *colon = strchr(start, ':');
        size_t length = colon != NULL ? (size_t)(colon - start) : strlen(start);
        if (length > 0) {
            char *directory = phx_strndup(start, length);
            phx_unit_add_directory(unit, directory);
            free(directory);
        }
        if (colon == NULL) return;
        start = colon + 1;
    }
}

const PhxSource *phx_unit_loaded(const PhxUnit *unit, const char *path)
{
    for (int i = 0; i < unit->count; i++)
        if (strcmp(unit->sources[i]->path, path) == 0) return unit->sources[i];
    return NULL;
}

const PhxSource *phx_unit_read(PhxUnit *unit, const char *path)
{
    PhxSource *source = phx_alloc(sizeof *source);
    if (!phx_source_read(source, path)) {
        free(source);
        return NULL;
    }

    if (unit->count == unit->capacity) {
        unit->capacity = unit->capacity < 8 ? 8 : unit->capacity * 2;
        unit->sources = phx_realloc(unit->sources,
                                    (size_t)unit->capacity * sizeof *unit->sources);
    }
    unit->sources[unit->count++] = source;
    return source;
}

/* Both readers end here, so a unit never holds a source it did not allocate
   and free the same way. */
static const PhxSource *keep(PhxUnit *unit, PhxSource *source)
{
    if (unit->count == unit->capacity) {
        unit->capacity = unit->capacity < 8 ? 8 : unit->capacity * 2;
        unit->sources = phx_realloc(unit->sources,
                                    (size_t)unit->capacity * sizeof *unit->sources);
    }
    unit->sources[unit->count++] = source;
    return source;
}

const PhxSource *phx_unit_adopt(PhxUnit *unit, const char *path,
                                const char *text)
{
    PhxSource *source = phx_alloc(sizeof *source);
    phx_source_adopt(source, path, text);
    return keep(unit, source);
}

static bool readable(const char *path)
{
    FILE *file = fopen(path, "rb");
    if (file == NULL) return false;
    fclose(file);
    return true;
}

static char *joined(const char *directory, size_t directory_length,
                    const char *name)
{
    size_t name_length = strlen(name);
    bool slash = directory_length > 0 &&
                 directory[directory_length - 1] != '/';

    char *path = phx_alloc(directory_length + (slash ? 1 : 0) + name_length + 1);
    memcpy(path, directory, directory_length);
    if (slash) path[directory_length] = '/';
    memcpy(path + directory_length + (slash ? 1 : 0), name, name_length + 1);
    return path;
}

/* Beside the file doing the using, then each directory in turn.
 *
 * Beside it first, and not last, because that is what a program with its
 * dialect in the same folder means and it should not be reachable only by
 * saying so on a command line. Solveig's `@include` looks in the same order for
 * the same reason. */
char *phx_unit_resolve(const PhxUnit *unit, const PhxSource *from,
                       const char *name)
{
    if (name[0] == '/') return readable(name)
                             ? phx_strndup(name, strlen(name)) : NULL;

    const char *slash = strrchr(from->path, '/');
    size_t directory_length = slash != NULL ? (size_t)(slash - from->path) : 0;
    char *beside = joined(from->path, directory_length, name);
    if (readable(beside)) return beside;
    free(beside);

    for (int i = 0; i < unit->directory_count; i++) {
        char *candidate = joined(unit->directories[i],
                                 strlen(unit->directories[i]), name);
        if (readable(candidate)) return candidate;
        free(candidate);
    }
    return NULL;
}
