/* unit.c -- holding the files, and finding the next one. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "parasol/unit.h"

void parasol_unit_init(ParasolUnit *unit)
{
    unit->sources = NULL;
    unit->count = unit->capacity = 0;
    unit->directories = NULL;
    unit->directory_count = unit->directory_capacity = 0;
}

void parasol_unit_free(ParasolUnit *unit)
{
    for (int i = 0; i < unit->count; i++) {
        parasol_source_free(unit->sources[i]);
        free(unit->sources[i]);
    }
    free(unit->sources);
    for (int i = 0; i < unit->directory_count; i++) free(unit->directories[i]);
    free(unit->directories);
    parasol_unit_init(unit);
}

void parasol_unit_add_directory(ParasolUnit *unit, const char *directory)
{
    if (unit->directory_count == unit->directory_capacity) {
        unit->directory_capacity = unit->directory_capacity < 8
                                 ? 8 : unit->directory_capacity * 2;
        unit->directories = parasol_realloc(unit->directories,
                                        (size_t)unit->directory_capacity
                                            * sizeof *unit->directories);
    }
    unit->directories[unit->directory_count++] =
        parasol_strndup(directory, strlen(directory));
}

void parasol_unit_add_environment(ParasolUnit *unit)
{
    const char *path = getenv("PARASOL_PATH");
    if (path == NULL || *path == '\0') return;

    const char *start = path;
    for (;;) {
        const char *colon = strchr(start, ':');
        size_t length = colon != NULL ? (size_t)(colon - start) : strlen(start);
        if (length > 0) {
            char *directory = parasol_strndup(start, length);
            parasol_unit_add_directory(unit, directory);
            free(directory);
        }
        if (colon == NULL) return;
        start = colon + 1;
    }
}

const ParasolSource *parasol_unit_loaded(const ParasolUnit *unit,
                                     const char *identity)
{
    for (int i = 0; i < unit->count; i++)
        if (strcmp(unit->sources[i]->identity, identity) == 0)
            return unit->sources[i];
    return NULL;
}

const ParasolSource *parasol_unit_read(ParasolUnit *unit, const char *path)
{
    ParasolSource *source = parasol_alloc(sizeof *source);
    if (!parasol_source_read(source, path)) {
        free(source);
        return NULL;
    }

    if (unit->count == unit->capacity) {
        unit->capacity = unit->capacity < 8 ? 8 : unit->capacity * 2;
        unit->sources = parasol_realloc(unit->sources,
                                    (size_t)unit->capacity * sizeof *unit->sources);
    }
    unit->sources[unit->count++] = source;
    return source;
}

/* Both readers end here, so a unit never holds a source it did not allocate
   and free the same way. */
static const ParasolSource *keep(ParasolUnit *unit, ParasolSource *source)
{
    if (unit->count == unit->capacity) {
        unit->capacity = unit->capacity < 8 ? 8 : unit->capacity * 2;
        unit->sources = parasol_realloc(unit->sources,
                                    (size_t)unit->capacity * sizeof *unit->sources);
    }
    unit->sources[unit->count++] = source;
    return source;
}

const ParasolSource *parasol_unit_adopt(ParasolUnit *unit, const char *path,
                                const char *text)
{
    ParasolSource *source = parasol_alloc(sizeof *source);
    parasol_source_adopt(source, path, text);
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

    char *path = parasol_alloc(directory_length + (slash ? 1 : 0) + name_length + 1);
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
char *parasol_unit_resolve(const ParasolUnit *unit, const ParasolSource *from,
                       const char *name)
{
    if (name[0] == '/') return readable(name)
                             ? parasol_strndup(name, strlen(name)) : NULL;

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
