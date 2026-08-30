#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "solum/bytecode.h"

void sol_chunk_init(SolChunk *chunk)
{
    chunk->count = 0;
    chunk->capacity = 0;
    chunk->code = NULL;
    chunk->lines = NULL;
    chunk->file_ids = NULL;
    chunk->writing_file = 0;
    chunk->files.count = 0;
    chunk->files.capacity = 0;
    chunk->files.names = NULL;
    chunk->slot_names.count = 0;
    chunk->slot_names.capacity = 0;
    chunk->slot_names.names = NULL;
    sol_value_array_init(&chunk->constants);
    chunk->names.count = 0;
    chunk->names.capacity = 0;
    chunk->names.names = NULL;
    chunk->methods.count = 0;
    chunk->methods.capacity = 0;
    chunk->methods.methods = NULL;
    chunk->interned = NULL;
    chunk->global_slots = NULL;
    chunk->interned_for = 0;
    chunk->name_index.slots = NULL;
    chunk->name_index.capacity = 0;
    chunk->name_index.count = 0;
    chunk->constant_index.slots = NULL;
    chunk->constant_index.capacity = 0;
    chunk->constant_index.count = 0;
    chunk->owner = NULL;          /* standalone until handed to the collector */
    chunk->slot_count = 0;
}

void sol_chunk_set_owner(SolChunk *chunk, SolCode *owner)
{
    chunk->owner = owner;
    for (int i = 0; i < chunk->methods.count; i++) {
        sol_chunk_set_owner(&chunk->methods.methods[i]->chunk, owner);
    }
}

SolMethod *sol_method_new(const char *name, int length, int arity)
{
    SolMethod *method = malloc(sizeof(SolMethod));
    if (method == NULL) {
        fprintf(stderr, "solvm: out of memory\n");
        exit(1);
    }
    method->name = malloc((size_t)length + 1);
    if (method->name == NULL) {
        fprintf(stderr, "solvm: out of memory\n");
        exit(1);
    }
    memcpy(method->name, name, (size_t)length);
    method->name[length] = '\0';

    method->arity = arity;
    method->slot_count = arity + 1;      /* self, plus one slot per parameter */
    method->is_block = false;
    method->captures = false;
    sol_chunk_init(&method->chunk);
    return method;
}

void sol_method_free(SolMethod *method)
{
    if (method == NULL) return;
    sol_chunk_free(&method->chunk);
    free(method->name);
    free(method);
}

int sol_chunk_add_method(SolChunk *chunk, SolMethod *method)
{
    SolMethodArray *methods = &chunk->methods;

    if (methods->capacity < methods->count + 1) {
        int capacity = methods->capacity < 4 ? 4 : methods->capacity * 2;
        methods->methods = realloc(methods->methods, sizeof(SolMethod *) * capacity);
        if (methods->methods == NULL) {
            fprintf(stderr, "solvm: out of memory\n");
            exit(1);
        }
        methods->capacity = capacity;
    }
    /* The subtree is complete when it is added, so this propagates ownership
       correctly for both the compiler, which adds a method after compiling its
       body, and the loader, which adds it before reading one. Doing it here
       rather than in a pass afterwards means a caller cannot forget. */
    sol_chunk_set_owner(&method->chunk, chunk->owner);

    methods->methods[methods->count] = method;
    return methods->count++;
}

void sol_chunk_write(SolChunk *chunk, uint8_t byte, int line)
{
    if (chunk->capacity < chunk->count + 1) {
        int capacity = chunk->capacity < 8 ? 8 : chunk->capacity * 2;
        chunk->code = realloc(chunk->code, sizeof(uint8_t) * capacity);
        chunk->lines = realloc(chunk->lines, sizeof(int) * capacity);
        chunk->file_ids = realloc(chunk->file_ids, sizeof(int) * capacity);
        if (chunk->code == NULL || chunk->lines == NULL || chunk->file_ids == NULL) {
            fprintf(stderr, "solvm: out of memory\n");
            exit(1);
        }
        chunk->capacity = capacity;
    }
    chunk->code[chunk->count] = byte;
    chunk->lines[chunk->count] = line;
    chunk->file_ids[chunk->count] = chunk->writing_file;
    chunk->count++;
}

/* Are these the same constant? Compared by bits rather than by `==`, which
   would fold -0.0 into 0.0 -- two constants that print differently -- and would
   never fold a NaN onto itself. Only immutable scalars ever reach the pool, so
   identical bits really do mean an interchangeable constant. */
static bool same_constant(SolValue a, SolValue b)
{
    if (a.type != b.type) return false;
    switch (a.type) {
    case SOL_NIL:   return true;
    case SOL_BOOL:  return SOL_AS_BOOL(a) == SOL_AS_BOOL(b);
    case SOL_INT:   return SOL_AS_INT(a) == SOL_AS_INT(b);
    case SOL_FLOAT: {
        double x = SOL_AS_FLOAT(a), y = SOL_AS_FLOAT(b);
        return memcmp(&x, &y, sizeof x) == 0;
    }
    default:        return false;   /* heap values are never pooled */
    }
}

/* ---- the side tables' hash index ---------------------------------------
 *
 * Interning used to scan. That was invisible at 256 entries and quadratic once
 * 4.2 allowed 65536, so filling a table now goes through here. Nothing about
 * the result changes -- the same entry lands at the same position -- only how
 * long it takes to find out that it is already there.
 */

/* Hash of a constant, over the same bits `same_constant` compares. Two values
   that compare equal must hash alike, so this hashes the type and the payload
   and never the padding between them. */
static uint32_t hash_constant(SolValue value)
{
    uint8_t type = (uint8_t)value.type;
    uint32_t hash = sol_hash_bytes((const char *)&type, 1);

    switch (value.type) {
    case SOL_NIL:   return hash;
    case SOL_BOOL: { uint8_t b = SOL_AS_BOOL(value) ? 1 : 0;
                     return hash ^ sol_hash_bytes((const char *)&b, 1); }
    case SOL_INT:  { int64_t i = SOL_AS_INT(value);
                     return hash ^ sol_hash_bytes((const char *)&i, (int)sizeof i); }
    case SOL_FLOAT:{ double d = SOL_AS_FLOAT(value);
                     return hash ^ sol_hash_bytes((const char *)&d, (int)sizeof d); }
    default:        return hash;      /* heap values are never pooled */
    }
}

/* Below this many entries a linear scan wins outright: it touches one cache
   line, needs no hash, and costs no memory. Most chunks -- a method body, a
   block, a REPL line -- never grow past it, so most chunks never build an index
   at all. Only the ones large enough for the scan to hurt pay for one. */
#define SOL_INDEX_THRESHOLD 16

static void index_free(SolIndex *index)
{
    free(index->slots);
    index->slots = NULL;
    index->capacity = 0;
    index->count = 0;
}

/* Kept under three quarters full, which is where linear probing stays short. */
static bool index_is_full(const SolIndex *index)
{
    return index->capacity == 0 || (index->count + 1) * 4 > index->capacity * 3;
}

static void index_reserve(SolIndex *index, int wanted)
{
    int capacity = index->capacity < 32 ? 32 : index->capacity * 2;
    while (capacity * 3 < (wanted + 1) * 4) capacity *= 2;

    free(index->slots);
    index->slots = malloc((size_t)capacity * sizeof *index->slots);
    if (index->slots == NULL) {
        fprintf(stderr, "solum: out of memory\n");
        exit(1);
    }
    for (int i = 0; i < capacity; i++) index->slots[i] = -1;
    index->capacity = capacity;
    index->count = 0;
}

/* Puts `entry` in a bucket, unless something equal is already recorded -- the
   loader may append a repeat, and the first position is the one interning
   should answer with. */
static void name_index_put(SolChunk *chunk, int entry)
{
    SolIndex *index = &chunk->name_index;
    const char *name = chunk->names.names[entry];

    uint32_t hash = sol_hash_bytes(name, (int)strlen(name));
    int at = (int)(hash & (uint32_t)(index->capacity - 1));
    while (index->slots[at] >= 0) {
        if (strcmp(chunk->names.names[index->slots[at]], name) == 0) return;
        at = (at + 1) & (index->capacity - 1);
    }
    index->slots[at] = entry;
    index->count++;
}

static void constant_index_put(SolChunk *chunk, int entry)
{
    SolIndex *index = &chunk->constant_index;
    SolValue value = chunk->constants.values[entry];

    uint32_t hash = hash_constant(value);
    int at = (int)(hash & (uint32_t)(index->capacity - 1));
    while (index->slots[at] >= 0) {
        if (same_constant(chunk->constants.values[index->slots[at]], value)) return;
        at = (at + 1) & (index->capacity - 1);
    }
    index->slots[at] = entry;
    index->count++;
}

/* Records a newly appended entry. Builds the index on the way past the
   threshold, and grows it when it fills; both rebuild from the side table
   rather than from the old buckets, so there is one way an entry gets in. */
static void index_insert_name(SolChunk *chunk, int entry)
{
    SolIndex *index = &chunk->name_index;

    if (index->capacity == 0) {
        if (chunk->names.count <= SOL_INDEX_THRESHOLD) return;   /* still scanning */
        index_reserve(index, chunk->names.count);
        for (int i = 0; i < chunk->names.count; i++) name_index_put(chunk, i);
        return;
    }
    if (index_is_full(index)) {
        index_reserve(index, chunk->names.count);
        for (int i = 0; i < chunk->names.count; i++) name_index_put(chunk, i);
        return;
    }
    name_index_put(chunk, entry);
}

static void index_insert_constant(SolChunk *chunk, int entry)
{
    SolIndex *index = &chunk->constant_index;

    if (index->capacity == 0) {
        if (chunk->constants.count <= SOL_INDEX_THRESHOLD) return;
        index_reserve(index, chunk->constants.count);
        for (int i = 0; i < chunk->constants.count; i++) constant_index_put(chunk, i);
        return;
    }
    if (index_is_full(index)) {
        index_reserve(index, chunk->constants.count);
        for (int i = 0; i < chunk->constants.count; i++) constant_index_put(chunk, i);
        return;
    }
    constant_index_put(chunk, entry);
}

/* Where this name already lives, or -1. Scans while the table is small, which
   is the same answer the index gives and the same answer the linear scan this
   replaced always gave. */
static int index_find_name(const SolChunk *chunk, const char *name, int length)
{
    const SolIndex *index = &chunk->name_index;

    if (index->capacity == 0) {
        for (int i = 0; i < chunk->names.count; i++) {
            if (strlen(chunk->names.names[i]) == (size_t)length &&
                memcmp(chunk->names.names[i], name, (size_t)length) == 0) {
                return i;
            }
        }
        return -1;
    }

    uint32_t hash = sol_hash_bytes(name, length);
    int at = (int)(hash & (uint32_t)(index->capacity - 1));
    for (;;) {
        int found = index->slots[at];
        if (found < 0) return -1;
        const char *candidate = chunk->names.names[found];
        if (strlen(candidate) == (size_t)length &&
            memcmp(candidate, name, (size_t)length) == 0) {
            return found;
        }
        at = (at + 1) & (index->capacity - 1);
    }
}

static int index_find_constant(const SolChunk *chunk, SolValue value)
{
    const SolIndex *index = &chunk->constant_index;

    if (index->capacity == 0) {
        for (int i = 0; i < chunk->constants.count; i++) {
            if (same_constant(chunk->constants.values[i], value)) return i;
        }
        return -1;
    }

    uint32_t hash = hash_constant(value);
    int at = (int)(hash & (uint32_t)(index->capacity - 1));
    for (;;) {
        int found = index->slots[at];
        if (found < 0) return -1;
        if (same_constant(chunk->constants.values[found], value)) return found;
        at = (at + 1) & (index->capacity - 1);
    }
}

int sol_chunk_add_constant(SolChunk *chunk, SolValue value)
{
    int found = index_find_constant(chunk, value);
    if (found >= 0) return found;
    return sol_chunk_append_constant(chunk, value);
}

int sol_chunk_append_constant(SolChunk *chunk, SolValue value)
{
    int at = sol_value_array_write(&chunk->constants, value);
    index_insert_constant(chunk, at);
    return at;
}

/* The file bytes written from here on came from. A chunk holds a handful of
   these -- one for a method body, a few for a script that includes -- so this
   scans rather than carrying an index of its own. */
int sol_chunk_file(SolChunk *chunk, const char *path)
{
    if (path == NULL) path = "";

    SolNameArray *files = &chunk->files;
    for (int i = 0; i < files->count; i++) {
        if (strcmp(files->names[i], path) == 0) return i;
    }

    if (files->capacity < files->count + 1) {
        int capacity = files->capacity < 4 ? 4 : files->capacity * 2;
        files->names = realloc(files->names, sizeof(char *) * capacity);
        if (files->names == NULL) {
            fprintf(stderr, "solvm: out of memory\n");
            exit(1);
        }
        files->capacity = capacity;
    }

    size_t length = strlen(path);
    char *copy = malloc(length + 1);
    if (copy == NULL) {
        fprintf(stderr, "solvm: out of memory\n");
        exit(1);
    }
    memcpy(copy, path, length + 1);
    files->names[files->count] = copy;
    return files->count++;
}

/* The path a byte came from, or "" when nothing said. */
const char *sol_chunk_file_of(const SolChunk *chunk, int offset)
{
    if (chunk->file_ids == NULL || offset < 0 || offset >= chunk->count) return "";
    int id = chunk->file_ids[offset];
    if (id < 0 || id >= chunk->files.count) return "";
    return chunk->files.names[id];
}

void sol_chunk_name_slot(SolChunk *chunk, int index, const char *name, int length)
{
    SolNameArray *slots = &chunk->slot_names;
    if (index < 0 || index > UINT8_MAX) return;   /* a slot index is a u8 */

    while (slots->count <= index) {
        if (slots->capacity < slots->count + 1) {
            int capacity = slots->capacity < 8 ? 8 : slots->capacity * 2;
            slots->names = realloc(slots->names, sizeof(char *) * capacity);
            if (slots->names == NULL) {
                fprintf(stderr, "solvm: out of memory\n");
                exit(1);
            }
            slots->capacity = capacity;
        }
        /* A slot nobody named -- the receiver, or a gap -- still takes a place,
           so that index N of this table is slot N and not the Nth named one. */
        char *blank = malloc(1);
        if (blank == NULL) { fprintf(stderr, "solvm: out of memory\n"); exit(1); }
        blank[0] = '\0';
        slots->names[slots->count++] = blank;
    }

    char *copy = malloc((size_t)length + 1);
    if (copy == NULL) { fprintf(stderr, "solvm: out of memory\n"); exit(1); }
    memcpy(copy, name, (size_t)length);
    copy[length] = '\0';

    free(slots->names[index]);
    slots->names[index] = copy;
}

const char *sol_chunk_slot_name(const SolChunk *chunk, int index)
{
    if (index < 0 || index >= chunk->slot_names.count) return "";
    return chunk->slot_names.names[index];
}

int sol_chunk_add_name(SolChunk *chunk, const char *name, int length)
{
    int found = index_find_name(chunk, name, length);
    if (found >= 0) return found;
    return sol_chunk_append_name(chunk, name, length);
}

int sol_chunk_append_name(SolChunk *chunk, const char *name, int length)
{
    SolNameArray *names = &chunk->names;

    if (names->capacity < names->count + 1) {
        int capacity = names->capacity < 8 ? 8 : names->capacity * 2;
        names->names = realloc(names->names, sizeof(char *) * capacity);
        if (names->names == NULL) {
            fprintf(stderr, "solvm: out of memory\n");
            exit(1);
        }
        names->capacity = capacity;
    }

    char *copy = malloc((size_t)length + 1);
    if (copy == NULL) {
        fprintf(stderr, "solvm: out of memory\n");
        exit(1);
    }
    memcpy(copy, name, (size_t)length);
    copy[length] = '\0';

    names->names[names->count] = copy;
    int at = names->count++;
    index_insert_name(chunk, at);
    return at;
}

const char *sol_chunk_name(const SolChunk *chunk, int index)
{
    if (index < 0 || index >= chunk->names.count) return "?";
    return chunk->names.names[index];
}

void sol_chunk_free(SolChunk *chunk)
{
    free(chunk->code);
    free(chunk->lines);
    free(chunk->file_ids);
    for (int i = 0; i < chunk->files.count; i++) free(chunk->files.names[i]);
    free(chunk->files.names);
    for (int i = 0; i < chunk->slot_names.count; i++) free(chunk->slot_names.names[i]);
    free(chunk->slot_names.names);
    sol_value_array_free(&chunk->constants);
    for (int i = 0; i < chunk->names.count; i++) free(chunk->names.names[i]);
    free(chunk->names.names);
    index_free(&chunk->name_index);
    index_free(&chunk->constant_index);
    free(chunk->interned);        /* the names themselves belong to the VM */
    free(chunk->global_slots);    /* and the slots belong to the root object */
    /* Recursive: a method owns its chunk, which may own further methods. */
    for (int i = 0; i < chunk->methods.count; i++) sol_method_free(chunk->methods.methods[i]);
    free(chunk->methods.methods);
    sol_chunk_init(chunk);
}

/* The one place instruction lengths are written down. Everything that walks
   bytecode -- the compiler deciding whether a block touches its home, the
   verifier marking instruction boundaries, the disassembler, the tests --
   asks here, so none of them can drift apart from the executor. */
int sol_op_length(uint8_t op)
{
    switch (op) {
    case OP_NIL:
    case OP_POP:
    case OP_RETURN:
    case OP_HALT:
        return 1;
    case OP_LOCAL:
    case OP_SET_LOCAL:
        return 2;
    case OP_CONST:
    case OP_GLOBAL:
    case OP_SET_GLOBAL:
    case OP_BLOCK:
    case OP_SET_SLOT:
    case OP_STRING:
    case OP_SYMBOL:
    case OP_OUTER:
    case OP_SET_OUTER:
    case OP_JUMP:
    case OP_EXIT_IF_FALSE:
    case OP_CHECK_BOOL:
    case OP_LOOP:
        return 3;
    case OP_SEND:
        return 4;
    case OP_JUMP_IF_FALSE:
        return 5;
    default:
        return 0;                          /* not an opcode we emit */
    }
}

/* ---- disassembler ---------------------------------------------------- */

static int simple_instruction(const char *name, int offset)
{
    printf("%s\n", name);
    return offset + 1;
}

/* Renders one pooled constant, with no VM to render it against.
 *
 * That is not a limitation here: a constant is only ever an immutable scalar --
 * `check_constants` refuses objects, blocks, arrays, strings, delegates and
 * symbols outright -- so there is never a receiver to ask. Roadmap 5.2 recorded
 * this as a gap for a while, on the strength of the function's old name rather
 * than what it is handed. `print` the message goes through `prim_print`, which
 * does have a VM and does send `asString`. */
static void print_constant(SolValue value)
{
    SolText text;
    sol_text_init(&text);
    sol_value_render(NULL, value, &text);
    fwrite(text.chars, 1, (size_t)text.length, stdout);
    sol_text_free(&text);
}

static int constant_instruction(const char *name, const SolChunk *chunk, int offset)
{
    uint16_t index = sol_read_u16(&chunk->code[offset + 1]);
    printf("%-8s %4d '", name, index);
    print_constant(chunk->constants.values[index]);
    printf("'\n");
    return offset + 3;
}

static int name_instruction(const char *name, const SolChunk *chunk, int offset)
{
    uint16_t index = sol_read_u16(&chunk->code[offset + 1]);
    printf("%-8s %4d '%s'\n", name, index, sol_chunk_name(chunk, index));
    return offset + 3;
}

/* A u16 index that names a nested method rather than a name or a constant. */
static int method_instruction(const char *name, const SolChunk *chunk, int offset)
{
    printf("%-8s %4d\n", name, sol_read_u16(&chunk->code[offset + 1]));
    return offset + 3;
}

static int slot_instruction(const char *name, const SolChunk *chunk, int offset)
{
    printf("%-8s %4d\n", name, chunk->code[offset + 1]);
    return offset + 2;
}

static int depth_instruction(const char *name, const SolChunk *chunk, int offset)
{
    printf("%-8s %4d ^%d\n", name, chunk->code[offset + 2], chunk->code[offset + 1]);
    return offset + 3;
}

static int send_instruction(const char *name, const SolChunk *chunk, int offset)
{
    uint16_t index = sol_read_u16(&chunk->code[offset + 1]);
    uint8_t  argc  = chunk->code[offset + 3];
    printf("%-8s %4d '%s' (%d args)\n", name, index,
           sol_chunk_name(chunk, index), argc);
    return offset + 4;
}

/* Prints the absolute target as well as the offset -- the offset alone is
   almost unreadable when checking that a branch lands where it should. */
static int jump_instruction(const SolChunk *chunk, const char *name, int offset)
{
    uint8_t op = chunk->code[offset];
    int length = sol_op_length(op);
    uint16_t jump = sol_read_u16(&chunk->code[offset + 1]);
    int target = (op == OP_LOOP) ? offset + length - jump : offset + length + jump;

    printf("%-8s %4d -> %d", name, jump, target);
    if (op == OP_JUMP_IF_FALSE) {
        printf(" (%s)", sol_chunk_name(chunk, sol_read_u16(&chunk->code[offset + 3])));
    }
    printf("\n");
    return offset + length;
}

int sol_chunk_disassemble_instruction(const SolChunk *chunk, int offset)
{
    printf("%04d ", offset);
    if (offset > 0 && chunk->lines[offset] == chunk->lines[offset - 1]) {
        printf("   | ");
    } else {
        printf("%4d ", chunk->lines[offset]);
    }

    uint8_t instruction = chunk->code[offset];
    switch (instruction) {
    case OP_CONST:  return constant_instruction("CONST", chunk, offset);
    case OP_NIL:    return simple_instruction("NIL", offset);
    case OP_GLOBAL: return name_instruction("GLOBAL", chunk, offset);
    case OP_SET_GLOBAL: return name_instruction("SETGLOB", chunk, offset);
    case OP_LOCAL:  return slot_instruction("LOCAL", chunk, offset);
    case OP_SET_LOCAL: return slot_instruction("SETLOCL", chunk, offset);
    case OP_OUTER:  return depth_instruction("OUTER", chunk, offset);
    case OP_SET_OUTER: return depth_instruction("SETOUTR", chunk, offset);
    case OP_BLOCK:  return method_instruction("BLOCK", chunk, offset);
    case OP_STRING: return name_instruction("STRING", chunk, offset);
    case OP_SYMBOL: return name_instruction("SYMBOL", chunk, offset);
    case OP_SEND:   return send_instruction("SEND", chunk, offset);
    case OP_SET_SLOT: return name_instruction("SETSLOT", chunk, offset);
    case OP_POP:    return simple_instruction("POP", offset);
    case OP_RETURN: return simple_instruction("RETURN", offset);
    case OP_HALT:   return simple_instruction("HALT", offset);
    case OP_JUMP:   return jump_instruction(chunk, "JUMP", offset);
    case OP_JUMP_IF_FALSE: return jump_instruction(chunk, "JUMP_IF_FALSE", offset);
    case OP_EXIT_IF_FALSE: return jump_instruction(chunk, "EXITIFF", offset);
    case OP_CHECK_BOOL: return name_instruction("CHKBOOL", chunk, offset);
    case OP_LOOP:   return jump_instruction(chunk, "LOOP", offset);
    default:
        printf("unknown opcode %d\n", instruction);
        return offset + 1;
    }
}

void sol_chunk_disassemble(const SolChunk *chunk, const char *name)
{
    printf("== %s ==\n", name);
    for (int offset = 0; offset < chunk->count; ) {
        offset = sol_chunk_disassemble_instruction(chunk, offset);
    }
    /* Then each method the chunk defines, so one --dump shows everything. */
    for (int i = 0; i < chunk->methods.count; i++) {
        const SolMethod *method = chunk->methods.methods[i];
        printf("\n");
        sol_chunk_disassemble(&method->chunk, method->name);
    }
}
