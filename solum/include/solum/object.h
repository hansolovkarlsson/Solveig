/* object.h -- objects and message dispatch.
 *
 * Solum follows the Smalltalk lineage: an object is a bag of named slots plus
 * a pointer to the object it delegates to. A class is not a separate kind of
 * thing -- `integer` is a class object living in a slot of the globals
 * namespace, and sending it `new` asks it to make an instance.
 */
#ifndef SOLUM_OBJECT_H
#define SOLUM_OBJECT_H

#include "solum/common.h"
#include "solum/bytecode.h"
#include "solum/value.h"

typedef struct SolVM SolVM;

/* A primitive is a message implemented in C rather than in Solum bytecode. */
typedef SolValue (*SolPrimitive)(SolVM *vm, SolValue self, SolValue *args, int argc);

typedef struct SolSlot {
    char           *name;
    SolValue        value;
    SolPrimitive    primitive;  /* non-NULL if this slot is a C method       */
    const SolMethod *method;    /* non-NULL if this slot is a Solum method   */
    struct SolSlot *next;
} SolSlot;

struct SolObject {
    SolObject *proto;      /* delegation target; NULL for the root Object */
    SolSlot   *slots;
    int64_t    payload;    /* raw storage for integer/boolean-like objects */
    SolObject *next;       /* all-objects list, for the future collector */
};

SolObject *sol_object_new(SolVM *vm, SolObject *proto);

/* Slot access. Lookup walks the proto chain; define always writes locally. */
SolSlot *sol_object_lookup(SolObject *obj, const char *name);
void     sol_object_define(SolObject *obj, const char *name, SolValue value);
void     sol_object_define_primitive(SolObject *obj, const char *name, SolPrimitive fn);

/* Binds a bytecode method. The object does not own `method` -- it belongs to
   the chunk that compiled it, which must outlive the binding. */
void     sol_object_define_method(SolObject *obj, const char *name, const SolMethod *method);

/* TODO: sol_object_send() -- resolve `name` on the receiver and either invoke
   the primitive or push a call frame for a bytecode method. Lives here rather
   than in vm.c so that dispatch stays next to the slot layout it depends on. */

#endif /* SOLUM_OBJECT_H */
