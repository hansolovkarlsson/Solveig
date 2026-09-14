/* unit.h -- every file one compilation is made of.
 *
 * A module used to be a file. With `@use` it is a file and the dialect files
 * behind it, and all of them have to stay in memory until the last diagnostic
 * is printed: a template read from a used file keeps spans into that file, and
 * an error inside an expansion of it wants to show the line.
 *
 * The sources are held by pointer rather than by value on purpose. A span
 * carries the `ParasolSource *` it belongs to, and an array of sources that grew by
 * `realloc` would move them all and leave every span in the tree pointing at
 * freed memory -- a bug that shows up only in the file that made the array
 * grow, which is to say the second one. */
#ifndef PARASOL_UNIT_H
#define PARASOL_UNIT_H

#include "parasol/source.h"

typedef struct {
    ParasolSource **sources;
    int count, capacity;

    char **directories;
    int directory_count, directory_capacity;
} ParasolUnit;

void parasol_unit_init(ParasolUnit *unit);
void parasol_unit_free(ParasolUnit *unit);

/* Where a `@use` falls back to when the file is not beside the one using it.
   First added is first searched, which is what `-I` repeated means. */
void parasol_unit_add_directory(ParasolUnit *unit, const char *directory);

/* PARASOL_PATH, colon-separated. Added after whatever `-I` gave, so a flag on
   the command line beats the environment rather than the other way round. */
void parasol_unit_add_environment(ParasolUnit *unit);

/* Reads and keeps the file, or answers NULL. The result outlives every call
   after it and is freed with the unit. */
const ParasolSource *parasol_unit_read(ParasolUnit *unit, const char *path);

/* A source built in memory rather than read from disk, kept by the unit on the
   same terms as any other. The tests compile from strings; nothing else does. */
const ParasolSource *parasol_unit_adopt(ParasolUnit *unit, const char *path,
                                const char *text);

/* The one already read with this identity, or NULL. Takes what
 * `parasol_path_identity` answers, not the path somebody wrote.
 *
 * What makes a diamond harmless: two dialects that both use a third read it
 * once, so the third's declarations are not added twice and do not collide with
 * themselves. It compared path strings until 0.17.0, so two arms spelling the
 * third differently defeated it and the file collided with itself. */
const ParasolSource *parasol_unit_loaded(const ParasolUnit *unit,
                                     const char *identity);

/* Where `@use "name"` written in `from` should look, in order. Answers a path
   that exists, or NULL. The caller frees. */
char *parasol_unit_resolve(const ParasolUnit *unit, const ParasolSource *from,
                       const char *name);

#endif /* PARASOL_UNIT_H */
