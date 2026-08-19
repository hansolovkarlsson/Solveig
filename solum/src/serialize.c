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

SolSerResult sol_chunk_save(const SolChunk *chunk, const char *path)
{
    /* Refuse to write something that could not be loaded back. */
    SolSerResult check = sol_chunk_verify(chunk);
    if (check != SOL_SER_OK) return check;

    for (int i = 0; i < chunk->constants.count; i++) {
        if (chunk->constants.values[i].type == SOL_OBJ) return SOL_SER_UNSUPPORTED;
    }

    FILE *f = fopen(path, "wb");
    if (f == NULL) return SOL_SER_IO;

    fwrite(SOL_SOB_MAGIC, 1, 4, f);
    put_u16(f, SOL_SOB_VERSION);
    put_u16(f, 0);                       /* reserved */

    put_u32(f, (uint32_t)chunk->names.count);
    for (int i = 0; i < chunk->names.count; i++) {
        size_t len = strlen(chunk->names.names[i]);
        if (len > UINT16_MAX) { fclose(f); return SOL_SER_UNSUPPORTED; }
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
        case SOL_OBJ:
            fclose(f);
            return SOL_SER_UNSUPPORTED;
        }
    }

    put_u32(f, (uint32_t)chunk->count);
    fwrite(chunk->code, 1, (size_t)chunk->count, f);

    /* Line numbers, run-length encoded -- neighbouring instructions nearly
       always share a line, so the runs are far smaller than the raw array. */
    long runs_at = ftell(f);
    put_u32(f, 0);                       /* patched below */
    uint32_t runs = 0;
    for (int i = 0; i < chunk->count; ) {
        int line = chunk->lines[i];
        int j = i;
        while (j < chunk->count && chunk->lines[j] == line) j++;
        put_u32(f, (uint32_t)(j - i));
        put_u32(f, (uint32_t)line);
        runs++;
        i = j;
    }

    if (fseek(f, runs_at, SEEK_SET) != 0) { fclose(f); return SOL_SER_IO; }
    put_u32(f, runs);

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

SolSerResult sol_chunk_load(SolChunk *chunk, const char *path)
{
    sol_chunk_init(chunk);

    size_t size = 0;
    uint8_t *buffer = read_whole_file(path, &size);
    if (buffer == NULL) return SOL_SER_IO;

    Cursor cursor = { buffer, size, 0, false };
    Cursor *c = &cursor;
    SolSerResult status = SOL_SER_MALFORMED;

    const uint8_t *magic;
    if (!take(c, 4, &magic)) { status = SOL_SER_TRUNCATED; goto fail; }
    if (memcmp(magic, SOL_SOB_MAGIC, 4) != 0) { status = SOL_SER_BAD_MAGIC; goto fail; }

    uint16_t version = get_u16(c);
    uint16_t reserved = get_u16(c);
    if (c->overran) { status = SOL_SER_TRUNCATED; goto fail; }
    if (version != SOL_SOB_VERSION) { status = SOL_SER_BAD_VERSION; goto fail; }
    if (reserved != 0) { status = SOL_SER_MALFORMED; goto fail; }

    /* Names. Each entry costs at least 2 bytes on disk, so a count that could
       not possibly fit in what remains is rejected before allocating for it. */
    uint32_t name_count = get_u32(c);
    if (c->overran) { status = SOL_SER_TRUNCATED; goto fail; }
    if ((size_t)name_count * 2 > c->size - c->pos) { status = SOL_SER_TRUNCATED; goto fail; }

    for (uint32_t i = 0; i < name_count; i++) {
        uint16_t length = get_u16(c);
        const uint8_t *bytes;
        if (c->overran || !take(c, length, &bytes)) { status = SOL_SER_TRUNCATED; goto fail; }
        sol_chunk_append_name(chunk, (const char *)bytes, (int)length);
    }

    /* Constants: one tag byte minimum each. */
    uint32_t const_count = get_u32(c);
    if (c->overran) { status = SOL_SER_TRUNCATED; goto fail; }
    if ((size_t)const_count > c->size - c->pos) { status = SOL_SER_TRUNCATED; goto fail; }

    for (uint32_t i = 0; i < const_count; i++) {
        const uint8_t *tag;
        if (!take(c, 1, &tag)) { status = SOL_SER_TRUNCATED; goto fail; }
        switch (*tag) {
        case TAG_NIL:
            sol_chunk_add_constant(chunk, SOL_NIL_VAL);
            break;
        case TAG_INT:
            sol_chunk_add_constant(chunk, SOL_INT_VAL((int64_t)get_u64(c)));
            break;
        case TAG_FLOAT: {
            uint64_t bits = get_u64(c);
            double d;
            memcpy(&d, &bits, sizeof d);
            sol_chunk_add_constant(chunk, SOL_FLOAT_VAL(d));
            break;
        }
        default:
            status = SOL_SER_MALFORMED;
            goto fail;
        }
        if (c->overran) { status = SOL_SER_TRUNCATED; goto fail; }
    }

    /* Code. */
    uint32_t code_length = get_u32(c);
    if (c->overran) { status = SOL_SER_TRUNCATED; goto fail; }
    const uint8_t *code;
    if (!take(c, code_length, &code)) { status = SOL_SER_TRUNCATED; goto fail; }

    /* Line runs, expanded back into the parallel array. Written before the code
       bytes so sol_chunk_write has a line for each one. */
    uint32_t run_count = get_u32(c);
    if (c->overran) { status = SOL_SER_TRUNCATED; goto fail; }
    if ((size_t)run_count * 8 > c->size - c->pos) { status = SOL_SER_TRUNCATED; goto fail; }

    uint32_t written = 0;
    for (uint32_t i = 0; i < run_count; i++) {
        uint32_t run = get_u32(c);
        uint32_t line = get_u32(c);
        if (c->overran) { status = SOL_SER_TRUNCATED; goto fail; }
        if (run > code_length - written) { status = SOL_SER_MALFORMED; goto fail; }

        for (uint32_t j = 0; j < run; j++, written++) {
            sol_chunk_write(chunk, code[written], (int)line);
        }
    }
    /* Every code byte must be covered by exactly one run. */
    if (written != code_length) { status = SOL_SER_MALFORMED; goto fail; }

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

SolSerResult sol_chunk_verify(const SolChunk *chunk)
{
    if (chunk->count == 0) return SOL_SER_MALFORMED;

    int offset = 0;
    int last = 0;

    while (offset < chunk->count) {
        last = offset;
        uint8_t op = chunk->code[offset];

        /* operands: how many bytes follow the opcode. */
        int operands;
        switch (op) {
        case OP_NIL:
        case OP_POP:
        case OP_RETURN:
        case OP_HALT:
            operands = 0;
            break;
        case OP_CONST:
        case OP_GLOBAL:
        case OP_SET_GLOBAL:
            operands = 1;
            break;
        case OP_SEND:
            operands = 2;
            break;
        default:
            return SOL_SER_MALFORMED;      /* unknown opcode */
        }

        if (offset + 1 + operands > chunk->count) {
            return SOL_SER_TRUNCATED;      /* instruction runs off the end */
        }

        /* Operand indices must point at something that exists, or the dispatch
           loop would read past a side table. */
        switch (op) {
        case OP_CONST:
            if (chunk->code[offset + 1] >= chunk->constants.count) return SOL_SER_MALFORMED;
            break;
        case OP_GLOBAL:
        case OP_SET_GLOBAL:
        case OP_SEND:
            if (chunk->code[offset + 1] >= chunk->names.count) return SOL_SER_MALFORMED;
            break;
        default:
            break;
        }

        offset += 1 + operands;
    }

    /* Execution is linear, so it is enough that the final instruction stops the
       machine -- without this the dispatch loop would read past the buffer.
       When jumps arrive, this needs to become a check that every target lands
       on an instruction boundary. */
    uint8_t final = chunk->code[last];
    if (final != OP_HALT && final != OP_RETURN) return SOL_SER_MALFORMED;

    return SOL_SER_OK;
}
