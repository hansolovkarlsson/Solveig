/* gc.c -- mark and sweep.
 *
 * Roots are cheaper here than in most VMs, because of two properties of the
 * interpreter. Frame locals live *inside* the value stack -- push_frame sets
 * slots = stack_top - argc - 1 and fills the rest by pushing -- so scanning the
 * stack covers every local of every frame with no separate frame walk. And a
 * primitive's arguments are still on the stack while it runs, since the dispatch
 * loop drops them only after it returns. That leaves the value stack, the root
 * object, and the built-in classes.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "solum/gc.h"
#include "solum/object.h"
#include "solum/vm.h"

#define SOL_GC_GROWTH_FACTOR 2

/* ---- accounting ------------------------------------------------------- */

/* Bytes a cell accounts for, including anything it owns outright. An object's
   slots are its own, so they are counted here rather than tracked separately. */
static size_t cell_size(const SolGCHeader *header)
{
    if (header->type == SOL_GC_BLOCK) return sizeof(SolBlock);

    const SolObject *obj = (const SolObject *)header;
    size_t size = sizeof(SolObject);
    for (const SolSlot *slot = obj->slots; slot != NULL; slot = slot->next) {
        size += sizeof(SolSlot) + strlen(slot->name) + 1;
    }
    return size;
}

void sol_gc_register(SolVM *vm, SolGCHeader *header, SolGCType type, size_t size)
{
    header->type = type;
    header->marked = false;
    header->next = vm->heap;
    vm->heap = header;
    vm->bytes_allocated += size;
}

size_t sol_gc_live_bytes(const SolVM *vm)
{
    size_t total = 0;
    for (const SolGCHeader *h = vm->heap; h != NULL; h = h->next) total += cell_size(h);
    return total;
}

int sol_gc_live_count(const SolVM *vm)
{
    int count = 0;
    for (const SolGCHeader *h = vm->heap; h != NULL; h = h->next) count++;
    return count;
}

/* ---- marking ---------------------------------------------------------- */

/* Pushes a cell onto the gray worklist the first time it is reached. */
static void mark_cell(SolVM *vm, SolGCHeader *header)
{
    if (header == NULL || header->marked) return;
    header->marked = true;

    if (vm->gray_count + 1 > vm->gray_capacity) {
        int capacity = vm->gray_capacity < 32 ? 32 : vm->gray_capacity * 2;
        SolGCHeader **grown = realloc(vm->gray, sizeof(SolGCHeader *) * (size_t)capacity);
        if (grown == NULL) {
            /* The worklist is the collector's own memory, not the mutator's.
               Failing to grow it would mean losing track of a reachable cell,
               so there is nothing safe to do but stop. */
            fprintf(stderr, "solum: out of memory during collection\n");
            exit(1);
        }
        vm->gray = grown;
        vm->gray_capacity = capacity;
    }
    vm->gray[vm->gray_count++] = header;
}

static void mark_value(SolVM *vm, SolValue value)
{
    if (SOL_IS_OBJ(value))        mark_cell(vm, (SolGCHeader *)SOL_AS_OBJ(value));
    else if (SOL_IS_BLOCK(value)) mark_cell(vm, (SolGCHeader *)SOL_AS_BLOCK(value));
}

/* Traces one gray cell's outgoing edges. The whole object graph is these three:
   an object's proto and its slots' values, and a block's captured self. */
static void blacken(SolVM *vm, SolGCHeader *header)
{
    if (header->type == SOL_GC_BLOCK) {
        mark_value(vm, ((SolBlock *)header)->self);
        return;
    }

    SolObject *obj = (SolObject *)header;
    mark_cell(vm, (SolGCHeader *)obj->proto);
    for (SolSlot *slot = obj->slots; slot != NULL; slot = slot->next) {
        mark_value(vm, slot->value);
    }
}

static void mark_roots(SolVM *vm)
{
    /* The value stack, which is also every frame's locals. */
    for (SolValue *v = vm->stack; v < vm->stack_top; v++) mark_value(vm, *v);

    mark_cell(vm, (SolGCHeader *)vm->root);
    mark_cell(vm, (SolGCHeader *)vm->integer_class);
    mark_cell(vm, (SolGCHeader *)vm->float_class);
    mark_cell(vm, (SolGCHeader *)vm->nil_class);
    mark_cell(vm, (SolGCHeader *)vm->bool_class);
    mark_cell(vm, (SolGCHeader *)vm->block_class);
}

/* ---- sweeping --------------------------------------------------------- */

static void free_cell(SolGCHeader *header)
{
    if (header->type == SOL_GC_OBJECT) {
        SolObject *obj = (SolObject *)header;
        SolSlot *slot = obj->slots;
        while (slot != NULL) {
            SolSlot *next = slot->next;
            free(slot->name);
            free(slot);
            slot = next;
        }
    }
    free(header);
}

static void sweep(SolVM *vm)
{
    SolGCHeader **link = &vm->heap;
    size_t live = 0;

    while (*link != NULL) {
        SolGCHeader *header = *link;
        if (header->marked) {
            header->marked = false;         /* clear for the next cycle */
            live += cell_size(header);
            link = &header->next;
        } else {
            *link = header->next;
            free_cell(header);
        }
    }
    vm->bytes_allocated = live;
}

/* ---- the collector ---------------------------------------------------- */

void sol_gc_collect(SolVM *vm)
{
    mark_roots(vm);

    while (vm->gray_count > 0) {
        blacken(vm, vm->gray[--vm->gray_count]);
    }

    sweep(vm);

    vm->next_gc = vm->bytes_allocated * SOL_GC_GROWTH_FACTOR;
    if (vm->next_gc < SOL_GC_INITIAL_THRESHOLD) vm->next_gc = SOL_GC_INITIAL_THRESHOLD;
}

void sol_gc_maybe_collect(SolVM *vm)
{
    if (vm->gc_stress || vm->bytes_allocated > vm->next_gc) sol_gc_collect(vm);
}

void sol_gc_free_all(SolVM *vm)
{
    SolGCHeader *header = vm->heap;
    while (header != NULL) {
        SolGCHeader *next = header->next;
        free_cell(header);
        header = next;
    }
    vm->heap = NULL;
    vm->bytes_allocated = 0;

    free(vm->gray);
    vm->gray = NULL;
    vm->gray_count = 0;
    vm->gray_capacity = 0;
}
