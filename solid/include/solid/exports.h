/* exports.h -- what a compiled file puts into the machine, and what may be
 * sent to it.
 *
 * A different question from stepping, answered from the same place: only
 * something holding the root object can ask it. Globals are slots on an object
 * with no name in the language, so `slots` cannot reach them and neither can
 * `perform` (2.10 in ROADMAP.md) -- which means a program in `programs/` could
 * not have been this tool, however much it would have belonged there beside
 * `disasm.sol`. The debugger holds the root directly, so here it is answerable,
 * and that is the whole reason this lives under `solid/`.
 *
 * The method is to load and then look, rather than to read the bytecode:
 *
 *   - A `.so` has no bytecode to read. Its surface exists only after
 *     `sol_extension_init` has run, and both file kinds end in the same place
 *     -- slots on the root object -- so one mechanism reads both.
 *   - A `.sob` need not bind a global at all. `lib/text.sob` hangs `asUtf8` on
 *     `integer` and binds nothing, so a reader of OP_SET_GLOBAL would print
 *     nothing for it and be wrong. Every built-in class is measured before the
 *     run and again after, which catches that.
 *
 * The cost is that the file *runs*, with whatever it does on the way. That is
 * what solid does to a file in every other mode too, and `--exports` says so.
 */
#ifndef SOLID_EXPORTS_H
#define SOLID_EXPORTS_H

#include "solum/vm.h"

/* What the machine held before anything was done to it, so that afterwards the
   difference is the command line's doing. Taken before the extensions load as
   well as before the chunk runs, so one report covers both halves. */
typedef struct {
    int builtin_globals;          /* the run of root slots that was already there */

    /* Every global holding an object, and how many slots it had. A library that
       extends `integer` rather than binding a name shows up as a difference
       here and nowhere else. */
    struct SolidClassBefore {
        const char *name;
        SolObject  *object;
        int         slot_count;
    } *classes;
    int class_count;
} SolidSurface;

void solid_surface_take(const SolVM *vm, SolidSurface *before);
void solid_surface_free(SolidSurface *before);

/* Prints what appeared since `before` was taken. `all` includes the names an
   `exports` boundary keeps private, which are otherwise counted and not
   listed -- the boundary is the answer to the question being asked, so honouring
   it is the default. */
void solid_surface_show(const SolVM *vm, const SolidSurface *before, bool all);

#endif /* SOLID_EXPORTS_H */
