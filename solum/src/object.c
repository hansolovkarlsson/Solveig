#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "solum/object.h"
#include "solum/vm.h"

static char *dup_name(const char *name)
{
    size_t len = strlen(name);
    char *copy = malloc(len + 1);
    if (copy == NULL) {
        fprintf(stderr, "solum: out of memory\n");
        exit(1);
    }
    memcpy(copy, name, len + 1);
    return copy;
}

SolObject *sol_object_new(SolVM *vm, SolObject *proto)
{
    /* Collect before allocating, never after: the new cell is reachable from
       nothing yet, so a collection here cannot sweep it. */
    sol_gc_maybe_collect(vm);

    SolObject *obj = malloc(sizeof(SolObject));
    if (obj == NULL) {
        fprintf(stderr, "solum: out of memory\n");
        exit(1);
    }
    obj->proto = proto;
    obj->slots = NULL;
    obj->payload = 0;

    sol_gc_register(vm, &obj->gc, SOL_GC_OBJECT, sizeof(SolObject));
    return obj;
}

SolBlock *sol_block_new(SolVM *vm, const SolMethod *code, SolValue self,
                        int home_frame, uint64_t home_id)
{
    sol_gc_maybe_collect(vm);

    SolBlock *block = malloc(sizeof(SolBlock));
    if (block == NULL) {
        fprintf(stderr, "solum: out of memory\n");
        exit(1);
    }
    block->code = code;
    block->owner = code->chunk.owner;
    block->self = self;
    block->home_frame = home_frame;
    block->home_id = home_id;

    sol_gc_register(vm, &block->gc, SOL_GC_BLOCK, sizeof(SolBlock));
    return block;
}

SolSlot *sol_object_lookup(SolObject *obj, const char *name)
{
    for (SolObject *o = obj; o != NULL; o = o->proto) {
        for (SolSlot *slot = o->slots; slot != NULL; slot = slot->next) {
            if (strcmp(slot->name, name) == 0) return slot;
        }
    }
    return NULL;
}

/* Finds a slot on `obj` itself, ignoring the proto chain. */
static SolSlot *lookup_local(SolObject *obj, const char *name)
{
    for (SolSlot *slot = obj->slots; slot != NULL; slot = slot->next) {
        if (strcmp(slot->name, name) == 0) return slot;
    }
    return NULL;
}

/* A slot is owned by its object and freed with it, so it is not registered with
   the collector; cell_size counts its bytes when the object is swept. */
static SolSlot *ensure_local(SolObject *obj, const char *name)
{
    SolSlot *slot = lookup_local(obj, name);
    if (slot != NULL) return slot;

    slot = malloc(sizeof(SolSlot));
    if (slot == NULL) {
        fprintf(stderr, "solum: out of memory\n");
        exit(1);
    }
    slot->name = dup_name(name);
    slot->value = SOL_NIL_VAL;
    slot->primitive = NULL;
    slot->next = obj->slots;
    obj->slots = slot;
    return slot;
}

void sol_object_define(SolObject *obj, const char *name, SolValue value)
{
    SolSlot *slot = ensure_local(obj, name);
    slot->value = value;
    slot->primitive = NULL;
}

void sol_object_define_primitive(SolObject *obj, const char *name, SolPrimitive fn)
{
    SolSlot *slot = ensure_local(obj, name);
    slot->value = SOL_NIL_VAL;
    slot->primitive = fn;
}
