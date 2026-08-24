#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "solum/object.h"
#include "solum/vm.h"

/* ---- the name table ---------------------------------------------------
 *
 * One copy of every selector and slot name, so two names that spell the same
 * thing are one pointer and comparing them is comparing addresses. Open
 * addressing with linear probing; entries are never removed, so a probe stops
 * at the first empty bucket.
 *
 * The symbol table below does the same job for `'foo`, and does it weakly. The
 * difference is what holds the two: a symbol is a value a program can drop,
 * while a name is pointed at by slots and by chunks that have no way to
 * announce that they are done with it. So these are immortal for the VM. */
static void name_table_grow(SolVM *vm)
{
    int capacity = vm->name_capacity < 128 ? 128 : vm->name_capacity * 2;
    char **names = calloc((size_t)capacity, sizeof *names);
    if (names == NULL) {
        fprintf(stderr, "solvm: out of memory\n");
        exit(1);
    }

    for (int i = 0; i < vm->name_capacity; i++) {
        char *name = vm->names[i];
        if (name == NULL) continue;
        uint32_t hash = sol_hash_bytes(name, (int)strlen(name));
        int at = (int)(hash & (uint32_t)(capacity - 1));
        while (names[at] != NULL) at = (at + 1) & (capacity - 1);
        names[at] = name;
    }

    free(vm->names);
    vm->names = names;
    vm->name_capacity = capacity;
}

const char *sol_vm_intern_name(SolVM *vm, const char *chars, int length)
{
    if (vm->name_capacity == 0 || (vm->name_count + 1) * 4 > vm->name_capacity * 3) {
        name_table_grow(vm);
    }

    uint32_t hash = sol_hash_bytes(chars, length);
    int at = (int)(hash & (uint32_t)(vm->name_capacity - 1));
    for (;;) {
        char *found = vm->names[at];
        if (found == NULL) break;
        if (strlen(found) == (size_t)length &&
            memcmp(found, chars, (size_t)length) == 0) {
            return found;                   /* the one that already exists */
        }
        at = (at + 1) & (vm->name_capacity - 1);
    }

    char *copy = malloc((size_t)length + 1);
    if (copy == NULL) {
        fprintf(stderr, "solvm: out of memory\n");
        exit(1);
    }
    memcpy(copy, chars, (size_t)length);
    copy[length] = '\0';

    vm->names[at] = copy;
    vm->name_count++;
    return copy;
}

void sol_vm_free_names(SolVM *vm)
{
    for (int i = 0; i < vm->name_capacity; i++) free(vm->names[i]);
    free(vm->names);
    vm->names = NULL;
    vm->name_capacity = 0;
    vm->name_count = 0;
}

SolObject *sol_object_new(SolVM *vm, SolObject *proto)
{
    /* Collect before allocating, never after: the new cell is reachable from
       nothing yet, so a collection here cannot sweep it. */
    sol_gc_maybe_collect(vm);

    SolObject *obj = malloc(sizeof(SolObject));
    if (obj == NULL) {
        fprintf(stderr, "solvm: out of memory\n");
        exit(1);
    }
    obj->proto = proto;
    obj->slots = NULL;
    obj->payload = 0;
    obj->index = NULL;
    obj->index_mask = 0;
    obj->slot_count = 0;

    sol_gc_register(vm, &obj->gc, SOL_GC_OBJECT, sizeof(SolObject));
    return obj;
}

SolBlock *sol_block_new(SolVM *vm, const SolMethod *code, SolValue self,
                        int home_frame, uint64_t home_id)
{
    sol_gc_maybe_collect(vm);

    SolBlock *block = malloc(sizeof(SolBlock));
    if (block == NULL) {
        fprintf(stderr, "solvm: out of memory\n");
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

SolArray *sol_array_new(SolVM *vm, int capacity)
{
    sol_gc_maybe_collect(vm);

    SolArray *array = malloc(sizeof(SolArray));
    if (array == NULL) {
        fprintf(stderr, "solvm: out of memory\n");
        exit(1);
    }
    array->count = 0;
    array->capacity = capacity;
    array->items = NULL;

    if (capacity > 0) {
        array->items = malloc(sizeof(SolValue) * (size_t)capacity);
        if (array->items == NULL) {
            fprintf(stderr, "solvm: out of memory\n");
            exit(1);
        }
    }

    sol_gc_register(vm, &array->gc, SOL_GC_ARRAY,
                    sizeof(SolArray) + sizeof(SolValue) * (size_t)capacity);
    return array;
}

SolString *sol_string_new(SolVM *vm, const char *chars, int length)
{
    sol_gc_maybe_collect(vm);

    SolString *string = malloc(sizeof(SolString));
    char *copy = malloc((size_t)length + 1);
    if (string == NULL || copy == NULL) {
        fprintf(stderr, "solvm: out of memory\n");
        exit(1);
    }
    memcpy(copy, chars, (size_t)length);
    copy[length] = '\0';

    string->length = length;
    string->chars = copy;

    sol_gc_register(vm, &string->gc, SOL_GC_STRING,
                    sizeof(SolString) + (size_t)length + 1);
    return string;
}

/* FNV-1a. Any decent spread will do; symbols are compared by pointer once
   interned, so the hash only has to find the bucket. */
uint32_t sol_hash_bytes(const char *chars, int length)
{
    uint32_t hash = 2166136261u;
    for (int i = 0; i < length; i++) {
        hash ^= (uint8_t)chars[i];
        hash *= 16777619u;
    }
    return hash;
}

/* ---- dictionaries ------------------------------------------------------ *
 *
 * See object.h for why an object could not serve as one, and for why keys are
 * values rather than anything at all.
 */

bool sol_value_equals(SolValue a, SolValue b)
{
    if (a.type != b.type) return false;

    switch (a.type) {
    case SOL_NIL:      return true;
    case SOL_BOOL:     return SOL_AS_BOOL(a) == SOL_AS_BOOL(b);
    case SOL_INT:      return SOL_AS_INT(a) == SOL_AS_INT(b);
    case SOL_FLOAT:    return SOL_AS_FLOAT(a) == SOL_AS_FLOAT(b);
    case SOL_BLOCK:    return SOL_AS_BLOCK(a) == SOL_AS_BLOCK(b);
    case SOL_ARRAY:    return SOL_AS_ARRAY(a) == SOL_AS_ARRAY(b);
    case SOL_DELEGATE: return SOL_AS_DELEGATE(a) == SOL_AS_DELEGATE(b);
    case SOL_SYMBOL:   return SOL_AS_SYMBOL(a) == SOL_AS_SYMBOL(b);
    case SOL_OBJ:      return SOL_AS_OBJ(a) == SOL_AS_OBJ(b);
    case SOL_DICT:     return SOL_AS_DICT(a) == SOL_AS_DICT(b);
    /* A point in time is a value: two of the same instant are the same date,
       and the nanoseconds are exact, so this is an integer comparison. */
    case SOL_TIME:     return SOL_AS_TIME(a) == SOL_AS_TIME(b);
    case SOL_STRING: {
        const SolString *x = SOL_AS_STRING(a);
        const SolString *y = SOL_AS_STRING(b);
        return x->length == y->length &&
               memcmp(x->chars, y->chars, (size_t)x->length) == 0;
    }
    }
    return false;
}

bool sol_dict_key_ok(SolValue key)
{
    switch (key.type) {
    case SOL_NIL: case SOL_BOOL: case SOL_INT:
    case SOL_FLOAT: case SOL_STRING: case SOL_SYMBOL:
    case SOL_TIME:                      /* a value, so a key like any other */
        return true;
    case SOL_BLOCK: case SOL_ARRAY: case SOL_OBJ:
    case SOL_DELEGATE: case SOL_DICT:
        return false;
    }
    return false;
}

static uint32_t mix64(uint64_t x)
{
    x ^= x >> 33;
    x *= 0xff51afd7ed558ccdULL;
    x ^= x >> 33;
    x *= 0xc4ceb9fe1a85ec53ULL;
    x ^= x >> 33;
    return (uint32_t)x;
}

/* The type goes into the hash because `#1` and `1.0` are different keys --
   `equals` says so -- and would otherwise land in the same bucket for no
   reason. */
static uint32_t hash_key(SolValue key)
{
    switch (key.type) {
    case SOL_NIL:  return 0x9e3779b9u;
    case SOL_BOOL: return SOL_AS_BOOL(key) ? 0x85ebca6bu : 0xc2b2ae35u;
    case SOL_INT:  return mix64((uint64_t)SOL_AS_INT(key)) ^ 0x01u;
    case SOL_FLOAT: {
        double d = SOL_AS_FLOAT(key);
        /* -0.0 equals 0.0, so it has to hash as 0.0 or the two would be one key
           by `equals` and two by the table. `nan` is left alone: it equals
           nothing, itself included, so a nan key can be stored and never found
           again -- which is IEEE showing through rather than a decision here. */
        if (d == 0.0) d = 0.0;
        uint64_t bits;
        memcpy(&bits, &d, sizeof bits);
        return mix64(bits) ^ 0x02u;
    }
    case SOL_STRING: {
        const SolString *s = SOL_AS_STRING(key);
        return sol_hash_bytes(s->chars, s->length) ^ 0x03u;
    }
    /* Interned, so the address is the name and hashing it is hashing the name
       -- the same reason `equals` compares symbols by pointer. */
    case SOL_SYMBOL: return mix64((uint64_t)(uintptr_t)SOL_AS_SYMBOL(key)) ^ 0x04u;
    case SOL_TIME:   return mix64((uint64_t)SOL_AS_TIME(key)) ^ 0x05u;
    default: return 0;
    }
}

/* The entry `key` belongs in: the one holding it, or the first place to put it.
   Tombstones are probed through, and the first one seen is remembered so an
   insert reuses it rather than growing the table for nothing. */
static SolDictEntry *find_entry(SolDictEntry *entries, int capacity, SolValue key)
{
    uint32_t index = hash_key(key) & (uint32_t)(capacity - 1);
    SolDictEntry *tombstone = NULL;

    for (;;) {
        SolDictEntry *entry = &entries[index];

        if (entry->state == SOL_DICT_EMPTY) {
            return tombstone != NULL ? tombstone : entry;
        }
        if (entry->state == SOL_DICT_GONE) {
            if (tombstone == NULL) tombstone = entry;
        } else if (sol_value_equals(entry->key, key)) {
            return entry;
        }
        index = (index + 1) & (uint32_t)(capacity - 1);
    }
}

static void grow(SolVM *vm, SolDict *dict)
{
    int capacity = dict->capacity < 8 ? 8 : dict->capacity * 2;

    SolDictEntry *entries = calloc((size_t)capacity, sizeof(SolDictEntry));
    if (entries == NULL) {
        fprintf(stderr, "solvm: out of memory\n");
        exit(1);
    }

    /* Rebuilding drops the tombstones, which is why `used` can fall here. */
    int count = 0;
    for (int i = 0; i < dict->capacity; i++) {
        SolDictEntry *old = &dict->entries[i];
        if (old->state != SOL_DICT_LIVE) continue;

        SolDictEntry *entry = find_entry(entries, capacity, old->key);
        entry->key = old->key;
        entry->value = old->value;
        entry->state = SOL_DICT_LIVE;
        count++;
    }

    /* Charge the growth the way `sol_array_add` does, so a dictionary that
       grows large enough eventually triggers a collection on its own account.
       calloc and free rather than a heap allocation, so nothing can be
       collected in the middle of the rebuild. */
    vm->bytes_allocated += sizeof(SolDictEntry) * (size_t)(capacity - dict->capacity);

    free(dict->entries);
    dict->entries = entries;
    dict->capacity = capacity;
    dict->count = count;
    dict->used = count;
}

SolDict *sol_dict_new(SolVM *vm)
{
    sol_gc_maybe_collect(vm);

    SolDict *dict = malloc(sizeof(SolDict));
    if (dict == NULL) {
        fprintf(stderr, "solvm: out of memory\n");
        exit(1);
    }
    dict->entries = NULL;
    dict->capacity = 0;
    dict->count = 0;
    dict->used = 0;

    sol_gc_register(vm, &dict->gc, SOL_GC_DICT, sizeof(SolDict));
    return dict;
}

bool sol_dict_get(const SolDict *dict, SolValue key, SolValue *out)
{
    if (dict->count == 0) return false;

    SolDictEntry *entry = find_entry(dict->entries, dict->capacity, key);
    if (entry->state != SOL_DICT_LIVE) return false;

    *out = entry->value;
    return true;
}

void sol_dict_put(SolVM *vm, SolDict *dict, SolValue key, SolValue value)
{
    /* Three quarters full counting tombstones, so a table full of them is
       rebuilt rather than probed through forever. */
    if (dict->used + 1 > dict->capacity - dict->capacity / 4) grow(vm, dict);

    SolDictEntry *entry = find_entry(dict->entries, dict->capacity, key);
    if (entry->state != SOL_DICT_LIVE) {
        dict->count++;
        if (entry->state == SOL_DICT_EMPTY) dict->used++;   /* not reusing one */
    }
    entry->key = key;
    entry->value = value;
    entry->state = SOL_DICT_LIVE;
}

bool sol_dict_remove(SolDict *dict, SolValue key, SolValue *out)
{
    if (dict->count == 0) return false;

    SolDictEntry *entry = find_entry(dict->entries, dict->capacity, key);
    if (entry->state != SOL_DICT_LIVE) return false;

    *out = entry->value;
    /* A tombstone rather than an empty: a key that probed past this one on the
       way in has to be found on the way out. `used` stays put, so the table is
       rebuilt once the tombstones crowd it. */
    entry->state = SOL_DICT_GONE;
    entry->key = SOL_NIL_VAL;
    entry->value = SOL_NIL_VAL;
    dict->count--;
    return true;
}

static void symbol_table_grow(SolVM *vm)
{
    int capacity = vm->symbol_capacity < 64 ? 64 : vm->symbol_capacity * 2;
    SolSymbol **buckets = calloc((size_t)capacity, sizeof(SolSymbol *));
    if (buckets == NULL) {
        fprintf(stderr, "solvm: out of memory\n");
        exit(1);
    }
    for (int i = 0; i < vm->symbol_capacity; i++) {
        SolSymbol *symbol = vm->symbols[i];
        while (symbol != NULL) {
            SolSymbol *next = symbol->chain;
            int slot = (int)(symbol->hash & (uint32_t)(capacity - 1));
            symbol->chain = buckets[slot];
            buckets[slot] = symbol;
            symbol = next;
        }
    }
    free(vm->symbols);
    vm->symbols = buckets;
    vm->symbol_capacity = capacity;
}

SolSymbol *sol_symbol_intern(SolVM *vm, const char *chars, int length)
{
    uint32_t hash = sol_hash_bytes(chars, length);

    if (vm->symbol_capacity > 0) {
        int slot = (int)(hash & (uint32_t)(vm->symbol_capacity - 1));
        for (SolSymbol *s = vm->symbols[slot]; s != NULL; s = s->chain) {
            if (s->hash == hash && s->length == length &&
                memcmp(s->chars, chars, (size_t)length) == 0) {
                return s;                       /* the one that already exists */
            }
        }
    }

    sol_gc_maybe_collect(vm);

    SolSymbol *symbol = malloc(sizeof(SolSymbol));
    char *copy = malloc((size_t)length + 1);
    if (symbol == NULL || copy == NULL) {
        fprintf(stderr, "solvm: out of memory\n");
        exit(1);
    }
    memcpy(copy, chars, (size_t)length);
    copy[length] = '\0';

    symbol->length = length;
    symbol->hash = hash;
    symbol->chars = copy;
    symbol->chain = NULL;

    sol_gc_register(vm, &symbol->gc, SOL_GC_SYMBOL,
                    sizeof(SolSymbol) + (size_t)length + 1);

    /* Collecting above may have emptied buckets, so the table is sized after. */
    if (vm->symbol_count + 1 > vm->symbol_capacity - vm->symbol_capacity / 4) {
        symbol_table_grow(vm);
    }
    int slot = (int)(hash & (uint32_t)(vm->symbol_capacity - 1));
    symbol->chain = vm->symbols[slot];
    vm->symbols[slot] = symbol;
    vm->symbol_count++;
    return symbol;
}

SolDelegate *sol_delegate_new(SolVM *vm, SolValue receiver, SolObject *start)
{
    sol_gc_maybe_collect(vm);

    SolDelegate *delegate = malloc(sizeof(SolDelegate));
    if (delegate == NULL) {
        fprintf(stderr, "solvm: out of memory\n");
        exit(1);
    }
    delegate->receiver = receiver;
    delegate->start = start;

    sol_gc_register(vm, &delegate->gc, SOL_GC_DELEGATE, sizeof(SolDelegate));
    return delegate;
}

void sol_array_add(SolVM *vm, SolArray *array, SolValue value)
{
    if (array->capacity < array->count + 1) {
        int capacity = array->capacity < 8 ? 8 : array->capacity * 2;
        SolValue *grown = realloc(array->items, sizeof(SolValue) * (size_t)capacity);
        if (grown == NULL) {
            fprintf(stderr, "solvm: out of memory\n");
            exit(1);
        }
        /* Charge the growth, so an array that grows large enough eventually
           triggers a collection on its own account. Plain realloc rather than a
           heap allocation, so nothing can be collected here. */
        vm->bytes_allocated += sizeof(SolValue) * (size_t)(capacity - array->capacity);
        array->items = grown;
        array->capacity = capacity;
    }
    array->items[array->count++] = value;
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

/* A name is an interned pointer, so the pointer *is* the key. Mixing is still
   needed: the low bits of a malloc'd address carry no information -- every one
   of them is aligned the same way -- so using the address raw would leave three
   quarters of the table empty.
 *
   Two shifts and an xor, and not something stronger. splitmix64's finaliser was
   the first thing here and it is two multiplies; it measured *slower* on every
   benchmark, because what this costs is one dependent load and the arithmetic
   before it is on the critical path of every lookup in the language. Spreading
   the keys better bought fewer probes than the mixing cost -- 1.38 probes a
   lookup over a real program, which is close enough to one. */
static inline size_t name_hash(const char *name)
{
    uintptr_t h = (uintptr_t)name;
    return (size_t)((h >> 4) ^ (h >> 11));
}

/* Open addressing with linear probing, at two seats a slot, so a probe run is
   short and there is always an empty seat to stop at.
 *
   The name is compared before the slot is touched, which is the difference
   between this and the version that stored slot pointers alone: that one had to
   follow the pointer to read `slot->name`, three dependent loads to the list's
   one, and it cost a shallow send 30%. The linked list is not slow for a short
   chain -- an object's slots are allocated together, so the walk reads memory
   the prefetcher has already fetched. A table has to be built to match that,
   and this is what it takes: the key beside the answer, in the same sixteen
   bytes, so one cache line settles both.
 *
   No deletion, because a slot is never removed from an object -- redefining a
   name finds the slot and overwrites its value, and the only thing that ends a
   slot's life is the object being swept. That is what makes this a table and
   not a hash map: there are no tombstones to reason about. */
static SolSlot *index_find(SolObject *obj, const char *name)
{
    size_t i = name_hash(name) & (size_t)obj->index_mask;
    for (;;) {
        const SolIndexEntry *entry = &obj->index[i];
        if (entry->name == name) return entry->slot;
        if (entry->name == NULL) return NULL;
        i = (i + 1) & (size_t)obj->index_mask;
    }
}

/* The caller keeps the table at least twice the size of what it holds, so there
   is always an empty seat and this always stops -- and `index_find` relies on
   the same thing, since an empty seat is what tells it a name is not there.
 *
   The bound is here rather than trusted, because the failure mode of a full
   table is not a wrong answer but a spin: breaking the growth rule deliberately
   to check this test would catch it hung the suite instead, which is a worse
   thing to leave possible than the bug it was standing in for. */
static void index_put(SolObject *obj, SolSlot *slot)
{
    size_t i = name_hash(slot->name) & (size_t)obj->index_mask;
    for (int seats = obj->index_mask + 1; seats > 0; seats--) {
        if (obj->index[i].name == NULL) {
            obj->index[i].name = slot->name;
            obj->index[i].slot = slot;
            return;
        }
        i = (i + 1) & (size_t)obj->index_mask;
    }
    assert(false && "the index filled, which the growth rule should prevent");
}

/* Build or grow the table, then fill it from the list. Rebuilding from the list
   rather than rehashing in place keeps one copy of the truth: if the two ever
   disagree the list is right, and the table is discarded and made again. */
static void index_rebuild(SolObject *obj)
{
    int capacity = 16;
    while (capacity < obj->slot_count * 2) capacity *= 2;

    SolIndexEntry *table = calloc((size_t)capacity, sizeof(SolIndexEntry));
    if (table == NULL) {
        /* The list is still correct and still complete, so a failure here costs
           speed and nothing else. */
        return;
    }

    free(obj->index);
    obj->index = table;
    obj->index_mask = capacity - 1;
    for (SolSlot *slot = obj->slots; slot != NULL; slot = slot->next) {
        index_put(obj, slot);
    }
}

SolSlot *sol_object_lookup_interned(SolVM *vm, SolObject *obj, const char *name)
{
    /* Every slot name went through the table, so a name that did not is one
       this can never match -- a bug at the call site rather than a miss, and a
       silent one, since the answer would simply be NULL.
     *
     * Checking costs a hash of the name, which is the whole expense this
     * function exists to avoid, so it is compiled in only when asked for:
     * build with -DSOLUM_CHECK_INTERNED. That is the same bargain as
     * SOLUM_GC_STRESS -- a check too expensive to leave on, run deliberately
     * rather than never. */
#ifdef SOLUM_CHECK_INTERNED
    assert(name == sol_vm_intern_name(vm, name, (int)strlen(name)));
#endif
    (void)vm;

    for (SolObject *o = obj; o != NULL; o = o->proto) {
        if (o->index != NULL) {
            SolSlot *slot = index_find(o, name);
            if (slot != NULL) return slot;
            continue;
        }
        for (SolSlot *slot = o->slots; slot != NULL; slot = slot->next) {
            if (slot->name == name) return slot;
        }
    }
    return NULL;
}

/* A slot is owned by its object and freed with it, so it is not registered with
   the collector; cell_size counts its bytes when the object is swept. Its name
   is *not* owned: it is the VM's interned copy, shared with every other slot
   spelling the same thing, and outlives them all. */
/* The name must already be interned. Every assignment the VM runs comes through
   here, and interning is a hash of the string -- paid on a name that is already
   a pointer into the table, on the hot path, to learn nothing. The callers that
   hold a C literal go through `ensure_local` below and pay it once. */
static SolSlot *ensure_local_interned(SolVM *vm, SolObject *obj, const char *name)
{
    (void)vm;

    SolSlot *slot = obj->index != NULL ? index_find(obj, name) : NULL;
    if (slot == NULL && obj->index == NULL) {
        for (SolSlot *s = obj->slots; s != NULL; s = s->next) {
            if (s->name == name) { slot = s; break; }
        }
    }
    if (slot != NULL) return slot;

    slot = malloc(sizeof(SolSlot));
    if (slot == NULL) {
        fprintf(stderr, "solvm: out of memory\n");
        exit(1);
    }
    slot->name = name;
    slot->value = SOL_NIL_VAL;
    slot->primitive = NULL;
    slot->receiver_type = SOL_ANY_RECEIVER;
    slot->next = obj->slots;
    obj->slots = slot;
    obj->slot_count++;

    /* Crossing the threshold builds the table; after that it is kept in step,
       and grown when it would otherwise fill past half. */
    if (obj->index == NULL) {
        if (obj->slot_count > SOL_INDEX_THRESHOLD) index_rebuild(obj);
    } else if (obj->slot_count * 2 > obj->index_mask + 1) {
        index_rebuild(obj);
    } else {
        index_put(obj, slot);
    }
    return slot;
}

static SolSlot *ensure_local(SolVM *vm, SolObject *obj, const char *name)
{
    return ensure_local_interned(
        vm, obj, sol_vm_intern_name(vm, name, (int)strlen(name)));
}

/* The same as sol_object_define, for a caller that already holds the interned
   name -- which the VM always does, since it reads names out of a chunk's table
   and those were interned when the chunk was loaded. */
void sol_object_define_interned(SolVM *vm, SolObject *obj, const char *name,
                                SolValue value)
{
    SolSlot *slot = ensure_local_interned(vm, obj, name);
    slot->value = value;
    slot->primitive = NULL;
    slot->receiver_type = SOL_ANY_RECEIVER;
}

void sol_object_define(SolVM *vm, SolObject *obj, const char *name, SolValue value)
{
    SolSlot *slot = ensure_local(vm, obj, name);
    slot->value = value;
    slot->primitive = NULL;
    slot->receiver_type = SOL_ANY_RECEIVER;
}

void sol_object_define_primitive(SolVM *vm, SolObject *obj, const char *name,
                                 SolPrimitive fn)
{
    sol_object_define_primitive_for(vm, obj, name, fn, SOL_ANY_RECEIVER);
}

void sol_object_define_primitive_for(SolVM *vm, SolObject *obj, const char *name,
                                     SolPrimitive fn, int receiver_type)
{
    SolSlot *slot = ensure_local(vm, obj, name);
    slot->value = SOL_NIL_VAL;
    slot->primitive = fn;
    slot->receiver_type = receiver_type;
}

bool sol_slot_accepts(const SolSlot *slot, SolValue receiver)
{
    if (slot->primitive == NULL) return true;
    if (slot->receiver_type == SOL_ANY_RECEIVER) return true;
    return (int)receiver.type == slot->receiver_type;
}
