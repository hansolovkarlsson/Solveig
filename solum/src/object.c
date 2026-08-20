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
        for (SolSlot *slot = o->slots; slot != NULL; slot = slot->next) {
            if (slot->name == name) return slot;
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
   the collector; cell_size counts its bytes when the object is swept. Its name
   is *not* owned: it is the VM's interned copy, shared with every other slot
   spelling the same thing, and outlives them all. */
static SolSlot *ensure_local(SolVM *vm, SolObject *obj, const char *name)
{
    SolSlot *slot = lookup_local(obj, name);
    if (slot != NULL) return slot;

    slot = malloc(sizeof(SolSlot));
    if (slot == NULL) {
        fprintf(stderr, "solvm: out of memory\n");
        exit(1);
    }
    slot->name = sol_vm_intern_name(vm, name, (int)strlen(name));
    slot->value = SOL_NIL_VAL;
    slot->primitive = NULL;
    slot->receiver_type = SOL_ANY_RECEIVER;
    slot->next = obj->slots;
    obj->slots = slot;
    return slot;
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
