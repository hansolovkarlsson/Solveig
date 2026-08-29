/* Solid: what a file put into the machine, once it has. */
#define _POSIX_C_SOURCE 200809L

#include <stdio.h>
#include <stdlib.h>

#include "solid/exports.h"
#include "solum/object.h"

/* The root's slots run newest first, so a walk straight through would report
   the last line of a file before its first. Collected, then read backwards --
   the same order `slots` answers in, and the order they were written. */
static int collect(SolSlot *from, SolSlot **into, int limit)
{
    int count = 0;
    for (SolSlot *slot = from; slot != NULL && count < limit; slot = slot->next) {
        into[count++] = slot;
    }
    return count;
}

void solid_surface_take(const SolVM *vm, SolidSurface *before)
{
    before->builtin_globals = vm->root->slot_count;
    before->classes = NULL;
    before->class_count = 0;

    int total = vm->root->slot_count;
    if (total <= 0) return;

    before->classes = malloc(sizeof *before->classes * (size_t)total);
    if (before->classes == NULL) return;      /* the globals still work */

    for (SolSlot *slot = vm->root->slots; slot != NULL; slot = slot->next) {
        if (!SOL_IS_OBJ(slot->value)) continue;
        before->classes[before->class_count].name       = slot->name;
        before->classes[before->class_count].object     = SOL_AS_OBJ(slot->value);
        before->classes[before->class_count].slot_count =
            SOL_AS_OBJ(slot->value)->slot_count;
        before->class_count++;
    }
}

void solid_surface_free(SolidSurface *before)
{
    free(before->classes);
    before->classes = NULL;
    before->class_count = 0;
}

/* ---- saying what a slot is ---------------------------------------------- */

/* A value stands in the report as a column rather than as its whole self, so a
   slot holding a large dictionary does not bury the names around it. `print` is
   where the whole of one is read. */
#define SOL_EXPORTS_VALUE_WIDTH 56

static void show_value(SolValue value)
{
    SolText text;
    sol_text_init(&text);
    sol_value_render(NULL, value, &text);

    if (text.length > SOL_EXPORTS_VALUE_WIDTH) {
        /* Backed off the cut to a byte that starts a character, so that a
           string of text is shortened rather than made invalid. A continuation
           byte is 10xxxxxx and never the first of anything. */
        int cut = SOL_EXPORTS_VALUE_WIDTH - 3;
        while (cut > 0 && (text.chars[cut] & 0xC0) == 0x80) cut--;
        fwrite(text.chars, 1, (size_t)cut, stdout);
        printf("...");
    } else {
        fwrite(text.chars, 1, (size_t)text.length, stdout);
    }
    sol_text_free(&text);
}

/* A slot holding a block is a method and its arity is worth knowing; a slot
   holding anything else answers that value, and the value is worth showing. A
   primitive has no arity to report -- `sol_object_define_primitive` records
   none, because a primitive checks `argc` itself.

   `marked` reserves the column that says which side of a boundary a name is on.
   It is asked for only when both sides are being listed, so the ordinary report
   has no empty column down the middle of it. */
static void show_slot(const SolSlot *slot, bool exported, bool marked)
{
    printf("    %-20s ", slot->name);
    if (marked) printf("%-16s", exported ? "" : "(not exported)");

    if (slot->primitive != NULL) {
        printf("a primitive");
    } else if (SOL_IS_BLOCK(slot->value)) {
        int arity = SOL_AS_BLOCK(slot->value)->code->arity;
        printf("takes %d argument%s", arity, arity == 1 ? "" : "s");
    } else {
        show_value(slot->value);
    }
    printf("\n");
}

/* One object's names, newest last. `count` is how many of its slots are the
   file's doing: all of them for a global the file bound, and only the new ones
   for a built-in class it extended. */
static void show_object(const SolObject *object, int count, bool all)
{
    SolSlot **order = malloc(sizeof *order * (size_t)(count > 0 ? count : 1));
    if (order == NULL) { printf("    (out of memory)\n"); return; }

    int found = collect(object->slots, order, count);
    bool bounded = !SOL_IS_NIL(sol_object_boundary(object));
    int hidden = 0;

    for (int i = found - 1; i >= 0; i--) {
        bool exported = !bounded || sol_object_exports_name(object, order[i]->name);
        if (!exported && !all) { hidden++; continue; }
        show_slot(order[i], exported, all && bounded);
    }
    free(order);

    if (hidden > 0) {
        printf("    -- and %d behind an `exports` boundary; `--exports=all` for those too\n",
               hidden);
    }
}

/* Whether the object measured before the run is still the one bound to that
   name -- and so still alive, since a global is a root.

   The pointer alone would not be enough to know that. A file may rebind a name
   the machine arrived with, and the object that was there is then unreachable
   and may have been collected, leaving what was recorded pointing at freed
   memory. So the name is looked up again and the two pointers compared, which
   never dereferences the old one: equal means the slot still holds it, and
   holding it is what keeps it alive. Unequal means the file replaced it, which
   is not extending it and is not this report's business.

   The built-in classes are additionally roots in their own right (`vm->root` is
   not the only thing holding `integer`), so in practice this bites only for a
   global an extension bound. It is written for the general case because the
   cost is a walk of twenty slots and the alternative is being right by luck. */
static bool still_the_same_object(const SolVM *vm, const char *name,
                                  const SolObject *object)
{
    for (SolSlot *slot = vm->root->slots; slot != NULL; slot = slot->next) {
        if (slot->name != name) continue;
        return SOL_IS_OBJ(slot->value) && SOL_AS_OBJ(slot->value) == object;
    }
    return false;
}

/* ---- the report ---------------------------------------------------------- */

void solid_surface_show(const SolVM *vm, const SolidSurface *before, bool all)
{
    int total = vm->root->slot_count;
    int bound = total - before->builtin_globals;
    bool any = false;

    if (bound > 0) {
        SolSlot **order = malloc(sizeof *order * (size_t)total);
        if (order == NULL) { printf("  (out of memory)\n"); return; }
        int found = collect(vm->root->slots, order, total);

        for (int i = bound - 1; i >= 0; i--) {
            if (i >= found) continue;
            any = true;
            if (!SOL_IS_OBJ(order[i]->value)) {
                /* A name bound to a value rather than to an object has no
                   surface of its own; the value is the whole of it. */
                printf("  %-22s ", order[i]->name);
                show_value(order[i]->value);
                printf("\n");
                continue;
            }
            printf("  %s\n", order[i]->name);
            show_object(SOL_AS_OBJ(order[i]->value),
                        SOL_AS_OBJ(order[i]->value)->slot_count, all);
        }
        free(order);
    }

    /* What was extended rather than bound. A library may do only this and bind
       nothing at all, which is why the two are asked separately.

       Backwards, because `classes` was filled by walking a list that runs
       newest first -- so this is oldest first, which is the order `globals all`
       lists the built-ins in and the order they were bound. */
    for (int c = before->class_count - 1; c >= 0; c--) {
        if (!still_the_same_object(vm, before->classes[c].name,
                                   before->classes[c].object)) {
            continue;
        }
        int added = before->classes[c].object->slot_count -
                    before->classes[c].slot_count;
        if (added <= 0) continue;
        any = true;
        printf("  %s   (extended)\n", before->classes[c].name);
        show_object(before->classes[c].object, added, all);
    }

    if (!any) printf("  (it binds nothing and extends nothing)\n");
}
