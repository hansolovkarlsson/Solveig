/* serialize.c -- reading and writing .sob files.
 *
 * Writing is straightforward. Reading treats the file as untrusted: the whole
 * thing is pulled into memory, then parsed through a cursor that bounds-checks
 * every read, and the result is verified before anyone can execute it.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "solum/serialize.h"

_Static_assert(sizeof(double) == 8, "the .sob format stores floats as binary64");

#define TAG_NIL   0
#define TAG_INT   1
#define TAG_FLOAT 2
#define TAG_BOOL  3

#define METHOD_IS_BLOCK 0x1
#define METHOD_CAPTURES 0x2

const char *sol_ser_message(SolSerResult result)
{
    switch (result) {
    case SOL_SER_OK:          return "ok";
    case SOL_SER_IO:          return "could not read or write the file";
    case SOL_SER_BAD_MAGIC:   return "not a Solum bytecode file";
    case SOL_SER_BAD_VERSION: return "unsupported bytecode version";
    case SOL_SER_TRUNCATED:   return "file ends mid-structure";
    case SOL_SER_MALFORMED:   return "bytecode is internally inconsistent";
    case SOL_SER_UNSUPPORTED: return "bytecode holds an unsupported constant";
    }
    return "unknown error";
}

/* ---- little-endian writing ------------------------------------------- */

static void put_u16(FILE *f, uint16_t v)
{
    fputc((int)(v & 0xff), f);
    fputc((int)((v >> 8) & 0xff), f);
}

static void put_u32(FILE *f, uint32_t v)
{
    for (int i = 0; i < 4; i++) fputc((int)((v >> (8 * i)) & 0xff), f);
}

static void put_u64(FILE *f, uint64_t v)
{
    for (int i = 0; i < 8; i++) fputc((int)((v >> (8 * i)) & 0xff), f);
}

static SolSerResult check_constants(const SolChunk *chunk)
{
    for (int i = 0; i < chunk->constants.count; i++) {
        SolValueType type = chunk->constants.values[i].type;
        /* Arrays are mutable and built at run time, so a literal is a
           construction rather than a pooled constant. */
        if (type == SOL_OBJ || type == SOL_BLOCK || type == SOL_ARRAY ||
            type == SOL_STRING || type == SOL_DELEGATE || type == SOL_SYMBOL) {
            return SOL_SER_UNSUPPORTED;
        }
    }
    for (int i = 0; i < chunk->methods.count; i++) {
        SolSerResult result = check_constants(&chunk->methods.methods[i]->chunk);
        if (result != SOL_SER_OK) return result;
    }
    return SOL_SER_OK;
}

/* Number of runs the line array collapses into. */
static uint32_t count_line_runs(const SolChunk *chunk)
{
    uint32_t runs = 0;
    for (int i = 0; i < chunk->count; ) {
        int line = chunk->lines[i];
        int j = i;
        while (j < chunk->count && chunk->lines[j] == line) j++;
        runs++;
        i = j;
    }
    return runs;
}

/* Everything about a chunk except the file header. Recursive: a method carries
   a chunk of its own. */
static void write_chunk_body(FILE *f, const SolChunk *chunk)
{
    put_u32(f, (uint32_t)chunk->names.count);
    for (int i = 0; i < chunk->names.count; i++) {
        size_t len = strlen(chunk->names.names[i]);
        put_u16(f, (uint16_t)len);
        fwrite(chunk->names.names[i], 1, len, f);
    }

    put_u32(f, (uint32_t)chunk->constants.count);
    for (int i = 0; i < chunk->constants.count; i++) {
        SolValue value = chunk->constants.values[i];
        switch (value.type) {
        case SOL_NIL:
            fputc(TAG_NIL, f);
            break;
        case SOL_INT:
            fputc(TAG_INT, f);
            put_u64(f, (uint64_t)SOL_AS_INT(value));
            break;
        case SOL_FLOAT: {
            uint64_t bits;
            double d = SOL_AS_FLOAT(value);
            memcpy(&bits, &d, sizeof bits);
            fputc(TAG_FLOAT, f);
            put_u64(f, bits);
            break;
        }
        case SOL_BOOL:
            fputc(TAG_BOOL, f);
            fputc(SOL_AS_BOOL(value) ? 1 : 0, f);
            break;
        case SOL_BLOCK:
        case SOL_ARRAY:
        case SOL_STRING:
        case SOL_SYMBOL:
        case SOL_DELEGATE:
        case SOL_OBJ:
            break;      /* rejected by check_constants before we get here */
        }
    }

    put_u32(f, (uint32_t)chunk->count);
    fwrite(chunk->code, 1, (size_t)chunk->count, f);

    /* Line numbers, run-length encoded -- neighbouring instructions nearly
       always share a line, so the runs are far smaller than the raw array. */
    put_u32(f, count_line_runs(chunk));
    for (int i = 0; i < chunk->count; ) {
        int line = chunk->lines[i];
        int j = i;
        while (j < chunk->count && chunk->lines[j] == line) j++;
        put_u32(f, (uint32_t)(j - i));
        put_u32(f, (uint32_t)line);
        i = j;
    }

    put_u32(f, (uint32_t)chunk->methods.count);
    for (int i = 0; i < chunk->methods.count; i++) {
        const SolMethod *method = chunk->methods.methods[i];
        size_t len = strlen(method->name);
        put_u16(f, (uint16_t)len);
        fwrite(method->name, 1, len, f);
        put_u16(f, (uint16_t)method->arity);
        put_u16(f, (uint16_t)method->slot_count);
        put_u16(f, (uint16_t)((method->is_block ? METHOD_IS_BLOCK : 0) |
                              (method->captures ? METHOD_CAPTURES : 0)));
        write_chunk_body(f, &method->chunk);
    }
}

/* Names longer than a u16 length field cannot be written back. */
static SolSerResult check_name_lengths(const SolChunk *chunk)
{
    for (int i = 0; i < chunk->names.count; i++) {
        if (strlen(chunk->names.names[i]) > UINT16_MAX) return SOL_SER_UNSUPPORTED;
    }
    for (int i = 0; i < chunk->methods.count; i++) {
        const SolMethod *method = chunk->methods.methods[i];
        if (strlen(method->name) > UINT16_MAX) return SOL_SER_UNSUPPORTED;
        SolSerResult result = check_name_lengths(&method->chunk);
        if (result != SOL_SER_OK) return result;
    }
    return SOL_SER_OK;
}

SolSerResult sol_chunk_save(const SolChunk *chunk, const char *path)
{
    /* Refuse to write something that could not be loaded back. */
    SolSerResult check = sol_chunk_verify(chunk);
    if (check != SOL_SER_OK) return check;

    check = check_constants(chunk);
    if (check != SOL_SER_OK) return check;

    check = check_name_lengths(chunk);
    if (check != SOL_SER_OK) return check;

    FILE *f = fopen(path, "wb");
    if (f == NULL) return SOL_SER_IO;

    fwrite(SOL_SOB_MAGIC, 1, 4, f);
    put_u16(f, SOL_SOB_VERSION);
    put_u16(f, 0);                       /* reserved */
    write_chunk_body(f, chunk);

    bool failed = ferror(f) != 0;
    if (fclose(f) != 0 || failed) return SOL_SER_IO;
    return SOL_SER_OK;
}

/* ---- bounds-checked reading ------------------------------------------ */

typedef struct {
    const uint8_t *data;
    size_t         size;
    size_t         pos;
    bool           overran;   /* sticky: set by the first read past the end */
} Cursor;

static bool take(Cursor *c, size_t n, const uint8_t **out)
{
    if (c->overran || c->size - c->pos < n) { c->overran = true; return false; }
    *out = c->data + c->pos;
    c->pos += n;
    return true;
}

static uint16_t get_u16(Cursor *c)
{
    const uint8_t *p;
    if (!take(c, 2, &p)) return 0;
    return (uint16_t)(p[0] | (p[1] << 8));
}

static uint32_t get_u32(Cursor *c)
{
    const uint8_t *p;
    if (!take(c, 4, &p)) return 0;
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) |
           ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static uint64_t get_u64(Cursor *c)
{
    const uint8_t *p;
    if (!take(c, 8, &p)) return 0;
    uint64_t v = 0;
    for (int i = 0; i < 8; i++) v |= (uint64_t)p[i] << (8 * i);
    return v;
}

/* Reads the whole file. Returns NULL on failure; *size gets the byte count. */
static uint8_t *read_whole_file(const char *path, size_t *size)
{
    FILE *f = fopen(path, "rb");
    if (f == NULL) return NULL;

    if (fseek(f, 0L, SEEK_END) != 0) { fclose(f); return NULL; }
    long end = ftell(f);
    if (end < 0) { fclose(f); return NULL; }
    rewind(f);

    uint8_t *buffer = malloc((size_t)end + 1);
    if (buffer == NULL) { fclose(f); return NULL; }

    size_t read = fread(buffer, 1, (size_t)end, f);
    fclose(f);

    *size = read;
    return buffer;
}

#define SOL_MAX_NESTING 16

/* Reads one chunk body. Returns SOL_SER_OK or the reason it failed; on failure
   the caller frees `chunk`. */
static SolSerResult read_chunk_body(Cursor *c, SolChunk *chunk, int depth)
{
    if (depth > SOL_MAX_NESTING) return SOL_SER_MALFORMED;

    /* Names. Each entry costs at least 2 bytes on disk, so a count that could
       not possibly fit in what remains is rejected before allocating for it. */
    uint32_t name_count = get_u32(c);
    if (c->overran) return SOL_SER_TRUNCATED;
    if ((size_t)name_count * 2 > c->size - c->pos) return SOL_SER_TRUNCATED;

    for (uint32_t i = 0; i < name_count; i++) {
        uint16_t length = get_u16(c);
        const uint8_t *bytes;
        if (c->overran || !take(c, length, &bytes)) return SOL_SER_TRUNCATED;
        sol_chunk_append_name(chunk, (const char *)bytes, (int)length);
    }

    /* Constants: one tag byte minimum each. */
    uint32_t const_count = get_u32(c);
    if (c->overran) return SOL_SER_TRUNCATED;
    if ((size_t)const_count > c->size - c->pos) return SOL_SER_TRUNCATED;

    for (uint32_t i = 0; i < const_count; i++) {
        const uint8_t *tag;
        if (!take(c, 1, &tag)) return SOL_SER_TRUNCATED;
        switch (*tag) {
        /* Appended rather than interned, for the same reason the names are:
           the code refers to this table by position, so folding a duplicate
           here would shift every constant after it. A file written by Solas
           has no duplicates to fold; one that does is still loaded as written
           and still verifies. */
        case TAG_NIL:
            sol_chunk_append_constant(chunk, SOL_NIL_VAL);
            break;
        case TAG_INT:
            sol_chunk_append_constant(chunk, SOL_INT_VAL((int64_t)get_u64(c)));
            break;
        case TAG_FLOAT: {
            uint64_t bits = get_u64(c);
            double d;
            memcpy(&d, &bits, sizeof d);
            sol_chunk_append_constant(chunk, SOL_FLOAT_VAL(d));
            break;
        }
        case TAG_BOOL: {
            const uint8_t *b;
            if (!take(c, 1, &b)) return SOL_SER_TRUNCATED;
            sol_chunk_append_constant(chunk, SOL_BOOL_VAL(*b != 0));
            break;
        }
        default:
            return SOL_SER_MALFORMED;
        }
        if (c->overran) return SOL_SER_TRUNCATED;
    }

    /* Code. */
    uint32_t code_length = get_u32(c);
    if (c->overran) return SOL_SER_TRUNCATED;
    const uint8_t *code;
    if (!take(c, code_length, &code)) return SOL_SER_TRUNCATED;

    /* Line runs, expanded back into the parallel array. */
    uint32_t run_count = get_u32(c);
    if (c->overran) return SOL_SER_TRUNCATED;
    if ((size_t)run_count * 8 > c->size - c->pos) return SOL_SER_TRUNCATED;

    uint32_t written = 0;
    for (uint32_t i = 0; i < run_count; i++) {
        uint32_t run = get_u32(c);
        uint32_t line = get_u32(c);
        if (c->overran) return SOL_SER_TRUNCATED;
        if (run > code_length - written) return SOL_SER_MALFORMED;

        for (uint32_t j = 0; j < run; j++, written++) {
            sol_chunk_write(chunk, code[written], (int)line);
        }
    }
    /* Every code byte must be covered by exactly one run. */
    if (written != code_length) return SOL_SER_MALFORMED;

    /* Methods, each carrying a chunk of its own. */
    uint32_t method_count = get_u32(c);
    if (c->overran) return SOL_SER_TRUNCATED;
    if ((size_t)method_count * 8 > c->size - c->pos) return SOL_SER_TRUNCATED;

    for (uint32_t i = 0; i < method_count; i++) {
        uint16_t name_length = get_u16(c);
        const uint8_t *name;
        if (c->overran || !take(c, name_length, &name)) return SOL_SER_TRUNCATED;

        uint16_t arity = get_u16(c);
        uint16_t slot_count = get_u16(c);
        uint16_t flags = get_u16(c);
        if (c->overran) return SOL_SER_TRUNCATED;
        if ((flags & ~(METHOD_IS_BLOCK | METHOD_CAPTURES)) != 0) return SOL_SER_MALFORMED;

        /* A frame is addressed by one-byte slot operands, and must have room
           for self plus every argument. */
        if (arity > UINT8_MAX || slot_count > UINT8_MAX) return SOL_SER_MALFORMED;
        if (slot_count < arity + 1) return SOL_SER_MALFORMED;

        SolMethod *method = sol_method_new((const char *)name, (int)name_length,
                                           (int)arity);
        method->slot_count = (int)slot_count;
        method->is_block = (flags & METHOD_IS_BLOCK) != 0;
        method->captures = (flags & METHOD_CAPTURES) != 0;
        sol_chunk_add_method(chunk, method);      /* owned by the chunk now */

        SolSerResult result = read_chunk_body(c, &method->chunk, depth + 1);
        if (result != SOL_SER_OK) return result;
    }

    return SOL_SER_OK;
}

SolSerResult sol_chunk_load(SolChunk *chunk, const char *path)
{
    sol_chunk_init(chunk);

    size_t size = 0;
    uint8_t *buffer = read_whole_file(path, &size);
    if (buffer == NULL) return SOL_SER_IO;

    Cursor cursor = { buffer, size, 0, false };
    Cursor *c = &cursor;
    SolSerResult status;

    const uint8_t *magic;
    if (!take(c, 4, &magic)) { status = SOL_SER_TRUNCATED; goto fail; }
    if (memcmp(magic, SOL_SOB_MAGIC, 4) != 0) { status = SOL_SER_BAD_MAGIC; goto fail; }

    uint16_t version = get_u16(c);
    uint16_t reserved = get_u16(c);
    if (c->overran) { status = SOL_SER_TRUNCATED; goto fail; }
    if (version != SOL_SOB_VERSION) { status = SOL_SER_BAD_VERSION; goto fail; }
    if (reserved != 0) { status = SOL_SER_MALFORMED; goto fail; }

    status = read_chunk_body(c, chunk, 0);
    if (status != SOL_SER_OK) goto fail;

    free(buffer);

    /* Structure is intact; now check that it is safe to execute. */
    SolSerResult verified = sol_chunk_verify(chunk);
    if (verified != SOL_SER_OK) {
        sol_chunk_free(chunk);
        return verified;
    }
    return SOL_SER_OK;

fail:
    free(buffer);
    sol_chunk_free(chunk);
    return status;
}

/* ---- verification ---------------------------------------------------- */

/* `slot_count` is how many frame slots this chunk's code may address; 0 for the
 * top-level chunk, which has neither self nor locals. `ancestors` carries the
 * slot counts of the enclosing frames, nearest first, so an OUTER at depth d
 * can be bounds-checked against the frame it actually reaches.
 *
 * Without this a crafted file could reach past a frame it never entered.
 */
static SolSerResult verify_chunk(const SolChunk *chunk, int slot_count,
                                 const int *ancestors, int ancestor_count,
                                 int depth)
{
    if (depth > SOL_MAX_NESTING) return SOL_SER_MALFORMED;
    if (chunk->count == 0) return SOL_SER_MALFORMED;

    /* Execution is no longer linear, so knowing each instruction is well formed
       is not enough: a jump target has to be the *start* of one. Recorded here
       in the same walk, checked in a second pass below. A crafted file whose
       target lands one byte into a send would otherwise read its operands as an
       opcode. */
    bool *boundary = calloc((size_t)chunk->count, sizeof(bool));
    if (boundary == NULL) return SOL_SER_MALFORMED;

#define FAIL(code) do { free(boundary); return (code); } while (0)

    int offset = 0;
    int last = 0;

    while (offset < chunk->count) {
        boundary[offset] = true;
        last = offset;
        uint8_t op = chunk->code[offset];

        /* An opcode with no length is not one of ours, and rejecting it here
           is what lets the rest of this walk trust the lengths it steps by. */
        int length = sol_op_length(op);
        if (length == 0) FAIL(SOL_SER_MALFORMED);

        if (offset + length > chunk->count) {
            FAIL(SOL_SER_TRUNCATED);       /* instruction runs off the end */
        }

        /* Operand indices must point at something that exists, or the dispatch
           loop would read past a side table or outside a frame. */
        switch (op) {
        case OP_CONST:
            if (sol_read_u16(&chunk->code[offset + 1]) >= chunk->constants.count) {
                FAIL(SOL_SER_MALFORMED);
            }
            break;
        case OP_GLOBAL:
        case OP_SET_GLOBAL:
        case OP_SEND:
        case OP_SET_SLOT:
        case OP_STRING:
        case OP_SYMBOL:
            if (sol_read_u16(&chunk->code[offset + 1]) >= chunk->names.count) {
                FAIL(SOL_SER_MALFORMED);
            }
            break;
        /* The selector follows the offset rather than leading, so it starts at
           the third operand byte. */
        case OP_JUMP_IF_FALSE:
            if (sol_read_u16(&chunk->code[offset + 3]) >= chunk->names.count) {
                FAIL(SOL_SER_MALFORMED);
            }
            break;
        case OP_LOCAL:
        case OP_SET_LOCAL:
            if (chunk->code[offset + 1] >= slot_count) FAIL(SOL_SER_MALFORMED);
            break;
        case OP_OUTER:
        case OP_SET_OUTER: {
            int d = chunk->code[offset + 1];
            int slot = chunk->code[offset + 2];
            if (d < 1 || d > ancestor_count) FAIL(SOL_SER_MALFORMED);
            if (slot >= ancestors[d - 1]) FAIL(SOL_SER_MALFORMED);
            break;
        }
        case OP_BLOCK: {
            uint16_t index = sol_read_u16(&chunk->code[offset + 1]);
            if (index >= chunk->methods.count) FAIL(SOL_SER_MALFORMED);
            /* OP_BLOCK must name a block: a non-block entry would be entered
               with a frame it was not compiled for. */
            if (!chunk->methods.methods[index]->is_block) FAIL(SOL_SER_MALFORMED);
            break;
        }
        default:
            break;
        }

        offset += length;
    }

    /* Second pass: every branch target must be the start of an instruction in
       this chunk. This walk visits exactly the offsets the first one did, since
       both step by sol_op_length, so every length here is known non-zero.
     *
     * OP_LOOP subtracts rather than adds, which is the whole of what a backward
     * jump costs us: a verified chunk can now run forever. That is not a new
     * capability -- `{ true }:whileTrue({})` is a legal program, and a loop
     * built from real sends could already spin -- so the obligation here is
     * unchanged. Land on an instruction, inside this chunk. Termination was
     * never something the verifier promised.
     */
    for (int at = 0; at < chunk->count; ) {
        uint8_t op = chunk->code[at];
        int length = sol_op_length(op);

        if (op == OP_JUMP || op == OP_JUMP_IF_FALSE ||
            op == OP_EXIT_IF_FALSE || op == OP_LOOP) {
            uint16_t jump = sol_read_u16(&chunk->code[at + 1]);
            long target = (op == OP_LOOP) ? (long)at + length - jump
                                          : (long)at + length + jump;
            if (target < 0 || target >= chunk->count) FAIL(SOL_SER_MALFORMED);
            if (!boundary[target]) FAIL(SOL_SER_MALFORMED);
        }
        at += length;
    }

    free(boundary);
#undef FAIL

    /* The last instruction must still stop the machine. Every jump lands on an
       instruction inside this chunk, so the ip can only leave the code by
       falling off the end of it -- and this is the instruction it would fall
       off. A backward jump does not change that; it only means the fall may
       take a while to arrive. */
    uint8_t final = chunk->code[last];
    if (final != OP_HALT && final != OP_RETURN) return SOL_SER_MALFORMED;

    /* Blocks defined here are entered with this chunk's frame as their nearest
       ancestor, so push it and verify each body against the extended chain. */
    int child[SOL_MAX_NESTING + 1];
    int child_count = ancestor_count + 1;
    if (child_count > SOL_MAX_NESTING) child_count = SOL_MAX_NESTING;
    child[0] = slot_count;
    for (int i = 1; i < child_count; i++) child[i] = ancestors[i - 1];

    for (int i = 0; i < chunk->methods.count; i++) {
        const SolMethod *entry = chunk->methods.methods[i];
        if (entry->slot_count < entry->arity + 1) return SOL_SER_MALFORMED;
        if (entry->slot_count > UINT8_MAX) return SOL_SER_MALFORMED;

        SolSerResult result = verify_chunk(&entry->chunk, entry->slot_count,
                                           child, child_count, depth + 1);
        if (result != SOL_SER_OK) return result;
    }

    return SOL_SER_OK;
}

SolSerResult sol_chunk_verify(const SolChunk *chunk)
{
    return verify_chunk(chunk, 0, NULL, 0, 0);
}
