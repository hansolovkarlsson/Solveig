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

    /* Whether a sender other than the object itself may reach this slot.
       True unless `exports` has drawn a boundary and left this name out of it,
       so an object that never declares one behaves exactly as it always did and
       the dispatch loop pays a bit test. */
    bool            exported;

    struct SolSlot *next;
} SolSlot;

/* Above this many slots an object keeps an index beside the list. Below it the
   list wins: every name is an interned pointer, so a step is one comparison on
   a cache line the walk is already reading, and a hash is a multiply, a mask
   and a dependent load before the first comparison happens at all. Measured --
   see ROADMAP 3.17. */
#define SOL_INDEX_THRESHOLD 12

/* An entry carries the key beside the slot so that a probe compares without
   dereferencing the slot. That is one dependent load rather than two, and the
   two live in the same sixteen bytes, so the compare and the answer come off
   one cache line -- which is what the linked list gets for free by having its
   slots allocated together, and what a table has to be built to match. */
typedef struct SolIndexEntry {
    const char *name;
    SolSlot    *slot;
} SolIndexEntry;

struct SolObject {
    SolGCHeader gc;        /* must be first: the collector casts between them */
    SolObject *proto;      /* delegation target; NULL for the root Object */
    SolSlot   *slots;
    int64_t    payload;    /* raw storage for integer/boolean-like objects */

    /* An index over `slots`, and only over this object's own -- the proto chain
       is walked object by object as it always was.
     *
     * The list stays the object's state: it holds definition order, which
       `slots` answers with, and it is what the collector walks and frees. This
       is a lookup table beside it, built when the list gets long enough to be
       worth one, and holding the same SolSlot pointers. Open addressing on the
       interned name pointer, which is stable for the life of the VM.
     *
     * NULL until the object crosses SOL_INDEX_THRESHOLD, which most objects
       never do: a point with three slots pays nothing. */
    SolIndexEntry *index;
    int            index_mask;   /* capacity - 1; capacity is a power of two */
    int            slot_count;

    /* The object's external surface, or nil for an object that has not drawn
       one -- which is nearly all of them, and which behaves as it always did.
     *
     * An array of symbols, kept rather than only stamped onto the slots that
     * existed when it arrived, so that a name bound afterwards can be asked
     * about too. Without it `exports` would have to be the last statement of a
     * file, and putting it first would quietly make the whole API private. */
    SolValue       exports;
};

/* The boundary `obj` is under: its own if it drew one, otherwise the nearest
   prototype's, or nil where nothing in the chain drew one. Inherited because an
   object made by a prototype's constructor *is* one of them, and every piece of
   state a program holds lives on such an object rather than on the prototype. */
SolValue sol_object_boundary(const SolObject *obj);

/* Whether `name` -- interned -- is exported by the boundary `obj` is under.
   False for every name when nothing in the chain drew one, which callers check
   for first. */
bool sol_object_exports_name(const SolObject *obj, const char *name);

/* The same question asked of this object's own declaration only, ignoring what
   it inherits. */
bool sol_object_declares_name(const SolObject *obj, const char *name);

/* Draws the boundary: records `exports` and re-stamps every slot the object
   already has. */
void sol_object_set_exports(SolObject *obj, SolValue exports);

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

/* A dictionary: values kept under keys, found by hashing rather than by
 * looking at every one.
 *
 * An object is already a set of named slots, and cannot serve as this. A slot
 * name is interned in the VM's *permanent* name table -- it outlives every slot
 * that uses it and is freed only with the VM -- so a dictionary of keys read
 * from a file would leak a name per key. And slots are a linked list walked
 * linearly, so it would not even be faster than the array of pairs it replaces.
 *
 * **Keys are values.** Integers, floats, strings, symbols, booleans and nil are
 * compared by content, so two of them that look alike are the same key. Arrays,
 * blocks, objects and delegates are references compared by identity, where two
 * that look alike are two different keys -- a rule that is right for `equals`
 * and useless in a dictionary, so they are refused rather than surprising
 * somebody. It is the same line the language already draws between values and
 * references.
 *
 * Open addressing: one allocation for the entries, a tombstone where one has
 * been removed, and `used` counting live entries and tombstones together so the
 * probe never runs long. Growth rebuilds and drops the tombstones. */
typedef enum {
    SOL_DICT_EMPTY = 0,      /* never used; a probe stops here                */
    SOL_DICT_LIVE,
    SOL_DICT_GONE            /* removed; a probe passes through               */
} SolDictState;

typedef struct {
    SolValue key;
    SolValue value;
    uint8_t  state;
} SolDictEntry;

struct SolDict {
    SolGCHeader   gc;
    SolDictEntry *entries;
    int           capacity;   /* a power of two, or 0 when entries is NULL */
    int           count;      /* live entries */
    int           used;       /* live plus tombstones */
};

SolDict *sol_dict_new(SolVM *vm);

/* Whether `key` may be a key at all: true for the value types. */
bool sol_dict_key_ok(SolValue key);

/* Answers whether the key was there, and writes its value to `out` if so. */
bool sol_dict_get(const SolDict *dict, SolValue key, SolValue *out);

/* Binds `key` to `value`, replacing any previous binding. */
void sol_dict_put(SolVM *vm, SolDict *dict, SolValue key, SolValue value);

/* Removes `key`, writing what it held to `out`. False if it was not there. */
bool sol_dict_remove(SolDict *dict, SolValue key, SolValue *out);

/* The comparison `equals` makes, so that a dictionary and `equals` can never
   come to disagree about what one key being another means. */
bool sol_value_equals(SolValue a, SolValue b);

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

/* A resource an extension owns and the machine does not understand: a socket, a
 * window, a database connection, a compiled pattern.
 *
 * **The collector is the whole reason this is a cell rather than an integer.**
 * Before it, an extension handed such a thing back as a number -- so nothing
 * closed it when the program was stopped, it was not counted against
 * `--memory`, and a program could invent one and pass it back. All three go
 * away by making it a value the machine can see.
 *
 * `release` runs from `free_cell` and nowhere else, which is what gets both
 * guarantees from one line: the sweep calls `free_cell` when the cell becomes
 * unreachable, and `sol_gc_free_all` calls it for everything at shutdown
 * whatever its reachability. So a socket is closed when the program lets go of
 * it *and* when the program is taken away -- and the second is what an explicit
 * `close` could never promise, since a limit-stop does not run `ensure`
 * (COMPLETED 6.33). Sweeping is the path that matters for a program that holds
 * many in turn; teardown is the backstop.
 *
 * `handle` becomes NULL when released, so a double release is impossible and a
 * use afterwards is a refusal rather than a crash.
 *
 * `kind` is the extension's own word for what this is, used in messages and to
 * stop one extension's handle reaching another's primitive. Compared with
 * `strcmp` rather than by pointer, because two extensions are two binaries and
 * their string literals are not shared.
 *
 * `footprint` is what the resource costs where the machine cannot see it -- a
 * texture, a decoded image, a connection's buffers. Added to `cell_size`, so
 * `--memory` measures what is really held rather than the forty bytes of the
 * cell. Zero when there is nothing sensible to say, which is most of the time.
 * Without it, ROADMAP 3.7 -- a limit bounds dispatch and not work -- would
 * simply reappear here. */
struct SolForeign {
    SolGCHeader gc;        /* must be first: the collector casts between them */
    void       *handle;
    void      (*release)(void *handle);
    const char *kind;
    size_t      footprint;
};

/* Takes ownership of `handle`: from here it is the collector's to release.
   `kind` must outlive the VM, which a string literal in the extension does.
   `release` may be NULL for a resource with nothing to give back. */
SolForeign *sol_foreign_new(SolVM *vm, void *handle, void (*release)(void *),
                            const char *kind, size_t footprint);

/* The handle, if this really is a `kind` and has not been released; NULL if it
   is neither. A primitive checks with this rather than casting, which is what
   stops one extension's socket being handed to another's `close`. */
void *sol_foreign_handle(SolValue value, const char *kind);

/* Releases now rather than waiting for the collector, and answers whether there
   was anything to release. Not reachable from Solum -- there is no `close`
   message -- and here because an extension that must close in a known order
   (a child before its parent) has no other way to say so. */
bool sol_foreign_release(SolValue value);

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

/* Binds a name the caller has already interned, which every name the VM reads
   out of a chunk is. */
void sol_object_define_interned(SolVM *vm, SolObject *obj, const char *name,
                                SolValue value);

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
