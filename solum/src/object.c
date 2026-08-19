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
    SolObject *obj = malloc(sizeof(SolObject));
    if (obj == NULL) {
        fprintf(stderr, "solum: out of memory\n");
        exit(1);
    }
    obj->proto = proto;
    obj->slots = NULL;
    obj->payload = 0;

    /* Thread onto the VM's all-objects list so a collector can find it later. */
    obj->next = vm->objects;
    vm->objects = obj;
    return obj;
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
