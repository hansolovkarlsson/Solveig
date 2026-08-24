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

SolCode *sol_code_new(SolVM *vm)
{
    sol_gc_maybe_collect(vm);

    SolCode *code = malloc(sizeof(SolCode));
    if (code == NULL) {
        fprintf(stderr, "solvm: out of memory\n");
        exit(1);
    }
    sol_chunk_init(&code->chunk);
    code->chunk.owner = code;

    sol_gc_register(vm, &code->gc, SOL_GC_CODE, sizeof(SolCode));
    return code;
}

/* ---- accounting ------------------------------------------------------- */

/* Bytes a cell accounts for, including anything it owns outright. An object's
   slots are its own, so they are counted here rather than tracked separately. */
/* Bytes a chunk tree accounts for -- code, lines, and the side tables, plus
   everything nested. Approximate on purpose: it drives the collection threshold,
   not any correctness property. */
static size_t chunk_size(const SolChunk *chunk)
{
    size_t size = sizeof(SolChunk);
    size += (size_t)chunk->capacity * (sizeof(uint8_t) + sizeof(int));
    size += (size_t)chunk->constants.capacity * sizeof(SolValue);
    for (int i = 0; i < chunk->names.count; i++) size += strlen(chunk->names.names[i]) + 1;
    for (int i = 0; i < chunk->methods.count; i++) {
        size += sizeof(SolMethod) + chunk_size(&chunk->methods.methods[i]->chunk);
    }
    return size;
}

static size_t cell_size(const SolGCHeader *header)
{
    if (header->type == SOL_GC_BLOCK) return sizeof(SolBlock);
    if (header->type == SOL_GC_ARRAY) {
        const SolArray *array = (const SolArray *)header;
        return sizeof(SolArray) + sizeof(SolValue) * (size_t)array->capacity;
    }
    if (header->type == SOL_GC_DICT) {
        const SolDict *dict = (const SolDict *)header;
        return sizeof(SolDict) + sizeof(SolDictEntry) * (size_t)dict->capacity;
    }
    if (header->type == SOL_GC_STRING) {
        return sizeof(SolString) + (size_t)((const SolString *)header)->length + 1;
    }
    if (header->type == SOL_GC_DELEGATE) return sizeof(SolDelegate);
    if (header->type == SOL_GC_SYMBOL) {
        return sizeof(SolSymbol) + (size_t)((const SolSymbol *)header)->length + 1;
    }
    if (header->type == SOL_GC_CODE) {
        return sizeof(SolCode) + chunk_size(&((const SolCode *)header)->chunk);
    }

    const SolObject *obj = (const SolObject *)header;
    size_t size = sizeof(SolObject);
    for (const SolSlot *slot = obj->slots; slot != NULL; slot = slot->next) {
        size += sizeof(SolSlot);       /* the name is shared, not this object's */
    }
    if (obj->index != NULL) {
        size += sizeof(SolIndexEntry) * (size_t)(obj->index_mask + 1);
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
            fprintf(stderr, "solvm: out of memory during collection\n");
            exit(1);
        }
        vm->gray = grown;
        vm->gray_capacity = capacity;
    }
    vm->gray[vm->gray_count++] = header;
}

/* A switch rather than a chain of `if (SOL_IS_...)`, and deliberately: with no
   `default`, -Wswitch makes the compiler name any value type added later that
   is not handled here.

   It was a chain once, and SOL_DICT was added without a line in it. Every other
   place a new type has to appear -- `sol_type_name`, `sol_vm_class_of`, the
   renderer, the serializer -- is a switch and all four were flagged at the
   first build. This one compiled cleanly and swept live dictionaries instead,
   which took a segfault and a stack trace to find. The check was worth having
   at the fifth site too. */
static void mark_value(SolVM *vm, SolValue value)
{
    switch (value.type) {
    case SOL_OBJ:      mark_cell(vm, (SolGCHeader *)SOL_AS_OBJ(value)); break;
    case SOL_BLOCK:    mark_cell(vm, (SolGCHeader *)SOL_AS_BLOCK(value)); break;
    case SOL_ARRAY:    mark_cell(vm, (SolGCHeader *)SOL_AS_ARRAY(value)); break;
    case SOL_DICT:     mark_cell(vm, (SolGCHeader *)SOL_AS_DICT(value)); break;
    case SOL_STRING:   mark_cell(vm, (SolGCHeader *)SOL_AS_STRING(value)); break;
    case SOL_DELEGATE: mark_cell(vm, (SolGCHeader *)SOL_AS_DELEGATE(value)); break;
    case SOL_SYMBOL:   mark_cell(vm, (SolGCHeader *)SOL_AS_SYMBOL(value)); break;
    /* Unboxed: nothing on the heap to reach. */
    case SOL_NIL: case SOL_BOOL: case SOL_INT: case SOL_FLOAT:
    case SOL_TIME: break;
    }
}

/* A chunk's constants can hold heap values, so a live code tree keeps them
   alive. Recursion is bounded by the nesting cap the verifier enforces. */
static void mark_chunk_constants(SolVM *vm, const SolChunk *chunk)
{
    for (int i = 0; i < chunk->constants.count; i++) {
        mark_value(vm, chunk->constants.values[i]);
    }
    for (int i = 0; i < chunk->methods.count; i++) {
        mark_chunk_constants(vm, &chunk->methods.methods[i]->chunk);
    }
}

/* Marks the code tree a chunk belongs to, if the collector owns it. Only safe
   for a chunk known to be live -- one a frame is executing. A chunk reached from
   a block goes through the block's own owner field instead. */
static void mark_code(SolVM *vm, const SolChunk *chunk)
{
    if (chunk != NULL && chunk->owner != NULL) {
        mark_cell(vm, (SolGCHeader *)chunk->owner);
    }
}

/* Traces one gray cell's outgoing edges. */
static void blacken(SolVM *vm, SolGCHeader *header)
{
    if (header->type == SOL_GC_BLOCK) {
        SolBlock *block = (SolBlock *)header;
        mark_value(vm, block->self);
        /* The code tree must outlive the block. Read from the block's own copy:
           the chunk itself may be caller-owned and already freed. */
        if (block->owner != NULL) mark_cell(vm, (SolGCHeader *)block->owner);
        return;
    }

    /* A string holds bytes, not values, so it has no outgoing edges at all --
       the difference from an array that made arrays the better first heap type
       with contents. Marking one is done as soon as it is reached. */
    if (header->type == SOL_GC_STRING) return;
    if (header->type == SOL_GC_SYMBOL) return;   /* characters, like a string */

    if (header->type == SOL_GC_DELEGATE) {
        const SolDelegate *delegate = (const SolDelegate *)header;
        mark_value(vm, delegate->receiver);
        mark_cell(vm, (SolGCHeader *)delegate->start);
        return;
    }

    if (header->type == SOL_GC_ARRAY) {
        /* The reason arrays came before strings: every element is an edge. */
        const SolArray *array = (const SolArray *)header;
        for (int i = 0; i < array->count; i++) mark_value(vm, array->items[i]);
        return;
    }

    if (header->type == SOL_GC_DICT) {
        /* Both halves of a live entry are edges. A tombstone holds nil in both,
           so skipping it is tidiness rather than necessity -- but an entry that
           was never used holds whatever calloc left, which is a zeroed
           SolValue, and marking that would be marking SOL_NIL. Skip anything
           not live and neither question arises. */
        const SolDict *dict = (const SolDict *)header;
        for (int i = 0; i < dict->capacity; i++) {
            if (dict->entries[i].state != SOL_DICT_LIVE) continue;
            mark_value(vm, dict->entries[i].key);
            mark_value(vm, dict->entries[i].value);
        }
        return;
    }

    if (header->type == SOL_GC_CODE) {
        mark_chunk_constants(vm, &((SolCode *)header)->chunk);
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

    /* Code a frame is executing, which may be the only reference to it. */
    for (int i = 0; i < vm->frame_count; i++) mark_code(vm, vm->frames[i].chunk);

    /* Cells held only in a C local across an allocation. */
    for (int i = 0; i < vm->temp_count; i++) mark_cell(vm, vm->temps[i]);

    mark_cell(vm, (SolGCHeader *)vm->root);
    mark_cell(vm, (SolGCHeader *)vm->integer_class);
    mark_cell(vm, (SolGCHeader *)vm->float_class);
    mark_cell(vm, (SolGCHeader *)vm->nil_class);
    mark_cell(vm, (SolGCHeader *)vm->bool_class);
    mark_cell(vm, (SolGCHeader *)vm->block_class);
    mark_cell(vm, (SolGCHeader *)vm->array_class);
    mark_cell(vm, (SolGCHeader *)vm->dict_class);
    mark_cell(vm, (SolGCHeader *)vm->error_class);
    mark_cell(vm, (SolGCHeader *)vm->time_class);
    mark_cell(vm, (SolGCHeader *)vm->random_class);
    mark_cell(vm, (SolGCHeader *)vm->string_class);
    mark_cell(vm, (SolGCHeader *)vm->object_class);
    mark_cell(vm, (SolGCHeader *)vm->symbol_class);
}

/* ---- sweeping --------------------------------------------------------- */

static void free_cell(SolGCHeader *header)
{
    if (header->type == SOL_GC_CODE) {
        sol_chunk_free(&((SolCode *)header)->chunk);
        free(header);
        return;
    }

    if (header->type == SOL_GC_ARRAY) {
        free(((SolArray *)header)->items);
        free(header);
        return;
    }

    if (header->type == SOL_GC_DICT) {
        free(((SolDict *)header)->entries);
        free(header);
        return;
    }

    if (header->type == SOL_GC_STRING) {
        free(((SolString *)header)->chars);
        free(header);
        return;
    }

    if (header->type == SOL_GC_SYMBOL) {
        free(((SolSymbol *)header)->chars);
        free(header);
        return;
    }

    if (header->type == SOL_GC_OBJECT) {
        SolObject *obj = (SolObject *)header;
        SolSlot *slot = obj->slots;
        while (slot != NULL) {
            SolSlot *next = slot->next;
            /* The name is the VM's interned copy, shared and immortal (4.3). */
            free(slot);
            slot = next;
        }
        /* The index holds the same slots and owns none of them. */
        free(obj->index);
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

/* The intern table is weak: a symbol is dropped from it the moment nothing else
   refers to it. Done after marking and before sweeping, so the table never names
   a cell the sweep is about to free. */
void sol_gc_prune_symbols(SolVM *vm)
{
    for (int i = 0; i < vm->symbol_capacity; i++) {
        SolSymbol **link = &vm->symbols[i];
        while (*link != NULL) {
            SolSymbol *symbol = *link;
            if (symbol->gc.marked) {
                link = &symbol->chain;
            } else {
                *link = symbol->chain;
                vm->symbol_count--;
            }
        }
    }
}

void sol_gc_collect(SolVM *vm)
{
    mark_roots(vm);

    while (vm->gray_count > 0) {
        blacken(vm, vm->gray[--vm->gray_count]);
    }

    sol_gc_prune_symbols(vm);
    sweep(vm);

    vm->next_gc = vm->bytes_allocated * SOL_GC_GROWTH_FACTOR;
    if (vm->next_gc < SOL_GC_INITIAL_THRESHOLD) vm->next_gc = SOL_GC_INITIAL_THRESHOLD;
}

/* The ceiling is tested here, where a collection is already decided about, and
 * it is tested *after* one rather than before.
 *
 * That is the whole difficulty of a memory limit: `bytes_allocated` before a
 * sweep counts everything the program has ever asked for and not yet had taken
 * back, most of which may be unreachable. A limit read off that figure stops a
 * program for litter rather than for what it is holding, and a loop building
 * one string at a time would trip it however small the strings were. After a
 * sweep the figure is what is live, which is the thing worth having an opinion
 * about.
 *
 * So going over is a reason to collect, and being over once that has happened
 * is a reason to stop. The current allocation still completes -- the caller
 * needs a cell to put its half-built object in -- and the program unwinds at
 * the next instruction boundary, which is a bounded overshoot rather than an
 * open one. */
void sol_gc_maybe_collect(SolVM *vm)
{
    bool over = vm->memory_limit > 0 && vm->bytes_allocated > vm->memory_limit;

    if (vm->gc_stress || vm->bytes_allocated > vm->next_gc || over) sol_gc_collect(vm);

    if (vm->memory_limit > 0 && vm->bytes_allocated > vm->memory_limit) {
        sol_vm_stop(vm, "stopped: the memory limit of %zu bytes was reached, "
                        "with %zu live", vm->memory_limit, vm->bytes_allocated);
    }
}

void sol_gc_push_temp(SolVM *vm, SolGCHeader *header)
{
    if (vm->temp_count == SOL_GC_MAX_TEMPS) {
        fprintf(stderr, "solvm: too many temporary roots\n");
        exit(1);
    }
    vm->temps[vm->temp_count++] = header;
}

void sol_gc_pop_temp(SolVM *vm)
{
    if (vm->temp_count > 0) vm->temp_count--;
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

    free(vm->symbols);
    vm->symbols = NULL;
    vm->symbol_capacity = 0;
    vm->symbol_count = 0;

    free(vm->gray);
    vm->gray = NULL;
    vm->gray_count = 0;
    vm->gray_capacity = 0;
}
