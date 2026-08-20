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

/* A primitive that will take any receiver: the class-side messages, and
   reflection, which is meaningful on an instance and on a class alike. */
#define SOL_ANY_RECEIVER (-1)

/* A slot holds a value and, for the built-ins, a C implementation.
 *
 * There is no separate notion of a method: a slot whose value is a block is
 * one. Sending its name runs the block with the receiver as `self`; sending the
 * name of a slot holding anything else answers that value. */
typedef struct SolSlot {
    /* The VM's interned copy, shared with every slot of the same name and
       outliving them all -- so const, and never freed with the slot (4.3). */
    const char     *name;
    SolValue        value;
    SolPrimitive    primitive;  /* non-NULL if this slot is a C method */
    /* The receiver `primitive` requires, as a SolValueType, or
       SOL_ANY_RECEIVER. A built-in class holds the messages its *instances*
       understand and answers them itself, so `array` is found to understand
       `add` -- and `prim_array_add` would then read the class object as an
       array. This is what stops it. Unused when `primitive` is NULL: a slot
       holding a block is a method, and a block checks its own arity. */
    int             receiver_type;
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
    /* The code cell owning `code`, captured here rather than read back through
       `code` when tracing. A caller-owned chunk can be freed while blocks that
       point into it are still on the heap -- calling one was always wrong, but
       the tracer must not fault merely for walking past it. NULL when the chunk
       is caller-owned. */
    SolCode         *owner;
    SolValue         self;      /* the receiver where the block was written */
    int              home_frame;
    uint64_t         home_id;
};

/* A growable array of values.
 *
 * Indices are one-based everywhere they are visible from Solum: an index is an
 * ordinal, not an offset into anything. `items` is a plain C array underneath,
 * so the translation happens at the boundary and nowhere else. */
struct SolArray {
    SolGCHeader gc;
    int         count;
    int         capacity;
    SolValue   *items;
};

SolObject *sol_object_new(SolVM *vm, SolObject *proto);
SolBlock  *sol_block_new(SolVM *vm, const SolMethod *code, SolValue self,
                         int home_frame, uint64_t home_id);

/* An empty array with room for `capacity` values, which may be zero. */
SolArray *sol_array_new(SolVM *vm, int capacity);

/* An immutable string.
 *
 * Immutable, so a string is a *value* rather than a reference: `equals` compares
 * contents, the way it does for numbers, rather than identity the way it does
 * for objects, blocks, and arrays. Nothing can mutate one, so sharing is always
 * safe.
 *
 * `chars` is NUL-terminated for the convenience of C, but `length` is what
 * counts -- the terminator is not part of the string. */
struct SolString {
    SolGCHeader gc;
    int         length;
    char       *chars;
};

/* Copies `length` bytes. The caller keeps ownership of what it passed in. */
SolString *sol_string_new(SolVM *vm, const char *chars, int length);

/* A delegating view, answered by `self:via(ancestor)`.
 *
 * Sending to one looks the message up starting at `start` rather than at the
 * receiver's own object, but runs it with `receiver` as `self`. That is the
 * whole of what an overriding method needs in order to call the version it
 * overrides: naming the ancestor directly would send to *it*, and `self` inside
 * would become the ancestor rather than staying the instance.
 *
 * The ancestor is named rather than inferred, so a method extends the object it
 * was written against however deep the receiver turns out to be -- and cannot
 * find itself again and recurse. */
struct SolDelegate {
    SolGCHeader gc;
    SolValue    receiver;   /* what `self` will be */
    SolObject  *start;      /* where the lookup begins */
};

SolDelegate *sol_delegate_new(SolVM *vm, SolValue receiver, SolObject *start);

/* An interned name.
 *
 * Two symbols spelling the same thing are the same symbol, so equality is a
 * pointer comparison rather than a walk over characters. That is the whole
 * reason for having them apart from strings: a name is compared far more often
 * than it is read.
 *
 * `chain` threads the intern table's bucket. The table holds symbols weakly --
 * being in it does not keep one alive -- or a name mentioned once would outlive
 * every use of it. */
struct SolSymbol {
    SolGCHeader gc;
    int         length;
    uint32_t    hash;
    char       *chars;
    SolSymbol  *chain;
};

/* Answers the symbol for these characters, making it only if it is new. */
SolSymbol *sol_symbol_intern(SolVM *vm, const char *chars, int length);

/* Appends, growing by doubling. Takes the VM so the growth is charged to the
   collection threshold: a backing store that grew without the collector knowing
   would never itself trigger a collection. */
void sol_array_add(SolVM *vm, SolArray *array, SolValue value);

/* Answers this VM's one copy of these characters, making it if it is new.
 *
 * Two interned names spelling the same thing are the same pointer, which is
 * what lets a send compare selectors with `==` instead of `strcmp`. Every slot
 * name is interned, and a chunk's name table is resolved through here once
 * before it runs. Immortal for the life of the VM -- see the note in vm.h. */
const char *sol_vm_intern_name(SolVM *vm, const char *chars, int length);

/* Slot access. Lookup walks the proto chain; define always writes locally.
 *
 * `sol_object_lookup` compares spelling, and is for C callers holding an
 * ordinary string literal. The dispatch loop uses the interned form below. */
SolSlot *sol_object_lookup(SolObject *obj, const char *name);

/* The same lookup, given a name already interned by this VM: the comparison is
   a pointer test rather than a walk over characters, which is the whole of 4.3.
 *
 * Passing a name that is *not* interned would silently answer NULL, so a debug
 * build asserts that it was. Nothing in a release build checks, which is why
 * the two spellings of this function have different names rather than one
 * taking a flag. */
SolSlot *sol_object_lookup_interned(SolVM *vm, SolObject *obj, const char *name);

void     sol_object_define(SolVM *vm, SolObject *obj, const char *name, SolValue value);
void     sol_object_define_primitive(SolVM *vm, SolObject *obj, const char *name,
                                     SolPrimitive fn);

/* The same, for a primitive that only an instance of `receiver_type` may
   receive. Pass a SolValueType, or SOL_ANY_RECEIVER for the plain form. */
void     sol_object_define_primitive_for(SolVM *vm, SolObject *obj, const char *name,
                                         SolPrimitive fn, int receiver_type);

/* May `receiver` be handed to this slot's primitive? True for a slot that is
   not a primitive at all, and for one that takes any receiver. */
bool     sol_slot_accepts(const SolSlot *slot, SolValue receiver);

#endif /* SOLUM_OBJECT_H */
