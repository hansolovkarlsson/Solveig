/* unit.h -- every file one compilation is made of.
 *
 * A module used to be a file. With `@use` it is a file and the dialect files
 * behind it, and all of them have to stay in memory until the last diagnostic
 * is printed: a template read from a used file keeps spans into that file, and
 * an error inside an expansion of it wants to show the line.
 *
 * The sources are held by pointer rather than by value on purpose. A span
 * carries the `PhxSource *` it belongs to, and an array of sources that grew by
 * `realloc` would move them all and leave every span in the tree pointing at
 * freed memory -- a bug that shows up only in the file that made the array
 * grow, which is to say the second one. */
#ifndef PHOENIX_UNIT_H
#define PHOENIX_UNIT_H

#include "phoenix/source.h"

typedef struct {
    PhxSource **sources;
    int count, capacity;

    char **directories;
    int directory_count, directory_capacity;
} PhxUnit;

void phx_unit_init(PhxUnit *unit);
void phx_unit_free(PhxUnit *unit);

/* Where a `@use` falls back to when the file is not beside the one using it.
   First added is first searched, which is what `-I` repeated means. */
void phx_unit_add_directory(PhxUnit *unit, const char *directory);

/* PHOENIX_PATH, colon-separated. Added after whatever `-I` gave, so a flag on
   the command line beats the environment rather than the other way round. */
void phx_unit_add_environment(PhxUnit *unit);

/* Reads and keeps the file, or answers NULL. The result outlives every call
   after it and is freed with the unit. */
const PhxSource *phx_unit_read(PhxUnit *unit, const char *path);

/* A source built in memory rather than read from disk, kept by the unit on the
   same terms as any other. The tests compile from strings; nothing else does. */
const PhxSource *phx_unit_adopt(PhxUnit *unit, const char *path,
                                const char *text);

/* The one already read under this exact path, or NULL.
 *
 * What makes a diamond harmless: two dialects that both use a third read it
 * once, so the third's declarations are not added twice and do not collide with
 * themselves. */
const PhxSource *phx_unit_loaded(const PhxUnit *unit, const char *path);

/* Where `@use "name"` written in `from` should look, in order. Answers a path
   that exists, or NULL. The caller frees. */
char *phx_unit_resolve(const PhxUnit *unit, const PhxSource *from,
                       const char *name);

#endif /* PHOENIX_UNIT_H */
