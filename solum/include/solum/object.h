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
#include "solum/gc.h"
#include "solum/value.h"

typedef struct SolVM SolVM;

/* A primitive is a message implemented in C rather than in Solum bytecode. */
typedef SolValue (*SolPrimitive)(SolVM *vm, SolValue self, SolValue *args, int argc);

/* A slot holds a value and, for the built-ins, a C implementation.
 *
 * There is no separate notion of a method: a slot whose value is a block is
 * one. Sending its name runs the block with the receiver as `self`; sending the
 * name of a slot holding anything else answers that value. */
typedef struct SolSlot {
    char           *name;
    SolValue        value;
    SolPrimitive    primitive;  /* non-NULL if this slot is a C method */
    struct SolSlot *next;
} SolSlot;

struct SolObject {
    SolGCHeader gc;        /* must be first: the collector casts between them */
    SolObject *proto;      /* delegation target; NULL for the root Object */
    SolSlot   *slots;
    int64_t    payload;    /* raw storage for integer/boolean-like objects */
};

/* A block: unevaluated code plus the frame it was written in.
 *
 * The code is compiled exactly like a method body, so it reuses SolMethod. What
 * makes it a block is the home frame: `self` and the enclosing method's locals
 * are read through it, which is what lets `{ limit:print }` still mean the
 * right `limit` when some other method eventually runs it.
 *
 * `self` is captured when the block is written, so a block always answers the
 * receiver it was written under -- including one nested inside another block.
 * A block held in a slot is a method, and a send overrides slot 0 with its own
 * receiver, which is what lets a block be built and then installed.
 *
 * The home frame is identified by index *and* id. A frame's id is unique for
 * the life of the VM, so a block that outlives its frame is detected rather
 * than reading a slot that now belongs to someone else. */
struct SolBlock {
    SolGCHeader      gc;        /* must be first: the collector casts between them */
    const SolMethod *code;
    SolValue         self;      /* the receiver where the block was written */
    int              home_frame;
    uint64_t         home_id;
};

SolObject *sol_object_new(SolVM *vm, SolObject *proto);
SolBlock  *sol_block_new(SolVM *vm, const SolMethod *code, SolValue self,
                         int home_frame, uint64_t home_id);

/* Slot access. Lookup walks the proto chain; define always writes locally. */
SolSlot *sol_object_lookup(SolObject *obj, const char *name);
void     sol_object_define(SolObject *obj, const char *name, SolValue value);
void     sol_object_define_primitive(SolObject *obj, const char *name, SolPrimitive fn);

#endif /* SOLUM_OBJECT_H */
